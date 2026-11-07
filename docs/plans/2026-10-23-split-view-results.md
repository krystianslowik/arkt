# Split View results

Plan: `docs/plans/2026-10-23-split-view.md`, S9. Issue #27 is closed as an umbrella; its acceptance items are owned by #59 and recorded below. The divider frame-time numbers are pending: maintainer run on an idle 120 Hz machine.

## S0 baselines

As recorded in PR #141 at `9bf54f2`: ArktCore 316 Swift Testing tests, ShellKit non-GUI 312 Swift Testing tests, and ShellKit GUI 172 XCTest tests.

## S9: divider pacing (#59)

### Final counts (2026-11-07, after merging main)

Against the S0 baselines:

- ArktCore, `cd app/ArktCore && swift test -j 2`: 576 passed, 0 failures (316 + 260; the difference includes intervening work).
- ShellKit non-GUI, `cd app/ArktShell/ShellKit && swift test -j 2 --skip ShellKitGUITests`: 2,432 Swift Testing tests passed, 0 failures, summed over the package's test runs (312 + 2,120; the difference includes intervening work).
- ShellKit GUI: left to CI.

### Gate convention (after merging #665)

The three gated cases follow the shared rule in `PacingEnvironment` and match `SplitReflowPacingTests` (#602, #665, #671):

- `skipIfNotMeasurable` skips a case as NOT-MEASURABLE below 120 Hz or at a 1-minute load at or above the active core count.
- Every case measures, prints its `split.pacing` summary line and attaches it, and prints `split.pacing gate=asserts|reports`. After the drag the 1-minute load is read again. The hitch count (no frame over 8.6 ms, threshold unchanged) is asserted only when the case is gated (`PacingEnvironment.gateAsserts(for: SplitPacingTests.self)`: `ARKT_PACING_GATE=1`, or `SplitPacingTests` run alone) and that load is below the core count; the summary's `asserted` field says which.
- The drag is a sine sweep across the divider's allowed range: the amplitude is half the two panes' combined length minus `SplitLayout.minimumPaneLength`, 1 pt inside the clamp, for one and a quarter periods over 60 frames (ending at one end of the range, so the drag commits). A case whose amplitude is under 8 pt is skipped as NOT-MEASURABLE, with the split length in the message; each case prints its `split.pacing sweep` line with the length and amplitude.
- Precondition guards: since #665, `beginDividerDrag` ends a running reflow into the same `lastPacing` (that takeover is covered by `SplitPaneCloseTests`). Each case asserts that no reflow runs when the drag begins, that the pacer's session is "split-divider" during and after the drag, and that the drag changed `liveFactors`. `testDividerDragCommitsOnce` asserts the reflow and movement preconditions.

### Local runs (2026-11-07)

- `swift test -j 2 --filter SplitPacingTests` (the class alone, so the gated cases are gated): 5 executed, 0 failures, 0 skipped. Developer machine, screen maximum 120 Hz, 10 cores, 1-minute load 2.88 to 3.88 (not idle): `split-divider-2`, `split-divider-4` and `split-divider-4-stacked` each 59 frames, 0 over 8.6 ms, max and p99 8.33 ms, `asserted=yes`. Sweeps: `split-divider-2` length 1000 pt, +/-254.0 pt; `split-divider-4` length 1200 pt, +/-51.5 pt; `split-divider-4-stacked` length 1052 pt, +/-14.5 pt. FakeEngine informational: 59 frames, 0 over 8.6 ms, max 8.33 ms. These are a local check, not the recorded gate result. Raising the floor to 100 pt for one run skipped the two four-pane cases as NOT-MEASURABLE with their lengths in the message; restored to 8 pt.
- `swift test --skip-build --filter SplitPacingTests.testDividerDragCommitsOnce`, 20 consecutive runs: 20 passed, load 2.90 before and 2.58 after on 10 cores. Replacing the `onCommitFactors` call in `SplitContainerView.endDividerDrag` with nothing made it fail (0 writes, expected 1); restoring it made it pass.

### History (2026-10-26, before the merge of #665 and the gate convention)

- Initial red: `swift test -j 2 list` failed because the new pacing test could not access `FrameScript`; the frame helpers then moved to `FrameTestSupport.swift`.
- The three gated cases were NOT-MEASURABLE in every run (load 19 to 23 on 12 cores). `testDividerDragCommitsOnce` passed 20 consecutive runs, and the `onCommitFactors` break made it fail. FakeEngine informational at 240 Hz: 29 intervals, 0 over 8.6 ms.

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

Four panes leave a divider little or no room in the planned 1200 x 800 window: each pane keeps at least 240 pt, and the middle divider moves only within its two panes' share above those minima. Side by side, the split is 1000 pt wide, 970 pt after the gaps, so the sweep is about +/-1.5 pt; the case requests a 1400 x 800 window (split 1200 pt, sweep +/-51.5 pt). Stacked, 800 pt is below the 990 pt that four minima and three gaps need, and `SplitLayout.factors` returns equal shares; the case requests a 1200 x 1100 window (split 1052 pt here, sweep +/-14.5 pt). The two-pane cases keep 1200 x 800. One rule replaces the earlier 990 pt check: a case whose sweep amplitude is under 8 pt is NOT-MEASURABLE. On a built-in ProMotion display the visible screen height can keep the stacked window shorter, so that case may skip; then run it on an external 120 Hz display, or record it as NOT-MEASURABLE. Each case fails if the scripted drag leaves the factors unchanged.

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
| BH-118 | Implemented: drop a tab onto another sidebar tab (GS-010) | #104 (PR #374) |
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
