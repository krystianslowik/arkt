import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Keyboard commands (#598)

extension ChromiumEngine {
  /// The profile's commands as Chromium's CommandService has them: every command of every enabled extension, sorted by
  /// extension name, the action's (`_execute_action`) first within an extension. A shortcut the shell cannot name
  /// (none today: the facade and `ExtensionShortcut.Key` cover the same keys) reads as none.
  public var extensionCommands: [ExtensionCommand] {
    facade.extensionCommands.map { command in
      ExtensionCommand(
        id: ExtensionCommandID(extensionID: command.extensionID, name: command.commandName),
        extensionName: command.extensionName, description: command.commandDescription,
        shortcut: command.shortcut.flatMap(ExtensionShortcut.init(facadeForm:)),
        scope: command.isGlobal ? .global : .inApp)
    }
  }

  /// Through Chromium's CommandService, as Chrome's shortcuts page sets a shortcut: the shortcut is the user's from
  /// then on, so an update of the extension keeps it. The engine refuses what `ui::Command::ParseImpl` refuses and
  /// global scope on an action command (`.rejected(.notAllowed)`); it never answers `.rejected(.noKeyCode)`, since
  /// every `ExtensionShortcut.Key` has a Chromium name. `.rejected(.globalShortcutTaken)` when the engine's global
  /// listener could not register a global shortcut.
  public func setExtensionCommandShortcut(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?,
                                          scope: ExtensionCommandScope,
                                          replacingConflict: Bool) -> ExtensionShortcutResult {
    let change = facade.setExtensionCommandShortcut(
      shortcut?.facadeForm, forCommand: id.name, ofExtension: id.extensionID, global: scope == .global,
      replacingConflict: replacingConflict)
    switch change.result {
    case .applied: return .applied
    case .conflict:
      return .conflict(with: ExtensionCommandID(extensionID: change.conflictExtensionID ?? "",
                                                name: change.conflictCommandName ?? ""))
    case .notAllowed: return .rejected(.notAllowed)
    case .globalShortcutTaken: return .rejected(.globalShortcutTaken)
    case .unknownCommand: return .unknownCommand
    @unknown default: return .unknownCommand
    }
  }
}

// MARK: - Chromium's shortcut form

extension ExtensionShortcut {
  /// The shortcut in Chromium's form (`ui::Command::AcceleratorToString`): Ctrl, Alt, Command and Shift in that order,
  /// then the key, joined by "+". Ctrl is the Control key and Alt the Option key.
  var facadeForm: String {
    var parts: [String] = []
    if modifiers.contains(.control) { parts.append("Ctrl") }
    if modifiers.contains(.option) { parts.append("Alt") }
    if modifiers.contains(.command) { parts.append("Command") }
    if modifiers.contains(.shift) { parts.append("Shift") }
    parts.append(key.facadeName)
    return parts.joined(separator: "+")
  }

  /// A shortcut from Chromium's form, modifiers in any order. Nil when a token is unknown, the key is missing or
  /// repeated, or a modifier repeats.
  init?(facadeForm text: String) {
    var modifiers: Modifiers = []
    var key: Key?
    for token in text.split(separator: "+", omittingEmptySubsequences: false) {
      let modifier: Modifiers? = switch token {
      case "Ctrl": .control
      case "Alt": .option
      case "Command": .command
      case "Shift": .shift
      default: nil
      }
      if let modifier {
        guard !modifiers.contains(modifier) else { return nil }
        modifiers.insert(modifier)
      } else if key == nil, let named = Key(facadeName: String(token)) {
        key = named
      } else {
        return nil
      }
    }
    guard let key else { return nil }
    self.init(key: key, modifiers: modifiers)
  }
}

extension ExtensionShortcut.Key {
  /// Chromium's name of the key (`ui/base/accelerators/command_constants.h`).
  var facadeName: String {
    switch self {
    case .letter(let letter): letter.rawValue.uppercased()
    case .digit(let digit): String(digit.rawValue)
    case .comma: "Comma"
    case .period: "Period"
    case .up: "Up"
    case .down: "Down"
    case .left: "Left"
    case .right: "Right"
    case .home: "Home"
    case .end: "End"
    case .pageUp: "PageUp"
    case .pageDown: "PageDown"
    case .space: "Space"
    case .tab: "Tab"
    case .insert: "Insert"
    case .delete: "Delete"
    case .mediaNextTrack: "MediaNextTrack"
    case .mediaPreviousTrack: "MediaPrevTrack"
    case .mediaPlayPause: "MediaPlayPause"
    case .mediaStop: "MediaStop"
    }
  }

  /// The key with Chromium's name `name`: an upper-case letter, a digit, or a named key. Nil for anything else.
  init?(facadeName name: String) {
    if name.count == 1, let character = name.first {
      if character.isUppercase, let letter = ExtensionShortcut.Letter(rawValue: name.lowercased()) {
        self = .letter(letter); return
      }
      if let value = character.wholeNumberValue, character.isASCII, let digit = ExtensionShortcut.Digit(rawValue: value) {
        self = .digit(digit); return
      }
      return nil
    }
    guard let key = Self.byFacadeName[name] else { return nil }
    self = key
  }

  private static let byFacadeName: [String: Self] = {
    let named: [Self] = [
      .comma, .period, .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .space, .tab, .insert, .delete,
      .mediaNextTrack, .mediaPreviousTrack, .mediaPlayPause, .mediaStop,
    ]
    return Dictionary(uniqueKeysWithValues: named.map { ($0.facadeName, $0) })
  }()
}
