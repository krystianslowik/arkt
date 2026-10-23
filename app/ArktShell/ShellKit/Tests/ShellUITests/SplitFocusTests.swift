import Testing
@testable import ShellUI

struct SplitFocusTests {
  /// Ctrl-Shift-1...4 (KB-072): pane N is index N - 1 when the split has that many panes.
  @Test(arguments: 2...4)
  func paneNumberMapsToIndexWhenPresent(count: Int) {
    for number in 1...4 {
      let expected: Int? = number <= count ? number - 1 : nil
      #expect(SplitFocus.pane(number: number, count: count) == expected)
    }
    #expect(SplitFocus.pane(number: 0, count: count) == nil)
    #expect(SplitFocus.pane(number: -1, count: count) == nil)
  }

  /// KB-073, BH-128: next and previous wrap around both ways.
  @Test func nextAndPreviousWrapAround() {
    #expect(SplitFocus.next(from: 0, count: 3) == 1)
    #expect(SplitFocus.next(from: 2, count: 3) == 0)
    #expect(SplitFocus.previous(from: 1, count: 3) == 0)
    #expect(SplitFocus.previous(from: 0, count: 3) == 2)
    #expect(SplitFocus.next(from: 3, count: 4) == 0)
    #expect(SplitFocus.previous(from: 0, count: 2) == 1)
  }

  @Test func degenerateCountsStayInRange() {
    #expect(SplitFocus.next(from: 0, count: 1) == 0)
    #expect(SplitFocus.previous(from: 0, count: 1) == 0)
    #expect(SplitFocus.next(from: 0, count: 0) == 0)
    #expect(SplitFocus.previous(from: 0, count: 0) == 0)
    // A stale index past the end (a pane just left) is clamped to the last pane first.
    #expect(SplitFocus.next(from: 7, count: 3) == 0)
    #expect(SplitFocus.previous(from: 7, count: 3) == 1)
  }
}
