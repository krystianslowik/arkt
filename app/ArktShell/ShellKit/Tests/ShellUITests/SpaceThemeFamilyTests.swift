import Testing
@testable import ShellUI

/// Onboarding spec, section 5: six theme families for the first Space, Dune first and the default.
struct SpaceThemeFamilyTests {
  @Test func familiesInOrderDuneFirst() {
    #expect(SpaceThemeCatalog.families.map(\.title) == ["Dune", "Mist", "Paper", "Sage", "Blossom", "Indigo"])
    #expect(SpaceThemeCatalog.defaultFamily == SpaceThemeCatalog.families[0])
    #expect(SpaceThemeCatalog.defaultFamily.title == "Dune")
  }

  @Test func stopsMatchTheSpec() {
    let expected: [(String, [UInt32], [UInt32])] = [
      ("Dune", [0xF7EED2, 0xEBD592], [0x3D3420, 0x1E1A10]),
      ("Mist", [0xE0F2FB, 0xC5C6E2], [0x3A4158, 0x1C2030]),
      ("Paper", [0xF4F1EA, 0xE4DDD2], [0x3A3631, 0x211F1C]),
      ("Sage", [0xE6EDE3, 0xC4D3C0], [0x2F3B33, 0x171E1A]),
      ("Blossom", [0xF2EAE4, 0xF29BBB], [0x4A2A3A, 0x1F1520]),
      ("Indigo", [0xE4E2F4, 0xC9C3E8], [0x2D4468, 0x120F2E]),
    ]
    for (family, (title, light, dark)) in zip(SpaceThemeCatalog.families, expected) {
      #expect(family.title == title)
      #expect(family.light.baseColors == light.map { RGBA.srgb(hex: $0) }, "\(title) light")
      #expect(family.dark.baseColors == dark.map { RGBA.srgb(hex: $0) }, "\(title) dark")
      #expect(!family.light.isDark && family.dark.isDark)
      #expect(family.light.texture == nil && family.dark.texture == nil)
    }
  }

  @Test func themeForFlavor() {
    let dune = SpaceThemeCatalog.defaultFamily
    #expect(dune.theme(.light) == dune.light)
    #expect(dune.theme(.dark) == dune.dark)
  }

  /// The header menu's two named themes are family members, so nothing outside the families ships.
  @Test func headerMenuThemesAreFamilyMembers() {
    let all = SpaceThemeCatalog.families.flatMap { [$0.light, $0.dark] }
    #expect(all.contains(SpaceThemeCatalog.paper))
    #expect(all.contains(SpaceThemeCatalog.dusk))
  }

  /// Every family stop is measured by `ShellTokensContrastTests` (spec: "Each stop pair must pass").
  @MainActor
  @Test func everyFamilyIsAShippedTheme() {
    let shipped = ShellContrastProbe.shippedThemes()
    for family in SpaceThemeCatalog.families {
      #expect(shipped.contains(family.light), "\(family.title) light")
      #expect(shipped.contains(family.dark), "\(family.title) dark")
    }
  }
}
