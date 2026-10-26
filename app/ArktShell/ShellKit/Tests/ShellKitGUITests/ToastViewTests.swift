import AppKit
import CoreBridge
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
    controller.toasts.show(Toast(text: "Saved", kind: .persistent))
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
    controller.toasts.show(Toast(text: "Restored", kind: .persistent, actionTitle: "Show Files")) { calls += 1 }
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

/// The restyled toast (alerts design 4.2): glyph, action pill, the multi-line persistent variant, the Space tint,
/// timers that wait for hover and key, and replacement.
@MainActor
final class ToastLayoutTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeController(theme: SpaceThemeInfo? = nil) -> ShellWindowController {
    let stub = StubSidebar.sample()
    if let theme, let space = stub.spaceOrder.first { stub.setTheme(space, to: theme) }
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func shown(_ controller: ShellWindowController, _ toast: Toast) throws -> ToastView {
    controller.toasts.show(toast)
    controller.rootView.card.layoutSubtreeIfNeeded()
    let view = try XCTUnwrap(controller.toasts.view)
    view.layoutSubtreeIfNeeded()
    return view
  }

  /// One line: 36 high, the glyph 16 x 16 at 12 from the leading edge, the action a 24 pt pill 6 from the trailing
  /// edge, no key hint on Undo.
  func testTheUndoToastHasAGlyphAndASmallPill() throws {
    let controller = makeController()
    let view = try shown(controller, Toast(text: "Archived 3 tabs", kind: .undo, actionTitle: "Undo"))
    XCTAssertEqual(view.frame.height, 36)
    XCTAssertFalse(view.glyphView.isHidden)
    XCTAssertEqual(view.glyphView.frame, NSRect(x: 12, y: 10, width: 16, height: 16))
    XCTAssertEqual(view.actionButton.frame.height, 24)
    XCTAssertEqual(view.actionButton.frame.maxX, view.bounds.width - 6, accuracy: 0.5)
    XCTAssertEqual(view.actionButton.displayedTitleText, "Undo")
    XCTAssertTrue(view.dismissButton.isHidden)
    XCTAssertEqual(view.layer?.cornerRadius, 18)
    XCTAssertTrue(view.showsWholeText)
    XCTAssertGreaterThanOrEqual(view.label.frame.minX, view.glyphView.frame.maxX + 6)
    XCTAssertLessThanOrEqual(view.label.frame.maxX, view.actionButton.frame.minX)
    controller.close()
  }

  /// No glyph: the text starts at the leading padding.
  func testANoticeWithoutAGlyphStartsAtThePadding() throws {
    let controller = makeController()
    let view = try shown(controller, Toast(text: "New Tab Created"))
    XCTAssertTrue(view.glyphView.isHidden)
    XCTAssertEqual(view.label.frame.minX + 2, 12, accuracy: 0.5)
    XCTAssertTrue(view.actionButton.isHidden)
    controller.close()
  }

  /// None of the four recovery texts truncates: they wrap to at most three lines in a 300 pt column, at most 480 pt
  /// wide, with Show Files and the dismiss button top-aligned.
  func testNoRecoveryNoticeTruncates() throws {
    let notices: [RecoveryNotice] = [.restoredFromBackup(liveFileWasDamaged: true),
                                     .restoredFromBackup(liveFileWasDamaged: false),
                                     .recreatedEmpty(liveFileWasDamaged: true),
                                     .recreatedEmpty(liveFileWasDamaged: false)]
    for notice in notices {
      let controller = makeController()
      let view = try shown(controller, notice.toast)
      XCTAssertTrue(view.showsWholeText, "truncated: \(notice)")
      XCTAssertLessThanOrEqual(view.frame.width, ToastView.maxWidth)
      XCTAssertLessThanOrEqual(view.label.frame.width, ToastView.textColumnWidth + 2)
      XCTAssertLessThanOrEqual(view.label.frame.height, ToastView.lineHeight * 3)
      XCTAssertGreaterThan(view.frame.height, ToastView.height, "the long text wraps")
      XCTAssertEqual(view.layer?.cornerRadius, ToastView.multiLineRadius)
      XCTAssertFalse(view.dismissButton.isHidden)
      XCTAssertEqual(view.actionButton.frame.midY, view.dismissButton.frame.midY, accuracy: 0.5)
      XCTAssertLessThan(view.actionButton.frame.midY, view.bounds.midY, "actions sit on the first line")
      XCTAssertEqual(view.frame.minY, ToastView.bottomInset)
      controller.close()
    }
  }

  /// The dismiss button takes a persistent toast down without running its action; it never takes focus.
  func testTheDismissButtonClosesAPersistentToast() throws {
    let controller = makeController()
    var calls = 0
    controller.toasts.show(RecoveryNotice.recreatedEmpty(liveFileWasDamaged: true).toast) { calls += 1 }
    let view = try XCTUnwrap(controller.toasts.view)
    XCTAssertTrue(view.dismissButton.refusesFirstResponder)
    XCTAssertEqual(view.dismissButton.accessibilityIdentifier(), AXID.Toast.dismiss)
    view.dismissButton.performClick(nil)
    XCTAssertNil(controller.toasts.current)
    XCTAssertEqual(calls, 0)
    controller.close()
  }

  /// Decision 2: the surface takes the Space theme's first stop; Reduce Transparency makes it opaque.
  func testTheSurfaceFollowsTheSpaceTheme() throws {
    let blue = SpaceThemeInfo(baseColors: [.srgb(hex: 0x3B82F6)], isDark: false)
    let controller = makeController(theme: blue)
    controller.toasts.view?.reduceTransparency = { false }         // the runner's own setting must not decide
    let view = try shown(controller, Toast(text: "Pinned to Work"))
    XCTAssertEqual(view.theme, blue)
    XCTAssertEqual(view.layer?.backgroundColor, AlertTokens.toastSurface(theme: blue).cgColor)
    view.reduceTransparency = { true }
    view.theme = nil
    view.theme = blue
    XCTAssertEqual(view.layer?.backgroundColor?.alpha, 1)
    XCTAssertEqual(view.layer?.borderWidth, 0.5)
    XCTAssertGreaterThan(view.layer?.shadowRadius ?? 0, 0)
    controller.close()
  }

  /// Timers wait while the pointer is over the toast and while the window is not key.
  func testHoverAndAResignedKeyPauseTheTimer() throws {
    let controller = makeController()
    let view = try shown(controller, Toast(text: "Archived 3 tabs", kind: .undo, actionTitle: "Undo"))
    XCTAssertFalse(controller.toasts.isPaused)
    let window = try XCTUnwrap(controller.window)
    let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, trackingNumber: 0, userData: nil))
    view.mouseEntered(with: enter)
    XCTAssertTrue(controller.toasts.isPaused)
    view.mouseExited(with: enter)
    XCTAssertFalse(controller.toasts.isPaused)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    XCTAssertTrue(controller.toasts.isPaused)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    XCTAssertFalse(controller.toasts.isPaused)
    controller.close()
  }

  /// A new toast replaces the shown one: the old one leaves as a snapshot while the new one enters at its own width.
  func testAReplacedToastLeavesWhileTheNewOneEnters() throws {
    let controller = makeController()
    let view = try shown(controller, Toast(text: "Pinned to Work"))
    view.reduceMotion = { false }
    controller.toasts.show(Toast(text: "Archived 3 tabs", kind: .undo, actionTitle: "Undo"))
    let ghost = try XCTUnwrap(view.leavingSnapshot)
    XCTAssertTrue(ghost.superlayer === view.superview?.layer)
    XCTAssertNotNil(ghost.animation(forKey: ToastView.fadeKey))
    XCTAssertTrue(view.layer?.animation(forKey: ToastView.transformKey) is CASpringAnimation)
    XCTAssertEqual(view.label.stringValue, "Archived 3 tabs")
    controller.close()
  }

  /// VoiceOver: a group labelled with the text; the action and dismiss buttons are its children.
  func testVoiceOverReachesTheDismissButton() throws {
    let controller = makeController()
    let view = try shown(controller, RecoveryNotice.restoredFromBackup(liveFileWasDamaged: false).toast)
    let exposed = NSAccessibility.unignoredChildren(from: view.accessibilityChildren() ?? []).map { $0 as AnyObject }
    XCTAssertTrue(exposed.contains { $0 === view.dismissButton || $0 === view.dismissButton.cell })
    XCTAssertTrue(exposed.contains { $0 === view.actionButton || $0 === view.actionButton.cell })
    XCTAssertFalse(exposed.contains { $0 === view.glyphView || $0 === view.glyphView.cell })
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
  func addTab(url: URL, title: String, in location: SidebarLocation, at index: Int?) throws -> NodeID {
    base.addTab(url: url, title: title, in: location, at: index)
  }
  func addSpace(title: String) throws -> SpaceID { throw CocoaError(.featureUnsupported) }
  func addSpace(title: String, after space: SpaceID?) throws -> SpaceID { throw CocoaError(.featureUnsupported) }
  func renameSpace(_ id: SpaceID, to title: String) { base.renameSpace(id, to: title) }
  func moveSpace(_ id: SpaceID, to index: Int) { base.moveSpace(id, to: index) }
  func setIcon(_ id: SpaceID, to icon: SpaceIconInfo?) { base.setIcon(id, to: icon) }
  func setTheme(_ id: SpaceID, to theme: SpaceThemeInfo?) { base.setTheme(id, to: theme) }
  func updateTab(_ id: NodeID, url: URL?, title: String?) { base.updateTab(id, url: url, title: title) }
  func renameNode(_ id: NodeID, to title: String?) { base.renameNode(id, to: title) }
  func duplicateNode(_ id: NodeID) throws -> NodeID { try base.duplicateNode(id) }
  func addFolder(title: String, in location: SidebarLocation, at index: Int?) throws -> NodeID {
    base.addFolder(title: title, in: location, at: index)
  }
  func moveNode(_ id: NodeID, to location: SidebarLocation, at index: Int) throws {
    base.moveNode(id, to: location, at: index)
  }
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
