import Archive
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

/// #111: store-side Archive search (the folded `search_text` column), counts and the education banner flag.
struct ArchiveStoreSearchTests {
  static func at(_ seconds: Double) -> Date { ArchiveStoreTests.at(seconds) }

  static func tab(_ title: String, _ url: String, at seconds: Double = 1) -> NodeSnapshot {
    NodeSnapshot(kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: Self.at(0))
  }

  static func item(_ snapshot: NodeSnapshot, at seconds: Double, source: ArchiveSource = .unknown,
                   reason: ArchiveReason = .manual) -> ArchivedItem {
    ArchivedItem(reason: reason, archivedAt: Self.at(seconds), source: source, snapshot: snapshot)
  }

  @Test func searchIgnoresCaseAndDiacriticsBeyondASCII() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let umlaut = Self.item(Self.tab("Übersicht der Ergebnisse", "https://a.example/1"), at: 1)
    let accent = Self.item(Self.tab("Crème brûlée", "https://b.example/2"), at: 2)
    _ = try await store.add([umlaut, accent], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(text: "ubersicht")).items == [umlaut])
    #expect(try await store.items(matching: ArchiveFilter(text: "ÜBER")).items == [umlaut])
    #expect(try await store.items(matching: ArchiveFilter(text: "creme BRULEE")).items == [accent])
    #expect(try await store.items(matching: ArchiveFilter(text: "  brûlée ")).items == [accent])
    #expect(try await store.items(matching: ArchiveFilter(text: "   ")).items.count == 2)
  }

  /// A folder matches through any tab inside it (title or URL), at any depth; a split through its panes.
  @Test func searchCoversFolderChildrenAndSplitPanes() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let folder = Self.item(NodeSnapshot(
      kind: .folder(FolderItem(title: "Research")), createdAt: Self.at(0),
      children: [NodeSnapshot(kind: .folder(FolderItem(title: "Inner")), createdAt: Self.at(0),
                              children: [Self.tab("Lichens", "https://fieldguide.example/moss")])]), at: 1)
    let split = Self.item(NodeSnapshot(
      kind: .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])), createdAt: Self.at(0),
      children: [Self.tab("Left pane", "https://left.example"), Self.tab("Right pane", "https://right.example")]),
      at: 2)
    _ = try await store.add([folder, split], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(text: "fieldguide")).items == [folder])
    #expect(try await store.items(matching: ArchiveFilter(text: "lichens")).items == [folder])
    #expect(try await store.items(matching: ArchiveFilter(text: "right pane")).items == [split])
    #expect(try await store.items(matching: ArchiveFilter(text: "pane")).items == [split])
  }

  /// `.replace` rewrites the search text with the rest of the row.
  @Test func replaceRewritesTheSearchText() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let id = NodeID()
    let first = Self.item(NodeSnapshot(id: id, kind: .tab(TabItem(url: URL(string: "https://a.example")!,
                                                                  title: "Alpha")), createdAt: Self.at(0)), at: 1)
    let second = Self.item(NodeSnapshot(id: id, kind: .tab(TabItem(url: URL(string: "https://b.example")!,
                                                                   title: "Beta")), createdAt: Self.at(0)), at: 2)
    _ = try await store.add([first], onConflict: .replace)
    _ = try await store.add([second], onConflict: .replace)
    #expect(try await store.items(matching: ArchiveFilter(text: "alpha")).items.isEmpty)
    #expect(try await store.items(matching: ArchiveFilter(text: "beta")).items == [second])
  }

  @Test func countMatchingAppliesEveryFilter() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let space = SpaceID()
    _ = try await store.add([
      Self.item(Self.tab("Report", "https://a.example/1"), at: 1, source: .space(space)),
      Self.item(Self.tab("Report", "https://a.example/2"), at: 2, source: .space(space), reason: .auto),
      Self.item(Self.tab("Other", "https://a.example/3"), at: 3, source: .littleArc, reason: .auto),
    ], onConflict: .replace)
    #expect(try await store.count(matching: ArchiveFilter()) == 3)
    #expect(try await store.count(matching: ArchiveFilter(text: "report")) == 2)
    #expect(try await store.count(matching: ArchiveFilter(source: .space(space), reason: .auto)) == 1)
    #expect(try await store.count(matching: ArchiveFilter(source: .littleArc, text: "report")) == 0)
  }

  /// `v4-archive-search` adds the column and fills it from each stored snapshot (folder children included); a row
  /// whose snapshot does not decode falls back to its title and URL columns.
  @Test func migrationBackfillsTheSearchTextOfExistingRows() async throws {
    let queue = try DatabaseQueue(configuration: ArktDatabase.configuration)
    try ArktDatabase.migrator.migrate(queue, upTo: "v3-settings")
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "Trips")), createdAt: Self.at(0),
                              children: [Self.tab("Müllerstraße", "https://map.example/x")])
    let body = try SidebarStorageFormat.makeEncoder().encode(folder)
    try await queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO archived_item (id, format_version, reason, archived_at, source_kind, title, url, snapshot)
          VALUES (?, 1, 'manual', ?, 'unknown', 'Trips', NULL, ?), (?, 1, 'manual', ?, 'unknown', 'Brûlé', ?, x'00')
          """,
        arguments: [folder.id.uuidString, Self.at(1).timeIntervalSinceReferenceDate, body,
                    UUID().uuidString, Self.at(2).timeIntervalSinceReferenceDate, "https://broken.example"])
    }
    try ArktDatabase.migrator.migrate(queue)
    let texts = try await queue.read { db in
      try String.fetchAll(db, sql: "SELECT search_text FROM archived_item ORDER BY archived_at")
    }
    #expect(texts.count == 2)
    #expect(texts[0].contains("mullerstraße") || texts[0].contains("mullerstrasse"))
    #expect(texts[0].contains("map.example"))
    #expect(texts[1].contains("brule"))
    #expect(texts[1].contains("broken.example"))
    let store = ArchiveStore(database: ArktDatabase(writer: queue))
    #expect(try await store.items(matching: ArchiveFilter(text: "muller")).items.map(\.id) == [folder.id])
  }

  // MARK: - Clear Archive and the education banner

  @Test func removeAllAlsoEmptiesTheCount() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    _ = try await store.add([Self.item(Self.tab("A", "https://a.example"), at: 1)], onConflict: .replace)
    try await store.removeAll()
    #expect(try await store.count(matching: ArchiveFilter()) == 0)
  }

  @Test func educationBannerDismissalPersistsAndKeepsTheAutoArchiveStart() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    #expect(try await store.isEducationBannerDismissed() == false)
    let started = try await store.resolveAutoArchiveStart(now: Self.at(5))
    try await store.dismissEducationBanner(at: Self.at(9))
    #expect(try await store.isEducationBannerDismissed())
    #expect(try await store.load(ArchiveState.self).autoArchiveStartedAt == started)
  }
}
