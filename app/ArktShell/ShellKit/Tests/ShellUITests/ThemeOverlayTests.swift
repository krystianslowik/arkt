import AppKit
import Testing
@testable import ShellUI

/// Each visible Space is represented by one opaque composite gradient, below the texture.
@MainActor
struct ThemeOverlayTests {
  private func theme(overlay: [RGBA] = []) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: [.p3(hex: 0xF2EAE4), .p3(hex: 0xF29BBB)], overlayColors: overlay, isDark: false)
  }

  private func view(_ themes: [SpaceThemeInfo]) -> ThemeBackgroundView {
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 120, height: 80), grainRenderer: nil)
    view.reducesMotion = { false }
    view.themes = themes
    view.setPosition(0)
    return view
  }

  private func gradients(_ view: ThemeBackgroundView) -> [CAGradientLayer] {
    (view.layer?.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
  }

  private func components(_ color: CGColor) -> [Double] { (color.components ?? []).map { Double($0) } }

  private func expectColor(_ color: CGColor, _ expected: RGBA) {
    let got = components(color)
    let want = [expected.red, expected.green, expected.blue, expected.alpha]
    #expect(got.count == 4)
    #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-6 })
  }

  @Test func shippedThemesKeepTheirExpandedStops() throws {
    let shipped = [SpaceThemeCatalog.paper, SpaceThemeCatalog.dusk]
      + SpaceThemeCatalog.families.flatMap { [$0.light, $0.dark] }
    for theme in shipped {
      let colors = try #require(gradients(view([theme, theme])).first?.colors as? [CGColor])
      let expanded = ThemeGradient.expand(theme.baseColors)
      #expect(colors.count == expanded.count)
      for (color, expected) in zip(colors, expanded) { expectColor(color, expected) }
    }
  }

  @Test func unequalStopsUseExplicitUnionLocationsInOneGradientPerSpace() throws {
    let a = SpaceThemeInfo(baseColors: [.p3(hex: 0x224466), .p3(hex: 0xAACCEE)],
                           overlayColors: [.p3(hex: 0xFF0000, alpha: 0.4), .p3(hex: 0x00FF00, alpha: 0.2),
                                           .p3(hex: 0x0000FF, alpha: 0.3), .p3(hex: 0xFFFFFF, alpha: 0.1)],
                           isDark: false)
    let view = view([a, theme()])
    let layers = gradients(view)
    #expect(layers.count == 2)
    let lower = try #require(layers.first)
    let colors = try #require(lower.colors as? [CGColor])
    let locations = try #require(lower.locations?.map(\.doubleValue))
    #expect(colors.count == locations.count)
    #expect(locations.contains { abs($0 - 1.0 / 3.0) < 1e-9 })
    #expect(locations.contains { abs($0 - 1.0 / 32.0) < 1e-9 })
    #expect(zip(locations, locations.dropFirst()).allSatisfy { $0 < $1 })
    let third = try #require(locations.firstIndex { abs($0 - 1.0 / 3.0) < 1e-9 })
    let expanded = ThemeGradient.expand(a.baseColors)
    let position = Double(expanded.count - 1) / 3
    let index = Int(position)
    let base = RGBA.mix(expanded[index], expanded[index + 1], position - Double(index))
    expectColor(colors[third], RGBA(red: base.red * 0.8, green: 0.2 + base.green * 0.8,
                                    blue: base.blue * 0.8, alpha: 1, space: .displayP3))
    #expect(colors[third].colorSpace?.name == CGColorSpace.displayP3)
  }

  @Test func emptyBaseStillDrawsOverlayOverWhiteAndSingleStopsAreFlat() throws {
    let empty = SpaceThemeInfo(baseColors: [], overlayColors: [.srgb(hex: 0xFF0000, alpha: 0.25)], isDark: false)
    let single = SpaceThemeInfo(baseColors: [.srgb(hex: 0x0000FF)],
                                overlayColors: [.srgb(hex: 0xFF0000, alpha: 0.5)], isDark: false)
    let view = view([empty, single])
    let layers = gradients(view)
    #expect(layers.count == 2)
    let lower = try #require(layers.first?.colors as? [CGColor])
    let upper = try #require(layers.last?.colors as? [CGColor])
    #expect(lower.count == 2 && upper.count == 2)
    for color in lower { expectColor(color, RGBA(red: 1, green: 0.75, blue: 0.75, alpha: 1)) }
    for color in upper { expectColor(color, RGBA(red: 0.5, green: 0, blue: 0.5, alpha: 1)) }
  }

  /// The counter counts completed expansions/composites, including both colors and locations, per drawn theme.
  /// It is a test-only cumulative observation, not a control for the cache.
  @Test func swipesReuseCachedStopsAndChangedDrawnThemesInvalidateThem() throws {
    let a = theme(overlay: [.p3(hex: 0x000000, alpha: 0.2)])
    let b = theme(overlay: [.p3(hex: 0xFFFFFF, alpha: 0.3)])
    let c = SpaceThemeCatalog.paper
    let view = view([a, b, c])
    for position: CGFloat in [0.25, 1.25, 2, 1.5, 0.5, 0] { view.setPosition(position) }
    let builds = view.compositeBuildCountForTesting
    for _ in 0..<3 {
      for position: CGFloat in [0.25, 0.5, 1.25, 2, 1.5, 0] { view.setPosition(position) }
    }
    #expect(view.compositeBuildCountForTesting == builds)
    view.setPosition(0.25)
    let layers = gradients(view)
    #expect(layers.count == 2)
    #expect(abs(layers[1].opacity - 0.25) < 1e-6)
    let oldColors = layers[0].colors as? [CGColor]
    let oldLocations = layers[0].locations
    view.previewTheme(theme(overlay: [.p3(hex: 0xFF0000, alpha: 0.6)]), at: 0)
    #expect(view.compositeBuildCountForTesting > builds)
    #expect(layers[0].colors as? [CGColor] != oldColors)
    #expect(layers[0].locations == oldLocations)
  }

  @Test func appearanceAndContrastChangesReplaceTheCachedDrawnTheme() throws {
    // Zero opacity makes appearance change the surface. Mid orange needs a stronger mix at 7:1.
    let surface = SpaceThemeInfo(baseColors: [.srgb(hex: 0x777777)], opacity: 0, isDark: false)
    let mid = ThemePad.color(ThemePadPoint(hue: 30, tone: 0.5))
    let orange = SpaceThemeInfo(baseColors: [mid], isDark: false)
    for (stored, from, to) in [
      (surface, ThemeContext(appearance: .light), ThemeContext(appearance: .dark)),
      (orange, ThemeContext(appearance: .light), ThemeContext(appearance: .light, increaseContrast: true)),
    ] {
      let stub = StubSidebar()
      let id = stub.addSpace(title: "A", theme: stored)
      let controller = SidebarController(source: stub)
      controller.themeContext = from
      let original = try #require(controller.drawnSpace(id)?.theme)
      let view = view([original])
      controller.themeContext = to
      let drawn = try #require(controller.drawnSpace(id)?.theme)
      #expect(drawn != original)
      let before = view.compositeBuildCountForTesting
      view.themes = [drawn]
      #expect(view.compositeBuildCountForTesting > before)
      let layer = try #require(gradients(view).first)
      let colors = try #require(layer.colors as? [CGColor])
      let expected = try #require(ThemeGradient.composite(base: drawn.baseColors, overlay: drawn.overlayColors).first)
      #expect(colors.count == 2)
      for color in colors { expectColor(color, expected.color) }
    }
  }

  @Test func compositeGradientsStayBelowTextureAndCrossfadeTogether() throws {
    var old = theme(overlay: [.p3(hex: 0x000000, alpha: 0.2)])
    old.texture = "grain"
    old.noiseFactor = 0.5
    let new = theme(overlay: [.p3(hex: 0xFFFFFF, alpha: 0.3)])
    let view = view([old, theme()])
    let layers = try #require(view.layer?.sublayers)
    let grain = try #require(view.grainLayerForTesting(.grain))
    let grainIndex = try #require(layers.firstIndex { $0 === grain })
    #expect(gradients(view).count == 2)
    for gradient in gradients(view) { #expect(try #require(layers.firstIndex { $0 === gradient }) < grainIndex) }
    var completion: (@MainActor () -> Void)?
    view.crossfadeCompletionDriver = { completion = $0 }
    let oldColors = view.baseColorsForTesting
    view.replaceThemes([new, theme()], crossfade: true)
    #expect(view.baseColorsForTesting == oldColors)
    let animation = try #require(view.crossfadeAnimationForTesting)
    #expect((animation.fromValue as? NSNumber)?.floatValue == 0 && (animation.toValue as? NSNumber)?.floatValue == 1)
    let upper = try #require(gradients(view).last?.colors as? [CGColor])
    #expect(upper != oldColors)
    try #require(completion)()
    #expect(view.crossfadeAnimationForTesting == nil)
    #expect(view.baseColorsForTesting == upper)
    view.reducesMotion = { true }
    view.replaceThemes([old, theme()], crossfade: true)
    #expect(view.crossfadeAnimationForTesting == nil)
    #expect(view.baseColorsForTesting == oldColors)
    view.previewTheme(new, at: 0)
    #expect(view.baseColorsForTesting == upper)
  }
}
