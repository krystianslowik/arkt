import Synchronization

/// GPU milliseconds of completed command buffers, written from Metal's completion queue: the last frame, the run
/// of consecutive frames over `budgetMilliseconds` (the particle field's fallback trigger) and up to 4,096 samples
/// for budgets and tests. Shared by the Metal renderers (the particle field, the Space theme texture).
final class GPUFrameTimes: Sendable {
  let budgetMilliseconds: Double
  private let state = Mutex<(last: Double, overBudget: Int, samples: [Double])>((0, 0, []))

  init(budgetMilliseconds: Double) {
    self.budgetMilliseconds = budgetMilliseconds
  }

  func record(_ milliseconds: Double) {
    let budget = budgetMilliseconds
    state.withLock {
      $0.last = milliseconds
      $0.overBudget = milliseconds > budget ? $0.overBudget + 1 : 0
      if $0.samples.count < 4_096 { $0.samples.append(milliseconds) }
    }
  }

  /// Consecutive frames over the budget.
  var consecutiveOverBudget: Int { state.withLock { $0.overBudget } }
  var samples: [Double] { state.withLock { $0.samples } }
  func reset() { state.withLock { $0 = (0, 0, []) } }
}
