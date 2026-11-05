import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import FakeEngineKit

/// FakeEngine's tab state from WebKit's own signals (#576): a web content process that really exits is a crash, and
/// `pageZoom` is the zoom. The crash checks kill the tab's real web content process; they are skipped when WebKit no
/// longer publishes its pid.
@MainActor
struct FakeEngineTabStateTests {
  init() { _ = NSApplication.shared }

  /// Pages as data URLs (no files, no network) whose title is `title`; the crash driver kills the page's process.
  static let harness = EngineHarness(
    makeEngine: { FakeEngine() },
    pageURL: { title in
      try #require(URL(string: "data:text/html,%3Ctitle%3E\(title)%3C/title%3E%3Cp%3E\(title)%3C/p%3E"))
    },
    settle: { engine, id in
      try await EngineContract.waitUntil(timeout: .seconds(10)) {
        engine.snapshot(of: id).map { !$0.isLoading && !$0.title.isEmpty } ?? true
      }
    },
    retitle: { _, _, _ in },
    pagesOnTwoHosts: { (URL(string: "about:blank")!, URL(string: "about:blank")!) },
    crashTab: { engine, id in
      let fake = try #require(engine as? FakeEngine)
      let pid = try #require(fake.webContentProcessIdentifier(of: id), "the page has a web content process")
      try #require(kill(pid, SIGKILL) == 0)
    }
  )

  @Test(.enabled(if: FakeEngine.canReadWebContentProcessIdentifier))
  func webContentProcessExitIsACrashAndReloadRecovers() async throws {
    let engine = FakeEngine()
    let tab = engine.createTab(url: try Self.harness.pageURL("Crash"), in: engine.createWindow(host: StubWindowHost()))
    try await Self.harness.settle(engine, tab)
    let recorder = EventRecorder(engine)

    let crash = try #require(Self.harness.crashTab)
    try await crash(engine, tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash != nil }
    #expect(engine.snapshot(of: tab)?.crash == .crashed)

    engine.reload(tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.crash == nil }
    try await Self.harness.settle(engine, tab)

    // The recovery comes with the reload's commit: after the crash, possibly after the reload's loadingChanged(true),
    // and before its loadingChanged(false).
    let events = recorder.events(for: tab)
    let crashed = try #require(events.firstIndex(of: .tabCrashed(tab, .crashed)))
    let recovered = try #require(events.firstIndex(of: .tabRecovered(tab)))
    let finished = try #require(events.lastIndex(of: .loadingChanged(tab, isLoading: false)))
    #expect(crashed < recovered && recovered < finished, "\(events)")
    #expect(events.filter { $0 == .tabRecovered(tab) }.count == 1)
    #expect(engine.snapshot(of: tab)?.title == "Crash")
    engine.closeTab(tab)
  }

  // Rule 25 of the shared contract.
  @Test func zoomStepIsReportedOnceAndNothingAtTheEnds() async throws {
    try await EngineContract.zoomStepIsReportedOnceAndNothingAtTheEnds(Self.harness)
  }
  @Test(.enabled(if: FakeEngine.canReadWebContentProcessIdentifier))
  func crashedTabStaysListed() async throws { try await EngineContract.crashedTabStaysListed(Self.harness) }
  @Test(.enabled(if: FakeEngine.canReadWebContentProcessIdentifier))
  func reloadRecoversACrashedTabOnce() async throws {
    try await EngineContract.reloadRecoversACrashedTabOnce(Self.harness)
  }

  @Test func zoomFollowsPageZoomAndIsReportedOncePerChange() throws {
    let engine = FakeEngine()
    let tab = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    let recorder = EventRecorder(engine)

    engine.zoomIn(tab)
    engine.zoomOut(tab)
    engine.zoomOut(tab)
    engine.resetZoom(tab)
    engine.resetZoom(tab)

    #expect(recorder.events(for: tab) == [
      .zoomChanged(tab, TabZoom(percent: 115, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
      .zoomChanged(tab, TabZoom(percent: 85, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
    ])
    #expect(engine.snapshot(of: tab)?.zoom == .default)
  }

  @Test func zoomCommandsReportTheSameEvents() throws {
    let engine = FakeEngine()
    let host = StubWindowHost()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: nil, in: window)
    let forward = try #require(host.forward)
    let recorder = EventRecorder(engine)

    forward.execute(.zoomIn, .currentTab)
    forward.execute(.zoomReset, .currentTab)

    #expect(recorder.events(for: tab) == [
      .zoomChanged(tab, TabZoom(percent: 115, isDefault: false), userInitiated: true),
      .zoomChanged(tab, .default, userInitiated: true),
    ])
  }

  @Test func hasNoCrashedSession() {
    #expect(FakeEngine().sessionRecovery == nil)
  }
}
