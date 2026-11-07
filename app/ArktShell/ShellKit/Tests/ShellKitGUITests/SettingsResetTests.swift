import AppKit
import XCTest
@testable import ShellUI

/// Settings > Advanced > Reset all settings (#617; docs/design/settings.md, section 3): the red Reset... link opens the
/// shared dialog sheet on the Settings window. Cancel and Escape change nothing; Reset Settings returns every
/// preference to its default, and the shown controls follow. Spaces, tabs and the Archive are not settings and are
/// not asked about. No waits: every step is a synchronous call on the main actor.
@MainActor
final class SettingsResetTests: XCTestCase {
  private var controllers: [SettingsWindowController] = []
  private var suiteName = ""
  private var defaults = UserDefaults.standard

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "dev.arkt.tests.settingsReset.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() async throws {
    for controller in controllers {
      controller.resetSheet?.dismiss()
      controller.window?.close()
    }
    controllers = []
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  /// The archive rows' values and every reset the window asks for.
  private final class ArchiveRows {
    var tabs = "7 days"
    var littleArkt = "Never"
    var resets = 0

    @MainActor var rows: SettingsArchiveRows {
      SettingsArchiveRows(
        tabsAfter: { self.tabs }, setTabsAfter: { self.tabs = $0 },
        littleArktAfter: { self.littleArkt }, setLittleArktAfter: { self.littleArkt = $0 },
        reset: {
          self.resets += 1
          self.tabs = "12 hours"
          self.littleArkt = "6 hours"
        })
    }
  }

  private func make(settings: AppSettings, archive: ArchiveRows? = nil) -> SettingsWindowController {
    var env = SettingsServices()
    env.archiveRows = archive?.rows
    let controller = SettingsWindowController(settings: settings, services: env)
    controllers.append(controller)
    return controller
  }

  private func find<T: NSView>(_ identifier: String, in controller: SettingsWindowController,
                               as type: T.Type = NSView.self) throws -> T {
    let root = try XCTUnwrap(controller.window?.contentView)
    let found = try XCTUnwrap(Self.view(identifier, in: root), "no view \(identifier)")
    return try XCTUnwrap(found as? T, "\(identifier) is \(Swift.type(of: found))")
  }

  private static func view(_ identifier: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == identifier { return root }
    for child in root.subviews {
      if let hit = view(identifier, in: child) { return hit }
    }
    return nil
  }

  /// Every preference away from its default.
  private func changeEveryPreference(_ settings: AppSettings) {
    settings.tabNavigation.countsFavorites = false
    settings.tabNavigation.ninthOpensNinth = true
    settings.peekLinks.opensCrossSiteLinks = false
    settings.peekLinks.opensShiftClickedLinks = false
    settings.opensLittleArktOnOptionCommandClick = false
    settings.warnsBeforeQuitting = true
    settings.sendsCrashReports = true
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: true)
    settings.toolbar.isVisible = true
    settings.toolbar.showsFullURL = false
  }

  /// Opens the sheet with the Advanced pane's Reset... link.
  @discardableResult
  private func openSheet(_ controller: SettingsWindowController) throws -> DialogSheet {
    controller.show(pane: .advanced)
    let link = try find(AXID.Settings.control("advanced", "resetAll"), in: controller, as: ArchiveLinkButton.self)
    XCTAssertTrue(link.isEnabled)
    link.performClick(nil)
    return try XCTUnwrap(controller.resetSheet, "Reset... opens the sheet")
  }

  // MARK: The row and the sheet

  func testTheRowIsBuiltAndQuiet() throws {
    let controller = make(settings: AppSettings(defaults: defaults))
    controller.show(pane: .advanced)
    let link = try find(AXID.Settings.control("advanced", "resetAll"), in: controller, as: ArchiveLinkButton.self)
    XCTAssertEqual(link.style, .destructive, "destructive is a quiet red link")
    XCTAssertEqual(link.title, "Reset...")
    let row = try XCTUnwrap(link.enclosingSettingsRow)
    XCTAssertFalse(row.isPlanned)
    XCTAssertEqual(row.captionText, "Your Spaces, tabs and the Archive stay as they are.")
    XCTAssertEqual(controller.primaryActionCount(in: .advanced), 0)
  }

  /// The shared dialog sheet (alerts design 3.1 to 3.3): hung from the Settings window, a quiet red Reset Settings
  /// and Cancel, focus on Cancel, no Return key on the destructive answer.
  func testResetOpensTheSharedSheetOnTheSettingsWindow() throws {
    let controller = make(settings: AppSettings(defaults: defaults))
    let sheet = try openSheet(controller)
    let window = try XCTUnwrap(sheet.window)
    XCTAssertTrue(controller.window?.attachedSheet === window, "a sheet on the Settings window")
    XCTAssertEqual(window.accessibilitySubrole(), .dialog)
    let view = sheet.view
    XCTAssertEqual(view.titleField.stringValue, "Reset all settings?")
    XCTAssertEqual(view.paragraphFields.map(\.stringValue), [
      "Every setting returns to its default. Your Spaces, tabs and archived items stay as they are.",
    ])
    XCTAssertEqual(view.primaryButton.title, "Reset Settings")
    XCTAssertEqual(view.primaryButton.accessibilityHelp(), "Returns every setting to its default")
    XCTAssertEqual(view.primaryButton.style, .destructive)
    XCTAssertEqual(view.cancelButton?.title, "Cancel")
    XCTAssertEqual(sheet.content.defaultButton, DialogContent.DefaultButton.none)
    XCTAssertTrue(view.initialFocus === view.cancelButton, "focus starts on Cancel")
    XCTAssertTrue(window.firstResponder === view.cancelButton)
    XCTAssertEqual(view.primaryButton.keyEquivalent, "", "a stray Return never resets")
  }

  /// A second click while the sheet is up does not stack another one.
  func testASecondClickKeepsTheOneSheet() throws {
    let controller = make(settings: AppSettings(defaults: defaults))
    let sheet = try openSheet(controller)
    let link = try find(AXID.Settings.control("advanced", "resetAll"), in: controller, as: ArchiveLinkButton.self)
    link.performClick(nil)
    XCTAssertTrue(controller.resetSheet === sheet)
  }

  // MARK: Answers

  func testCancelAndEscapeChangeNothing() throws {
    let settings = AppSettings(defaults: defaults)
    changeEveryPreference(settings)
    let archive = ArchiveRows()
    let controller = make(settings: settings, archive: archive)

    try XCTUnwrap(openSheet(controller).view.cancelButton).performClick(nil)
    XCTAssertNil(controller.resetSheet)
    XCTAssertNil(controller.window?.attachedSheet)

    let sheet = try openSheet(controller)
    try XCTUnwrap(sheet.window).cancelOperation(nil)              // Escape
    XCTAssertNil(controller.resetSheet)
    XCTAssertNil(controller.window?.attachedSheet)
    XCTAssertTrue(controller.window?.isVisible == true, "Escape answers the sheet, not the window")

    XCTAssertTrue(settings.warnsBeforeQuitting)
    XCTAssertTrue(settings.toolbar.isVisible)
    XCTAssertFalse(settings.peekLinks.opensCrossSiteLinks)
    XCTAssertEqual(archive.resets, 0)
    XCTAssertEqual(archive.tabs, "7 days")
  }

  /// Reset Settings: every preference is back at its default, the archive rows are reset through the app, and the
  /// switches and pop-ups already built show the new values.
  func testResetSettingsReturnsEveryPreferenceAndTheControlsFollow() throws {
    let settings = AppSettings(defaults: defaults)
    changeEveryPreference(settings)
    settings.crashReportAskAnswered = true
    let archive = ArchiveRows()
    let controller = make(settings: settings, archive: archive)
    controller.show(pane: .general)
    let warn = try find(AXID.Settings.control("general", "warnBeforeQuitting"), in: controller,
                        as: SettingsSwitch.self)
    XCTAssertTrue(warn.isOn)
    controller.show(pane: .spaces)
    let today = try find(AXID.Settings.control("spaces", "archiveTodayAfter"), in: controller,
                         as: SettingsPopUpButton.self)
    let little = try find(AXID.Settings.control("spaces", "archiveLittleArktAfter"), in: controller,
                          as: SettingsPopUpButton.self)
    XCTAssertEqual(today.selectedTitle, "7 days")
    controller.show(pane: .appearance)
    XCTAssertTrue(controller.toolbarSwitch?.isOn == true)

    let sheet = try openSheet(controller)
    sheet.view.primaryButton.performClick(nil)

    XCTAssertNil(controller.resetSheet)
    XCTAssertNil(controller.window?.attachedSheet)
    XCTAssertEqual(settings.tabNavigation, TabNavigationSettings())
    XCTAssertEqual(settings.peekLinks, PeekLinkSettings())
    XCTAssertTrue(settings.opensLittleArktOnOptionCommandClick)
    XCTAssertFalse(settings.warnsBeforeQuitting)
    XCTAssertFalse(settings.sendsCrashReports)
    XCTAssertEqual(settings.downloadLocation, DownloadLocationSetting())
    XCTAssertFalse(settings.toolbar.isVisible)
    XCTAssertTrue(settings.toolbar.showsFullURL)
    XCTAssertTrue(settings.crashReportAskAnswered, "the one-time ask is not a setting")
    XCTAssertEqual(settings.lastPane, .advanced, "window state stays")
    XCTAssertEqual(archive.resets, 1)

    XCTAssertFalse(warn.isOn)
    XCTAssertEqual(today.selectedTitle, "12 hours")
    XCTAssertEqual(little.selectedTitle, "6 hours")
    XCTAssertTrue(controller.toolbarSwitch?.isOn == false)
    XCTAssertTrue(controller.fullURLSwitch?.isOn == true)
    XCTAssertTrue(controller.peekCrossSiteSwitch?.isOn == true)
    XCTAssertTrue(controller.countFavoritesSwitch?.isOn == true)
    XCTAssertEqual(controller.selectedPane, .advanced, "the window stays where it was")
  }

  /// Without the archive rows (the app gave none), the reset still covers the store.
  func testResetWithoutArchiveRows() throws {
    let settings = AppSettings(defaults: defaults)
    changeEveryPreference(settings)
    let controller = make(settings: settings)
    try openSheet(controller).view.primaryButton.performClick(nil)
    XCTAssertFalse(settings.warnsBeforeQuitting)
    XCTAssertFalse(settings.toolbar.isVisible)
  }
}
