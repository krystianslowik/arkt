# Track E: Core Integration Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** Replace `StubSidebar` in the running app with Arkt's real data layer: the app launches from the GRDB
database (`ArktLaunch.openAndLoad`), renders the real `SidebarModel.Sidebar` through a `SidebarSource` adapter,
autosaves every change and flushes on quit, offers a first-run empty state with "Import from Arc" and "New Space",
imports Arc's sidebar, archive and favicons read-only, archives Today tabs on Cmd-W and by the idle policy, and
restores them from a minimal Archive window. A scripted smoke run proves: empty DB, import, quit, relaunch, same state.

**Architecture:** Three layers, with GRDB reachable from exactly one of them. (1) `app/ArktCore` (unchanged layout)
gains four small seams: `Sidebar.updateTab`, store protocols `ArchiveStoring` / `ArchiveStateStoring` in the pure
`Archive` target (the query value types move there from `Persistence`), `SettingsStore.resetAutoArchiveStart(to:)`,
and deterministic Space ids in `ArcSidebarImporter`. (2) `app/ArktShell/ShellKit` depends on `../../ArktCore` by
relative path and adds ONE new target, `CoreBridge` (depends on `ShellUI`, `SidebarModel`, `Archive`, `ArcImport`;
never `Persistence`): `ModelSidebarSource` (the `SidebarSource` adapter with a diff-based change emitter),
`ArchiveCoordinator`, `ArcImportCoordinator`, `FaviconStore`, `ArchiveListModel`, `RecoveryNotice`, toast texts.
`ShellUI` never imports any ArktCore module (it keeps its own `SpaceID` / `NodeID` / `RGBA`, which collide by name
with `SidebarModel`'s) and gains only UI: toasts, the empty state, the Archive window, Cmd-W, a `.spaces` change.
(3) The XcodeGen app target is the composition root and the only place that links `Persistence` (and therefore
GRDB): `AppSession` owns the database, `SidebarAutosaver`, `ArchiveStore`, `SettingsStore`, timers and the
termination flush, and hands `CoreBridge` objects their protocol-typed stores. `StubSidebar` stays for tests.

**Tech Stack:** Swift 6.4 toolchain (Swift 6 language mode, complete concurrency checking), macOS 15 deployment
target, Xcode 27.1 + XcodeGen, SwiftPM, AppKit (window, sidebar, toasts, Archive table), Core Animation,
GRDB.swift 7.11.1 (exact pin, linked only by the app target through `Persistence`), Swift Testing for pure tests,
XCTest (`ShellKitGUITests`) for window/run-loop tests. No new third-party dependencies.

---

## Rules (read before every task)

| Name | Path |
|---|---|
| `$REPO` | `/path/to/arkt-wt/track-e` (git worktree, branch `track-e`) |
| `$APP` | `$REPO/app/ArktShell` |
| `$KIT` | `$APP/ShellKit` |
| `$CORE` | `$REPO/app/ArktCore` |
| `$DD` | `$APP/build` (xcodebuild `-derivedDataPath`, gitignored) |

- **Start condition.** Track E edits `SidebarSource`, `SidebarController` and `ShellWindowController`, which C6
  (Space paging, worktree `arkt-wt/track-c`, in review) rewrites (`syncPages`, `pager`, `tabToRestore`,
  `onSpacesChanged`, `refreshThemes`, `SpaceThemeInfo.noiseFactor`). Create the Track E worktree only AFTER C6 is
  merged into `spike/week1`. Every snippet below is written against the post-C6 code. If C6 renamed something, follow
  C6's names; do not reintroduce the pre-C6 versions.
- Shell is zsh. Set once per shell:
  `REPO=/path/to/arkt-wt/track-e; APP=$REPO/app/ArktShell; KIT=$APP/ShellKit; CORE=$REPO/app/ArktCore; DD=$APP/build`
- **Capacity rule.** A Chromium build may be saturating the CPU. Every build or test runs with `nice -n 20` and two
  jobs: `nice -n 20 swift test -j 2`, `nice -n 20 swift build -j 2`, `nice -n 20 xcodebuild ... -jobs 2`. At most
  two Swift builds may run at the same time across all tracks; never run two builds inside this track at once.
- Swift 6 language mode, macOS 15 (`platforms: [.macOS(.v15)]`, `MACOSX_DEPLOYMENT_TARGET = 15.0`). No
  `@unchecked Sendable` and no `nonisolated(unsafe)` in production code; fix concurrency diagnostics at the root.
- AppKit + Core Animation for hot paths (sidebar, toasts over the card, Archive table). No SwiftUI lists. Frames on
  hot-path views are set directly, not with Auto Layout.
- The main thread never waits on disk: every database, file and Arc read runs in `@concurrent` functions or GRDB's
  queue; main-actor code only `await`s.
- **Layering is enforced, not asserted.** Only the app target (`$APP/App/*.swift`) may `import Persistence`;
  nothing in `$KIT/Sources` may `import Persistence` or `import GRDB`; nothing in `$KIT/Sources/ShellUI` may import
  `SidebarModel`, `Archive`, `ArcImport`, `Persistence` or `GRDB`. The Swift test added in E1
  (`IsolationTests/CoreIsolationTests`) is the gate; the WebKit isolation grep from the Track C plan (Rules section)
  still runs at the end of every task and must print nothing.
- **Arc data.** Never write anything into `~/Library/Application Support/Arc` (or any Arc directory). Arc files are
  opened read-only (`Data(contentsOf:)`) and only after the user clicks "Import from Arc". Tests and the smoke run use
  only the synthetic fixtures in `$CORE/Tests/ArcImportTests/Fixtures/` (copied into a temp directory). Never open,
  cat, copy or grep the user's real Arc data. Logs and smoke output print counts and enum case names only, never
  titles, URLs or paths of user data.
- No emojis anywhere (code, comments, fixtures, commit messages).
- TDD: write the test, run it and watch it fail (a compile error counts), implement, run again, commit.
- **Commits.** One per task (sub-tasks may commit separately as listed), staged with explicit pathspecs
  (`git add <paths>`; never `git add -A` or `git add .`), Plain commit messages.
- Test commands used below:
  - Core: `cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -5`
  - ShellKit pure tests: `cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -5`
  - ShellKit GUI tests (logged-in GUI session only): `cd $KIT && nice -n 20 swift test -j 2 --filter ShellKitGUITests 2>&1 | tail -5`
  - App: `cd $APP && xcodegen generate && nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Debug -derivedDataPath $DD -jobs 2 build 2>&1 | tail -3`
- Expected test counts are written as "baseline + N" against the numbers recorded in E0 (Swift Testing counts
  `@Test` functions; a parameterized test counts once).

## Parity IDs this track implements (from `docs/spec/arc-parity-spec.md`)

| ID | Behavior in Track E | Task |
|---|---|---|
| KB-008, BH-071 | Cmd-W on the active Today tab archives it (reason manual), restorable | E5b |
| BH-067 | Cmd-W on the active pinned tab closes its page but keeps it in the sidebar; not archived | E5b |
| BH-048 | Favorites never auto-archive; Cmd-W on a Favorite closes the page and keeps it [I, same as BH-067] | E5b, E5d |
| BH-073 | Archiving the last Today tab of a Space leaves the window open on that Space (NEEDS-RUNTIME-CHECK) | E5b |
| BH-080, BH-084, BH-054 | Idle Today tabs auto-archive after the profile threshold; pinned, Favorites, foldered never | E5d |
| BH-076 | Media-playing tabs are exempt (hook only: FakeEngine reports no media; see E5d) | E5d |
| BH-083, BH-179 | Threshold per profile via `ArchiveSettings.tabThreshold(forProfile:)` | E5d |
| BH-085 | Toast "Auto archived N tabs" | E5d |
| BH-086, BH-090 | Restore to the original Space (tabs top of Today, folders end of Pinned) with the restore toast | E5c |
| BH-087 (part) | Archive list shows readable items newest first; unreadable rows counted, not shown | E5c |
| KB-043 | "Show Archive" exists as a menu command, unbound by default | E5c |

Not in this track (cited so nobody adds them by accident): BH-069 (second Cmd-W on a closed pinned tab unpins it,
NEEDS-RUNTIME-CHECK), BH-072 (multi-select Cmd-W), BH-074 / KB-010 (Cmd-Shift-T reopen), BH-075 / BH-077 / BH-078
(Clear, Archive Below), BH-088 filters UI, BH-089 education banner, BH-122 / BH-123 (split pane removal), BH-157 (Air
Traffic Control routing of restores), BH-211 (onboarding).

## Decisions fixed for this track

1. **Composition root owns GRDB.** `project.yml` links `ArktCore`'s `Persistence` product into the app only. CoreBridge
   talks to stores through protocols that live in the pure `Archive` target (`ArchiveStoring`,
   `ArchiveStateStoring`); `ArchiveStore` and `SettingsStore` conform in `Persistence`. Sidebar saving uses
   `SidebarAutosaver` directly in the app; `ModelSidebarSource.onDidChange` is the only hook.
2. **One mutation path, diff-emitted changes.** `ModelSidebarSource.mutate(_:)` copies the value, runs the closure,
   and on success diffs old vs new: `.spaces` when the Space list or any Space changed; `.structure(location)` for
   every child list that changed (sections first, then containers by depth; containers whose node was removed are
   skipped because their parent's change already removed the rows); `.node(id)` only when the drawn presentation
   (`SidebarNodeInfo`) changed, so `lastActiveAt` stamps redraw nothing. Every emission is impossible to forget,
   and the O(nodes) diff is negligible at sidebar sizes (hundreds of nodes) and runs only on mutations.
3. **Never seed before the user acts.** After `.created` or `.recreatedEmpty` (and whenever the window's profile has
   no Space) the content card shows an empty state with "Import from Arc" (only when Arc's `StorableSidebar.json`
   exists; existence check only, no read) and "New Space". Those two buttons, and Cmd-T with no Space (it creates a
   Space first, then the tab [I]), are the only things that create a Space. `ArktLaunch`'s note explains why: a seeded
   sidebar would start rolling backups that can prune older backups holding real data.
4. **Recovery is never silent.** `.restoredFromBackup` and `.recreatedEmpty` show a persistent (not auto-dismissed)
   notice with a "Show Files" action that reveals Arkt's data folder, plus an `os` log line with the outcome case only.
   A thrown `openAndLoad` (I/O, permissions, `ArktDatabaseError.newerSchema`) shows a modal alert with Quit (and Try
   Again for non-schema errors); the app never creates or autosaves a database in that state.
5. **Backups.** `makeBackup` once after a successful load, then every 30 minutes while the sidebar changed (Track D
   open question 2, proposed cadence adopted). `makeBackup` returns nil while the database is empty, so a first run
   writes none.
6. **Arc import rules.** (a) The sidebar part is merged, not replaced (user decisions 2 and 5, 2026-10-23): a run
   adds only Arc Spaces and top-level Favorites never imported before. `ArcImportRecord` (`SettingsStore`, key
   `arcImport.record`) holds the Arc Space ids and Arc Favorite item ids every earlier run handled; anything in it is
   skipped whatever the sidebar holds now, so items deleted in Arkt are not restored and a Favorite whose URL drifted
   in Arc is not added again. A Space whose stable id is already in Arkt is skipped too (left untouched), and a
   Favorite tab whose URL is already a Favorite is skipped (no duplicates across profiles). With an empty record (a
   database filled by an import that ran before the record existed) the id and URL matches are all there is for that
   run, which then records what it saw. `ArcSidebarImporter` mints fresh node ids, which never collide with existing
   nodes. (b) The archive part always runs and is idempotent: `ArchiveStore.add(_, onConflict: .keepExisting)` with
   Arc's stable item ids; an unreadable archive file is reported (`archiveFailed`) and never costs the sidebar part.
   (c) Space ids become deterministic (Arc's space UUID, or a SHA-256-derived UUID for a non-UUID key, the same rule
   `ArcArchiveImporter` uses), so a re-import maps Spaces and archive entry sources to the same Arkt Spaces. (d) The
   result UI shows counts only.
7. **Open question 6 (Track D), decided: an Arc sidebar import resets `ArchiveState.autoArchiveStartedAt` to the
   import time.** Imported Today tabs carry Arc's old `lastActiveAt` values; without the reset the first tick after
   import would archive almost all of them at once. With it, every imported Today tab gets one full threshold (12 h by
   default) from the import. The reset happens whenever a run adds at least one Space (first import or a re-import
   that adds a missing Space); a run that adds no Space does not reset it. Arc's own `autoArchiveStartTime` is not
   carried over. Confirmed by the user (User decisions 1).
8. **Favicons.** Imported favicons (Arc's `SidebarItemsFaviconCache`, read through `ArcFaviconCache`) and engine
   favicons are written to `<Arkt data dir>/Favicons/<node UUID>.png` by `FaviconStore` (atomic writes, off-main) and
   loaded once after launch. They are not in SQLite and not in backups (re-fetched by the engine later). The sidebar
   keeps a node's favicon while the node exists (today `SidebarController.deactivate(node:)` drops it when the engine
   tab closes; E4b fixes that).
9. **Cmd-W on a split pane** archives the whole split as one unit [I]: `Archiver.archive` requires the split root and
   BH-123 (pane archive) is NEEDS-RUNTIME-CHECK. Pane removal is a later track.
10. **lastActiveAt contract (D4b).** The idle policy exempts visible tabs, so a tab's idle clock must start when it
    stops being visible: the outgoing tab gets `lastActiveAt = now` when another tab becomes current, when its window
    closes, and for every visible tab in `applicationShouldTerminate` before the flush (otherwise the last visible tab
    relaunches with a stale value and archives on the first tick).
11. **Archive writes are an outbox.** The in-memory sidebar changes first (the tab leaves the sidebar immediately),
    the `ArchivedItem` goes to an outbox that writes with `.replace` right away (not debounced) and retries with backoff
    1, 2, 5, 15, 30 s on failure, keeping items in memory (an archived item must not vanish). Restore removes from the
    store after the model insert; a failed remove leaves a harmless duplicate. Termination flushes the outbox and the
    autosaver together, bounded by 1 s each. Residual risk, documented: a crash after the sidebar save landed but before
    the outbox write succeeded loses that archived entry; the outbox write is issued ~500 ms before the debounced
    sidebar save, so this needs a failing archive write plus a crash.
12. **Profiles.** `SidebarController` shows one profile (`"default"`). Spaces and Favorites imported from non-default
    Arc profiles are merged into the default profile and shown immediately (User decisions 3); they lose separate
    cookies and logins. The import summary counts the Spaces that came from other profiles.

## File map (end state)

```
app/ArktCore/
  Sources/SidebarModel/SidebarModel.swift            (E2a: updateTab)
  Sources/Archive/ArchiveQuery.swift                 (E4a: moved ArchiveFilter, ArchiveConflictPolicy, ArchivePage)
  Sources/Archive/ArchiveStoring.swift               (E4a: ArchiveStoring, ArchiveStateStoring)
  Sources/Persistence/ArchiveStore.swift             (E4a: types moved out, conformance added)
  Sources/Persistence/SettingsStore.swift            (E4a: resetAutoArchiveStart(to:), conformance; E4c: import record)
  Sources/ArcImport/ArcSidebarImporter.swift         (E4a: deterministic Space ids)
  Sources/ArcImport/StableID.swift                   (E4a: shared stable-id helper, used by both importers)
  Sources/ArcImport/ArcImportRecord.swift            (E4c: Arc ids earlier imports handled, store protocol)
  Tests/SidebarModelTests/SidebarTests.swift         (E2a)
  Tests/PersistenceTests/SettingsStoreTests.swift    (E4a)
  Tests/PersistenceTests/ArchiveStoreTests.swift     (E4a: import Archive where the moved types are used)
  Tests/ArcImportTests/ArcSidebarImporterTests.swift (E4a)
app/ArktShell/
  project.yml                                        (E1: ArktCore package, Persistence/ArcImport/CoreBridge products)
  App/AppDelegate.swift                              (E3c: async launch, termination)
  App/AppSession.swift                               (E3c, E4c, E5: composition root, timers, flush)
  App/AppEnvironment.swift                           (E3c, E6: data/Arc directories, DEBUG smoke hooks)
  App/MainMenu.swift                                 (E4c, E5b, E5c: Import from Arc, Archive Tab, Show Archive)
  ShellKit/Package.swift                             (E1)
  ShellKit/Package.resolved                          (E1: new, GRDB pinned transitively)
  ShellKit/Sources/CoreBridge/BridgeMapping.swift    (E2c)
  ShellKit/Sources/CoreBridge/SidebarDiff.swift      (E2c)
  ShellKit/Sources/CoreBridge/ModelSidebarSource.swift (E2c, E5a)
  ShellKit/Sources/CoreBridge/RecoveryNotice.swift   (E3c)
  ShellKit/Sources/CoreBridge/FaviconStore.swift     (E4b)
  ShellKit/Sources/CoreBridge/ArcImportCoordinator.swift (E4c)
  ShellKit/Sources/CoreBridge/ArcImportMerge.swift   (E4c: merge against the import record)
  ShellKit/Sources/CoreBridge/FaviconWriter.swift    (E4c: favicon writes queued behind the launch prune)
  ShellKit/Sources/CoreBridge/ArchiveCoordinator.swift (E5a, E5d)
  ShellKit/Sources/CoreBridge/ArchiveListModel.swift (E5c)
  ShellKit/Sources/CoreBridge/ToastText.swift        (E5a)
  ShellKit/Sources/ShellUI/Sidebar/SidebarSource.swift (E2b: throwing addTab, addSpace, .spaces, section(containing:))
  ShellKit/Sources/ShellUI/Sidebar/StubSidebar.swift (E2b)
  ShellKit/Sources/ShellUI/Sidebar/SidebarController.swift (E2b: .spaces; E4b: favicon retention)
  ShellKit/Sources/ShellUI/Sidebar/SidebarOutlineController.swift (E2b: prune caches of removed nodes)
  ShellKit/Sources/ShellUI/Toast/ToastPresenter.swift, Toast/ToastView.swift (E3a)
  ShellKit/Sources/ShellUI/Window/EmptyStateView.swift (E3b)
  ShellKit/Sources/ShellUI/Window/ShellWindowController.swift (E2b, E3b, E5b: empty state, toasts, Cmd-W, hooks)
  ShellKit/Sources/ShellUI/Archive/ArchiveWindowController.swift (E5c)
  ShellKit/Tests/IsolationTests/CoreIsolationTests.swift (E1)
  ShellKit/Tests/CoreBridgeTests/*.swift             (E2c onward)
  ShellKit/Tests/ShellUITests/ToastPresenterTests.swift (E3a)
  ShellKit/Tests/ShellKitGUITests/EmptyStateTests.swift, ArchiveWindowTests.swift, CloseTabTests.swift (E3b, E5)
docs/plans/2026-10-23-track-e-results.md             (E6)
```

Execution order: E0, E1, E2a, E2b, E2c, E3a, E3b, E3c, E4a, E4b, E4c, E5a, E5b, E5c, E5d, E6. E4a touches only
`$CORE` and may run in parallel with E3a/E3b if a second Swift build slot is free (capacity rule).

---

### Task E0: Worktree and baselines

**Step 1: Confirm C6 is merged and create the worktree**

```zsh
cd /path/to/arkt && git log --oneline -5 spike/week1
git log spike/week1 --oneline | grep -i "space paging"     # must print the C6 merge
git worktree add ../arkt-wt/track-e -b track-e spike/week1
```
Expected: the grep prints the C6 commit; the worktree exists. If C6 is not merged yet, stop and report.

**Step 2: Record baselines**

```zsh
cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -3
cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -3
```
Write both counts into the E6 results file later (keep them in the task log until then). No commit.

---

### Task E1: Package wiring (ShellKit depends on ArktCore; GRDB only in the app)

**Files:**
- Modify: `$KIT/Package.swift`
- Create: `$KIT/Package.resolved` (generated), `$KIT/Sources/CoreBridge/CoreBridge.swift` (placeholder, deleted in E2c)
- Create: `$KIT/Tests/IsolationTests/CoreIsolationTests.swift`
- Modify: `$APP/project.yml`

**Step 1: Write the failing isolation test** (`CoreIsolationTests.swift`; the target has no dependencies and reads
source files, like `WebKitIsolationTests`)

```swift
import Foundation
import Testing

struct CoreIsolationTests {
  static let kit = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  static let importPattern = /^\s*(@[A-Za-z_]+\s+)*((public|package|internal|fileprivate|private)\s+)?import\s+(\w+\s+)?(\w+)/

  static func imports(under relative: String) throws -> [(file: String, module: String)] {
    let root = kit.appendingPathComponent(relative)
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    return try files.flatMap { file in
      try String(contentsOf: file, encoding: .utf8).split(separator: "\n").compactMap { line in
        (try? Self.importPattern.firstMatch(in: String(line))).flatMap { $0 }.map { (file.lastPathComponent, String($0.output.5)) }
      }
    }
  }

  @Test func noShellKitSourceImportsPersistenceOrGRDB() throws {
    let offenders = try Self.imports(under: "Sources").filter { ["Persistence", "GRDB"].contains($0.module) }
    #expect(offenders.isEmpty, "\(offenders)")
  }

  @Test func shellUIImportsNoArktCoreModule() throws {
    let banned: Set = ["SidebarModel", "Archive", "ArcImport", "Persistence", "GRDB"]
    let offenders = try Self.imports(under: "Sources/ShellUI").filter { banned.contains($0.module) }
    #expect(offenders.isEmpty, "\(offenders)")
  }

  /// Guards against a vacuous pass: CoreBridge must import SidebarModel, so the scanner sees real imports.
  @Test func scannerSeesCoreBridgeImports() throws {
    #expect(try Self.imports(under: "Sources/CoreBridge").contains { $0.module == "SidebarModel" })
  }

  @Test func manifestNeverNamesPersistence() throws {
    let manifest = try String(contentsOf: Self.kit.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(!manifest.contains("\"Persistence\""))
  }
}
```

**Step 2: Run it**

Run: `cd $KIT && nice -n 20 swift test -j 2 --filter CoreIsolationTests 2>&1 | tail -5`
Expected: `scannerSeesCoreBridgeImports` fails (no `Sources/CoreBridge` yet; the enumerator is nil, so make it crash-free
by returning `[]` when `root` does not exist if you prefer a clean failure).

**Step 3: Wire the package**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ShellKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EngineAPI", targets: ["EngineAPI"]),
    .library(name: "FakeEngineKit", targets: ["FakeEngineKit"]),
    .library(name: "Motion", targets: ["Motion"]),
    .library(name: "ShellUI", targets: ["ShellUI"]),
    .library(name: "CoreBridge", targets: ["CoreBridge"]),
  ],
  dependencies: [
    // Local, relative: ShellKit lives in app/ArktShell/ShellKit, ArktCore in app/ArktCore. Only pure products are
    // used here; the app target alone links ArktCore's GRDB-backed product (see project.yml).
    .package(name: "ArktCore", path: "../../ArktCore"),
  ],
  targets: [
    .target(name: "EngineAPI"),
    .target(name: "EngineAPITestSupport", dependencies: ["EngineAPI"]),
    .target(name: "FakeEngineKit", dependencies: ["EngineAPI"]),
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["EngineAPI", "Motion"]),
    .target(
      name: "CoreBridge",
      dependencies: [
        "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
      ]
    ),
    .testTarget(name: "EngineAPITests", dependencies: ["EngineAPI", "EngineAPITestSupport"]),
    .testTarget(name: "MotionTests", dependencies: ["Motion"]),
    .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "EngineAPITestSupport"]),
    .testTarget(name: "IsolationTests"),
    .testTarget(
      name: "CoreBridgeTests",
      dependencies: [
        "CoreBridge", "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
      ]
    ),
    .testTarget(
      name: "ShellKitGUITests",
      dependencies: ["ShellUI", "FakeEngineKit", "EngineAPITestSupport", "Motion"]
    ),
  ]
)
```

Placeholder so the target builds (`Sources/CoreBridge/CoreBridge.swift`; E2c replaces it):

```swift
import SidebarModel

/// Placeholder until E2c adds the adapter.
enum CoreBridgeVersion { static let modelVersion = SidebarModelVersion.current }
```

Also create `Tests/CoreBridgeTests/SmokeTests.swift` with one `@Test` that reads `SidebarModelVersion.current == 1`
(a test target needs at least one source file).

Note: SwiftPM resolves the whole ArktCore graph, so the first resolve fetches GRDB (needs network once) and the first
build compiles it even though no ShellKit target links it. `Package.resolved` appears in `$KIT`; commit it (GRDB stays
on ArktCore's exact 7.11.1 pin).

**Step 4: Link the app**

In `$APP/project.yml`:

```yaml
packages:
  ShellKit:
    path: ShellKit
  ArktCore:
    path: ../ArktCore
...
    dependencies:
      - package: ShellKit
        product: ShellUI
      - package: ShellKit
        product: FakeEngineKit
      - package: ShellKit
        product: EngineAPI
      - package: ShellKit
        product: CoreBridge
      - package: ArktCore
        product: Persistence      # composition root only: the one GRDB link
      - package: ArktCore
        product: SidebarModel
      - package: ArktCore
        product: Archive
      - package: ArktCore
        product: ArcImport
```

**Step 5: Verify**

```zsh
cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -5
cd $APP && xcodegen generate && nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Debug -derivedDataPath $DD -jobs 2 build 2>&1 | tail -3
```
Expected: baseline + 5 tests pass (4 isolation, 1 smoke); `** BUILD SUCCEEDED **`; WebKit isolation grep prints nothing.

**Step 6: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Package.swift app/ArktShell/ShellKit/Package.resolved app/ArktShell/ShellKit/Sources/CoreBridge app/ArktShell/ShellKit/Tests/IsolationTests/CoreIsolationTests.swift app/ArktShell/ShellKit/Tests/CoreBridgeTests app/ArktShell/project.yml && git commit -m "Wire ArktCore into ShellKit and the app; GRDB linked only by the app"
```

---

### Task E2a: `Sidebar.updateTab` (ArktCore)

The model has no way to change a tab's url, title or `lastActiveAt` (`nodes` is `private(set)`), but engine events
and the D4b contract need all three.

**Files:**
- Modify: `$CORE/Sources/SidebarModel/SidebarModel.swift`
- Modify: `$CORE/Tests/SidebarModelTests/SidebarTests.swift`

**Step 1: Failing tests** (append to `SidebarTests`)

```swift
  @Test func updateTabChangesOnlyGivenFields() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let tab = try sidebar.addTab(url: URL(string: "https://a.example")!, title: "A", in: .today(space))
    let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    try sidebar.updateTab(tab, title: "B", lastActiveAt: when)
    guard case .tab(let item)? = sidebar.nodes[tab]?.kind else { Issue.record("not a tab"); return }
    #expect(item.url == URL(string: "https://a.example")!)
    #expect(item.title == "B")
    #expect(item.lastActiveAt == when)
    #expect(sidebar.children(of: .today(space)) == [tab])          // position untouched
  }

  @Test func updateTabRejectsUnknownAndNonTabNodes() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    let before = sidebar
    #expect(throws: SidebarError.unknownNode(folder)) { try sidebar.updateTab(folder, title: "X") }
    let ghost = NodeID()
    #expect(throws: SidebarError.unknownNode(ghost)) { try sidebar.updateTab(ghost, title: "X") }
    #expect(sidebar == before)
  }
```

**Step 2:** Run `cd $CORE && nice -n 20 swift test -j 2 --filter SidebarTests 2>&1 | tail -5`. Expected: compile error
(`updateTab` missing).

**Step 3: Implement** (in `Sidebar`, after `remove`)

```swift
  /// Changes a tab's own fields; nil leaves a field as it is. Throws `.unknownNode` when `id` is not a tab (unknown
  /// ids and folders or splits alike); the sidebar is unchanged on throw. Never moves the node.
  public mutating func updateTab(_ id: NodeID, url: URL? = nil, title: String? = nil, lastActiveAt: Date? = nil) throws {
    guard case .tab(var tab)? = nodes[id]?.kind else { throw SidebarError.unknownNode(id) }
    if let url { tab.url = url }
    if let title { tab.title = title }
    if let lastActiveAt { tab.lastActiveAt = lastActiveAt }
    nodes[id]?.kind = .tab(tab)
  }
```

**Step 4:** Run the core suite. Expected: baseline + 2, all pass.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktCore/Sources/SidebarModel/SidebarModel.swift app/ArktCore/Tests/SidebarModelTests/SidebarTests.swift && git commit -m "Add Sidebar.updateTab for url, title and last-active changes"
```

---

### Task E2b: Shell protocol seams (throwing addTab, addSpace, `.spaces`, cache pruning)

**Files:**
- Modify: `$KIT/Sources/ShellUI/Sidebar/SidebarSource.swift`, `StubSidebar.swift`, `SidebarController.swift`,
  `SidebarOutlineController.swift`
- Modify: `$KIT/Sources/ShellUI/Window/ShellWindowController.swift` (call sites only)
- Modify: `$KIT/Tests/ShellUITests/SidebarModelStubTests.swift`; Create: `$KIT/Tests/ShellKitGUITests/SpaceListChangeTests.swift`

**Step 1: Failing tests**

`SidebarModelStubTests` (pure):

```swift
  @Test func addSpaceEmitsSpaces() {
    let stub = StubSidebar()
    var changes: [SidebarChange] = []
    let observation = stub.observe { changes.append($0) }
    _ = try? stub.addSpace(title: "New")
    #expect(changes == [.spaces])
    _ = observation
  }

  @Test func sectionContainingWalksThroughFolders() {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    let folder = stub.addFolder(title: "F", in: .pinned(space))
    let tab = stub.addTab(url: URL(string: "https://a.example")!, title: "A", in: .folder(folder))
    #expect(stub.section(containing: tab) == .pinned(space))
  }
```

`SpaceListChangeTests` (XCTest, GUI): a `SidebarController` over an EMPTY `StubSidebar` has `currentSpace == nil`;
after `stub.addSpace(title:)` and one tab, `currentSpace` is the new Space and `currentPage` exists (proves `.spaces`
reaches `syncPages`), and `onSpacesChanged` fired once.

**Step 2:** Run both filters; expect compile errors.

**Step 3: Implement**

`SidebarSource.swift`:

```swift
@MainActor
public protocol SidebarSource: AnyObject {
  // ... unchanged requirements ...
  /// Throws when the model refuses the location (unknown Space, too deep). `StubSidebar` never throws.
  @discardableResult func addTab(url: URL, title: String, in location: SidebarLocation) throws -> NodeID
  /// A new Space for this source's default profile, appended to `spaceOrder`. Emits `.spaces`.
  @discardableResult func addSpace(title: String) throws -> SpaceID
  // ...
}

public enum SidebarChange: Hashable, Sendable {
  case structure(SidebarLocation)
  case node(NodeID)
  /// `spaceOrder` or any Space's title, profile or theme changed.
  case spaces
}

extension SidebarSource {
  /// The top-level section (`.favorites`, `.pinned`, `.today`) holding `id`, through folders and splits.
  public func section(containing id: NodeID) -> SidebarLocation? {
    var location = parent(of: id)
    for _ in 0..<64 {
      guard let current = location, let container = current.containerNode else { return location }
      location = parent(of: container)
    }
    return nil
  }
}
```

`StubSidebar`: `addSpace(title:profile:theme:)` now also calls `hub.emit(.spaces)`; add
`public func addSpace(title: String) -> SpaceID { addSpace(title: title, theme: SpaceThemeInfo(baseColors: [], isDark: false)) }`
(non-throwing witnesses satisfy throwing requirements; existing stub-typed call sites stay as they are).

`SidebarController.apply(_:)` (post-C6 code) gains:

```swift
    case .spaces:
      syncPages()                                   // C6: creates/drops pages, refreshes dot titles, calls onSpacesChanged
      let currentIsShown = currentSpace.map { spaces.contains($0) } ?? false
      if !currentIsShown, let first = spaces.first { showSpace(first) }
```
(If C6's `syncPages()` does not refresh dot titles on a rename, set `view.spaceDots.titles` here as well.)

`SidebarOutlineController.applyDiff`: after `endUpdates()`, for every removed root or container item whose node no
longer exists in the source (`source.node(id) == nil`), drop `items[id]` and `containerChildren[id]` for it and its
cached descendants, so a node restored later with the same id is read fresh. (C3 follow-up "removal handling" is
otherwise unchanged: moves stay out of scope.)

`ShellWindowController.open(_:inNewTab:)`: `do { let node = try sidebar.addTab(...); activate(node: node) } catch
{ onError?(error) }` with `public var onError: (@MainActor (any Error) -> Void)?` (E3a wires it to a toast). Also
make `sidebar` a required init parameter (drop the `= StubSidebar.sample()` default) and pass
`StubSidebar.sample()` explicitly in GUI tests; production must never fall back to the stub silently.

**Step 4:** Run ShellKit pure tests and the GUI filter `SpaceListChangeTests`. Expected: baseline + 2 pure, new GUI test
passes, all earlier tests pass (fix any `addTab` call through `any SidebarSource` with `try`).

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/ShellUI/Sidebar app/ArktShell/ShellKit/Sources/ShellUI/Window/ShellWindowController.swift app/ArktShell/ShellKit/Tests/ShellUITests/SidebarModelStubTests.swift app/ArktShell/ShellKit/Tests/ShellKitGUITests && git commit -m "Sidebar source: throwing addTab, addSpace and a Space-list change"
```

---

### Task E2c: `ModelSidebarSource` over `SidebarModel.Sidebar`

**Files:**
- Delete: `$KIT/Sources/CoreBridge/CoreBridge.swift`
- Create: `$KIT/Sources/CoreBridge/BridgeMapping.swift`, `SidebarDiff.swift`, `ModelSidebarSource.swift`
- Create: `$KIT/Tests/CoreBridgeTests/SidebarSourceContractTests.swift`, `SidebarDiffTests.swift`,
  `ModelSidebarSourceTests.swift`

Name collisions: `ShellUI` and `SidebarModel` both declare `SpaceID`, `NodeID` and `RGBA`. In CoreBridge files use
`UUID` for ids and qualify `SidebarModel.RGBA`, `ShellUI.RGBA`, `SidebarModel.Location`, `SidebarModel.Sidebar`.

**Step 1: Failing tests**

`SidebarSourceContractTests`: one parameterized suite over both implementations (the same idea as `EngineContract`):

```swift
import CoreBridge
import Foundation
import ShellUI
import Testing

@MainActor
enum SourceKind: CaseIterable, Sendable { case stub, model
  func make() -> any SidebarSource { self == .stub ? StubSidebar() : ModelSidebarSource() }
}

@MainActor
struct SidebarSourceContractTests {
  @Test(arguments: SourceKind.allCases)
  func addTabAppendsAndEmitsStructure(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let a = try source.addTab(url: URL(string: "https://a.example")!, title: "A", in: .today(space))
    let b = try source.addTab(url: URL(string: "https://b.example")!, title: "B", in: .today(space))
    #expect(source.children(of: .today(space)) == [a, b])
    #expect(source.parent(of: a) == .today(space))
    #expect(changes == [.structure(.today(space)), .structure(.today(space))])
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func updateTabEmitsNodeOnlyWhenDrawnFieldsChange(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: URL(string: "https://a.example")!, title: "A", in: .today(space))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    source.updateTab(a, url: nil, title: "A2")
    #expect(changes == [.node(a)])
    #expect(source.node(a) == .tab(id: a, url: URL(string: "https://a.example")!, title: "A2"))
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func releasedObservationStopsDelivery(kind: SourceKind) throws { /* observe, drop handle, mutate, expect none */ }
}
```

`ModelSidebarSourceTests` (model-only behavior):
- `addTab(in: .today(unknownSpace))` throws `SidebarError.invalidDestination`, emits nothing, `onDidChange` not called.
- Nesting past `Sidebar.maximumNestingDepth` through `mutate` throws `.nestingTooDeep` and leaves `sidebar` unchanged.
- Every successful mutation calls `onDidChange` exactly once with the new value; a no-op mutation (`updateTab` with
  equal fields) calls it zero times.
- `markInactive([tab], at:)` updates `lastActiveAt`, calls `onDidChange`, emits no change (presentation unchanged).
- Favorites per profile: tabs in `.favorites(profile: "work")` are not returned for `.favorites(profile: "default")`.
- A split maps to `.split(id:)`, its panes to `.tab`, `children(of: .split(id))` follows the model.
- `space(_:)` maps title, profile and theme: an Arc `extendedSRGB` color maps to `ShellUI.RGBA(space: .sRGB)` with the
  same components; a nil theme or empty `baseColors` maps to `SpaceThemeInfo.bridgeDefault`.
- Tab title is `customTitle ?? title`.

`SidebarDiffTests` (pure functions over two `Sidebar` values):
- Removing a folder with children emits `.structure(.pinned(space))` and NOT `.structure(.folder(folder))`.
- Adding a tab inside a nested folder emits only `.structure(.folder(inner))`.
- Order: `.spaces`, then sections, then containers by ascending depth; ties sorted by UUID string (deterministic).
- Moving a node between sections emits both sections and no `.node`.

**Step 2:** Run `cd $KIT && nice -n 20 swift test -j 2 --filter CoreBridgeTests 2>&1 | tail -5`. Expected: compile errors.

**Step 3: Implement**

`BridgeMapping.swift`:

```swift
import Foundation
import ShellUI
import SidebarModel

enum BridgeMapping {
  static func location(_ location: SidebarLocation) -> SidebarModel.Location {
    switch location {
    case .favorites(let profile): .favorites(profile: profile)
    case .pinned(let id): .pinned(id)
    case .today(let id): .today(id)
    case .folder(let id): .folder(id)
    case .split(let id): .split(id)
    }
  }

  static func location(_ location: SidebarModel.Location) -> SidebarLocation { /* the inverse, case by case */ }

  static func nodeInfo(_ node: SidebarModel.Node) -> SidebarNodeInfo {
    switch node.kind {
    case .tab(let tab): .tab(id: node.id, url: tab.url, title: tab.customTitle ?? tab.title)
    case .folder(let folder): .folder(id: node.id, title: folder.title)
    case .split: .split(id: node.id)
    }
  }

  static func spaceInfo(_ space: SidebarModel.Space) -> SidebarSpaceInfo {
    SidebarSpaceInfo(id: space.id, title: space.title, profile: space.profile, theme: theme(space.theme))
  }

  static func theme(_ theme: SidebarModel.SpaceTheme?) -> SpaceThemeInfo {
    guard let theme, !theme.baseColors.isEmpty else { return .bridgeDefault }
    return SpaceThemeInfo(
      baseColors: theme.baseColors.map(rgba), overlayColors: theme.overlayColors.map(rgba), texture: theme.texture,
      // [I] Arc's noiseFactor is not in the core model yet (data-model 1.6); a mid value until it is.
      noiseFactor: theme.texture == nil ? 0 : 0.5, isDark: theme.isDark)
  }

  /// Arc stores `extendedSRGB` components (data-model doc); values outside 0...1 are kept.
  static func rgba(_ color: SidebarModel.RGBA) -> ShellUI.RGBA {
    ShellUI.RGBA(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha, space: .sRGB)
  }
}

extension SpaceThemeInfo {
  /// Light neutral theme for Spaces without one (new Spaces, Arc Spaces with an unsupported theme).
  public static let bridgeDefault = SpaceThemeInfo(
    baseColors: [.p3(hex: 0xF2F0EE, alpha: 1), .p3(hex: 0xE4E1DD, alpha: 1)], isDark: false)  // TODO(design)
}
```

`SidebarDiff.swift`:

```swift
import Foundation
import ShellUI
import SidebarModel

enum SidebarDiff {
  static func changes(from old: SidebarModel.Sidebar, to new: SidebarModel.Sidebar) -> [SidebarChange] {
    var result: [SidebarChange] = []
    if old.spaceOrder != new.spaceOrder || old.spaces != new.spaces { result.append(.spaces) }

    var sections: [SidebarModel.Location] = []
    var containers: [(depth: Int, location: SidebarModel.Location)] = []
    for location in Set(old.childOrder.keys).union(new.childOrder.keys)
    where old.childOrder[location] != new.childOrder[location] {
      if let container = location.containerNode {
        guard new.nodes[container] != nil else { continue }  // removed with its parent: rows already gone
        containers.append((depth(of: container, in: new), location))
      } else {
        sections.append(location)
      }
    }
    result += sections.sorted(by: sortKey).map { .structure(BridgeMapping.location($0)) }
    result += containers.sorted { ($0.depth, key($0.location)) < ($1.depth, key($1.location)) }
      .map { .structure(BridgeMapping.location($0.location)) }

    var nodeChanges: [UUID] = []
    for (id, node) in new.nodes {
      guard let before = old.nodes[id], before != node else { continue }
      if BridgeMapping.nodeInfo(before) != BridgeMapping.nodeInfo(node) { nodeChanges.append(id) }
    }
    result += nodeChanges.sorted { $0.uuidString < $1.uuidString }.map { .node($0) }
    return result
  }
  // depth(of:in:), key(_:) (case rank + id string) and sortKey: small private helpers.
}
```

`ModelSidebarSource.swift`:

```swift
import Archive
import Foundation
import ShellUI
import SidebarModel

/// `SidebarSource` over Arkt's value-type `Sidebar`. The value is the single source of truth; every change goes
/// through `mutate`, which emits the exact `SidebarChange`s (diffed) and then reports the new value through
/// `onDidChange` (the app wires it to `SidebarAutosaver.scheduleSave`). Errors from the model are rethrown and leave
/// the value, the observers and `onDidChange` untouched.
@MainActor
public final class ModelSidebarSource: SidebarSource {
  public private(set) var sidebar: SidebarModel.Sidebar
  public var onDidChange: (@MainActor (SidebarModel.Sidebar) -> Void)?
  public let defaultProfile: String
  private let hub = SidebarChangeHub()
  private let now: @MainActor () -> Date

  public init(sidebar: SidebarModel.Sidebar = .init(), defaultProfile: String = "default",
              now: @escaping @MainActor () -> Date = { Date() }) {
    self.sidebar = sidebar; self.defaultProfile = defaultProfile; self.now = now
  }

  // MARK: SidebarSource (reads)
  public var spaceOrder: [UUID] { sidebar.spaceOrder }
  public func space(_ id: UUID) -> SidebarSpaceInfo? { sidebar.spaces[id].map(BridgeMapping.spaceInfo) }
  public func children(of location: SidebarLocation) -> [UUID] { sidebar.children(of: BridgeMapping.location(location)) }
  public func node(_ id: UUID) -> SidebarNodeInfo? { sidebar.nodes[id].map(BridgeMapping.nodeInfo) }
  public func parent(of id: UUID) -> SidebarLocation? { sidebar.nodes[id].map { BridgeMapping.location($0.parent) } }
  public func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation {
    hub.observe(handler)
  }

  // MARK: SidebarSource (writes)
  @discardableResult
  public func addTab(url: URL, title: String, in location: SidebarLocation) throws -> UUID {
    let createdAt = now()
    return try mutate {
      try $0.addTab(url: url, title: title, lastActiveAt: createdAt, in: BridgeMapping.location(location),
                    createdAt: createdAt)
    }
  }

  @discardableResult
  public func addSpace(title: String) throws -> UUID {
    mutate { $0.addSpace(title: title, profile: defaultProfile) }
  }

  /// Engine-driven title / URL changes. Unknown or non-tab ids are ignored, like `StubSidebar`.
  public func updateTab(_ id: UUID, url: URL?, title: String?) {
    try? mutate { try $0.updateTab(id, url: url, title: title) }
  }

  /// D4b contract: stamps tabs that stopped being visible. Non-tabs and unknown ids are skipped.
  public func markInactive(_ ids: some Sequence<UUID>, at date: Date) {
    mutate { sidebar in for id in ids { try? sidebar.updateTab(id, lastActiveAt: date) } }
  }

  // MARK: Mutation

  @discardableResult
  public func mutate<T>(_ body: (inout SidebarModel.Sidebar) throws -> T) rethrows -> T {
    var copy = sidebar
    let result = try body(&copy)
    guard copy != sidebar else { return result }
    let old = sidebar
    sidebar = copy
    for change in SidebarDiff.changes(from: old, to: copy) { hub.emit(change) }
    onDidChange?(copy)
    return result
  }
}
```

Note: `addTab` stamps `lastActiveAt = createdAt` so a brand-new background tab starts its idle clock now; the policy
falls back to `createdAt` anyway, so this only makes the stored value explicit.

**Step 4:** Run `--filter CoreBridgeTests`, then the whole pure suite. Expected: all contract cases pass on both
kinds; baseline + the new count; `CoreIsolationTests` still green (CoreBridge imports SidebarModel, never Persistence).

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/CoreBridge app/ArktShell/ShellKit/Tests/CoreBridgeTests && git commit -m "Add ModelSidebarSource: SidebarSource over the real sidebar model"
```

---

### Task E3a: Toasts (non-blocking notices)

ShellUI has no toast. E3 (recovery notice, errors), E4 (import summary line) and E5 (BH-085, BH-086) all need one.

**Files:**
- Create: `$KIT/Sources/ShellUI/Toast/ToastPresenter.swift`, `ToastView.swift`
- Modify: `$KIT/Sources/ShellUI/Window/ShellWindowController.swift` (`public let toasts: ToastPresenter`, `onError` default)
- Create: `$KIT/Tests/ShellUITests/ToastPresenterTests.swift`, `$KIT/Tests/ShellKitGUITests/ToastViewTests.swift`

**Step 1: Failing tests** (pure, state only; time injected like `SidebarAutosaver`)

```swift
@MainActor
struct ToastPresenterTests {
  @Test func newToastReplacesCurrent() {
    let presenter = ToastPresenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    presenter.show(Toast(text: "One"))
    presenter.show(Toast(text: "Two"))
    #expect(presenter.current?.text == "Two")
  }

  @Test func transientToastDismissesAfterDuration() async {
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: { _ in for await _ in gate.stream { return } })
    presenter.show(Toast(text: "Bye"))
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func persistentToastStaysUntilDismissed() { /* show(.persistent), no timer armed, dismiss() clears */ }
  @Test func actionRunsAndDismisses() { /* performActionForTesting() calls the closure once, current == nil */ }
}
```

**Step 2:** Run `--filter ToastPresenterTests`; expect compile errors.

**Step 3: Implement**

```swift
public struct Toast: Equatable, Sendable {
  public var text: String
  public var actionTitle: String?
  /// Persistent toasts (recovery notices) stay until dismissed or replaced by another persistent one.
  public var isPersistent: Bool
  public init(text: String, actionTitle: String? = nil, isPersistent: Bool = false) { ... }
}

@MainActor
public final class ToastPresenter {
  public static let defaultDuration: Duration = .seconds(4)       // TODO(measure): Arc's duration is unknown (BH-192)
  public private(set) var current: Toast?
  /// Set by the window: draws `current` over the bottom of the content card.
  var view: ToastView?
  ...
  public func show(_ toast: Toast, onAction: (@MainActor () -> Void)? = nil)
  public func dismiss()
}
```

`ToastView`: an `NSView` with a layer-backed rounded rect (Space-flavor fill: dark text on light themes, light on dark,
BH-190 partly), one `NSTextField` label and an optional borderless `NSButton`; frame set by `ContentCardView.layout()`
(centered, 16 pt above the card's bottom edge, max width 480 pt). Fade in/out with a 150 ms `CABasicAnimation` on
`opacity` (no layout animation). A transient toast never steals first responder. Accessibility: role
`.staticText`, `NSAccessibility.post(element:notification: .announcementRequested)` with the text.

`ShellWindowController`: create `toasts`, attach its view to `rootView.card`; default
`onError = { [weak self] _ in self?.toasts.show(Toast(text: "Couldn't add the tab.")) }`.

**Step 4:** Pure and GUI filters pass (GUI: the view is inside the card, hidden when `current == nil`).

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/ShellUI/Toast app/ArktShell/ShellKit/Sources/ShellUI/Window app/ArktShell/ShellKit/Tests/ShellUITests/ToastPresenterTests.swift app/ArktShell/ShellKit/Tests/ShellKitGUITests/ToastViewTests.swift && git commit -m "Add toasts over the content card"
```

---

### Task E3b: First-run empty state

**Files:**
- Create: `$KIT/Sources/ShellUI/Window/EmptyStateView.swift`
- Modify: `$KIT/Sources/ShellUI/Window/ShellWindowController.swift`
- Create: `$KIT/Tests/ShellKitGUITests/EmptyStateTests.swift`

**Design.** When the window's profile has no Space, the content card shows (instead of a page) a centered panel:
heading "Welcome to Arkt", one line "Bring your Spaces, pinned tabs and Archive over from Arc, or start fresh.", and two
buttons: "Import from Arc" (default button, only when `isArcImportAvailable`) and "New Space". The sidebar column stays
(empty pages, no dots); Cmd-T still works (decision 3). The panel disappears as soon as a Space exists (`.spaces`
through C6's `onSpacesChanged`). No onboarding beyond this (BH-211 is a later track).

**Note (from the E2b review).** `SidebarController.apply(.spaces)` calls `showSpace(first)` when the current Space is
no longer listed, but `showSpace` only commits the page; it does not activate a tab. Whenever the current Space is
removed and another Space becomes current (here, and in E5 when an archive or restore empties or removes a Space),
also activate `tabToRestore(in:)` for the new Space, the way `pagerSettled(on:)` does, and cover it with a GUI test.
When the last Space goes away, E2b already sets `currentSpace = nil` and clears the current page; the empty state
above takes over.

**Step 1: Failing GUI tests**

- Empty `StubSidebar`: `controller.isShowingEmptyState == true`; "Import from Arc" hidden while
  `isArcImportAvailable == false`, shown after setting it true.
- Clicking "New Space" (`performClick`) calls `onNewSpace` once; with the default handler, the stub gains one Space
  named per `ShellWindowController.newSpaceTitle`, `isShowingEmptyState` becomes false and `currentSpace` is set.
- Clicking "Import from Arc" calls `onImportFromArc` once and creates nothing.
- Cmd-T path with no Space: `open(url, inNewTab: true)` creates one Space, then the tab, and activates it.

**Step 2:** Run `--filter EmptyStateTests`; expect compile errors.

**Step 3: Implement**

```swift
// ShellWindowController
  public var isArcImportAvailable = false { didSet { emptyState.showsImport = isArcImportAvailable } }
  public var onImportFromArc: (@MainActor () -> Void)?
  public var onNewSpace: (@MainActor () -> Void)?        // default: createFirstSpace()
  public static let newSpaceTitle = "Space"               // [I] product wording, see open questions
  public var isShowingEmptyState: Bool { sidebarController.spaces.isEmpty }

  @discardableResult
  func createSpace() -> SpaceID? {
    do { return try sidebar.addSpace(title: Self.newSpaceTitle) } catch { onError?(error); return nil }
  }

  private func updateEmptyState() {
    rootView.card.setEmptyState(isShowingEmptyState ? emptyState : nil)
  }
```

`updateEmptyState()` runs at the end of `init` and inside the existing C6 `onSpacesChanged` hook (next to
`refreshThemes()`). In `open(_:inNewTab:)`: `guard let space = sidebarController.currentSpace ?? createSpace() else { return }`.

**Step 4:** GUI filter passes; pure suite unchanged.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/ShellUI/Window app/ArktShell/ShellKit/Tests/ShellKitGUITests/EmptyStateTests.swift && git commit -m "Add first-run empty state with Import from Arc and New Space"
```

---

### Task E3c: Launch, autosave, backups and termination (app target)

**Files:**
- Create: `$KIT/Sources/CoreBridge/RecoveryNotice.swift`, `$KIT/Tests/CoreBridgeTests/RecoveryNoticeTests.swift`
- Create: `$APP/App/AppEnvironment.swift`, `$APP/App/AppSession.swift`
- Modify: `$APP/App/AppDelegate.swift`

**Step 1: Failing tests (CoreBridge, pure)**

`RecoveryNotice` is CoreBridge's own enum (CoreBridge cannot see `OpenOutcome`; the app maps it, one switch):

```swift
struct RecoveryNoticeTests {
  @Test func restoredFromBackupIsPersistentWithShowFiles() {
    let toast = RecoveryNotice.restoredFromBackup(liveFileWasDamaged: true).toast
    #expect(toast.isPersistent && toast.actionTitle == "Show Files")
    #expect(toast.text == "Arkt couldn't read its saved sidebar and restored it from a backup. Recent changes may be missing.")
  }
  @Test func restoredWhenLiveFileMissing() { /* liveFileWasDamaged false: "Arkt's saved sidebar was missing and was restored from a backup." */ }
  @Test func recreatedEmpty() { /* "Arkt couldn't read its saved sidebar and no backup could be used. The damaged file was kept aside." */ }
  @Test func noFileNamesOrPathsInText() { /* every case: text contains no "/" and no ".sqlite" */ }
}
```

**Step 2:** Run `--filter RecoveryNoticeTests`; expect compile errors. Implement the enum (`toast` computed property),
re-run, pass.

**Step 3: App environment** (`AppEnvironment.swift`)

```swift
import Foundation
import Persistence

enum AppEnvironment {
  static func databaseLocation() throws -> DatabaseLocation {
    #if DEBUG
    if let path = ProcessInfo.processInfo.environment["ARKT_DATA_DIR"] {
      return DatabaseLocation(directory: URL(fileURLWithPath: path, isDirectory: true))
    }
    #endif
    return try .applicationSupport()
  }

  /// Arc's data folder; read only after the user asks for an import. DEBUG builds may point it at a fixture copy.
  static var arcDirectory: URL {
    #if DEBUG
    if let path = ProcessInfo.processInfo.environment["ARKT_ARC_DIR"] { return URL(fileURLWithPath: path, isDirectory: true) }
    #endif
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
  }
}
```

**Step 4: Composition root** (`AppSession.swift`, the only file family importing `Persistence`)

```swift
import AppKit
import Archive
import CoreBridge
import EngineAPI
import Persistence
import ShellUI
import SidebarModel
import os

@MainActor
final class AppSession {
  static let log = Logger(subsystem: "dev.arkt.shell", category: "session")
  let location: DatabaseLocation
  let database: ArktDatabase
  let source: ModelSidebarSource
  let autosaver: SidebarAutosaver
  let window: ShellWindowController
  private var backupTimer: Timer?
  private var changedSinceBackup = false

  init(state: LaunchState, location: DatabaseLocation, engine: any EngineClient) {
    self.location = location
    self.database = state.database
    let source = ModelSidebarSource(sidebar: state.sidebar ?? SidebarModel.Sidebar())
    self.source = source
    self.autosaver = SidebarAutosaver(store: SidebarStore(database: state.database))
    self.window = ShellWindowController(engine: engine, sidebar: source)
    source.onDidChange = { [weak self] sidebar in
      self?.autosaver.scheduleSave(sidebar)        // every model change (design 4)
      self?.changedSinceBackup = true
    }
  }

  func start(outcome: OpenOutcome) {
    window.window?.center()
    window.showWindow(nil)
    if let notice = Self.notice(for: outcome) {
      Self.log.notice("launch outcome \(String(describing: notice), privacy: .public)")
      window.toasts.show(notice.toast) { [location] in
        NSWorkspace.shared.activateFileViewerSelecting([location.directory])
      }
    }
    switch outcome {
    case .opened, .restoredFromBackup: backUp()
    case .created, .recreatedEmpty: break      // nothing to back up; never seed (decision 3)
    }
    backupTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { if self?.changedSinceBackup == true { self?.backUp() } }
    }
  }

  static func notice(for outcome: OpenOutcome) -> RecoveryNotice? {
    switch outcome {
    case .created, .opened: nil
    case .restoredFromBackup(_, let quarantined): .restoredFromBackup(liveFileWasDamaged: quarantined != nil)
    case .recreatedEmpty: .recreatedEmpty
    }
  }

  /// The latest backup task; the DEBUG smoke phases await it before printing and quitting (E6), so a quick quit
  /// cannot race the launch backup.
  private(set) var lastBackup: Task<Void, Never>?

  private func backUp() {
    changedSinceBackup = false
    let (database, location) = (database, location)
    lastBackup = Task {
      do { _ = try await database.makeBackup(in: location, now: .now) }
      catch { Self.log.error("backup failed \(String(describing: type(of: error)), privacy: .public)") }
    }
  }

  // MARK: Termination
  var needsFlush: Bool { autosaver.needsFlush }       // E5a adds: || archive.hasPendingWrites
  func prepareForTermination() { /* E5b: source.markInactive(window.visibleNodes, at: .now) */ }
  func flush() async -> Bool { await autosaver.flush() }  // E5a: also the archive outbox, concurrently
}
```

**Step 5: App delegate** (`AppDelegate.swift`)

```swift
import AppKit
import FakeEngineKit
import Persistence
import ShellUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var session: AppSession?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    NSApp.activate()
    Task { await launch() }
  }

  /// `openAndLoad` is `@concurrent`: all disk work runs off the main thread; the main actor only awaits. The window
  /// is built after the load (milliseconds) so the sidebar never flashes empty.
  private func launch() async {
    do {
      let location = try AppEnvironment.databaseLocation()
      let state = try await ArktLaunch.openAndLoad(location, now: .now)
      let session = AppSession(state: state, location: location, engine: FakeEngine())   // composition root only
      self.session = session
      session.start(outcome: state.outcome)
    } catch {
      presentLaunchFailure(error)
    }
  }

  private func presentLaunchFailure(_ error: any Error) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    if case ArktDatabaseError.newerSchema = error {
      alert.messageText = "This data was saved by a newer version of Arkt."
      alert.informativeText = "Update Arkt to open it. Nothing was changed."
      alert.addButton(withTitle: "Quit")
    } else {
      alert.messageText = "Arkt couldn't open its data."
      alert.informativeText = "Nothing was changed. (\(type(of: error)) \((error as NSError).code))"
      alert.addButton(withTitle: "Try Again")
      alert.addButton(withTitle: "Quit")
    }
    if alert.runModal() == .alertFirstButtonReturn, alert.buttons.count == 2 {
      Task { await launch() }
    } else {
      NSApp.terminate(nil)
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let session else { return .terminateNow }
    session.prepareForTermination()                  // stamps visible tabs first (decision 10)
    guard session.needsFlush else { return .terminateNow }
    Task { @MainActor in
      _ = await session.flush()                       // bounded by flushTimeout
      sender.reply(toApplicationShouldTerminate: true) // always true: never block quitting on a failed save
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```
(Check whether `ArktDatabaseError.newerSchema` carries associated values; match with `case .newerSchema` accordingly.)

**Step 6: Build and manual checks**

Run the App build command. Expected `** BUILD SUCCEEDED **`. Then, with a scratch data folder (never the real one
while developing; `ARKT_DATA_DIR` works in Debug):

```zsh
SCRATCH=$(mktemp -d); BIN=$DD/Build/Products/Debug/ArktShell.app/Contents/MacOS/ArktShell
ARKT_DATA_DIR=$SCRATCH/data $BIN
```
1. Empty state shows; no `Backups` folder content: `ls $SCRATCH/data/Backups 2>/dev/null | wc -l` prints 0.
2. Click "New Space", press Cmd-T, type `example.com`, Enter. Quit with Cmd-Q. Relaunch: the Space and tab are back.
3. **Manual `NSModalPanelRunLoopMode` check (required by `SidebarAutosaver.flush` docs):** press Cmd-T, type
   `example.org`, Enter, and press Cmd-Q within half a second (inside the 500 ms debounce, so the quit takes the
   `.terminateLater` path). Relaunch: the new tab is present. Optionally confirm with
   `log show --last 2m --predicate 'subsystem == "dev.arkt.shell"' | grep -c flush` after adding a debug log line at
   the end of the flush Task (remove it before committing).
4. Recovery: quit, then `printf 'not a database' > $SCRATCH/data/Arkt.sqlite`, relaunch: the persistent
   "restored it from a backup" toast shows (a backup exists from step 2's relaunch), the sidebar is back, and
   `ls $SCRATCH/data` shows `Arkt.sqlite.corrupt-*`. "Show Files" reveals the folder.
5. `rm -rf $SCRATCH`.

**Step 7: Commit**

```zsh
cd $REPO && git add app/ArktShell/App app/ArktShell/ShellKit/Sources/CoreBridge/RecoveryNotice.swift app/ArktShell/ShellKit/Tests/CoreBridgeTests/RecoveryNoticeTests.swift && git commit -m "Launch from the database, autosave every change, flush on quit"
```

---

### Task E4a: Core seams for import and archive (ArktCore)

**Files:**
- Create: `$CORE/Sources/Archive/ArchiveQuery.swift` (move `ArchiveFilter`, `ArchiveConflictPolicy`, `ArchivePage`
  verbatim from `Persistence/ArchiveStore.swift`)
- Create: `$CORE/Sources/Archive/ArchiveStoring.swift`
- Modify: `$CORE/Sources/Persistence/ArchiveStore.swift`, `SettingsStore.swift`
- Create: `$CORE/Sources/ArcImport/StableID.swift`; Modify: `ArcSidebarImporter.swift`, `ArcArchiveImporter.swift`
- Modify tests: `SettingsStoreTests.swift`, `ArcSidebarImporterTests.swift` (+ `import Archive` where moved types are used)

**Step 1: Failing tests**

`SettingsStoreTests`:

```swift
  @Test func resetAutoArchiveStartOverwritesAndKeepsOtherFields() async throws {
    let store = SettingsStore(database: try ArktDatabase.inMemory())
    let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try await store.resolveAutoArchiveStart(now: first)
    try await store.save(ArchiveState(autoArchiveStartedAt: first, educationBannerDismissed: true), at: first)
    let later = first.addingTimeInterval(3600)
    try await store.resetAutoArchiveStart(to: later)
    let state = try await store.load(ArchiveState.self)
    #expect(state.autoArchiveStartedAt == later)
    #expect(state.educationBannerDismissed)
    #expect(try await store.resolveAutoArchiveStart(now: later.addingTimeInterval(60)) == later)
  }
```

`ArcSidebarImporterTests`:

```swift
  @Test func spaceIDsAreStableAcrossImports() throws {
    let file = try ArcSidebarFile.decode(Self.fixtureData("StorableSidebar-synthetic.json"))
    let first = try ArcSidebarImporter.makeSidebar(from: file)
    let second = try ArcSidebarImporter.makeSidebar(from: file)
    #expect(!first.spaceIDsByArcID.isEmpty)
    #expect(first.spaceIDsByArcID == second.spaceIDsByArcID)
    for (arcID, spaceID) in first.spaceIDsByArcID where UUID(uuidString: arcID) != nil {
      #expect(spaceID == UUID(uuidString: arcID))
    }
  }
```
(Use the helper the existing tests use to load fixtures; keep everything synthetic.)

A compile-level conformance test in `PersistenceTests`: `let _: any ArchiveStoring = ArchiveStore(database: db)` and
`let _: any ArchiveStateStoring = SettingsStore(database: db)`.

**Step 2:** Run the core suite; expect compile errors.

**Step 3: Implement**

`ArchiveStoring.swift` (Archive target, pure):

```swift
import Foundation
import SidebarModel

/// What app code needs from the archive table. `Persistence.ArchiveStore` conforms; CoreBridge tests use fakes.
public protocol ArchiveStoring: Sendable {
  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int
  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage
  func remove(_ ids: [NodeID]) async throws
}

/// Auto-archive bookkeeping (`ArchiveState`). `Persistence.SettingsStore` conforms.
public protocol ArchiveStateStoring: Sendable {
  func resolveAutoArchiveStart(now: Date) async throws -> Date
  /// Track D open question 6, decided in Track E: an Arc sidebar import restarts the auto-archive clock.
  func resetAutoArchiveStart(to date: Date) async throws
  func loadArchiveSettings() async throws -> ArchiveSettings
}
```

`SettingsStore`: add, in one transaction like `resolveAutoArchiveStart`,

```swift
  @concurrent
  public func resetAutoArchiveStart(to date: Date) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let key = ArchiveState.storageKey
    let updatedAt = date.timeIntervalSinceReferenceDate
    try await database.writer.write { db in
      var state = Self.decode(ArchiveState.self, from: try Self.fetchValue(db, key: key))
      state.autoArchiveStartedAt = date
      try Self.store(db, key: key, value: try Self.encode(state), updatedAt: updatedAt)
    }
  }

  @concurrent
  public func loadArchiveSettings() async throws -> ArchiveSettings { try await load(ArchiveSettings.self) }
```
plus `extension SettingsStore: ArchiveStateStoring {}` and `extension ArchiveStore: ArchiveStoring {}`. If the compiler
rejects `@concurrent` witnesses for plain `async` requirements, mark the protocol requirements `@concurrent` as well
(same isolation, so the store keeps running off the main actor).

`StableID.swift`: move `ArcArchiveImporter`'s private "Arc UUID or SHA-256-derived UUID" helper here as
`enum StableID { static func uuid(forArcID: String) -> UUID }` and use it from both importers. In
`ArcSidebarImporter.importSpace`, replace `sidebar.addSpace(title:profile:theme:)` with
`try sidebar.addSpace(Space(id: StableID.uuid(forArcID: space.id), title: ..., profile: ..., theme: theme))`; on
`.duplicateID` (two Arc spaces with the same id cannot happen in a valid file) skip the space with a `.decodeFailed`
reason. Node ids stay freshly minted (decision 6a).

**Step 4:** Core suite passes (baseline + new). Then rebuild ShellKit (`--skip ShellKitGUITests`) since CoreBridge sees
the moved types.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktCore/Sources/Archive app/ArktCore/Sources/Persistence/ArchiveStore.swift app/ArktCore/Sources/Persistence/SettingsStore.swift app/ArktCore/Sources/ArcImport app/ArktCore/Tests && git commit -m "Archive store protocols, auto-archive clock reset, stable imported Space ids"
```

---

### Task E4b: Favicon store and favicon retention

**Files:**
- Create: `$KIT/Sources/CoreBridge/FaviconStore.swift`, `$KIT/Tests/CoreBridgeTests/FaviconStoreTests.swift`
- Modify: `$KIT/Sources/ShellUI/Sidebar/SidebarController.swift`, `$KIT/Sources/ShellUI/Window/ShellWindowController.swift`
- Create/modify: `$KIT/Tests/ShellKitGUITests/SidebarViewTests.swift` (one test)

**Step 1: Failing tests**

`FaviconStoreTests` (temp directory from `FileManager.default.temporaryDirectory`, removed in `defer`):
- `save([id: png])` then `loadAll(for: [id, other])` returns exactly `[id: png]`.
- `prune(keeping: [])` deletes files; unrelated files in the directory (not `<UUID>.png`) are untouched.
- `init` refuses a directory inside an Arc folder: `#expect(throws: FaviconStoreError.forbiddenDirectory)` for
  `.../Library/Application Support/Arc/Favicons`.

GUI: after `setFavicon(data, for: node)` and `deactivate(node:)` for a node that still exists in the source, the
favicon is still served (`favicons[node] != nil`); after the node is removed from the source it is dropped.

**Step 2:** Run the filters; expect failures.

**Step 3: Implement**

```swift
public enum FaviconStoreError: Error, Equatable { case forbiddenDirectory }

/// Favicons as `<node UUID>.png` files in Arkt's own data folder. All I/O is `@concurrent`.
public struct FaviconStore: Sendable {
  public let directory: URL

  public init(directory: URL) throws {
    // Arkt never writes into Arc's folder (design 5, Track E rules).
    guard !directory.standardizedFileURL.path.contains("/Application Support/Arc/") else {
      throw FaviconStoreError.forbiddenDirectory
    }
    self.directory = directory
  }

  @concurrent public func save(_ favicons: [UUID: Data]) async throws { /* create dir, write each .atomic */ }
  @concurrent public func loadAll(for ids: Set<UUID>) async -> [UUID: Data] { /* read existing files only */ }
  @concurrent public func prune(keeping ids: Set<UUID>) async { /* remove <UUID>.png not in ids */ }
}
```

`SidebarController.deactivate(node:)`: drop the favicon only when `source.node(node) == nil`; in `apply(.structure)`,
drop favicons of nodes that no longer exist (`favicons.keys.filter { source.node($0) == nil }`). Add
`public func setFavicons(_ batch: [NodeID: Data])` that decodes all, then reloads each affected row once.
`ShellWindowController`: `public var onFaviconChanged: (@MainActor (NodeID, Data?) -> Void)?`, called from the
`.faviconChanged` engine event (the app persists it).

**Step 4:** Filters pass, full pure suite passes.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/CoreBridge/FaviconStore.swift app/ArktShell/ShellKit/Sources/ShellUI app/ArktShell/ShellKit/Tests && git commit -m "Persist favicons in Arkt's data folder; keep them while the node exists"
```

---

### Task E4c: Arc import (coordinator, merge, record, menu, summary)

As built (including the review follow-ups). The rules are decision 6 and User decisions 1, 2, 3 and 5: a run
adds only Arc Spaces and top-level Favorites never imported before, merges other Arc profiles into the default one,
imports the archive idempotently, and never restores items the user deleted in Arkt.

**Files:**
- Create: `$CORE/Sources/ArcImport/ArcImportRecord.swift` (`ArcImportRecord`, `ArcImportRecordStoring`)
- Modify: `$CORE/Package.swift` (`Persistence` and `PersistenceTests` depend on `ArcImport`),
  `$CORE/Sources/Persistence/SettingsStore.swift` (`ArcImportRecord: SettingsGroup` under key `arcImport.record`,
  `loadArcImportRecord()`, `recordArcImport(_:at:)` as read, union, write in one transaction, conformance),
  `$CORE/Tests/PersistenceTests/SettingsStoreTests.swift`
- Create: `$KIT/Sources/CoreBridge/ArcImportMerge.swift` (pure merge), `$KIT/Sources/CoreBridge/ArcImportCoordinator.swift`,
  `$KIT/Sources/CoreBridge/FaviconWriter.swift`, `$KIT/Tests/CoreBridgeTests/ArcImportMergeTests.swift`,
  `$KIT/Tests/CoreBridgeTests/ArcImportCoordinatorTests.swift`, `$KIT/Tests/CoreBridgeTests/FaviconWriterTests.swift`,
  `$KIT/Tests/CoreBridgeTests/Fakes.swift` (`FakeArchiveStore`, `FakeArchiveState`, `FakeArcImportRecordStore`,
  `ArcFixtureFolder`), and the two synthetic fixtures copied into `$KIT/Tests/CoreBridgeTests/Fixtures/`
  (`resources: [.copy("Fixtures")]` on the test target)
- Modify: `$KIT/Package.swift`, `$KIT/Sources/CoreBridge/FaviconStore.swift` (init doc: it does disk I/O, never on
  the main actor), `$APP/App/AppSession.swift`, `$APP/App/AppDelegate.swift`, `$APP/App/MainMenu.swift`,
  `$APP/App/AppEnvironment.swift`. `ModelSidebarSource` gets no import entry point: the coordinator uses `mutate`.

**Step 1: Failing tests** (fixtures only; the Arc "directory" is a temp folder holding copies named
`StorableSidebar.json` and `StorableArchiveItems.json`, plus one hand-made favicon file named
`ArcFaviconCache.fileName(forItemID:)` of a fixture tab id inside `SidebarItemsFaviconCache/`; `arc.unchanged()`
compares SHA-256 digests of every file before and after)

`SettingsStoreTests`: an empty record until something is recorded; `recordArcImport` unions with what is stored;
the stored JSON has sorted arrays and survives a reopen; `SettingsStore` is an `ArcImportRecordStoring`.

`ArcImportMergeTests` (pure, `ArcImportResult` built by hand with Arc ids):
- An existing Space (same id) is left exactly as it is, and its Arc id is recorded (`counts.handled`).
- An added Space keeps its tree and moves to the target profile.
- Favorites of every profile merge without duplicate URLs; without a record the URL match still prevents duplicates.
- A folder (and a split) Favorite imported twice is added once (`previouslyImportedFavorites == 2`).
- A deleted Space is not restored (`missingSpaces` is empty, so no clock reset; `previouslyImportedSpaces == 1`).
- A deleted Favorite is not restored; a Favorite whose URL drifted in Arc is not added again.
- Never imported items are still added when a record exists.

`ArcImportCoordinatorTests` (fakes for the archive, the archive state and the record):
- First import fills the empty sidebar (2 Spaces, 7 tabs, 1 folder, 1 split, 2 Favorites), adds the archive with
  `.keepExisting`, resets the clock once, returns 1 favicon, records both Space ids and both Favorite ids.
- Re-import of the same file adds nothing, keeps the clock, archive delta 0, `previouslyImportedFavorites == 2`.
- Re-import adds a missing Space (and resets the clock) and leaves the rest alone, user Space order kept.
- Archive sources map to the same Spaces on re-import.
- A Favorite deleted in Arkt is not restored; recorded Spaces missing from Arkt are not restored and keep the clock.
- An import from before the record existed falls back to the id and URL matches, then records everything it saw.
- Other-profile Spaces and Favorites merge into the default profile without duplicate URLs.
- Failures: no archive file (`archiveImported == nil`); an unreadable or wrong-version archive file keeps the
  sidebar part (`archiveFailed`, no archive write); an undecodable sidebar throws and changes nothing; a failed
  record load or clock reset throws before anything changed; a failed archive write or record write keeps the
  sidebar part and is reported (`archiveFailed`, `recordFailed`); the record is written only after the persist hook
  saw the merged sidebar, and when it reports the sidebar unsaved nothing is recorded (`recordFailed`); a second run
  while one is running is refused.
- Summary lines are counts only (no fixture title or URL fragment).

`FaviconWriterTests`: coalescing, delay, ordering, waiting for the launch task, `touched`, and `touched` is cleared
and stops growing after `launchLoadDidComplete()`.

**Step 2:** Run the filters; expect compile errors.

**Step 3: Implement**

- `ArcImportRead.read` (`@concurrent`, reads only): decodes the sidebar (a failure throws), then the archive file in
  its own `do`/`catch` (a decode or version failure sets `archiveUnreadable`, the archive is nil), then the favicons
  of imported tabs from `SidebarItemsFaviconCache`.
- `ArcImportMerge.merge(_ imported: ArcImportResult, into:profile:record:)`: per Space, skip when the id is in Arkt
  (`existingSpaces`) or its Arc id is recorded (`previouslyImportedSpaces`), else add it with its Pinned and Today
  trees into `profile`. Per top-level Favorite of every Arc profile (the target profile first), skip when its Arc id
  is recorded (`previouslyImportedFavorites`) or, for a tab, when its URL is already a Favorite
  (`duplicateFavorites`), else add it. `counts.handled` collects every Arc id it added or skipped (not refused ones),
  so an import from before the record existed records what it matched. `missingSpaces(in:comparedTo:record:)` drives
  the clock reset.
- `ArcImportCoordinator.run(_:)`:

```swift
let bundle = try await ArcImportRead.read(files)
let imported = bundle.sidebar
let record = try await importRecord.loadArcImportRecord()
if !ArcImportMerge.missingSpaces(in: imported, comparedTo: source.sidebar, record: record).isEmpty {
  try await archiveState.resetAutoArchiveStart(to: now())
}
var counts = ArcImportMergeCounts()
source.mutate { counts = ArcImportMerge.merge(imported, into: &$0, profile: visibleProfile, record: record) }
// Record only once the merged sidebar is on disk: recorded ids are never imported again, so a record ahead of the
// saved sidebar would lose those items for good after a crash or force quit in the autosave debounce.
var recordFailed = false
if !counts.handled.isEmpty {
  if await persistSidebar() {
    do { try await importRecord.recordArcImport(counts.handled, at: now()) } catch { recordFailed = true }
  } else {
    recordFailed = true
  }
}
// summary from counts; archiveFailed = bundle.archiveUnreadable
if let items = bundle.archive {
  do { summary.archiveImported = try await archive.add(items.items, onConflict: .keepExisting) }
  catch { summary.archiveFailed = true }
}
return ArcImportOutcome(summary: summary, favicons: bundle.favicons.filter { counts.addedNodes.contains($0.key) })
```

  `persistSidebar: @MainActor () async -> Bool` is injected: the app passes `{ await autosaver.flush() }`, tests a
  fake. `isRunning` guards a second run (`ArcImportCoordinatorError.alreadyRunning`).
- `ArcImportSummary` fields: `spaces`, `existingSpaces`, `previouslyImportedSpaces`, `otherProfileSpaces`, `tabs`,
  `folders`, `splits`, `favorites`, `duplicateFavorites`, `previouslyImportedFavorites`, `skipped`,
  `archiveImported` (nil: no file or failed), `archiveSkipped`, `archiveFailed`, `recordFailed` (sidebar not saved
  or record write failed; logged, not shown).

**Step 4: App wiring**

- `AppSession` creates `ArchiveStore(database:)`, `SettingsStore(database:)` and the coordinator
  (`archiveState` and `importRecord` are both the `SettingsStore`, `persistSidebar` flushes the `SidebarAutosaver`); the `FaviconStore` comes from
  `AppEnvironment.faviconStore(in:)` (`@concurrent`). `window.onImportFromArc` calls `importFromArc()`.
- Availability: `refreshArcImportAvailability()` runs `ArcSourceFiles.isAvailable()` (`@concurrent`, existence only)
  in one cached `Task` at launch and each time `AppDelegate.validateMenuItem` validates "Import from Arc..."; the
  validation returns the cached value and the result updates `window.isArcImportAvailable` (empty-state button).
- Favicons at launch, in this order: prune (only when the launch outcome is `.opened`; a restored or re-created
  database is not the sidebar the favicons were written for), then the one launch load
  (`loadAll(for:)` of the loaded node ids, skipping ids in `FaviconWriter.touched`), then
  `writer.launchLoadDidComplete()`. Every `FaviconWriter` batch (engine changes, import favicons) is queued behind
  the prune task (`FaviconWriter(after:)`), so the prune never removes a favicon written after launch.
- `importFromArc()`: guarded by `canImportFromArc` (available and not running); `Task { outcome = try await
  coordinator.run(...); faviconWriter.save(outcome.favicons); window.sidebarController.setFavicons(outcome.favicons);
  log counts; showSummary(outcome.summary) }`, errors: toast "Couldn't import from Arc." and a log line with the
  error type and code only.
- `showSummary`: an `NSAlert` sheet titled "Imported from Arc" with `summary.lines` joined, for example
  "2 Spaces, 7 tabs, 1 folder, 1 split", "1 Space already in Arkt left unchanged",
  "1 Space imported before and removed in Arkt not restored", "1 Space from other Arc profiles added to the default
  profile", "2 favorites added, 1 already in Arkt, 2 imported before", "4 new archived items" (or "0 archived items:
  the Archive could not be imported" / "0 archived items: no Archive file"), "1 item could not be imported". A
  re-import of the same file starts with "0 new Spaces: all 2 Spaces from Arc are already in Arkt".
- `MainMenu`: File > "Import from Arc..." (no shortcut) targeting `AppDelegate.importFromArc(_:)` (forwards to the
  session), enabled through `validateMenuItem`.

**Step 5:** Core suite, CoreBridge filter and the full pure suite pass; App builds.

**Step 6: Commits** (as landed)

- Import from Arc: add missing Spaces, merge profiles, archive idempotently, favicons, counts-only summary
- Record the Arc ids each Arc import handled
- Arc re-import adds only items never imported before; keep the sidebar on a bad archive file; favicon launch fixes
- Record Arc import ids only after the merged sidebar is saved (persistSidebar)

---

### Task E5a: Archive coordinator (model first, outbox to the store)

**Files:**
- Modify: `$KIT/Sources/CoreBridge/ModelSidebarSource.swift` (archive / restore)
- Create: `$KIT/Sources/CoreBridge/ArchiveCoordinator.swift`, `ToastText.swift`
- Create: `$KIT/Tests/CoreBridgeTests/ArchiveCoordinatorTests.swift`, `ToastTextTests.swift`
- Modify: `$APP/App/AppSession.swift` (flush and needsFlush)

**Step 1: Failing tests**

`ArchiveCoordinatorTests` (fake store with injectable failures; manual sleeper like Track D's `ManualSleeper`):
- `archive([todayTab], reason: .manual)` removes it from the sidebar synchronously (`.structure(.today(space))`
  emitted, `onDidChange` once) and the fake store receives one `add` with `.replace` and `reason == .manual`,
  `section == .today`, `source == .space(space)`.
- Store failure: the item stays in `pendingItems`, `hasPendingWrites == true`, retried after the first backoff
  (1 s via the manual sleeper), then succeeds and `hasPendingWrites == false`.
- `flush()` with a failing store returns false within `flushTimeout` and keeps the item pending.
- `restore(item, fallbackSpace:)` inserts into the model (top of Today of the source Space; folders end of Pinned,
  BH-086, BH-090) and THEN calls `remove([item.id])`; a failing remove leaves the model restored (duplicate in store is
  allowed) and is not retried.
- `restore` with an id already in the sidebar restores under fresh ids (Archiver behavior surfaces through the adapter).
- `restore` throws `.noSpaceForRestore` when the sidebar has no Space.

`ToastTextTests`: `autoArchived(1) == "Auto archived 1 tab"`, `autoArchived(3) == "Auto archived 3 tabs"` (BH-085;
singular form [I]); `restored(kind: .tab, spaceTitle: "Work") == "Tab restored to Work. Click to view."`,
`.folder -> "Folder restored to Work. Click to view."` (BH-086), `.split -> "Split View restored to Work. Click to view."` [I],
favorites destination `"Tab restored to Favorites. Click to view."` [I].

**Step 2:** Run; expect compile errors.

**Step 3: Implement**

`ModelSidebarSource`:

```swift
  /// Archives nodes through `Archiver` (pure) and returns the entries; nodes are removed from the value in one
  /// mutation. Unknown ids are skipped.
  public func archive(_ ids: [UUID], reason: ArchiveReason, at date: Date) -> [ArchivedItem] {
    mutate { sidebar in ids.compactMap { try? Archiver.archive($0, from: &sidebar, reason: reason, at: date) } }
  }

  public func restore(_ item: ArchivedItem, fallbackSpace: UUID) throws -> RestoredItem {
    try mutate { try Archiver.restore(item, into: &$0, fallbackSpace: fallbackSpace) }
  }
```

`ArchiveCoordinator`:

```swift
@MainActor
public final class ArchiveCoordinator {
  public enum RestoreError: Error, Equatable { case noSpaceForRestore }
  nonisolated public static let retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(15), .seconds(30)]

  public private(set) var pendingItems: [ArchivedItem] = []
  public var hasPendingWrites: Bool { !pendingItems.isEmpty || writer != nil }

  public init(source: ModelSidebarSource, store: any ArchiveStoring, now: @escaping @MainActor () -> Date = { Date() },
              flushTimeout: Duration = .seconds(1),
              sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })

  @discardableResult
  public func archive(_ ids: [UUID], reason: ArchiveReason) -> [ArchivedItem] {
    let items = source.archive(ids, reason: reason, at: now())
    guard !items.isEmpty else { return [] }
    pendingItems += items
    startWriterIfNeeded()          // immediate, not debounced (decision 11)
    return items
  }

  public func restore(_ item: ArchivedItem, fallbackSpace: UUID?) throws -> RestoredItem {
    guard let fallback = fallbackSpace ?? source.sidebar.spaceOrder.first else { throw RestoreError.noSpaceForRestore }
    let restored = try source.restore(item, fallbackSpace: fallback)
    pendingItems.removeAll { $0.id == item.id }
    let store = self.store
    Task { try? await store.remove([item.id]) }   // failure leaves a harmless duplicate (Track D notes)
    return restored
  }

  /// Termination: one bounded attempt to write everything pending.
  public func flush() async -> Bool
  // writer loop: take a snapshot of pendingItems, add(.replace), on success drop exactly those ids,
  // on failure back off with retryDelays (last repeats); one writer at a time.
}
```

`AppSession`: create `archive = ArchiveCoordinator(source:store: archiveStore)`;
`needsFlush` becomes `autosaver.needsFlush || archive.hasPendingWrites`; `flush()` becomes

```swift
  func flush() async -> Bool {
    async let sidebarSaved = autosaver.flush()
    async let archiveSaved = archive.flush()
    return await sidebarSaved && archiveSaved
  }
```

**Step 4:** Filters pass, full pure suite passes, App builds.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/CoreBridge app/ArktShell/ShellKit/Tests/CoreBridgeTests app/ArktShell/App/AppSession.swift && git commit -m "Archive coordinator: model first, outbox to the archive store, restore"
```

---

### Task E5b: Cmd-W, visibility and engine cleanup in the window

**Files:**
- Modify: `$KIT/Sources/ShellUI/Window/ShellWindowController.swift`, `$APP/App/MainMenu.swift`, `$APP/App/AppSession.swift`
- Create: `$KIT/Tests/ShellKitGUITests/CloseTabTests.swift`

(See the E3b note: a removed current Space must hand activation to `tabToRestore(in:)` of the next Space.)

**Step 1: Failing GUI tests** (`StubSidebar.sample()` + `InMemoryEngine` or `FakeEngine`; the archive handler is a
closure that records ids and removes them from the stub through a test-only remove helper, or use
`ModelSidebarSource` directly since ShellKitGUITests may depend on CoreBridge; add the dependency if needed)

- Active Today tab, `closeTab(nil)`: `onArchive` receives `[tab]` (BH-071, KB-008); afterwards the next Today sibling
  below (else above) is current; with no sibling left, `currentTab == nil`, the card is empty and the window stays
  open (BH-073).
- Active pinned tab: `onArchive` is NOT called; the engine tab is closed (`engine.tabIDs` shrinks); the node stays in
  `.pinned` (BH-067); `currentTab == nil`.
- Active Favorite: same as pinned (BH-048 [I]).
- Active pane of a split in Today: `onArchive` receives the split root id (decision 9).
- No current tab: `closeTab` does nothing (BH-069 is NEEDS-RUNTIME-CHECK; not implemented).
- Removing a node that has an engine tab (from any cause) closes that engine tab (`.structure` observer).
- `onTabHidden` fires with the old node when another tab becomes current, and with the current node on
  `windowWillClose`; `visibleNodes` is `[current]` (empty when none).

**Step 2:** Run `--filter CloseTabTests`; expect compile errors.

**Step 3: Implement** (`ShellWindowController`)

```swift
  /// Today items to archive (the app's ArchiveCoordinator). Nil in tests that do not care.
  public var onArchive: (@MainActor ([NodeID]) -> Void)?
  /// A tab stopped being visible in this window (D4b: the app stamps lastActiveAt).
  public var onTabHidden: (@MainActor (NodeID) -> Void)?
  public var visibleNodes: Set<NodeID> { currentNode.map { [$0] } ?? [] }
  private var currentNode: NodeID? { currentTab.flatMap { nodeByTab[$0] } }

  /// Cmd-W (KB-008). Today: archive (BH-071). Pinned or Favorites: close the page, keep the item (BH-067, BH-048 [I]).
  @objc public func closeTab(_ sender: Any?) {
    guard let node = currentNode else { return }
    let target = splitRoot(of: node) ?? node
    switch sidebar.section(containing: target) {
    case .today(let space)?:
      let next = neighbor(of: target, in: .today(space))
      onArchive?([target])
      if let next { activate(node: next) }
    case .pinned?, .favorites?:
      closeEngineTabs(under: target)
    default:
      return
    }
  }
```

plus: `splitRoot(of:)` (parent is `.split(id)` -> `id`), `neighbor(of:in:)` (next sibling, else previous, resolved
before the archive), `closeEngineTabs(under:)` (the node, or each pane of a split: `engine.closeTab`; the existing
`.tabClosed` handler clears mappings and calls `sidebarController.deactivate`). A sidebar observation in `init`:
on `.structure`, close engine tabs whose node no longer exists (`tabsByNode.keys.filter { sidebar.node($0) == nil }`).
In `show(node:)`, before switching, `if let old = currentNode, old != node { onTabHidden?(old) }`; in
`windowWillClose`, `if let node = currentNode { onTabHidden?(node) }`.

`MainMenu` File menu: `item("Archive Tab", #selector(ShellWindowController.closeTab(_:)), "w")` (KB-008). Check that no
other item already uses Cmd-W (the window has no standard Close item today).

`AppSession`: `window.onArchive = { [weak self] ids in self?.archive.archive(ids, reason: .manual) }`;
`window.onTabHidden = { [weak self] id in self?.source.markInactive([id], at: .now) }`;
`prepareForTermination()` becomes `source.markInactive(window.visibleNodes, at: .now)`.

**Step 4:** GUI filter passes; pure suite passes; App builds. Manual: in the app, Cmd-W on a Today tab removes it, on a
pinned tab blanks the card and keeps the row.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/ShellUI/Window/ShellWindowController.swift app/ArktShell/ShellKit/Tests/ShellKitGUITests/CloseTabTests.swift app/ArktShell/ShellKit/Package.swift app/ArktShell/App && git commit -m "Cmd-W archives Today tabs and keeps pinned ones; stamp tabs when hidden"
```

---

### Task E5c: Archive window and restore

**Files:**
- Create: `$KIT/Sources/ShellUI/Archive/ArchiveWindowController.swift`
- Create: `$KIT/Sources/CoreBridge/ArchiveListModel.swift`, `$KIT/Tests/CoreBridgeTests/ArchiveListModelTests.swift`
- Create: `$KIT/Tests/ShellKitGUITests/ArchiveWindowTests.swift`
- Modify: `$APP/App/AppSession.swift`, `$APP/App/MainMenu.swift`

**Note (from E4c, decide here): favicons of archived nodes.** `AppSession.startFavicons` prunes
`<data dir>/Favicons` once at launch, keeping only the node ids in the loaded sidebar. An archived tab leaves the
sidebar, so its favicon is deleted at the next launch, and a restore (same node id) comes back with the letter
placeholder until the engine reports the favicon again. Decide whether archived node ids count as kept: either add
the archive's root ids (and their snapshot descendants) to the keep set, which needs an id-only archive query at
launch so the prune stays cheap, or accept the placeholder and document it. Whichever is chosen, the prune must
still run before any favicon write (`FaviconWriter(after:)`).

**Decided (E5c): archived node ids count as kept.** The launch prune keeps the sidebar's node ids plus the root and
snapshot-descendant ids of every readable archive entry (`CoreBridge.FaviconRetention.keptIDs`, one off-main
`items(matching:limit: nil)` read inside the prune task, so favicon writes still wait for it). An archive that cannot
be read skips the prune for that launch; unreadable rows contribute no ids (they can be neither shown nor restored).
No new store API: the read reuses `ArchiveStoring`. After a restore the app loads the restored subtree's favicons from
the folder, because the sidebar drops a node's cached favicon when the node leaves (also within one session). A
restore under fresh ids (the original id was taken) still shows the letter placeholder until the engine reports one.

**Step 1: Failing tests**

`ArchiveListModelTests` (fake store with 450 readable items and 3 unreadable rows):
- First `loadPage()` asks the store for `limit: 200` and returns 200 rows newest first, `unreadable` as reported,
  `mayHaveMore == true`.
- `loadMore()` asks for `limit: 400`; after the third call (`limit: 600`) `mayHaveMore == false` and 450 rows.
  (`ArchiveStore` exposes only `limit`, so paging re-queries with a growing limit; fine at Arc's ~1200 entries. A
  public cursor is a later optimization.)
- Row text: title from `ArchivedItem.title`; detail = URL host (or "Folder" / "Split View") + " - " + Space title (or
  "Little Arc", "Unknown Space") + " - " + relative date; reason "Closed" (manual) / "Auto archived" (auto).
- `restore(rowID)` calls the coordinator, drops the row locally, and returns the toast text; with no Space it returns
  nil and `canRestore == false`.

GUI: the window lists rows from a stub data source, shows "3 items could not be read" in the footer when
`unreadable == 3`, "Load More" visible only while `mayHaveMore`, double-click and the Restore button call `restore`.

Required GUI test (covers the E2b outline cache pruning): through `ModelSidebarSource`, a `SidebarController` shows a
folder (or split) with children, expanded; remove it (archive, or `mutate`), then insert a node under the SAME id with
a different title and different children (restore, or `mutate`). The outline must show the new title and children,
not the cached ones (`SidebarOutlineController` drops `items` and `containerChildren` for removed nodes).

**Step 2:** Run the filters; expect compile errors.

**Step 3: Implement**

ShellUI (no ArktCore types):

```swift
public struct ArchiveRow: Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var detail: String
  public var reason: String
}

@MainActor
public protocol ArchiveListDataSource: AnyObject {
  var canRestore: Bool { get }
  func loadPage() async -> (rows: [ArchiveRow], unreadable: Int, mayHaveMore: Bool)
  func loadMore() async -> (rows: [ArchiveRow], unreadable: Int, mayHaveMore: Bool)
  func restore(_ id: UUID)
}
```

`ArchiveWindowController`: a regular titled `NSWindow` (600x480, title "Archive"), an `NSTableView` in an
`NSScrollView` with one column of two-line cells (title, detail + reason), a bottom bar with "Restore" (enabled with a
selection and `canRestore`), "Load More", and the unreadable footer label. Opening it calls `loadPage()`; it reloads
when shown again. Not a hot path, but still AppKit (no SwiftUI list).

CoreBridge `ArchiveListModel: ArchiveListDataSource` holds the loaded `ArchivedItem`s by id, maps rows, and on
`restore` calls `ArchiveCoordinator.restore(item, fallbackSpace: currentSpaceProvider())`, then
`onRestored?(RestoredItem, toastText)`.

`AppSession`: `showArchive()` creates or fronts the window; `onRestored = { restored, text in
window.toasts.show(Toast(text: text, actionTitle: "View")) { window.activate(node: restored.nodeID) } }` (BH-086:
clicking focuses the item). `currentSpaceProvider = { window.currentSpace }` (restore falls back to it when the
source Space is gone; BH-157 routing is a later track).

`MainMenu`: Window menu (create it) > "Show Archive" with no key equivalent (KB-043: unbound by default; Cmd-Shift-L
stays reserved for the Library, KB-065).

**Step 4:** Filters pass; App builds. Manual: archive two tabs with Cmd-W, open Show Archive, restore one: it returns
to the top of Today in its Space and the toast's "View" activates it.

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/ShellUI/Archive app/ArktShell/ShellKit/Sources/CoreBridge/ArchiveListModel.swift app/ArktShell/ShellKit/Tests app/ArktShell/App && git commit -m "Add a minimal Archive window with paging and restore"
```

---

### Task E5d: Auto-archive timer

**Files:**
- Modify: `$KIT/Sources/CoreBridge/ArchiveCoordinator.swift`, `$KIT/Tests/CoreBridgeTests/ArchiveCoordinatorTests.swift`
- Modify: `$APP/App/AppSession.swift`

**Step 1: Failing tests**

```swift
  @Test func autoArchiveUsesPolicyClampAndExemptions() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let (source, ids) = Self.sidebarWithTodayTabs(idleHours: [13, 2, 40], pinnedIdleHours: [400], now: now)
    let coordinator = ArchiveCoordinator(source: source, store: FakeArchiveStore(), now: { now })
    let archived = coordinator.runAutoArchive(
      startedAt: now.addingTimeInterval(-100 * 3600), settings: ArchiveSettings(), exempt: [ids.today[2]])
    #expect(archived.map(\.id) == [ids.today[0]])                    // 13 h idle; 2 h too fresh; 40 h exempt; pinned never
    #expect(archived.allSatisfy { $0.reason == .auto })
  }

  @Test func startedAtClampProtectsFreshImports() {
    // all Today tabs idle 400 h, startedAt = now - 1 h: nothing archived (decision 7)
  }

  @Test func perProfileThreshold() {
    // Space in profile "work" with threshold oneHour archives a 2 h idle tab; default profile (12 h) keeps it
  }
```

**Step 2:** Run; expect compile errors.

**Step 3: Implement**

```swift
  /// One auto-archive pass (BH-080, BH-084, BH-054, BH-048, BH-083). Returns what was archived; the caller shows the
  /// BH-085 toast when non-empty.
  @discardableResult
  public func runAutoArchive(startedAt: Date, settings: ArchiveSettings, exempt: Set<UUID>) -> [ArchivedItem] {
    let input = AutoArchiveInput(now: now(), startedAt: startedAt, exempt: exempt,
                                 threshold: { settings.tabThreshold(forProfile: $0) })
    let ids = AutoArchivePolicy.itemsToArchive(in: source.sidebar, input)
    return archive(ids, reason: .auto)
  }
```

`AppSession.start` (after the window is up):

```swift
    Task {
      do {
        startedAt = try await settingsStore.resolveAutoArchiveStart(now: .now)
        archiveSettings = try await settingsStore.loadArchiveSettings()
      } catch { Self.log.error("archive settings unavailable \(String(describing: type(of: error)), privacy: .public)"); return }
      autoArchiveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.autoArchiveTick() }
      }
      autoArchiveTimer?.tolerance = 10
      autoArchiveTick()
    }

  private func autoArchiveTick() {
    guard let startedAt else { return }
    // BH-076: media-playing tabs are exempt. EngineClient has no audio state yet (FakeEngine cannot report it);
    // add `EngineEvent.audibleChanged` with ChromiumEngine and union those node ids here.
    let archived = archive.runAutoArchive(startedAt: startedAt, settings: archiveSettings, exempt: window.visibleNodes)
    if !archived.isEmpty { window.toasts.show(Toast(text: ToastText.autoArchived(archived.count))) }   // BH-085
  }
```
After an Arc import with `summary.spaces > 0` (the run added a Space, so it reset the clock), set `startedAt` to the coordinator's reset date (re-read with
`resolveAutoArchiveStart`) so the running timer uses the new clock immediately.

**Step 4:** Filters pass; App builds. Manual (Debug, scratch data dir): set the profile threshold through a temporary
debug line or wait is impractical, so rely on the tests; only check that no toast appears in the first minute after a
fresh import (clock reset).

**Step 5: Commit**

```zsh
cd $REPO && git add app/ArktShell/ShellKit/Sources/CoreBridge/ArchiveCoordinator.swift app/ArktShell/ShellKit/Tests/CoreBridgeTests app/ArktShell/App/AppSession.swift && git commit -m "Run auto-archive every minute with per-profile thresholds and the import clock"
```

---

### Task E6: End-to-end smoke (empty DB, import, quit, relaunch)

**Files:**
- Modify: `$APP/App/AppEnvironment.swift`, `$APP/App/AppSession.swift` (DEBUG-only smoke hooks)
- Create: `docs/plans/2026-10-23-track-e-results.md`

**Step 1: DEBUG smoke hooks.** In `AppEnvironment`, `#if DEBUG` only:
`static var smokePhase: String? { ProcessInfo.processInfo.environment["ARKT_SMOKE"] }` (`import` or `verify`). In
`AppSession.start`, when set:
- `import`: run `importFromArc()` without the summary sheet, then print one line and call `NSApp.terminate(nil)` (so the
  quit takes the real `applicationShouldTerminate` + flush path).
- `verify`: print one line and terminate.
- Both phases first `await lastBackup?.value` (E3c) so the launch backup lands before the quit; otherwise smoke steps 3
  and 6 (which need that backup) race `NSApp.terminate`.

The line is counts and case names only:

```
ARKT_SMOKE phase=verify outcome=opened spaces=3 tabs=12 folders=2 splits=1 favorites=2 archive=4 added=- existing=- archiveAdded=-
```
(`archive` comes from `ArchiveStore.items(limit: nil).items.count`; `outcome` is the `OpenOutcome` case name. On
the `import` phase `added`, `existing` and `archiveAdded` are the run's `summary.spaces`, `summary.existingSpaces`
and `summary.archiveImported`; `verify` prints `-`. Spaces of other Arc profiles are merged into the default
profile, so `spaces` counts them.)

**Step 2: Build Debug** (App command). Expected `** BUILD SUCCEEDED **`.

**Step 3: Run the smoke** (GUI session required; the app shows its window briefly each time)

```zsh
SMOKE=$(mktemp -d); BIN=$DD/Build/Products/Debug/ArktShell.app/Contents/MacOS/ArktShell
mkdir -p $SMOKE/arc $SMOKE/data
cp $CORE/Tests/ArcImportTests/Fixtures/StorableSidebar-synthetic.json $SMOKE/arc/StorableSidebar.json
cp $CORE/Tests/ArcImportTests/Fixtures/StorableArchiveItems-synthetic.json $SMOKE/arc/StorableArchiveItems.json
shasum -a 256 $SMOKE/arc/*.json > $SMOKE/arc.sha256

# Expected counts from the counts-only CLI, on the synthetic copy (never the real Arc folder):
cd $CORE && nice -n 20 swift run -j 2 arkt-import-check $SMOKE/arc/StorableSidebar.json

# 1. Empty database: created, nothing seeded, no backup.
ARKT_DATA_DIR=$SMOKE/data ARKT_SMOKE=verify $BIN
ls $SMOKE/data/Backups 2>/dev/null | wc -l

# 2. Import through the debug path, quit through applicationShouldTerminate.
ARKT_DATA_DIR=$SMOKE/data ARKT_ARC_DIR=$SMOKE/arc ARKT_SMOKE=import $BIN

# 3. Relaunch: state restored, one backup written after the load.
ARKT_DATA_DIR=$SMOKE/data ARKT_SMOKE=verify $BIN
ls $SMOKE/data/Backups | wc -l
sqlite3 $SMOKE/data/Arkt.sqlite 'SELECT COUNT(*) FROM archived_item'

# 4. Re-import is idempotent: sidebar skipped, archive writes 0, counts unchanged.
ARKT_DATA_DIR=$SMOKE/data ARKT_ARC_DIR=$SMOKE/arc ARKT_SMOKE=import $BIN
ARKT_DATA_DIR=$SMOKE/data ARKT_SMOKE=verify $BIN

# 5. Arc copy untouched.
shasum -a 256 -c $SMOKE/arc.sha256

# 6. Corruption fallback.
printf 'not a database' > $SMOKE/data/Arkt.sqlite
ARKT_DATA_DIR=$SMOKE/data ARKT_SMOKE=verify $BIN
ls $SMOKE/data | grep -c 'corrupt'
```

Expected:
1. `outcome=created spaces=0 ... archive=0`, and `0` backups.
2. `phase=import ... added=N existing=0` with N and spaces/tabs/folders/splits matching the CLI's section totals,
   and `archive` and `archiveAdded` matching the CLI's `archive imported` line.
3. `outcome=opened` with the same counts as step 2; `1` backup; the `sqlite3` count equals `archive`.
4. Re-import adds only Arc items never imported before, and the copy is unchanged, so the import line shows
   `added=0 existing=N archiveAdded=0` with every count (Favorites included) equal to step 3; the verify line
   matches step 3.
5. Every line `OK`.
6. `outcome=restoredFromBackup` with the same counts; `1` quarantined file.

Then the two manual checks from E3c step 6 (quit within the debounce window; recovery toast visible) on this build, and
`rm -rf $SMOKE`.

**Step 4: Final verification**

```zsh
cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -3
cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -3
cd $KIT && nice -n 20 swift test -j 2 --filter ShellKitGUITests 2>&1 | tail -3
# the WebKit isolation grep from the Track C plan: no output
cd $REPO && git status --short
```
Expected: all pass; `git status` shows only the results file (no `build/`, `.build/`, `ArktShell.xcodeproj`,
`Info.plist`, no local tool directories staged).

**Step 5: Record results** in `docs/plans/2026-10-23-track-e-results.md`: date, machine, macOS build, whether the
Chromium build was running, E0 baselines and final test counts, the six `ARKT_SMOKE` lines, the CLI counts, the two
manual checks (pass/fail), and any deviations from this plan.

**Step 6: Commit**

```zsh
cd $REPO && git add app/ArktShell/App docs/plans/2026-10-23-track-e-results.md && git commit -m "Add debug smoke hooks and record the Track E smoke run"
```

**Step 7: Housekeeping** (mandatory after the run): kill any app instance the smoke left running (by PID from
`pgrep -x ArktShell`), remove `$SMOKE` if still present, and leave the `track-e` worktree for review; after the merge
into `spike/week1`, `git worktree remove ../arkt-wt/track-e`, `git worktree prune`, `git branch -d track-e`.

---

## Out of scope (next tracks)

- `ChromiumEngine` (replaces `FakeEngine` in `AppDelegate.launch`), media state for BH-076, per-frame engine event
  batching.
- Profile switching in the window (Spaces of non-default Arc profiles are merged into the default profile for now,
  decision 12).
- Drag and drop, moves, renames, Space deletion, the C3 removal/move follow-ups beyond cache pruning.
- Clear / Archive Below / multi-select archive (BH-075, BH-077, BH-078, BH-072), Cmd-Shift-T (BH-074), archive search
  and filters UI (BH-087, BH-088, Unicode search follow-up), Clear Archive, education banner (BH-089).
- Split pane removal (BH-122, BH-123), Air Traffic Control restore routing (BH-157), Little Arc archive (BH-137, BH-138).
- Window/session restore (BH-173, data-model section 3, Track D open question 11), per-window expanded folders (BH-098).
- Importing Arc passwords, cookies, history, extensions (design 4 step 3) and Arc's per-profile thresholds (Track D
  open question 8).
- Settings UI for "Archive tabs after" (BH-081 to BH-083); the Default-profile "only this Profile" UI follow-up.

## Open questions (product decisions)

1. Resolved (User decisions 1): Arc import resets the auto-archive clock to the import time.
2. Resolved (User decisions 2 and 5): a re-import imports the archive and adds only Arc Spaces and Favorites never
   imported before; items deleted in Arkt are not restored.
3. First-run wording and naming: the empty-state text, and the name of a Space created by "New Space" or by Cmd-T with
   no Space (placeholder "Space").
4. Cmd-W on a split pane archives the whole split until BH-123 is checked in Arc; Cmd-W on a Favorite closes the page
   and keeps it (like pinned). Confirm both.
5. Resolved (User decisions 3): Spaces and Favorites from non-default Arc profiles are merged into the default
   profile.
6. Favicons imported from Arc live in Arkt's data folder and are not part of database backups. Acceptable?
7. Recovery notices stay until dismissed; "Show Files" reveals Arkt's data folder. Acceptable, or should it be a sheet?
8. The Archive window is reached from Window > Show Archive with no shortcut (KB-043). Confirm, given Cmd-Shift-L is
   kept for the Library (KB-065).

## User decisions (2026-10-23)

1. Arc import resets the auto-archive clock to the import time (`SettingsStore.resetAutoArchiveStart(to: importTime)`).
2. Re-import when Arkt already has Spaces: import the archive AND add Arc Spaces that Arkt doesn't have yet (matched by the fixed Space ids from E4a), with their pinned/Today/folder trees; existing Spaces are left untouched, nothing is duplicated.
3. Spaces from non-default Arc profiles are merged into the default profile (shown immediately; they lose separate cookies/logins). Their favorites merge into the default profile's favorites without duplicates.
4. Cmd-W on a split pane closes/archives only that pane; the split shrinks (a split left with one pane becomes a plain tab). Cmd-W on a Favorite closes the page and keeps the Favorite, like a pinned tab (BH-067). Mark the pane rule PARITY(NEEDS-RUNTIME-CHECK BH-123).
5. Re-import adds only Arc items never imported before; items deleted in Arkt are not restored.
Other open questions use the plan's defaults (first-run copy and new Space name "Space" placeholder; favicons in the data folder but not in DB backups; recovery notices are non-blocking toasts with "Show Files"; "Show Archive" in the Window menu without a shortcut).
