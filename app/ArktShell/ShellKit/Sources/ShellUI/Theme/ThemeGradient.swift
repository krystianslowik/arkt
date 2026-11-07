import Foundation

/// OKLab interpolation for Space theme gradients (#381).
///
/// Core Animation interpolates a gradient's stops component-wise in the layer's color space, which muddies the
/// middle of a long or saturated gradient. `expand` walks every pair of stops in OKLab and writes the samples back
/// as stops, so the layer's own blend runs between points that are already perceptually spaced. The expansion is
/// CPU-side and happens once per theme (and per settled theme change), never per pager frame.
///
/// OKLab conversions use the D65 matrices from Björn Ottosson's definition, with the sRGB transfer curve that
/// Display P3 also uses. Components outside the stops' gamut are clamped to 0...1, the range a `CGColor` in that
/// space can show.
public enum ThemeGradient {
  /// Samples per pair of adjacent stops, matching the contrast probe so tests measure what the window draws.
  public static let segmentsPerPair = 32

  /// `a` at t = 0, `b` at t = 1, interpolated in OKLab with alpha linear. The result is in `a`'s color space;
  /// themes keep one space per theme, so mixed-space pairs are only a fallback.
  public static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
    let t = min(max(t, 0), 1)
    let from = oklab(a), to = oklab(b)
    let lab = OKLab(l: from.l + (to.l - from.l) * t,
                    a: from.a + (to.a - from.a) * t,
                    b: from.b + (to.b - from.b) * t)
    let alpha = a.alpha + (b.alpha - a.alpha) * t
    return rgba(lab, space: a.space, alpha: alpha)
  }

  /// Every pair of adjacent stops expanded into `segments` OKLab steps: `(count - 1) * segments + 1` stops. A single
  /// stop comes back as is (the caller duplicates it for a gradient layer); zero stops stay empty.
  public static func expand(_ colors: [RGBA], segments: Int = segmentsPerPair) -> [RGBA] {
    guard colors.count > 1, segments > 0 else { return colors }
    var out: [RGBA] = [colors[0]]
    out.reserveCapacity((colors.count - 1) * segments + 1)
    for pair in 0..<(colors.count - 1) {
      for step in 1...segments {
        out.append(mix(colors[pair], colors[pair + 1], Double(step) / Double(segments)))
      }
    }
    return out
  }

  /// The color of an evenly spaced gradient of `colors` at `position` (0...1): the OKLab mix of the two stops around
  /// it. A single color is flat; no colors is clear black. Matches what `expand` draws at the same position.
  public static func sample(_ colors: [RGBA], at position: Double) -> RGBA {
    guard let first = colors.first else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
    guard colors.count > 1 else { return first }
    let scaled = min(max(position, 0), 1) * Double(colors.count - 1)
    let index = min(Int(scaled), colors.count - 2)
    let fraction = scaled - Double(index)
    if fraction == 0 { return colors[index] }             // a stop is returned as given, with no round trip
    if fraction == 1 { return colors[index + 1] }
    return mix(colors[index], colors[index + 1], fraction)
  }

  // MARK: - OKLab

  /// A color in OKLab: perceptual lightness L (0 for black, 1 for white) and the a/b opponent axes.
  struct OKLab: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double
  }

  static func oklab(_ color: RGBA) -> OKLab {
    let xyz = Self.xyz(color)
    let l = 0.8189330101 * xyz.x + 0.3618667424 * xyz.y - 0.1288597137 * xyz.z
    let m = 0.0329845436 * xyz.x + 0.9293118715 * xyz.y + 0.0361456387 * xyz.z
    let s = 0.0482003018 * xyz.x + 0.2643662691 * xyz.y + 0.6338517070 * xyz.z
    let lRoot = cbrt(l), mRoot = cbrt(m), sRoot = cbrt(s)
    return OKLab(
      l: 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
      a: 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
      b: 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot)
  }

  static func rgba(_ lab: OKLab, space: RGBA.Space, alpha: Double) -> RGBA {
    let lRoot = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
    let mRoot = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
    let sRoot = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
    let l = lRoot * lRoot * lRoot
    let m = mRoot * mRoot * mRoot
    let s = sRoot * sRoot * sRoot
    let x = 1.2270138511 * l - 0.5577999807 * m + 0.2812561490 * s
    let y = -0.0405801784 * l + 1.1122568696 * m - 0.0716766787 * s
    let z = -0.0763812845 * l - 0.4214819784 * m + 1.5861632204 * s
    let linear: (r: Double, g: Double, b: Double)
    switch space {
    case .sRGB:
      linear = (3.2409699419 * x - 1.5373831776 * y - 0.4986107603 * z,
                -0.9692436363 * x + 1.8759675015 * y + 0.0415550574 * z,
                0.0556300797 * x - 0.2039769589 * y + 1.0569715142 * z)
    case .displayP3:
      linear = (2.4934969119 * x - 0.9313836179 * y - 0.4027107845 * z,
                -0.8294889696 * x + 1.7626640603 * y + 0.0236246858 * z,
                0.0358458302 * x - 0.0761723893 * y + 0.9568845240 * z)
    }
    return RGBA(red: encode(linear.r), green: encode(linear.g), blue: encode(linear.b),
                alpha: min(max(alpha, 0), 1), space: space)
  }

  private static func xyz(_ color: RGBA) -> (x: Double, y: Double, z: Double) {
    let r = decode(color.red), g = decode(color.green), b = decode(color.blue)
    switch color.space {
    case .sRGB:
      return (0.4123907993 * r + 0.3575843394 * g + 0.1804807884 * b,
              0.2126390059 * r + 0.7151686788 * g + 0.0721923154 * b,
              0.0193308187 * r + 0.1191947798 * g + 0.9505321522 * b)
    case .displayP3:
      return (0.4865709486 * r + 0.2656676932 * g + 0.1982172852 * b,
              0.2289745641 * r + 0.6917385218 * g + 0.0792869141 * b,
              0.0000000000 * r + 0.0451133819 * g + 1.0439443689 * b)
    }
  }

  /// The sRGB transfer curve (Display P3 shares it), odd-extended so out-of-gamut values round-trip.
  private static func decode(_ value: Double) -> Double {
    let x = abs(value)
    let y = x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    return value < 0 ? -y : y
  }

  private static func encode(_ value: Double) -> Double {
    let x = abs(value)
    let y = x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    return min(max(value < 0 ? -y : y, 0), 1)
  }
}
