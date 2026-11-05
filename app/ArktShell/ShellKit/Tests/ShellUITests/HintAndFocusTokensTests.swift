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

  /// The current Favorite tile: the ring is drawn inside the tile, over its `tabCurrent` fill, on every shipped Space.
  @Test(arguments: flavors)
  func focusRingStandsOutOnTheCurrentFavoriteTile(flavor: ThemeFlavor) {
    let worst = ShellContrastProbe.worstCase(ShellTokens.focusRing.resolve(flavor), flavor: flavor,
                                             layers: [ShellTokens.tabCurrent.resolve(flavor)])
    #expect(worst >= Contrast.minimumNonText, "focusRing on the current tile \(flavor): \(worst)")
  }

  /// Settings rows and their switches, pop-ups and add rows sit in a group's recessed field on `surfaceBrand`.
  @Test(arguments: flavors)
  func focusRingStandsOutOnASettingsGroup(flavor: ThemeFlavor) {
    let field = ShellContrastProbe.over(SettingsTokens.groupField.resolve(flavor),
                                        BrandTokens.surfaceBrand.resolve(flavor))
    let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: field)
    #expect(ratio >= Contrast.minimumNonText, "focusRing on the group field \(flavor): \(ratio)")
  }

  /// The pane items sit on the chrome's toolbar material while content is scrolled under it (measured over
  /// `surfaceBrand`; Reduce Transparency draws `surfaceBrand` itself, covered above).
  @Test(arguments: flavors)
  func focusRingStandsOutOnTheSettingsToolbarMaterial(flavor: ThemeFlavor) {
    let material = ShellContrastProbe.over(SettingsTokens.toolbarMaterial.resolve(flavor),
                                           BrandTokens.surfaceBrand.resolve(flavor))
    let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: material)
    #expect(ratio >= Contrast.minimumNonText, "focusRing on the toolbar material \(flavor): \(ratio)")
  }

  /// A toast's action pill: the ring sits outside the pill on the toast surface, tinted by each shipped Space.
  @Test func focusRingStandsOutOnEveryToastSurface() {
    for theme in ShellContrastProbe.shippedThemes() {
      for opaque in [false, true] {
        let surface = AlertTokens.toastSurface(theme: theme, opaque: opaque)
        let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(theme.flavor), onOpaque: surface)
        #expect(ratio >= Contrast.minimumNonText, "focusRing on a toast (\(theme.flavor), opaque \(opaque)): \(ratio)")
      }
    }
  }
}
