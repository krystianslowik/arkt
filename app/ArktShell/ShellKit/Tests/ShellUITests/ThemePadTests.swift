import CoreGraphics
import Testing
@testable import ShellUI

/// The colour pad's mapping (design/theme-creator/README.md, "Colour pad"): hue across, tone down.
struct ThemePadTests {
  static func close(_ a: RGBA, _ b: RGBA, _ tolerance: Double = 1e-9) -> Bool {
    abs(a.red - b.red) < tolerance && abs(a.green - b.green) < tolerance && abs(a.blue - b.blue) < tolerance
  }

  @Test func toneRunsFromPorcelainThroughTheHueToNearBlack() {
    #expect(Self.close(ThemePad.color(ThemePadPoint(hue: 120, tone: 0)), .srgb(hex: 0xFAF9F5)))
    #expect(Self.close(ThemePad.color(ThemePadPoint(hue: 120, tone: 1)), .srgb(hex: 0x121214)))
    // The middle is the hue at HSL 60 %, 52 %: hue 0 is (0.808, 0.232, 0.232).
    #expect(Self.close(ThemePad.color(ThemePadPoint(hue: 0, tone: 0.5)), RGBA(red: 0.808, green: 0.232,
                                                                           blue: 0.232, alpha: 1)))
    let quarter = ThemePad.color(ThemePadPoint(hue: 0, tone: 0.25))
    #expect(Self.close(quarter, RGBA.mix(.srgb(hex: 0xFAF9F5), RGBA(red: 0.808, green: 0.232, blue: 0.232, alpha: 1),
                                         0.5)))
  }

  @Test func colorsAreOpaqueSRGB() {
    let color = ThemePad.color(ThemePadPoint(hue: 216, tone: 0.74))
    #expect(color.alpha == 1 && color.space == .sRGB)
  }

  /// The pad draws its field in the same function, so a dot shows exactly the colour it stores.
  @Test func locationAndPointRoundTrip() {
    let size = ThemePad.size
    for point in [ThemePadPoint(hue: 0, tone: 0.06), ThemePadPoint(hue: 216, tone: 0.74),
                  ThemePadPoint(hue: 359, tone: 0.94)] {
      let location = ThemePad.location(of: point, in: size)
      let back = ThemePad.point(at: location, in: size)
      #expect(abs(back.hue - point.hue) < 1e-9 && abs(back.tone - point.tone) < 1e-9)
    }
    #expect(ThemePad.location(of: ThemePadPoint(hue: 180, tone: 0.5), in: size) == CGPoint(x: 136, y: 106))
  }

  /// The top and bottom 6 % cannot be reached; the pointer clamps hue at the pad's edges.
  @Test func pointerClampsToTheReachableBand() {
    let size = ThemePad.size
    let above = ThemePad.point(at: CGPoint(x: -40, y: -30), in: size)
    #expect(above.tone == ThemePad.minimumTone && above.hue == 0)
    let below = ThemePad.point(at: CGPoint(x: 400, y: 500), in: size)
    #expect(below.tone == ThemePad.maximumTone && below.hue == 360)
    #expect(ThemePad.minimumTone == 0.06 && ThemePad.maximumTone == 0.94)
  }

  @Test func nearestPointKeepsTheHueAndFindsTheClosestTone() {
    let stored = ThemePad.color(ThemePadPoint(hue: 27, tone: 0.34))
    let point = ThemePad.nearestPoint(to: stored)
    #expect(abs(point.hue - 27) < 0.5)
    #expect(abs(point.tone - 0.34) < 0.002)
    // An off-pad colour (pure white) lands on the top limit.
    let white = ThemePad.nearestPoint(to: .white(1))
    #expect(white.tone == ThemePad.minimumTone)
    // A preset's colour lands near its own hue, on the pad colour closest to it.
    let pinkColor = RGBA.srgb(hex: 0xF29BBB)
    let pink = ThemePad.nearestPoint(to: pinkColor)
    #expect(abs(pink.hue - ThemePad.hue(of: pinkColor)) <= ThemePad.nearestHueWindow)
    let atHue = ThemePad.nearestTone(to: pinkColor, hue: ThemePad.hue(of: pinkColor))
    #expect(ThemePad.distance(ThemePad.color(pink), pinkColor)
      <= ThemePad.distance(ThemePad.color(ThemePadPoint(hue: ThemePad.hue(of: pinkColor), tone: atHue)), pinkColor))
  }

  /// Pad colours drift a little in HSL hue toward the warm porcelain and the cool near-black ends; the nearest point
  /// still finds them exactly.
  @Test func padColoursFindTheirOwnPoint() {
    for point in [ThemePadPoint(hue: 0, tone: 0.06), ThemePadPoint(hue: 120, tone: 0.94),
                  ThemePadPoint(hue: 300, tone: 0.5)] {
      let found = ThemePad.nearestPoint(to: ThemePad.color(point))
      let hueGap = min(abs(found.hue - point.hue), 360 - abs(found.hue - point.hue))
      #expect(hueGap < 0.05 && abs(found.tone - point.tone) < 0.0005, "\(point) -> \(found)")
    }
  }

  /// The HSL hue of each family's second light stop: the preset hues the haptics mark.
  @Test func presetHuesMatchTheDesign() {
    let hues = SpaceThemeCatalog.families.map { ThemePad.hue(of: $0.light.baseColors[1]).rounded() }
    #expect(hues == [45, 238, 37, 107, 338, 250])
  }

  /// The second colour springs out 40 degrees of hue away and a quarter of the pad toward the middle.
  @Test func secondColourSitsFortyDegreesAwayTowardTheMiddle() {
    let fromLight = ThemePad.secondPoint(from: ThemePadPoint(hue: 340, tone: 0.2))
    #expect(abs(fromLight.hue - 20) < 1e-9 && abs(fromLight.tone - 0.45) < 1e-9)
    let fromDark = ThemePad.secondPoint(from: ThemePadPoint(hue: 216, tone: 0.74))
    #expect(abs(fromDark.hue - 256) < 1e-9 && abs(fromDark.tone - 0.49) < 1e-9)
  }

  /// Arrows: hue by 2 degrees (wrapping), tone by 2 %; Shift: 10 and 10 %. Up is lighter.
  @Test func keyboardSteps() {
    let start = ThemePadPoint(hue: 1, tone: 0.5)
    #expect(ThemePad.step(start, .left, large: false) == ThemePadPoint(hue: 359, tone: 0.5))
    #expect(ThemePad.step(start, .right, large: true) == ThemePadPoint(hue: 11, tone: 0.5))
    let up = ThemePad.step(start, .up, large: false)
    #expect(abs(up.tone - 0.48) < 1e-9)
    let down = ThemePad.step(start, .down, large: true)
    #expect(abs(down.tone - 0.6) < 1e-9)
    #expect(ThemePad.step(ThemePadPoint(hue: 0, tone: 0.9), .down, large: true).tone == ThemePad.maximumTone)
  }

  @Test func accessibilityValueNamesTheColourAndTone() {
    #expect(ThemePad.accessibilityValue(ThemePadPoint(hue: 216, tone: 0.74)) == "blue, light 26 percent")
    #expect(ThemePad.accessibilityValue(ThemePadPoint(hue: 27, tone: 0.34)) == "orange, light 66 percent")
    #expect(ThemePad.colorName(hue: 0) == "red" && ThemePad.colorName(hue: 355) == "red")
    #expect(ThemePad.colorName(hue: 120) == "green" && ThemePad.colorName(hue: 300) == "pink")
  }
}
