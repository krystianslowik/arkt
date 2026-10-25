import Foundation
import Testing
@testable import ShellUI

struct ContrastTests {
  @Test func relativeLuminanceOfBlackAndWhite() {
    #expect(Contrast.relativeLuminance(.black(1)) == 0)
    #expect(abs(Contrast.relativeLuminance(.white(1)) - 1) < 1e-9)
  }

  @Test func blackOnWhiteIsTwentyOneToOne() {
    #expect(abs(Contrast.ratio(.black(1), .white(1)) - 21) < 1e-9)
  }

  @Test func ratioIsSymmetricAndOneForEqualColors() {
    let a = RGBA.srgb(hex: 0x8A5A0E), b = RGBA.srgb(hex: 0xFAF9F5)
    #expect(Contrast.ratio(a, b) == Contrast.ratio(b, a))
    #expect(Contrast.ratio(a, a) == 1)
  }

  @Test func knownMidGrayPair() {
    // #777777 on white is the textbook near-miss for AA body text: 4.48:1.
    let ratio = Contrast.ratio(.srgb(hex: 0x777777), .white(1))
    #expect(abs(ratio - 4.48) < 0.01)
  }
}

struct RGBAHexTests {
  @Test func parsesHashedSixDigitHex() {
    #expect(RGBA.srgb(hexString: "#E9B520") == .srgb(hex: 0xE9B520))
    #expect(RGBA.srgb(hexString: "#e9b520") == .srgb(hex: 0xE9B520))
  }

  @Test func rejectsOtherForms() {
    for bad in ["E9B520", "#E9B52", "#E9B5200", "#+9B520", "#GGGGGG", ""] {
      #expect(RGBA.srgb(hexString: bad) == nil, "\(bad)")
    }
  }
}

struct BrandTokensTests {
  private static let flavors: [ThemeFlavor] = [.light, .dark]

  // MARK: - Text pairs: WCAG 2.x AA, 4.5:1

  @Test(arguments: flavors)
  func onAccentReadsOnEveryAccentFill(flavor: ThemeFlavor) {
    let text = BrandTokens.onAccent.resolve(flavor)
    for fill in [BrandTokens.accent, BrandTokens.accentHighlight, BrandTokens.accentPressed] {
      #expect(Contrast.ratio(text, fill.resolve(flavor)) >= Contrast.minimumText)
    }
  }

  @Test(arguments: flavors)
  func accentTextReadsOnBrandSurface(flavor: ThemeFlavor) {
    let ratio = Contrast.ratio(BrandTokens.accentText.resolve(flavor), BrandTokens.surfaceBrand.resolve(flavor))
    #expect(ratio >= Contrast.minimumText)
  }

  // MARK: - First-run text tokens (onboarding spec, section 5)

  @Test(arguments: flavors)
  func brandTextReadsOnBrandSurface(flavor: ThemeFlavor) {
    let surface = BrandTokens.surfaceBrand.resolve(flavor)
    for token in [BrandTokens.brandTextPrimary, BrandTokens.brandTextSecondary, BrandTokens.brandTextSecondaryContrast] {
      #expect(Contrast.ratio(token.resolve(flavor), surface) >= Contrast.minimumText)
    }
  }

  /// The spec's table: primary 15.06:1, secondary 5.62 / 8.06. The spec lists 10.1 / 12.9 for the contrast variant;
  /// its hex values measure 9.99 / 12.58, still above AAA (7:1).
  @Test func brandTextRatiosMatchTheSpec() {
    func ratio(_ token: TokenPair, _ flavor: ThemeFlavor) -> Double {
      Contrast.ratio(token.resolve(flavor), BrandTokens.surfaceBrand.resolve(flavor))
    }
    #expect(abs(ratio(BrandTokens.brandTextPrimary, .light) - 15.06) < 0.05)
    #expect(abs(ratio(BrandTokens.brandTextPrimary, .dark) - 15.06) < 0.05)
    #expect(abs(ratio(BrandTokens.brandTextSecondary, .light) - 5.62) < 0.05)
    #expect(abs(ratio(BrandTokens.brandTextSecondary, .dark) - 8.06) < 0.05)
    #expect(abs(ratio(BrandTokens.brandTextSecondaryContrast, .light) - 9.99) < 0.05)
    #expect(abs(ratio(BrandTokens.brandTextSecondaryContrast, .dark) - 12.58) < 0.05)
  }

  /// Increase Contrast must raise every secondary level, never lower it.
  @Test(arguments: flavors)
  func contrastVariantsAreStronger(flavor: ThemeFlavor) {
    let surface = BrandTokens.surfaceBrand.resolve(flavor)
    #expect(Contrast.ratio(BrandTokens.brandTextSecondaryContrast.resolve(flavor), surface)
            > Contrast.ratio(BrandTokens.brandTextSecondary.resolve(flavor), surface))
    #expect(BrandTokens.brandHairlineContrast.resolve(flavor).alpha > BrandTokens.brandHairline.resolve(flavor).alpha)
  }

  /// `brandHairlineContrast` is the Increase Contrast edge of the glass button and the option pill: 3:1 against the
  /// surface it is drawn on, after compositing.
  @Test(arguments: flavors)
  func contrastHairlineStandsOutFromBrandSurface(flavor: ThemeFlavor) {
    let surface = BrandTokens.surfaceBrand.resolve(flavor)
    let edge = BrandTokens.composite(BrandTokens.brandHairlineContrast.resolve(flavor), over: surface)
    #expect(Contrast.ratio(edge, surface) >= Contrast.minimumNonText)
  }

  @Test func translucentBrandTokensUseThePalette() {
    let p = BrandTokens.Palette.self
    #expect(BrandTokens.brandTextPrimary == TokenPair(light: p.graphite, dark: p.porcelain))
    #expect(BrandTokens.brandTextSecondary == TokenPair(light: .srgb(hex: 0x62655F), dark: .srgb(hex: 0xB6BAB3)))
    #expect(BrandTokens.brandTextSecondaryContrast
            == TokenPair(light: .srgb(hex: 0x3D403B), dark: .srgb(hex: 0xE3E6DF)))
    #expect(BrandTokens.brandHairline == TokenPair(light: .srgb(hex: 0x202321, alpha: 0.12),
                                                   dark: .srgb(hex: 0xFAF9F5, alpha: 0.12)))
    #expect(BrandTokens.brandHairlineContrast == TokenPair(light: .srgb(hex: 0x202321, alpha: 0.50),
                                                           dark: .srgb(hex: 0xFAF9F5, alpha: 0.50)))
    #expect(BrandTokens.brandControlFill == TokenPair(light: .srgb(hex: 0x202321, alpha: 0.05),
                                                      dark: .srgb(hex: 0xFAF9F5, alpha: 0.06)))
    #expect(BrandTokens.brandControlFillPressed == TokenPair(light: .srgb(hex: 0x202321, alpha: 0.10),
                                                             dark: .srgb(hex: 0xFAF9F5, alpha: 0.12)))
  }

  @Test func compositeIsSourceOver() {
    let half = BrandTokens.composite(.srgb(hex: 0x000000, alpha: 0.5), over: .srgb(hex: 0xFFFFFF))
    #expect(abs(half.red - 0.5) < 1e-9 && half.alpha == 1)
  }

  // MARK: - UI component pairs: WCAG 2.x non-text contrast, 3:1

  @Test(arguments: flavors)
  func focusRingStandsOutFromBrandSurface(flavor: ThemeFlavor) {
    let ratio = Contrast.ratio(BrandTokens.focusRing.resolve(flavor), BrandTokens.surfaceBrand.resolve(flavor))
    #expect(ratio >= Contrast.minimumNonText)
  }

  @Test func focusRingOnLightSurfacesIsGraphiteNotMustard() {
    #expect(BrandTokens.focusRing.light == BrandTokens.Palette.graphite)
    #expect(BrandTokens.focusRing.light != BrandTokens.Palette.mustard)
  }

  // MARK: - Guards: these colors are not text on light surfaces

  @Test func mustardAsTextOnLightSurfaceFails() {
    let ratio = Contrast.ratio(BrandTokens.accent.light, BrandTokens.surfaceBrand.light)
    #expect(ratio < Contrast.minimumText)
    #expect(ratio < Contrast.minimumNonText)
  }

  @Test func foldShadowAsTextOnLightSurfaceFails() {
    let ratio = Contrast.ratio(BrandTokens.foldShadow.light, BrandTokens.surfaceBrand.light)
    #expect(ratio < Contrast.minimumText)
  }

  @Test func lightAccentTextIsNotTheAccentFill() {
    #expect(BrandTokens.accentText.light != BrandTokens.accent.light)
  }

  // MARK: - Values

  @Test func tokensUseThePalette() {
    let p = BrandTokens.Palette.self
    #expect(BrandTokens.accent == TokenPair(light: p.mustard, dark: p.mustard))
    #expect(BrandTokens.accentHighlight == TokenPair(light: p.mustardHighlight, dark: p.mustardHighlight))
    #expect(BrandTokens.accentPressed == TokenPair(light: p.mustardShade, dark: p.mustardShade))
    #expect(BrandTokens.onAccent == TokenPair(light: p.graphite, dark: p.graphite))
    #expect(BrandTokens.accentText == TokenPair(light: p.accentTextOnLight, dark: p.mustard))
    #expect(BrandTokens.foldShadow == TokenPair(light: p.foldShadow, dark: p.foldShadow))
    #expect(BrandTokens.surfaceBrand == TokenPair(light: p.porcelain, dark: p.graphite))
    #expect(p.accentTextOnLight == .srgb(hex: 0x8A5A0E))
  }

  /// The palette mirrors `design/brand/tokens/brand-tokens.json`; this keeps the two from drifting.
  @Test func paletteMatchesBrandTokensJSON() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // ShellUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // ShellKit
      .deletingLastPathComponent()  // ArktShell
      .deletingLastPathComponent()  // app
      .deletingLastPathComponent()
    let url = repoRoot.appendingPathComponent("design/brand/tokens/brand-tokens.json")
    let json = try JSONDecoder().decode(BrandTokensFile.self, from: Data(contentsOf: url))
    let p = BrandTokens.Palette.self
    let expected: [String: RGBA] = [
      "mustard": p.mustard, "mustardHighlight": p.mustardHighlight, "mustardShade": p.mustardShade,
      "foldShadow": p.foldShadow, "porcelain": p.porcelain, "graphite": p.graphite,
    ]
    #expect(Set(json.colors.keys) == Set(expected.keys))
    for (name, color) in expected {
      let hex = try #require(json.colors[name])
      #expect(RGBA.srgb(hexString: hex) == color, "\(name)")
    }
  }
}

private struct BrandTokensFile: Decodable {
  let colors: [String: String]
}
