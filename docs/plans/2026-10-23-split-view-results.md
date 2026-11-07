# Split View results

Plan: `docs/plans/2026-10-23-split-view.md`, S9. Issue #27 is closed as an umbrella; its acceptance items are owned by #59 and recorded below. The divider frame-time numbers are pending: maintainer run on an idle 120 Hz machine.

## S0 baselines

As recorded in PR #141 at `9bf54f2`: ArktCore 316 Swift Testing tests, ShellKit non-GUI 312 Swift Testing tests, and ShellKit GUI 172 XCTest tests.

## S9: divider pacing (#59)

- Initial red: `swift test -j 2 list` failed because the new pacing test could not access `FrameScript`, then the existing frame helpers were moved to `FrameTestSupport.swift` and the build succeeded.
- `cd app/ArktCore && swift test -j 2`: 428 tests passed after merging main (S0 baseline 316; the difference includes intervening work).
- `cd app/ArktShell/ShellKit && swift test -j 2 --skip ShellKitGUITests`: 1,237 tests passed after merging main (S0 baseline 312; the difference includes intervening work).
- `swift test --skip-build --filter SplitPacingTests` (before merging main): 5 executed, 3 skipped, 0 failures. The deterministic commit check and FakeEngine informational run passed. The three gated InMemoryEngine scenarios were NOT-MEASURABLE: load 22.83 on 12 cores.
- `swift test --skip-build --filter SpacePagerTests` (before merging main): 22 executed, 1 skipped, 0 failures. The frame-pacing test was not measurable under load.
- `swift test --skip-build --filter SplitPacingTests.testDividerDragCommitsOnce`, 20 consecutive runs under load: 20 passed; load immediately after was 17.62 on 12 cores. Removing the `onCommitFactors` call in `SplitContainerView.endDividerDrag` made that test fail (observed 0 writes, expected 1); restoring it made the test pass.
- FakeEngine informational (`split-divider-webkit`): screen maximum 240 Hz, 29 intervals, 0 over 8.6 ms, max and p99 8.33 ms, load 22.83 on 12 cores. This is not a gated timing result.
- Post-merge `swift test -j 2 --filter SplitPacingTests`: 5 executed, 3 skipped, 0 failures. The gated cases were NOT-MEASURABLE at load 22.20 on 12 cores; FakeEngine reported 29 intervals, 0 over 8.6 ms, max 8.33 ms, 240 Hz (informational only).
- Post-merge `swift test -j 2 --filter ShellKitGUITests`: 1,088 executed, 20 skipped, 0 failures. The three divider gates were NOT-MEASURABLE at load 19.09 on 12 cores; the SpacePager timing test also skipped. These runs predate the merge of #665 and the gate convention below.

### Gate convention (after merging #665)

The three gated cases follow the shared rule in `PacingEnvironment` (#602, #665, #671):

- `skipIfNotMeasurable` skips a case as NOT-MEASURABLE below 120 Hz or at a 1-minute load at or above the active core count. The pull request's own load check was removed.
- Every case measures, prints its `split.pacing` summary line and attaches it. The hitch count (no frame over 8.6 ms, threshold unchanged) is asserted only when `PacingEnvironment.gateAsserts(for: SplitPacingTests.self)` is true: with `ARKT_PACING_GATE=1`, or when `SplitPacingTests` runs alone.
- Since #665, `beginDividerDrag` ends a running reflow and closes its "split-reflow" pacing session into the same `lastPacing`. Each case now asserts that no reflow runs when the drag begins, that the pacer's session is "split-divider" during and after the drag, and that the drag changed `liveFactors`, so the stats read are the drag's own and the divider really moved. `testDividerDragCommitsOnce` asserts the same preconditions.

### After merging main again (2026-11-07, gate convention applied)

- `swift test -j 2 --filter SplitPacingTests` (the class alone, so `gateAsserts` is true): 5 executed, 0 failures, 0 skipped. Developer machine, screen maximum 120 Hz, 10 cores, 1-minute load 8.73 to 9.15 (other builds running, not idle): `split-divider-2`, `split-divider-4` and `split-divider-4-stacked` each 59 frames, 0 over 8.6 ms, max and p99 8.33 ms, `asserted=yes`; the stacked case was not skipped, so its container reached 990 pt, and its drag changed the factors. FakeEngine informational: 59 frames, 0 over 8.6 ms, max 8.33 ms. These are a local check, not the recorded gate result.
- `swift test --skip-build --filter SplitPacingTests.testDividerDragCommitsOnce`, 20 consecutive runs: 20 passed, load 7.69 before and 6.40 after on 10 cores. Replacing the `onCommitFactors` call in `SplitContainerView.endDividerDrag` with nothing made it fail (0 writes, expected 1); restoring it made it pass.
- `cd app/ArktShell/ShellKit && swift test -j 2 --skip ShellKitGUITests`: 2,432 Swift Testing tests passed, 0 failures (sum of the package's test runs). `cd app/ArktCore && swift test -j 2`: 576 passed, 0 failures. The full GUI suite is left to CI.

### Measurement (pending)

Pending: maintainer run on an idle 120 Hz machine. Command, run alone so nothing earlier in the process lands in the measured frames:

```zsh
cd app/ArktShell/ShellKit
ARKT_PACING_GATE=1 swift test --filter SplitPacingTests
```

Record each `split.pacing` line (`split-divider-2`, `split-divider-4`, `split-divider-4-stacked`, and the informational `split-divider-webkit`): `screenMaxFPS`, `frames`, `over8.6`, `maxMs`, `p99Ms`, `load1`, `cores` and `asserted=yes`. A case that prints NOT-MEASURABLE has not been measured.

| Case | screenMaxFPS | frames | over 8.6 ms | max ms | p99 ms | load1 / cores |
|---|---|---|---|---|---|---|
| split-divider-2 | pending | pending | pending | pending | pending | pending |
| split-divider-4 | pending | pending | pending | pending | pending | pending |
| split-divider-4-stacked | pending | pending | pending | pending | pending | pending |

### Plan deviation

Four stacked panes need at least 990 pt for four 240 pt minima plus three 10 pt gaps. The planned 1200 x 800 window cannot resize them: `SplitLayout.factors` returns equal shares. The stacked test requests a 1200 x 1100 window and skips if its split container stays under 990 pt; on the maintainer run, the stacked window should reach 990 pt (check that the case is not skipped for that reason). The other cases keep 1200 x 800. The case now fails if the scripted drag leaves the factors unchanged.

### Keys

S5 uses Ctrl-Shift-= to add (KB-070), Ctrl-Shift-- to close the pane (KB-071), Ctrl-Shift-1 through 4 to focus a pane (KB-072), and Ctrl-Shift-[ / ] for previous / next (KB-073, RT-06). KB-074 is Cmd-L on the focused pane. KB-075's Separate Page from Split View and Expand Current Split are menu items, unbound by default as in the reference. Key equivalents are the unshifted US character with Control-Shift (`SplitMenu`); other keyboard layouts (German, French) are a recorded risk, not a gate.

## #27 acceptance checklist (owned by #59)

- [x] Behavior rules BH-115 to BH-128 implemented or explicitly deferred: see the table below.
- [x] Shortcuts KB-070 to KB-075 bound: see Keys above (`SplitMenu`, `SplitShortcutTests`, `MainMenuKeyEquivalentTests`).
- [ ] Divider resize meets the frame-time gate: pending the maintainer run above.

### BH-115 to BH-128 disposition

| ID | Status | Where |
|---|---|---|
| BH-115 | Implemented: one sidebar item in Pinned, Today, a folder or Favorites, movable. Deferred: renaming a split (the Rename item is shown disabled) and drawing a split as a Favorites tile (`FavoritesGridView` draws tabs only); neither has an issue yet | S1, S2, S6 |
| BH-116 | Implemented: a 5th pane does nothing and shows "Cannot Add New Pane" | S1, S2, S5, S7 |
| BH-117 | Implemented: Ctrl-Shift-=, drag a sidebar tab onto the content, Opt-click the current tab (GS-032), Add Right / Left / Top / Bottom Split. Deferred: multi-select Open in Split View and the plus-menu New Split | S5, S6, S7 |
| BH-118 | Implemented: drop a tab onto another sidebar tab (GS-010) | #104 |
| BH-119 | Implemented: a split made from a Pinned tab stays in Pinned | S1 |
| BH-120 | Implemented: Convert to Horizontal / Vertical Split View | S1, S5, S6 |
| BH-121 | Implemented: Separate All Tabs (menu, Opt-click on the split row) and Remove Tab from Split View | S1, S6 |
| BH-122 | Implemented: Ctrl-Shift-- takes the focused pane out, after the split [I]; RT-21 open | S1, S5 |
| BH-123 | Implemented: Cmd-W archives or closes only the focused pane; RT-21 and RT-36 open | S4, S8 |
| BH-124 | Implemented: Expand Current Split and Separate Page from Split View | S1, S5 |
| BH-125 | Implemented: each pane's Toolbar shows its URL; Cmd-L edits the focused pane | S4 |
| BH-126 | Implemented: Duplicate Split View (S6), Mute per pane (#364), Archive Below on a pane row. Deferred: Share and Share Split View are shown disabled (#362) | S6, #364, #362 |
| BH-127 | Not planned: Opt-click on a split's close button acts like a plain click; the reference gates it behind a flag and Arkt keeps it off (decision 2026-11-05, #83) | #83 |
| BH-128 | Implemented: Ctrl-Shift-1 to 4 focus pane N; next / previous wraps; RT-06 open | S3, S5 |

### Outstanding runtime checks and deferrals

- Runtime checks RT-06, RT-21, RT-22 and RT-31 through RT-38 remain open in #78. RT-22 no longer blocks work: #83 was closed as not planned.
- Deferred, from the plan's Deferred section: split rename and the Favorites tile (BH-115), Share (#362), multi-select Open in Split View, the plus-menu New Split, BH-190 (toast above its pane), and KB-064 (left out by user decision). BH-148, Peek's Split button, belongs to #29.
- The gate measures shell work with `InMemoryEngine` views. A real-engine re-run of the divider drag belongs to the engine lane.
