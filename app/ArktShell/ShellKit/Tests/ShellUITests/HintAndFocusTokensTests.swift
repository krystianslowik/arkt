import Testing
@testable import ShellUI

/// The drag hint (#641) and the chrome focus ring (#642), design/drag-hint-focus-ring/README.md: both are the ink
/// tone, graphite where the text is dark and porcelain where it is light, at their own alpha.
@MainActor
struct HintAndFocusTokensTests {
  nonisolated private static let flavors: [ThemeFlavor] = [.light, .dark]

  private static func ink(_ alpha: Double) -> TokenPair {
    TokenPair(light: .srgb(hex: 0x202321, alpha: alpha), dark: .srgb(hex: 0xFAF9F5, alpha: alpha))
  }

  @Test func dragHintIsTheInkToneAtTwelveAndFortyFivePercent() {
    #expect(ShellTokens.dragHint == Self.ink(0.12))
    #expect(ShellTokens.dragHintEdge == Self.ink(0.45))
  }

  @Test func focusRingIsTheInkToneAtEightyFivePercent() {
    #expect(ShellTokens.focusRing == Self.ink(0.85))
    #expect(ShellTokens.focusRingWidth == 3)
  }

  /// One ring: on brand surfaces (Settings) `ShellTokens.focusRing` is `BrandTokens.focusRing` at 85 %.
  @Test(arguments: flavors)
  func focusRingIsTheBrandRingAtEightyFivePercent(flavor: ThemeFlavor) {
    var brand = BrandTokens.focusRing.resolve(flavor)
    brand.alpha = 0.85
    #expect(ShellTokens.focusRing.resolve(flavor) == brand)
  }

  @Test(arguments: flavors)
  func noFocusRingOrDragHintIsMustard(flavor: ThemeFlavor) {
    for token in [ShellTokens.focusRing, ShellTokens.dragHint, ShellTokens.dragHintEdge, BrandTokens.focusRing] {
      var color = token.resolve(flavor)
      color.alpha = 1
      #expect(color != BrandTokens.Palette.mustard)
    }
  }

  // MARK: WCAG 2.x non-text 3:1

  /// Sidebar rows and Favorite tiles: the ring is drawn over the row or tile fill, over every shipped Space theme.
  @Test(arguments: flavors)
  func focusRingStandsOutOnEveryShippedSpace(flavor: ThemeFlavor) {
    let ring = ShellTokens.focusRing.resolve(flavor)
    let layers = ShellTokenSites.sidebarForegroundLayers(flavor) + [ShellTokens.sidebarItemBackground.resolve(flavor)]
    let worst = ShellContrastProbe.worstCase(ring, flavor: flavor, layers: layers)
    #expect(worst >= Contrast.minimumNonText, "focusRing \(flavor): \(worst)")
  }

  /// Settings controls sit on `surfaceBrand`.
  @Test(arguments: flavors)
  func focusRingStandsOutOnBrandSurfaces(flavor: ThemeFlavor) {
    let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor),
                                         onOpaque: BrandTokens.surfaceBrand.resolve(flavor))
    #expect(ratio >= Contrast.minimumNonText, "focusRing on surfaceBrand \(flavor): \(ratio)")
  }
}
