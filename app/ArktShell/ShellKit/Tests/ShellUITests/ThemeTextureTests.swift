import AppKit
import Testing
@testable import ShellUI

// MARK: - Synthesis

/// Statistics of a tile of multiply factors (0...1), with wraparound neighbours.
private struct TileStats {
  let mean: Double
  let deviation: Double
  let pixels: Int
  private let values: [Double]

  init(_ bytes: [UInt8], pixels: Int) {
    let values = bytes.map { Double($0) / 255 }
    let mean = values.reduce(0, +) / Double(values.count)
    self.values = values
    self.pixels = pixels
    self.mean = mean
    deviation = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
  }

  /// Correlation between each pixel and the one `dx`, `dy` away (wrapping).
  func correlation(_ dx: Int, _ dy: Int) -> Double {
    var sum = 0.0
    for y in 0..<pixels {
      for x in 0..<pixels {
        let other = values[((y + dy + pixels) % pixels) * pixels + (x + dx + pixels) % pixels]
        sum += (values[y * pixels + x] - mean) * (other - mean)
      }
    }
    return sum / Double(values.count) / (deviation * deviation)
  }
}

struct ThemeTextureSynthesisTests {
  @Test func namesMapToTexturesAndUnknownNamesDrawAsGrain() {
    #expect(ThemeTexture(name: nil) == nil)
    #expect(ThemeTexture(name: "grain") == .grain)
    #expect(ThemeTexture(name: "Sand") == .sand)
    #expect(ThemeTexture(name: "denim") == .denim)
    #expect(ThemeTexture(name: "tweed") == .tweed)
    #expect(ThemeTexture(name: "linen") == .grain)
  }

  @Test(arguments: ThemeTexture.allCases)
  func theMasterTileIsDeterministic(texture: ThemeTexture) {
    let tile = texture.masterTile()
    #expect(tile.count == ThemeTexture.masterPixels * ThemeTexture.masterPixels)
    #expect(tile == texture.masterTile())
  }

  /// The target 2x statistics of each texture: mean factor, spread and neighbour correlation.
  @Test(arguments: ThemeTexture.allCases)
  func theMasterTileMatchesTheMeasuredStatistics(texture: ThemeTexture) {
    let stats = TileStats(texture.masterTile(), pixels: ThemeTexture.masterPixels)
    let target = texture.target
    #expect(abs(stats.mean - target.mean) < 0.006, "mean \(stats.mean)")
    #expect(abs(stats.deviation - target.deviation) / target.deviation < 0.08, "deviation \(stats.deviation)")
    if texture != .denim {
      #expect(abs(stats.correlation(1, 0) - target.lag1.x) < 0.06, "lag x \(stats.correlation(1, 0))")
      #expect(abs(stats.correlation(0, 1) - target.lag1.y) < 0.06, "lag y \(stats.correlation(0, 1))")
      #expect(abs(stats.correlation(4, 0)) < 0.06, "no structure beyond the grain size")
    }
  }

  /// Twill: ribs along the diagonal (strong correlation along x = y), a period of about 4.4 px across them.
  @Test func denimHasADiagonalTwill() {
    let stats = TileStats(ThemeTexture.denim.masterTile(), pixels: ThemeTexture.masterPixels)
    #expect(stats.correlation(1, 1) > 0.7)
    #expect(stats.correlation(2, 2) > 0.7)
    #expect(stats.correlation(1, -1) < -0.5)
    #expect(stats.correlation(2, 0) < -0.5)
    #expect(stats.correlation(4, 0) > 0.4)
  }

  /// Texels darken or leave the gradient alone; grain's light end is flat at 1.
  @Test func grainNeverBrightensAndReachesOne() {
    let tile = ThemeTexture.grain.masterTile()
    #expect(tile.max() == 255)
    #expect(Double(tile.min() ?? 0) / 255 > 0.6)
  }

  /// Seamless: the jump across the tile's wrap edge is no larger than between two interior columns.
  @Test(arguments: ThemeTexture.allCases)
  func theTileWrapsWithoutASeam(texture: ThemeTexture) {
    let n = ThemeTexture.masterPixels
    let tile = texture.masterTile().map(Double.init)
    func columnStep(_ a: Int, _ b: Int) -> Double {
      (0..<n).reduce(0) { $0 + abs(tile[$1 * n + a] - tile[$1 * n + b]) } / Double(n)
    }
    func rowStep(_ a: Int, _ b: Int) -> Double {
      (0..<n).reduce(0) { $0 + abs(tile[a * n + $1] - tile[b * n + $1]) } / Double(n)
    }
    let interiorColumns = (1..<n).map { columnStep($0 - 1, $0) }.reduce(0, +) / Double(n - 1)
    let interiorRows = (1..<n).map { rowStep($0 - 1, $0) }.reduce(0, +) / Double(n - 1)
    #expect(columnStep(n - 1, 0) < interiorColumns * 1.25)
    #expect(rowStep(n - 1, 0) < interiorRows * 1.25)
  }

  @Test(arguments: ThemeTexture.allCases)
  func theOneXTileIsTheMasterBoxDownsampled(texture: ThemeTexture) {
    let one = texture.tile(scale: 1)
    #expect(one.pixels == ThemeTexture.tilePoints)
    let master = texture.masterTile(), n = ThemeTexture.masterPixels
    let sum = Int(master[0]) + Int(master[1]) + Int(master[n]) + Int(master[n + 1])
    #expect(Int(one.bytes[0]) == (sum + 2) / 4)
    let two = texture.tile(scale: 2)
    #expect(two.pixels == ThemeTexture.masterPixels && two.bytes == master)
    #expect(abs(TileStats(one.bytes, pixels: one.pixels).mean - texture.meanFactor) < 0.006)
  }
}

// MARK: - Intensity

struct ThemeTextureIntensityTests {
  /// The overlay alpha is the theme's noiseFactor: `gradient * mix(1, texel, noiseFactor)`.
  @Test func overlayAlphaIsTheNoiseFactor() {
    #expect(ShellTokens.themeTextureMaxOpacity == 1)
    let theme = SpaceThemeInfo(baseColors: [.white(1)], texture: "sand", noiseFactor: 0.35, isDark: false)
    #expect(abs(theme.textureOpacity - 0.35) < 1e-12)
    #expect(theme.textureKind == .sand)
    #expect(SpaceThemeInfo(baseColors: [.white(1)], noiseFactor: 0.35, isDark: false).textureKind == nil)
  }

  /// The mean darkening a texture applies at a given alpha, which the contrast probe composites.
  @Test func meanFactorAtAlphaMixesTowardOne() {
    let theme = SpaceThemeInfo(baseColors: [.white(1)], texture: "tweed", noiseFactor: 0.5, isDark: false)
    #expect(abs(theme.meanTextureFactor - (1 - 0.5 * (1 - ThemeTexture.tweed.meanFactor))) < 1e-12)
    #expect(SpaceThemeInfo(baseColors: [.white(1)], isDark: false).meanTextureFactor == 1)
  }
}

// MARK: - Layers

@MainActor
struct ThemeGrainLayerTests {
  private func theme(_ texture: String?, _ noise: Double, dark: Bool = false) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: [.p3(hex: 0xF2EAE4, alpha: 1), .p3(hex: 0xF29BBB, alpha: 1)], texture: texture,
                   noiseFactor: noise, isDark: dark)
  }

  /// No Metal: the static Core Animation tier. Same layer per texture, multiply compositing.
  private func view(_ themes: [SpaceThemeInfo]) -> ThemeBackgroundView {
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 120, height: 80), grainRenderer: nil)
    view.reducesMotion = { false }
    view.themes = themes
    view.setPosition(0)
    return view
  }

  @Test func eachTextureHasItsOwnMultiplyLayer() throws {
    let view = view([theme("grain", 0.5), theme("sand", 1)])
    let grain = try #require(view.grainLayerForTesting(.grain))
    let sand = try #require(view.grainLayerForTesting(.sand))
    #expect(grain !== sand)
    #expect(grain.compositingFilter as? String == "multiplyBlendMode")
    #expect(sand.compositingFilter as? String == "multiplyBlendMode")
    #expect(view.grainLayerForTesting(.denim) == nil, "layers exist only for textures in use")
  }

  /// Between two Spaces each texture's alpha follows its own Space's weight; a texture at 0 is hidden.
  @Test func alphasFollowThePagerPerTexture() throws {
    let view = view([theme("grain", 0.5), theme("sand", 1), theme(nil, 0)])
    #expect(abs(view.grainOpacityForTesting(.grain) - 0.5) < 1e-6)
    #expect(view.grainOpacityForTesting(.sand) == 0)
    #expect(try #require(view.grainLayerForTesting(.sand)).isHidden)
    view.setPosition(0.25)
    #expect(abs(view.grainOpacityForTesting(.grain) - 0.375) < 1e-6)
    #expect(abs(view.grainOpacityForTesting(.sand) - 0.25) < 1e-6)
    #expect(try #require(view.grainLayerForTesting(.sand)).isHidden == false)
    view.setPosition(1.5)
    #expect(abs(view.grainOpacityForTesting(.sand) - 0.5) < 1e-6)
    #expect(view.grainOpacityForTesting(.grain) == 0)
    #expect(try #require(view.grainLayerForTesting(.grain)).isHidden)
  }

  @Test func twoSpacesWithTheSameTextureShareItsLayer() {
    let view = view([theme("tweed", 0.2), theme("tweed", 0.6)])
    view.setPosition(0.5)
    #expect(abs(view.grainOpacityForTesting(.tweed) - 0.4) < 1e-6)
    #expect(abs(view.grainOpacityForTesting - 0.4) < 1e-6)
  }

  /// Changing the current Space's texture fades the old texture out and the new one in, with the gradient.
  @Test func aTextureChangeCrossfadesBothTextures() throws {
    let view = view([theme("grain", 0.5), theme(nil, 0)])
    view.crossfadeDuration = 0.28
    view.replaceThemes([theme("denim", 0.8), theme(nil, 0)], crossfade: true)
    let out = try #require(view.grainFadeForTesting(.grain))
    let into = try #require(view.grainFadeForTesting(.denim))
    #expect((out.fromValue as? NSNumber)?.floatValue == 0.5 && (out.toValue as? NSNumber)?.floatValue == 0)
    #expect((into.fromValue as? NSNumber)?.floatValue == 0 && (into.toValue as? NSNumber)?.floatValue == 0.8)
    #expect(out.duration == 0.28 && into.duration == 0.28)
    #expect(try #require(view.grainLayerForTesting(.grain)).isHidden == false, "the fading texture stays shown")
    view.setPosition(0)
    #expect(view.grainFadeForTesting(.grain) == nil && view.grainFadeForTesting(.denim) == nil)
    #expect(try #require(view.grainLayerForTesting(.grain)).isHidden)
  }

  /// The Core Animation tier tiles the same synthesized texture as the Metal tier.
  @Test func theFallbackTierTilesThePattern() throws {
    let view = view([theme("sand", 1)])
    let layer = try #require(view.grainLayerForTesting(.sand))
    #expect(layer.backgroundColor?.pattern != nil)
    #expect(!(layer is CAMetalLayer))
  }
}
