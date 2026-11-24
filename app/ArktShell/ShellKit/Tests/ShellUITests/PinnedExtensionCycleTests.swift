import Testing
@testable import ShellUI

/// Cmd-E (KB-047, #599): while Command is held, each tap names the next pinned extension in pin order, wrapping.
struct PinnedExtensionCycleTests {
  @Test func `taps go through the pinned extensions in pin order and wrap`() {
    var cycle = PinnedExtensionCycle()
    let pinned = ["c", "a", "b"]
    #expect(!cycle.isRunning)
    #expect(cycle.next(in: pinned) == "c")
    #expect(cycle.isRunning)
    #expect(cycle.next(in: pinned) == "a")
    #expect(cycle.next(in: pinned) == "b")
    #expect(cycle.next(in: pinned) == "c")
  }

  @Test func `with none pinned a tap names nothing and starts no cycle`() {
    var cycle = PinnedExtensionCycle()
    #expect(cycle.next(in: []) == nil)
    #expect(!cycle.isRunning)
  }

  @Test func `releasing Command ends the cycle so the next hold starts at the first`() {
    var cycle = PinnedExtensionCycle()
    _ = cycle.next(in: ["a", "b", "c"])
    _ = cycle.next(in: ["a", "b", "c"])
    cycle.end()
    #expect(!cycle.isRunning)
    #expect(cycle.next(in: ["a", "b", "c"]) == "a")
  }

  @Test func `the order is read on every tap, so a pin change while held is followed`() {
    var cycle = PinnedExtensionCycle()
    #expect(cycle.next(in: ["a", "b", "c"]) == "a")
    #expect(cycle.next(in: ["a", "c"]) == "c", "b was unpinned: the one after a now")
    #expect(cycle.next(in: ["a", "b"]) == "a", "c was unpinned while open: start again at the first")
  }

  @Test func `one pinned extension is named on every tap`() {
    var cycle = PinnedExtensionCycle()
    #expect(cycle.next(in: ["a"]) == "a")
    #expect(cycle.next(in: ["a"]) == "a")
  }
}
