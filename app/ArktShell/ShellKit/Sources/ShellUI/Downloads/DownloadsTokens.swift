import AppKit

/// Colors of the Downloads UI that the shell's tokens do not name (design/downloads). Everything else on it reuses
/// `ShellTokens`, `BrandTokens` and `ArchiveTokens`.
public enum DownloadsTokens {
  /// The progress fill is graphite (the maintainer's pick): `primaryText`, graphite at 90 % in light and white at
  /// 84 % in dark. The track under it is the hovered row level.
  public static let progressFill = ShellTokens.primaryText
  public static let progressTrack = ShellTokens.sidebarItemHovered
  /// A row's resting fill and its hover and selection fill.
  public static let rowFill = ShellTokens.sidebarItemBackground
  /// The tile of a blocked file: a neutral fill with `primaryText` on it, never a file color.
  public static let warnTileFill = ShellTokens.sidebarItemHovered
  /// White on a file tile, in light and dark.
  public static let tileText = RGBA.white(1)
  /// The unseen dot on the Library button.
  public static let dot = ShellTokens.primaryText
}

/// Geometry of the Downloads UI, in points (design/downloads, Directions and Library).
enum DownloadsMetrics {
  // The Library button's ring.
  static let ringSize: CGFloat = 28
  static let ringLineWidth: CGFloat = 2.2
  static let glyphSize: CGFloat = 16
  static let dotSize: CGFloat = 8
  /// The pointer rests this long on the button before the popover lists the recent files.
  static let hoverDelay: TimeInterval = 0.4
  /// The popover stays this long after the pointer left the button and it.
  static let leaveGrace: TimeInterval = 0.25
  static let recentLimit = 6

  // The popover.
  static let popoverWidth: CGFloat = 316
  static let popoverPadding: CGFloat = 6
  static let popoverCorner: CGFloat = 14
  static let popoverRowMin: CGFloat = 52
  static let popoverFooter: CGFloat = 40
  static let popoverGap: CGFloat = 8

  // Rows.
  static let tilePopover: CGFloat = 32
  static let tileLibrary: CGFloat = 36
  static let barHeight: CGFloat = 3
  static let iconButton: CGFloat = 24
  static let pill: CGFloat = 24
  static let rowCorner: CGFloat = 9
  static let rowInset: CGFloat = 8

  // The Library window.
  static let libraryContent = NSSize(width: 800, height: 540)
  static let libraryMinimum = NSSize(width: 560, height: 320)
  static let barHeightWindow: CGFloat = 52
  static let railWidth: CGFloat = 176
  static let railRow: CGFloat = 32
  static let libraryRow: CGFloat = 56
  static let footerHeight: CGFloat = 44
  static let groupHeader: CGFloat = 32
}
