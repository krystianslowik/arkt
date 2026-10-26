import CoreGraphics
import Foundation

/// The theme creator's state (#410): one or two dots on the pad, and the theme they write.
///
/// A theme from elsewhere (a preset, an import, more than two colours) opens with each dot at the nearest pad point
/// and is written back unchanged until a dot moves: an unmoved dot keeps the colour it came from. With more than two
/// colours the dots show the first and last, and moving either writes a two-colour theme.
public struct ThemeCreatorModel: Equatable, Sendable {
  public struct Dot: Equatable, Sendable {
    public var point: ThemePadPoint
    /// The colour the dot writes: its pad colour once it moved, the theme's own colour before.
    public var color: RGBA
  }

  /// Opacity of a theme made for a Space that had none of its own.
  public static let newThemeOpacity = 0.8
  /// How far outside the pad a dragged dot must be let go to be removed.
  public static let removeDistance: CGFloat = 24

  public private(set) var dots: [Dot]
  /// The theme to store: what the window shows while the creator is open.
  public private(set) var theme: SpaceThemeInfo

  /// The amount slider works only with a texture; with None it keeps its value.
  public var isAmountEnabled: Bool { theme.texture != nil }

  /// `isNew`: the Space draws the default theme. The creator then starts from `theme`'s colours placed on the pad,
  /// at `newThemeOpacity`.
  public init(theme: SpaceThemeInfo, isNew: Bool) {
    let colors = theme.baseColors.isEmpty ? [ThemeContrast.porcelain] : theme.baseColors
    let shown = colors.count > 2 ? [colors[0], colors[colors.count - 1]] : colors
    dots = shown.map { Dot(point: ThemePad.nearestPoint(to: $0), color: $0) }
    self.theme = theme
    if isNew || theme.baseColors.isEmpty {
      dots = dots.map { Dot(point: $0.point, color: ThemePad.color($0.point)) }
      self.theme.opacity = Self.newThemeOpacity
      writeColors()
    }
  }

  // MARK: - Colours

  public mutating func moveDot(_ index: Int, to point: ThemePadPoint) {
    guard dots.indices.contains(index) else { return }
    let clamped = ThemePad.clamped(point)
    dots[index] = Dot(point: clamped, color: ThemePad.color(clamped))
    writeColors()
  }

  /// Adds the second colour at `point`, or (nil, from the button) 40 degrees from the first and a quarter of the pad
  /// toward the middle. False when there are two already.
  @discardableResult
  public mutating func addSecondColour(at point: ThemePadPoint?) -> Bool {
    guard dots.count == 1 else { return false }
    let spot = ThemePad.clamped(point ?? ThemePad.secondPoint(from: dots[0].point))
    dots.append(Dot(point: spot, color: ThemePad.color(spot)))
    writeColors()
    return true
  }

  /// Removes a colour. The last one cannot be removed.
  @discardableResult
  public mutating func removeDot(_ index: Int) -> Bool {
    guard dots.count > 1, dots.indices.contains(index) else { return false }
    dots.remove(at: index)
    writeColors()
    return true
  }

  /// Whether a dot let go at `location` (pad coordinates, top-left origin) is far enough off the pad to be removed.
  public static func isOffPad(_ location: CGPoint, padSize: CGSize) -> Bool {
    location.x < -removeDistance || location.x > padSize.width + removeDistance
      || location.y < -removeDistance || location.y > padSize.height + removeDistance
  }

  // MARK: - Texture and opacity

  /// A texture name (`ThemeTexture`), or nil for None. The amount is kept either way.
  public mutating func setTexture(_ name: String?) { theme.texture = name }

  public mutating func setAmount(_ amount: Double) { theme.noiseFactor = min(max(amount, 0), 1) }

  public mutating func setOpacity(_ opacity: Double) { theme.opacity = min(max(opacity, 0), 1) }

  /// A theme set from elsewhere while the creator is open (a preset): the dots move to its colours.
  public mutating func replace(with theme: SpaceThemeInfo) {
    self = ThemeCreatorModel(theme: theme, isNew: false)
  }

  // MARK: - Writing

  private mutating func writeColors() {
    theme.baseColors = dots.map(\.color)
    theme.isDark = Self.prefersLightText(theme.baseColors)
  }

  /// The stored tone flag: true when light text reads better than dark text over the colours (worst case of each).
  /// What the window draws comes from `ThemeContrast`, which starts from the appearance; this only keeps `isDark`
  /// meaningful for callers that read it directly.
  static func prefersLightText(_ colors: [RGBA]) -> Bool {
    func worst(_ tone: ThemeFlavor) -> Double {
      let text = ShellTokens.primaryText.resolve(tone)
      return colors.map { Contrast.ratio(BrandTokens.composite(text, over: $0), $0) }.min() ?? 0
    }
    return worst(.dark) > worst(.light)
  }
}
