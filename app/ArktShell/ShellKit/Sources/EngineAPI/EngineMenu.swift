/// The id of one command item in an engine menu: an id meaningful only to the source that built this menu; hand it
/// back to that source, never to `EngineWindowHost.perform` / command forwarding. Page context menu ids
/// (`IDC_CONTENT_CONTEXT_*`, the dynamic `IDC_EXTENSIONS_CONTEXT_CUSTOM_*`) and an extension action menu's own ids
/// are not browser commands, so they get their own type rather than `EngineCommand`.
public struct EngineMenuCommand: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public var description: String { "EngineMenuCommand(\(rawValue))" }
}

/// One item of a menu the engine asks the shell to show: the page context menu (#122) and an extension's context
/// menu items (#121). Every title is the engine's, so the shell adds no copy of its own. A command item carries its
/// `EngineMenuCommand`, passed back unchanged to the menu's source; a separator and a submenu holder carry none.
public struct EngineMenuItem: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case command(EngineMenuCommand)
    case separator
    case submenu([EngineMenuItem])
  }

  /// "" for a separator.
  public var title: String
  /// Set only by the initializers, so a separator stays disabled and unchecked.
  public private(set) var kind: Kind
  /// Always false for a separator.
  public private(set) var isEnabled: Bool
  /// Shown with a check mark (a toggle or the chosen radio item). Always false for a separator or a submenu holder.
  public private(set) var isChecked: Bool

  public init(title: String, command: EngineMenuCommand, isEnabled: Bool = true, isChecked: Bool = false) {
    self.init(title: title, kind: .command(command), isEnabled: isEnabled, isChecked: isChecked)
  }

  private init(title: String, kind: Kind, isEnabled: Bool, isChecked: Bool) {
    self.title = title
    self.kind = kind
    self.isEnabled = isEnabled
    self.isChecked = isChecked
  }

  public static let separator = EngineMenuItem(title: "", kind: .separator, isEnabled: false, isChecked: false)

  /// An item that opens `items`.
  public static func submenu(_ title: String, _ items: [EngineMenuItem], isEnabled: Bool = true) -> EngineMenuItem {
    EngineMenuItem(title: title, kind: .submenu(items), isEnabled: isEnabled, isChecked: false)
  }

  public var isSeparator: Bool { if case .separator = kind { true } else { false } }

  /// The command a command item carries; nil for a separator or a submenu holder.
  public var command: EngineMenuCommand? { if case .command(let command) = kind { command } else { nil } }

  /// The items a submenu holder opens; nil for any other item.
  public var submenu: [EngineMenuItem]? { if case .submenu(let items) = kind { items } else { nil } }

  /// `items` tidied the macOS way, in every submenu too: a separator at the start or end is dropped and a run of
  /// separators becomes one. A submenu holder keeps every other value; only its items change.
  public static func tidied(_ items: [EngineMenuItem]) -> [EngineMenuItem] {
    var result: [EngineMenuItem] = []
    for item in items {
      if item.isSeparator {
        if let last = result.last, !last.isSeparator { result.append(item) }
      } else if let children = item.submenu {
        var holder = item
        holder.kind = .submenu(tidied(children))
        result.append(holder)
      } else {
        result.append(item)
      }
    }
    if result.last?.isSeparator == true { result.removeLast() }
    return result
  }
}
