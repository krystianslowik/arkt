import Testing
@testable import ShellUI

/// The Archive window's colors (design/archive-search, sections 9 and 12) over its `surfaceBrand` surface: text
/// reaches WCAG AA 4.5:1 on the list field, on every Space-tinted chip and on the pills; mustard is only ever a fill.
@MainActor
struct ArchiveTokensContrastTests {
  nonisolated static let flavors: [ThemeFlavor] = [.light, .dark]

  private static func surface(_ flavor: ThemeFlavor) -> RGBA { BrandTokens.surfaceBrand.resolve(flavor) }

  /// Contrast of a possibly translucent `text` over an opaque `fill`.
  private static func ratio(_ text: RGBA, on fill: RGBA) -> Double {
    ShellContrastProbe.ratio(ShellContrastProbe.over(text, fill), ShellContrastProbe.toP3(fill))
  }

  @Test func theNewTokensAreTheDesigns() {
    #expect(ArchiveTokens.chipTintAlpha == 0.16)
    #expect(ArchiveTokens.matchHighlight.light.alpha == 0.35)
    #expect(ArchiveTokens.listField == TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.035), dark: .black(0.14)))
    #expect(ArchiveTokens.destructiveText == TokenPair(light: .srgb(hex: 0xB3261E), dark: .srgb(hex: 0xFFAAA2)))
  }

  @Test(arguments: flavors)
  func rowTextReadsOnTheListField(flavor: ThemeFlavor) {
    let field = ShellContrastProbe.over(ArchiveTokens.listField.resolve(flavor), Self.surface(flavor))
    for text in [ShellTokens.primaryText, ShellTokens.secondaryText] {
      let value = Self.ratio(text.resolve(flavor), on: field)
      #expect(value >= 4.5, "\(flavor) \(value):1")
    }
    let selected = ShellContrastProbe.over(ShellTokens.tabCurrent.resolve(flavor), field)
    #expect(Self.ratio(ShellTokens.primaryText.resolve(flavor), on: selected) >= 4.5)
  }

  /// A Space chip is the Space's color at 16 % over the surface; its name stays readable for every shipped theme's
  /// first stop (the color the chip uses).
  @Test(arguments: flavors)
  func chipTextReadsOnEverySpaceTint(flavor: ThemeFlavor) {
    for theme in ShellContrastProbe.shippedThemes() {
      guard let color = theme.baseColors.first else { continue }
      let chip = ArchiveTokens.chipFill(color, over: Self.surface(flavor))
      let value = Self.ratio(ShellTokens.primaryText.resolve(flavor), on: chip)
      #expect(value >= 4.5, "\(flavor) chip \(color) \(value):1")
    }
    let neutral = ShellContrastProbe.over(ShellTokens.sidebarItemHovered.resolve(flavor), Self.surface(flavor))
    #expect(Self.ratio(ShellTokens.primaryText.resolve(flavor), on: neutral) >= 4.5)
  }

  @Test(arguments: flavors)
  func destructiveTextReadsOnTheSurfaceAndTheNeutralPill(flavor: ThemeFlavor) {
    let text = ArchiveTokens.destructiveText.resolve(flavor)
    #expect(Self.ratio(text, on: Self.surface(flavor)) >= 4.5)
    let pill = ShellContrastProbe.over(ShellTokens.sidebarItemHovered.resolve(flavor), Self.surface(flavor))
    #expect(Self.ratio(text, on: pill) >= 4.5)
  }

  @Test(arguments: flavors)
  func restoreTitleReadsOnMustard(flavor: ThemeFlavor) {
    let value = Self.ratio(BrandTokens.onAccent.resolve(flavor), on: BrandTokens.accent.resolve(flavor))
    #expect(value >= 4.5, "\(value):1")
  }
}
