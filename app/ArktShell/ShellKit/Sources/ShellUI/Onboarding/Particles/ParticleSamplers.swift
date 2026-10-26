import CoreGraphics
import CoreText
import Foundation
import simd

/// The prototype's xorshift generator: the same seed builds the same formation.
struct SeededRandom: Sendable {
  private var state: UInt32

  init(seed: UInt32) { state = seed == 0 ? 1 : seed }

  mutating func next() -> Float {
    state ^= state << 13
    state ^= state >> 17
    state ^= state << 5
    return Float(state % 1_000_000_000) / 1_000_000_000
  }

  /// About a unit normal, from four uniforms (the prototype's `gauss`).
  mutating func gauss() -> Float { (next() + next() + next() + next() - 2) / 2 }
}

/// Points sampled from real type (section 7.2): the counts in Avenir Next DemiBold, the key caps' letters, the
/// Command glyph from the system font. Centred on the ink's box, in points. Never a vector redraw: the glyph is
/// rasterized and its covered pixels become the points.
enum GlyphSampler {
  struct Points: Sendable {
    var points: [SIMD2<Float>]
    var width: Float
    var height: Float
  }

  /// `postScriptName` nil uses the system font.
  static func points(_ text: String, size: CGFloat, postScriptName: String?, tracking: CGFloat = -0.04) -> Points {
    let font: CTFont = postScriptName.map { CTFontCreateWithName($0 as CFString, size, nil) }
      ?? CTFontCreateUIFontForLanguage(.system, size, nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTKernAttributeName as String): tracking * size,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetImageBounds(line, nil)
    let width = Int(ceil(bounds.width)) + 8, height = Int(ceil(size * 1.3))
    guard width > 8, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
      return Points(points: [], width: 0, height: 0)
    }
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.textPosition = CGPoint(x: 4 - bounds.minX, y: size * 0.3)
    CTLineDraw(line, context)
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
      return Points(points: [], width: 0, height: 0)
    }
    let step = max(1, Int((size / 120).rounded()))
    var raw: [SIMD2<Float>] = []
    var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude), high = -low
    for y in stride(from: 0, to: height, by: step) {
      for x in stride(from: 0, to: width, by: step) where data[y * width + x] >= 140 {
        let point = SIMD2(Float(x), Float(y))            // the context's first row is the image's top row
        raw.append(point)
        low = simd_min(low, point)
        high = simd_max(high, point)
      }
    }
    guard !raw.isEmpty else { return Points(points: [], width: 0, height: 0) }
    let centre = (low + high) / 2
    return Points(points: raw.map { $0 - centre }, width: high.x - low.x, height: high.y - low.y)
  }
}

/// Shapes from geometry (the prototype's `roundRect`, `foldPoint`, `project`).
enum ParticleGeometry {
  /// A point inside, or on the edge of, a rounded rectangle centred at 0.
  static func roundRect(_ random: inout SeededRandom, width w: Float, height h: Float, radius r: Float,
                        edge: Bool) -> SIMD2<Float> {
    var px: Float = 0, py: Float = 0
    for _ in 0..<64 {
      px = (random.next() - 0.5) * w
      py = (random.next() - 0.5) * h
      let qx = abs(px) - (w / 2 - r), qy = abs(py) - (h / 2 - r)
      if qx > 0, qy > 0, qx * qx + qy * qy > r * r { continue }
      break
    }
    guard edge else { return SIMD2(px, py) }
    if abs(px) / w > abs(py) / h { px = (px < 0 ? -1 : 1) * w / 2 } else { py = (py < 0 ? -1 : 1) * h / 2 }
    let qx = abs(px) - (w / 2 - r), qy = abs(py) - (h / 2 - r)
    if qx > 0, qy > 0 {
      let ox = (px < 0 ? -1 : 1) * (w / 2 - r), oy = (py < 0 ? -1 : 1) * (h / 2 - r)
      let dx = px - ox, dy = py - oy, length = max(sqrt(dx * dx + dy * dy), 1e-6)
      px = ox + dx / length * r
      py = oy + dy / length * r
    }
    return SIMD2(px, py)
  }

  private static func smooth(_ a: Float, _ b: Float, _ v: Float) -> Float {
    let t = min(1, max(0, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)
  }

  /// The fold's centre line in its own 3D space, t in 0...1.
  static func foldCentre(_ t: Float) -> SIMD3<Float> {
    SIMD3(-10.5 + 21 * t, -6.15 + 3.0 * smooth(0.4, 1.0, t) + 0.6 * sin(.pi * t * 1.4), -1.2 + 1.6 * sin(.pi * t))
  }

  /// A point on the brand fold, a ribbon that sweeps and flips once, shaded like the fold artwork; its colour is
  /// one of the artwork's mustards.
  static func foldPoint(_ random: inout SeededRandom, widthScale: Float) -> (point: SIMD3<Float>, color: SIMD3<Float>) {
    let t = random.next()
    let across: Float = random.next() < 0.22
      ? (random.next() < 0.5 ? -1 : 1) * (0.92 + random.next() * 0.08) : random.next() * 2 - 1
    func centre(_ u: Float) -> SIMD3<Float> { foldCentre(min(1, max(0, u))) }
    let c = centre(t)
    let tangent = simd_normalize(centre(t + 0.002) - centre(t - 0.002))
    var d = SIMD3<Float>(-tangent.z, 0, tangent.x)
    let dl = simd_length(d)
    d = dl > 0 ? d / dl : SIMD3(1, 0, 0)
    let up = simd_cross(d, tangent)
    let theta = Float.pi * smooth(0.4, 0.8, t)
    let w = up * cos(theta) + d * sin(theta)
    let width = across * (1.25 + 0.6 * t) * widthScale
    let point = c + w * width
    let facing = tangent.x * w.y - tangent.y * w.x
    let mustard = ParticleColors.mustard, highlight = ParticleColors.highlight
    let shade = ParticleColors.shade, fold = ParticleColors.fold
    let color: SIMD3<Float> = facing < -0.05
      ? simd_mix(fold, shade, SIMD3(repeating: 0.25 * (1 - abs(across))))
      : simd_mix(simd_mix(shade, mustard, SIMD3(repeating: 0.55 + 0.45 * facing)), highlight,
                 SIMD3(repeating: max(0, abs(across) - 0.82) * 4))
    return (point, color)
  }

  /// Perspective projection of the fold onto the window: (x, y, scale).
  static func project(_ p: SIMD3<Float>, cx: Float, cy: Float, scale: Float, camera: Float = 20) -> SIMD3<Float> {
    let f = camera / (camera - p.z)
    return SIMD3(cx + p.x * scale * f, cy - p.y * scale * f, f)
  }
}

/// Brand colours as linear-free sRGB components (the website draws them the same way).
enum ParticleColors {
  static func rgb(_ hex: UInt32) -> SIMD3<Float> {
    SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
  }

  static let mustard = rgb(0xE9B520)
  static let highlight = rgb(0xF3CA3D)
  static let shade = rgb(0xDCA319)
  static let fold = rgb(0xA96E12)
  static let porcelain = rgb(0xFAF9F5)
  static let graphite = rgb(0x202321)
}
