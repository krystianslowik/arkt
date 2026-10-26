import AppKit

/// Colors of the Settings window that ShellTokens, BrandTokens and ArchiveTokens do not have
/// (docs/design/settings.md, section 4). Everything else reuses the sidebar's and the Archive's tokens.
public enum SettingsTokens {
  /// The recessed field a group of rows sits in: the Archive's list field.
  public static let groupField = ArchiveTokens.listField
  /// A switch's on fill: graphite on porcelain, porcelain on graphite. Mustard is kept for the one primary action.
  public static let switchOn = TokenPair(light: BrandTokens.Palette.graphite, dark: .srgb(hex: 0xF4F3EF))
  /// The knob of a switch that is on: the opposite of `switchOn`.
  public static let switchKnobOn = TokenPair(light: .white(1), dark: BrandTokens.Palette.graphite)
  /// The knob of a switch that is off.
  public static let switchKnobOff = TokenPair(light: .white(1), dark: .white(0.84))
  /// The chrome over scrolled content, drawn over the `.titlebar` vibrancy; Reduce Transparency draws
  /// `surfaceBrand` opaque instead.
  public static let toolbarMaterial = TokenPair(light: BrandTokens.Palette.porcelain.atAlpha(0.82),
                                                dark: BrandTokens.Palette.graphite.atAlpha(0.80))
  /// Group, pop-up and search field edges under Increase Contrast.
  public static let separatorIncreasedContrast = TokenPair(light: .black(0.20), dark: .white(0.20))
  /// A disabled control's opacity (decision 4: rows for features not built yet).
  public static let disabledControlAlpha: CGFloat = 0.42
}

/// Colors shared by alerts, sheets and destructive actions (docs/design/alerts-sheets-toasts.md).
public enum AlertTokens {
  /// Destructive links and button titles: 6.20:1 on porcelain, 8.71:1 on graphite, and at least 4.5:1 on the neutral
  /// button fills and the Settings group field. Destructive buttons never use the pressed fill.
  public static let destructiveText = TokenPair(light: .srgb(hex: 0xB3261E), dark: .srgb(hex: 0xFFAAA2))
}

/// Geometry of the Settings window, in points (docs/design/settings.md, section 4). Content views are flipped.
public enum SettingsMetrics {
  public static let windowWidth: CGFloat = 680
  /// The unified chrome: title and pane bar.
  public static let chromeHeight: CGFloat = 84
  /// The window is at most the screen's visible height minus this.
  public static let screenMargin: CGFloat = 120
  static let titleCenterY: CGFloat = 20
  static let trafficLightX: CGFloat = 20
  static let trafficLightSpacing: CGFloat = 20
  static let paneBarTop: CGFloat = 36
  static let paneItemSize = NSSize(width: 84, height: 44)
  static let paneItemGap: CGFloat = 2
  static let paneItemRadius: CGFloat = 9
  static let paneGlyph: CGFloat = 16
  static let paneGlyphToLabel: CGFloat = 3
  static let contentTop: CGFloat = 8
  static let contentSide: CGFloat = 16
  static let contentBottom: CGFloat = 20
  static let sectionTitleLeading: CGFloat = 10
  static let sectionTitleBelow: CGFloat = 6
  static let sectionGap: CGFloat = 18
  static let groupRadius: CGFloat = 10
  static let groupPadding: CGFloat = 4
  static let rowGap: CGFloat = 2
  static let rowMinHeight: CGFloat = 36
  static let rowRadius: CGFloat = 9
  static let rowPaddingTop: CGFloat = 6
  static let rowPaddingTrailing: CGFloat = 8
  static let rowPaddingBottom: CGFloat = 6
  static let rowPaddingLeading: CGFloat = 10
  static let rowGapToControl: CGFloat = 12
  static let captionBelowLabel: CGFloat = 1
  static let addRowHeight: CGFloat = 34
  static let addRowLeading: CGFloat = 14
  static let noteBelow: CGFloat = 8
  static let noteMaxWidth: CGFloat = 560
  static let switchSize = NSSize(width: 32, height: 20)
  static let knob: CGFloat = 16
  static let popUpHeight: CGFloat = 26
  static let popUpRadius: CGFloat = 8
  static let keycapHeight: CGFloat = 22
  static let searchHeight: CGFloat = 32
  static let searchBelow: CGFloat = 14
}
