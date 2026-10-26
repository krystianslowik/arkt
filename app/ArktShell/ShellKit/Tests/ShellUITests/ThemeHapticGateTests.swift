import AppKit
import Testing
@testable import ShellUI

/// The creator's haptic map (design/theme-creator/README.md, "Haptics"): which drag events play what, each event's
/// re-arm rule, and the global limit of one every 50 ms (dropped, never queued).
@MainActor
struct ThemeHapticGateTests {
  /// Far enough apart that the global limit never interferes.
  static func time(_ n: Int) -> Double { Double(n) * 0.2 }

  @Test func catalogHuesComeFromTheSecondLightStops() {
    #expect(ThemeHapticGate.catalogHues.map { $0.rounded() } == [45, 238, 37, 107, 338, 250])
  }

  @Test func sliderDetentsPlayOncePerCrossingAndReArmAfterThreePercent() {
    let gate = GateProbe()
    #expect(gate.slider(.opacity, from: 0.40, to: 0.45, at: Self.time(0)) == nil)
    #expect(gate.slider(.opacity, from: 0.45, to: 0.52, at: Self.time(1)) == .generic)
    // Back across inside 3 %: still disarmed.
    #expect(gate.slider(.opacity, from: 0.52, to: 0.49, at: Self.time(2)) == nil)
    #expect(gate.slider(.opacity, from: 0.49, to: 0.51, at: Self.time(3)) == nil)
    // 3 % away re-arms it.
    #expect(gate.slider(.opacity, from: 0.51, to: 0.54, at: Self.time(4)) == nil)
    #expect(gate.slider(.opacity, from: 0.54, to: 0.50, at: Self.time(5)) == .generic)
  }

  @Test func reachingAnEndIsADetent() {
    let gate = GateProbe()
    #expect(gate.slider(.amount, from: 0.95, to: 1, at: Self.time(0)) == .generic)
    #expect(gate.slider(.amount, from: 1, to: 1, at: Self.time(1)) == nil)
    #expect(gate.slider(.amount, from: 0.04, to: 0, at: Self.time(2)) == .generic)
  }

  /// Each slider keeps its own arming.
  @Test func slidersAreArmedSeparately() {
    let gate = GateProbe()
    #expect(gate.slider(.amount, from: 0.45, to: 0.55, at: Self.time(0)) == .generic)
    #expect(gate.slider(.opacity, from: 0.45, to: 0.55, at: Self.time(1)) == .generic)
  }

  @Test func presetHueCrossingPlaysAlignmentAndReArmsAfterSixDegrees() {
    let gate = GateProbe(presetHues: [107])
    #expect(gate.hue(from: 100, to: 105, at: Self.time(0)) == nil)
    #expect(gate.hue(from: 105, to: 109, at: Self.time(1)) == .alignment)
    #expect(gate.hue(from: 109, to: 104, at: Self.time(2)) == nil)
    #expect(gate.hue(from: 104, to: 100, at: Self.time(3)) == nil)
    #expect(gate.hue(from: 100, to: 108, at: Self.time(4)) == .alignment)
  }

  /// A fling of more than 30 degrees in one event plays nothing.
  @Test func aFastFlingSkipsTheHueHaptic() {
    let gate = GateProbe(presetHues: [107])
    #expect(gate.hue(from: 90, to: 121, at: Self.time(0)) == nil)
    #expect(gate.hue(from: 121, to: 100, at: Self.time(1)) == .alignment)
  }

  @Test func toneLimitPlaysOncePerArrivalAndReArmsFourPointsAway() {
    let gate = GateProbe()
    gate.beginToneTracking(distanceFromLimit: 20)
    #expect(gate.tone(distanceFromLimit: 6, at: Self.time(0)) == nil)
    #expect(gate.tone(distanceFromLimit: 0, at: Self.time(1)) == .levelChange)
    #expect(gate.tone(distanceFromLimit: 0, at: Self.time(2)) == nil)
    #expect(gate.tone(distanceFromLimit: 3, at: Self.time(3)) == nil)
    #expect(gate.tone(distanceFromLimit: 0, at: Self.time(4)) == nil)
    #expect(gate.tone(distanceFromLimit: 4, at: Self.time(5)) == nil)
    #expect(gate.tone(distanceFromLimit: 0, at: Self.time(6)) == .levelChange)
  }

  /// A dot picked up while resting on the limit has not arrived there.
  @Test func aDotPickedUpAtTheLimitHasNotArrived() {
    let gate = GateProbe()
    gate.beginToneTracking(distanceFromLimit: 0)
    #expect(gate.tone(distanceFromLimit: 0, at: Self.time(0)) == nil)
  }

  @Test func textureStepPlaysAlignment() {
    let gate = GateProbe()
    #expect(gate.textureChanged(at: Self.time(0)) == .alignment)
    #expect(gate.textureChanged(at: Self.time(1)) == .alignment)
  }

  /// At most one haptic every 50 ms; one inside that window is dropped, not queued, and its arming is spent.
  @Test func theGlobalLimitDropsEventsInsideFiftyMilliseconds() {
    let gate = GateProbe(presetHues: [107])
    #expect(gate.textureChanged(at: 1.0) == .alignment)
    #expect(gate.hue(from: 105, to: 109, at: 1.03) == nil)
    // The dropped crossing spent its arming: crossing back within 6 degrees plays nothing.
    #expect(gate.hue(from: 109, to: 104, at: 1.2) == nil)
    #expect(gate.textureChanged(at: 1.049) == nil)
    #expect(gate.textureChanged(at: 1.1) == .alignment)
  }

  /// The player sends what the gate lets through to the injected performer, at the injected time.
  @Test func playerPerformsThroughTheInjectedPerformer() {
    let performer = CountingPerformer()
    let clock = TestClock(10)
    let player = ThemeHaptics(performer: performer, now: { clock.time })
    player.textureChanged()
    player.textureChanged()
    clock.time += 0.06
    player.textureChanged()
    #expect(performer.patterns == [.alignment, .alignment])
  }
}

/// A settable time for the player.
@MainActor
final class TestClock {
  var time: Double
  init(_ time: Double) { self.time = time }
}

/// The gate behind a reference, so `#expect` can call its mutating methods.
final class GateProbe {
  var gate: ThemeHapticGate
  init(presetHues: [Double] = ThemeHapticGate.catalogHues) { gate = ThemeHapticGate(presetHues: presetHues) }
  func slider(_ slider: ThemeHapticGate.Slider, from old: Double, to new: Double, at time: Double)
    -> ThemeHapticGate.Pattern? { gate.slider(slider, from: old, to: new, at: time) }
  func hue(from old: Double, to new: Double, at time: Double) -> ThemeHapticGate.Pattern? {
    gate.hue(from: old, to: new, at: time)
  }
  func beginToneTracking(distanceFromLimit: Double) { gate.beginToneTracking(distanceFromLimit: distanceFromLimit) }
  func tone(distanceFromLimit: Double, at time: Double) -> ThemeHapticGate.Pattern? {
    gate.tone(distanceFromLimit: distanceFromLimit, at: time)
  }
  func textureChanged(at time: Double) -> ThemeHapticGate.Pattern? { gate.textureChanged(at: time) }
}

/// Counts what the creator plays, in place of `NSHapticFeedbackManager.defaultPerformer`.
final class CountingPerformer: NSObject, NSHapticFeedbackPerformer {
  private(set) var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []

  func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern,
               performanceTime: NSHapticFeedbackManager.PerformanceTime) {
    patterns.append(pattern)
  }
}
