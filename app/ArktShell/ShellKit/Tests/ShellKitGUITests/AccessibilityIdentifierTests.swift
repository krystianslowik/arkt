import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The UI test suite drives the shell only through accessibility identifiers (`AXID`). These tests walk the window's
/// accessibility tree the way an accessibility client sees it (unignored children only) and check each identifier
/// with its role, label and value or enabled state. Group U4a: window, content card, empty state, Toolbar, toasts.
@MainActor
final class AccessibilityIdentifierTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeController(_ sidebar: StubSidebar = .sample()) -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar, toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  // MARK: Tree walking

  /// Every unignored accessibility element below `root`, depth first.
  private func descendants(of root: Any) -> [Any] {
    guard let element = root as? NSAccessibilityProtocol else { return [] }
    let children = NSAccessibility.unignoredChildren(from: element.accessibilityChildren() ?? [])
    return children.flatMap { [$0] + descendants(of: $0) }
  }

  /// The identifier an accessibility client reads from the element itself. For a control that element is its cell,
  /// so the identifier must be set on the cell too (`setAccessibilityIdentifierWithCell`).
  private func identifier(of element: Any) -> String? {
    guard let id = (element as? NSAccessibilityProtocol)?.accessibilityIdentifier(), !id.isEmpty else { return nil }
    return id
  }

  /// The label set on a control is kept on the control, not on the cell the tree lists.
  private func label(of element: NSAccessibilityProtocol) -> String? {
    if let control = (element as? NSCell)?.controlView { return control.accessibilityLabel() }
    return element.accessibilityLabel()
  }

  private func elements(_ id: String, in controller: ShellWindowController) throws -> [NSAccessibilityProtocol] {
    let window = try XCTUnwrap(controller.window)
    return descendants(of: window).filter { identifier(of: $0) == id }.compactMap { $0 as? NSAccessibilityProtocol }
  }

  private func element(_ id: String, in controller: ShellWindowController,
                       file: StaticString = #filePath, line: UInt = #line) throws -> NSAccessibilityProtocol {
    let found = try elements(id, in: controller)
    XCTAssertEqual(found.count, 1, "exactly one element with identifier \(id)", file: file, line: line)
    return try XCTUnwrap(found.first, "no element with identifier \(id)", file: file, line: line)
  }

  // MARK: Window and content card

  func testWindowAndContentCardHaveIdentifiers() throws {
    let controller = makeController()
    let window = try XCTUnwrap(controller.window)
    XCTAssertEqual(window.accessibilityIdentifier(), AXID.Shell.window)
    XCTAssertEqual(window.accessibilityRole(), .window)
    let card = try element(AXID.Content.card, in: controller)
    XCTAssertEqual(card.accessibilityRole(), .group)
    XCTAssertTrue(card as AnyObject === controller.rootView.card)
    controller.close()
  }

  // MARK: Empty state

  func testEmptyStateHasIdentifiersAndImportIsAbsentWhileHidden() throws {
    let controller = makeController(StubSidebar())
    let group = try element(AXID.EmptyState.root, in: controller)
    XCTAssertEqual(group.accessibilityRole(), .group)
    XCTAssertTrue(group as AnyObject === controller.emptyState)
    let newSpace = try element(AXID.EmptyState.newSpace, in: controller)
    XCTAssertEqual(newSpace.accessibilityRole(), .button)
    XCTAssertEqual(newSpace.accessibilityTitle(), "New Space")
    XCTAssertEqual(try elements(AXID.EmptyState.importFromArc, in: controller).count, 0,
                   "Import from Arc is absent from the tree while hidden")

    controller.isArcImportAvailable = true
    controller.rootView.layoutSubtreeIfNeeded()
    let importButton = try element(AXID.EmptyState.importFromArc, in: controller)
    XCTAssertEqual(importButton.accessibilityRole(), .button)
    XCTAssertEqual(importButton.accessibilityTitle(), "Import from Arc")
    controller.close()
  }

  func testEmptyStateIsAbsentWhenASpaceExists() throws {
    let controller = makeController()
    XCTAssertEqual(try elements(AXID.EmptyState.root, in: controller).count, 0)
    controller.close()
  }

  // MARK: Toolbar

  func testToolbarIsAbsentWhileHidden() throws {
    let controller = makeController()
    XCTAssertFalse(controller.isToolbarVisible)
    for id in [AXID.Toolbar.root, AXID.Toolbar.back, AXID.Toolbar.forward, AXID.Toolbar.reload, AXID.Toolbar.urlBar] {
      XCTAssertEqual(try elements(id, in: controller).count, 0, "\(id) is absent while the Toolbar is hidden")
    }
    controller.close()
  }

  func testToolbarButtonsAndURLBarHaveIdentifiersLabelsAndState() throws {
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample(), toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.toggleToolbar(nil)
    controller.rootView.layoutSubtreeIfNeeded()

    let toolbar = try element(AXID.Toolbar.root, in: controller)
    XCTAssertEqual(toolbar.accessibilityRole(), .toolbar)
    XCTAssertEqual(toolbar.accessibilityLabel(), "Toolbar")
    let back = try element(AXID.Toolbar.back, in: controller)
    let forward = try element(AXID.Toolbar.forward, in: controller)
    let reload = try element(AXID.Toolbar.reload, in: controller)
    for (button, label) in [(back, "Back"), (forward, "Forward"), (reload, "Reload")] {
      XCTAssertEqual(button.accessibilityRole(), .button, label)
      XCTAssertEqual(self.label(of: button), label)
    }
    XCTAssertFalse(back.isAccessibilityEnabled(), "no history yet")
    XCTAssertFalse(forward.isAccessibilityEnabled(), "no history yet")
    XCTAssertTrue(reload.isAccessibilityEnabled())

    let tab = try XCTUnwrap(controller.currentTab)
    let next = try XCTUnwrap(URL(string: "https://second.example/page"))
    engine.navigate(tab, to: next)
    XCTAssertTrue(back.isAccessibilityEnabled(), "Back follows setHistory")
    XCTAssertFalse(forward.isAccessibilityEnabled())

    let urlBar = try element(AXID.Toolbar.urlBar, in: controller)
    XCTAssertEqual(urlBar.accessibilityRole(), .button)
    XCTAssertEqual(urlBar.accessibilityValue() as? String, controller.rootView.card.toolbar.urlBar.displayedText)
    XCTAssertTrue((urlBar.accessibilityValue() as? String)?.contains("second.example/page") == true, "the full address")
    controller.close()
  }

  // MARK: Toasts

  func testToastIsAbsentWhileIdle() throws {
    let controller = makeController()
    XCTAssertEqual(try elements(AXID.Toast.root, in: controller).count, 0)
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0)
    controller.close()
  }

  func testTimedToastHasIdentifierLabelAndValueAndNoActionWithoutTitle() throws {
    let controller = makeController()
    controller.toasts.show(Toast(text: "Saved"))
    controller.rootView.layoutSubtreeIfNeeded()
    let toast = try element(AXID.Toast.root, in: controller)
    XCTAssertEqual(toast.accessibilityRole(), .group)
    XCTAssertEqual(toast.accessibilityLabel(), "Saved")
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.timed)
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0, "no action button without a title")
    controller.close()
  }

  func testPersistentToastWithActionHasActionButton() throws {
    let controller = makeController()
    controller.toasts.show(Toast(text: "Could not save", actionTitle: "Retry", isPersistent: true))
    controller.rootView.layoutSubtreeIfNeeded()
    let toast = try element(AXID.Toast.root, in: controller)
    XCTAssertEqual(toast.accessibilityLabel(), "Could not save")
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.persistent)
    let action = try element(AXID.Toast.action, in: controller)
    XCTAssertEqual(action.accessibilityRole(), .button)
    XCTAssertEqual(action.accessibilityTitle(), "Retry")

    controller.toasts.show(Toast(text: "Opened"))
    XCTAssertEqual(toast.accessibilityValue() as? String, AXID.Toast.timed, "a timed toast over it updates the value")
    XCTAssertEqual(try elements(AXID.Toast.action, in: controller).count, 0)
    controller.close()
  }
}
