import simd

/// One mote's target in a formation, laid out for the compute kernel (`ParticleShaders`): six float4, 96 bytes.
/// Built on the CPU when a step appears; the kernel evaluates paths and springs every frame.
struct ParticleTarget: Equatable, Sendable {
  /// x, y (points, top-left origin), drift amplitude (points), path kind (`ParticlePath.Kind` raw value).
  var target: SIMD4<Float>
  /// Path parameters a, b, c, d.
  var pathA: SIMD4<Float>
  /// Path parameters e, f, g, h.
  var pathB: SIMD4<Float>
  /// Colour and the formation's alpha for this mote.
  var color: SIMD4<Float>
  /// Size (points), start time (field seconds), spring stiffness k, spring damping c.
  var motion: SIMD4<Float>
  /// Path rate (cycles a second), phase (0...1), fade along the path (1) or not (0), formation epoch.
  var extra: SIMD4<Float>

  static let zero = ParticleTarget(target: .zero, pathA: .zero, pathB: .zero, color: .zero, motion: .zero,
                                   extra: .zero)
}

/// A mote's live state, read and written by the kernel: position and velocity, colour, size and the epoch of the
/// formation it has dissolved into under Reduce Motion.
struct ParticleState: Equatable, Sendable {
  var positionVelocity: SIMD4<Float>
  var color: SIMD4<Float>
  /// size, seed (0...1), epoch, unused.
  var sizeSeed: SIMD4<Float>
}

/// Per-frame values for the kernel and the draw.
struct ParticleUniforms: Equatable, Sendable {
  /// Field time (seconds), step dt, substeps, Reduce Motion (1 or 0).
  var time: SIMD4<Float>
  /// Viewport width and height (points), backing scale, field opacity.
  var view: SIMD4<Float>
  /// Count, colour easing rate, the clock paths use under Reduce Motion, additive blending (1 or 0).
  var config: SIMD4<Float>
}

/// How a target moves (P7, P8): at rest with drift, or along a path the kernel evaluates with the field clock.
enum ParticlePath: Equatable, Sendable {
  case rest
  /// A quadratic curve from (x0, y0) to (x1, y1) whose control point sits `bend` below the midpoint.
  case curve(x0: Float, y0: Float, x1: Float, y1: Float, bend: Float)
  /// An ellipse around (cx, cy), radii (rx, ry), tilted, with a fixed offset (orbits, rings).
  case ellipse(cx: Float, cy: Float, rx: Float, ry: Float, tilt: Float, offsetX: Float, offsetY: Float)
  /// Rising from below the window to above it at x (Make it yours's margins).
  case rising(x: Float, height: Float)
  /// A room of tip 3: (x, y) at page 0, `room` its index; the rooms pan one room at +1.4 s, again at +3.0 s and back
  /// to the second at +4.6 s from `start`.
  case pan(x: Float, y: Float, room: Float, start: Float)

  enum Kind: Float { case rest = 0, curve = 1, ellipse = 2, rising = 3, pan = 4 }

  var kind: Kind {
    switch self {
    case .rest: .rest
    case .curve: .curve
    case .ellipse: .ellipse
    case .rising: .rising
    case .pan: .pan
    }
  }

  var parameters: (SIMD4<Float>, SIMD4<Float>) {
    switch self {
    case .rest: (.zero, .zero)
    case let .curve(x0, y0, x1, y1, bend): (SIMD4(x0, y0, x1, y1), SIMD4(bend, 0, 0, 0))
    case let .ellipse(cx, cy, rx, ry, tilt, ox, oy): (SIMD4(cx, cy, rx, ry), SIMD4(tilt, ox, oy, 0))
    case let .rising(x, height): (SIMD4(x, height, 0, 0), .zero)
    case let .pan(x, y, room, start): (SIMD4(x, y, room, start), .zero)
    }
  }

  /// The path's point at phase `u` and field clock `t`, the same as the kernel's (`ParticleShaders.pathPoint`).
  func point(phase u: Float, clock t: Float, settled: Bool = false) -> SIMD2<Float> {
    switch self {
    case .rest:
      return .zero
    case let .curve(x0, y0, x1, y1, bend):
      let mx = (x0 + x1) / 2, my = (y0 + y1) / 2 + bend
      let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u
      return SIMD2(a * x0 + b * mx + c * x1, a * y0 + b * my + c * y1)
    case let .ellipse(cx, cy, rx, ry, tilt, ox, oy):
      let angle = u * 2 * .pi
      let ex = cos(angle) * rx, ey = sin(angle) * ry
      return SIMD2(cx + ex * cos(tilt) - ey * sin(tilt) + ox, cy + ex * sin(tilt) + ey * cos(tilt) + oy)
    case let .rising(x, height):
      return SIMD2(x + sin(u * 9 + x) * 6, height + 20 - u * (height + 40))
    case let .pan(x, y, room, start):
      let page = settled ? 1 : Self.pan(t - start)
      return SIMD2(x + (room - page) * 168, y)
    }
  }

  /// P8: the rooms' page at `t` seconds after tip 3 appears, an exponential ease at 4/s between rests.
  static func pan(_ t: Float) -> Float {
    func ease(_ a: Float) -> Float { 1 - exp(-4 * max(0, a)) }
    if t < 1.4 { return 0 }
    if t < 3.0 { return ease(t - 1.4) }
    if t < 4.6 { return 1 + ease(t - 3.0) }
    return 2 - ease(t - 4.6)
  }
}
