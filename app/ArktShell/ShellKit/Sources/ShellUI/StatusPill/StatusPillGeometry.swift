import CoreGraphics
import Motion

/// Which bottom corner of the card the pill sits in.
enum StatusPillCorner: Equatable, Sendable {
  case leading, trailing

  var other: StatusPillCorner { self == .leading ? .trailing : .leading }
}

/// Where the status pill goes in a card and when it gets out of the pointer's way (design/status-pill, direction A).
/// The card is not flipped: the bottom edge is `minY`.
enum StatusPillGeometry {
  static let height: CGFloat = 26
  /// From the card's bottom and its leading or trailing edge.
  static let inset: CGFloat = 12
  /// The pill's own limit.
  static let maxWidth: CGFloat = 480
  /// Never wider than this share of the card, so it cannot reach into the other corner's area.
  static let maxCardFraction: CGFloat = 0.62
  /// The pointer this close to the pill sends it to the other corner.
  static let avoidDistance: CGFloat = 28

  static func maxWidth(cardWidth: CGFloat) -> CGFloat {
    max(0, min(maxWidth, (cardWidth * maxCardFraction).rounded(.down)))
  }

  static func frame(corner: StatusPillCorner, width: CGFloat, in bounds: CGRect) -> CGRect {
    let x = corner == .leading ? bounds.minX + inset : bounds.maxX - inset - width
    return CGRect(x: x, y: bounds.minY + inset, width: width, height: height)
  }

  /// Zero inside the rectangle.
  static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return hypot(dx, dy)
  }

  /// The corner the pill should be in: the other one when the pointer is within `avoidDistance` of it here, unless
  /// the pointer is no farther from the other one (a card too small to hold both apart), then it stays.
  static func corner(current: StatusPillCorner, pointer: CGPoint?, width: CGFloat, in bounds: CGRect)
    -> StatusPillCorner {
    guard let pointer else { return current }
    let here = distance(from: pointer, to: frame(corner: current, width: width, in: bounds))
    guard here < avoidDistance else { return current }
    let there = distance(from: pointer, to: frame(corner: current.other, width: width, in: bounds))
    return there > here ? current.other : current
  }
}

/// The corner crossing as data (design/status-pill, "Motion"): a `firmFast` spring on the horizontal offset from the
/// new resting place to where the pill was. A new crossing starts from the offset and speed the last one had reached,
/// so a pointer that chases the pill never makes it jump.
struct StatusPillSlide {
  private var run: SpringRun?

  var isActive: Bool { run != nil }

  /// The horizontal offset to present at `time`; zero at rest.
  mutating func offset(at time: Double) -> Double {
    guard let current = run else { return 0 }
    let frame = current.frame(at: time)
    if frame.done { run = nil }
    return frame.value
  }

  /// Starts a crossing from `offset` points away from rest, carrying over the speed of a crossing in flight.
  mutating func begin(from offset: Double, at time: Double) {
    let velocity = run?.interrupt(at: time).velocity ?? 0
    run = SpringRun(from: offset, to: 0, initialVelocity: velocity, parameters: SpringPreset.firmFast.parameters,
                    start: time, threshold: 0.25)
  }

  mutating func cancel() { run = nil }
}
