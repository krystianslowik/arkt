# Track C results: shell smoke (C7)

## Phase 1: functional smoke (2026-10-23, loaded machine)

| | |
|---|---|
| Date | 2026-10-23 |
| Machine | Apple silicon MacBook Pro, 120 Hz ProMotion; macOS 27 |
| `screenMaxFPS` | 120 |
| Load (1/5/15 min) | 75-123 during the runs (e.g. `116.82 112.28 114.35` at the end) |
| Chromium build | running |
| Build | Release, `xcodebuild -configuration Release -jobs 2` under `nice -n 20`, `** BUILD SUCCEEDED **` |

Because the 1-minute load was 8-12x the core count, the 120 Hz gates are recorded as
`NOT-MEASURABLE` (the same rule as the C5 earliest-frame check) and are pending phase 2 below. The
functional part does not depend on load and passed.

### Scripted smoke (`SmokeRunner`, Release binary, `-ArktSmoke YES`)

The runner drives the same code paths as user input: the command bar's `toggle` / `setQueryForTesting` /
`commit`, the pager's `beginTracking` / `track` / `endTracking` stepped once per vsync (20 frames of 9 pt,
the same shape as the GUI pacing test), and `nextSpace` / `previousSpace` for the keyboard. It exits 0
(functional PASS, pacing PASS), 1 (functional PASS, pacing FAIL or NOT-MEASURABLE) or 2 (functional FAIL).

4 runs, all `functional: PASS`, `exampleLoaded: true`, `exampleTitle: "Example Domain"`, every interaction
landed on its expected page, exit code 1 (`pacingVerdict: NOT-MEASURABLE (load ... on 10 cores)`).

| Run | load1 | bar first ms | bar warm p95 ms | swipe-next over8.6 / max ms | swipe-back over8.6 / max ms | key-next | key-previous |
|---|---|---|---|---|---|---|---|
| 1 | 93.6 | 19.93 | 28.28 | 0 / 8.33 | 1 / 25.96 | 0 / 8.33 | 0 / 8.33 |
| 2 | 75.6 | 20.22 | 22.01 | 0 / 8.33 | 1 / 18.25 | 0 / 8.33 | 0 / 8.33 |
| 3 | 103.5 | 19.42 | 24.45 | 0 / 8.33 | 1 / 18.01 (frame 6) | 0 / 8.33 | 0 / 8.33 |
| 4 | 108.0 | 37.15 | 29.45 | 0 / 8.33 | 0 / 8.33 | 0 / 8.33 | 0 / 8.33 |

Frames per interaction: 82-83 (swipe), 71-72 (keyboard). Lead-in (interval 0, excluded from the gate) was
8.33 ms in every interaction except one 7.12 ms. Run 4 line in full:

```
ARKT_SMOKE {"commandBarFirstShowMs":37.14795829728246,"commandBarWarmP95Ms":29.445875028613955,"commandBarWarmShowMs":[1.1608333443291485,22.22912502475083,20.960541674867272,21.09691663645208,9.424583346117288,29.445875028613955,12.874833308160305,10.275208333041519,33.40987500268966,10.120249993633479],"cores":10,"exampleLoaded":true,"exampleTitle":"Example Domain","functional":"PASS","functionalFailures":[],"interactions":[{"expectedIndex":1,"frames":83,"hitches":[],"index":1,"label":"swipe-next","leadInMs":8.333333302289248,"maxMs":8.333333360496908,"over8_6ms":0,"overBudgetPct":0,"p99Ms":8.333333360496908},{"expectedIndex":0,"frames":83,"hitches":[],"index":0,"label":"swipe-back","leadInMs":8.333333360496908,"maxMs":8.333333360496908,"over8_6ms":0,"overBudgetPct":0,"p99Ms":8.333333360496908},{"expectedIndex":1,"frames":72,"hitches":[],"index":1,"label":"key-next","leadInMs":8.333333302289248,"maxMs":8.333333360496908,"over8_6ms":0,"overBudgetPct":0,"p99Ms":8.333333360496908},{"expectedIndex":0,"frames":72,"hitches":[],"index":0,"label":"key-previous","leadInMs":8.333333360496908,"maxMs":8.333333360496908,"over8_6ms":0,"overBudgetPct":0,"p99Ms":8.333333360496908}],"load1":108.00048828125,"pacingVerdict":"NOT-MEASURABLE (load 108.00 on 10 cores)","screenMaxFPS":120}
```

Observations (loaded, so indicative only):
- The swipe back to Space 1 (the Space holding the live example.com WKWebView) had one 18-26 ms frame in 3
  of 4 runs, at frame 6 of the tracking phase in run 3; the swipe away from it never did. Keyboard switches
  were clean in all 4 scripted runs. Check on the idle machine whether this survives (candidate: the web
  view's page being un-hidden / composited as it comes on screen during the drag).
- Run 1 recorded a warm command bar show of -0.38 ms: a first-frame display-link callback already in flight
  when a hide/show pair ran back to back reported a vsync due before the new show. Fixed in
  `CommandBarController.firstFrame` (a frame whose `targetTimestamp` is not after `showStart` is skipped);
  runs 2-4 have no negative values.
- Warm command bar shows are 8-33 ms wall clock under this load, above the 16 ms gate; the C5 CPU-time gate
  (`show()` p95 < 4 ms) passed in the GUI suite. The wall-clock gate is pending phase 2.

### Interactive pass (Release app via `open -n`, System Events keystrokes, accessibility, screenshots)

Launched with `open -n .../Release/ArktShell.app` (pid <pid>), `caffeinate -u -t 900` held the display awake,
keystrokes were sent through System Events after bringing the process frontmost by pid (permitted), the
accessibility tree was read with a JXA walker, screenshots are of the window rect only, and the app was
quit with `kill -TERM <pid>`.

| Step | Input | Accessibility result | Screenshot |
|---|---|---|---|
| Launch | - | 1 window (AXStandardWindow); favorites grid of 6 buttons; Space title `Personal`; 8 outline rows; `Archive`, `New Tab`; group `Spaces` with buttons Personal (selected), Work, Dev; AXWebArea `Example Domain` | `c7-1-launch.png`: pink Personal theme, first pinned tab selected, page rendered |
| Command bar | Cmd-T, type `example.com` | 2 windows: an AXDialog with text field `example.com`; 6 result rows (open example.com selected, 4 "Switch to Tab", Search Google) | `c7-2-commandbar.png` |
| Open | Return | bar gone (1 window); new outline row `Example Domain` under the Today divider; web area `Example Domain` | `c7-3-example-opened.png`: new Today tab selected |
| Next Space | Cmd-Opt-Right | title `Work`, dot Work selected | `c7-4-space2-key.png`: light blue Work theme, second dot filled |
| Space 3 | Ctrl-3 | title `Dev`, dot Dev selected; web area `Sign in to GitHub` | `c7-5-space3-ctrl3.png`: dark blue Dev theme, dark sidebar flavor; card still blank 1.5 s after the switch (first network load); `c7-9-space3-after5s.png` rendered with favicon |
| Space 1 | Ctrl-1 | title `Personal`, dot Personal selected; the Today tab opened above is restored as active | `c7-6-space1-ctrl1.png` |
| Cmd-L | Cmd-L | AXDialog, field prefilled `https://example.com/` (selected) | `c7-7-cmdL.png` |
| Esc | Esc | bar gone, 1 window | `c7-8-esc.png` |

Perf log of the interactive keyboard switches (`/usr/bin/log show ... category == "perf"`; note that zsh
has a builtin `log`, so the full path is needed): 4 `pacing label=space-key` lines, frames 70-77, two with
`over8.6=0` and two with one 20.83 ms frame (load ~110). Recorded, not gated.

Accessibility notes for later: the main window has an empty AX title (no window title is set), and the
outline's divider row is an unnamed AXRow.

Screenshots and AX dumps: `c7-*.png` and `c7-ax-*.txt` in a local scratch directory (not committed).

### Tests and checks

- `swift test -j 2` (full, including ShellKitGUITests): 80 XCTest tests, 0 failures; Swift Testing suites
  all passed. Pacing test lines (asserted=no, load 123):
  `space-swipe frames=83 over8.6=0 maxMs=8.33 leadInMs=8.33`, `space-key frames=71 over8.6=0 maxMs=8.33 leadInMs=8.33`;
  `commandbar.earliestframe p95=16.94 bound=21.26 load1=116.72 asserted=no`.
- WebKit isolation grep: no output; the guard variant prints only `ShellKit/Sources/FakeEngineKit/FakeEngine.swift`.

### C6 re-review minors folded in

- Resumed settles (touch-down freeze, then a vertical gesture) log as `space-resume`, not `space-key`.
- `FrameStats.leadInInterval`: the first interval of a pacing session (display-link start-up) is recorded
  apart and excluded from `frameCount`, `intervals`, `maxInterval` and both gates; it is printed as
  `leadInMs=` in the `pacing` log line, the GUI pacing test line and the smoke JSON, and logged as a
  `leadin` line instead of a `hitch` line. Hitch indices count from the first gated interval.
- `testTouchDownFreezesASettleAndVerticalResumesIt` asserts its `waitUntil`.
- `VelocityTracker` clamps a negative span (out-of-order timestamps) to 0 and returns 0 for a non-positive
  duration; tests for both lead-in and out-of-order timestamps added.

## Phase 2: idle-machine pacing (2026-10-23)

Conditions: Chromium build finished (`pgrep -x siso` empty), 1-minute load 3.5-6.2 on 10 cores, built-in
120 Hz panel (`screenMaxFPS` 120), Low Power Mode off, display held awake with `caffeinate -u -t 900`. Builds
and tests at normal priority with `-jobs 4` / `-j 4`. Meanwhile a Debug `ArktShell -ArktSmoke YES` process
(pid <pid>) was left running, and a second one (pid <pid>, `-ArktSmokeRepeat 20`) later. Correction:
both were started by this run. `xcrun xctrace record --launch -- <path inside the Release bundle>` resolved
the bundle id through LaunchServices and launched a stale Debug build, which has no smoke runner
and never exited. Both were killed (one by the coordinator, one here), the stale Debug product was
deleted, and the profiling recipe uses `--attach` only. The runs from before they started show the same
pattern as the later runs.

### Verdicts

| Gate | Result |
|---|---|
| Space keyboard switches, zero intervals over 8.6 ms | PASS-ish: 1 hitch in 74 interactions (key-next 0/37, key-previous 1/37) |
| Space scripted swipe, zero intervals over 8.6 ms | FAIL: swipe-next 0/37, swipe-back 8/37 interactions with one or two late frames (14-21 ms) |
| GUI pacing test (`testFramePacingDuringSwipeAndKeyboardSwitch`, asserted=yes) | 4 of 5 runs PASS; 1 run failed with `0@20.83` (first gated frame right after the test window opened) |
| Command bar CPU gate (`show()` main-thread CPU p95 < 4 ms) | PASS: 2.6-3.0 ms in the GUI test, about 1 ms in the app |
| Command bar earliest-frame gate, GUI test (asserted=yes) | PASS 5 of 5: p95 17.14 / 20.46 / 21.56 / 18.88 / 18.92 ms against bounds 22.59 / 23.84 / 26.01 / 24.61 / 24.29 |
| Command bar in the Release app (smoke, warm p95) | FAIL: 21-33 ms (the literal 16 ms gate and the earliest-frame bound of about 18.2 ms both miss) |
| Design section 5 (<= 1% of frames over one 120 Hz interval) | PASS in aggregate: 11 of 11471 frames (0.096%) over 8.34 ms across 148 interactions. Per interaction it fails 9 times (one late frame in about 82 frames is 1.2%) |

The 8.6 ms gate for swipes and the command bar's wall clock in the real app are not met at idle. Both are
diagnosed below; fixes are proposed, not implemented.

### Smoke runs (Release, `-ArktSmoke YES`)

The 3 runs as documented all printed `functional: PASS` with `exit=1` (pacing FAIL):

| Run | load1 | bar first ms | bar warm p95 ms | swipe-next | swipe-back | key-next | key-previous |
|---|---|---|---|---|---|---|---|
| 1 | 3.93 | 43.13 | 23.79 | 0 / 8.33 | 1 / 16.67 (`22@16.67`) | 0 / 8.33 | 0 / 8.33 |
| 2 | 4.09 | 35.22 | 22.26 | 0 / 8.33 | 1 / 16.67 (`37@16.67`) | 0 / 8.33 | 0 / 8.33 |
| 3 | 4.20 | 49.62 | 22.56 | 0 / 8.33 | 1 / 16.67 (`33@16.67`) | 0 / 8.33 | 0 / 8.33 |

(cells: over8.6 / max ms; `frame@ms` counts from the first gated frame; tracking is frames 0-19, the settle
follows.) Diagnostic runs that followed:
- `-ArktSmokePause 3`, with 3 s between interactions: 1 of 3 runs still hitched on swipe-back (`33@19.40,34@13.94`), and that run also had the only key-previous hitch (`7@20.83`). Waiting after a Space switch does not remove the hitch.
- `-ArktSmokeRepeat 15`: swipe-back 3/15 (`24@16.74`, `47@20.81`, `20@19.26,21@14.08`), the other three 0/15.
- `-ArktSmokeRepeat 25` under Time Profiler: swipe-back 3/25 (`20@17.54`, `43@16.85`, `33@16.74`), the others 0/25.

Totals over 23 smoke runs: swipe-next 0 hitches in 3082 frames, swipe-back 10 in 3072 (8 of 37
interactions), key-next 0 in 2658, key-previous 1 in 2659.

### Swipe-back hitch: diagnosis

- The new `hitch` log line records how late each display-link callback ran. At a hitch the callback is on
  time (`lateMs` 0.01-0.07). The previous callback ran 0.02-5.4 ms late, and one vsync was skipped. So the
  main thread was busy across a vsync; the display link did not fail on its own.
- A Time Profiler trace (attached to a `-ArktSmokeRepeat 25` run) caught a `Hitch` signpost event, the
  pacer's new `emitEvent("Hitch")`. Just before it the main thread ran 17 ms without a break (1 ms samples,
  34.843-34.860 s). 16 of those 17 samples are inside one `CA::Transaction::commit` started from
  `SpacePagerView.apply(offset:)` (the spring settle's strip move). The commit runs
  `-[NSViewBackingLayer display]` -> `-[_NSSimpleImageView updateLayer]` ->
  `-[NSImage CGImageForProposedRect:]` -> `NSImageSymbolRepProvider bestRepresentationForImage:` ->
  `_NSSimpleLRUCache objectForKey:creationBlock:`. That call evicts old `NSSymbolImageRep` /
  `CUINamedVectorGlyph` entries (dealloc) and rasterizes new glyphs (`CUICGBitmapContextCreate`,
  `CGBitmapContextCreate`).
- Cause: SF Symbol image views are re-rasterized (the trace does not name the view; the likely ones are the
  outline cells' symbol icons, such as the folder and split icons, and the bottom-bar buttons) in the middle of the swipe. AppKit's symbol representation cache is a
  small LRU, so the shell's symbol variants (several symbols x light/dark x tint x the command bar's icons)
  push each other out, and every redisplay pays for a vector-glyph rasterization (several ms each) inside
  the frame's commit. The likely reason it shows on swipe-back (inferred, not traced) is that the swipe-next settle activates the destination Space's
  tab. `activate` pushes row states into every page's outline, so the hidden Personal page's cells are left
  needing display, and they redraw when the page is moving on screen.

Proposed fix (not implemented, for review):
1. Rasterize symbol icons once per (symbol, point size, flavor/tint, backing scale) into plain bitmap
   `NSImage`s (or `CGImage` layer contents) held in a small ShellUI cache, and give the image views those,
   so AppKit's symbol LRU is never consulted on the hot path. Prewarm the cache at launch, next to the
   command bar prewarm.
2. In `SidebarController.activate`, push row states only to cells whose state changed (today every page's
   outline gets `setRowStates`). Also skip `setFlavor` when the flavor is unchanged, since a settle and a
   commit call it unconditionally.
3. Re-run `-ArktSmokeRepeat 25` after the fix: the gate is 0 hitches in 100 interactions.

### Command bar in the app: diagnosis

- The work inside `show()` is small: about 1 ms main-thread CPU and wall time in the Release app (per-show
  `commandBarWarmCPUMs` / `commandBarWarmWallMs` added to the smoke JSON).
- The slow part is the time from show() to the first tick of the bar's display link. `vsyncWait`
  (show() to the first callback's vsync) is bimodal in the app: either -5 to +6 ms or 10-19 ms, so the
  total is about 2.5-4 frames instead of at most 2. In the GUI test (accessory app, InMemoryEngine, no web
  view) it stays within one frame. The 30 ms gap between shows that the GUI test uses did not help: the
  app's warm p95 was mostly 30-33 ms with it (two runs 15.8 and 21.9), against 21-26 ms back to back.
- The extra frames sit between `makeKeyAndOrderFront` and the window server putting the panel on screen,
  where the display link on the panel's view is attached. The shell's main thread is not the bottleneck,
  and with this proxy the measured value also depends on when that link re-attaches.

Proposed fix (not implemented, for review):
1. Keep the panel ordered in at all times (alpha 0, `ignoresMouseEvents`, no shadow while hidden), and show
   it by setting alpha and `makeKey`. That turns show into a single Core Animation commit with no
   window-server ordering. Check that focus and key-window behavior (KB-003, resign-key hides) still hold.
2. Measure the first frame with a display link on the parent window, which is always attached, plus a
   Core Animation commit handler that confirms the bar's commit. Then measurement noise no longer depends
   on the link re-attaching.

### GUI tests

- `swift test -j 4 --filter 'testFramePacingDuringSwipeAndKeyboardSwitch|testAppearsUnder16ms'` (first run):
  `commandbar.earliestframe p95=17.14 bound=22.59 load1=3.45 cores=10 asserted=yes`;
  `spacepager.pacing label=space-swipe frames=83 over8.6=1 maxMs=20.83 leadInMs=13.77 asserted=yes hitchesMs=[0@20.83]`
  (failed); `label=space-key frames=72 over8.6=0 maxMs=8.33 leadInMs=8.33 asserted=yes`.
- The next 3 pacing-test runs and the full-suite run: `space-swipe over8.6=0 maxMs=8.33` (lead-in 7.9-11.9 ms),
  `space-key over8.6=0`, all asserted=yes. The one failure is the first gated frame right after the test
  window appears (lead-in 13.8 ms). That matches the start-up effect the lead-in split was meant to
  isolate, but here it spilled into frame 0. If it recurs, have the test wait a few frames after
  `showWindow` before it measures.
- Full `swift test -j 4`: 80 XCTest tests, 0 failures; all Swift Testing suites passed.

### Diagnostics added in this phase

- The `hitch` log line now carries `lateMs` and `prevLateMs` (how late this callback and the previous one
  ran after their vsync), and the pacer emits a `Hitch` signpost event (Points of Interest) at every hitch.
- SmokeRunner: `-ArktSmokeRepeat N` (N swipe and keyboard rounds), `-ArktSmokePause S` (seconds between
  interactions), per-show `commandBarWarmCPUMs` / `commandBarWarmWallMs` / `commandBarWarmVsyncWaitMs`, and
  a 30 ms gap between command bar shows, matching the GUI test.
- Profiling recipe: launch `.../Release/ArktShell.app/Contents/MacOS/ArktShell -ArktSmoke YES -ArktSmokeRepeat 25`,
  then `xcrun xctrace record --template 'Time Profiler' --instrument os_signpost --attach <pid> --time-limit 70s`,
  and export the `os-signpost` and `time-profile` tables around the `Hitch` events.
  (`xctrace --launch` did not run the smoke; attach instead.)

### Still pending for the user

- Plan step 4, manual trackpad pass: open the Release app, Cmd-T, `example.com`, Enter, then 10 real
  two-finger swipes (5 each way, mixed slow drags and flicks), then
  `/usr/bin/log show --last 5m --info --style compact --predicate 'subsystem == "dev.arkt.shell" AND category == "perf"' | grep -E 'pacing label=space-swipe|hitch|commandbar.show'`.
  Expect 10 `pacing label=space-swipe` lines. Given the diagnosis above, expect occasional `over8.6=1`
  on swipes into a Space whose page was invalidated while hidden, until the symbol fix lands.
- C6 follow-ups I3 / I4: the profile shows symbol rasterization inside the commit, not scroll-view or
  `setFrameOrigin` cost, so these are not needed now. M9 (flavor flip): not exercised. The smoke only
  switches between Personal and Work, which are both light.

## Fixes and after-fix numbers (2026-10-23)

Commits: "Cache SF Symbol bitmaps; push only changed row states" (also adds the smoke watchdog and
the hitch log's `lateMs` / `prevLateMs` / `frameMs`), and "Keep the command bar ordered in and show
by alpha".

### What changed

1. `SymbolImageCache` (ShellUI) renders every SF Symbol once per (name, box, weight, color, backing scale)
   into a single `NSBitmapImageRep`, and letter tiles once per (letter, flavor, size, scale). The cache is
   prewarmed when the shell window is created. Sidebar row and folder/split icons, favorites letters,
   bottom-bar buttons and command bar icons all use it, with no template tinting.
   - `SidebarOutlineController.setRowStates` touches only rows whose state changed
     (`Resolver.changedNodes(from:)`).
   - `SidebarContainerView.setFlavor` is a no-op when the flavor is unchanged.
2. The command bar panel is ordered in once at prewarm and presented by alpha plus `makeKey`. While hidden it
   ignores the mouse, cannot become key, sits outside the Cmd-` cycle (`.ignoresCycle`) and reports no
   accessibility element or children.
   - If app activation hands the hidden panel key status, it passes key status to the shell window
     (deferred one run loop turn).
   - `show()` orders the panel back in only if `hidesOnDeactivate` ordered it out.
   - The first frame is measured on the parent window's display link: the first vsync after a run loop
     observer (ordered after Core Animation's commit observer) marks the show's commit.
     `CATransaction.addCommitHandler` does not exist in this SDK.
3. SmokeRunner:
   - The watchdog `_exit(3)`s after `-ArktSmokeTimeout`, else 60 s + 8 s per round, and prints
     `ARKT_SMOKE {"functional":"TIMEOUT"}`.
   - The command bar gate is the adopted earliest-frame bound (wall p95 + 2 refresh intervals + 0.5 ms,
     18.2-18.5 ms here) instead of an absolute 16 ms.

Tests added: `SymbolImageCacheTests` (7), `ResolverDiffTests`, `testActivationRepaintsOnlyChangedRows`,
`testRowGlyphsAreCachedBitmaps`, `testHiddenPanelStaysOrderedInButIsInert`,
`testShowOrdersThePanelBackInAfterItWasOrderedOut`, `testFirstFrameIsAfterTheShowCommit`,
`testHiddenPanelThatBecomesKeyHandsKeyToTheShellWindow`; `testEscapeCloses` now checks alpha instead of
`isVisible`. Full `swift test`: 86 XCTest tests and all Swift Testing suites pass.

### Measurement hygiene found on the way

- `caffeinate -u` (declare user activity) produced hitches on a 5 s grid: the hitch timestamps of one
  25-round run fell at .566-.603 s past each 5 s boundary. Without it the swipe hitch rate dropped about
  five-fold. Do not run pacing with `caffeinate -u`; the display stayed awake through another app's
  display-sleep assertion.
- After the symbol fix, the remaining hitches were 20.8 ms intervals, which is 8.33 + 12.5 ms. The
  callback was on time and the main thread was idle (Time Profiler: 5 samples in the 40 ms before one).
  The Animation Hitches trace showed one missing app commit with renders still on cadence. Pinning the
  Space paging display links to 120/120/120 Hz did not change the rate (4 hitches in 300 interactions
  with the pin, 2 in 200 without), so it was reverted.
- Each measurement below ran only when `pgrep -x siso` was empty and the 1-minute load was below 6. The
  idle gate itself waited out several Chromium builds. Background CPU at measurement time: a Java process
  at 145-166% (r25 runs), UVFSXPCService and the spike Chromium app at about 97% (smoke runs), and
  a concurrent `xctrace --all-processes` at about 100% (GUI runs).
- The GUI runs compiled sources that contained another track's temporary, log-only diagnostics in
  `CommandBarController` / `SmokeRunner` (uncommitted, not part of either fix). The smoke runs used the
  Release build of the second fix commit.

### Swipe and keyboard pacing (gate: 0 intervals over 8.6 ms)

| Run | load1 | interactions | frames | over 8.6 ms | detail |
|---|---|---|---|---|---|
| before, phase 2 (23 runs) | 3.9-10.5 | 148 | 11471 | 11 | swipe-back 8/37, key-previous 1/37; 16-26 ms, main thread busy rasterizing symbols |
| after `-ArktSmokeRepeat 25` #1 | 5.53 | 100 | 7749 | 0 | PASS |
| after `-ArktSmokeRepeat 25` #2 | 5.72 | 100 | 7748 | 2 | one key-previous: `31@20.52, 32@12.81` |
| after `-ArktSmokeRepeat 25` #3 | 6.27 | 100 | 7750 | 0 | PASS |
| after standard smoke x3 | 5.5-10.3 | 12 | 930 | 0 | |
| GUI pacing test x5 (asserted=yes) | 5.6-5.9 | 10 | 770 | 0 | all PASS, lead-in 8.33 ms |

The 100-interaction gate passed in 2 of 3 runs. The single miss was one key-previous interaction with a
20.5 ms interval, the same signature as the residual described above. Design section 5: 2 of 23247 frames
(0.009%) over one 120 Hz interval across the three 25-round runs.

### Command bar (gate: warm-show p95 <= 18 ms, earliest frame)

| Run | warm p95 ms | earliest-frame bound ms | warm samples (sorted) |
|---|---|---|---|
| before, phase 2 smoke | 21-33 | (16 literal) | bimodal: 1-6 or 20-41 |
| after r25 #1 | 17.06 | 18.25 | 10.7 ... 17.1, 17.6 |
| after r25 #2 | 19.05 | 18.30 | 14.7 ... 19.0, 19.3 |
| after r25 #3 | 16.67 | 18.46 | 15.1 ... 16.7, 18.6 |
| after smoke #1 | 22.50 | 18.29 | 12.3, 15.6-18.2, 22.5, 25.8 |
| after smoke #2 | 18.68 | 18.34 | 16.6-17.7, 18.7, 20.8 |
| after smoke #3 (load 10.25, not measurable) | 22.60 | 18.23 | 11.1, 17.3-18.3, 21.8, 22.6, 31.1 |
| GUI test x5 (asserted=yes) | 17.52 / 11.23 / 10.84 / 17.06 / 10.99 | 19.31 / 17.54 / 17.56 / 17.52 / 17.55 | all PASS |

`show()` work is 1.1-1.3 ms wall. Medians moved from about 20 ms to 16-17.5 ms and the bimodal 20-41 ms
tail is gone. By construction the total is commit + 1 to 2 refresh intervals, so p95 sits at the 16.7-18.3
ms ceiling. The ≤ 18 ms gate passed in 2 of 5 idle smoke runs (17.06, 16.67) and missed in 3 (19.05,
22.50, 18.68). The misses are one or two shows per run that land a frame later (20.8-25.8 ms), which is
the same 1-frame slip as the swipe residual.

### Interactive check of fix 2 (Release app, System Events)

With a single activation: Cmd-T showed the bar (focused AXDialog, 2 windows), typing went into the field,
Esc closed it (focused AXStandardWindow, 1 window), and Cmd-L / Cmd-L and Cmd-T / Cmd-T toggled. After
switching to Finder and back with the bar hidden, the shell window was focused and the bar was not
listed. A click where the hidden bar sits reached the web content (click-through). The hidden panel is
never listed by accessibility. While the hidden panel was ordered in, an early build without the key
hand-back left an invisible key window after reactivation; the deferred hand-back fixes it (unit test).

Later keystroke runs were stopped: the spike Chromium app came to the front at one point, and System
Events keystrokes stopped reaching the shell. Some of them (Cmd-T, `x`, Esc, Cmd-L) may have reached
Chromium. Not verified interactively since then: deactivating while the bar is open, then reactivating
and pressing Cmd-T (covered by `testShowOrdersThePanelBackInAfterItWasOrderedOut`).

### Still open

- The 1-frame residual (about 1 in 100-150 interactions, and the command bar's late shows) with an idle
  main thread. Next step: a WindowServer-side trace (`--all-processes` Animation Hitches) correlating the
  missed app commit with compositor activity, on a machine without the Chromium spike or Java running.
- Manual trackpad pass (plan step 4, 10 real two-finger swipes): still for the user.

## C7 phase 3: post-fix measurement (2026-10-23)

Release build (`xcodebuild -target ArktShell -configuration Release -jobs 4` under `nice -n 10`), smoke
`-ArktSmoke YES -ArktSmokeRepeat 25` (100 interactions per run), 120 Hz built-in panel, no `caffeinate`.
`pgrep -x siso` was empty for every run. Another track's ShellKit GUI tests (`xctest`, track-e worktree) ran
at times, and system daemons (fileproviderd, suggestd) pushed load1 to 13-17 for a few minutes.
Every ArktShell process this phase started exited or was killed by PID (one stray from an
`xctrace --launch` attempt, pid <pid>, was killed).

### Verdicts

| Gate | Result |
|---|---|
| 0 intervals over 8.6 ms in 100 interactions (smoke) | Machine-dependent; not a stable PASS. First runs: 0 hitches in 700 interactions over the 7 counted runs (3 on the second fix commit, 4 with the fix below). One diagnostic run had 2 swipe-back hitches at load1 10.34, which the smoke marks NOT-MEASURABLE. Later runs, with suggestd at about 90% CPU and WindowServer at 15-50%: 1, 5, 1, 0 hitches on the committed build, and 3, 3 on an A/B build without the new KB-003 check (see below). Over those 6 runs, 4 of 6 failed the gate |
| Command bar warm p95 <= 18 ms (smoke) | FAIL on the second fix commit as committed (24.41 / 24.53 / 24.90). With the fix below, the representative runs (2-4 of the first set, then the 3 runs of the committed build) gave 14.96 / 17.64 / 18.16 / 17.38 / 17.13 / 15.91: 5 of 6 under the literal 18 ms, and 6 of 6 under the smoke's earliest-frame bound. Run 1 of the first set (15.65) is excluded as optimistic, see below |
| GUI tests `testFramePacingDuringSwipeAndKeyboardSwitch`, `testAppearsUnder16ms` | PASS 3 of 3, asserted=yes; earliest frame p95 10.95 / 10.44 / 10.71 ms (bounds 17.4-17.6); swipe `over8.6=0 maxMs=8.33` |
| Full `swift test -j 4` (ShellKit) | PASS: 88 XCTest tests (86 plus 2 new), 0 failures; all Swift Testing suites pass |
| KB-003 (resign key hides the bar) after the second fix commit | PASS. Covered by the existing delegate-level unit tests and by a new in-process smoke check that uses a real key change |

### Smoke runs on the second fix commit (before the fix in this phase)

| Run | load1 (smoke / uptime) | bar warm p95 | bound | warm shows (ms) | hitches |
|---|---|---|---|---|---|
| 1 | 8.82 / 8.55 | 24.41 | 18.43 | 11.4, 24.4, 10.9, 24.4, 12.1, 16.4, 25.9, 12.5, 16.3, 17.5 | 0 / 100 |
| 2 | 8.11 / 8.29 | 24.53 | 18.35 | 23.3, 10.9, 24.1, 11.8, 24.9, 12.3, 24.5, 13.6, 18.6, 10.4 | 0 / 100 |
| 3 (not measurable) | 11.89 / 10.93 | 24.90 | 18.28 | 11.4, 17.1, 18.6, 11.9, 24.9, 23.4, 11.0, 18.6, 12.0, 25.3 | 0 / 100 |

Runs 2 and 3 overlapped a concurrent `CommandBarTests` run.

### Command bar late show: root cause

The phase 2 note ("one show landing a frame late with an idle main thread") does not hold for the bar.
Temporary probes (later removed) logged a run loop observer at the first before-waiting after `show()`,
with thread CPU time, and counted `CommandBarCellView` inits.
- The late shows are not idle. Between `show()` entry and the commit, the main thread spends 9-15 ms of
  CPU (wall about equal to CPU), against 2-3.5 ms for the on-time shows. The split is bimodal, about every
  other show, and it holds over 200 back-to-back shows (12 s), so it is not launch settling.
- Each slow show creates 6 new `CommandBarCellView`s, one per result row; fast shows create none.
  `sample` (1 ms, 6 s) puts that time in the show's `CA::Transaction` flush. `NSTableView` layout calls
  `_addRowViewForVisibleRow` -> `tableView(_:viewFor:)` -> `CommandBarCellView.init` (`NSTextField`
  label creation), then text-field layout and CoreText drawing, plus the old cells' `NSTextField dealloc`.
- Cause: `show()` calls `reloadResults()`, which ran `table.reloadData()` even when the results had not
  changed. On about half the shows the table's reuse queue was already empty, so every cell was rebuilt
  inside the show's commit. That pushed the commit past a vsync and added one frame (8.3 ms), sometimes
  two.

Fix (this commit): `reloadResults()` reloads the table only when the new results differ
(`CommandBarResults.Result` is `Equatable`); row 0 is still selected on every show. Tests:
`testShowWithUnchangedResultsKeepsTheCells` (it fails without the fix: the cell is rebuilt and
reconfigured) and `testShowWithChangedResultsReloads`. Typing still reloads on every keystroke, and it pays
the same cell rebuild when the reuse queue is empty. That path is not gated; if typing latency is ever
gated, keep a controller-owned cell pool.

Commit delay (show entry to end of the run loop pass) went from 2-3.5 ms (with 9-15 ms on the slow
shows) to 1.5-3.3 ms. `show()` wall is 1.3-1.6 ms, and about 1.1-1.3 ms of that is `panel.makeKey()`, a
window-server round trip. The remaining tail is `show()` wall spikes of 7-14 ms with CPU still at 1.1 ms,
so the thread is blocked, not busy. It shows up when other GUI processes are using the window server (2 of
10 shows in two runs at load 10.3-10.8). A per-step timing probe put about 1.2 ms in `makeKey`; the spikes
themselves were not caught with that probe. Not fixed: deferring `makeKey` until after the alpha commit
would open a window in which keystrokes land in the shell window (KB-003 / focus semantics).

### Smoke runs after the fix (first set, before the KB-003 smoke check was added)

| Run | load1 smoke / before / after | other xctest | bar warm p95 | bound | commit delay ms | hitches | verdict |
|---|---|---|---|---|---|---|---|
| 1 | 8.65 / 8.45 / 6.46 | 1 | 15.65 | 17.61 | 0.2-0.5 | 0 / 100 (7717 frames) | PASS |
| 2 | 6.43 / 6.46 / 5.52 | 0 | 14.96 | 18.89 | 1.6-3.1 | 0 / 100 (7724) | PASS |
| 3 | 5.52 / 5.52 / 6.15 | 0 | 17.64 | 19.77 | 1.5-3.3 | 0 / 100 (7713) | PASS |
| 4 | 6.21 / 6.15 / 6.29 | 0 | 18.16 | 18.65 | 1.5-2.9 | 0 / 100 (7704) | PASS (literal 18 ms: miss by 0.16) |

Run 1's `show()` wall was 0.2-0.5 ms with no `makeKey` cost, which suggests the app was not active while
another test process was running. Treat that run's bar number as optimistic. Runs 2-4 (`show()`
wall 1.3-3.0 ms) are representative: p95 14.96 / 17.64 / 18.16. Earlier runs of the fix with probes
(diagnostic logging only) at load1 13-15: p95 17.50 / 14.49 / 15.49 / 17.07.
Design section 5: 0 of 30858 frames over one 120 Hz interval across the 4 final runs.

### Runs of the committed source (fix plus KB-003 check), then an A/B

The first-set runs above predate the KB-003 smoke check. The check runs after the bar measurement, and the
ShellUI code is identical. The committed source was measured afterwards:

| Run | load1 smoke / uptime | other xctest | bar warm p95 | bound | hitch interactions | detail |
|---|---|---|---|---|---|---|
| C1 | 6.73 / 6.79 | 0 | 17.38 | 19.43 | 5 / 100 | swipe-back 17.61, 16.80; key-next x3 `19.2 + 14.1` pairs |
| C2 | 5.75 / 5.75 | 0 | 17.13 | 20.89 | 1 / 100 | swipe-back 16.75 |
| C3 | 5.01 / 5.01 | 0 | 15.91 | 19.72 | 0 / 100 | PASS |
| A1 (no KB-003 check) | 5.70 / 5.70 | 1 | - | - | 3 / 100 | 16.63, 16.88, 20.82 |
| B1 (committed) | 14.28 / 5.95 | 0 | - | - | 6 / 100 | NOT-MEASURABLE; swipe-back 17.2-18.3 x5 |
| A2 (no KB-003 check) | 8.33 / 8.33 | 0 | - | - | 3 / 100 | 17.46, 18.65, 18.71 |
| B2 (committed) | 6.18 / 6.18 | 4 | - | - | 1 / 100 | 20.81 |

The A build has the same fix and no KB-003 check. It hitches at the same rate, so the check does not cause
the hitches. These hitches look like the residual described above: the callback is on time
(`lateMs` 0.01-0.07), but the previous callback ran 7.4-7.7 ms late. So the main thread or the run loop was
held for most of one frame just before the vsync. In this window the machine was busier than during the first set
(suggestd about 90% CPU, WindowServer 15-50%, an Arc renderer about 38%). The same binary content gave 0
in 400 in that earlier window. No profile was taken of these, so the source of the 7.5 ms hold is open.

### Diagnostics kept

- Smoke JSON `commandBarWarmCommitDelayMs` (show entry to the end of the run loop pass that committed it,
  from the existing `lastShowCommitDelay`).
- Smoke functional check 1b (KB-003): show the bar, wait until the shell window loses key, `makeKey` the
  shell window in-process, and require that the bar hides and the shell window is key. It is a functional
  failure otherwise. It passed in the run after it was added (`functionalFailures: []`, load1 9.57). No
  synthetic OS events are used.

### Still open

- Swipe and keyboard pacing still produces the occasional single late frame (16.6-20.8 ms) on a busy
  machine, with the previous display-link callback about 7.5 ms late. Next step: a Time Profiler attach
  (`--attach`, Hitch signposts) during a run on a machine as loaded as during the later runs, to name what
  holds the main run loop.
- The bar's residual tail is window-server latency in `makeKey` while other GUI processes are active.
  Re-measure on a machine where no other GUI tests are running before treating it as a product issue.
- Manual trackpad pass (plan step 4): still for the user.

## Pre-merge fixes (2026-10-23)

From the pre-merge review, one commit each:

- Command bar on another Space. The panel stays ordered in for good, so it stayed on the Space it
  was prewarmed on. `show()` now orders it out and back in when `!panel.isVisible || !panel.isOnActiveSpace`
  (before key status changes); on the active Space the fast path is unchanged (no ordering). Not used:
  `.moveToActiveSpace`. It does not conflict with `.fullScreenAuxiliary` (different exclusivity groups in
  `NSWindow.h`), but it only acts when a window is ordered front or activated, which the warm show
  deliberately avoids, so it would not fix this alone. Tests use an `isOnActiveSpace` seam on the panel and
  ordering counters.
- Backing scale changes. `SidebarOutlineController.refreshRealizedCells()` (factored out of
  `setFlavor`) runs from `SpacePageView.viewDidChangeBackingProperties`; `FavoritesGridView` refreshes its
  visible tiles there too. The command bar takes the icon scale from the parent window (the panel reports the
  old display's scale until its frame moves) and reloads on a show when that scale changed, even with
  unchanged results. Prewarm uses the shell window's scale (window created first) and runs again from
  `windowDidChangeBackingProperties`.
- Symbol bitmaps render into a Display P3 `CGContext` (was device RGB); sRGB tokens convert exactly,
  cache keys unchanged. Note for tests: `NSBitmapImageRep.colorAt` tags CGImage-backed pixels as calibrated
  RGB, so the test reads raw samples and tags them with the rep's color space.
- `SmokeWatchdog` is `@MainActor` with a plain static timer and an explicit `@Sendable` handler
  (no `nonisolated(unsafe)`). Checked at run time: Release app with `-ArktSmokeTimeout 3` printed the
  TIMEOUT line and exited 3. `SidebarContainerView.swift` `nonisolated(unsafe)` left alone (fixed on track-e).
- Pacing test warm-up: `testFramePacingDuringSwipeAndKeyboardSwitch` waits for 10 consecutive
  display-link intervals within 8.6 ms (2 s cap, never fails on warm-up) before the scripted swipe. The gate
  on measured frames is unchanged. 5 runs: 5/5 pass, warm-up reached 10 of 10 each time, both interactions
  `over8.6=0 maxMs=8.33 leadInMs=8.33`, load1 5.22-5.46 on 10 cores, `asserted=yes` every run.

Checks: full `nice -n 10 swift test -j 4` in ShellKit: 92 XCTest tests (88 plus 4 new), 0 failures; all
Swift Testing runs pass (73, 32, 17, 7 tests; the P3 test is new). Release and Debug app builds
(`xcodebuild -scheme ArktShell`, `nice -n 10`, `-jobs 4`): `** BUILD SUCCEEDED **`, no Swift warnings.

Needs a manual check (tests cannot switch Spaces or displays):
- Cmd-T with the shell window full screen, and Cmd-T on a second desktop after the bar was prewarmed on the
  first: the bar should appear over the shell window on the current Space.
- Move the shell window between a 1x and a 2x display: sidebar glyphs, favorite letter tiles, bottom-bar
  buttons and command bar icons should be sharp on both.

## Note (2026-10-23, track-e): pacing runs now use the Profile configuration

Since Track E the smoke runner is compiled into Debug and the new `Profile` configuration only (Release
settings plus `ARKT_SMOKE_BUILD`); the Release binary has no smoke runner. Pacing and `-ArktSmoke YES` runs
above that say "Release binary" now use `-configuration Profile`, product
`build/Build/Products/Profile/ArktShell.app` (the scheme's profile action also uses it). The configuration lives in
`project.yml`, so an existing checkout needs `cd app/ArktShell && xcodegen generate` after pulling before it can
build Profile. Release check, must print `0`:

```zsh
cd app/ArktShell && strings build/Build/Products/Release/ArktShell.app/Contents/MacOS/ArktShell | grep -c ArktSmoke
```

## Text contrast of secondaryText and sidebarForeground (#72)

`ShellTokensContrastTests` (ShellUITests) composites each token over every shipped Space theme surface and
measures it with `Contrast` from #66. Surfaces: the bridge default, the empty-theme white fallback and the
`StubSidebar.sample()` Spaces, each gradient sampled at 33 points per stop pair (a component-wise blend can be
darker than both ends), plus the fills a token sits on at its call sites. Compositing is source-over in Display P3
components; the result is converted to sRGB before `Contrast.ratio`. The grain layer is ignored (soft light,
mean-preserving). Arc-imported themes are user data and not covered.

Targets per token, from the call sites:

- `secondaryText` is text (Space title, URL bar label, toolbar buttons): 4.5:1 over the theme, the URL bar fills
  (`sidebarItemBackground`, `sidebarItemHovered`) and the opaque `toolbarSurface`.
- `sidebarForeground` is icon-only (idle page dots, bottom-bar symbols, hover close X; row titles use
  `primaryText`): 3:1 over the theme and every row fill the hovered row can have.

Worst case, before and after:

| Token | Mode | Before | After | Worst surface |
|---|---|---|---|---|
| `secondaryText` | light | 0.50: 3.16:1 | 0.64: 4.55:1 | hovered URL bar over the pink stop `#F29BBB` |
| `secondaryText` | dark | 0.50: 2.91:1 | 0.76: 4.53:1 | hovered URL bar over the Dev stop `#2D4468` |
| `sidebarForeground` | light | 0.30: 1.92:1 | 0.48: 3.00:1 | close X on a hovered row over `#F29BBB` |
| `sidebarForeground` | dark | 0.45: 2.45:1 | 0.57: 3.00:1 | close X on `tabCurrent` over `#2D4468` |

One step lower (0.63, 0.75, 0.47, 0.56) fails each case, so these are the smallest passing values at 0.01. The
order primary > secondary > sidebar foreground holds in both modes and is asserted. Arc parity: both tokens are
now darker (light) and brighter (dark) than Arc's levels.

Not fixed here: `primaryText` dark (white 0.80) reaches 4.27:1 on `tabCurrent` over `#2D4468`, below 4.5.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 334 tests (327 plus 7 new), XCTest 181 tests
(GUI included), 0 failures. Debug app build: `** BUILD SUCCEEDED **`.

## Toolbar Back and Forward enabled state (#79)

`TabSnapshot` carries `canGoBack` / `canGoForward`, announced with `EngineEvent.historyChanged`. Engine contract
rule 8 (`EngineContract.historyAvailabilityIsReported`) runs against `InMemoryEngine` (Swift Testing) and
`FakeEngine` (ShellKitGUITests): a new tab has neither, a second page enables Back, `goBack` enables Forward,
`goForward` restores Back, and the last `historyChanged` agrees with the snapshot. The rule polls the snapshot and
does not pin the event's position relative to `urlChanged` / `loadingChanged`: WebKit reports `canGoBack` by KVO in
its own order, and history moves served from the page cache may not toggle `isLoading`. `FakeEngine` observes both
properties and copies both flags in each handler, so one back-forward list change emits one event; the flags are
also synced before `loadingChanged(false)`. The FakeEngine rule passed four runs in a row (0.7 to 2.4 s).

The Toolbar's Back and Forward are disabled until the shown tab can move that way; a disabled button sends no
action and VoiceOver reads it as dimmed. `ShellWindowController.toolbarTab` (the current tab for now) is the one
place the Toolbar's target is chosen, for Split View S4 to point at the focused pane.

Remaining: ChromiumEngine (#33) provides the same fields by passing rule 8.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 337 tests (2 new), XCTest 182 tests (GUI included,
9 new), 0 failures. Debug app build: `** BUILD SUCCEEDED **`. Only `FakeEngine.swift` imports WebKit.
