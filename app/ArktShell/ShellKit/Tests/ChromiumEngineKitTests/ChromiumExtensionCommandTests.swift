import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Extension keyboard commands through the facade (#598). The facade lists the profile's commands with shortcuts in
/// Chromium's form ("Command+Shift+Y") and sets them through CommandService; ChromiumEngine maps that form onto
/// `ExtensionShortcut` both ways, maps the answers onto `ExtensionShortcutResult`, and turns the facade's
/// `ExtensionCommandsChanged` into `.commandsChanged`.
@MainActor
struct ChromiumExtensionCommandTests {
  let facade = ScriptedFacade()
  let alpha = String(repeating: "a", count: 32)
  let beta = String(repeating: "b", count: 32)

  private func command(_ name: String, of id: String, shortcut: String?, global: Bool = false,
                       description: String = "Run it") -> ScriptedExtensionCommand {
    ScriptedExtensionCommand(extensionID: id, commandName: name, extensionName: "Alpha Clips",
                             commandDescription: description, shortcut: shortcut, isGlobal: global)
  }

  // MARK: - Listing

  @Test func theListingCarriesIdsNamesDescriptionsAndScope() {
    facade.extensionCommandList = [
      command("_execute_action", of: alpha, shortcut: "Ctrl+Shift+U", description: "Activate the extension"),
      command("run-probe", of: alpha, shortcut: "Command+Shift+9", global: true),
      command("unset", of: beta, shortcut: nil, description: "Has none"),
    ]
    let engine = ChromiumEngine(facade: facade)
    let commands = engine.extensionCommands
    #expect(commands.map(\.id) == [
      ExtensionCommandID(extensionID: alpha, name: "_execute_action"),
      ExtensionCommandID(extensionID: alpha, name: "run-probe"),
      ExtensionCommandID(extensionID: beta, name: "unset"),
    ])
    #expect(commands.map(\.extensionName) == ["Alpha Clips", "Alpha Clips", "Alpha Clips"])
    #expect(commands.map(\.description) == ["Activate the extension", "Run it", "Has none"])
    #expect(commands.map(\.shortcut) == [
      ExtensionShortcut(key: .letter(.u), modifiers: [.control, .shift]),
      ExtensionShortcut(key: .digit(.nine), modifiers: [.command, .shift]),
      nil,
    ])
    #expect(commands.map(\.scope) == [.inApp, .global, .inApp])
  }

  @Test(arguments: [
    ("Ctrl+Alt+Comma", ExtensionShortcut(key: .comma, modifiers: [.control, .option])),
    ("Alt+Shift+Period", ExtensionShortcut(key: .period, modifiers: [.option, .shift])),
    ("Command+Tab", ExtensionShortcut(key: .tab, modifiers: [.command])),
    ("Ctrl+Space", ExtensionShortcut(key: .space, modifiers: [.control])),
    ("Command+PageUp", ExtensionShortcut(key: .pageUp, modifiers: [.command])),
    ("Command+Delete", ExtensionShortcut(key: .delete, modifiers: [.command])),
    ("MediaPlayPause", ExtensionShortcut(key: .mediaPlayPause, modifiers: [])),
    ("MediaPrevTrack", ExtensionShortcut(key: .mediaPreviousTrack, modifiers: [])),
    ("Shift+Command+A", ExtensionShortcut(key: .letter(.a), modifiers: [.command, .shift])),
  ])
  func aFacadeShortcutReadsAsTheShellsValue(text: String, expected: ExtensionShortcut) {
    #expect(ExtensionShortcut(facadeForm: text) == expected)
  }

  @Test(arguments: ["", "Command", "Command+", "Command+Y+Z", "Command+Escape", "Super+Y", "Command+y", "Command+F1"])
  func aShortcutTheShellCannotNameReadsAsNone(text: String) {
    #expect(ExtensionShortcut(facadeForm: text) == nil)
  }

  @Test func everyKeyAndModifierSetRoundTripsThroughChromiumsForm() {
    let keys: [ExtensionShortcut.Key] =
      ExtensionShortcut.Letter.allCases.map { .letter($0) } + ExtensionShortcut.Digit.allCases.map { .digit($0) } + [
        .comma, .period, .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .space, .tab, .insert, .delete,
        .mediaNextTrack, .mediaPreviousTrack, .mediaPlayPause, .mediaStop,
      ]
    for key in keys {
      for raw in UInt8(0)..<16 {
        let shortcut = ExtensionShortcut(key: key, modifiers: ExtensionShortcut.Modifiers(rawValue: raw))
        #expect(ExtensionShortcut(facadeForm: shortcut.facadeForm) == shortcut, "\(shortcut.facadeForm)")
      }
    }
  }

  @Test func theFormListsModifiersInChromiumsOrder() {
    let all = ExtensionShortcut(key: .letter(.k), modifiers: [.shift, .command, .option, .control])
    #expect(all.facadeForm == "Ctrl+Alt+Command+Shift+K")
    #expect(ExtensionShortcut(key: .digit(.zero), modifiers: [.command]).facadeForm == "Command+0")
    #expect(ExtensionShortcut(key: .mediaStop, modifiers: []).facadeForm == "MediaStop")
  }

  // MARK: - Setting

  @Test func aSetReachesTheFacadeOnceInChromiumsForm() {
    let engine = ChromiumEngine(facade: facade)
    let id = ExtensionCommandID(extensionID: alpha, name: "run-probe")
    let result = engine.setExtensionCommandShortcut(
      id, to: ExtensionShortcut(key: .letter(.y), modifiers: [.control, .shift]), scope: .global,
      replacingConflict: true)
    #expect(result == .applied)
    #expect(facade.shortcutCalls.count == 1)
    let call = facade.shortcutCalls.first
    #expect(call?.shortcut == "Ctrl+Shift+Y")
    #expect(call?.commandName == "run-probe")
    #expect(call?.extensionID == alpha)
    #expect(call?.global == true)
    #expect(call?.replacing == true)
  }

  @Test func clearingPassesNoShortcut() {
    let engine = ChromiumEngine(facade: facade)
    let result = engine.setExtensionCommandShortcut(
      ExtensionCommandID(extensionID: alpha, name: "run-probe"), to: nil, scope: .inApp, replacingConflict: false)
    #expect(result == .applied)
    #expect(facade.shortcutCalls.map(\.shortcut) == [nil])
    #expect(facade.shortcutCalls.map(\.global) == [false])
  }

  @Test(arguments: [
    (ArktExtensionShortcutResult.applied, ExtensionShortcutResult.applied),
    (.notAllowed, .rejected(.notAllowed)),
    (.unknownCommand, .unknownCommand),
    (.globalShortcutTaken, .rejected(.globalShortcutTaken)),
  ])
  func theFacadesAnswerMaps(answer: ArktExtensionShortcutResult, expected: ExtensionShortcutResult) {
    facade.shortcutAnswer = ScriptedShortcutChange(result: answer)
    let engine = ChromiumEngine(facade: facade)
    let result = engine.setExtensionCommandShortcut(
      ExtensionCommandID(extensionID: alpha, name: "run-probe"),
      to: ExtensionShortcut(key: .letter(.y), modifiers: [.command]), scope: .inApp, replacingConflict: false)
    #expect(result == expected)
  }

  @Test func aConflictNamesTheCommandThatHasTheShortcut() {
    facade.shortcutAnswer = ScriptedShortcutChange(result: .conflict, conflictExtensionID: beta,
                                                   conflictCommandName: "_execute_action")
    let engine = ChromiumEngine(facade: facade)
    let result = engine.setExtensionCommandShortcut(
      ExtensionCommandID(extensionID: alpha, name: "run-probe"),
      to: ExtensionShortcut(key: .letter(.y), modifiers: [.command]), scope: .inApp, replacingConflict: false)
    #expect(result == .conflict(with: ExtensionCommandID(extensionID: beta, name: "_execute_action")))
  }

  // MARK: - Changes

  @Test func theFacadesChangeArrivesAsCommandsChanged() async throws {
    let engine = ChromiumEngine(facade: facade)
    var events: [EngineExtensionEvent] = []
    let observation = engine.observeExtensions { events.append($0) }
    defer { observation.cancel() }

    facade.recordExtensionCommandsChanged()
    try await ScriptedHarness.delivered(engine)

    #expect(events == [.commandsChanged])
  }
}
