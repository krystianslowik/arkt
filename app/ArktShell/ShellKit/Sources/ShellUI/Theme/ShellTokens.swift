import AppKit

public enum ThemeFlavor: Sendable {
  case light, dark

  /// `.darkAqua` (and its high-contrast/vibrant variants) map to `.dark`, everything else to `.light`.
  @MainActor
  public init(appearance: NSAppearance) {
    self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
}

public struct TokenPair: Sendable, Equatable {
  public let light: RGBA
  public let dark: RGBA
  public init(light: RGBA, dark: RGBA) { self.light = light; self.dark = dark }
  public func resolve(_ flavor: ThemeFlavor) -> RGBA { flavor == .light ? light : dark }
}

/// Arc's approach: chrome is black/white at low alpha over the Space theme.
/// Levels follow Arc's token levels; Arkt owns the values and may diverge.
public enum ShellTokens {
  public static let cardBorder = TokenPair(light: .black(0.10), dark: .white(0.20))       // FloatingScrimBorder
  public static let cardShadow = TokenPair(light: .black(0.20), dark: .black(0))           // Shadow
  public static let sidebarForeground = TokenPair(light: .black(0.30), dark: .white(0.45))
  public static let sidebarItemBackground = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.05), dark: .p3(hex: 0xFAFBFF, alpha: 0.10))
  public static let sidebarItemHovered = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.10), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  public static let primaryText = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.90), dark: .white(0.80))
  public static let secondaryText = TokenPair(light: .black(0.50), dark: .white(0.50))
  // Tab cell states (C3 tests these levels).
  public static let tabCurrent = TokenPair(light: .white(0.85), dark: .p3(hex: 0xFAFBFF, alpha: 0.20))
  public static let tabContentVisible = TokenPair(light: .white(0.70), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  public static let tabPrevious = TokenPair(light: .white(0.32), dark: .p3(hex: 0xFAFBFF, alpha: 0.08))
  public static let tabPreviousHovered = TokenPair(light: .white(0.50), dark: .p3(hex: 0xFAFBFF, alpha: 0.12))
  public static let tabPressed = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.065), dark: .p3(hex: 0xFAFBFF, alpha: 0.065))
  public static let tabCurrentShadow = TokenPair(light: .black(0.20), dark: .black(0))
  // Command bar (always dark surface, C5).
  public static let commandBarSurface = RGBA.p3(hex: 0x1C1C20, alpha: 0.98)                 // TODO(measure)
  public static let commandBarText = RGBA.white(0.80)
  public static let commandBarSecondaryText = RGBA.white(0.33)
  public static let commandBarDivider = RGBA.white(0.10)
  public static let commandBarSelectedRow = RGBA.white(0.10)                                // TODO(measure)
  public static let commandBarBorder = RGBA.white(0.10)
  // Toasts (E3a): dark text on a light fill over light themes, light text on a dark fill over dark ones.
  public static let toastSurface = TokenPair(light: .white(0.96), dark: .p3(hex: 0x1C1C20, alpha: 0.96))  // TODO(measure)
  public static let toastText = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.90), dark: .white(0.85))
  // Toolbar over the page (KB-018, BH-032): an opaque strip in the card, the card's hairline below it.
  public static let toolbarSurface = TokenPair(light: .white(1), dark: .p3(hex: 0x1C1C20, alpha: 1))    // TODO(measure)
  // Space theme background (C6).
  /// Texture layer opacity at noiseFactor 1. TODO(parity): match Arc's grain intensity.
  public static let themeTextureMaxOpacity = 0.16
  /// Grain tile edge in points (Arc's `grain` texture is 155 pt).
  public static let themeGrainTile: CGFloat = 155
}
