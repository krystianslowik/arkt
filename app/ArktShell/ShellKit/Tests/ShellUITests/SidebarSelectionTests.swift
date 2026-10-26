import Foundation
import Testing
@testable import ShellUI

/// Sidebar multi-selection (BH-028, GS-031): Cmd-click toggles, Shift-click selects a contiguous range from the
/// anchor; the current row seeds the selection. Plus the bulk normalization that keeps Split View panes whole.
@MainActor
struct SidebarSelectionTests {
  private let rows = (0..<5).map { _ in NodeID() }

  @Test func commandClickAddsTheCurrentRowAndTheClickedRow() {
    var selection = SidebarSelection()
    selection.toggle(rows[2], seed: rows[0])
    #expect(selection.nodes == [rows[0], rows[2]])
    #expect(selection.anchor == rows[2])
  }

  @Test func commandClickOnASelectedRowRemovesIt() {
    var selection = SidebarSelection()
    selection.toggle(rows[2], seed: rows[0])
    selection.toggle(rows[3], seed: rows[0])
    selection.toggle(rows[2], seed: rows[0])
    #expect(selection.nodes == [rows[0], rows[3]])
  }

  @Test func commandClickOnTheCurrentRowWithNothingSelectedSelectsOnlyIt() {
    var selection = SidebarSelection()
    selection.toggle(rows[1], seed: rows[1])
    #expect(selection.nodes == [rows[1]])
  }

  @Test func shiftClickSelectsTheRangeFromTheCurrentRow() {
    var selection = SidebarSelection()
    selection.extend(to: rows[3], seed: rows[1], order: rows)
    #expect(selection.nodes == [rows[1], rows[2], rows[3]])
    #expect(selection.anchor == rows[1])
  }

  /// A second Shift-click moves the range end and keeps the anchor (Finder's rule).
  @Test func aSecondShiftClickReplacesTheRangeFromTheSameAnchor() {
    var selection = SidebarSelection()
    selection.extend(to: rows[3], seed: rows[1], order: rows)
    selection.extend(to: rows[0], seed: rows[4], order: rows)
    #expect(selection.nodes == [rows[0], rows[1]])
    #expect(selection.anchor == rows[1])
  }

  @Test func shiftClickWorksUpwardAndKeepsRowOrder() {
    var selection = SidebarSelection()
    selection.extend(to: rows[0], seed: rows[2], order: rows)
    #expect(selection.nodes == [rows[0], rows[1], rows[2]])
  }

  @Test func shiftClickAfterCommandClickRangesFromTheLastCommandClickedRow() {
    var selection = SidebarSelection()
    selection.toggle(rows[3], seed: rows[0])
    selection.extend(to: rows[4], seed: rows[0], order: rows)
    #expect(selection.nodes == [rows[3], rows[4]])
  }

  @Test func retainDropsRowsThatLeft() {
    var selection = SidebarSelection()
    selection.extend(to: rows[3], seed: rows[0], order: rows)
    selection.retain { $0 != rows[1] && $0 != rows[0] }
    #expect(selection.nodes == [rows[2], rows[3]])
    #expect(selection.anchor == nil, "the anchor left with its row")
  }

  @Test func orderedSortsByRowOrder() {
    var selection = SidebarSelection()
    selection.toggle(rows[4], seed: nil)
    selection.toggle(rows[1], seed: nil)
    #expect(selection.ordered(by: rows) == [rows[1], rows[4]])
  }

  // MARK: Bulk normalization (Split View panes stay whole)

  @Test func panesResolveToTheirSplitAndFoldersAreDropped() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let url = URL(string: "https://example.com")!
    let tab = sidebar.addTab(url: url, title: "T", in: .today(space))
    let split = sidebar.addSplit(in: .today(space))
    let left = sidebar.addTab(url: url, title: "L", in: .split(split))
    let right = sidebar.addTab(url: url, title: "R", in: .split(split))
    let folder = sidebar.addFolder(title: "F", in: .pinned(space))
    #expect(SidebarSelection.bulkTargets([left, tab, right, split, folder], in: sidebar) == [split, tab])
  }
}
