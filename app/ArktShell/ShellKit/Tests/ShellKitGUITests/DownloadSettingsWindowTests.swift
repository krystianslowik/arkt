import AppKit
import XCTest
@testable import ShellUI

/// Settings > General > Downloads (#132, BH-182): the mode, the folder pop-up and Choose..., the Library row, and the
/// dimmed folder while the panel asks.
@MainActor
final class DownloadSettingsWindowTests: XCTestCase {
  private var controller: SettingsWindowController!
  private var settings: AppSettings!
  private var opened = 0
  private let downloads = URL(filePath: "/Users/test/Downloads", directoryHint: .isDirectory)

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    settings = AppSettings.ephemeral()
    var services = SettingsServices()
    services.downloadsFolder = downloads
    services.openLibrary = { [weak self] in self?.opened += 1 }
    controller = SettingsWindowController(settings: settings, services: services)
    controller.show(pane: .general)
  }

  override func tearDown() async throws {
    controller.window?.close()
    controller = nil
  }

  func testTheDownloadsSectionIsInGeneralAndAdvancedHasNoneAnyMore() throws {
    let mode = try XCTUnwrap(controller.downloadModeControl)
    XCTAssertEqual(mode.segments, ["Ask Where to Save", "Save to Folder"])
    XCTAssertEqual(mode.selectedIndex, 1, "save to a folder by default")
    XCTAssertEqual(mode.accessibilityIdentifier(), AXID.Downloads.locationMode)
    XCTAssertEqual(controller.downloadModeRow?.captionText, "Files save straight to the folder below. No panel.")
    XCTAssertEqual(controller.downloadFolderRow?.captionText, "/Users/test/Downloads")
    controller.show(pane: .advanced)
    let advanced = try XCTUnwrap(controller.window?.contentView)
    XCTAssertNil(Self.label("Save downloads to", in: advanced))
    XCTAssertNil(Self.label("Ask where to save each file", in: advanced))
  }

  func testChoosingAskChangesTheSettingAndDimsTheFolder() throws {
    let mode = try XCTUnwrap(controller.downloadModeControl)
    mode.onChange?(0)
    XCTAssertTrue(settings.downloadLocation.asksWhereToSave)
    XCTAssertEqual(mode.selectedIndex, 0)
    XCTAssertEqual(controller.downloadModeRow?.captionText, "A save panel asks where to put each file.")
    XCTAssertEqual(controller.downloadFolderRow?.isDimmed, true)
    mode.onChange?(1)
    XCTAssertEqual(controller.downloadFolderRow?.isDimmed, false)
  }

  func testTheSettingChangedElsewhereMovesTheControls() throws {
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: true, folder: nil)
    XCTAssertEqual(controller.downloadModeControl?.selectedIndex, 0)
    XCTAssertEqual(controller.downloadFolderRow?.isDimmed, true)
  }

  func testTheFolderPopUpOffersDownloadsDesktopTheChosenFolderAndOther() throws {
    var (items, selected) = controller.downloadFolderItems()
    XCTAssertEqual(items, ["Downloads", "Desktop", "Other..."])
    XCTAssertEqual(selected, "Downloads")
    settings.downloadLocation.folder = URL(filePath: "/Users/test/Projects/Field Data", directoryHint: .isDirectory)
    (items, selected) = controller.downloadFolderItems()
    XCTAssertEqual(items, ["Downloads", "Desktop", "Field Data", "Other..."])
    XCTAssertEqual(selected, "Field Data")
    XCTAssertEqual(controller.downloadFolderRow?.captionText, "/Users/test/Projects/Field Data")
  }

  func testChooseAndOtherUseThePanelAndCancelChangesNothing() throws {
    var shown = 0
    var answer: URL? = URL(filePath: "/Users/test/Picked", directoryHint: .isDirectory)
    controller.downloadFolderPicker = { _, done in shown += 1; done(answer) }
    controller.pickDownloadFolder()
    XCTAssertEqual(shown, 1)
    XCTAssertEqual(settings.downloadLocation.folder?.lastPathComponent, "Picked")
    answer = nil
    controller.chooseDownloadFolder(titled: "Other...")
    XCTAssertEqual(shown, 2)
    XCTAssertEqual(settings.downloadLocation.folder?.lastPathComponent, "Picked", "cancelled: unchanged")
    controller.chooseDownloadFolder(titled: "Downloads")
    XCTAssertNil(settings.downloadLocation.folder)
  }

  func testTheLibraryRowOpensTheLibrary() throws {
    let root = try XCTUnwrap(controller.window?.contentView)
    let pill = try XCTUnwrap(Self.control(AXID.Downloads.openLibrary, in: root) as? NSButton)
    pill.performClick(nil)
    XCTAssertEqual(opened, 1)
  }

  // MARK: Helpers

  private static func label(_ text: String, in view: NSView) -> NSView? {
    if let field = view as? NSTextField, field.stringValue == text { return field }
    for subview in view.subviews { if let found = label(text, in: subview) { return found } }
    return nil
  }

  private static func control(_ identifier: String, in view: NSView) -> NSView? {
    if view.accessibilityIdentifier() == identifier { return view }
    if let control = view as? NSControl, control.cell?.accessibilityIdentifier() == identifier { return view }
    for subview in view.subviews { if let found = control(identifier, in: subview) { return found } }
    return nil
  }
}
