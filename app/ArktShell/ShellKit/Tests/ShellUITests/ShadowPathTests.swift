import AppKit
import Testing
@testable import ShellUI

/// Shadowed layers that move or fade carry an explicit `shadowPath` matching their shape (#604), so Core Animation
/// never derives the shadow from their alpha offscreen. The path follows every size and corner radius change.
@MainActor
struct ShadowPathTests {
  // MARK: The layer

  @Test func aBoundsChangeRebuildsThePath() {
    let layer = ShadowPathLayer()
    layer.cornerRadius = 8
    layer.bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
    expectPath(of: layer)
    layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 30)
    expectPath(of: layer)
  }

  @Test func aFrameChangeRebuildsThePath() {
    let layer = ShadowPathLayer()
    layer.cornerRadius = 4
    layer.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
    expectPath(of: layer)
    layer.frame = CGRect(x: 50, y: 5, width: 60, height: 18)
    expectPath(of: layer)
  }

  @Test func aCornerRadiusChangeRebuildsThePath() {
    let layer = ShadowPathLayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 80, height: 24)
    layer.cornerRadius = 12
    expectPath(of: layer)
    #expect(layer.shadowPath == ShadowPathLayer.shadowPath(for: layer.bounds, cornerRadius: 12))
    layer.cornerRadius = 3
    #expect(layer.shadowPath == ShadowPathLayer.shadowPath(for: layer.bounds, cornerRadius: 3))
  }

  @Test func aRadiusPastACapsuleIsClampedAndEmptyBoundsHaveNoPath() {
    #expect(ShadowPathLayer.shadowPath(for: .zero, cornerRadius: 4) == nil)
    let capsule = CGRect(x: 0, y: 0, width: 60, height: 20)
    #expect(ShadowPathLayer.shadowPath(for: capsule, cornerRadius: 50)
            == ShadowPathLayer.shadowPath(for: capsule, cornerRadius: 10))
  }

  @Test func thePathAnimatesOnlyWhenTheBoundsWould() {
    let layer = ShadowPathLayer()
    let pathAnimation = CABasicAnimation(keyPath: "shadowPath")
    layer.actions = ["bounds": NSNull(), "shadowPath": pathAnimation]
    #expect(layer.action(forKey: "shadowPath") == nil)
    layer.actions = ["bounds": CABasicAnimation(keyPath: "bounds"), "shadowPath": pathAnimation]
    #expect(layer.action(forKey: "shadowPath") as? CABasicAnimation === pathAnimation)
  }

  // MARK: The controls

  @Test func theStatusPillFollowsItsWidth() {
    let pill = StatusPillView(frame: NSRect(x: 0, y: 0, width: 120, height: StatusPillGeometry.height))
    pill.layout()
    expectEveryShadowHasAPath(in: pill)
    pill.setFrameSize(NSSize(width: 260, height: StatusPillGeometry.height))
    pill.layout()
    expectEveryShadowHasAPath(in: pill)
    #expect(pill.layer?.shadowPath?.boundingBox == pill.layer?.bounds)
  }

  @Test func theThemeCreatorSliderKnob() {
    let slider = ThemeSliderView(label: "Grain", identifier: "test.slider")
    slider.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    slider.setValue(0.3)
    slider.layout()
    expectEveryShadowHasAPath(in: slider)
    slider.setFrameSize(NSSize(width: 320, height: 28))
    slider.setValue(0.9)
    slider.layout()
    expectEveryShadowHasAPath(in: slider)
  }

  @Test func theSettingsSwitchKnobInBothStates() {
    let toggle = SettingsSwitch(frame: .zero)
    toggle.appearance = NSAppearance(named: .aqua)
    toggle.setOn(false, animated: false)
    expectEveryShadowHasAPath(in: toggle)
    toggle.setOn(true, animated: false)
    expectEveryShadowHasAPath(in: toggle)
  }

  @Test func theSettingsSegmentPlate() {
    let control = SettingsSegmentedControl(segments: ["One", "Two", "Three"], selected: 0, segmentWidth: 96)
    control.appearance = NSAppearance(named: .aqua)
    control.select(2)
    expectEveryShadowHasAPath(in: control)
  }

  @Test func theSettingsPaneItemPlate() {
    let item = SettingsPaneItemView(pane: .general)
    item.appearance = NSAppearance(named: .aqua)
    item.viewDidChangeEffectiveAppearance()
    expectEveryShadowHasAPath(in: item)
  }

  @Test func theOnboardingAppearanceThumbAcrossAResize() {
    let view = AppearanceSegmentView(appearance: OnboardingAppearance(flavor: .light, reduceMotion: true))
    view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
    view.layout()
    expectEveryShadowHasAPath(in: view)
    view.setFrameSize(NSSize(width: view.frame.width + 60, height: view.frame.height + 10))
    view.layout()
    view.setValue(.dark, animated: false)
    expectEveryShadowHasAPath(in: view)
  }

  // MARK: Helpers

  private func expectPath(of layer: CALayer, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(layer.shadowPath != nil, "no shadow path", sourceLocation: sourceLocation)
    let box = layer.shadowPath?.boundingBox
    #expect(box == layer.bounds, "path \(String(describing: box)) vs bounds \(layer.bounds)",
            sourceLocation: sourceLocation)
  }

  /// Every layer under `view` that casts a visible shadow has a path matching its bounds. At least one such layer is
  /// expected, so a control that lost its shadow altogether does not pass by accident.
  private func expectEveryShadowHasAPath(in view: NSView, sourceLocation: SourceLocation = #_sourceLocation) {
    var shadowed: [CALayer] = []
    func walk(_ layer: CALayer) {
      if layer.shadowOpacity > 0 { shadowed.append(layer) }
      layer.sublayers?.forEach(walk)
    }
    if let layer = view.layer { walk(layer) }
    #expect(!shadowed.isEmpty, "no shadowed layer found", sourceLocation: sourceLocation)
    for layer in shadowed { expectPath(of: layer, sourceLocation: sourceLocation) }
  }
}
