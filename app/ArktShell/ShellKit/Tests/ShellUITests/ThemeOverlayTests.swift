import AppKit
import Testing
@testable import ShellUI

/// The second gradient layer (overlay colors) and the OKLab-expanded base gradient in the theme background (#381).
@MainActor
struct ThemeOverlayTests {
  private static let segments = ThemeGradient.segmentsPerPair

  private func theme(overlay: [RGBA] = [], dark: Bool = false) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: [.p3(hex: 0xF2EAE4, alpha: 1), .p3(hex: 0xF29BBB, alpha: 1)], overlayColors: overlay,
                   isDark: dark)
  }

  private func view(_ themes: [SpaceThemeInfo]) -> ThemeBackgroundView {
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 120, height: 80), grainRenderer: nil)
    view.reducesMotion = { false }
    view.crossfadeDuration = 0.28
    view.themes = themes
    view.setPosition(0)
    return view
  }

  private func components(_ color: CGColor) -> [Double] { (color.components ?? []).map { Double($0) } }

  // MARK: Existing themes

  /// Every shipped theme keeps its look: the same end stops and the same stops at its own positions, with only the
  /// steps between them perceptual and close to the old blend. No overlay layer is shown.
  @Test func shippedThemesKeepTheirStopsAndShowNoOverlay() {
    let shipped = [SpaceThemeCatalog.paper, SpaceThemeCatalog.dusk]
      + SpaceThemeCatalog.families.flatMap { [$0.light, $0.dark] }
    for theme in shipped {
      let view = view([theme, theme])
      let drawn = view.baseColorsForTesting
      #expect(drawn.count == (theme.baseColors.count - 1) * Self.segments + 1)
      for (index, stop) in theme.baseColors.enumerated() {
        let got = components(drawn[index * Self.segments]), want = components(stop.cgColor)
        #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-6 }, "stop \(index) of \(theme.baseColors)")
      }
      for pair in 0..<(theme.baseColors.count - 1) {
        for step in 1..<Self.segments {
          let t = Double(step) / Double(Self.segments)
          let old = RGBA.mix(theme.baseColors[pair], theme.baseColors[pair + 1], t)
          let got = components(drawn[pair * Self.segments + step])
          #expect(zip(got, [old.red, old.green, old.blue]).allSatisfy { abs($0 - $1) < 0.05 },
                  "step \(step) of \(theme.baseColors)")
        }
      }
      #expect(view.overlayColorLayersForTesting.allSatisfy { $0.isHidden })
    }
  }

  @Test func aSingleColorStaysFlat() {
    let one = SpaceThemeInfo(baseColors: [.srgb(hex: 0x336699)], isDark: false)
    let drawn = view([one, one]).baseColorsForTesting
    #expect(drawn.count == 2)
    #expect(components(drawn[0]) == components(drawn[1]))
  }

  // MARK: Overlay layer

  /// The overlay colors are an OKLab-expanded gradient above the base, hidden for themes without any.
  @Test func overlayColorsAreDrawnAsAnExpandedGradient() throws {
    let overlay: [RGBA] = [.black(0.2), RGBA.white(0.1)]
    let view = view([theme(overlay: overlay), theme()])
    let lower = try #require(view.overlayColorLayersForTesting.first)
    #expect(lower.isHidden == false)
    #expect(lower.opacity == 1)
    #expect((lower.colors as? [CGColor])?.count == Self.segments + 1)
    let upper = try #require(view.overlayColorLayersForTesting.last)
    #expect(upper.isHidden, "the next Space has no overlay")
  }

  /// A single overlay color is a flat tint.
  @Test func aSingleOverlayColorIsFlat() throws {
    let view = view([theme(overlay: [.black(0.3)]), theme()])
    let colors = try #require(view.overlayColorLayersForTesting.first?.colors as? [CGColor])
    #expect(colors.count == 2)
  }

  /// Per pager frame only opacities change: the lower Space's overlay fades out as the upper one fades in, and the
  /// colors are set again only when the lower index changes.
  @Test func thePagerChangesOnlyOpacities() throws {
    let a = theme(overlay: [.black(0.2), .black(0.4)]), b = theme(overlay: [RGBA.white(0.3)])
    let view = view([a, b, theme()])
    let lower = try #require(view.overlayColorLayersForTesting.first)
    let upper = try #require(view.overlayColorLayersForTesting.last)
    let lowerColors = lower.colors as? [CGColor]
    view.setPosition(0.25)
    #expect(abs(lower.opacity - 0.75) < 1e-6 && abs(upper.opacity - 0.25) < 1e-6)
    #expect(lower.colors as? [CGColor] == lowerColors)
    view.setPosition(0.5)
    #expect(abs(lower.opacity - 0.5) < 1e-6 && abs(upper.opacity - 0.5) < 1e-6)
    #expect(lower.isHidden == false && upper.isHidden == false)
    view.setPosition(1.5)
    #expect(upper.isHidden, "Space 3 has no overlay")
    #expect(lower.isHidden == false)
    #expect(abs(lower.opacity - 0.5) < 1e-6)
  }

  /// The overlay layers sit above the base gradients and below the texture multiply.
  @Test func overlayLayersSitBetweenTheGradientsAndTheTexture() throws {
    let textured = SpaceThemeInfo(baseColors: theme().baseColors, overlayColors: [.black(0.2)], texture: "grain",
                                  noiseFactor: 0.5, isDark: false)
    let view = view([textured, textured])
    let layers = try #require(view.layer?.sublayers)
    let grain = try #require(view.grainLayerForTesting(.grain))
    let grainIndex = try #require(layers.firstIndex { $0 === grain })
    for layer in view.overlayColorLayersForTesting {
      let index = try #require(layers.firstIndex { $0 === layer })
      #expect(index < grainIndex)
      #expect(index > 1, "above the base and the upper-theme gradient")
    }
  }

  // MARK: Crossfade

  /// A settled theme change fades the old overlay out and the new one in with the gradient, on the same curve.
  @Test func aThemeChangeCrossfadesTheOverlayWithTheGradient() throws {
    let view = view([theme(overlay: [.black(0.2)]), theme()])
    view.replaceThemes([theme(overlay: [RGBA.white(0.3)]), theme()], crossfade: true)
    let lower = try #require(view.overlayColorLayersForTesting.first)
    let upper = try #require(view.overlayColorLayersForTesting.last)
    let out = try #require(lower.animation(forKey: "themeCrossfade") as? CABasicAnimation)
    let into = try #require(upper.animation(forKey: "themeCrossfade") as? CABasicAnimation)
    #expect((out.fromValue as? NSNumber)?.floatValue == 1 && (out.toValue as? NSNumber)?.floatValue == 0)
    #expect((into.fromValue as? NSNumber)?.floatValue == 0 && (into.toValue as? NSNumber)?.floatValue == 1)
    #expect(out.duration == 0.28 && into.duration == 0.28)
    #expect(lower.isHidden == false && upper.isHidden == false)
    view.setPosition(0)
    #expect(lower.animation(forKey: "themeCrossfade") == nil && upper.animation(forKey: "themeCrossfade") == nil)
    #expect(upper.isHidden, "settled on a Space without a second overlay")
  }

  /// Adding the first overlay to a Space with none fades only the new one in.
  @Test func addingAnOverlayFadesOnlyTheNewOneIn() throws {
    let view = view([theme(), theme()])
    view.replaceThemes([theme(overlay: [.black(0.3)]), theme()], crossfade: true)
    let lower = try #require(view.overlayColorLayersForTesting.first)
    let upper = try #require(view.overlayColorLayersForTesting.last)
    #expect(lower.isHidden)
    #expect(upper.isHidden == false)
    #expect(upper.animation(forKey: "themeCrossfade") != nil)
  }

  @Test func reduceMotionSnapsTheOverlay() throws {
    let view = view([theme(), theme()])
    view.reducesMotion = { true }
    view.replaceThemes([theme(overlay: [.black(0.3)]), theme()], crossfade: true)
    let lower = try #require(view.overlayColorLayersForTesting.first)
    let upper = try #require(view.overlayColorLayersForTesting.last)
    #expect(lower.isHidden == false && lower.opacity == 1)
    #expect(upper.animation(forKey: "themeCrossfade") == nil)
  }

  /// The creator's live preview draws the overlay at once.
  @Test func aPreviewDrawsTheOverlayAtOnce() throws {
    let view = view([theme(), theme()])
    view.previewTheme(theme(overlay: [.black(0.3)]), at: 0)
    let lower = try #require(view.overlayColorLayersForTesting.first)
    #expect(lower.isHidden == false && lower.opacity == 1)
    #expect(lower.animation(forKey: "themeCrossfade") == nil)
  }
}
