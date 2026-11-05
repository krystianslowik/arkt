/// One item of a menu the engine asks the shell to show: the page context menu (#122) and an extension's context
/// menu items (#121). Every title is the engine's, so the shell adds no copy of its own. A command item runs its
/// `EngineCommand` (Chromium's id for the item, passed back unchanged); a separator and a submenu holder run nothing.
public struct EngineMenuItem: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case command(EngineCommand)
    case separator
    case submenu([EngineMenuItem])
  }

  /// "" for a separator.
  public var title: String
  public var kind: Kind
  /// Always false for a separator.
  public var isEnabled: Bool
  /// Shown with a check mark (a toggle or the chosen radio item).
  public var isChecked: Bool

  public init(title: String, command: EngineCommand, isEnabled: Bool = true, isChecked: Bool = false) {
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

  /// The command a command item runs; nil for a separator or a submenu holder.
  public var command: EngineCommand? { if case .command(let command) = kind { command } else { nil } }

  /// The items a submenu holder opens; nil for any other item.
  public var submenu: [EngineMenuItem]? { if case .submenu(let items) = kind { items } else { nil } }
}
