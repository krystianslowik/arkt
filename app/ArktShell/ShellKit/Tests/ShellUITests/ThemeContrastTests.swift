import Testing
@testable import ShellUI

/// The automatic contrast rule (design/theme-creator/README.md, "Automatic contrast"), as a pure function.
struct ThemeContrastTests {
  static let light = ThemeContext(appearance: .light)
  static let dark = ThemeContext(appearance: .dark)

  /// The contrast of `primaryText` in `tone` over `color`, as the rule measures it.
  static func ratio(_ color: RGBA, tone: ThemeFlavor) -> Double {
    let text = ShellTokens.primaryText.resolve(tone)
    return Contrast.ratio(BrandTokens.composite(text, over: color), color)
  }

  /// The stored colours of the design's screenshots: a deep blue and a copper, from the pad.
  static let blue = ThemePad.color(ThemePadPoint(hue: 216, tone: 0.74))
  static let copper = ThemePad.color(ThemePadPoint(hue: 27, tone: 0.34))

  @Test func everyPresetDrawsUnchangedInBothAppearances() {
    for family in SpaceThemeCatalog.families {
      for theme in [family.light, family.dark] {
        for context in [Self.light, Self.dark] {
          let drawn = ThemeContrast.drawn(theme, in: context)
          #expect(drawn.baseColors == theme.baseColors, "\(family.title) in \(context.appearance)")
          #expect(drawn.flavor == theme.flavor, "\(family.title) in \(context.appearance)")
        }
      }
    }
  }

  @Test func theHeaderMenuPresetsDrawUnchanged() {
    for theme in [SpaceThemeCatalog.paper, SpaceThemeCatalog.dusk] {
      for context in [Self.light, Self.dark] {
        #expect(ThemeContrast.drawn(theme, in: context) == theme)
      }
    }
  }

  /// A pale theme in dark mode keeps its colours and takes dark text: light text would need more than 50 %.
  @Test func paleThemeInDarkModeFlipsToDarkText() throws {
    let pale = ThemePad.color(ThemePadPoint(hue: 200, tone: 0.1))
    let resolution = try #require(ThemeContrast.resolve(stops: [pale], opacity: 1, in: Self.dark))
    #expect(resolution.tone == .light)
    #expect(resolution.mixes == [0])
    #expect(resolution.colors == [pale])
  }

  /// A deep theme in light mode keeps its colours and takes light text.
  @Test func deepThemeInLightModeFlipsToLightText() throws {
    let deep = ThemePad.color(ThemePadPoint(hue: 250, tone: 0.9))
    let resolution = try #require(ThemeContrast.resolve(stops: [deep], opacity: 1, in: Self.light))
    #expect(resolution.tone == .dark)
    #expect(resolution.mixes == [0])
  }

  /// The design's example: in dark mode the copper is drawn darker so light titles stay readable; in light mode the
  /// blue is drawn lighter so dark titles stay readable. Each mix is the smallest 1 % step that passes.
  @Test(arguments: [ThemeFlavor.light, .dark])
  func blueAndCopperMixOnlyTheStopThatNeedsIt(appearance: ThemeFlavor) throws {
    let context = ThemeContext(appearance: appearance)
    let resolution = try #require(ThemeContrast.resolve(stops: [Self.blue, Self.copper], opacity: 0.8, in: context))
    #expect(resolution.tone == appearance)
    let adjusted = appearance == .dark ? 1 : 0
    #expect(resolution.mixes[1 - adjusted] == 0)
    let mix = resolution.mixes[adjusted]
    #expect(mix > 0 && mix <= ThemeContrast.maximumMix)
    for color in resolution.colors {
      #expect(Self.ratio(color, tone: appearance) >= Contrast.minimumText)
      #expect(color.alpha == 1)
    }
    // One step less does not pass.
    let stop = [Self.blue, Self.copper][adjusted]
    let less = ThemeContrast.composite(stop, mix: mix - 0.01, tone: appearance, opacity: 0.8, in: context)
    #expect(Self.ratio(less, tone: appearance) < Contrast.minimumText)
  }

  /// Light text mixes toward near-black (the copper darkens in dark mode); dark text toward porcelain (the blue
  /// lightens in light mode).
  @Test func mixingGoesTowardNearBlackForLightTextAndPorcelainForDarkText() throws {
    let inDark = try #require(ThemeContrast.resolve(stops: [Self.blue, Self.copper], opacity: 0.8, in: Self.dark))
    let copperAsIs = ThemeContrast.composite(Self.copper, mix: 0, tone: .dark, opacity: 0.8, in: Self.dark)
    #expect(Contrast.relativeLuminance(inDark.colors[1]) < Contrast.relativeLuminance(copperAsIs))
    let inLight = try #require(ThemeContrast.resolve(stops: [Self.blue, Self.copper], opacity: 0.8, in: Self.light))
    let blueAsIs = ThemeContrast.composite(Self.blue, mix: 0, tone: .light, opacity: 0.8, in: Self.light)
    #expect(Contrast.relativeLuminance(inLight.colors[0]) > Contrast.relativeLuminance(blueAsIs))
  }

  /// Increase Contrast raises the target to 7:1.
  @Test func increaseContrastTargetsSevenToOne() throws {
    #expect(ThemeContrast.target(increaseContrast: false) == 4.5)
    #expect(ThemeContrast.target(increaseContrast: true) == 7)
    let context = ThemeContext(appearance: .light, increaseContrast: true)
    // A mid orange: dark text reads on it at 4.5:1 as it is, 7:1 needs it lighter.
    let mid = ThemePad.color(ThemePadPoint(hue: 30, tone: 0.5))
    let plain = try #require(ThemeContrast.resolve(stops: [mid], opacity: 1, in: Self.light))
    let strong = try #require(ThemeContrast.resolve(stops: [mid], opacity: 1, in: context))
    #expect(Self.ratio(plain.colors[0], tone: plain.tone) >= 4.5)
    #expect(Self.ratio(strong.colors[0], tone: strong.tone) >= 7)
    #expect(plain.mixes == [0])
    #expect(strong.mixes[0] > 0 && strong.tone == .light)
  }

  /// Opacity composites the colour over the window surface: at 0 the window draws its plain surface.
  @Test func opacityZeroDrawsTheWindowSurface() throws {
    for context in [Self.light, Self.dark] {
      let resolution = try #require(ThemeContrast.resolve(stops: [Self.copper], opacity: 0, in: context))
      #expect(resolution.colors == [ThemeContrast.surface(context.appearance)])
      #expect(resolution.tone == context.appearance)
    }
  }

  /// The drawn theme carries the resolved colours and tone and an opacity of 1; the stored theme is not touched.
  @Test func drawnThemeKeepsTextureAndStrength() {
    let stored = SpaceThemeInfo(baseColors: [Self.blue, Self.copper], texture: "sand", noiseFactor: 0.4, opacity: 0.8,
                                isDark: false)
    let drawn = ThemeContrast.drawn(stored, in: Self.dark)
    #expect(drawn.texture == "sand" && drawn.noiseFactor == 0.4 && drawn.opacity == 1)
    #expect(drawn.isDark)
    #expect(drawn.baseColors != stored.baseColors)
    #expect(stored.baseColors == [Self.blue, Self.copper])
  }

  @Test func themeWithoutColoursDrawsAsStored() {
    let empty = SpaceThemeInfo(baseColors: [], isDark: true)
    #expect(ThemeContrast.drawn(empty, in: Self.light) == empty)
    #expect(ThemeContrast.resolve(stops: [], opacity: 1, in: Self.light) == nil)
  }

  // MARK: - Overlay colors (#381)

  private static let pale = ThemePad.color(ThemePadPoint(hue: 200, tone: 0.1))

  /// The overlay's strength is the theme's opacity: the drawn overlay carries its own alpha times that opacity, and
  /// the drawn theme is opaque like its base colors. The stored theme is not touched.
  @Test func theDrawnOverlayIsScaledByTheOpacity() {
    let stored = SpaceThemeInfo(baseColors: [Self.pale, Self.pale], overlayColors: [.black(0.4), RGBA.white(0.2)],
                                opacity: 0.5, isDark: false)
    let drawn = ThemeContrast.drawn(stored, in: Self.light)
    #expect(drawn.overlayColors.map(\.alpha) == [0.2, 0.1])
    #expect(drawn.opacity == 1)
    #expect(stored.overlayColors.map(\.alpha) == [0.4, 0.2])
  }

  @Test func aThemeAtZeroOpacityDrawsNoOverlay() {
    let stored = SpaceThemeInfo(baseColors: [Self.blue], overlayColors: [.black(0.6)], opacity: 0, isDark: false)
    #expect(ThemeContrast.drawn(stored, in: Self.dark).overlayColors.map(\.alpha) == [0])
  }

  /// Without overlay colors nothing about the result changes.
  @Test func noOverlayResolvesAsBefore() throws {
    for context in [Self.light, Self.dark] {
      let plain = try #require(ThemeContrast.resolve(stops: [Self.blue, Self.copper], opacity: 0.8, in: context))
      let empty = try #require(ThemeContrast.resolve(stops: [Self.blue, Self.copper], opacity: 0.8, overlay: [],
                                                     in: context))
      #expect(plain == empty)
      #expect(plain.overlay.isEmpty)
    }
  }

  /// A dark overlay over a pale base is what the text sits on: light text in light mode, where the base alone
  /// would keep dark text.
  @Test func theOverlayIsPartOfWhatTheTextSitsOn() throws {
    let alone = try #require(ThemeContrast.resolve(stops: [Self.pale, Self.pale], opacity: 1, in: Self.light))
    #expect(alone.tone == .light)
    let covered = try #require(ThemeContrast.resolve(stops: [Self.pale, Self.pale], opacity: 1,
                                                     overlay: [.black(0.9)], in: Self.light))
    #expect(covered.tone == .dark)
  }

  /// Wherever a base stop is drawn, base plus overlay reaches the target, with the mix being the smallest step.
  @Test(arguments: [ThemeFlavor.light, .dark])
  func baseAndOverlayTogetherReachTheTarget(appearance: ThemeFlavor) throws {
    let context = ThemeContext(appearance: appearance)
    let overlay = [RGBA.white(0.5), RGBA.black(0.3)]
    let stops = [Self.blue, Self.copper]
    let resolution = try #require(ThemeContrast.resolve(stops: stops, opacity: 0.8, overlay: overlay, in: context))
    #expect(abs(resolution.overlay[0].alpha - 0.4) < 1e-12 && abs(resolution.overlay[1].alpha - 0.24) < 1e-12)
    for (index, color) in resolution.colors.enumerated() {
      let top = ThemeGradient.sample(resolution.overlay, at: Double(index))
      let alpha = top.alpha
      let seen = RGBA(red: top.red * alpha + color.red * (1 - alpha), green: top.green * alpha + color.green * (1 - alpha),
                      blue: top.blue * alpha + color.blue * (1 - alpha), alpha: 1, space: color.space)
      #expect(Self.ratio(seen, tone: resolution.tone) >= ThemeContrast.target(increaseContrast: false) - 1e-9,
              "stop \(index) in \(appearance)")
    }
  }

  /// A sample of a gradient: the ends are exact, the middle is the perceptual mix, one color is flat.
  @Test func aGradientIsSampledByPosition() {
    let stops = [RGBA.white(1), RGBA.black(1), RGBA.srgb(hex: 0xFF0000)]
    #expect(ThemeGradient.sample(stops, at: 0) == stops[0])
    #expect(ThemeGradient.sample(stops, at: 1) == stops[2])
    #expect(ThemeGradient.sample(stops, at: 0.5) == stops[1])
    #expect(ThemeGradient.sample([stops[2]], at: 0.7) == stops[2])
    let quarter = ThemeGradient.sample(stops, at: 0.25)
    let expected = ThemeGradient.mix(stops[0], stops[1], 0.5)
    #expect(abs(quarter.red - expected.red) < 1e-9)
    #expect(ThemeGradient.sample([], at: 0.5) == RGBA(red: 0, green: 0, blue: 0, alpha: 0))
  }
}
