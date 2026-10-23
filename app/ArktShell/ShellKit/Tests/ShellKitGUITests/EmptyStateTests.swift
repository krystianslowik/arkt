import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// First run: a profile with no Space shows the empty state in the content card (decision 3).
@MainActor
final class EmptyStateTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeController(_ stub: StubSidebar = StubSidebar()) -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  func testEmptySidebarShowsTheEmptyStateAndImportFollowsAvailability() throws {
    let controller = makeController()
    XCTAssertTrue(controller.isShowingEmptyState)
    let view = controller.emptyState
    XCTAssertTrue(controller.rootView.card.emptyStateView === view)
    XCTAssertTrue(view.superview === controller.rootView.card.clipView)
    XCTAssertFalse(view.isHidden)
    XCTAssertEqual(view.headingLabel.stringValue, "Welcome to Arkt")
    XCTAssertEqual(view.bodyLabel.stringValue,
                   "Bring your Spaces, pinned tabs and Archive over from Arc, or start fresh.")
    XCTAssertTrue(view.importButton.isHidden)
    XCTAssertFalse(view.newSpaceButton.isHidden)

    controller.isArcImportAvailable = true
    XCTAssertFalse(view.importButton.isHidden)
    XCTAssertEqual(view.importButton.keyEquivalent, "\r", "Import from Arc is the default button")
    controller.close()
  }

  func testSidebarWithASpaceShowsNoEmptyState() throws {
    let controller = makeController(StubSidebar.sample())
    XCTAssertFalse(controller.isShowingEmptyState)
    XCTAssertNil(controller.emptyState.superview)
    controller.close()
  }

  func testNewSpaceCallsHandlerOnce() throws {
    let stub = StubSidebar()
    let controller = makeController(stub)
    var calls = 0
    controller.onNewSpace = { calls += 1 }
    controller.emptyState.newSpaceButton.performClick(nil)
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(stub.spaceOrder.isEmpty)
    controller.close()
  }

  func testDefaultNewSpaceCreatesOneSpaceAndHidesTheEmptyState() throws {
    let stub = StubSidebar()
    let controller = makeController(stub)
    controller.emptyState.newSpaceButton.performClick(nil)
    XCTAssertEqual(stub.spaceOrder.count, 1)
    let space = try XCTUnwrap(stub.spaceOrder.first)
    XCTAssertEqual(stub.space(space)?.title, ShellWindowController.newSpaceTitle)
    XCTAssertFalse(controller.isShowingEmptyState)
    XCTAssertNil(controller.emptyState.superview)
    XCTAssertEqual(controller.currentSpace, space)
    controller.close()
  }

  func testImportFromArcCallsHandlerOnceAndCreatesNothing() throws {
    let stub = StubSidebar()
    let controller = makeController(stub)
    controller.isArcImportAvailable = true
    var calls = 0
    controller.onImportFromArc = { calls += 1 }
    controller.emptyState.importButton.performClick(nil)
    XCTAssertEqual(calls, 1)
    XCTAssertTrue(stub.spaceOrder.isEmpty)
    XCTAssertTrue(controller.isShowingEmptyState)
    controller.close()
  }

  func testNewTabWithNoSpaceCreatesASpaceThenTheTab() throws {
    let stub = StubSidebar()
    let controller = makeController(stub)
    let url = try XCTUnwrap(URL(string: "https://example.com/page"))
    controller.commandBar.onOpen?(url, .newTab)
    XCTAssertEqual(stub.spaceOrder.count, 1)
    let space = try XCTUnwrap(stub.spaceOrder.first)
    let tabs = stub.children(of: .today(space))
    XCTAssertEqual(tabs.count, 1)
    XCTAssertEqual(controller.sidebarController.current, tabs.first)
    XCTAssertNotNil(controller.currentTab)
    XCTAssertFalse(controller.isShowingEmptyState)
    controller.close()
  }

  func testRemovingTheLastSpaceShowsTheEmptyStateAgain() throws {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Only")
    let controller = makeController(stub)
    XCTAssertFalse(controller.isShowingEmptyState)
    stub.removeSpace(space)
    XCTAssertTrue(controller.isShowingEmptyState)
    XCTAssertTrue(controller.rootView.card.emptyStateView === controller.emptyState)
    controller.close()
  }

  func testEmptyStateCoversThePageAndSitsBelowToasts() throws {
    let controller = makeController()
    let card = controller.rootView.card
    let page = NSView()
    card.setContent(page)
    XCTAssertTrue(card.clipView.subviews.last === controller.emptyState, "a page set later stays under it")
    XCTAssertTrue(card.subviews.last === controller.toasts.view, "toasts draw above the clip view")
    controller.close()
  }
}
