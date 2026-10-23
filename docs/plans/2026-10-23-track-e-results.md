# Track E results: end-to-end smoke (E6)

| | |
|---|---|
| Date | 2026-10-23 |
| Machine | Apple silicon MacBook Pro (`Mac14,9`, 10 cores) |
| macOS | 27.0 (26A428) |
| Toolchain | Xcode 27.1 (27A9275), Swift 6.4 |
| Chromium build | not running (no `ninja` / `siso`); other Swift builds were, load 15-30 |
| Base | `main` at `3642311` (E1 to E5d merged), rebased onto `0c0a3f3` before the PR |
| Builds | Debug and Release, `nice -n 10 xcodebuild ... -jobs 4`, both `** BUILD SUCCEEDED **` |

## Test counts

E0 baselines were not recorded in a results file, so the baseline is `main` at `3642311`, run in this worktree before
any E6 change. Swift Testing counts `@Test` functions; `swift test` prints one total per test product, summed here.

| Suite | Baseline | Final | Delta |
|---|---|---|---|
| ArktCore `swift test` | 316 | 316 | 0 |
| ShellKit `swift test --skip ShellKitGUITests` | 312 | 328 | +15 from `main` (`BrandTokensTests`, #140), +1 (`ArchiveListModelTests`, overlapping loads) |
| ShellKit `swift test --filter ShellKitGUITests` (XCTest) | 172 | 173 | +1 (`ArchiveWindowTests`, Escape closes) |

All pass, before and after the rebase. The WebKit isolation grep from the Track C plan prints nothing.

## Smoke hooks

`ARKT_SMOKE=import|verify` (Debug only, `#if DEBUG` in `App/AppEnvironment.swift` and `App/AppSession.swift`; the
scripted UI smoke `-ArktSmoke YES` is separate and untouched). Each phase awaits the launch backup, imports on
`import` (no summary sheet), prints one line of counts and case names, and quits through `NSApp.terminate`, so the
quit takes `applicationShouldTerminate` and the flush.

Release check: `strings -a` on the Release `ArktShell` binary finds none of `ARKT_SMOKE`, `phase=`, `smokePhase`,
`SmokePhase`, `SmokeRunner`, `ArktSmoke`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` (0 matches each). As a control, the same
check finds `ARKT_SMOKE` 5 times in the Debug `ArktShell.debug.dylib`.

## Expected counts (counts-only CLI on the synthetic copy)

`swift run arkt-import-check $SMOKE/arc/StorableSidebar.json` (the fixture copies, never the real Arc folder):

```
spaces: 2 (report: 2)
favorites: tabs 2, folders 0, splits 0
pinned: tabs 5, folders 1, splits 1
today: tabs 2, folders 0, splits 0
imported totals (report): tabs 9, folders 1, splits 1
skipped: 1
  unsupportedKind: 1
warnings: 0
favicons (imported tabs): found 0, missing 9
archive entries: 10
archive imported: 7 (manual 5, auto 2)
archive sources: space 4, little arc 1, unknown 2
archive skipped: 3
  decodeFailed: 1
  invalidURL: 1
  unsupportedKind: 1
archive warnings: 2
  archiveSpaceNotImported: 1
  unsupportedValue: 1
```

So: `spaces=2 tabs=9 folders=1 splits=1 favorites=2`, `archive=7`.

## Smoke run

Run five times on fresh `mktemp -d` folders (two on the first hook build, two on the final build with the
follow-ups and the `toast=` field, one more after the rebase). Each phase sets `ARKT_DATA_DIR=$SMOKE/data` and
`ARKT_ARC_DIR=$SMOKE/arc` (also on
`verify`, so no phase looks at the real Arc folder) and runs under a 60 s `perl` alarm. Every phase exited 0 within
1 s. The five runs printed the same outcomes and counts (the first two without `toast=`); final run 2:

```
1  ARKT_SMOKE phase=verify outcome=created spaces=0 tabs=0 folders=0 splits=0 favorites=0 archive=0 added=- existing=- archiveAdded=- toast=none
   backups=0
2  ARKT_SMOKE phase=import outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=2 existing=0 archiveAdded=7 toast=none
3  ARKT_SMOKE phase=verify outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=- existing=- archiveAdded=- toast=none
   backups=1 sqlite_archived_item=7
4  ARKT_SMOKE phase=import outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=0 existing=2 archiveAdded=0 toast=none
   ARKT_SMOKE phase=verify outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=- existing=- archiveAdded=- toast=none
5  StorableArchiveItems.json: OK
   StorableSidebar.json: OK
6  ARKT_SMOKE phase=verify outcome=restoredFromBackup spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=- existing=- archiveAdded=- toast=persistent
   quarantined=1
```

| Step | Expected | Result |
|---|---|---|
| 1 | `outcome=created`, zero counts, no backup | PASS |
| 2 | counts match the CLI; sidebar imported (`added=2`), `archiveAdded=7` | PASS |
| 3 | `outcome=opened`, same counts, one backup, `sqlite3` count = `archive` | PASS |
| 4 | re-import idempotent: `added=0 existing=2 archiveAdded=0`, counts unchanged | PASS |
| 5 | Arc fixture checksums unchanged | PASS |
| 6 | `outcome=restoredFromBackup`, same counts, one quarantined file | PASS |

## Manual checks (E3c step 6)

Not performed by a person in this run (they need keyboard input, and this run drove the app in-process only).
What the automated run shows instead:

- Quit with unsaved changes: in steps 3, 4 and 6 the quit takes the `.terminateLater` path (stamping the visible
  tabs makes `needsFlush` true), the flush completes in the nested run loop, the process exits 0, and the next
  launch sees the same counts. The exact manual case (Cmd-T, Enter, Cmd-Q inside the 500 ms debounce) is still open.
- Recovery toast: step 6 reports `toast=persistent`, the presenter's current toast after a `restoredFromBackup`
  launch. That is the model state, not a look at the screen; seeing it on screen is still open.

## Deviations from the plan

- Capacity: `nice -n 10` and `-j 4` instead of `nice -n 20` and `-j 2`, as instructed for this run.
- The issue's acceptance criteria name `sidebarImported=yes|no`; the plan's line has `added=` / `existing=`, which
  this follows. `added>0` is "sidebar imported", `added=0 existing=N` is "skipped".
- Extra field `toast=none|timed|persistent` (case names only), for the recovery toast evidence above.
- Step 2 reports `outcome=opened`, not `created`: step 1 already created the (empty) database.
- `ARKT_ARC_DIR` is set on `verify` phases too (the plan sets it only on `import`), so the launch's existence check
  never looks at the real Arc folder.
- The hooks are `#if DEBUG` only, so they run on the Debug binary, not Profile.
- Finding, fixed in the hook: calling `NSApp.terminate(nil)` directly from the main-actor smoke Task deadlocked
  whenever `applicationShouldTerminate` returned `.terminateLater` (steps 3, 4, 6 hung until the alarm, exit 142).
  `terminate` waits in a nested run loop for the flush Task, which cannot start on the main actor while the calling
  job is still running. The hook now schedules `terminate` from the run loop
  (`perform(_:with:afterDelay: 0)`), like a menu Quit. Any future code that quits from inside a main-actor Task
  needs the same treatment; today's only other caller (`presentLaunchFailure`) has no session, so it gets
  `.terminateNow`.

## Review follow-ups (separate commit)

- Archive window: Escape (`cancelOperation:`) closes it via `performClose`, and `NSApp.windowsMenu` is the Window
  menu, so open windows are listed there.
- The overlapping-loads generation check moved from `ArchiveWindowController` into `ArchiveListModel`: a load that a
  newer one overtook leaves the model's rows and restorable items alone and reports the current state.

## Archive window: entries still in the outbox (#88)

Follow-up to E5c (#49, "Not done"). Base `main` at `772f94c`; `nice -n 10`, `-j 4`.

- `ArchiveListModel` lists the coordinator's `pendingItems` with every page: merged with the store's items newest
  first, one row per id (the newer entry wins). The pending list is read before the store read, so an entry whose
  write lands during the read is never missing from both. When the store read fails (the usual reason entries sit
  in the outbox), the pending entries are listed with the rows of the last read that succeeded, and the footer
  reports the failure. A pending row restores through the coordinator like any other row.
- `ArchiveCoordinator.onPendingItemsChange` fires on an archive, a restore that drops a pending entry, and a landed
  write. The model sets it and passes it on as `ArchiveListDataSource.onChange`; the window refreshes while on screen
  (`refresh()` re-reads at the loaded depth, so "Load More" pages stay) and keeps the selected row selected.
- Restoring a pending entry whose add was never sent (queued behind a write in flight or a retrying remove) drops it
  from the outbox without a store remove. When an add holding the id was sent (in flight, failed, written) or a
  remove of the id failed, the entry may be in the store, so the restore still queues a remove, as before.

Baselines run on `main` at `772f94c` before this change; all pass, before and after.

| Suite | Baseline | Final | Delta |
|---|---|---|---|
| ShellKit `swift test --skip ShellKitGUITests` | 392 | 404 | +3 `ArchiveCoordinatorTests`, +9 `ArchiveListModelTests` |
| ShellKit `swift test --filter ShellKitGUITests` (XCTest) | 240 | 243 | +3 `ArchiveWindowTests` |
| ArktCore | not touched | | |

Debug app build: `** BUILD SUCCEEDED **`. No change to `AppSession.swift`: the model wires itself to the coordinator.

## Manual checks pending (#26)

Quit within the save window and the recovery toast: pending. It needs a Debug build, because the Release build ignores
`ARKT_DATA_DIR`. See "Manual checks (#26)" in `2026-10-22-track-c-results.md`.

## Archive window: Restore after a Space is created (#89)

Follow-up to E5c (#49, "Not done"). Base `main` at `a79d75f`; `nice -n 10`, `-j 4`.

- `ArchiveListModel` observes its `ModelSidebarSource` and passes `.spaces` changes on as `onChange`, like the
  outbox changes from #88. The window refreshes while on screen, and `apply` re-evaluates Restore, so a Space created
  with the window open enables Restore without a selection change. The refresh also re-words the rows' Space titles.
  Tab changes (`.structure`, `.node`) are not passed on, so tab edits cause no store read.
- Built on the existing `.spaces` change; no Space-level event API from #86 is needed or added. When #86 splits
  `.spaces` into finer events, this observer matches the ones that change `spaceOrder` or a Space's title.

Baselines are the final counts minus the new tests; all pass.

| Suite | Baseline | Final | Delta |
|---|---|---|---|
| ArktCore `swift test` | 336 | 336 | not touched |
| ShellKit `swift test --skip ShellKitGUITests` | 424 | 425 | +1 `ArchiveListModelTests` |
| ShellKit `swift test --filter ShellKitGUITests` (XCTest) | 310 | 311 | +1 `ArchiveWindowTests` |

Debug app build: `** BUILD SUCCEEDED **`. No change to `AppSession.swift`.

## Archive window and restore: robustness follow-ups (#91)

Suggestions 1, 2, 4, 5 and 6 of the #49 review. `nice -n 10`, `-j 4`.

- Overlapping loads: already handled since E6 (#143), where the `generation` guard moved into `ArchiveListModel`
  and only the newest load sets `limit`. A regression test now covers the review's case: a "Load More" that returns
  after a later reload leaves the limit at 200, so the next "Load More" asks for 400.
- Favicon reads: `FaviconWriter.loadStored(_:)` replaces the launch-only `touched` set. Each read leaves out the ids
  reported (engine record or import save) from the call until it returns, so both the launch load and the restore
  load (`AppSession.didRestore`) skip ids whose newer favicon the sidebar already has. Tracking no longer stops after
  launch.
- The launch load no longer waits for the prune: the prune keeps every sidebar id and `FaviconStore` runs one call at
  a time, so the archive-wide decode is off the launch favicon path. Writes still wait for the prune.
- A restore the sidebar model refuses (`SidebarError`) calls `ArchiveListModel.onRestoreFailed`; the app shows the
  toast "Couldn't restore from the Archive." and the row stays.
- `ArchiveRowCellView` is one accessibility element (role cell) labelled "title, place - date, reason"; the two text
  fields and their cells are hidden from accessibility.
- Not done: the id-only `ArchiveStoring` query. The review ties it to archives well past about 10k entries; Arc
  archives are about 1200, and the prune no longer delays the launch load.

Baselines are the counts on `main` before the change; final counts are after rebasing on #208, #209 and the other merges
of the day (they added tests of their own).

| Suite | Baseline (`40ddc42`) | Final | Delta from this change |
|---|---|---|---|
| ArktCore `swift test` | 336 | 342 | not touched |
| ShellKit `swift test --skip ShellKitGUITests` | 433 | 452 | +2 `ArchiveListModelTests`; `FaviconWriterTests` 2 replaced |
| ShellKit `swift test --filter ShellKitGUITests` (XCTest) | 317 | 341 | +1 `ArchiveWindowTests` |

Debug app build: `** BUILD SUCCEEDED **`.
