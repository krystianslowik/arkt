import AppKit
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

  private static let defaultsKey = "shortcutOverrides"
  public let catalog: [ShortcutDefinition]
  public private(set) var overrides: [ShortcutActionID: ShortcutOverride] = [:]
  public private(set) var recordingAction: ShortcutActionID?
  public private(set) var conflictingActions: [ShortcutActionID] = []
  private var pendingBinding: ShortcutBinding?
  private let defaults: UserDefaults

  public init(catalog: [ShortcutDefinition], defaults: UserDefaults) {
    // The first definition owns an ID; duplicate definitions cannot alter lookup or conflict behavior.
    var seen: Set<ShortcutActionID> = []
    self.catalog = catalog.filter { seen.insert($0.id).inserted }
    self.defaults = defaults
    guard let data = defaults.data(forKey: Self.defaultsKey),
          let stored = try? JSONDecoder().decode([String: StoredOverride].self, from: data) else { return }
    for definition in self.catalog {
      guard let value = stored[definition.id.rawValue] else { continue }
      if let key = value.key, let flags = value.modifiers, !key.isEmpty {
        overrides[definition.id] = .binding(ShortcutBinding(key: key, modifiers: .init(rawValue: flags)))
      } else if value.key == nil && value.modifiers == nil {
        overrides[definition.id] = .cleared
      }
    }
  }

  public func binding(for id: ShortcutActionID) -> ShortcutBinding? {
    guard let definition = catalog.first(where: { $0.id == id }) else { return nil }
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
    guard catalog.contains(where: { $0.id == id }) else { return }
    overrides.removeValue(forKey: id)
    if recordingAction == id { cancelRecording() }
    persist()
  }

  public func resetAll() {
    overrides.removeAll()
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
  }

  public func record(event: NSEvent) {
    guard event.type == .keyDown, let id = recordingAction else { return }
    if event.keyCode == 53 { cancelRecording(); return }
    if event.keyCode == 51 || event.keyCode == 117 {
      setBinding(nil, for: id)
      cancelRecording()
      return
    }
    guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return }
    let binding = ShortcutBinding(key: key.lowercased(), modifiers: event.modifierFlags)
    let conflicts = catalog.filter { $0.id != id && self.binding(for: $0.id) == binding }.map(\.id)
    if conflicts.isEmpty {
      setBinding(binding, for: id)
      cancelRecording()
    } else {
      pendingBinding = binding
      conflictingActions = conflicts
    }
  }

  public func keepExisting() { cancelRecording() }

  public func useRecordedShortcut() {
    guard let id = recordingAction, let binding = pendingBinding else { return }
    // Recompute conflicts so changes made while the notice is open cannot create duplicates.
    for definition in catalog where definition.id != id && self.binding(for: definition.id) == binding {
      overrides[definition.id] = .cleared
    }
    setBinding(binding, for: id)
    cancelRecording()
  }

  private func persist() {
    var stored: [String: StoredOverride] = [:]
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
  }
}
