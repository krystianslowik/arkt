import AppKit
import Carbon.HIToolbox
import Foundation

/// A stable identifier supplied by the shortcut catalog, independent of the displayed title.
public struct ShortcutActionID: Hashable, Codable, Sendable {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ShortcutBinding: Equatable, Sendable {
  public let key: String
  public let modifiers: NSEvent.ModifierFlags

  public init(key: String, modifiers: NSEvent.ModifierFlags) {
    self.key = key.lowercased()
    var flags = modifiers.intersection([.command, .option, .control, .shift])
    if key.lowercased() != key { flags.insert(.shift) }
    self.modifiers = flags
  }
}

public struct ShortcutDefinition: Sendable {
  public let id: ShortcutActionID
  public let title: String
  public let defaultBinding: ShortcutBinding?

  public init(id: ShortcutActionID, title: String, defaultBinding: ShortcutBinding?) {
    self.id = id
    self.title = title
    self.defaultBinding = defaultBinding
  }
}

/// A missing override means the catalog default; a cleared override deliberately has no binding.
public enum ShortcutOverride: Equatable, Sendable {
  case binding(ShortcutBinding)
  case cleared
}

@MainActor
public final class ShortcutEditorModel {
  private struct StoredOverride: Codable {
    let key: String?
    let modifiers: UInt?
  }

  /// A damaged entry must not discard the rest of the user's overrides.
  private struct DecodedOverride: Decodable {
    let value: StoredOverride?
    init(from decoder: Decoder) { value = try? StoredOverride(from: decoder) }
  }

  private static let defaultsKey = "shortcutOverrides"
  public let catalog: [ShortcutDefinition]
  public private(set) var overrides: [ShortcutActionID: ShortcutOverride] = [:]
  public private(set) var recordingAction: ShortcutActionID?
  public private(set) var conflictingActions: [ShortcutActionID] = []
  public struct ProtectedConflict: Equatable {
    public let title: String
    public let binding: ShortcutBinding
  }
  public private(set) var protectedConflicts: [ProtectedConflict] = []
  /// Why the last key pressed while recording was refused; nil once a key is accepted or recording ends.
  public enum Rejection: Equatable, Sendable { case needsCommandOrControl, textEditing, confirmOrFocusKey }
  public private(set) var rejection: Rejection?
  /// Saved entries for actions this build does not list (a newer build's catalog); written back on every save.
  private var foreignOverrides: [String: StoredOverride] = [:]
  /// Saved requests that cannot currently be applied without taking a noneditable command's key.
  public private(set) var blockedOverrides: [ShortcutActionID: [ProtectedConflict]] = [:]
  public var pendingShortcut: ShortcutBinding? { pendingBinding }
  var protectedOwners: (@MainActor (ShortcutBinding) -> [ProtectedConflict])? {
    didSet { refreshBlockedOverrides() }
  }
  private var pendingBinding: ShortcutBinding?
  private let defaults: UserDefaults
  private var observers: [UUID: @MainActor () -> Void] = [:]

  func observe(_ callback: @escaping @MainActor () -> Void) -> UUID {
    let id = UUID()
    observers[id] = callback
    return id
  }

  func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

  public init(catalog: [ShortcutDefinition], defaults: UserDefaults) {
    // The first definition owns an ID; duplicate definitions cannot alter lookup or conflict behavior.
    var seen: Set<ShortcutActionID> = []
    self.catalog = catalog.filter { seen.insert($0.id).inserted }
    self.defaults = defaults
    guard let data = defaults.data(forKey: Self.defaultsKey),
          let stored = try? JSONDecoder().decode([String: DecodedOverride].self, from: data) else { return }
    let known = Set(self.catalog.map(\.id.rawValue))
    for (id, entry) in stored where !known.contains(id) {
      if let value = entry.value { foreignOverrides[id] = value }
    }
    for definition in self.catalog {
      guard let value = stored[definition.id.rawValue]?.value else { continue }
      if let key = value.key, let flags = value.modifiers, !key.isEmpty {
        overrides[definition.id] = .binding(ShortcutBinding(key: key, modifiers: .init(rawValue: flags)))
      } else if value.key == nil && value.modifiers == nil {
        overrides[definition.id] = .cleared
      }
    }
  }

  public func binding(for id: ShortcutActionID) -> ShortcutBinding? {
    guard let definition = catalog.first(where: { $0.id == id }) else { return nil }
    guard blockedOverrides[id] == nil else { return nil }
    switch overrides[id] {
    case .binding(let binding): return binding
    case .cleared: return nil
    case nil: return definition.defaultBinding
    }
  }

  public func setBinding(_ binding: ShortcutBinding?, for id: ShortcutActionID) {
    guard let definition = catalog.first(where: { $0.id == id }) else { return }
    if binding == definition.defaultBinding {
      overrides.removeValue(forKey: id)
    } else if let binding {
      overrides[id] = .binding(binding)
    } else {
      overrides[id] = .cleared
    }
    persist()
  }

  public func reset(_ id: ShortcutActionID) {
    guard let definition = catalog.first(where: { $0.id == id }) else { return }
    if let binding = definition.defaultBinding {
      let conflicts = catalog.filter { $0.id != id && self.binding(for: $0.id) == binding }.map(\.id)
      let protected = protectedOwners?(binding) ?? []
      if !conflicts.isEmpty || !protected.isEmpty {
        beginRecording(id)
        pendingBinding = binding
        conflictingActions = conflicts
        protectedConflicts = protected
        return
      }
    }
    overrides.removeValue(forKey: id)
    if recordingAction == id { cancelRecording() }
    persist()
  }

  public func resetAll() {
    overrides.removeAll()
    foreignOverrides.removeAll()
    cancelRecording()
    persist()
  }

  public func beginRecording(_ id: ShortcutActionID) {
    cancelRecording()
    guard catalog.contains(where: { $0.id == id }) else { return }
    recordingAction = id
  }

  public func cancelRecording() {
    recordingAction = nil
    pendingBinding = nil
    conflictingActions = []
    protectedConflicts = []
    rejection = nil
  }

  public func record(event: NSEvent) {
    guard event.type == .keyDown, let id = recordingAction else { return }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let code = Int(event.keyCode)
    if code == kVK_Escape && flags.isEmpty { cancelRecording(); return }
    if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.isEmpty {
      setBinding(nil, for: id)
      cancelRecording()
      return
    }
    guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return }
    if let reason = Self.rejection(keyCode: code, key: key, flags: flags) {
      rejection = reason
      return
    }
    rejection = nil
    let binding = ShortcutBinding(key: key.lowercased(), modifiers: event.modifierFlags)
    let conflicts = catalog.filter { $0.id != id && self.binding(for: $0.id) == binding }.map(\.id)
    let protected = protectedOwners?(binding) ?? []
    if conflicts.isEmpty && protected.isEmpty {
      setBinding(binding, for: id)
      cancelRecording()
    } else {
      pendingBinding = binding
      conflictingActions = conflicts
      protectedConflicts = protected
    }
  }

  public func keepExisting() { cancelRecording() }

  public func useRecordedShortcut() {
    guard let id = recordingAction, let binding = pendingBinding else { return }
    // A dynamic menu owner may have appeared while the notice was open.
    protectedConflicts = protectedOwners?(binding) ?? []
    guard protectedConflicts.isEmpty else { return }
    // Recompute conflicts so changes made while the notice is open cannot create duplicates.
    for definition in catalog where definition.id != id && self.binding(for: definition.id) == binding {
      setBinding(nil, for: definition.id)
    }
    setBinding(binding, for: id)
    cancelRecording()
  }

  /// The recorder's key rules (maintainer decision 2026-11-16, #828): an edited binding goes to the menu before the
  /// focused view (`ShortcutCatalog.reserves`), so it must never take typing or text editing from a field or a page.
  /// It needs Command or Control, bare F1 ... F20 aside; Return, Tab and Escape stay theirs with any modifier; Cmd or
  /// Opt with an arrow or Delete, and Ctrl with an Emacs editing letter, stay the text system's.
  static func rejection(keyCode: Int, key: String, flags: NSEvent.ModifierFlags) -> Rejection? {
    if [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape].contains(keyCode) { return .confirmOrFocusKey }
    let unshifted = flags.subtracting(.shift)
    let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Delete, kVK_ForwardDelete]
    if arrows.contains(keyCode), unshifted == .command || unshifted == .option { return .textEditing }
    if unshifted == .control, key.count == 1, "abdefhklnoptvy".contains(key.lowercased()) { return .textEditing }
    if flags.contains(.command) || flags.contains(.control) { return nil }
    let functionKeys = UInt32(NSF1FunctionKey)...UInt32(NSF20FunctionKey)
    if key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first, functionKeys.contains(scalar.value) {
      return nil
    }
    return .needsCommandOrControl
  }

  private func persist() {
    refreshBlockedOverrides()
    var stored = foreignOverrides
    for (id, value) in overrides {
      switch value {
      case .binding(let binding):
        stored[id.rawValue] = StoredOverride(key: binding.key, modifiers: binding.modifiers.rawValue)
      case .cleared:
        stored[id.rawValue] = StoredOverride(key: nil, modifiers: nil)
      }
    }
    if stored.isEmpty { defaults.removeObject(forKey: Self.defaultsKey) }
    else if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    for callback in Array(observers.values) { callback() }
  }

  private func refreshBlockedOverrides() {
    var blocked: [ShortcutActionID: [ProtectedConflict]] = [:]
    for (id, value) in overrides {
      guard case .binding(let binding) = value else { continue }
      let owners = protectedOwners?(binding) ?? []
      if !owners.isEmpty { blocked[id] = owners }
    }
    blockedOverrides = blocked
  }
}
