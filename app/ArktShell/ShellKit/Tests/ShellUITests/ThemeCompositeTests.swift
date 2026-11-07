import AppKit
import Testing
@testable import ShellUI

/// The compositor takes the opaque base and opacity-scaled overlay produced by ThemeContrast.drawn.
struct ThemeCompositeTests {
  @Test func unequalStopsCompositeAtOverlayMiddle() throws {
    let base: [RGBA] = [.black(1), .white(1)]
    let overlay: [RGBA] = [.black(0), .srgb(hex: 0xFF0000, alpha: 0.4), .white(0)]
    let stops = ThemeGradient.composite(base: base, overlay: overlay)
    let middle = try #require(stops.first { abs($0.location - 0.5) < 1e-9 })
    let underneath = ThemeGradient.sample(base, at: 0.5)
    #expect(abs(middle.color.red - (0.4 + underneath.red * 0.6)) < 1e-6)
    #expect(abs(middle.color.green - underneath.green * 0.6) < 1e-6)
    #expect(abs(middle.color.blue - underneath.blue * 0.6) < 1e-6)
    #expect(abs(middle.color.alpha - 1) < 1e-9)
  }

  @Test func retainsUnevenStopLocationsAndInterpolatesTheOtherGradient() throws {
    let base: [RGBA] = [.black(1), .white(1)]
    let overlay: [RGBA] = [.black(0), .white(0.5), .black(0), .white(0)]
    let stops = ThemeGradient.composite(base: base, overlay: overlay)
    let location = 1.0 / 3.0
    let third = try #require(stops.first { abs($0.location - location) < 1e-9 })
    // The existing expanded base is linearly interpolated by the gradient layer between its samples.
    let expanded = ThemeGradient.expand(base)
    let position = location * Double(expanded.count - 1)
    let index = Int(position)
    let underneath = RGBA.mix(expanded[index], expanded[index + 1], position - Double(index))
    #expect(abs(third.color.red - (0.5 + underneath.red * 0.5)) < 1e-6)
    #expect(abs(third.color.green - (0.5 + underneath.green * 0.5)) < 1e-6)
    #expect(abs(third.color.blue - (0.5 + underneath.blue * 0.5)) < 1e-6)
    #expect(stops.first?.location == 0 && stops.last?.location == 1)
    #expect(zip(stops, stops.dropFirst()).allSatisfy { pair in pair.0.location < pair.1.location })
  }

  @Test func resolvedOpacityIsAppliedOnlyOnce() throws {
    let theme = SpaceThemeInfo(baseColors: [.white(1)], overlayColors: [.black(0.8)], opacity: 0.5, isDark: false)
    let drawn = ThemeContrast.drawn(theme, in: ThemeContext(appearance: .light))
    let stops = ThemeGradient.composite(base: drawn.baseColors, overlay: drawn.overlayColors)
    let first = try #require(stops.first)
    #expect(abs(drawn.overlayColors[0].alpha - 0.4) < 1e-9)
    #expect(abs(first.color.red - drawn.baseColors[0].red * 0.6) < 1e-6)
    #expect(abs(first.color.green - drawn.baseColors[0].green * 0.6) < 1e-6)
    #expect(abs(first.color.blue - drawn.baseColors[0].blue * 0.6) < 1e-6)
  }

  @Test(arguments: [0.25, 1.0])
  func mixedColorSpacesConvertBeforeBlending(alpha: Double) throws {
    let pairs: [(RGBA, RGBA)] = [
      (.p3(hex: 0x5A8CBA, alpha: 1), .srgb(hex: 0xC47850, alpha: alpha)),
      (.srgb(hex: 0x5A8CBA), .p3(hex: 0xA07860, alpha: alpha)),
    ]
    for (base, overlay) in pairs {
      let name = base.space == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB
      let target = try #require(CGColorSpace(name: name))
      let converted = try #require(overlay.cgColor.converted(to: target, intent: .relativeColorimetric, options: nil))
      let components = try #require(converted.components)
      let result = try #require(ThemeGradient.composite(base: [base], overlay: [overlay]).first?.color)
      #expect(result.space == base.space)
      for (actual, top, bottom) in zip(zip([result.red, result.green, result.blue], components),
                                       [base.red, base.green, base.blue]).map({ ($0.0.0, Double($0.0.1), $0.1) }) {
        #expect(abs(actual - (top * alpha + bottom * (1 - alpha))) < 0.003)
      }
      #expect(result.alpha == 1)
    }
  }

  @Test func noOverlayKeepsTheExpandedBase() {
    let base: [RGBA] = [.srgb(hex: 0x336699), .srgb(hex: 0xF29BBB)]
    let expanded = ThemeGradient.expand(base)
    let stops = ThemeGradient.composite(base: base, overlay: [])
    #expect(stops.count == expanded.count)
    for (index, pair) in zip(stops, expanded).enumerated() {
      let (stop, color) = pair
      #expect(stop.color == color)
      #expect(abs(stop.location - Double(index) / Double(expanded.count - 1)) < 1e-9)
    }
  }

  @Test func emptyAndSingleStopsAndSharedUnionLocations() throws {
    #expect(ThemeGradient.composite(base: [], overlay: [.black(0.5)]).isEmpty)
    let flat = ThemeGradient.composite(base: [.p3(hex: 0x0000FF, alpha: 1)], overlay: [.p3(hex: 0xFF0000, alpha: 0.5)])
    let stop = try #require(flat.first)
    #expect(flat.count == 1 && stop.location == 0)
    #expect(stop.color.space == RGBA.Space.displayP3)
    #expect(abs(stop.color.red - 0.5) < 1e-9 && abs(stop.color.blue - 0.5) < 1e-9)
    let shared = ThemeGradient.composite(base: [.black(1), .white(1)],
                                         overlay: [.black(0), .white(0.5), .black(0)])
    #expect(shared.filter { $0.location == 0.5 }.count == 1)
    #expect(zip(shared, shared.dropFirst()).allSatisfy { $0.location < $1.location })
  }

}
