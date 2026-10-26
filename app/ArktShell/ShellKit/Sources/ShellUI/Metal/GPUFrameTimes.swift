import Synchronization

/// Which of the last 60 frames went over a GPU-time budget: a sliding window, so a sustained alternating overload
/// trips the particle field's fallback tier while a lone spike does not (onboarding spec, section 7.4, #375).
/// Bit 0 is the newest frame.
struct GPUBudgetWindow: Equatable, Sendable {
  static let frames = 60
  static let tripCount = 30
  private static let mask: UInt64 = (1 << UInt64(frames)) - 1

  let budgetMilliseconds: Double
  private var bits: UInt64 = 0

  init(budgetMilliseconds: Double = 2) {
    self.budgetMilliseconds = budgetMilliseconds
  }

  mutating func record(_ milliseconds: Double) {
    bits = (bits << 1 | (milliseconds > budgetMilliseconds ? 1 : 0)) & Self.mask
  }

  /// Frames over budget among the last 60.
  var overBudget: Int { bits.nonzeroBitCount }
  /// 30 of the last 60 frames over budget.
  var tripsFallback: Bool { overBudget >= Self.tripCount }
}

/// GPU milliseconds of completed command buffers, written from Metal's completion queue: the last frame, the
/// sliding window of frames over `budgetMilliseconds` (the particle field's fallback trigger) and up to 4,096
/// samples for budgets and tests. Shared by the Metal renderers (the particle field, the Space theme texture).
final class GPUFrameTimes: Sendable {
  let budgetMilliseconds: Double
  private let state: Mutex<(last: Double, window: GPUBudgetWindow, samples: [Double])>

  init(budgetMilliseconds: Double) {
    self.budgetMilliseconds = budgetMilliseconds
    state = Mutex((0, GPUBudgetWindow(budgetMilliseconds: budgetMilliseconds), []))
  }

  func record(_ milliseconds: Double) {
    state.withLock {
      $0.last = milliseconds
      $0.window.record(milliseconds)
      if $0.samples.count < 4_096 { $0.samples.append(milliseconds) }
    }
  }

  /// 30 of the last 60 frames went over the budget.
  var tripsFallback: Bool { state.withLock { $0.window.tripsFallback } }
  var samples: [Double] { state.withLock { $0.samples } }
  func reset() {
    let budget = budgetMilliseconds
    state.withLock { $0 = (0, GPUBudgetWindow(budgetMilliseconds: budget), []) }
  }
}
