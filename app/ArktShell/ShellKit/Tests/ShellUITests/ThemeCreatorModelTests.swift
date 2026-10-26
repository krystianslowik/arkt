import CoreGraphics
import Testing
@testable import ShellUI

/// The creator's state: one or two dots on the pad, texture, amount and opacity, and the theme they write.
struct ThemeCreatorModelTests {
  static let blue = ThemePadPoint(hue: 216, tone: 0.74)
  static let copper = ThemePadPoint(hue: 27, tone: 0.34)

  static func padTheme(_ points: [ThemePadPoint], texture: String? = "sand", noiseFactor: Double = 0.4,
                       opacity: Double = 0.8) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: points.map(ThemePad.color), texture: texture, noiseFactor: noiseFactor,
                   opacity: opacity, isDark: true)
  }

  @Test func opensWithTheDotsOfAPadTheme() {
    let model = ThemeCreatorModel(theme: Self.padTheme([Self.blue, Self.copper]), isNew: false)
    #expect(model.dots.count == 2)
    #expect(abs(model.dots[0].point.hue - 216) < 0.5 && abs(model.dots[1].point.tone - 0.34) < 0.002)
    #expect(model.theme == Self.padTheme([Self.blue, Self.copper]))
  }

  /// A theme with colours off the pad opens with the dots at the nearest pad point and stays unchanged until a dot
  /// moves; with more than two colours the dots show the first and last.
  @Test func foreignColoursStayUntilADotMoves() {
    let foreign = SpaceThemeInfo(baseColors: [.white(1), .srgb(hex: 0x336699), .srgb(hex: 0xF29BBB)], isDark: false)
    var model = ThemeCreatorModel(theme: foreign, isNew: false)
    #expect(model.dots.count == 2)
    #expect(model.theme == foreign)
    model.setOpacity(0.5)
    #expect(model.theme.baseColors == foreign.baseColors && model.theme.opacity == 0.5)
    model.moveDot(1, to: Self.copper)
    #expect(model.theme.baseColors == [.white(1), ThemePad.color(Self.copper)])
  }

  /// A Space without a theme of its own starts from the given colours at the nearest pad points, at 80 %.
  @Test func aNewThemeStartsAtEightyPercent() {
    let model = ThemeCreatorModel(theme: SpaceThemeInfo(baseColors: [.srgb(hex: 0xF2F0EE)], isDark: false), isNew: true)
    #expect(model.theme.opacity == 0.8)
    #expect(model.theme.baseColors == model.dots.map { ThemePad.color($0.point) })
    #expect(ThemeCreatorModel.newThemeOpacity == 0.8)
  }

  @Test func movingADotClampsItToTheReachableBand() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    model.moveDot(0, to: ThemePadPoint(hue: 400, tone: 1.2))
    #expect(model.dots[0].point == ThemePadPoint(hue: 360, tone: ThemePad.maximumTone))
    #expect(model.theme.baseColors == [ThemePad.color(model.dots[0].point)])
  }

  @Test func theButtonAddsTheSecondColourAndRemovesIt() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    let added = model.addSecondColour(at: nil)
    #expect(added)
    #expect(model.dots.count == 2)
    #expect(model.dots[1].point == ThemePad.secondPoint(from: model.dots[0].point))
    #expect(model.theme.baseColors.count == 2)
    let addedAgain = model.addSecondColour(at: nil)
    #expect(!addedAgain)
    let removed = model.removeDot(1)
    #expect(removed)
    #expect(model.dots.count == 1 && model.theme.baseColors.count == 1)
    let removedLast = model.removeDot(0)
    #expect(!removedLast)
  }

  @Test func aDoubleClickAddsTheSecondColourWhereItLands() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    let added = model.addSecondColour(at: ThemePadPoint(hue: 90, tone: 0.01))
    #expect(added)
    #expect(model.dots[1].point == ThemePadPoint(hue: 90, tone: ThemePad.minimumTone))
  }

  /// Removing the first colour keeps the second as the only one.
  @Test func removingTheFirstDotKeepsTheSecond() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue, Self.copper]), isNew: false)
    let removed = model.removeDot(0)
    #expect(removed)
    #expect(model.theme.baseColors == [ThemePad.color(Self.copper)])
  }

  /// A dot dragged more than 24 pt off the pad is removed on release.
  @Test func dragOffThePadDistance() {
    let size = ThemePad.size
    #expect(!ThemeCreatorModel.isOffPad(CGPoint(x: -24, y: 10), padSize: size))
    #expect(ThemeCreatorModel.isOffPad(CGPoint(x: -24.5, y: 10), padSize: size))
    #expect(ThemeCreatorModel.isOffPad(CGPoint(x: 100, y: size.height + 25), padSize: size))
    #expect(!ThemeCreatorModel.isOffPad(CGPoint(x: 100, y: 100), padSize: size))
  }

  /// With None the amount keeps its value, so a texture chosen again draws at it.
  @Test func textureNoneKeepsTheAmount() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue], noiseFactor: 0.4), isNew: false)
    model.setTexture(nil)
    #expect(model.theme.texture == nil && model.theme.noiseFactor == 0.4)
    #expect(!model.isAmountEnabled)
    model.setTexture("tweed")
    #expect(model.theme.texture == "tweed" && model.theme.noiseFactor == 0.4 && model.isAmountEnabled)
  }

  @Test func slidersClampToTheirRange() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    model.setAmount(1.4)
    model.setOpacity(-0.2)
    #expect(model.theme.noiseFactor == 1 && model.theme.opacity == 0)
  }

  /// A preset picked while the creator is open moves the dots; the theme becomes the preset as given.
  @Test func anExternalThemeMovesTheDots() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    let preset = SpaceThemeCatalog.families[1].dark
    model.replace(with: preset)
    #expect(model.theme == preset)
    #expect(model.dots.count == 2)
    #expect(model.dots[0].point == ThemePad.nearestPoint(to: preset.baseColors[0]))
  }

  /// The stored tone flag follows the colours: light text reads better over deep colours.
  @Test func writtenThemeMarksDeepColoursDark() {
    var model = ThemeCreatorModel(theme: Self.padTheme([Self.blue]), isNew: false)
    model.moveDot(0, to: ThemePadPoint(hue: 216, tone: 0.9))
    #expect(model.theme.isDark)
    model.moveDot(0, to: ThemePadPoint(hue: 216, tone: 0.1))
    #expect(!model.theme.isDark)
  }
}
