import AppKit
import Foundation
import Testing
import Motion
@testable import ShellUI

/// The pure pieces of sidebar drag and drop (#104) around the resolver: the Space edge dwell (GS-012), dragging a
/// tab out to a new window (GS-013), dropped text (GS-015), and the gap springs the rows make room with.
struct SidebarDragRulesTests {
  // MARK: GS-012 edge dwell

  @Test func restingAtTheRightEdgePagesForwardAfterTheDwell() {
    var dwell = SpaceEdgeDwell()
    #expect(dwell.update(x: 195, width: 200, at: 0) == nil)
    #expect(dwell.update(x: 196, width: 200, at: SpaceEdgeDwell.dwell - 0.01) == nil)
    #expect(dwell.update(x: 196, width: 200, at: SpaceEdgeDwell.dwell) == 1)
  }

  @Test func restingAtTheLeftEdgePagesBack() {
    var dwell = SpaceEdgeDwell()
    _ = dwell.update(x: 2, width: 200, at: 1)
    #expect(dwell.update(x: 3, width: 200, at: 1 + SpaceEdgeDwell.dwell) == -1)
  }

  @Test func leavingTheEdgeRestartsTheDwell() {
    var dwell = SpaceEdgeDwell()
    _ = dwell.update(x: 198, width: 200, at: 0)
    #expect(dwell.update(x: 100, width: 200, at: 0.3) == nil)
    #expect(dwell.update(x: 198, width: 200, at: 0.4) == nil)
    #expect(dwell.update(x: 198, width: 200, at: 0.4 + SpaceEdgeDwell.dwell) == 1)
  }

  @Test func stayingAtTheEdgeKeepsPagingOncePerDwell() {
    var dwell = SpaceEdgeDwell()
    _ = dwell.update(x: 198, width: 200, at: 0)
    #expect(dwell.update(x: 198, width: 200, at: SpaceEdgeDwell.dwell) == 1)
    #expect(dwell.update(x: 198, width: 200, at: SpaceEdgeDwell.dwell + 0.1) == nil)
    #expect(dwell.update(x: 198, width: 200, at: 2 * SpaceEdgeDwell.dwell) == 1)
  }

  // MARK: Spring-loaded folders

  @Test func hoveringAClosedFolderOpensItAfterTheDwell() {
    var load = FolderSpringLoad()
    let folder = UUID()
    #expect(load.update(closedFolder: folder, at: 0) == nil)
    #expect(load.update(closedFolder: folder, at: FolderSpringLoad.dwell - 0.01) == nil)
    #expect(load.update(closedFolder: folder, at: FolderSpringLoad.dwell) == folder)
    #expect(load.update(closedFolder: folder, at: 2 * FolderSpringLoad.dwell) == nil, "once per hover")
  }

  @Test func movingOffTheFolderRestartsTheDwell() {
    var load = FolderSpringLoad()
    let folder = UUID()
    _ = load.update(closedFolder: folder, at: 0)
    #expect(load.update(closedFolder: nil, at: 0.3) == nil)
    #expect(load.update(closedFolder: folder, at: 0.4) == nil)
    #expect(load.update(closedFolder: folder, at: 0.4 + FolderSpringLoad.dwell) == folder)
  }

  // MARK: GS-013 drag out

  @Test func aSingleTabReleasedOutsideEveryWindowOpensOne() {
    let frames = [CGRect(x: 0, y: 0, width: 800, height: 600)]
    let tab = SidebarDragPayload(nodes: [UUID()], isSingleTab: true)
    #expect(SidebarDragOut.opensWindow(operation: [], endedByEscape: false, endPoint: CGPoint(x: 900, y: 100),
                                       windowFrames: frames, payload: tab))
  }

  @Test func aDragOutIsNotTakenOverAWindowAfterEscapeOrForASet() {
    let frames = [CGRect(x: 0, y: 0, width: 800, height: 600)]
    let tab = SidebarDragPayload(nodes: [UUID()], isSingleTab: true)
    let outside = CGPoint(x: 900, y: 100)
    #expect(!SidebarDragOut.opensWindow(operation: [], endedByEscape: false, endPoint: CGPoint(x: 100, y: 100),
                                        windowFrames: frames, payload: tab))
    #expect(!SidebarDragOut.opensWindow(operation: [], endedByEscape: true, endPoint: outside,
                                        windowFrames: frames, payload: tab))
    #expect(!SidebarDragOut.opensWindow(operation: .move, endedByEscape: false, endPoint: outside,
                                        windowFrames: frames, payload: tab))
    #expect(!SidebarDragOut.opensWindow(operation: [], endedByEscape: false, endPoint: outside, windowFrames: frames,
                                        payload: SidebarDragPayload(nodes: [UUID(), UUID()], isSingleTab: false)))
  }

  // MARK: GS-015 text

  @Test func droppedTextOpensAURLOrASearch() throws {
    #expect(SidebarTextDrop.url(for: "  https://example.com/a \n") == URL(string: "https://example.com/a"))
    let search = try #require(SidebarTextDrop.url(for: "spring physics"))
    #expect(search == URLInputParser.searchURL(for: "spring physics"))
    #expect(SidebarTextDrop.url(for: "   ") == nil)
  }

  @Test func droppedTextLandsWhereTheIndicatorIs() {
    let space = UUID(), folder = UUID(), tab = UUID()
    #expect(SidebarTextDrop.location(for: .insert(location: .pinned(space), index: 2, gapBeforeRow: 2, level: 0),
                                     space: space) == SidebarDropPlacement(location: .pinned(space), index: 2))
    #expect(SidebarTextDrop.location(for: .folder(folder, row: 1), space: space) == SidebarDropPlacement(location: .folder(folder), index: nil))
    #expect(SidebarTextDrop.location(for: .split(target: tab, before: true, row: 3), space: space)
      == SidebarDropPlacement(location: .today(space), index: 0))
    #expect(SidebarTextDrop.location(for: .insert(location: .split(folder), index: 0, gapBeforeRow: 2, level: 1),
                                     space: space) == SidebarDropPlacement(location: .today(space), index: 0))
    #expect(SidebarTextDrop.location(for: nil, space: space) == SidebarDropPlacement(location: .today(space), index: 0))
  }

  // MARK: Gap springs

  @Test func gapOffsetsSpringTowardTheirTargetAndSettle() {
    var springs = DropGapSprings<Int>()
    springs.retarget([1: 41, 2: 41], at: 0, parameters: SidebarDropMotion.makeRoom)
    #expect(springs.offset(of: 1, at: 0) == 0)
    let mid = springs.offset(of: 1, at: 0.05)
    #expect(mid > 0 && mid < 41)
    #expect(springs.offset(of: 1, at: 2) == 41)
    #expect(springs.isSettled(at: 2))
    #expect(!springs.isSettled(at: 0.05))
  }

  @Test func aRetargetMidFlightContinuesFromWhereTheRowIs() {
    var springs = DropGapSprings<Int>()
    springs.retarget([1: 41], at: 0, parameters: SidebarDropMotion.makeRoom)
    let before = springs.offset(of: 1, at: 0.04)
    springs.retarget([:], at: 0.04, parameters: SidebarDropMotion.snapBack)    // the gap moved away
    #expect(abs(springs.offset(of: 1, at: 0.04) - before) < 0.001)
    #expect(springs.velocity(of: 1, at: 0.04) > 0)                               // still moving down as it turns
    #expect(springs.offset(of: 1, at: 3) == 0)
  }

  @Test func settledKeysAtRestAreDropped() {
    var springs = DropGapSprings<Int>()
    springs.retarget([1: 41], at: 0, parameters: SidebarDropMotion.makeRoom)
    springs.retarget([:], at: 0.01, parameters: SidebarDropMotion.snapBack)
    springs.prune(at: 5)
    #expect(springs.keys.isEmpty)
  }

  @Test func reduceMotionOpensNoGap() {
    #expect(SidebarDropMotion.gapOffsets(rowCount: 4, gapBeforeRow: 2, gap: 41, reduceMotion: false)
      == [2: 41, 3: 41])
    #expect(SidebarDropMotion.gapOffsets(rowCount: 4, gapBeforeRow: 2, gap: 41, reduceMotion: true).isEmpty)
    #expect(SidebarDropMotion.gapOffsets(rowCount: 4, gapBeforeRow: 4, gap: 41, reduceMotion: false).isEmpty)
  }
}
