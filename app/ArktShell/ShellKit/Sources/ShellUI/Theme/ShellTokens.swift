import AppKit

public enum ThemeFlavor: Sendable {
  case light, dark

  /// `.darkAqua` (and its high-contrast/vibrant variants) map to `.dark`, everything else to `.light`.
  @MainActor
  public init(appearance: NSAppearance) {
    self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
}

public struct TokenPair: Sendable, Equatable {
  public let light: RGBA
  public let dark: RGBA
  public init(light: RGBA, dark: RGBA) { self.light = light; self.dark = dark }
  public func resolve(_ flavor: ThemeFlavor) -> RGBA { flavor == .light ? light : dark }
}

/// Arc's approach: chrome is black/white at low alpha over the Space theme.
/// Levels follow Arc's token levels; Arkt owns the values and may diverge.
public enum ShellTokens {
  public static let cardBorder = TokenPair(light: .black(0.10), dark: .white(0.20))       // FloatingScrimBorder
  public static let cardShadow = TokenPair(light: .black(0.20), dark: .black(0))           // Shadow
  /// The hover-revealed sidebar floating over the page (BH-004). Unlike the card it needs a shadow in dark too: its
  /// edge sits on page content, not on the theme. TODO(measure): RT-10.
  public static let sidebarOverlayShadow = TokenPair(light: .black(0.22), dark: .black(0.45))
  /// Icon-only (idle page dots, bottom-bar symbols, the hover close X): WCAG non-text 3:1 over every shipped
  /// Space theme and row fill. Raised from Arc's 0.30 / 0.45 (#72), and light from 0.48 to 0.49 for the Blossom
  /// family's sRGB pink stop (#310); worst cases are the close X on a hovered row over that stop (light) and on
  /// `tabCurrent` over the Dev theme's light stop (dark).
  public static let sidebarForeground = TokenPair(light: .black(0.49), dark: .white(0.57))
  public static let sidebarItemBackground = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.05), dark: .p3(hex: 0xFAFBFF, alpha: 0.10))
  public static let sidebarItemHovered = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.10), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  /// Fill of the letter tile for rows and favorites without a favicon; `primaryText` is drawn on it. Light keeps
  /// `sidebarItemHovered`; dark darkens instead of lightening (#153): the lighter chip held the letter below 4.5:1
  /// on `tabCurrent` over the Dev theme's light stop even at white 1.0.
  public static let letterTileFill = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.10), dark: .p3(hex: 0x0E0F10, alpha: 0.15))
  /// Text (row titles, row symbols, the active page dot): WCAG AA 4.5:1 over every shipped Space theme and row
  /// fill. Dark raised from Arc's 0.80 (#146); the worst case is `tabCurrent` over the Dev theme's light stop.
  public static let primaryText = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.90), dark: .white(0.84))
  /// Text (Space title, URL bar label, toolbar buttons): WCAG AA 4.5:1 over every shipped Space theme, the URL bar
  /// fills and the toolbar strip. Raised from Arc's 0.50 / 0.50 (#72), and light from 0.64 to 0.65 for the Blossom
  /// family's sRGB pink stop (#310), then to 0.66 for the Personal sample's pink stop darkened by its grain (the
  /// texture multiplies, #120); the worst case is the hovered URL bar (`sidebarItemHovered`) over that stop (light)
  /// and the Dev theme's light stop (dark).
  public static let secondaryText = TokenPair(light: .black(0.66), dark: .white(0.76))
  // Tab cell states (C3 tests these levels).
  public static let tabCurrent = TokenPair(light: .white(0.85), dark: .p3(hex: 0xFAFBFF, alpha: 0.20))
  public static let tabContentVisible = TokenPair(light: .white(0.70), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  public static let tabPrevious = TokenPair(light: .white(0.32), dark: .p3(hex: 0xFAFBFF, alpha: 0.08))
  public static let tabPreviousHovered = TokenPair(light: .white(0.50), dark: .p3(hex: 0xFAFBFF, alpha: 0.12))
  public static let tabPressed = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.065), dark: .p3(hex: 0xFAFBFF, alpha: 0.065))
  public static let tabCurrentShadow = TokenPair(light: .black(0.20), dark: .black(0))
  // Command bar (always dark surface, C5).
  public static let commandBarSurface = RGBA.p3(hex: 0x1C1C20, alpha: 0.98)                 // TODO(measure)
  public static let commandBarText = RGBA.white(0.80)
  public static let commandBarSecondaryText = RGBA.white(0.33)
  public static let commandBarDivider = RGBA.white(0.10)
  public static let commandBarSelectedRow = RGBA.white(0.10)                                // TODO(measure)
  public static let commandBarBorder = RGBA.white(0.10)
  // Toasts (E3a): dark text on a light fill over light themes, light text on a dark fill over dark ones.
  public static let toastSurface = TokenPair(light: .white(0.96), dark: .p3(hex: 0x1C1C20, alpha: 0.96))  // TODO(measure)
  public static let toastText = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.90), dark: .white(0.85))
  // Toolbar over the page (KB-018, BH-032): an opaque strip in the card, a hairline below it.
  /// Arc 1.168 draws the strip on the content card's own surface (sRGB #878787 in the one dark theme measured, window
  /// not key). Not applied: `secondaryText` reaches only about 2.8:1 there and Arc's own placeholder 2.75:1, below
  /// 4.5:1, so Arkt keeps these opaque surfaces (accessibility first, see `ShellTokensContrastTests`). Light, a key
  /// window and other themes were not measured.
  public static let toolbarSurface = TokenPair(light: .white(1), dark: .p3(hex: 0x1C1C20, alpha: 1))
  /// The Toolbar's 1 pt hairline. Dark: Arc 1.168, about white 5 % over the strip, measured in a non-key dark 2x
  /// window (a key window may draw it brighter). Light: not measured, the card border's level.
  public static let toolbarHairline = TokenPair(light: .black(0.10), dark: .white(0.05))
  /// The sidebar hairline between pinned and Today. Dark: Arc 1.168, about white 7.5 % over the sidebar, measured in a
  /// non-key dark 2x window. Light: not measured, the hovered item level as before. Decorative, no contrast minimum.
  public static let sidebarDivider = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.10), dark: .white(0.075))
  /// Floating overlays (the tab switcher; the alerts design's `overlayShadow`): 18 / 48 and 3 / 10 drops (CSS blur,
  /// so radius 24 and 5), plus `overlayEdge`.
  public static let overlayShadow = ShadowToken(color: TokenPair(light: .black(0.22), dark: .black(0.55)), radius: 24,
                                                offsetY: 18,
                                                contactColor: TokenPair(light: .black(0.10), dark: .black(0.30)),
                                                contactRadius: 5, contactOffsetY: 3)
  /// The 0.5 pt edge of a floating overlay.
  public static let overlayEdge = TokenPair(light: .black(0.12), dark: .white(0.20))
  /// Small floating pills (the sidebar overflow pill; the alerts design's `toastShadow`): 8 / 24 and 1 / 3 drops,
  /// plus `toastEdge`.
  public static let toastShadow = ShadowToken(color: TokenPair(light: .black(0.16), dark: .black(0.45)), radius: 12,
                                              offsetY: 8,
                                              contactColor: TokenPair(light: .black(0.08), dark: .black(0.30)),
                                              contactRadius: 1.5, contactOffsetY: 1)
  /// The 0.5 pt edge of a toast-style pill.
  public static let toastEdge = TokenPair(light: .black(0.10), dark: .white(0.14))
  // Space theme background (C6).
  /// Texture overlay alpha at noiseFactor 1. Arc multiplies the gradient by `mix(1, texel, alpha)` with alpha the
  /// noiseFactor itself; each texture's strength is in its texels (`ThemeTexture`), not in this scale (#120).
  public static let themeTextureMaxOpacity = 1.0
}
