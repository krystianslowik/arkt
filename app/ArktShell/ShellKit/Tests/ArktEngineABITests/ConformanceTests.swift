import AppKit
import ArktEngineABI
import Testing

// Swift implementations of every protocol in arkt_engine.h. They prove the header imports into Swift 6 as main-actor
// protocols that plain NSObject subclasses can adopt, with no engine class symbol and without the framework. W3-6's
// scripted facade grows from these.

final class TestHistoryEntry: NSObject, ArktHistoryEntry {
  let url: URL
  let title: String
  init(url: URL, title: String) { self.url = url; self.title = title }
}

final class TestExtensionAction: NSObject, ArktExtensionAction {
  let actionId: String
  let name: String
  let iconPNG: Data?
  let isEnabled: Bool
  init(actionId: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true) {
    self.actionId = actionId; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
  }
}

/// A host as the shell will write it: no optional placeholder members.
final class TestWindowHost: NSObject, ArktWindowHost {
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                        backing: .buffered, defer: true)
  let cardView = NSView()
  var closeRequested: (() -> Void)?
  var validateCommand: ((Int) -> Bool)?
  var executeCommand: ((Int, Int) -> Void)?
}

/// A link activation as the facade reports it (#313).
final class TestLinkActivation: NSObject, ArktLinkActivation {
  let url: URL
  let tab: any ArktTabHandle
  let sourceURL: URL?
  let modifierFlags: NSEvent.ModifierFlags = .shift
  let disposition = 1
  init(url: URL, tab: any ArktTabHandle, sourceURL: URL?) { self.url = url; self.tab = tab; self.sourceURL = sourceURL }
}

/// A host that takes the optional link and key seams (#313).
final class TestLinkHost: NSObject, ArktWindowHost {
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                        backing: .buffered, defer: true)
  let cardView = NSView()
  var closeRequested: (() -> Void)?
  var validateCommand: ((Int) -> Bool)?
  var executeCommand: ((Int, Int) -> Void)?
  var asked: [URL] = []
  var keys: [UInt16] = []
  func decideLinkActivation(_ activation: any ArktLinkActivation) -> ArktLinkDecision {
    asked.append(activation.url)
    return .cancel
  }
  func unhandledKeyDown(_ event: NSEvent, in tab: (any ArktTabHandle)?) { keys.append(event.keyCode) }
}

final class TestWindowRequest: NSObject, ArktWindowRequest {
  let kind: ArktWindowRequestKind
  let opener: (any ArktBrowserHandle)?
  let bounds: NSRect
  let hasBounds: Bool
  let profileId = "Default"
  let initialURL: URL?
  let isPopup: Bool
  init(kind: ArktWindowRequestKind, opener: (any ArktBrowserHandle)?, bounds: NSRect?, initialURL: URL?,
       isPopup: Bool = false) {
    self.kind = kind; self.opener = opener; self.bounds = bounds ?? .zero; self.hasBounds = bounds != nil
    self.initialURL = initialURL; self.isPopup = isPopup
  }
}

final class TestEvent: NSObject, ArktEngineEvent {
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
  var findRequestId = 0
  var findOrdinal = 0
  var findCount = 0
  var findIsFinal = false
  init(_ kind: ArktEngineEventKind, tab: (any ArktTabHandle)?, browser: (any ArktBrowserHandle)?) {
    self.kind = kind; self.tab = tab; self.browser = browser
  }
}

final class TestTab: NSObject, ArktTabHandle {
  let containerView = NSView()
  let sessionId: Int32
  weak var owner: TestBrowser?
  var browser: (any ArktBrowserHandle)? { owner }
  var url: URL?
  var title = ""
  var faviconPNG: Data?
  var isLoading = false
  /// Nearest first, as the header specifies.
  var backEntries: [any ArktHistoryEntry] = []
  var forwardEntries: [any ArktHistoryEntry] = []
  var canGoBack: Bool { !backEntries.isEmpty }
  var canGoForward: Bool { !forwardEntries.isEmpty }
  let opener: (any ArktTabHandle)?
  let origin: ArktTabOrigin
  var isActive: Bool { owner?.activeTab === self }
  var isClosing = false
  var wouldHoldClose = false
  var isAudible = false
  private(set) var isMuted = false

  init(sessionId: Int32, owner: TestBrowser, url: URL?, opener: (any ArktTabHandle)?, origin: ArktTabOrigin) {
    self.sessionId = sessionId; self.owner = owner; self.url = url; self.opener = opener; self.origin = origin
  }

  private var here: (any ArktHistoryEntry)? { url.map { TestHistoryEntry(url: $0, title: title) } }

  func navigate(to url: URL) {
    if let here { backEntries.insert(here, at: 0) }
    forwardEntries = []
    self.url = url
  }
  func reload() { isLoading = true }
  func goBack() { goToHistory(offset: -1) }
  func goForward() { goToHistory(offset: 1) }
  func goToHistory(offset: Int) {
    guard let here else { return }
    if offset < 0, -offset <= backEntries.count {
      let steps = -offset
      url = backEntries[steps - 1].url
      forwardEntries = backEntries[..<(steps - 1)].reversed() + [here] + forwardEntries
      backEntries.removeFirst(steps)
    } else if offset > 0, offset <= forwardEntries.count {
      url = forwardEntries[offset - 1].url
      backEntries = forwardEntries[..<(offset - 1)].reversed() + [here] + backEntries
      forwardEntries.removeFirst(offset)
    }
  }
  func activate() { owner?.activate(self) }
  func close(mode: ArktCloseMode) -> ArktCloseResult {
    if wouldHoldClose && mode == .honourUnloadHandlers {
      isClosing = true
      return .held
    }
    owner?.remove(self, reason: .client)
    return .closed
  }
  func focus() {}
  private(set) var movedTo: [any ArktBrowserHandle] = []
  func move(to browser: any ArktBrowserHandle) { movedTo.append(browser) }
  func setMuted(_ muted: Bool) {
    guard isMuted != muted else { return }
    isMuted = muted
    let event = TestEvent(.mutedChanged, tab: self, browser: owner)
    event.isMuted = muted
    owner?.engine.record(event)
  }
  /// The find (#134): the calls as received, and one final reply of 1 of 1 per non-empty text.
  private(set) var finds: [(text: String, forward: Bool, matchCase: Bool)] = []
  private(set) var stops: [ArktFindAction] = []
  func findInPage(text: String, forward: Bool, matchCase: Bool) {
    finds.append((text, forward, matchCase))
    let event = TestEvent(.findResult, tab: self, browser: owner)
    event.findRequestId = text.isEmpty ? 0 : finds.count
    event.findOrdinal = text.isEmpty ? 0 : 1
    event.findCount = text.isEmpty ? 0 : 1
    event.findIsFinal = true
    owner?.engine.record(event)
  }
  func stopFinding(action: ArktFindAction) { stops.append(action) }
  /// Reports the link under the pointer (#114).
  func hover(_ url: URL?) {
    let event = TestEvent(.targetURLChanged, tab: self, browser: owner)
    event.url = url
    owner?.engine.record(event)
  }
  /// A copy of the current frame (#370, #352): a 2 x 1 pixel PNG stand-in at scale 1, or nil with no URL.
  private(set) var copyRequests: [NSSize] = []
  func copyFrame(maxPixelSize: NSSize, completion: @escaping (Data?, NSSize, CGFloat) -> Void) {
    copyRequests.append(maxPixelSize)
    let hasFrame = url != nil
    Task { @MainActor in
      completion(hasFrame ? Data("png".utf8) : nil, hasFrame ? NSSize(width: 2, height: 1) : .zero, hasFrame ? 1 : 0)
    }
  }
  func duplicate() -> (any ArktTabHandle)? {
    guard let owner else { return nil }
    let copy = owner.insertTab(url: url, active: false, opener: self, origin: .client)
    copy.title = title
    copy.backEntries = backEntries
    copy.forwardEntries = forwardEntries
    return copy
  }
}

final class TestBrowser: NSObject, ArktBrowserHandle {
  let windowId: Int32
  let host: any ArktWindowHost
  unowned let engine: TestEngine
  private(set) var tabList: [TestTab] = []
  private(set) weak var active: TestTab?
  var tabs: [any ArktTabHandle] { tabList }
  var activeTab: (any ArktTabHandle)? { active }

  init(windowId: Int32, host: any ArktWindowHost, engine: TestEngine) {
    self.windowId = windowId; self.host = host; self.engine = engine
  }

  func createTab(url: URL?, active: Bool) -> any ArktTabHandle {
    insertTab(url: url, active: active, opener: nil, origin: .client)
  }

  @discardableResult
  func insertTab(url: URL?, active: Bool, opener: (any ArktTabHandle)?, origin: ArktTabOrigin) -> TestTab {
    let tab = TestTab(sessionId: engine.nextId(), owner: self, url: url ?? URL(string: "about:blank"),
                      opener: opener, origin: origin)
    tabList.append(tab)
    let created = TestEvent(.tabCreated, tab: tab, browser: self)
    created.url = tab.url; created.opener = opener; created.origin = origin
    engine.record(created)
    if active || self.active == nil { activate(tab) }
    created.isActive = tab.isActive
    return tab
  }

  func activate(_ tab: TestTab) {
    guard active !== tab else { return }
    active = tab
    engine.record(TestEvent(.activeTabChanged, tab: tab, browser: self))
  }

  func remove(_ tab: TestTab, reason: ArktCloseReason) {
    tabList.removeAll { $0 === tab }
    tab.owner = nil
    if active === tab { active = nil }
    let closed = TestEvent(.tabClosed, tab: tab, browser: self)
    closed.closeReason = reason
    engine.record(closed)
  }

  func close() {
    for tab in tabList { remove(tab, reason: .windowClosing) }
    engine.closeBrowser(self)
  }
}

/// A facade that records events and delivers them as one batch on `flush()`, as the real facade does from a posted
/// task.
final class TestEngine: NSObject, ArktEngine {
  private var lastId: Int32 = 0
  private var pending: [any ArktEngineEvent] = []
  private var sinks: [ObjectIdentifier: (token: NSObject, sink: ([any ArktEngineEvent]) -> Void)] = [:]
  private(set) var browserList: [TestBrowser] = []
  private(set) var isReady = false
  private(set) var failed = false
  private(set) var ranActions: [String] = []
  var testAPIEnabled = true
  var browsers: [any ArktBrowserHandle] { browserList }

  func nextId() -> Int32 { lastId += 1; return lastId }
  func record(_ event: any ArktEngineEvent) { pending.append(event) }
  func flush() {
    let batch = pending
    pending = []
    for entry in sinks.values { entry.sink(batch) }
  }

  func embedderReady() { isReady = true }
  func embedderFailed() { failed = true }

  func createBrowser(host: any ArktWindowHost) -> any ArktBrowserHandle {
    let browser = TestBrowser(windowId: nextId(), host: host, engine: self)
    browserList.append(browser)
    host.closeRequested = { [unowned browser] in browser.close() }
    host.validateCommand = { $0 > 0 }
    host.executeCommand = { _, _ in }
    record(TestEvent(.windowOpened, tab: nil, browser: browser))
    return browser
  }

  func closeBrowser(_ browser: TestBrowser) {
    browserList.removeAll { $0 === browser }
    browser.host.closeRequested = nil
    let event = TestEvent(.windowClosed, tab: nil, browser: browser)
    event.windowCloseReason = .user
    record(event)
  }

  func extensionActions(in browser: any ArktBrowserHandle) -> [any ArktExtensionAction] {
    [TestExtensionAction(actionId: "action-probe", name: "Action Probe")]
  }

  func runExtensionAction(_ actionId: String, in browser: any ArktBrowserHandle, anchor: NSView) {
    ranActions.append(actionId)
  }

  func addEventSink(_ sink: @escaping ([any ArktEngineEvent]) -> Void) -> any NSObjectProtocol {
    let token = NSObject()
    sinks[ObjectIdentifier(token)] = (token, sink)
    return token
  }

  func removeEventSink(_ token: any NSObjectProtocol) {
    guard let object = token as? NSObject else { return }
    sinks[ObjectIdentifier(object)] = nil
  }

  func evaluateScript(_ script: String, in tab: any ArktTabHandle, userGesture: Bool,
                      completion: @escaping (Any?, (any Error)?) -> Void) {
    completion(testAPIEnabled ? script.count : nil, nil)
  }

  func answerDialog(in tab: any ArktTabHandle, accept: Bool) -> Bool { false }
}

/// The app's embedder, as `ArktShellEmbedder` will be: found by name, never linked by the engine.
@objc(ArktEngineABITestEmbedder)
final class TestEmbedder: NSObject, ArktEngineEmbedder {
  static let shared = TestEmbedder()
  private(set) var engine: (any ArktEngine)?
  private(set) var requests: [any ArktWindowRequest] = []
  private(set) var terminationLog: [String] = []

  static func sharedEmbedder() -> any ArktEngineEmbedder { shared }

  func engineDidStart(_ engine: any ArktEngine) {
    self.engine = engine
    engine.embedderReady()
  }

  func host(for request: any ArktWindowRequest) -> any ArktWindowHost {
    requests.append(request)
    return TestWindowHost()
  }

  func engineWillBeginTerminating() { terminationLog.append("begin") }
  func engineDidCancelTerminating() { terminationLog.append("cancel") }
  func engineWillTerminate(_ completion: @escaping () -> Void) {
    terminationLog.append("terminate")
    completion()
  }
}

@MainActor
struct ConformanceTests {
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  @Test func embedderIsFoundByItsRuntimeNameAndAnswersTheHook() throws {
    // What the hook does: NSClassFromString, then +sharedEmbedder through the protocol.
    let found = try #require(NSClassFromString("ArktEngineABITestEmbedder") as? any ArktEngineEmbedder.Type)
    let embedder = found.sharedEmbedder()
    #expect(embedder === TestEmbedder.shared)

    let engine = TestEngine()
    embedder.engineDidStart(engine)
    #expect(engine.isReady)
    #expect(TestEmbedder.shared.engine === engine)
  }

  @Test func engineCreatesBrowsersAndTabsThroughTheProtocols() {
    let engine: any ArktEngine = TestEngine()
    let host = TestWindowHost()
    let browser = engine.createBrowser(host: host)
    #expect(engine.browsers.count == 1)
    #expect(browser.host === host)

    let first = browser.createTab(url: Self.url("a"), active: true)
    let second = browser.createTab(url: nil, active: false)
    #expect(browser.tabs.map(\.sessionId) == [first.sessionId, second.sessionId])
    #expect(browser.activeTab === first)
    #expect(second.url == URL(string: "about:blank"))
    #expect(second.origin == .client && second.browser === browser && second.containerView !== first.containerView)

    second.activate()
    #expect(browser.activeTab === second && second.isActive && !first.isActive)
    first.focus()
    first.reload()
    #expect(first.isLoading)
  }

  /// The facade serves EngineClient's history(of:), goToHistory(_:offset:) and duplicateTab(_:) (contract rules 9
  /// and 10): entries nearest first, offsets as steps, a duplicate with the source's history.
  @Test func historyIsNearestFirstAndDuplicatesCarryIt() throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: Self.url("a"), active: true)
    tab.navigate(to: Self.url("b"))
    tab.navigate(to: Self.url("c"))
    #expect(tab.backEntries.map(\.url) == [Self.url("b"), Self.url("a")])

    tab.goToHistory(offset: -2)
    #expect(tab.url == Self.url("a") && !tab.canGoBack)
    #expect(tab.forwardEntries.map(\.url) == [Self.url("b"), Self.url("c")])
    tab.goToHistory(offset: 0)
    tab.goToHistory(offset: 3)
    #expect(tab.url == Self.url("a"), "0 and out-of-range offsets are no-ops")
    tab.goForward()
    #expect(tab.url == Self.url("b"))
    #expect(tab.backEntries.map(\.url) == [Self.url("a")] && tab.forwardEntries.map(\.url) == [Self.url("c")])

    let copy = try #require(tab.duplicate())
    #expect(copy.url == tab.url && copy.title == tab.title && copy.origin == .client && copy.opener === tab)
    #expect(copy.backEntries.map(\.url) == tab.backEntries.map(\.url))
    #expect(copy.forwardEntries.map(\.url) == tab.forwardEntries.map(\.url))
    #expect(browser.tabs.count == 2 && browser.activeTab === tab)
  }

  @Test func closesAnswerClosedOrHeldByMode() throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)
    try #require(tab as? TestTab).wouldHoldClose = true

    #expect(tab.wouldHoldClose)
    #expect(tab.close(mode: .honourUnloadHandlers) == .held)
    #expect(tab.isClosing && browser.tabs.count == 1)
    #expect(tab.close(mode: .skipUnloadHandlers) == .closed)
    #expect(browser.tabs.isEmpty && tab.browser == nil)
    #expect(tab.duplicate() == nil, "a closed tab cannot be duplicated")
  }

  @Test func eventBatchArrivesInOrderWithPlainValues() throws {
    let engine = TestEngine()
    var batches: [[any ArktEngineEvent]] = []
    let token = engine.addEventSink { batches.append($0) }

    let browser = engine.createBrowser(host: TestWindowHost())
    let opener = browser.createTab(url: Self.url("opener"), active: true)
    let popup = try #require(browser as? TestBrowser).insertTab(url: nil, active: true, opener: opener, origin: .engine)
    #expect(opener.close(mode: .honourUnloadHandlers) == .closed)
    #expect(batches.isEmpty, "events are delivered from a posted task, never from inside the call")
    engine.flush()

    #expect(batches.count == 1)
    let batch = try #require(batches.first)
    #expect(batch.map(\.kind) == [.windowOpened, .tabCreated, .activeTabChanged, .tabCreated, .activeTabChanged,
                                  .tabClosed])
    try #require(batch.count == 6)
    #expect(batch[0].tab == nil && batch[0].browser === browser)
    #expect(batch[1].url == Self.url("opener") && batch[1].origin == .client && batch[1].isActive)
    #expect(batch[3].tab === popup && batch[3].opener === opener && batch[3].origin == .engine)
    #expect(batch[5].tab === opener && batch[5].closeReason == .client)
    #expect(batch.dropLast().allSatisfy { $0.closeReason == .none })

    engine.removeEventSink(token)
    browser.close()
    engine.flush()
    #expect(batches.count == 1, "a removed sink receives nothing")
  }

  @Test func windowCloseClosesTabsWithWindowClosingThenReportsTheWindow() throws {
    let engine = TestEngine()
    var kinds: [ArktEngineEventKind] = []
    var reasons: [ArktCloseReason] = []
    var windowReasons: [ArktWindowCloseReason] = []
    _ = engine.addEventSink { batch in
      kinds += batch.map(\.kind)
      reasons += batch.filter { $0.kind == .tabClosed }.map(\.closeReason)
      windowReasons += batch.map(\.windowCloseReason)
    }
    let host = TestWindowHost()
    let browser = engine.createBrowser(host: host)
    _ = browser.createTab(url: nil, active: true)
    _ = browser.createTab(url: nil, active: false)
    engine.flush()
    kinds = []
    windowReasons = []

    // The host never closes its window itself: it calls the block the engine set.
    let closeRequested = try #require(host.closeRequested)
    closeRequested()
    engine.flush()
    #expect(kinds == [.tabClosed, .tabClosed, .windowClosed])
    #expect(reasons == [.windowClosing, .windowClosing])
    // #401: only WindowClosed carries a window close reason; the host's request is the user's.
    #expect(windowReasons == [.none, .none, .user])
    #expect(engine.browsers.isEmpty && host.closeRequested == nil)
  }

  @Test func windowRequestIsAnsweredWithAHost() {
    let engine = TestEngine()
    let opener = engine.createBrowser(host: TestWindowHost())
    let request = TestWindowRequest(kind: .extension, opener: opener,
                                    bounds: NSRect(x: 10, y: 20, width: 800, height: 600),
                                    initialURL: Self.url("popup"))
    let unsized = TestWindowRequest(kind: .reopen, opener: nil, bounds: nil, initialURL: nil)

    let embedder = TestEmbedder()
    let host = (embedder as any ArktEngineEmbedder).host(for: request)
    _ = (embedder as any ArktEngineEmbedder).host(for: unsized)
    _ = engine.createBrowser(host: host)

    #expect(request.hasBounds && request.bounds.width == 800 && request.opener === opener)
    #expect(!unsized.hasBounds && unsized.opener == nil && unsized.initialURL == nil)
    #expect(engine.browsers.count == 2)
    #expect(embedder.requests.map(\.kind) == [.extension, .reopen])
  }

  @Test func hostAnswersCommandsThroughEngineBlocksAndOmitsPlaceholderMembers() throws {
    let host = TestWindowHost()
    _ = TestEngine().createBrowser(host: host)
    let validate = try #require(host.validateCommand)
    #expect(validate(34014) && !validate(0))
    host.executeCommand?(34014, 1)
    // The placeholder-only members are optional, so a shell host does not implement them.
    #expect(!host.responds(to: #selector(ArktWindowHost.tabListChanged(_:))))
    #expect(!host.responds(to: #selector(setter: ArktWindowHost.activateTab)))
    #expect(host.responds(to: #selector(setter: ArktWindowHost.closeRequested)))
    #expect(!host.responds(to: #selector(ArktWindowHost.decideLinkActivation(_:))))
  }

  @Test func linkAndKeySeamsAreOptionalHostMembers() throws {
    let host = TestLinkHost()
    let engine = TestEngine()
    let browser = engine.createBrowser(host: host)
    let tab = browser.createTab(url: URL(string: "https://mail.test/")!, active: true)
    let seam: any ArktWindowHost = host
    let answer = seam.decideLinkActivation?(TestLinkActivation(url: URL(string: "https://atlas.test/")!, tab: tab,
                                                               sourceURL: tab.url))
    #expect(answer == .cancel)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: 0, context: nil, characters: "\u{1b}",
                                               charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53))
    seam.unhandledKeyDown?(escape, in: tab)
    #expect(host.asked == [URL(string: "https://atlas.test/")!] && host.keys == [53])
    withExtendedLifetime(engine) {}
  }

  @Test func extensionActionsAndTestAPIGoThroughTheFacade() {
    let facade = TestEngine()
    let engine: any ArktEngine = facade
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)

    let actions = engine.extensionActions(in: browser)
    #expect(actions.map(\.actionId) == ["action-probe"])
    #expect(actions.allSatisfy { $0.isEnabled && $0.iconPNG == nil && !$0.name.isEmpty })
    engine.runExtensionAction("action-probe", in: browser, anchor: NSView())
    #expect(facade.ranActions == ["action-probe"])

    var result: Any?
    engine.evaluateScript("1 + 1", in: tab, userGesture: true) { value, _ in result = value }
    #expect(result as? Int == 5)
    #expect(engine.testAPIEnabled && !engine.answerDialog(in: tab, accept: true))
  }

  @Test func terminationSeamsRunTheCompletion() {
    let embedder = TestEmbedder()
    var completed = false
    embedder.engineWillBeginTerminating()
    embedder.engineDidCancelTerminating()
    embedder.engineWillBeginTerminating()
    embedder.engineWillTerminate { completed = true }
    #expect(completed)
    #expect(embedder.terminationLog == ["begin", "cancel", "begin", "terminate"])
  }

  @Test func readinessAndFailureReachTheFacade() {
    let ready = TestEngine()
    let failed = TestEngine()
    let engines: [any ArktEngine] = [ready, failed]
    engines[0].embedderReady()
    engines[1].embedderFailed()
    #expect(ready.isReady && !ready.failed)
    #expect(failed.failed && !failed.isReady)
  }

  /// Raw values cross the boundary as integers; pinning them catches a reordered enum.
  @Test func enumRawValuesAreStable() {
    #expect([ArktCloseMode.honourUnloadHandlers, .skipUnloadHandlers].map(\.rawValue) == [0, 1])
    #expect([ArktCloseResult.closed, .held].map(\.rawValue) == [0, 1])
    #expect([ArktCloseReason.none, .client, .page, .extension, .windowClosing, .appTerminating].map(\.rawValue)
      == Array(0...5))
    #expect([ArktWindowCloseReason.none, .user, .extension, .lastTabClosed, .appTerminating].map(\.rawValue)
      == Array(0...4))
    #expect([ArktTabOrigin.client, .engine].map(\.rawValue) == [0, 1])
    #expect([ArktEngineEventKind.tabCreated, .tabClosed, .activeTabChanged, .closeCancelled, .urlChanged,
             .titleChanged, .faviconChanged, .loadingChanged, .historyChanged, .tabReplaced, .tabMoved,
             .windowOpened, .windowClosed, .extensionActionsChanged, .audibleChanged, .mutedChanged,
             .dialogRequested, .dialogEnded, .permissionRequested, .permissionEnded, .infobarsChanged,
             .findResult, .targetURLChanged].map(\.rawValue)
      == Array(0...22))
    #expect([ArktFindAction.clear, .keep, .activate].map(\.rawValue) == [0, 1, 2])
    #expect([ArktInfobarKind.other, .debugger, .automation, .reload].map(\.rawValue) == Array(0...3))
    #expect([ArktInfobarAction.ok, .cancel, .link, .messageLink, .close].map(\.rawValue) == Array(0...4))
    #expect([ArktPermissionKind.other, .geolocation, .notifications, .camera, .microphone].map(\.rawValue)
      == Array(0...4))
    #expect([ArktPermissionChoice.allow, .allowThisTime, .block, .dismiss].map(\.rawValue) == Array(0...3))
    #expect([ArktDialogKind.alert, .confirm, .prompt].map(\.rawValue) == [0, 1, 2])
    #expect([ArktWindowRequestKind.extension, .page, .reopen, .startupURL].map(\.rawValue) == Array(0...3))
    #expect([ArktLinkDecision.navigate, .cancel].map(\.rawValue) == [0, 1])
  }
}

/// Little Arkt (#314): the request's popup flag and the tab move are part of the ABI.
@MainActor
struct LittleArktABITests {
  @Test func popupRequestAndTabMoveAreReachable() {
    let engine = TestEngine()
    let source = engine.createBrowser(host: TestWindowHost())
    let target = engine.createBrowser(host: TestWindowHost())
    let request: any ArktWindowRequest = TestWindowRequest(kind: .page, opener: source, bounds: nil,
                                                           initialURL: nil, isPopup: true)
    #expect(request.kind == .page && request.isPopup)
    let tab = source.createTab(url: nil, active: true)
    tab.move(to: target)
    #expect((tab as? TestTab)?.movedTo.first === target)
  }
}

/// Tab mute (#364): the handle's sound state and `setMuted(_:)` are part of the ABI, and a change arrives as a
/// `MutedChanged` event with the plain value.
@MainActor
struct MuteABITests {
  @Test func setMutedChangesTheHandleAndRecordsOneEvent() throws {
    let engine = TestEngine()
    var batches: [[any ArktEngineEvent]] = []
    let token = engine.addEventSink { batches.append($0) }
    defer { engine.removeEventSink(token) }
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)
    engine.flush()
    #expect(!tab.isMuted && !tab.isAudible)

    tab.setMuted(true)
    tab.setMuted(true)
    engine.flush()

    #expect(tab.isMuted)
    let events = try #require(batches.last)
    #expect(events.map(\.kind) == [.mutedChanged])
    #expect(events.first?.isMuted == true && events.first?.tab === tab)
  }
}

/// Find in page and link hover (#134, #114): the calls and the plain values of the two events are part of the ABI.
@MainActor
struct FindABITests {
  @Test func findAndStopReachTheHandleAndRepliesCarryPlainValues() throws {
    let engine = TestEngine()
    var batches: [[any ArktEngineEvent]] = []
    let token = engine.addEventSink { batches.append($0) }
    defer { engine.removeEventSink(token) }
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = try #require(browser.createTab(url: nil, active: true) as? TestTab)
    engine.flush()

    tab.findInPage(text: "needle", forward: false, matchCase: true)
    tab.stopFinding(action: .keep)
    engine.flush()

    #expect(tab.finds.count == 1 && tab.finds[0].text == "needle" && !tab.finds[0].forward && tab.finds[0].matchCase)
    #expect(tab.stops == [.keep])
    let reply = try #require(batches.last?.first)
    #expect(reply.kind == .findResult && reply.tab === tab)
    #expect(reply.findRequestId == 1 && reply.findOrdinal == 1 && reply.findCount == 1 && reply.findIsFinal)
  }

  @Test func targetURLEventCarriesTheURLOrNilOnLeave() throws {
    let engine = TestEngine()
    var batches: [[any ArktEngineEvent]] = []
    let token = engine.addEventSink { batches.append($0) }
    defer { engine.removeEventSink(token) }
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = try #require(browser.createTab(url: nil, active: true) as? TestTab)
    engine.flush()

    let link = URL(string: "https://example.com/next")!
    tab.hover(link)
    engine.flush()
    tab.hover(nil)
    engine.flush()

    let events = batches.suffix(2).compactMap(\.first)
    #expect(events.map(\.kind) == [.targetURLChanged, .targetURLChanged])
    #expect(events.map(\.url) == [link, nil])
  }
}

/// The frame copy seam (#370, #352): an asynchronous completion with the PNG, its pixel size and scale, and the cap
/// passed through as given.
@MainActor
struct FrameCopyABITests {
  @Test func copyFrameAnswersLaterWithTheFrame() async throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: URL(string: "arkt-test://page/Frame"), active: true)
    var answered = false
    let result: (Data?, NSSize, CGFloat) = await withCheckedContinuation { continuation in
      tab.copyFrame(maxPixelSize: NSSize(width: 600, height: 360)) { png, size, scale in
        answered = true
        continuation.resume(returning: (png, size, scale))
      }
      #expect(!answered, "the completion runs later, never inside the call")
    }
    #expect(result.0 == Data("png".utf8))
    #expect(result.1 == NSSize(width: 2, height: 1))
    #expect(result.2 == 1)
    #expect((tab as? TestTab)?.copyRequests == [NSSize(width: 600, height: 360)])
  }
}

/// JavaScript dialogs (#400): the event carries the dialog, the dialog carries the engine's strings and takes one
/// answer, and an answer after the end is refused.
@MainActor
struct JavaScriptDialogABITests {
  final class Dialog: NSObject, ArktJavaScriptDialog {
    let kind: ArktDialogKind = .prompt
    let tab: any ArktTabHandle
    let title = "example.com says"
    let message = "Name?"
    let defaultPromptText: String? = "Ada"
    let acceptTitle = "OK"
    let cancelTitle: String? = "Cancel"
    private(set) var isEnded = false
    private(set) var answers: [(Bool, String?)] = []
    init(tab: any ArktTabHandle) { self.tab = tab }
    func respond(accepted: Bool, userInput: String?) -> Bool {
      guard !isEnded else { return false }
      isEnded = true
      answers.append((accepted, userInput))
      return true
    }
  }

  @Test func theEventCarriesTheDialogAndItTakesOneAnswer() throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)
    let dialog = Dialog(tab: tab)
    let event = TestEvent(.dialogRequested, tab: tab, browser: browser)
    event.dialog = dialog

    let carried = try #require(event.dialog)
    #expect(carried.kind == .prompt && carried.title == "example.com says" && carried.message == "Name?")
    #expect(carried.defaultPromptText == "Ada" && carried.acceptTitle == "OK" && carried.cancelTitle == "Cancel")
    #expect(carried.tab === tab)
    #expect(carried.respond(accepted: true, userInput: "Grace"))
    #expect(!carried.respond(accepted: false, userInput: nil), "the answer after the end is refused")
    #expect(carried.isEnded && dialog.answers.count == 1 && dialog.answers.first?.1 == "Grace")
  }
}

/// Permission requests (#400): the event carries the request, the request carries the engine's strings and takes one
/// answer, and an answer after the end is refused.
@MainActor
struct PermissionRequestABITests {
  final class Request: NSObject, ArktPermissionRequest {
    let tab: any ArktTabHandle
    let origin = "example.com"
    let kinds: [NSNumber] = [NSNumber(value: ArktPermissionKind.geolocation.rawValue)]
    let title = "example.com wants to"
    let items = ["Know your location"]
    let allowTitle = "Allow while visiting the site"
    let allowThisTimeTitle: String? = "Allow this time"
    let blockTitle = "Never allow"
    private(set) var isEnded = false
    private(set) var choices: [ArktPermissionChoice] = []
    init(tab: any ArktTabHandle) { self.tab = tab }
    func respond(choice: ArktPermissionChoice) -> Bool {
      guard !isEnded else { return false }
      isEnded = true
      choices.append(choice)
      return true
    }
  }

  @Test func theEventCarriesTheRequestAndItTakesOneAnswer() throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)
    let request = Request(tab: tab)
    let event = TestEvent(.permissionRequested, tab: tab, browser: browser)
    event.permission = request

    let carried = try #require(event.permission)
    #expect(carried.origin == "example.com" && carried.title == "example.com wants to")
    #expect(carried.kinds == [1] && carried.items == ["Know your location"])
    #expect(carried.allowTitle == "Allow while visiting the site" && carried.allowThisTimeTitle == "Allow this time")
    #expect(carried.blockTitle == "Never allow" && carried.tab === tab)
    #expect(carried.respond(choice: .allowThisTime))
    #expect(!carried.respond(choice: .block), "the answer after the end is refused")
    #expect(carried.isEnded && request.choices == [.allowThisTime])
  }
}

/// Infobars (#400): the event carries the tab's list, an infobar carries the engine's strings and takes actions until it
/// is gone, and a gone infobar refuses them.
@MainActor
struct InfobarABITests {
  final class Infobar: NSObject, ArktInfobar {
    let infobarId: UInt = 7
    let tab: any ArktTabHandle
    let kind = ArktInfobarKind.debugger
    let message = "\"Page Inspector\" started debugging this browser"
    let messageLinkRanges: [NSValue] = [NSValue(range: NSRange(location: 1, length: 14))]
    let linkTitle: String? = nil
    let linkAccessibilityLabel: String? = nil
    let linkBeforeButtons = false
    let okTitle: String? = "Cancel"
    let okTooltip: String? = nil
    let okEnabled = true
    let cancelTitle: String? = nil
    let cancelTooltip: String? = nil
    let cancelEnabled = true
    let closeAccessibilityLabel: String? = "Close"
    let iconPNG: Data? = nil
    private(set) var isEnded = false
    private(set) var actions: [(ArktInfobarAction, UInt)] = []
    init(tab: any ArktTabHandle) { self.tab = tab }
    func act(_ action: ArktInfobarAction, linkIndex: UInt) -> Bool {
      guard !isEnded else { return false }
      actions.append((action, linkIndex))
      isEnded = action == .ok
      return true
    }
  }

  @Test func theEventCarriesTheListAndAnInfobarTakesActionsUntilItIsGone() throws {
    let engine = TestEngine()
    let browser = engine.createBrowser(host: TestWindowHost())
    let tab = browser.createTab(url: nil, active: true)
    let infobar = Infobar(tab: tab)
    let event = TestEvent(.infobarsChanged, tab: tab, browser: browser)
    event.infobars = [infobar]

    let carried = try #require(event.infobars?.first)
    #expect(event.infobars?.count == 1 && carried.infobarId == 7 && carried.tab === tab)
    #expect(carried.kind == .debugger && carried.okTitle == "Cancel" && carried.cancelTitle == nil)
    #expect(carried.messageLinkRanges.map(\.rangeValue) == [NSRange(location: 1, length: 14)])
    #expect(carried.closeAccessibilityLabel == "Close")
    #expect(carried.act(.messageLink, linkIndex: 0))
    #expect(carried.act(.ok, linkIndex: 0))
    #expect(!carried.act(.close, linkIndex: 0), "an action after the end is refused")
    #expect(infobar.actions.map(\.0) == [.messageLink, .ok])
  }
}
