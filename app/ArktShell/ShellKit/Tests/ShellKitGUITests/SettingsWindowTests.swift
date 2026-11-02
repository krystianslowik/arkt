import AppKit
import XCTest
@testable import ShellUI

/// The Settings window (#307, docs/design/settings.md): one window of seven panes, keys that switch and close it,
/// rows wired to the app's settings, unbuilt rows shown disabled, and the one primary per pane.
@MainActor
final class SettingsWindowTests: XCTestCase {
  private var controllers: [SettingsWindowController] = []
  private var suiteName = ""
  private var defaults = UserDefaults.standard

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "dev.arkt.tests.settingsWindow.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() async throws {
    controllers.forEach { $0.window?.close() }
    controllers = []
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  /// Calls the services record, for the actions the app target answers.
  private final class Services {
    var isDefault = false
    var made = 0
    var imported = 0
    var revealed = 0
    var canImport = true
  }

  private func make(settings: AppSettings? = nil, services: Services = Services(),
                    menu: NSMenu? = nil, sidebar: StubSidebar? = nil) -> SettingsWindowController {
    var env = SettingsServices()
    env.isDefaultBrowser = { services.isDefault }
    env.makeDefaultBrowser = {
      services.made += 1
      services.isDefault = true
    }
    env.canImportBrowserData = { services.canImport }
    env.importBrowserData = { services.imported += 1 }
    env.showDataFolder = { services.revealed += 1 }
    let shortcuts = menu ?? MainMenu.make(commands: AppCommands()).menu
    env.shortcutsMenu = { shortcuts }
    if let sidebar { env.spaces = { SettingsSpaceSummary.list(from: sidebar) } }
    let controller = SettingsWindowController(settings: settings ?? AppSettings(defaults: defaults), services: env)
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

  private func keyDown(_ characters: String, _ flags: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: characters,
                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
  }

  // MARK: - Window

  func testWindowShapeTitleAndIdentifier() throws {
    let controller = make()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    XCTAssertEqual(window.frame.width, 680, "fixed width (decision 5)")
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "one unified bar")
    XCTAssertFalse(window.styleMask.contains(.resizable))
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertFalse(window.isReleasedWhenClosed, "one instance, fronted again")
    XCTAssertEqual(window.accessibilityIdentifier(), AXID.Settings.window)
    XCTAssertEqual(window.accessibilityTitle(), "Settings, General")
    XCTAssertEqual(controller.titleLabel.stringValue, "General")
    XCTAssertEqual(controller.selectedPane, .general)
  }

  func testEveryPaneHasATabItem() throws {
    let controller = make()
    controller.show()
    for pane in SettingsPane.allCases {
      let item = try find(AXID.Settings.tab(pane.rawValue), in: controller, as: SettingsPaneItemView.self)
      XCTAssertEqual(item.accessibilityRole(), .radioButton)
      XCTAssertEqual(item.accessibilityLabel(), pane.label)
      XCTAssertEqual(item.frame.size, NSSize(width: 84, height: 44))
      XCTAssertEqual(item.isSelected, pane == .general)
    }
  }

  /// The height fits the pane, at most the screen's visible height minus 120; the content scrolls past that.
  func testHeightFitsThePaneUpToTheScreen() throws {
    let controller = make()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    let limit = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame.height - 120
    for pane in SettingsPane.allCases {
      controller.select(pane, animated: false)
      let expected = min(limit, SettingsMetrics.chromeHeight + controller.paneContentHeight(pane))
      XCTAssertEqual(window.contentLayoutRect.height + (window.frame.height - window.contentLayoutRect.height),
                     window.frame.height)
      XCTAssertEqual(window.frame.height, expected, accuracy: 0.5, "\(pane)")
    }
  }

  /// Keyboard pane switches keep the top edge where it was.
  func testPaneSwitchKeepsTheTopEdge() throws {
    let controller = make()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    let top = window.frame.maxY
    controller.select(.shortcuts, animated: false)
    XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
    controller.select(.general, animated: false)
    XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
  }

  func testShowFrontsTheOneWindowAndRemembersThePane() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show()
    controller.select(.advanced, animated: false)
    XCTAssertEqual(settings.lastPane, .advanced)
    controller.window?.close()
    controller.show()
    XCTAssertEqual(controller.selectedPane, .advanced)
    XCTAssertTrue(controller.window?.isVisible == true)

    let reopened = make(settings: AppSettings(defaults: defaults))
    reopened.show()
    XCTAssertEqual(reopened.selectedPane, .advanced, "the last pane is restored across launches")
  }

  /// The frame origin is restored: the top-left corner, kept in the settings suite.
  func testWindowPositionIsRestored() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show()
    let window = try XCTUnwrap(controller.window)
    let visible = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
    let topLeft = NSPoint(x: visible.minX + 40, y: visible.maxY - 30)
    window.setFrameTopLeftPoint(topLeft)
    window.close()
    XCTAssertEqual(settings.windowTopLeft, topLeft)

    let reopened = make(settings: AppSettings(defaults: defaults))
    reopened.show()
    let frame = try XCTUnwrap(reopened.window?.frame)
    XCTAssertEqual(frame.minX, topLeft.x, accuracy: 0.5)
    XCTAssertEqual(frame.maxY, topLeft.y, accuracy: 0.5)
  }

  func testShowWithAPaneSelectsIt() {
    let controller = make()
    controller.show(pane: .spaces)
    XCTAssertEqual(controller.selectedPane, .spaces)
    XCTAssertEqual(controller.titleLabel.stringValue, "Spaces and Profiles")
  }

  // MARK: - Keys

  /// Cmd-1 to Cmd-7 switch panes with no animation: the frame and the tab tile change in the same turn.
  func testCommandNumberSwitchesPanesInstantly() throws {
    let controller = make()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    XCTAssertTrue(window.performKeyEquivalent(with: try keyDown("4", .command, in: window)))
    XCTAssertEqual(controller.selectedPane, .shortcuts)
    let limit = (window.screen ?? NSScreen.main).map { $0.visibleFrame.height - 120 } ?? .infinity
    XCTAssertEqual(window.frame.height,
                   min(limit, SettingsMetrics.chromeHeight + controller.paneContentHeight(.shortcuts)), accuracy: 0.5)
    let item = try find(AXID.Settings.tab("shortcuts"), in: controller, as: SettingsPaneItemView.self)
    XCTAssertTrue(item.isSelected)
    XCTAssertEqual(item.plateOpacity, 1, "no fade on a keyboard switch")
    XCTAssertNil(controller.paneContainer.layer?.animationKeys(), "no pane animation on a keyboard switch")
    XCTAssertFalse(window.performKeyEquivalent(with: try keyDown("8", .command, in: window)), "only 1 to 7")
    XCTAssertEqual(controller.selectedPane, .shortcuts)
  }

  /// Cmd-W closes Settings (Archive Tab would be disabled there), and the item reads Close Window; Go to Sidebar
  /// Item validates false while Settings is key (decision 1).
  func testMenuValidationWhileSettingsIsKey() throws {
    let controller = make()
    controller.show()
    let close = NSMenuItem(title: "Archive Tab", action: #selector(ShellWindowController.closeTab(_:)),
                           keyEquivalent: "w")
    XCTAssertTrue(controller.validateMenuItem(close))
    XCTAssertEqual(close.title, "Close Window")
    let goTo = NSMenuItem(title: "Go to Sidebar Item 1", action: #selector(ShellWindowController.goToSidebarItem(_:)),
                          keyEquivalent: "1")
    XCTAssertFalse(controller.validateMenuItem(goTo))

    controller.closeTab(nil)
    XCTAssertFalse(controller.window?.isVisible == true)
  }

  func testCommandWClosesTheWindow() throws {
    let controller = make()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    XCTAssertTrue(window.performKeyEquivalent(with: try keyDown("w", .command, in: window)))
    XCTAssertFalse(window.isVisible)
  }

  func testEscapeCloses() throws {
    let controller = make()
    controller.show()
    controller.cancelOperation(nil)
    XCTAssertFalse(controller.window?.isVisible == true)
  }

  /// A real Escape key event (not a direct `cancelOperation`), with no control focused and with a switch focused,
  /// reaches the window controller and closes Settings.
  func testEscapeKeyEventCloses() throws {
    for focusesSwitch in [false, true] {
      let controller = make()
      controller.show(pane: .appearance)
      let window = try XCTUnwrap(controller.window)
      if focusesSwitch {
        let toggle = try find(AXID.Settings.control("appearance", "showToolbar"), in: controller)
        window.makeFirstResponder(toggle)
      }
      let escape = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
      window.sendEvent(escape)
      XCTAssertFalse(window.isVisible, "Escape closes Settings (switch focused: \(focusesSwitch))")
    }
  }

  /// In the Shortcuts search field Escape first clears a non-empty search; with an empty field it closes Settings.
  func testEscapeInTheShortcutsSearchClearsFirst() throws {
    let controller = make()
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let field = try find(AXID.Settings.shortcutsSearch, in: controller, as: NSSearchField.self)
    controller.setShortcutSearch("toolbar")
    XCTAssertEqual(controller.visibleShortcutTitles, ["Show Toolbar"])
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertEqual(field.stringValue, "")
    XCTAssertTrue(window.isVisible, "the first Escape only cleared the search")
    XCTAssertGreaterThan(controller.visibleShortcutTitles.count, 10)
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertFalse(window.isVisible)
  }

  // MARK: - General

  /// Not the default browser: Make Default is the pane's one primary; afterwards the row shows the Default capsule.
  func testDefaultBrowserRow() async throws {
    let services = Services()
    let controller = make(services: services)
    controller.show()
    let button = try find(AXID.Settings.control("general", "makeDefault"), in: controller, as: ArchivePillButton.self)
    XCTAssertEqual(button.style, .primary)
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(controller.primaryActionCount(in: .general), 1)

    button.performClick(nil)
    await controller.pendingDefaultBrowserChange?.value
    XCTAssertEqual(services.made, 1)
    XCTAssertNotNil(try? find(AXID.Settings.control("general", "defaultBrowserSeal"), in: controller))
    XCTAssertEqual(controller.primaryActionCount(in: .general), 0, "no mustard once Arkt is the default")
  }

  /// The row is read again when the app becomes active (macOS asks in its own prompt).
  func testDefaultBrowserRowRefreshesOnActivation() throws {
    let services = Services()
    let controller = make(services: services)
    controller.show()
    services.isDefault = true
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
    XCTAssertNotNil(try? find(AXID.Settings.control("general", "defaultBrowserSeal"), in: controller))
  }

  func testPeekLinkSwitchesWriteTheSettings() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show()
    let crossSite = try find(AXID.Settings.control("general", "peekCrossSiteLinks"), in: controller,
                             as: SettingsSwitch.self)
    let shift = try find(AXID.Settings.control("general", "peekShiftClick"), in: controller, as: SettingsSwitch.self)
    XCTAssertTrue(crossSite.isEnabled)
    XCTAssertTrue(crossSite.isOn)
    crossSite.performClick(nil)
    XCTAssertFalse(settings.peekLinks.opensCrossSiteLinks)
    shift.performClick(nil)
    XCTAssertFalse(settings.peekLinks.opensShiftClickedLinks)
    XCTAssertEqual(crossSite.accessibilityLabel(), "Open a Peek window when clicking on links to other sites")
    XCTAssertEqual(crossSite.accessibilityHelp(), "Only affects Favorites and pinned tabs")
    XCTAssertEqual(shift.accessibilityLabel(), "Open a Peek window when clicking on links with Shift held")
    XCTAssertTrue(controller.visibleTexts().contains("Only affects Favorites and pinned tabs"),
                  "the note under the row is the design copy")
  }

  /// Decision 4: an unbuilt row is shown, disabled: secondary label, control at 42 % and not enabled, caption ending
  /// "Not available yet.".
  func testUnbuiltRowsAreShownDisabled() throws {
    let controller = make()
    controller.show()
    for name in ["updateAutomatically"] {
      let control = try find(AXID.Settings.control("general", name), in: controller, as: SettingsSwitch.self)
      XCTAssertFalse(control.isEnabled, name)
      XCTAssertEqual(control.alphaValue, 0.42, accuracy: 0.001, name)
      XCTAssertTrue(control.accessibilityHelp()?.hasSuffix("Not available yet.") == true, name)
      let row = try XCTUnwrap(control.enclosingSettingsRow)
      XCTAssertTrue(row.isPlanned)
      XCTAssertTrue(row.captionText.hasSuffix("Not available yet."))
      XCTAssertEqual(row.labelColor, ShellTokens.secondaryText.resolve(row.archiveFlavor))
    }
    let restore = try find(AXID.Settings.control("general", "whenArktOpens"), in: controller,
                           as: SettingsPopUpButton.self)
    XCTAssertFalse(restore.isEnabled)
    XCTAssertEqual(restore.selectedTitle, "Restore last windows")
  }

  /// BH-177: the row is a real switch, off until the user turns it on, and a later change follows the setting.
  func testWarnBeforeQuittingIsARealToggleDefaultOff() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show()
    let control = try find(AXID.Settings.control("general", "warnBeforeQuitting"), in: controller,
                           as: SettingsSwitch.self)
    XCTAssertTrue(control.isEnabled)
    XCTAssertFalse(control.isOn)
    XCTAssertEqual(control.alphaValue, 1, accuracy: 0.001)
    let row = try XCTUnwrap(control.enclosingSettingsRow)
    XCTAssertFalse(row.isPlanned)
    XCTAssertEqual(row.captionText, "Hold Command-Q to quit while a window is open.")
    XCTAssertFalse(row.captionText.contains("Not available yet."))

    control.performClick(nil)
    XCTAssertTrue(settings.warnsBeforeQuitting)
    XCTAssertEqual(defaults.object(forKey: AppSettings.Key.shouldWarnBeforeQuitting) as? Bool, true)

    settings.warnsBeforeQuitting = false
    XCTAssertFalse(control.isOn)
    XCTAssertEqual(defaults.object(forKey: AppSettings.Key.shouldWarnBeforeQuitting) as? Bool, false)
  }

  // MARK: - Appearance

  /// Settings and the View menu (Cmd-Shift-D) move the same shared value, in both directions; Show the full URL is
  /// disabled while the Toolbar is off.
  func testToolbarSwitchesFollowTheSharedSetting() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show(pane: .appearance)
    let toolbar = try find(AXID.Settings.control("appearance", "showToolbar"), in: controller, as: SettingsSwitch.self)
    let fullURL = try find(AXID.Settings.control("appearance", "showFullURL"), in: controller, as: SettingsSwitch.self)
    XCTAssertFalse(toolbar.isOn)
    XCTAssertFalse(fullURL.isEnabled, "dimmed while the Toolbar is off")

    toolbar.performClick(nil)
    XCTAssertTrue(settings.toolbar.isVisible)
    XCTAssertTrue(fullURL.isEnabled)
    XCTAssertTrue(controller.appearancePreviewShowsToolbar)

    settings.toolbar.isVisible = false                       // as Cmd-Shift-D in a browser window
    XCTAssertFalse(toolbar.isOn)
    XCTAssertFalse(fullURL.isEnabled)
    settings.toolbar.showsFullURL = false
    XCTAssertFalse(fullURL.isOn)
    XCTAssertEqual(toolbar.accessibilityRole(), .checkBox)
    XCTAssertEqual(toolbar.accessibilitySubrole(), .switch)
  }

  func testTabNavigationSwitchesWriteTheSettings() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = make(settings: settings)
    controller.show(pane: .appearance)
    let favorites = try find(AXID.Settings.control("appearance", "countFavorites"), in: controller,
                             as: SettingsSwitch.self)
    let ninth = try find(AXID.Settings.control("appearance", "ninthTab"), in: controller, as: SettingsSwitch.self)
    XCTAssertTrue(favorites.isOn)
    XCTAssertFalse(ninth.isOn)
    favorites.performClick(nil)
    ninth.performClick(nil)
    XCTAssertEqual(settings.tabNavigation.countsFavorites, false)
    XCTAssertEqual(settings.tabNavigation.ninthOpensNinth, true)
    let haptics = try find(AXID.Settings.control("appearance", "reorderHaptics"), in: controller,
                           as: SettingsSwitch.self)
    XCTAssertFalse(haptics.isEnabled)
  }

  // MARK: - Shortcuts, Spaces, Advanced

  func testShortcutsListTheMainMenu() throws {
    let controller = make()
    controller.show(pane: .shortcuts)
    let titles = controller.visibleShortcutTitles
    XCTAssertTrue(titles.contains("New Tab"))
    XCTAssertTrue(titles.contains("Show or Hide Toolbar") || titles.contains("Show Toolbar"))
    XCTAssertFalse(titles.contains("Next Tab") && titles.filter { $0 == "Next Tab" }.count > 1,
                   "hidden aliases are not listed")
    controller.setShortcutSearch("Command-T")
    XCTAssertEqual(controller.visibleShortcutTitles, ["New Tab"])
    let reset = try find(AXID.Settings.control("shortcuts", "resetAll"), in: controller, as: NSButton.self)
    XCTAssertFalse(reset.isEnabled, "rebinding is #119")
  }

  func testSpacesPaneShowsTheSidebarsSpaces() throws {
    let sidebar = StubSidebar()
    let theme = SpaceThemeInfo(baseColors: [.srgb(hex: 0xB9D5F5), .srgb(hex: 0x8FB3E8)], isDark: false)
    let work = sidebar.addSpace(title: "Work", theme: theme)
    try sidebar.addTab(url: URL(string: "https://a.example")!, title: "A", in: .pinned(work), at: nil)
    let controller = make(sidebar: sidebar)
    controller.show(pane: .spaces)
    let row = try find(AXID.Settings.spaceRow(work.uuidString), in: controller, as: SettingsRowView.self)
    XCTAssertEqual(row.labelText, "Work")
    XCTAssertEqual(row.captionText, "1 pinned, 0 in Today")
    XCTAssertEqual(controller.primaryActionCount(in: .spaces), 0)
  }

  func testAdvancedImportAndDataFolder() throws {
    let services = Services()
    let controller = make(services: services)
    controller.show(pane: .advanced)
    let importButton = try find(AXID.Settings.control("advanced", "importBrowserData"), in: controller,
                                as: ArchivePillButton.self)
    let reveal = try find(AXID.Settings.control("advanced", "showDataFolder"), in: controller,
                          as: ArchivePillButton.self)
    XCTAssertEqual(importButton.style, .neutral)
    importButton.performClick(nil)
    reveal.performClick(nil)
    XCTAssertEqual(services.imported, 1)
    XCTAssertEqual(services.revealed, 1)
    XCTAssertEqual(controller.primaryActionCount(in: .advanced), 0)
    let reset = try find(AXID.Settings.control("advanced", "resetAll"), in: controller, as: NSButton.self)
    XCTAssertFalse(reset.isEnabled)
  }

  /// No ad blocking row (decision 3) and no user-facing "Arc" anywhere in Settings.
  func testCopyHasNoAdBlockingAndNoArc() throws {
    let controller = make()
    controller.show()
    var texts: [String] = []
    for pane in SettingsPane.allCases {
      controller.select(pane, animated: false)
      texts += controller.visibleTexts()
    }
    XCTAssertFalse(texts.isEmpty)
    for text in texts {
      XCTAssertNil(text.range(of: "\\bArc\\b", options: .regularExpression), text)
      XCTAssertFalse(text.localizedCaseInsensitiveContains("ad block"), text)
      XCTAssertFalse(text.localizedCaseInsensitiveContains("tracker blocking"), text)
    }
    XCTAssertTrue(texts.contains("Import browser data"))
  }

  /// Mustard is only the one primary: Extensions and Privacy have no enabled primary today.
  func testAtMostOnePrimaryPerPane() {
    let controller = make()
    controller.show()
    for pane in SettingsPane.allCases {
      controller.select(pane, animated: false)
      XCTAssertLessThanOrEqual(controller.primaryActionCount(in: pane), 1, "\(pane)")
    }
  }

  // MARK: - Motion

  /// A click switch animates (the pane fades and rises on a spring) and stays interruptible: a second switch
  /// mid-flight lands on the second pane.
  func testClickSwitchAnimatesAndCanBeInterrupted() throws {
    let controller = make()
    controller.reduceMotion = { false }
    controller.show()
    controller.select(.appearance, animated: true)
    XCTAssertEqual(controller.selectedPane, .appearance)
    XCTAssertNotNil(controller.paneContainer.layer?.animation(forKey: "opacity"))
    controller.select(.privacy, animated: true)
    XCTAssertEqual(controller.selectedPane, .privacy)
    XCTAssertEqual(controller.titleLabel.stringValue, "Privacy and Security")
  }

  /// Reduce Motion: no translate, the pane only cross-fades.
  func testReduceMotionCrossFadesOnly() throws {
    let controller = make()
    controller.reduceMotion = { true }
    controller.show()
    controller.select(.appearance, animated: true)
    XCTAssertNil(controller.paneContainer.layer?.animation(forKey: "transform.translation.y"))
    XCTAssertNotNil(controller.paneContainer.layer?.animation(forKey: "opacity"))
  }
}
