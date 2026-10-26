import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// The pure drop rules of sidebar drag and drop (#104): GS-007 pin / unpin across the divider, GS-009 onto a
/// folder, GS-010 / BH-118 onto a tab, reorder in every section, and the refusals.
struct SidebarDropResolverTests {
  /// Pinned `[p0, F (open: [f0]), p1]`, the divider, Today `[t0, S (panes a, b), t1]`.
  struct Fixture {
    let space = UUID()
    let p0 = UUID(), folder = UUID(), f0 = UUID(), p1 = UUID()
    let t0 = UUID(), split = UUID(), a = UUID(), b = UUID(), t1 = UUID()

    var rows: [SidebarDropRow] {
      [
        SidebarDropRow(node: p0, kind: .tab, location: .pinned(space), index: 0, level: 0),          // 0
        SidebarDropRow(node: folder, kind: .folder(expanded: true), location: .pinned(space), index: 1,
                       level: 0),                                                                    // 1
        SidebarDropRow(node: f0, kind: .tab, location: .folder(folder), index: 0, level: 1),         // 2
        SidebarDropRow(node: p1, kind: .tab, location: .pinned(space), index: 2, level: 0),          // 3
        SidebarDropRow(node: nil, kind: .divider, location: .today(space), index: 0, level: 0),      // 4
        SidebarDropRow(node: t0, kind: .tab, location: .today(space), index: 0, level: 0),           // 5
        SidebarDropRow(node: split, kind: .split, location: .today(space), index: 1, level: 0),      // 6
        SidebarDropRow(node: a, kind: .pane(split: split), location: .split(split), index: 0, level: 1), // 7
        SidebarDropRow(node: b, kind: .pane(split: split), location: .split(split), index: 1, level: 1), // 8
        SidebarDropRow(node: t1, kind: .tab, location: .today(space), index: 2, level: 0),           // 9
      ]
    }

    func target(row: Int?, y: CGFloat, x: CGFloat = 0.3, dragging nodes: [UUID],
                singleTab: Bool = true) -> SidebarDropTarget? {
      SidebarDropResolver.target(rows: rows, row: row, fractionY: y, fractionX: x,
                                 payload: SidebarDragPayload(nodes: nodes, isSingleTab: singleTab),
                                 space: space, todayCount: 3)
    }
  }

  let f = Fixture()

  // MARK: Reorder

  @Test func theTopOfARowInsertsBeforeIt() {
    #expect(f.target(row: 5, y: 0.1, dragging: [f.t1])
      == .insert(location: .today(f.space), index: 0, gapBeforeRow: 5, level: 0))
  }

  @Test func theBottomOfARowInsertsAfterIt() {
    #expect(f.target(row: 5, y: 0.9, dragging: [f.t1])
      == .insert(location: .today(f.space), index: 1, gapBeforeRow: 6, level: 0))
  }

  @Test func belowTheLastRowIsTheEndOfToday() {
    #expect(f.target(row: nil, y: 0, dragging: [f.p0])
      == .insert(location: .today(f.space), index: 3, gapBeforeRow: 10, level: 0))
  }

  @Test func afterASplitRowLandsBelowItsPanes() {
    #expect(f.target(row: 6, y: 0.9, dragging: [f.t0])
      == .insert(location: .today(f.space), index: 2, gapBeforeRow: 9, level: 0))
  }

  // MARK: GS-007 pin and unpin

  @Test func theUpperHalfOfTheDividerEndsPinned() {
    #expect(f.target(row: 4, y: 0.3, dragging: [f.t0])
      == .insert(location: .pinned(f.space), index: 3, gapBeforeRow: 4, level: 0))
  }

  @Test func theLowerHalfOfTheDividerStartsToday() {
    #expect(f.target(row: 4, y: 0.7, dragging: [f.p0])
      == .insert(location: .today(f.space), index: 0, gapBeforeRow: 5, level: 0))
  }

  @Test func aTodayTabDroppedAmongPinnedRowsPins() {
    #expect(f.target(row: 0, y: 0.1, dragging: [f.t0])
      == .insert(location: .pinned(f.space), index: 0, gapBeforeRow: 0, level: 0))
  }

  // MARK: GS-009 folders

  @Test func theMiddleOfAFolderRowDropsIntoTheFolder() {
    #expect(f.target(row: 1, y: 0.5, dragging: [f.t0]) == .folder(f.folder, row: 1))
  }

  @Test func theBottomOfAnOpenFolderInsertsAsItsFirstChild() {
    #expect(f.target(row: 1, y: 0.9, dragging: [f.t0])
      == .insert(location: .folder(f.folder), index: 0, gapBeforeRow: 2, level: 1))
  }

  @Test func theBottomOfAClosedFolderInsertsAfterIt() {
    var rows = f.rows
    rows[1].kind = .folder(expanded: false)
    rows.remove(at: 2)
    let target = SidebarDropResolver.target(rows: rows, row: 1, fractionY: 0.9, fractionX: 0.5,
                                            payload: SidebarDragPayload(nodes: [f.t0], isSingleTab: true),
                                            space: f.space, todayCount: 3)
    #expect(target == .insert(location: .pinned(f.space), index: 2, gapBeforeRow: 2, level: 0))
  }

  @Test func aFolderNeverDropsIntoItselfOrItsChildren() {
    #expect(f.target(row: 1, y: 0.5, dragging: [f.folder]) == nil)
    #expect(f.target(row: 2, y: 0.1, dragging: [f.folder]) == nil)
    #expect(f.target(row: 1, y: 0.9, dragging: [f.folder]) == nil)
  }

  @Test func aFolderMovesBetweenRowsOfItsSection() {
    #expect(f.target(row: 0, y: 0.1, dragging: [f.folder], singleTab: false)
      == .insert(location: .pinned(f.space), index: 0, gapBeforeRow: 0, level: 0))
  }

  // MARK: GS-010 / BH-118 split

  @Test func theLeftHalfOfATabMakesASplitWithTheDroppedTabFirst() {
    #expect(f.target(row: 5, y: 0.5, x: 0.2, dragging: [f.t1]) == .split(target: f.t0, before: true, row: 5))
  }

  @Test func theRightHalfOfATabPutsTheDroppedTabSecond() {
    #expect(f.target(row: 5, y: 0.5, x: 0.8, dragging: [f.t1]) == .split(target: f.t0, before: false, row: 5))
  }

  @Test func theMiddleOfASplitRowJoinsIt() {
    #expect(f.target(row: 6, y: 0.5, x: 0.8, dragging: [f.t1]) == .split(target: f.split, before: false, row: 6))
  }

  @Test func onlyASingleTabMakesASplit() {
    #expect(f.target(row: 5, y: 0.4, dragging: [f.t1, f.p0], singleTab: false)
      == .insert(location: .today(f.space), index: 0, gapBeforeRow: 5, level: 0))
    #expect(f.target(row: 5, y: 0.6, dragging: [f.folder], singleTab: false)
      == .insert(location: .today(f.space), index: 1, gapBeforeRow: 6, level: 0))
  }

  @Test func aTabOverItsOwnRowOnlyInserts() {
    #expect(f.target(row: 5, y: 0.4, dragging: [f.t0])
      == .insert(location: .today(f.space), index: 0, gapBeforeRow: 5, level: 0))
  }

  @Test func betweenPanesReordersOrJoinsThatSplit() {
    #expect(f.target(row: 8, y: 0.3, dragging: [f.a])
      == .insert(location: .split(f.split), index: 1, gapBeforeRow: 8, level: 1))
    #expect(f.target(row: 8, y: 0.7, dragging: [f.t1])
      == .insert(location: .split(f.split), index: 2, gapBeforeRow: 9, level: 1))
  }

  @Test func aSplitNeverDropsIntoItself() {
    #expect(f.target(row: 7, y: 0.3, dragging: [f.split], singleTab: false) == nil)
  }

  // MARK: Payload

  @Test func thePayloadRoundTripsThroughThePasteboardString() {
    let payload = SidebarDragPayload(nodes: [f.t0, f.p1], isSingleTab: false)
    #expect(SidebarDragPayload.nodes(fromPasteboardString: payload.pasteboardString) == [f.t0, f.p1])
    #expect(SidebarDragPayload.nodes(fromPasteboardString: "not a uuid") == nil)
    #expect(SidebarDragPayload.nodes(fromPasteboardString: "") == nil)
  }
}
