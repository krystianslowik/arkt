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

Not fixed here: `primaryText` dark (white 0.80) reaches 4.27:1 on `tabCurrent` over `#2D4468`, below 4.5 (fixed in
#146, below).

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 334 tests (327 plus 7 new), XCTest 181 tests
(GUI included), 0 failures. Debug app build: `** BUILD SUCCEEDED **`.

## Text contrast of primaryText (#146)

`primaryText` colors row titles, row symbols and the active page dot. `ShellTokensContrastTests` now measures it
with the same probe as #72: 4.5:1 over every shipped Space theme surface, bare and under each row fill
(`tabCurrent`, `tabContentVisible`, `sidebarItemHovered`, `tabPrevious`, `tabPreviousHovered`, `tabPressed`).

| Token | Mode | Before | After | Worst surface |
|---|---|---|---|---|
| `primaryText` | light | 0.90: 6.83:1 | unchanged | |
| `primaryText` | dark | 0.80: 4.27:1 | 0.84: 4.52:1 | `tabCurrent` over the Dev stop `#2D4468` |

0.83 gives 4.46:1, so 0.84 is the smallest passing level at 0.01. The fix raises the text level instead of lowering
`tabCurrent` dark (0.17 would also pass) because it changes one token, keeps the current row clearly brighter than
`tabContentVisible` (0.15), and leaves the `secondaryText` and `sidebarForeground` cases untouched. The order
primary > secondary (0.76) > sidebar foreground (0.57) still holds. Arc parity: dark row titles are brighter than
Arc's 0.80.

Not covered: the letter tile shown for rows without a favicon draws `primaryText` on `sidebarItemHovered` on top of
the row fill. In dark mode on `tabCurrent` over `#2D4468` that nested fill stays below 4.5:1 even at white 1.0
(about 4.1:1), so it needs a change to the tile itself rather than the text level (fixed in #153, below).

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 338 tests, XCTest 182 tests (GUI included), 0
failures. Debug app build: `** BUILD SUCCEEDED **`.

## Letter tile contrast (#153)

The letter tile of a row or favorite without a favicon (`SidebarGlyphs.letter`) draws `primaryText` on a rounded
fill that sits on the row fill. `ShellTokensContrastTests.letterTileReadsOnEveryShippedSurface` measures it with the
same probe as #146, in both flavors: theme, then each row fill `primaryText` sits on (plus none, plus the idle
favorite tile's `sidebarItemBackground`), then the tile fill, then the letter. The letter is treated as text (it
stands in for the site's favicon and is read as an initial), so the test asserts 4.5:1, not the non-text 3:1.

| Mode | Tile fill | Before | After | Worst surface |
|---|---|---|---|---|
| light | P3 `#0E0F10` at 0.10 | 5.78:1 | unchanged | |
| dark | P3 `#FAFBFF` at 0.15, now P3 `#0E0F10` at 0.15 | 3.40:1 | 5.43:1 | `tabCurrent` over the Dev stop `#2D4468` |

The fix is a new token, `ShellTokens.letterTileFill`: light keeps the shipped value (the same as
`sidebarItemHovered` light), dark now darkens the surface instead of lightening it, so both flavors draw the tile
as the palette's dark ink at a low level. `primaryText` is unchanged. Alternatives measured and dropped: white 1.0
ink on the old tile reaches 4.09:1; a fainter light tile makes it worse (`#FAFBFF` at 0.05: 4.10:1); no fill
passes with no headroom (4.52:1) and loses the tile shape. Black at 0.12 (5.36:1) is equivalent; `#0E0F10` matches
the light tile. On the darkest shipped dark stop (`#120F2E`, bare row) the dark tile is barely visible; the letter
still reads there, which is what the tile is for.

Fill and ink depend on the flavor only, so the bitmap cache key (`letter-<letter>-<flavor>@<size>x<scale>`) is
unchanged. `SymbolImageCacheTests.letterTileIsFilledWithItsFlavorsTileToken` checks the drawn fill against the
token per flavor and that the two flavors are separate cache entries.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 406 tests (2 new, each run for both flavors),
XCTest 261 tests (GUI included), 0 failures. The new contrast test failed first at 3.40:1 (dark). Debug app build:
`** BUILD SUCCEEDED **`.

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

## Favorite tiles: hover close (X) (#82)

A Favorite tile shows the X (`SidebarGlyphs.close`, the rows' glyph and fade) in its top trailing corner while it is
hovered and its page is loaded. The X and VoiceOver's "Close" custom action call `FavoritesGridView.onClose`, which
`SidebarController` forwards to the same `onClose` the rows use, so the window runs `close(node:)` as Cmd-W does: the
page closes, the Favorite stays, nothing is archived (`RowCloseAction.closeFavorite`, tooltip "Close this tab" [I]).
A tile without a loaded page shows no X and has no custom action.

"Loaded" is `SidebarController.loadedNodes`: a tab is inserted on activation (activating shows the tab, which creates
its page) and removed in `deactivate(node:)`, which the window calls on `.tabClosed`. It is per window, like the close
path. Closing a background Favorite reloads that tile from `deactivate`, so its X hides at once under a still
pointer. `ShellWindowController` is unchanged.

Hover resync: the guard from `SidebarRowView.resyncHoverWithPointer` moved unchanged into a shared
`NSView.resyncHoverWithPointer(_:)` (`HoverResync.swift`); rows and tiles call it from `updateTrackingAreas`. The
guard's polish (child panels, fade interruption, Reduce Motion) stays with #87 and now applies to both. Frames are set
directly in `layout()`; no per-frame work. Metrics `favoriteCloseButtonSize` (16) and `favoriteCloseButtonInset` (3)
are TODO(measure).

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 359 tests, XCTest 193 tests (GUI included, 11 new in
`FavoriteTileCloseTests`, baseline 182), 0 failures. Debug app build: `** BUILD SUCCEEDED **`.

## Command bar keys and hover selection (#95)

RT-08 (KB-084, KB-085) has not been run against Arc, and the spec has no `[S]` or `[O]` evidence for these keys,
so every rule below is `[I]` and marked as such in the code:

| Key | Behavior | Source |
|---|---|---|
| Esc | closes the bar (unchanged) | KB-084 [I] |
| Enter on an empty query | takes the first result, which is the first open tab; closes the bar when there are no tabs (unchanged, now pinned by tests) | [I] |
| Cmd-Enter, Opt-Enter | open the selected result in a new tab from Cmd-T and Cmd-L alike; never reload on an unedited Cmd-L; a "Switch to Tab" result still switches | KB-085 [I], Chromium omnibox convention |
| Up / Down (Ctrl-P / Ctrl-N) | move by one and wrap at both ends | KB-085 [I] |
| PageUp / PageDown | move by `maxVisibleRows` and stop at the ends | [I] |
| Pointer | a pointer move over a row selects it; a pointer resting where the bar appears changes nothing | [I] |

Cmd-Return has no field editor binding, so the panel's `sendEvent` hands Return / keypad Enter with exactly Cmd or
Opt to the controller (not during IME composition); menu key equivalents still run first. Shift-Return (KB-086,
Arc Max) is not taken over. The selection math is the pure `CommandBarSelection` (Swift Testing). Hover uses one
tracking area installed in `CommandBarView.init`; `show()` and `reloadResults()` are unchanged.

Menu routing: `testMenuActionsReachTheShellWhileTheBarIsKey` checks that nothing in the panel's responder chain
takes `newTab:` / `openLocation:`, that the panel cannot become main, and that the shell window's chain reaches
`ShellWindowController`, which closes the bar (KB-003). The test runner cannot activate itself, so the nil-target
`NSApp.sendAction` path runs only when the app is active.

Remaining: run RT-08 and adjust the `[I]` rules (Esc, empty-query Enter, Cmd-Enter vs Opt-Enter, wrap). If Arc's
Cmd-Enter opens a background tab (Chromium's Mac convention), the shell needs a background-open hook in
`ShellWindowController`.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 368 tests (359 + 9), XCTest 208 tests (193 + 15,
GUI included), 0 failures. `commandbar.showcpu.ms median=0.92 p95=1.18`; earliest-frame not asserted (load 33.6 on
10 cores). Debug app build: `** BUILD SUCCEEDED **`.

## Row hover X: resync guard and fade polish (#87)

Hover resync guard: tracking areas are `.activeAlways`, so hover shows in background windows too, and the old guard
(active app and key window only) left a stale X after scrolling a window that was not key. The resync now runs in any
visible window and keeps the existing covered check: when another window is frontmost under the pointer (the presented
command bar panel, another app's window), the rows and tiles under it drop their hover. A window that is not visible
is left alone.

One lookup per host: rows and tiles no longer query the window server from `updateTrackingAreas`. They ask their host
(`SidebarOutlineView`, `FavoritesGridView`, both `HoverResyncHost`), which coalesces every request of a scroll or a
reload into one `NSWindow.windowNumber(at:)` call on the next main-queue turn and syncs all realized rows or visible
tiles from it (`HoverResyncScheduler` in `HoverResync.swift`). The pointer and window-server reads sit behind
`HoverPointerLookup`, which the GUI tests replace, so they exercise `resyncHoverWithPointer()` without depending on
key-window state.

Fade: rows and tiles share `HoverCloseButton`. Every show or hide bumps a generation; a fade's completion hides the
button only while it is the latest, so a fade-out that replaces a running fade-in no longer hides the X early (the
replaced fade's completion runs at once). An interrupted fade starts from the opacity on screen and lasts the remaining
share of `closeButtonFadeDuration` (`HoverCloseFade.duration`). With Reduce Motion the X appears and hides at once.

`SidebarController.loadedNodes` is pruned with the favicon cache on `.structure` and `.spaces` changes, so nodes that
leave the source drop out even without a window reporting the closed page. `deactivate(node:)` on the current or
previous Favorite no longer reloads its tile before the row-state refresh, which configures every visible tile once.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 388 tests (384 + 4, new in `HoverCloseFadeTests`),
XCTest 235 tests (224 + 11, GUI included; 6 new in `RowCloseButtonTests`, 5 new in `FavoriteTileCloseTests`),
0 failures. Debug app build: `** BUILD SUCCEEDED **`.

## Command bar URL parsing edge cases and duplicate rows (#96)

`URLInputParser` rules added, checked against Chromium 156 (`net::IsCanonicalizedHostCompliant`,
`AutocompleteInput::Parse`); Arc unverified:

| Input | Before | Now | Source |
|---|---|---|---|
| `example.com.` (trailing dot) | query | `https://example.com.` (dot kept) | Chromium canonical host keeps it |
| `my_host.example.com`, `_dmarc.example.com` | query | URL | underscores allowed in labels; TLD stays letters only |
| `user@example.com` | query | query | omnibox: `user@host` alone is an email address, search by default |
| `user:pass@example.com`, `user@example.com/inbox`, `user@example.com:8443` | query | URL | omnibox: password, or more than one non-host component |
| `010.0.0.1`, `192.168.01.1` | URL (decimal) | query | Chromium reads leading-zero parts as octal; rejected instead of canonicalised |

With an explicit scheme (`http://010.0.0.1`) the input still opens and the engine canonicalises the host.

Duplicate rows: an input with an explicit http(s) scheme (Cmd-L prefills one) no longer gets a "Search Google" row
repeating it, and the open row drops a subtitle equal to its title. Chromium keeps a demoted search-what-you-typed
row there; Arc unverified [I] (RT-08). Schemeless input such as `example.com` keeps both rows.

Also from the #157 review: hover selects only rows inside the table's visible rect; the
`insertNewlineIgnoringFieldEditor:` fallback opens a new tab only for an actual Opt-Return (other bindings commit
like Return); `MainMenuKeyEquivalentTests` builds the app's main menu (`App/MainMenu.swift`, linked into the GUI
test target with a stub `AppDelegate`) and checks that no item binds Cmd-Return or Opt-Return, which the panel's
`sendEvent` takes first. `show()` and `reloadResults()` are unchanged.

Checks (rebased on #158): `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 392 tests (388 + 4), XCTest 240
tests (235 + 5, GUI included), 0 failures. `commandbar.showcpu.ms median=0.29 p95=0.44`; earliest-frame not
asserted (load 13.1 on 10 cores; `p95=17.53 bound=19.89`). Before the rebases the same suite gave
`commandbar.earliestframe p95=17.25 bound=17.88 load1=9.72 cores=10 asserted=yes`. ArktCore `swift test`: 336
tests, 0 failures. Debug app build: `** BUILD SUCCEEDED **`.

## Measured Arc values applied to the shell tokens (#186)

Source: `docs/plans/2026-10-23-arc-measurements.md` (Arc 1.168.0, one 1800 x 1072 pt window on a 2x display, Dark,
window not key, Toolbar on). 18 of the 39 `TODO(measure)` markers are gone; 21 stay for #77's interaction checklist.
Each changed value carries an "Arc 1.168" comment pointing at that file.

| Token | Before | Now | Note |
|---|---|---|---|
| bottom bar button size (`SidebarMetrics.bottomBarButtonSize`, was a literal) | 28 | 32 | 8 pt from both sidebar edges |
| `titleTrailing` | 10 | 9 | inferred (assumes the 8 pt row inset) |
| `spaceTitleHeight` | 28 | 36 | |
| `dividerHeight` | 13 | 25 | hairline inset 18 pt from the sidebar edges and 11.5 pt from the row top, as before |
| `indentationPerLevel` | 14 | 16 | |
| `favoritesTopGap` | 4 | 8 | Toolbar-on layout only: strip to tiles. Toolbar off it follows the URL bar, not measured |
| `favoritesBottomGap` | 10 | 8 | |
| `bottomBarHeight` | 36 | 50 | |
| `spaceDotSize` | 6 | 4 | color kept, see deviations |
| `spaceDotSpacing` | 8 | 17.5 | 21.5 pt pitch |
| `toolbarSurface` | white / P3 #1C1C20 | unchanged | measured, not applied, see deviations |
| Toolbar `height` | 40 | 33 | 32 pt strip plus a 1 pt hairline (was one device pixel) |
| Toolbar `buttonSize` | 28 x 28 | 32 x 24 | 5 pt apart (`buttonSpacing`), 4 pt from the top |
| Toolbar `iconSize` | 14 | 14 | confirmed (inferred from glyph boxes) |
| Toolbar `horizontalPadding` | 8 | 5 | |
| Toolbar `urlBarHeight` | 28 (pill) | 24, no pill | see behavior |
| `trafficLightOrigin` | (16, 16) | (12, 16) | |
| `sidebarTopBarHeight` | 44 | 36 | Toolbar-on layout only |

Alpha-dependent levels, measured in the non-key dark 2x window and marked so in their comments: the sidebar divider
(new `ShellTokens.sidebarDivider`, dark white 7.5 %, light unchanged), the Toolbar hairline (new
`ShellTokens.toolbarHairline`, dark white 5 %, light the card border's black 10 %) and the Space dot (not applied).

Related values (not tokens), decided here:

- Applied: traffic-light pitch 20 -> 23 (`trafficLightSpacing`, exact AX) and `cardInsetTop` 9 -> 10 (the card now
  has even 10 pt insets).
- Not applied: sidebar width 192 (that window's resized width, not a default; Arkt keeps 190), Favorites tile height
  47 and gap about 8.2 (depend on the sidebar width; FavoritesLayout keeps 46 and 9 until #77 measures them at a known
  width), the 3 pt spacer row at the top of the tab list, the sidebar toggle next to the traffic lights and Arc's
  trailing Toolbar button (Arkt has neither), and the Toolbar URL font size (about 11 to 12 pt, inferred; it shares
  `urlBarFontSize`, still a #77 token).

Behavior:

- The sidebar URL bar hides while the Toolbar is on (`SidebarContainerView.showsURLBar`, set by
  `ShellWindowController.applyToolbarVisibility`); the Favorites move up to 8 pt below the 36 pt strip (tiles at
  y 44), as in Arc.
- The Toolbar URL is plain text centered in the strip: no fill, border, radius or hover fill. Its frame keeps the
  same inset on both sides (the width of the button cluster), so it stays centered in the card and clear of the
  buttons. The press target is 24 pt tall like the buttons (Arc's text frame is 16 pt).
- The titlebar container that hosts the traffic lights is now as tall as the strip (36 pt) instead of
  `2 * origin.y + button height` (48 pt). With the shorter strip the old height would have covered the top 8 pt of the
  sidebar URL bar (Toolbar off); `URLBarTests` now hit-tests the bar's top edge too.

Deviations (accessibility first):

- `toolbarSurface` keeps Arkt's opaque values. Arc draws the strip on the card's own surface, sRGB #878787 in the
  measured theme, where `secondaryText` (dark white 0.76) reaches about 2.8:1 (Arc's own placeholder 2.75:1), below
  4.5:1. `ShellTokensContrastTests.arcsMeasuredToolbarSurfaceWouldFailSecondaryText` records it.
- Idle Space dots keep `sidebarForeground` (3:1 non-text, #72); Arc's dot is about white 8 % over the theme.

Also in this change (follow-up from the #188 review): `EnvironmentOverrides.isUsableSuiteName` rejects
`ARKT_DEFAULTS_SUITE` names that contain a slash or start with a dot, and compares against the bundle id and
`NSGlobalDomain` without regard to case.

Checks (rebased on #187 and #189): `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 423 tests (416 + 7: 2 in
`EnvironmentOverridesTests`, 2 in `TabRowStateTests`, 2 in `ShellLayoutTests`, 1 in `ShellTokensContrastTests`), XCTest
285 tests (280 + 5 in `URLBarTests`, GUI included), 0 failures. Pacing asserted: `space-swipe` and `space-key` 0 frames
over 8.6 ms (load 9.79 on 10 cores); command bar earliest frame not asserted (load 11.7, `p95=16.81 bound=18.05`).
Debug app build: `** BUILD SUCCEEDED **`.

## Manual checks (#26) (2026-10-23)

Maintainer pass on the Release build of `main` at `ba0c281` (ad-hoc signed), 120 Hz display. Issue #26 stays open: three
checks remain.

- Trackpad Space swipes: PASS. 20 real two-finger swipes (both directions) logged 20 `pacing label=space-swipe` lines
  from the app process; every one had `over8.6=0`, `maxMs=8.33`, `p99Ms=8.33`, frames 22 to 77. No hitches. The xctest
  lines in the same window came from concurrent automated test runs and are excluded.
- Cmd-T with the window in fullscreen: PASS. The command bar opens correctly.
- Cmd-T on a second desktop: not run yet.
- Move between a 1x and a 2x display: not run yet.
- Quit within the save window and the recovery toast: not run yet. The Release build ignores `ARKT_DATA_DIR` by design
  (environment overrides are honoured only in Debug and Profile builds), so this check, like the save one in the Track E
  results, must use a Debug build.

## Space dock scrolls when the dots overflow (#193)

With the measured 21.5 pt pitch (#186) only 5 dots fit between the archive and new-tab buttons at the default 190 pt
sidebar (110 pt slot) and 4 at the 150 pt minimum (70 pt slot); more drew over the buttons and could not be clicked.
Arc's dock is a scroll area (measurement doc, `bottomBarHeight` row), so the dock now scrolls.

- `SpaceDockLayout` (pure geometry, Swift Testing): dots stay centered while they fit; otherwise they sit on a strip
  with half a gap before the first dot and after the last, and the strip scrolls. `offsetRevealing` scrolls only as
  far as needed to show a dot's whole hit box.
- `SpaceDotsView` clips the dots to its bounds and moves one strip layer to scroll (frames set directly, actions
  off). Trackpad and scroll wheel scroll it (a vertical wheel scrolls sideways; wheel lines move one dot); there is
  no visible scroller. When the dots fit, scroll events go up the responder chain as before.
- Edges fade (a gradient mask, 8.75 pt, half a gap) only on the sides where dots are hidden.
- The current Space's dot is scrolled into view on every Space change, and during a swipe the dot nearest the
  fingers follows. The swipe path only compares an offset and, when it changes, moves the strip and re-sets the
  accessibility frames: no layout and no redraw.
- Accessibility: every dot stays a child button (VoiceOver can still move to it and press it, which selects the
  Space and scrolls the dot into view). Frames are clipped to the dock; a dot scrolled out reports a 1 pt sliver at
  the edge it left by (an empty frame reads as the screen origin).
- Width changes and Space count changes re-clamp the strip; removing Spaces until they fit centers them again.

Not measured: Arc's exact overflow behavior (fade, scroll indicator, reveal animation). The reveal is immediate, not
animated. Left for #77's interaction checklist.

Checks (rebased on #194): `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 431 tests (423 + 8 in
`SpaceDockLayoutTests`), XCTest 299 tests (293 + 6 in `SpaceDockOverflowTests`: 5, 7 and 12 Spaces at 150 and 190
pt; no overlap with the buttons, current dot visible, accessibility frames inside the dock, clicks select the dot
under the pointer, scroll wheel, swipe without relayout, back to centered), 0 failures apart from one pacing frame:
`space-key` had 1 frame of 17 ms (load 5.5; the 3-Space fixture fits, so the dock does no scroll work there). The
rerun of `testFramePacingDuringSwipeAndKeyboardSwitch` asserted `space-swipe` and `space-key` at 0 frames over 8.6 ms
(load 4.98). Debug app build: `** BUILD SUCCEEDED **`.

## Space removal and Space-level change events (#86)

Decision on #86 (maintainer, 2026-10-23): deleting a Space that has pinned tabs or folders asks for confirmation
first, then moves its pinned items and Today items to the Archive (restorable).

Model and archive:

- `Sidebar.removeSpace(_:)` drops a Space with every node in its Pinned and Today sections; Favorites belong to the
  profile and stay. An unknown id is a no-op, like `remove(_:)`.
- `Archiver.removeSpace(_:from:at:)` archives the Space's top-level Pinned items, then its Today items (reason
  `.manual`, source `.space(id)`, one entry per item), then removes the Space. A restore of such an entry uses the
  default rules in the fallback Space (folders to Pinned, tabs and splits to the top of Today).
- `ModelSidebarSource.removeSpace(_:at:)` does both in one mutation (one autosave, one Space event; the removed
  Space's sections emit no structure change). `ArchiveCoordinator.removeSpace(_:)` queues the entries through the
  same outbox as `archive`.

Events (C6 review M10): `SidebarChange.spaces` is replaced by `.spaceAdded`, `.spaceRemoved`, `.spaceMoved` and
`.spaceChanged` (title, profile or theme), each with the Space's id. `SidebarDiff` reports them first, removed in the
old order, then added, moved and changed in the new order. `.spaceMoved` goes to the Spaces outside a longest run that
kept its relative order, so a drag reports the dragged Space and an add or removal alone reports no move.
`StubSidebar` gains `moveSpace(_:to:)`. The window's engine-tab cleanup now runs on `.structure` and `.spaceRemoved`
only (no longer on renames and theme changes).

Shell: when the current Space is removed, the Space after it becomes current, else the one before it [I]
(PARITY(NEEDS-RUNTIME-CHECK): which Space Arc shows); before, it was always the first Space. The dots' selected index
follows the current Space when Spaces move or an earlier one is removed. Removing the last Space shows the empty state
(unchanged).

Not in this change: the menu entry and the confirmation sheet (no Space context menu exists yet), and BH-158 (routes
to a removed Space are deleted), which waits for link routing in #113.

Checks (rebased on #192, #195, #197, #198, #200, #202 and #204): `nice -n 10 swift test -j 4` in ArktCore: 342 tests
(336 + 6: 2 in `SidebarTests`, 4 in `ArchiverTests`), 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing
442 tests (433 + 9: 4 in `SidebarDiffTests`, 2 in `SidebarModelStubTests`, 1 in `ModelSidebarSourceTests`, 2 in
`ArchiveCoordinatorTests`), 0 failures. ShellKit `--filter ShellKitGUITests`: XCTest 322 tests (317 + 5: 4 in
`SpaceListChangeTests`, 1 in `CloseTabTests`), 0 failures; pacing asserted, `space-swipe` and `space-key` 0 frames
over 8.6 ms, command bar earliest frame asserted (load 5.44 on 10 cores). Debug app build: `** BUILD SUCCEEDED **`.

## Command bar: follow the parent window (#97)

- The open bar follows its parent window: `CommandBarController` observes the parent's `didMove`, `didResize` and
  `didChangeScreen` notifications and sets the panel frame from `CommandBarGeometry` (no layout or reload; an equal
  frame is skipped). A closed bar does nothing on these notifications; the next show places it, as before.
- Prewarm lays the panel out over the parent window (alpha 0 and inert, the state a hidden bar is in after a hide)
  instead of at (-10000, -10000), so it is warmed on the parent's display and at its backing scale.
- Not changed: icons of an open bar keep their scale until the next show when the parent moves to a display of
  another scale (the show-time scale check stays). The "move between a 1x and a 2x display" manual check (#26) covers
  it.

Tests (written first, 4 failed before the change; the fifth guards the closed-bar case): `CommandBarTests`
`testPrewarmPutsThePanelOnTheParentScreen`, `testOpenBarFollowsTheParentWhenItMoves`,
`testOpenBarFollowsTheParentWhenItResizes`, `testOpenBarRepositionsWhenTheParentChangesScreen` (one display in tests:
the panel is displaced and the parent's screen change is posted) and `testClosedBarDoesNotFollowTheParent`. They wait
on conditions, not timers.

Checks: `nice -n 10 swift test -j 4` in ShellKit: Swift Testing 424 tests, XCTest 315 tests (310 + 5, GUI included),
0 failures. Latency gate (#25) unchanged: `commandbar.showcpu.ms p95=0.24`, `commandbar.earliestframe p95=10.38
bound=17.42 load1=5.14 cores=10 asserted=yes`. Rebased on #198 and #204: Swift Testing 433 tests, XCTest 322 tests
(317 + 5), 0 failures; `commandbar.showcpu.ms p95=0.31`, `commandbar.earliestframe p95=11.16 bound=17.73 load1=11.74
asserted=no`. Debug app build: `** BUILD SUCCEEDED **`.

## Delete Space: menu entry and confirmation (#206)

- Spaces menu > Delete Space... (after a separator, no key) calls `ShellWindowController.deleteSpace(_:)`. It asks
  through the injectable `confirmSpaceRemoval` (default: an alert sheet on the window, "Delete Space" marked
  destructive and without a key, so Return never deletes; "Cancel" keeps Escape), then hands the Space it asked about to `onRemoveSpace`, which `AppSession` wires to
  `ArchiveCoordinator.removeSpace` (decision on #86: pinned and Today items go to the Archive). An answer for a Space
  that is already gone does nothing; another Space becoming current while the sheet is open does not change which
  Space is removed.
- Every Space asks, empty and Today-only ones included: the Space itself (name, theme) cannot be restored from the
  Archive. The text says where the items go, or "This cannot be undone." for an empty Space.
- Last Space: removal is allowed and shows the empty state (decision on #86). The item is disabled with no current
  Space, no `onRemoveSpace` or while a sheet is open, so a second request queues no second sheet.
- [I] PARITY(NEEDS-RUNTIME-CHECK): the menu title and place and the confirmation wording; the parity spec has no
  Delete Space flow. No Space context menu exists yet.

Checks (`nice -n 10`, `-j 4`, rebased on #216): ArktCore 342 tests (342 + 0), 0 failures. ShellKit
`--skip ShellKitGUITests`: Swift Testing 455 tests (452 + 3 in `SpaceRemovalPromptTests`), 0 failures. ShellKit
`--filter ShellKitGUITests`: XCTest 350 tests (341 + 9: 8 in `DeleteSpaceTests`, 1 in `MainMenuKeyEquivalentTests`),
0 failures; pacing not asserted at load 11.65 (`space-key` 2 frames over 8.6 ms; before the rebase, at load 3.09,
`space-swipe` and `space-key` 0 frames, asserted). Debug app build: `** BUILD SUCCEEDED **`.

## Command bar: cross-display icon scale and closed-panel screen change (#212)

- Open bar across displays of different backing scales: `CommandBarController` now also observes the parent window's
  `didChangeBackingProperties` notification and runs `refreshCellScaleIfNeeded()` from `parentFrameDidChange(_:)`
  whenever `isVisible`. When `backingScale != cellScale`, the table reloads at the new `cellScale` and restores the
  selected row index, so result icons are re-rendered immediately without waiting for the next `show()`.
- Closed panel on `didChangeScreen`: `parentFrameDidChange(_:)` now updates the hidden (alpha 0) panel's frame on
  `didChangeScreenNotification` only (ordinary `didMove` and `didResize` notifications while closed still do nothing).
  Moving the hidden panel when the parent crosses displays takes the `panel.setFrame` window-server call out of the
  first `show()` after a display change (`with-closed-follow`: `show()` CPU median 0.20 ms / p95 0.21 ms, wall median
  0.27 ms / p95 0.31 ms, total p95 9.07 ms <= bound 9.15 ms; `without-closed-follow`: `show()` CPU median 0.23 ms /
  p95 0.25 ms, wall median 0.34 ms / p95 0.39 ms, total p95 7.43 ms <= bound 9.22 ms).
- Tests (`CommandBarTests`, waiting on conditions via `waitUntil`): `testOpenBarReRendersIconsWhenBackingScaleChanges`
  and `testClosedBarDoesNotFollowTheParent` (extended for `didChangeScreen`).

Checks: ArktCore 342 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 456 tests, 0 failures.
`CommandBarTests`: 52 tests, 0 failures (`commandbar.showcpu.ms p95=0.28`, `commandbar.earliestframe p95=9.24
bound=9.54 load1=11.23 cores=12 asserted=yes`).

## Toolbar: host-only URL option (#80)

- `ToolbarSetting.showsFullURL` (stored under Arc's key `toolbarShowFullURLsEnabledPreference` in user defaults,
  default `true` until RT-30 is measured) notifies every observing window through `toolbarSettingDidChange(_:)`.
- `URLBarView.style` is now mutable and refreshes `displayedText`, `label.stringValue` and `accessibilityValue` live
  between `.full` and `.host` while keeping the Toolbar URL bar's centered plain-text layout (`showsPill` stays fixed
  from `init(style:)`).
- `ShellWindowController.applyToolbarVisibility()` and `configurePaneToolbars()` propagate `showsFullURL` to the card's
  Toolbar and every Split View pane card's Toolbar.
- Tests: `ToolbarSettingTests` (key name, default `true`, persistence, ephemeral, observer notification) and
  `URLBarTests.testShowsFullURLSwitchesToolbarURLBarBetweenFullAndHostLive`.

Checks: ArktCore 342 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 456 tests, 0 failures.
`URLBarTests`: 22/22 GUI tests pass.

## Space pager edge cases: overshoot catch, resize during swipe, flavor flip (#99)

- M3 (overshoot catch): `PagingMath.unrubberBand(_:dimension:)` and `PagingMath.initialTranslation(offset:index:pageWidth:count:)`
  invert the rubber-band resistance when `offset` is already overshot past the first or last page, so `beginTracking()`
  followed by `track(delta: 0, at:)` keeps the exact overshot position instead of applying `rubberBand` a second time.
- M4 (resize during swipe): `SpacePagerView.layout()` now recomputes `offset` via
  `PagingMath.offset(index: dragBase, translation: translation, pageWidth: width, count: pages.count)` when
  `isTracking` is true and `width != laidOutWidth`, so both page frames and the strip offset follow a sidebar resize
  during an active swipe.
- M9 (flavor flip at the halfway point): `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` now also runs a
  20-frame scripted swipe from `Dev` (`.dark`) to `Work` (`.light`) (`space-swipe-flavor`, crossing the halfway
  `.darkAqua` -> `.aqua` flip). Measured: `frames=67 over8.6=0 maxMs=8.33 p99Ms=8.33 hitchesMs=[]` (each
  `SpacePageView` pins its own `appearance`, so the chrome flavor flip does not invalidate row views inside the pages).
- Tests: `PagingMathTests.initialTranslationInvertsRubberBandOnOvershoot`,
  `SpacePagerTests.testCatchingAnOvershootingSettleKeepsTheExactPosition`,
  `SpacePagerTests.testPageWidthFollowsASidebarResizeDuringASwipe`, and `space-swipe-flavor` in
  `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch`.

Checks: ArktCore 345 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 458 tests (+1
`PagingMathTests`), 0 failures. `SpacePagerTests`: 20/20 GUI tests pass (+2).

## Sidebar follow-ups from the Track C C3 review (#94)

- `StubSidebar.moveNode(_:to:at:)` implements `Sidebar.move`'s index-before-removal convention, ignores unknown nodes or
  destinations and moves into a node's own subtree, and emits `.structure` only for locations whose child order changed.
- `SidebarOutlineController` tracks user-collapsed folders (`collapsedFolders: Set<NodeID>`) and expands inserted
  containers through `expandContainer(_:)`, so outline removals and within- or cross-section moves preserve folders'
  expanded or collapsed state. Expanded folders show `folder.fill` and collapsed folders show `folder` (both prewarmed
  in `SymbolImageCache.sidebarSymbols`).
- `SidebarRowView.isPressed` immediately updates `backgroundLayer.backgroundColor = displayedFill?.cgColor` (with
  implicit animations disabled) in addition to `needsDisplay = true`, so the 6.5% pressed fill (`ShellTokens.tabPressed`)
  is visible on the layer during `NSOutlineView`'s modal mouse tracking loop without waiting for a later layout pass.
- `FavoritesCollectionView` accepts first responder and routes arrow-key navigation (`moveRight`, `moveLeft`,
  `moveDown`, `moveUp`, and `keyDown` for arrow key codes) to `FavoritesGridView.moveKeyboardFocus`, stepping across the
  3-column Favorites grid and activating the destination tile.
- Tests: `SidebarModelStubTests.removeNodeAndMoveNodeFollowIndexBeforeRemovalAndSubtreeRules`,
  `SymbolImageCacheTests.prewarmRendersEveryShellSymbolForBothFlavors` (`folder.fill`), and
  `SidebarViewTests.testFolderExpansionIconPreservedAcrossMovesPressedLayerFillAndFavoritesKeyboard`.

Checks: ArktCore 348 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 459 tests (+1
`SidebarModelStubTests`), 0 failures. `SidebarViewTests`: 18/18 GUI tests pass (+1).

## Space switching: mouse buttons 3 / 4, wrap at the ends, swipes from the Favorites grid and bottom bar (#98)

- GS-002, BH-035: `ShellWindow.sendEvent(_:)` routes `.otherMouseDown` with `buttonNumber == 3` or `4` to
  `otherMouseDown(with:)`, and `ShellWindowController.otherMouseDown(with:)` switches to `previousSpace(nil)` on button 3
  and `nextSpace(nil)` on button 4 anywhere in the window (leaving button 2 middle-clicks untouched).
- Stop-at-the-ends (`nextSpace` / `previousSpace`): kept as `[I]` (`PARITY(NEEDS-RUNTIME-CHECK #78)`) and pinned at both
  ends for keyboard (`Cmd-Opt-Right` / `Cmd-Opt-Left`) and mouse buttons 3 / 4 while `#78` is open.
- M1, GS-001: `SidebarContainerView.scrollWheel(with:)` forwards trackpad gestures (`event.phase != [] ||
  event.momentumPhase != []`) to `pager.scrollWheel(with:)`, so horizontal swipes starting over the Favorites grid, the
  bottom bar, or other sidebar chrome outside the outline page the Spaces.
- Tests (`SpacePagerTests`): `testMouseButtons3And4SwitchToPreviousAndNextSpaceAndStopAtEnds` and
  `testHorizontalGestureOverFavoritesGridAndBottomBarReachesThePager`.

Checks: ArktCore 348 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 459 tests, 0 failures.
`SpacePagerTests`: 22/22 GUI tests pass (+2).

## Toolbar: history menus and modifier clicks on Back, Forward and Reload (#81)

- Engine API (`EngineClient`, `InMemoryEngine`, `FakeEngine`, `EngineContract` rules 9 and 10):
  - `HistoryEntry` (`url`, `title`) and `TabHistory` (`back` and `forward`, both ordered nearest-first).
  - `history(of:) -> TabHistory?`, `goToHistory(_:offset:)` (`-k` = `k` steps back, `+k` = `k` steps forward), and
    `duplicateTab(_:) -> TabID?` (copies the source tab's URL, title and back/forward history, `BH-027`).
- `ToolbarNavigationButton` & `ContentToolbarView`:
  - Right-click (`menu(for:)`), Ctrl-click, long-press (`ToolbarNavigationButton.longPressDuration`), and VoiceOver
    Show Menu (`accessibilityPerformShowMenu()`) on Back and Forward present `backHistoryMenu()` /
    `forwardHistoryMenu()` (`GS-024`, `BH-166`); choosing an item jumps via `onSelectHistory` ->
    `engine.goToHistory(_:offset:)`.
  - Cmd-click or middle-click (`buttonNumber == 2`) on Back or Forward opens the nearest back/forward entry in a new
    background Today tab in the current Space without changing the active tab (`GS-025`, `BH-165`).
  - Cmd-click on Reload duplicates the current tab into Today with its back/forward history and activates the duplicate
    (`GS-026`, `BH-027`).
  - Both the single-card Toolbar and Split View pane card Toolbars wire all history menu and modifier-click handlers.
- Navigation controls when the Toolbar is off: recorded as a parity gap pending the interactive Toolbar-off measurement
  pass (`docs/plans/2026-10-23-arc-measurements.md`, interaction checklist item 4; in the passive Toolbar-on capture,
  only the 28 x 28 sidebar toggle button at `(77, 9.5)` was present next to the traffic lights).
- Tests: `EngineContract.historyEntriesAndOffsetNavigation` and `EngineContract.duplicateTabCopiesURLTitleAndHistory`
  (in `InMemoryEngineContractTests` and `FakeEngineContractTests`), plus
  `ToolbarHistoryTests.testBackAndForwardHistoryMenusListEntriesAndJumpToSelectedOffset`,
  `testCommandClickAndMiddleClickOnBackAndForwardOpenEntryInBackgroundTodayTab`, and
  `testCommandClickReloadDuplicatesCurrentTabWithHistory`.

Checks: ArktCore 348 tests, 0 failures. ShellKit `--skip ShellKitGUITests`: Swift Testing 461 tests (+2
`InMemoryEngineContractTests`), 0 failures. `ToolbarHistoryTests`: 11/11 GUI tests pass (+3);
`FakeEngineContractTests`: 16/16 GUI tests pass (+2).

## Command bar: makeKey latency tail (#25)

- Root cause of the remaining warm-show latency tail:
  1. `prewarm()` ended by clearing `results = []` and reloading an empty table, and did not install the field editor
     (`panel.makeFirstResponder(barView.field)`), so the first show after launch rebuilt the open-tab cells, resized the
     panel via `setFrame` (a window-server round trip), and attached the field editor.
  2. Every warm `show(.newTab)` unconditionally assigned `barView.field.stringValue = ""` (resetting the active field
     editor `NSTextView` and marking the field dirty inside the show's Core Animation transaction), called
     `selectAll(nil)` on an empty string, and called `barView.table.selectRowIndexes([0])` even when row 0 was already
     selected.
  3. In `SmokeRunner.measureShow`, `waitFor` polled at 5 ms intervals and then slept 30 ms (`3.6` 120 Hz intervals),
     waking `5-7.5 ms` into a `8.33 ms` frame (`~1 ms` before vsync) so `panel.makeKey()` (`~1.2 ms`) straddled the
     vsync boundary.
- Fix:
  - `CommandBarController.prewarm()` installs the field editor on `barView.field` and finishes with `reloadResults()`
    and `setPanelFrame(frame(in: parent), display: true)` so the open-tab cells and panel height are already warm before
    the first show.
  - `CommandBarController.show(_:)` skips `barView.field.stringValue = targetText` when the text is unchanged, skips
    `selectAll(nil)` when `targetText.isEmpty`, and `reloadResults()` skips `selectRowIndexes([0])` when row 0 is
    already selected.
  - `SmokeRunner.waitFor` polls at 1 ms and `measureShow` sleeps 25 ms (`3 x 8.33 ms` frames) after hide so warm shows
    do not start on top of a vsync edge.
- 3 Profile smoke runs (`./build/Build/Products/Profile/ArktShell.app/Contents/MacOS/ArktShell -ArktSmoke YES`):
  - Run 1: `commandBarWarmP95Ms = 12.36 ms` (bound `12.81 ms`, warm shows `6.28 - 12.96 ms`, `functional = PASS`)
  - Run 2: `commandBarWarmP95Ms = 12.54 ms` (bound `13.06 ms`, warm shows `5.75 - 16.12 ms`, `functional = PASS`)
  - Run 3: `commandBarWarmP95Ms = 12.48 ms` (bound `12.32 ms`, warm shows `7.86 - 17.47 ms`, `functional = PASS`)
  - All 3 of 3 runs have warm-show p95 under 18 ms (`12.36 / 12.54 / 12.48 ms`).
- `CommandBarTests` (53/53 GUI tests pass, including interactive/delegate checks for Cmd-T/Cmd-L toggles, Esc,
  click-through while hidden, key hand-back after reactivation, and
  `testWarmShowWithEmptyFieldPrewarmsEditorAndSkipsRedundantSelectionNotification`):
  `commandbar.showcpu.ms median=0.15 p95=0.17`, `commandbar.showwall.ms median=0.18 p95=0.47`,
  `commandbar.earliestframe p95=6.55 bound=9.30 load1=6.75 cores=12 asserted=yes`.

## Space swipe: single late frame under load (#24) (2026-10-24)

Evidence without Instruments: a run loop probe in the pacer, a GUI test that measures main-thread CPU per run loop
pass, and `sample` (1 ms) on the test process. Machine: 120 Hz built-in panel, 10 cores, load1 6-17 during the work
(another agent's GUI tests, WindowServer at 60-66% CPU), so most wall-clock pacing runs were NOT-MEASURABLE and the
load-independent number (thread CPU time per pass) leads.

### Probe

`MainThreadBusyProbe` (ShellUI/Perf) records every main run loop pass (wake-up to sleep, after Core Animation's commit
observer) with wall and thread CPU time while a pacer session runs. Each `hitch` log line now also carries the longest
pass around the missed vsync: `busyMs` (wall), `cpuMs`, `offCpuMs` (wall the thread was not running: preempted or
blocked), `passes`, `passesCpuMs`; `FramePacer.hitchDetails` keeps them for tests. CPU near wall time is app work; a
large `offCpuMs` with little CPU is the thread waiting (scheduler, or a blocking call).

### Root cause

`SpacePagerView.apply(offset:)` moved the strip view with `setFrameOrigin` on every frame. For AppKit that is a view
geometry change of the whole strip subtree, every frame:

- `NSViewHierarchyInvalidateVisibleRect` over every descendant, a window layout pass
  (`_layoutSubtreeWithOldSize`, `_findAnySubviewNeedingAutoLayoutEngine`), and redisplay of image views and text fields
  (`_NSSimpleImageView updateLayer`, `NSStringDrawingEngine`) inside the commit. Main-thread CPU per pass: median about
  3 ms, single passes 10-15 ms (Debug and optimized alike).
- Tracking areas of every row in the strip were rebuilt (`updateTrackingAreasWithInvalidCursorRects`), and each row's
  `updateTrackingAreas` asks its host for a hover resync, which on the next main-queue turn calls
  `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`, a synchronous window-server query. In the `sample` of a
  scripted swipe loop, 1843 of 7348 main-thread samples (25% of the wall time) were inside that query. Its latency
  depends on the window server, not on the app: 600 calls at load1 13 gave median 0.22 ms, p99 10.9 ms, max 26 ms,
  with 0.05 ms of CPU each (141 over 2 ms, 10 over 8 ms).

The second point is the "late frame with an idle main thread" of C7 phase 3: the previous display-link callback ran
about 7.5 ms late while the thread used almost no CPU, and it got worse with WindowServer activity. It is not
scheduler contention outside the app; the app waited on a window-server reply it asked for on every frame. The
first point is the CPU half (passes over one refresh even on an idle machine).

A/B with the same test (`-Xswiftc -O`, 30 rounds): taking the explicit `CATransaction` out of `apply` but keeping
`setFrameOrigin` made it worse (swipe-back 91 of 2230 passes over 8.3 ms CPU, max 14.3 ms), so the explicit
transaction was not the cause; the view frame move was.

### Fix

- The strip moves on its layer: during tracking and the settle, `apply` sets a pixel-aligned translation
  (`setAffineTransform`) relative to the strip view's frame; the frame itself does not change. The frame catches up
  and the translation is cleared in the same implicit transaction when the strip rests: settle completion,
  `jump(to:)`, `stopInteraction()`, a touch-down freeze (`gestureMayBegin`) and `layout()`. No explicit
  `CATransaction` in `apply` or `layout()` (backing layers do not animate implicitly; the test checks
  `animationKeys()` is nil). The spring, rubber band, velocity hand-over and freeze logic are unchanged.
  Mid-motion, AppKit's view geometry is brought to the screen on input instead of per frame (review of #282: with the
  rest frame, a click during a `go(to:)` settle landed on the row the stale frame put under the pointer, possibly in
  the Space being left). The pager syncs the strip frame (and clears the translation; the spring carries on from the
  new frame) on: a hit test inside it for any event except the changed-phase and momentum events of a scroll gesture
  (those stream at display rate and the pager handles them wherever they land), so clicks, drags, the first event of a
  scroll gesture and accessibility hit tests find the view drawn under the point and that view converts the event with
  its on-screen frame; a pointer move over the pager (its own `.mouseMoved` area, which never moves), so rows enter and
  leave by where they show; a backing change (`viewDidChangeBackingProperties`, a window dragged to a display with
  another scale), so AppKit updating the backing layer's geometry has no transform to reset; and a touch-down freeze.
  Not synced mid-motion: accessibility frames read without a hit test, which are off by the current translation until
  the next input or rest. A swipe with a still pointer and a keyboard switch with a still pointer stay transform-only.
  Alternatives rejected: translating the point in an overridden `hitTest(_:)` returns the right view, but that view
  then converts the event with its stale frame (a table picks the wrong row) and tracking areas stay stale; moving a
  layer AppKit does not own (layer-hosting strip, manual sublayer) cannot hold the pages, which are views.
- While the strip moves, the set of shown pages only grows; it shrinks to the current page at rest. Before, a settle
  that overshot its page hid and showed the neighbour on each swing (3 changes of one page in one swipe), and each
  change rebuilt that page's tracking areas and queued another window-server query. At rest the shown page is
  `targetIndex`: with Reduce Motion the spring presents its final value before its completion sets `index`, and
  showing `index` for that one call hid and showed the destination again (the CI GUI job failed with `3 > 2`; forcing
  Reduce Motion reproduces exactly that locally; `testAnInteractionShowsAndHidesEachPageOnceWithReduceMotion` covers it).

### Before and after

`SpaceSwipeHitchTests.testSpaceSwitchPassesStayUnderOneFrameOfMainThreadCPU`, main-thread CPU per run loop pass,
20 rounds of scripted swipes (20 frames of 9 pt, the smoke's medium swipe) between Personal and Work:

| Build | Code | load1 | label | passes | median ms | p95 ms | max ms | passes over 8.3 ms | hitches (pacer) |
|---|---|---|---|---|---|---|---|---|---|
| Debug | before | 8.0 | swipe-next | 1588 | 3.06 | 5.24 | 7.36 | 0 | 13 in 40 swipes |
| Debug | before | 8.0 | swipe-back | 1620 | 2.65 | 7.82 | 13.70 | 76 | |
| Debug | after | 6.2 | swipe-next | 1475 | 0.45 | 1.02 | 3.90 | 0 | 0 in 40 swipes |
| Debug | after | 6.2 | swipe-back | 1460 | 0.44 | 0.89 | 3.59 | 0 | |
| -O | before | 6.6 | swipe-next | 1612 | 3.16 | 5.17 | 8.35 | 1 | 16 in 40 swipes |
| -O | before | 6.6 | swipe-back | 1592 | 3.01 | 9.30 | 14.79 | 104 | |
| -O | after | 6.1 | swipe-next | 1475 | 0.39 | 0.67 | 4.02 | 0 | 0 in 40 swipes |
| -O | after | 6.1 | swipe-back | 1460 | 0.37 | 0.67 | 4.58 | 0 | |

An earlier 30-round `-O` pair at load1 12-14 gave the same picture (before: 4 hitches, max 10.2 ms; after: 0
hitches in 60 swipes, max 3.8 ms, p95 0.56 ms). Keyboard switches after the fix: median 0.3-0.4 ms, max 2.4-4.4 ms,
0 hitches. With all six legs (15 rounds, load1 9-16), before/after: Debug 15 / 2 pacer hitches, `-O` 1 / 0; the
light/dark legs keep their flip pass (below), every other leg's maximum went from 5.9-13.9 ms to 1.8-3.2 ms. Main-thread samples inside the window-server query during a swipe loop: 25% before, 0.3% after.

`testFramePacingDuringSwipeAndKeyboardSwitch` (wall clock, asserts only below load 10), after the fix, 8 runs at load1
5.5-8.3: `space-swipe` `over8.6=0 maxMs=8.33` 8 of 8. `space-key` failed 3 times (`9@17.00`, `9@20.36`, `9@21.21`)
and `space-swipe-flavor` twice (`64@20.58`, `9@30.30`). The probe names both:
- Frame 9 of the Work -> Dev switch is the halfway light -> dark chrome flip (`SidebarContainerView.setFlavor`, then a
  commit that relayouts and redisplays the chrome): 4 ms CPU optimized, 10-29 ms in Debug
  (`hitch label=space-key frame=9 ... cpuMs=29.30 offCpuMs=1.04`). App work, but in the sidebar chrome, not the pager;
  the smoke's Personal and Work are both light and never flip. Follow-up #275. Not a regression of this change: a
  diagnostic loop of 40 Work <-> Dev keyboard switches per run (`-O`) gave a flip-pass median of 9.0 / 9.9 / 10.1 ms
  before the fix (3 runs; 2 earlier runs 4.0 / 4.6) and 4.2-9.9 ms after it (9 runs). The value is bimodal per
  process run, so single runs do not compare; the largest other pass per switch went from 4.3-4.8 ms to 0.6 ms.
- `64@20.58` was `cpuMs=0.29 offCpuMs=20.23`: the thread did nothing for 20 ms. The remaining window-server queries
  (one hover resync when a page is shown or hidden at the start and end of a switch) are the likely waiter; follow-up
  #278 defers them while the pager moves.

### Tests added

- `SpaceSwipeHitchTests` (GUI): `testSwipeMovesTheStripLayerNotItsFrame` (frame unchanged while tracking, translation
  matches the offset, no implicit animation, frame synced and translation cleared at rest),
  `testFrozenSettleSyncsTheStripFrame`, `testAHitTestMidSettleFindsTheViewShownUnderThePoint`,
  `testOnlyGestureStartsAndNonScrollEventsSyncTheGeometryOnAHitTest`, `testAPointerMoveMidSettleSyncsTheStripFrame`,
  `testABackingChangeMidSettleKeepsTheStripWhereItShows`, `testStopInteractionMidSettleRestsOnTheSettledPage` (the
  mid-settle ones present spring frames at chosen times through `SpringDriver.tick(at:)`, no sleeps or display
  waits), `testAnInteractionShowsAndHidesEachPageOnce` and its Reduce Motion variant (both fail
  before the fix: a page changed 3 times in one swipe), and `testSpaceSwitchPassesStayUnderOneFrameOfMainThreadCPU` (every pass of swipes and
  keyboard switches both ways under 8.34 ms of main-thread CPU; it fails before the fix with 13.7-14.8 ms; the two
  legs that cross the light/dark flip are reported, not gated, until #275; skipped as NOT-MEASURABLE on screens below
  120 Hz, as CI's virtual display is).
- `SpacePagerTests.testTouchDownFreezesASettleAndVerticalResumesIt`: only the timing (the settle already finished
  before the test looked) may skip as NOT-MEASURABLE; `frozenTarget == 1` after the touch-down is a hard assertion
  again (review finding from #270).

### Still open

- WindowServer trace (acceptance criterion 1 of #24) and a manual trackpad swipe plus a window drag across displays
  with different scales mid-swipe: maintainer steps, not run here.
- Smoke `-ArktSmokeRepeat 25` in 3 of 3 idle runs (acceptance criterion of #24) needs a Profile build of the app and an
  idle machine; not run here (no app launches in this task). The smoke swipes Personal <-> Work, which no longer
  rebuilds tracking areas per frame.
- The WindowServer-side trace of the acceptance criteria was not taken: the cause is in the app (a per-frame
  window-server query and per-frame view geometry), shown by the probe, `sample` and the A/B above.
- #275 (light/dark chrome flip pass), #278 (hover resync query during a switch).

## Space icon, theme picker and header drag reorder (#279)

Plan: parity spec section 2.2 (BH-034, BH-038, BH-039); decisions D1 and D2 are in the track C plan's Decisions
section. Pull request #287.

- Model and storage: `Space.icon` is `SpaceIcon` (`.symbol(name)` or `.emoji(text)`, D1), stored as a tagged object.
  Sidebar documents are written as format version 2 with a frozen fixture (`sidebar-v2.json`, a symbol and an emoji
  icon, the emoji written as JSON escapes). Version 1 documents still load, every icon nil; a version 1 document that
  carries an `icon` key is decoded through the version 1 Space shape, so the key is ignored whatever it holds.
- Archive rows keep their own format version (`ArchiveStore.snapshotFormatVersion = 1`). `NodeSnapshot` holds no Space
  data and did not change, so stamping rows with the sidebar format (2) would only have hidden them from builds that
  read version 1.
- `SidebarSource.setTheme(_:to:)` takes an optional theme; nil is the header menu's "Default" (D2), and
  `SidebarSpaceInfo.usesDefaultTheme` drives its checkmark.
- The bridge stores theme colors as sRGB components and converts Display P3 colors (through extended sRGB) instead of
  copying their components.
- Dock: a symbol is the dot's own fill (`sidebarForeground` to `primaryText`, the #72 contrast pair) seen through the
  symbol as a mask; an emoji is drawn as text into a bitmap at the backing scale and dims by the idle dot's alpha ratio
  (TODO(measure)). Icon bitmaps are cached per (icon, scale); a swipe frame sets only fills and opacities, no frame,
  image or rasterization (`swipeFramesNeverRedrawAnIcon`).
- Header drag: the title follows the pointer 1:1 (frame origin only), rubber-banded where no Space is left to pass;
  one slot is one header width, so a move commits at half of it, like a swipe between Space pages. On release the
  title springs home (`SpringDriver`, damping 1.0, response 0.3 s, TODO(parity)) with the release velocity; a press
  during the spring catches it; Reduce Motion snaps. The "Drag to Reorder Space" tip is off while the title is open
  and is installed again only when the header rect changes.

Tests: counts are taken from the macOS CI run of this pull request (no local Swift toolchain was used for this
section). New test functions against `main`: ArktCore 9, ShellKit unit 20 (17 `ShellUITests`, 3 `CoreBridgeTests`),
`ShellKitGUITests` 5.

Deviations from the plan:

- Paper and Dusk are placeholder colors, `TODO(design)` like `bridgeDefault`; no design or Arc measurement backs them.
- Profile is a disabled item on the header menu; profiles are not in the model yet.
- The icon picker lives on the header "..." menu (symbols, then "Emoji..."); Arc's own picker was not measured.
- The header draws no Space icon next to the title; the spec does not place one there (BH-038 names the edit icon and
  the "..." menu only). Icons show in the dock.

## Sidebar: hide, hover reveal and edge gestures (#102) (2026-10-25)

Spec section 2.1 (BH-001 to BH-006), KB-017, GS-017, GS-018.

- **Cmd-S (KB-017, BH-001).** View > Hide Sidebar / Show Sidebar (first in the View menu, Cmd-S) calls
  `ShellWindowController.toggleSidebarVisibility(_:)`. Not `toggleSidebar:`: `NSWindow` answers that selector itself
  (disabled) ahead of its controller in the responder chain, so the item never reached the controller in the app
  (`testMenuActionReachesTheControllerThroughTheResponderChain`). Instant, no animation (a keyboard action). Not a
  reserved key: a page that handles Cmd-S keeps it.
- **Edge drag (BH-002, BH-003, GS-017).** `ShellLayout.resolveDrag`: a proposed width below `sidebarHideWidth` (75 pt,
  PARITY(NEEDS-RUNTIME-CHECK RT-10)) hides the sidebar; between it and the minimum the sidebar stays at its minimum, and
  dragging back right in the same drag shows it again. Double-click on the edge resets the width (existing, now tested).
- **Hover reveal (BH-004, GS-018).** The sidebar column now lives in `SidebarOverlayView`, above the card and split.
  Docked it is the plain column. Hidden it keeps its width (no row relayout) and becomes a floating card inset
  `sidebarOverlayInset` (10 pt) from the window's edges, with its own mirror of the Space theme, the card's hairline
  border and a `sidebarOverlayShadow`. An 8 pt strip at the window's left edge reveals it after 100 ms; it slides back
  250 ms after the pointer leaves it (not while a mouse button is held). Delay, inset and edge width are
  PARITY(NEEDS-RUNTIME-CHECK RT-10). Motion: `SpringDriver` on the overlay's display link drives one offset; per frame
  only the overlay layer's transform (pixel-aligned) and opacity change. Reveal `SpringPreset.firm`, conceal
  `.firmFast`; turning around mid-flight continues from the presented offset and velocity. Reduce Motion fades in place.
  The traffic lights hide with the sidebar and fade in with the overlay; the titlebar container is zero wide while the
  sidebar is hidden, so the page's top-left corner stays clickable.
- **BH-005** (a brief Option press shows the sidebar) is not implemented: expected absent in Arc 1.168, RT-11.
- **BH-006.** A new tab (Cmd-T, an engine-created tab, a background history tab, a duplicate) or a new Space while
  hidden shows the existing toast "New Tab Created" / "New Space Created" with a "Show Sidebar" button. What a click on
  Arc's toast does is not recorded (PARITY(NEEDS-RUNTIME-CHECK BH-006)). New Space while hidden opens no rename field.
- **State.** Per window, in memory, like the sidebar width (neither is persisted across launches; there is no
  per-window store yet).

Frame-time gate (`SidebarHideTests.testRevealPacing`, 1200 x 800 window, InMemoryEngine, two reveal and conceal rounds,
120 Hz display, M-series 10 cores): 7 measurable runs. 5 runs (load1 5.5 to 8.6) were clean: 20 sessions, reveal 44 to 45
frames and conceal 27 frames, 0 frames over 8.6 ms, max and p99 8.33 ms. 2 runs at load1 about 8 (other builds on the
machine) had 1 to 2 late frames (16.8 to 20.8 ms) in the second reveal; in the same minutes the existing pager gate
(`space-key`) failed the same way once at load1 9.3 and then passed 3 of 3. Runs above load1 10 were NOT-MEASURABLE.

Tests (after rebasing on main with #312 and #324): ShellKit unit 612 (599 + 13 new), ShellKitGUITests 538 (515 + 23 new:
22 in `SidebarHideTests`, 1 in `MainMenuKeyEquivalentTests`); `WindowChromeTests.testResizeHandleClampsSidebarWidth` now
drags to 100 pt (10 pt hides). ArktCore is not touched.

## Favorites: add, remove, limit and unloading (#107) (2026-10-26)

Spec section 2.3 (BH-046 to BH-053).

- **BH-046 (limit).** `Sidebar.maximumFavorites = 12` per profile (CF-17). The add methods and `move` into a
  Favorites section throw `SidebarError.favoritesFull(profile)`; snapshot `insert(_:in:at:)` is exempt, the same
  rule as the split pane cap, so stored trees over the cap still load. The refusal crosses the adapter as
  `SidebarMoveError.favoritesFull` and toasts "Favorites are full." [I].
- **BH-047 (add and remove).** Three parts. (a) Menu: plain tab rows (Today, Pinned, inside folders) get
  "Move To > Favorites"; split and pane rows keep their own menus, and the full menu set stays with #105. The move
  goes through the new `SidebarSource.moveNode(_:to:at:)`, appended. (b) Drag on: a tab dragged onto the Favorites
  band above the Space title becomes a Favorite; the band keeps a one-tile-row drop target at zero Favorites.
  (c) Drag off: a Favorite dragged below the Space title (onto the Space page) is pinned in the current Space,
  appended to Pinned [I] (the drop position inside Pinned is not modeled). Both zones live in
  `FavoritesDropOverlayView`, shown only during a sidebar drag (the `SplitDropOverlayView` pattern); the zone math
  is pure (`FavoritesDrop`). The command-bar actions ("Favorite Tab" / "Move To Favorites") are deferred: the
  command bar has no actions infrastructure on main yet - it lands with #112 (PR #322), and wiring the two actions
  then is a small follow-up.
- **BH-048.** Already held: a Favorite keeps its pinned URL (activation opens the node's URL) and Favorites are
  never auto-archived (`AutoArchivePolicy`, covered there). The Peek part (cross-site links open in Peek) is
  deferred: Peek is design-only (#304) and needs an engine link-activation hook that does not exist.
- **BH-049 (unloading).** Loading a Favorite past `FavoritesUnloadPolicy.maximumLoadedFavorites` closes the least
  recently used one's page (same close as the tile's X), so the row stays and the page - and with it any playback
  (BH-053) - is gone. Activations track recency per window; the current tab, visible panes and held closes never
  unload. The threshold (4) is [I] PARITY(NEEDS-RUNTIME-CHECK): Arc's count is unpublished (BH-049 is
  single-source).
- **BH-050 / RT-15 (grid above 4).** Deferred: NEEDS-RUNTIME-CHECK. The exact layout above 4 Favorites is
  unpublished; RT-15 measures it against the reference browser (add 1..12 Favorites, screenshot at each count and
  two sidebar widths), a maintainer runtime step. The 3-column grid stays for all counts meanwhile.
- **BH-051 (badges, music notes, Live Calendar).** Deferred: needs engine media state (`TabSnapshot` has no
  audio/PiP fields; the same gap sits behind BH-076 in `AutoArchiveTimer`) and per-site unread-badge sources.
- **BH-052 (custom icon).** Deferred: the Favorite tile context menu is #105's scope, and the icon picker plus its
  storage are a product decision.
- **BH-053.** Satisfied by the close path: closing a loaded Favorite destroys its engine page
  (`FavoriteTileCloseTests`), so playback stops with it; there is no media/PiP state yet to test the media side
  (deferred with BH-051).

Tests: ArktCore 98 (89 + 9 new in `FavoritesLimitTests`); ShellKit unit 619 (604 + 15 new cases; 14 new test
functions, one parameterized over both sources); ShellKitGUITests 554 executed, 5 skipped (540 + 14 new:
`FavoritesMoveTests` 11, `FavoritesUnloadTests` 3). The full run's only failures were
`SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` (1 to 2 late frames) and
`SpaceSwipeHitchTests.testSpaceSwitchPassesStayUnderOneFrameOfMainThreadCPU`, both at load1 about 5 to 8 with
another worktree's build running; isolated reruns passed (2 of 3 and 1 of 1) with every frame at 8.33 ms - the
flake mode the #102 section records.

## Pinned tabs: pin, reset to pinned URL, replace pin (#108) (2026-10-26)

Spec section 2.4 (BH-055 to BH-066).

- **The pinned URL is the node's `url`.** Pinned and Favorite nodes no longer track the page's URL on navigation
  (`writesLiveURL(toSection:)`, one rule behind `.urlChanged` and the create-tab replay); the title still follows
  the page (BH-062). That matches the reference browser's own model (`savedURL`), needs no storage-format change,
  and makes reopening a closed pin load the pinned URL (BH-068's direction; BH-068 itself stays
  NEEDS-RUNTIME-CHECK). Reset (BH-057) navigates the live engine tab back to the node URL; Replace Pin (BH-060)
  writes the page's URL into the node.
- **BH-055 (pin / unpin).** Cmd-D (KB-012, File > Pin / Unpin Tab, newly reserved so a focused page cannot
  swallow it) and the rows' context menu: a tab directly in Today pins (appended to Pinned [I]) with the [S]
  toast "Pinned Tab to <Space>"; a pinned tab unpins (on top of Today [I]) with "Un-Pinned Tab from <Space>". A
  focused pane pins its whole Split View (BH-115); panes are never moved alone, and Favorites and foldered tabs
  have no toggle (a foldered tab is pinned through its folder). The page never closes and the row never archives
  on a toggle. Dragging above the divider is #104 (GS-007); the command bar actions land with #112's action
  search.
- **BH-056.** Holds on main: same-site links navigate in place, and a cross-site link in a pinned tab opens a
  Peek over it - #349's link-activation routing (`PeekRouting` gates on the pinned / Favorites section), merged
  while this branch was open; nothing was left to do here.
- **BH-057.** File > Back to Pinned URL (KB-041, unbound as in the reference browser) and the row context menu
  reset a navigated pinned tab; a favicon click on a navigated pinned row resets it (GS-005), a click anywhere
  else on the row still activates it. The reset-family items are enabled only while the tab sits away from its
  pinned URL.
- **BH-058.** Cmd-click on the favicon resets the pin and opens the page it was on in a new background [I] Today
  tab.
- **BH-059.** Spaces > Reset Space navigates every loaded, navigated pinned tab of the current Space (foldered
  tabs and split panes included) back to its pinned URL; disabled with nothing to reset.
- **BH-060.** Replace Pin with Current Page on the pinned row's context menu. "Edit Pinned URL" (the variant
  with a text field) waits on the design pass (#304).
- **BH-061.** Separate From Pinned Tab: the page detaches into a new Today tab on top (focused [I]) and the pin
  resets; the page loads again in the new tab [I] - moving the live page across tabs is the same handoff BH-066
  needs (#300). The hover affordance waits on the design pass (#304); the action lives on the context menu
  meanwhile.
- **BH-063.** Deferred per the issue (RT-16, a maintainer runtime check).
- **BH-064.** Holds trivially: no rename prompt exists on main (rename is #105); when #105 lands, its prompt must
  not open on a pin.
- **BH-065.** The Space header grows a caret (shown while the Space has pinned tabs) plus "Collapse Pinned" /
  "Expand Pinned" in the Space options menu ([S] names): the pinned rows leave the outline and the divider stays
  [I] (the collapsed look is unmeasured). The state is per window (DM 3.1), kept in the page - not persisted
  across launches [I] (window-state persistence is #331's shape). While collapsed the title draws bold when the
  window shows one of the section's tabs [I] (PARITY: "the last pinned tab is in view"). The title click keeps
  opening the rename field (BH-038; TB24's title-toggle variant is not taken).
- **BH-066.** Two windows already show the same Space's pinned and Today tabs (one source). The one-loaded-copy
  handoff is deferred to #300 (the known bug: selecting a row that is live in another window loads the page a
  second time). Done in #300: the page moves to the selecting window (engine week-3 results, "#300").

Tests (after rebasing on main with #349): ArktCore 387 (not touched). ShellKit non-GUI 798 passed (791 + 7 new:
`PinnedTabLogicTests`; `ReservedKeysTests` moves Cmd-D into the reserved set); ShellKitGUITests 636 executed, 9
skipped, 0 failures (610 + 26 new: `PinnedTabTests` 25, `MainMenuKeyEquivalentTests` 1). Existing expectations
updated for the new menu items and the header caret: `SpaceChromeTests` (options menu), `SplitSidebarTests` (3 menu
assertions), `SidebarViewTests.testContainerLayout` (title leading with the caret). The Debug app builds.
`SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` flaked as documented in the #102 and #107 sections in
an earlier loaded run (1 to 2 frames over 8.6 ms at load15 5.4 with other worktrees' builds running); the final
full run is green.

## Tab switcher and keyboard tab navigation (#103) (2026-10-26)

Spec sections 1.1 and 2.1 (BH-007 to BH-020, KB-020 to KB-030, KB-036), built against `design/tab-switcher/`.

- **Recent tabs.** `RecentTabs`: per window, newest first, moved to front whenever `currentTab` changes (a split's
  focused pane counts), pruned on sidebar changes; capacity 64, not persisted. Scope is the window's own Spaces and
  Favorites, PARITY(NEEDS-RUNTIME-CHECK RT-12).
- **Switcher (BH-007 to BH-011, KB-022 to KB-025).** `ShellWindow.sendEvent` gives key-down, flags-changed and
  mouse-down events to `TabSwitcherController` before anything else, so a focused page never sees Ctrl-Tab, Tab,
  backtick, W or Esc while the switcher uses them; Ctrl-Tab and Ctrl-Shift-Tab are also in `ReservedKeys.arkt`. The
  panel (`TabSwitcherView`) is built with the window and only filled and unhidden on the key-down, at full opacity,
  so it is on screen with the next frame; a Ctrl release before the first presented frame (display-link tick)
  commits with no fade (the flick). Up to five rows, highlight wraps, Ctrl-Shift-Tab opens on the last row, W closes
  the highlighted tab through the Cmd-W path and keeps the switcher open, Esc, a click outside or another key cancel
  (another key then goes on as usual), a lost key window cancels. Rows: favicon or letter tile, title, split glyph
  for a pane, Space dot (the theme's most saturated stop) and name. VoiceOver: a "Recent tabs" dialog group, rows
  "title, Space, k of n[, split]", announcements on open, move, close and cancel.
- **Motion.** Open: none. Highlight: `springyFast` on the fill's translation, retargeted from the presented value
  and velocity. W: the panel takes its new height at once (a key press), the closed row fades where it was and the
  rows below slide up (`firmFast`, transform only) under a clip. Dismiss: 0.10 s opacity, strong ease-out. Reduce
  Motion: highlight jumps, W crossfades, the fade stays.
- **Cmd-1 ... Cmd-9, next / previous (BH-014 to BH-016, KB-020, KB-021, KB-028 to KB-030).** `SidebarTabOrder`:
  Favorites, Pinned, Today of the current Space; an open folder's items in place, a collapsed folder's none, a split
  is one item. Cmd-9 is the last item unless "Command-9 opens the ninth tab"; Favorites are counted unless "Count
  Favorites in Command-1 to Command-8" is off (`TabNavigationSettings`, defaults until #307 builds Settings). Next /
  previous stop at the ends. Cmd-} / Cmd-{ are hidden aliases (RT-02). New Tabs menu after Spaces.
- **Ctrl-Cmd-Right / Left (BH-013, KB-026, KB-027).** Cycle the recent-tab order without an overlay, wrapping; the
  order is frozen for the run of presses (RT-01).
- **Reveal (BH-018).** A keyboard landing on a row out of view scrolls the outline (`SpringDriver`, `springyFast`;
  Reduce Motion jumps) and shows "N more above / below" for 3 s or until the next user scroll.
- **Ctrl-Space (BH-019, BH-020, KB-036).** Shows a hidden sidebar [I], opens the folders holding the current tab,
  makes the outline the key view with a focus row: Up / Down (divider skipped, scrolled by the reveal spring),
  Return opens and gives focus back to the page (a folder toggles in place), Esc gives focus back. The ring is a
  3 pt stroke in `NSColor.keyboardFocusIndicatorColor`: a table view ignores a row-sized focus ring mask. The next
  click removes it.
- **Not built here.** The recording indicator needs camera and microphone state from the engine (#117). BH-017 has
  nothing to skip until the Pinned section collapses (#108). The Favorites grid has no keyboard focus yet (Left /
  Right).

Tests (after rebasing on main with #336, #341, #342 and #349): ShellKit unit 830 (791 + 39), ShellKitGUITests 651 run,
8 skipped (610 + 41), ArktCore 387 (not touched). The Space pager pacing gate failed by 1 to 2 frames at load1 7 to 9;
alternating single runs at load1 about 5.5 passed 3 of 3 on this branch and 2 of 3 on `main`. UI tests: 34 run, 33
passed, 1 skipped, outside `OnboardingTests`, whose 4 tests fail identically on `main`. The switcher stays closed while
the first run covers the window.

## Sidebar tab actions: rename, duplicate, multi-select and the context menus (#105) (2026-10-26)

Built against `design/tab-context-menus/tab-context-menus.md` (#321).

- **Menus (design 3).** `SidebarContextMenu` builds each menu as values (`SidebarMenuEntry`: title, action, key,
  enabled, Option alternate, submenu) for the eight targets: Today tab, pinned tab, Favorite tile, folder, Split Tab
  row, pane row, a multi-selection and the empty area. `SidebarContextMenu.menu(_:target:action:)` turns them into
  plain `NSMenu`s (`autoenablesItems` off, no custom views, no attributed titles, no brand color). The outline runs
  the items that already had callbacks (split items, pin, reset family, Move To > Favorites) through them; every
  other action goes to the window (`ShellWindowController+TabActions`). Move To lists Favorites, then every Space
  of the profile in order with the row's own Space disabled. Option alternates: Copy Link as Markdown, Copy Links as
  Markdown, Copy All as Markdown Links.
- **Rename (BH-026).** Double-click a tab row (folders open and close on click, so they rename from their menu), or
  Rename. The cell shows a native rounded `NSTextField` over the title, 13 pt, title selected, system focus ring and
  selection color, no animation. Return or a click anywhere in the outline commits, Escape cancels; a row reload
  for that node waits until the field closes. Tabs store the name as `TabItem.customTitle` through the new
  `Sidebar.rename` (`SidebarSource.renameNode`), so page titles no longer replace it and it survives a relaunch;
  an empty name clears it. Folders take the name as their title.
- **Duplicate (BH-027).** `SidebarSource.duplicateNode`: a copy with new ids right after the original (custom title
  kept). A loaded tab's copy is mapped to `EngineClient.duplicateTab`, so its history comes along; a single
  duplicate becomes current [I]. Splits use Duplicate Split View; folders copy their rows.
- **Multi-selection (BH-028).** `SidebarSelection`: Cmd-click toggles, Shift-click selects the contiguous range from
  the anchor; the current row seeds an empty selection. Tabs and split rows are selectable; panes and folders are
  not. Selected rows draw the `contentVisible` fill, the current row keeps `current`. A plain click, a Space switch
  or a right-click on an unselected row ends it; rows that leave the outline leave it. The Ctrl-Space focus ring is
  untouched (a click still removes it).
- **Bulk actions.** Cmd-W (BH-072), Archive on the multi menu, Archive Below (BH-077) and Clear Today Tabs (BH-075)
  go through `closeAll`: whole tabs and splits only (`SidebarSelection.bulkTargets`), each through `close(node:)`,
  the node holding the current tab last, and "Archived N tabs" when two or more Today tabs go. `successor(of:)` now
  skips siblings whose archive waits on a leave-site prompt. Archive Below on a pane archives the panes below it,
  one by one. Cmd-D pins or unpins a selection (Pin Tabs / Unpin Tabs). Open in Split View (2 to 4 plain tabs,
  BH-117), New Folder (BH-094: a new pinned folder takes the selection, then opens for naming [I]), Move To and Copy
  Links act on the selection.
- **Empty area (BH-021, BH-023).** In the outline below and between rows, a press drags the window
  (`performDrag`), a double-click opens the command bar for a new tab, and a right-click shows New Tab, New Folder,
  Paste URL as New Tab and Clear Today Tabs.
- **Non-key dimming (BH-025).** `SidebarContainerView.isDimmed`: URL bar, Favorites, Space pages and bottom bar at
  0.6 opacity, instant. The window's own command bar panel taking key does not dim it (`dimsSidebar`).
- **Not built, shown disabled (design OQ6).** Share, Share Split View, Change Icon, Edit Pinned URL, Mute (no
  engine mute), Rename on a Favorite tile (no title is drawn) and on a Split Tab row (no stored title).

Deviations: no key equivalents on Copy Link (Shift-Cmd-C), Paste URL as New Tab (Opt-Cmd-V) and Clear Today Tabs
(Shift-Cmd-K), because a context menu's key fires only while it is open and the menu bar has no such items yet;
Separate From Pinned Tab (BH-061, #108) stays in the pinned menu, as its only entry point; Copy Link copies the page
URL as is (no tracker stripping); "Archived N tabs" has no Undo button yet; the dimming has no 12 % theme wash.

Tests (rebased on main with #357): ArktCore 393 (387 + 6). ShellKit unit 900 (862 + 38). ShellKitGUITests 730 run
(702 + 28), 7 skipped; 2 failures, both the Space pager frame-time gate
(`SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch`) at load 7 to 8 on 10 cores, which fails the same way
on `main` at that load. The Peek frame-time gate failed once at that load and passed 2 of 3 reruns. Debug app build
succeeds. UI tests (XCUITest) not run here.

Review fixes: committing the rename field unchanged stores no custom title (an accidental double-click no longer
freezes the page title); another tab coming forward or a plain press on empty sidebar space ends the
multi-selection, so a later Cmd-W closes the tab on screen; a right-click commits a rename in progress; sheets and
child windows taking key keep the sidebar lit. ShellKitGUITests 734 run (730 + 4), 5 skipped; the only failures are
the load-dependent frame-time gates noted above. Disabled items now tracked: Share (#362), Edit Pinned URL and
Favorite rename (#363), Mute (#364); Change Icon (#339, #109), the Undo toast (#308), Copy Link keys and tracker
stripping (#118), Clear Today Tabs key (#110), Split Tab rename (#27, BH-115).

## Folders: create, rename, nest, collapse all, Folder Preview (#109) (2026-10-26)

Built on the folder menu, New Folder and rename that #105 shipped; spec section 2.6.

- **Open and close on a spring.** A pointer toggle runs one interruptible spring per folder (`FolderMotion`, on
  `SpringField`, a new keyed spring set in Motion; `SpringPreset.firm`, no visible overshoot, about 0.3 s). The
  rows that come and go slide in under the folder row and fade; every row below follows by the height still missing
  (`FolderMotionLayout`). Frames go to the row views as layer transform and opacity, never as frame changes. A
  closing folder keeps its rows in the outline until its spring settles (`FolderDisplay.closing`), so a second click
  mid-close reverses from where the rows are, with their velocity. Reduce Motion: the change applies at once and the
  rows a folder shows fade in (0.15 s); keyboard toggles (Return on a focused folder, Ctrl-Space reveals) never
  animate. A page that is not on screen changes at once.
- **Peeking rows (BH-092, BH-105, BH-093).** `FolderDisplay` decides what a folder lists: everything while open;
  while closed only the rows peeking out of it, with the path of folders down to them. A tab moved into a closed
  folder peeks out and the folder stays closed (the model side of BH-091); the current tab peeks out of the closed
  folders around it (switched to from the command bar, the tab switcher, Cmd-1 to Cmd-9, Folder Preview, or
  closing its own folder [I]); the peek ends when another tab becomes current. A pane peeks through its split.
- **Collapse All / Expand All Folders (BH-097), New Folder (KB-040).** In the Tabs menu, no keys: KB-040 stays
  unbound until RT-04 (#78), and Cmd-Shift-N stays New Incognito Window (CF-02). Collapse / Expand All act on every
  Space page of the window; only the page on screen moves, nested folders ride their outer folder's spring, and the
  current tab keeps peeking [I]. They are disabled in a Space without folders. New Folder takes a multi-selection,
  else adds an empty pinned folder, open for naming [I].
- **Per window (BH-098).** Every outline keeps its own `FolderDisplay`; two windows on one sidebar open and close
  folders independently. Keeping them across a relaunch waits on session restore (#116).
- **Nested New Folder (BH-094).** Rows that all sit in one folder form a new folder nested there, at the first
  one's place; any other selection still gets a new pinned folder. Splits move whole.
- **Rename commit (BH-096).** The rename field already commits whenever it loses focus; a test now covers a folder
  losing focus outside the sidebar.
- **Folder Preview (BH-093, GS-019).** Hovering a closed folder's row for 0.5 s [I] shows its tabs (nested folders'
  tabs and panes included [I]) beside the sidebar, in the window's root view, with the tab switcher's surface,
  edge, shadow and highlight tokens. Its search field takes the keyboard: typing filters by title or host and
  selects the first match, Up and Down move, Return or a click activates the tab, which then peeks out under the
  still-closed folder. Esc, leaving both the row and the preview (0.25 s grace [I]), the field losing focus, the
  folder opening or a Space switch close it, and focus goes back where it was. Motion: a 0.15 s fade and scale from
  0.97 at its leading edge on the strong ease-out, a 0.10 s fade out; Reduce Motion keeps the fades only. Always on
  [I]: Arc's `folderPreviewEnabled` switch waits for Settings.

Deferred: the drag gesture of BH-091 (sidebar drag and drop, #104; dropping into a closed folder will get the peek
above); Change Icon (#366, blocked on the picker, #304 and #339); Share (#362); GitHub Live Folders, BH-099 (scope
decision #124); the KB-040 key (RT-04, #78); expanded folders across relaunch (#116). Deleting a folder still
closes its pages without leave-site prompts, the same as Delete Space and Clear Today; that gap is unchanged.

Review fixes: a tab moved into a folder nested in a closed folder shows with the path to it, and a moved folder no
longer peeks itself (the current tab inside it does); the Pinned / Today divider moves with the rows around it; a
keyboard toggle mid-spring stops the spring; a folder removed mid-spring leaves no row offset; opening a folder ends
its moved-in peeks; a page leaving the screen settles its springs; the Reduce Motion fade reaches rows realized
after the change; moving the pointer from one closed folder to another keeps Folder Preview up with its field
focused.

Tests (rebased on main with #360 and #365): ShellKit unit 950 (929 + 21). ShellKitGUITests 799 run (771 + 28), 7
skipped; 3 failed assertions in two load-dependent frame-time gates at load 10 to 12 on 10 cores
(`CommandBarTests.testAppearsUnder16ms`, 17.6 ms against a 17.5 ms bar, passes on rerun;
`PeekMotionOnScreenTests.testOpenAndCloseStayInsideTheFrameTimeGate`, skips itself on rerun at that load); the run
before the review fixes had 0 failures. ArktCore untouched: 405, all pass. Debug app build succeeds. UI tests
(XCUITest) not run here; no existing accessibility identifier changed.

## Sidebar drag and drop: reorder, pin, favorite, folder, Split View, Space and window (#104) (2026-10-26)

- **Model.** `Sidebar.moveNodes(_:to:at:)` moves a dragged set as one step: the set keeps its order and lands at one
  index (measured before removal), descendants of a moved node move with it, a refused move changes nothing, and a
  pane that leaves its split shrinks the split (a split never keeps one pane). A split is not a destination there;
  panes join through `addToSplit` and reorder through `movePane`. `SidebarSource.moveNodes` (one mutation, one save)
  and `moveNode` of a pane now go through it.
- **Rules.** `SidebarDropResolver` (pure): a row's top and bottom quarter insert before or after it, the middle half
  acts on the row: a folder takes the nodes (GS-009), a tab or split row takes one dragged tab into a Split View, its
  left half putting the dragged tab first (GS-010, BH-118). The divider's halves end Pinned and start Today (GS-007);
  below the last row is the end of Today; drops into a dragged node are refused. Every node row is draggable now
  (folders and splits too), and a row of a multi-selection carries the whole selection (#105).
- **Window.** `ShellWindowController+SidebarDrop` performs drops through the existing paths: `move(_:to:at:)` (nodes
  arriving in Today take the live URL and restart their idle clock), `addToSplit` and `movePane`. The shown tab moved
  to another Space stays shown. Opt-drag duplicates (GS-014). Dropped text or a link opens a tab at the indicator
  (GS-015). A Favorite dropped on the page lands at the indicator (BH-047). Resting at a page's edge turns to the
  previous or next Space (GS-012), resting on a closed folder opens it on the folder spring (#109). A tab released
  over no window opens in a new window at that point, and a row dropped on another window's sidebar is shown there;
  both move the live page without a reload (#300, GS-013). Folder drops go through `folderDropPlacement` (#109 seam).
- **Motion.** Rows below the drop point make room on a `springyFast` spring through their layer's
  `sublayerTransform` (no view frames move); retargets start from each row's value and velocity, and an exit or
  cancel springs them back (`firm`). A 2 pt accent line rides the gap; folder and tab targets get a highlight. Both
  fade in 120 ms. Reduce Motion: no row moves, the line sits on the row boundary. BH-024 haptic tick on each new
  place. `DropGapSprings` settles by the solver's envelopes instead of `SpringRun`'s settling scan (about 0.9 ms per
  run in Debug), which kept a page-wide retarget inside the frame budget: worst preview frame 0.2 ms of main-thread
  CPU in the sweep gate.

Deviations: BH-039 (reorder Spaces) was already on main (Space header drag). The Favorites overlay now covers only
its band, so the page's outline takes everything below it (two `FavoritesMoveTests` page tests were rewritten and
`SplitDragTests.testPasteboardWriterOnlyForTabs` became `testPasteboardWriterForNodeRowsAndTabTiles`). Opt-drag
copies on the sidebar rows only; the band and the content overlay refuse a copy. GS-012 has no Profile prompt
(windows show one profile). GS-013 tells Escape from a miss by the current event. Haptics are not gated by
`tabReorderingHapticsDisabled` yet (no setting). Band sizes, dwell times and folder end placement are [I].

Tests (rebased on main with #367 and #368): ArktCore 423 (405 + 18). ShellKit unit 998 (958 + 40). ShellKitGUITests
839 run (806 + 33), 8 skipped; 1 failure, the load-dependent Space pager frame-time gate
(`SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch`) at load 5 to 7. Debug app build succeeds; the app
was launched with throwaway directories. UI tests (XCUITest) not run here.

Review fixes (each with a GUI test): hit-testing follows the rows where the open gap shows them (a point in the gap
keeps the target, a point below it moves up one row pitch), so pointing at the line no longer turns the drop into a
Split View on the row laid out under it. A pin dropped on a Today tab's half joins a Today split through
`didEnterToday` (live URL, restarted idle clock), as a move does. A cancelled drag closes the folders it sprang
open; a drop keeps open the folders it lands in. A navigated pin dropped in another window's Today was checked to
store its live URL. Follow-up: move `DropGapSprings` into `Motion` and give `SpringField` (#109) its envelope
settling, so one spring type serves both.

## Reopen closed tabs and Peeks, the Peek closed toast (#346, reopen part of #110) (2026-10-26)

One reopen stack per window for closed tabs and closed Peeks (BH-074, BH-150, KB-010, KB-011, KB-079). Cmd-Shift-T
(File > Reopen Closed Tab, reserved before the page) and Cmd-Z take the most recent close back; repeating walks back
further.

- **History.** Decided on #346: just before a page closes, the window parks an engine duplicate of it
  (`EngineClient.duplicateTab`, back and forward entries included) that is never shown, and the page closes as
  before. Chromium loads a cloned tab only when it is first shown, so a parked copy runs no page and plays no audio;
  keeping the closed tab alive would keep its audio playing. Reopen maps the copy to the row again or puts it back in
  the Peek. No Chromium change: no new patch, `.patches` unchanged. The stack keeps 20 closes [I]; the oldest one's
  copy closes when it falls off, and older closes stay in the Archive. A copy that closes on its own (its window
  closed) leaves its item to reopen without history.
- **What goes on the stack.** User closes only: Cmd-W, the row's X, Archive Below, Clear Today and a multi-selection
  Cmd-W (each row its own item). A Today row comes back from the archive record (`ArchiveCoordinator.restoreRecent`,
  the latest 50 archive entries [I], without a store read) at the place it had; a pinned tab or Favorite gets its page
  back. A close cancelled at a leave-site prompt never happened and leaves nothing. Auto-archive, a page closing
  itself and Delete Space do not go on the stack. Clear Archive forgets the archive entries, so a cleared tab does not
  come back.
- **Peek.** Every close (the Close control, the scrim, Esc, Cmd-W, a fling) shows "Peek closed" with "Reopen" and
  its key (`ToastView`, 16 above the card bottom, 4 s), 140 ms into the close, a polite live region that says "Peek
  closed. Press Command-Z to reopen." A Peek closed by a tab or Space switch (#349) or by a new Peek is on the stack
  too, without a toast, and comes back over its source, which is shown first. Closing the source tab closes its Peek,
  and one item brings both back. A reopen while the close still runs turns the card around where it is. The motion
  table's Reopen row: from scale 0.96 and opacity 0 at its frame, `firm`; controls after 60 ms, grabber after 90 ms;
  Reduce Motion fades in over 0.20 s. A later close of a reopened Peek still goes back towards the original link.
- **Cmd-Z.** Edit > Undo targets `ReopenUndoRouter`: it reopens when the key browser window has something to reopen
  and no text is being edited there (a text view, or a view with an input context: Chromium's page view has one only
  while an editable field has the focus); otherwise it sends `undo:` down the responder chain as before. A page keeps
  Cmd-Z first: the engine gives the main menu only the key equivalents the page did not handle, so a web app's own
  undo keeps working.
- **Toast motion** (alerts design, section 7): in, 12 pt up and from 0.96 on `springyFast` with a 0.16 s ease-out
  fade; out, 6 pt down to 0.98 in 0.15 s; Reduce Motion keeps the 0.15 s fades. Layer transform and opacity only;
  an exit started during the entrance leaves from where the pill is.
- **Toast width.** In the Engine build the text field's intrinsic width came out a few points short and toasts
  truncated ("Pinned Tab to Spac...", "Peek clos..."); `ToastView` now sizes the pill by the text's own width too.

Not on the stack yet (rest of #110): the bottom bar menu (BH-033), media-playing tabs exempt from Clear (BH-076, needs
the engine's audio state), Clear unselected Today tabs (BH-078) and the Cmd-Shift-K key (KB-019). The rest of the
toast system (#308: glyph, hairline, shadow, timers that pause) is unchanged.

Tests (rebased on main with #374): ArktCore not touched. ShellKit unit 1019 (998 + 21). ShellKitGUITests 857 run
(839 + 18), 5 skipped; 4 failed assertions in the two load-dependent frame-time gates
(`PeekMotionOnScreenTests.testOpenAndCloseStayInsideTheFrameTimeGate`,
`SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch`) at load 12 to 18 on 10 cores while another
worktree's GUI tests ran; both pass on rerun at load 6, with the Peek and reopen suites (45 tests, 0 failures).
Debug and Engine app builds succeed. Real-app check on the Engine build (out/Spike, throwaway profile and data
folder, synthetic pages on a local server): Cmd-W archived a tab whose history was A then B, the parked copy made no
request; Cmd-Shift-T put the row back with the page on B, `history.length` 2, and Back (Cmd-[) went to A. A Peek
navigated from one page to a second closed with Esc and showed "Peek closed / Reopen ⌘Z"; Cmd-Z brought it back on
the second page with `history.length` 2. A Peek closed with its Close control came back with Cmd-Shift-T; its page
was requested only when it was shown again. UI tests (XCUITest) not run here.
