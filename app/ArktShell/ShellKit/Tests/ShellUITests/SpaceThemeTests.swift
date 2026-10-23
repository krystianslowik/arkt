import Testing
@testable import ShellUI

struct SpaceThemeTests {
  @Test func mixBlendsComponentsAndClamps() {
    let a = RGBA.black(0.2), b = RGBA.white(1)
    let half = RGBA.mix(a, b, 0.5)
    #expect(abs(half.red - 0.5) < 1e-9 && abs(half.alpha - 0.6) < 1e-9)
    #expect(RGBA.mix(a, b, -1) == a)
    #expect(RGBA.mix(a, b, 2) == b)
  }

  @Test func textureOpacityNeedsATexture() {
    let plain = SpaceThemeInfo(baseColors: [.white(1)], noiseFactor: 1, isDark: false)
    #expect(plain.textureOpacity == 0)
    let grain = SpaceThemeInfo(baseColors: [.white(1)], texture: "grain", noiseFactor: 0.5, isDark: false)
    #expect(abs(grain.textureOpacity - 0.5 * ShellTokens.themeTextureMaxOpacity) < 1e-9)
    let loud = SpaceThemeInfo(baseColors: [.white(1)], texture: "grain", noiseFactor: 4, isDark: false)
    #expect(loud.textureOpacity == ShellTokens.themeTextureMaxOpacity)
  }
}
