import AppKit

/// Colors of the Archive window that ShellTokens and BrandTokens do not have (design/archive-search, section 9).
/// Everything else on the window reuses ShellTokens, SidebarMetrics and BrandTokens.
public enum ArchiveTokens {
  /// The search match highlight: mustard at 35 % behind the matched title text. A fill, never text.
  public static let matchHighlight = TokenPair(light: BrandTokens.Palette.mustard.atAlpha(0.35),
                                               dark: BrandTokens.Palette.mustard.atAlpha(0.35))
  /// The recessed field the list sits in, so the selected row lifts off it in `tabCurrent`.
  public static let listField = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.035), dark: .black(0.14))
  /// A Space chip's fill: the Space's color at this alpha over the window surface.
  public static let chipTintAlpha = 0.16
  /// Destructive titles (Clear Archive, the confirmation's Clear Archive button). The alerts design's
  /// `AlertTokens.destructiveText`: 6.20:1 on porcelain, 8.71:1 on graphite.
  public static let destructiveText = AlertTokens.destructiveText
  /// The 1 pt edge of the search field, chips and list field under Increase Contrast
  /// (`SettingsTokens.separatorIncreasedContrast` in the settings design).
  public static let increasedContrastEdge = TokenPair(light: .black(0.20), dark: .white(0.20))

  /// A Space chip's opaque fill over `surface`.
  public static func chipFill(_ color: RGBA, over surface: RGBA) -> RGBA {
    BrandTokens.composite(color.atAlpha(chipTintAlpha), over: surface)
  }
}

/// Geometry of the Archive window, in points (design section 9). The content view is flipped: y grows downwards.
enum ArchiveMetrics {
  static let barHeight: CGFloat = 52
  static let footerHeight: CGFloat = 52
  /// Traffic lights: close at x 20, then every 20 pt, vertically centered in the bar.
  static let trafficLightX: CGFloat = 20
  static let trafficLightSpacing: CGFloat = 20
  static let titleLeading: CGFloat = 92
  static let titleToField: CGFloat = 16
  static let fieldHeight: CGFloat = 32
  static let fieldRadius: CGFloat = 9
  static let filterButtonSize: CGFloat = 32
  static let filterButtonTrailing: CGFloat = 10
  static let fieldToFilterButton: CGFloat = 8
  static let chipHeight: CGFloat = 24
  static let chipBelow: CGFloat = 10
  static let sideMargin: CGFloat = 12
  static let chipSpacing: CGFloat = 6
  static let bannerBelow: CGFloat = 10
  static let listInset: CGFloat = 8
  static let listRadius: CGFloat = 10
  static let listPaddingY: CGFloat = 4
  static let rowInset: CGFloat = 4
  /// The row fill; rows sit at a 37 pt pitch (3 pt between fills), tighter than the sidebar's 41.
  static let rowHeight: CGFloat = 34
  static let rowPitch: CGFloat = 37
  static let loadingRowHeight: CGFloat = 30
  static let faviconLeading: CGFloat = 10
  static let titleGap: CGFloat = 8
  static let timeWidth: CGFloat = 58
  static let timeTrailing: CGFloat = 9
  static let dotSize: CGFloat = 7
  static let dotToTime: CGFloat = 8
  static let titleToTrailing: CGFloat = 16
  static let childIndent: CGFloat = 22
  static let footerLeading: CGFloat = 16
  static let footerTrailing: CGFloat = 12
  static let countToRestore: CGFloat = 14
  static let pillHeight: CGFloat = 28
  static let smallPillHeight: CGFloat = 24
  static let toastAboveFooter: CGFloat = 16
  /// Auto-load starts when the list shows a row this close to its end.
  static let autoLoadDistance = 10
}

extension RGBA {
  /// The same color at `alpha`.
  func atAlpha(_ alpha: Double) -> RGBA { RGBA(red: red, green: green, blue: blue, alpha: alpha, space: space) }
}
