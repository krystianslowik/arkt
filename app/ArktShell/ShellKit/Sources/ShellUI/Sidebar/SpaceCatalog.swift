import Foundation

/// SF Symbols offered for a Space icon (BH-034). "None" clears it; the dock draws a dot.
enum SpaceIconCatalog {
  struct Choice: Equatable, Sendable {
    var title: String
    var symbol: String?
  }

  static let choices: [Choice] = [
    Choice(title: "None", symbol: nil),
    Choice(title: "Star", symbol: "star"),
    Choice(title: "Bookmark", symbol: "bookmark"),
    Choice(title: "Folder", symbol: "folder"),
    Choice(title: "Heart", symbol: "heart"),
    Choice(title: "Bolt", symbol: "bolt"),
    Choice(title: "Book", symbol: "book"),
    Choice(title: "Globe", symbol: "globe"),
    Choice(title: "Person", symbol: "person"),
  ]
}

/// Themes offered on the Space header (BH-034). "Default" clears the Space's own theme, so it draws the source's
/// default (D2 on #279). The others have no texture and sRGB colors: storing one and reading it back compares equal,
/// because the bridge does not keep `noiseFactor` and reads components as sRGB.
public enum SpaceThemeCatalog {
  struct Choice: Equatable, Sendable {
    var title: String
    /// Nil is "Default".
    var theme: SpaceThemeInfo?
  }

  /// A theme family of the first run (onboarding spec, section 5): a two-stop gradient from top left to bottom
  /// right in a light and a dark version.
  public struct Family: Equatable, Sendable {
    public var title: String
    public var light: SpaceThemeInfo
    public var dark: SpaceThemeInfo

    init(_ title: String, light: [UInt32], dark: [UInt32]) {
      self.title = title
      self.light = SpaceThemeInfo(baseColors: light.map { RGBA.srgb(hex: $0) }, isDark: false)
      self.dark = SpaceThemeInfo(baseColors: dark.map { RGBA.srgb(hex: $0) }, isDark: true)
    }

    public func theme(_ flavor: ThemeFlavor) -> SpaceThemeInfo { flavor == .light ? light : dark }
  }

  /// The six families, Dune first. Every stop is measured by `ShellTokensContrastTests`.
  public static let families: [Family] = [
    Family("Dune", light: [0xF7EED2, 0xEBD592], dark: [0x3D3420, 0x1E1A10]),
    Family("Mist", light: [0xE0F2FB, 0xC5C6E2], dark: [0x3A4158, 0x1C2030]),
    Family("Paper", light: [0xF4F1EA, 0xE4DDD2], dark: [0x3A3631, 0x211F1C]),
    Family("Sage", light: [0xE6EDE3, 0xC4D3C0], dark: [0x2F3B33, 0x171E1A]),
    Family("Blossom", light: [0xF2EAE4, 0xF29BBB], dark: [0x4A2A3A, 0x1F1520]),
    Family("Indigo", light: [0xE4E2F4, 0xC9C3E8], dark: [0x2D4468, 0x120F2E]),
  ]

  /// Dune: the theme of the Space the first run creates (decision 5).
  public static var defaultFamily: Family { families[0] }

  /// The header menu's "Paper": Paper's light stops.
  static let paper = families[2].light
  /// The header menu's "Dusk": Mist's dark stops.
  static let dusk = families[1].dark

  static let choices: [Choice] = [
    Choice(title: "Default", theme: nil),
    Choice(title: "Paper", theme: paper),
    Choice(title: "Dusk", theme: dusk),
  ]

  /// "Default" is current while the Space has no theme of its own; a theme only when it is the Space's own (a Space
  /// whose own theme happens to equal the default is not on "Default").
  static func isCurrent(_ choice: Choice, for info: SidebarSpaceInfo?) -> Bool {
    guard let info else { return false }
    guard let theme = choice.theme else { return info.usesDefaultTheme }
    return !info.usesDefaultTheme && info.theme == theme
  }
}
