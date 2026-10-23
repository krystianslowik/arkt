import Testing
@testable import ShellUI

/// Selection moves in the command bar results (KB-085, RT-08). Wrap and page size are [I].
struct CommandBarSelectionTests {
  @Test func arrowsMoveByOne() {
    #expect(CommandBarSelection.step(from: 0, by: 1, count: 3) == 1)
    #expect(CommandBarSelection.step(from: 2, by: -1, count: 3) == 1)
  }

  @Test func downFromTheLastRowWrapsToTheFirst() {
    #expect(CommandBarSelection.step(from: 2, by: 1, count: 3) == 0)
  }

  @Test func upFromTheFirstRowWrapsToTheLast() {
    #expect(CommandBarSelection.step(from: 0, by: -1, count: 3) == 2)
  }

  @Test func noSelectionStartsAtTheEnds() {
    #expect(CommandBarSelection.step(from: -1, by: 1, count: 3) == 0)
    #expect(CommandBarSelection.step(from: -1, by: -1, count: 3) == 2)
  }

  @Test func singleRowStaysPut() {
    #expect(CommandBarSelection.step(from: 0, by: 1, count: 1) == 0)
    #expect(CommandBarSelection.step(from: 0, by: -1, count: 1) == 0)
  }

  @Test func emptyResultsHaveNoSelection() {
    #expect(CommandBarSelection.step(from: -1, by: 1, count: 0) == nil)
    #expect(CommandBarSelection.page(from: -1, by: 1, count: 0) == nil)
  }

  @Test func pageMovesByTheVisibleRowCountAndClamps() {
    let size = CommandBarGeometry.maxVisibleRows
    #expect(CommandBarSelection.page(from: 0, by: 1, count: 20) == size)
    #expect(CommandBarSelection.page(from: size, by: -1, count: 20) == 0)
    #expect(CommandBarSelection.page(from: 15, by: 1, count: 20) == 19)
    #expect(CommandBarSelection.page(from: 3, by: -1, count: 20) == 0)
  }

  @Test func pageDoesNotWrap() {
    #expect(CommandBarSelection.page(from: 4, by: 1, count: 5) == 4)
    #expect(CommandBarSelection.page(from: 0, by: -1, count: 5) == 0)
  }

  @Test func pageFromNoSelectionStartsAtTheTop() {
    #expect(CommandBarSelection.page(from: -1, by: 1, count: 20) == CommandBarGeometry.maxVisibleRows - 1)
    #expect(CommandBarSelection.page(from: -1, by: -1, count: 20) == 0)
  }
}
