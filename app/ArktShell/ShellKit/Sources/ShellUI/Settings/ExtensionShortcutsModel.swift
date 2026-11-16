import AppKit
import Carbon.HIToolbox
import EngineAPI

/// Who holds a shortcut an extension command is about to take (#597, `shortcuts-conflict`).
public enum ExtensionShortcutOwner: Equatable, Sendable {
  /// An app shortcut the editor can change (`ShortcutCatalog`): Use removes it there.
  case appAction(ShortcutActionID, title: String)
  /// A key Arkt keeps (a main-menu item the editor cannot change, or a key the window handles itself): Use is
  /// unavailable.
  case arkt(title: String)
  /// Another extension command: Use takes it from that command.
  case extensionCommand(ExtensionCommandID, title: String)

  public var title: String {
    switch self {
    case .appAction(_, let title), .arkt(let title), .extensionCommand(_, let title): title
    }
  }
}

/// Settings > Shortcuts > Extension Shortcuts (#597; design/extensions `shortcuts`, `shortcuts-conflict`): the
/// profile's extension commands grouped by extension, and the recorder for one of them. The recorder applies the app
/// recorder's key rules (#828, `ShortcutEditorModel.rejection`) plus the keys `chrome.commands` can name, and checks
/// conflicts with Arkt's shortcuts and the other extension commands before the engine sees the shortcut. Return keeps
/// the existing shortcut (#590). The engine holds the commands; nothing is stored here but a chosen scope for a
/// command without a shortcut.
@MainActor
public final class ExtensionShortcutsModel {
  public struct Group: Equatable, Sendable {
    public var extensionID: String
    public var name: String
    public var commands: [ExtensionCommand]
  }

  public enum Phase: Equatable, Sendable {
    case idle
    /// The recorder listens for the command's new shortcut.
    case listening(ExtensionCommandID)
    /// The pressed shortcut has owners; the notice asks Keep Existing or Use.
    case conflict(ExtensionCommandID, ExtensionShortcut, owners: [ExtensionShortcutOwner])
  }

  /// What the last change ended with, shown in the notice line.
  public enum Notice: Equatable, Sendable {
    /// The engine refused the shortcut or scope.
    case engine(ExtensionShortcutRejection)
    /// The command's extension went away.
    case commandGone
  }

  let engine: any EngineExtensions
  private weak var editor: ShortcutEditorModel?
  /// Titles of the keys Arkt keeps for a binding: main-menu items the editor cannot change and keys owned outside
  /// the menu.
  private let arktOwners: @MainActor (ShortcutBinding) -> [String]
  public private(set) var phase: Phase = .idle
  /// Why the last key pressed while listening was refused; nil once a key is accepted or the recorder stops.
  public private(set) var rejection: ShortcutEditorModel.Rejection?
  public private(set) var notice: Notice?
  /// The scope chosen for a command without a shortcut, applied with its first shortcut (the engine ignores scope
  /// when clearing).
  private var pendingScopes: [ExtensionCommandID: ExtensionCommandScope] = [:]

  public init(engine: any EngineExtensions, editor: ShortcutEditorModel?,
              arktOwners: @escaping @MainActor (ShortcutBinding) -> [String]) {
    self.engine = engine
    self.editor = editor
    self.arktOwners = arktOwners
  }

  // MARK: Rows

  /// The engine's commands, one group per extension, in the engine's order.
  public var groups: [Group] {
    var groups: [Group] = []
    for command in engine.extensionCommands {
      if let index = groups.firstIndex(where: { $0.extensionID == command.id.extensionID }) {
        groups[index].commands.append(command)
      } else {
        groups.append(Group(extensionID: command.id.extensionID, name: command.extensionName, commands: [command]))
      }
    }
    return groups
  }

  public func command(_ id: ExtensionCommandID) -> ExtensionCommand? {
    engine.extensionCommands.first { $0.id == id }
  }

  /// The row's title: the manifest's description, or the command's name when it has none.
  public static func title(of command: ExtensionCommand) -> String {
    command.description.isEmpty ? command.id.name : command.description
  }

  /// The scope the row shows: the engine's for a command with a shortcut, the chosen one otherwise.
  public func scope(of id: ExtensionCommandID) -> ExtensionCommandScope {
    guard let command = command(id) else { return .inApp }
    return command.shortcut == nil ? pendingScopes[id] ?? command.scope : command.scope
  }

  /// Keycaps in AppKit's order (Control, Option, Shift, Command, then the key) and the words VoiceOver reads.
  public static func display(_ shortcut: ExtensionShortcut) -> (keys: [String], spoken: String) {
    if let media = mediaName(shortcut.key) { return ([media], media) }
    let binding = bindings(for: shortcut)[0]
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: binding.key)
    item.keyEquivalentModifierMask = binding.modifiers
    let entry = ShortcutCatalog.entry(for: item)
    return (entry?.keys ?? [], entry?.spoken ?? "")
  }

  private static func mediaName(_ key: ExtensionShortcut.Key) -> String? {
    switch key {
    case .mediaPlayPause: "Play/Pause"
    case .mediaNextTrack: "Next Track"
    case .mediaPreviousTrack: "Previous Track"
    case .mediaStop: "Stop"
    default: nil
    }
  }

  // MARK: Two forms of one shortcut

  /// The forms an app binding of `shortcut` can take: the unshifted key the engine stores, and, with Shift on a
  /// digit, comma or period, the character a US layout types (the app recorder stores "@" for Shift-2, and a menu
  /// item may hold "@" without Shift). The first is the canonical form. Empty for a media key.
  public static func bindings(for shortcut: ExtensionShortcut) -> [ShortcutBinding] {
    guard let key = keyString(shortcut.key) else { return [] }
    let flags = modifierFlags(shortcut.modifiers)
    var forms = [ShortcutBinding(key: key, modifiers: flags)]
    if flags.contains(.shift), let shifted = usShifted[key] {
      forms.append(ShortcutBinding(key: shifted, modifiers: flags))
      forms.append(ShortcutBinding(key: shifted, modifiers: flags.subtracting(.shift)))
    }
    return forms
  }

  private static let usShifted: [String: String] = [
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
    ",": "<", ".": ">",
  ]

  static func modifierFlags(_ modifiers: ExtensionShortcut.Modifiers) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers.contains(.command) { flags.insert(.command) }
    if modifiers.contains(.option) { flags.insert(.option) }
    if modifiers.contains(.control) { flags.insert(.control) }
    if modifiers.contains(.shift) { flags.insert(.shift) }
    return flags
  }

  static func modifiers(_ flags: NSEvent.ModifierFlags) -> ExtensionShortcut.Modifiers {
    var modifiers: ExtensionShortcut.Modifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    return modifiers
  }

  /// The key as a menu item's key equivalent stores it; nil for media keys.
  private static func keyString(_ key: ExtensionShortcut.Key) -> String? {
    func scalar(_ value: Int) -> String { String(UnicodeScalar(UInt32(value))!) }
    switch key {
    case .letter(let letter): return letter.rawValue
    case .digit(let digit): return String(digit.rawValue)
    case .comma: return ","
    case .period: return "."
    case .space: return " "
    case .tab: return "\t"
    case .up: return scalar(NSUpArrowFunctionKey)
    case .down: return scalar(NSDownArrowFunctionKey)
    case .left: return scalar(NSLeftArrowFunctionKey)
    case .right: return scalar(NSRightArrowFunctionKey)
    case .home: return scalar(NSHomeFunctionKey)
    case .end: return scalar(NSEndFunctionKey)
    case .pageUp: return scalar(NSPageUpFunctionKey)
    case .pageDown: return scalar(NSPageDownFunctionKey)
    case .insert: return scalar(NSInsertFunctionKey)
    case .delete: return scalar(NSDeleteFunctionKey)
    case .mediaNextTrack, .mediaPreviousTrack, .mediaPlayPause, .mediaStop: return nil
    }
  }

  /// The key pressed: a letter by the character the layout prints on the key, anything else by key code (an AZERTY
  /// digit row types "&" on the 1 key). Nil for a key `chrome.commands` cannot name.
  static func key(keyCode: UInt16, unmodified: String?) -> ExtensionShortcut.Key? {
    if let text = unmodified, text.count == 1, let character = text.first,
       case .letter(let letter)? = ExtensionShortcut.Key(character: character) {
      return .letter(letter)
    }
    return ExtensionShortcut.Key(keyCode: keyCode)
  }

  // MARK: Owners

  /// Keys the shell's window handles outside the main menu that the engine cannot see (`ReservedKeys`; #922 review):
  /// the tab switcher's Ctrl-Tab and Ctrl-Shift-Tab.
  static let windowKeys: [(ExtensionShortcut, String)] = [
    (ExtensionShortcut(key: .tab, modifiers: .control), "Tab Switcher"),
    (ExtensionShortcut(key: .tab, modifiers: [.control, .shift]), "Tab Switcher (previous tab)"),
  ]

  /// Everyone else who holds `shortcut`: Arkt's editable shortcuts, the keys Arkt keeps, then the other extension
  /// commands.
  public func owners(of shortcut: ExtensionShortcut, excluding id: ExtensionCommandID) -> [ExtensionShortcutOwner] {
    var owners: [ExtensionShortcutOwner] = []
    let forms = Self.bindings(for: shortcut)
    if let editor {
      for definition in editor.catalog {
        guard let binding = editor.binding(for: definition.id), forms.contains(binding) else { continue }
        owners.append(.appAction(definition.id, title: Self.menuTitle(definition.title)))
      }
    }
    var kept: [String] = []
    for form in forms { kept += arktOwners(form).filter { !kept.contains($0) } }
    kept += Self.windowKeys.filter { $0.0 == shortcut }.map(\.1)
    owners += kept.map { .arkt(title: Self.menuTitle($0)) }
    for command in engine.extensionCommands where command.id != id && command.shortcut == shortcut {
      owners.append(.extensionCommand(command.id, title: Self.ownerTitle(command)))
    }
    return owners
  }

  /// "Toggle reading view (Quiet Reader)": how a notice names an extension command.
  static func ownerTitle(_ command: ExtensionCommand) -> String { "\(title(of: command)) (\(command.extensionName))" }

  private static func menuTitle(_ title: String) -> String {
    for suffix in ["...", "\u{2026}"] where title.hasSuffix(suffix) { return String(title.dropLast(suffix.count)) }
    return title
  }

  /// Use on a conflict is unavailable while a key Arkt keeps owns the shortcut.
  public var canUse: Bool {
    guard case .conflict(_, _, let owners) = phase else { return false }
    return !owners.contains { if case .arkt = $0 { true } else { false } }
  }

  /// Makes extension commands conflict owners in the app shortcut editor (the reverse direction): recording an app
  /// shortcut an extension command holds opens the notice, and Use takes it from the command.
  public func connect(_ editor: ShortcutEditorModel) {
    editor.extensionOwners = { [weak self] binding in
      guard let self else { return [] }
      return self.engine.extensionCommands.compactMap { command in
        guard let shortcut = command.shortcut, Self.bindings(for: shortcut).contains(binding) else { return nil }
        return ShortcutEditorModel.ProtectedConflict(title: Self.ownerTitle(command), binding: binding)
      }
    }
    editor.releaseExtensionOwners = { [weak self] binding in
      guard let self else { return }
      for command in self.engine.extensionCommands {
        guard let shortcut = command.shortcut, Self.bindings(for: shortcut).contains(binding) else { continue }
        _ = self.engine.setExtensionCommandShortcut(command.id, to: nil, scope: command.scope,
                                                    replacingConflict: false)
      }
    }
  }

  // MARK: Recording

  public var recordingCommand: ExtensionCommandID? {
    switch phase {
    case .idle: nil
    case .listening(let id), .conflict(let id, _, _): id
    }
  }

  public func begin(_ id: ExtensionCommandID) {
    cancel()
    guard command(id) != nil else { return }
    notice = nil
    phase = .listening(id)
  }

  public func cancel() {
    phase = .idle
    rejection = nil
  }

  public func keepExisting() { cancel() }

  /// A key pressed while listening: Escape cancels, Delete clears, a refused key keeps listening with a reason, a
  /// free shortcut is set, and a taken one opens the notice.
  public func record(event: NSEvent) {
    guard event.type == .keyDown, case .listening(let id) = phase else { return }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let code = Int(event.keyCode)
    if code == kVK_Escape && flags.isEmpty { cancel(); return }
    if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.isEmpty {
      cancel()
      set(id, to: nil)
      return
    }
    let unmodified = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
    let typed = event.charactersIgnoringModifiers ?? unmodified ?? ""
    if let reason = ShortcutEditorModel.rejection(keyCode: code, key: typed, flags: flags) {
      rejection = reason
      return
    }
    guard let key = Self.key(keyCode: event.keyCode, unmodified: unmodified?.lowercased()) else {
      rejection = .notAnExtensionKey
      return
    }
    if flags.contains(.option), !flags.isDisjoint(with: [.command, .control]) {
      rejection = .optionWithCommandOrControl
      return
    }
    rejection = nil
    let shortcut = ExtensionShortcut(key: key, modifiers: Self.modifiers(flags))
    let owners = owners(of: shortcut, excluding: id)
    if owners.isEmpty {
      set(id, to: shortcut)
    } else {
      phase = .conflict(id, shortcut, owners: owners)
    }
  }

  /// Use on the notice: takes the shortcut from its owners, now (one may have changed while the notice was open).
  /// An app shortcut is cleared before the engine sets the extension's (the engine refuses All Apps on a key the main
  /// menu holds) and comes back if the engine still refuses.
  public func useRecorded() {
    guard case .conflict(let id, let shortcut, _) = phase else { return }
    let owners = owners(of: shortcut, excluding: id)
    phase = .conflict(id, shortcut, owners: owners)
    guard canUse else { return }
    var released: [(ShortcutActionID, ShortcutBinding)] = []
    for case .appAction(let action, _) in owners {
      guard let editor, let binding = editor.binding(for: action) else { continue }
      released.append((action, binding))
      editor.setBinding(nil, for: action)
    }
    let result = engine.setExtensionCommandShortcut(id, to: shortcut, scope: scope(of: id), replacingConflict: true)
    if result != .applied {
      for (action, binding) in released { editor?.setBinding(binding, for: action) }
    }
    apply(result, for: id, shortcut: shortcut)
  }

  /// Sets (nil clears) the command's shortcut in its scope.
  public func set(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?) {
    let result = engine.setExtensionCommandShortcut(id, to: shortcut, scope: scope(of: id), replacingConflict: false)
    apply(result, for: id, shortcut: shortcut)
  }

  /// The row's scope pop-up: kept in the row for a command without a shortcut, sent to the engine otherwise.
  public func setScope(_ scope: ExtensionCommandScope, for id: ExtensionCommandID) {
    guard let command = command(id) else { return }
    guard let shortcut = command.shortcut else {
      pendingScopes[id] = scope
      return
    }
    let result = engine.setExtensionCommandShortcut(id, to: shortcut, scope: scope, replacingConflict: false)
    if result == .applied { pendingScopes[id] = nil }
    apply(result, for: id, shortcut: shortcut)
  }

  /// The engine's answer to a set, as the recorder's next phase and notice.
  func apply(_ result: ExtensionShortcutResult, for id: ExtensionCommandID, shortcut: ExtensionShortcut?) {
    switch result {
    case .applied:
      notice = nil
      pendingScopes[id] = nil
      cancel()
    case .conflict(let holder):
      guard let shortcut, let owner = command(holder) else { cancel(); return }
      notice = nil
      phase = .conflict(id, shortcut, owners: [.extensionCommand(holder, title: Self.ownerTitle(owner))])
    case .rejected(let reason):
      notice = .engine(reason)
      cancel()
    case .unknownCommand:
      notice = .commandGone
      cancel()
    }
  }

  // MARK: Search

  /// Commands whose extension name or title contains `query`, or whose shortcut is the combination it spells
  /// (`ShortcutCatalog.filter`); groups without a match are dropped. A blank query keeps everything.
  public static func filter(_ groups: [Group], query: String) -> [Group] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return groups }
    return groups.compactMap { group in
      if group.name.localizedCaseInsensitiveContains(trimmed) { return group }
      let entries = group.commands.enumerated().map { index, command in
        let shown = command.shortcut.map(display) ?? (keys: [], spoken: "None")
        return ShortcutCatalog.Entry(title: title(of: command), actionID: ShortcutActionID(String(index)),
                                     keys: shown.keys, spoken: shown.spoken)
      }
      let found = ShortcutCatalog.filter([ShortcutCatalog.Section(title: group.name, entries: entries)], query: query)
      let kept = Set(found.flatMap(\.entries).compactMap { $0.actionID.flatMap { Int($0.rawValue) } })
      guard !kept.isEmpty else { return nil }
      var filtered = group
      filtered.commands = group.commands.enumerated().filter { kept.contains($0.offset) }.map(\.element)
      return filtered
    }
  }
}
