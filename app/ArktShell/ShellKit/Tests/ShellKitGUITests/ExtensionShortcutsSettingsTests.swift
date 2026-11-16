import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Settings > Shortcuts > Extension Shortcuts (#597; design/extensions `shortcuts`, `shortcuts-conflict`) in the real
/// Settings window, with InMemoryEngine's extension commands: the rows, the recorder and its suspension of the
/// engine's extension shortcuts (#954), the conflict notice in both directions, search and the worst case.
@MainActor
final class ExtensionShortcutsSettingsTests: XCTestCase {
  private var controllers: [SettingsWindowController] = []
  private var suiteName = ""
  private var defaults = UserDefaults.standard

  private let open = ExtensionCommandID(extensionID: "reader", name: "_execute_action")
  private let read = ExtensionCommandID(extensionID: "reader", name: "toggle-reading")
  private let clip = ExtensionCommandID(extensionID: "clips", name: "clip-page")
  private let list = ExtensionCommandID(extensionID: "clips", name: "open-list")

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "dev.arkt.tests.extensionShortcuts.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() async throws {
    controllers.forEach { $0.window?.close() }
    controllers = []
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  private func shortcut(_ key: ExtensionShortcut.Key, _ modifiers: ExtensionShortcut.Modifiers) -> ExtensionShortcut {
    ExtensionShortcut(key: key, modifiers: modifiers)
  }

  /// The design's two extensions: Quiet Reader (Opt-Shift-Q, Cmd-Shift-E) and Tidy Clips (Ctrl-Shift-K in All Apps,
  /// and an unset command).
  private func designEngine() -> InMemoryEngine {
    let engine = InMemoryEngine()
    engine.setExtensionCommands([
      ExtensionCommand(id: open, extensionName: "Quiet Reader", description: "Open Quiet Reader",
                       shortcut: shortcut(.letter(.q), [.option, .shift])),
      ExtensionCommand(id: read, extensionName: "Quiet Reader", description: "Toggle reading view",
                       shortcut: shortcut(.letter(.e), [.command, .shift])),
      ExtensionCommand(id: clip, extensionName: "Tidy Clips", description: "Clip this page",
                       shortcut: shortcut(.letter(.k), [.control, .shift]), scope: .global),
      ExtensionCommand(id: list, extensionName: "Tidy Clips", description: "Open clip list"),
    ])
    return engine
  }

  /// The app menu with the editor bound to it, as the app runs them, and an engine with extensions.
  private func make(engine: InMemoryEngine?, appearance: NSAppearance.Name? = nil)
    -> (SettingsWindowController, ShortcutEditorModel) {
    let menu = MainMenu.make(commands: AppCommands()).menu
    let editor = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    ShortcutCatalog.bind(model: editor, to: menu)
    var services = SettingsServices()
    services.shortcutsMenu = { menu }
    services.shortcutEditor = editor
    services.isSystemShortcut = { _ in false }
    services.extensions = engine
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    if let appearance { controller.window?.appearance = NSAppearance(named: appearance) }
    controllers.append(controller)
    return (controller, editor)
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

  private func recorder(_ id: ExtensionCommandID, in controller: SettingsWindowController) throws -> NSButton {
    try find("settings.shortcuts.extension.record.\(id.extensionID).\(id.name)", in: controller, as: NSButton.self)
  }

  private func key(_ text: String, _ flags: NSEvent.ModifierFlags, code: UInt16, in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: text,
                                   charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
  }

  private func command(_ engine: InMemoryEngine, _ id: ExtensionCommandID) -> ExtensionCommand? {
    engine.extensionCommands.first { $0.id == id }
  }

  // MARK: - Rows

  func testSectionsShowTheEnginesCommandsAndOnlyWithAnEngine() throws {
    let (plain, _) = make(engine: nil)
    plain.show(pane: .shortcuts)
    let plainRoot = try XCTUnwrap(plain.window?.contentView)
    XCTAssertNil(Self.view("settings.shortcuts.extension.cycle", in: plainRoot))
    XCTAssertTrue(plain.visibleExtensionShortcutTitles.isEmpty)
    plain.window?.close()

    let (controller, _) = make(engine: designEngine())
    controller.show(pane: .shortcuts)
    let cycle = try find("settings.shortcuts.extension.cycle", in: controller)
    XCTAssertEqual(cycle.accessibilityLabel(), "Cycle through pinned extensions, Command E")
    XCTAssertEqual(controller.visibleExtensionShortcutTitles,
                   ["Open Quiet Reader", "Toggle reading view", "Clip this page", "Open clip list"])
    _ = try find("settings.shortcuts.extension.group.reader", in: controller)
    _ = try find("settings.shortcuts.extension.group.clips", in: controller)
    XCTAssertEqual(try recorder(open, in: controller).title, "\u{2325}\u{21E7}Q")
    XCTAssertEqual(try recorder(read, in: controller).accessibilityValue() as? String, "Shift Command E")
    let unset = try find("settings.shortcuts.extension.set.clips.open-list", in: controller, as: ArchivePillButton.self)
    XCTAssertNotNil(unset.superview, "an unset command shows Set Shortcut")
    let scope = try find("settings.shortcuts.extension.scope.clips.clip-page", in: controller,
                         as: SettingsPopUpButton.self)
    XCTAssertEqual(scope.selectedTitle, "All Apps")
    XCTAssertEqual(scope.items, ["In Arkt", "All Apps"])
  }

  // MARK: - Recording and suspension

  func testRecorderSuspendsExtensionShortcutsOnlyWhileItListens() throws {
    let engine = designEngine()
    let (controller, editor) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)

    // Esc cancels.
    try recorder(read, in: controller).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended, "suspended while listening")
    XCTAssertEqual(try recorder(read, in: controller).title, "Press new shortcut")
    window.sendEvent(try key("\u{1B}", [], code: 53, in: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertTrue(window.isVisible, "Escape cancels recording, not Settings")
    XCTAssertEqual(command(engine, read)?.shortcut, shortcut(.letter(.e), [.command, .shift]))

    // A commit.
    try find("settings.shortcuts.extension.set.clips.open-list", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    window.sendEvent(try key("j", .control, code: 38, in: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertEqual(command(engine, list)?.shortcut, shortcut(.letter(.j), .control))
    XCTAssertEqual(try recorder(list, in: controller).title, "\u{2303}J")

    // Delete clears.
    try recorder(list, in: controller).performClick(nil)
    window.sendEvent(try key("\u{7F}", [], code: 51, in: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertNil(command(engine, list)?.shortcut)
    XCTAssertNotNil(try find("settings.shortcuts.extension.set.clips.open-list", in: controller).superview)

    // A refused key keeps listening.
    try recorder(read, in: controller).performClick(nil)
    window.sendEvent(try key("q", [.option, .shift], code: 12, in: window))
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertNotNil(try? find("settings.shortcuts.rejected", in: controller))

    // Focus loss: a click on the search field.
    let search = try find(AXID.Settings.shortcutsSearch, in: controller, as: NSSearchField.self)
    XCTAssertTrue(window.makeFirstResponder(search))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended, "focus left the recorder")
    XCTAssertNil(controller.extensionShortcuts?.recordingCommand)

    // Settings loses key status.
    try recorder(read, in: controller).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)

    // A pane switch.
    try recorder(read, in: controller).performClick(nil)
    controller.select(.general, animated: false)
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    controller.select(.shortcuts, animated: false)

    // Tab moves on.
    try recorder(read, in: controller).performClick(nil)
    window.sendEvent(try key("\t", [], code: 48, in: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)

    // The app recorder suspends them too.
    try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertNotNil(editor.recordingAction)
    window.sendEvent(try key("\u{1B}", [], code: 53, in: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)

    // The window closes.
    try recorder(read, in: controller).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    window.close()
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended, "closing Settings resumes them")
    XCTAssertEqual(command(engine, read)?.shortcut, shortcut(.letter(.e), [.command, .shift]))
  }

  func testRemovingTheExtensionWhileRecordingStopsTheRecorder() throws {
    let engine = designEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    try recorder(clip, in: controller).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    engine.setExtensionCommands(engine.extensionCommands.filter { $0.id.extensionID != "clips" })
    waitUntil("the removal reaches Settings") { controller.extensionShortcuts?.recordingCommand == nil }
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertEqual(controller.visibleExtensionShortcutTitles, ["Open Quiet Reader", "Toggle reading view"])
    XCTAssertNil(Self.view("settings.shortcuts.extension.group.clips", in: try XCTUnwrap(controller.window?.contentView)))
  }

  /// The pane outlives a closed window; reopening Settings shows the commands the engine has now.
  func testReopeningSettingsShowsCommandsChangedWhileItWasClosed() throws {
    let engine = designEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    controller.window?.close()
    engine.setExtensionCommands(engine.extensionCommands.filter { $0.id.extensionID == "clips" } + [
      ExtensionCommand(id: ExtensionCommandID(extensionID: "notes", name: "jot"), extensionName: "Margin Notes",
                       description: "Jot a note"),
    ])
    controller.show(pane: .shortcuts)
    let root = try XCTUnwrap(controller.window?.contentView)
    XCTAssertNil(Self.view("settings.shortcuts.extension.group.reader", in: root), "a removed extension's group goes")
    XCTAssertNotNil(Self.view("settings.shortcuts.extension.group.notes", in: root), "a new extension's group shows")
    XCTAssertNotNil(Self.view("settings.shortcuts.extension.set.notes.jot", in: root))
  }

  /// Without the app shortcut editor (no menu binding), every exit still resumes the engine's shortcuts.
  func testSuspensionEndsWithoutTheAppShortcutEditor() throws {
    let engine = designEngine()
    var services = SettingsServices()
    let menu = MainMenu.make(commands: AppCommands()).menu
    services.shortcutsMenu = { menu }
    services.isSystemShortcut = { _ in false }
    services.extensions = engine
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    controllers.append(controller)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    try recorder(read, in: controller).performClick(nil)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended)
    controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    try recorder(read, in: controller).performClick(nil)
    controller.select(.general, animated: false)
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    controller.select(.shortcuts, animated: false)
    try recorder(read, in: controller).performClick(nil)
    window.close()
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
  }

  // MARK: - Conflicts

  func testAnAppShortcutConflictKeepsOnReturnAndUseMovesIt() throws {
    let engine = designEngine()
    let (controller, editor) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let newTab = ShortcutActionID("newTab")
    try recorder(read, in: controller).performClick(nil)
    window.sendEvent(try key("t", .command, code: 17, in: window))
    let message = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertEqual(message.stringValue,
                   "\u{2318}T is already used by \u{201C}New Tab\u{201D}. Using it here removes it there.")
    let keep = try find("settings.shortcuts.conflict.keep", in: controller, as: NSButton.self)
    let use = try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self)
    XCTAssertEqual(use.title, "Use \u{2318}T")
    XCTAssertTrue(window.firstResponder === keep, "Keep Existing is the default (#590)")
    XCTAssertTrue(window.defaultButtonCell === keep.cell)
    XCTAssertTrue(engine.isExtensionShortcutHandlingSuspended, "still listening while the notice asks")
    window.sendEvent(try key("\r", [], code: 36, in: window))
    XCTAssertNil(Self.view("settings.shortcuts.conflict.keep", in: try XCTUnwrap(window.contentView)))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
    XCTAssertEqual(command(engine, read)?.shortcut, shortcut(.letter(.e), [.command, .shift]))
    XCTAssertEqual(editor.binding(for: newTab), ShortcutBinding(key: "t", modifiers: .command))

    try recorder(read, in: controller).performClick(nil)
    window.sendEvent(try key("t", .command, code: 17, in: window))
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(command(engine, read)?.shortcut, shortcut(.letter(.t), .command))
    XCTAssertNil(editor.binding(for: newTab), "Use removes it from New Tab")
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
  }

  func testAShortcutArktKeepsCannotBeUsed() throws {
    let engine = designEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    try recorder(read, in: controller).performClick(nil)
    window.sendEvent(try key("T", [.command, .shift], code: 17, in: window))
    let message = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertTrue(message.stringValue.hasPrefix("\u{21E7}\u{2318}T is already used by \u{201C}Reopen Closed Tab\u{201D}."),
                  message.stringValue)
    XCTAssertFalse(try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).isEnabled)
    window.sendEvent(try key("\u{1B}", [], code: 53, in: window))
    XCTAssertEqual(command(engine, read)?.shortcut, shortcut(.letter(.e), [.command, .shift]))
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
  }

  func testAnotherExtensionCommandConflictsAndUseReplacesIt() throws {
    let engine = designEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    try find("settings.shortcuts.extension.set.clips.open-list", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try key("E", [.command, .shift], code: 14, in: window))
    let message = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertEqual(message.stringValue, "\u{21E7}\u{2318}E is already used by "
                   + "\u{201C}Toggle reading view (Quiet Reader)\u{201D}. Using it here removes it there.")
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(command(engine, list)?.shortcut, shortcut(.letter(.e), [.command, .shift]))
    XCTAssertNil(command(engine, read)?.shortcut)
  }

  /// The #828 review note: an extension command is a conflict owner for the app shortcut editor too.
  func testRecordingAnAppShortcutAnExtensionHoldsNamesTheCommand() throws {
    let engine = designEngine()
    let (controller, editor) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let sidebar = ShortcutActionID("toggleSidebarVisibility")
    let appRecorder = try find("settings.shortcuts.record.toggleSidebarVisibility", in: controller, as: NSButton.self)
    appRecorder.performClick(nil)
    window.sendEvent(try key("E", [.command, .shift], code: 14, in: window))
    let message = try find("settings.shortcuts.conflict.message", in: controller, as: NSTextField.self)
    XCTAssertTrue(message.stringValue.contains("Toggle reading view (Quiet Reader)"), message.stringValue)
    XCTAssertTrue(try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).isEnabled)
    window.sendEvent(try key("\r", [], code: 36, in: window))
    XCTAssertEqual(editor.binding(for: sidebar), ShortcutBinding(key: "s", modifiers: .command))

    appRecorder.performClick(nil)
    window.sendEvent(try key("E", [.command, .shift], code: 14, in: window))
    try find("settings.shortcuts.conflict.use", in: controller, as: NSButton.self).performClick(nil)
    XCTAssertEqual(editor.binding(for: sidebar), ShortcutBinding(key: "e", modifiers: [.command, .shift]))
    XCTAssertNil(command(engine, read)?.shortcut, "Use takes it from the extension")
    XCTAssertFalse(engine.isExtensionShortcutHandlingSuspended)
  }

  // MARK: - Scope

  func testScopeOfAnUnsetCommandAppliesWithItsShortcut() throws {
    let engine = designEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    let window = try XCTUnwrap(controller.window)
    let scope = try find("settings.shortcuts.extension.scope.clips.open-list", in: controller,
                         as: SettingsPopUpButton.self)
    scope.select("All Apps")
    XCTAssertEqual(command(engine, list)?.scope, .inApp)
    try find("settings.shortcuts.extension.set.clips.open-list", in: controller, as: NSButton.self).performClick(nil)
    window.sendEvent(try key("j", .control, code: 38, in: window))
    XCTAssertEqual(command(engine, list)?.scope, .global)
    engine.heldGlobalShortcuts = [shortcut(.letter(.e), [.command, .shift])]
    try find("settings.shortcuts.extension.scope.reader.toggle-reading", in: controller,
             as: SettingsPopUpButton.self).select("All Apps")
    XCTAssertEqual(try find("settings.shortcuts.extension.notice", in: controller, as: NSTextField.self).stringValue,
                   "This shortcut couldn\u{2019}t be set to work in All Apps.")
    XCTAssertEqual(command(engine, read)?.scope, .inApp)
    XCTAssertEqual(try find("settings.shortcuts.extension.scope.reader.toggle-reading", in: controller,
                            as: SettingsPopUpButton.self).selectedTitle, "In Arkt", "a refused scope goes back")
  }

  // MARK: - Search

  func testSearchFindsAnExtensionByNameAndACommandByShortcut() throws {
    let (controller, _) = make(engine: designEngine())
    controller.show(pane: .shortcuts)
    controller.setShortcutSearch("Tidy")
    XCTAssertEqual(controller.visibleExtensionShortcutTitles, ["Clip this page", "Open clip list"])
    controller.setShortcutSearch("Option Shift Q")
    XCTAssertEqual(controller.visibleExtensionShortcutTitles, ["Open Quiet Reader"])
    controller.setShortcutSearch("Command-E")
    XCTAssertTrue(controller.visibleExtensionShortcutTitles.isEmpty)
    _ = try find("settings.shortcuts.extension.cycle", in: controller)
    controller.setShortcutSearch("pinned")
    _ = try find("settings.shortcuts.extension.cycle", in: controller)
  }

  // MARK: - Worst case

  /// 20 extensions with 4 commands each, long descriptions and unset commands: every row is there and no title runs
  /// under its controls.
  func testTwentyExtensionsWithFourCommandsLongDescriptionsAndUnsetCommands() throws {
    let engine = worstCaseEngine()
    let (controller, _) = make(engine: engine)
    controller.show(pane: .shortcuts)
    XCTAssertEqual(controller.visibleExtensionShortcutTitles.count, 80)
    let root = try XCTUnwrap(controller.window?.contentView)
    root.layoutSubtreeIfNeeded()
    for ext in 0..<20 {
      for index in 0..<4 {
        let key = "ext\(ext).cmd\(index)"
        let first: NSView = index == 0
          ? try find("settings.shortcuts.extension.record.\(key)", in: controller)
          : try find("settings.shortcuts.extension.set.\(key)", in: controller)
        let row = try XCTUnwrap(first.superview as? SettingsRowView, key)
        row.layoutSubtreeIfNeeded()
        let title = try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first, key)
        XCTAssertLessThanOrEqual(title.frame.maxX, first.frame.minX, "\(key): the title stays clear of its controls")
        XCTAssertGreaterThan(title.frame.height, 0, key)
      }
    }
  }

  /// 20 extensions with long names and 4 commands each: a set shortcut, a long description, and two unset commands.
  private func worstCaseEngine() -> InMemoryEngine {
    let engine = InMemoryEngine()
    let long = String(repeating: "Switches the page to a calm layout that keeps going ", count: 4)
    engine.setExtensionCommands((0..<20).flatMap { ext in
      (0..<4).map { index in
        ExtensionCommand(id: ExtensionCommandID(extensionID: "ext\(ext)", name: "cmd\(index)"),
                         extensionName: "Synthetic Extension With A Long Name Number \(ext)",
                         description: index == 1 ? long : "Command \(index)",
                         shortcut: index == 0 ? shortcut(.digit(ExtensionShortcut.Digit(rawValue: ext % 10)!),
                                                         ext < 10 ? [.control, .shift] : [.control, .option]) : nil)
      }
    })
    return engine
  }

  // MARK: - Screenshots

  /// Opt-in: the new section in light and dark, with the conflict notice, for the pull request.
  func testExtensionShortcutsShots() throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_EXTENSION_SHORTCUTS_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_EXTENSION_SHORTCUTS_SHOTS_DIR to export the Extension Shortcuts screenshots")
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for dark in [false, true] {
      for state in ["", "-recording", "-conflict", "-worst-case"] {
        let engine = state == "-worst-case" ? worstCaseEngine() : designEngine()
        let (controller, _) = make(engine: engine, appearance: dark ? .darkAqua : .aqua)
        controller.show(pane: .shortcuts)
        let window = try XCTUnwrap(controller.window)
        // One size on every screen, so the local and CI shots match.
        window.setContentSize(NSSize(width: SettingsMetrics.windowWidth, height: 640))
        window.contentView?.layoutSubtreeIfNeeded()
        let section = try find("settings.shortcuts.extension.cycle", in: controller)
        if let scroll = section.enclosingScrollView, let pane = scroll.documentView {
          // The pane container is flipped; the clip view starts at -chromeHeight (the content inset).
          let top = section.convert(section.bounds, to: pane).minY - SettingsMetrics.chromeHeight - 60
          // Clamped to the document, so a short window (a CI screen) does not scroll past the pane's end.
          let clip = scroll.contentView
          let target = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: top), size: clip.bounds.size))
          clip.scroll(to: target.origin)
          scroll.reflectScrolledClipView(scroll.contentView)
        }
        if state == "-recording" { try recorder(read, in: controller).performClick(nil) }
        if state == "-conflict" {
          try recorder(read, in: controller).performClick(nil)
          window.sendEvent(try key("t", .command, code: 17, in: window))
        }
        window.displayIfNeeded()
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let name = "extension-shortcuts\(state)-\(dark ? "dark" : "light").png"
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        window.close()
      }
    }
  }
}
