import AppKit
import Motion
import QuartzCore
import Testing
@testable import ShellUI

/// Toast motion (docs/design/alerts-sheets-toasts.md, section 7; the Peek's "Peek closed" toast, #346): it rises
/// from the edge it lives on and leaves the way it came, faster than it came; Reduce Motion keeps the fade only.
@MainActor
struct ToastMotionTests {
  @Test func `the entrance rises twelve points and grows from 0.96 on springyFast`() {
    let enter = ToastMotion.enter(reduceMotion: false)
    #expect(enter.offset == 12 && enter.scale == 0.96)
    #expect(enter.spring == SpringPreset.springyFast.parameters)
    #expect(enter.fadeDuration == 0.16)
  }

  @Test func `the exit sinks six points to 0.98 and is faster than the entrance`() {
    let exit = ToastMotion.exit(reduceMotion: false)
    #expect(exit.offset == 6 && exit.scale == 0.98)
    #expect(exit.spring == nil, "an eased exit, no spring")
    #expect(exit.fadeDuration == 0.15)
    #expect(exit.fadeDuration < ToastMotion.enter(reduceMotion: false).fadeDuration)
  }

  @Test func `reduce motion fades only`() {
    for step in [ToastMotion.enter(reduceMotion: true), ToastMotion.exit(reduceMotion: true)] {
      #expect(step.offset == 0 && step.scale == 1 && step.spring == nil)
      #expect(step.fadeDuration == 0.15)
    }
  }

  /// The transform scales about the pill's center (AppKit anchors a view's layer at its origin) and moves it down
  /// in an unflipped host.
  @Test func `the transform scales about the center and moves down`() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 36)
    let transform = ToastMotion.transform(offset: 12, scale: 0.96, bounds: bounds, anchor: .zero)
    let center = CGPoint(x: 100, y: 18).applying(CATransform3DGetAffineTransform(transform))
    #expect(abs(center.x - 100) < 1e-9)
    #expect(abs(center.y - 6) < 1e-9, "12 points lower in an unflipped superview")
    #expect(CATransform3DIsIdentity(ToastMotion.transform(offset: 0, scale: 1, bounds: bounds, anchor: .zero)))
  }

  /// The view drives the layer: an entrance adds a spring on the transform and a fade on the opacity; the model
  /// values are the resting ones. Reduce Motion adds the fade only.
  @Test func `the view animates transform and opacity on its layer`() throws {
    let view = ToastView(frame: CGRect(x: 0, y: 0, width: 200, height: 36))
    view.reduceMotion = { false }
    view.display(Toast(text: "Peek closed", actionTitle: "Reopen"), animated: true)
    let layer = try #require(view.layer)
    #expect(layer.animation(forKey: ToastView.transformKey) is CASpringAnimation)
    #expect(layer.animation(forKey: ToastView.fadeKey) != nil)
    #expect(CATransform3DIsIdentity(layer.transform) && layer.opacity == 1)

    let still = ToastView(frame: CGRect(x: 0, y: 0, width: 200, height: 36))
    still.reduceMotion = { true }
    still.display(Toast(text: "Peek closed"), animated: true)
    #expect(still.layer?.animation(forKey: ToastView.transformKey) == nil)
    #expect(still.layer?.animation(forKey: ToastView.fadeKey) != nil)
  }

  /// "Reopen" with its key after it, the key at half strength.
  @Test func `the action shows its key after the title`() {
    let view = ToastView(frame: CGRect(x: 0, y: 0, width: 200, height: 36))
    view.display(Toast(text: "Peek closed", actionTitle: "Reopen", shortcut: "\u{2318}Z"), animated: false)
    #expect(view.actionButton.displayedTitleText == "Reopen \u{2318}Z")
    #expect(view.actionButton.accessibilityLabel() == "Reopen")
    view.display(Toast(text: "Restored", actionTitle: "View"), animated: false)
    #expect(view.actionButton.displayedTitleText == "View")
  }
}
