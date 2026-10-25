import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// W3-7 part C: the composition root's windows. Shell-created windows (launch, New Window, a Dock reopen under
/// FakeEngine) and windows built for the engine's own requests (a Dock reopen under Chromium, `chrome.windows.create`,
/// a startup URL) live in one set; a provider window is adopted when the engine announces the window it was handed
/// to, matched by host, never by order.
@MainActor
final class ShellWindowSetTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet(_ sidebar: SidebarModel.Sidebar? = nil, engine: InMemoryEngine = InMemoryEngine())
    throws -> (set: ShellWindowSet, engine: InMemoryEngine, source: ModelSidebarSource, world: EngineWorld) {
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: sidebar ?? world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine, source, world)
  }

  // MARK: Shell-created windows

  func testOpenWindowConfiguresShowsAndListsTheWindow() throws {
    let (set, _, _, _) = try makeSet()
    var configured: [ShellWindowController] = []
    set.configure = { configured.append($0) }

    let controller = set.openWindow()

    XCTAssertEqual(configured.map(ObjectIdentifier.init), [ObjectIdentifier(controller)])
    XCTAssertTrue(controller.window?.isVisible ?? false)
    XCTAssertEqual(set.controllers.map(ObjectIdentifier.init), [ObjectIdentifier(controller)])
    XCTAssertNotNil(controller.currentTab, "a launch window shows the first tab of its Space")
  }

  func testAClosedWindowLeavesTheSet() throws {
    let (set, _, _, _) = try makeSet()
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    first.window?.close()
    XCTAssertEqual(set.controllers.map(ObjectIdentifier.init), [ObjectIdentifier(second)])
    XCTAssertTrue(set.primary === second)
  }

  /// New Window (Cmd-N): the host claims `IDC_NEW_WINDOW` and the set opens a window on the same sidebar, without a
  /// page until the user picks one (no second engine tab for the row the first window shows).
  func testNewWindowIsClaimedAndOpensAWindowWithoutAPage() throws {
    let (set, engine, _, _) = try makeSet()
    let first = set.openWindow()
    let host = first.engineHost
    XCTAssertEqual(host.claim(PendingEngineCommands.newWindow), CommandClaim(isEnabled: true))

    XCTAssertTrue(host.perform(PendingEngineCommands.newWindow, disposition: .currentTab))

    XCTAssertEqual(set.controllers.count, 2)
    let second = try XCTUnwrap(set.controllers.last)
    XCTAssertTrue(second.window?.isVisible ?? false)
    XCTAssertNil(second.currentTab)
    XCTAssertEqual(engine.windowIDs.count, 1, "its engine window comes with its first tab (decision 4)")
    XCTAssertTrue(engine.executedCommands.isEmpty)
  }

  func testNewWindowIsDisabledOutsideASet() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let host = harness.controller.engineHost
    XCTAssertEqual(host.claim(PendingEngineCommands.newWindow), CommandClaim(isEnabled: false))
    XCTAssertFalse(host.perform(PendingEngineCommands.newWindow, disposition: .currentTab))
  }

  // MARK: Engine-initiated windows

  /// `chrome.windows.create` from the shown window: a window in the opener's Space, shown once adopted, with the
  /// engine's tab as a Today tab.
  func testAnExtensionWindowIsAdoptedInItsOpenersSpace() throws {
    var sidebar = try EngineWorld.make().sidebar
    let other = sidebar.addSpace(title: "Other")
    let (set, engine, source, world) = try makeSet(sidebar)
    var configured = 0
    set.configure = { _ in configured += 1 }
    let opener = set.openWindow()
    opener.sidebarController.showSpace(other)
    let openerWindow = try XCTUnwrap(opener.ensureEngineWindow())
    let url = EngineWorld.url("created")

    let id = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(
      kind: .extension, openerWindow: openerWindow, profile: EngineProfileID("default"), initialURL: url)))

    let adopted = try XCTUnwrap(set.controllers.first { $0.engineWindow == id })
    XCTAssertFalse(adopted === opener)
    XCTAssertEqual(configured, 2)
    XCTAssertTrue(adopted.window?.isVisible ?? false)
    XCTAssertEqual(adopted.currentSpace, other)
    let node = try XCTUnwrap(adopted.currentNode)
    XCTAssertEqual(source.section(containing: node), .today(other))
    XCTAssertNotEqual(source.section(containing: node), .today(world.space))
  }

  /// A request with bounds gets them (a frame inside the screen, which AppKit keeps when the window is shown).
  func testARequestedFrameIsApplied() throws {
    let (set, engine, _, _) = try makeSet()
    _ = set.openWindow()
    let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
    let bounds = CGRect(x: visible.minX + 40, y: visible.minY + 40,
                        width: min(900, visible.width - 80), height: min(640, visible.height - 80)).integral

    let id = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(
      kind: .extension, bounds: bounds, profile: EngineProfileID("default"))))

    let adopted = try XCTUnwrap(set.controllers.first { $0.engineWindow == id })
    XCTAssertEqual(adopted.window?.frame, bounds)
  }

  /// The provider's window is not shown or adopted before the engine announces it (Chromium is inside `Browser`
  /// construction), and a shell window that creates its own engine window meanwhile does not take the adoption.
  func testAPendingProviderWindowIsMatchedByItsHostNotByOrder() throws {
    let (set, engine, _, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let request = EngineWindowRequest(kind: .startupURL, profile: EngineProfileID("default"))

    let pendingHost = set.host(for: request)
    let pending = try XCTUnwrap(set.controllers.first { $0.engineHost === pendingHost })
    XCTAssertFalse(pending.window?.isVisible ?? true, "not shown before its window is announced")
    first.activate(node: world.today[0])                  // the shell's own createWindow announces its window

    let own = try XCTUnwrap(first.engineWindow)
    XCTAssertNil(pending.engineWindow, "the shell's own window is not adopted by the pending controller")
    XCTAssertTrue(engine.host(of: own) === first.engineHost)

    let id = engine.createWindow(host: pendingHost)
    XCTAssertEqual(pending.engineWindow, id)
    XCTAssertTrue(pending.window?.isVisible ?? false)
  }

  /// Dock reopen under Chromium arrives as a `.reopen` request: a shown window that never got an engine window (no
  /// tab yet, first run) is the one reused; it is not built twice.
  func testAReopenRequestReusesAShownWindowWithoutAnEngineWindow() throws {
    let (set, engine, _, _) = try makeSet()
    let shown = set.openWindow(opensFirstTab: false)

    let id = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(kind: .reopen,
                                                                       profile: EngineProfileID("default"))))

    XCTAssertEqual(set.controllers.count, 1)
    XCTAssertEqual(shown.engineWindow, id)
  }

  /// With every window closed, a reopen request builds a new one.
  func testAReopenRequestWithNoWindowBuildsOne() throws {
    let (set, engine, _, _) = try makeSet()
    let first = set.openWindow()
    first.window?.close()
    XCTAssertTrue(set.controllers.isEmpty)

    let id = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(kind: .reopen,
                                                                       profile: EngineProfileID("default"))))

    let reopened = try XCTUnwrap(set.controllers.first)
    XCTAssertEqual(reopened.engineWindow, id)
    XCTAssertTrue(reopened.window?.isVisible ?? false)
  }

  /// FakeEngine's Dock reopen (`applicationShouldHandleReopen`): the primary window comes back, or a new one is built
  /// when every window closed (#241).
  func testReopenFrontsThePrimaryWindowOrBuildsOne() throws {
    let (set, _, _, _) = try makeSet()
    let first = set.openWindow()
    first.window?.orderOut(nil)
    XCTAssertTrue(set.reopen() === first)
    XCTAssertTrue(first.window?.isVisible ?? false)
    first.window?.close()
    let second = set.reopen()
    XCTAssertFalse(second === first)
    XCTAssertTrue(second.window?.isVisible ?? false)
  }

  // MARK: Unions

  /// Quit stamps, and auto-archive skips, the tabs of every window, not only the first one.
  func testVisibleAndHoldingNodesAreUnitedOverWindows() throws {
    let (set, engine, _, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[0])
    second.activate(node: world.today[1])
    let held = try XCTUnwrap(second.currentTab)
    engine.holdClose(held)

    XCTAssertEqual(set.visibleNodes, [world.today[0], world.today[1]])
    XCTAssertEqual(set.nodesHoldingClose, [world.today[1]])
    XCTAssertTrue(set.autoArchiveExempt.isSuperset(of: [world.today[0], world.today[1]]))
  }
}
