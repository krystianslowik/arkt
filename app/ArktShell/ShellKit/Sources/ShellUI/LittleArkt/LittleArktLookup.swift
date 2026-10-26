import AppKit

/// The quick lookup bar's copy and screen geometry (#354, docs/design/little-arkt.md "Quick lookup"). Pure values, so
/// they are unit-tested away from the window server; the bar itself is `LittleArktLookupController`.
public enum LittleArktLookup {
  /// The tag before the input.
  public static let tag = "Little Arkt"
  /// The field's visible placeholder: the command bar's, unchanged.
  public static let placeholder = "Search or Enter URL..."
  /// The field's accessibility label, as the design's VoiceOver note words it.
  public static let fieldLabel = "Little Arkt: Search or Enter URL"
  /// File > New Little Arkt Window (KB-044).
  public static let menuTitle = "New Little Arkt Window"
  /// The Settings > Links row (BH-131); off by default (decision 2026-10-25).
  public static let settingLabel = "Open Little Arkt when I press \u{2325}\u{2318}N"
  /// Under the switch when another app holds the combination.
  public static let conflictMessage = "\u{2325}\u{2318}N is used by another app."

  /// The command bar panel on the current screen: 766 pt wide (narrower on small screens), 60 pt input, 50 pt rows,
  /// its top at 34 % of the screen. `screen` is a visible frame in screen coordinates.
  public static func frame(in screen: CGRect, rowCount: Int) -> CGRect {
    CommandBarGeometry.frame(parentFrame: screen,
                             contentHeight: CommandBarGeometry.contentHeight(rowCount: rowCount))
  }
}
