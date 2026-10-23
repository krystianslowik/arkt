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
/// - Gradients are sampled between every pair of stops, because the luminance of a component-wise blend can dip
///   below both ends.
/// - The grain layer (soft light, at most `ShellTokens.themeTextureMaxOpacity`) is mean-preserving and ignored.
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
  /// fallback `ThemeBackgroundView` draws as white, and the sample Spaces of `StubSidebar.sample()`.
  @MainActor
  static func shippedThemes() -> [SpaceThemeInfo] {
    let bridgeDefault = SpaceThemeInfo(baseColors: [.p3(hex: 0xF2F0EE, alpha: 1), .p3(hex: 0xE4E1DD, alpha: 1)],
                                       isDark: false)
    let emptyFallback = SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    let sample = StubSidebar.sample()
    let sampleThemes = sample.spaceOrder.compactMap { sample.space($0)?.theme }
    return [bridgeDefault, emptyFallback] + sampleThemes
  }

  static func sampleGradient(_ theme: SpaceThemeInfo) -> [RGBA] {
    let stops = theme.baseColors.map(toP3)
    guard stops.count > 1 else { return stops }
    return zip(stops, stops.dropFirst()).flatMap { a, b in
      (0...samplesPerSegment).map { RGBA.mix(a, b, Double($0) / Double(samplesPerSegment)) }
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
  /// `secondaryText` is text: the Space title (`SpacePageView`, on the theme), the URL bar label (`URLBarView`, on
  /// `sidebarItemBackground`, `sidebarItemHovered` while hovered), and the toolbar buttons (`ContentToolbarView`,
  /// on the opaque `toolbarSurface`).
  static func secondaryTextLayers(_ flavor: ThemeFlavor) -> [ShellContrastProbe.Layer?] {
    [nil, ShellTokens.sidebarItemBackground.resolve(flavor), ShellTokens.sidebarItemHovered.resolve(flavor)]
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
  func secondaryTextReadsOnEveryShippedSurface(flavor: ThemeFlavor) {
    let text = ShellTokens.secondaryText.resolve(flavor)
    let onTheme = ShellContrastProbe.worstCase(text, flavor: flavor,
                                               layers: ShellTokenSites.secondaryTextLayers(flavor))
    let onToolbar = ShellContrastProbe.ratio(text, onOpaque: ShellTokens.toolbarSurface.resolve(flavor))
    #expect(onTheme >= Contrast.minimumText, "secondaryText \(flavor) over theme: \(onTheme)")
    #expect(onToolbar >= Contrast.minimumText, "secondaryText \(flavor) over toolbar: \(onToolbar)")
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
}
