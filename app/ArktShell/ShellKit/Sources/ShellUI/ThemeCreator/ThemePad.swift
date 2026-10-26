import CoreGraphics
import Foundation

/// A point on the theme creator's colour pad: `hue` in degrees (0...360, left to right) and `tone` (0 at the top,
/// 1 at the bottom).
public struct ThemePadPoint: Equatable, Sendable {
  public var hue: Double
  public var tone: Double

  public init(hue: Double, tone: Double) {
    self.hue = hue
    self.tone = tone
  }
}

/// The colour pad's mapping (#410, design/theme-creator/README.md, "Colour pad").
///
/// Horizontal is hue. Vertical is tone: the middle band is the hue at HSL 60 %, 52 %; above it the colour blends
/// toward porcelain, below it toward near-black #121214. The pad draws exactly `color(_:)`, so a dot shows the colour
/// it stores. The top and bottom 6 % cannot be reached.
public enum ThemePad {
  /// The pad in points.
  public static let size = CGSize(width: 272, height: 212)
  public static let minimumTone = 0.06
  public static let maximumTone = 0.94
  /// The middle band's saturation and lightness (HSL).
  static let saturation = 0.60
  static let lightness = 0.52
  /// How far from a colour's own HSL hue `nearestPoint(to:)` looks: the pad's ends drift a few degrees in HSL hue
  /// (warm porcelain, cool near-black).
  static let nearestHueWindow = 15.0

  public enum Arrow: Sendable { case left, right, up, down }

  // MARK: - Mapping

  /// The colour at `point`, opaque sRGB.
  public static func color(_ point: ThemePadPoint) -> RGBA {
    let middle = hsl(hue: wrapped(point.hue), saturation: saturation, lightness: lightness)
    let tone = min(max(point.tone, 0), 1)
    if tone <= 0.5 { return RGBA.mix(ThemeContrast.porcelain, middle, tone / 0.5) }
    return RGBA.mix(middle, ThemeContrast.nearBlack, (tone - 0.5) / 0.5)
  }

  /// The point under `location` (top-left origin, in `size`), clamped to the pad and its reachable band.
  public static func point(at location: CGPoint, in size: CGSize) -> ThemePadPoint {
    let x = min(max(location.x / max(size.width, 1), 0), 1)
    let y = Double(location.y / max(size.height, 1))
    return ThemePadPoint(hue: Double(x) * 360, tone: clampedTone(y))
  }

  /// Where `point` sits in a pad of `size` (top-left origin).
  public static func location(of point: ThemePadPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: point.hue / 360 * size.width, y: point.tone * size.height)
  }

  public static func clampedTone(_ tone: Double) -> Double { min(max(tone, minimumTone), maximumTone) }

  /// `point` with its hue in 0...360 and its tone in the reachable band.
  public static func clamped(_ point: ThemePadPoint) -> ThemePadPoint {
    ThemePadPoint(hue: min(max(point.hue, 0), 360), tone: clampedTone(point.tone))
  }

  // MARK: - Colours from elsewhere

  /// The pad point closest to `color`: its hue (refined within a few degrees, since the pad's ends drift in HSL hue)
  /// and the closest tone in the reachable band. A pad colour finds its own point.
  public static func nearestPoint(to color: RGBA) -> ThemePadPoint {
    let center = hue(of: color)
    var best = ThemePadPoint(hue: center, tone: nearestTone(to: color, hue: center))
    var bestDistance = distance(self.color(best), color)
    var hueStep = 2.0, toneStep = 0.004
    while hueStep > 1e-4 || toneStep > 1e-7 {
      var improved = false
      let candidates = [
        ThemePadPoint(hue: best.hue - hueStep, tone: best.tone),
        ThemePadPoint(hue: best.hue + hueStep, tone: best.tone),
        ThemePadPoint(hue: best.hue, tone: best.tone - toneStep),
        ThemePadPoint(hue: best.hue, tone: best.tone + toneStep),
      ]
      for candidate in candidates where abs(candidate.hue - center) <= nearestHueWindow {
        let point = ThemePadPoint(hue: candidate.hue, tone: clampedTone(candidate.tone))
        let d = distance(self.color(point), color)
        if d < bestDistance - 1e-15 {
          best = point
          bestDistance = d
          improved = true
        }
      }
      if !improved {
        hueStep /= 2
        toneStep /= 2
      }
    }
    return ThemePadPoint(hue: wrapped(best.hue), tone: best.tone)
  }

  /// The reachable tone at `hue` whose colour is closest to `color`, to 0.001.
  public static func nearestTone(to color: RGBA, hue: Double) -> Double {
    let steps = Int(((maximumTone - minimumTone) * 1000).rounded())
    var bestTone = minimumTone
    var bestDistance = Double.infinity
    for step in 0...steps {
      let tone = minimumTone + Double(step) / 1000
      let d = distance(self.color(ThemePadPoint(hue: hue, tone: tone)), color)
      if d < bestDistance {
        bestDistance = d
        bestTone = tone
      }
    }
    return bestTone
  }

  /// Squared distance between two colours' components.
  public static func distance(_ a: RGBA, _ b: RGBA) -> Double {
    let r = a.red - b.red, g = a.green - b.green, bl = a.blue - b.blue
    return r * r + g * g + bl * bl
  }

  /// HSL hue in degrees, 0..<360; 0 for a grey.
  public static func hue(of color: RGBA) -> Double {
    let r = color.red, g = color.green, b = color.blue
    let high = max(r, g, b), low = min(r, g, b), delta = high - low
    guard delta > 1e-12 else { return 0 }
    let sector: Double
    if high == r {
      sector = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    } else if high == g {
      sector = (b - r) / delta + 2
    } else {
      sector = (r - g) / delta + 4
    }
    return wrapped(sector * 60)
  }

  // MARK: - Editing

  /// The second colour added from the button: 40 degrees of hue away and a quarter of the pad toward the middle.
  public static func secondPoint(from first: ThemePadPoint) -> ThemePadPoint {
    let towardMiddle = first.tone < 0.5 ? 0.25 : -0.25
    return ThemePadPoint(hue: wrapped(first.hue + 40), tone: clampedTone(first.tone + towardMiddle))
  }

  /// A keyboard step: Left and Right change hue by 2 degrees (10 with `large`), wrapping; Up and Down change tone
  /// by 2 % (10 %), Up lighter.
  public static func step(_ point: ThemePadPoint, _ arrow: Arrow, large: Bool) -> ThemePadPoint {
    let hueStep = large ? 10.0 : 2.0, toneStep = large ? 0.10 : 0.02
    switch arrow {
    case .left: return ThemePadPoint(hue: wrapped(point.hue - hueStep), tone: point.tone)
    case .right: return ThemePadPoint(hue: wrapped(point.hue + hueStep), tone: point.tone)
    case .up: return ThemePadPoint(hue: point.hue, tone: clampedTone(point.tone - toneStep))
    case .down: return ThemePadPoint(hue: point.hue, tone: clampedTone(point.tone + toneStep))
    }
  }

  // MARK: - Accessibility

  /// A plain colour name and tone, such as "blue, light 26 percent".
  public static func accessibilityValue(_ point: ThemePadPoint) -> String {
    "\(colorName(hue: point.hue)), light \(Int(((1 - point.tone) * 100).rounded())) percent"
  }

  /// A plain name for a hue.
  public static func colorName(hue: Double) -> String {
    switch wrapped(hue) {
    case ..<15: "red"
    case ..<45: "orange"
    case ..<70: "yellow"
    case ..<165: "green"
    case ..<195: "teal"
    case ..<255: "blue"
    case ..<285: "purple"
    case ..<345: "pink"
    default: "red"
    }
  }

  // MARK: - Helpers

  static func wrapped(_ hue: Double) -> Double {
    let value = hue.truncatingRemainder(dividingBy: 360)
    return value < 0 ? value + 360 : value
  }

  /// HSL to sRGB (CSS Color 4).
  static func hsl(hue: Double, saturation s: Double, lightness l: Double) -> RGBA {
    let a = s * min(l, 1 - l)
    func channel(_ n: Double) -> Double {
      let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
      return l - a * max(-1, min(k - 3, 9 - k, 1))
    }
    return RGBA(red: channel(0), green: channel(8), blue: channel(4), alpha: 1)
  }
}
