import AppKit
import Testing
@testable import ShellUI

/// The theme creator's slider knob, pad and colour dots, first run's appearance thumb and Space preview, and the
/// floating sidebar read their shadow geometry from named `ShadowToken`s (#764, after #622 and #762) instead of
/// literals. The values are today's: the tests pin them, and check every site draws exactly its token, with the same
/// offset it drew before, in light and dark.
@MainActor
struct ControlShadowTokenTests {
  // MARK: The tokens keep today's look

  @Test func theThemeSliderKnobIsBlackAtAQuarterThreePointsSoftTwoPointsDown() {
    let token = ThemeCreatorTokens.sliderKnobShadow
    #expect(token.color == TokenPair(light: .black(0.25), dark: .black(0.25)))
    #expect(token.radius == 3)
    #expect(token.offsetY == 2)
    #expect(token.unflippedOffset == CGSize(width: 0, height: -2))
    expectNoContactShadow(token)
  }

  @Test func theThemePadInnerShadowAndTheDotShadowsKeepTheirLevels() {
    let pad = ThemeCreatorTokens.padInnerShadow
    #expect(pad.color == TokenPair(light: .black(0.12), dark: .black(0.12)))
    #expect(pad.radius == 7)
    #expect(pad.offsetY == 3)
    let rest = ThemeCreatorTokens.dotRestShadow
    #expect(rest.color == TokenPair(light: .black(0.35), dark: .black(0.35)))
    #expect(rest.radius == 4)
    #expect(rest.offsetY == 2)
    let lift = ThemeCreatorTokens.dotLiftShadow
    #expect(lift.color == TokenPair(light: .black(0.38), dark: .black(0.38)))
    #expect(lift.radius == 11)
    #expect(lift.offsetY == 8)
    for token in [pad, rest, lift] {
      #expect(token.flippedOffset == CGSize(width: 0, height: token.offsetY))
      expectNoContactShadow(token)
    }
  }

  @Test func theFirstRunShadowsKeepTheirLevels() {
    let thumb = BrandTokens.appearanceThumbShadow
    #expect(thumb.color == TokenPair(light: .black(0.12), dark: .black(0.12)))
    #expect(thumb.radius == 1)
    #expect(thumb.offsetY == 1)
    #expect(thumb.unflippedOffset == CGSize(width: 0, height: -1))
    let preview = BrandTokens.spacePreviewShadow
    #expect(preview.color == TokenPair(light: .black(0.45), dark: .black(0.45)))
    #expect(preview.radius == 24)
    #expect(preview.offsetY == 14)
    #expect(preview.unflippedOffset == CGSize(width: 0, height: -14))
    for token in [thumb, preview] { expectNoContactShadow(token) }
  }

  @Test func theFloatingSidebarKeepsItsColorAndTheRevealsBlur() {
    let token = ShellTokens.sidebarOverlayLiftShadow
    #expect(token.color == ShellTokens.sidebarOverlayShadow)
    #expect(token.radius == SidebarRevealMotion.shadowRadius)
    #expect(token.radius == 12)
    #expect(token.offsetY == 2)
    #expect(token.unflippedOffset == CGSize(width: 0, height: -2))
    expectNoContactShadow(token)
  }

  // MARK: Every site draws its token

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theThemeSliderKnob(appearance: NSAppearance.Name) {
    let slider = ThemeSliderView(label: "Grain", identifier: "test.slider")
    slider.appearance = NSAppearance(named: appearance)
    slider.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    slider.setValue(0.3)
    slider.layout()
    let knob = layers(in: slider).first { $0 is ShadowPathLayer }
    #expect(knob != nil, "the knob")
    if let knob {
      expectDraws(ThemeCreatorTokens.sliderKnobShadow, .light, offset: CGSize(width: 0, height: -2), on: knob)
    }
  }

  @Test func theThemePadInnerShadow() throws {
    let pad = ThemePadView(frame: NSRect(x: 0, y: 0, width: 272, height: 200))
    pad.layout()
    let inner = try #require(layers(in: pad).first { $0 is CAShapeLayer && $0.mask != nil })
    expectDraws(ThemeCreatorTokens.padInnerShadow, .light, offset: CGSize(width: 0, height: 3), on: inner)
  }

  @Test func theColourDotAtRestAndPickedUp() throws {
    let dot = ThemeDotView(index: 0)
    let shadows = try #require(dot.layer?.sublayers).filter { $0.shadowPath != nil }
    #expect(shadows.count == 2, "a rest and a lift shadow")
    guard shadows.count == 2 else { return }
    expectDraws(ThemeCreatorTokens.dotRestShadow, .light, offset: CGSize(width: 0, height: 2), on: shadows[0])
    expectDraws(ThemeCreatorTokens.dotLiftShadow, .light, offset: CGSize(width: 0, height: 8), on: shadows[1])
  }

  @Test(arguments: [ThemeFlavor.light, .dark])
  func theFirstRunAppearanceThumb(flavor: ThemeFlavor) {
    let view = AppearanceSegmentView(appearance: OnboardingAppearance(flavor: flavor, reduceMotion: true))
    view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
    view.layout()
    let thumb = layers(in: view).first { $0 is ShadowPathLayer }
    #expect(thumb != nil, "the thumb")
    if let thumb {
      expectDraws(BrandTokens.appearanceThumbShadow, flavor, offset: CGSize(width: 0, height: -1), on: thumb)
    }
  }

  @Test func theFirstRunSpacePreview() throws {
    let preview = SpacePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 220))
    let layer = try #require(preview.layer)
    expectDraws(BrandTokens.spacePreviewShadow, .light, offset: CGSize(width: 0, height: -14), on: layer)
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theFloatingSidebar(appearance: NSAppearance.Name) throws {
    let overlay = SidebarOverlayView(sidebar: SidebarContainerView(source: StubSidebar.sample()))
    overlay.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
    overlay.appearance = NSAppearance(named: appearance)
    overlay.isDocked = false
    overlay.updateLayer()
    let layer = try #require(overlay.layer)
    expectDraws(ShellTokens.sidebarOverlayLiftShadow, ThemeFlavor(appearance: overlay.effectiveAppearance),
                offset: CGSize(width: 0, height: -2), on: layer)
  }

  // MARK: Helpers

  /// What reaches the screen: Core Animation multiplies the color's alpha by the layer's shadow opacity.
  private func effectiveAlpha(_ layer: CALayer) -> Double {
    Double(layer.shadowColor?.alpha ?? 0) * Double(layer.shadowOpacity)
  }

  /// The layer casts `token` for `flavor`: its blur and visible alpha, at `offset`, the literal the site drew before
  /// the token (#764 keeps every value, the direction included).
  private func expectDraws(_ token: ShadowToken, _ flavor: ThemeFlavor, offset: CGSize, on layer: CALayer,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(layer.shadowRadius == token.radius, "blur", sourceLocation: sourceLocation)
    #expect(layer.shadowOffset == offset, "offset \(layer.shadowOffset)", sourceLocation: sourceLocation)
    let alpha = effectiveAlpha(layer)
    #expect(abs(alpha - token.color.resolve(flavor).alpha) < 1e-6,
            "alpha \(alpha) vs \(token.color.resolve(flavor).alpha)", sourceLocation: sourceLocation)
  }

  private func expectNoContactShadow(_ token: ShadowToken, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(token.contactRadius == 0, sourceLocation: sourceLocation)
    #expect(token.contactOffsetY == 0, sourceLocation: sourceLocation)
    #expect(token.contactColor.light.alpha == 0 && token.contactColor.dark.alpha == 0, sourceLocation: sourceLocation)
  }

  private func layers(in view: NSView) -> [CALayer] {
    var found: [CALayer] = []
    func walk(_ layer: CALayer) {
      found.append(layer)
      layer.sublayers?.forEach(walk)
    }
    if let layer = view.layer { walk(layer) }
    return found
  }
}
