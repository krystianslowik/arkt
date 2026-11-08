import AppKit

/// One step of the chrome's type: a system font size and weight. A value, so the roles can be shared constants.
public struct ShellTypeStyle: Equatable, Sendable {
  public var size: CGFloat
  public var weight: NSFont.Weight

  public init(size: CGFloat, weight: NSFont.Weight) {
    self.size = size
    self.weight = weight
  }

  /// The system font at this size and weight. AppKit caches system fonts, so reading it is cheap.
  public var font: NSFont { .systemFont(ofSize: size, weight: weight) }

  /// The same size at another weight, for a label that changes weight with its state.
  public func weight(_ weight: NSFont.Weight) -> ShellTypeStyle { ShellTypeStyle(size: size, weight: weight) }
}

/// The chrome's type roles (#621), in the system font. Surfaces take a font from a role or from their own metric
/// enum, never from a number at the call (`SystemFontLintTests`). A size that fits no role stays in the surface's
/// metric enum under its own name. Changing a value here moves every surface of that role at once. The brand face for
/// first run and other moments is `BrandType`.
public enum ShellType {
  /// Titles of rows in lists: tab switcher, Archive, downloads, import, toasts. Sidebar tab rows keep their measured
  /// `SidebarMetrics.titleFontSize`.
  public static let rowTitle = ShellTypeStyle(size: 13, weight: .medium)
  /// Running text, fields and plain buttons.
  public static let body = ShellTypeStyle(size: 13, weight: .regular)
  /// The title line of a panel or window (page info host, Archive and Library titles, Edit Pin).
  public static let bodyEmphasis = ShellTypeStyle(size: 13, weight: .semibold)
  /// Secondary lines under a title: subtitles, details, status and notices.
  public static let caption = ShellTypeStyle(size: 12, weight: .regular)
  /// Group headings and labels set in the caption size.
  public static let captionEmphasis = ShellTypeStyle(size: 12, weight: .semibold)
  /// Chip and pill labels: Archive filter chips, command bar filter pills.
  public static let chip = ShellTypeStyle(size: 12, weight: .medium)
  /// Hints and metadata: the command bar hint strip, preview meta, download status.
  public static let hint = ShellTypeStyle(size: 11.5, weight: .regular)
  /// The smallest running text: errors under a field, read-only notes, the tab switcher's Space name.
  public static let footnote = ShellTypeStyle(size: 11, weight: .regular)
  /// Section headers over lists: command bar sections, the sidebar footer, page info permissions, field labels.
  public static let sectionHeader = ShellTypeStyle(size: 11, weight: .semibold)
  /// Dialog, sheet and empty-panel titles.
  public static let dialogTitle = ShellTypeStyle(size: 15, weight: .semibold)
  /// The command bar's input line.
  public static let commandInput = ShellTypeStyle(size: 22, weight: .regular)
  /// The Toolbar's URL text (#623). The sidebar URL bar keeps `SidebarMetrics.urlBarFontSize`.
  /// TODO(measure): the reference Toolbar text reads about 11 to 12 pt from its cap height; 12 is the candidate,
  /// kept at 13 until #77 checklist items 4 and 9 confirm it.
  public static let toolbarURL = ShellTypeStyle(size: 13, weight: .medium)
}
