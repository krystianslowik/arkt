import ArcImport
import CoreBridge
import Foundation
import SidebarModel
import Testing

struct ArcImportMergeTests {
  static let mail = URL(string: "https://mail.example")!
  static let docs = URL(string: "https://docs.example")!
  static let drifted = URL(string: "https://mail.example/inbox")!

  /// An importer-shaped result; `spaces` and `nodes` give the Arc id of each Space and top-level node.
  static func result(_ sidebar: Sidebar, spaces: [String: SpaceID] = [:], nodes: [String: NodeID] = [:])
    -> ArcImportResult
  {
    ArcImportResult(sidebar: sidebar, report: ImportReport(), nodeIDsByArcID: nodes, spaceIDsByArcID: spaces)
  }

  @Test func existingSpaceIsLeftExactlyAsItIsAndRecorded() throws {
    let id = SpaceID()
    var imported = Sidebar()
    try imported.addSpace(Space(id: id, title: "From Arc"))
    try imported.addTab(url: Self.docs, title: "Docs", in: .today(id))
    var sidebar = Sidebar()
    try sidebar.addSpace(Space(id: id, title: "Renamed in Arkt"))
    let before = sidebar

    let counts = ArcImportMerge.merge(Self.result(imported, spaces: ["arc-s": id]), into: &sidebar)

    #expect(sidebar == before)
    #expect(counts.spaces == 0 && counts.existingSpaces == 1 && counts.tabs == 0)
    #expect(counts.addedNodes.isEmpty)
    // Already in Arkt counts as handled, so a user who imported before the record existed gets it recorded now.
    #expect(counts.handled == ArcImportRecord(spaceIDs: ["arc-s"]))
  }

  @Test func addedSpaceKeepsItsTreeAndMovesToTheTargetProfile() throws {
    let id = SpaceID()
    var imported = Sidebar()
    try imported.addSpace(Space(id: id, title: "Work", profile: "profile-custom"))
    let folder = try imported.addFolder(title: "F", in: .pinned(id))
    let inner = try imported.addTab(url: Self.docs, title: "Docs", in: .folder(folder))
    let today = try imported.addTab(url: Self.mail, title: "Mail", in: .today(id))
    var sidebar = Sidebar()

    let counts = ArcImportMerge.merge(Self.result(imported, spaces: ["arc-work": id]), into: &sidebar)

    #expect(sidebar.spaces[id]?.profile == "default")
    #expect(sidebar.spaces[id]?.title == "Work")
    #expect(sidebar.snapshot(of: folder) == imported.snapshot(of: folder))
    #expect(sidebar.children(of: .today(id)) == [today])
    #expect(counts.spaces == 1 && counts.otherProfileSpaces == 1)
    #expect(counts.tabs == 2 && counts.folders == 1 && counts.splits == 0)
    #expect(counts.addedNodes == [folder, inner, today])
    #expect(counts.handled == ArcImportRecord(spaceIDs: ["arc-work"]))
  }

  @Test func favoritesOfEveryProfileMergeWithoutDuplicateURLs() throws {
    var imported = Sidebar()
    let shared = try imported.addTab(url: Self.mail, title: "Mail", in: .favorites(profile: "profile-b"))
    let docs = try imported.addTab(url: Self.docs, title: "Docs", in: .favorites(profile: "profile-b"))
    let mail = try imported.addTab(url: Self.mail, title: "Mail", in: .favorites(profile: "default"))
    let result = Self.result(imported, nodes: ["arc-shared": shared, "arc-docs": docs, "arc-mail": mail])
    var sidebar = Sidebar()

    let first = ArcImportMerge.merge(result, into: &sidebar)
    // The target profile's own Favorites come first, so its copy of a shared URL is the one kept.
    #expect(sidebar.children(of: .favorites(profile: "default")) == [mail, docs])
    #expect(sidebar.children(of: .favorites(profile: "profile-b")).isEmpty)
    #expect(first.favorites == 2 && first.duplicateFavorites == 1)
    // The skipped duplicate counts as handled too: the Favorite that was kept stands for it.
    #expect(first.handled.favoriteItemIDs == ["arc-shared", "arc-docs", "arc-mail"])

    // Without a record (an import from before the record existed) the URL match still prevents duplicates.
    let before = sidebar
    let second = ArcImportMerge.merge(result, into: &sidebar)
    #expect(sidebar == before)
    #expect(second.favorites == 0 && second.duplicateFavorites == 3)
  }

  // MARK: Re-import rule (user decision, 2026-10-23: only Arc items never imported before)

  @Test func folderFavoriteImportedTwiceIsAddedOnce() throws {
    var imported = Sidebar()
    let folder = try imported.addFolder(title: "Work", in: .favorites(profile: "default"))
    try imported.addTab(url: Self.docs, title: "Docs", in: .folder(folder))
    let split = try imported.addSplit(
      orientation: .vertical, widthFactors: [0.5, 0.5], in: .favorites(profile: "default"))
    try imported.addTab(url: Self.mail, title: "Mail", in: .split(split))
    let result = Self.result(imported, nodes: ["arc-folder": folder, "arc-split": split])
    var sidebar = Sidebar()

    let first = ArcImportMerge.merge(result, into: &sidebar)
    #expect(first.favorites == 2)
    let afterFirst = sidebar
    let second = ArcImportMerge.merge(result, into: &sidebar, record: first.handled)

    #expect(sidebar == afterFirst)
    #expect(sidebar.children(of: .favorites(profile: "default")).count == 2)
    #expect(second.favorites == 0 && second.previouslyImportedFavorites == 2)
    #expect(second.handled.favoriteItemIDs == ["arc-folder", "arc-split"])
  }

  @Test func deletedSpaceIsNotRestored() throws {
    let id = SpaceID()
    var imported = Sidebar()
    try imported.addSpace(Space(id: id, title: "Gone"))
    try imported.addTab(url: Self.docs, title: "Docs", in: .today(id))
    let result = Self.result(imported, spaces: ["arc-gone": id])
    var sidebar = Sidebar()                       // the user deleted the Space after importing it
    let record = ArcImportRecord(spaceIDs: ["arc-gone"])

    #expect(ArcImportMerge.missingSpaces(in: result, comparedTo: sidebar, record: record).isEmpty)
    let counts = ArcImportMerge.merge(result, into: &sidebar, record: record)

    #expect(sidebar == Sidebar())
    #expect(counts.spaces == 0 && counts.existingSpaces == 0 && counts.previouslyImportedSpaces == 1)
    #expect(counts.handled.spaceIDs == ["arc-gone"])
  }

  @Test func deletedFavoriteIsNotRestored() throws {
    var imported = Sidebar()
    let mail = try imported.addTab(url: Self.mail, title: "Mail", in: .favorites(profile: "default"))
    let result = Self.result(imported, nodes: ["arc-mail": mail])
    var sidebar = Sidebar()
    let first = ArcImportMerge.merge(result, into: &sidebar)
    sidebar.remove(mail)                          // the user deleted it in Arkt

    let second = ArcImportMerge.merge(result, into: &sidebar, record: first.handled)

    #expect(sidebar.children(of: .favorites(profile: "default")).isEmpty)
    #expect(second.favorites == 0 && second.previouslyImportedFavorites == 1)
  }

  @Test func favoriteWhoseURLDriftedIsNotAddedAgain() throws {
    var arcBefore = Sidebar()
    let mail = try arcBefore.addTab(url: Self.mail, title: "Mail", in: .favorites(profile: "default"))
    var sidebar = Sidebar()
    let first = ArcImportMerge.merge(Self.result(arcBefore, nodes: ["arc-mail": mail]), into: &sidebar)
    // Later the same Arc Favorite points elsewhere (and the importer mints a fresh node id on every run).
    var arcAfter = Sidebar()
    let moved = try arcAfter.addTab(url: Self.drifted, title: "Mail", in: .favorites(profile: "default"))
    let before = sidebar

    let second = ArcImportMerge.merge(
      Self.result(arcAfter, nodes: ["arc-mail": moved]), into: &sidebar, record: first.handled)

    #expect(sidebar == before)
    #expect(second.favorites == 0 && second.duplicateFavorites == 0 && second.previouslyImportedFavorites == 1)
  }

  @Test func neverImportedItemsAreStillAddedWhenARecordExists() throws {
    let id = SpaceID()
    var imported = Sidebar()
    try imported.addSpace(Space(id: id, title: "New in Arc"))
    let docs = try imported.addTab(url: Self.docs, title: "Docs", in: .favorites(profile: "default"))
    var sidebar = Sidebar()
    let record = ArcImportRecord(spaceIDs: ["arc-other"], favoriteItemIDs: ["arc-other-favorite"])
    let result = Self.result(imported, spaces: ["arc-new": id], nodes: ["arc-docs": docs])

    #expect(ArcImportMerge.missingSpaces(in: result, comparedTo: sidebar, record: record) == [id])
    let counts = ArcImportMerge.merge(result, into: &sidebar, record: record)

    #expect(counts.spaces == 1 && counts.favorites == 1)
    #expect(counts.handled == ArcImportRecord(spaceIDs: ["arc-new"], favoriteItemIDs: ["arc-docs"]))
  }
}
