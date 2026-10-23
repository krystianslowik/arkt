import AppKit

/// A color token value. Sendable and comparable so tokens can live in static tables and tests.
public struct RGBA: Sendable, Equatable {
  public enum Space: Sendable, Equatable { case sRGB, displayP3 }

  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double
  public var space: Space

  public init(red: Double, green: Double, blue: Double, alpha: Double, space: Space = .sRGB) {
    self.red = red; self.green = green; self.blue = blue; self.alpha = alpha; self.space = space
  }

  public static func white(_ alpha: Double) -> RGBA { RGBA(red: 1, green: 1, blue: 1, alpha: alpha) }
  public static func black(_ alpha: Double) -> RGBA { RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }

  /// Display P3 color from a 0xRRGGBB hex (P3 hex values are recreated as P3).
  public static func p3(hex: UInt32, alpha: Double) -> RGBA {
    RGBA(red: Double((hex >> 16) & 0xFF) / 255,
         green: Double((hex >> 8) & 0xFF) / 255,
         blue: Double(hex & 0xFF) / 255,
         alpha: alpha, space: .displayP3)
  }

  /// sRGB color from a 0xRRGGBB hex, the form brand colors are specified in.
  public static func srgb(hex: UInt32, alpha: Double = 1) -> RGBA {
    RGBA(red: Double((hex >> 16) & 0xFF) / 255,
         green: Double((hex >> 8) & 0xFF) / 255,
         blue: Double(hex & 0xFF) / 255,
         alpha: alpha)
  }

  /// sRGB color from a "#RRGGBB" string; nil when the string is not exactly that form.
  public static func srgb(hexString: String) -> RGBA? {
    let digits = hexString.dropFirst()
    guard hexString.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit),
          let hex = UInt32(digits, radix: 16) else { return nil }
    return srgb(hex: hex)
  }

  /// Linear blend from `a` (t = 0) to `b` (t = 1), per component; the result takes the nearer end's space.
  public static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
    let t = min(max(t, 0), 1)
    func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
    return RGBA(red: lerp(a.red, b.red), green: lerp(a.green, b.green), blue: lerp(a.blue, b.blue),
                alpha: lerp(a.alpha, b.alpha), space: t < 0.5 ? a.space : b.space)
  }

  public var cgColor: CGColor {
    let name = space == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB
    let colorSpace = CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
    let components = [red, green, blue, alpha].map { CGFloat($0) }
    return CGColor(colorSpace: colorSpace, components: components)
      ?? CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
  }

  public func nsColor() -> NSColor {
    switch space {
    case .sRGB:
      return NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    case .displayP3:
      return NSColor(displayP3Red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
  }
}
