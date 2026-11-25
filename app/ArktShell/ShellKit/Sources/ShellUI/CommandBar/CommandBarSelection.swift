/// Selection moves in the command bar results and Little Arkt's lookup. Pure, so it is unit-tested.
enum CommandBarSelection {
  /// Little Arkt's Up / Down: wraps at both ends; from no selection (-1), Down picks the first row and Up the last.
  /// Nil when there are no results.
  static func step(from current: Int, by delta: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    if current < 0 || current >= count { return delta >= 0 ? 0 : count - 1 }
    return ((current + delta) % count + count) % count
  }

  /// The command bar's Up / Down and Ctrl-P / Ctrl-N (design/command-bar/README.md, Keyboard): a fresh press wraps
  /// from the last row to the first and back; a held key's repeat stops at the ends.
  static func move(from current: Int, by delta: Int, count: Int, isRepeat: Bool) -> Int? {
    guard count > 0 else { return nil }
    guard isRepeat, current >= 0, current < count else { return step(from: current, by: delta, count: count) }
    return min(max(current + delta, 0), count - 1)
  }

  /// Tab and Shift-Tab: the first row of the next or previous group. The literal row (no group) is a group of its
  /// own. Nil past the first or last group.
  static func groupJump<G: Equatable>(from current: Int, forward: Bool, groups: [G?]) -> Int? {
    guard !groups.isEmpty else { return nil }
    var starts: [Int] = []
    for index in groups.indices where index == 0 || groups[index] != groups[index - 1] { starts.append(index) }
    let current = min(max(current, 0), groups.count - 1)
    let own = starts.lastIndex { $0 <= current } ?? 0
    let target = own + (forward ? 1 : -1)
    return starts.indices.contains(target) ? starts[target] : nil
  }

  /// PageUp / PageDown: moves by `pageSize` rows and stops at the ends (no wrap) [I].
  /// From no selection (-1), a page starts at the top. Nil when there are no results.
  static func page(from current: Int, by pages: Int, count: Int,
                   pageSize: Int = CommandBarGeometry.pageRows) -> Int? {
    guard count > 0 else { return nil }
    return min(max(current + pages * pageSize, 0), count - 1)
  }
}
