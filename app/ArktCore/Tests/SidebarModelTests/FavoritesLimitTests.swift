import Foundation
import Testing
import SidebarModel

/// BH-046 / CF-17: a Profile holds at most 12 Favorites; a 13th add or move-in is refused and zero is allowed.
/// The cap is a user-action rule, like `maximumSplitPanes`: the add and move paths enforce it, while snapshot
/// `insert(_:in:at:)` does not, so stored or imported trees with more items still load.
struct FavoritesLimitTests {
  let url = URL(string: "https://example.com/a")!

  /// A sidebar whose "default" profile has `count` Favorites.
  private func makeFavorites(_ count: Int, profile: String = "default") throws -> (Sidebar, [NodeID]) {
    var sidebar = Sidebar()
    let ids = try (0..<count).map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: "F\($0)",
                         in: .favorites(profile: profile))
    }
    return (sidebar, ids)
  }

  @Test func addingUpToTwelveFavoritesWorks() throws {
    let (sidebar, ids) = try makeFavorites(Sidebar.maximumFavorites)
    #expect(sidebar.children(of: .favorites(profile: "default")) == ids)
    #expect(Sidebar.maximumFavorites == 12)
  }

  @Test func addingAThirteenthFavoriteIsRefused() throws {
    var (sidebar, _) = try makeFavorites(Sidebar.maximumFavorites)
    #expect(throws: SidebarError.favoritesFull("default")) {
      try sidebar.addTab(url: url, title: "13th", in: .favorites(profile: "default"))
    }
    #expect(sidebar.children(of: .favorites(profile: "default")).count == Sidebar.maximumFavorites)
  }

  @Test func theCapCountsEveryChildKind() throws {
    var (sidebar, _) = try makeFavorites(Sidebar.maximumFavorites)
    #expect(throws: SidebarError.favoritesFull("default")) {
      try sidebar.addFolder(title: "Folder", in: .favorites(profile: "default"))
    }
  }

  @Test func theCapIsPerProfile() throws {
    var (sidebar, _) = try makeFavorites(Sidebar.maximumFavorites)
    let other = try sidebar.addTab(url: url, title: "Other", in: .favorites(profile: "work"))
    #expect(sidebar.children(of: .favorites(profile: "work")) == [other])
  }

  @Test func movingAThirteenthTabIntoFavoritesIsRefused() throws {
    var (sidebar, _) = try makeFavorites(Sidebar.maximumFavorites)
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: url, title: "T", in: .today(space))
    #expect(throws: SidebarError.favoritesFull("default")) {
      try sidebar.move(tab, to: .favorites(profile: "default"), at: 0)
    }
    #expect(sidebar.children(of: .today(space)) == [tab])
  }

  @Test func reorderingInsideAFullFavoritesStillWorks() throws {
    var (sidebar, ids) = try makeFavorites(Sidebar.maximumFavorites)
    try sidebar.move(ids[0], to: .favorites(profile: "default"), at: Sidebar.maximumFavorites)
    #expect(sidebar.children(of: .favorites(profile: "default")).last == ids[0])
  }

  @Test func movingOutAndBackInWorksBelowTheCap() throws {
    var (sidebar, ids) = try makeFavorites(Sidebar.maximumFavorites)
    let space = sidebar.addSpace(title: "Work")
    try sidebar.move(ids[11], to: .pinned(space), at: 0)
    try sidebar.move(ids[11], to: .favorites(profile: "default"), at: 12)
    #expect(sidebar.children(of: .favorites(profile: "default")).last == ids[11])
  }

  /// Same rule as split panes: a stored or restored tree over the cap still loads; the refusal is for adds.
  @Test func snapshotInsertIsNotCapped() throws {
    var sidebar = Sidebar()
    for index in 0..<Sidebar.maximumFavorites + 1 {
      let snapshot = NodeSnapshot(
        id: NodeID(), kind: .tab(TabItem(url: url, title: "F\(index)")), createdAt: .now, children: [])
      try sidebar.insert(snapshot, in: .favorites(profile: "default"))
    }
    #expect(sidebar.children(of: .favorites(profile: "default")).count == Sidebar.maximumFavorites + 1)
  }

  @Test func zeroFavoritesIsAllowed() {
    let sidebar = Sidebar()
    #expect(sidebar.children(of: .favorites(profile: "default")).isEmpty)
  }
}
