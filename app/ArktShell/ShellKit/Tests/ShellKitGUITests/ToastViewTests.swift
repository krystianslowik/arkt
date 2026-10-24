import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Toasts drawn over the content card of a real window.
@MainActor
final class ToastViewTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeController() -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func toastView(_ controller: ShellWindowController) throws -> ToastView {
    try XCTUnwrap(controller.toasts.view)
  }

  func testToastViewIsInsideTheCardAboveThePageAndHiddenWhenIdle() throws {
    let controller = makeController()
    let view = try toastView(controller)
    XCTAssertTrue(view.superview === controller.rootView.card)
    XCTAssertTrue(controller.rootView.card.subviews.last === view, "the toast draws above the page")
    XCTAssertNil(controller.toasts.current)
    XCTAssertTrue(view.isHidden)
    controller.close()
  }

  func testShownToastIsVisibleCenteredNearTheBottomAndCapped() throws {
    let controller = makeController()
    let view = try toastView(controller)
    controller.toasts.show(Toast(text: String(repeating: "Long notice ", count: 60)))
    controller.rootView.card.layoutSubtreeIfNeeded()
    XCTAssertFalse(view.isHidden)
    XCTAssertEqual(view.label.stringValue, controller.toasts.current?.text)
    let card = controller.rootView.card.bounds
    XCTAssertLessThanOrEqual(view.frame.width, ToastView.maxWidth)
    XCTAssertEqual(view.frame.midX, card.midX, accuracy: 1)
    XCTAssertEqual(view.frame.minY, ToastView.bottomInset, "card is not flipped: minY is the bottom edge")
    XCTAssertEqual(view.accessibilityRole(), .group)
    XCTAssertEqual(view.accessibilityLabel(), controller.toasts.current?.text)
    XCTAssertFalse(controller.window?.firstResponder === view.actionButton)
    controller.close()
  }

  func testDismissHidesTheViewAfterTheFade() throws {
    let controller = makeController()
    let view = try toastView(controller)
    controller.toasts.show(Toast(text: "Saved", isPersistent: true))
    controller.toasts.dismiss()
    XCTAssertNil(controller.toasts.current)
    let hidden = expectation(description: "hidden after fade")
    Task { @MainActor in
      while !view.isHidden { try? await Task.sleep(for: .milliseconds(20)) }
      hidden.fulfill()
    }
    wait(for: [hidden], timeout: 2)
    controller.close()
  }

  func testActionButtonRunsTheActionOnce() throws {
    let controller = makeController()
    let view = try toastView(controller)
    var calls = 0
    controller.toasts.show(Toast(text: "Restored", actionTitle: "Show Files", isPersistent: true)) { calls += 1 }
    XCTAssertFalse(view.actionButton.isHidden)
    XCTAssertEqual(view.actionButton.title, "Show Files")
    XCTAssertTrue(view.isAccessibilityElement())
    XCTAssertEqual(view.accessibilityRole(), .group)
    XCTAssertEqual(view.accessibilityLabel(), "Restored")
    // AppKit exposes a control through its cell; accept either.
    let exposed = NSAccessibility.unignoredChildren(from: view.accessibilityChildren() ?? []).map { $0 as AnyObject }
    XCTAssertTrue(exposed.contains { $0 === view.actionButton || $0 === view.actionButton.cell },
                  "VoiceOver reaches the action button inside the toast")
    XCTAssertFalse(exposed.contains { $0 === view.label || $0 === view.label.cell },
                   "the text is the group's label, not read twice")
    view.actionButton.performClick(nil)
    XCTAssertEqual(calls, 1)
    XCTAssertNil(controller.toasts.current)
    controller.close()
  }

  func testDefaultErrorHandlerShowsAToast() throws {
    let controller = makeController()
    controller.onError?(.addTab, CocoaError(.featureUnsupported))
    XCTAssertEqual(controller.toasts.current?.text, "Couldn't add the tab.")
    XCTAssertEqual(controller.toasts.current?.isPersistent, false)
    controller.close()
  }

  func testFailedNewSpaceShowsTheSpaceErrorToast() throws {
    let source = FailingSpaceSidebar()
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    XCTAssertTrue(controller.isShowingEmptyState)
    controller.onNewSpace?()
    XCTAssertEqual(controller.toasts.current?.text, "Couldn't create a Space.")
    XCTAssertEqual(controller.toasts.current?.isPersistent, false)
    XCTAssertTrue(controller.isShowingEmptyState)
    controller.close()
  }

  func testToastFlavorFollowsTheCurrentSpaceTheme() throws {
    let stub = StubSidebar()
    _ = stub.addSpace(title: "Dark", theme: SpaceThemeInfo(baseColors: [.black(1)], isDark: true))
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    XCTAssertEqual(try toastView(controller).flavor, .dark)
    controller.close()
  }
}

/// A `SidebarSource` whose `addSpace` always fails; everything else forwards to an empty `StubSidebar`.
@MainActor
private final class FailingSpaceSidebar: SidebarSource {
  private let base = StubSidebar()
  var spaceOrder: [SpaceID] { base.spaceOrder }
  func space(_ id: SpaceID) -> SidebarSpaceInfo? { base.space(id) }
  func children(of location: SidebarLocation) -> [NodeID] { base.children(of: location) }
  func node(_ id: NodeID) -> SidebarNodeInfo? { base.node(id) }
  func parent(of id: NodeID) -> SidebarLocation? { base.parent(of: id) }
  func addTab(url: URL, title: String, in location: SidebarLocation) throws -> NodeID {
    base.addTab(url: url, title: title, in: location)
  }
  func addSpace(title: String) throws -> SpaceID { throw CocoaError(.featureUnsupported) }
  func addSpace(title: String, after space: SpaceID?) throws -> SpaceID { throw CocoaError(.featureUnsupported) }
  func renameSpace(_ id: SpaceID, to title: String) { base.renameSpace(id, to: title) }
  func moveSpace(_ id: SpaceID, to index: Int) { base.moveSpace(id, to: index) }
  func setIcon(_ id: SpaceID, to icon: SpaceIconInfo?) { base.setIcon(id, to: icon) }
  func setTheme(_ id: SpaceID, to theme: SpaceThemeInfo) { base.setTheme(id, to: theme) }
  func updateTab(_ id: NodeID, url: URL?, title: String?) { base.updateTab(id, url: url, title: title) }
  func addToSplit(_ pane: SplitPaneSource, target: NodeID, at index: Int, orientation: SplitOrientation) throws
    -> (split: NodeID, pane: NodeID)
  {
    try base.addToSplit(pane, target: target, at: index, orientation: orientation)
  }
  func separatePane(_ pane: NodeID) throws { try base.separatePane(pane) }
  func separateSplit(_ split: NodeID) throws -> [NodeID] { try base.separateSplit(split) }
  func expandPane(_ pane: NodeID) throws { try base.expandPane(pane) }
  func movePane(_ pane: NodeID, to index: Int) throws { try base.movePane(pane, to: index) }
  func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws {
    try base.setSplitWidthFactors(split, factors)
  }
  func setSplitOrientation(_ split: NodeID, _ orientation: SplitOrientation) throws {
    try base.setSplitOrientation(split, orientation)
  }
  func duplicateSplit(_ split: NodeID) throws -> NodeID { try base.duplicateSplit(split) }
  func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation {
    base.observe(handler)
  }
}
