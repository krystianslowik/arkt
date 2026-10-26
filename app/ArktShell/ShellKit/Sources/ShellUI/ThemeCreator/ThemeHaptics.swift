import AppKit

/// Which drag events of the theme creator play a haptic, and when (#410, design/theme-creator/README.md, "Haptics").
///
/// Pure: events and times in, a pattern or nil out. Each event has its own arming (it plays once, then waits to be
/// re-armed), and all share a global limit of one haptic every 50 ms. An event inside that window is dropped, never
/// queued, and its arming is spent as if it had played. Only pointer drags feed the gate; keyboard changes play none.
public struct ThemeHapticGate: Sendable {
  public typealias Pattern = NSHapticFeedbackManager.FeedbackPattern

  public enum Slider: Hashable, Sendable { case amount, opacity }

  /// Slider stops that play `.generic`.
  public static let detents: [Double] = [0, 0.5, 1]
  /// A detent re-arms once the value is this far from it.
  public static let detentReArm = 0.03
  /// A preset hue re-arms once the hue is this many degrees from it.
  public static let hueReArm = 6.0
  /// A hue jump larger than this in one event is a fling and plays nothing.
  public static let hueFling = 30.0
  /// The tone limit re-arms once the dot is this many points from it.
  public static let toneReArm = 4.0
  /// At most one haptic per this interval, in seconds.
  public static let minimumInterval = 0.05

  /// The HSL hue of each theme family's second light stop (`SpaceThemeCatalog.families`): Dune 45, Mist 238,
  /// Paper 37, Sage 107, Blossom 338, Indigo 250.
  public static let catalogHues: [Double] = SpaceThemeCatalog.families.compactMap { family in
    family.light.baseColors.count > 1 ? ThemePad.hue(of: family.light.baseColors[1]) : nil
  }

  public let presetHues: [Double]
  private var disarmedDetents: Set<DetentKey> = []
  private var disarmedHues: Set<Int> = []
  private var toneArmed = true
  private var lastPlayed = -Double.infinity

  private struct DetentKey: Hashable, Sendable {
    var slider: Slider
    var index: Int
  }

  public init(presetHues: [Double] = ThemeHapticGate.catalogHues) {
    self.presetHues = presetHues
  }

  /// A slider dragged from `old` to `new`: `.generic` when it reaches or crosses 0, 50 or 100 %.
  public mutating func slider(_ slider: Slider, from old: Double, to new: Double, at time: Double) -> Pattern? {
    var crossed = false
    for (index, stop) in Self.detents.enumerated() {
      let key = DetentKey(slider: slider, index: index)
      if old != new, old != stop, (old - stop) * (new - stop) <= 0, !disarmedDetents.contains(key) {
        disarmedDetents.insert(key)
        crossed = true
      } else if abs(new - stop) >= Self.detentReArm - 1e-12 {
        disarmedDetents.remove(key)
      }
    }
    return crossed ? play(.generic, at: time) : nil
  }

  /// The dragged dot's hue moved from `old` to `new` (pointer hue does not wrap): `.alignment` when it reaches or
  /// crosses a preset hue.
  public mutating func hue(from old: Double, to new: Double, at time: Double) -> Pattern? {
    let fling = abs(new - old) > Self.hueFling
    var crossed = false
    for (index, presetHue) in presetHues.enumerated() {
      let crosses = old != new && old != presetHue && (old - presetHue) * (new - presetHue) <= 0
      if crosses, !fling, !disarmedHues.contains(index) {
        disarmedHues.insert(index)
        crossed = true
      } else if abs(new - presetHue) >= Self.hueReArm - 1e-12 {
        disarmedHues.remove(index)
      }
    }
    return crossed ? play(.alignment, at: time) : nil
  }

  /// Starts tracking a picked-up dot: it is armed unless it already rests on the limit.
  public mutating func beginToneTracking(distanceFromLimit: Double) {
    toneArmed = distanceFromLimit > 0
  }

  /// The dragged dot is `distanceFromLimit` points from the pad's top or bottom limit (0 on it): `.levelChange` once
  /// per arrival.
  public mutating func tone(distanceFromLimit: Double, at time: Double) -> Pattern? {
    if distanceFromLimit <= 0 {
      guard toneArmed else { return nil }
      toneArmed = false
      return play(.levelChange, at: time)
    }
    if distanceFromLimit >= Self.toneReArm - 1e-9 { toneArmed = true }
    return nil
  }

  /// The selected texture swatch changed.
  public mutating func textureChanged(at time: Double) -> Pattern? { play(.alignment, at: time) }

  private mutating func play(_ pattern: Pattern, at time: Double) -> Pattern? {
    guard time - lastPlayed >= Self.minimumInterval - 1e-9 else { return nil }
    lastPlayed = time
    return pattern
  }
}

/// Plays the gate's haptics through `NSHapticFeedbackManager.defaultPerformer`, or an injected performer in tests.
@MainActor
public final class ThemeHaptics {
  private var gate: ThemeHapticGate
  private let performer: any NSHapticFeedbackPerformer
  private let now: @MainActor () -> Double

  public init(performer: any NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer,
              gate: ThemeHapticGate = ThemeHapticGate(),
              now: @escaping @MainActor () -> Double = { CACurrentMediaTime() }) {
    self.performer = performer
    self.gate = gate
    self.now = now
  }

  public func slider(_ slider: ThemeHapticGate.Slider, from old: Double, to new: Double) {
    perform(gate.slider(slider, from: old, to: new, at: now()))
  }

  public func hue(from old: Double, to new: Double) { perform(gate.hue(from: old, to: new, at: now())) }

  public func beginToneTracking(distanceFromLimit: Double) {
    gate.beginToneTracking(distanceFromLimit: distanceFromLimit)
  }

  public func tone(distanceFromLimit: Double) { perform(gate.tone(distanceFromLimit: distanceFromLimit, at: now())) }

  public func textureChanged() { perform(gate.textureChanged(at: now())) }

  private func perform(_ pattern: ThemeHapticGate.Pattern?) {
    guard let pattern else { return }
    performer.perform(pattern, performanceTime: .now)
  }
}
