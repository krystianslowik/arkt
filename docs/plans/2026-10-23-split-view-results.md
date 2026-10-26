# Split View results

Plan: `docs/plans/2026-10-23-split-view.md`, S9. This section is a work in progress; the frame-time gate has not been measured on a quiet machine.

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
- Post-merge `swift test -j 2 --filter ShellKitGUITests`: 1,088 executed, 20 skipped, 0 failures. The three divider gates were NOT-MEASURABLE at load 19.09 on 12 cores; the SpacePager timing test also skipped. The three quiet-machine pacing measurements remain required before the pull request is ready.

### Plan deviation

Four stacked panes need at least 990 pt for four 240 pt minima plus three 10 pt gaps. The planned 1200 x 800 window cannot resize them: `SplitLayout.factors` returns equal shares. The stacked test requests a 1200 x 1100 window and skips if its split container remains under 990 pt. The other cases retain 1200 x 800. The final window size and actual movement must be verified in the quiet run.

### Keys and outstanding parity

S5 uses Ctrl-Shift-= to add, Ctrl-Shift-- to separate, Ctrl-Shift-1 through 4 to focus a pane, and Ctrl-Shift-[ / ] for previous / next. KB-075's expand and separate actions are unbound by default. Runtime checks RT-06, RT-21, RT-22 and RT-31 through RT-38 remain open in #78. The Split View plan's Deferred section retains the split rename and Favorites tile, the Opt-click close-button rule, sharing, multi-select Open in Split, and the plus-menu New Split. The BH-115 through BH-128 disposition and #27 acceptance checklist still need a final review after the timing gate.
