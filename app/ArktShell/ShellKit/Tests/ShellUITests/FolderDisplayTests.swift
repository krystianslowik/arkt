import Foundation
import Testing
@testable import ShellUI

/// Which rows a folder shows (#109): every child while open, and under a closed folder only the rows peeking out
/// (BH-092 a moved-in tab, BH-093 a tab chosen in Folder Preview, BH-105 a tab switched to). A folder whose close
/// spring still runs shows everything until it settles.
@MainActor
struct FolderDisplayTests {
  private let sidebar = StubSidebar()
  private let space: SpaceID
  /// Pinned: folder `outer` [a, inner [b, c], split [p0, p1]].
  private let outer: NodeID
  private let inner: NodeID
  private let a: NodeID
  private let b: NodeID
  private let c: NodeID
  private let split: NodeID
  private let panes: [NodeID]

  init() throws {
    space = sidebar.addSpace(title: "Work")
    outer = sidebar.addFolder(title: "Outer", in: .pinned(space))
    a = sidebar.addTab(url: Self.url("a"), title: "A", in: .folder(outer))
    inner = sidebar.addFolder(title: "Inner", in: .folder(outer))
    b = sidebar.addTab(url: Self.url("b"), title: "B", in: .folder(inner))
    c = sidebar.addTab(url: Self.url("c"), title: "C", in: .folder(inner))
    split = try sidebar.addToSplit(.new(url: Self.url("p0"), title: "P0"), target: sidebar.addTab(
      url: Self.url("p1"), title: "P1", in: .folder(outer)), at: 0, orientation: .horizontal).split
    panes = sidebar.children(of: .split(split))
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  @Test func openFoldersShowEveryChildInOrder() {
    let display = FolderDisplay()
    #expect(display.children(of: outer, in: sidebar) == [a, inner, split])
    #expect(display.descendants(of: outer, in: sidebar) == [a, inner, b, c, split] + panes)
  }

  @Test func aClosedFolderShowsNothingWithoutPeeks() {
    var display = FolderDisplay()
    display.collapsed = [outer]
    #expect(display.children(of: outer, in: sidebar).isEmpty)
    #expect(!display.isEffectivelyOpen(outer, in: sidebar))
    #expect(!display.isEffectivelyOpen(inner, in: sidebar), "an open folder inside a closed one is hidden too")
  }

  @Test func aPeekingTabShowsAloneUnderItsClosedFolder() {
    var display = FolderDisplay()
    display.collapsed = [outer]
    display.peeks = [a]
    #expect(display.children(of: outer, in: sidebar) == [a])
  }

  /// BH-105: a tab deep inside closed folders shows with the path to it, and nothing else.
  @Test func aDeepPeekShowsThePathToItOnly() {
    var display = FolderDisplay()
    display.collapsed = [outer]
    display.peeks = [c]
    #expect(display.descendants(of: outer, in: sidebar) == [inner, c],
            "inner is open, but inside a closed folder it shows only the peeking tab")
  }

  /// A pane peeks through its split: the split row shows whole.
  @Test func aPanePeeksThroughItsSplit() {
    #expect(FolderDisplay.peekRoot(of: panes[1], in: sidebar) == split)
    #expect(FolderDisplay.peekRoot(of: a, in: sidebar) == a)
    var display = FolderDisplay()
    display.collapsed = [outer]
    display.peeks = [split]
    #expect(display.descendants(of: outer, in: sidebar) == [split] + panes)
  }

  /// While its close spring runs a folder still shows everything; the rows leave when it settles.
  @Test func aClosingFolderStillShowsItsRows() {
    var display = FolderDisplay()
    display.collapsed = [outer]
    display.closing = [outer]
    #expect(display.descendants(of: outer, in: sidebar) == [a, inner, b, c, split] + panes)
    #expect(display.settled.descendants(of: outer, in: sidebar).isEmpty)
  }

  @Test func isHiddenFollowsTheClosedAncestors() {
    var display = FolderDisplay()
    #expect(!display.isHidden(b, in: sidebar))
    display.collapsed = [inner]
    #expect(display.isHidden(b, in: sidebar))
    #expect(!display.isHidden(a, in: sidebar))
    display.peeks = [b]
    #expect(!display.isHidden(b, in: sidebar))
  }
}
