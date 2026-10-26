import AppKit

/// Colors of the dialogs and toasts (docs/design/alerts-sheets-toasts.md, sections 3.2 and 4.2). Values other surfaces
/// already own are forwarded, not copied: the destructive red is the Archive's, the shadows and edges are the floating
/// overlays' and pills' (`ShellTokens`). The engine mirrors these by value (`arkt_dialog_sheet.mm`).
public enum AlertTokens {
  /// Destructive titles (Delete Space, Remove, Clear Archive): light #B3261E, dark #FFAAA2; at least 4.5:1 on the
  /// neutral pill idle and hovered (`AlertTokensTests`).
  public static let destructiveText = ArchiveTokens.destructiveText
  /// Dialog surfaces: porcelain, graphite in dark.
  public static let dialogSurface = BrandTokens.surfaceBrand
  /// Sheets, panels and alerts: 18 / 48 and 3 / 10 drops plus `overlayEdge`.
  public static let overlayShadow = ShellTokens.overlayShadow
  public static let overlayEdge = ShellTokens.overlayEdge
  /// Toasts: 8 / 24 and 1 / 3 drops plus `toastEdge`.
  public static let toastShadow = ShellTokens.toastShadow
  public static let toastEdge = ShellTokens.toastEdge
  /// Dialog edges, the list field and the toast's action pill under Increase Contrast.
  public static let increasedContrastEdge = ArchiveTokens.increasedContrastEdge
  /// How much of the Space theme's first color stop the toast surface takes (decision 2).
  public static let toastTintLight = 0.22
  public static let toastTintDark = 0.30
  /// The toast glyph's strength over `toastText`.
  public static let toastGlyphAlpha = TokenPair(light: .white(0.64), dark: .white(0.72))

  /// The toast fill for a Space theme: `ShellTokens.toastSurface` in the theme's flavor with the theme's first color
  /// stop mixed in (22 % light, 30 % dark), as a plain fill. The default theme (a plain white or black first stop of
  /// its own flavor) keeps plain `toastSurface`. `opaque` (Reduce Transparency) draws it at alpha 1 instead of 0.96.
  public static func toastSurface(theme: SpaceThemeInfo?, opaque: Bool = false) -> RGBA {
    let flavor = theme?.flavor ?? .light
    let base = ShellTokens.toastSurface.resolve(flavor)
    var surface = base
    if let stop = theme?.baseColors.first, !isPlainDefault(stop, flavor: flavor) {
      surface = mixed(base, toward: stop, amount: flavor == .light ? toastTintLight : toastTintDark)
    }
    if opaque { surface.alpha = 1 }
    return surface
  }

  /// White over a light theme or black over a dark one adds no color: the toast stays plain.
  private static func isPlainDefault(_ stop: RGBA, flavor: ThemeFlavor) -> Bool {
    let channels = [stop.red, stop.green, stop.blue]
    return flavor == .light ? channels.allSatisfy { $0 >= 0.99 } : channels.allSatisfy { $0 <= 0.01 }
  }

  /// `base` moved `amount` of the way to `stop`'s color, in sRGB, keeping `base`'s alpha.
  private static func mixed(_ base: RGBA, toward stop: RGBA, amount: Double) -> RGBA {
    let a = srgb(base)
    let b = srgb(stop)
    var result = RGBA.mix(a, b, amount)
    result.alpha = base.alpha
    result.space = .sRGB
    return result
  }

  private static func srgb(_ color: RGBA) -> RGBA {
    guard color.space == .displayP3, let converted = color.nsColor().usingColorSpace(.sRGB) else { return color }
    return RGBA(red: Double(converted.redComponent), green: Double(converted.greenComponent),
                blue: Double(converted.blueComponent), alpha: color.alpha)
  }
}
