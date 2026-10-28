import Foundation
import Testing
@testable import ShellUI

// MARK: - Measurement

/// Contrast of the translucent `ShellTokens` chrome colors as they are actually seen: composited over the Space theme
/// surfaces the app ships, then measured with `Contrast` (WCAG 2.x, sRGB).
///
/// - Compositing is source-over in Display P3 encoded components, the space the shipped themes are written in.
///   Black and white are the same in sRGB and P3, so the black/white text levels composite exactly.
/// - The composited color is converted to sRGB (unclamped) before `Contrast.ratio`, so P3 luminance is not
///   read through sRGB coefficients.
/// - Gradients are sampled between every pair of stops in OKLab (`ThemeGradient.mix`), the interpolation the window
///   draws (#381); the luminance of a blend can dip below both ends. A theme's overlay colors are composited over
///   each sample at the same position.
/// - The texture multiplies the gradient (#120), so it darkens: each sample is also measured multiplied by the
///   theme's mean texture factor (`SpaceThemeInfo.meanTextureFactor`, encoded components).
/// - Arc-imported themes are user data and not covered; the measured set is what ships: the bridge default, the
///   empty-theme fallback and the sample Spaces.
enum ShellContrastProbe {
  /// A fill drawn between the theme and the foreground (URL bar, row states, toolbar strip).
  typealias Layer = RGBA

  /// Gradient samples per pair of adjacent stops.
  static let samplesPerSegment = 32

  /// Every theme background point the sidebar can sit on in `flavor`.
  @MainActor
  static func themeSurfaces(_ flavor: ThemeFlavor) -> [RGBA] {
    shippedThemes().filter { $0.flavor == flavor }.flatMap(sampleGradient)
  }

  /// Bridge default (`SpaceThemeInfo.bridgeDefault` in CoreBridge, not visible to this target), the empty-theme
  /// fallback `ThemeBackgroundView` draws as white, the sample Spaces of `StubSidebar.sample()` and both stops of
  /// every first-run theme family (`SpaceThemeCatalog.families`).
  @MainActor
  static func shippedThemes() -> [SpaceThemeInfo] {
    let bridgeDefault = SpaceThemeInfo(baseColors: [.p3(hex: 0xF2F0EE, alpha: 1), .p3(hex: 0xE4E1DD, alpha: 1)],
                                       isDark: false)
    let emptyFallback = SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    let sample = StubSidebar.sample()
    let sampleThemes = sample.spaceOrder.compactMap { sample.space($0)?.theme }
    let families = SpaceThemeCatalog.families.flatMap { [$0.light, $0.dark] }
    return [bridgeDefault, emptyFallback] + sampleThemes + families
  }

  static func sampleGradient(_ theme: SpaceThemeInfo) -> [RGBA] {
    let stops = theme.baseColors.map(toP3)
    var samples = stops.count > 1 ? zip(stops, stops.dropFirst()).flatMap { a, b in
      (0...samplesPerSegment).map { ThemeGradient.mix(a, b, Double($0) / Double(samplesPerSegment)) }
    } : stops
    if !theme.overlayColors.isEmpty, samples.count > 1 {
      let overlay = theme.overlayColors.map(toP3)
      samples = samples.enumerated().map { index, base in
        over(ThemeGradient.sample(overlay, at: Double(index) / Double(samples.count - 1)), base)
      }
    }
    let factor = theme.meanTextureFactor
    guard factor < 1 else { return samples }
    return samples + samples.map {
      RGBA(red: $0.red * factor, green: $0.green * factor, blue: $0.blue * factor, alpha: $0.alpha, space: $0.space)
    }
  }

  /// Lowest contrast of `foreground` over every theme surface of `flavor`, with each of `layers` (or none, when
  /// `layers` contains `nil`) drawn in between.
  @MainActor
  static func worstCase(_ foreground: RGBA, flavor: ThemeFlavor, layers: [Layer?]) -> Double {
    var worst = Double.infinity
    for theme in themeSurfaces(flavor) {
      for layer in layers {
        let surface = layer.map { over($0, theme) } ?? theme
        worst = min(worst, ratio(over(foreground, surface), surface))
      }
    }
    return worst
  }

  /// Lowest contrast of `foreground` drawn on a translucent `tile` fill that itself sits on each of `layers` (or
  /// on the bare theme, for `nil`) over every theme surface of `flavor`: theme, then row fill, then tile, then ink.
  @MainActor
  static func worstCase(_ foreground: RGBA, onTile tile: Layer, flavor: ThemeFlavor, layers: [Layer?]) -> Double {
    var worst = Double.infinity
    for theme in themeSurfaces(flavor) {
      for layer in layers {
        let surface = over(tile, layer.map { over($0, theme) } ?? theme)
        worst = min(worst, ratio(over(foreground, surface), surface))
      }
    }
    return worst
  }

  /// Contrast of `foreground` over a fixed opaque surface (the toolbar strip).
  static func ratio(_ foreground: RGBA, onOpaque surface: RGBA) -> Double {
    let base = toP3(surface)
    return ratio(over(foreground, base), base)
  }

  static func ratio(_ a: RGBA, _ b: RGBA) -> Double { Contrast.ratio(toSRGB(a), toSRGB(b)) }

  /// Source-over of `top` on an opaque `bottom`, in P3 encoded components. The result is opaque P3.
  static func over(_ top: RGBA, _ bottom: RGBA) -> RGBA {
    let t = toP3(top), b = toP3(bottom), a = t.alpha
    return RGBA(red: t.red * a + b.red * (1 - a), green: t.green * a + b.green * (1 - a),
                blue: t.blue * a + b.blue * (1 - a), alpha: 1, space: .displayP3)
  }

  // MARK: Color space conversion (linear-light matrices, D65)

  static func toP3(_ c: RGBA) -> RGBA {
    guard c.space == .sRGB else { return c }
    return convert(c, to: .displayP3, matrix: [[0.8224621, 0.1775380, 0.0000000],
                                               [0.0331941, 0.9668058, 0.0000000],
                                               [0.0170827, 0.0723974, 0.9105199]])
  }

  static func toSRGB(_ c: RGBA) -> RGBA {
    guard c.space == .displayP3 else { return c }
    return convert(c, to: .sRGB, matrix: [[1.2249401, -0.2249404, 0.0000000],
                                          [-0.0420569, 1.0420571, 0.0000000],
                                          [-0.0196376, -0.0786361, 1.0982735]])
  }

  private static func convert(_ c: RGBA, to space: RGBA.Space, matrix m: [[Double]]) -> RGBA {
    let l = [decode(c.red), decode(c.green), decode(c.blue)]
    let out = m.map { row in encode(row[0] * l[0] + row[1] * l[1] + row[2] * l[2]) }
    return RGBA(red: out[0], green: out[1], blue: out[2], alpha: c.alpha, space: space)
  }

  /// sRGB transfer curve (shared by Display P3), odd-extended so out-of-gamut values round-trip.
  private static func decode(_ v: Double) -> Double {
    let x = abs(v)
    let y = x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    return v < 0 ? -y : y
  }

  private static func encode(_ v: Double) -> Double {
    let x = abs(v)
    let y = x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    return v < 0 ? -y : y
  }
}

// MARK: - Use sites

/// Where each token is drawn. Kept next to the assertions so a new call site shows up as a missing case here.
enum ShellTokenSites {
  /// `secondaryText` is text: the Space title (`SpacePageView`, on the theme), the sidebar URL bar label
  /// (`URLBarView` `.host`, on `sidebarItemBackground`, `sidebarItemHovered` while hovered), and the Toolbar buttons
  /// and plain URL text (`ContentToolbarView`, `URLBarView` `.full` without a pill, on the opaque `toolbarSurface`).
  static func secondaryTextLayers(_ flavor: ThemeFlavor) -> [ShellContrastProbe.Layer?] {
    [nil, ShellTokens.sidebarItemBackground.resolve(flavor), ShellTokens.sidebarItemHovered.resolve(flavor)]
  }

  /// `primaryText` is text: row titles and row symbols (`SidebarTabCellView`, on whichever fill the row has, or
  /// none) and the active page dot (`SidebarContainerView`, on the theme).
  static func primaryTextLayers(_ flavor: ThemeFlavor) -> [ShellContrastProbe.Layer?] {
    let rowFills = [ShellTokens.tabCurrent, ShellTokens.tabContentVisible, ShellTokens.sidebarItemHovered,
                    ShellTokens.tabPrevious, ShellTokens.tabPreviousHovered, ShellTokens.tabPressed]
    return [nil] + rowFills.map { $0.resolve(flavor) }
  }

  /// The letter tile of a row or favorite without a favicon (`SidebarGlyphs.letter`): a rounded fill with the first
  /// letter drawn on it. Rows put it on every row fill `primaryText` sits on; favorite tiles also on their idle
  /// `sidebarItemBackground` (`FavoriteTileView`).
  static func letterTileLayers(_ flavor: ThemeFlavor) -> [ShellContrastProbe.Layer?] {
    primaryTextLayers(flavor) + [ShellTokens.sidebarItemBackground.resolve(flavor)]
  }

  /// `sidebarForeground` is icon-only: idle page dots and bottom-bar symbols (`SidebarContainerView`, on the
  /// theme) and the hover close X (`SidebarTabCellView`, on whichever row fill the hovered row has).
  static func sidebarForegroundLayers(_ flavor: ThemeFlavor) -> [ShellContrastProbe.Layer?] {
    let rowFills = [ShellTokens.sidebarItemHovered, ShellTokens.tabCurrent, ShellTokens.tabContentVisible,
                    ShellTokens.tabPrevious, ShellTokens.tabPreviousHovered, ShellTokens.tabPressed]
    return [nil] + rowFills.map { $0.resolve(flavor) }
  }
}

// MARK: - Tests

@MainActor
struct ShellTokensContrastTests {
  nonisolated private static let flavors: [ThemeFlavor] = [.light, .dark]

  // MARK: Probe

  @Test func probeAgreesWithContrastOnOpaqueSRGB() {
    #expect(abs(ShellContrastProbe.ratio(.black(1), .white(1)) - 21) < 1e-9)
    #expect(abs(ShellContrastProbe.ratio(.black(0.5), onOpaque: .white(1))
                - Contrast.ratio(RGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), .white(1))) < 1e-4)
  }

  @Test func probeConvertsP3WhiteAndBlackUnchanged() {
    for v in [0.0, 1.0] {
      let c = ShellContrastProbe.toSRGB(RGBA(red: v, green: v, blue: v, alpha: 1, space: .displayP3))
      #expect(abs(c.red - v) < 1e-5 && abs(c.green - v) < 1e-5 && abs(c.blue - v) < 1e-5)
    }
  }

  @Test func probeReadsP3ThroughP3Luminance() {
    // P3 #F29BBB (the sample Personal Space's end stop): Y = 0.4694 with the P3 matrix; read as sRGB it would be
    // 0.4369.
    let pink = ShellContrastProbe.toSRGB(.p3(hex: 0xF29BBB, alpha: 1))
    #expect(abs(Contrast.relativeLuminance(pink) - 0.4694) < 1e-3)
  }

  /// `Contrast` linearizes negative components wrongly (a P3 color far outside sRGB); above 1 is fine (the pink end
  /// stop reaches 1.003 red), so the measured surfaces must convert without negative components.
  @Test(arguments: flavors)
  func everyFlavorHasShippedSurfacesWithoutNegativeSRGB(flavor: ThemeFlavor) {
    let surfaces = ShellContrastProbe.themeSurfaces(flavor).map(ShellContrastProbe.toSRGB)
    #expect(!surfaces.isEmpty)
    for c in surfaces {
      #expect([c.red, c.green, c.blue].allSatisfy { $0 >= -1e-6 }, "\(c)")
    }
  }

  // MARK: Text, WCAG 2.x AA 4.5:1

  @Test(arguments: flavors)
  func primaryTextReadsOnEveryShippedSurface(flavor: ThemeFlavor) {
    let text = ShellTokens.primaryText.resolve(flavor)
    let worst = ShellContrastProbe.worstCase(text, flavor: flavor, layers: ShellTokenSites.primaryTextLayers(flavor))
    #expect(worst >= Contrast.minimumText, "primaryText \(flavor): \(worst)")
  }

  /// The tile letter is text (a site's initial stands in for its favicon), so it gets the text level, measured on
  /// the tile fill over every row fill and theme surface.
  @Test(arguments: flavors)
  func letterTileReadsOnEveryShippedSurface(flavor: ThemeFlavor) {
    let worst = ShellContrastProbe.worstCase(SidebarGlyphs.letterInk.resolve(flavor),
                                             onTile: SidebarGlyphs.letterFill.resolve(flavor), flavor: flavor,
                                             layers: ShellTokenSites.letterTileLayers(flavor))
    #expect(worst >= Contrast.minimumText, "letter tile \(flavor): \(worst)")
  }

  @Test(arguments: flavors)
  func secondaryTextReadsOnEveryShippedSurface(flavor: ThemeFlavor) {
    let text = ShellTokens.secondaryText.resolve(flavor)
    let onTheme = ShellContrastProbe.worstCase(text, flavor: flavor,
                                               layers: ShellTokenSites.secondaryTextLayers(flavor))
    let onToolbar = ShellContrastProbe.ratio(text, onOpaque: ShellTokens.toolbarSurface.resolve(flavor))
    #expect(onTheme >= Contrast.minimumText, "secondaryText \(flavor) over theme: \(onTheme)")
    #expect(onToolbar >= Contrast.minimumText, "secondaryText \(flavor) over toolbar: \(onToolbar)")
  }

  /// The Space theme creator's popover (#410): porcelain in light, #262927 in dark, with the Space name in
  /// `primaryText`, the section labels in `secondaryText`, and the colour-count button's `sidebarItemHovered` fill.
  @Test(arguments: flavors)
  func themePopoverTextReadsOnItsSurface(flavor: ThemeFlavor) {
    let surface = ShellTokens.themePopoverSurface.resolve(flavor)
    #expect(surface.alpha == 1)
    let primary = ShellContrastProbe.ratio(ShellTokens.primaryText.resolve(flavor), onOpaque: surface)
    let secondary = ShellContrastProbe.ratio(ShellTokens.secondaryText.resolve(flavor), onOpaque: surface)
    let onButton = ShellContrastProbe.ratio(ShellTokens.secondaryText.resolve(flavor),
                                            onOpaque: ShellContrastProbe.over(ShellTokens.sidebarItemHovered
                                              .resolve(flavor), surface))
    #expect(primary >= Contrast.minimumText, "primaryText \(flavor) on the theme popover: \(primary)")
    #expect(secondary >= Contrast.minimumText, "secondaryText \(flavor) on the theme popover: \(secondary)")
    #expect(onButton >= Contrast.minimumText, "secondaryText \(flavor) on the colour-count button: \(onButton)")
  }

  @Test func themePopoverSurfaceIsTheDesignedPair() {
    #expect(ShellTokens.themePopoverSurface.light == .srgb(hex: 0xFAF9F5))
    #expect(ShellTokens.themePopoverSurface.dark == .srgb(hex: 0x262927))
  }

  /// Why `toolbarSurface` is not Arc's measured strip (#186): Arc 1.168 draws the Toolbar on the card's own surface,
  /// sRGB #878787 in the dark theme measured, where `secondaryText` would fall below 4.5:1. If this ever passes, the
  /// measured surface can be reconsidered.
  @Test func arcsMeasuredToolbarSurfaceWouldFailSecondaryText() {
    let arcStrip = RGBA.srgb(hex: 0x878787)
    let ratio = ShellContrastProbe.ratio(ShellTokens.secondaryText.dark, onOpaque: arcStrip)
    #expect(ratio < Contrast.minimumText, "secondaryText dark over Arc's strip: \(ratio)")
  }

  // MARK: Icons, WCAG 2.x non-text 3:1

  @Test(arguments: flavors)
  func sidebarForegroundIconsStandOutOnEveryShippedSurface(flavor: ThemeFlavor) {
    let icon = ShellTokens.sidebarForeground.resolve(flavor)
    let worst = ShellContrastProbe.worstCase(icon, flavor: flavor,
                                             layers: ShellTokenSites.sidebarForegroundLayers(flavor))
    #expect(worst >= Contrast.minimumNonText, "sidebarForeground \(flavor): \(worst)")
  }

  // MARK: Hierarchy (Arc: primary > secondary > sidebar foreground)

  @Test(arguments: flavors)
  func textLevelsKeepTheirOrder(flavor: ThemeFlavor) {
    func bare(_ token: TokenPair) -> Double {
      ShellContrastProbe.worstCase(token.resolve(flavor), flavor: flavor, layers: [nil])
    }
    let primary = bare(ShellTokens.primaryText)
    let secondary = bare(ShellTokens.secondaryText)
    let foreground = bare(ShellTokens.sidebarForeground)
    #expect(primary > secondary, "\(flavor): primary \(primary), secondary \(secondary)")
    #expect(secondary > foreground, "\(flavor): secondary \(secondary), sidebarForeground \(foreground)")
  }

  // MARK: Command bar (#371, design/command-bar/README.md, Accessibility)

  /// The fills a command bar text sits on, over the opaque surface: bare, the selected row, a key cap, the pill well.
  private static func commandBarFills(_ flavor: ThemeFlavor) -> [RGBA] {
    let surface = ShellTokens.commandBarSurfaceOpaque.resolve(flavor)
    let layers = [ShellTokens.commandBarSelectedRow, ShellTokens.commandBarKeyCap, ShellTokens.commandBarPillWell]
    return [surface] + layers.map { ShellContrastProbe.over($0.resolve(flavor), surface) }
  }

  @Test(arguments: flavors)
  func commandBarTextReadsOnTheOpaqueSurfaceAndItsFills(flavor: ThemeFlavor) {
    for fill in Self.commandBarFills(flavor) {
      for (name, token) in [("text", ShellTokens.commandBarText), ("secondary", ShellTokens.commandBarSecondaryText),
                            ("tertiary", ShellTokens.commandBarTertiaryText)] {
        let ratio = ShellContrastProbe.ratio(token.resolve(flavor), onOpaque: fill)
        #expect(ratio >= Contrast.minimumText, "commandBar \(name) \(flavor): \(ratio)")
      }
    }
  }

  @Test(arguments: flavors)
  func theSelectedPillReadsInTheCapsule(flavor: ThemeFlavor) {
    let surface = ShellTokens.commandBarSurfaceOpaque.resolve(flavor)
    let well = ShellContrastProbe.over(ShellTokens.commandBarPillWell.resolve(flavor), surface)
    let on = ShellContrastProbe.over(ShellTokens.commandBarPillOn.resolve(flavor), well)
    let text = ShellContrastProbe.ratio(ShellTokens.commandBarPillOnText.resolve(flavor), onOpaque: on)
    #expect(text >= Contrast.minimumText, "selected pill text \(flavor): \(text)")
    let count = ShellContrastProbe.over(CommandBarFilterPills.selectedCountColor(flavor), on)
    #expect(ShellContrastProbe.ratio(count, on) >= Contrast.minimumText, "selected pill count \(flavor)")
  }

  /// Text on a mustard fill is graphite (the brand pair), above 7:1.
  @Test func graphiteOnMustardIsAbove7() {
    let ratio = ShellContrastProbe.ratio(BrandTokens.onAccent.dark, onOpaque: ShellTokens.commandBarTick.dark)
    #expect(ratio >= 7, "graphite on mustard: \(ratio)")
  }

  /// Mustard is a fill only: no command bar text token is the accent.
  @Test func mustardIsOnlyAFillInTheCommandBar() {
    #expect(ShellTokens.commandBarTick == BrandTokens.accent)
    let text = [ShellTokens.commandBarText, ShellTokens.commandBarSecondaryText, ShellTokens.commandBarTertiaryText,
                ShellTokens.commandBarPillOnText]
    for token in text {
      #expect(token.light != BrandTokens.Palette.mustard && token.dark != BrandTokens.Palette.mustard)
    }
  }

  @Test func theTextLevelsKeepTheirOrderOnTheSurface() {
    for flavor in Self.flavors {
      let surface = ShellTokens.commandBarSurfaceOpaque.resolve(flavor)
      func ratio(_ token: TokenPair) -> Double { ShellContrastProbe.ratio(token.resolve(flavor), onOpaque: surface) }
      #expect(ratio(ShellTokens.commandBarText) > ratio(ShellTokens.commandBarSecondaryText))
      #expect(ratio(ShellTokens.commandBarSecondaryText) > ratio(ShellTokens.commandBarTertiaryText))
    }
  }

  @Test func theScrimIsLighterInLight() {
    #expect(ShellTokens.commandBarScrim.dark.alpha == 0.28)
    #expect(ShellTokens.commandBarScrim.light.alpha < ShellTokens.commandBarScrim.dark.alpha)
  }
}
