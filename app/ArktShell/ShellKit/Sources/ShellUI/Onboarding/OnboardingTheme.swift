import Foundation

/// Make it yours as a value (onboarding spec, section 6.3): the swatch row, the selected swatch, the appearance, the
/// Space name and its placeholder. The step keeps the value it opened with so Skip (and a confirmed Skip setup) can
/// restore it.
public struct OnboardingTheme: Equatable, Sendable {
  public static let maximumNameLength = 40

  public enum Swatch: Equatable, Sendable {
    /// One of `SpaceThemeCatalog.families`, by index.
    case family(Int)
    /// The Space's own gradient, kept as it is: "Imported" on the import path, "Current" on re-entry.
    case own(title: String, theme: SpaceThemeInfo)

    public var title: String {
      switch self {
      case .family(let index): SpaceThemeCatalog.families[index].title
      case .own(let title, _): title
      }
    }

    /// The swatch's colours in `flavor`.
    public func theme(_ flavor: ThemeFlavor) -> SpaceThemeInfo {
      switch self {
      case .family(let index): SpaceThemeCatalog.families[index].theme(flavor)
      case .own(_, let theme): theme
      }
    }

    public var isOwn: Bool {
      if case .own = self { return true }
      return false
    }
  }

  public private(set) var swatches: [Swatch]
  public private(set) var selected: Int
  public var appearance: ThemeFlavor
  /// What the user typed; at most `maximumNameLength` characters.
  public var name: String {
    didSet { if name.count > Self.maximumNameLength { name = String(name.prefix(Self.maximumNameLength)) } }
  }
  /// Shown while the name is empty, and used as the name then.
  public let placeholder: String

  private static let familySwatches = SpaceThemeCatalog.families.indices.map(Swatch.family)

  /// The fresh path: Dune selected, "Space 1", the system appearance.
  public static func fresh(appearance: ThemeFlavor, placeholder: String = "Space 1") -> OnboardingTheme {
    OnboardingTheme(swatches: familySwatches, selected: 0, appearance: appearance, placeholder: placeholder)
  }

  /// The import path: a seventh swatch, "Imported" (the imported Space's own gradient), comes first and is selected;
  /// the placeholder is that Space's name. Appearance starts at the system's, disabled while "Imported" is selected.
  public static func imported(theme: SpaceThemeInfo, name: String, appearance: ThemeFlavor) -> OnboardingTheme {
    OnboardingTheme(swatches: [.own(title: OnboardingCopy.importedSwatch, theme: theme)] + familySwatches,
                    selected: 0, appearance: appearance, placeholder: name)
  }

  /// Re-entry over an existing Space: its family is selected when its theme is one, else its own gradient leads as
  /// "Current".
  public static func current(theme: SpaceThemeInfo, name: String, appearance: ThemeFlavor) -> OnboardingTheme {
    for (index, family) in SpaceThemeCatalog.families.enumerated() {
      for flavor in [ThemeFlavor.light, .dark] where family.theme(flavor) == theme {
        return OnboardingTheme(swatches: familySwatches, selected: index, appearance: flavor, placeholder: name)
      }
    }
    return OnboardingTheme(swatches: [.own(title: OnboardingCopy.currentSwatch, theme: theme)] + familySwatches,
                           selected: 0, appearance: appearance, placeholder: name)
  }

  private init(swatches: [Swatch], selected: Int, appearance: ThemeFlavor, placeholder: String) {
    self.swatches = swatches
    self.selected = selected
    self.appearance = appearance
    self.name = ""
    self.placeholder = placeholder
  }

  public var selectedSwatch: Swatch { swatches[selected] }
  public var selectedTitle: String { selectedSwatch.title }
  /// Appearance applies to the families only; it is disabled while an own gradient is selected.
  public var isAppearanceEnabled: Bool { !selectedSwatch.isOwn }
  public var resolvedTheme: SpaceThemeInfo { selectedSwatch.theme(appearance) }
  public var resolvedName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? placeholder : trimmed
  }

  public mutating func select(_ index: Int) {
    guard swatches.indices.contains(index) else { return }
    selected = index
  }

  /// The swatches are a radio group: arrows move the selection and wrap.
  public mutating func moveSelection(by delta: Int) {
    let count = swatches.count
    selected = ((selected + delta) % count + count) % count
  }

  public mutating func restore(_ opened: OnboardingTheme) { self = opened }
}
