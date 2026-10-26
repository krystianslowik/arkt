import Testing
@testable import ShellUI

/// The Settings window's colors (docs/design/settings.md, section 4) over its `surfaceBrand` surface: the new tokens
/// are the design's values, destructive text reaches 4.5:1 wherever it is drawn, and the graphite switch reads 3:1
/// against the group it sits in.
@MainActor
struct SettingsTokensContrastTests {
  nonisolated static let flavors: [ThemeFlavor] = [.light, .dark]

  private static func surface(_ flavor: ThemeFlavor) -> RGBA { BrandTokens.surfaceBrand.resolve(flavor) }

  /// The recessed group field over the surface, opaque.
  private static func group(_ flavor: ThemeFlavor) -> RGBA {
    ShellContrastProbe.over(SettingsTokens.groupField.resolve(flavor), surface(flavor))
  }

  /// Contrast of a possibly translucent `text` over an opaque `fill`.
  private static func ratio(_ text: RGBA, on fill: RGBA) -> Double {
    ShellContrastProbe.ratio(ShellContrastProbe.over(text, fill), ShellContrastProbe.toP3(fill))
  }

  @Test func theNewTokensAreTheDesigns() {
    #expect(SettingsTokens.groupField == ArchiveTokens.listField)
    #expect(SettingsTokens.switchOn == TokenPair(light: .srgb(hex: 0x202321), dark: .srgb(hex: 0xF4F3EF)))
    #expect(SettingsTokens.switchKnobOn == TokenPair(light: .white(1), dark: .srgb(hex: 0x202321)))
    #expect(SettingsTokens.separatorIncreasedContrast == TokenPair(light: .black(0.20), dark: .white(0.20)))
    #expect(SettingsTokens.toolbarMaterial.light == BrandTokens.Palette.porcelain.atAlpha(0.82))
    #expect(SettingsTokens.toolbarMaterial.dark == BrandTokens.Palette.graphite.atAlpha(0.80))
    #expect(AlertTokens.destructiveText == TokenPair(light: .srgb(hex: 0xB3261E), dark: .srgb(hex: 0xFFAAA2)))
    #expect(ArchiveTokens.destructiveText == AlertTokens.destructiveText, "one destructive red")
    #expect(SettingsTokens.disabledControlAlpha == 0.42)
  }

  /// The doc's table: 6.20 and 8.71 on the surface.
  @Test func destructiveTextOnTheSurface() {
    #expect(Contrast.ratio(AlertTokens.destructiveText.light, Self.surface(.light)) >= 6.19)
    #expect(Contrast.ratio(AlertTokens.destructiveText.dark, Self.surface(.dark)) >= 8.70)
  }

  /// Destructive links and destructive button titles: bare on the surface and over the group field, on the neutral
  /// pill fill idle (`sidebarItemHovered`) and hovered (`sidebarItemBackground`), and on a hovered row; each at least
  /// 4.5:1. The pressed fill is never used behind destructive text.
  @Test(arguments: flavors)
  func destructiveTextReadsEverywhereItIsDrawn(flavor: ThemeFlavor) {
    let text = AlertTokens.destructiveText.resolve(flavor)
    let bases = [Self.surface(flavor), Self.group(flavor)]
    let fills: [RGBA?] = [nil, ShellTokens.sidebarItemHovered.resolve(flavor),
                          ShellTokens.sidebarItemBackground.resolve(flavor)]
    var lowest = Double.infinity
    for base in bases {
      for fill in fills {
        let backdrop = fill.map { ShellContrastProbe.over($0, base) } ?? ShellContrastProbe.toP3(base)
        lowest = min(lowest, Self.ratio(text, on: backdrop))
      }
    }
    #expect(lowest >= 4.5, "\(flavor) lowest \(lowest):1")
  }

  @Test(arguments: flavors)
  func captionsAndLabelsReadOnTheGroupField(flavor: ThemeFlavor) {
    let group = Self.group(flavor)
    let hovered = ShellContrastProbe.over(ShellTokens.sidebarItemBackground.resolve(flavor), group)
    for backdrop in [group, hovered] {
      for text in [ShellTokens.primaryText, ShellTokens.secondaryText] {
        let value = Self.ratio(text.resolve(flavor), on: backdrop)
        #expect(value >= 4.5, "\(flavor) \(value):1")
      }
    }
  }

  /// Non-text: the switch's on fill against the group field (3:1 needed), and its knob against the on fill.
  @Test(arguments: flavors)
  func theSwitchReadsAgainstItsGroup(flavor: ThemeFlavor) {
    let on = SettingsTokens.switchOn.resolve(flavor)
    #expect(Self.ratio(on, on: Self.group(flavor)) >= Contrast.minimumNonText)
    #expect(Contrast.ratio(SettingsTokens.switchKnobOn.resolve(flavor), on) >= Contrast.minimumNonText)
  }

  /// The one primary pill: graphite on mustard.
  @Test func primaryPillText() {
    #expect(Contrast.ratio(BrandTokens.onAccent.light, BrandTokens.accent.light) >= 4.5)
  }
}
