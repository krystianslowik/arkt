/// Pane focus math for the split shortcuts (BH-128).
public enum SplitFocus {
  /// Ctrl-Shift-N (KB-072): the index of pane `number` (1-based), or nil when the split has fewer panes.
  public static func pane(number: Int, count: Int) -> Int? {
    number >= 1 && number <= count ? number - 1 : nil
  }

  /// The next pane, wrapping from the last to the first (KB-073). An index out of range is clamped first.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-06)
  public static func next(from index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return (clamped(index, count: count) + 1) % count
  }

  /// The previous pane, wrapping from the first to the last (KB-073). An index out of range is clamped first.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-06)
  public static func previous(from index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return (clamped(index, count: count) - 1 + count) % count
  }

  private static func clamped(_ index: Int, count: Int) -> Int {
    min(max(index, 0), count - 1)
  }
}
