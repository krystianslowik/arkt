import Testing
@testable import ShellUI

/// The Peek tokens (docs/design/peek.md): the grabber is a non-text control, WCAG 1.4.11 asks 3:1. Measured against
/// white and against the dark page fill, each under `peekScrim`, as the design does (3.6:1 light, 6.3:1 dark).
@MainActor
struct PeekTokensContrastTests {
  /// The near-black page fill the dark design screenshots use.
  static let darkPage = RGBA.srgb(hex: 0x1C1C20)

  @Test func theGrabberValuesAreTheDesigns() {
    #expect(ShellTokens.peekGrabber == TokenPair(light: .black(0.50), dark: .white(0.55)))
    #expect(ShellTokens.peekScrim == TokenPair(light: .black(0.18), dark: .black(0.42)))
  }

  @Test func theLightGrabberHoldsThreeToOneOverAWhitePageUnderTheScrim() {
    let surface = ShellContrastProbe.over(ShellTokens.peekScrim.light, .white(1))
    let ratio = ShellContrastProbe.ratio(ShellContrastProbe.over(ShellTokens.peekGrabber.light, surface), surface)
    #expect(ratio >= 3, "light grabber \(ratio):1")
    #expect(ratio >= 3.5, "design value is 3.6:1, got \(ratio):1")
  }

  @Test func theDarkGrabberHoldsThreeToOneOverTheDarkPageUnderTheScrim() {
    let surface = ShellContrastProbe.over(ShellTokens.peekScrim.dark, Self.darkPage)
    let ratio = ShellContrastProbe.ratio(ShellContrastProbe.over(ShellTokens.peekGrabber.dark, surface), surface)
    #expect(ratio >= 3, "dark grabber \(ratio):1")
    #expect(ratio >= 6, "design value is 6.3:1, got \(ratio):1")
  }

  @Test func theGrabberHoldsThreeToOneOnPlainPagesToo() {
    let light = ShellContrastProbe.ratio(ShellContrastProbe.over(ShellTokens.peekGrabber.light, .white(1)), .white(1))
    let dark = ShellContrastProbe.ratio(ShellContrastProbe.over(ShellTokens.peekGrabber.dark, Self.darkPage),
                                        Self.darkPage)
    #expect(light >= 3 && dark >= 3)
  }

  @Test func thePeekShadowIsDeeperInDarkAndKeptThere() {
    #expect(ShellTokens.peekShadow.color.dark.alpha > ShellTokens.peekShadow.color.light.alpha)
    #expect(ShellTokens.peekShadow.color.dark.alpha > 0, "dark keeps the Peek shadow, unlike cardShadow")
    #expect(ShellTokens.peekShadow.radius == 24 && ShellTokens.peekShadow.offsetY == 18)
  }
}
