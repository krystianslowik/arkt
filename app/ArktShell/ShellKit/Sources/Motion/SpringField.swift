/// One interruptible spring per key, on a clock passed in: a dynamic counterpart of `SpringChannelSet` for motion
/// whose members come and go (the sidebar's folders, #109). Retargeting a running key starts from its current value
/// and velocity, so a reversal never jumps. Pure: time is passed in.
///
/// Values are unitless (a progress of 0...1); runs are kept in thousandths, as `SpringChannelSet` keeps a scale or an
/// opacity, so `SpringRun`'s point thresholds settle them without a visible snap.
public struct SpringField<Key: Hashable & Sendable>: Sendable {
  private static var scale: Double { 1000 }
  private var runs: [Key: SpringRun] = [:]

  public init() {}

  /// The keys with a run, settled or not.
  public var keys: Set<Key> { Set(runs.keys) }

  /// Sends `key` toward `value` from time `t`. A key with a run continues from where it is at `t`; a new key starts
  /// at `from` with no velocity.
  public mutating func retarget(_ key: Key, to value: Double, from: Double, at t: Double,
                                parameters: SpringParameters) {
    let (start, velocity) = runs[key].map { state(of: $0, at: t) } ?? (from * Self.scale, 0)
    runs[key] = SpringRun(from: start, to: value * Self.scale, initialVelocity: velocity, parameters: parameters,
                          start: t)
  }

  /// The value of `key` at `t`; nil for a key without a run.
  public func value(of key: Key, at t: Double) -> Double? {
    runs[key].map { $0.frame(at: t).value / Self.scale }
  }

  /// Units per second; 0 for a settled key or one without a run.
  public func velocity(of key: Key, at t: Double) -> Double {
    runs[key].map { state(of: $0, at: t).1 / Self.scale } ?? 0
  }

  public func target(of key: Key) -> Double? { runs[key].map { $0.to / Self.scale } }

  /// The keys whose run has settled by `t`.
  public func settledKeys(at t: Double) -> Set<Key> {
    Set(runs.filter { $0.value.frame(at: t).done }.keys)
  }

  public mutating func remove(_ key: Key) { runs[key] = nil }

  /// Value and velocity in run units; a settled run rests at its target.
  private func state(of run: SpringRun, at t: Double) -> (Double, Double) {
    let frame = run.frame(at: t)
    if frame.done { return (frame.value, 0) }
    return run.interrupt(at: t)
  }
}
