/// Arkt's brand colors, kept apart from the Arc-parity `ShellTokens` so brand work never moves parity values.
///
/// Every token is an sRGB `TokenPair`; all are opaque except the hairlines and control fills, which are graphite or
/// porcelain at a low alpha over `surfaceBrand`. `BrandTokensTests` checks the WCAG 2.x contrast of each text and UI
/// pair (translucent ones after `composite(_:over:)`), and that `Palette` matches
/// `design/brand/tokens/brand-tokens.json`.
///
/// Mustard (`accent`) is about 1.8:1 on porcelain: it is a fill, never text or a focus ring on light surfaces. Use
/// `accentText` for accent-colored text and `onAccent` for text and glyphs on accent fills.
///
/// Nothing here is wired into a global `AccentColor` or app-wide accent; controls adopt these tokens one at a time.
public enum BrandTokens {
  /// Raw brand colors. Tokens below refer to these; the first six mirror `brand-tokens.json`.
  public enum Palette {
    public static let mustard = RGBA.srgb(hex: 0xE9B520)
    public static let mustardHighlight = RGBA.srgb(hex: 0xF3CA3D)
    public static let mustardShade = RGBA.srgb(hex: 0xDCA319)
    public static let foldShadow = RGBA.srgb(hex: 0xA96E12)
    public static let porcelain = RGBA.srgb(hex: 0xFAF9F5)
    public static let graphite = RGBA.srgb(hex: 0x202321)
    /// Darkened mustard for accent text on light surfaces (about 5.6:1 on porcelain). Not in the brand kit's JSON,
    /// which only lists fill colors.
    public static let accentTextOnLight = RGBA.srgb(hex: 0x8A5A0E)
  }

  /// Accent fill (buttons, badges, selection). Fill only, never text.
  public static let accent = TokenPair(light: Palette.mustard, dark: Palette.mustard)
  /// Accent fill on hover.
  public static let accentHighlight = TokenPair(light: Palette.mustardHighlight, dark: Palette.mustardHighlight)
  /// Accent fill while pressed.
  public static let accentPressed = TokenPair(light: Palette.mustardShade, dark: Palette.mustardShade)
  /// Text and glyphs on any accent fill.
  public static let onAccent = TokenPair(light: Palette.graphite, dark: Palette.graphite)
  /// Accent-colored text. Light uses the darkened mustard because mustard fails as text on light surfaces. Dark uses
  /// mustard itself: it already reaches about 8.4:1 on graphite, so a separate shade would only dull the brand color.
  public static let accentText = TokenPair(light: Palette.accentTextOnLight, dark: Palette.mustard)
  /// The fold shadow in the logo mark. Decorative only: below 4.5:1 on both surfaces, so never text.
  public static let foldShadow = TokenPair(light: Palette.foldShadow, dark: Palette.foldShadow)
  /// Branded surfaces such as About and first run.
  public static let surfaceBrand = TokenPair(light: Palette.porcelain, dark: Palette.graphite)
  /// Keyboard focus ring on branded surfaces. Graphite on light surfaces, where mustard would fail 3:1.
  public static let focusRing = TokenPair(light: Palette.graphite, dark: Palette.mustard)

  // MARK: - First run (onboarding spec, section 5)

  /// Titles and labels on brand surfaces and glass: 15.06:1 on `surfaceBrand`.
  public static let brandTextPrimary = TokenPair(light: Palette.graphite, dark: Palette.porcelain)
  /// Ledes, count labels and the footer: 5.62:1 (light) and 8.06:1 (dark) on `surfaceBrand`.
  public static let brandTextSecondary = TokenPair(light: .srgb(hex: 0x62655F), dark: .srgb(hex: 0xB6BAB3))
  /// `brandTextSecondary` under Increase Contrast: 9.99:1 and 12.58:1.
  public static let brandTextSecondaryContrast = TokenPair(light: .srgb(hex: 0x3D403B), dark: .srgb(hex: 0xE3E6DF))
  /// The glass button's and the option pill's edge. Decorative, no contrast minimum.
  public static let brandHairline = TokenPair(light: .srgb(hex: 0x202321, alpha: 0.12),
                                              dark: .srgb(hex: 0xFAF9F5, alpha: 0.12))
  /// Hairlines under Increase Contrast: 3:1 or more against `surfaceBrand` (3.13:1 light, 4.8:1 dark). Light is
  /// graphite at 50 %, not the spec's 45 %, which composites to 2.73:1.
  public static let brandHairlineContrast = TokenPair(light: .srgb(hex: 0x202321, alpha: 0.50),
                                                      dark: .srgb(hex: 0xFAF9F5, alpha: 0.50))
  /// Hover of the quiet buttons, the option pill and the segmented track.
  public static let brandControlFill = TokenPair(light: .srgb(hex: 0x202321, alpha: 0.05),
                                                 dark: .srgb(hex: 0xFAF9F5, alpha: 0.06))
  /// Pressed fills of the glass and quiet buttons.
  public static let brandControlFillPressed = TokenPair(light: .srgb(hex: 0x202321, alpha: 0.10),
                                                        dark: .srgb(hex: 0xFAF9F5, alpha: 0.12))

  /// Source-over of a translucent `top` on an opaque `bottom`, both read as sRGB; the result is opaque. For contrast
  /// checks of the translucent tokens above.
  public static func composite(_ top: RGBA, over bottom: RGBA) -> RGBA {
    let a = top.alpha
    return RGBA(red: top.red * a + bottom.red * (1 - a), green: top.green * a + bottom.green * (1 - a),
                blue: top.blue * a + bottom.blue * (1 - a), alpha: 1)
  }
}
