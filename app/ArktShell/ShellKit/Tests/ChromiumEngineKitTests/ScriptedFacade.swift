import AppKit
import ImageIO
import ArktEngineABI
import EngineAPITestSupport

// A scripted Swift implementation of the facade protocols (arkt_engine.h), modelled on the real facade's recorded
// behaviour (week-3 results, W3-3 to W3-5 and #258): events are recorded as plain values and delivered in one batch
// on the next main-actor turn, never from inside the call that caused them; a close answers `closed` or `held`; a
// call made while `isNested` is set is deferred (pending handle, `held` close) and runs before the next batch; the
// test API's `evaluateScript` understands the few scripts the contract drivers send.

final class ScriptedEvent: NSObject, ArktEngineEvent {
  let kind: ArktEngineEventKind
  let tab: (any ArktTabHandle)?
  let browser: (any ArktBrowserHandle)?
  var closeReason: ArktCloseReason = .none
  var windowCloseReason: ArktWindowCloseReason = .none
  var url: URL?
  var title: String?
  var faviconPNG: Data?
  var isLoading = false
  var canGoBack = false
  var canGoForward = false
  var opener: (any ArktTabHandle)?
  var origin: ArktTabOrigin = .client
  var isActive = false
  var isAudible = false
  var isMuted = false
  var dialog: (any ArktJavaScriptDialog)?
  var permission: (any ArktPermissionRequest)?
  var infobars: [any ArktInfobar]?

  init(_ kind: ArktEngineEventKind, tab: (any ArktTabHandle)?, browser: (any ArktBrowserHandle)?) {
    self.kind = kind; self.tab = tab; self.browser = browser
  }
}

/// A page's alert, confirm or prompt (#400): plain values and the one answer. `answers` records what the page's call
/// would have returned.
final class ScriptedDialog: NSObject, ArktJavaScriptDialog {
  let kind: ArktDialogKind
  let tab: any ArktTabHandle
  let title: String
  let message: String
  let defaultPromptText: String?
  let acceptTitle = "OK"
  let cancelTitle: String?
  private(set) var isEnded = false
  private(set) var answer: (accepted: Bool, userInput: String?)?
  var onEnd: (() -> Void)?

  init(kind: ArktDialogKind, tab: any ArktTabHandle, title: String, message: String, defaultPromptText: String?) {
    self.kind = kind; self.tab = tab; self.title = title; self.message = message
    self.defaultPromptText = kind == .prompt ? (defaultPromptText ?? "") : nil
    cancelTitle = kind == .alert ? nil : "Cancel"
  }

  func respond(accepted: Bool, userInput: String?) -> Bool {
    guard !isEnded else { return false }
    answer = (accepted, userInput)
    end()
    return true
  }

  /// The engine's own end, or the end after an answer: once, reported with `DialogEnded`.
  func end() {
    guard !isEnded else { return }
    isEnded = true
    onEnd?()
  }
}

/// A site's permission request (#400): plain values and the one answer. `choice` records what the shell answered.
final class ScriptedPermission: NSObject, ArktPermissionRequest {
  let tab: any ArktTabHandle
  let origin: String
  let kinds: [NSNumber]
  let title: String
  let items: [String]
  let allowTitle: String
  let allowThisTimeTitle: String?
  let blockTitle: String
  private(set) var isEnded = false
  private(set) var choice: ArktPermissionChoice?
  var onEnd: (() -> Void)?

  init(tab: any ArktTabHandle, origin: String, kinds: [ArktPermissionKind], items: [String], oneTime: Bool) {
    self.tab = tab; self.origin = origin; self.kinds = kinds.map { NSNumber(value: $0.rawValue) }
    self.items = items
    title = "\(origin) wants to"
    allowTitle = oneTime ? "Allow while visiting the site" : "Allow"
    allowThisTimeTitle = oneTime ? "Allow this time" : nil
    blockTitle = oneTime ? "Never allow" : "Block"
  }

  func respond(choice: ArktPermissionChoice) -> Bool {
    guard !isEnded else { return false }
    self.choice = choice
    end()
    return true
  }

  /// The engine's own end, or the end after an answer: once, reported with `PermissionEnded`.
  func end() {
    guard !isEnded else { return }
    isEnded = true
    onEnd?()
  }
}

/// An infobar (#400): plain values and the shell's actions. `actions` records what reached the delegate; Ok, Cancel and
/// Close remove the infobar (the delegate returned true), a link keeps it.
final class ScriptedInfobar: NSObject, ArktInfobar {
  private static var counter: UInt = 0
  let infobarId: UInt
  let tab: any ArktTabHandle
  var kind: ArktInfobarKind = .other
  var message: String
  var messageLinkRanges: [NSValue] = []
  var linkTitle: String?
  var linkAccessibilityLabel: String?
  var linkBeforeButtons = false
  var okTitle: String? = "OK"
  var okTooltip: String?
  var okEnabled = true
  var cancelTitle: String? = "Cancel"
  var cancelTooltip: String?
  var cancelEnabled = true
  var closeAccessibilityLabel: String? = "Close"
  var iconPNG: Data?
  private(set) var isEnded = false
  private(set) var actions: [(action: ArktInfobarAction, linkIndex: UInt)] = []
  /// The tab removes the infobar from its list and reports the new one.
  var onRemoved: ((ScriptedInfobar) -> Void)?

  init(tab: any ArktTabHandle, message: String) {
    Self.counter += 1
    infobarId = Self.counter
    self.tab = tab; self.message = message
  }

  func act(_ action: ArktInfobarAction, linkIndex: UInt) -> Bool {
    guard !isEnded else { return false }
    actions.append((action, linkIndex))
    switch action {
    case .link, .messageLink: break
    case .ok, .cancel, .close: remove()
    @unknown default: break
    }
    return true
  }

  /// The infobar is gone, whoever removed it.
  func remove() {
    guard !isEnded else { return }
    isEnded = true
    onRemoved?(self)
  }
}

final class ScriptedHistoryEntry: NSObject, ArktHistoryEntry {
  let url: URL
  let title: String
  init(url: URL, title: String) { self.url = url; self.title = title }
}

final class ScriptedAction: NSObject, ArktExtensionAction {
  let actionId: String
  let name: String
  let iconPNG: Data?
  let isEnabled: Bool
  init(actionId: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true) {
    self.actionId = actionId; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
  }
}

final class ScriptedRequest: NSObject, ArktWindowRequest {
  let kind: ArktWindowRequestKind
  let opener: (any ArktBrowserHandle)?
  let bounds: NSRect
  let hasBounds: Bool
  let profileId = "Default"
  let initialURL: URL?
  let isPopup: Bool
  init(kind: ArktWindowRequestKind, opener: (any ArktBrowserHandle)? = nil, bounds: NSRect? = nil,
       initialURL: URL? = nil, isPopup: Bool = false) {
    self.kind = kind; self.opener = opener; self.bounds = bounds ?? .zero; self.hasBounds = bounds != nil
    self.initialURL = initialURL; self.isPopup = isPopup
  }
}

/// What a leave-site dialog, when answered, decides.
enum PendingDialog {
  /// A single tab close with the reason it reports when accepted.
  case tab(ArktCloseReason)
  /// The tab's window is closing.
  case window
}

final class ScriptedTab: NSObject, ArktTabHandle {
  unowned let facade: ScriptedFacade
  let containerView = NSView()
  private(set) var contentsView = NSView()
  var sessionId: Int32
  weak var owner: ScriptedBrowser?
  var browser: (any ArktBrowserHandle)? { owner }
  var url: URL?
  var title = ""
  var faviconPNG: Data?
  var isLoading = false
  /// Nearest first, as the header specifies.
  var back: [(url: URL, title: String)] = []
  var forward: [(url: URL, title: String)] = []
  var backEntries: [any ArktHistoryEntry] { back.map { ScriptedHistoryEntry(url: $0.url, title: $0.title) } }
  var forwardEntries: [any ArktHistoryEntry] { forward.map { ScriptedHistoryEntry(url: $0.url, title: $0.title) } }
  var canGoBack: Bool { !back.isEmpty }
  var canGoForward: Bool { !forward.isEmpty }
  let opener: (any ArktTabHandle)?
  let origin: ArktTabOrigin
  var isActive: Bool { owner?.active === self }
  var isClosing = false
  /// A `beforeunload` handler registered with sticky user activation.
  var wouldHoldClose = false
  /// Sound (#364). Set directly, they model a tab that was already playing or muted when it was inserted.
  var isAudible = false
  var isMuted = false
  var dialog: PendingDialog?
  /// Inserted later (a deferred createTab); calls queue until then.
  var isPending = false
  var queued: [() -> Void] = []
  /// Showing the initial about:blank, which is replaced by the first navigation and never kept in the history.
  var isInitialBlank = false
  /// The title the current load will report.
  private var loadingTitle: String?
  private var committedHost: String?
  private var lastHistory = (false, false)

  init(facade: ScriptedFacade, owner: ScriptedBrowser, opener: (any ArktTabHandle)?, origin: ArktTabOrigin) {
    self.facade = facade; self.owner = owner; self.opener = opener; self.origin = origin
    sessionId = facade.nextId()
    super.init()
    containerView.addSubview(contentsView)
  }

  private var current: (url: URL, title: String)? { url.map { ($0, title) } }

  // MARK: JavaScript dialogs (#400)

  /// The pending alert, confirm or prompt.
  private(set) var jsDialog: ScriptedDialog?

  /// The page raises a dialog: the earlier one ends first, as Chromium's manager closes it.
  @discardableResult
  func raiseDialog(_ kind: ArktDialogKind, message: String, defaultText: String? = nil) -> ScriptedDialog {
    endJSDialog()
    let dialog = ScriptedDialog(kind: kind, tab: self, title: "\(url?.host() ?? "This page") says", message: message,
                                defaultPromptText: defaultText)
    dialog.onEnd = { [weak self, unowned dialog] in
      guard let self else { return }
      if jsDialog === dialog { jsDialog = nil }
      record(.dialogEnded) { $0.dialog = dialog }
    }
    jsDialog = dialog
    record(.dialogRequested) { $0.dialog = dialog }
    return dialog
  }

  /// The tab stopped being its window's active tab: Chromium's manager answers a confirm or prompt false or null
  /// (`kTabHidden`) and closes it; an alert already ran its callback and stays.
  func hidden() {
    guard let kind = jsDialog?.kind, kind != .alert else { return }
    endJSDialog()
  }

  /// The engine ends the pending dialog (a navigation, a later dialog, the tab closing).
  func endJSDialog() { jsDialog?.end() }

  // MARK: Permission requests (#400)

  /// The pending request, and what asked for it (kept so a hidden tab can ask again, as Chromium's manager does).
  private(set) var permission: ScriptedPermission?
  private var permissionAsk: (origin: String, kinds: [ArktPermissionKind], items: [String], oneTime: Bool)?

  /// The page asks for a permission: the earlier request ends first. Shown only while the tab is its window's active
  /// tab (a hidden tab's ask stays pending until it is shown).
  @discardableResult
  func askPermission(_ kinds: [ArktPermissionKind], items: [String], oneTime: Bool) -> ScriptedPermission? {
    endPermission()
    permissionAsk = (url?.host() ?? "This page", kinds, items, oneTime)
    return showPermission()
  }

  private func showPermission() -> ScriptedPermission? {
    guard let ask = permissionAsk, isActive else { return nil }
    let request = ScriptedPermission(tab: self, origin: ask.origin, kinds: ask.kinds, items: ask.items,
                                     oneTime: ask.oneTime)
    request.onEnd = { [weak self, unowned request] in
      guard let self else { return }
      if permission === request { permission = nil }
      record(.permissionEnded) { $0.permission = request }
    }
    permission = request
    record(.permissionRequested) { $0.permission = request }
    return request
  }

  /// The tab stopped being its window's active tab: Chromium's manager deletes the prompt and keeps the ask pending.
  func permissionHidden() { endPermissionView() }

  /// The tab is its window's active tab again: the pending ask gets a new prompt.
  func permissionShown() {
    guard permission == nil, permissionAsk != nil else { return }
    _ = showPermission()
  }

  /// The site withdraws the ask, or a navigation or the tab closing drops it: the prompt ends and the ask is gone.
  func endPermission() {
    permissionAsk = nil
    permission?.end()
  }

  private func endPermissionView() { permission?.end() }

  // MARK: Infobars (#400)

  /// The tab's infobars in the engine's order; they stay while the tab is hidden.
  private(set) var infobars: [ScriptedInfobar] = []

  private func makeInfobar(_ message: String, _ configure: (ScriptedInfobar) -> Void) -> ScriptedInfobar {
    let infobar = ScriptedInfobar(tab: self, message: message)
    configure(infobar)
    infobar.onRemoved = { [weak self] removed in
      guard let self else { return }
      infobars.removeAll { $0 === removed }
      reportInfobars()
    }
    return infobar
  }

  /// The engine adds an infobar and reports the tab's whole list.
  @discardableResult
  func addInfobar(_ message: String, configure: (ScriptedInfobar) -> Void = { _ in }) -> ScriptedInfobar {
    let infobar = makeInfobar(message, configure)
    infobars.append(infobar)
    reportInfobars()
    return infobar
  }

  /// The tab moved to another window: its infobars come back as one list of new infobars; the old objects are gone and
  /// refuse every action.
  func moveInfobarsToNewPresenter() {
    let old = infobars
    for previous in old { previous.onRemoved = nil; previous.remove() }
    infobars = old.map { previous in makeInfobar(previous.message) { _ in } }
    reportInfobars()
  }

  private func reportInfobars() {
    let list = infobars
    record(.infobarsChanged) { $0.infobars = list }
  }

  private func record(_ kind: ArktEngineEventKind, _ fill: (ScriptedEvent) -> Void = { _ in }) {
    let event = ScriptedEvent(kind, tab: self, browser: owner)
    fill(event)
    facade.record(event)
  }

  /// Runs now, or after the deferred insert.
  private func whenInserted(_ call: @escaping () -> Void) {
    if isPending { queued.append(call) } else { call() }
  }

  // MARK: Loads

  func startLoad(_ target: URL, title: String?) {
    isInitialBlank = false
    url = target
    loadingTitle = title
    record(.urlChanged) { $0.url = target }
    if !isLoading {
      isLoading = true
      record(.loadingChanged) { $0.isLoading = true }
    }
    reportHistory()
  }

  /// The end of the current load: the document's title, a favicon clear on a host change, the load end, then the
  /// new favicon. With `facade.titleAfterLoadEnd` the title and the clear are recorded after the load end, in the
  /// same batch (contract rules 2 and 6 rely on ChromiumEngine's reordering).
  func finishLoad() {
    guard isLoading, let url else { return }
    let newTitle = loadingTitle ?? ScriptedFacade.title(of: url)
    let host = url.host ?? url.absoluteString
    let hostChanged = committedHost != nil && committedHost != host
    committedHost = host
    let clear = { [self] in
      if hostChanged, faviconPNG != nil {
        faviconPNG = nil
        record(.faviconChanged)
      }
    }
    let retitle = { [self] in
      if title != newTitle {
        title = newTitle
        record(.titleChanged) { $0.title = newTitle }
      }
    }
    if !facade.titleAfterLoadEnd { retitle(); clear() }
    isLoading = false
    record(.loadingChanged) { $0.isLoading = false }
    if facade.titleAfterLoadEnd { retitle(); clear() }
    if faviconPNG == nil {
      let png = Data("png:\(host)".utf8)
      faviconPNG = png
      record(.faviconChanged) { $0.faviconPNG = png }
    }
  }

  func setDocumentTitle(_ newTitle: String) {
    guard title != newTitle else { return }
    title = newTitle
    record(.titleChanged) { $0.title = newTitle }
  }

  func reportHistory() {
    let now = (canGoBack, canGoForward)
    guard now != lastHistory else { return }
    lastHistory = now
    record(.historyChanged) { $0.canGoBack = now.0; $0.canGoForward = now.1 }
  }

  // MARK: ArktTabHandle

  func navigate(to target: URL) {
    whenInserted { [self] in
      guard owner != nil else { return }
      endJSDialog()                 // Chromium closes it when the navigation starts
      endPermission()               // and drops the ask
      if let current, current.url != target, !isInitialBlank {
        back.insert(current, at: 0)
        forward = []
      }
      startLoad(target, title: nil)
    }
  }

  func reload() {
    whenInserted { [self] in
      guard owner != nil, url != nil, !isLoading else { return }
      isLoading = true
      record(.loadingChanged) { $0.isLoading = true }
    }
  }

  func goBack() { goToHistory(offset: -1) }
  func goForward() { goToHistory(offset: 1) }

  func goToHistory(offset: Int) {
    whenInserted { [self] in
      guard owner != nil, let here = current, offset != 0 else { return }
      let target: (url: URL, title: String)
      if offset < 0, -offset <= back.count {
        let steps = -offset
        target = back[steps - 1]
        forward = Array(back[..<(steps - 1)].reversed()) + [here] + forward
        back.removeFirst(steps)
      } else if offset > 0, offset <= forward.count {
        target = forward[offset - 1]
        back = Array(forward[..<(offset - 1)].reversed()) + [here] + back
        forward.removeFirst(offset)
      } else {
        return
      }
      startLoad(target.url, title: target.title)
    }
  }

  func activate() {
    whenInserted { [self] in
      owner?.activate(self)
      unpark()
    }
  }

  func close(mode: ArktCloseMode) -> ArktCloseResult {
    // As the real facade (`ScopedSkipUnloadHandlers`), a close that skips unload handlers runs whatever close is
    // under way, a pending leave-site dialog included; ChromiumEngine guards its own held close (`clientCloseHeld`).
    guard let owner, !isClosing || mode == .skipUnloadHandlers else {
      return isClosing ? .held : .closed
    }
    if isPending || facade.isNested {
      isClosing = true
      let deferred = { [self] in
        isClosing = false
        _ = close(mode: mode)
      }
      if isPending { queued.append(deferred) } else { facade.defer(deferred) }
      return .held
    }
    if wouldHoldClose && mode == .honourUnloadHandlers {
      isClosing = true
      dialog = .tab(.client)
      return .held
    }
    owner.remove(self, reason: .client)
    return .closed
  }

  /// `WebContents::SetAudioMuted`: `MutedChanged` only when the state changes.
  func setMuted(_ muted: Bool) {
    whenInserted { [self] in
      guard owner != nil, isMuted != muted else { return }
      isMuted = muted
      record(.mutedChanged) { $0.isMuted = muted }
    }
  }

  // MARK: Frame copy (#370, #352)

  /// The page's size in points and its backing scale, for `copyFrame`.
  var frameSize = NSSize(width: 1280, height: 800)
  var frameScale: CGFloat = 2
  /// False models a tab whose surface Chromium cannot copy: hidden and evicted, discarded, or never drawn.
  var frameAvailable = true
  /// The `maxPixelSize` of every `copyFrame`, in order.
  private(set) var copyRequests: [NSSize] = []

  /// `RenderWidgetHostView::CopyFromSurface` as the facade runs it: nil without a drawn frame, else a PNG scaled down
  /// to fit `maxPixelSize` (zero: full size), answered later on the main thread.
  func copyFrame(maxPixelSize: NSSize, completion: @escaping (Data?, NSSize, CGFloat) -> Void) {
    copyRequests.append(maxPixelSize)
    let frame = owner != nil && committedHost != nil && frameAvailable ? renderFrame(fitting: maxPixelSize) : nil
    Task { @MainActor in completion(frame?.png, frame?.size ?? .zero, frame?.scale ?? 0) }
  }

  private func renderFrame(fitting cap: NSSize) -> (png: Data, size: NSSize, scale: CGFloat)? {
    var width = (frameSize.width * frameScale).rounded()
    var height = (frameSize.height * frameScale).rounded()
    if cap.width > 0, cap.height > 0 {
      let factor = min(1, cap.width / width, cap.height / height)
      width = max(1, (width * factor).rounded(.down))
      height = max(1, (height * factor).rounded(.down))
    }
    guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return (data as Data, NSSize(width: width, height: height), width / frameSize.width)
  }

  /// The page starts or stops playing sound (`OnAudioStateChanged`).
  func setAudible(_ audible: Bool) {
    guard isAudible != audible else { return }
    recordAudible(audible)
  }

  /// Records `AudibleChanged` whatever the last report was.
  func recordAudible(_ audible: Bool) {
    isAudible = audible
    record(.audibleChanged) { $0.isAudible = audible }
  }

  /// How often the client asked for focus.
  private(set) var focusCount = 0
  func focus() { focusCount += 1 }

  /// Little Arkt's Open in (#314): `TabMoved`, then the tab becomes the target's active tab; an emptied window
  /// closes, as Chromium closes a Browser whose last tab left.
  func move(to browser: any ArktBrowserHandle) {
    whenInserted { [self] in
      guard let source = owner, let target = browser as? ScriptedBrowser, target !== source, !target.isClosed else {
        return
      }
      source.move(self, to: target)
      target.activate(self)
      if source.tabList.isEmpty { source.finishClose(reason: .windowClosing, window: .lastTabClosed) }
    }
  }

  /// A parked copy (#380): the page's URL, title and history, not active, and no load until it is shown (activated,
  /// navigated or moved), as the real facade holds the clone outside the tab strip.
  func duplicate() -> (any ArktTabHandle)? {
    guard let owner else { return nil }
    return owner.insertParkedCopy(of: self)
  }

  /// The load a parked copy still owes; it starts when the copy is shown.
  var parkedLoad: (url: URL, title: String?)?

  private func unpark() {
    guard let pending = parkedLoad else { return }
    parkedLoad = nil
    startLoad(pending.url, title: pending.title)
  }

  // MARK: Engine side

  /// `kReplaced` (crash recovery, prerender): new contents in the same container, a new session id.
  func replaceContents() {
    contentsView.removeFromSuperview()
    contentsView = NSView()
    containerView.addSubview(contentsView)
    sessionId = facade.nextId()
    record(.tabReplaced)
  }

  /// The dialog's answer (`answerDialogInTab:accept:`).
  func answer(accept: Bool) -> Bool {
    guard let pending = dialog, let owner else { return false }
    dialog = nil
    switch pending {
    case .tab(let reason):
      if accept {
        owner.remove(self, reason: reason)
      } else {
        isClosing = false
        record(.closeCancelled)
      }
    case .window:
      owner.windowDialogAnswered(by: self, accept: accept)
    }
    return true
  }
}

final class ScriptedBrowser: NSObject, ArktBrowserHandle {
  unowned let facade: ScriptedFacade
  let windowId: Int32
  let host: any ArktWindowHost
  private(set) var tabList: [ScriptedTab] = []
  private(set) weak var active: ScriptedTab?
  var tabs: [any ArktTabHandle] { tabList }
  var activeTab: (any ArktTabHandle)? { active }
  private(set) var isClosingWindow = false
  private(set) var isClosed = false
  /// Commands the host forwarded (`executeCommand`).
  var executed: [(command: Int, disposition: Int)] = []

  init(facade: ScriptedFacade, host: any ArktWindowHost) {
    self.facade = facade; self.host = host
    windowId = facade.nextId()
  }

  func createTab(url: URL?, active: Bool) -> any ArktTabHandle {
    if facade.isNested {
      let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .client)
      tab.isPending = true
      tab.sessionId = -1
      facade.defer { [self] in
        guard !isClosed else {
          tab.isPending = false
          tab.owner = nil
          let closed = ScriptedEvent(.tabClosed, tab: tab, browser: nil)
          closed.closeReason = .windowClosing
          facade.record(closed)
          return
        }
        tab.sessionId = facade.nextId()
        insert(tab, active: active, url: url)
        tab.isPending = false
        let calls = tab.queued
        tab.queued = []
        calls.forEach { $0() }
      }
      return tab
    }
    let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .client)
    insert(tab, active: active, url: url)
    return tab
  }

  @discardableResult
  /// A duplicate parked for this window: reported with `TabCreated`, never active, loading only when shown.
  func insertParkedCopy(of source: ScriptedTab) -> ScriptedTab {
    let tab = ScriptedTab(facade: facade, owner: self, opener: source, origin: .client)
    tab.url = source.url
    tab.title = source.title
    tab.isInitialBlank = source.isInitialBlank
    tab.back = source.back
    tab.forward = source.forward
    if let url = source.url, !source.isInitialBlank { tab.parkedLoad = (url, source.title) }
    insert(tab, active: false, url: nil)
    tab.reportHistory()
    return tab
  }

  func insertTab(opener: (any ArktTabHandle)?, origin: ArktTabOrigin, active: Bool) -> ScriptedTab {
    let tab = ScriptedTab(facade: facade, owner: self, opener: opener, origin: origin)
    insert(tab, active: active, url: nil)
    return tab
  }

  /// `chrome::NewEmptyWindow`'s tab: Chromium's New Tab page, created already showing its URL (#299).
  /// `urlAtInsert` false: the tab is inserted before its navigation starts (TabCreated without the URL).
  @discardableResult
  func insertNewTabPage(urlAtInsert: Bool = true) -> ScriptedTab {
    let tab = ScriptedTab(facade: facade, owner: self, opener: nil, origin: .engine)
    if urlAtInsert {
      tab.url = ScriptedFacade.newTabPage
      tab.title = "New Tab"
    }
    insert(tab, active: true, url: urlAtInsert ? nil : ScriptedFacade.newTabPage)
    return tab
  }

  /// A tab without a URL shows the initial about:blank, with no load events.
  private func insert(_ tab: ScriptedTab, active: Bool, url: URL?) {
    if tab.url == nil {
      tab.url = URL(string: "about:blank")
      tab.isInitialBlank = true
    }
    tabList.append(tab)
    let created = ScriptedEvent(.tabCreated, tab: tab, browser: self)
    created.url = tab.url; created.title = tab.title; created.opener = tab.opener; created.origin = tab.origin
    facade.record(created)
    if active || self.active == nil { activate(tab) }
    created.isActive = tab.isActive
    if let url { tab.startLoad(url, title: nil) }
  }

  func activate(_ tab: ScriptedTab) {
    guard active !== tab, tabList.contains(where: { $0 === tab }) else { return }
    let previous = active
    active = tab
    facade.record(ScriptedEvent(.activeTabChanged, tab: tab, browser: self))
    previous?.hidden()
    previous?.permissionHidden()
    tab.permissionShown()
  }

  /// Removes a tab; closing the active tab activates its right neighbour, else the left one.
  func remove(_ tab: ScriptedTab, reason: ArktCloseReason, reactivate: Bool = true) {
    guard let index = tabList.firstIndex(where: { $0 === tab }) else { return }
    tabList.remove(at: index)
    tab.owner = nil
    tab.isClosing = false
    tab.dialog = nil
    let closed = ScriptedEvent(.tabClosed, tab: tab, browser: self)
    closed.closeReason = reason
    facade.record(closed)
    tab.endJSDialog()           // the manager goes with the contents, after the tab strip reported the removal
    tab.endPermission()
    if active === tab {
      active = nil
      if reactivate, !tabList.isEmpty { activate(tabList[min(index, tabList.count - 1)]) }
    }
  }

  /// Moves a tab out to another window (`chrome.tabs.move`): same handle, same container.
  func move(_ tab: ScriptedTab, to target: ScriptedBrowser) {
    guard let index = tabList.firstIndex(where: { $0 === tab }) else { return }
    tabList.remove(at: index)
    if active === tab { active = nil }
    target.tabList.append(tab)
    tab.owner = target
    facade.record(ScriptedEvent(.tabMoved, tab: tab, browser: target))
    if target.active == nil { target.activate(tab) }
  }

  /// What the window close under way reports: its tabs' reason and its own.
  private var closing: (tabs: ArktCloseReason, window: ArktWindowCloseReason) = (.windowClosing, .user)

  /// The host's close request (the user): tabs `windowClosing`, the window `user`.
  func close() { close(tabs: .windowClosing, window: .user) }

  /// `chrome.windows.remove`: tabs and window report `extension` (Decision 12, #401).
  func closeByExtension() { close(tabs: .extension, window: .extension) }

  /// Unload processing first: a tab with a `beforeunload` handler holds the whole window close.
  private func close(tabs tabReason: ArktCloseReason, window windowReason: ArktWindowCloseReason) {
    guard !isClosed, !isClosingWindow else { return }
    closing = (tabReason, windowReason)
    let holding = tabList.filter(\.wouldHoldClose)
    guard holding.isEmpty else {
      isClosingWindow = true
      for tab in holding {
        tab.isClosing = true
        tab.dialog = .window
      }
      return
    }
    finishClose(reason: tabReason, window: windowReason)
  }

  func windowDialogAnswered(by tab: ScriptedTab, accept: Bool) {
    guard isClosingWindow else { return }
    if accept {
      tab.isClosing = false
      guard !tabList.contains(where: { $0.dialog != nil }) else { return }
      isClosingWindow = false
      finishClose(reason: closing.tabs, window: closing.window)
    } else {
      isClosingWindow = false
      for held in tabList where held.isClosing {
        held.isClosing = false
        held.dialog = nil
        facade.record(ScriptedEvent(.closeCancelled, tab: held, browser: self))
      }
    }
  }

  func finishClose(reason: ArktCloseReason, window windowReason: ArktWindowCloseReason) {
    for tab in tabList { remove(tab, reason: reason, reactivate: false) }
    isClosed = true
    facade.closed(self, reason: windowReason)
  }
}

/// The facade. One instance per test; several `ChromiumEngine`s may share it.
final class ScriptedFacade: NSObject, ArktEngine {
  private var lastId: Int32 = 100
  private var pending: [any ArktEngineEvent] = []
  private var deferred: [() -> Void] = []
  private var sinks: [(token: NSObject, sink: ([any ArktEngineEvent]) -> Void)] = []
  private var flushScheduled = false
  private(set) var browserList: [ScriptedBrowser] = []
  private(set) var batches: [[any ArktEngineEvent]] = []
  private(set) var ready = false
  private(set) var failed = false
  private(set) var ranActions: [(id: String, window: Int32, anchor: NSView)] = []
  private var actions: [ObjectIdentifier: [ScriptedAction]] = [:]

  /// While set, mutators defer their work to the next batch (a nested run loop is up).
  var isNested = false
  /// Records a load's title and favicon clear after its load end (Risk 2).
  var titleAfterLoadEnd = false
  /// While set, batches wait for `flush()`.
  var holdsBatches = false
  var testAPIEnabled = true
  /// Answers engine window requests (`-hostForEngineWindowRequest:` on the embedder).
  var hostProvider: ((any ArktWindowRequest) -> any ArktWindowHost)?

  var browsers: [any ArktBrowserHandle] { browserList.filter { !$0.isClosed } }
  /// No event waits for delivery.
  var isIdle: Bool { pending.isEmpty && deferred.isEmpty && !flushScheduled }

  func nextId() -> Int32 { lastId += 1; return lastId }

  func record(_ event: any ArktEngineEvent) {
    pending.append(event)
    scheduleFlush()
  }

  func `defer`(_ work: @escaping () -> Void) {
    deferred.append(work)
    scheduleFlush()
  }

  private func scheduleFlush() {
    guard !flushScheduled, !holdsBatches else { return }
    flushScheduled = true
    Task { @MainActor in self.flush() }
  }

  /// Runs deferred work, then delivers one batch to every sink, in order.
  func flush() {
    flushScheduled = false
    let work = deferred
    deferred = []
    work.forEach { $0() }
    guard !pending.isEmpty else { return }
    let batch = pending
    pending = []
    batches.append(batch)
    for entry in sinks { entry.sink(batch) }
  }

  func closed(_ browser: ScriptedBrowser, reason: ArktWindowCloseReason) {
    browser.host.closeRequested = nil
    browser.host.validateCommand = nil
    browser.host.executeCommand = nil
    let event = ScriptedEvent(.windowClosed, tab: nil, browser: browser)
    event.windowCloseReason = reason
    record(event)
  }

  // MARK: ArktEngine

  func embedderReady() { ready = true }
  func embedderFailed() { failed = true }

  func createBrowser(host: any ArktWindowHost) -> any ArktBrowserHandle {
    makeBrowser(host: host)
  }

  @discardableResult
  private func makeBrowser(host: any ArktWindowHost) -> ScriptedBrowser {
    let browser = ScriptedBrowser(facade: self, host: host)
    browserList.append(browser)
    host.closeRequested = { [unowned browser] in browser.close() }
    host.validateCommand = { $0 > 0 }
    host.executeCommand = { [unowned browser] command, disposition in
      browser.executed.append((command, disposition))
    }
    record(ScriptedEvent(.windowOpened, tab: nil, browser: browser))
    return browser
  }

  func extensionActions(in browser: any ArktBrowserHandle) -> [any ArktExtensionAction] {
    actions[ObjectIdentifier(browser)] ?? []
  }

  func runExtensionAction(_ actionId: String, in browser: any ArktBrowserHandle, anchor: NSView) {
    ranActions.append((actionId, browser.windowId, anchor))
  }

  func addEventSink(_ sink: @escaping ([any ArktEngineEvent]) -> Void) -> any NSObjectProtocol {
    let token = NSObject()
    sinks.append((token, sink))
    return token
  }

  func removeEventSink(_ token: any NSObjectProtocol) {
    sinks.removeAll { $0.token === token }
  }

  var sinkCount: Int { sinks.count }

  /// The scripts the harness drivers send, as the W3-9 runner will through the real test API.
  func evaluateScript(_ script: String, in tab: any ArktTabHandle, userGesture: Bool,
                      completion: @escaping (Any?, (any Error)?) -> Void) {
    let answer: (Any?, (any Error)?)
    if !testAPIEnabled {
      answer = (nil, NSError(domain: "ScriptedFacade", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "the test API is disabled"]))
    } else if let tab = tab as? ScriptedTab, tab.owner != nil {
      answer = (run(script, in: tab, userGesture: userGesture), nil)
    } else {
      answer = (nil, NSError(domain: "ScriptedFacade", code: 2,
                             userInfo: [NSLocalizedDescriptionKey: "The page went away before the script answered"]))
    }
    // The real facade answers from a posted task.
    Task { @MainActor in completion(answer.0, answer.1) }
  }

  private func run(_ script: String, in tab: ScriptedTab, userGesture: Bool) -> Any? {
    if let title = script.firstMatch(of: #/^document\.title = "(.*)"$/#)?.output.1 {
      tab.setDocumentTitle(String(title))
      return String(title)
    }
    if script.hasPrefix("window.onbeforeunload") {
      // Chromium shows the leave-site dialog only with sticky user activation.
      tab.wouldHoldClose = userGesture
      return true
    }
    if let target = script.firstMatch(of: #/^window\.open\("(.*)"\)$/#)?.output.1, let url = URL(string: String(target)) {
      guard userGesture, let owner = tab.owner else { return false }
      let opened = owner.insertTab(opener: tab, origin: .engine, active: true)
      opened.startLoad(url, title: nil)
      return true
    }
    if script == EngineContract.toneScript {
      // The autoplay policy lets a page start sound only with a user gesture.
      guard userGesture else { return "suspended" }
      tab.setAudible(true)
      return "running"
    }
    if script == "window.close()" {
      engineCloseTab(tab, reason: .page)
      return NSNull()
    }
    if script == "({sum: 1 + 2, list: [1, \"two\", null], ok: true})" {
      return ["sum": NSNumber(value: 3), "list": [NSNumber(value: 1), "two", NSNull()], "ok": NSNumber(value: true)]
    }
    return nil
  }

  func answerDialog(in tab: any ArktTabHandle, accept: Bool) -> Bool {
    guard testAPIEnabled, let tab = tab as? ScriptedTab else { return false }
    return tab.answer(accept: accept)
  }

  // MARK: Engine-side drivers (what a page, an extension or the user does)

  /// `chrome.tabs.create` from an extension.
  @discardableResult
  func engineCreateTab(in browser: ScriptedBrowser, url: URL?, opener: ScriptedTab?, active: Bool) -> ScriptedTab {
    let tab = browser.insertTab(opener: opener, origin: .engine, active: active)
    if let url { tab.startLoad(url, title: nil) }
    return tab
  }

  /// `chrome.tabs.remove` (`.extension`) or `window.close()` (`.page`); held by a `beforeunload` handler.
  func engineCloseTab(_ tab: ScriptedTab, reason: ArktCloseReason) {
    guard let owner = tab.owner else { return }
    if tab.wouldHoldClose {
      tab.isClosing = true
      tab.dialog = .tab(reason)
      return
    }
    owner.remove(tab, reason: reason)
  }

  /// `chrome.tabs.update({active: true})`.
  func engineActivate(_ tab: ScriptedTab) { tab.owner?.activate(tab) }

  /// `chrome.windows.create` and friends: asks the embedder for a host inside construction, then a first tab.
  @discardableResult
  func openEngineWindow(_ request: ScriptedRequest) -> ScriptedBrowser? {
    guard let hostProvider else { return nil }
    let browser = makeBrowser(host: hostProvider(request))
    engineCreateTab(in: browser, url: request.initialURL, opener: nil, active: true)
    return browser
  }

  /// A Dock reopen with no window (`applicationShouldHandleReopen:` -> `chrome::NewEmptyWindow`): asks the embedder
  /// for a host inside construction, then adds the New Tab page. `kind` lets a test give the same window another
  /// request kind.
  @discardableResult
  func dockReopen(kind: ArktWindowRequestKind = .reopen, urlAtInsert: Bool = true) -> (ScriptedBrowser, ScriptedTab)? {
    guard let hostProvider else { return nil }
    let browser = makeBrowser(host: hostProvider(ScriptedRequest(kind: kind)))
    return (browser, browser.insertNewTabPage(urlAtInsert: urlAtInsert))
  }

  /// Chromium's New Tab page URL.
  // A constant literal that always parses.
  static let newTabPage = URL(string: "chrome://newtab/")!

  func setActions(_ list: [ScriptedAction], in browser: ScriptedBrowser) {
    actions[ObjectIdentifier(browser)] = list
    record(ScriptedEvent(.extensionActionsChanged, tab: nil, browser: browser))
  }

  /// Quit: every tab closes with `.appTerminating`, then every window.
  func terminate() {
    for browser in browsers.compactMap({ $0 as? ScriptedBrowser }) { browser.finishClose(reason: .appTerminating, window: .appTerminating) }
  }

  /// The page's title for a test URL: its last path component.
  static func title(of url: URL) -> String {
    url.scheme == "about" ? "" : url.lastPathComponent
  }
}
