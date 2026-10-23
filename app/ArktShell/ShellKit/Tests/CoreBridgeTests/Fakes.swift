import Archive
import ArcImport
import CoreBridge
import CryptoKit
import Foundation
import SidebarModel
import Testing

struct FakeStoreError: Error {}

/// In-memory `ArchiveStoring` that honors the conflict policy, so a repeated `.keepExisting` add writes 0.
actor FakeArchiveStore: ArchiveStoring {
  struct AddCall: Equatable, Sendable {
    var ids: [NodeID]
    var policy: ArchiveConflictPolicy
  }

  /// Every store call in arrival order.
  enum Call: Equatable, Sendable {
    case add([NodeID])
    case remove([NodeID])
  }

  private(set) var calls: [Call] = []
  private(set) var addCalls: [AddCall] = []
  private(set) var addedItems: [[ArchivedItem]] = []
  private(set) var removeCalls: [[NodeID]] = []
  private(set) var stored: [NodeID: ArchivedItem] = [:]
  private var failsAdds = false
  private var failsRemoves = false
  private var holdsAdds = false
  private var heldAdds: [CheckedContinuation<Void, Never>] = []

  func setFailsAdds(_ fails: Bool) { failsAdds = fails }
  func setFailsRemoves(_ fails: Bool) { failsRemoves = fails }
  /// While true, `add` parks after recording the call until `releaseAdds()`.
  func holdAdds() { holdsAdds = true }

  func releaseAdds() {
    holdsAdds = false
    for held in heldAdds { held.resume() }
    heldAdds = []
  }

  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int {
    addCalls.append(AddCall(ids: items.map(\.id), policy: policy))
    calls.append(.add(items.map(\.id)))
    addedItems.append(items)
    if holdsAdds { await withCheckedContinuation { heldAdds.append($0) } }
    if failsAdds { throw FakeStoreError() }
    var written = 0
    for item in items {
      if policy == .keepExisting, stored[item.id] != nil { continue }
      stored[item.id] = item
      written += 1
    }
    return written
  }

  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage {
    let items = stored.values.sorted { $0.archivedAt > $1.archivedAt }
    return ArchivePage(items: limit.map { Array(items.prefix($0)) } ?? items, unreadable: 0)
  }

  func remove(_ ids: [NodeID]) async throws {
    removeCalls.append(ids)
    calls.append(.remove(ids))
    if failsRemoves { throw FakeStoreError() }
    for id in ids { stored[id] = nil }
  }
}

/// In-memory `ArchiveStateStoring` that records every clock reset. The resolved start is the last reset, else the
/// stored start (`setStarted`), else `now` (which is then stored, like `SettingsStore`).
actor FakeArchiveState: ArchiveStateStoring {
  private(set) var resets: [Date] = []
  private var started: Date?
  private var settings = ArchiveSettings()
  private var failsResets = false
  private var failsLoads = false

  func setFailsResets(_ fails: Bool) { failsResets = fails }
  func setFailsLoads(_ fails: Bool) { failsLoads = fails }
  func setStarted(_ date: Date) { started = date }
  func setSettings(_ settings: ArchiveSettings) { self.settings = settings }

  private var holdsLoads = false
  private var heldLoads: [CheckedContinuation<Void, Never>] = []
  /// While true, `resolveAutoArchiveStart` parks until `releaseLoads()`.
  func holdLoads() { holdsLoads = true }
  var heldLoadCount: Int { heldLoads.count }

  func releaseLoads() {
    holdsLoads = false
    for held in heldLoads { held.resume() }
    heldLoads = []
  }

  func resolveAutoArchiveStart(now: Date) async throws -> Date {
    if holdsLoads { await withCheckedContinuation { heldLoads.append($0) } }
    if failsLoads { throw FakeStoreError() }
    if let last = resets.last { return last }
    if started == nil { started = now }
    return started ?? now
  }

  func resetAutoArchiveStart(to date: Date) async throws {
    if failsResets { throw FakeStoreError() }
    resets.append(date)
  }

  func loadArchiveSettings() async throws -> ArchiveSettings {
    if failsLoads { throw FakeStoreError() }
    return settings
  }
}

/// In-memory `ArcImportRecordStoring` that unions like `SettingsStore` and records every write.
actor FakeArcImportRecordStore: ArcImportRecordStoring {
  private(set) var stored: ArcImportRecord
  private(set) var writes: [ArcImportRecord] = []
  private var failsLoads = false
  private var failsWrites = false

  init(_ stored: ArcImportRecord = ArcImportRecord()) { self.stored = stored }

  func setFailsLoads(_ fails: Bool) { failsLoads = fails }
  func setFailsWrites(_ fails: Bool) { failsWrites = fails }

  func loadArcImportRecord() async throws -> ArcImportRecord {
    if failsLoads { throw FakeStoreError() }
    return stored
  }

  func recordArcImport(_ record: ArcImportRecord, at date: Date) async throws {
    if failsWrites { throw FakeStoreError() }
    writes.append(record)
    stored.formUnion(record)
  }
}

/// Stands in for the app's autosaver flush: remembers each sidebar it was asked to save and returns `succeeds`.
@MainActor
final class FakeSidebarPersist {
  var succeeds = true
  private(set) var saved: [SidebarModel.Sidebar] = []

  func persist(_ sidebar: SidebarModel.Sidebar) async -> Bool {
    saved.append(sidebar)
    return succeeds
  }
}

/// A temp folder laid out like Arc's data folder, holding copies of the synthetic fixtures (never real Arc data):
/// `StorableSidebar.json`, optionally `StorableArchiveItems.json` (the fixture, or `archive` bytes), and one favicon
/// in `SidebarItemsFaviconCache/`.
/// Removed on deinit. `unchanged()` proves the import only read it.
final class ArcFixtureFolder {
  /// The Beta Space's Today tab; the one fixture tab with a favicon file.
  static let faviconTabID = "A0000000-0000-4000-8000-000000000221"
  static let favicon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x2A])
  static let alphaID = "A0000000-0000-4000-8000-0000000000A1"
  static let betaID = "A0000000-0000-4000-8000-0000000000B1"
  /// The two top-level Favorites (default profile).
  static let mailFavoriteID = "A0000000-0000-4000-8000-000000000311"
  static let calendarFavoriteID = "A0000000-0000-4000-8000-000000000312"
  /// Every title and URL fragment in the fixture that a counts-only text must never contain.
  static let userStrings = [
    "Alpha", "Beta", "Reading", "Example", "Renamed", "example.com", "http", "mail", "wiki", "news", "articles",
  ]

  let url: URL
  private let digests: [String: SHA256.Digest]

  /// `mutateGlobal` edits the sidebar file's global container (as `[String: Any]`) before it is written.
  init(
    sidebar: Data? = nil, includeArchive: Bool = true, archive: Data? = nil,
    mutateGlobal: ((inout [String: Any]) throws -> Void)? = nil
  ) throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArcFixtureFolder-\(UUID().uuidString)", isDirectory: true)
    let favicons = url.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true)
    try FileManager.default.createDirectory(at: favicons, withIntermediateDirectories: true)
    var sidebarData = try sidebar ?? Self.fixture("StorableSidebar-synthetic")
    if let mutateGlobal { sidebarData = try Self.mutated(sidebarData, mutateGlobal) }
    try sidebarData.write(to: url.appendingPathComponent("StorableSidebar.json"))
    if includeArchive {
      try (archive ?? Self.fixture("StorableArchiveItems-synthetic"))
        .write(to: url.appendingPathComponent("StorableArchiveItems.json"))
    }
    try Self.favicon.write(
      to: favicons.appendingPathComponent(ArcFaviconCache.fileName(forItemID: Self.faviconTabID)))
    digests = try Self.digests(of: url)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  var files: ArcSourceFiles { ArcSourceFiles(directory: url) }

  /// Same files with the same bytes as when the folder was made.
  func unchanged() throws -> Bool { try Self.digests(of: url) == digests }

  static func fixture(_ name: String) throws -> Data {
    let file = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: file)
  }

  private static func digests(of directory: URL) throws -> [String: SHA256.Digest] {
    var result: [String: SHA256.Digest] = [:]
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    while let file = enumerator?.nextObject() as? URL {
      guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
      result[file.path] = SHA256.hash(data: try Data(contentsOf: file))
    }
    return result
  }

  private static func mutated(_ data: Data, _ change: (inout [String: Any]) throws -> Void) throws -> Data {
    var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var sidebar = try #require(root["sidebar"] as? [String: Any])
    var containers = try #require(sidebar["containers"] as? [Any])
    var global = try #require(containers[1] as? [String: Any])
    try change(&global)
    containers[1] = global
    sidebar["containers"] = containers
    root["sidebar"] = sidebar
    return try JSONSerialization.data(withJSONObject: root)
  }

  // MARK: Global container edits (flat `[k0, v0, k1, v1, ...]` arrays)

  /// Drops the entry under `id` from the flat array `field`.
  static func removeEntry(_ id: String, in field: String, of global: inout [String: Any]) throws {
    var flat = try #require(global[field] as? [Any])
    let index = try #require(stride(from: 0, to: flat.count, by: 2).first { flat[$0] as? String == id })
    flat.removeSubrange(index...(index + 1))
    global[field] = flat
  }

  /// Rewrites the object stored under `id` in the flat array `field`.
  static func mutateEntry(
    _ id: String, in field: String, of global: inout [String: Any], _ change: (inout [String: Any]) -> Void
  ) throws {
    var flat = try #require(global[field] as? [Any])
    let index = try #require(stride(from: 0, to: flat.count, by: 2).first { flat[$0] as? String == id })
    var value = try #require(flat[index + 1] as? [String: Any])
    change(&value)
    flat[index + 1] = value
    global[field] = flat
  }

  /// Appends `key, value` to the flat array `field`.
  static func appendEntry(_ key: Any, _ value: Any, in field: String, of global: inout [String: Any]) throws {
    var flat = try #require(global[field] as? [Any])
    flat.append(key)
    flat.append(value)
    global[field] = flat
  }
}
