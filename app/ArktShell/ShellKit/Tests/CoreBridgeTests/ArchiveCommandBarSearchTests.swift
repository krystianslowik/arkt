import Archive
import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// #111 (BH-087, BH-104): the command bar's archived matches come from the store search, newest first, at most three,
/// worded "host, Space, archived <when>"; Enter restores through the coordinator with the restore toast.
@MainActor
struct ArchiveCommandBarSearchTests {
  private static let now = Date(timeIntervalSinceReferenceDate: 900_000_000)   // Monday 9 July 2029, 16:00 GMT
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
  }

  private static func tab(_ title: String, url: String, ago: TimeInterval, source: ArchiveSource) -> ArchivedItem {
    ArchivedItem(reason: .manual, archivedAt: now.addingTimeInterval(-ago), source: source, section: .today,
                 snapshot: NodeSnapshot(kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: now))
  }

  private static func make(_ items: [ArchivedItem]) throws -> (ArchiveCommandBarSearch, ModelSidebarSource, UUID,
                                                               PagedArchiveStore) {
    let source = ModelSidebarSource(now: { now })
    let work = try source.addSpace(title: "Work")
    let store = PagedArchiveStore(items: items)
    let coordinator = ArchiveCoordinator(source: source, store: store, now: { now })
    let search = ArchiveCommandBarSearch(source: source, store: store, coordinator: coordinator, now: { now },
                                         locale: Locale(identifier: "en_US"), calendar: calendar)
    return (search, source, work, store)
  }

  @Test func matchesAreWordedNewestFirstAndCapped() async throws {
    let (bar, _, work, store) = try Self.make([])
    await store.seed([
      Self.tab("Expense report template", url: "https://sheets.example/t", ago: 86_400 * 17, source: .space(work)),
      Self.tab("Expense older", url: "https://a.example", ago: 86_400 * 20, source: .littleArc),
      Self.tab("Expense new", url: "https://b.example", ago: 7200, source: .space(work)),
      Self.tab("Expense oldest", url: "https://c.example", ago: 86_400 * 25, source: .unknown),
      Self.tab("Lichens", url: "https://d.example", ago: 60, source: .space(work)),
    ])

    let matches = await bar.matches(for: "EXPENSE")

    #expect(matches.map(\.title) == ["Expense new", "Expense report template", "Expense older"])
    #expect(matches[0].subtitle == "b.example, Work, archived 2h ago")
    #expect(matches[1].subtitle == "sheets.example, Work, archived Jun 22")
    #expect(matches[2].subtitle == "a.example, Little Arkt, archived Jun 19")
    #expect(await bar.matches(for: "   ").isEmpty)
    #expect(await store.limits.last == 3, "the store returns three at most")
  }

  @Test func restoringAMatchGoesThroughTheCoordinator() async throws {
    let (bar, source, work, store) = try Self.make([])
    let item = Self.tab("Expense", url: "https://sheets.example", ago: 60, source: .unknown)
    await store.seed([ArchivedItem(reason: item.reason, archivedAt: item.archivedAt, source: .space(work),
                                   section: .today, snapshot: item.snapshot)])
    var toasts: [String] = []
    bar.onRestored = { _, text in toasts.append(text) }
    let match = try #require(await bar.matches(for: "expense").first)

    bar.restore(match.id)

    #expect(toasts == ["Tab restored to Work. Click to view."])
    #expect(source.sidebar.children(of: .today(work)).count == 1)
    bar.restore(match.id)
    #expect(toasts.count == 1, "restored once")
  }

  @Test func aCancelledOlderReplyKeepsTheNewerMatchesRestorable() async throws {
    let (bar, source, work, store) = try Self.make([])
    await store.seed([
      Self.tab("Expense report", url: "https://sheets.example", ago: 60, source: .space(work)),
      Self.tab("Exponent notes", url: "https://notes.example", ago: 30, source: .space(work)),
    ])
    await store.holdReads()
    let older = Task { await bar.matches(for: "expo") }
    while await store.heldReadCount < 1 { await Task.yield() }
    let newer = Task { await bar.matches(for: "expense") }
    while await store.heldReadCount < 2 { await Task.yield() }

    await store.releaseLastRead()
    let shown = await newer.value
    older.cancel()                                  // the bar drops the older query's task
    await store.releaseReads()
    #expect(await older.value.isEmpty)

    let match = try #require(shown.first)
    #expect(match.title == "Expense report")
    bar.restore(match.id)
    #expect(source.sidebar.children(of: .today(work)).count == 1, "the shown match still restores")
  }
}
