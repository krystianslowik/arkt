/// Selection moves in the command bar results. Pure, so it is unit-tested.
/// Parity: KB-085 / RT-08. Arc's wrap and paging are unverified; both rules here are [I].
enum CommandBarSelection {
  /// Up / Down (and Ctrl-P / Ctrl-N). Wraps at both ends [I]; from no selection (-1), Down picks the first
  /// row and Up the last. Nil when there are no results.
  static func step(from current: Int, by delta: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    if current < 0 || current >= count { return delta >= 0 ? 0 : count - 1 }
    return ((current + delta) % count + count) % count
  }

  /// PageUp / PageDown: moves by the visible row count and stops at the ends (no wrap) [I].
  /// From no selection (-1), a page starts at the top. Nil when there are no results.
  static func page(from current: Int, by pages: Int, count: Int,
                   pageSize: Int = CommandBarGeometry.maxVisibleRows) -> Int? {
    guard count > 0 else { return nil }
    return min(max(current + pages * pageSize, 0), count - 1)
  }
}
