import AppKit

/// One notice for the sidebar banner (#648, design/sidebar-banner): "update ready" with Restart, or a short
/// announcement whose row opens a popover. `id` is what a dismissal is stored under, so the same notice (an update's
/// version, an announcement's id) never comes back once dismissed.
public struct SidebarNotice: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable {
    case update
    case announcement
  }

  public let id: String
  public let kind: Kind
  /// The full title: "Update ready", or the announcement's title (drawn whole in the popover).
  public let title: String
  /// The popover's body; empty for an update.
  public let body: String
  /// The row's pill (Restart) or the popover's neutral action; nil: none.
  public let actionTitle: String?

  public init(id: String, kind: Kind, title: String, body: String = "", actionTitle: String? = nil) {
    self.id = id
    self.kind = kind
    self.title = title
    self.body = body
    self.actionTitle = actionTitle
  }

  /// An update downloaded and ready to install on restart; one notice per version.
  public static func update(version: String) -> SidebarNotice {
    SidebarNotice(id: "update-\(version)", kind: .update, title: "Update ready", actionTitle: "Restart")
  }

  /// A short announcement: one truncated line in the row, the whole text in the popover.
  public static func announcement(id: String, title: String, body: String,
                                  actionTitle: String? = nil) -> SidebarNotice {
    SidebarNotice(id: "announcement-\(id)", kind: .announcement, title: title, body: body, actionTitle: actionTitle)
  }

  public var isUpdate: Bool { kind == .update }
  /// What the row's label shows: "Update", or the announcement's title (truncated by the row).
  public var rowLabel: String { isUpdate ? "Update" : title }
  /// What VoiceOver says once when the notice first shows (design: "Update ready. Restart").
  public var spokenText: String {
    guard isUpdate else { return title }
    return [title, actionTitle].compactMap { $0 }.joined(separator: ". ")
  }
}

/// Where sidebar notices come from. The updater (#126) and the announcement feed plug in here; until then the app
/// uses `ManualSidebarNoticeSource`. `notices` is in priority order; the banner shows the first one not dismissed.
@MainActor
public protocol SidebarNoticeSource: AnyObject {
  var notices: [SidebarNotice] { get }
  /// Set by the banner's model; the source calls it whenever `notices` changes.
  var onChange: (@MainActor () -> Void)? { get set }
  /// The notice's action was chosen: Restart for an update (the updater relaunches), the popover's action for an
  /// announcement.
  func perform(_ notice: SidebarNotice)
}

/// A notice source driven by hand: tests, and the app's test driver until the updater (#126) exists.
@MainActor
public final class ManualSidebarNoticeSource: SidebarNoticeSource {
  public var notices: [SidebarNotice] { didSet { onChange?() } }
  public var onChange: (@MainActor () -> Void)?
  /// Every notice whose action was chosen, in order.
  public private(set) var performed: [SidebarNotice] = []
  /// Runs after an action is recorded (the app's driver withdraws the notice).
  public var onPerform: (@MainActor (SidebarNotice) -> Void)?

  public init(notices: [SidebarNotice] = []) {
    self.notices = notices
  }

  public func perform(_ notice: SidebarNotice) {
    performed.append(notice)
    onPerform?(notice)
  }
}

/// The ids of dismissed notices, kept in the user defaults so a dismissed notice never comes back for the same
/// version. Only the newest `limit` ids are kept. `ephemeral()` keeps them in memory (tests, the smoke), like
/// `CopyLinkEducation`.
@MainActor
public final class SidebarNoticeDismissals {
  public static let defaultsKey = "sidebarNoticeDismissedIDs"
  /// Ids kept; the oldest go first. Far more than the notices one version of the app can show.
  public static let limit = 100

  private let defaults: UserDefaults?
  private var ids: [String]

  public convenience init(defaults: UserDefaults) { self.init(store: defaults) }

  private init(store: UserDefaults?) {
    defaults = store
    ids = store?.stringArray(forKey: Self.defaultsKey) ?? []
  }

  public func contains(_ id: String) -> Bool { ids.contains(id) }

  public func insert(_ id: String) {
    guard !ids.contains(id) else { return }
    ids.append(id)
    if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit) }
    defaults?.set(ids, forKey: Self.defaultsKey)
  }

  /// Never touches user defaults.
  public static func ephemeral() -> SidebarNoticeDismissals { SidebarNoticeDismissals(store: nil) }
}

/// A model observer; cancelled on `cancel()` or when released.
@MainActor
public final class SidebarBannerObservation {
  private var onCancel: (@MainActor () -> Void)?
  init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }
  public func cancel() { onCancel?(); onCancel = nil }
  isolated deinit { onCancel?() }
}

/// The banner's state, one per app and shared by every window: the source's first notice that was not dismissed.
/// Dismissing stores the id; an announcement's action retires it too, while an update stays until the source
/// withdraws it. VoiceOver hears each notice once, however many windows show it, and only once a window shows it.
@MainActor
public final class SidebarBannerModel {
  public let source: any SidebarNoticeSource
  public let dismissals: SidebarNoticeDismissals
  public private(set) var current: SidebarNotice?
  /// Reduce Motion, read when a window shows or hides the banner (tests set it).
  public var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  private let announce: AXAnnouncement.Poster
  private var announced: Set<String> = []
  /// A window shows the banner (`windowAttached()`); until then nothing is announced.
  private var hasWindow = false
  private var observers: [Int: @MainActor (SidebarNotice?) -> Void] = [:]
  private var nextObserver = 0

  public convenience init(source: any SidebarNoticeSource, dismissals: SidebarNoticeDismissals) {
    self.init(source: source, dismissals: dismissals, announce: AXAnnouncement.post)
  }

  init(source: any SidebarNoticeSource, dismissals: SidebarNoticeDismissals,
       announce: @escaping AXAnnouncement.Poster) {
    self.source = source
    self.dismissals = dismissals
    self.announce = announce
    source.onChange = { [weak self] in self?.refresh() }
    refresh()
  }

  /// `handler` runs on every change of `current` (not now).
  public func addObserver(_ handler: @escaping @MainActor (SidebarNotice?) -> Void) -> SidebarBannerObservation {
    let key = nextObserver
    nextObserver += 1
    observers[key] = handler
    return SidebarBannerObservation { [weak self] in self?.observers[key] = nil }
  }

  /// A window now shows the banner. The first call announces the notice already showing; later notices are announced
  /// as they come.
  public func windowAttached() {
    guard !hasWindow else { return }
    hasWindow = true
    announceIfNew(current)
  }

  /// The close button or the popover's Dismiss: the notice goes and does not come back.
  public func dismiss() {
    guard let current else { return }
    dismissals.insert(current.id)
    refresh()
  }

  /// Restart, or the popover's action. An announcement is done with once its action ran.
  public func performAction() {
    guard let notice = current else { return }
    if !notice.isUpdate { dismissals.insert(notice.id) }
    source.perform(notice)
    refresh()
  }

  private func refresh() {
    let next = source.notices.first { !dismissals.contains($0.id) }
    guard next != current else { return }
    current = next
    announceIfNew(next)
    for handler in observers.values { handler(next) }
  }

  private func announceIfNew(_ notice: SidebarNotice?) {
    guard hasWindow, let notice, announced.insert(notice.id).inserted else { return }
    // A status region: polite, it never interrupts what VoiceOver is reading.
    announce(notice.spokenText, .medium)
  }
}
