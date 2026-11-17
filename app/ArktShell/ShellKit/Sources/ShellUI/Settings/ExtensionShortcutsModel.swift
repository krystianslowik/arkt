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
    /// A scope change: another extension command already has the shortcut (as `ownerTitle` names it).
    case taken(by: String)
  }

  let engine: any EngineExtensions
  private weak var editor: ShortcutEditorModel?
  /// The keys Arkt keeps, by binding, with their owners' titles: main-menu items the editor cannot change and keys
  /// owned outside the menu (`ShortcutCatalog.keptOwnerIndex`). Read once per `ownerIndex()`.
  private let keptOwners: @MainActor () -> [ShortcutBinding: [String]]
  /// The character the keyboard layout types for a key code with Shift (`currentLayoutShifted`).
  private let shifted: @MainActor (UInt16) -> String?
  public private(set) var phase: Phase = .idle
  /// Why the last key pressed while listening was refused; nil once a key is accepted or the recorder stops.
  public private(set) var rejection: ShortcutEditorModel.Rejection?
  public private(set) var notice: Notice?
  /// The scope chosen for a command without a shortcut, applied with its first shortcut (the engine ignores scope
  /// when clearing).
  private var pendingScopes: [ExtensionCommandID: ExtensionCommandScope] = [:]

  public init(engine: any EngineExtensions, editor: ShortcutEditorModel?,
              shifted: @escaping @MainActor (UInt16) -> String? = ExtensionShortcutsModel.currentLayoutShifted,
              keptOwners: @escaping @MainActor () -> [ShortcutBinding: [String]]) {
    self.engine = engine
    self.editor = editor
    self.shifted = shifted
    self.keptOwners = keptOwners
  }

  // MARK: Rows

  /// The engine's commands, one group per extension, in the engine's order.
  public var groups: [Group] { Self.groups(of: engine.extensionCommands) }

  static func groups(of commands: [ExtensionCommand]) -> [Group] {
    var groups: [Group] = []
    for command in commands {
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

  /// The commands that run the extension's action.
  static let actionCommandNames: Set<String> = ["_execute_action", "_execute_browser_action", "_execute_page_action"]

  /// The row's title: "Open <extension>" for the action command (design/extensions `shortcuts`), otherwise the
  /// manifest's description, or the command's name when it has none.
  public static func title(of command: ExtensionCommand) -> String {
    if actionCommandNames.contains(command.id.name) { return "Open \(command.extensionName)" }
    return command.description.isEmpty ? command.id.name : command.description
  }

  /// The row's description line: "The main action" for the action command. `chrome.commands` gives a command one
  /// string, which is its title, so other commands have none.
  public static func detail(of command: ExtensionCommand) -> String? {
    actionCommandNames.contains(command.id.name) ? "The main action" : nil
  }

  /// The scope the row shows: the engine's for a command with a shortcut, the chosen one otherwise.
  public func scope(of id: ExtensionCommandID) -> ExtensionCommandScope {
    command(id).map(scope(of:)) ?? .inApp
  }

  public func scope(of command: ExtensionCommand) -> ExtensionCommandScope {
    command.shortcut == nil ? pendingScopes[command.id] ?? command.scope : command.scope
  }

  /// Keycaps in AppKit's order (Control, Option, Shift, Command, then the key) and the words VoiceOver reads.
  public static func display(_ shortcut: ExtensionShortcut) -> (keys: [String], spoken: String) {
    if let media = mediaName(shortcut.key) { return ([media], media) }
    let binding = bindings(for: shortcut, shifted: { _ in nil })[0]
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
  /// digit, comma or period, the character the keyboard layout types with Shift on that key (`shifted`, by key
  /// code): the app recorder stores "@" for Shift-2 on a US layout and "/" for Shift-7 on a German one, and a menu
  /// item may hold that character without Shift. The first is the canonical form. Empty for a media key.
  public static func bindings(for shortcut: ExtensionShortcut,
                              shifted: (UInt16) -> String?) -> [ShortcutBinding] {
    guard let key = keyString(shortcut.key) else { return [] }
    let flags = modifierFlags(shortcut.modifiers)
    var forms = [ShortcutBinding(key: key, modifiers: flags)]
    if flags.contains(.shift), let code = shiftableKeyCodes[key], let character = shifted(code), !character.isEmpty,
       character != key {
      forms.append(ShortcutBinding(key: character, modifiers: flags))
      forms.append(ShortcutBinding(key: character, modifiers: flags.subtracting(.shift)))
    }
    return forms
  }

  /// `bindings(for:shifted:)` with this model's keyboard layout.
  public func bindings(for shortcut: ExtensionShortcut) -> [ShortcutBinding] {
    Self.bindings(for: shortcut, shifted: shifted)
  }

  /// The key codes of the keys whose Shift character differs by layout: the digit row, comma and period.
  private static let shiftableKeyCodes: [String: UInt16] = [
    "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
    ",": 0x2B, ".": 0x2F,
  ]

  /// What a US layout types with Shift on those keys.
  public static func usShifted(_ keyCode: UInt16) -> String? {
    let table: [UInt16: String] = [
      0x12: "!", 0x13: "@", 0x14: "#", 0x15: "$", 0x17: "%", 0x16: "^", 0x1A: "&", 0x1C: "*", 0x19: "(",
      0x1D: ")", 0x2B: "<", 0x2F: ">",
    ]
    return table[keyCode]
  }

  /// What the current keyboard layout types with Shift on `keyCode` (`UCKeyTranslate`), or the US character when the
  /// layout has no Unicode data.
  public static func currentLayoutShifted(_ keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return usShifted(keyCode)
    }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var deadKeys: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = data.withUnsafeBytes { buffer -> OSStatus in
      guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
      return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), UInt32((shiftKey >> 8) & 0xFF),
                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                            characters.count, &length, &characters)
    }
    guard status == noErr, length > 0 else { return usShifted(keyCode) }
    return String(utf16CodeUnits: characters, count: length)
  }

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

  /// The key pressed, as the layout prints it: a letter, comma, period, space or digit by its character (Dvorak's
  /// "," on the QWERTY W key is Comma, not W), except that the digit row goes by key code (AZERTY types "&" on the 1
  /// key). A key that types no ASCII character goes by key code: the arrows and named keys, and the letters of a
  /// non-Latin layout, as the main menu matches them. Other ASCII punctuation ("'" on Dvorak's Q key) is no key
  /// `chrome.commands` can name: nil.
  static func key(keyCode: UInt16, unmodified: String?) -> ExtensionShortcut.Key? {
    if let byCode = ExtensionShortcut.Key(keyCode: keyCode), case .digit = byCode { return byCode }
    guard let text = unmodified, text.count == 1, let character = text.first, character.isASCII else {
      return ExtensionShortcut.Key(keyCode: keyCode)
    }
    if character.isLetter || character.isNumber || [",", ".", " "].contains(character) {
      return ExtensionShortcut.Key(character: character)
    }
    // Tab and other control characters have names by key code; printable punctuation does not.
    return character.asciiValue.map { $0 < 0x20 || $0 == 0x7F } == true ? ExtensionShortcut.Key(keyCode: keyCode) : nil
  }

  // MARK: Owners

  /// Keys the shell's window handles outside the main menu that the engine cannot see (`ReservedKeys`; #922 review):
  /// the tab switcher's Ctrl-Tab and Ctrl-Shift-Tab.
  static let windowKeys: [(ExtensionShortcut, String)] = [
    (ExtensionShortcut(key: .tab, modifiers: .control), "Tab Switcher"),
    (ExtensionShortcut(key: .tab, modifiers: [.control, .shift]), "Tab Switcher (previous tab)"),
  ]

  /// Who holds what, read once: the engine's commands, the editor's bindings and the keys Arkt keeps. A pane rebuild
  /// makes one and asks it for every row.
  public struct OwnerIndex {
    public let commands: [ExtensionCommand]
    let app: [ShortcutBinding: [(ShortcutActionID, String)]]
    let kept: [ShortcutBinding: [String]]
  }

  public func ownerIndex() -> OwnerIndex {
    var app: [ShortcutBinding: [(ShortcutActionID, String)]] = [:]
    if let editor {
      for definition in editor.catalog {
        guard let binding = editor.binding(for: definition.id) else { continue }
        app[binding, default: []].append((definition.id, definition.title))
      }
    }
    return OwnerIndex(commands: engine.extensionCommands, app: app, kept: keptOwners())
  }

  /// Everyone else who holds `shortcut`: Arkt's editable shortcuts, the keys Arkt keeps, then the other extension
  /// commands.
  public func owners(of shortcut: ExtensionShortcut, excluding id: ExtensionCommandID) -> [ExtensionShortcutOwner] {
    owners(of: shortcut, excluding: id, in: ownerIndex())
  }

  public func owners(of shortcut: ExtensionShortcut, excluding id: ExtensionCommandID,
                     in index: OwnerIndex) -> [ExtensionShortcutOwner] {
    var owners: [ExtensionShortcutOwner] = []
    let forms = bindings(for: shortcut)
    for form in forms {
      for (action, title) in index.app[form] ?? [] where !owners.contains(.appAction(action, title: Self.menuTitle(title))) {
        owners.append(.appAction(action, title: Self.menuTitle(title)))
      }
    }
    var kept: [String] = []
    for form in forms { kept += (index.kept[form] ?? []).filter { !kept.contains($0) } }
    kept += Self.windowKeys.filter { $0.0 == shortcut }.map(\.1)
    owners += kept.map { .arkt(title: Self.menuTitle($0)) }
    for command in index.commands where command.id != id && command.shortcut == shortcut {
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
        guard let shortcut = command.shortcut, self.bindings(for: shortcut).contains(binding) else { return nil }
        return ShortcutEditorModel.ProtectedConflict(title: Self.ownerTitle(command), binding: binding)
      }
    }
    // True when every holder lost it; otherwise the ones already cleared get it back and nothing changed.
    editor.releaseExtensionOwners = { [weak self] binding in
      guard let self else { return false }
      var cleared: [ExtensionCommand] = []
      for command in self.engine.extensionCommands {
        guard let shortcut = command.shortcut, self.bindings(for: shortcut).contains(binding) else { continue }
        let result = self.engine.setExtensionCommandShortcut(command.id, to: nil, scope: command.scope,
                                                             replacingConflict: false)
        guard result == .applied else {
          for done in cleared {
            _ = self.engine.setExtensionCommandShortcut(done.id, to: done.shortcut, scope: done.scope,
                                                        replacingConflict: false)
          }
          return false
        }
        cleared.append(command)
      }
      return true
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

  /// The row's scope pop-up: kept in the row for a command without a shortcut, sent to the engine otherwise. It ends
  /// a recording in progress, and a conflict the engine reports for it is a notice, never a conflict phase (the
  /// notice belongs to a recorder).
  public func setScope(_ scope: ExtensionCommandScope, for id: ExtensionCommandID) {
    cancel()
    guard let command = command(id) else { return }
    guard let shortcut = command.shortcut else {
      pendingScopes[id] = scope
      return
    }
    let result = engine.setExtensionCommandShortcut(id, to: shortcut, scope: scope, replacingConflict: false)
    if case .conflict(let holder) = result {
      cancel()
      notice = .taken(by: self.command(holder).map(Self.ownerTitle) ?? "another extension")
      return
    }
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
        let shown = command.shortcut.map { display($0) } ?? (keys: [], spoken: "None")
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
