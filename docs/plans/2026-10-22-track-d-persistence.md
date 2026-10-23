# Track D: Persistence and Archive Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** Make Arkt's in-memory sidebar durable and give it Arc's archive: a versioned, deterministic, validated
storage format for `Sidebar`; a GRDB/SQLite store with rolling backups and corruption fallback; a debounced background
writer the main thread never waits on; an archive model, store, restore path and a pure auto-archive policy that
matches Arc 1.168.0 (parity spec BH-048, BH-054, BH-071, BH-076, BH-080 to BH-088, BH-090, BH-137, BH-179); a
read-only importer for Arc's `StorableArchiveItems.json`; and typed, persisted archive settings with Arc's defaults.

**Architecture:** The in-memory `Sidebar` value stays the source of truth (design 4, 5). `SidebarModel` gains
`Codable` through a nested, versioned document (`NodeSnapshot` trees per section), so parent links and child order
cannot disagree in a file and decoding re-validates every invariant through the same code paths the UI uses. A new
pure target `Archive` holds `ArchivedItem`, `Archiver` (archive/restore), `AutoArchivePolicy` and `ArchiveSettings`.
A new target `Persistence` is the only one that links GRDB: one SQLite file (`Arkt.sqlite`) with three tables
(`sidebar_snapshot`, `archived_item`, `setting`), forward-only migrations, a whole-sidebar snapshot written in one
transaction, file-level rolling backups (5, made with SQLite's backup API into a temp file then renamed), and a
launch path that quarantines a bad file and restores the newest usable backup. `SidebarAutosaver` (main-actor,
synchronous `scheduleSave`) coalesces changes and hands the newest sidebar to `@concurrent` store methods, so
encoding and disk I/O never run on the main thread. `ArcImport` gains `ArcArchiveFile` + `ArcArchiveImporter` and a
counts-only extension of `arkt-import-check`.

**Tech Stack:** Swift 6 language mode (strict concurrency), Swift 6.4 toolchain, SwiftPM, Swift Testing
(`import Testing`), Foundation, CryptoKit, Synchronization (`Mutex`, tests), GRDB.swift 7.11.1 (exact pin), system
SQLite.

---

## Rules (read before every task)

- `$WT` = `/path/to/arkt-wt/track-d`, branch `track-d`. Package root:
  `$WT/app/ArktCore`. Work only in this worktree.
- Shell is zsh. Set once per shell: `WT=/path/to/arkt-wt/track-d`.
- A Chromium build saturates the CPU. Every build/test runs as `nice -n 10 swift test -j 2` (or
  `nice -n 10 swift build -j 2`, `nice -n 10 swift run -j 2 ...`). Never drop `nice` or `-j 2`.
- Swift 6 strict concurrency, macOS 15 deployment target. No `@unchecked Sendable` in production code, no
  `nonisolated(unsafe)`. Fix concurrency diagnostics at the root.
- No emojis anywhere (code, comments, fixtures, commit messages).
- Privacy: test fixtures are synthetic. Never open, cat, copy or grep the user's real Arc data
  (`~/Library/Application Support/Arc`). The only allowed contact is running the counts-only `arkt-import-check`
  CLI (Task D5b). Never write anything into Arc's directory; Arkt's own data lives elsewhere.
- Commits: one per task, staged with explicit pathspecs (`git add <paths>`, never `git add -A` or `git add .`),
  Plain commit messages.
- TDD: write the test, run it and watch it fail (compile errors count as failing), implement, run again, commit.
- Baseline before D1: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2` reports 88 tests passing. Expected counts
  below are cumulative (Swift Testing counts `@Test` functions; a parameterized test counts once).
- GRDB API was checked against the 7.11.1 sources: `DatabaseQueue(path:)`, `DatabaseQueue()` (in memory),
  `DatabaseMigrator.registerMigration(_:migrate:)`, `migrate(_:)`, `migrate(_:upTo:)`,
  `completedMigrations(_:)`, `hasCompletedMigrations(_:)`, async `write`/`read` taking `@Sendable` closures,
  `DatabaseReader.backup(to:)`, `DatabaseQueue.close()`, `Database.changesCount`, `Row: Sendable`.
  `StatementArguments` is NOT `Sendable`: always build arguments inside the database closure.

## Design decisions (fixed for this track)

1. **Storage format (D1).** JSON, version 1, nested: `{version, spaces: [{space, pinned: [NodeSnapshot], today:
   [NodeSnapshot]}], favorites: [{profile, items: [NodeSnapshot]}]}`. Spaces follow `spaceOrder`, children follow
   `childOrder`, favorites are sorted by profile, keys are sorted by the encoder (`.sortedKeys`). Dates use
   `.deferredToDate` (Double seconds since 2001, Arc's convention): Swift's JSON writer emits the shortest
   round-tripping Double, so `decode(encode(x)) == x` holds exactly; a test pins this with fractional dates. IDs are
   kept: decoding goes through new id-preserving APIs (`addSpace(_ space:)`, `insert(_ snapshot:in:at:)`), never
   through the id-minting `add*` calls. Per-window UI state (expanded folders, sidebar width, last focused Space:
   data-model 3.1) is deliberately not part of the sidebar document; it gets its own table in a later track.
2. **One database file, whole-sidebar blob (D2).** `sidebar_snapshot` holds exactly one row (`id = 1`) with the D1
   bytes, a SHA-256 and the format version, replaced in one transaction. Rationale: reuses the deterministic bytes,
   matches "whole-sidebar snapshots", makes partial-update bugs impossible; a normalized schema is a later
   optimization only if profiling asks for it. A write whose SHA equals the stored one is skipped.
3. **Atomicity and backups (D2b).** The live file is atomic through SQLite transactions with the default rollback
   journal (`journal_mode=delete`, asserted by a test), so the file is self-contained and never needs `-wal` care.
   The design's "temp file + rename" applies to backups: `Backups/Arkt-<UTC stamp>.sqlite` is written by SQLite's
   online backup API into a hidden temp file and renamed into place; the newest 5 are kept. Backups are made on
   launch after a successful load, before a schema migration, and periodically by the app (cadence: open
   question). They are NOT made per debounced save (that would turn 5 backups into the last few seconds of edits).
4. **Corruption fallback (D2b).** On launch: open + migrate + `PRAGMA quick_check` + checksum + decode. Any failure
   quarantines the live file (renamed to `Arkt.sqlite.corrupt-<stamp>`, never deleted), then backups are tried
   newest first, each through a copy so a backup file is never opened or migrated in place. The outcome says which
   path won so the app can tell the user.
5. **Writer (D3).** `@MainActor final class SidebarAutosaver`: `scheduleSave(_:)` is synchronous and only stores the
   value and arms a timer. The first change opens a window of `delay` (default 500 ms); changes inside it coalesce;
   when it closes the newest sidebar is written. Writes never overlap. A change that arrives during a write opens a
   new window after the write. A failed write keeps the newest value pending and retries with backoff 1, 2, 5, 15,
   30 s (last repeats). `flush()` (app termination) cancels the timer and any backoff, makes one immediate attempt
   and reports success. Time is injected as a `sleep` closure; tests drive it with a hand-written `ManualSleeper`
   (full code in D3), so no third-party clock dependency is added. Ordering is guaranteed because the newest value
   is replaced synchronously on the main actor (a `nonisolated` actor entry that spawns a `Task` per call could
   reorder saves).
6. **GRDB.swift 7.11.1, exact pin.** Latest release (tag v7.11.1, 2026-06-18, four months old). GRDB 7 is the
   Swift 6 / Sendable-audited line (`DatabaseWriter: Sendable`, async `read`/`write` that run on GRDB's own serial
   queue, not on the caller's thread), has first-class forward-only migrations, exposes SQLite's online backup API,
   uses the system SQLite (no binary to ship), and its manifest (tools 6.1, macOS 10.15 floor) builds with our 6.4
   toolchain. Exact pin because the on-disk format and SQLite behavior are user data: upgrades are deliberate,
   reviewed commits. `Package.resolved` is committed.
7. **Archive (D4).** `ArchivedItem {reason, archivedAt, source, snapshot: NodeSnapshot}` mirrors Arc's
   `StorableArchiveItems` entry (data-model 2.2); the entry id is the archived root node's id (Arc keys by item id).
   The archive table stores the snapshot as D1 JSON plus denormalized `title`/`url` columns for search (BH-087,
   BH-104) and `source_*`/`reason` columns for filters (BH-088). Restore puts tabs and splits at the top of the
   source Space's Today and folders at the end of its Pinned (BH-086, BH-090); if that Space is gone or the source is
   Little Arc/unknown, the caller's fallback Space is used. Air Traffic Control routing of restores (BH-157) belongs
   to the link-routing track, not here: the caller passes the fallback.
8. **Auto-archive policy (D4b).** Pure function. Scope: direct children of `.today(space)` only. Pinned (BH-054),
   Favorites (BH-048) and anything inside a folder (BH-084, BH-090) never auto-archive; a folder sitting directly in
   Today is skipped as a unit [I]. Idle reference = `lastActiveAt ?? createdAt`, but never earlier than
   `startedAt` (`autoArchiveStartTime` in Arc's archive JSON, data-model 2.1), so an Arc import or first launch does
   not archive everything at once. A split in Today is one unit: archived only when its most recently active pane is
   past the threshold and no pane is exempt [I, BH-122/123 unresolved]. Exempt ids (media playing BH-076, visible
   tabs) come from the caller. Boundary: idle >= threshold archives.
9. **Thresholds (D4b, D6).** `AutoArchiveThreshold` has the seven BH-081 options (`oneHour, sixHours, twelveHours,
   twentyFourHours, sevenDays, thirtyDays, never`). Raw values reuse Arc's known case names (`twelveHours`,
   `twentyFourHours`, `sevenDays`, `thirtyDays`, data-model 2.1); the other three names are ours [I]. Defaults: tabs
   12 h (BH-080), Little Arc 6 h (BH-137). `never` is a real case; whether the UI shows it (BH-082) is not this
   track's call. Per-profile tab thresholds (BH-083, BH-179) persist in SQLite (`setting` table), not user defaults:
   they are profile data, travel with the database and its backups, and design 4 reserves user defaults for
   app-level values.

## File map (end state)

```
app/ArktCore/
  Package.swift                                  (modified D1b, D2a, D4a, D4c, D5a)
  Package.resolved                               (new D2a)
  Sources/SidebarModel/SidebarModel.swift        (modified D1a)
  Sources/SidebarModel/NodeSnapshot.swift        (new D1a)
  Sources/SidebarModel/SidebarStorageFormat.swift(new D1b)
  Sources/Archive/ArchivedItem.swift             (new D4a)
  Sources/Archive/Archiver.swift                 (new D4a)
  Sources/Archive/AutoArchivePolicy.swift        (new D4b)
  Sources/Archive/ArchiveSettings.swift          (new D6)
  Sources/Persistence/ArktDatabase.swift         (new D2a, extended D2b, D4c, D6)
  Sources/Persistence/SidebarStore.swift         (new D2a)
  Sources/Persistence/Backups.swift              (new D2b)
  Sources/Persistence/ArktLaunch.swift           (new D2b)
  Sources/Persistence/SidebarAutosaver.swift     (new D3)
  Sources/Persistence/ArchiveStore.swift         (new D4c)
  Sources/Persistence/SettingsStore.swift        (new D6)
  Sources/ArcImport/ArcSidebarImporter.swift     (modified D5a: spaceIDsByArcID)
  Sources/ArcImport/ArcArchiveFile.swift         (new D5a)
  Sources/ArcImport/ArcArchiveImporter.swift     (new D5a)
  Sources/ArcImport/ArchiveCheckSummary.swift    (new D5b)
  Sources/arkt-import-check/main.swift           (modified D5b)
  Tests/SidebarModelTests/NodeSnapshotTests.swift          (D1a)
  Tests/SidebarModelTests/SidebarStorageFormatTests.swift  (D1b)
  Tests/SidebarModelTests/Fixtures/sidebar-v1.json         (D1b)
  Tests/PersistenceTests/TestSupport.swift                 (D2a, extended D3)
  Tests/PersistenceTests/SidebarStoreTests.swift           (D2a)
  Tests/PersistenceTests/ArktLaunchTests.swift             (D2b)
  Tests/PersistenceTests/SidebarAutosaverTests.swift       (D3)
  Tests/PersistenceTests/ArchiveStoreTests.swift           (D4c)
  Tests/PersistenceTests/SettingsStoreTests.swift          (D6)
  Tests/ArchiveTests/ArchiverTests.swift                   (D4a)
  Tests/ArchiveTests/AutoArchivePolicyTests.swift          (D4b)
  Tests/ArchiveTests/ArchiveSettingsTests.swift            (D6)
  Tests/ArcImportTests/ArcArchiveImporterTests.swift       (D5a)
  Tests/ArcImportTests/ArchiveCheckSummaryTests.swift      (D5b)
  Tests/ArcImportTests/Fixtures/StorableArchiveItems-synthetic.json (D5a)
docs/plans/2026-10-22-week1-results.md                     (D5b: counts-only real-file result)
```

Execution order: D1a, D1b, D2a, D2b, D3, D4a, D4b, D4c, D5a, D5b, D6. D4b only needs `AutoArchiveThreshold`, which it
defines; D6 adds `ArchiveSettings` on top.

---

### Task D1a: Codable leaf types, `NodeSnapshot`, id-preserving insert

**Files:**
- Modify: `app/ArktCore/Sources/SidebarModel/SidebarModel.swift`
- Create: `app/ArktCore/Sources/SidebarModel/NodeSnapshot.swift`
- Create: `app/ArktCore/Tests/SidebarModelTests/NodeSnapshotTests.swift`

**Step 1: Write the failing tests** (`NodeSnapshotTests.swift`)

```swift
import Foundation
import Testing
import SidebarModel

struct NodeSnapshotTests {
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  /// Space "Work": pinned [folder Docs [tab a, tab b], tab c], today [tab d]; a split with two tabs in pinned.
  static func makeSidebar() throws -> (Sidebar, SpaceID, folder: NodeID, split: NodeID) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(space))
    try sidebar.addTab(url: url("a"), title: "A", in: .folder(folder))
    try sidebar.addTab(url: url("b"), title: "B", customTitle: "Bee", in: .folder(folder))
    try sidebar.addTab(url: url("c"), title: "C", in: .pinned(space))
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .pinned(space))
    try sidebar.addTab(url: url("s1"), title: "S1", in: .split(split))
    try sidebar.addTab(url: url("s2"), title: "S2", in: .split(split))
    try sidebar.addTab(url: url("d"), title: "D", in: .today(space))
    return (sidebar, space, folder, split)
  }

  @Test func snapshotCapturesSubtreeInOrder() throws {
    let (sidebar, _, folder, _) = try Self.makeSidebar()
    let snapshot = try #require(sidebar.snapshot(of: folder))
    #expect(snapshot.id == folder)
    #expect(snapshot.kind == .folder(FolderItem(title: "Docs")))
    #expect(snapshot.children.map(\.id) == sidebar.children(of: .folder(folder)))
    #expect(snapshot.children.allSatisfy { $0.children.isEmpty })
    #expect(snapshot.allIDs == [folder] + sidebar.children(of: .folder(folder)))
  }

  @Test func snapshotOfUnknownIDIsNil() throws {
    let (sidebar, _, _, _) = try Self.makeSidebar()
    #expect(sidebar.snapshot(of: NodeID()) == nil)
  }

  @Test func removeThenInsertAtOldIndexRestoresSidebarExactly() throws {
    let (original, space, folder, _) = try Self.makeSidebar()
    var sidebar = original
    let snapshot = try #require(sidebar.snapshot(of: folder))
    let index = try #require(sidebar.children(of: .pinned(space)).firstIndex(of: folder))
    sidebar.remove(folder)
    try sidebar.insert(snapshot, in: .pinned(space), at: index)
    #expect(sidebar == original)
  }

  @Test func insertAppendsWithoutIndexAndClampsLargeIndex() throws {
    let made = try Self.makeSidebar()
    var sidebar = made.0
    let space = made.1
    let a = NodeSnapshot(kind: .tab(TabItem(url: Self.url("x"), title: "X")), createdAt: .distantPast)
    let b = NodeSnapshot(kind: .tab(TabItem(url: Self.url("y"), title: "Y")), createdAt: .distantPast)
    try sidebar.insert(a, in: .today(space))
    try sidebar.insert(b, in: .today(space), at: 99)
    #expect(sidebar.children(of: .today(space)).suffix(2) == [a.id, b.id])
    let c = NodeSnapshot(kind: .tab(TabItem(url: Self.url("z"), title: "Z")), createdAt: .distantPast)
    try sidebar.insert(c, in: .today(space), at: -3)
    #expect(sidebar.children(of: .today(space)).first == c.id)
  }

  @Test func insertRejectsDuplicateIDAndLeavesSidebarUnchanged() throws {
    let (original, space, folder, _) = try Self.makeSidebar()
    var sidebar = original
    let snapshot = try #require(sidebar.snapshot(of: folder))
    #expect(throws: SidebarError.duplicateID(folder)) { try sidebar.insert(snapshot, in: .today(space)) }
    #expect(sidebar == original)
  }

  @Test func insertRejectsFolderInsideSplit() throws {
    let (original, _, _, split) = try Self.makeSidebar()
    var sidebar = original
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "F")), createdAt: .distantPast)
    #expect(throws: SidebarError.invalidDestination(.split(split))) { try sidebar.insert(folder, in: .split(split)) }
    #expect(sidebar == original)
  }

  @Test func insertRejectsChildrenUnderATab() throws {
    let (original, space, _, _) = try Self.makeSidebar()
    var sidebar = original
    let child = NodeSnapshot(kind: .tab(TabItem(url: Self.url("k"), title: "K")), createdAt: .distantPast)
    let parent = NodeSnapshot(
      kind: .tab(TabItem(url: Self.url("p"), title: "P")), createdAt: .distantPast, children: [child])
    #expect(throws: SidebarError.invalidDestination(.folder(parent.id))) {
      try sidebar.insert(parent, in: .today(space))
    }
    #expect(sidebar == original)
  }

  @Test func addSpaceKeepsIDAndRejectsDuplicates() throws {
    var sidebar = Sidebar()
    let space = Space(title: "Kept", profile: "work")
    try sidebar.addSpace(space)
    #expect(sidebar.spaceOrder == [space.id])
    #expect(sidebar.spaces[space.id] == space)
    #expect(throws: SidebarError.duplicateID(space.id)) { try sidebar.addSpace(space) }
    #expect(sidebar.spaceOrder == [space.id])
  }

  @Test func withFreshIDsChangesEveryIDAndKeepsShape() throws {
    let (sidebar, _, folder, _) = try Self.makeSidebar()
    let snapshot = try #require(sidebar.snapshot(of: folder))
    let fresh = snapshot.withFreshIDs()
    #expect(Set(fresh.allIDs).isDisjoint(with: snapshot.allIDs))
    #expect(fresh.allIDs.count == snapshot.allIDs.count)
    #expect(fresh.children.map(\.kind) == snapshot.children.map(\.kind))
    #expect(fresh.createdAt == snapshot.createdAt)
  }
}
```

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter NodeSnapshotTests`
Expected: build fails (`NodeSnapshot`, `snapshot(of:)`, `insert(_:in:at:)`, `addSpace(_:)`, `duplicateID` unknown).

**Step 3: Implement**

`SidebarModel.swift` changes:
- Add `Codable` to `RGBA`, `SpaceTheme`, `Space`, `TabItem`, `FolderItem`, `SplitItem` (synthesized).
- `public enum Orientation: String, Hashable, Sendable, Codable { case horizontal, vertical }` (raw values give a
  plain string on disk; existing call sites are unchanged).
- Add to `SidebarError`:
  ```swift
  /// A space or node with this id already exists (or appears twice in an inserted snapshot).
  case duplicateID(UUID)
  ```
- Add inside `struct Sidebar` (same file, because it touches the `private(set)` storage):
  ```swift
  /// Adds `space` keeping its id, for decoding and restore. Throws `.duplicateID` if the id is taken.
  public mutating func addSpace(_ space: Space) throws {
    guard spaces[space.id] == nil else { throw SidebarError.duplicateID(space.id) }
    spaces[space.id] = space
    spaceOrder.append(space.id)
  }

  /// The subtree rooted at `id`, in child order, or nil for an unknown id.
  public func snapshot(of id: NodeID) -> NodeSnapshot? {
    guard let node = nodes[id] else { return nil }
    let childLocation: Location? = switch node.kind {
    case .folder: .folder(id)
    case .split: .split(id)
    case .tab: nil
    }
    let children = childLocation.map { children(of: $0).compactMap { snapshot(of: $0) } } ?? []
    return NodeSnapshot(id: id, kind: node.kind, createdAt: node.createdAt, children: children)
  }

  /// Inserts `snapshot` with its whole subtree into `location`, keeping every id and `createdAt`.
  /// `index` follows `Array.insert` (clamped); nil appends.
  /// Throws `.duplicateID` when an id is already used or repeats inside the snapshot, and `.invalidDestination` when a
  /// node cannot live where it would land (same rules as `move`; children under a tab report `.folder(tabID)`).
  /// The sidebar is unchanged on throw.
  public mutating func insert(_ snapshot: NodeSnapshot, in location: Location, at index: Int? = nil) throws {
    var copy = self
    try copy.insertTree(snapshot, in: location)
    if let index, var siblings = copy.childOrder[location] {
      siblings.removeLast()
      siblings.insert(snapshot.id, at: min(max(index, 0), siblings.count))
      copy.childOrder[location] = siblings
    }
    self = copy
  }

  private mutating func insertTree(_ snapshot: NodeSnapshot, in location: Location) throws {
    guard nodes[snapshot.id] == nil else { throw SidebarError.duplicateID(snapshot.id) }
    try validate(location, accepting: snapshot.kind)
    nodes[snapshot.id] = Node(id: snapshot.id, kind: snapshot.kind, parent: location, createdAt: snapshot.createdAt)
    childOrder[location, default: []].append(snapshot.id)
    // A tab has no child location; `.folder(tabID)` fails validation, which is the error we want.
    let childLocation: Location = if case .split = snapshot.kind { .split(snapshot.id) } else { .folder(snapshot.id) }
    for child in snapshot.children { try insertTree(child, in: childLocation) }
  }
  ```

`NodeSnapshot.swift`:

```swift
import Foundation

/// A node and its whole subtree, detached from any sidebar. Used by the storage format (D1b), the archive and restore.
public struct NodeSnapshot: Hashable, Sendable, Codable, Identifiable {
  public var id: NodeID
  public var kind: NodeKind
  public var createdAt: Date
  public var children: [NodeSnapshot]

  public init(id: NodeID = NodeID(), kind: NodeKind, createdAt: Date, children: [NodeSnapshot] = []) {
    self.id = id
    self.kind = kind
    self.createdAt = createdAt
    self.children = children
  }

  /// Every id in the subtree, root first, depth first.
  public var allIDs: [NodeID] { [id] + children.flatMap(\.allIDs) }

  /// The same subtree with new ids, used when restoring over an id that is already taken.
  public func withFreshIDs() -> NodeSnapshot {
    NodeSnapshot(kind: kind, createdAt: createdAt, children: children.map { $0.withFreshIDs() })
  }
}

/// On disk: `{"type": "tab", "tab": {...}}`, `{"type": "folder", "folder": {...}}`, `{"type": "split", "split": {...}}`.
extension NodeKind: Codable {
  private enum CodingKeys: String, CodingKey { case type, tab, folder, split }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "tab": self = .tab(try container.decode(TabItem.self, forKey: .tab))
    case "folder": self = .folder(try container.decode(FolderItem.self, forKey: .folder))
    case "split": self = .split(try container.decode(SplitItem.self, forKey: .split))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "Unknown node type \(type)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .tab(let tab):
      try container.encode("tab", forKey: .type)
      try container.encode(tab, forKey: .tab)
    case .folder(let folder):
      try container.encode("folder", forKey: .type)
      try container.encode(folder, forKey: .folder)
    case .split(let split):
      try container.encode("split", forKey: .type)
      try container.encode(split, forKey: .split)
    }
  }
}
```

**Step 4: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 97 tests` ... `passed` (88 + 9). Existing importer tests still pass (the new
`SidebarError` case is additive; the importer catches `SidebarError` as a type).

**Step 5: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/SidebarModel/SidebarModel.swift \
  app/ArktCore/Sources/SidebarModel/NodeSnapshot.swift \
  app/ArktCore/Tests/SidebarModelTests/NodeSnapshotTests.swift
git commit -m "Add node snapshots and id-preserving sidebar insert"
```

---

### Task D1b: Versioned, deterministic, validating `Sidebar: Codable`

**Files:**
- Create: `app/ArktCore/Sources/SidebarModel/SidebarStorageFormat.swift`
- Create: `app/ArktCore/Tests/SidebarModelTests/Fixtures/sidebar-v1.json`
- Create: `app/ArktCore/Tests/SidebarModelTests/SidebarStorageFormatTests.swift`
- Modify: `app/ArktCore/Package.swift` (SidebarModelTests gets `resources: [.copy("Fixtures")]`)

**Step 1: Fixture** (`sidebar-v1.json`, synthetic, fixed ids; this file is the format-compatibility contract for
version 1: never edit it once committed, add `sidebar-v2.json` for a new version)

```json
{
  "version": 1,
  "spaces": [
    {
      "space": {
        "id": "D1000000-0000-4000-8000-0000000000A1",
        "title": "Alpha",
        "profile": "default",
        "theme": {
          "baseColors": [{ "red": 0.2, "green": 0.4, "blue": 0.6, "alpha": 1 }],
          "overlayColors": [],
          "texture": "grain",
          "isDark": true
        }
      },
      "pinned": [
        {
          "id": "D1000000-0000-4000-8000-000000000101",
          "createdAt": 783000000,
          "kind": { "type": "folder", "folder": { "title": "Docs" } },
          "children": [
            {
              "id": "D1000000-0000-4000-8000-000000000102",
              "createdAt": 783000001.5,
              "kind": { "type": "tab", "tab": { "url": "https://example.com/a", "title": "A", "customTitle": "Renamed A" } },
              "children": []
            }
          ]
        },
        {
          "id": "D1000000-0000-4000-8000-000000000103",
          "createdAt": 783000002,
          "kind": { "type": "split", "split": { "orientation": "horizontal", "widthFactors": [0.5, 0.5] } },
          "children": [
            {
              "id": "D1000000-0000-4000-8000-000000000104",
              "createdAt": 783000003,
              "kind": { "type": "tab", "tab": { "url": "https://example.com/b", "title": "B" } },
              "children": []
            },
            {
              "id": "D1000000-0000-4000-8000-000000000105",
              "createdAt": 783000004,
              "kind": { "type": "tab", "tab": { "url": "https://example.com/c", "title": "C" } },
              "children": []
            }
          ]
        }
      ],
      "today": [
        {
          "id": "D1000000-0000-4000-8000-000000000106",
          "createdAt": 783000005,
          "kind": { "type": "tab", "tab": { "url": "https://example.com/d", "title": "D", "lastActiveAt": 783000100.25 } },
          "children": []
        }
      ]
    },
    {
      "space": { "id": "D1000000-0000-4000-8000-0000000000B1", "title": "Beta", "profile": "work" },
      "pinned": [],
      "today": []
    }
  ],
  "favorites": [
    {
      "profile": "default",
      "items": [
        {
          "id": "D1000000-0000-4000-8000-000000000107",
          "createdAt": 783000006,
          "kind": { "type": "tab", "tab": { "url": "https://example.com/mail", "title": "Mail" } },
          "children": []
        }
      ]
    }
  ]
}
```

**Step 2: Write the failing tests** (`SidebarStorageFormatTests.swift`)

```swift
import Foundation
import Testing
import SidebarModel

struct SidebarStorageFormatTests {
  static func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "sidebar-v1", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// The fixture as a mutable JSON tree, changed by `change`, re-serialized.
  static func mutatedFixture(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    try change(&json)
    return try JSONSerialization.data(withJSONObject: json)
  }

  static func roundTrip(_ sidebar: Sidebar) throws -> Sidebar {
    try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
  }

  /// A rich sidebar built through the public API, including a move, two favorites profiles and a theme.
  static func richSidebar() throws -> Sidebar {
    var sidebar = Sidebar()
    let theme = SpaceTheme(baseColors: [RGBA(red: 0.1, green: 0.2, blue: 0.3)], texture: "grain", isDark: true)
    let work = sidebar.addSpace(title: "Work", theme: theme)
    let home = sidebar.addSpace(title: "Home", profile: "personal")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(work))
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(folder))
    try sidebar.addTab(url: URL(string: "https://example.com/1")!, title: "One", customTitle: "Uno", in: .folder(inner))
    let split = try sidebar.addSplit(orientation: .vertical, widthFactors: [0.3, 0.7], in: .today(work))
    try sidebar.addTab(url: URL(string: "https://example.com/2")!, title: "Two", in: .split(split))
    try sidebar.addTab(url: URL(string: "https://example.com/3")!, title: "Three", in: .split(split))
    let moved = try sidebar.addTab(
      url: URL(string: "https://example.com/4")!, title: "Four", lastActiveAt: Date(), in: .today(home))
    try sidebar.move(moved, to: .pinned(home), at: 0)
    try sidebar.addTab(url: URL(string: "https://example.com/m")!, title: "Mail", in: .favorites(profile: "default"))
    try sidebar.addTab(url: URL(string: "https://example.com/p")!, title: "Pay", in: .favorites(profile: "personal"))
    return sidebar
  }

  @Test func roundTripPreservesEverything() throws {
    let sidebar = try Self.richSidebar()
    #expect(try Self.roundTrip(sidebar) == sidebar)
  }

  @Test func roundTripKeepsFractionalDatesExactly() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let created = Date(timeIntervalSinceReferenceDate: 783_000_000.123_456_7)
    let active = Date(timeIntervalSinceReferenceDate: 1.0 / 3.0)
    try sidebar.addTab(
      url: URL(string: "https://example.com")!, title: "T", lastActiveAt: active, in: .today(space), createdAt: created)
    #expect(try Self.roundTrip(sidebar) == sidebar)
  }

  @Test func emptySidebarRoundTrips() throws {
    #expect(try Self.roundTrip(Sidebar()) == Sidebar())
  }

  @Test func encodingIsDeterministic() throws {
    let sidebar = try Self.richSidebar()
    let first = try SidebarStorageFormat.encode(sidebar)
    #expect(try SidebarStorageFormat.encode(sidebar) == first)
    #expect(try SidebarStorageFormat.encode(SidebarStorageFormat.decode(first)) == first)
  }

  @Test func decodesVersion1Fixture() throws {
    let sidebar = try SidebarStorageFormat.decode(Self.fixtureData())
    let alpha = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
    let folder = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000101"))
    let split = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000103"))
    #expect(sidebar.spaceOrder.count == 2)
    #expect(sidebar.spaces[alpha]?.theme?.texture == "grain")
    #expect(sidebar.children(of: .pinned(alpha)) == [folder, split])
    #expect(sidebar.children(of: .split(split)).count == 2)
    #expect(sidebar.children(of: .favorites(profile: "default")).count == 1)
    let renamed = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000102"))
    #expect(sidebar.nodes[renamed]?.parent == .folder(folder))
    #expect(sidebar.nodes[renamed]?.kind == .tab(TabItem(
      url: URL(string: "https://example.com/a")!, title: "A", customTitle: "Renamed A")))
    #expect(sidebar.nodes[renamed]?.createdAt == Date(timeIntervalSinceReferenceDate: 783_000_001.5))
  }

  @Test func rejectsUnsupportedVersion() throws {
    let data = try Self.mutatedFixture { $0["version"] = 2 }
    #expect(throws: SidebarDocumentError.unsupportedVersion(2)) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsDuplicateNodeIDAcrossSections() throws {
    let duplicate = "D1000000-0000-4000-8000-000000000107"
    let data = try Self.mutatedFixture { json in
      var spaces = json["spaces"] as! [[String: Any]]
      var today = spaces[0]["today"] as! [[String: Any]]
      today[0]["id"] = duplicate
      spaces[0]["today"] = today
      json["spaces"] = spaces
    }
    let id = try #require(UUID(uuidString: duplicate))
    #expect(throws: SidebarDocumentError.invalidTree(.duplicateID(id))) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsDuplicateSpaceID() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = json["spaces"] as! [[String: Any]]
      var beta = spaces[1]["space"] as! [String: Any]
      beta["id"] = "D1000000-0000-4000-8000-0000000000A1"
      spaces[1]["space"] = beta
      json["spaces"] = spaces
    }
    let id = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
    #expect(throws: SidebarDocumentError.invalidTree(.duplicateID(id))) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsFolderInsideSplit() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = json["spaces"] as! [[String: Any]]
      var pinned = spaces[0]["pinned"] as! [[String: Any]]
      var children = pinned[1]["children"] as! [[String: Any]]
      children[0]["kind"] = ["type": "folder", "folder": ["title": "Nope"]]
      pinned[1]["children"] = children
      spaces[0]["pinned"] = pinned
      json["spaces"] = spaces
    }
    let split = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000103"))
    #expect(throws: SidebarDocumentError.invalidTree(.invalidDestination(.split(split)))) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsChildrenUnderATab() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = json["spaces"] as! [[String: Any]]
      var today = spaces[0]["today"] as! [[String: Any]]
      today[0]["children"] = [[
        "id": "D1000000-0000-4000-8000-000000000199", "createdAt": 0, "children": [],
        "kind": ["type": "tab", "tab": ["url": "https://example.com/x", "title": "X"]],
      ]]
      spaces[0]["today"] = today
      json["spaces"] = spaces
    }
    let tab = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000106"))
    #expect(throws: SidebarDocumentError.invalidTree(.invalidDestination(.folder(tab)))) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsDuplicateFavoritesProfile() throws {
    let data = try Self.mutatedFixture { json in
      json["favorites"] = [["profile": "default", "items": []], ["profile": "default", "items": []]]
    }
    #expect(throws: SidebarDocumentError.duplicateFavoritesProfile("default")) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsUnknownNodeType() throws {
    let data = try Self.mutatedFixture { json in
      var favorites = json["favorites"] as! [[String: Any]]
      var items = favorites[0]["items"] as! [[String: Any]]
      items[0]["kind"] = ["type": "easel", "easel": [:]]
      favorites[0]["items"] = items
      json["favorites"] = favorites
    }
    #expect(throws: DecodingError.self) { try SidebarStorageFormat.decode(data) }
  }
}
```

**Step 3: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter SidebarStorageFormatTests`
Expected: build fails (`SidebarStorageFormat`, `SidebarDocumentError` unknown; `Bundle.module` missing until the
manifest change).

**Step 4: Implement**

`Package.swift`: change the SidebarModelTests line to
`.testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"], resources: [.copy("Fixtures")]),`

`SidebarStorageFormat.swift`:

```swift
import Foundation

/// Arkt's on-disk sidebar format.
///
/// Version 1 is nested: each Space carries its pinned and Today trees, and Favorites are listed per profile, so a
/// file cannot express a parent link that disagrees with child order. Decoding rebuilds the sidebar through
/// `addSpace(_:)` and `insert(_:in:at:)`, which enforce every model invariant and keep ids.
/// Deterministic: arrays follow model order, favorites are sorted by profile and keys are sorted. Dates are Double
/// seconds since 2001-01-01 (Swift's default, also Arc's), written in shortest round-trip form.
public enum SidebarStorageFormat {
  public static let currentVersion = 1

  /// A fresh encoder with the canonical settings. Not stored: `JSONEncoder` is not `Sendable`.
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .deferredToDate
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    return decoder
  }

  public static func encode(_ sidebar: Sidebar) throws -> Data { try makeEncoder().encode(sidebar) }
  public static func decode(_ data: Data) throws -> Sidebar { try makeDecoder().decode(Sidebar.self, from: data) }
}

public enum SidebarDocumentError: Error, Hashable, Sendable {
  /// Written by a newer (or unknown) format. Never guessed at.
  case unsupportedVersion(Int)
  /// The same profile appears twice in `favorites`.
  case duplicateFavoritesProfile(String)
  /// The tree breaks a model rule (duplicate id, a folder in a split, children under a tab, ...).
  case invalidTree(SidebarError)
}

private struct SpaceEntry: Codable {
  var space: Space
  var pinned: [NodeSnapshot]
  var today: [NodeSnapshot]
}

private struct FavoritesEntry: Codable {
  var profile: String
  var items: [NodeSnapshot]
}

extension Sidebar: Codable {
  private enum CodingKeys: String, CodingKey { case version, spaces, favorites }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == SidebarStorageFormat.currentVersion else {
      throw SidebarDocumentError.unsupportedVersion(version)
    }
    let spaces = try container.decode([SpaceEntry].self, forKey: .spaces)
    let favorites = try container.decode([FavoritesEntry].self, forKey: .favorites)
    var sidebar = Sidebar()
    var profiles: Set<String> = []
    do {
      for entry in spaces {
        try sidebar.addSpace(entry.space)
        for tree in entry.pinned { try sidebar.insert(tree, in: .pinned(entry.space.id)) }
        for tree in entry.today { try sidebar.insert(tree, in: .today(entry.space.id)) }
      }
      for entry in favorites {
        guard profiles.insert(entry.profile).inserted else {
          throw SidebarDocumentError.duplicateFavoritesProfile(entry.profile)
        }
        for tree in entry.items { try sidebar.insert(tree, in: .favorites(profile: entry.profile)) }
      }
    } catch let error as SidebarError {
      throw SidebarDocumentError.invalidTree(error)
    }
    self = sidebar
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(SidebarStorageFormat.currentVersion, forKey: .version)
    let spaceEntries = spaceOrder.compactMap { id in
      spaces[id].map { SpaceEntry(space: $0, pinned: trees(in: .pinned(id)), today: trees(in: .today(id))) }
    }
    try container.encode(spaceEntries, forKey: .spaces)
    let profiles = Set(childOrder.keys.compactMap { location -> String? in
      if case .favorites(let profile) = location { return profile }
      return nil
    }).sorted()
    try container.encode(
      profiles.map { FavoritesEntry(profile: $0, items: trees(in: .favorites(profile: $0))) }, forKey: .favorites)
  }

  private func trees(in location: Location) -> [NodeSnapshot] {
    children(of: location).compactMap { snapshot(of: $0) }
  }
}
```

Expected: `roundTripKeepsFractionalDatesExactly` passes as written. If it fails on this toolchain, do not loosen the
test: stop and report, because the fix (a custom date strategy) changes the version-1 format before it ships.

**Step 5: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 109 tests` ... `passed`.

**Step 6: Commit**
```zsh
cd $WT && git add app/ArktCore/Package.swift app/ArktCore/Sources/SidebarModel/SidebarStorageFormat.swift \
  app/ArktCore/Tests/SidebarModelTests/SidebarStorageFormatTests.swift \
  app/ArktCore/Tests/SidebarModelTests/Fixtures/sidebar-v1.json
git commit -m "Add versioned sidebar storage format with validation"
```

---

### Task D2a: GRDB, database, migrations, `SidebarStore`

**Files:**
- Modify: `app/ArktCore/Package.swift`
- Create: `app/ArktCore/Package.resolved` (generated)
- Create: `app/ArktCore/Sources/Persistence/ArktDatabase.swift`
- Create: `app/ArktCore/Sources/Persistence/SidebarStore.swift`
- Create: `app/ArktCore/Tests/PersistenceTests/TestSupport.swift`
- Create: `app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift`

**Step 1: Manifest** (full file after this task)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ArktCore",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SidebarModel", targets: ["SidebarModel"]),
    .library(name: "ArcImport", targets: ["ArcImport"]),
    .library(name: "Persistence", targets: ["Persistence"]),
  ],
  dependencies: [
    // Exact pin: the on-disk format is user data. Upgrade only in a dedicated, reviewed commit.
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
  ],
  targets: [
    .target(name: "SidebarModel"),
    .target(name: "ArcImport", dependencies: ["SidebarModel"]),
    .target(
      name: "Persistence",
      dependencies: ["SidebarModel", .product(name: "GRDB", package: "GRDB.swift")]
    ),
    .executableTarget(name: "arkt-import-check", dependencies: ["ArcImport"]),
    .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"], resources: [.copy("Fixtures")]),
    .testTarget(
      name: "ArcImportTests",
      dependencies: ["ArcImport", "SidebarModel"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "PersistenceTests",
      dependencies: ["Persistence", "SidebarModel", .product(name: "GRDB", package: "GRDB.swift")]
    ),
  ]
)
```

Run: `cd $WT/app/ArktCore && nice -n 10 swift package resolve`
Expected: fetches GRDB.swift, writes `Package.resolved` with `"version" : "7.11.1"` and revision
`b83108d10f42680d78f23fe4d4d80fc88dab3212`. If the revision differs, stop and report (tag moved).

**Step 2: Test support** (`TestSupport.swift`)

```swift
import Foundation
import Testing
@testable import Persistence
import SidebarModel

enum TestSidebars {
  /// A small sidebar distinguishable by `title` (space title and a tab title).
  static func make(_ title: String) -> Sidebar {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: title)
    _ = try? sidebar.addTab(url: URL(string: "https://example.com/\(title)")!, title: title, in: .today(space))
    return sidebar
  }
}

/// A fresh empty directory under the temp dir, removed after `body`.
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("arkt-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: url) }
  return try await body(url)
}
```

**Step 3: Write the failing tests** (`SidebarStoreTests.swift`)

```swift
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct SidebarStoreTests {
  @Test func freshDatabaseHasNoSidebar() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    #expect(try await store.load() == nil)
  }

  @Test func saveThenLoadRoundTrips() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    let sidebar = TestSidebars.make("a")
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 10)) == .written)
    #expect(try await store.load() == sidebar)
  }

  @Test func secondSaveReplacesTheOnlyRow() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    let b = TestSidebars.make("b")
    _ = try await store.save(b, at: Date(timeIntervalSinceReferenceDate: 2))
    #expect(try await store.load() == b)
    let rows = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM sidebar_snapshot") }
    #expect(rows == 1)
  }

  @Test func identicalSaveIsSkipped() async throws {
    let store = SidebarStore(database: try ArktDatabase.inMemory())
    let sidebar = TestSidebars.make("a")
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 1)) == .written)
    #expect(try await store.save(sidebar, at: Date(timeIntervalSinceReferenceDate: 2)) == .unchanged)
  }

  @Test func corruptedBodyFailsTheChecksum() async throws {
    let database = try ArktDatabase.inMemory()
    let store = SidebarStore(database: database)
    _ = try await store.save(TestSidebars.make("a"), at: Date(timeIntervalSinceReferenceDate: 1))
    try await database.writer.write { db in
      try db.execute(sql: "UPDATE sidebar_snapshot SET body = ?", arguments: [Data("garbage".utf8)])
    }
    await #expect(throws: SidebarStoreError.checksumMismatch) { try await store.load() }
  }

  @Test func persistsAcrossReopen() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      let sidebar = TestSidebars.make("kept")
      do {
        let database = try ArktDatabase.open(at: url)
        _ = try await SidebarStore(database: database).save(sidebar, at: Date(timeIntervalSinceReferenceDate: 1))
        try database.writer.close()
      }
      let reopened = try ArktDatabase.open(at: url)
      #expect(try await SidebarStore(database: reopened).load() == sidebar)
    }
  }

  @Test func usesRollbackJournal() async throws {
    try await withTemporaryDirectory { directory in
      let database = try ArktDatabase.open(at: directory.appendingPathComponent("Arkt.sqlite"))
      let mode = try await database.writer.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
      #expect(mode == "delete")
    }
  }

  @Test func reopeningRunsNoMigrationTwice() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      try ArktDatabase.open(at: url).writer.close()
      let database = try ArktDatabase.open(at: url)
      let applied = try await database.writer.read { try ArktDatabase.migrator.completedMigrations($0) }
      #expect(applied == ["v1-sidebar"])
    }
  }
}
```

**Step 4: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter SidebarStoreTests`
Expected: the first build compiles GRDB (several minutes at `-j 2` under `nice`), then fails on the missing
`ArktDatabase`, `SidebarStore`, `SidebarStoreError`.

**Step 5: Implement**

`ArktDatabase.swift`:

```swift
import Foundation
import GRDB

/// Arkt's single SQLite database: sidebar snapshot, archive and settings.
///
/// `DatabaseQueue` with GRDB's default rollback journal (`journal_mode=delete`): one connection, one self-contained
/// file. Every access goes through GRDB's async `read`/`write`, which run on GRDB's serial queue, never on the caller's
/// thread. Migrations are forward-only: never edit a registered migration, add a new one.
public struct ArktDatabase: Sendable {
  public let writer: DatabaseQueue

  init(writer: DatabaseQueue) { self.writer = writer }

  /// A migrated in-memory database, for tests and previews.
  public static func inMemory() throws -> ArktDatabase {
    let queue = try DatabaseQueue()
    try migrator.migrate(queue)
    return ArktDatabase(writer: queue)
  }

  /// Opens (creating it and its directory if needed) and migrates the database at `url`, then runs
  /// `PRAGMA quick_check`. Throws on any failure; `ArktLaunch` decides what to do about it.
  public static func open(at url: URL) throws -> ArktDatabase {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let queue = try DatabaseQueue(path: url.path)
    do {
      try migrator.migrate(queue)
      let check = try queue.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }
      guard check == "ok" else { throw ArktDatabaseError.integrityCheckFailed }
    } catch {
      try? queue.close()
      throw error
    }
    return ArktDatabase(writer: queue)
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    // Never set eraseDatabaseOnSchemaChange: it deletes user data.
    migrator.registerMigration("v1-sidebar") { db in
      try db.execute(sql: """
        CREATE TABLE sidebar_snapshot (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          format_version INTEGER NOT NULL,
          saved_at REAL NOT NULL,
          sha256 TEXT NOT NULL,
          body BLOB NOT NULL
        )
        """)
    }
    return migrator
  }
}

public enum ArktDatabaseError: Error, Hashable, Sendable {
  case integrityCheckFailed
}
```

`SidebarStore.swift`:

```swift
import CryptoKit
import Foundation
import GRDB
import SidebarModel

public enum SaveOutcome: Hashable, Sendable {
  case written
  /// The stored bytes were already identical; nothing was written.
  case unchanged
}

public enum SidebarStoreError: Error, Hashable, Sendable {
  /// The stored body does not match its SHA-256: the row was damaged after it was written.
  case checksumMismatch
}

/// Whole-sidebar snapshots in `sidebar_snapshot` (one row, replaced in one transaction).
public struct SidebarStore: Sendable {
  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// Encodes and writes `sidebar`. `@concurrent`: encoding runs on the global executor even when called from the
  /// main actor, and the write runs on GRDB's queue.
  @concurrent
  public func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let body = try SidebarStorageFormat.encode(sidebar)
    let digest = Self.sha256(body)
    let savedAt = date.timeIntervalSinceReferenceDate
    return try await database.writer.write { db -> SaveOutcome in
      let stored = try String.fetchOne(db, sql: "SELECT sha256 FROM sidebar_snapshot WHERE id = 1")
      if stored == digest { return .unchanged }
      try db.execute(
        sql: """
          INSERT INTO sidebar_snapshot (id, format_version, saved_at, sha256, body) VALUES (1, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET format_version = excluded.format_version, saved_at = excluded.saved_at,
            sha256 = excluded.sha256, body = excluded.body
          """,
        arguments: [SidebarStorageFormat.currentVersion, savedAt, digest, body])
      return .written
    }
  }

  /// The stored sidebar, or nil when none was saved yet. Throws `checksumMismatch` or a decoding error
  /// (`SidebarDocumentError`, `DecodingError`) for a damaged row.
  @concurrent
  public func load() async throws -> Sidebar? {
    let stored = try await database.writer.read { db -> (digest: String, body: Data)? in
      try Row.fetchOne(db, sql: "SELECT sha256, body FROM sidebar_snapshot WHERE id = 1")
        .map { (digest: $0["sha256"], body: $0["body"]) }
    }
    guard let stored else { return nil }
    guard Self.sha256(stored.body) == stored.digest else { throw SidebarStoreError.checksumMismatch }
    return try SidebarStorageFormat.decode(stored.body)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
```

If the compiler rejects `@concurrent` (it requires Swift 6.2+; our toolchain is 6.4, so it should not), stop and
report instead of falling back to `Task.detached`.

**Step 6: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 117 tests` ... `passed`.

**Step 7: Commit**
```zsh
cd $WT && git add app/ArktCore/Package.swift app/ArktCore/Package.resolved \
  app/ArktCore/Sources/Persistence/ArktDatabase.swift app/ArktCore/Sources/Persistence/SidebarStore.swift \
  app/ArktCore/Tests/PersistenceTests/TestSupport.swift app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift
git commit -m "Add GRDB-backed sidebar store"
```

---

### Task D2b: Rolling file backups and corruption fallback on launch

**Files:**
- Create: `app/ArktCore/Sources/Persistence/Backups.swift`
- Create: `app/ArktCore/Sources/Persistence/ArktLaunch.swift`
- Create: `app/ArktCore/Tests/PersistenceTests/ArktLaunchTests.swift`

**Step 1: Write the failing tests** (`ArktLaunchTests.swift`)

```swift
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct ArktLaunchTests {
  static func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

  @Test func firstLaunchCreatesAnEmptyDatabase() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      #expect(state.outcome == .created)
      #expect(state.sidebar == nil)
      #expect(FileManager.default.fileExists(atPath: location.databaseURL.path))
    }
  }

  @Test func relaunchLoadsTheSavedSidebar() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let sidebar = TestSidebars.make("a")
      let first = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      _ = try await SidebarStore(database: first.database).save(sidebar, at: Self.at(1))
      try first.database.writer.close()
      let second = try await ArktLaunch.openAndLoad(location, now: Self.at(2))
      #expect(second.outcome == .opened)
      #expect(second.sidebar == sidebar)
    }
  }

  @Test func backupsKeepTheNewestFive() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      var made: [URL] = []
      for second in 1...7 { made.append(try await state.database.makeBackup(in: location, now: Self.at(Double(second)))) }
      let kept = try Backups.list(in: location.backupsDirectory)
      #expect(kept == Array(made.suffix(5).reversed()))
    }
  }

  @Test func backupLeavesNoTempFilesAndContainsTheSidebar() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("b")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      let backup = try await state.database.makeBackup(in: location, now: Self.at(2))
      let names = try FileManager.default.contentsOfDirectory(atPath: location.backupsDirectory.path)
      #expect(names == [backup.lastPathComponent])
      #expect(try await SidebarStore(database: ArktDatabase.open(at: backup)).load() == sidebar)
    }
  }

  @Test func garbageLiveFileRestoresTheNewestBackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let store = SidebarStore(database: state.database)
      _ = try await store.save(TestSidebars.make("old"), at: Self.at(1))
      _ = try await state.database.makeBackup(in: location, now: Self.at(2))
      let newest = TestSidebars.make("new")
      _ = try await store.save(newest, at: Self.at(3))
      let newestBackup = try await state.database.makeBackup(in: location, now: Self.at(4))
      try state.database.writer.close()
      let garbage = Data(repeating: 0x42, count: 4096)
      try garbage.write(to: location.databaseURL)

      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(5))
      guard case .restoredFromBackup(let file, let quarantined) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(file == newestBackup.lastPathComponent)
      #expect(recovered.sidebar == newest)
      #expect(try Data(contentsOf: directory.appendingPathComponent(quarantined)) == garbage)
      #expect(try Data(contentsOf: newestBackup).count > 0)  // the backup itself is untouched
    }
  }

  @Test func checksumFailureAlsoFallsBackToABackup() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("good")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      _ = try await state.database.makeBackup(in: location, now: Self.at(2))
      try await state.database.writer.write { db in
        try db.execute(sql: "UPDATE sidebar_snapshot SET body = ?", arguments: [Data("bad".utf8)])
      }
      try state.database.writer.close()
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(3))
      #expect(recovered.sidebar == sidebar)
      if case .restoredFromBackup = recovered.outcome {} else { Issue.record("expected restore") }
    }
  }

  @Test func unusableNewestBackupIsSkipped() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      let state = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      let sidebar = TestSidebars.make("older")
      _ = try await SidebarStore(database: state.database).save(sidebar, at: Self.at(1))
      let older = try await state.database.makeBackup(in: location, now: Self.at(2))
      let newer = try await state.database.makeBackup(in: location, now: Self.at(3))
      try state.database.writer.close()
      try Data("not sqlite".utf8).write(to: newer)
      try Data("not sqlite".utf8).write(to: location.databaseURL)
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(4))
      guard case .restoredFromBackup(let file, _) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(file == older.lastPathComponent)
      #expect(recovered.sidebar == sidebar)
    }
  }

  @Test func noUsableBackupRecreatesAnEmptyDatabase() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      try Data("not sqlite".utf8).write(to: location.databaseURL)
      let recovered = try await ArktLaunch.openAndLoad(location, now: Self.at(0))
      guard case .recreatedEmpty(let quarantined) = recovered.outcome else {
        Issue.record("unexpected outcome \(recovered.outcome)")
        return
      }
      #expect(recovered.sidebar == nil)
      #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(quarantined).path))
    }
  }

  @Test func backupNamesSortChronologically() {
    let early = Backups.fileName(for: Self.at(0))
    let late = Backups.fileName(for: Self.at(0.5))
    #expect(early.hasPrefix("Arkt-") && early.hasSuffix(".sqlite"))
    #expect(early < late)
  }
}
```

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter ArktLaunchTests`
Expected: build fails (`DatabaseLocation`, `ArktLaunch`, `Backups`, `makeBackup` unknown).

**Step 3: Implement**

`Backups.swift`:

```swift
import Foundation
import GRDB

/// Where Arkt keeps its database. App code uses `applicationSupport()`; tests pass a temp directory.
public struct DatabaseLocation: Hashable, Sendable {
  public static let backupsKept = 5

  public let directory: URL
  public init(directory: URL) { self.directory = directory }

  public var databaseURL: URL { directory.appendingPathComponent("Arkt.sqlite", isDirectory: false) }
  public var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

  /// `~/Library/Application Support/Arkt`. Never Arc's directory.
  public static func applicationSupport() throws -> DatabaseLocation {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return DatabaseLocation(directory: base.appendingPathComponent("Arkt", isDirectory: true))
  }
}

/// Rolling file backups: `Backups/Arkt-<UTC stamp>.sqlite`, newest `DatabaseLocation.backupsKept` kept.
enum Backups {
  static func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
    return formatter.string(from: date)
  }

  static func fileName(for date: Date) -> String { "Arkt-\(stamp(date)).sqlite" }

  /// Backup files, newest first.
  static func list(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix("Arkt-") && $0.hasSuffix(".sqlite") }
      .sorted(by: >)
      .map { directory.appendingPathComponent($0, isDirectory: false) }
  }

  /// Copies `source` with SQLite's online backup API into a hidden temp file, renames it into place, then prunes.
  /// Blocking: call only from a `@concurrent` context.
  static func write(from source: some DatabaseReader, to directory: URL, now: Date) throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let final = directory.appendingPathComponent(fileName(for: now), isDirectory: false)
    let temp = directory.appendingPathComponent(".\(final.lastPathComponent).tmp", isDirectory: false)
    try? fileManager.removeItem(at: temp)
    do {
      let destination = try DatabaseQueue(path: temp.path)
      try source.backup(to: destination)
      try destination.close()
      if fileManager.fileExists(atPath: final.path) {
        _ = try fileManager.replaceItemAt(final, withItemAt: temp)
      } else {
        try fileManager.moveItem(at: temp, to: final)
      }
    } catch {
      try? fileManager.removeItem(at: temp)
      throw error
    }
    for old in try list(in: directory).dropFirst(DatabaseLocation.backupsKept) {
      try fileManager.removeItem(at: old)
    }
    return final
  }
}

extension ArktDatabase {
  /// Makes one rolling backup. Call on launch after a successful load and periodically; not per save.
  @concurrent
  public func makeBackup(in location: DatabaseLocation, now: Date) async throws -> URL {
    try Backups.write(from: writer, to: location.backupsDirectory, now: now)
  }
}
```

`ArktLaunch.swift`:

```swift
import Foundation
import GRDB
import SidebarModel

public enum OpenOutcome: Hashable, Sendable {
  /// No database existed; a new one was created.
  case created
  /// The live database opened, checked and decoded.
  case opened
  /// The live file was bad; it was renamed to `quarantinedAs` and backup `fileName` was restored.
  case restoredFromBackup(fileName: String, quarantinedAs: String)
  /// The live file was bad and no backup was usable; a new empty database was created.
  case recreatedEmpty(quarantinedAs: String)
}

public struct LaunchState: Sendable {
  public let database: ArktDatabase
  /// Nil when nothing was saved yet (or after `recreatedEmpty`).
  public let sidebar: Sidebar?
  public let outcome: OpenOutcome
}

public enum ArktLaunch {
  /// Opens and loads the database, falling back to the newest usable backup. Never deletes user data: a bad live file
  /// is renamed aside, and backups are only ever copied. Throws only when not even an empty database can be created.
  @concurrent
  public static func openAndLoad(_ location: DatabaseLocation, now: Date) async throws -> LaunchState {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
    let live = location.databaseURL

    guard fileManager.fileExists(atPath: live.path) else {
      return LaunchState(database: try ArktDatabase.open(at: live), sidebar: nil, outcome: .created)
    }
    if let opened = await attempt(live) {
      return LaunchState(database: opened.database, sidebar: opened.sidebar, outcome: .opened)
    }

    let quarantined = "\(live.lastPathComponent).corrupt-\(Backups.stamp(now))"
    try fileManager.moveItem(at: live, to: location.directory.appendingPathComponent(quarantined))
    let journal = URL(fileURLWithPath: live.path + "-journal")
    if fileManager.fileExists(atPath: journal.path) {
      try fileManager.moveItem(
        at: journal, to: location.directory.appendingPathComponent(quarantined + "-journal"))
    }

    for backup in try Backups.list(in: location.backupsDirectory) {
      let staging = location.directory.appendingPathComponent(".Arkt.sqlite.restoring")
      try? fileManager.removeItem(at: staging)
      try fileManager.copyItem(at: backup, to: staging)
      try fileManager.moveItem(at: staging, to: live)
      if let opened = await attempt(live) {
        return LaunchState(
          database: opened.database, sidebar: opened.sidebar,
          outcome: .restoredFromBackup(fileName: backup.lastPathComponent, quarantinedAs: quarantined))
      }
      try fileManager.removeItem(at: live)  // only our copy; the backup file is untouched
    }

    return LaunchState(
      database: try ArktDatabase.open(at: live), sidebar: nil, outcome: .recreatedEmpty(quarantinedAs: quarantined))
  }

  /// Open, migrate, quick_check, checksum and decode. Nil on any failure, with the connection closed.
  private static func attempt(_ url: URL) async -> (database: ArktDatabase, sidebar: Sidebar?)? {
    guard let database = try? ArktDatabase.open(at: url) else { return nil }
    do {
      return (database: database, sidebar: try await SidebarStore(database: database).load())
    } catch {
      try? database.writer.close()
      return nil
    }
  }
}
```

**Step 4: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 126 tests` ... `passed`.

**Step 5: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/Persistence/Backups.swift app/ArktCore/Sources/Persistence/ArktLaunch.swift \
  app/ArktCore/Tests/PersistenceTests/ArktLaunchTests.swift
git commit -m "Add rolling database backups and corruption fallback"
```

---

### Task D3: Debounced background writer

**Files:**
- Create: `app/ArktCore/Sources/Persistence/SidebarAutosaver.swift`
- Modify: `app/ArktCore/Tests/PersistenceTests/TestSupport.swift` (add `ManualSleeper`, `RecordingStore`, `waitUntil`)
- Create: `app/ArktCore/Tests/PersistenceTests/SidebarAutosaverTests.swift`

**Step 1: Test doubles** (append to `TestSupport.swift`; add `import Synchronization` at the top)

```swift
/// A manual stand-in for `Task.sleep`: each call parks until the test resumes it, or throws `CancellationError` when
/// its task is cancelled (also when cancelled before it parked).
final class ManualSleeper: Sendable {
  private struct Parked {
    let id: Int
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var nextID = 0
    var parked: [Parked] = []
    var cancelledEarly: Set<Int> = []
  }

  private let state = Mutex(State())

  var sleep: AutosaveSleep { { [self] duration in try await self.park(duration) } }
  var parkedCount: Int { state.withLock { $0.parked.count } }
  var parkedDurations: [Duration] { state.withLock { $0.parked.map(\.duration) } }

  /// Resumes the oldest parked sleeper.
  func resumeNext() {
    let parked = state.withLock { $0.parked.isEmpty ? nil : $0.parked.removeFirst() }
    parked?.continuation.resume()
  }

  private func park(_ duration: Duration) async throws {
    let id = state.withLock { state -> Int in
      state.nextID += 1
      return state.nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let cancelled = state.withLock { state -> Bool in
          if state.cancelledEarly.remove(id) != nil { return true }
          state.parked.append(Parked(id: id, duration: duration, continuation: continuation))
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      let parked = state.withLock { state -> Parked? in
        if let index = state.parked.firstIndex(where: { $0.id == id }) { return state.parked.remove(at: index) }
        state.cancelledEarly.insert(id)
        return nil
      }
      parked?.continuation.resume(throwing: CancellationError())
    }
  }
}

struct InjectedFailure: Error {}

/// Records saves; can fail the next N calls or hold calls until `unblock()`.
final class RecordingStore: SidebarSaving, Sendable {
  private struct State {
    var saved: [Sidebar] = []
    var started = 0
    var failuresLeft = 0
    var blocked = false
    var waiting: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  var saved: [Sidebar] { state.withLock { $0.saved } }
  var started: Int { state.withLock { $0.started } }
  func failNext(_ count: Int) { state.withLock { $0.failuresLeft = count } }
  func block() { state.withLock { $0.blocked = true } }

  func unblock() {
    let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.blocked = false
      defer { state.waiting = [] }
      return state.waiting
    }
    for continuation in waiting { continuation.resume() }
  }

  func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome {
    let fail = state.withLock { state -> Bool in
      state.started += 1
      guard state.failuresLeft > 0 else { return false }
      state.failuresLeft -= 1
      return true
    }
    if fail { throw InjectedFailure() }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = state.withLock { state -> Bool in
        guard state.blocked else { return false }
        state.waiting.append(continuation)
        return true
      }
      if !wait { continuation.resume() }
    }
    state.withLock { $0.saved.append(sidebar) }
    return .written
  }
}

/// Yields until `condition` holds; records an issue instead of hanging.
@MainActor
func waitUntil(
  _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<10_000 {
    if condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}
```

**Step 2: Write the failing tests** (`SidebarAutosaverTests.swift`)

```swift
import Foundation
import Testing
@testable import Persistence
import SidebarModel

@MainActor
struct SidebarAutosaverTests {
  let sleeper = ManualSleeper()
  let store = RecordingStore()

  func makeAutosaver() -> SidebarAutosaver {
    SidebarAutosaver(
      store: store, delay: .milliseconds(500), retryDelays: [.seconds(1), .seconds(2)],
      now: { Date(timeIntervalSinceReferenceDate: 0) }, sleep: sleeper.sleep)
  }

  @Test func coalescesChangesInsideTheWindow() async {
    let saver = makeAutosaver()
    let (a, b, c) = (TestSidebars.make("a"), TestSidebars.make("b"), TestSidebars.make("c"))
    saver.scheduleSave(a)
    saver.scheduleSave(b)
    saver.scheduleSave(c)
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(sleeper.parkedDurations == [.milliseconds(500)])
    #expect(store.saved.isEmpty)
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 1 }
    #expect(store.saved == [c])
    #expect(!saver.hasPendingChanges)
  }

  @Test func scheduleSaveNeverWaitsForTheStore() async {
    let saver = makeAutosaver()
    store.block()
    let (a, b) = (TestSidebars.make("a"), TestSidebars.make("b"))
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.started == 1 }  // the write is now stuck inside the store
    saver.scheduleSave(b)                   // synchronous: returning at all proves the main actor is free
    #expect(saver.hasPendingChanges)
    #expect(store.saved.isEmpty)
    store.unblock()
    await waitUntil { store.saved == [a] }
    await waitUntil { sleeper.parkedCount == 1 }  // b gets its own window after the write
    sleeper.resumeNext()
    await waitUntil { store.saved == [a, b] }
  }

  @Test func changeAfterAWriteOpensANewWindow() async {
    let saver = makeAutosaver()
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 1 }
    saver.scheduleSave(TestSidebars.make("b"))
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(store.saved.count == 1)
    sleeper.resumeNext()
    await waitUntil { store.saved.count == 2 }
  }

  @Test func flushWritesPendingImmediatelyAndCancelsTheTimer() async {
    let saver = makeAutosaver()
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    #expect(await saver.flush())
    #expect(store.saved == [a])
    await waitUntil { sleeper.parkedCount == 0 }
    for _ in 0..<100 { await Task.yield() }
    #expect(store.saved == [a])
  }

  @Test func flushWithNothingPendingWritesNothing() async {
    let saver = makeAutosaver()
    #expect(await saver.flush())
    #expect(store.started == 0)
  }

  @Test func failedWriteRetriesTheNewestValueAfterBackoff() async {
    let saver = makeAutosaver()
    store.failNext(1)
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { sleeper.parkedCount == 1 && store.started == 1 }
    #expect(sleeper.parkedDurations == [.seconds(1)])
    #expect(saver.lastError != nil)
    let b = TestSidebars.make("b")
    saver.scheduleSave(b)                 // during backoff: no second timer
    #expect(sleeper.parkedCount == 1)
    sleeper.resumeNext()
    await waitUntil { store.saved == [b] }
    #expect(saver.lastError == nil)
  }

  @Test func backoffGrowsThenRepeatsTheLastDelay() async {
    let saver = makeAutosaver()
    store.failNext(3)
    saver.scheduleSave(TestSidebars.make("a"))
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    var seen: [Duration] = []
    for attempt in 1...3 {
      await waitUntil { sleeper.parkedCount == 1 && store.started == attempt }
      seen += sleeper.parkedDurations
      sleeper.resumeNext()
    }
    #expect(seen == [.seconds(1), .seconds(2), .seconds(2)])
    await waitUntil { store.saved.count == 1 }
  }

  @Test func flushDuringBackoffMakesOneAttemptAndReturns() async {
    let saver = makeAutosaver()
    store.failNext(1)
    let a = TestSidebars.make("a")
    saver.scheduleSave(a)
    await waitUntil { sleeper.parkedCount == 1 }
    sleeper.resumeNext()
    await waitUntil { sleeper.parkedCount == 1 && store.started == 1 }
    #expect(await saver.flush())
    #expect(store.saved == [a])
    await waitUntil { sleeper.parkedCount == 0 }
  }

  @Test func flushReportsAFailedAttempt() async {
    let saver = makeAutosaver()
    store.failNext(5)
    saver.scheduleSave(TestSidebars.make("a"))
    #expect(await saver.flush() == false)
    #expect(saver.hasPendingChanges)
    #expect(saver.lastError != nil)
  }

  @Test func writesThroughTheRealStoreOffTheMainThread() async throws {
    let database = try ArktDatabase.inMemory()
    let realStore = SidebarStore(database: database)
    let saver = SidebarAutosaver(store: realStore, sleep: sleeper.sleep)
    let sidebar = TestSidebars.make("real")
    saver.scheduleSave(sidebar)
    #expect(await saver.flush())   // SidebarStore.save traps if it runs on the main thread
    #expect(try await realStore.load() == sidebar)
  }
}
```

**Step 3: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter SidebarAutosaverTests`
Expected: build fails (`SidebarAutosaver`, `SidebarSaving`, `AutosaveSleep` unknown).

**Step 4: Implement** (`SidebarAutosaver.swift`)

```swift
import Foundation
import SidebarModel

/// Anything that can persist a whole sidebar. `SidebarStore` conforms; tests use a recording fake.
public protocol SidebarSaving: Sendable {
  func save(_ sidebar: Sidebar, at date: Date) async throws -> SaveOutcome
}

extension SidebarStore: SidebarSaving {}

/// Injected time: `Task.sleep(for:)` in the app, a manual sleeper in tests.
public typealias AutosaveSleep = @Sendable (Duration) async throws -> Void

/// Coalesces sidebar changes and writes the newest one in the background.
///
/// Main-actor facing and synchronous: `scheduleSave` only stores the value and arms a timer, so the main thread never
/// waits on disk; encoding and I/O happen inside the store's `@concurrent` methods. The first change opens a window of
/// `delay`; changes inside it coalesce and the newest is written when it closes. Writes never overlap; a change during
/// a write opens a new window afterwards. A failed write keeps the newest value and retries after `retryDelays` (the
/// last one repeats). `flush()` is for app termination.
@MainActor
public final class SidebarAutosaver {
  nonisolated public static let defaultDelay: Duration = .milliseconds(500)
  nonisolated public static let defaultRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(15), .seconds(30)]

  private let store: any SidebarSaving
  private let delay: Duration
  private let retryDelays: [Duration]
  private let now: @Sendable () -> Date
  private let sleep: AutosaveSleep

  private var pending: Sidebar?
  private var timer: Task<Void, Never>?
  private var writer: Task<Void, Never>?

  public private(set) var lastError: (any Error)?
  public private(set) var consecutiveFailures = 0
  public var hasPendingChanges: Bool { pending != nil }

  public init(
    store: any SidebarSaving,
    delay: Duration = SidebarAutosaver.defaultDelay,
    retryDelays: [Duration] = SidebarAutosaver.defaultRetryDelays,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping AutosaveSleep = { try await Task.sleep(for: $0) }
  ) {
    precondition(!retryDelays.isEmpty, "retryDelays must not be empty")
    self.store = store
    self.delay = delay
    self.retryDelays = retryDelays
    self.now = now
    self.sleep = sleep
  }

  /// Records `sidebar` as the newest state. Never blocks and never awaits.
  public func scheduleSave(_ sidebar: Sidebar) {
    pending = sidebar
    if timer == nil, writer == nil { armTimer() }
  }

  /// Writes the newest pending sidebar now: cancels the timer and any retry wait, makes exactly one attempt.
  /// Returns true when nothing is left unsaved. For `applicationShouldTerminate` (`.terminateLater`).
  @discardableResult
  public func flush() async -> Bool {
    timer?.cancel()
    timer = nil
    if let running = writer {
      running.cancel()
      await running.value
    }
    timer?.cancel()  // the finished write loop may have armed one
    timer = nil
    guard let sidebar = pending else { return true }
    pending = nil
    do {
      _ = try await store.save(sidebar, at: now())
      lastError = nil
      consecutiveFailures = 0
    } catch {
      if pending == nil { pending = sidebar }
      lastError = error
      consecutiveFailures += 1
    }
    return pending == nil
  }

  private func armTimer() {
    let (sleep, delay) = (self.sleep, self.delay)
    timer = Task { [weak self] in
      do { try await sleep(delay) } catch { return }  // cancelled by flush
      self?.timerFired()
    }
  }

  private func timerFired() {
    timer = nil
    guard writer == nil, pending != nil else { return }
    writer = Task { [weak self] in await self?.writeLoop() }
  }

  private func writeLoop() async {
    while let sidebar = pending {
      pending = nil
      do {
        _ = try await store.save(sidebar, at: now())
        lastError = nil
        consecutiveFailures = 0
        break
      } catch {
        if pending == nil { pending = sidebar }  // keep the newest value, never an older one
        lastError = error
        let wait = retryDelays[min(consecutiveFailures, retryDelays.count - 1)]
        consecutiveFailures += 1
        do { try await sleep(wait) } catch { break }  // cancelled by flush
      }
    }
    writer = nil
    if pending != nil, timer == nil, !Task.isCancelled { armTimer() }
  }
}
```

**Step 5: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 136 tests` ... `passed`. Then run the autosaver suite 20 times to shake out ordering flakes:
`for i in {1..20}; do nice -n 10 swift test -j 2 --skip-build --filter SidebarAutosaverTests >/dev/null || echo "run $i failed"; done`
Expected: no output.

**Step 6: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/Persistence/SidebarAutosaver.swift \
  app/ArktCore/Tests/PersistenceTests/TestSupport.swift \
  app/ArktCore/Tests/PersistenceTests/SidebarAutosaverTests.swift
git commit -m "Add debounced background sidebar autosaver"
```

---

### Task D4a: Archive model, archive and restore

**Files:**
- Modify: `app/ArktCore/Package.swift`
- Create: `app/ArktCore/Sources/Archive/ArchivedItem.swift`
- Create: `app/ArktCore/Sources/Archive/Archiver.swift`
- Create: `app/ArktCore/Tests/ArchiveTests/ArchiverTests.swift`

**Step 1: Manifest.** Add product `.library(name: "Archive", targets: ["Archive"])`, target
`.target(name: "Archive", dependencies: ["SidebarModel"])` and
`.testTarget(name: "ArchiveTests", dependencies: ["Archive", "SidebarModel"])`.

**Step 2: Write the failing tests** (`ArchiverTests.swift`)

```swift
import Archive
import Foundation
import Testing
import SidebarModel

struct ArchiverTests {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  struct World {
    var sidebar = Sidebar()
    var work: SpaceID
    var folder: NodeID
    var nested: NodeID
    var today: [NodeID]
    var favorite: NodeID
  }

  static func makeWorld() throws -> World {
    var sidebar = Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(work))
    let nested = try sidebar.addTab(url: url("n"), title: "Nested", in: .folder(folder))
    let t1 = try sidebar.addTab(url: url("1"), title: "One", customTitle: "Uno", in: .today(work))
    let t2 = try sidebar.addTab(url: url("2"), title: "Two", in: .today(work))
    let favorite = try sidebar.addTab(url: url("f"), title: "Fav", in: .favorites(profile: "default"))
    return World(sidebar: sidebar, work: work, folder: folder, nested: nested, today: [t1, t2], favorite: favorite)
  }

  /// BH-071: Cmd-W on a Today tab removes it from the sidebar and archives it with reason manual.
  @Test func archivingATodayTabRemovesItAndRecordsTheSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(world.sidebar.nodes[world.today[0]] == nil)
    #expect(world.sidebar.children(of: .today(world.work)) == [world.today[1]])
    #expect(item.id == world.today[0])
    #expect(item.reason == .manual)
    #expect(item.archivedAt == Self.now)
    #expect(item.source == .space(world.work))
  }

  @Test func archivingAFolderSnapshotsTheWholeSubtree() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.snapshot.allIDs == [world.folder, world.nested])
    #expect(world.sidebar.nodes[world.nested] == nil)
  }

  @Test func nestedNodeSourceIsItsSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.nested, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.source == .space(world.work))
  }

  @Test func favoriteSourceIsUnknown() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.favorite, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(item.source == .unknown)
  }

  @Test func archivingAnUnknownNodeThrows() throws {
    var world = try Self.makeWorld()
    let id = NodeID()
    #expect(throws: SidebarError.unknownNode(id)) {
      try Archiver.archive(id, from: &world.sidebar, reason: .auto, at: Self.now)
    }
  }

  /// BH-086: a restored tab returns to its original Space (top of Today [I]) with its original id.
  @Test func restoredTabGoesToTheTopOfTodayInItsSpace() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[1], from: &world.sidebar, reason: .auto, at: Self.now)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored == RestoredItem(nodeID: world.today[1], space: world.work, location: .today(world.work)))
    #expect(world.sidebar.children(of: .today(world.work)) == [world.today[1], world.today[0]])
  }

  /// BH-086, BH-090: a restored folder returns to the end of its Space's Pinned section with its children.
  @Test func restoredFolderGoesToTheEndOfPinned() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    let restored = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(restored.location == .pinned(world.work))
    #expect(world.sidebar.children(of: .pinned(world.work)).last == world.folder)
    #expect(world.sidebar.children(of: .folder(world.folder)) == [world.nested])
  }

  /// BH-138: Little Arc items (and items whose Space is gone) restore into the caller's fallback Space.
  @Test func littleArcAndMissingSpaceUseTheFallback() throws {
    var world = try Self.makeWorld()
    let tab = NodeSnapshot(kind: .tab(TabItem(url: Self.url("l"), title: "L")), createdAt: Self.now)
    let little = ArchivedItem(reason: .manual, archivedAt: Self.now, source: .littleArc, snapshot: tab)
    #expect(try Archiver.restore(little, into: &world.sidebar, fallbackSpace: world.work).space == world.work)
    let gone = ArchivedItem(
      reason: .auto, archivedAt: Self.now, source: .space(SpaceID()), snapshot: tab.withFreshIDs())
    #expect(try Archiver.restore(gone, into: &world.sidebar, fallbackSpace: world.work).space == world.work)
    let badFallback = SpaceID()
    let other = ArchivedItem(reason: .auto, archivedAt: Self.now, source: .unknown, snapshot: tab.withFreshIDs())
    #expect(throws: SidebarError.invalidDestination(.today(badFallback))) {
      try Archiver.restore(other, into: &world.sidebar, fallbackSpace: badFallback)
    }
  }

  @Test func restoreOverATakenIDUsesFreshIDs() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    _ = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    let again = try Archiver.restore(item, into: &world.sidebar, fallbackSpace: world.work)
    #expect(again.nodeID != world.today[0])
    #expect(world.sidebar.children(of: .today(world.work)).count == 3)
  }

  @Test func archivedItemRoundTripsThroughJSON() throws {
    var world = try Self.makeWorld()
    let item = try Archiver.archive(world.folder, from: &world.sidebar, reason: .auto, at: Self.now)
    let data = try SidebarStorageFormat.makeEncoder().encode(item)
    #expect(try SidebarStorageFormat.makeDecoder().decode(ArchivedItem.self, from: data) == item)
  }

  @Test func titleAndURLComeFromTheSnapshot() throws {
    var world = try Self.makeWorld()
    let tab = try Archiver.archive(world.today[0], from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(tab.title == "Uno")
    #expect(tab.url == Self.url("1"))
    let folder = try Archiver.archive(world.folder, from: &world.sidebar, reason: .manual, at: Self.now)
    #expect(folder.title == "Docs")
    #expect(folder.url == nil)
  }
}
```

**Step 3: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter ArchiverTests`
Expected: build fails (module `Archive` has no `ArchivedItem`, `Archiver`, `RestoredItem`).

**Step 4: Implement**

`ArchivedItem.swift`:

```swift
import Foundation
import SidebarModel

/// Why an item is in the archive (Arc: `reason`, data-model 2.2).
public enum ArchiveReason: String, Codable, Hashable, Sendable, CaseIterable {
  /// Closed by the user (Cmd-W, Clear, Archive Below): BH-071, BH-075, BH-077.
  case manual
  /// Archived by the idle policy: BH-080.
  case auto
}

/// Where an archived item came from (Arc: `source`, data-model 2.2). Drives the Archive filters (BH-088).
public enum ArchiveSource: Hashable, Sendable, Codable {
  case space(SpaceID)
  case littleArc
  case unknown
}

/// One archive entry: a full snapshot of the archived node and its subtree.
public struct ArchivedItem: Identifiable, Hashable, Sendable, Codable {
  public var reason: ArchiveReason
  public var archivedAt: Date
  public var source: ArchiveSource
  public var snapshot: NodeSnapshot

  public init(reason: ArchiveReason, archivedAt: Date, source: ArchiveSource, snapshot: NodeSnapshot) {
    self.reason = reason
    self.archivedAt = archivedAt
    self.source = source
    self.snapshot = snapshot
  }

  /// The archived root node's id; one entry per root, as Arc keys its archive by item id.
  public var id: NodeID { snapshot.id }

  /// Display and search title: a tab's custom title or page title, a folder's title, a split's pane titles.
  public var title: String {
    switch snapshot.kind {
    case .tab(let tab): tab.customTitle ?? tab.title
    case .folder(let folder): folder.title
    case .split:
      snapshot.children.compactMap { child -> String? in
        if case .tab(let tab) = child.kind { return tab.customTitle ?? tab.title }
        return nil
      }.joined(separator: " | ")
    }
  }

  /// The tab URL, nil for folders and splits.
  public var url: URL? {
    if case .tab(let tab) = snapshot.kind { return tab.url }
    return nil
  }
}
```

`Archiver.swift`:

```swift
import Foundation
import SidebarModel

public struct RestoredItem: Hashable, Sendable {
  public var nodeID: NodeID
  public var space: SpaceID
  public var location: Location

  public init(nodeID: NodeID, space: SpaceID, location: Location) {
    self.nodeID = nodeID
    self.space = space
    self.location = location
  }
}

extension Sidebar {
  /// The top-level section (favorites, pinned, today) that holds `id`, directly or through folders and splits.
  public func section(of id: NodeID) -> Location? {
    var location = nodes[id]?.parent
    while let current = location, let container = current.containerNode {
      location = nodes[container]?.parent
    }
    return location
  }
}

/// Moves nodes between the sidebar and archive entries. Pure: callers persist the results.
public enum Archiver {
  /// Removes `id` and its subtree and returns the archive entry. Source is the containing Space; Favorites give
  /// `.unknown`. Whether an action archives at all (pinned Cmd-W does not, BH-067) is the caller's decision.
  public static func archive(
    _ id: NodeID, from sidebar: inout Sidebar, reason: ArchiveReason, at date: Date
  ) throws -> ArchivedItem {
    guard let snapshot = sidebar.snapshot(of: id) else { throw SidebarError.unknownNode(id) }
    let source: ArchiveSource = switch sidebar.section(of: id) {
    case .pinned(let space)?, .today(let space)?: .space(space)
    default: .unknown
    }
    sidebar.remove(id)
    return ArchivedItem(reason: reason, archivedAt: date, source: source, snapshot: snapshot)
  }

  /// Puts `item` back (BH-086): folders at the end of Pinned (BH-090), tabs and splits at the top of Today [I], in the
  /// source Space if it still exists, else in `fallbackSpace` (Little Arc and unknown sources too). Air Traffic
  /// Control routing (BH-157) is applied by the caller when choosing `fallbackSpace`. Original ids are kept unless one
  /// is taken, then the whole subtree gets fresh ids. The sidebar is unchanged on throw.
  public static func restore(
    _ item: ArchivedItem, into sidebar: inout Sidebar, fallbackSpace: SpaceID
  ) throws -> RestoredItem {
    var space = fallbackSpace
    if case .space(let original) = item.source, sidebar.spaces[original] != nil { space = original }
    let isFolder = if case .folder = item.snapshot.kind { true } else { false }
    let location: Location = isFolder ? .pinned(space) : .today(space)
    let taken = item.snapshot.allIDs.contains { sidebar.nodes[$0] != nil }
    let snapshot = taken ? item.snapshot.withFreshIDs() : item.snapshot
    try sidebar.insert(snapshot, in: location, at: isFolder ? nil : 0)
    return RestoredItem(nodeID: snapshot.id, space: space, location: location)
  }
}
```

**Step 5: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 147 tests` ... `passed`.

**Step 6: Commit**
```zsh
cd $WT && git add app/ArktCore/Package.swift app/ArktCore/Sources/Archive/ArchivedItem.swift \
  app/ArktCore/Sources/Archive/Archiver.swift app/ArktCore/Tests/ArchiveTests/ArchiverTests.swift
git commit -m "Add archive model with archive and restore"
```

---

### Task D4b: Auto-archive policy (pure)

**Files:**
- Create: `app/ArktCore/Sources/Archive/AutoArchivePolicy.swift`
- Create: `app/ArktCore/Tests/ArchiveTests/AutoArchivePolicyTests.swift`

**Step 1: Write the failing tests** (`AutoArchivePolicyTests.swift`)

```swift
import Archive
import Foundation
import Testing
import SidebarModel

struct AutoArchivePolicyTests {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static let hour: TimeInterval = 3600
  static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  static func input(
    threshold: AutoArchiveThreshold = .twelveHours,
    perProfile: [String: AutoArchiveThreshold] = [:],
    exempt: Set<NodeID> = [],
    startedAt: Date = .distantPast
  ) -> AutoArchiveInput {
    AutoArchiveInput(now: now, startedAt: startedAt, exempt: exempt) { perProfile[$0] ?? threshold }
  }

  /// Space "Work" with one Today tab last active `idle` seconds ago.
  static func oneTodayTab(idle: TimeInterval) throws -> (Sidebar, NodeID) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(
      url: url("t"), title: "T", lastActiveAt: ago(idle), in: .today(space), createdAt: ago(100 * hour))
    return (sidebar, tab)
  }

  /// BH-080: fresh install, a Today tab unviewed for 12 hours is auto-archived (boundary included).
  @Test func todayTabIdleForTwelveHoursIsArchivedByDefault() throws {
    let (sidebar, tab) = try Self.oneTodayTab(idle: 12 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [tab])
  }

  /// BH-080
  @Test func todayTabJustUnderTheThresholdStays() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 12 * Self.hour - 1)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()).isEmpty)
  }

  /// BH-080: viewing a tab resets its timer (lastActiveAt wins over an old createdAt).
  @Test func viewingResetsTheTimer() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 60)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-054, BH-084: pinned tabs never auto-archive.
  @Test func pinnedTabsAreNeverArchived() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    try sidebar.addTab(url: Self.url("p"), title: "P", lastActiveAt: Self.ago(400 * Self.hour), in: .pinned(space))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-048, BH-084: Favorites never auto-archive.
  @Test func favoritesAreNeverArchived() throws {
    var sidebar = Sidebar()
    sidebar.addSpace(title: "Work")
    try sidebar.addTab(
      url: Self.url("f"), title: "F", lastActiveAt: Self.ago(400 * Self.hour), in: .favorites(profile: "default"))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-084, BH-090: tabs in folders never auto-archive, including a folder that sits in Today.
  @Test func folderedTabsAreNeverArchived() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let pinnedFolder = try sidebar.addFolder(title: "P", in: .pinned(space))
    let todayFolder = try sidebar.addFolder(title: "T", in: .today(space), createdAt: Self.ago(400 * Self.hour))
    for folder in [pinnedFolder, todayFolder] {
      try sidebar.addTab(url: Self.url("x"), title: "X", lastActiveAt: Self.ago(400 * Self.hour), in: .folder(folder))
    }
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-081: "never" archives nothing.
  @Test func neverArchivesNothing() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 1000 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .never)).isEmpty)
  }

  /// BH-081: every finite option archives at exactly its interval and not one second before.
  @Test(arguments: AutoArchiveThreshold.allCases.filter { $0 != .never })
  func everyOptionUsesItsInterval(_ threshold: AutoArchiveThreshold) throws {
    let interval = try #require(threshold.interval)
    let (atLimit, tab) = try Self.oneTodayTab(idle: interval)
    #expect(AutoArchivePolicy.itemsToArchive(in: atLimit, Self.input(threshold: threshold)) == [tab])
    let (under, _) = try Self.oneTodayTab(idle: interval - 1)
    #expect(AutoArchivePolicy.itemsToArchive(in: under, Self.input(threshold: threshold)).isEmpty)
  }

  /// BH-083, BH-179: each profile has its own threshold; a Space uses its profile's.
  @Test func perProfileThresholds() throws {
    var sidebar = Sidebar()
    let personal = sidebar.addSpace(title: "Home", profile: "default")
    let work = sidebar.addSpace(title: "Work", profile: "work")
    try sidebar.addTab(url: Self.url("h"), title: "H", lastActiveAt: Self.ago(2 * Self.hour), in: .today(personal))
    let workTab = try sidebar.addTab(
      url: Self.url("w"), title: "W", lastActiveAt: Self.ago(2 * Self.hour), in: .today(work))
    let input = Self.input(threshold: .twelveHours, perProfile: ["work": .oneHour])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [workTab])
  }

  /// BH-076: a Today tab playing media is not archived.
  @Test func exemptTabsStay() throws {
    let (sidebar, tab) = try Self.oneTodayTab(idle: 400 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(exempt: [tab])).isEmpty)
  }

  /// Arc's autoArchiveStartTime (data-model 2.1): idle time never counts from before auto-archive started.
  @Test func idleTimeCountsFromStartedAt() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 400 * Self.hour)
    let input = Self.input(startedAt: Self.ago(Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input).isEmpty)
  }

  @Test func tabWithoutLastActiveUsesCreatedAt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let old = try sidebar.addTab(url: Self.url("o"), title: "O", in: .today(space), createdAt: Self.ago(13 * Self.hour))
    try sidebar.addTab(url: Self.url("n"), title: "N", in: .today(space), createdAt: Self.ago(Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [old])
  }

  /// [I] A split in Today is one unit: archived only when its most recent pane is idle and no pane is exempt.
  @Test func splitInTodayIsArchivedAsAUnit() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(
      orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space), createdAt: Self.ago(100 * Self.hour))
    let oldPane = try sidebar.addTab(
      url: Self.url("a"), title: "A", lastActiveAt: Self.ago(20 * Self.hour), in: .split(split))
    let recentPane = try sidebar.addTab(
      url: Self.url("b"), title: "B", lastActiveAt: Self.ago(Self.hour), in: .split(split))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()).isEmpty)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)) == [split])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour, exempt: [oldPane])).isEmpty)
    _ = recentPane
  }

  @Test func resultFollowsSpaceThenTodayOrder() throws {
    var sidebar = Sidebar()
    let first = sidebar.addSpace(title: "1")
    let second = sidebar.addSpace(title: "2")
    let b = try sidebar.addTab(url: Self.url("b"), title: "B", lastActiveAt: Self.ago(99 * Self.hour), in: .today(second))
    let a1 = try sidebar.addTab(url: Self.url("a1"), title: "A1", lastActiveAt: Self.ago(99 * Self.hour), in: .today(first))
    let a2 = try sidebar.addTab(url: Self.url("a2"), title: "A2", lastActiveAt: Self.ago(99 * Self.hour), in: .today(first))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [a1, a2, b])
  }

  /// BH-137: Little Arc windows idle for 6 hours (their own default) are closed and archived.
  @Test func littleArcWindowsUseTheirOwnSixHourDefault() {
    let idle = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(6 * Self.hour))
    let fresh = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(6 * Self.hour - 1))
    let result = AutoArchivePolicy.littleArcWindowsToArchive(
      [idle, fresh], threshold: AutoArchiveThreshold.littleArcDefault, now: Self.now, exempt: [])
    #expect(AutoArchiveThreshold.littleArcDefault == .sixHours)
    #expect(result == [idle.id])
  }

  /// BH-137, BH-076: "never" and exempt windows stay.
  @Test func littleArcNeverAndExemptWindowsStay() {
    let idle = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(100 * Self.hour))
    #expect(AutoArchivePolicy.littleArcWindowsToArchive([idle], threshold: .never, now: Self.now, exempt: []).isEmpty)
    #expect(AutoArchivePolicy.littleArcWindowsToArchive(
      [idle], threshold: .oneHour, now: Self.now, exempt: [idle.id]).isEmpty)
  }
}
```

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter AutoArchivePolicyTests`
Expected: build fails (`AutoArchiveThreshold`, `AutoArchiveInput`, `AutoArchivePolicy`, `LittleArcWindowActivity`).

**Step 3: Implement** (`AutoArchivePolicy.swift`)

```swift
import Foundation
import SidebarModel

/// "Archive tabs after" / "Archive Little Arcs after:" options (BH-081). Raw values reuse the threshold
/// strings Arc writes in its settings, where they exist (data-model 2.1); `oneHour`, `sixHours`, `never` are ours.
public enum AutoArchiveThreshold: String, CaseIterable, Codable, Hashable, Sendable {
  case oneHour, sixHours, twelveHours, twentyFourHours, sevenDays, thirtyDays, never

  /// Fresh-install tab default (BH-080).
  public static let tabsDefault: AutoArchiveThreshold = .twelveHours
  /// Fresh-install Little Arc default (BH-137).
  public static let littleArcDefault: AutoArchiveThreshold = .sixHours

  /// Idle time after which an item is archived; nil for `never`.
  public var interval: TimeInterval? {
    switch self {
    case .oneHour: 3600
    case .sixHours: 6 * 3600
    case .twelveHours: 12 * 3600
    case .twentyFourHours: 24 * 3600
    case .sevenDays: 7 * 86_400
    case .thirtyDays: 30 * 86_400
    case .never: nil
    }
  }
}

public struct AutoArchiveInput: Sendable {
  public var now: Date
  /// When auto-archive started on this install (Arc: `autoArchiveStartTime` in Arc's archive JSON). Idle time never counts
  /// from earlier, so an Arc import or first launch does not archive everything at once.
  public var startedAt: Date
  /// Never archived this run: tabs playing media (BH-076) and tabs visible in a window.
  public var exempt: Set<NodeID>
  /// The tab threshold for a profile name (BH-083, BH-179). App code passes `ArchiveSettings.tabThreshold(forProfile:)`.
  public var threshold: @Sendable (_ profile: String) -> AutoArchiveThreshold

  public init(
    now: Date, startedAt: Date, exempt: Set<NodeID> = [],
    threshold: @escaping @Sendable (_ profile: String) -> AutoArchiveThreshold
  ) {
    self.now = now
    self.startedAt = startedAt
    self.exempt = exempt
    self.threshold = threshold
  }
}

public struct LittleArcWindowActivity: Hashable, Sendable {
  public var id: UUID
  public var lastActiveAt: Date

  public init(id: UUID, lastActiveAt: Date) {
    self.id = id
    self.lastActiveAt = lastActiveAt
  }
}

/// Which items the idle timer archives. Pure; the caller archives them with reason `.auto` and shows the toast
/// "Auto archived N tabs" (BH-085).
public enum AutoArchivePolicy {
  /// Direct children of each Space's Today section whose idle time reached the Space profile's threshold, in Space
  /// order then Today order. Pinned (BH-054), Favorites (BH-048) and folder contents (BH-084, BH-090) are never
  /// candidates; a folder directly in Today is skipped as a unit [I]. Idle reference: `lastActiveAt ?? createdAt`,
  /// clamped to `startedAt`. Idle time equal to the threshold archives.
  public static func itemsToArchive(in sidebar: Sidebar, _ input: AutoArchiveInput) -> [NodeID] {
    var result: [NodeID] = []
    for spaceID in sidebar.spaceOrder {
      guard let space = sidebar.spaces[spaceID], let interval = input.threshold(space.profile).interval else {
        continue
      }
      for id in sidebar.children(of: .today(spaceID)) {
        guard let lastActive = lastActive(id, in: sidebar, exempt: input.exempt) else { continue }
        if input.now.timeIntervalSince(max(lastActive, input.startedAt)) >= interval { result.append(id) }
      }
    }
    return result
  }

  /// Little Arc windows past their own threshold (BH-137), in input order.
  public static func littleArcWindowsToArchive(
    _ windows: [LittleArcWindowActivity], threshold: AutoArchiveThreshold, now: Date, exempt: Set<UUID>
  ) -> [UUID] {
    guard let interval = threshold.interval else { return [] }
    return windows
      .filter { !exempt.contains($0.id) && now.timeIntervalSince($0.lastActiveAt) >= interval }
      .map(\.id)
  }

  /// Nil means "not a candidate". Splits are one unit [I]: the most recent pane counts, any exempt pane protects it.
  static func lastActive(_ id: NodeID, in sidebar: Sidebar, exempt: Set<NodeID>) -> Date? {
    guard !exempt.contains(id), let node = sidebar.nodes[id] else { return nil }
    switch node.kind {
    case .tab(let tab):
      return tab.lastActiveAt ?? node.createdAt
    case .folder:
      return nil
    case .split:
      var latest: Date?
      for pane in sidebar.children(of: .split(id)) {
        guard !exempt.contains(pane), let paneNode = sidebar.nodes[pane] else { return nil }
        if case .tab(let tab) = paneNode.kind {
          let paneActive = tab.lastActiveAt ?? paneNode.createdAt
          latest = max(latest ?? paneActive, paneActive)
        }
      }
      return latest ?? node.createdAt
    }
  }
}
```

**Step 4: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 163 tests` ... `passed`.

**Step 5: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/Archive/AutoArchivePolicy.swift \
  app/ArktCore/Tests/ArchiveTests/AutoArchivePolicyTests.swift
git commit -m "Add auto-archive policy matching Arc thresholds"
```

---

### Task D4c: `ArchiveStore` and pre-migration backup

> **Review follow-up (D4a F1, required before implementing D4c):** `ArchivedItem.section` must round-trip. Store it in
> `section_kind` / `section_profile` (both nullable; nil section = unknown, e.g. Arc imports), include both in the
> INSERT and SELECT statements below, and add a store round-trip test for each section kind plus nil.
>
> **Review follow-up (D4c, later):** (1) Search is ASCII case-insensitive `LIKE` over title and URL only. Make it
> Unicode case- and diacritic-insensitive (a `search_text` column filled with folded text, or FTS5) and include the
> tabs inside archived folders and splits; check BH-087 for what Arc matches. (2) Add a deterministic test that the
> leftover sweep (`Backups.removeLeftovers`) runs at launch only and never removes the temp file of a backup in
> progress.

**Files:**
- Modify: `app/ArktCore/Package.swift` (Persistence depends on `Archive`; PersistenceTests too)
- Modify: `app/ArktCore/Sources/Persistence/ArktDatabase.swift` (migration `v2-archive`, pre-migration backup)
- Create: `app/ArktCore/Sources/Persistence/ArchiveStore.swift`
- Create: `app/ArktCore/Tests/PersistenceTests/ArchiveStoreTests.swift`
- Modify: `app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift` (expected migration list)

**Step 1: Write the failing tests** (`ArchiveStoreTests.swift`)

```swift
import Archive
import Foundation
import GRDB
import Testing
@testable import Persistence
import SidebarModel

struct ArchiveStoreTests {
  static func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

  static func tab(_ title: String, url: String, source: ArchiveSource, reason: ArchiveReason = .manual, at seconds: Double)
    -> ArchivedItem
  {
    let snapshot = NodeSnapshot(kind: .tab(TabItem(url: URL(string: url)!, title: title)), createdAt: Self.at(0))
    return ArchivedItem(reason: reason, archivedAt: Self.at(seconds), source: source, snapshot: snapshot)
  }

  @Test func addThenFetchNewestFirst() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let old = Self.tab("Old", url: "https://example.com/o", source: .unknown, at: 1)
    let new = Self.tab("New", url: "https://example.com/n", source: .unknown, at: 2)
    #expect(try await store.add([old, new]) == 2)
    #expect(try await store.items() == [new, old])
    #expect(try await store.count() == 2)
  }

  @Test func addingTheSameIDTwiceIsIgnored() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let item = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
    #expect(try await store.add([item]) == 1)
    #expect(try await store.add([item]) == 0)
    #expect(try await store.count() == 1)
  }

  /// BH-088: filter by Space.
  @Test func filtersBySpace() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let (s1, s2) = (SpaceID(), SpaceID())
    let a = Self.tab("A", url: "https://example.com/a", source: .space(s1), at: 1)
    let b = Self.tab("B", url: "https://example.com/b", source: .space(s2), at: 2)
    _ = try await store.add([a, b])
    #expect(try await store.items(matching: ArchiveFilter(source: .space(s1))) == [a])
  }

  /// BH-088, BH-138: filter by Little Arc.
  @Test func filtersByLittleArc() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let little = Self.tab("L", url: "https://example.com/l", source: .littleArc, at: 1)
    _ = try await store.add([little, Self.tab("U", url: "https://example.com/u", source: .unknown, at: 2)])
    #expect(try await store.items(matching: ArchiveFilter(source: .littleArc)) == [little])
  }

  /// BH-088: filter by close type.
  @Test func filtersByReason() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let auto = Self.tab("Auto", url: "https://example.com/1", source: .unknown, reason: .auto, at: 1)
    _ = try await store.add([auto, Self.tab("Manual", url: "https://example.com/2", source: .unknown, at: 2)])
    #expect(try await store.items(matching: ArchiveFilter(reason: .auto)) == [auto])
  }

  /// BH-087: search matches title or URL, case-insensitively; LIKE wildcards in the query are literal.
  @Test func textSearchMatchesTitleAndURL() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let byTitle = Self.tab("Quarterly Report", url: "https://example.com/1", source: .unknown, at: 1)
    let byURL = Self.tab("x", url: "https://docs.example.org/report", source: .unknown, at: 2)
    let percent = Self.tab("100% done", url: "https://example.com/3", source: .unknown, at: 3)
    _ = try await store.add([byTitle, byURL, percent])
    #expect(try await store.items(matching: ArchiveFilter(text: "REPORT")) == [byURL, byTitle])
    #expect(try await store.items(matching: ArchiveFilter(text: "0%")) == [percent])
    #expect(try await store.items(matching: ArchiveFilter(text: "_")).isEmpty)
  }

  @Test func removeDeletesRestoredItems() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let a = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
    let b = Self.tab("B", url: "https://example.com/b", source: .unknown, at: 2)
    _ = try await store.add([a, b])
    try await store.remove([a.id])
    #expect(try await store.items() == [b])
  }

  /// BH-087: Clear Archive.
  @Test func removeAllClearsTheArchive() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    _ = try await store.add([Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)])
    try await store.removeAll()
    #expect(try await store.count() == 0)
  }

  @Test func unreadableSnapshotRowsAreSkipped() async throws {
    let database = try ArktDatabase.inMemory()
    let store = ArchiveStore(database: database)
    let good = Self.tab("A", url: "https://example.com/a", source: .unknown, at: 1)
    _ = try await store.add([good])
    try await database.writer.write { db in
      try db.execute(sql: """
        INSERT INTO archived_item (id, reason, archived_at, source_kind, source_space_id, title, url, snapshot)
        VALUES ('BAD', 'manual', 0, 'unknown', NULL, 't', NULL, x'00')
        """)
    }
    #expect(try await store.items() == [good])
  }

  @Test func folderSnapshotRoundTrips() async throws {
    let store = ArchiveStore(database: try ArktDatabase.inMemory())
    let child = NodeSnapshot(kind: .tab(TabItem(url: URL(string: "https://example.com/c")!, title: "C")), createdAt: Self.at(0))
    let folder = NodeSnapshot(kind: .folder(FolderItem(title: "F")), createdAt: Self.at(0), children: [child])
    let item = ArchivedItem(reason: .manual, archivedAt: Self.at(1), source: .space(SpaceID()), snapshot: folder)
    _ = try await store.add([item])
    #expect(try await store.items() == [item])
  }

  @Test func openingAnOlderSchemaBacksItUpFirst() async throws {
    try await withTemporaryDirectory { directory in
      let location = DatabaseLocation(directory: directory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      do {
        let queue = try DatabaseQueue(path: location.databaseURL.path)
        try ArktDatabase.migrator.migrate(queue, upTo: "v1-sidebar")
        try queue.close()
      }
      _ = try await ArktLaunch.openAndLoad(location, now: Self.at(5))
      #expect(try Backups.list(in: location.backupsDirectory).count == 1)
      _ = try await ArktLaunch.openAndLoad(location, now: Self.at(6))  // already current: no new backup
      #expect(try Backups.list(in: location.backupsDirectory).count == 1)
    }
  }
}
```

In `SidebarStoreTests.reopeningRunsNoMigrationTwice`, change the expectation to `["v1-sidebar", "v2-archive"]`.

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter ArchiveStoreTests`
Expected: build fails (`ArchiveStore`, `ArchiveFilter` unknown; `Archive` not a Persistence dependency).

**Step 3: Implement**

`Package.swift`: Persistence dependencies become `["SidebarModel", "Archive", .product(name: "GRDB", package:
"GRDB.swift")]`; PersistenceTests dependencies become
`["Persistence", "SidebarModel", "Archive", .product(name: "GRDB", package: "GRDB.swift")]`.

`ArktDatabase.swift`:
- Register after `v1-sidebar`:
  ```swift
  migrator.registerMigration("v2-archive") { db in
    try db.execute(sql: """
      CREATE TABLE archived_item (
        id TEXT PRIMARY KEY NOT NULL,
        reason TEXT NOT NULL CHECK (reason IN ('manual', 'auto')),
        archived_at REAL NOT NULL,
        source_kind TEXT NOT NULL CHECK (source_kind IN ('space', 'littleArc', 'unknown')),
        source_space_id TEXT,
        section_kind TEXT CHECK (section_kind IN ('pinned', 'today', 'favorites')),
        section_profile TEXT,
        title TEXT NOT NULL,
        url TEXT,
        snapshot BLOB NOT NULL
      );
      CREATE INDEX archived_item_archived_at ON archived_item (archived_at DESC);
      CREATE INDEX archived_item_source ON archived_item (source_kind, source_space_id);
      """)
  }
  ```
- Change `open(at:)` to `open(at url: URL, backupsDirectory: URL? = nil, now: Date = Date())`. Between creating the
  queue and `migrator.migrate(queue)` insert:
  ```swift
  if let backupsDirectory {
    // An existing database on an older schema is backed up before any migration touches it.
    let isOlderSchema = try queue.read { db -> Bool in
      let started = try !migrator.completedMigrations(db).isEmpty
      let current = try migrator.hasCompletedMigrations(db)
      return started && !current
    }
    if isOlderSchema { _ = try Backups.write(from: queue, to: backupsDirectory, now: now) }
  }
  ```
- In `ArktLaunch.attempt`, pass `backupsDirectory: location.backupsDirectory, now: now` (thread `location` and
  `now` through `attempt`'s parameters). The `.created` and `.recreatedEmpty` paths keep plain `open(at:)`.

`ArchiveStore.swift`:

```swift
import Archive
import Foundation
import GRDB
import SidebarModel

public struct ArchiveFilter: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case space(SpaceID)
    case littleArc
  }

  public var source: Source?
  public var reason: ArchiveReason?
  /// Case-insensitive (ASCII) substring of the title or URL.
  public var text: String?

  public init(source: Source? = nil, reason: ArchiveReason? = nil, text: String? = nil) {
    self.source = source
    self.reason = reason
    self.text = text
  }
}

/// The archive table. Snapshots are D1 JSON; title, URL, reason and source are columns for search and filters.
public struct ArchiveStore: Sendable {
  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// Inserts items in one transaction; ids already present are ignored (re-import safe). Returns how many were new.
  @concurrent
  public func add(_ items: [ArchivedItem]) async throws -> Int {
    let encoder = SidebarStorageFormat.makeEncoder()
    let rows = try items.map { item in
      let (kind, space): (String, String?) = switch item.source {
      case .space(let id): ("space", id.uuidString)
      case .littleArc: ("littleArc", nil)
      case .unknown: ("unknown", nil)
      }
      return InsertRow(
        id: item.id.uuidString, reason: item.reason.rawValue,
        archivedAt: item.archivedAt.timeIntervalSinceReferenceDate, sourceKind: kind, sourceSpaceID: space,
        title: item.title, url: item.url?.absoluteString, snapshot: try encoder.encode(item.snapshot))
    }
    return try await database.writer.write { db in
      var inserted = 0
      for row in rows {
        try db.execute(
          sql: """
            INSERT OR IGNORE INTO archived_item
              (id, reason, archived_at, source_kind, source_space_id, title, url, snapshot)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [row.id, row.reason, row.archivedAt, row.sourceKind, row.sourceSpaceID, row.title, row.url,
                      row.snapshot])
        inserted += db.changesCount
      }
      return inserted
    }
  }

  /// Matching items, newest first. Rows whose snapshot no longer decodes are skipped.
  @concurrent
  public func items(matching filter: ArchiveFilter = ArchiveFilter(), limit: Int? = nil) async throws
    -> [ArchivedItem]
  {
    let rows = try await database.writer.read { db -> [FetchedRow] in
      var clauses: [String] = []
      var arguments: StatementArguments = []
      switch filter.source {
      case .space(let id)?:
        clauses.append("source_kind = 'space' AND source_space_id = ?")
        arguments += [id.uuidString]
      case .littleArc?:
        clauses.append("source_kind = 'littleArc'")
      case nil:
        break
      }
      if let reason = filter.reason {
        clauses.append("reason = ?")
        arguments += [reason.rawValue]
      }
      if let text = filter.text, !text.isEmpty {
        let pattern = "%" + Self.escapeLike(text) + "%"
        clauses.append("(title LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\')")
        arguments += [pattern, pattern]
      }
      var sql = "SELECT reason, archived_at, source_kind, source_space_id, snapshot FROM archived_item"
      if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
      sql += " ORDER BY archived_at DESC, id"
      if let limit { sql += " LIMIT \(max(limit, 0))" }
      return try Row.fetchAll(db, sql: sql, arguments: arguments).map(FetchedRow.init)
    }
    let decoder = SidebarStorageFormat.makeDecoder()
    return rows.compactMap { $0.item(decoder) }
  }

  @concurrent
  public func count() async throws -> Int {
    try await database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM archived_item") ?? 0 }
  }

  /// Deletes entries, for example after a restore.
  @concurrent
  public func remove(_ ids: [NodeID]) async throws {
    let strings = ids.map(\.uuidString)
    try await database.writer.write { db in
      for id in strings { try db.execute(sql: "DELETE FROM archived_item WHERE id = ?", arguments: [id]) }
    }
  }

  /// Clear Archive (BH-087). The confirmation dialog is the caller's.
  @concurrent
  public func removeAll() async throws {
    try await database.writer.write { try $0.execute(sql: "DELETE FROM archived_item") }
  }

  static func escapeLike(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }
}

private struct InsertRow: Sendable {
  var id: String
  var reason: String
  var archivedAt: Double
  var sourceKind: String
  var sourceSpaceID: String?
  var title: String
  var url: String?
  var snapshot: Data
}

private struct FetchedRow: Sendable {
  var reason: String
  var archivedAt: Double
  var sourceKind: String
  var sourceSpaceID: String?
  var snapshot: Data

  init(_ row: Row) {
    reason = row["reason"]
    archivedAt = row["archived_at"]
    sourceKind = row["source_kind"]
    sourceSpaceID = row["source_space_id"]
    snapshot = row["snapshot"]
  }

  func item(_ decoder: JSONDecoder) -> ArchivedItem? {
    guard let reason = ArchiveReason(rawValue: reason),
          let snapshot = try? decoder.decode(NodeSnapshot.self, from: snapshot) else { return nil }
    let source: ArchiveSource
    switch sourceKind {
    case "space":
      guard let id = sourceSpaceID.flatMap(UUID.init(uuidString:)) else { return nil }
      source = .space(id)
    case "littleArc": source = .littleArc
    default: source = .unknown
    }
    return ArchivedItem(
      reason: reason, archivedAt: Date(timeIntervalSinceReferenceDate: archivedAt), source: source,
      snapshot: snapshot)
  }
}
```

**Step 4: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 174 tests` ... `passed`.

**Step 5: Commit**
```zsh
cd $WT && git add app/ArktCore/Package.swift app/ArktCore/Sources/Persistence/ArktDatabase.swift \
  app/ArktCore/Sources/Persistence/ArktLaunch.swift app/ArktCore/Sources/Persistence/ArchiveStore.swift \
  app/ArktCore/Tests/PersistenceTests/ArchiveStoreTests.swift app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift
git commit -m "Add archive store and back up before schema migrations"
```

---

### Task D5a: Decode and import Arc's `StorableArchiveItems.json`

**Files:**
- Modify: `app/ArktCore/Package.swift` (ArcImport and ArcImportTests depend on `Archive`)
- Modify: `app/ArktCore/Sources/ArcImport/ArcSidebarImporter.swift`
- Create: `app/ArktCore/Sources/ArcImport/ArcArchiveFile.swift`
- Create: `app/ArktCore/Sources/ArcImport/ArcArchiveImporter.swift`
- Create: `app/ArktCore/Tests/ArcImportTests/Fixtures/StorableArchiveItems-synthetic.json`
- Create: `app/ArktCore/Tests/ArcImportTests/ArcArchiveImporterTests.swift`

**Step 1: Fixture** (synthetic, built only from data-model 2.2; ids reuse the sidebar fixture's space ids
`...0A1` Alpha and `...0B1` Beta)

```json
{
  "version": 1,
  "items": [
    "C0000000-0000-4000-8000-000000000001",
    { "reason": "manual", "archivedAt": 783000000,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000A1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000001", "parentID": null, "childrenIds": [],
        "title": null, "createdAt": 782990000,
        "data": { "tab": { "savedURL": "https://example.com/manual", "savedTitle": "Manual tab",
                           "timeLastActiveAt": 782999000 } } } },
    "C0000000-0000-4000-8000-000000000002",
    { "reason": "auto", "archivedAt": 783000100,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000B1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000002", "parentID": null, "childrenIds": [],
        "title": "Renamed", "createdAt": 782990100,
        "data": { "tab": { "savedURL": "https://example.com/auto", "savedTitle": "Auto tab" } } } },
    "C0000000-0000-4000-8000-000000000003",
    { "reason": "manual", "archivedAt": 783000200, "source": { "littleArc": {} },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000003", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "https://example.com/little" } } } },
    "C0000000-0000-4000-8000-000000000004",
    { "reason": "auto", "archivedAt": 783000300, "source": { "unknown": {} },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000004", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "https://example.com/unknown", "savedTitle": "Unknown source" } } } },
    "C0000000-0000-4000-8000-000000000005",
    { "reason": "manual", "archivedAt": 783000400,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000FF" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000005", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "https://example.com/gone", "savedTitle": "Gone space" } } } },
    "C0000000-0000-4000-8000-000000000006",
    { "reason": "manual", "archivedAt": 783000500,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000A1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000006", "parentID": null, "childrenIds": [],
        "title": "Old folder", "createdAt": 782990600, "data": { "list": {} } } },
    "C0000000-0000-4000-8000-000000000007",
    { "reason": "auto", "archivedAt": 783000600,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000A1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000007", "parentID": null, "childrenIds": [],
        "data": { "easel": { "easelID": "E1" } } } },
    "C0000000-0000-4000-8000-000000000008",
    { "reason": "manual", "archivedAt": 783000700,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000A1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000008", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "not a url" } } } },
    "C0000000-0000-4000-8000-000000000009",
    { "reason": "manual", "source": { "unknown": {} },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-000000000009", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "https://example.com/no-date" } } } },
    "C0000000-0000-4000-8000-00000000000A",
    { "reason": "trashed", "archivedAt": 783000900,
      "source": { "space": { "_0": "A0000000-0000-4000-8000-0000000000A1" } },
      "sidebarItem": { "id": "C0000000-0000-4000-8000-00000000000A", "parentID": null, "childrenIds": [],
        "data": { "tab": { "savedURL": "https://example.com/odd-reason", "savedTitle": "Odd reason" } } } }
  ]
}
```

Expected import: 7 imported (`001`-`006`, `00A`); manual 5 (`001`, `003`, `005`, `006`, `00A`), auto 2; sources:
space 4 (`001`, `002`, `006`, `00A`), little arc 1 (`003`), unknown 2 (`004`, `005`); skipped 3 (`007`
unsupportedKind, `008` invalidURL, `009` decodeFailed); warnings 2 (`005` archiveSpaceNotImported, `00A`
unsupportedValue reason).

**Step 2: Write the failing tests** (`ArcArchiveImporterTests.swift`)

```swift
import Archive
import Foundation
import Testing
import ArcImport
import SidebarModel

struct ArcArchiveImporterTests {
  static let alpha = SpaceID()
  static let beta = SpaceID()
  static let spaceMap = [ArcSidebarImporterTests.alphaID: alpha, ArcSidebarImporterTests.betaID: beta]

  static func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(
      forResource: "StorableArchiveItems-synthetic", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  static func importFixture() throws -> ArcArchiveImportResult {
    ArcArchiveImporter.makeItems(from: try ArcArchiveFile.decode(fixtureData()), spaceIDsByArcID: spaceMap)
  }

  static func item(_ result: ArcArchiveImportResult, _ suffix: String) throws -> ArchivedItem {
    let id = try #require(UUID(uuidString: "C0000000-0000-4000-8000-000000000\(suffix)"))
    return try #require(result.items.first { $0.id == id })
  }

  @Test func sidebarImportMapsArcSpaceIDs() throws {
    let result = try ArcSidebarImporterTests.importFixtureResult()
    #expect(result.spaceIDsByArcID.count == 2)
    #expect(result.spaceIDsByArcID[ArcSidebarImporterTests.alphaID] == result.sidebar.spaceOrder[0])
    #expect(Set(result.spaceIDsByArcID.values) == Set(result.sidebar.spaceOrder))
  }

  @Test func reportCountsEveryEntry() throws {
    let result = try Self.importFixture()
    #expect(result.items.count == 7)
    #expect(result.report == ArchiveImportReport(
      entries: 10, imported: 7, manual: 5, auto: 2, fromSpace: 4, fromLittleArc: 1, fromUnknown: 2,
      skipped: result.report.skipped, warnings: result.report.warnings))
    #expect(result.report.skipped.count == 3)
    #expect(result.report.warnings.count == 2)
  }

  @Test func manualTabFromASpaceKeepsItsFields() throws {
    let item = try Self.item(try Self.importFixture(), "001")
    #expect(item.reason == .manual)
    #expect(item.archivedAt == Date(timeIntervalSinceReferenceDate: 783_000_000))
    #expect(item.source == .space(Self.alpha))
    #expect(item.snapshot.createdAt == Date(timeIntervalSinceReferenceDate: 782_990_000))
    #expect(item.snapshot.kind == .tab(TabItem(
      url: URL(string: "https://example.com/manual")!, title: "Manual tab",
      lastActiveAt: Date(timeIntervalSinceReferenceDate: 782_999_000))))
    let renamed = try Self.item(try Self.importFixture(), "002")
    #expect(renamed.title == "Renamed")
    #expect(renamed.reason == .auto)
  }

  @Test func littleArcAndUnknownSources() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "003").source == .littleArc)
    #expect(try Self.item(result, "004").source == .unknown)
    // No createdAt in the file: archivedAt stands in.
    #expect(try Self.item(result, "003").snapshot.createdAt == Date(timeIntervalSinceReferenceDate: 783_000_200))
  }

  @Test func spaceThatWasNotImportedBecomesUnknownWithAWarning() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "005").source == .unknown)
    #expect(result.report.warnings.contains(.archiveSpaceNotImported(itemID: "C0000000-0000-4000-8000-000000000005")))
  }

  @Test func listBecomesAnEmptyFolder() throws {
    let item = try Self.item(try Self.importFixture(), "006")
    #expect(item.snapshot.kind == .folder(FolderItem(title: "Old folder")))
    #expect(item.snapshot.children.isEmpty)
  }

  @Test func skipsUnsupportedInvalidAndUndecodableEntries() throws {
    let skipped = try Self.importFixture().report.skipped
    #expect(skipped.contains(SkippedItem(itemID: "C0000000-0000-4000-8000-000000000007", reason: .unsupportedKind("easel"))))
    #expect(skipped.contains(SkippedItem(itemID: "C0000000-0000-4000-8000-000000000008", reason: .invalidURL)))
    #expect(skipped.contains { item in
      guard item.itemID == "C0000000-0000-4000-8000-000000000009", case .decodeFailed = item.reason else { return false }
      return true
    })
  }

  @Test func unknownReasonDefaultsToManualWithAWarning() throws {
    let result = try Self.importFixture()
    #expect(try Self.item(result, "00A").reason == .manual)
    #expect(result.report.warnings.contains(
      .unsupportedValue(itemID: "C0000000-0000-4000-8000-00000000000A", field: "reason")))
  }

  @Test func rejectsAnUnknownFileVersion() throws {
    var json = try #require(try JSONSerialization.jsonObject(with: Self.fixtureData()) as? [String: Any])
    json["version"] = 2
    let file = try ArcArchiveFile.decode(JSONSerialization.data(withJSONObject: json))
    #expect(throws: ArcImportError.unsupportedVersion(2)) {
      try ArcArchiveImporter.checkVersion(file)
    }
  }

  @Test func importingTwiceGivesTheSameIDs() throws {
    #expect(try Self.importFixture().items.map(\.id) == Self.importFixture().items.map(\.id))
  }
}
```

**Step 3: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter ArcArchiveImporterTests`
Expected: build fails (new types and `spaceIDsByArcID` missing).

**Step 4: Implement**

`Package.swift`: `.target(name: "ArcImport", dependencies: ["SidebarModel", "Archive"])`; ArcImportTests
dependencies `["ArcImport", "SidebarModel", "Archive"]`.

`ArcSidebarImporter.swift` (additive, the existing call site keeps compiling):
- `ArcImportError` gains `case unsupportedVersion(Int)`.
- `ImportWarning` gains
  `/// An archived item's source Space was not imported; its source became unknown.`
  `case archiveSpaceNotImported(itemID: String)`.
- `ArcImportResult` gains `public var spaceIDsByArcID: [String: SpaceID]` (doc: "The Arkt Space created for each
  imported Arc space id."), and its init gains a trailing `spaceIDsByArcID: [String: SpaceID] = [:]`.
- `Builder` gains `var spaceIDsByArcID: [String: SpaceID] = [:]`; in `importSpace`, after `addSpace`:
  `spaceIDsByArcID[space.id] = spaceID`; `makeSidebar` passes `spaceIDsByArcID: builder.spaceIDsByArcID`.

`ArcArchiveFile.swift`:

```swift
import Foundation

/// Read-only mirror of Arc's `StorableArchiveItems.json` (data-model 2.2):
/// `{version, items: [itemID, ArchivedItem, ...]}` with `ArchivedItem {reason, archivedAt, source, sidebarItem}`.
public struct ArcArchiveFile: Decodable, Sendable {
  public let version: Int
  /// Entries in file order; a bad entry is kept as a failure and never fails the file.
  public let items: FlatDictionary<String, ArcLossy<ArcArchivedItem>>

  public static func decode(_ data: Data) throws -> ArcArchiveFile {
    try JSONDecoder().decode(ArcArchiveFile.self, from: data)
  }
}

public struct ArcArchivedItem: Decodable, Sendable {
  /// `"manual"` or `"auto"`; anything else is imported as manual with a warning.
  public let reason: String
  public let archivedAt: Date
  /// `{"space": {"_0": spaceID}}`, `{"littleArc": {}}` or `{"unknown": {}}`.
  public let source: TaggedEnum
  /// Full snapshot; Arc writes `parentID` null and `childrenIds` empty.
  public let sidebarItem: ArcItem
}
```

`ArcArchiveImporter.swift`:

```swift
import Archive
import Foundation
import SidebarModel

public struct ArchiveImportReport: Hashable, Sendable {
  /// Entries in the file, including undecodable ones.
  public var entries = 0
  public var imported = 0
  public var manual = 0
  public var auto = 0
  public var fromSpace = 0
  public var fromLittleArc = 0
  public var fromUnknown = 0
  public var skipped: [SkippedItem] = []
  public var warnings: [ImportWarning] = []

  public init(
    entries: Int = 0, imported: Int = 0, manual: Int = 0, auto: Int = 0, fromSpace: Int = 0, fromLittleArc: Int = 0,
    fromUnknown: Int = 0, skipped: [SkippedItem] = [], warnings: [ImportWarning] = []
  ) {
    self.entries = entries
    self.imported = imported
    self.manual = manual
    self.auto = auto
    self.fromSpace = fromSpace
    self.fromLittleArc = fromLittleArc
    self.fromUnknown = fromUnknown
    self.skipped = skipped
    self.warnings = warnings
  }
}

public struct ArcArchiveImportResult: Hashable, Sendable {
  public var items: [ArchivedItem]
  public var report: ArchiveImportReport
}

/// Turns a decoded `StorableArchiveItems.json` into archive entries. Pure: reads nothing and writes nothing.
public enum ArcArchiveImporter {
  public static func checkVersion(_ file: ArcArchiveFile) throws {
    guard file.version == 1 else { throw ArcImportError.unsupportedVersion(file.version) }
  }

  /// Entries in file order. Ids reuse Arc's item UUIDs, so importing twice yields the same ids and `ArchiveStore.add`
  /// ignores the repeats. `spaceIDsByArcID` comes from `ArcImportResult`. Bad entries are skipped and reported.
  public static func makeItems(
    from file: ArcArchiveFile, spaceIDsByArcID: [String: SpaceID]
  ) -> ArcArchiveImportResult {
    var report = ArchiveImportReport()
    var items: [ArchivedItem] = []
    for pair in file.items.pairs {
      report.entries += 1
      let id = pair.key
      guard let entry = pair.value.value else {
        report.skipped.append(SkippedItem(itemID: id, reason: .decodeFailed(pair.value.failureReason ?? "unknown")))
        continue
      }
      let snapshot: NodeSnapshot
      do {
        guard let made = try makeSnapshot(entry, id: id, report: &report) else { continue }
        snapshot = made
      } catch {
        report.skipped.append(SkippedItem(itemID: id, reason: .decodeFailed(String(describing: error))))
        continue
      }

      let reason: ArchiveReason
      if let known = ArchiveReason(rawValue: entry.reason) {
        reason = known
      } else {
        reason = .manual
        report.warnings.append(.unsupportedValue(itemID: id, field: "reason"))
      }

      let source: ArchiveSource
      switch entry.source.caseName {
      case "space":
        if let arcSpace = try? entry.source.payload(String.self), let space = spaceIDsByArcID[arcSpace] {
          source = .space(space)
        } else {
          source = .unknown
          report.warnings.append(.archiveSpaceNotImported(itemID: id))
        }
      case "littleArc": source = .littleArc
      case "unknown": source = .unknown
      default:
        source = .unknown
        report.warnings.append(.unsupportedValue(itemID: id, field: "source"))
      }

      items.append(ArchivedItem(reason: reason, archivedAt: entry.archivedAt, source: source, snapshot: snapshot))
      report.imported += 1
      switch reason {
      case .manual: report.manual += 1
      case .auto: report.auto += 1
      }
      switch source {
      case .space: report.fromSpace += 1
      case .littleArc: report.fromLittleArc += 1
      case .unknown: report.fromUnknown += 1
      }
    }
    return ArcArchiveImportResult(items: items, report: report)
  }

  /// Tab -> tab; list -> folder (children are not in the archive file, so it is empty). Anything else is skipped.
  static func makeSnapshot(
    _ entry: ArcArchivedItem, id: String, report: inout ArchiveImportReport
  ) throws -> NodeSnapshot? {
    let item = entry.sidebarItem
    let nodeID = UUID(uuidString: id) ?? UUID()
    let createdAt = item.createdAt ?? entry.archivedAt
    switch item.data.caseName {
    case "tab":
      guard let tab = try item.tabData else { return nil }
      guard let url = URL(string: tab.savedURL), url.scheme != nil else {
        report.skipped.append(SkippedItem(itemID: id, reason: .invalidURL))
        return nil
      }
      let tabItem = TabItem(url: url, title: tab.savedTitle ?? "", customTitle: item.title, lastActiveAt: tab.timeLastActiveAt)
      return NodeSnapshot(id: nodeID, kind: .tab(tabItem), createdAt: createdAt)
    case "list":
      if !item.childrenIds.isEmpty { report.warnings.append(.unsupportedValue(itemID: id, field: "childrenIds")) }
      return NodeSnapshot(id: nodeID, kind: .folder(FolderItem(title: item.title ?? "Folder")), createdAt: createdAt)
    default:
      report.skipped.append(SkippedItem(itemID: id, reason: .unsupportedKind(item.data.caseName)))
      return nil
    }
  }
}
```

**Step 5: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 184 tests` ... `passed`.

**Step 6: Commit**
```zsh
cd $WT && git add app/ArktCore/Package.swift app/ArktCore/Sources/ArcImport/ArcSidebarImporter.swift \
  app/ArktCore/Sources/ArcImport/ArcArchiveFile.swift app/ArktCore/Sources/ArcImport/ArcArchiveImporter.swift \
  app/ArktCore/Tests/ArcImportTests/ArcArchiveImporterTests.swift \
  app/ArktCore/Tests/ArcImportTests/Fixtures/StorableArchiveItems-synthetic.json
git commit -m "Import Arc archive items"
```

---

### Task D5b: Counts-only archive check in `arkt-import-check`

**Files:**
- Create: `app/ArktCore/Sources/ArcImport/ArchiveCheckSummary.swift`
- Create: `app/ArktCore/Tests/ArcImportTests/ArchiveCheckSummaryTests.swift`
- Modify: `app/ArktCore/Sources/arkt-import-check/main.swift`
- Modify: `docs/plans/2026-10-22-week1-results.md`

**Step 1: Write the failing tests** (`ArchiveCheckSummaryTests.swift`)

```swift
import Foundation
import Testing
import ArcImport

struct ArchiveCheckSummaryTests {
  @Test func summarizesTheSyntheticFixtureAsCountsOnly() throws {
    let result = try ArcArchiveImporterTests.importFixture()
    let lines = ArchiveCheckSummary.lines(report: result.report)
    #expect(lines == [
      "archive entries: 10",
      "archive imported: 7 (manual 5, auto 2)",
      "archive sources: space 4, little arc 1, unknown 2",
      "archive skipped: 3",
      "  decodeFailed: 1",
      "  invalidURL: 1",
      "  unsupportedKind: 1",
      "archive warnings: 2",
      "  archiveSpaceNotImported: 1",
      "  unsupportedValue: 1",
    ])
    ImportCheckSummaryTests.expectAllowlisted(lines)
    let text = lines.joined(separator: "\n")
    for item in result.items {
      if !item.title.isEmpty { #expect(!text.contains(item.title)) }
      if let url = item.url { #expect(!text.contains(url.absoluteString)) }
      #expect(!text.contains(item.id.uuidString))
    }
  }

  @Test func groupsByCaseNameWithoutPayloads() {
    var report = ArchiveImportReport(entries: 2)
    report.skipped = [SkippedItem(itemID: "secret-1", reason: .unsupportedKind("secret easel"))]
    report.warnings = [.archiveSpaceNotImported(itemID: "secret-2")]
    let lines = ArchiveCheckSummary.lines(report: report)
    ImportCheckSummaryTests.expectAllowlisted(lines)
    #expect(!lines.joined().contains("secret"))
  }
}
```

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter ArchiveCheckSummaryTests`
Expected: build fails (`ArchiveCheckSummary` unknown).

**Step 3: Implement**

`ArchiveCheckSummary.swift`:

```swift
/// Counts-only text for the archive part of `arkt-import-check`. Never includes titles, URLs, ids or Space names.
/// Values stay lowercase so every line passes the import check's allowlist.
public enum ArchiveCheckSummary {
  public static func lines(report: ArchiveImportReport) -> [String] {
    var out = [
      "archive entries: \(report.entries)",
      "archive imported: \(report.imported) (manual \(report.manual), auto \(report.auto))",
      "archive sources: space \(report.fromSpace), little arc \(report.fromLittleArc), unknown \(report.fromUnknown)",
      "archive skipped: \(report.skipped.count)",
    ]
    out += ImportCheckSummary.grouped(report.skipped.map { ImportCheckSummary.caseName($0.reason) })
    out.append("archive warnings: \(report.warnings.count)")
    out += ImportCheckSummary.grouped(report.warnings.map { ImportCheckSummary.caseName($0) })
    return out
  }
}
```

`main.swift`: after the sidebar `for line in ImportCheckSummary.lines(...)` loop, inside the same `do`, add:

```swift
  // Archive: optional, read-only, counts only. Reads one file next to the sidebar file; writes nothing.
  let archiveURL = sidebarURL.deletingLastPathComponent().appendingPathComponent("StorableArchiveItems.json")
  if FileManager.default.isReadableFile(atPath: archiveURL.path) {
    do {
      let archive = try ArcArchiveFile.decode(Data(contentsOf: archiveURL))
      try ArcArchiveImporter.checkVersion(archive)
      let imported = ArcArchiveImporter.makeItems(from: archive, spaceIDsByArcID: result.spaceIDsByArcID)
      for line in ArchiveCheckSummary.lines(report: imported.report) { print(line) }
    } catch {
      print("archive error: \(type(of: error)) code \((error as NSError).code)")
    }
  } else {
    print("archive: not found")
  }
```

**Step 4: Run tests**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 186 tests` ... `passed`.

**Step 5: Real-file check (the only allowed contact with real Arc data)**

Run: `cd $WT/app/ArktCore && nice -n 10 swift run -j 2 arkt-import-check`
Expected: the eight sidebar lines as in week1-results B7 (numbers may have moved), then archive lines of the shape
`archive entries: N`, `archive imported: N (manual N, auto N)`, `archive sources: space N, little arc N, unknown N`,
`archive skipped: N`, `archive warnings: N` (expect counts in line with the data-model notes: mostly tabs, few or no
skips). Check before recording: every line is labels and numbers only. If any
line contains anything else, do not record it; fix `ArchiveCheckSummary` first.

Append to `docs/plans/2026-10-22-week1-results.md` a `## Track D: persistence and archive` section with a results
table row `D5b Real-file archive check | PASS | counts only` and a fenced block holding exactly the archive lines
printed above.

**Step 6: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/ArcImport/ArchiveCheckSummary.swift \
  app/ArktCore/Tests/ArcImportTests/ArchiveCheckSummaryTests.swift \
  app/ArktCore/Sources/arkt-import-check/main.swift docs/plans/2026-10-22-week1-results.md
git commit -m "Add counts-only Arc archive check"
```

---

### Task D6: Typed archive settings, persisted

**Files:**
- Create: `app/ArktCore/Sources/Archive/ArchiveSettings.swift`
- Create: `app/ArktCore/Tests/ArchiveTests/ArchiveSettingsTests.swift`
- Modify: `app/ArktCore/Sources/Persistence/ArktDatabase.swift` (migration `v3-settings`)
- Create: `app/ArktCore/Sources/Persistence/SettingsStore.swift`
- Create: `app/ArktCore/Tests/PersistenceTests/SettingsStoreTests.swift`
- Modify: `app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift` (expected migration list)

**Step 1: Write the failing tests**

`ArchiveSettingsTests.swift`:

```swift
import Archive
import Foundation
import Testing
import SidebarModel

struct ArchiveSettingsTests {
  /// BH-080, BH-137: Arc's fresh-install defaults.
  @Test func defaultsMatchArc() {
    let settings = ArchiveSettings()
    #expect(settings.tabThreshold(forProfile: "default") == .twelveHours)
    #expect(settings.tabThreshold(forProfile: "anything") == .twelveHours)
    #expect(settings.littleArcThreshold == .sixHours)
  }

  /// BH-081: seven options in picker order.
  @Test func optionsAreArcsSevenInOrder() {
    #expect(AutoArchiveThreshold.allCases == [
      .oneHour, .sixHours, .twelveHours, .twentyFourHours, .sevenDays, .thirtyDays, .never,
    ])
    #expect(AutoArchiveThreshold.allCases.compactMap(\.interval) == [
      3600, 21_600, 43_200, 86_400, 604_800, 2_592_000,
    ])
  }

  /// BH-083: a profile without its own value follows the Default profile.
  @Test func newProfilesInheritTheDefaultProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: "default", scope: .thisProfile)
    #expect(settings.tabThreshold(forProfile: "brand-new") == .sevenDays)
  }

  /// BH-083, BH-179: "only this Profile".
  @Test func thisProfileScopeChangesOnlyThatProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    #expect(settings.tabThreshold(forProfile: "work") == .oneHour)
    #expect(settings.tabThreshold(forProfile: "default") == .twelveHours)
  }

  /// BH-083: "apply to all Profiles".
  @Test func allProfilesScopeChangesEveryKnownProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    settings.setTabThreshold(.thirtyDays, forProfile: "home", scope: .allProfiles, knownProfiles: ["work", "home"])
    for profile in ["work", "home", "default", "later"] {
      #expect(settings.tabThreshold(forProfile: profile) == .thirtyDays)
    }
  }

  @Test func lossyDecodingKeepsGoodValuesAndDefaultsBadOnes() throws {
    let json = Data("""
      {"tabThresholdsByProfile": {"default": "sevenDays", "work": "fortnight"}, "littleArcThreshold": 42}
      """.utf8)
    let settings = try JSONDecoder().decode(ArchiveSettings.self, from: json)
    #expect(settings.tabThreshold(forProfile: "default") == .sevenDays)
    #expect(settings.tabThreshold(forProfile: "work") == .sevenDays)  // bad entry dropped, inherits default
    #expect(settings.littleArcThreshold == .sixHours)
    #expect(try JSONDecoder().decode(ArchiveSettings.self, from: Data("{}".utf8)) == ArchiveSettings())
  }

  @Test func settingsRoundTrip() throws {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.never, forProfile: "work", scope: .thisProfile)
    settings.littleArcThreshold = .oneHour
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(ArchiveSettings.self, from: data) == settings)
  }

  /// BH-179 end to end: the policy uses the settings lookup per Space profile.
  @Test func policyHonorsPerProfileSettings() throws {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    var sidebar = Sidebar()
    let home = sidebar.addSpace(title: "Home")
    let work = sidebar.addSpace(title: "Work", profile: "work")
    try sidebar.addTab(url: URL(string: "https://example.com/h")!, title: "H",
                       lastActiveAt: now.addingTimeInterval(-7200), in: .today(home))
    let workTab = try sidebar.addTab(url: URL(string: "https://example.com/w")!, title: "W",
                                     lastActiveAt: now.addingTimeInterval(-7200), in: .today(work))
    let lookup = settings  // a let: @Sendable closures cannot capture a var
    let input = AutoArchiveInput(now: now, startedAt: .distantPast) { lookup.tabThreshold(forProfile: $0) }
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [workTab])
  }
}
```

`SettingsStoreTests.swift`:

```swift
import Archive
import Foundation
import GRDB
import Testing
@testable import Persistence

struct SettingsStoreTests {
  static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test func missingGroupLoadsItsDefault() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    #expect(try await store.load(ArchiveSettings.self) == ArchiveSettings())
    #expect(try await store.load(ArchiveState.self) == ArchiveState())
  }

  @Test func saveThenLoad() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: "default", scope: .thisProfile)
    try await store.save(settings, at: Self.date)
    #expect(try await store.load(ArchiveSettings.self) == settings)
  }

  @Test func unreadableValueLoadsTheDefault() async throws {
    let database = try ArktDatabase.inMemory()
    try await database.writer.write { db in
      try db.execute(
        sql: "INSERT INTO setting (key, value, updated_at) VALUES (?, ?, 0)",
        arguments: [ArchiveSettings.storageKey, Data("not json".utf8)])
    }
    #expect(try await SettingsStore(database: database).load(ArchiveSettings.self) == ArchiveSettings())
  }

  @Test func groupsAreIndependent() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let state = ArchiveState(autoArchiveStartedAt: Self.date, educationBannerDismissed: true)
    try await store.save(state, at: Self.date)
    #expect(try await store.load(ArchiveSettings.self) == ArchiveSettings())
    #expect(try await store.load(ArchiveState.self) == state)
  }

  @Test func settingsSurviveReopen() async throws {
    try await withTemporaryDirectory { directory in
      let url = directory.appendingPathComponent("Arkt.sqlite")
      var settings = ArchiveSettings()
      settings.littleArcThreshold = .twentyFourHours
      do {
        let database = try ArktDatabase.open(at: url)
        try await SettingsStore(database: database).save(settings, at: Self.date)
        try database.writer.close()
      }
      #expect(try await SettingsStore(database: ArktDatabase.open(at: url)).load(ArchiveSettings.self) == settings)
    }
  }
}
```

In `SidebarStoreTests.reopeningRunsNoMigrationTwice`, expect `["v1-sidebar", "v2-archive", "v3-settings"]`.

**Step 2: Run, expect failure**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2 --filter "ArchiveSettingsTests|SettingsStoreTests"`
Expected: build fails (`ArchiveSettings`, `ArchiveState`, `SettingsStore` unknown).

**Step 3: Implement**

`ArchiveSettings.swift`:

```swift
import Foundation

/// "Archive tabs after" per profile (BH-081, BH-083, BH-179) and "Archive Little Arcs after:" (BH-137).
/// Decoding is lossy per field: an unknown or malformed value falls back to its default, never fails the group.
public struct ArchiveSettings: Hashable, Sendable, Codable {
  public static let defaultProfile = "default"

  public enum Scope: Hashable, Sendable {
    case thisProfile
    case allProfiles
  }

  public private(set) var tabThresholdsByProfile: [String: AutoArchiveThreshold]
  public var littleArcThreshold: AutoArchiveThreshold

  public init(
    tabThresholdsByProfile: [String: AutoArchiveThreshold] = [:],
    littleArcThreshold: AutoArchiveThreshold = .littleArcDefault
  ) {
    self.tabThresholdsByProfile = tabThresholdsByProfile
    self.littleArcThreshold = littleArcThreshold
  }

  /// The profile's own value, else the Default profile's (new profiles inherit it, BH-083), else 12 hours (BH-080).
  public func tabThreshold(forProfile profile: String) -> AutoArchiveThreshold {
    tabThresholdsByProfile[profile] ?? tabThresholdsByProfile[Self.defaultProfile] ?? .tabsDefault
  }

  /// BH-083: Arc asks "apply to all Profiles or only this Profile". `.allProfiles` sets `profile`, every
  /// `knownProfiles` entry and the Default profile, so profiles created later inherit it too.
  public mutating func setTabThreshold(
    _ threshold: AutoArchiveThreshold, forProfile profile: String, scope: Scope, knownProfiles: [String] = []
  ) {
    switch scope {
    case .thisProfile:
      tabThresholdsByProfile[profile] = threshold
    case .allProfiles:
      for name in Set(knownProfiles + [profile, Self.defaultProfile]) { tabThresholdsByProfile[name] = threshold }
    }
  }

  private enum CodingKeys: String, CodingKey { case tabThresholdsByProfile, littleArcThreshold }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = (try? container.decodeIfPresent([String: String].self, forKey: .tabThresholdsByProfile)) ?? [:]
    tabThresholdsByProfile = raw.compactMapValues(AutoArchiveThreshold.init(rawValue:))
    littleArcThreshold = (try? container.decodeIfPresent(String.self, forKey: .littleArcThreshold))
      .flatMap(AutoArchiveThreshold.init(rawValue:)) ?? .littleArcDefault
  }
}

/// Archive bookkeeping, not user-facing settings.
public struct ArchiveState: Hashable, Sendable, Codable {
  /// When auto-archive first ran on this install (Arc: `autoArchiveStartTime` in Arc's archive JSON). Set once on first
  /// launch (and after an Arc import); feeds `AutoArchiveInput.startedAt`.
  public var autoArchiveStartedAt: Date?
  /// BH-089: the education banner is shown once and not again after dismissal.
  public var educationBannerDismissed: Bool

  public init(autoArchiveStartedAt: Date? = nil, educationBannerDismissed: Bool = false) {
    self.autoArchiveStartedAt = autoArchiveStartedAt
    self.educationBannerDismissed = educationBannerDismissed
  }
}
```

`ArktDatabase.swift`, register after `v2-archive`:

```swift
migrator.registerMigration("v3-settings") { db in
  try db.execute(sql: """
    CREATE TABLE setting (
      key TEXT PRIMARY KEY NOT NULL,
      value BLOB NOT NULL,
      updated_at REAL NOT NULL
    )
    """)
}
```

`SettingsStore.swift`:

```swift
import Archive
import Foundation
import GRDB

/// A typed group of settings stored as one JSON value under `storageKey`.
public protocol SettingsGroup: Codable, Sendable {
  static var storageKey: String { get }
  static var defaultValue: Self { get }
}

extension ArchiveSettings: SettingsGroup {
  public static let storageKey = "archive.settings"
  public static var defaultValue: ArchiveSettings { ArchiveSettings() }
}

extension ArchiveState: SettingsGroup {
  public static let storageKey = "archive.state"
  public static var defaultValue: ArchiveState { ArchiveState() }
}

/// Profile-scoped settings in SQLite (`setting` table). App-level preferences stay in user defaults (design 4).
public struct SettingsStore: Sendable {
  let database: ArktDatabase

  public init(database: ArktDatabase) { self.database = database }

  /// The stored group, or its default when missing or unreadable.
  @concurrent
  public func load<Group: SettingsGroup>(_ type: Group.Type) async throws -> Group {
    let key = Group.storageKey
    let data = try await database.writer.read { db in
      try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
    }
    guard let data else { return Group.defaultValue }
    return (try? JSONDecoder().decode(Group.self, from: data)) ?? Group.defaultValue
  }

  @concurrent
  public func save<Group: SettingsGroup>(_ value: Group, at date: Date) async throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let key = Group.storageKey
    let updatedAt = date.timeIntervalSinceReferenceDate
    try await database.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO setting (key, value, updated_at) VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
          """,
        arguments: [key, data, updatedAt])
    }
  }
}
```

**Step 4: Run**

Run: `cd $WT/app/ArktCore && nice -n 10 swift test -j 2`
Expected: `Test run with 199 tests` ... `passed`.

**Step 5: Commit**
```zsh
cd $WT && git add app/ArktCore/Sources/Archive/ArchiveSettings.swift \
  app/ArktCore/Tests/ArchiveTests/ArchiveSettingsTests.swift \
  app/ArktCore/Sources/Persistence/ArktDatabase.swift app/ArktCore/Sources/Persistence/SettingsStore.swift \
  app/ArktCore/Tests/PersistenceTests/SettingsStoreTests.swift \
  app/ArktCore/Tests/PersistenceTests/SidebarStoreTests.swift
git commit -m "Add typed archive settings with Arc defaults"
```

---

## Integration notes (for the app-shell track; not tasks here)

- Launch: `let state = try await ArktLaunch.openAndLoad(.applicationSupport(), now: .now)` before the first sidebar
  render (the main actor suspends, it does not block). On `.restoredFromBackup` or `.recreatedEmpty`, tell the user
  (toast plus log; never silent). Then `makeBackup` once, and every 30 minutes while the sidebar changed.
- Every reducer change to the sidebar calls `autosaver.scheduleSave(newSidebar)`.
- Termination: in `applicationShouldTerminate`, if `autosaver.hasPendingChanges`, return `.terminateLater` and run
  `Task { @MainActor in await autosaver.flush(); NSApp.reply(toApplicationShouldTerminate: true) }`.
- On first launch (and after an Arc import), set `ArchiveState.autoArchiveStartedAt` if nil.
- Auto-archive tick (every minute): `AutoArchivePolicy.itemsToArchive`, then `Archiver.archive(reason: .auto)` for
  each, `ArchiveStore.add`, `scheduleSave`, toast "Auto archived N tabs" (BH-085). The in-memory sidebar changes
  first; if `ArchiveStore.add` fails, keep the items in memory and retry (an archived item must not vanish).
- Restore: `Archiver.restore` into the in-memory sidebar, `scheduleSave`, then `ArchiveStore.remove`. A failed remove
  leaves a duplicate in the archive (harmless, retried), never a lost item.
- Arc import: run `ArcArchiveImporter` with `ArcImportResult.spaceIDsByArcID`, then `ArchiveStore.add` (idempotent).

## Open questions

1. Debounce delay: 500 ms chosen. Longer windows mean fewer writes but more loss on a crash (flush covers clean quits).
2. Backup cadence (#100, decided): launch + pre-migration + every 30 min while changed (`AppSession.backupInterval`),
   keeping the newest 5 (`DatabaseLocation.backupsKept = 5`); no time-spread buckets. `setting` rows do not count as
   backup content (`Backups.hasContent`), and an unreadable `setting` group falls back to `defaultValue` on `load` and
   is overwritten on the next `save`.
3. Restore position: tabs to the top of Today and folders to the end of Pinned are inferences; needs a runtime check
   in Arc (add to parity spec section 6).
4. Splits in Today: archived as one unit when the most recent pane is idle [I]. BH-122/123 remain runtime checks.
5. Tabs with `lastActiveAt == nil` use `createdAt`. Arc's exact rule is unknown.
6. `startedAt` clamp: Arc's `autoArchiveStartTime` semantics are inferred (data-model 2.1). Should an Arc import reset
   it to the import time (proposed) or carry Arc's value over?
7. New-profile inheritance (BH-083) is implemented as lookup-time fallback to the Default profile. Arc may copy the
   value at profile creation instead; the difference shows only when Default changes later.
8. Arc's per-profile thresholds (`autoArchiveTimeThresholdsPerProfile` entry shape is unknown, data-model unknown 3)
   are not imported; Arc's thresholds could be read later through a counts-only probe.
9. Archive retention (#100, decided 2026-10-23): archive entries older than 30 days (`ArchiveStore.retentionInterval`)
   are pruned automatically (like Arc) via `ArchiveStore.pruneExpired(now:)`, in addition to restore
   (`ArchiveStore.remove`) and Clear Archive (`ArchiveStore.removeAll`, BH-087).
10. App Support directory name `Arkt` assumes the final bundle id; adjust `DatabaseLocation.applicationSupport()` if
    the product name or sandboxing changes.
11. Window/session state (data-model section 3) is out of Track D scope; it will need its own table (`v4-...`).
