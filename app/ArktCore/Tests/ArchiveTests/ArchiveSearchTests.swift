import Archive
import Foundation
import SidebarModel
import Testing

/// #111: the Archive search folds text the same way for the store's `search_text` column and for in-memory checks
/// (which folder child matched, the match highlight), so both always agree.
struct ArchiveSearchTests {
  private static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private static func tab(_ title: String, _ url: String, custom: String? = nil) -> NodeSnapshot {
    NodeSnapshot(kind: .tab(TabItem(url: URL(string: url)!, title: title, customTitle: custom)), createdAt: date)
  }

  @Test(arguments: [
    ("Übersicht", "ubersicht"),
    ("CAFÉ", "cafe"),
    ("ｆｕｌｌ", "full"),
    ("Mixed Case", "mixed case"),
  ])
  func foldIgnoresCaseDiacriticsAndWidth(_ input: String, _ folded: String) {
    #expect(ArchiveSearch.fold(input) == folded)
  }

  @Test func queryTrimsWhitespaceAndFolds() {
    #expect(ArchiveSearch.query("  Über ") == "uber")
    #expect(ArchiveSearch.query("   ") == nil)
    #expect(ArchiveSearch.query(nil) == nil)
  }

  @Test func searchTextCoversTitlesURLsAndEveryDescendant() {
    let folder = NodeSnapshot(
      kind: .folder(FolderItem(title: "Research")), createdAt: Self.date,
      children: [
        Self.tab("Q3 Report outline", "https://docs.example/q3"),
        NodeSnapshot(kind: .folder(FolderItem(title: "Nested")), createdAt: Self.date,
                     children: [Self.tab("Deep", "https://deep.example/ÿ", custom: "Renamed")]),
      ])
    let text = ArchiveSearch.searchText(of: folder)
    for part in ["research", "q3 report outline", "https://docs.example/q3", "nested", "deep", "renamed",
                 "deep.example"] {
      #expect(text.contains(part), "\(part)")
    }
  }

  @Test func matchesAreFoldedSubstrings() throws {
    let tab = Self.tab("Café Menu", "https://menu.example/a")
    #expect(ArchiveSearch.matches(tab, query: try #require(ArchiveSearch.query("CAFE"))))
    #expect(ArchiveSearch.matches(tab, query: try #require(ArchiveSearch.query("menu.example"))))
    #expect(!ArchiveSearch.matches(tab, query: try #require(ArchiveSearch.query("zebra"))))
  }

  /// A folder or split that matched only through a tab inside lists those tabs; one whose own title matches lists
  /// none (it is shown closed, design section 4).
  @Test func matchingTabsOnlyWhenTheRootItselfDoesNotMatch() throws {
    let match = Self.tab("Q3 report outline", "https://docs.example/q3")
    let other = Self.tab("Budget", "https://sheets.example/b")
    let nested = Self.tab("Report card", "https://school.example")
    let folder = NodeSnapshot(
      kind: .folder(FolderItem(title: "Research")), createdAt: Self.date,
      children: [match, other, NodeSnapshot(kind: .folder(FolderItem(title: "Inner")), createdAt: Self.date,
                                            children: [nested])])
    let report = try #require(ArchiveSearch.query("report"))
    #expect(ArchiveSearch.matchingTabs(in: folder, query: report).map(\.id) == [match.id, nested.id])
    let research = try #require(ArchiveSearch.query("research"))
    #expect(ArchiveSearch.matchingTabs(in: folder, query: research).isEmpty)
    #expect(ArchiveSearch.matchingTabs(in: match, query: report).isEmpty, "a tab has no children to open")
  }
}
