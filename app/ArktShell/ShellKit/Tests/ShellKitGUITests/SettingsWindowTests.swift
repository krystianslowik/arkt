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
                    menu: NSMenu? = nil, sidebar: StubSidebar? = nil,
                    editor: ShortcutEditorModel? = nil,
                    isSystemShortcut: @escaping @MainActor (ShortcutBinding) -> Bool = { _ in false }
  ) -> SettingsWindowController {
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
    env.shortcutEditor = editor
    env.isSystemShortcut = isSystemShortcut
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
    XCTAssertFalse(reset.isEnabled, "there are no customized shortcuts to reset")
  }

  /// The recorder receives window events while focused; Tab leaves it, Escape cancels and Delete clears.
  func testShortcutRecorderRoutesKeyboardAndFocus() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let id = ShortcutActionID("toggleSidebarVisibility")
    let recorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)
    recorder.performClick(nil)
    XCTAssertTrue(window.firstResponder === recorder)
    window.sendEvent(try shortcutEvent("k", .command, code: 40, in: window))
    XCTAssertEqual(model.binding(for: id), ShortcutBinding(key: "k", modifiers: .command))

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("\t", [], code: 48, in: window))
    XCTAssertNotNil(window.firstResponder)
    XCTAssertFalse(window.firstResponder === recorder, "Tab navigates away instead of becoming a binding")
    XCTAssertEqual(model.binding(for: id), ShortcutBinding(key: "k", modifiers: .command))
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("\u{1B}", [], code: 53, in: window))
    XCTAssertTrue(window.isVisible, "Escape cancels recording, not Settings")
    XCTAssertEqual(model.binding(for: id), ShortcutBinding(key: "k", modifiers: .command))
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("\u{7F}", [], code: 51, in: window))
    XCTAssertNil(model.binding(for: id))
  }

  /// Search tracks both changed bindings and updates to an already-filtered list, including clears and resets.
  func testShortcutSearchUsesLiveBindingsAfterEditClearAndReset() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    ShortcutCatalog.bind(model: model, to: menu)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let root = try XCTUnwrap(window.contentView)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let identifier = "settings.shortcuts.record.toggleSidebarVisibility"
    let recorder = try find(identifier, in: controller, as: NSButton.self)
    controller.setShortcutSearch("Command-S")
    XCTAssertNotNil(Self.view(identifier, in: root))

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("k", .command, code: 40, in: window))
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "k", modifiers: .command))
    XCTAssertNil(Self.view(identifier, in: root), "the unchanged Command-S filter drops the edited binding")
    controller.setShortcutSearch("Command-K")
    XCTAssertNotNil(Self.view(identifier, in: root), "the new binding is searchable immediately")
    let title = try XCTUnwrap(model.catalog.first { $0.id == sidebar }).title
    XCTAssertTrue(controller.visibleShortcutTitles.contains(title))

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("\u{7F}", [], code: 51, in: window))
    XCTAssertNil(model.binding(for: sidebar))
    XCTAssertNil(Self.view(identifier, in: root), "clearing removes the row from its old key search")
    controller.setShortcutSearch("Sidebar")
    XCTAssertNotNil(Self.view(identifier, in: root), "an unbound action remains searchable by title")
    XCTAssertEqual(recorder.title, "None")

    controller.setShortcutSearch("Command-S")
    XCTAssertNil(Self.view(identifier, in: root), "a cleared action does not match its default")
    try find(AXID.Settings.control("shortcuts", "resetAll"), in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertNotNil(Self.view(identifier, in: root), "reset refreshes the unchanged key search")
    let reopened = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reopened.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
  }

  /// Moving focus to search must deliver its next key to the text editor, without saving it as a shortcut.
  func testLeavingShortcutRecorderForSearchStopsCapture() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let original = model.binding(for: sidebar)
    let recorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)
    let search = try find(AXID.Settings.shortcutsSearch, in: controller, as: NSSearchField.self)
    recorder.performClick(nil)
    XCTAssertTrue(window.firstResponder === recorder)
    XCTAssertTrue(window.makeFirstResponder(search), "the search field accepts the focus change")
    let textEditor = try XCTUnwrap(search.currentEditor())
    XCTAssertTrue(window.firstResponder === textEditor)
    window.sendEvent(try shortcutEvent("q", [], code: 12, in: window))
    XCTAssertEqual(textEditor.string, "q", "typing reaches the focused search field")
    XCTAssertNil(model.recordingAction)
    XCTAssertEqual(model.binding(for: sidebar), original)
    let reopened = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reopened.binding(for: sidebar), original, "focus changes do not persist a stray key")
  }

  /// Conflict choices leave persisted bindings alone until the user chooses, including reset conflicts.
  func testShortcutConflictChoicesAndResetConflict() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let tab = ShortcutActionID("newTab")
    let recorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("t", .command, code: 17, in: window))
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    let explanation = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertTrue(explanation.stringValue.contains("New Tab"), "the conflict notice names the occupied action")
    let spokenBinding = explanation.accessibilityLabel() ?? explanation.stringValue
    XCTAssertTrue(spokenBinding.contains("Command T") || spokenBinding.contains("⌘T"),
                  "the conflict notice identifies the occupied binding")
    let use = try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self)
    let keep = try find("settings.shortcuts.conflict.keep", in: controller, as: NSButton.self)
    XCTAssertTrue((use.accessibilityLabel() ?? use.title).localizedCaseInsensitiveContains("Use"))
    XCTAssertTrue((keep.accessibilityLabel() ?? keep.title).localizedCaseInsensitiveContains("Keep"))
    XCTAssertTrue(window.firstResponder === keep, "Keep Existing is the initial conflict choice")
    window.sendEvent(try shortcutEvent("\r", [], code: 36, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.conflict.keep", in: try XCTUnwrap(window.contentView)))
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertEqual(model.binding(for: tab), ShortcutBinding(key: "t", modifiers: .command))
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("t", .command, code: 17, in: window))
    window.sendEvent(try shortcutEvent("\u{1B}", [], code: 53, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.conflict.keep", in: try XCTUnwrap(window.contentView)))
    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertEqual(model.binding(for: tab), ShortcutBinding(key: "t", modifiers: .command))
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("t", .command, code: 17, in: window))
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "t", modifiers: .command))
    XCTAssertNil(model.binding(for: tab))

    // Assign the sidebar default to the other action, then reset through the row's menu.
    model.setBinding(ShortcutBinding(key: "s", modifiers: .command), for: tab)
    let reset = try XCTUnwrap(recorder.menu?.item(withTitle: "Reset Shortcut to Default"))
    NSApp.sendAction(try XCTUnwrap(reset.action), to: reset.target, from: reset)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "t", modifiers: .command))
    try find("settings.shortcuts.conflict.keep", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: tab), ShortcutBinding(key: "s", modifiers: .command))
    NSApp.sendAction(try XCTUnwrap(reset.action), to: reset.target, from: reset)
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertNil(model.binding(for: tab))
    let reloaded = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reloaded.binding(for: sidebar), model.binding(for: sidebar))
    XCTAssertNil(reloaded.binding(for: tab))
  }

  /// The warning source is injected: this test never reads or changes system keyboard preferences.
  func testSystemShortcutWarningUsesProvidedConflictInformation() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let system = ShortcutBinding(key: " ", modifiers: .control)
    let controller = make(menu: menu, editor: model, isSystemShortcut: { $0 == system })
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try shortcutEvent(" ", .control, code: 49, in: window))
    let warning = try find("settings.shortcuts.systemConflict", in: controller)
    XCTAssertTrue(warning.accessibilityLabel()?.contains("System shortcuts may take priority") == true)
    try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try shortcutEvent("k", [.control, .option], code: 40, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.systemConflict", in: try XCTUnwrap(window.contentView)),
                 "ordinary bindings have no warning")
  }

  func testAcceptingAppConflictStillShowsSystemShortcutWarning() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let system = ShortcutBinding(key: " ", modifiers: .control)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let tab = ShortcutActionID("newTab")
    model.setBinding(system, for: tab)
    let controller = make(menu: menu, editor: model, isSystemShortcut: { $0 == system })
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let root = try XCTUnwrap(window.contentView)
    let recorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent(" ", .control, code: 49, in: window))
    try find("settings.shortcuts.conflict.keep", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: tab), system)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertNil(Self.view("settings.shortcuts.systemConflict", in: root), "Keep does not assign the candidate")

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent(" ", .control, code: 49, in: window))
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertNil(Self.view("settings.shortcuts.conflict.use", in: root))
    XCTAssertEqual(model.binding(for: sidebar), system)
    XCTAssertNil(model.binding(for: tab))
    let warning = Self.view("settings.shortcuts.systemConflict", in: root)
    XCTAssertNotNil(warning, "accepting an app conflict must also check the system-warning predicate")
    XCTAssertTrue(warning?.accessibilityLabel()?.contains("System shortcuts may take priority") == true)
    let reopened = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reopened.binding(for: sidebar), system)
    XCTAssertNil(reopened.binding(for: tab))

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("k", [.control, .option], code: 40, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.systemConflict", in: root), "an ordinary replacement clears the warning")
  }

  /// Return keeps the default choice; Space activates an explicitly focused Use control.
  func testConflictReturnDefaultAndFocusedUseSpaceActivation() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let root = try XCTUnwrap(window.contentView)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let tab = ShortcutActionID("newTab")
    let recorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)
    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("t", .command, code: 17, in: window))
    let firstUse = try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self)
    XCTAssertTrue(window.makeFirstResponder(firstUse))
    XCTAssertTrue(window.firstResponder === firstUse)
    window.sendEvent(try shortcutEvent("\r", [], code: 36, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.conflict.use", in: root))
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertEqual(model.binding(for: tab), ShortcutBinding(key: "t", modifiers: .command))

    recorder.performClick(nil)
    window.sendEvent(try shortcutEvent("t", .command, code: 17, in: window))
    let use = try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self)
    XCTAssertTrue(window.makeFirstResponder(use))
    XCTAssertTrue(window.firstResponder === use)
    window.sendEvent(try shortcutEvent(" ", [], code: 49, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.conflict.use", in: root))
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "t", modifiers: .command))
    XCTAssertNil(model.binding(for: tab))
    let reopened = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reopened.binding(for: sidebar), ShortcutBinding(key: "t", modifiers: .command))
    XCTAssertNil(reopened.binding(for: tab))
  }

  func testResetAllRestoresMultipleOverridesAndRemovesSavedValues() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let tab = ShortcutActionID("newTab")
    try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try shortcutEvent("k", [.control, .option], code: 40, in: window))
    try find("settings.shortcuts.record.newTab", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try shortcutEvent("\u{7F}", [], code: 51, in: window))
    XCTAssertNotNil(defaults.data(forKey: "shortcutOverrides"))
    let reset = try find(AXID.Settings.control("shortcuts", "resetAll"), in: controller, as: NSButton.self)
    XCTAssertTrue(reset.isEnabled)
    reset.performClick(nil)
    XCTAssertEqual(model.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertEqual(model.binding(for: tab), ShortcutBinding(key: "t", modifiers: .command))
    XCTAssertNil(defaults.object(forKey: "shortcutOverrides"))
    let reloaded = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertTrue(reloaded.overrides.isEmpty)
    XCTAssertEqual(reloaded.binding(for: sidebar), model.binding(for: sidebar))
    XCTAssertEqual(reloaded.binding(for: tab), model.binding(for: tab))
    window.close()
    controller.show(pane: .shortcuts)
    XCTAssertFalse(try find(AXID.Settings.control("shortcuts", "resetAll"), in: controller, as: NSButton.self).isEnabled)
    let reopened = ShortcutEditorModel(catalog: model.catalog, defaults: defaults)
    XCTAssertEqual(reopened.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))
    XCTAssertEqual(reopened.binding(for: tab), ShortcutBinding(key: "t", modifiers: .command))
  }

  func testProtectedMenuConflictExplainsWhyUseIsUnavailable() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    ShortcutCatalog.bind(model: model, to: menu)
    defer { ShortcutCatalog.unbind(from: menu) }
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let id = ShortcutActionID("newTab")
    try find("settings.shortcuts.record.newTab", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertTrue(window.performKeyEquivalent(with: try shortcutEvent("n", .command, code: 45, in: window)))
    let notice = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertEqual(notice.stringValue, "Command N is already used by New Window. This command cannot be changed here; keep the existing shortcut and try another.")
    let use = try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self)
    XCTAssertFalse(use.isEnabled)
    try find("settings.shortcuts.conflict.keep", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(model.binding(for: id), ShortcutBinding(key: "t", modifiers: .command))
    XCTAssertEqual(controller.selectedPane, .shortcuts)
  }

  /// Component coverage for SettingsWindow's key-equivalent boundary. Actual app dispatch lives in ShortcutWiringTests.
  func testRecorderBeatsSettingsWindowKeyEquivalentsUntilRecordingEnds() throws {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    let controller = make(menu: menu, editor: model)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let id = ShortcutActionID("toggleSidebarVisibility")
    for (key, code) in [("w", UInt16(13)), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
                        ("5", 23), ("6", 22), ("7", 26)] {
      try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self).performClick(nil)
      XCTAssertTrue(window.performKeyEquivalent(with: try shortcutEvent(key, .command, code: code, in: window)), key)
      XCTAssertTrue(window.isVisible, key)
      XCTAssertEqual(controller.selectedPane, .shortcuts, key)
      // A conflict is also capture: it must refer to the attempted binding, not route to Settings.
      if !model.conflictingActions.isEmpty {
        try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
      }
      XCTAssertEqual(model.binding(for: id), ShortcutBinding(key: key, modifiers: .command), key)
    }
    XCTAssertTrue(window.performKeyEquivalent(with: try shortcutEvent("1", .command, code: 18, in: window)))
    XCTAssertEqual(controller.selectedPane, .general)
    XCTAssertTrue(window.performKeyEquivalent(with: try shortcutEvent("w", .command, code: 13, in: window)))
    XCTAssertFalse(window.isVisible)
  }

  private func shortcutEvent(_ text: String, _ flags: NSEvent.ModifierFlags, code: UInt16,
                             in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: text,
                                   charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
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

  /// Without the archive rows' services the two thresholds stay planned at their defaults.
  func testArchiveRowsArePlannedWithoutTheirServices() throws {
    let controller = make()
    controller.show(pane: .spaces)
    for (name, title) in [("archiveTodayAfter", "12 hours"), ("archiveLittleArktAfter", "6 hours")] {
      let popUp = try find(AXID.Settings.control("spaces", name), in: controller, as: SettingsPopUpButton.self)
      XCTAssertFalse(popUp.isEnabled, name)
      XCTAssertEqual(popUp.selectedTitle, title, name)
      XCTAssertTrue(try XCTUnwrap(popUp.enclosingSettingsRow).isPlanned, name)
    }
  }

  /// #448: "Archive Today tabs after" and "Archive Little Arkt windows after" are real pop-ups with all seven
  /// durations; each shows its stored value and writes a choice back at once.
  func testArchiveRowsReadAndWriteTheirThresholds() throws {
    var tabs = "24 hours"
    var littleArkt = "6 hours"
    var writes: [String] = []
    var env = SettingsServices()
    env.archiveRows = SettingsArchiveRows(
      tabsAfter: { tabs },
      setTabsAfter: { tabs = $0; writes.append("tabs \($0)") },
      littleArktAfter: { littleArkt },
      setLittleArktAfter: { littleArkt = $0; writes.append("little \($0)") })
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: env)
    controllers.append(controller)
    controller.show(pane: .spaces)

    let today = try find(AXID.Settings.control("spaces", "archiveTodayAfter"), in: controller,
                         as: SettingsPopUpButton.self)
    let little = try find(AXID.Settings.control("spaces", "archiveLittleArktAfter"), in: controller,
                          as: SettingsPopUpButton.self)
    let options = ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"]
    for popUp in [today, little] {
      XCTAssertTrue(popUp.isEnabled)
      XCTAssertEqual(popUp.items, options)
      XCTAssertEqual(popUp.alphaValue, 1, accuracy: 0.001)
      XCTAssertFalse(try XCTUnwrap(popUp.enclosingSettingsRow).isPlanned)
    }
    XCTAssertEqual(today.selectedTitle, "24 hours")
    XCTAssertEqual(little.selectedTitle, "6 hours")
    XCTAssertEqual(today.accessibilityLabel(), "Archive Today tabs after")
    XCTAssertEqual(little.accessibilityLabel(), "Archive Little Arkt windows after")
    XCTAssertFalse(try XCTUnwrap(today.enclosingSettingsRow).captionText.contains("Not available yet."))

    today.select("7 days")
    little.select("Never")
    today.select("7 days")                                   // the current title again: no write

    XCTAssertEqual(writes, ["tabs 7 days", "little Never"])
    XCTAssertEqual(today.selectedTitle, "7 days")
    XCTAssertEqual(little.selectedTitle, "Never")
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
    XCTAssertTrue(reset.isEnabled, "Reset all settings is built (#617)")
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
