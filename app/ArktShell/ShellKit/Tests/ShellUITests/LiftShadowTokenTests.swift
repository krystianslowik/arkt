import AppKit
import Testing
@testable import ShellUI

/// The row, tile and card lifts and the Settings control lifts read their geometry from named `ShadowToken`s (#622)
/// instead of literals, so the reference geometry (#77) changes in one place. The values are today's: the tests pin
/// them and check every site draws exactly its token, in light and dark, with Increase Contrast on and off.
@MainActor
struct LiftShadowTokenTests {
  // MARK: The tokens keep today's look

  @Test func theRowLiftIsTheCurrentTabsShadowTwoPointsSoftOnePointDown() {
    let token = ShellTokens.rowLiftShadow
    #expect(token.color == ShellTokens.tabCurrentShadow)
    #expect(token.radius == 2)
    #expect(token.offsetY == 1)
    #expect(token.unflippedOffset == CGSize(width: 0, height: -1))
    expectNoContactShadow(token)
  }

  @Test func theCardLiftIsTheCardShadowThreePointsSoftOnePointDown() {
    let token = ShellTokens.cardLiftShadow
    #expect(token.color == ShellTokens.cardShadow)
    #expect(token.radius == 3)
    #expect(token.offsetY == 1)
    #expect(token.unflippedOffset == CGSize(width: 0, height: -1))
    expectNoContactShadow(token)
  }

  @Test func theSettingsLiftsKeepTheirLevels() {
    let knob = SettingsTokens.switchKnobShadow
    #expect(knob.color == TokenPair(light: .black(0.22), dark: .black(0.40)))
    #expect(knob.radius == 1)
    #expect(knob.offsetY == 1)
    let segment = SettingsTokens.segmentPlateShadow
    #expect(segment.color == TokenPair(light: .black(0.10), dark: .black(0)))
    #expect(segment.radius == 1)
    #expect(segment.offsetY == 1)
    let pane = SettingsTokens.paneItemPlateShadow
    #expect(pane.color.light.alpha == ShellTokens.tabCurrentShadow.light.alpha * 0.5)
    #expect(pane.color.dark.alpha == 0)
    #expect(pane.radius == 1.5)
    #expect(pane.offsetY == 1)
    for token in [knob, segment, pane] { expectNoContactShadow(token) }
  }

  // MARK: Every site draws its token

  @Test(arguments: [ThemeFlavor.light, .dark], [false, true])
  func theCurrentTabRow(flavor: ThemeFlavor, increased: Bool) {
    let row = SidebarRowView(frame: NSRect(x: 0, y: 0, width: 240, height: SidebarMetrics.rowPitch))
    row.increaseContrast = { increased }
    row.flavor = flavor
    row.state = .current
    row.layout()
    row.updateLayer()
    expectDraws(ShellTokens.rowLiftShadow, flavor, on: row.backgroundLayer)
    #expect(row.backgroundLayer.shadowPath != nil, "an explicit path, no offscreen pass")
  }

  @Test(arguments: [ThemeFlavor.light, .dark], [false, true])
  func theCurrentFavoriteTile(flavor: ThemeFlavor, increased: Bool) {
    let tile = FavoriteTileView(frame: NSRect(x: 0, y: 0, width: 52, height: 46))
    tile.increaseContrast = { increased }
    tile.flavor = flavor
    tile.isCurrent = true
    tile.layout()
    tile.updateLayer()
    expectDraws(ShellTokens.rowLiftShadow, flavor, on: tile.fillLayer)
    #expect(tile.fillLayer.shadowPath != nil, "an explicit path, no offscreen pass")
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theSelectedArchiveRow(appearance: NSAppearance.Name) {
    let row = ArchiveRowView(frame: NSRect(x: 0, y: 0, width: 400, height: 36))
    row.appearance = NSAppearance(named: appearance)
    row.isSelected = true
    row.updateLayer()
    let fill = row.layer?.sublayers?.first { $0.cornerRadius == SidebarMetrics.rowCornerRadius }
    #expect(fill != nil, "the row's fill layer")
    if let fill { expectDraws(ShellTokens.rowLiftShadow, row.archiveFlavor, on: fill) }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theContentCard(appearance: NSAppearance.Name) throws {
    let card = ContentCardView()
    card.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    card.appearance = NSAppearance(named: appearance)
    card.updateLayer()
    let layer = try #require(card.layer)
    expectDraws(ShellTokens.cardLiftShadow, ThemeFlavor(appearance: card.effectiveAppearance), on: layer)
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua], [false, true])
  func theSettingsSwitchKnob(appearance: NSAppearance.Name, on: Bool) {
    let toggle = SettingsSwitch(frame: .zero)
    toggle.appearance = NSAppearance(named: appearance)
    toggle.setOn(on, animated: false)
    let flavor = ThemeFlavor(appearance: toggle.effectiveAppearance)
    let knob = layers(in: toggle).first { $0 is ShadowPathLayer }
    #expect(knob != nil, "the knob")
    guard let knob else { return }
    if on && flavor == .dark {
      #expect(effectiveAlpha(knob) == 0, "an on knob in dark casts no shadow")
    } else {
      expectDraws(SettingsTokens.switchKnobShadow, flavor, on: knob)
    }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theSettingsSegmentPlate(appearance: NSAppearance.Name) {
    let control = SettingsSegmentedControl(segments: ["One", "Two"], selected: 0, segmentWidth: 96)
    control.appearance = NSAppearance(named: appearance)
    control.select(1)
    let plate = layers(in: control).first { $0 is ShadowPathLayer }
    #expect(plate != nil, "the plate")
    if let plate {
      expectDraws(SettingsTokens.segmentPlateShadow, ThemeFlavor(appearance: control.effectiveAppearance), on: plate)
    }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theSettingsPaneItemPlate(appearance: NSAppearance.Name) {
    let item = SettingsPaneItemView(pane: .general)
    item.appearance = NSAppearance(named: appearance)
    item.viewDidChangeEffectiveAppearance()
    let plate = layers(in: item).first { $0 is ShadowPathLayer }
    #expect(plate != nil, "the plate")
    if let plate {
      expectDraws(SettingsTokens.paneItemPlateShadow, ThemeFlavor(appearance: item.effectiveAppearance), on: plate)
    }
  }

  // MARK: Helpers

  /// What reaches the screen: Core Animation multiplies the color's alpha by the layer's shadow opacity.
  private func effectiveAlpha(_ layer: CALayer) -> Double {
    Double(layer.shadowColor?.alpha ?? 0) * Double(layer.shadowOpacity)
  }

  /// The layer casts `token` for `flavor`: the same blur, offset and visible alpha (none where the token is clear).
  private func expectDraws(_ token: ShadowToken, _ flavor: ThemeFlavor, on layer: CALayer,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(layer.shadowRadius == token.radius, "blur", sourceLocation: sourceLocation)
    #expect(layer.shadowOffset == token.unflippedOffset, "offset", sourceLocation: sourceLocation)
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
