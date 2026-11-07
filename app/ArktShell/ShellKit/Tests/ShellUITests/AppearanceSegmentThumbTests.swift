import AppKit
import Testing
@testable import ShellUI

/// The Light / Dark pill on the onboarding theme step (#459): wherever the thumb is asked to sit, its frame in the
/// control's coordinate space is the selected segment's frame. Motion is stepped on an injected clock, never slept.
@MainActor
struct AppearanceSegmentThumbTests {
  private func makeView(reduceMotion: Bool = false) -> AppearanceSegmentView {
    let view = AppearanceSegmentView(appearance: OnboardingAppearance(flavor: .dark, reduceMotion: reduceMotion))
    view.frame = NSRect(origin: NSPoint(x: 40, y: 12), size: view.intrinsicContentSize)
    view.layout()
    return view
  }

  private func expectThumb(on flavor: ThemeFlavor, in view: AppearanceSegmentView,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(view.thumbFrame == view.segmentFrame(for: flavor), "thumb for \(flavor)", sourceLocation: sourceLocation)
  }

  @Test func initialLayoutPutsThePillUnderLight() {
    let view = makeView()
    expectThumb(on: .light, in: view)
  }

  @Test func selectingDarkThenLightWithoutMotionMovesThePillToEachSegment() {
    let view = makeView(reduceMotion: true)
    view.setValue(.dark, animated: true)
    expectThumb(on: .dark, in: view)
    view.setValue(.light, animated: true)
    expectThumb(on: .light, in: view)
  }

  @Test func aLayoutPassKeepsThePillUnderTheSelectedSegment() {
    for flavor in [ThemeFlavor.light, .dark] {
      let view = makeView(reduceMotion: true)
      view.setValue(flavor, animated: false)
      view.needsLayout = true
      view.layout()
      expectThumb(on: flavor, in: view)
    }
  }

  @Test func resizingTheControlKeepsThePillUnderTheSelectedSegment() {
    for flavor in [ThemeFlavor.light, .dark] {
      let view = makeView(reduceMotion: true)
      view.setValue(flavor, animated: false)
      view.setFrameSize(NSSize(width: view.frame.width + 60, height: view.frame.height + 10))
      view.layout()
      expectThumb(on: flavor, in: view)
      view.setFrameSize(view.intrinsicContentSize)
      view.layout()
      expectThumb(on: flavor, in: view)
    }
  }

  // MARK: - Stepped motion

  /// A control on a clock the test owns; no display link, no sleeping.
  private final class Clock { var t = 100.0 }

  private func steppedView(_ clock: Clock, reduceMotion: Bool = false) -> AppearanceSegmentView {
    let view = makeView(reduceMotion: reduceMotion)
    view.now = { clock.t }
    view.drivesFramesItself = false
    return view
  }

  private func step(_ view: AppearanceSegmentView, _ clock: Clock, by dt: Double) {
    clock.t += dt
    view.presentFrame()
  }

  @Test func theThumbTravelsOnItsSpringAndRestsUnderDark() {
    let clock = Clock()
    let view = steppedView(clock)
    let light = view.segmentFrame(for: .light), dark = view.segmentFrame(for: .dark)
    view.setValue(.dark, animated: true)
    #expect(view.isAnimating)
    #expect(view.thumbFrame.minX == light.minX, "the first frame starts where the thumb was")
    step(view, clock, by: 0.1)
    #expect(view.thumbFrame.minX > light.minX && view.thumbFrame.minX < dark.minX, "mid-flight")
    #expect(view.thumbFrame.minY == light.minY && view.thumbFrame.size == light.size, "position only")
    step(view, clock, by: 5)
    #expect(!view.isAnimating)
    expectThumb(on: .dark, in: view)
  }

  @Test func aLayoutPassMidFlightKeepsTheThumbOnItsSpring() {
    let clock = Clock()
    let view = steppedView(clock)
    view.setValue(.dark, animated: true)
    step(view, clock, by: 0.1)
    let before = view.thumbFrame
    view.setFrameSize(NSSize(width: view.frame.width + 30, height: view.frame.height))
    view.layout()
    #expect(view.thumbFrame == before)
  }

  @Test func aNewSelectionMidFlightContinuesFromWhereTheThumbIsAndSettlesOnTheNewSegment() {
    let clock = Clock()
    let view = steppedView(clock)
    view.setValue(.dark, animated: true)
    step(view, clock, by: 0.1)
    let before = view.thumbFrame.minX
    view.setValue(.light, animated: true)
    #expect(abs(view.thumbFrame.minX - before) < 0.001, "no jump when the spring is retargeted")
    step(view, clock, by: 5)
    #expect(!view.isAnimating)
    expectThumb(on: .light, in: view)
  }

  @Test func reduceMotionJumpsWithoutTravel() {
    let clock = Clock()
    let view = steppedView(clock, reduceMotion: true)
    view.setValue(.dark, animated: true)
    #expect(!view.isAnimating)
    expectThumb(on: .dark, in: view)
  }

  @Test func settingTheSameValueDoesNotMoveTheThumb() {
    let clock = Clock()
    let view = steppedView(clock)
    view.setValue(.light, animated: true)
    #expect(!view.isAnimating)
    expectThumb(on: .light, in: view)
  }
}
