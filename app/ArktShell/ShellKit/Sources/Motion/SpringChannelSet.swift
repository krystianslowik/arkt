import Foundation

/// One animated scalar of a component (a translation, a scale, an opacity).
public protocol SpringChannel: CaseIterable, Hashable, Sendable where AllCases == [Self] {
  /// Spring units per channel unit. `SpringRun`'s thresholds are in points (a quarter point, two points a second), so
  /// a scale or an opacity runs in thousandths (1000) and a translation in points (1).
  var springScale: Double { get }
  /// The channel's value at rest.
  var restValue: Double { get }
}

/// The values of every channel at one moment.
public struct ChannelScene<Channel: SpringChannel>: Equatable, Sendable {
  private var values: [Channel: Double]

  public init(_ values: [Channel: Double] = [:]) {
    self.values = values.filter { $0.value != $0.key.restValue }   // one spelling per scene, for ==
  }

  public subscript(_ channel: Channel) -> Double {
    get { values[channel] ?? channel.restValue }
    set { values[channel] = newValue == channel.restValue ? nil : newValue }
  }

  public func with(_ channel: Channel, _ value: Double) -> ChannelScene {
    var copy = self
    copy[channel] = value
    return copy
  }

  /// Every channel at rest.
  public static var rest: ChannelScene { ChannelScene() }
}

/// A channel heading for `value` on a spring, after `delay` seconds. A nil `value` holds the channel where it is.
/// `velocity` (channel units per second) replaces the carried velocity: a kick, or a pointer's release velocity.
public struct ChannelTarget<Channel: SpringChannel>: Equatable, Sendable {
  public var channel: Channel
  public var value: Double?
  public var parameters: SpringParameters
  public var delay: Double
  public var velocity: Double?

  public init(_ channel: Channel, _ value: Double?, _ parameters: SpringParameters, delay: Double = 0,
              velocity: Double? = nil) {
    self.channel = channel; self.value = value; self.parameters = parameters; self.delay = delay
    self.velocity = velocity
  }
}

/// Every channel as an interruptible spring: a new target starts from the channel's current value and velocity,
/// never from rest, so any transition can take over from any other mid-flight. Pure: time is passed in.
public struct SpringChannelSet<Channel: SpringChannel>: Sendable {
  private struct Entry: Sendable {
    /// Value in spring units while no run is set, else the run's target.
    var value: Double
    /// The same value in channel units, exact, for a settled channel.
    var goal: Double
    var run: SpringRun?
  }

  private var entries: [Channel: Entry] = [:]

  public init(scene: ChannelScene<Channel>) {
    for channel in Channel.allCases {
      entries[channel] = Entry(value: scene[channel] * channel.springScale, goal: scene[channel], run: nil)
    }
  }

  /// Sets every channel to `scene` at once, dropping the runs.
  public mutating func jump(to scene: ChannelScene<Channel>) {
    self = SpringChannelSet(scene: scene)
  }

  /// Retargets the channels named in `targets` at time `t`.
  public mutating func apply(_ targets: [ChannelTarget<Channel>], at t: Double) {
    for target in targets { retarget(target, at: t) }
  }

  private mutating func retarget(_ target: ChannelTarget<Channel>, at t: Double) {
    let channel = target.channel
    let scale = channel.springScale
    let (value, carried) = state(of: channel, at: t)
    let goal = target.value.map { $0 * scale } ?? value
    let velocity = target.velocity.map { $0 * scale } ?? carried
    entries[channel] = Entry(value: goal, goal: target.value ?? value / scale,
                             run: SpringRun(from: value, to: goal, initialVelocity: velocity,
                                            parameters: target.parameters, start: t + target.delay))
  }

  /// Value and velocity in spring units. Before a delayed run starts, the channel holds still.
  private func state(of channel: Channel, at t: Double) -> (Double, Double) {
    guard let entry = entries[channel] else { return (channel.restValue * channel.springScale, 0) }
    guard let run = entry.run else { return (entry.value, 0) }
    if t < run.start { return (run.from, 0) }
    let state = run.interrupt(at: t)
    return run.frame(at: t).done ? (run.to, 0) : (state.value, state.velocity)
  }

  public func scene(at t: Double) -> ChannelScene<Channel> {
    var scene = ChannelScene<Channel>()
    for channel in Channel.allCases {
      guard let entry = entries[channel] else { continue }
      let settled = entry.run.map { $0.frame(at: t).done } ?? true
      scene[channel] = settled ? entry.goal : state(of: channel, at: t).0 / channel.springScale
    }
    return scene
  }

  /// Channel units per second.
  public func velocity(of channel: Channel, at t: Double) -> Double {
    state(of: channel, at: t).1 / channel.springScale
  }

  public func isSettled(at t: Double) -> Bool {
    entries.values.allSatisfy { entry in entry.run.map { $0.frame(at: t).done } ?? true }
  }
}
