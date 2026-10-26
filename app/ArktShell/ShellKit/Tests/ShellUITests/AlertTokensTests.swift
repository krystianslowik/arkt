import Testing
@testable import ShellUI

/// Alerts design 3.2 and 4.2: the destructive red's contrast and the toast surface tinted by the Space theme.
struct AlertTokensTests {
  /// The prototype's blue Work theme.
  private static let work = SpaceThemeInfo(baseColors: [.srgb(hex: 0x3B82F6), .srgb(hex: 0x93C5FD)], isDark: false)
  private static let workDark = SpaceThemeInfo(baseColors: [.srgb(hex: 0x3B82F6)], isDark: true)

  @Test(arguments: [ThemeFlavor.light, .dark])
  func destructiveTextReadsOnTheNeutralPillIdleAndHovered(_ flavor: ThemeFlavor) {
    let surface = AlertTokens.dialogSurface.resolve(flavor)
    let text = AlertTokens.destructiveText.resolve(flavor)
    for fill in [ShellTokens.sidebarItemHovered, ShellTokens.sidebarItemBackground] {
      let seen = BrandTokens.composite(fill.resolve(flavor), over: surface)
      #expect(Contrast.ratio(text, seen) >= Contrast.minimumText)
    }
  }

  @Test func theDestructiveRedIsTheDesignedPair() {
    #expect(AlertTokens.destructiveText.light == .srgb(hex: 0xB3261E))
    #expect(AlertTokens.destructiveText.dark == .srgb(hex: 0xFFAAA2))
  }

  @Test func theDefaultThemeKeepsThePlainSurface() {
    #expect(AlertTokens.toastSurface(theme: nil) == ShellTokens.toastSurface.light)
    let white = SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    #expect(AlertTokens.toastSurface(theme: white) == ShellTokens.toastSurface.light)
    let black = SpaceThemeInfo(baseColors: [.black(1)], isDark: true)
    #expect(AlertTokens.toastSurface(theme: black) == ShellTokens.toastSurface.dark)
  }

  @Test func aColoredThemeTintsTheSurfaceByItsFirstStop() {
    let light = AlertTokens.toastSurface(theme: Self.work)
    #expect(abs(light.blue - (1 + (Double(0xF6) / 255 - 1) * 0.22)) < 0.001)
    #expect(abs(light.red - (1 + (Double(0x3B) / 255 - 1) * 0.22)) < 0.001)
    #expect(light.alpha == 0.96)
    let dark = AlertTokens.toastSurface(theme: Self.workDark)
    #expect(dark.blue > dark.red, "faintly blue")
    #expect(dark.alpha == 0.96)
  }

  @Test func reduceTransparencyMakesTheSurfaceOpaque() {
    #expect(AlertTokens.toastSurface(theme: Self.work, opaque: true).alpha == 1)
    #expect(AlertTokens.toastSurface(theme: nil, opaque: true).alpha == 1)
  }

  @Test func toastTextReadsOnTheTintedSurfaces() {
    for theme in [Self.work, Self.workDark] {
      let surface = AlertTokens.toastSurface(theme: theme, opaque: true)
      let text = BrandTokens.composite(ShellTokens.toastText.resolve(theme.flavor), over: surface)
      #expect(Contrast.ratio(text, surface) >= Contrast.minimumText)
    }
  }
}
