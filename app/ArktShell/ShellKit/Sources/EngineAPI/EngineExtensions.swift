import AppKit

/// One extension toolbar action of a window, as plain values (Decision 10).
public struct ExtensionAction: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  /// The 16 pt icon at 2x, PNG.
  public var iconPNG: Data?
  public var isEnabled: Bool

  public init(id: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true) {
    self.id = id; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
  }
}

/// Extension actions, for engines that run extensions. A separate protocol: FakeEngine does not adopt it, and the
/// shell shows its Extensions control only when `engine is EngineExtensions`. Changes are announced with
/// `EngineWindowEvent.extensionActionsChanged`.
@MainActor
public protocol EngineExtensions: AnyObject {
  /// The window's actions in toolbar order, with icon and enabled state for its active tab.
  func extensionActions(in window: EngineWindowID) -> [ExtensionAction]
  /// Runs the action as a toolbar click; its popup is anchored to `anchor` (engine-drawn this week).
  func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView)
}
