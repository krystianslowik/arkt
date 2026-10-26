import CoreGraphics
import Motion

/// One animated scalar of a Peek. Everything the Peek animates is a layer transform, an opacity or the card mask
/// (`expand`); nothing changes a view's frame while it moves.
public enum PeekChannel: Int, CaseIterable, Sendable {
  /// Card translation in points from its frame (down and right positive).
  case cardX, cardY
  case cardScale, cardOpacity
  /// Scrim opacity factor over the token's alpha, 0...1.
  case scrim
  /// The source card's scale (1, or `PeekMotion.recededScale` under a Peek).
  case recede
  /// Controls and grabber, 0 (gone) ... 1 (shown); the controls also slide in from the card by `controlSlide`.
  case controls, grabber
  /// The card mask from the Peek frame (0) to the frame it expands into (1): Open as Tab, Add to Split View.
  case expand

  /// Opacities, factors and progress run in thousandths, so SpringRun's point thresholds (a quarter point, two
  /// points a second) mean a quarter of a thousandth.
  var springScale: Double {
    switch self {
    case .cardX, .cardY: 1
    default: 1000
    }
  }
}

/// The values of every channel at one moment.
public struct PeekScene: Equatable, Sendable {
  private var values: [Double]

  public init(_ values: [PeekChannel: Double] = [:]) {
    self.values = PeekChannel.allCases.map { values[$0] ?? PeekScene.restValue($0) }
  }

  public subscript(_ channel: PeekChannel) -> Double {
    get { values[channel.rawValue] }
    set { values[channel.rawValue] = newValue }
  }

  public func with(_ channel: PeekChannel, _ value: Double) -> PeekScene {
    var copy = self
    copy[channel] = value
    return copy
  }

  /// A Peek at rest over a receded source.
  public static let rest = PeekScene()

  private static func restValue(_ channel: PeekChannel) -> Double {
    switch channel {
    case .cardX, .cardY, .expand: 0
    case .recede: PeekMotion.recededScale
    case .cardScale, .cardOpacity, .scrim, .controls, .grabber: 1
    }
  }
}

/// A channel heading for `value` on a spring, after `delay` seconds. A nil `value` holds the channel where it is
/// (its velocity still settles out).
public struct PeekTarget: Equatable, Sendable {
  public var channel: PeekChannel
  public var value: Double?
  public var parameters: SpringParameters
  public var delay: Double
  /// Replaces the carried velocity (points or units per second): a release velocity from the pointer.
  public var velocity: Double?

  public init(_ channel: PeekChannel, _ value: Double?, _ parameters: SpringParameters, delay: Double = 0,
              velocity: Double? = nil) {
    self.channel = channel; self.value = value; self.parameters = parameters; self.delay = delay
    self.velocity = velocity
  }
}

public enum PeekTransition: Equatable, Sendable {
  /// From `PeekMotion.openStart` to rest.
  case open
  /// The Close control or the scrim: back towards the link (`linkOffset`: the link point from the card's center).
  case close(linkOffset: CGVector)
  /// Esc and Cmd-W: in place, almost at once.
  case closeInPlace
  /// Open as Tab: the mask grows into the content card. Add to Split View uses it too, into the pane.
  case expand
  /// A drag released past the threshold, with the pointer's velocity (points per second, down positive).
  case fling(velocity: Double)
  /// A drag released short of the threshold.
  case snapBack(velocity: Double)
  /// Reduce Motion's second half of Open as Tab and Add to Split View: the card fades in at its new frame.
  case fadeIn
  /// A closed Peek comes back (BH-150, #346): from `PeekMotion.reopenStart`, in place, without the travel.
  case reopen
}

/// The Peek's motion table (docs/design/peek.md, Motion), as data.
public enum PeekMotion {
  /// The source card's scale under a Peek (decided 2026-10-25).
  public static let recededScale = 0.985
  /// The open starts this fraction of the way from the card to the clicked link.
  public static let openTravel = 0.30
  /// Points the controls slide in from the card.
  public static let controlSlide = 10.0
  /// Drag thresholds (GS-022).
  public static let dismissDistance = 120.0
  public static let dismissVelocity = 800.0
  /// Where a fling ends, below the card's frame.
  public static let flingDistance = 520.0

  static func critical(_ seconds: Double) -> SpringParameters { SpringParameters(dampingRatio: 1, response: seconds) }

  /// The resting scene; Reduce Motion never recedes the source.
  public static func restScene(reduceMotion: Bool) -> PeekScene {
    reduceMotion ? PeekScene.rest.with(.recede, 1) : .rest
  }

  /// Where the open starts: 30 % of the way to the link, scale 0.90, transparent; nothing around it yet. Reduce
  /// Motion: at the card's frame, transparent.
  public static func openStart(linkOffset: CGVector, reduceMotion: Bool) -> PeekScene {
    var scene = PeekScene([.scrim: 0, .recede: 1, .controls: 0, .grabber: 0, .cardOpacity: 0])
    if !reduceMotion {
      scene[.cardX] = Double(linkOffset.dx) * openTravel
      scene[.cardY] = Double(linkOffset.dy) * openTravel
      scene[.cardScale] = 0.90
    }
    return scene
  }

  /// Where a reopen starts: at the card's frame, scale 0.96, transparent; nothing around it yet. Reduce Motion: at
  /// full size, transparent.
  public static func reopenStart(reduceMotion: Bool) -> PeekScene {
    PeekScene([.scrim: 0, .recede: 1, .controls: 0, .grabber: 0, .cardOpacity: 0, .cardScale: reduceMotion ? 1 : 0.96])
  }

  public static func targets(for transition: PeekTransition, reduceMotion: Bool) -> [PeekTarget] {
    reduceMotion ? reducedTargets(transition) : fullTargets(transition)
  }

  private static func fullTargets(_ transition: PeekTransition) -> [PeekTarget] {
    let firmSlow = SpringPreset.firmSlow.parameters
    let springyFast = SpringPreset.springyFast.parameters
    switch transition {
    case .open, .fadeIn:
      return [
        PeekTarget(.cardX, 0, firmSlow), PeekTarget(.cardY, 0, firmSlow), PeekTarget(.cardScale, 1, firmSlow),
        PeekTarget(.cardOpacity, 1, critical(0.16)), PeekTarget(.scrim, 1, firmSlow),
        PeekTarget(.recede, recededScale, firmSlow),
        PeekTarget(.controls, 1, springyFast, delay: 0.07), PeekTarget(.grabber, 1, springyFast, delay: 0.11),
      ]
    case .close(let link):
      let firm = SpringPreset.firm.parameters
      return [
        PeekTarget(.cardX, Double(link.dx) * openTravel, firm), PeekTarget(.cardY, Double(link.dy) * openTravel, firm),
        PeekTarget(.cardScale, 0.92, firm), PeekTarget(.cardOpacity, 0, critical(0.12)),
      ] + dismissChrome(firm)
    case .closeInPlace:
      let fast = SpringPreset.firmFast.parameters
      return [
        PeekTarget(.cardX, nil, fast), PeekTarget(.cardY, nil, fast), PeekTarget(.cardScale, 0.97, fast),
        PeekTarget(.cardOpacity, 0, fast),
      ] + dismissChrome(fast)
    case .expand:
      return [
        PeekTarget(.expand, 1, firmSlow), PeekTarget(.cardX, 0, firmSlow), PeekTarget(.cardY, 0, firmSlow),
        PeekTarget(.cardScale, 1, firmSlow), PeekTarget(.cardOpacity, 1, critical(0.16)),
        PeekTarget(.scrim, 0, firmSlow), PeekTarget(.recede, 1, firmSlow),
        PeekTarget(.controls, 0, springyFast), PeekTarget(.grabber, 0, springyFast),
      ]
    case .reopen:
      let firm = SpringPreset.firm.parameters
      return [
        PeekTarget(.cardScale, 1, firm), PeekTarget(.cardOpacity, 1, critical(0.16)), PeekTarget(.scrim, 1, firm),
        PeekTarget(.recede, recededScale, firm),
        PeekTarget(.controls, 1, springyFast, delay: 0.06), PeekTarget(.grabber, 1, springyFast, delay: 0.09),
      ]
    case .fling(let velocity):
      let firm = SpringPreset.firm.parameters
      return [
        PeekTarget(.cardY, flingDistance, firm, velocity: velocity), PeekTarget(.cardX, nil, firm),
        PeekTarget(.cardScale, 0.90, firm), PeekTarget(.cardOpacity, 0, critical(0.12)),
      ] + dismissChrome(firm)
    case .snapBack(let velocity):
      let springy = SpringPreset.springy.parameters
      return [
        PeekTarget(.cardY, 0, springy, velocity: velocity), PeekTarget(.cardX, 0, springy),
        PeekTarget(.cardScale, 1, springy), PeekTarget(.cardOpacity, 1, springy),
        PeekTarget(.scrim, 1, springy), PeekTarget(.controls, 1, springyFast), PeekTarget(.grabber, 1, springyFast),
      ]
    }
  }

  /// Scrim out, source back to full size, controls out first.
  private static func dismissChrome(_ parameters: SpringParameters) -> [PeekTarget] {
    [
      PeekTarget(.scrim, 0, parameters), PeekTarget(.recede, 1, parameters),
      PeekTarget(.controls, 0, SpringPreset.springyFast.parameters),
      PeekTarget(.grabber, 0, SpringPreset.springyFast.parameters),
    ]
  }

  /// Fades only: no travel, no scale, no recede.
  private static func reducedTargets(_ transition: PeekTransition) -> [PeekTarget] {
    let fadeIn = critical(0.20)
    let fadeOut = critical(0.12)
    switch transition {
    case .open, .fadeIn, .reopen:
      return [
        PeekTarget(.cardOpacity, 1, fadeIn), PeekTarget(.scrim, 1, fadeIn), PeekTarget(.controls, 1, fadeIn),
        PeekTarget(.grabber, 1, fadeIn),
      ]
    case .close, .closeInPlace, .fling, .expand:
      return [
        PeekTarget(.cardOpacity, 0, fadeOut), PeekTarget(.scrim, 0, fadeOut), PeekTarget(.controls, 0, fadeOut),
        PeekTarget(.grabber, 0, fadeOut),
      ]
    case .snapBack:
      let firm = SpringPreset.firm.parameters
      return [
        PeekTarget(.cardY, 0, firm), PeekTarget(.cardX, 0, firm), PeekTarget(.cardScale, 1, firm),
        PeekTarget(.scrim, 1, firm), PeekTarget(.controls, 1, fadeIn), PeekTarget(.grabber, 1, fadeIn),
      ]
    }
  }

  // MARK: Drag (GS-022)

  /// Direct manipulation at `offset` points below the card's frame (negative: above). Down, the card scales towards
  /// 0.94 and the scrim towards 25 % at 300 pt, and the controls and grabber are gone by 60 pt. Up, the card moves
  /// with resistance (offset to the power of 0.7). Reduce Motion keeps the scale.
  public static func dragScene(offset: Double, reduceMotion: Bool) -> PeekScene {
    var scene = restScene(reduceMotion: reduceMotion)
    guard offset > 0 else {
      scene[.cardY] = -pow(-offset, 0.7)
      return scene
    }
    let progress = min(offset, 300) / 300
    scene[.cardY] = offset
    if !reduceMotion { scene[.cardScale] = 1 - 0.06 * progress }
    scene[.scrim] = 1 - 0.75 * progress
    let chrome = max(0, 1 - offset / 60)
    scene[.controls] = chrome
    scene[.grabber] = chrome
    return scene
  }

  /// A release past 120 pt or faster than 800 pt/s downward dismisses.
  public static func releaseDismisses(offset: Double, velocity: Double) -> Bool {
    offset > dismissDistance || velocity > dismissVelocity
  }
}

// MARK: - Springs

/// Every Peek channel as an interruptible spring: a new target starts from the channel's current value and
/// velocity, never from rest, so any transition can take over from any other mid-flight. Pure: time is passed in.
public struct PeekSpringSet: Sendable {
  private struct Channel: Sendable {
    /// Value in spring units (`springScale`) while no run is set, else the run's target.
    var value: Double
    /// The same value in channel units, exact, for a settled channel.
    var goal: Double
    var run: SpringRun?
  }

  private var channels: [Channel]

  public init(scene: PeekScene) {
    channels = PeekChannel.allCases.map { Channel(value: scene[$0] * $0.springScale, goal: scene[$0], run: nil) }
  }

  /// Sets every channel to `scene` at once, dropping the runs (a drag frame, a jump).
  public mutating func jump(to scene: PeekScene) {
    self = PeekSpringSet(scene: scene)
  }

  /// Retargets the channels named in `targets` at time `t`.
  public mutating func apply(_ targets: [PeekTarget], at t: Double) {
    for target in targets { retarget(target, at: t) }
  }

  private mutating func retarget(_ target: PeekTarget, at t: Double) {
    let channel = target.channel
    let scale = channel.springScale
    let (value, carried) = state(of: channel, at: t)
    let goal = target.value.map { $0 * scale } ?? value
    let velocity = target.velocity.map { $0 * scale } ?? carried
    channels[channel.rawValue].run = SpringRun(from: value, to: goal, initialVelocity: velocity,
                                               parameters: target.parameters, start: t + target.delay)
    channels[channel.rawValue].value = goal
    channels[channel.rawValue].goal = target.value ?? value / scale
  }

  /// Value and velocity in spring units. Before a delayed run starts, the channel holds still.
  private func state(of channel: PeekChannel, at t: Double) -> (Double, Double) {
    let entry = channels[channel.rawValue]
    guard let run = entry.run else { return (entry.value, 0) }
    if t < run.start { return (run.from, 0) }
    let state = run.interrupt(at: t)
    return run.frame(at: t).done ? (run.to, 0) : (state.value, state.velocity)
  }

  public func scene(at t: Double) -> PeekScene {
    var scene = PeekScene()
    for channel in PeekChannel.allCases {
      let entry = channels[channel.rawValue]
      let settled = entry.run.map { $0.frame(at: t).done } ?? true
      scene[channel] = settled ? entry.goal : state(of: channel, at: t).0 / channel.springScale
    }
    return scene
  }

  /// Points (or units) per second.
  public func velocity(of channel: PeekChannel, at t: Double) -> Double {
    state(of: channel, at: t).1 / channel.springScale
  }

  public func isSettled(at t: Double) -> Bool {
    channels.allSatisfy { entry in entry.run.map { $0.frame(at: t).done } ?? true }
  }
}
