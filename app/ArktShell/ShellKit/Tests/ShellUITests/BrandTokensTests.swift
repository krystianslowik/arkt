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
