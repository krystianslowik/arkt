import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Cmd-W on the window's last page (#386). Chromium closes a `Browser` with its last tab, so the engine window goes
/// away (`.windowClosed`) although nobody asked to close the shell window: the shell window stays open, shows the
/// empty card of an empty Space (#301) and keeps its rows, and the next page it shows makes a new engine window.
/// Cmd-W with no page shown closes the window (CF-03: "Close current tab or window").
@MainActor
final class LastTabCloseTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = LastTabClosesWindowEngine()
    let controller: ShellWindowController
    let space: UUID
    let pinned: [UUID]
    let today: [UUID]

    init(pinned pinnedCount: Int = 0, today todayCount: Int = 0) throws {
      var sidebar = SidebarModel.Sidebar()
      let space = sidebar.addSpace(title: "Work")
      self.space = space
      pinned = try (0..<pinnedCount).map {
        try sidebar.addTab(url: Harness.url("p\($0)"), title: "P\($0)", in: .pinned(space))
      }
      today = try (0..<todayCount).map {
        try sidebar.addTab(url: Harness.url("t\($0)"), title: "T\($0)", in: .today(space))
      }
      let source = ModelSidebarSource(sidebar: sidebar, now: { LastTabCloseTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source, opensFirstTab: false)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.onArchive = { ids in source.archive(ids, reason: .manual, at: LastTabCloseTests.now) }
      controller.showWindow(nil)
    }

    static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

    var rows: [UUID] {
      source.children(of: .pinned(space)) + source.children(of: .today(space))
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: - Last page closed

  /// The maintainer's setup: five rows, one loaded. Cmd-W on a pinned one closes its page and keeps every row; the
  /// window stays on the Space with the empty card.
  func testCmdWOnTheLastLoadedPinnedTabKeepsTheWindowWithTheEmptyCard() throws {
    let harness = try Harness(pinned: 5)
    harness.controller.activate(node: harness.pinned[2])
    let window = try XCTUnwrap(harness.controller.engineWindow)
    XCTAssertNotNil(harness.controller.rootView.card.contentView)

    harness.controller.closeTab(nil)

    XCTAssertFalse(harness.engine.windowIDs.contains(window), "the engine closed its emptied window")
    XCTAssertEqual(harness.controller.window?.isVisible, true)
    XCTAssertNil(harness.controller.engineWindow)
    XCTAssertNil(harness.controller.currentTab)
    XCTAssertNil(harness.controller.rootView.card.contentView, "the empty card of an empty Space")
    XCTAssertNil(harness.controller.rootView.card.emptyStateView, "not the first-run panel")
    XCTAssertEqual(harness.rows, harness.pinned, "every row stays")
    XCTAssertEqual(harness.controller.currentSpace, harness.space)
    harness.controller.close()
  }

  /// The row's X takes the same path as Cmd-W.
  func testTheRowXOnTheLastLoadedTabKeepsTheWindow() throws {
    let harness = try Harness(pinned: 3)
    harness.controller.activate(node: harness.pinned[0])

    harness.controller.close(node: harness.pinned[0])

    XCTAssertEqual(harness.controller.window?.isVisible, true)
    XCTAssertNil(harness.controller.rootView.card.contentView)
    XCTAssertEqual(harness.rows, harness.pinned)
    harness.controller.close()
  }

  /// After the engine window went, the next row shown gets a new engine window and its page.
  func testTheNextRowShownOpensANewEngineWindow() throws {
    let harness = try Harness(pinned: 3)
    harness.controller.activate(node: harness.pinned[0])
    let closed = try XCTUnwrap(harness.controller.engineWindow)
    harness.controller.closeTab(nil)

    harness.controller.activate(node: harness.pinned[1])

    let window = try XCTUnwrap(harness.controller.engineWindow)
    XCTAssertNotEqual(window, closed)
    let tab = try XCTUnwrap(harness.controller.currentTab)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.window, window)
    XCTAssertNotNil(harness.controller.rootView.card.contentView)
    harness.controller.close()
  }

  /// A Today tab is archived and its sibling becomes current (BH-071). The sibling's new page landed in the closing
  /// engine window and went with it, so the window shows it again in a new engine window.
  func testCmdWOnTheLastLoadedTodayTabShowsTheSiblingInANewEngineWindow() throws {
    let harness = try Harness(today: 5)
    harness.controller.activate(node: harness.today[2])
    let closed = try XCTUnwrap(harness.controller.engineWindow)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.controller.window?.isVisible, true)
    XCTAssertEqual(harness.rows, harness.today.filter { $0 != harness.today[2] }, "only the archived row left")
    let window = try XCTUnwrap(harness.controller.engineWindow)
    XCTAssertNotEqual(window, closed)
    XCTAssertEqual(harness.controller.sidebarController.current, harness.today[3])
    let tab = try XCTUnwrap(harness.controller.currentTab)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.window, window)
    XCTAssertNotNil(harness.controller.rootView.card.contentView)
    harness.controller.close()
  }

  // MARK: - Other closes still close the window

  /// The engine closing the window by itself (`chrome.windows.remove`) still closes the shell window.
  func testTheEngineClosingTheWindowClosesTheShellWindow() throws {
    let harness = try Harness(pinned: 2)
    harness.controller.activate(node: harness.pinned[0])

    harness.engine.closeWindow(try XCTUnwrap(harness.controller.engineWindow))

    XCTAssertEqual(harness.controller.window?.isVisible, false)
  }

  /// The close button with a page shown closes the window, as before.
  func testCloseWindowWithAPageShownClosesTheWindow() throws {
    let harness = try Harness(pinned: 2)
    harness.controller.activate(node: harness.pinned[0])

    harness.controller.window?.performClose(nil)

    XCTAssertEqual(harness.controller.window?.isVisible, false)
  }

  /// CF-03, #386: Cmd-W with no page shown closes the window.
  func testCmdWWithNoPageShownClosesTheWindow() throws {
    let harness = try Harness(pinned: 2)
    harness.controller.activate(node: harness.pinned[0])
    harness.controller.closeTab(nil)
    XCTAssertEqual(harness.controller.window?.isVisible, true)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.controller.window?.isVisible, false)
  }

  /// FakeEngine's shape: the engine window stays open with no page (and the parked copy). The second Cmd-W asks the
  /// engine to close it, and that close is the user's, so the window goes.
  func testASecondCmdWClosesTheWindowWhenTheEngineWindowStayed() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinned = try sidebar.addTab(url: Harness.url("p"), title: "P", in: .pinned(space))
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: ModelSidebarSource(sidebar: sidebar),
                                           opensFirstTab: false)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.activate(node: pinned)
    let window = try XCTUnwrap(controller.engineWindow)

    controller.closeTab(nil)
    XCTAssertEqual(controller.engineWindow, window, "this engine keeps an emptied window")
    XCTAssertEqual(controller.window?.isVisible, true)
    XCTAssertNil(controller.rootView.card.contentView)

    controller.closeTab(nil)

    XCTAssertFalse(engine.windowIDs.contains(window))
    XCTAssertEqual(controller.window?.isVisible, false)
  }

  /// The known gap: after a Today Cmd-W whose sibling loaded in the surviving engine window, the window still keeps
  /// itself without an engine window. A close the user asks for (Close Window, Shift-Cmd-W) wins over it: the window
  /// closes and nothing is shown again.
  func testCloseWindowAfterATodayCloseInASurvivingEngineWindowClosesTheWindow() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let first = try sidebar.addTab(url: Harness.url("t0"), title: "T0", in: .today(space))
    let second = try sidebar.addTab(url: Harness.url("t1"), title: "T1", in: .today(space))
    let source = ModelSidebarSource(sidebar: sidebar, now: { LastTabCloseTests.now })
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source, opensFirstTab: false)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.onArchive = { ids in source.archive(ids, reason: .manual, at: LastTabCloseTests.now) }
    controller.showWindow(nil)
    controller.activate(node: first)
    let window = try XCTUnwrap(controller.engineWindow)

    controller.closeTab(nil)
    XCTAssertEqual(controller.engineWindow, window, "the sibling loaded in the same engine window")
    XCTAssertEqual(controller.sidebarController.current, second)
    XCTAssertTrue(controller.keepsWindowWithoutEngine)

    controller.window?.performClose(nil)

    XCTAssertFalse(engine.windowIDs.contains(window))
    XCTAssertEqual(controller.window?.isVisible, false)
    XCTAssertNil(controller.engineWindow, "no new engine window: nothing was shown again")
  }

  /// A window that never showed a page closes on Cmd-W too.
  func testCmdWInAFreshEmptyWindowClosesIt() throws {
    let harness = try Harness(pinned: 1)
    XCTAssertNil(harness.controller.currentTab)

    harness.controller.closeTab(nil)

    XCTAssertEqual(harness.controller.window?.isVisible, false)
  }
}

/// Chromium's window life (#386): a `Browser` closes with its last tab. A tab created in a window whose last tab is
/// closing lands in the closing `Browser` and goes with it. No copy is parked (the engine refused the duplicate), so
/// nothing keeps the emptied window alive.
@MainActor
private final class LastTabClosesWindowEngine: EngineClient {
  let inner = InMemoryEngine()
  var tabIDs: [TabID] { inner.tabIDs }
  func createTab(url: URL?) -> TabID { inner.createTab(url: url) }
  func createTab(url: URL?, in window: EngineWindowID) -> TabID { inner.createTab(url: url, in: window) }
  func closeTab(_ id: TabID) { closeTab(id, mode: .honourUnloadHandlers) }
  func closeTab(_ id: TabID, mode: CloseMode) {
    guard let window = inner.snapshot(of: id)?.window else { return inner.closeTab(id, mode: mode) }
    let isLast = tabs(in: window) == [id]
    inner.closeTab(id, mode: mode)
    guard isLast, inner.snapshot(of: id) == nil, inner.windowIDs.contains(window) else { return }
    inner.closeWindow(window)
  }
  func navigate(_ id: TabID, to url: URL) { inner.navigate(id, to: url) }
  func reload(_ id: TabID) { inner.reload(id) }
  func goBack(_ id: TabID) { inner.goBack(id) }
  func goForward(_ id: TabID) { inner.goForward(id) }
  func goToHistory(_ id: TabID, offset: Int) { inner.goToHistory(id, offset: offset) }
  func history(of id: TabID) -> TabHistory? { inner.history(of: id) }
  func duplicateTab(_ id: TabID) -> TabID? { nil }
  func setMuted(_ id: TabID, muted: Bool) { inner.setMuted(id, muted: muted) }
  func snapshot(of id: TabID) -> TabSnapshot? { inner.snapshot(of: id) }
  func contentView(for id: TabID) -> NSView? { inner.contentView(for: id) }
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { inner.observe(handler) }
  var windowIDs: [EngineWindowID] { inner.windowIDs }
  func createWindow(host: any EngineWindowHosting) -> EngineWindowID { inner.createWindow(host: host) }
  func closeWindow(_ id: EngineWindowID) { inner.closeWindow(id) }
  func activateTab(_ id: TabID) { inner.activateTab(id) }
  func activeTab(in window: EngineWindowID) -> TabID? { inner.activeTab(in: window) }
  func observeWindows(_ handler: @escaping @MainActor (EngineWindowEvent) -> Void) -> EngineObservation {
    inner.observeWindows(handler)
  }
  func observe(window: EngineWindowID, _ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    inner.observe(window: window, handler)
  }

  private func tabs(in window: EngineWindowID) -> [TabID] {
    inner.tabIDs.filter { inner.snapshot(of: $0)?.window == window }
  }
}
