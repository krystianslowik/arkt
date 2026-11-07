import Foundation

/// What a Space theme is drawn against: the window's appearance and the Increase Contrast setting.
public struct ThemeContext: Equatable, Sendable {
  public var appearance: ThemeFlavor
  public var increaseContrast: Bool

  public init(appearance: ThemeFlavor, increaseContrast: Bool = false) {
    self.appearance = appearance
    self.increaseContrast = increaseContrast
  }
}

/// Automatic contrast for Space themes (#410, design/theme-creator/README.md, "Automatic contrast").
///
/// Applied when drawing, never stored: the window draws `drawn(_:in:)`, the source keeps the user's colors. Per color
/// of the theme, in the current appearance:
///
/// 1. Composite the color at the theme's opacity over the window surface (`BrandTokens.surfaceBrand`). The theme's
///    overlay colors (#381) are drawn above it at their own alpha times the same opacity: the opacity is the overlay's
///    strength, and at each stop the overlay color at that stop's position is composited over the stop before measuring.
/// 2. Measure `primaryText`, composited at its own alpha, over that with WCAG 2.x (`Contrast.ratio`). Target 4.5:1,
///    7:1 with Increase Contrast.
/// 3. If it falls short, mix the color toward near-black #121214 (light text) or porcelain (dark text) in 1 % steps
///    until it passes, at most 50 %.
/// 4. If any color would need more than 50 % in the appearance's own tone, flip the text tone for the Space and run
///    step 3 with it.
///
/// One step comes first (a deviation from the README, listed in the pull request): when either tone already passes
/// with no mix at all, the appearance's own tone first, that tone is used and nothing is mixed. Without it a dark
/// preset in light mode would be mixed 35 to 49 % toward porcelain instead of keeping its light text, and the presets
/// would not pass unchanged.
public enum ThemeContrast {
  /// The dark end of the pad and of the mix (#410). Belongs with the theme code, not the brand palette.
  public static let nearBlack = RGBA.srgb(hex: 0x121214)
  /// The light end of the mix: porcelain.
  public static let porcelain = BrandTokens.Palette.porcelain
  /// The largest mix toward the end color before the tone flips.
  public static let maximumMix = 0.5
  /// Mix steps: 1 %, up to `maximumMix`.
  static let mixSteps = 50

  /// The contrast `primaryText` must reach over every drawn color.
  public static func target(increaseContrast: Bool) -> Double { increaseContrast ? 7 : Contrast.minimumText }

  /// The window surface a theme covers at its opacity: porcelain in light, graphite in dark.
  public static func surface(_ appearance: ThemeFlavor) -> RGBA { BrandTokens.surfaceBrand.resolve(appearance) }

  /// The colors to draw, each stop's mix (0...`maximumMix`), and the sidebar's text tone as a flavor (`.dark` draws
  /// light text).
  public struct Resolution: Equatable, Sendable {
    public var tone: ThemeFlavor
    public var colors: [RGBA]
    public var mixes: [Double]
    /// The overlay colors to draw: each with its alpha times the opacity (empty without overlay colors).
    public var overlay: [RGBA] = []
  }

  /// The drawn colors and tone for `stops` at `opacity`, with `overlay` colors above them; nil without stops.
  public static func resolve(stops: [RGBA], opacity: Double, overlay: [RGBA] = [],
                             in context: ThemeContext) -> Resolution? {
    guard !stops.isEmpty else { return nil }
    let opacity = min(max(opacity, 0), 1)
    let tints = overlayTints(overlay, stops: stops.count, opacity: opacity)
    func fits(_ tone: ThemeFlavor, _ mixes: [Double?]) -> Bool {
      stops.indices.allSatisfy { index in
        mixes[index].map { passes(stops[index], mix: $0, tone: tone, opacity: opacity, tint: tints[index], in: context) }
          ?? false
      }
    }
    func result(_ tone: ThemeFlavor, _ mixes: [Double]) -> Resolution {
      resolution(stops, mixes: mixes, tone: tone, opacity: opacity, overlay: overlay, in: context)
    }
    let own = context.appearance
    let other: ThemeFlavor = own == .light ? .dark : .light
    let none = stops.map { _ in Double?.some(0) }
    for tone in [own, other] where fits(tone, none) { return result(tone, none.map { $0 ?? 0 }) }
    for tone in [own, other] {
      let steps = stops.indices.map {
        requiredStep(stops[$0], tone: tone, opacity: opacity, tint: tints[$0], in: context)
      }
      guard steps.allSatisfy({ $0 != nil }) else { continue }
      return result(tone, steps.map { Double($0 ?? 0) / 100 })
    }
    // Neither tone reaches the target within 50 %: the appearance's tone at the strongest mix.
    return result(own, stops.map { _ in maximumMix })
  }

  /// `theme` as the window draws it in `context`: resolved, opaque colors at opacity 1 and the resolved tone in
  /// `isDark`, and overlay colors whose alpha carries the opacity. Texture and strength are kept. A theme without colors is returned as it is.
  public static func drawn(_ theme: SpaceThemeInfo, in context: ThemeContext) -> SpaceThemeInfo {
    guard let resolution = resolve(stops: theme.baseColors, opacity: theme.opacity, overlay: theme.overlayColors,
                                   in: context) else { return theme }
    var drawn = theme
    drawn.baseColors = resolution.colors
    drawn.overlayColors = resolution.overlay
    drawn.opacity = 1
    drawn.isDark = resolution.tone == .dark
    return drawn
  }

  /// The overlay color above each of `count` evenly spaced stops, its alpha times `opacity`; clear where there is no
  /// overlay. The overlay gradient runs over the same diagonal as the base, so a stop's position is its index over
  /// `count - 1`.
  static func overlayTints(_ overlay: [RGBA], stops count: Int, opacity: Double) -> [RGBA?] {
    guard !overlay.isEmpty else { return Array(repeating: nil, count: count) }
    return (0..<count).map { index in
      var tint = ThemeGradient.sample(overlay, at: count > 1 ? Double(index) / Double(count - 1) : 0)
      tint.alpha *= opacity
      return tint
    }
  }

  /// `stop` mixed `mix` toward the end color for `tone`, at `opacity` over the surface, with `tint` above it. Keeps
  /// the stop's color space; with no mix at full opacity and no tint it is the stop itself.
  static func composite(_ stop: RGBA, mix: Double, tone: ThemeFlavor, opacity: Double, tint: RGBA? = nil,
                        in context: ThemeContext) -> RGBA {
    let end = tone == .dark ? nearBlack : porcelain
    let mixed = mix > 0 ? RGBA.mix(stop, end, mix) : stop
    let alpha = mixed.alpha * opacity
    let surface = surface(context.appearance)
    func over(_ top: Double, _ bottom: Double, _ alpha: Double) -> Double { top * alpha + bottom * (1 - alpha) }
    let base = RGBA(red: over(mixed.red, surface.red, alpha), green: over(mixed.green, surface.green, alpha),
                    blue: over(mixed.blue, surface.blue, alpha), alpha: 1, space: stop.space)
    guard let tint, tint.alpha > 0 else { return base }
    // A theme keeps one color space for its colors and its overlay, so the components blend as they are.
    return RGBA(red: over(tint.red, base.red, tint.alpha), green: over(tint.green, base.green, tint.alpha),
                blue: over(tint.blue, base.blue, tint.alpha), alpha: 1, space: base.space)
  }

  private static func passes(_ stop: RGBA, mix: Double, tone: ThemeFlavor, opacity: Double, tint: RGBA?,
                             in context: ThemeContext) -> Bool {
    let background = composite(stop, mix: mix, tone: tone, opacity: opacity, tint: tint, in: context)
    let text = BrandTokens.composite(ShellTokens.primaryText.resolve(tone), over: background)
    return Contrast.ratio(text, background) >= target(increaseContrast: context.increaseContrast)
  }

  /// The smallest mix, in 1 % steps, at which `stop` passes in `tone`; nil past `maximumMix`.
  private static func requiredStep(_ stop: RGBA, tone: ThemeFlavor, opacity: Double, tint: RGBA?,
                                   in context: ThemeContext) -> Int? {
    (0...mixSteps).first { passes(stop, mix: Double($0) / 100, tone: tone, opacity: opacity, tint: tint, in: context) }
  }

  private static func resolution(_ stops: [RGBA], mixes: [Double], tone: ThemeFlavor, opacity: Double,
                                 overlay: [RGBA], in context: ThemeContext) -> Resolution {
    let colors = zip(stops, mixes).map { composite($0, mix: $1, tone: tone, opacity: opacity, in: context) }
    let scaled = overlay.map { color -> RGBA in
      var color = color
      color.alpha *= opacity
      return color
    }
    return Resolution(tone: tone, colors: colors, mixes: mixes, overlay: scaled)
  }
}
