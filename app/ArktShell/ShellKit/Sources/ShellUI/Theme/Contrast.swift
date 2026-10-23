import Foundation

/// WCAG 2.x relative luminance and contrast ratio.
///
/// Pure math on opaque sRGB colors: alpha is ignored and the components are read as sRGB, so use it for tokens
/// specified in sRGB (`BrandTokens`), not for the translucent Arc-parity levels in `ShellTokens`.
public enum Contrast {
  /// WCAG 2.x AA minimum for normal-size text (SC 1.4.3).
  public static let minimumText = 4.5
  /// WCAG 2.x minimum for UI components and focus indicators against adjacent colors (SC 1.4.11).
  public static let minimumNonText = 3.0

  /// Relative luminance, 0 (black) to 1 (white).
  public static func relativeLuminance(_ color: RGBA) -> Double {
    func linear(_ c: Double) -> Double {
      c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
  }

  /// Contrast ratio between two colors, 1 to 21; symmetric in its arguments.
  public static func ratio(_ a: RGBA, _ b: RGBA) -> Double {
    let la = relativeLuminance(a), lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }
}
