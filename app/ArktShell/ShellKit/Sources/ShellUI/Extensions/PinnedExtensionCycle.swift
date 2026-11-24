/// Cmd-E (KB-047, #599): hold Command and tap E; each tap opens the next pinned extension's popup in pin order,
/// wrapping. The position lasts while Command stays down, so the next hold starts again at the first pinned extension.
/// It remembers the action it opened last, not an index, and reads the pin order on every tap, so a pin change while
/// Command is held is followed.
struct PinnedExtensionCycle: Equatable, Sendable {
  /// The action the running hold opened last; nil when no hold runs.
  private(set) var last: String?

  var isRunning: Bool { last != nil }

  /// The action to open for a tap: the one after the last opened in `pinned` (action ids in pin order), wrapping, or
  /// the first when no hold runs or the last one is no longer pinned. Nil, and no cycle, when none is pinned.
  mutating func next(in pinned: [String]) -> String? {
    guard !pinned.isEmpty else {
      last = nil
      return nil
    }
    let index = last.flatMap { pinned.firstIndex(of: $0) }.map { ($0 + 1) % pinned.count } ?? 0
    last = pinned[index]
    return last
  }

  /// Command went up.
  mutating func end() { last = nil }
}
