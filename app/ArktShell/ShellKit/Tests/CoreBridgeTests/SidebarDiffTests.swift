import Foundation
import ShellUI
import SidebarModel
import Testing
@testable import CoreBridge

/// `SidebarDiff.changes(from:to:)` over two `Sidebar` values.
struct SidebarDiffTests {
  private static let url = URL(string: "https://a.example")!

  @Test func identicalSidebarsEmitNothing() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "S")
    _ = try sidebar.addTab(url: Self.url, title: "A", in: .today(space))
    #expect(SidebarDiff.changes(from: sidebar, to: sidebar).isEmpty)
  }

  @Test func removingAFolderWithChildrenEmitsOnlyItsSection() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let folder = try old.addFolder(title: "F", in: .pinned(space))
    let inner = try old.addFolder(title: "Inner", in: .folder(folder))
    _ = try old.addTab(url: Self.url, title: "A", in: .folder(folder))
    _ = try old.addTab(url: Self.url, title: "B", in: .folder(inner))
    var new = old
    new.remove(folder)
    #expect(SidebarDiff.changes(from: old, to: new) == [.structure(.pinned(space))])
  }

  @Test func addingATabInsideANestedFolderEmitsOnlyThatFolder() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let outer = try old.addFolder(title: "Outer", in: .pinned(space))
    let inner = try old.addFolder(title: "Inner", in: .folder(outer))
    _ = try old.addTab(url: Self.url, title: "A", in: .folder(inner))
    var new = old
    _ = try new.addTab(url: Self.url, title: "B", in: .folder(inner))
    #expect(SidebarDiff.changes(from: old, to: new) == [.structure(.folder(inner))])
  }

  @Test func orderIsSpacesThenSectionsThenContainersByDepthThenID() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let deepParent = try old.addFolder(title: "Outer", in: .pinned(space))
    let deep = try old.addFolder(title: "Deep", in: .folder(deepParent))
    let shallowA = try old.addFolder(title: "A", in: .today(space))
    let shallowB = try old.addFolder(title: "B", in: .today(space))
    var new = old
    let second = new.addSpace(title: "Second")
    _ = try new.addTab(url: Self.url, title: "x", in: .folder(deep))
    _ = try new.addTab(url: Self.url, title: "y", in: .folder(shallowB))
    _ = try new.addTab(url: Self.url, title: "z", in: .folder(shallowA))
    _ = try new.addTab(url: Self.url, title: "t", in: .today(space))
    _ = try new.addTab(url: Self.url, title: "p", in: .pinned(space))
    _ = try new.addTab(url: Self.url, title: "f", in: .favorites(profile: "default"))
    let shallow = [shallowA, shallowB].sorted { $0.uuidString < $1.uuidString }
    #expect(SidebarDiff.changes(from: old, to: new) == [
      .spaceAdded(second),
      .structure(.favorites(profile: "default")), .structure(.pinned(space)), .structure(.today(space)),
      .structure(.folder(shallow[0])), .structure(.folder(shallow[1])),
      .structure(.folder(deep)),
    ])
  }

  @Test func sectionTiesSortByID() throws {
    var old = SidebarModel.Sidebar()
    let a = old.addSpace(title: "A")
    let b = old.addSpace(title: "B")
    var new = old
    _ = try new.addTab(url: Self.url, title: "1", in: .today(a))
    _ = try new.addTab(url: Self.url, title: "2", in: .today(b))
    let sorted = [a, b].sorted { $0.uuidString < $1.uuidString }
    #expect(SidebarDiff.changes(from: old, to: new) == [.structure(.today(sorted[0])), .structure(.today(sorted[1]))])
  }

  @Test func movingBetweenSectionsEmitsBothSectionsAndNoNode() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let tab = try old.addTab(url: Self.url, title: "A", in: .today(space))
    _ = try old.addTab(url: Self.url, title: "B", in: .today(space))
    var new = old
    try new.move(tab, to: .pinned(space), at: 0)
    #expect(SidebarDiff.changes(from: old, to: new) == [.structure(.pinned(space)), .structure(.today(space))])
  }

  @Test func drawnFieldChangesEmitNodeButLastActiveDoesNot() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let tab = try old.addTab(url: Self.url, title: "A", in: .today(space))
    var stamped = old
    try stamped.updateTab(tab, lastActiveAt: Date(timeIntervalSinceReferenceDate: 9))
    #expect(SidebarDiff.changes(from: old, to: stamped).isEmpty)
    var retitled = old
    try retitled.updateTab(tab, title: "B")
    #expect(SidebarDiff.changes(from: old, to: retitled) == [.node(tab)])
  }

  @Test func sectionsOfARemovedSpaceAreSkipped() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    _ = try old.addTab(url: Self.url, title: "A", in: .pinned(space))
    _ = try old.addTab(url: Self.url, title: "B", in: .today(space))
    #expect(SidebarDiff.changes(from: old, to: SidebarModel.Sidebar()) == [.spaceRemoved(space)])
  }

  @Test func addingASpaceEmitsSpaceAdded() throws {
    var old = SidebarModel.Sidebar()
    _ = old.addSpace(title: "S")
    var new = old
    let added = new.addSpace(title: "T")
    #expect(SidebarDiff.changes(from: old, to: new) == [.spaceAdded(added)])
  }

  // MARK: Space events

  private static func space(_ title: String, theme: SpaceTheme? = nil, id: UUID = UUID()) -> SidebarModel.Space {
    SidebarModel.Space(id: id, title: title, theme: theme)
  }

  /// A sidebar holding `spaces` in that order.
  private static func sidebar(_ spaces: [SidebarModel.Space]) throws -> SidebarModel.Sidebar {
    var sidebar = SidebarModel.Sidebar()
    for space in spaces { try sidebar.addSpace(space) }
    return sidebar
  }

  @Test func titleProfileThemeOrIconChangeEmitsSpaceChanged() throws {
    let (a, b) = (Self.space("A"), Self.space("B"))
    let old = try Self.sidebar([a, b])
    var renamed = a
    renamed.title = "A2"
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([renamed, b])) == [.spaceChanged(a.id)])
    var rethemed = b
    rethemed.theme = SpaceTheme(baseColors: [RGBA(red: 0, green: 0, blue: 0)], isDark: true)
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([a, rethemed])) == [.spaceChanged(b.id)])
    var reprofiled = a
    reprofiled.profile = "Work"
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([reprofiled, b])) == [.spaceChanged(a.id)])
    var reiconed = a
    reiconed.icon = .symbol("star")
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([reiconed, b])) == [.spaceChanged(a.id)])
  }

  /// Only the Space that left its place is reported, not every Space whose index shifted.
  @Test func reorderEmitsSpaceMovedForTheMovedSpaceOnly() throws {
    let (a, b, c, d) = (Self.space("A"), Self.space("B"), Self.space("C"), Self.space("D"))
    let old = try Self.sidebar([a, b, c, d])
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([b, c, d, a])) == [.spaceMoved(a.id)])
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([a, d, b, c])) == [.spaceMoved(d.id)])
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([d, a, c, b])).count == 2)
  }

  /// Removals and additions alone shift indexes but move nothing.
  @Test func removalAndAdditionAloneEmitNoMove() throws {
    let (a, b, c, d) = (Self.space("A"), Self.space("B"), Self.space("C"), Self.space("D"))
    let old = try Self.sidebar([a, b, c])
    #expect(SidebarDiff.changes(from: old, to: try Self.sidebar([d, a, c])) == [.spaceRemoved(b.id), .spaceAdded(d.id)])
  }

  /// Space events come first: removed (old order), added, moved, changed (new order).
  @Test func spaceEventsComeFirstRemovedAddedMovedChanged() throws {
    let (a, b, c, d, e) = (Self.space("A"), Self.space("B"), Self.space("C"), Self.space("D"), Self.space("E"))
    let f = Self.space("F")
    let old = try Self.sidebar([a, b, c, d, f])
    var renamed = c
    renamed.title = "C2"
    var new = try Self.sidebar([e, a, d, f, renamed])
    _ = try new.addTab(url: Self.url, title: "u", in: .today(d.id))
    #expect(SidebarDiff.changes(from: old, to: new) == [
      .spaceRemoved(b.id), .spaceAdded(e.id), .spaceMoved(c.id), .spaceChanged(c.id), .structure(.today(d.id)),
    ])
  }

  @Test func widthChangeEmitsNodeOfSplit() throws {
    var old = SidebarModel.Sidebar()
    let space = old.addSpace(title: "S")
    let left = try old.addTab(url: Self.url, title: "L", in: .today(space))
    let right = try old.addTab(url: Self.url, title: "R", in: .today(space))
    let split = try old.createSplit(of: [left, right])
    var resized = old
    try resized.setSplitWidthFactors(split, [3, 1])
    #expect(SidebarDiff.changes(from: old, to: resized) == [.node(split)])
    var flipped = old
    try flipped.setSplitOrientation(split, .vertical)
    #expect(SidebarDiff.changes(from: old, to: flipped) == [.node(split)])
  }
}
