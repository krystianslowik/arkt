import Foundation

/// The four tiled Space theme textures (Arc: `Modifiers.overlay`), synthesized procedurally.
///
/// Arc composites its overlay as a multiply: `gradient * mix(1, texel, alpha)`, with `alpha` the overlay alpha the
/// theme's `noiseFactor` sets. A texel here is that multiply factor (1 leaves the gradient alone, lower darkens), so
/// a texture's look is its statistics: the mean factor (how much it darkens), the spread (how loud it is) and the
/// correlation between neighbouring pixels (grain size and weave). The targets below were measured from the shipped
/// textures at 2x; no bitmap is copied. Each tile is seamless and deterministic: the same seed always yields the
/// same bytes.
public enum ThemeTexture: String, CaseIterable, Sendable {
  case grain, sand, denim, tweed

  /// The texture for a stored name; unknown names draw as grain, nil means no texture.
  public init?(name: String?) {
    guard let name else { return nil }
    self = ThemeTexture(rawValue: name.lowercased()) ?? .grain
  }

  /// Tile edge in points (the renderer's tiles are 100 pt, `masterPixels` at 2x).
  public static let tilePoints = 100
  /// Edge of the synthesized master tile, in pixels: one tile at 2x.
  public static let masterPixels = 200

  /// Measured statistics of the multiply factor at 2x.
  struct Target: Sendable {
    var mean: Double
    var deviation: Double
    /// Correlation with the neighbour one pixel to the right and one pixel down.
    var lag1: (x: Double, y: Double)
  }

  var target: Target {
    switch self {
    case .grain: Target(mean: 0.931, deviation: 0.055, lag1: (0.38, 0.39))
    case .sand: Target(mean: 0.656, deviation: 0.207, lag1: (0.55, 0.54))
    case .denim: Target(mean: 0.841, deviation: 0.049, lag1: (0.24, 0.25))
    case .tweed: Target(mean: 0.706, deviation: 0.046, lag1: (0.42, 0.50))
    }
  }

  /// Mean multiply factor of the tile: how much the texture darkens at full alpha.
  public var meanFactor: Double { target.mean }

  // MARK: - Synthesis

  /// The 2x master tile, row-major, `masterPixels` squared bytes of the multiply factor (0...255 for 0...1).
  public func masterTile() -> [UInt8] {
    let n = Self.masterPixels
    var random = SplitMix64(seed: seed)
    let field: [Double]
    switch self {
    case .grain:
      // Fine film grain: lightly smoothed noise, clipped at 1 so the light end is flat (texels never brighten).
      let z = Self.normalized(Self.smooth(Self.noise(n, &random), n, ax: 0.206, ay: 0.214))
      field = z.map { min(1, 0.9375 + 0.0660 * $0) }
    case .sand:
      // Coarse sand: heavier smoothing and a wide, nearly symmetric spread.
      let z = Self.normalized(Self.smooth(Self.noise(n, &random), n, ax: 0.338, ay: 0.330))
      field = z.map { 0.660 + 0.2160 * $0 }
    case .tweed:
      // Tweed: flecks stretched along the vertical warp.
      let z = Self.normalized(Self.smooth(Self.noise(n, &random), n, ax: 0.233, ay: 0.293))
      field = z.map { 0.706 + 0.046 * $0 }
    case .denim:
      // Twill: diagonal ribs (constant along x = y, 45 periods across the tile so it wraps), with thread noise
      // smoothed along the ribs.
      let ribs = Self.normalized(Self.smoothDiagonal(Self.noise(n, &random), n, a: 0.15))
      let cycles = 45.0
      field = (0..<(n * n)).map { i in
        let x = Double(i % n), y = Double(i / n)
        let phase = 2 * Double.pi * cycles * (x - y) / Double(n)
        return 0.841 + 0.049 * (0.86 * 2.0.squareRoot() * cos(phase) + 0.51 * ribs[i])
      }
    }
    return field.map { UInt8(clamping: Int(($0 * 255).rounded())) }
  }

  /// Edge in pixels of the tile `tile(scale:)` returns.
  public static func tilePixels(scale: Double) -> Int { scale < 1.5 ? tilePoints : masterPixels }

  /// The tile for a backing scale: the master at 2x and above, box-downsampled to `tilePoints` pixels below.
  public func tile(scale: Double) -> (bytes: [UInt8], pixels: Int) {
    let master = masterTile()
    guard Self.tilePixels(scale: scale) == Self.tilePoints else { return (master, Self.masterPixels) }
    let n = Self.masterPixels, half = n / 2
    var out = [UInt8](repeating: 0, count: half * half)
    for y in 0..<half {
      for x in 0..<half {
        let sum = Int(master[2 * y * n + 2 * x]) + Int(master[2 * y * n + 2 * x + 1])
          + Int(master[(2 * y + 1) * n + 2 * x]) + Int(master[(2 * y + 1) * n + 2 * x + 1])
        out[y * half + x] = UInt8((sum + 2) / 4)
      }
    }
    return (out, half)
  }

  private var seed: UInt64 {
    switch self {
    case .grain: 0x6772_6169_6E00_0001
    case .sand: 0x7361_6E64_0000_0002
    case .denim: 0x6465_6E69_6D00_0003
    case .tweed: 0x7477_6565_6400_0004
    }
  }

  /// Approximately normal noise (sum of four uniforms), zero mean.
  private static func noise(_ n: Int, _ random: inout SplitMix64) -> [Double] {
    (0..<(n * n)).map { _ in random.unit() + random.unit() + random.unit() + random.unit() - 2 }
  }

  /// Separable [a, 1, a] filter with wraparound, so the tile stays seamless.
  private static func smooth(_ v: [Double], _ n: Int, ax: Double, ay: Double) -> [Double] {
    var h = v
    for y in 0..<n {
      for x in 0..<n {
        h[y * n + x] = v[y * n + x] + ax * (v[y * n + (x + n - 1) % n] + v[y * n + (x + 1) % n])
      }
    }
    var out = h
    for y in 0..<n {
      for x in 0..<n {
        out[y * n + x] = h[y * n + x] + ay * (h[((y + n - 1) % n) * n + x] + h[((y + 1) % n) * n + x])
      }
    }
    return out
  }

  /// [a, 1, a] along the x = y diagonal, with wraparound.
  private static func smoothDiagonal(_ v: [Double], _ n: Int, a: Double) -> [Double] {
    (0..<(n * n)).map { i in
      let x = i % n, y = i / n
      return v[i] + a * (v[((y + n - 1) % n) * n + (x + n - 1) % n] + v[((y + 1) % n) * n + (x + 1) % n])
    }
  }

  /// Zero mean, unit deviation.
  private static func normalized(_ v: [Double]) -> [Double] {
    let mean = v.reduce(0, +) / Double(v.count)
    let variance = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)
    let deviation = variance.squareRoot()
    return v.map { ($0 - mean) / deviation }
  }
}

/// SplitMix64: a tiny deterministic generator, so a tile never depends on the system's random source.
struct SplitMix64 {
  private var state: UInt64
  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform in 0..<1.
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
