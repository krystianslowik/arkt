import AppKit
import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ShellUI

/// Settings > Shortcuts > Extension Shortcuts (#597, design/extensions `shortcuts`, `shortcuts-conflict`): the
/// extension commands as rows, the recorder's key rules, conflicts with Arkt's own shortcuts and with other extension
/// commands, scope, search, and the reverse direction in the app shortcut editor.
@MainActor
struct ExtensionShortcutsModelTests {
  private final class Suite {
    let name = "dev.arkt.tests.extensionShortcuts.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    deinit { UserDefaults().removePersistentDomain(forName: name) }
  }

  private let newTab = ShortcutActionID("newTab")
  private let read = ExtensionCommandID(extensionID: "reader", name: "toggle-reading")
  private let open = ExtensionCommandID(extensionID: "reader", name: "_execute_action")
  private let clip = ExtensionCommandID(extensionID: "clips", name: "clip-page")
  private let list = ExtensionCommandID(extensionID: "clips", name: "open-list")

  private func shortcut(_ key: ExtensionShortcut.Key, _ modifiers: ExtensionShortcut.Modifiers) -> ExtensionShortcut {
    ExtensionShortcut(key: key, modifiers: modifiers)
  }

  /// Two extensions as the design draws them: Quiet Reader (Opt-Shift-Q, Cmd-Shift-E) and Tidy Clips (Ctrl-Shift-K
  /// in All Apps, and an unset command).
  private func engine() -> InMemoryEngine {
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

  private func editor(_ suite: Suite) -> ShortcutEditorModel {
    ShortcutEditorModel(catalog: [ShortcutDefinition(id: newTab, title: "New Tab",
                                                     defaultBinding: ShortcutBinding(key: "t", modifiers: .command))],
                        defaults: suite.defaults)
  }

  /// Reopen Closed Tab stands in for a main-menu item the editor cannot change.
  private func model(_ engine: InMemoryEngine, editor: ShortcutEditorModel? = nil) -> ExtensionShortcutsModel {
    ExtensionShortcutsModel(engine: engine, editor: editor) { binding in
      binding == ShortcutBinding(key: "t", modifiers: [.command, .shift]) ? ["Reopen Closed Tab"] : []
    }
  }

  private func event(_ characters: String, keyCode: UInt16,
                     modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                  windowNumber: 0, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
  }

  private func command(_ engine: InMemoryEngine, _ id: ExtensionCommandID) -> ExtensionCommand? {
    engine.extensionCommands.first { $0.id == id }
  }

  // MARK: - Rows

  @Test func groupsFollowTheEngineOrderOneGroupPerExtension() {
    let model = model(engine())
    #expect(model.groups.map(\.name) == ["Quiet Reader", "Tidy Clips"])
    #expect(model.groups.map { $0.commands.map(\.id) } == [[open, read], [clip, list]])
  }

  @Test func twentyExtensionsWithFourCommandsEachAndLongOrMissingValues() {
    let engine = InMemoryEngine()
    let long = String(repeating: "A very long command description that keeps going ", count: 6)
    engine.setExtensionCommands((0..<20).flatMap { ext in
      (0..<4).map { index in
        ExtensionCommand(id: ExtensionCommandID(extensionID: "ext\(ext)", name: "cmd\(index)"),
                         extensionName: "Extension \(ext)", description: index == 1 ? long : "",
                         shortcut: index == 0 ? shortcut(.digit(digit(ext)), [.control, .shift]) : nil)
      }
    })
    let model = model(engine)
    #expect(model.groups.count == 20)
    #expect(model.groups.allSatisfy { $0.commands.count == 4 })
    #expect(model.groups[3].commands[2].shortcut == nil)
    #expect(ExtensionShortcutsModel.title(of: model.groups[0].commands[2]) == "cmd2",
            "a command without a description shows its name")
    #expect(ExtensionShortcutsModel.title(of: model.groups[0].commands[1]) == long)
  }

  private func digit(_ value: Int) -> ExtensionShortcut.Digit { ExtensionShortcut.Digit(rawValue: value % 10)! }

  @Test func everyKeyHasKeycapsAndASpokenName() {
    let cases: [(ExtensionShortcut, [String], String)] = [
      (shortcut(.letter(.q), [.option, .shift]), ["\u{2325}", "\u{21E7}", "Q"], "Option Shift Q"),
      (shortcut(.letter(.k), [.control, .shift]), ["\u{2303}", "\u{21E7}", "K"], "Control Shift K"),
      (shortcut(.digit(.two), [.command, .shift]), ["\u{21E7}", "\u{2318}", "2"], "Shift Command 2"),
      (shortcut(.comma, .command), ["\u{2318}", ","], "Command ,"),
      (shortcut(.period, .command), ["\u{2318}", "."], "Command ."),
      (shortcut(.up, .command), ["\u{2318}", "\u{2191}"], "Command Up Arrow"),
      (shortcut(.down, .command), ["\u{2318}", "\u{2193}"], "Command Down Arrow"),
      (shortcut(.left, .command), ["\u{2318}", "\u{2190}"], "Command Left Arrow"),
      (shortcut(.right, .command), ["\u{2318}", "\u{2192}"], "Command Right Arrow"),
      (shortcut(.home, .command), ["\u{2318}", "\u{2196}"], "Command Home"),
      (shortcut(.end, .command), ["\u{2318}", "\u{2198}"], "Command End"),
      (shortcut(.pageUp, .command), ["\u{2318}", "\u{21DE}"], "Command Page Up"),
      (shortcut(.pageDown, .command), ["\u{2318}", "\u{21DF}"], "Command Page Down"),
      (shortcut(.space, .control), ["\u{2303}", "Space"], "Control Space"),
      (shortcut(.tab, .control), ["\u{2303}", "\u{21E5}"], "Control Tab"),
      (shortcut(.insert, .command), ["\u{2318}", "Insert"], "Command Insert"),
      (shortcut(.delete, .command), ["\u{2318}", "\u{2326}"], "Command Forward Delete"),
      (shortcut(.mediaPlayPause, []), ["Play/Pause"], "Play/Pause"),
      (shortcut(.mediaNextTrack, []), ["Next Track"], "Next Track"),
      (shortcut(.mediaPreviousTrack, []), ["Previous Track"], "Previous Track"),
      (shortcut(.mediaStop, []), ["Stop"], "Stop"),
    ]
    for (value, keys, spoken) in cases {
      let shown = ExtensionShortcutsModel.display(value)
      #expect(shown.keys == keys, "\(spoken)")
      #expect(shown.spoken == spoken)
    }
  }

  // MARK: - Recording

  @Test func recordingSetsTheShortcutInTheCommandsScope() throws {
    let engine = engine()
    let model = model(engine)
    model.begin(list)
    #expect(model.phase == .listening(list))
    model.record(event: try event("j", keyCode: 38, modifiers: [.command, .shift]))
    #expect(model.phase == .idle)
    #expect(command(engine, list)?.shortcut == shortcut(.letter(.j), [.command, .shift]))
    #expect(command(engine, list)?.scope == .inApp)
  }

  @Test func escapeCancelsAndDeleteClears() throws {
    let engine = engine()
    let model = model(engine)
    model.begin(read)
    model.record(event: try event("\u{1b}", keyCode: 53))
    #expect(model.phase == .idle)
    #expect(command(engine, read)?.shortcut == shortcut(.letter(.e), [.command, .shift]))
    model.begin(read)
    model.record(event: try event("\u{7f}", keyCode: 51))
    #expect(model.phase == .idle)
    #expect(command(engine, read)?.shortcut == nil)
    model.begin(clip)
    model.record(event: try event(String(UnicodeScalar(NSDeleteFunctionKey)!), keyCode: 117))
    #expect(command(engine, clip)?.shortcut == nil, "Forward Delete clears too")
  }

  /// The #828 key rules, and the keys `chrome.commands` can name: a refused key leaves the recorder listening.
  @Test func refusedKeysKeepListeningWithAReason() throws {
    let engine = engine()
    let model = model(engine)
    model.begin(list)
    let cases: [(String, UInt16, NSEvent.ModifierFlags, ShortcutEditorModel.Rejection)] = [
      ("q", 12, [.option, .shift], .needsCommandOrControl),
      ("j", 38, [], .needsCommandOrControl),
      ("\r", 36, .command, .confirmOrFocusKey),
      ("\t", 48, .control, .confirmOrFocusKey),
      (String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123, .command, .textEditing),
      ("a", 0, .control, .textEditing),
      ("k", 40, [.command, .option], .optionWithCommandOrControl),
      ("k", 40, [.control, .option], .optionWithCommandOrControl),
      ("-", 27, .command, .notAnExtensionKey),
      (String(UnicodeScalar(NSF5FunctionKey)!), 96, [], .notAnExtensionKey),
    ]
    for (text, code, flags, reason) in cases {
      model.record(event: try event(text, keyCode: code, modifiers: flags))
      #expect(model.rejection == reason, "\(text) \(flags)")
      #expect(model.phase == .listening(list))
    }
    #expect(command(engine, list)?.shortcut == nil)
    model.record(event: try event("j", keyCode: 38, modifiers: .control))
    #expect(model.rejection == nil)
    #expect(command(engine, list)?.shortcut == shortcut(.letter(.j), .control))
  }

  /// A letter is the one the layout prints on the key; other keys go by key code, so AZERTY's digit row records
  /// digits.
  @Test func lettersByCharacterOtherKeysByKeyCode() throws {
    #expect(ExtensionShortcutsModel.key(keyCode: 13, unmodified: "z") == .letter(.z))
    #expect(ExtensionShortcutsModel.key(keyCode: 18, unmodified: "&") == .digit(.one))
    #expect(ExtensionShortcutsModel.key(keyCode: 0x7E, unmodified: nil) == .up)
    #expect(ExtensionShortcutsModel.key(keyCode: 27, unmodified: "-") == nil)
  }

  // MARK: - Conflicts

  @Test func anEditableAppShortcutConflictsAndUseMovesIt() throws {
    let suite = try Suite()
    let editor = editor(suite)
    let engine = engine()
    let model = model(engine, editor: editor)
    model.begin(list)
    model.record(event: try event("t", keyCode: 17, modifiers: .command))
    #expect(model.phase == .conflict(list, shortcut(.letter(.t), .command),
                                     owners: [.appAction(newTab, title: "New Tab")]))
    #expect(command(engine, list)?.shortcut == nil, "nothing changes until the user chooses")
    model.keepExisting()
    #expect(model.phase == .idle)
    #expect(editor.binding(for: newTab) == ShortcutBinding(key: "t", modifiers: .command))
    #expect(command(engine, list)?.shortcut == nil)

    model.begin(list)
    model.record(event: try event("t", keyCode: 17, modifiers: .command))
    model.useRecorded()
    #expect(model.phase == .idle)
    #expect(editor.binding(for: newTab) == nil, "Use removes it there")
    #expect(command(engine, list)?.shortcut == shortcut(.letter(.t), .command))
  }

  @Test func aShortcutArktKeepsConflictsAndUseIsUnavailable() throws {
    let engine = engine()
    let model = model(engine)
    model.begin(list)
    model.record(event: try event("T", keyCode: 17, modifiers: [.command, .shift]))
    #expect(model.phase == .conflict(list, shortcut(.letter(.t), [.command, .shift]),
                                     owners: [.arkt(title: "Reopen Closed Tab")]))
    #expect(model.canUse == false)
    model.useRecorded()
    #expect(command(engine, list)?.shortcut == nil)
    #expect(model.phase != .idle, "the notice stays until Keep Existing")
  }

  /// Ctrl-Tab and Ctrl-Shift-Tab are the window's own keys (`ReservedKeys`, the tab switcher), outside the main menu.
  /// The recorder refuses Tab already; a shortcut an extension brings with it counts them as Arkt's.
  @Test func theTabSwitcherKeysAreArkts() {
    let model = model(engine())
    #expect(model.owners(of: shortcut(.tab, .control), excluding: list) == [.arkt(title: "Tab Switcher")])
    #expect(model.owners(of: shortcut(.tab, [.control, .shift]), excluding: list)
            == [.arkt(title: "Tab Switcher (previous tab)")])
    #expect(model.owners(of: shortcut(.tab, .command), excluding: list).isEmpty)
  }

  @Test func anotherExtensionCommandConflictsAndUseReplacesIt() throws {
    let engine = engine()
    let model = model(engine)
    model.begin(list)
    model.record(event: try event("E", keyCode: 14, modifiers: [.command, .shift]))
    #expect(model.phase == .conflict(list, shortcut(.letter(.e), [.command, .shift]),
                                     owners: [.extensionCommand(read, title: "Toggle reading view (Quiet Reader)")]))
    model.useRecorded()
    #expect(command(engine, list)?.shortcut == shortcut(.letter(.e), [.command, .shift]))
    #expect(command(engine, read)?.shortcut == nil)
  }

  /// The app recorder stores what the key types with Shift ("@" for Shift-2 on a US layout) and a menu item may hold
  /// either form; an extension holds the unshifted key. Both forms conflict, in both directions.
  @Test func shiftedDigitsAndPunctuationConflictInBothForms() throws {
    let suite = try Suite()
    let editor = ShortcutEditorModel(catalog: [
      ShortcutDefinition(id: newTab, title: "New Tab", defaultBinding: ShortcutBinding(key: "@", modifiers: [.command, .shift])),
    ], defaults: suite.defaults)
    let engine = engine()
    let model = model(engine, editor: editor)
    #expect(model.owners(of: shortcut(.digit(.two), [.command, .shift]), excluding: list)
            == [.appAction(newTab, title: "New Tab")])
    let candidates = ExtensionShortcutsModel.bindings(for: shortcut(.comma, [.command, .shift]))
    #expect(candidates.contains(ShortcutBinding(key: ",", modifiers: [.command, .shift])))
    #expect(candidates.contains(ShortcutBinding(key: "<", modifiers: [.command, .shift])))
    #expect(candidates.contains(ShortcutBinding(key: "<", modifiers: .command)))

    engine.setExtensionCommands(engine.extensionCommands.map {
      var command = $0
      if command.id == list { command.shortcut = shortcut(.digit(.two), [.command, .shift]) }
      return command
    })
    model.connect(editor)
    let owners = editor.extensionOwners?(ShortcutBinding(key: "@", modifiers: [.command, .shift])) ?? []
    #expect(owners.map(\.title) == ["Open clip list (Tidy Clips)"])
  }

  /// Use clears the app binding before the engine sets the shortcut (the engine refuses All Apps on a key the main
  /// menu holds); when the engine still refuses, the app binding comes back and nothing is lost.
  @Test func aRefusedUseRestoresTheAppShortcut() throws {
    let suite = try Suite()
    let editor = editor(suite)
    let engine = engine()
    engine.heldGlobalShortcuts = [shortcut(.letter(.t), .command)]
    let model = model(engine, editor: editor)
    model.setScope(.global, for: list)
    model.begin(list)
    model.record(event: try event("t", keyCode: 17, modifiers: .command))
    model.useRecorded()
    #expect(model.phase == .idle)
    #expect(model.notice == .engine(.globalShortcutTaken))
    #expect(editor.binding(for: newTab) == ShortcutBinding(key: "t", modifiers: .command))
    #expect(command(engine, list)?.shortcut == nil)
  }

  @Test func everyEngineAnswerHasAnOutcome() throws {
    let engine = engine()
    let model = model(engine)
    // .rejected(.notAllowed): a combination Chrome forbids, as an extension may have brought it.
    engine.setExtensionCommands(engine.extensionCommands.map {
      var command = $0
      if command.id == open { command.shortcut = shortcut(.letter(.k), [.command, .option]) }
      return command
    })
    model.setScope(.global, for: open)
    #expect(model.notice == .engine(.notAllowed))
    #expect(command(engine, open)?.scope == .inApp)
    // .rejected(.globalShortcutTaken)
    engine.heldGlobalShortcuts = [shortcut(.letter(.j), .control)]
    model.setScope(.global, for: list)
    model.begin(list)
    model.record(event: try event("j", keyCode: 38, modifiers: .control))
    #expect(model.notice == .engine(.globalShortcutTaken))
    #expect(command(engine, list)?.shortcut == nil)
    // .unknownCommand: the extension went away while the recorder listened.
    model.begin(list)
    engine.setExtensionCommands(engine.extensionCommands.filter { $0.id.extensionID != "clips" })
    model.record(event: try event("j", keyCode: 38, modifiers: [.control, .shift]))
    #expect(model.phase == .idle)
    #expect(model.notice == .commandGone)
    // .applied clears the notice.
    model.begin(read)
    model.record(event: try event("r", keyCode: 15, modifiers: [.control, .shift]))
    #expect(model.notice == nil)
    #expect(command(engine, read)?.shortcut == shortcut(.letter(.r), [.control, .shift]))
  }

  /// Another command took the key between the shell's check and the set: the engine's `.conflict` opens the notice.
  @Test func theEngineReportsAConflictTheShellDidNotSee() {
    let model = model(engine())
    let key = shortcut(.letter(.u), [.control, .shift])
    model.begin(list)
    model.apply(.conflict(with: read), for: list, shortcut: key)
    #expect(model.phase == .conflict(list, key,
                                     owners: [.extensionCommand(read, title: "Toggle reading view (Quiet Reader)")]))
  }

  // MARK: - Scope

  /// An unset command keeps the chosen scope in the row until a shortcut is set (the engine ignores scope when
  /// clearing).
  @Test func scopeOfAnUnsetCommandWaitsForItsShortcut() throws {
    let engine = engine()
    let model = model(engine)
    model.setScope(.global, for: list)
    #expect(model.scope(of: list) == .global)
    #expect(command(engine, list)?.scope == .inApp, "nothing reaches the engine without a shortcut")
    model.begin(list)
    model.record(event: try event("j", keyCode: 38, modifiers: .control))
    #expect(command(engine, list)?.scope == .global)
    model.setScope(.inApp, for: list)
    #expect(command(engine, list)?.scope == .inApp)
    #expect(command(engine, list)?.shortcut == shortcut(.letter(.j), .control))
  }

  // MARK: - Search

  @Test func searchByExtensionNameDescriptionOrShortcut() {
    let model = model(engine())
    func found(_ query: String) -> [ExtensionCommandID] {
      ExtensionShortcutsModel.filter(model.groups, query: query).flatMap { $0.commands.map(\.id) }
    }
    #expect(found("") == [open, read, clip, list])
    #expect(found("tidy") == [clip, list], "the extension's name finds all of its commands")
    #expect(found("reading") == [read])
    #expect(found("Option Shift Q") == [open])
    #expect(found("\u{2303}\u{21E7}K") == [clip])
    #expect(found("Command-E").isEmpty, "a whole shortcut matches exactly that combination")
    #expect(found("nothing like this").isEmpty)
  }

  // MARK: - App shortcut editor, the reverse direction

  @Test func anExtensionCommandIsAConflictOwnerForAppShortcuts() throws {
    let suite = try Suite()
    let editor = editor(suite)
    let engine = engine()
    let model = model(engine, editor: editor)
    model.connect(editor)
    editor.beginRecording(newTab)
    editor.record(event: try event("E", keyCode: 14, modifiers: [.command, .shift]))
    #expect(editor.extensionConflicts.map(\.title) == ["Toggle reading view (Quiet Reader)"])
    #expect(editor.hasConflict)
    #expect(editor.binding(for: newTab) == ShortcutBinding(key: "t", modifiers: .command))
    editor.keepExisting()
    #expect(command(engine, read)?.shortcut == shortcut(.letter(.e), [.command, .shift]))

    editor.beginRecording(newTab)
    editor.record(event: try event("E", keyCode: 14, modifiers: [.command, .shift]))
    editor.useRecordedShortcut()
    #expect(editor.binding(for: newTab) == ShortcutBinding(key: "e", modifiers: [.command, .shift]))
    #expect(command(engine, read)?.shortcut == nil, "Use takes it from the extension")
    #expect(editor.recordingAction == nil)
  }

  @Test func resettingToADefaultAnExtensionHoldsAsks() throws {
    let suite = try Suite()
    let editor = editor(suite)
    let engine = engine()
    let model = model(engine, editor: editor)
    model.connect(editor)
    editor.setBinding(ShortcutBinding(key: "y", modifiers: .command), for: newTab)
    engine.setExtensionCommands(engine.extensionCommands.map {
      var command = $0
      if command.id == list { command.shortcut = shortcut(.letter(.t), .command) }
      return command
    })
    editor.reset(newTab)
    #expect(editor.extensionConflicts.map(\.title) == ["Open clip list (Tidy Clips)"])
    #expect(editor.binding(for: newTab) == ShortcutBinding(key: "y", modifiers: .command))
  }
}
