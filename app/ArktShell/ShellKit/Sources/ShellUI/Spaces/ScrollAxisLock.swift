import CoreGraphics

/// Decides once per trackpad gesture whether it is horizontal (Space paging) or vertical (outline
/// scrolling). Events are held back until the gesture has moved `threshold` points, then released in
/// order along the decided axis. A gesture that ends before moving counts as vertical. Diagonal
/// travel is biased toward vertical (outline scrolling is the common case): horizontal needs
/// `horizontalBias` times more horizontal than vertical travel.
struct ScrollAxisLock<Event> {
  enum Axis: Equatable { case undecided, horizontal, vertical }

  static var threshold: CGFloat { 7 }
  static var horizontalBias: CGFloat { 1.5 }

  private(set) var axis = Axis.undecided
  private var pending: [Event] = []
  private var travelX: CGFloat = 0
  private var travelY: CGFloat = 0

  /// Feeds one phased gesture event. Returns the events to route now along `axis` (empty while undecided).
  mutating func feed(_ event: Event, dx: CGFloat, dy: CGFloat, starts: Bool, ends: Bool) -> [Event] {
    // `mayBegin` then `began` is one gesture: an undecided lock keeps buffering across both.
    if starts && axis != .undecided { axis = .undecided; pending = []; travelX = 0; travelY = 0 }
    guard axis == .undecided else { return [event] }
    pending.append(event)
    travelX += abs(dx); travelY += abs(dy)
    if travelX + travelY >= Self.threshold {
      axis = travelX > travelY * Self.horizontalBias ? .horizontal : .vertical
    } else if ends {
      axis = .vertical
    } else {
      return []
    }
    defer { pending = [] }
    return pending
  }
}
