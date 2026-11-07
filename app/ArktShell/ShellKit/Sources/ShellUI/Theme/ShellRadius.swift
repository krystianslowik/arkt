import CoreGraphics

/// Corner radii for the chrome, named by role (#620). Surfaces set a radius from this scale or from their own metric
/// enum, never from a number at the assignment (`CornerRadiusLintTests`). A value that fits no role stays in the
/// surface's metric enum under its own name. Changing a value here moves every surface of that role at once.
public enum ShellRadius {
  /// Row-shaped fills: sidebar and Settings rows, the command bar's selected row, the sidebar drop slot.
  public static let row: CGFloat = 9  // TODO(measure): Arc's row radius (#77)
  /// Recessed fields that hold rows or text: Settings groups, the Archive list, the dialog list, the import field.
  public static let field: CGFloat = 10
  /// Empty-state tiles (Archive, Library, Extensions, Settings) and other glyph tiles.
  public static let tile: CGFloat = 12
  /// The web content card and the cards that preview one (`ShellMetrics.cardCornerRadius`).
  public static let card: CGFloat = 10
  /// Floating panels over the window: Little Arkt, the tab switcher, Edit Pin, dialog panels, multi-line toasts.
  public static let popover: CGFloat = 12
  /// Sheets and alerts.
  public static let sheet: CGFloat = 14
  /// A capsule: half the control's height (toasts, the find bar, the zoom pill, round buttons).
  public static func pill(height: CGFloat) -> CGFloat { height / 2 }
}
