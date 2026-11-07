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

  // MARK: #687: the theme creator, Peek, Little Arkt, find bar, Library and import

  /// Theme creator: the ring sits on the popover surface, and over the slider's track where it crosses it.
  @Test(arguments: flavors)
  func focusRingStandsOutOnTheThemeCreator(flavor: ThemeFlavor) {
    let surface = ShellTokens.themePopoverSurface.resolve(flavor)
    let track = ShellContrastProbe.over(ShellTokens.sidebarItemHovered.resolve(flavor), surface)
    for (name, base) in [("surface", surface), ("track", track)] {
      let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: base)
      #expect(ratio >= Contrast.minimumNonText, "focusRing on the theme creator \(name) \(flavor): \(ratio)")
    }
  }

  /// The selected texture swatch's ring (`primaryText`, in place of the system accent) on the popover surface.
  @Test(arguments: flavors)
  func theSelectedSwatchRingStandsOutOnThePopover(flavor: ThemeFlavor) {
    let ratio = ShellContrastProbe.ratio(ShellTokens.primaryText.resolve(flavor),
                                         onOpaque: ShellTokens.themePopoverSurface.resolve(flavor))
    #expect(ratio >= Contrast.minimumNonText, "selected swatch \(flavor): \(ratio)")
  }

  /// A colour dot sits on the user's colours; its ring hugs the dot's white edge, so it is graphite in both
  /// appearances and measured against that edge.
  @Test func theColourDotRingStandsOutOnItsWhiteEdge() {
    let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(.light), onOpaque: .white(1))
    #expect(ratio >= Contrast.minimumNonText, "dot ring on white: \(ratio)")
  }

  /// Peek: the ring sits beside the card, over the scrim on the page (white in light, the dark page fill in dark),
  /// and over a plain page.
  @Test(arguments: flavors)
  func focusRingStandsOutBesideThePeek(flavor: ThemeFlavor) {
    let page = flavor == .light ? RGBA.white(1) : RGBA.srgb(hex: 0x1C1C20)
    let scrimmed = ShellContrastProbe.over(ShellTokens.peekScrim.resolve(flavor), page)
    for (name, base) in [("scrim", scrimmed), ("page", page)] {
      let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: base)
      #expect(ratio >= Contrast.minimumNonText, "focusRing beside the Peek, \(name) \(flavor): \(ratio)")
    }
  }

  /// Little Arkt: Copy Link's ring on the bar (`surfaceBrand`); a segment's ring inside the mustard split in the
  /// graphite tone (`onAccent`) over every accent state, and in the window's tone over the quiet split.
  @Test(arguments: flavors)
  func focusRingStandsOutOnTheLittleArktBar(flavor: ThemeFlavor) {
    let bar = BrandTokens.surfaceBrand.resolve(flavor)
    let barRatio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: bar)
    #expect(barRatio >= Contrast.minimumNonText, "Copy Link \(flavor): \(barRatio)")
    for fill in [BrandTokens.accent, BrandTokens.accentHighlight, BrandTokens.accentPressed] {
      let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(.light), onOpaque: fill.resolve(flavor))
      #expect(ratio >= Contrast.minimumNonText, "segment on mustard \(flavor): \(ratio)")
    }
    let quiet = ShellContrastProbe.over(ShellTokens.sidebarItemBackground.resolve(flavor), bar)
    let quietRatio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: quiet)
    #expect(quietRatio >= Contrast.minimumNonText, "quiet segment \(flavor): \(quietRatio)")
  }

  /// The find bar's pill, the Library window (rail, rows and their hover fill) and the import sheet's list field and
  /// Hero entry all sit on `surfaceBrand`.
  @Test(arguments: flavors)
  func focusRingStandsOutOnTheFindBarLibraryAndImport(flavor: ThemeFlavor) {
    let brand = BrandTokens.surfaceBrand.resolve(flavor)
    let surfaces: [(String, RGBA)] = [
      ("find bar", brand), ("library", AlertTokens.dialogSurface.resolve(flavor)),
      ("download row", ShellContrastProbe.over(DownloadsTokens.rowFill.resolve(flavor), brand)),
      ("current rail item", ShellContrastProbe.over(ShellTokens.tabCurrent.resolve(flavor), brand)),
      ("import list", ShellContrastProbe.over(ArchiveTokens.listField.resolve(flavor), brand)),
    ]
    for (name, base) in surfaces {
      let ratio = ShellContrastProbe.ratio(ShellTokens.focusRing.resolve(flavor), onOpaque: base)
      #expect(ratio >= Contrast.minimumNonText, "focusRing on the \(name) \(flavor): \(ratio)")
    }
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
