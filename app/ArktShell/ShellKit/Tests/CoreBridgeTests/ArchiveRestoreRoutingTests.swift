import Archive
import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// The real coordinator, sidebar adapter and Core restore transaction; no window or placement stub.
@MainActor
struct ArchiveRestoreRoutingTests {
  private func fixture(url: URL) async throws -> (ModelSidebarSource, ArchiveCoordinator, RoutingArchiveStore, ArchivedItem, UUID, UUID) {
    let source = ModelSidebarSource()
    let original = try source.addSpace(title: "Original")
    let destination = try source.addSpace(title: "Destination")
    let tab = try source.addTab(url: url, title: "Archived", in: .today(original))
    let store = RoutingArchiveStore()
    let coordinator = ArchiveCoordinator(source: source, store: store)
    let item = try #require(coordinator.archive([tab], reason: .manual).first)
    try #require(await archiveWriteReaches {
      await store.entries[item.id] == item && !coordinator.hasPendingWrites
    })
    return (source, coordinator, store, item, original, destination)
  }

  @Test(arguments: [false, true])
  func explicitMatchUsesOneRestoreMutationAndPreservesSnapshot(exact: Bool) async throws {
    let url = URL(string: exact ? "https://status.example.test/Case?literal=%2F" : "https://docs.example.test/guide")!
    let (source, coordinator, store, item, original, destination) = try await fixture(url: url)
    let other = try source.addSpace(title: "Other")
    let target = exact ? other : destination
    let routing = LinkRouting(routes: [
      .init(condition: .matches("https://unrelated.example.test/"), destination: .space(original)),
      .init(condition: .contains("DOCS.EXAMPLE.TEST"), destination: .space(destination)),
      .init(condition: .matches("https://status.example.test/Case?literal=%2F"), destination: .space(other)),
      .init(condition: .contains("example.test"), destination: .space(original)),
    ])
    coordinator.linkRoutingProvider = { routing }
    var appearances: [SidebarLocation] = []
    source.onDidChange = { _ in
      if let parent = source.parent(of: item.id) { appearances.append(parent) }
    }
    defer { source.onDidChange = nil }

    let result = try #require(try coordinator.restore(item, fallbackSpace: original))

    #expect(result.nodeID == item.id)
    #expect(result.space == target)
    #expect(result.location == .today(target))
    #expect(appearances == [.today(target)])
    #expect(source.sidebar.snapshot(of: item.id) == item.snapshot)
    #expect(source.children(of: .today(original)).isEmpty)
    try #require(await archiveWriteReaches {
      await store.removals == [[item.id]] && !coordinator.hasPendingWrites
    })
    #expect(await store.removals == [[item.id]])
    #expect(await store.entries.isEmpty)
  }

  @Test func unavailableSnapshotRetainsEntryAndAllowsRetry() async throws {
    let (source, coordinator, store, item, original, destination) = try await fixture(url: URL(string: "https://docs.example.test/")!)
    var available: LinkRouting?
    coordinator.linkRoutingProvider = { available }
    #expect(throws: ArchiveCoordinator.RestoreError.routingUnavailable) {
      try coordinator.restore(item, fallbackSpace: original)
    }
    #expect(source.sidebar.snapshot(of: item.id) == nil)
    #expect(!coordinator.isRestored(item.id))
    #expect(await store.entries[item.id] == item)
    #expect(await store.removals.isEmpty)
    available = LinkRouting(routes: [.init(condition: .contains("DOCS.EXAMPLE.TEST"), destination: .space(destination))])
    #expect(try coordinator.restore(item, fallbackSpace: original)?.space == destination)
    try #require(await archiveWriteReaches {
      await store.removals == [[item.id]] && !coordinator.hasPendingWrites
    })
    #expect(await store.removals == [[item.id]])
  }

  @Test(arguments: [0, 1, 2, 3])
  func unavailableExplicitDestinationCannotFallBack(kind: Int) async throws {
    let (source, coordinator, store, item, original, _) = try await fixture(url: URL(string: "https://docs.example.test/")!)
    let foreign = source.mutate { $0.addSpace(title: "Foreign", profile: "other") }
    let targets: [LinkRouting.Destination] = [.littleArkt, .mostRecentSpace, .space(UUID()), .space(foreign)]
    let routing = LinkRouting(routes: [.init(condition: .contains("docs.example.test"), destination: targets[kind])])
    coordinator.linkRoutingProvider = { routing }
    #expect(throws: ArchiveCoordinator.RestoreError.routingDestinationUnavailable) {
      try coordinator.restore(item, fallbackSpace: original)
    }
    #expect(source.sidebar.snapshot(of: item.id) == nil)
    #expect(!coordinator.isRestored(item.id))
    #expect(await store.entries[item.id] == item)
    #expect(await store.removals.isEmpty)
    #expect(!coordinator.hasPendingWrites)
  }

  @Test func noExplicitMatchPreservesHistoricalArchivePlacement() async throws {
    let (source, coordinator, store, item, original, destination) = try await fixture(url: URL(string: "https://docs.example.test/")!)
    let routing = LinkRouting(routes: [.init(condition: .matches("https://unrelated.example.test/"), destination: .space(destination))],
                              defaultDestination: .littleArkt)
    coordinator.linkRoutingProvider = { routing }
    #expect(try coordinator.restore(item, fallbackSpace: destination)?.space == original)
    #expect(source.children(of: .today(original)) == [item.id])
    #expect(source.children(of: .today(destination)).isEmpty)
    try #require(await archiveWriteReaches {
      await store.removals == [[item.id]] && !coordinator.hasPendingWrites
    })
    #expect(await store.removals == [[item.id]])
  }
}

private actor RoutingArchiveStore: ArchiveStoring {
  private(set) var entries: [UUID: ArchivedItem] = [:]
  private(set) var removals: [[UUID]] = []
  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int {
    for item in items { entries[item.id] = item }
    return items.count
  }
  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage {
    let found = entries.values.filter(filter.matches).sorted { $0.archivedAt > $1.archivedAt }
    return ArchivePage(items: limit.map { Array(found.prefix($0)) } ?? found, unreadable: 0)
  }
  func remove(_ ids: [UUID]) async throws {
    removals.append(ids)
    for id in ids { entries[id] = nil }
  }
  func count(matching filter: ArchiveFilter) async throws -> Int { entries.values.filter(filter.matches).count }
  func removeAll() async throws { entries.removeAll() }
}

/// Waits for ordinary store/writer state rather than racing the production termination deadline. A finite
/// yield bound follows the canonical archive tests and fails the requirement if the expected write never arrives.
@MainActor
private func archiveWriteReaches(_ condition: @MainActor () async -> Bool) async -> Bool {
  for _ in 0..<20_000 {
    if await condition() { return true }
    await Task.yield()
  }
  return false
}
