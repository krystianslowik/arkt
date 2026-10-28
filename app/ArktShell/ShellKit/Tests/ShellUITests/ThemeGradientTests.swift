import AppKit
import Testing
@testable import ShellUI

// MARK: - Color space

/// OKLab round trips and the defining property of the interpolation: the result is linear in OKLab, not in the
/// encoded sRGB/P3 components.
struct ThemeGradientMathTests {
  private let colors: [RGBA] = [
    .srgb(hex: 0x1C1C20), .srgb(hex: 0xF2F0EE), .p3(hex: 0x2D4468, alpha: 1), .p3(hex: 0xF29BBB, alpha: 1),
    RGBA(red: 0.1, green: 0.7, blue: 0.4, alpha: 0.35, space: .displayP3),
    RGBA(red: -0.05, green: 0.5, blue: 1.2, alpha: 1, space: .sRGB),
  ]

  @Test(arguments: [0, 1, 2, 3, 4])
  func oklabRoundTrips(index: Int) {
    let color = colors[index]
    let back = ThemeGradient.rgba(ThemeGradient.oklab(color), space: color.space, alpha: color.alpha)
    #expect(abs(back.red - color.red) < 1e-6, "red \(back.red) vs \(color.red)")
    #expect(abs(back.green - color.green) < 1e-6)
    #expect(abs(back.blue - color.blue) < 1e-6)
    #expect(abs(back.alpha - color.alpha) < 1e-6)
    #expect(back.space == color.space)
  }

  /// Extended components outside 0...1 (an imported P3 color stored as extended sRGB) clamp to the drawable range.
  @Test func outOfGamutComponentsClamp() {
    let color = colors[5]
    let back = ThemeGradient.rgba(ThemeGradient.oklab(color), space: color.space, alpha: color.alpha)
    #expect(back.red == 0)
    #expect(back.blue == 1)
    #expect(abs(back.green - color.green) < 1e-6)
  }

  @Test func theEndpointsAreNotMoved() {
    let a = RGBA.p3(hex: 0xF2EAE4, alpha: 1), b = RGBA.p3(hex: 0xF29BBB, alpha: 1)
    for (t, expected) in [(0.0, a), (1.0, b)] {
      let got = ThemeGradient.mix(a, b, t)
      #expect(abs(got.red - expected.red) < 1e-6)
      #expect(abs(got.green - expected.green) < 1e-6)
      #expect(abs(got.blue - expected.blue) < 1e-6)
      #expect(got.space == expected.space)
    }
  }

  /// OKLab: L, a and b each move linearly between the stops. A component-wise RGB blend would not.
  @Test func theMixIsLinearInOKLab() {
    let a = RGBA.p3(hex: 0x2D4468, alpha: 1), b = RGBA.p3(hex: 0xF29BBB, alpha: 1)
    let from = ThemeGradient.oklab(a), to = ThemeGradient.oklab(b)
    for t in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] {
      let lab = ThemeGradient.oklab(ThemeGradient.mix(a, b, t))
      #expect(abs(lab.l - (from.l + (to.l - from.l) * t)) < 2e-6, "L at \(t)")
      #expect(abs(lab.a - (from.a + (to.a - from.a) * t)) < 2e-6, "a at \(t)")
      #expect(abs(lab.b - (from.b + (to.b - from.b) * t)) < 2e-6, "b at \(t)")
    }
  }

  /// The perceptual middle of black and white is L 0.5, which is about sRGB 0.39, not the encoded 0.5. This is the
  /// visible difference from a component-wise blend.
  @Test func theBlackWhiteMiddleHasHalfTheOKLabLightness() {
    let middle = ThemeGradient.mix(.black(1), .white(1), 0.5)
    #expect(abs(ThemeGradient.oklab(middle).l - 0.5) < 1e-5)
    #expect(middle.red < 0.45, "encoded \(middle.red)")
    #expect(abs(middle.red - middle.green) < 1e-6 && abs(middle.green - middle.blue) < 1e-6)
  }

  @Test func theMiddleOfTwoSaturatedStopsIsNotTheEncodedMiddle() {
    let red = RGBA.srgb(hex: 0xFF0000), blue = RGBA.srgb(hex: 0x0000FF)
    let middle = ThemeGradient.mix(red, blue, 0.5)
    let encoded = RGBA.mix(red, blue, 0.5)
    #expect(abs(middle.red - encoded.red) > 0.02 || abs(middle.green - encoded.green) > 0.02
              || abs(middle.blue - encoded.blue) > 0.02, "OKLab and sRGB middles differ")
  }

  @Test func alphaIsLinearAndTIsClamped() {
    let a = RGBA(red: 1, green: 0, blue: 0, alpha: 0.2), b = RGBA(red: 0, green: 0, blue: 1, alpha: 0.8)
    #expect(abs(ThemeGradient.mix(a, b, 0.25).alpha - 0.35) < 1e-9)
    #expect(abs(ThemeGradient.mix(a, b, -1).alpha - 0.2) < 1e-9)
    #expect(abs(ThemeGradient.mix(a, b, 2).alpha - 0.8) < 1e-9)
  }

  @Test func theResultStaysInsideTheStopsGamut() {
    let a = RGBA.p3(hex: 0x00FF00, alpha: 1), b = RGBA.srgb(hex: 0x0000FF)
    for t in stride(from: 0.0, through: 1.0, by: 0.05) {
      let c = ThemeGradient.mix(a, b, t)
      #expect(c.red >= 0 && c.red <= 1 && c.green >= 0 && c.green <= 1 && c.blue >= 0 && c.blue <= 1)
      #expect(c.alpha >= 0 && c.alpha <= 1)
    }
  }
}

// MARK: - Stop expansion

struct ThemeGradientExpansionTests {
  private let stops = [RGBA.p3(hex: 0xF2EAE4, alpha: 1), RGBA.p3(hex: 0xF29BBB, alpha: 1),
                       RGBA.p3(hex: 0x120F2E, alpha: 1)]

  /// `(n - 1) * segments + 1` stops, so the endpoints stay exact and every junction appears once.
  @Test func everyPairIsExpandedIntoEvenSteps() {
    let expanded = ThemeGradient.expand(stops, segments: 8)
    #expect(expanded.count == (stops.count - 1) * 8 + 1)
    for (index, stop) in stops.enumerated() {
      let got = expanded[index * 8]
      #expect(abs(got.red - stop.red) < 1e-6 && abs(got.green - stop.green) < 1e-6
                && abs(got.blue - stop.blue) < 1e-6, "stop \(index) kept")
    }
  }

  /// Every expanded stop is the OKLab mix at its parameter, so a gradient layer gets the perceptual curve.
  @Test func eachStepIsThePerceptualMixAtItsParameter() {
    let expanded = ThemeGradient.expand(stops, segments: 4)
    for pair in 0..<(stops.count - 1) {
      for step in 1..<4 {
        let expected = ThemeGradient.mix(stops[pair], stops[pair + 1], Double(step) / 4)
        let got = expanded[pair * 4 + step]
        #expect(abs(got.red - expected.red) < 1e-6)
        #expect(abs(got.green - expected.green) < 1e-6)
        #expect(abs(got.blue - expected.blue) < 1e-6)
      }
    }
  }

  /// An encoded blend would reproduce the old behavior; the expansion must not.
  @Test func theExpandedStopsAreNotTheEncodedBlend() {
    let expanded = ThemeGradient.expand([RGBA.srgb(hex: 0xFF0000), RGBA.srgb(hex: 0x0000FF)], segments: 2)
    let encoded = RGBA.mix(RGBA.srgb(hex: 0xFF0000), RGBA.srgb(hex: 0x0000FF), 0.5)
    let middle = expanded[1]
    #expect(abs(middle.green - encoded.green) > 0.02 || abs(middle.blue - encoded.blue) > 0.02
              || abs(middle.red - encoded.red) > 0.02)
  }

  @Test func oneStopExpandsToItselfAndNoStopsStayEmpty() {
    #expect(ThemeGradient.expand([.white(1)]) == [.white(1)])
    #expect(ThemeGradient.expand([]).isEmpty)
    #expect(ThemeGradient.expand([.white(1)], segments: 0) == [.white(1)])
  }

  /// Light and dark themes take the same path: the expansion does not look at `isDark`.
  @Test func theExpansionWorksTheSameInBothSpaces() throws {
    let light = SpaceThemeInfo(baseColors: [.srgb(hex: 0xF4F1EA), .srgb(hex: 0xE4DDD2)], isDark: false)
    let dark = SpaceThemeInfo(baseColors: [.srgb(hex: 0x3A3631), .srgb(hex: 0x211F1C)], isDark: true)
    let lightStops = ThemeGradient.expand(light.baseColors)
    let darkStops = ThemeGradient.expand(dark.baseColors)
    #expect(lightStops.count == ThemeGradient.segmentsPerPair + 1)
    #expect(darkStops.count == lightStops.count)
    #expect(lightStops.allSatisfy { $0.space == .sRGB })
    #expect(darkStops.allSatisfy { $0.space == .sRGB })
    #expect(abs(try #require(lightStops.first).red - 0xF4 / 255.0) < 1e-6)
    #expect(abs(try #require(darkStops.first).red - 0x3A / 255.0) < 1e-6)
  }
}
