import Archive
import CoreBridge
import Foundation
import SidebarModel
import Testing

/// E5c: archived nodes keep their favicons through the launch prune, so a restore under the same id shows it again.
struct FaviconRetentionTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)

  private static func tab(_ id: UUID = UUID()) -> NodeSnapshot {
    NodeSnapshot(id: id, kind: .tab(TabItem(url: URL(string: "https://a.example")!, title: "A")), createdAt: now)
  }

  private static func entry(_ snapshot: NodeSnapshot) -> ArchivedItem {
    ArchivedItem(reason: .manual, archivedAt: now, source: .unknown, snapshot: snapshot)
  }

  @Test func idsCoverTheRootAndEveryDescendant() {
    let inner = Self.tab()
    let nested = NodeSnapshot(kind: .folder(FolderItem(title: "Inner")), createdAt: Self.now, children: [inner])
    let first = Self.tab()
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "Outer")), createdAt: Self.now, children: [first, nested])

    #expect(FaviconRetention.ids(in: folder) == [folder.id, first.id, nested.id, inner.id])
  }

  @Test func keptIDsAreTheSidebarPlusEveryArchivedNode() async {
    let child = Self.tab()
    let split = NodeSnapshot(
      kind: .split(SplitItem(orientation: .horizontal, widthFactors: [1])), createdAt: Self.now, children: [child])
    let lone = Self.tab()
    let store = PagedArchiveStore(items: [Self.entry(split), Self.entry(lone)], unreadable: 2)
    let sidebar: Set<UUID> = [UUID(), UUID()]

    let kept = await FaviconRetention.keptIDs(sidebar: sidebar, archive: store)

    #expect(kept == sidebar.union([split.id, child.id, lone.id]))
    #expect(await store.limits == [nil], "one read of the whole archive")
  }

  @Test func unreadableArchiveMeansNoPrune() async {
    let store = PagedArchiveStore(items: [Self.entry(Self.tab())])
    await store.setFails(true)

    #expect(await FaviconRetention.keptIDs(sidebar: [UUID()], archive: store) == nil)
  }
}
