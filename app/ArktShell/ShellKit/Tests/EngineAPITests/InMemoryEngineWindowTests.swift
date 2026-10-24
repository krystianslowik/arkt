import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// InMemoryEngine behaviour beyond the contract that ShellUI tests (W3-7) rely on.
@MainActor
struct InMemoryEngineWindowTests {
  @Test func windowlessTabWithoutWindowsHasNoWindow() {
    let engine = InMemoryEngine()
    let id = engine.createTab(url: nil)
    #expect(engine.snapshot(of: id)?.window == nil)
    #expect(engine.snapshot(of: id)?.isActive == false)
  }

  @Test func extensionActionsAreListedAnnouncedAndRun() throws {
    let engine = InMemoryEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: StubWindowHost())
    let actions = [ExtensionAction(id: "a", name: "Alpha", iconPNG: Data([1])), ExtensionAction(id: "b", name: "Beta")]
    engine.setExtensionActions(actions, in: window)
    #expect(recorder.windowEvents == [.windowOpened(window), .extensionActionsChanged(window)])
    let extensions: any EngineExtensions = engine
    #expect(extensions.extensionActions(in: window) == actions)
    let anchor = NSView()
    extensions.runExtensionAction("b", in: window, anchor: anchor)
    extensions.runExtensionAction("missing", in: window, anchor: anchor)
    #expect(engine.ranExtensionActions.map(\.id) == ["b"])
    #expect(engine.ranExtensionActions.first?.anchor === anchor)
  }

  @Test func hostForwardReachesTheEngineAndIsClearedOnClose() throws {
    let engine = InMemoryEngine()
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let forward = try #require(host.forward)
    #expect(forward.validate(.find))
    forward.execute(.zoomIn, .currentTab)
    #expect(engine.executedCommands.map(\.command) == [.zoomIn])
    #expect(engine.executedCommands.first?.window == window)
    engine.closeWindow(window)
    #expect(host.forward == nil && host.onCloseRequested == nil)
  }

  @Test func engineWindowRequestsUseTheProvider() throws {
    let engine = InMemoryEngine()
    var requests: [EngineWindowRequest] = []
    #expect(engine.openEngineWindow(EngineWindowRequest(kind: .reopen, profile: EngineProfileID("p"))) == nil)
    engine.windowHostProvider = { request in requests.append(request); return StubWindowHost() }
    let url = URL(string: "arkt-test://page/Startup")!
    let request = EngineWindowRequest(kind: .startupURL, profile: EngineProfileID("p"), initialURL: url)
    let window = try #require(engine.openEngineWindow(request))
    #expect(requests == [request])
    let tab = try #require(engine.activeTab(in: window))
    let snap = try #require(engine.snapshot(of: tab))
    #expect(snap.origin == .engine && snap.url == url && snap.window == window)
  }

  @Test func observeWindowFiltersEngineTabsByWindow() {
    let engine = InMemoryEngine()
    let (first, second) = (engine.createWindow(host: StubWindowHost()), engine.createWindow(host: StubWindowHost()))
    var seen: [EngineEvent] = []
    let token = engine.observe(window: first) { seen.append($0) }
    let mine = engine.engineCreateTab(in: first)
    let theirs = engine.engineCreateTab(in: second)
    engine.engineCloseTab(mine, reason: .extension)
    #expect(seen == [.tabCreated(mine), .activeTabChanged(mine), .tabClosed(mine, reason: .extension)])
    #expect(!seen.contains { $0.tabID == theirs })
    token.cancel()
  }

  @Test func engineStartedHeldCloseKeepsItsReason() {
    let engine = InMemoryEngine()
    let recorder = EventRecorder(engine)
    let window = engine.createWindow(host: StubWindowHost())
    let id = engine.createTab(url: nil, in: window)
    engine.holdClose(id)
    engine.engineCloseTab(id, reason: .extension)
    #expect(engine.snapshot(of: id)?.isClosing == true)
    engine.closeTab(id)                                  // a second close while held does nothing
    #expect(engine.answerDialog(id, accept: true))
    #expect(recorder.events(for: id).last == .tabClosed(id, reason: .extension))
    #expect(!engine.answerDialog(id, accept: true), "no dialog left")
  }

  @Test func cancelledCloseKeepsWouldHoldClose() {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let id = engine.createTab(url: nil, in: window)
    engine.holdClose(id)
    engine.closeTab(id)
    engine.answerDialog(id, accept: false)
    #expect(engine.snapshot(of: id)?.isClosing == false && engine.snapshot(of: id)?.wouldHoldClose == true)
  }

  @Test func commandConstantsMatchChromiumIDs() {
    // chrome/app/chrome_command_ids.h at 156.0.8078.48 (week-3 results, W3-0 step 5).
    let expected: [EngineCommand: Int] = [
      .back: 33000, .forward: 33001, .reload: 33002, .closeWindow: 34012, .newTab: 34014, .closeTab: 34015,
      .exit: 34031, .viewSource: 35002, .print: 35003, .savePage: 35004, .find: 37000, .zoomIn: 38001,
      .zoomReset: 38002, .zoomOut: 38003, .devTools: 40004, .history: 40010, .downloads: 40012,
    ]
    #expect(Set(EngineCommand.all) == Set(expected.keys))
    for (command, value) in expected { #expect(command.rawValue == value, "\(command)") }
    #expect([EngineDisposition.currentTab, .newForegroundTab, .newBackgroundTab, .newWindow].map(\.rawValue)
              == [1, 3, 4, 6])
  }
}
