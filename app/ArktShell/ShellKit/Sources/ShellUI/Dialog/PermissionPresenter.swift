import AppKit
import EngineAPI

// A site's permission request in the shell's dialog system (#400, docs/design/alerts-sheets-toasts.md sections 3.2 and
// 3.3): the engine reports the request with Chromium's own strings, and the shell draws it as the anchored panel over
// the page that asked, with three stacked neutral answers and no Return default.

extension DialogContent {
  /// How long after a permission prompt appears that presses and Return are ignored (Chrome's input protection), so a
  /// keystroke or click meant for the page cannot grant a permission.
  public static let permissionInputProtection: TimeInterval = 0.5

  /// The dialog for a site's request: "example.com wants to", what it wants as a list, then Allow (while visiting the
  /// site), Allow this time when the engine offers it, and Block. Every string is the engine's. The answers carry equal
  /// weight (neutral pills) and nothing is the Return default, so the prompt does not steer toward Allow; Escape closes
  /// it without an answer, as the engine's own panel does.
  public static func permissionRequest(_ request: PermissionRequest, width: CGFloat = 320) -> DialogContent {
    DialogContent(title: request.title, listItems: request.items, primaryTitle: request.allowTitle,
                  secondaryTitle: request.allowThisTimeTitle, cancelTitle: request.blockTitle, defaultButton: .none,
                  width: width, stackedButtons: true, neutralPrimary: true, escapeDismisses: true,
                  inputProtection: permissionInputProtection)
  }
}

extension PermissionChoice {
  init(_ answer: DialogContent.Answer) {
    switch answer {
    case .primary: self = .allow
    case .secondary: self = .allowThisTime
    case .cancel: self = .block
    }
  }
}

/// Shows each pending permission request of the tabs the window shows, one per tab, and answers the engine. The panel
/// does not take key focus: the page keeps its text field until the user clicks the prompt. The engine ends a request
/// on its own (a navigation, the tab hidden or closing, the site withdrawing it) and asks again for a tab that comes
/// back; an end closes the panel with no answer, and an answer that races the end is dropped by the engine.
@MainActor
public final class PermissionPresenter {
  private struct Entry {
    let panel: DialogPanel
    var observers: [NSObjectProtocol]
  }

  private let engine: any EngineClient
  private let anchor: @MainActor (TabID) -> NSView?
  /// Whether a window can show a panel now: false while it is minimized or its app is hidden. Tests inject it.
  private let windowIsVisible: @MainActor (NSWindow) -> Bool
  private var returnObservers: [NSObjectProtocol] = []
  /// The last refresh found a pending request with no page view to point at, or one with empty bounds; the next layout
  /// or frame change of that view tries again.
  private var retryOnLayout = false
  private var retryScheduled = false
  /// Watches the frame of a page view that has no bounds yet, so its first layout shows the panel without waiting for
  /// the window's root layout.
  private var unlaidOutObservers: [NSObjectProtocol] = []
  /// The unanswered request of each tab.
  public private(set) var pending: [TabID: PermissionRequest] = [:]
  private var entries: [TabID: Entry] = [:]
  /// Reduce Motion, handed to each panel at its entrance. Tests set it.
  var reduceMotion: (@MainActor () -> Bool)?
  /// The clock of the input protection, handed to each panel. Tests set it.
  var clock: (@MainActor () -> TimeInterval)?
  /// Whether a panel's window is really visible (not occluded), handed to each panel. Tests set it.
  var isOnScreen: (@MainActor () -> Bool)?

  /// `anchor` returns the view of a tab that is on screen in a window, nil for one that is not.
  public init(engine: any EngineClient, anchor: @escaping @MainActor (TabID) -> NSView?,
              windowIsVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
    self.engine = engine
    self.anchor = anchor
    self.windowIsVisible = windowIsVisible
    let names: [Notification.Name] = [NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification,
                                      NSApplication.didUnhideNotification]
    returnObservers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
    // A Space change moves windows off and on screen without any window notification of its own.
    spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
  }

  private var spaceObserver: NSObjectProtocol?

  isolated deinit {
    for observer in returnObservers + unlaidOutObservers { NotificationCenter.default.removeObserver(observer) }
    if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
  }

  /// The tab whose panel is up, for tests and accessibility.
  public func panel(for tab: TabID) -> DialogPanel? { entries[tab]?.panel }

  public func handle(_ event: EngineEvent) {
    switch event {
    case .permissionRequested(let request):
      if pending[request.tab] != nil { dismissPanel(of: request.tab) }
      pending[request.tab] = request
      present(request.tab)
      scheduleRetryIfNeeded()
    case .permissionEnded(let tab, let id):
      guard pending[tab]?.id == id else { return }
      pending[tab] = nil
      dismissPanel(of: tab)
    default:
      break
    }
  }

  /// Shows the panels of tabs that came on screen and moves those whose page moved.
  public func refresh() {
    retryOnLayout = false
    stopWatchingUnlaidOutViews()
    for tab in pending.keys { present(tab) }
  }

  /// The window finished a layout pass: a request that found no page view to point at tries again.
  public func layoutDidFinish() {
    if retryOnLayout { refresh() }
  }

  /// A request that arrives before its tab has a page view does not wait for the window's next root layout: it tries
  /// once more on the next turn of the run loop (a new tab's view is placed within the same turn), then falls back to
  /// the layout and frame callbacks.
  private func scheduleRetryIfNeeded() {
    guard retryOnLayout, !retryScheduled else { return }
    retryScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.retryScheduled = false
        if self.retryOnLayout { self.refresh() }
      }
    }
  }

  private func stopWatchingUnlaidOutViews() {
    for observer in unlaidOutObservers { NotificationCenter.default.removeObserver(observer) }
    unlaidOutObservers = []
  }

  /// Takes every panel down without answering, as the window goes away.
  public func closeAll() {
    for tab in Array(entries.keys) { dismissPanel(of: tab) }
  }

  private func present(_ tab: TabID) {
    guard let request = pending[tab] else { return }
    guard let view = anchor(tab) else {
      retryOnLayout = true
      dismissPanel(of: tab)
      return
    }
    guard let window = view.window, windowIsVisible(window) else {
      dismissPanel(of: tab)                  // a window coming back (deminiaturize, unhide, occlusion) refreshes
      return
    }
    let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
    if let entry = entries[tab] {
      entry.panel.reposition(anchoredTo: frame)                  // an empty frame holds its input protection
      return
    }
    guard !frame.isEmpty else {
      // Not laid out yet: never place a panel at the screen origin. The view's own first frame change retries.
      retryOnLayout = true
      view.postsFrameChangedNotifications = true
      unlaidOutObservers.append(NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.refresh() }
        })
      return
    }
    let width = min(320, max(260, frame.width - 2 * DialogPanel.anchorInset))
    let panel = DialogPanel(content: .permissionRequest(request, width: width))
    if let reduceMotion { panel.reduceMotion = reduceMotion }
    if let clock { panel.clock = clock }
    if let isOnScreen { panel.isOnScreen = isOnScreen }
    panel.onAnswer = { [weak self] answer in self?.answered(tab, request, PermissionChoice(answer)) }
    panel.onDismiss = { [weak self] in self?.answered(tab, request, .dismiss) }
    let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    view.postsFrameChangedNotifications = true
    let observers = [
      NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main,
                                             using: reposition),
      NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main,
                                             using: reposition),
    ]
    entries[tab] = Entry(panel: panel, observers: observers)
    panel.show(over: window, anchoredTo: frame)
  }

  /// Takes the tab's panel down at once, with no answer to the engine.
  private func dismissPanel(of tab: TabID) {
    guard let entry = entries.removeValue(forKey: tab) else { return }
    for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    entry.panel.onAnswer = nil
    entry.panel.onDismiss = nil
    entry.panel.close(keyboard: true)
  }

  private func answered(_ tab: TabID, _ request: PermissionRequest, _ choice: PermissionChoice) {
    guard pending[tab]?.id == request.id else { return }
    pending[tab] = nil
    if let entry = entries.removeValue(forKey: tab) {
      for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    }
    engine.respond(toPermission: request.id, choice: choice)
  }
}
