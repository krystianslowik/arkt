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
enum SpaceThemeCatalog {
  struct Choice: Equatable, Sendable {
    var title: String
    /// Nil is "Default".
    var theme: SpaceThemeInfo?
  }

  /// TODO(design): placeholder colors, not from a design or from Arc (like `bridgeDefault`).
  static let paper = SpaceThemeInfo(
    baseColors: [.srgb(hex: 0xF4F1EA), .srgb(hex: 0xE4DDD2)], isDark: false)
  /// TODO(design): placeholder colors, not from a design or from Arc (like `bridgeDefault`).
  static let dusk = SpaceThemeInfo(
    baseColors: [.srgb(hex: 0x3A4158), .srgb(hex: 0x1C2030)], isDark: true)

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
