import QuartzCore
import Motion

/// One animated scalar of a Little Arkt window's content. The window never animates its frame: every transition moves
/// the content's root layer by transform and opacity only (docs/design/little-arkt.md, Motion).
public enum LittleArktChannel: Int, SpringChannel {
  /// Points above the resting position (the appear starts 10 higher).
  case lift
  /// Scale about the top center.
  case scale
  case opacity

  public var springScale: Double { self == .lift ? 1 : 1000 }
  public var restValue: Double { self == .lift ? 0 : 1 }
}

public typealias LittleArktScene = ChannelScene<LittleArktChannel>
public typealias LittleArktTarget = ChannelTarget<LittleArktChannel>
public typealias LittleArktSpringSet = SpringChannelSet<LittleArktChannel>

public enum LittleArktTransition: Equatable, Sendable {
  /// A new window: from `LittleArktMotion.appearStart` to rest.
  case appear
  /// The same link again: the window comes forward and swells (BH-134).
  case nudge
  /// Cmd-W or the close button: in place, almost at once.
  case close
  /// The page closed its popup (`window.close()`), or the page moved into a Space (Open in, no flight).
  case fadeOut
}

/// The motion table (docs/design/little-arkt.md, Motion), as data.
public enum LittleArktMotion {
  /// The nudge's kick on the scale, per second: a 1 to 2 % swell on `springy`.
  public static let nudgeKick = 0.45
  /// Reduce Motion's nudge: an opacity kick on a critical 0.20 s spring that dips the frame to about 60 %.
  public static let reducedNudgeKick = -34.0

  static func critical(_ seconds: Double) -> SpringParameters { SpringParameters(dampingRatio: 1, response: seconds) }

  /// Where the appear starts: 10 pt higher, scale 0.94 from the top center, transparent. Reduce Motion: in place.
  public static func appearStart(reduceMotion: Bool) -> LittleArktScene {
    reduceMotion ? LittleArktScene([.opacity: 0]) : LittleArktScene([.lift: 10, .scale: 0.94, .opacity: 0])
  }

  public static func targets(for transition: LittleArktTransition, reduceMotion: Bool) -> [LittleArktTarget] {
    reduceMotion ? reducedTargets(transition) : fullTargets(transition)
  }

  private static func fullTargets(_ transition: LittleArktTransition) -> [LittleArktTarget] {
    switch transition {
    case .appear:
      let firm = SpringPreset.firm.parameters
      return [
        LittleArktTarget(.lift, 0, firm), LittleArktTarget(.scale, 1, firm),
        LittleArktTarget(.opacity, 1, critical(0.16)),
      ]
    case .nudge:
      return [
        LittleArktTarget(.scale, 1, SpringPreset.springy.parameters, velocity: nudgeKick),
        LittleArktTarget(.lift, 0, SpringPreset.springy.parameters), LittleArktTarget(.opacity, 1, critical(0.16)),
      ]
    case .close:
      let fast = SpringPreset.firmFast.parameters
      return [LittleArktTarget(.scale, 0.97, fast), LittleArktTarget(.opacity, 0, fast)]
    case .fadeOut:
      return [LittleArktTarget(.opacity, 0, critical(0.12))]
    }
  }

  /// Fades only: no lift, no scale.
  private static func reducedTargets(_ transition: LittleArktTransition) -> [LittleArktTarget] {
    switch transition {
    case .appear:
      return [LittleArktTarget(.opacity, 1, critical(0.20))]
    case .nudge:
      return [LittleArktTarget(.opacity, 1, critical(0.20), velocity: reducedNudgeKick)]
    case .close, .fadeOut:
      return [LittleArktTarget(.opacity, 0, critical(0.12))]
    }
  }

  /// The content layer's transform for `scene`: scale about the top center of `bounds`, then the lift. For a
  /// layer-backed view's layer, whose anchor point AppKit keeps at (0, 0) and whose coordinates are not flipped (y up),
  /// so a lift moves the content up.
  public static func transform(for scene: LittleArktScene, in bounds: CGRect) -> CATransform3D {
    let scale = scene[.scale]
    let anchorY = bounds.maxY
    var transform = CATransform3DMakeTranslation(0, anchorY * (1 - scale) + scene[.lift], 0)
    transform = CATransform3DTranslate(transform, bounds.midX * (1 - scale), 0, 0)
    return CATransform3DScale(transform, scale, scale, 1)
  }
}
