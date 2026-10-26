import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Sidebar drag and drop across windows (#104): a tab dragged out over no window opens in a new one (GS-013), and a
/// row dropped on another window's sidebar is shown there. Both take the live page over with Tab Handoff (#300): one
/// engine tab, never a second load.
@MainActor
final class SidebarDragWindowTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet() throws -> (set: ShellWindowSet, engine: InMemoryEngine, source: ModelSidebarSource,
                                    world: EngineWorld) {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    sets.append(set)
    return (set, engine, source, world)
  }

  private func drop(of controller: ShellWindowController) throws -> SidebarOutlineDrop {
    try XCTUnwrap(controller.sidebarController.currentPage?.outlineController.drop)
  }

  /// Starts a drag of `node`'s row in `controller`, released at `point` over no window.
  private func dragOut(_ node: UUID, from controller: ShellWindowController, to point: NSPoint,
                       escape: Bool = false) throws {
    let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    outline.draggingSessionWillBegin(items: [outline.item(for: node)])
    outline.drop.endedByEscape = { escape }
    outline.drop.windowFrames = { [CGRect(x: 0, y: 0, width: 400, height: 400)] }
    outline.drop.sourceEnded(at: point, operation: [])
    outline.draggingSessionEnded()
  }

  func testATabDraggedOutOverNoWindowOpensInANewWindowWithItsPage() throws {
    let (set, engine, _, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    let tabsBefore = engine.tabIDs

    try dragOut(world.today[0], from: first, to: NSPoint(x: 900, y: 700))

    XCTAssertEqual(set.controllers.count, 2)
    let second = try XCTUnwrap(set.controllers.last)
    XCTAssertEqual(second.currentTab, tab, "the same page, moved")
    XCTAssertEqual(engine.tabIDs, tabsBefore, "no second load")
    let window = try XCTUnwrap(second.window)
    var placed = window.frame
    placed.origin = NSPoint(x: 900, y: 700 - placed.height)
    let expected = window.constrainFrameRect(placed, to: window.screen)
    XCTAssertEqual(window.frame.minX, expected.minX, accuracy: 1, "the window opens where the tab was let go")
    XCTAssertEqual(window.frame.maxY, expected.maxY, accuracy: 1)
    XCTAssertNil(first.engineTab(of: world.today[0]))
  }

  func testEscapeOrAReleaseOverAWindowOpensNothing() throws {
    let (set, _, _, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[0])
    try dragOut(world.today[0], from: first, to: NSPoint(x: 900, y: 700), escape: true)
    try dragOut(world.today[0], from: first, to: NSPoint(x: 100, y: 100))
    XCTAssertEqual(set.controllers.count, 1)
  }

  func testARowDroppedOnAnotherWindowsSidebarIsShownThereWithItsPage() throws {
    let (set, engine, source, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[1])
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    let tabsBefore = engine.tabIDs

    let drop = try drop(of: second)
    let outline = try XCTUnwrap(second.sidebarController.currentPage?.outlineController)
    let rect = outline.outlineView.rect(ofRow: outline.row(for: world.today[2]))
    let point = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.9)
    let payload = SidebarDragPayload(nodes: [world.today[0]], isSingleTab: true)
    drop.update(at: point, payload: payload)
    XCTAssertTrue(drop.perform(payload: payload, at: point, duplicate: false, fromOtherWindow: true))

    XCTAssertEqual(source.children(of: .today(world.space)).prefix(3),
                   [world.today[1], world.today[2], world.today[0]])
    XCTAssertEqual(second.currentTab, tab)
    XCTAssertEqual(engine.tabIDs, tabsBefore)
    XCTAssertNotNil(first.handoffPlaceholder, "the window the page left shows the placeholder")
  }

  /// The stale-URL bug class across windows: a navigated pin live in one window, dropped in another window's Today,
  /// stores the page it shows. Its live page was in the other window when the drop landed.
  func testANavigatedPinDroppedInAnotherWindowsTodayStoresItsLiveURL() throws {
    let (set, engine, source, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: world.pinned)
    let tab = try XCTUnwrap(first.engineTab(of: world.pinned))
    engine.navigate(tab, to: EngineWorld.url("p/elsewhere"))

    let drop = try drop(of: second)
    let outline = try XCTUnwrap(second.sidebarController.currentPage?.outlineController)
    let rect = outline.outlineView.rect(ofRow: outline.row(for: world.today[0]))
    let point = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.1)
    let payload = SidebarDragPayload(nodes: [world.pinned], isSingleTab: true)
    drop.update(at: point, payload: payload)
    XCTAssertTrue(drop.perform(payload: payload, at: point, duplicate: false, fromOtherWindow: true))

    XCTAssertEqual(source.children(of: .today(world.space)).first, world.pinned)
    guard case .tab(_, let url, _)? = source.node(world.pinned) else { return XCTFail("not a tab") }
    XCTAssertEqual(url, EngineWorld.url("p/elsewhere"), "no stale pinned URL saved")
    XCTAssertEqual(second.engineTab(of: world.pinned), tab, "the page moved over")
  }
}
