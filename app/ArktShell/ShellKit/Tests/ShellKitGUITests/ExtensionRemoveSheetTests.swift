import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The extension remove sheet (#720, design/alerts-sheets-toasts `ext-remove`): the Extensions panel's Remove from
/// Arkt... opens it on the panel's window; Remove uninstalls through `EngineExtensions.uninstallExtension` with the
/// Report abuse state; Cancel and Escape do nothing; an extension that goes away closes it. No waits: every step is a
/// synchronous call on the main actor.
@MainActor
final class ExtensionRemoveSheetTests: XCTestCase {
  private var harness: EngineHarnessWindow!
  private var engine: InMemoryEngine { harness.engine }
  private var window: EngineWindowID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    harness = EngineHarnessWindow(try EngineWorld.make().sidebar)
    harness.controller.showWindow(nil)
    window = try XCTUnwrap(harness.controller.engineWindow)
    panel.reduceMotion = { true }
  }

  override func tearDown() async throws {
    panel.closeRemoveSheet()
    panel.hide(keyboard: true)
    harness.controller.window?.orderOut(nil)
    harness = nil
  }

  private var panel: ExtensionsPanelController { harness.controller.extensionsPanel! }
  private var button: ExtensionsButton { harness.controller.extensionsButton! }

  private func action(_ id: String, name: String) -> ExtensionAction {
    ExtensionAction(id: id, name: name)
  }

  private func open(_ actions: [ExtensionAction]) {
    engine.setExtensionActions(actions, in: window)
    button.performClick(nil)
    XCTAssertTrue(panel.isShown)
  }

  /// The row's context menu and its item Remove from Arkt....
  private func removeItem(_ id: String) throws -> (menu: NSMenu, item: NSMenuItem) {
    let row = try XCTUnwrap(panel.contentView?.row(for: id))
    let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                      clickCount: 1, pressure: 1))
    let menu = try XCTUnwrap(row.menu(for: rightClick))
    return (menu, try XCTUnwrap(menu.items.first { $0.tag == ExtensionContextCommand.remove.rawValue }))
  }

  /// Opens the sheet for `id` through the panel's context menu.
  @discardableResult
  private func openSheet(_ id: String) throws -> ExtensionRemoveSheet {
    let (menu, item) = try removeItem(id)
    XCTAssertTrue(item.isEnabled, "Remove from Arkt... is enabled")
    menu.performActionForItem(at: menu.index(of: item))
    return try XCTUnwrap(panel.removeSheet)
  }

  // MARK: Opening and the content

  func testRemoveFromArktOpensTheSheetOnThePanelsWindow() throws {
    open([action("a", name: "JSON Formatter"), action("b", name: "B")])
    let sheet = try openSheet("a")
    XCTAssertFalse(panel.isShown, "the panel closes for the sheet")
    XCTAssertEqual(sheet.extensionID, "a")
    XCTAssertTrue(sheet.window?.sheetParent === harness.controller.window, "a sheet on the panel's window")
    let view = sheet.sheet.view
    XCTAssertEqual(view.titleField.stringValue, "Remove \u{201C}JSON Formatter\u{201D}?")
    XCTAssertNotNil(view.iconView, "the extension's icon tile")
    let checkbox = try XCTUnwrap(view.checkboxButton)
    XCTAssertEqual(checkbox.title, "Report abuse")
    XCTAssertEqual(checkbox.state, .off)
    XCTAssertEqual(view.primaryButton.title, "Remove")
    XCTAssertEqual(view.primaryButton.style, .destructive)
    XCTAssertEqual(view.cancelButton?.title, "Cancel")
    for button in [view.primaryButton, view.cancelButton].compactMap({ $0 }) {
      XCTAssertEqual(button.keyEquivalent, "", "Return removes nothing")
    }
    XCTAssertTrue(view.initialFocus === view.cancelButton, "focus starts on Cancel")
    XCTAssertTrue(engine.uninstalledExtensions.isEmpty, "opening asks; it removes nothing")
  }

  func testASecondRequestWhileTheSheetIsUpOpensNothing() throws {
    open([action("a", name: "A"), action("b", name: "B")])
    let first = try openSheet("a")
    panel.onRemove?(action("b", name: "B"))
    XCTAssertTrue(panel.removeSheet === first)
  }

  // MARK: Answers

  func testRemoveUninstallsOnceWithReportAbuseOffAndTheRowLeaves() throws {
    open([action("a", name: "A"), action("b", name: "B")])
    let sheet = try openSheet("a")
    sheet.sheet.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.uninstalledExtensions, [.init(extensionID: "a", reportAbuse: false)])
    XCTAssertNil(panel.removeSheet)
    button.performClick(nil)
    XCTAssertEqual(panel.contentView?.displayedRowIDs, ["b"], "the row left the panel")
  }

  func testRemoveCarriesTheCheckedReportAbuse() throws {
    open([action("a", name: "A")])
    let sheet = try openSheet("a")
    try XCTUnwrap(sheet.sheet.view.checkboxButton).performClick(nil)
    sheet.sheet.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.uninstalledExtensions, [.init(extensionID: "a", reportAbuse: true)])
  }

  func testCancelAndEscapeRemoveNothing() throws {
    open([action("a", name: "A")])
    var sheet = try openSheet("a")
    sheet.sheet.view.cancelButton?.performClick(nil)
    XCTAssertNil(panel.removeSheet)

    button.performClick(nil)
    sheet = try openSheet("a")
    try XCTUnwrap(sheet.sheet.view.checkboxButton).performClick(nil)
    sheet.window?.cancelOperation(nil)                     // Escape
    XCTAssertNil(panel.removeSheet)

    XCTAssertTrue(engine.uninstalledExtensions.isEmpty)
    XCTAssertEqual(engine.extensionActions(in: window).map(\.id), ["a"])
  }

  func testAnExtensionThatGoesAwayClosesTheSheetWithoutACall() throws {
    open([action("a", name: "A"), action("b", name: "B")])
    let sheet = try openSheet("a")
    engine.setExtensionActions([action("a", name: "A"), action("c", name: "C")], in: window)
    XCTAssertTrue(panel.removeSheet === sheet, "another change leaves it up")
    engine.setExtensionActions([action("b", name: "B")], in: window)
    XCTAssertNil(panel.removeSheet)
    XCTAssertNil(sheet.window?.sheetParent)
    XCTAssertTrue(engine.uninstalledExtensions.isEmpty)
  }

  // MARK: Worst case, accessibility, motion

  /// An 85-character name wraps to two lines and truncates; longer titles do not move the buttons further.
  func testALongNameWrapsToTwoLinesAndTheButtonsStay() throws {
    let long = String(repeating: "Quiet Reader Pro ", count: 5).prefix(85)
    let longer = String(repeating: "Quiet Reader Pro ", count: 20)
    let views = [String(long), longer].map {
      DialogSheetView(content: ExtensionRemoveSheet.content(for: action("a", name: $0)))
    }
    for view in views { view.frame.size.height = view.layoutContent(width: view.content.width) }
    let title = views[0].titleField
    let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: try XCTUnwrap(title.font)))
    XCTAssertGreaterThan(title.frame.height, lineHeight * 1.5, "two lines")
    XCTAssertLessThan(title.frame.height, lineHeight * 2.5, "never three")
    XCTAssertEqual(views[1].titleField.frame.height, title.frame.height)
    XCTAssertEqual(views[1].primaryButton.frame, views[0].primaryButton.frame)
    XCTAssertEqual(views[1].cancelButton?.frame, views[0].cancelButton?.frame)
    XCTAssertLessThanOrEqual(title.frame.maxX, views[0].content.width - 20)
  }

  /// VoiceOver: the title, then the checkbox, then the answers; Tab cycles the checkbox and the buttons.
  func testAccessibilityOrderIsTitleThenCheckbox() throws {
    let view = DialogSheetView(content: ExtensionRemoveSheet.content(for: action("a", name: "A")))
    let checkbox = try XCTUnwrap(view.checkboxButton)
    let cancel = try XCTUnwrap(view.cancelButton)
    let order = view.subviews
    let titleIndex = try XCTUnwrap(order.firstIndex { $0 === view.titleField })
    let checkboxIndex = try XCTUnwrap(order.firstIndex { $0 === checkbox })
    let cancelIndex = try XCTUnwrap(order.firstIndex { $0 === cancel })
    XCTAssertLessThan(titleIndex, checkboxIndex)
    XCTAssertLessThan(checkboxIndex, cancelIndex)
    XCTAssertEqual(checkbox.accessibilityLabel(), "Report abuse")
    XCTAssertEqual(view.accessibilityLabel(), "Remove \u{201C}A\u{201D}?")
    XCTAssertTrue(checkbox.nextKeyView === cancel)
    XCTAssertTrue(cancel.nextKeyView === view.primaryButton)
    XCTAssertTrue(view.primaryButton.nextKeyView === checkbox)
  }

  /// Reduce Motion: the panel goes at once for the sheet (AppKit draws the sheet's own motion, Reduce Motion
  /// included); without it, the panel fades out while the sheet comes in.
  func testThePanelLeavesAtOnceUnderReduceMotion() throws {
    open([action("a", name: "A")])
    var panelWindow = try XCTUnwrap(panel.panel)
    try openSheet("a")
    XCTAssertFalse(panelWindow.isVisible, "Reduce Motion: no fade")
    panel.closeRemoveSheet()

    panel.reduceMotion = { false }
    button.performClick(nil)
    panelWindow = try XCTUnwrap(panel.panel)
    try openSheet("a")
    XCTAssertFalse(panel.isShown)
    XCTAssertTrue(panelWindow.isVisible, "the fade runs")
  }
}
