import AppKit

/// The look of the first run for one window: light or dark, and the three accessibility settings of section 9.
/// Resolves the brand tokens to colours, so every view asks one place.
public struct OnboardingAppearance: Equatable, Sendable {
  public var flavor: ThemeFlavor
  public var reduceMotion: Bool
  public var reduceTransparency: Bool
  public var increaseContrast: Bool

  public init(flavor: ThemeFlavor, reduceMotion: Bool = false, reduceTransparency: Bool = false,
              increaseContrast: Bool = false) {
    self.flavor = flavor
    self.reduceMotion = reduceMotion
    self.reduceTransparency = reduceTransparency
    self.increaseContrast = increaseContrast
  }

  /// The system's settings for `appearance`.
  @MainActor
  public static func current(for appearance: NSAppearance) -> OnboardingAppearance {
    let workspace = NSWorkspace.shared
    return OnboardingAppearance(flavor: ThemeFlavor(appearance: appearance),
                                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                                increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
  }

  public func color(_ token: TokenPair) -> NSColor { token.resolve(flavor).nsColor() }

  public var surface: NSColor { color(BrandTokens.surfaceBrand) }
  public var textPrimary: NSColor { color(BrandTokens.brandTextPrimary) }
  public var textSecondary: NSColor {
    color(increaseContrast ? BrandTokens.brandTextSecondaryContrast : BrandTokens.brandTextSecondary)
  }
  public var hairline: NSColor {
    color(increaseContrast ? BrandTokens.brandHairlineContrast : BrandTokens.brandHairline)
  }
  public var controlFill: NSColor { color(BrandTokens.brandControlFill) }
  public var controlFillPressed: NSColor { color(BrandTokens.brandControlFillPressed) }
  public var accent: NSColor { color(BrandTokens.accent) }
  public var accentHighlight: NSColor { color(BrandTokens.accentHighlight) }
  public var accentPressed: NSColor { color(BrandTokens.accentPressed) }
  public var onAccent: NSColor { color(BrandTokens.onAccent) }
  public var accentText: NSColor { color(BrandTokens.accentText) }
  public var focusRing: NSColor { color(BrandTokens.focusRing) }
  public var focusRingWidth: CGFloat { increaseContrast ? 3 : 2 }

  /// The glass secondary button: `surfaceBrand` at 55 % (opaque under Reduce Transparency).
  public var glassFill: NSColor { surface.withAlphaComponent(reduceTransparency ? 1 : 0.55) }
  public var glassFillHover: NSColor { surface.withAlphaComponent(reduceTransparency ? 1 : 0.85) }
  /// The glass button's edge: a 1 pt hairline, 1.5 pt in `brandTextSecondaryContrast` under Increase Contrast.
  public var glassEdge: NSColor {
    increaseContrast ? color(BrandTokens.brandTextSecondaryContrast) : color(BrandTokens.brandHairline)
  }
  public var glassEdgeWidth: CGFloat { increaseContrast ? 1.5 : 1 }

  /// The theme wash over the surface on Make it yours: 22 % light, 16 % dark, 12 % under Reduce Transparency.
  public var washOpacity: Float { reduceTransparency ? 0.12 : (flavor == .light ? 0.22 : 0.16) }

  /// The text halo (section 3): three shadows in the surface colour, 32, 12 and 2 pt blur at 95, 80 and 60 %.
  public var halo: [NSShadow] {
    [(32.0, 0.95), (12.0, 0.80), (2.0, 0.60)].map { blur, alpha in
      let shadow = NSShadow()
      shadow.shadowBlurRadius = blur
      shadow.shadowOffset = .zero
      shadow.shadowColor = surface.withAlphaComponent(alpha)
      return shadow
    }
  }
}
