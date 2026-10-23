/// Display-link frame intervals for one interaction. `hitchThreshold` (8.6 ms) is this track's gate:
/// one 120 Hz refresh plus slack. `designBudget` (8.34 ms) is design section 5's 8.3 ms read as one
/// 120 Hz frame plus rounding, since a perfect frame is 8.333 ms.
/// The first recorded interval is kept apart as `leadInInterval`: it spans the display link's start-up
/// (link start to its first vsyncs) rather than a frame of the interaction, so it is reported but not
/// counted in `frameCount`, `intervals` or either gate.
public struct FrameStats: Sendable, Equatable {
  public let hitchThreshold: Double
  public let designBudget: Double
  public private(set) var frameCount = 0
  public private(set) var hitchCount = 0
  public private(set) var overBudgetCount = 0
  public private(set) var maxInterval = 0.0
  public private(set) var intervals: [Double] = []
  public private(set) var leadInInterval: Double?

  public init(hitchThreshold: Double = 0.0086, designBudget: Double = 0.00834) {
    self.hitchThreshold = hitchThreshold; self.designBudget = designBudget
  }

  public mutating func record(interval: Double) {
    guard leadInInterval != nil else { leadInInterval = interval; return }
    frameCount += 1
    intervals.append(interval)
    if interval > hitchThreshold { hitchCount += 1 }
    if interval > designBudget { overBudgetCount += 1 }
    maxInterval = max(maxInterval, interval)
  }

  public var overBudgetRatio: Double { frameCount == 0 ? 0 : Double(overBudgetCount) / Double(frameCount) }

  public var p99: Double {
    guard !intervals.isEmpty else { return 0 }
    let sorted = intervals.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
  }
}
