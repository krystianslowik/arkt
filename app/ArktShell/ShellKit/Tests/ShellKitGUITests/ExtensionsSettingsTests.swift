import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Settings > Extensions (#600; design/settings `extensions`, `extensions-empty`) in the real Settings window, with
/// InMemoryEngine's installed list: the rows (icon, name, caption, pin, switch), the details with Options...,
/// Keyboard Shortcuts... and Remove... (the remove sheet), developer mode and Load Unpacked..., the empty state, Manage
/// Extension... landing on its row, and the worst cases (40 extensions, long text, policy, a failed uninstall). No
/// waits: every step is a synchronous call on the main actor, and the unpacked load's task is awaited.
@MainActor
final class ExtensionsSettingsTests: XCTestCase {
  private var controllers: [SettingsWindowController] = []
  private var suiteName = ""
  private var defaults = UserDefaults.standard
  private var webStoreOpens = 0
  private var openedURLs: [URL] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "dev.arkt.tests.extensionsSettings.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    webStoreOpens = 0
    openedURLs = []
  }

  override func tearDown() async throws {
    for controller in controllers {
      controller.closeExtensionSheets()
      controller.window?.close()
    }
    controllers = []
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  // MARK: Fixtures

  private static let icon: Data = {
    let image = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
      NSColor.systemBlue.setFill()
      rect.fill()
      return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
    return rep?.representation(using: .png, properties: [:]) ?? Data()
  }()

  /// The design's three extensions, given out of name order.
  private func designList() -> [InstalledExtensionInfo] {
    [
      InstalledExtensionInfo(id: "ublock", name: "uBlock Origin Lite", version: "2025.1",
                             description: "Blocks ads and trackers.", iconPNG: Self.icon,
                             siteAccess: .someSites(count: 3)),
      InstalledExtensionInfo(id: "json", name: "JSON Formatter", version: "0.9", description: "Formats JSON.",
                             isEnabled: false),
      InstalledExtensionInfo(id: "onepassword", name: "1Password", version: "8.11",
                             description: "Fills your passwords.", iconPNG: Self.icon, hasOptionsPage: true,
                             siteAccess: .allSites),
    ]
  }

  private func engine(_ list: [InstalledExtensionInfo]? = nil) -> InMemoryEngine {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions(list ?? designList())
    return engine
  }

  private func make(engine: (any EngineExtensions)?, appearance: NSAppearance.Name? = nil)
    -> SettingsWindowController {
    var services = SettingsServices()
    services.shortcutsMenu = { NSMenu() }
    services.isSystemShortcut = { _ in false }
    services.extensions = engine
    services.openWebStore = { [weak self] in self?.webStoreOpens += 1 }
    services.openInBrowser = { [weak self] url in self?.openedURLs.append(url) }
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    if let appearance { controller.window?.appearance = NSAppearance(named: appearance) }
    controllers.append(controller)
    return controller
  }

  /// The window shown on Extensions.
  private func open(_ engine: (any EngineExtensions)?) -> SettingsWindowController {
    let controller = make(engine: engine)
    controller.show(pane: .extensions)
    return controller
  }

  private func find<T: NSView>(_ identifier: String, in controller: SettingsWindowController,
                               as type: T.Type = NSView.self) throws -> T {
    let root = try XCTUnwrap(controller.window?.contentView)
    let found = try XCTUnwrap(Self.view(identifier, in: root), "no view \(identifier)")
    return try XCTUnwrap(found as? T, "\(identifier) is \(Swift.type(of: found))")
  }

  private func has(_ identifier: String, in controller: SettingsWindowController) -> Bool {
    controller.window?.contentView.flatMap { Self.view(identifier, in: $0) } != nil
  }

  private static func view(_ identifier: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == identifier { return root }
    for child in root.subviews {
      if let hit = view(identifier, in: child) { return hit }
    }
    return nil
  }

  private func id(_ setting: String) -> String { AXID.Settings.control("extensions", setting) }

  private func row(_ extensionID: String, in controller: SettingsWindowController) throws -> SettingsRowView {
    try XCTUnwrap(try find(id("row.\(extensionID)"), in: controller).enclosingSettingsRow)
  }

  private func toggle(_ extensionID: String, in controller: SettingsWindowController) throws -> SettingsSwitch {
    try find(id("enabled.\(extensionID)"), in: controller, as: SettingsSwitch.self)
  }

  private func pin(_ extensionID: String, in controller: SettingsWindowController) throws -> ExtensionsPinToggle {
    try find(id("pin.\(extensionID)"), in: controller, as: ExtensionsPinToggle.self)
  }

  private func clickRow(_ extensionID: String, in controller: SettingsWindowController) throws {
    try find(id("row.\(extensionID)"), in: controller, as: NSButton.self).performClick(nil)
  }

  // MARK: The list

  func testTheListShowsTheDesignsRowsInNameOrder() throws {
    let controller = open(engine())
    XCTAssertEqual(controller.shownExtensionIDs, ["onepassword", "json", "ublock"], "sorted by name")
    let first = try row("onepassword", in: controller)
    XCTAssertEqual(first.labelText, "1Password")
    XCTAssertEqual(first.captionText, "Version 8.11. Can read and change data on all sites.")
    XCTAssertEqual(try row("ublock", in: controller).captionText, "Version 2025.1. Can read and change data on 3 sites.")
    XCTAssertEqual(try row("json", in: controller).captionText, "Version 0.9. Turned off.")
    let texts = controller.visibleTexts()
    XCTAssertTrue(texts.contains("Installed"))
    XCTAssertTrue(texts.contains("Click an extension for its details, options and keyboard shortcuts. "
                                 + "Remove it from its details."))
    XCTAssertTrue(texts.contains("Get more extensions"))
    XCTAssertTrue(texts.contains("Developer mode"))
    XCTAssertFalse(texts.contains("No Extensions Yet"))
    XCTAssertFalse(texts.contains { $0.contains(SettingsRowView.notAvailable) }, "nothing on the pane is planned")
    XCTAssertEqual(controller.primaryActionCount(in: .extensions), 0, "the Web Store pill is neutral with a list")
    let store = try find(id("openWebStore"), in: controller, as: ArchivePillButton.self)
    XCTAssertEqual(store.style, .neutral)
    store.performClick(nil)
    XCTAssertEqual(webStoreOpens, 1)
  }

  /// The design's site-access line; the short description only for an extension without site access (#600 decision).
  func testTheCaptionSaysWhatTheExtensionCanReadAndChange() throws {
    let list = [
      InstalledExtensionInfo(id: "a", name: "A", version: "1", siteAccess: .allSites),
      InstalledExtensionInfo(id: "b", name: "B", version: "2", siteAccess: .someSites(count: 1)),
      InstalledExtensionInfo(id: "c", name: "C", version: "3", siteAccess: .someSites(count: 12)),
      InstalledExtensionInfo(id: "d", name: "D", version: "4", siteAccess: .onClick),
      InstalledExtensionInfo(id: "e", name: "E", version: "5", description: "Formats JSON."),
      InstalledExtensionInfo(id: "f", name: "F", version: "6"),
    ]
    let controller = open(engine(list))
    XCTAssertEqual(try row("a", in: controller).captionText, "Version 1. Can read and change data on all sites.")
    XCTAssertEqual(try row("b", in: controller).captionText, "Version 2. Can read and change data on 1 site.")
    XCTAssertEqual(try row("c", in: controller).captionText, "Version 3. Can read and change data on 12 sites.")
    XCTAssertEqual(try row("d", in: controller).captionText,
                   "Version 4. Can read and change data when you click it.")
    XCTAssertEqual(try row("e", in: controller).captionText, "Version 5. Formats JSON.")
    XCTAssertEqual(try row("f", in: controller).captionText, "Version 6.")
  }

  /// A switch flipped on a row whose list did not change shape updates in place: the same row and switch stay.
  func testASwitchFlipUpdatesTheRowInPlace() throws {
    let engine = engine()
    let controller = open(engine)
    let rowBefore = try row("onepassword", in: controller)
    let control = try toggle("onepassword", in: controller)
    control.performClick(nil)
    XCTAssertTrue(try row("onepassword", in: controller) === rowBefore, "no rebuild for a state change")
    XCTAssertTrue(try toggle("onepassword", in: controller) === control)
    XCTAssertFalse(control.isOn)
    XCTAssertEqual(rowBefore.captionText, "Version 8.11. Turned off.")
    XCTAssertFalse(try pin("onepassword", in: controller).isEnabled)
    engine.installExtension(InstalledExtension(id: "zz", name: "Zebra"))
    XCTAssertFalse(try row("onepassword", in: controller) === rowBefore, "a new extension rebuilds the list")
  }

  func testTheSwitchTurnsAnExtensionOffAndOnThroughTheEngine() throws {
    let engine = engine()
    let controller = open(engine)
    let control = try toggle("onepassword", in: controller)
    XCTAssertTrue(control.isOn)
    control.performClick(nil)
    XCTAssertEqual(engine.installedExtensions.first { $0.id == "onepassword" }?.isEnabled, false)
    XCTAssertEqual(try row("onepassword", in: controller).captionText, "Version 8.11. Turned off.")
    XCTAssertFalse(try toggle("onepassword", in: controller).isOn)

    try toggle("json", in: controller).performClick(nil)
    XCTAssertEqual(engine.installedExtensions.first { $0.id == "json" }?.isEnabled, true)
    XCTAssertEqual(try row("json", in: controller).captionText, "Version 0.9. Formats JSON.")
  }

  func testARefusedSwitchSnapsBack() throws {
    let inner = engine()
    let controller = open(RefusingEngine(inner))
    let control = try toggle("onepassword", in: controller)
    control.performClick(nil)
    XCTAssertTrue(control.isOn, "the engine refused: the switch shows the extension's real state")
    XCTAssertEqual(inner.installedExtensions.first { $0.id == "onepassword" }?.isEnabled, true)
  }

  /// An extension Chromium turned off because its update asks for more permissions stays off; the sheet names it and
  /// opens chrome://extensions on it in a browser window (#600 decision B). Its switch is actionable (`canDisable`).
  func testAnExtensionNeedingNewPermissionsStaysOffAndOpensItsPage() throws {
    let engine = engine()
    engine.permissionApprovalIDs = ["json"]
    let controller = open(engine)
    let control = try toggle("json", in: controller)
    XCTAssertTrue(control.isEnabled, "the switch can be pressed, so the sheet can say why")
    control.performClick(nil)
    XCTAssertFalse(try toggle("json", in: controller).isOn, "the switch shows it is still off")
    XCTAssertEqual(engine.installedExtensions.first { $0.id == "json" }?.isEnabled, false)
    let alert = try XCTUnwrap(controller.extensionAlert)
    XCTAssertEqual(alert.view.titleField.stringValue, "\u{201C}JSON Formatter\u{201D} needs new permissions")
    XCTAssertEqual(alert.view.primaryButton.title, "Review Permissions")
    XCTAssertEqual(alert.view.cancelButton?.title, "Cancel")
    alert.view.primaryButton.performClick(nil)
    XCTAssertEqual(openedURLs, [URL(string: "chrome://extensions/?id=json")!])
    XCTAssertNil(controller.extensionAlert)
  }

  func testCancelOnTheNewPermissionsSheetOpensNothing() throws {
    let engine = engine()
    engine.permissionApprovalIDs = ["json"]
    let controller = open(engine)
    try toggle("json", in: controller).performClick(nil)
    try XCTUnwrap(controller.extensionAlert?.view.cancelButton).performClick(nil)
    XCTAssertTrue(openedURLs.isEmpty)
    XCTAssertNil(controller.extensionAlert)
  }

  func testAPolicyExtensionCannotBeTurnedOffOrRemoved() throws {
    let locked = InstalledExtensionInfo(id: "corp", name: "Corp Guard", version: "3.2", description: "Required.",
                                        canDisable: false, canUninstall: false, origin: .policy)
    let engine = engine([locked])
    let controller = open(engine)
    XCTAssertFalse(try toggle("corp", in: controller).isEnabled)
    XCTAssertEqual(try row("corp", in: controller).captionText, "Version 3.2. Installed by your organization.")
    try clickRow("corp", in: controller)
    XCTAssertFalse(has(id("remove.corp"), in: controller), "no Remove for a policy extension")
    XCTAssertTrue(controller.visibleTexts().contains("Version 3.2 \u{00B7} Installed by your organization"))
  }

  func testThePinPinsAndUnpinsAndIsOffWhileTheExtensionIsOff() throws {
    let engine = engine()
    let controller = open(engine)
    let pin = try pin("onepassword", in: controller)
    XCTAssertFalse(pin.isOn)
    XCTAssertEqual(pin.accessibilityLabel(), "Pin 1Password")
    pin.performClick(nil)
    XCTAssertEqual(engine.pinnedExtensionIDs, ["onepassword"])
    XCTAssertTrue(try self.pin("onepassword", in: controller).isOn)
    try self.pin("onepassword", in: controller).performClick(nil)
    XCTAssertEqual(engine.pinnedExtensionIDs, [])
    XCTAssertFalse(try self.pin("json", in: controller).isEnabled, "Chromium pins only extensions that are on")
  }

  func testAPinChangedElsewhereShowsWhenSettingsBecomesKeyAgain() throws {
    let engine = engine()
    let controller = open(engine)
    engine.setExtensionPinned("ublock", pinned: true)          // from the Extensions panel; no extension event
    controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
    XCTAssertTrue(try pin("ublock", in: controller).isOn)
  }

  // MARK: Details

  func testClickingARowOpensItsDetailsAndASecondClickClosesThem() throws {
    let engine = engine()
    engine.setExtensionCommands([
      ExtensionCommand(id: ExtensionCommandID(extensionID: "onepassword", name: "_execute_action"),
                       extensionName: "1Password", description: "Open 1Password"),
    ])
    let controller = open(engine)
    let before = controller.paneContentHeight(.extensions)
    try clickRow("onepassword", in: controller)
    XCTAssertEqual(controller.expandedExtensionID, "onepassword")
    XCTAssertTrue(has(id("details.onepassword"), in: controller))
    XCTAssertGreaterThan(controller.paneContentHeight(.extensions), before)
    let texts = controller.visibleTexts()
    XCTAssertTrue(texts.contains("Fills your passwords."))
    XCTAssertTrue(texts.contains("Version 8.11 \u{00B7} From the Chrome Web Store"))
    XCTAssertTrue(has(id("options.onepassword"), in: controller))
    XCTAssertTrue(has(id("shortcuts.onepassword"), in: controller))
    XCTAssertTrue(has(id("remove.onepassword"), in: controller))

    try clickRow("ublock", in: controller)
    XCTAssertEqual(controller.expandedExtensionID, "ublock", "one details block at a time")
    XCTAssertFalse(has(id("details.onepassword"), in: controller))
    XCTAssertFalse(has(id("options.ublock"), in: controller), "no options page, no Options...")
    XCTAssertFalse(has(id("shortcuts.ublock"), in: controller), "no commands, no Keyboard Shortcuts...")

    try clickRow("ublock", in: controller)
    XCTAssertNil(controller.expandedExtensionID)
    XCTAssertFalse(has(id("details.ublock"), in: controller))
  }

  func testOptionsOpensTheOptionsPageAndShortcutsGoesToItsShortcuts() throws {
    let engine = engine()
    engine.setExtensionCommands([
      ExtensionCommand(id: ExtensionCommandID(extensionID: "onepassword", name: "_execute_action"),
                       extensionName: "1Password", description: "Open 1Password"),
    ])
    let controller = open(engine)
    try clickRow("onepassword", in: controller)
    try find(id("options.onepassword"), in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(engine.openedOptionsPages, ["onepassword"])
    try find(id("shortcuts.onepassword"), in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(controller.selectedPane, .shortcuts)
    XCTAssertEqual(controller.shortcutsSearch.stringValue, "1Password", "the search finds its shortcuts")
  }

  // MARK: Remove

  func testRemoveAsksThenUninstallsAndTheRowLeaves() throws {
    let engine = engine()
    let controller = open(engine)
    try clickRow("ublock", in: controller)
    try find(id("remove.ublock"), in: controller, as: NSButton.self).performClick(nil)
    let sheet = try XCTUnwrap(controller.extensionRemoveSheet)
    XCTAssertEqual(sheet.extensionID, "ublock")
    XCTAssertTrue(sheet.window?.sheetParent === controller.window, "on the Settings window")
    XCTAssertEqual(sheet.sheet.view.titleField.stringValue, "Remove \u{201C}uBlock Origin Lite\u{201D}?")
    XCTAssertNotNil(sheet.sheet.view.checkboxButton, "a Web Store extension offers Report abuse")
    XCTAssertTrue(engine.uninstalledExtensions.isEmpty, "opening asks; it removes nothing")

    sheet.sheet.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.uninstalledExtensions, [.init(extensionID: "ublock", reportAbuse: false)])
    XCTAssertNil(controller.extensionRemoveSheet)
    XCTAssertEqual(controller.shownExtensionIDs, ["onepassword", "json"])
    XCTAssertNil(controller.expandedExtensionID, "its details went with it")
  }

  func testCancelRemovesNothing() throws {
    let engine = engine()
    let controller = open(engine)
    try clickRow("ublock", in: controller)
    try find(id("remove.ublock"), in: controller, as: NSButton.self).performClick(nil)
    let sheet = try XCTUnwrap(controller.extensionRemoveSheet)
    try XCTUnwrap(sheet.sheet.view.cancelButton).performClick(nil)
    XCTAssertTrue(engine.uninstalledExtensions.isEmpty)
    XCTAssertEqual(controller.shownExtensionIDs, ["onepassword", "json", "ublock"])
  }

  func testAFailedUninstallKeepsTheRow() throws {
    let engine = engine()
    engine.failingUninstallIDs = ["ublock"]
    let controller = open(engine)
    try clickRow("ublock", in: controller)
    try find(id("remove.ublock"), in: controller, as: NSButton.self).performClick(nil)
    try XCTUnwrap(controller.extensionRemoveSheet).sheet.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.uninstalledExtensions.map(\.extensionID), ["ublock"])
    XCTAssertEqual(controller.shownExtensionIDs, ["onepassword", "json", "ublock"], "the engine kept it")
    XCTAssertEqual(controller.expandedExtensionID, "ublock")
  }

  func testTheRemoveSheetClosesWhenTheExtensionGoesAwayElsewhere() throws {
    let engine = engine()
    let controller = open(engine)
    try clickRow("ublock", in: controller)
    try find(id("remove.ublock"), in: controller, as: NSButton.self).performClick(nil)
    XCTAssertNotNil(controller.extensionRemoveSheet)
    engine.uninstallExtension("ublock", reportAbuse: false)              // the panel's Remove from Arkt...
    XCTAssertNil(controller.extensionRemoveSheet)
    XCTAssertEqual(engine.uninstalledExtensions.count, 1, "the sheet made no second call")
  }

  // MARK: Developer mode and Load unpacked

  func testDeveloperModeShowsLoadUnpackedOnlyWhileOn() throws {
    let engine = engine()
    let controller = open(engine)
    XCTAssertFalse(has(id("loadUnpacked"), in: controller))
    let developer = try find(id("developerMode"), in: controller, as: SettingsSwitch.self)
    XCTAssertFalse(developer.isOn)
    developer.performClick(nil)
    XCTAssertTrue(engine.isExtensionDeveloperModeEnabled)
    XCTAssertTrue(has(id("loadUnpacked"), in: controller))
    XCTAssertTrue(try find(id("developerMode"), in: controller, as: SettingsSwitch.self).isOn)
    try find(id("developerMode"), in: controller, as: SettingsSwitch.self).performClick(nil)
    XCTAssertFalse(engine.isExtensionDeveloperModeEnabled)
    XCTAssertFalse(has(id("loadUnpacked"), in: controller))
  }

  /// Developer mode off turns off the unpacked extensions (Chromium does): the pane asks first; Cancel keeps it on.
  func testTurningOffDeveloperModeWithUnpackedExtensionsAsksFirst() throws {
    var list = designList()
    list.append(InstalledExtensionInfo(id: "tidy", name: "Tidy Clips", version: "0.1", origin: .unpacked))
    let engine = engine(list)
    engine.setExtensionDeveloperModeEnabled(true)
    let controller = open(engine)
    try find(id("developerMode"), in: controller, as: SettingsSwitch.self).performClick(nil)
    let ask = try XCTUnwrap(controller.extensionAlert)
    XCTAssertEqual(ask.view.titleField.stringValue, "Turn off developer mode?")
    XCTAssertTrue(ask.content.paragraphs.map(\.text).contains(
      "Unpacked extensions you loaded from a folder will be turned off. They come back on when you turn developer "
        + "mode on again."))
    XCTAssertTrue(engine.isExtensionDeveloperModeEnabled, "nothing changes before the answer")
    XCTAssertTrue(try find(id("developerMode"), in: controller, as: SettingsSwitch.self).isOn)
    try XCTUnwrap(ask.view.cancelButton).performClick(nil)
    XCTAssertTrue(engine.isExtensionDeveloperModeEnabled)
    XCTAssertTrue(has(id("loadUnpacked"), in: controller))

    try find(id("developerMode"), in: controller, as: SettingsSwitch.self).performClick(nil)
    try XCTUnwrap(controller.extensionAlert).view.primaryButton.performClick(nil)
    XCTAssertFalse(engine.isExtensionDeveloperModeEnabled)
    XCTAssertEqual(engine.installedExtensions.first { $0.id == "tidy" }?.isEnabled, false)
    XCTAssertEqual(try row("tidy", in: controller).captionText, "Version 0.1. Turned off while developer mode is off.")
    XCTAssertFalse(try toggle("tidy", in: controller).isEnabled, "locked until developer mode is on again")
    XCTAssertFalse(has(id("loadUnpacked"), in: controller))

    try find(id("developerMode"), in: controller, as: SettingsSwitch.self).performClick(nil)
    XCTAssertEqual(engine.installedExtensions.first { $0.id == "tidy" }?.isEnabled, true, "back on with it")
    XCTAssertTrue(try toggle("tidy", in: controller).isOn)
  }

  func testLoadUnpackedPassesOnlyAFileURL() async throws {
    let engine = engine()
    engine.setExtensionDeveloperModeEnabled(true)
    let controller = open(engine)
    controller.unpackedFolderPicker = { _, done in done(URL(string: "https://example.com/extension")) }
    try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
    await controller.pendingUnpackedLoad?.value
    XCTAssertTrue(engine.loadedUnpackedFolders.isEmpty)
    XCTAssertNil(controller.pendingUnpackedLoad)
  }

  func testLoadUnpackedLoadsTheChosenFolder() async throws {
    let engine = engine()
    engine.setExtensionDeveloperModeEnabled(true)
    let controller = open(engine)
    let folder = URL(fileURLWithPath: "/tmp/Tidy Clips", isDirectory: true)
    var asked = 0
    controller.unpackedFolderPicker = { window, done in
      asked += 1
      XCTAssertTrue(window === controller.window)
      done(folder)
    }
    try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
    await controller.pendingUnpackedLoad?.value
    XCTAssertEqual(asked, 1)
    XCTAssertEqual(engine.loadedUnpackedFolders, [folder])
    let loaded = try XCTUnwrap(engine.installedExtensions.first { $0.origin == .unpacked })
    XCTAssertTrue(controller.shownExtensionIDs.contains(loaded.id))
    XCTAssertEqual(controller.expandedExtensionID, loaded.id, "the loaded extension's details open")
    XCTAssertTrue(controller.visibleTexts().contains("Version 1.0 \u{00B7} Loaded from a folder"))
    XCTAssertNil(controller.extensionAlert)
  }

  func testACancelledFolderPanelLoadsNothing() async throws {
    let engine = engine()
    engine.setExtensionDeveloperModeEnabled(true)
    let controller = open(engine)
    controller.unpackedFolderPicker = { _, done in done(nil) }
    try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
    await controller.pendingUnpackedLoad?.value
    XCTAssertTrue(engine.loadedUnpackedFolders.isEmpty)
  }

  func testAFailedLoadShowsTheEnginesReason() async throws {
    let engine = engine()
    engine.setExtensionDeveloperModeEnabled(true)
    engine.unpackedLoadFailure = "Manifest file is missing or unreadable."
    let controller = open(engine)
    controller.unpackedFolderPicker = { _, done in done(URL(fileURLWithPath: "/tmp/empty", isDirectory: true)) }
    try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
    await controller.pendingUnpackedLoad?.value
    let alert = try XCTUnwrap(controller.extensionAlert)
    XCTAssertTrue(alert.window?.sheetParent === controller.window)
    XCTAssertEqual(alert.view.titleField.stringValue, "Couldn\u{2019}t load the extension")
    XCTAssertTrue(alert.content.paragraphs.map(\.text).contains("Manifest file is missing or unreadable."))
    XCTAssertEqual(alert.view.primaryButton.title, "OK")
    XCTAssertNil(alert.view.cancelButton, "one answer")
    alert.view.primaryButton.performClick(nil)
    XCTAssertNil(controller.extensionAlert)
    XCTAssertEqual(controller.shownExtensionIDs, ["onepassword", "json", "ublock"])
  }

  func testALoadThatFinishesAfterSettingsClosedIsIgnored() async throws {
    let engine = engine()
    engine.setExtensionDeveloperModeEnabled(true)
    engine.unpackedLoadFailure = "Manifest file is missing or unreadable."
    let controller = open(engine)
    controller.unpackedFolderPicker = { _, done in done(URL(fileURLWithPath: "/tmp/empty", isDirectory: true)) }
    try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
    let load = try XCTUnwrap(controller.pendingUnpackedLoad)
    controller.window?.close()
    XCTAssertNil(controller.pendingUnpackedLoad, "the window's close forgets it")
    await load.value
    XCTAssertNil(controller.extensionAlert, "no sheet on a closed window")
    XCTAssertNil(controller.expandedExtensionID)
  }

  // MARK: Empty

  func testNoExtensionsShowsTheEmptyStateWithTheOnePrimary() throws {
    let controller = open(engine([]))
    let texts = controller.visibleTexts()
    XCTAssertTrue(texts.contains("No Extensions Yet"))
    XCTAssertTrue(texts.contains("Arkt runs extensions from the Chrome Web Store. The ones you add show up here and "
                                 + "in the sidebar\u{2019}s extensions menu."))
    XCTAssertFalse(texts.contains("Installed"), "the empty state has no section title")
    XCTAssertFalse(texts.contains("Get more extensions"))
    XCTAssertTrue(texts.contains("Developer mode"))
    XCTAssertTrue(controller.shownExtensionIDs.isEmpty)
    XCTAssertEqual(controller.primaryActionCount(in: .extensions), 1, "Open Chrome Web Store is the one primary")
    try find(id("openWebStore"), in: controller, as: ArchivePillButton.self).performClick(nil)
    XCTAssertEqual(webStoreOpens, 1)
  }

  func testTheListFollowsAnInstallAndTheLastRemoval() throws {
    let engine = engine([])
    let controller = open(engine)
    let emptyHeight = controller.paneContentHeight(.extensions)
    engine.installExtension(InstalledExtension(id: "reader", name: "Quiet Reader"))
    XCTAssertEqual(controller.shownExtensionIDs, ["reader"])
    XCTAssertFalse(controller.visibleTexts().contains("No Extensions Yet"))
    engine.uninstallExtension("reader", reportAbuse: false)
    XCTAssertTrue(controller.shownExtensionIDs.isEmpty)
    XCTAssertTrue(controller.visibleTexts().contains("No Extensions Yet"))
    XCTAssertEqual(controller.paneContentHeight(.extensions), emptyHeight)
  }

  // MARK: Manage Extension...

  func testManageOpensThePaneWithTheExtensionsDetails() throws {
    let controller = make(engine: engine())
    controller.show(pane: .general)
    controller.show(extensionID: "ublock")
    XCTAssertEqual(controller.selectedPane, .extensions)
    XCTAssertEqual(controller.expandedExtensionID, "ublock")
    XCTAssertTrue(has(id("details.ublock"), in: controller))
  }

  /// Manage on the 40th extension: its details are scrolled into view, from an open window and from a closed one.
  func testManageScrollsAFarRowsDetailsIntoView() throws {
    let list = (0..<40).map { InstalledExtensionInfo(id: String(format: "ext%02d", $0), name: String(format: "Ext %02d", $0),
                                                     version: "1") }
    for opensFirst in [true, false] {
      let controller = make(engine: engine(list))
      if opensFirst { controller.show(pane: .general) }
      controller.show(extensionID: "ext39")
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      let details = try find(id("details.ext39"), in: controller)
      XCTAssertFalse(details.visibleRect.isEmpty, "details visible (window open first: \(opensFirst))")
      let row = try row("ext39", in: controller)
      XCTAssertFalse(row.visibleRect.isEmpty)
      controller.window?.close()
    }
  }

  func testManageForAClosedWindowAndAnUnknownExtension() throws {
    let controller = make(engine: engine())
    controller.show(extensionID: "json")
    XCTAssertEqual(controller.selectedPane, .extensions)
    XCTAssertEqual(controller.expandedExtensionID, "json")
    controller.show(extensionID: "gone")
    XCTAssertEqual(controller.selectedPane, .extensions)
    XCTAssertNil(controller.expandedExtensionID, "an extension that went away: the pane, nothing open")
  }

  // MARK: Worst cases

  func testFortyExtensionsWithLongTextScrollAndNeverOverlapTheirControls() throws {
    let long = String(repeating: "Extraordinarily Verbose Extension Name ", count: 4)
    let list = (0..<40).map { index in
      InstalledExtensionInfo(id: String(format: "ext%02d", index), name: "\(long)\(index)", version: "10.20.30.40",
                             description: String(repeating: "A long description that keeps going. ", count: 8),
                             isEnabled: index % 3 != 0)
    }
    let controller = open(engine(list))
    XCTAssertEqual(controller.shownExtensionIDs.count, 40)
    let window = try XCTUnwrap(controller.window)
    let screen = try XCTUnwrap(window.screen ?? NSScreen.main)
    XCTAssertLessThanOrEqual(window.frame.height, screen.visibleFrame.height - SettingsMetrics.screenMargin + 0.5,
                             "the window stops at the screen; the pane scrolls")
    XCTAssertGreaterThan(controller.paneContentHeight(.extensions), window.frame.height)
    for extensionID in ["ext00", "ext17", "ext39"] {
      let row = try row(extensionID, in: controller)
      row.layoutSubtreeIfNeeded()
      let labels = row.subviews.compactMap { $0 as? NSTextField }
      let pinFrame = try pin(extensionID, in: controller).frame
      for label in labels {
        XCTAssertLessThanOrEqual(label.frame.maxX, pinFrame.minX, "\(extensionID): text stops before the pin")
      }
      XCTAssertLessThanOrEqual(row.frame.height, 60, "\(extensionID): name and caption take one line each")
    }
    XCTAssertEqual(window.frame.width, SettingsMetrics.windowWidth, "no sideways growth")
  }

  func testDarkModeAndLightModeBuildTheSamePane() throws {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let controller = make(engine: engine(), appearance: appearance)
      controller.show(pane: .extensions)
      XCTAssertEqual(controller.shownExtensionIDs.count, 3, "\(appearance)")
      controller.window?.close()
    }
  }

  func testAnEngineWithoutExtensionsShowsTheEmptyStateAndAPlannedDeveloperMode() throws {
    let controller = open(nil)
    XCTAssertTrue(controller.visibleTexts().contains("No Extensions Yet"))
    let developer = try find(id("developerMode"), in: controller, as: SettingsSwitch.self)
    XCTAssertFalse(developer.isEnabled)
  }

  // MARK: Screenshots

  /// A 40 px letter tile, the design's synthetic icons.
  private static func tile(_ letter: String, _ color: NSColor) -> Data {
    let image = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
      color.setFill()
      rect.fill()
      let font = NSFont.systemFont(ofSize: 20, weight: .bold)
      let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
      let size = text.size()
      text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
      return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
    return rep?.representation(using: .png, properties: [:]) ?? Data()
  }

  /// Opt-in: the pane's states in light and dark, to compare with design/settings `extensions` and `extensions-empty`.
  /// The window's content is drawn into the PNG (the load error: the sheet's), so the shots do not depend on screen
  /// capture. Synthetic extensions only.
  func testExtensionsShots() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_EXTENSIONS_SETTINGS_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_EXTENSIONS_SETTINGS_SHOTS_DIR to export the Settings > Extensions screenshots")
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let design = [
      InstalledExtensionInfo(id: "onepassword", name: "1Password", version: "8.11",
                             description: "Fills your passwords and keeps them safe.",
                             iconPNG: Self.tile("1", NSColor(srgbRed: 0.16, green: 0.36, blue: 0.85, alpha: 1)),
                             hasOptionsPage: true, siteAccess: .allSites),
      InstalledExtensionInfo(id: "ublock", name: "uBlock Origin Lite", version: "2025.1",
                             description: "Blocks ads and trackers on all sites.",
                             iconPNG: Self.tile("u", NSColor(srgbRed: 0.5, green: 0.08, blue: 0.08, alpha: 1)),
                             siteAccess: .onClick),
      InstalledExtensionInfo(id: "json", name: "JSON Formatter", version: "0.9", description: "Formats JSON.",
                             iconPNG: Self.tile("{}", NSColor(srgbRed: 0.24, green: 0.33, blue: 0.29, alpha: 1)),
                             isEnabled: false),
    ]
    let worst = [
      InstalledExtensionInfo(id: "corp", name: "Corp Guard", version: "3.2", description: "Required by your company.",
                             canDisable: false, canUninstall: false, origin: .policy),
      InstalledExtensionInfo(id: "long", name: String(repeating: "Extraordinarily Verbose Extension Name ", count: 3),
                             version: "10.20.30.40",
                             description: String(repeating: "A long description that keeps going. ", count: 6)),
      InstalledExtensionInfo(id: "noicon", name: "No Icon", version: "", description: ""),
    ]
    for dark in [false, true] {
      for state in ["", "-empty", "-details", "-developer", "-worst-case", "-load-error"] {
        let list: [InstalledExtensionInfo] = switch state {
        case "-empty": []
        case "-worst-case": worst
        default: design
        }
        let engine = engine(list)
        engine.setExtensionPinned("onepassword", pinned: true)
        if state == "-developer" || state == "-load-error" { engine.setExtensionDeveloperModeEnabled(true) }
        let controller = make(engine: engine, appearance: dark ? .darkAqua : .aqua)
        controller.show(pane: .extensions)
        let window = try XCTUnwrap(controller.window)
        if state == "-details" { try clickRow("onepassword", in: controller) }
        if state == "-worst-case" { try clickRow("corp", in: controller) }
        if state == "-load-error" {
          engine.unpackedLoadFailure = "Manifest file is missing or unreadable."
          controller.unpackedFolderPicker = { _, done in done(URL(fileURLWithPath: "/tmp/empty", isDirectory: true)) }
          try find(id("loadUnpacked"), in: controller, as: NSButton.self).performClick(nil)
          await controller.pendingUnpackedLoad?.value
        }
        let shown = state == "-load-error" ? try XCTUnwrap(controller.extensionAlert?.window) : window
        let content = try XCTUnwrap(shown.contentView)
        content.layoutSubtreeIfNeeded()
        let file = folder.appendingPathComponent("extensions\(state)-\(dark ? "dark" : "light").png")
        try write(content, background: shown.backgroundColor, to: file)
        controller.closeExtensionSheets()
        window.close()
      }
    }
  }

  /// Draws `view` over the window background into a PNG.
  private func write(_ view: NSView, background: NSColor, to url: URL) throws {
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      background.setFill()
      NSRect(x: 0, y: 0, width: bitmap.size.width, height: bitmap.size.height).fill()
      NSGraphicsContext.restoreGraphicsState()
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
  }
}

/// Forwards to an InMemoryEngine but refuses every enable or disable.
@MainActor
private final class RefusingEngine: EngineExtensions {
  let inner: InMemoryEngine
  init(_ inner: InMemoryEngine) { self.inner = inner }
  var installedExtensions: [InstalledExtensionInfo] { inner.installedExtensions }
  var pinnedExtensionIDs: [String] { inner.pinnedExtensionIDs }
  func extensionActions(in window: EngineWindowID) -> [ExtensionAction] { [] }
  func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView) {}
  func setExtensionEnabled(_ extensionID: String, enabled: Bool) -> ExtensionEnableResult { .refused }
  func observeExtensions(_ handler: @escaping @MainActor (EngineExtensionEvent) -> Void) -> EngineObservation {
    inner.observeExtensions(handler)
  }
}
