import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// The page info panel's "Turned off in macOS" state (#786) in the shell window, on InMemoryEngine's page info. The
/// macOS location state comes from the panel's seam, never from the system: no test reads or asks for real access.
@MainActor
final class PageInfoSystemPermissionTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var denied: Set<SitePermissionKind> = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample(), toolbarSetting: .ephemeral())
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.pageInfo.reduceMotion = { true }
    controller.pageInfo.increaseContrast = { false }
    controller.pageInfo.deniedInMacOS = { [weak self] in self?.denied ?? [] }
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    controller.pageInfo.hide(keyboard: true)
    controller.close()
    controller = nil
    engine = nil
  }

  private func openPanel(_ address: String = "https://fieldguide.example/trails") throws -> PageInfoPanelView {
    let tab = try XCTUnwrap(controller.currentTab, "the window opens with a tab")
    engine.navigate(tab, to: try XCTUnwrap(URL(string: address)))
    engine.finishLoad(tab, title: "Page")
    controller.urlBar.onPressSiteGlyph?()
    let view = try XCTUnwrap(controller.pageInfo.contentView, "the panel opens")
    view.layoutSubtreeIfNeeded()
    return view
  }

  private func row(_ kind: SitePermissionKind, in view: PageInfoPanelView) throws -> PageInfoPermissionRow {
    try XCTUnwrap(view.rows.first { $0.kind == kind })
  }

  func testDeniedLocationShowsTheNoteUnderItsTitleAndKeepsThePopUp() throws {
    denied = [.location]
    let view = try openPanel()
    let location = try row(.location, in: view)
    XCTAssertFalse(location.note.isHidden)
    XCTAssertEqual(location.note.stringValue, "Turned off in macOS")
    XCTAssertEqual(location.frame.height, PageInfoMetrics.notedRowHeight)
    XCTAssertGreaterThanOrEqual(location.note.frame.minY, location.title.frame.maxY, "the note sits under the title")
    XCTAssertLessThanOrEqual(location.note.frame.maxY, location.bounds.height, "nothing clips at the bottom")
    XCTAssertLessThanOrEqual(location.note.frame.maxX, location.popUp.frame.minX, "the note stops before the pop-up")
    XCTAssertTrue(location.popUp.isEnabled, "the stored setting can still be changed")
    XCTAssertEqual(location.popUp.accessibilityLabel(), "Location, turned off in macOS")
    let camera = try row(.camera, in: view)
    XCTAssertTrue(camera.note.isHidden)
    XCTAssertEqual(camera.frame.height, PageInfoMetrics.rowHeight)
    XCTAssertEqual(camera.frame.minY, location.frame.maxY, "the next row follows the taller one")
    XCTAssertEqual(view.preferredHeight(width: view.bounds.width),
                   try XCTUnwrap(view.model).contentHeight, "view and model agree on height")
  }

  func testUndecidedLocationShowsNoNote() throws {
    let view = try openPanel()
    let location = try row(.location, in: view)
    XCTAssertTrue(location.note.isHidden, "macOS still asks on first use")
    XCTAssertEqual(location.frame.height, PageInfoMetrics.rowHeight)
    XCTAssertEqual(location.popUp.accessibilityLabel(), "Location")
  }

  /// The macOS state is read again when the panel follows a change: denied, then decided otherwise, drops the note.
  func testTheNoteFollowsTheStateOnReread() throws {
    denied = [.location]
    let view = try openPanel()
    XCTAssertFalse(try row(.location, in: view).note.isHidden)
    denied = []
    controller.pageInfo.pageDidChange(currentTab: controller.currentTab)
    view.layoutSubtreeIfNeeded()
    XCTAssertTrue(try row(.location, in: view).note.isHidden)
    XCTAssertEqual(try row(.location, in: view).frame.height, PageInfoMetrics.rowHeight)
  }

  /// The narrowest panel: title, note and pop-up do not overlap.
  func testNarrowPanelKeepsTitleNoteAndPopUpApart() throws {
    denied = [.location]
    let view = try openPanel()
    view.frame.size.width = PageInfoMetrics.minWidth
    view.layoutSubtreeIfNeeded()
    let location = try row(.location, in: view)
    XCTAssertLessThanOrEqual(location.title.frame.maxX, location.popUp.frame.minX)
    XCTAssertLessThanOrEqual(location.note.frame.maxX, location.popUp.frame.minX)
    XCTAssertGreaterThan(location.note.frame.width, 0)
  }

  /// A very long engine title at the narrowest width: title and note truncate before the pop-up.
  func testLongTitleTruncatesBeforeThePopUp() {
    let title = String(repeating: "Precise location for this site ", count: 4)
    let permission = SitePermission(kind: .location, title: title, setting: .allow, isDefault: false)
    let row = PageInfoPermissionRow(PageInfoModel.Row(permission, deniedInMacOS: true))
    row.frame = NSRect(x: 0, y: 0, width: PageInfoMetrics.minWidth, height: row.height)
    row.layoutSubtreeIfNeeded()
    XCTAssertEqual(row.height, PageInfoMetrics.notedRowHeight)
    XCTAssertGreaterThan(row.title.frame.width, 0)
    XCTAssertLessThanOrEqual(row.title.frame.maxX, row.popUp.frame.minX)
    XCTAssertLessThanOrEqual(row.note.frame.maxX, row.popUp.frame.minX)
    XCTAssertLessThan(row.title.frame.width, row.title.attributedStringValue.size().width, "the title truncates")
    XCTAssertEqual(row.title.lineBreakMode, .byTruncatingTail)
    XCTAssertEqual(row.note.lineBreakMode, .byTruncatingTail)
  }
}
