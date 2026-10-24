# Engine Week 3 Results

Plan: `docs/plans/2026-10-24-engine-week3.md` (pull request #220). Issue: #33. Variables as in the plan's Rules
(`$CHROMIUM_ROOT`, `$CR`, `$OUT` = `$CR/out/Spike`, `$PROF` = `$CHROMIUM_ROOT/profiles`, `$EMB` =
`$CHROMIUM_ROOT/embed-week3`).

| Task | What | Status | Result |
|---|---|---|---|
| W3-0a | Main-actor probe on the `Spike` configuration | DONE (#229) | GO; nested loops opened from a main-actor job starve the main actor (below) |
| W3-0 | Engine worktree, baselines, class lookup, command ids | DONE | lookup `found` in the app, `absent` in `Chromium.app`; 7 patch files, 17 upstream files, 0 hot-file hunks; W5c Step 3 and W6 Step 3 pass; command-id table; Swift baselines ShellKit 481, ArktCore 349; see "W3-0" below |
| W3-1 | `EngineAPI` additions, harness drivers, contract rules 11-16 (Swift lane) | TODO | |
| W3-2 | Facade header and its Swift module | DONE (#246) | see "W3-2" below |
| W3-3 | Engine configuration, readiness and quit seams, re-entrancy gate (GATE) | DONE | **GATE PASS** with recorded deviations (readiness queue for Chromium-created windows, quit-start seam, CDP keep-alive); see "W3-3" below |
| W3-4 | Host mode for ShellUI windows | TODO | |
| W3-5 | Tab facade | TODO | |
| W3-6 | `ChromiumEngineKit` over the facade | TODO | |
| W3-7 | The shell as engine host, composition root (Swift lane) | TODO | |
| W3-8 | Main menu inventory and owner decision | TODO | |
| W3-9 | Integration: ShellUI on ChromiumEngine, contract runner, smoke | TODO | |
| W3-10 | Infobars, or a recorded gap | TODO | |
| W3-11 | Self-contained bundle with the release framework | TODO | |
| W3-12 | Results, patch budget, issue updates, housekeeping | TODO | |

## Patch budget

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001-0006 | week 2 (hook, draw, keychain, factory hook, tab features, dialogs) | exist | 13 | 0 |
| 0007 | extension dialogs as native sheets (#244, pull request #252) | exists | 4 | 0 |
| - | Handshake (Decision 1) | ObjC runtime lookup, no patch (W3-0: lookup works) | 0 | 0 |
| - | Framework name (Decision 7) | no patch unless open decision 1 changes | 0 (1-2) | 0 |
| - | User data directory (Decision 8), `--no-startup-window` (Decision 2) | Info.plist key and argv, no patch | 0 | 0 |
| - | Quit seams (Decision 13) | existing observers, callback list and `KeepAliveOrigin`, no patch | 0 | 0 |
| - | Facade, host mode, infobars, menu routing, reserved keys | overlay only | 0 | 0 |

Current (W3-0): 7 patch files, 17 upstream files, 0 hot-file hunks. Projection after week 3: the same, or 8 patch files
if the framework is renamed by patch.

## W3-3: Engine configuration, readiness and quit seams, re-entrancy gate

Date 2026-10-24. Branch `engine/33-w3-3-gate` off `main` at `abeeec6`. `$CR` branch `arkt` at `e4a2ca5cca` (0001-0007)
before and after: no patch, no export. `/` had 12 GiB free and swap 8.8 GB used of 10 GB at the start of each build.

### What landed

- `app/ArktShell/project.yml`: configuration `Engine` replaces `Spike` (`ARKT_CHROMIUM_ENGINE`, `NSPrincipalClass`
  `BrowserCrApplication`, hardened runtime off, `ENABLE_DEBUG_DYLIB: NO`, `ArktEnvironmentOverrides` NO). A post-build
  script phase, which exits at once outside `Engine`, copies the engine framework when it changed (stamp of path, size
  and mtime; `cp -c` clone) and writes `ArktEngineFrameworkName` and `ArktEngineFrameworkVersion` from the framework's
  own `Info.plist` (`CFBundleExecutable`) and `Versions/Current`, plus `CrProductDirName = Arkt Dev Engine`, into the
  built `Info.plist`. The build log orders it `ProcessInfoPlistFile` -> `Ld` -> `PhaseScriptExecution Embed the engine
  framework` -> `CodeSign`. `Engine.xcconfig` (target level, `Engine` only) has `#include? "Local.xcconfig"`; the
  uncommitted `Local.xcconfig` names `ARKT_ENGINE_APP` (`.gitignore` line).
- `App/main.swift`: `#if ARKT_CHROMIUM_ENGINE` calls `engineMain()` and nothing else. `App/Engine/EngineMain.swift`
  (replaces `ChromiumSpikeMain.swift`; `ChromiumSpikeProbe.swift` is gone with the spike): `_ = ArktShellEmbedder.self`,
  the versioned path from the two keys, `dlopen(RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST)`, `--no-startup-window` appended
  unless passed, `ChromeMain`, `exit`. No `--arkt-native-window` (#21 has landed).
- `App/Engine/ArktShellEmbedder.swift`, `FacadeStandIn.swift`, `ReentrancyProbe.swift`: the stand-in embedder (below).
- Engine: `engine/arkt/api/BUILD.gn` (`//arkt/api` = the facade header, `//arkt/api:embedder`),
  `arkt_embedder.{h,mm}` (lookup, readiness queue, quit seams, lifetime keep-alive, nesting guard),
  `arkt_engine_facade.{h,mm}` (a first cut of the facade, below), `arkt_reentrancy_probe.{h,mm}`
  (`--arkt-reentrancy-probe`). `//arkt/browser` is split into `browser` (the hook) and `window` (everything else) so
  the hook can depend on the embedder, which uses the window code; `ArktBrowserWindow` gains `HoldShow` /
  `ReleaseHeldShow`. `gn check out/Spike '//arkt/*'`: `Header dependency check OK`. `browser_tabstrip.h` is included
  with `// nogncheck` (`//chrome/browser/ui` reaches `//arkt` through `//chrome/browser`).

Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome` (one fix for a missing `@` on a string literal, then
`The build has finished successfully.`, 0 `FAILED:`). Only `libchrome_dll.dylib` changed among the 518 dylibs; it was
re-cloned next to the bundle. App: `xcodegen generate`, then `xcodebuild -scheme ArktShell -configuration Engine
-derivedDataPath <scratch> -jobs 2 CONFIGURATION_BUILD_DIR=$EMB build`. A target-level `CONFIGURATION_BUILD_DIR`
does not work: the package modules (`ShellUI`, `Persistence`, ...) are then not found, so the bundle directory is
passed on the command line for all targets.

### Deviations from the plan

1. **Stand-in embedder without the header.** `EngineABIIsolationTests` lets only `ChromiumEngineKit` (W3-6) import
   `ArktEngineABI` and bars `project.yml` from naming it (#246 review: the typed embedder belongs in
   `ChromiumEngineKit`). W3-3 therefore keeps `@objc(ArktShellEmbedder)` in `App/Engine/`, implementing every
   `ArktEngineEmbedder` selector without declaring the protocol, and reaches the facade by selector name
   (`FacadeStandIn.swift`). The hook checks the selectors instead of `conformsToProtocol:` and logs both. W3-6/W3-9
   move the typed embedder into `ChromiumEngineKit` and delete the stand-in. W3-3 does not need W3-1.
2. **A first cut of the facade lands here, not in W3-4/W3-5.** The probes call `createTab` and `close` on a facade tab,
   so `arkt_engine_facade.mm` implements browsers, tab lists, tab creation, activation, navigation and closes with the
   nesting guard, and the `TabCreated`, `TabClosed`, `ActiveTabChanged`, `WindowOpened`, `WindowClosed` events in
   batches from a posted task (a facade call inside a notification `CHECK`s). Not yet: host mode and
   `createBrowserWithHost:` (W3-4, `NOTREACHED`), per-tab state events, stable containers, history, duplicate, close
   reasons other than `client` / `appTerminating`, `.skipUnloadHandlers`, extension actions and the test API (W3-5;
   logged, empty answers).
3. **Readiness queue for Chromium-created windows.** A URL argument is a real queued request: `--no-startup-window`
   makes `StartupBrowserCreator::ProcessCmdLineImpl` drop URL arguments (`startup_browser_creator.cc:1173`), so the
   seam reads `CommandLine::GetArgs()` and creates the `Browser` only after `embedderReady`. A `Browser` Chromium
   creates on its own (Dock reopen through `CreateBrowser` -> `chrome::NewEmptyWindow`, a URL from `open -a`) has no
   seam before construction short of a patch, so its window is built, **held hidden** (`HoldShow`) and its host request
   queued; replay asks the host and shows it. Its request kind is resolved at replay from the first tab (W3-4 owns the
   request fields). Until host mode (W3-4) the engine logs the embedder's host and keeps the placeholder host.
4. **Quit start uses `chrome::AddClosingAllBrowsersCallback`** (156 has no desktop `BrowserListObserver::
   OnBrowserClosing`; plan Decision 13 updated). `true` arrives from `tryToTerminateApplication` before
   `CloseAllBrowsersAndQuit` sets `IsTryingToQuit` (hence `trying to quit no` in the logs); `false` arrives once per
   browser on a cancel and is reported once. The same callback fires for "quit prevented by apps" and session end;
   W3-9 records those paths.
5. **Lifetime keep-alive origin `KeepAliveOrigin::PANEL_VIEW`**: referenced only by tests in 156 (`git grep` of
   `IsOriginRegistered` and of the origin), so registering it changes no shipped code path; `applicationWillTerminate`
   only `CHECK`s `BROWSER`.

### Gate

| Criterion | Result | Evidence |
|---|---|---|
| Launch from `$EMB`: class found, `engineDidStart`, no startup window, `embedderReady` after about 2 s, alive 30 s, 0 `FATAL`/`Check failed`, default user data dir ends in `Arkt Dev Engine` | PASS | run 1 below; census shows only the two requested windows |
| `nm -u` class check prints `0`; `ArktShellEmbedder` defined | PASS | below |
| Readiness: URL argument and Dock-style reopen queued, replayed after ready (queued, ready, host asked) | PASS (deviation 3) | run 1 |
| Quit: `engineWillBeginTerminating` before `native window destroyed`, then `engineWillTerminate`, exit after the completion; cancelled quit logs `engineDidCancelTerminating` and stays; no keep-alive `Check failed` | PASS | runs 1 and 2 |
| Re-entrancy probes recorded; mutators deferred in nested loops; forbidden case stall measured; batch under a Swift `NSAlert` handled, state consistent; engine-opened context menu measured | PASS (context menu: modelled, see below) | run 3 |
| `Chromium.app` logs `embedder class absent`, W5c checks pass; `Debug` unchanged | PASS | run 4, Debug comparison |

Binary checks (`$EMB/ArktShell.app`):

```
$ nm -u ArktShell.app/Contents/MacOS/ArktShell | grep -cF '_OBJC_CLASS_$_Arkt'
0
$ nm -m ArktShell.app/Contents/MacOS/ArktShell | grep -F 'OBJC_CLASS_$_Arkt'
0000000100458f30 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktShellEmbedder
0000000100459000 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktShellStandInWindowHost
$ plutil -p ArktShell.app/Contents/Info.plist   # Engine keys
  "ArktEngineFrameworkName" => "Chromium Framework"
  "ArktEngineFrameworkVersion" => "156.0.8078.48"
  "CrProductDirName" => "Arkt Dev Engine"
  "NSPrincipalClass" => "BrowserCrApplication"
$ codesign -dvvv <framework in the app>; codesign -dvvv <framework in out/Spike>
CDHash=0754af13a4a73b567d327a0424638020311ded9b   (both: Xcode did not re-sign the framework)
```

**Run 1** (readiness, cancelled quit; profile `$PROF/w3-3-run1`, port 9441, `--arkt-debug-reopen-before-ready`, a
`data:` URL argument). Launched 04:19:41; hook at 04:19:50 (9 s: no long first-launch scan this time, the framework
clone had the same content as the copy scanned in W3-0). Log, `ARKT:` prefixes shortened:

```
04:19:50.415 in-process hook alive
04:19:50.415 embedder class ArktShellEmbedder found (conforms to ArktEngineEmbedder no, responds to every selector yes)
04:19:50.415 default user data dir /Users/<user>/Library/Application Support/Arkt Dev Engine
04:19:50.415 lifetime keep-alive registered (origin PANEL_VIEW)
04:19:50.415 window request queued kind=startupURL url=data:text/html,<title>W3-3 startup URL</title>...
04:19:50.415 engineDidStart
04:19:50.577 debug reopen (chrome::NewEmptyWindow) before ready
04:19:50.699 window request queued kind=reopen window session id 951776989 (window held hidden)
04:19:50.811 native window show held (embedder not ready)
04:19:52.565 [shell] simulated start finished, calling embedderReady
04:19:52.565 embedderReady (2 queued request(s))
04:19:52.579 [shell] hostForEngineWindowRequest kind 3 initial URL data:text/html,...
04:19:52.581 host asked kind=startupURL window session id 951776991 answered ArktShellStandInWindowHost; placeholder host kept until W3-4
04:19:52.697 [shell] hostForEngineWindowRequest kind 2 initial URL chrome://newtab/
04:19:52.700 host asked kind=reopen window session id 951776989 answered ArktShellStandInWindowHost; placeholder host kept until W3-4
04:19:52.711 window number 95173
```

Census `normal=1` after the reopen and `normal=2` after replay; no other window: `--no-startup-window` holds. CDP
`/json/list`: the startup URL page and the reopen's New Tab only. Alive 29 s later, 0 `FATAL`/`Check failed` (one
`ERROR`: an IPH shown before its browser was active, Chromium's, harmless).

Cancelled quit: `onbeforeunload` set with a user gesture (`cdp.mjs --user-gesture`, `hasBeenActive` true); after the
frontmost check, AX `click menu item "Quit Chromium"`. Chromium showed its "Leave site?" dialog (an `AXDialog`
window, buttons Cancel and Leave); AX `click button "Cancel"`:

```
04:20:33.356 quit started (trying to quit no)
04:20:33.356 [shell] engineWillBeginTerminating
04:21:17.531 quit cancelled
04:21:17.531 [shell] engineDidCancelTerminating
```

The process stayed. Then, handler cleared, Quit again: `quit started` 04:21:23.214, both `TabClosed(reason 5)` (app
terminating) and `WindowClosed` batches, `native window destroyed` twice from 04:21:23.241, `app terminating`
04:21:23.272, `engineWillTerminate`, completion and `lifetime keep-alive released (embedder flushed)` 04:21:23.596.
**The process did not exit**: `ChromeDevToolsManagerDelegate` (`chrome_devtools_manager_delegate.cc:195-205`)
registers a `REMOTE_DEBUGGING` keep-alive whenever `--no-startup-window` and `--remote-debugging-port` are both
present ("controlled entirely by the automation process"). A sample showed the main thread idle in `[NSApp run]`;
stopped by its PID. This is Chromium's behaviour, not the seam's, and it matters for W3-9 (below).

**Run 2** (full quit; profile `$PROF/w3-3-run2`, no CDP port): AX Quit at 04:24:37:

```
04:24:37.526 quit started (trying to quit no)
04:24:37.526 [shell] engineWillBeginTerminating
04:24:37.552 native window destroyed
04:24:37.552 app terminating
04:24:37.552 [shell] engineWillTerminate
04:24:37.877 [shell] simulated flush done, calling the completion
04:24:37.877 lifetime keep-alive released (embedder flushed)
```

The process exited right after the release (last log write 04:24:37). 0 `FATAL`/`Check failed` in runs 1 and 2; no
`KeepAliveRegistry` check. Crash dumps under `~/Library/Application Support/Arkt Dev Engine/Crashpad`: 0 before and
after all runs.

**Run 3** (`--arkt-reentrancy-probe`; profile `$PROF/w3-3-run3`, port 9442). The engine opens each loop from a posted
Chromium task and closes it after 2 s with a common-mode timer; a 20 ms heartbeat timer measures Chromium task stalls;
the app was activated only for these phases. Times are from the phase's begin line.

| Phase | Main-actor job ran in the loop | Facade calls from it | Deferred work ran | Chromium heartbeat max gap |
|---|---|---|---|---|
| `NSMenu` from a Chromium task | yes, +342 ms, mode `NSEventTrackingRunLoopMode` | `createTab` deferred (handle at once, session id -1), `close` answered `held` | after the menu closed (+2.27 s): inserted, then `TabCreated`, `TabClosed(client)` | 2247 ms (Chromium bans its tasks) |
| `NSMenu` from a Chromium task, application tasks allowed (as `RenderViewContextMenuMacCocoa` via `ui::ShowContextMenu(allow_nested_tasks=true)`) | yes, +321 ms, tracking mode | deferred, `held` | inside the menu (+11 ms), batch delivered in tracking mode | 525 ms |
| `NSAlert runModal` from a Chromium task | yes, +389 ms, `NSModalPanelRunLoopMode` | deferred, `held` | after the alert (+2.06 s) | 2038 ms |
| Forbidden: Swift `NSAlert runModal` inside a batch handler | - | - | - | **2018 ms**: Chromium tasks stall for the whole alert (the handler runs inside a Chromium task) |
| Batch while a Swift `NSAlert` (opened from a run-loop callout) is up | timer callout inside the alert, modal mode | deferred, `held` | inside the alert (+12 ms) | 38 ms; two batches (`TabCreated, TabClosed` from Swift's calls, then the engine's `TabCreated`) handled under the alert; shell state consistent after it (3 tabs shell, 3 engine) |

Shell state (the stand-in's tab table from events against the facade's tab lists) was consistent at every phase end.
0 `FATAL`/`Check failed`; alive until stopped by its PID.

Engine-opened page context menu: still not shown on an Arkt window (`RenderViewContextMenuMacCocoa::Show` returns
without a top-level `views::Widget`, `render_view_context_menu_mac_cocoa.mm:77-82`, week-2 results row 7), so it
cannot be opened for real. The second phase models it exactly: an `NSMenu` tracked from inside a Chromium task with
`ScopedAllowApplicationTasksInNativeNestedLoop`, which is what `ui::ShowContextMenu(..., allow_nested_tasks=true)`
does. In that case Chromium tasks, facade batches and deferred facade work all run inside the menu; Swift handlers
must tolerate that (Decision 3 already says so).

**Run 4** (`$OUT/Chromium.app`, profile `$PROF/w3-3-chromium`, port 9443, the three probes, `--arkt-trace-visibility`,
`https://example.com`): `ARKT: embedder class ArktShellEmbedder absent`; W5c Step 3 over CDP: example.com `visible`,
`probe.create()` -> still `visible` (`tab list rows 2`), activate about:blank -> `hidden`, back -> `visible`, with
matching `ARKT: visibility` lines; 0 `FATAL`/`Check failed`. The AX row-selection half was not repeated (the window
code it exercises is unchanged; W3-0 ran it).

**Debug unchanged.** `main` at `abeeec6` and this branch, both built `Debug` with `CODE_SIGNING_ALLOWED=NO` (as CI):
`Info.plist` identical (`diff` of `plutil -p` empty; `NSPrincipalClass` `NSApplication`), `strings <ArktShell.debug.dylib>
| grep -c "ARKT engine"` prints `0` in both (the Engine binary has 3), no engine symbol (`ArktShellEmbedder`,
`engineMain`, `ChromeMain`) and no `Contents/Frameworks`; the embed script phase runs and exits at once.

Copy only on change: an incremental `Engine` rebuild prints `Engine framework unchanged: Chromium Framework.framework
156.0.8078.48`; the framework binary keeps its inode (4723531) and CDHash. The first incremental rebuild also showed
that without a declared input Xcode ran the script phase before `ProcessInfoPlistFile` and then rewrote the
Info.plist, dropping the three keys (the app then stops with `Info.plist has no ArktEngineFrameworkName`); the phase
now lists `$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)` as its input, and two further incremental rebuilds order it
`ProcessInfoPlistFile` -> script -> `CodeSign` with the keys present and `codesign -v` passing.

**Run 5** (`--arkt-embedder-fail`, URL argument, `--arkt-debug-reopen-before-ready`; profile `$PROF/w3-3-run5`):
`embedderFailed (dropping 2 queued request(s))` 2 s after start, the held reopen window's `Browser` closed (`browsers
normal=0`, `native window destroyed`), no window shown, 0 `FATAL`/`Check failed`. The process stays: the stand-in has
no launch-failure alert and no quit path yet (W3-7 part C); stopped by its PID.

Swift: `swift test --skip ShellKitGUITests` in ShellKit: 481 tests (baseline + 0), all pass, including
`EngineABIIsolationTests` (no app file imports `ArktEngineABI`, `project.yml` does not name it).

### What W3-4 and later need

- W3-4: host mode with the embedder's host (today logged and discarded), `createBrowserWithHost:`, request kinds from
  the call site instead of resolution at replay, `respondsToSelector:` guards for `activateTab` / `tabListChanged:`
  (#246 follow-up), and the held-window path switched to the embedder host at replay.
- W3-5: close reasons `page` / `extension` / `windowClosing`, `.skipUnloadHandlers`, stable containers, state events,
  history, duplicate, extension actions, the test API. The facade file from this task is its starting point. Known
  gap: `closeWithMode:` on a handle whose deferred insert has not run yet, called outside a nested loop, finds no tab
  and answers `closed` while the insert still lands later; closes of pending handles must queue behind the insert.
- The stand-in's `engineWillBeginTerminating (<n> visible window(s))` counts `NSApp.windows`, not shell windows.
- W3-6/W3-9: move the typed `ArktShellEmbedder` into `ChromiumEngineKit` and delete `FacadeStandIn.swift`; the hook
  already accepts either (selector check).
- W3-9: an engine launch with `--remote-debugging-port` (implied by `--no-startup-window`) never exits on Quit, because
  of Chromium's `REMOTE_DEBUGGING` keep-alive. Quit and Dock Quit checks must run without a CDP port (as run 2), or the
  runner closes the browser over CDP (`Browser.close`) for those runs.
- W3-7 part C can wire `AppComposition.start` / `prepareForTermination()` / `flush()` to the seams as described; they
  fire in the planned order.

## W3-0: engine baselines and embedder class lookup

Date 2026-10-24. Branch `engine/33-w3-0-baselines` off `main` at `1d15a49`. `$CR` branch `arkt` at `e4a2ca5cca`
(0001-0007) before and after; no patch change, no export.

Deviations from the plan's steps:
- Step 1: the engine lane keeps the existing worktree `arkt-wt/engine` (the one week 2 and #244 used) instead of a new
  `arkt-wt/engine-week3`, on a branch per task (`engine/33-w3-0-baselines`) rather than one long
  `engine/33-chromium-engine`. `$REPO` in the plan means this worktree. `readlink $CR/arkt` already printed
  `$REPO/engine/arkt`, so it was not repointed.
- Step 4: #21 has landed (W9, pull request #247): the native window is the default and `--arkt-native-window` is no
  longer read, so the checks ran with no window switch.

### Step 2: patch counts

```
$ git -C $CR rev-list --count 156.0.8078.48..arkt --
7
$ wc -l < $REPO/engine/patches/chromium/.patches
7
$ git -C $CR diff 156.0.8078.48..arkt -- chrome/browser/ui/browser_window/internal/browser_window_features.cc chrome/browser/ui/tabs/tab_features.cc | grep -c '^@@'
0
$ git -C $CR diff --stat 156.0.8078.48..arkt -- | tail -1
 17 files changed, 74 insertions(+), 5 deletions(-)
```

`$CR` needs `--` after `arkt` in `rev-list` and `log`: the checkout has an `arkt` path (the overlay symlink), so a bare
`arkt` is ambiguous.

### Step 3: embedder class lookup

`ArktBrowserMainExtraParts::PostBrowserStart` logs, right after `in-process hook alive`, one line per name for
`NSClassFromString(@"ArktShellEmbedderProbe")` (the W3-0a class) and `NSClassFromString(@"ArktShellEmbedder")` (the
W3-3 class, absent everywhere today): `ARKT: embedder class <name> absent`, or `found (responds to init <yes|no>,
engineDidStart: <yes|no>)` from `instancesRespondToSelector:` (selectors by name, as the facade header is not in a
`BUILD.gn` target yet). W3-3 replaces the probe name with the handshake itself.

Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome` (swap 8.8 GB used of 10 GB, `/` 10 GiB free before and after),
`The build has finished successfully.`, 0 `FAILED:`, 34 s; the string is in `libchrome_dll.dylib`.

`Chromium.app` (`$OUT`, profile `$PROF/w3-0-chromium`, port 9431):

```
ARKT: in-process hook alive
ARKT: embedder class ArktShellEmbedderProbe absent
ARKT: embedder class ArktShellEmbedder absent
```

W3-0a app (`$EMB/ArktShell.app`, the `Spike` configuration binary from #229, unchanged; its framework replaced with a
`cp -c -Rp` of the new `Chromium Framework.framework` and the 518 dylibs re-cloned next to it; profile
`$PROF/w3-0-app`, port 9432). Launched 03:36:12; the first launch after the copy spent about 100 s in `dlopen` as
expected:

```
$ nm -m $EMB/ArktShell.app/Contents/MacOS/ArktShell | grep -F 'OBJC_CLASS_$_ArktShellEmbedderProbe'
000000010043c918 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktShellEmbedderProbe
[03:37:52.996] ARKT: in-process hook alive
[03:37:52.996] ARKT: embedder class ArktShellEmbedderProbe found (responds to init yes, engineDidStart: no)
[03:37:52.996] ARKT: embedder class ArktShellEmbedder absent
[03:37:53.076] ARKT probe: main queue drained
[03:37:53.608] ARKT probe: main actor resumed
```

Alive 30 s later, 0 `FATAL`/`Check failed`, stopped by its PID. **Decision 1 holds:** a Swift class in the main
executable is reached from `//arkt` through the runtime, with no exported symbol on either side, and it is absent in
the GN-built app. The header frozen in W3-2 stands. (`engineDidStart: no` is expected: the probe class implements
nothing.)

### Step 4: W5c Step 3 and W6 Step 3 on the default path

Same `Chromium.app` run: `--arkt-trace-visibility`, `action-probe`, `tabs-probe` and `dialog-probe`,
`https://example.com`, `PROBE_SW=ceojeochoeiibbkbcnnidcahamphllac/sw.js`. Census `normal=1 arkt=1 views=0`.

- W6 Step 3: `ARKT: native window session id 1814676206` = `ARKT tabs.query windows=1814676206` = `windows.getAll`
  `[[1814676206,"normal",1]]`. Pass.
- W5c Step 3: `probe.create()` -> example.com `"visible"` (`tab list rows 2`); activate about:blank -> `"hidden"`;
  back -> `"visible"`; matching `ARKT: visibility` and `native window mounted tab` lines. AX, after the frontmost and
  key-window checks: `select row 2` -> example.com `hidden`, about:blank `visible`; `select row 1` -> `visible` /
  `hidden`. Pass. The AX path of the week-2 plan needs adapting: the `Tabs` table is
  `table 1 of (first scroll area of window 1 whose description is "Tabs")`; its index among the window's scroll areas
  changes with the mounted page. Window-only screenshots `$PROF/shots/w3-0-w5c-row1.png`, `-row2.png` (kept locally).
- 0 `FATAL`/`Check failed`/`Received signal` in the run.

### ModelSheet initial button state (#252 review)

`ModelSheet::BuildContent` passed only button titles; its "disabled OK" branch set `primaryEnableDelay = 0`, which is
already the default, so a `ui::DialogModel` that starts with OK or Cancel disabled showed them enabled.
`ModelSheet::Show` now calls `OnDialogButtonChanged()` after `beginOnWindow:`, which applies the model's enabled state
(it keeps the content's fallback titles: `setPrimaryTitle:enabled:` ignores an empty title), and the no-op branch is
gone. No extension dialog shipped in 156 starts with a disabled button, so only the regression could be run: the
uninstall sheet (`dialog-probe` page, `uninstall()` with a gesture) shows `dialog sheet shown
ExtensionUninstallDialog`; AX buttons `Cancel`, `Remove`, both enabled; AXPress `Cancel` gives `uninstall canceled by
user` and `dialog sheet closed`.

### Step 5: command ids

W3-1 has not started (no pull request), so the table checks the plan's proposed `EngineCommand` and
`EngineDisposition` names; repeat it when W3-1 fixes the names, and on every rebase. Commands from
`git -C $CR grep -n -E '#define (IDC_...) ' arkt -- chrome/app/chrome_command_ids.h`; the Mac main menu
(`main_menu_builder.mm`) uses the same ids for its items (`IDC_DEV_TOOLS` for Developer Tools, not
`IDC_DEV_TOOLS_TOGGLE`).

| `EngineCommand` | Chromium | Value | Line |
|---|---|---|---|
| `back` | `IDC_BACK` | 33000 | 42 |
| `forward` | `IDC_FORWARD` | 33001 | 43 |
| `reload` | `IDC_RELOAD` | 33002 | 44 |
| `closeWindow` | `IDC_CLOSE_WINDOW` | 34012 | 55 |
| `newTab` | `IDC_NEW_TAB` | 34014 | 56 |
| `closeTab` | `IDC_CLOSE_TAB` | 34015 | 57 |
| `exit` | `IDC_EXIT` | 34031 | 75 |
| `viewSource` | `IDC_VIEW_SOURCE` | 35002 | 137 |
| `print` | `IDC_PRINT` | 35003 | 138 |
| `savePage` | `IDC_SAVE_PAGE` | 35004 | 139 |
| `find` | `IDC_FIND` | 37000 | 185 |
| `zoomIn` | `IDC_ZOOM_PLUS` | 38001 | 204 |
| `zoomReset` | `IDC_ZOOM_NORMAL` | 38002 | 205 |
| `zoomOut` | `IDC_ZOOM_MINUS` | 38003 | 206 |
| `devTools` | `IDC_DEV_TOOLS` | 40004 | 222 |
| `history` | `IDC_SHOW_HISTORY` | 40010 | 228 |
| `downloads` | `IDC_SHOW_DOWNLOADS` | 40012 | 230 |
| (tag Arkt menus must not use, Decision 9) | `IDC_FILE_MENU` | 57326 | 612 |
| (tag Arkt menus must not use, Decision 9) | `IDC_TAB_MENU` | 57323 | 615 |

`EngineDisposition` against `ui/base/window_open_disposition.h` (`enum class WindowOpenDisposition`, no explicit
values, so the value is the declaration index: `UNKNOWN` 0, `CURRENT_TAB` 1, `SINGLETON_TAB` 2, ...):

| `EngineDisposition` | Chromium | Value | Line |
|---|---|---|---|
| `currentTab` | `CURRENT_TAB` | 1 | 10 |
| `newForegroundTab` | `NEW_FOREGROUND_TAB` | 3 | 13 |
| `newBackgroundTab` | `NEW_BACKGROUND_TAB` | 4 | 14 |
| `newWindow` | `NEW_WINDOW` | 6 | 16 |

### Step 6: Swift baselines (`main` at `1d15a49`)

`nice -n 10`, scratch paths on the Chromium disk, after the Chromium build and GUI runs had finished.

- ShellKit, `swift test --skip ShellKitGUITests`: **481** tests (208 + 33 + 23 + 4 + 24 + 177 + 12 across the test
  products), all pass. Matches W3-2's 481.
- ArktCore, `swift test`: **349** tests (88 + 100 + 63 + 98), all pass.

Later tasks record "baseline + N" against these.

### Plan fixes in this pull request

- Patch budget: a row for 0007 (#244), and the projection is now 7 patch files, 17 upstream files, 0 hot-file hunks,
  at worst 8 with a framework rename (it said 6 and 7).
- W3-0 Step 2's expected count is 7 (it said 6).

No leftover processes: both runs were stopped by PID; no `Chromium` or `ArktShell` process afterwards.

## W3-0a: main-actor probe on the `Spike` configuration

Date 2026-10-23. Branch `engine/33-w3-0a-mainactor-probe` off `main` at `3c8294b`. No Chromium build and no engine
worktree: `out/Spike` was only read and copied from (APFS clones, `cp -c`), `$CR/arkt` was not touched.

**Verdict: GO for the threading model, with one correction to Decision 3 and the Rules (below).** Swift's main-actor
executor runs under Chromium's run loop: a `Task { @MainActor }` and a `DispatchQueue.main.async` block scheduled
before `ChromeMain` both run as soon as Chromium's `MessagePumpNSApplication` spins, `Task.sleep` resumes on the main
actor, and main-actor jobs keep running inside native nested loops (menu tracking, `NSAlert` modal) entered from a
run-loop callout. They do **not** run inside a nested loop entered from a main-actor job itself. Chromium's own tasks
kept running in every Swift-opened nested loop.

### Probe

- `app/ArktShell/App/ChromiumSpikeProbe.swift` (new, only under `ARKT_CHROMIUM_SPIKE`): the `@objc(ArktShellEmbedderProbe)`
  class, `startMainActorProbe()` and, behind the switch `--arkt-probe-nested`, `NestedLoopProbe`. The plan put the
  probe inline in `ChromiumSpikeMain.swift`; it is a separate file so the nested-loop part stays out of the entry
  point. `ChromiumSpikeMain.swift` gains two statements before `ChromeMain`: `_ = ArktShellEmbedderProbe.self` and
  `startMainActorProbe()`. Nothing touches `NSApplication` before `ChromeMain`.
- Plan step 1: `Task { @MainActor in try await Task.sleep(for: .milliseconds(500)); log("main actor resumed") }` and
  `DispatchQueue.main.async { log("main queue drained") }`.
- Nested loops (extension of step 1, critic finding M6). Three tickers count main-thread work every 100 ms: a
  main-actor `Task.sleep` loop, a `DispatchQueue.main.asyncAfter` chain and a `Timer` in `.common` modes (the
  control). 20 s after the main actor first runs, four phases each open one nested loop for 3 s, with the app
  activated just before each: an `NSMenu` (`popUp(positioning:at:in:)`) and an `NSAlert` (`runModal`), each entered
  once from a `.common` run-loop timer callout and once from a main-actor job (`Task { @MainActor }`). Each loop is
  closed by a `.common` timer (`cancelTracking`, or `stopModal` plus a posted application-defined event), so closing
  never depends on main-actor jobs. A phase's end is logged by the loop's own caller.
- Chromium tasks: a Node CDP client on the probe's own port sends `Browser.getVersion` (handled on the browser UI
  thread) every 50 ms for the whole run and logs any reply slower than 150 ms.
- Build: `xcodegen generate`, then `nice -n 10 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell
  -configuration Spike -derivedDataPath <scratch derived data> -jobs 2 build`.
- Layout (Task WE Run B): `cp -Rp` of the built `ArktShell.app` to `$EMB`, `cp -c -Rp` of
  `$OUT/Chromium.app/Contents/Frameworks/Chromium Framework.framework` into its `Contents/Frameworks`, and
  `cp -c -p $OUT/*.dylib $EMB/` (518 dylibs). The executable was later replaced in place for the warm run.
- Launch: `$EMB/ArktShell.app/Contents/MacOS/ArktShell --user-data-dir=$PROF/w3-0a-run<n> --use-mock-keychain
  --no-first-run --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9373
  --arkt-probe-nested 'data:text/html,<title>W3-0a probe</title><h1>W3-0a probe</h1>'`, PID from `$!`, killed by
  that PID.

### Results

Plan step 3 (dead-strip safeguard). The plan's `grep 'OBJC_CLASS_$_ArktShellEmbedderProbe'` prints nothing because
`$` is a regular-expression anchor; use `grep -F`:

```
$ nm -m ArktShell.app/Contents/MacOS/ArktShell | grep -F 'OBJC_CLASS_$_ArktShellEmbedderProbe'
000000010043c918 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktShellEmbedderProbe
```

Acceptance (both probe lines within 3 s of the hook, alive 30 s, class defined): **pass** in both runs.

| Run | Launch | `in-process hook alive` | `main queue drained` | `main actor resumed` | Alive | `FATAL` |
|---|---|---|---|---|---|---|
| 1 (fresh copy) | 21:35:16 | 21:36:52.818 | 21:36:52.909 (+0.09 s) | 21:36:53.434 (+0.62 s) | 3 min 42 s, then killed | 0 |
| 2 (warm) | 21:39:22 | 21:39:27.395 | 21:39:27.460 (+0.07 s) | 21:39:27.984 (+0.59 s) | 1 min 44 s, then killed | 0 |

`main actor resumed` includes the probe's own 500 ms sleep. The first launch after the copy spent about 95 s in
`dlopen` (system scanning, as in Task WE).

Nested loops. Counts are ticks during the 3 s the loop was open (about 30 expected per ticker); the durations print
as `3.246 ms` in the log because the formatter used the system locale's grouping separator (3246 ms).

| Phase (entered from) | Run 1 main actor / main queue / run-loop timer | Run 2 | Slowest `Browser.getVersion` |
|---|---|---|---|
| `NSMenu` tracking, run-loop timer callout | 31 / 31 / 32 | 31 / 31 / 32 | under 150 ms |
| `NSAlert` modal, run-loop timer callout | 29 / 29 / 30 | 29 / 29 / 31 | under 150 ms |
| `NSMenu` tracking, main-actor job | **0 / 0** / 32 | **0 / 0** / 32 | under 150 ms |
| `NSAlert` modal, main-actor job | **0 / 0** / 30 | **0 / 0** / 30 | under 150 ms |

CDP over each whole run, covering all four phases: run 1 `1715 calls, 0 over 150 ms, max 33 ms`; run 2
`1430 calls, 0 over 150 ms, max 15 ms`.

Log lines (run 2):

```
[21:39:48.509] ARKT probe: menu-from-runloop-timer begin
[21:39:51.758] ARKT probe: menu-from-runloop-timer end after 3.242 ms: main actor ticks 31, main queue ticks 31, run loop timer ticks 32
[21:39:54.281] ARKT probe: alert-from-runloop-timer begin
[21:39:57.305] ARKT probe: alert-from-runloop-timer end after 3.024 ms: main actor ticks 29, main queue ticks 29, run loop timer ticks 31
[21:39:59.894] ARKT probe: menu-from-main-actor-job begin
[21:40:03.134] ARKT probe: menu-from-main-actor-job end after 3.239 ms: main actor ticks 0, main queue ticks 0, run loop timer ticks 32
[21:40:05.711] ARKT probe: alert-from-main-actor-job begin
[21:40:08.722] ARKT probe: alert-from-main-actor-job end after 3.011 ms: main actor ticks 0, main queue ticks 0, run loop timer ticks 30
```

Engine-opened menu: not measured. A CDP right click (`Input.dispatchMouseEvent`, `mouseMoved` then right
`mousePressed` / `mouseReleased`) reached the page (`contextmenu` listener count 1) but no native menu began tracking
in the spike's Arkt window host, so the case "nested loop entered by Chromium from inside a Chromium task" stays with
the W3-3 gate, which drives it from a posted Chromium task as the plan already says.

Errors: run 1 has only the known teardown pair (`bootstrap_look_up dev.arkt.ArktShell.MachPortRendezvousServer.1:
Permission denied` and `No rendezvous client`, one helper, after the kill; week-2 results, "Teardown rendezvous
lines"); run 2 has no `ERROR` line. No probe process left afterwards.

### What this means for the plan

1. **Risk 1 is retired.** `MessagePumpNSApplication` drains the main dispatch queue, so `Task.sleep` on the main
   actor, async `AppComposition.start` and the contract runner's waits work under `ChromeMain`. W3-2 and W3-6 can
   proceed on the threading model as written.
2. **Decision 3, "Nested run loops", needs a qualifier.** The main queue drains in every common-mode spin *except*
   inside a nested loop entered from a main-queue callout (measured above; it matches CFRunLoop's rule of not servicing
   the main queue port while a main-queue block, here a main-actor job, is on the stack). Swift's main executor is the main queue, so a
   menu or modal opened synchronously from a main-actor job freezes every other main-actor job (timers, `Task.sleep`
   resumptions, async completions) until it closes. Nested loops entered from a run-loop callout (AppKit event
   dispatch, timers, and Chromium's work source, which is a run-loop source) do drain main-actor jobs, so the
   facade's nesting guard for Chromium-entered loops stays necessary.
3. **Rules, "No nested loops in engine handlers", is wrong in its last sentence.** "Present modals from a fresh
   main-actor turn" is exactly the case that starves the main actor. Replace with: present menus and alerts from an
   AppKit action or event callout, or non-blocking (`beginSheetModal(for:)`, `NSMenu.popUp` from an action), or
   schedule the synchronous call on the run loop (`RunLoop.main.perform(inModes: [.common])`), never synchronously
   from a `Task` or `DispatchQueue.main.async`.
4. **Chromium tasks keep running inside Swift-opened nested loops**, even one entered from a main-actor job
   (`Browser.getVersion` never slower than 33 ms). This is consistent with Chromium banning its tasks only in native
   loops entered while one of its own tasks runs (`thread_controller_with_message_pump_impl.cc:389`, `:448`). So while a Swift menu or modal is open, facade event batches (posted Chromium tasks)
   still run and call Swift handlers on the same stack. Decision 3 should state it: handlers must not assume the
   shell is idle when they run, and the W3-3 gate should add "facade batch arrives while a Swift-opened `NSAlert` is
   up" next to its existing "Swift modal inside a batch" case.
5. Plan step 3's `grep` needs `-F` (above); W3-3's `nm -u` check has the same `$` and should also use `-F`.

## W3-2: facade header and its Swift module

Date 2026-10-24. Branch `engine/33-w3-2-facade` off `main`. No Chromium build, no engine worktree; `$CR` not touched.
Swift builds used a scratch path on the Chromium disk at `nice -n 10`.

**Frozen.** The plan freezes the header after the class lookup. W3-0a recorded the precondition the handshake rests on:
the `@objc` probe class is defined in the app binary (`_OBJC_CLASS_$_ArktShellEmbedderProbe`, `__objc_data`), so a
Swift class in the main executable is registered with the Objective-C runtime and reachable by
`NSClassFromString` once loaded. The runtime lookup from the hook itself is W3-0 step 3; if it ever logs `absent` in
the app, W3-0 stops and the handshake is redesigned with the maintainer (Decision 1), which reopens this header anyway.

Files:
- `engine/arkt/api/arkt_engine.h` and its byte-identical copy
  `app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h` with `module.modulemap`. Protocols
  `ArktEngineEmbedder`, `ArktEngine`, `ArktBrowserHandle`, `ArktTabHandle`, `ArktWindowHost`, `ArktWindowRequest`,
  `ArktEngineEvent`, `ArktExtensionAction`, `ArktHistoryEntry`; enums `ArktCloseMode`, `ArktCloseResult`,
  `ArktCloseReason`, `ArktTabOrigin`, `ArktEngineEventKind`, `ArktWindowRequestKind`. Every protocol is
  `NS_SWIFT_UI_ACTOR` (imports as `@MainActor`), nullability is annotated (`NS_ASSUME_NONNULL`), and selectors carry
  `NS_SWIFT_NAME`s (`createTab(url:active:)`, `close(mode:)`, `goToHistory(offset:)`, `host(for:)`, ...).
- Beyond the plan's list, for EngineClient's rules 9 and 10 (#81, pull request #238): `ArktHistoryEntry`,
  `backEntries` / `forwardEntries` (nearest first, as `TabHistory`), `goToHistoryOffset:` and `duplicate` on the tab
  handle. Also `removeEventSink:` (so several `ChromiumEngine` instances over one facade can stop observing, W3-9),
  `testAPIEnabled`, the window `host` on the browser handle, and two event kinds, `TabReplaced` and `TabMoved`.
- `ArktWindowHost` moved from `arkt/browser/arkt_window_host.h`, which now imports the facade header and keeps
  `ArktTabEvent`. The placeholder-only `activateTab` block and `tabListChanged:` are `@optional`; `tabListChanged:`
  takes an untyped `NSArray*` (its elements are `ArktTabEvent`, a class the header cannot name). The engine blocks
  (`closeRequested`, `validateCommand`, `executeCommand`) are `nullable`, as the engine nils them on teardown.
- `ArktEngineABI` is a C-family SwiftPM target; SwiftPM needs one source file per such target
  (`out/Products/Debug/ArktEngineABI.o` missing without it), so `arkt_engine_abi.m` imports the header and defines
  nothing.
- `ArktEngineABITests/ConformanceTests.swift` (12 tests): Swift `NSObject` classes implementing every protocol, a
  scripted facade that delivers one batch per flush, an event batch and window requests, close modes, history and
  duplicate, the termination seams and the embedder lookup by runtime name.
- `IsolationTests/EngineABIIsolationTests.swift` (8 tests): only `Sources/ChromiumEngineKit`,
  `Tests/ChromiumEngineKitTests` and `Tests/ArktEngineABITests` import `ArktEngineABI`; only those targets depend on
  it in `Package.swift`; no product and not `project.yml` names it; the two header copies are byte-identical; the
  header has no `#include`, `namespace`, `std::`, `template`, `@interface`, `@class` or `@implementation`, and imports
  only AppKit and Foundation. Checked to fail: an import from ShellUI, a dependency from `Motion` and one byte added
  to the copy each fail their test.

Acceptance:

```
$ clang -fsyntax-only -fobjc-arc -x objective-c   -isysroot $(xcrun --show-sdk-path) engine/arkt/api/arkt_engine.h   # exit 0
$ clang -fsyntax-only -fobjc-arc -x objective-c++ -isysroot $(xcrun --show-sdk-path) engine/arkt/api/arkt_engine.h   # exit 0
$ grep -E '#include|namespace|std::|template|@interface' engine/arkt/api/arkt_engine.h                                # no output, exit 1
$ swift test --filter 'IsolationTests|ArktEngineABITests'
Test run with 23 tests in 3 suites passed      (IsolationTests: 15 before, + 8)
Test run with 12 tests in 1 suite passed       (ArktEngineABITests)
```

`swift test --skip ShellKitGUITests`: baseline 461 tests (`main` at `d63d1a3`), now 481 (baseline + 20), all passing.

Engine side, not built (no Chromium build in this task): `arkt_window_host.h`, `arkt_placeholder_window_host.h`,
`arkt_window_host.mm` and `arkt_tab_list_view.mm` compile with `clang++ -fsyntax-only -fobjc-arc -std=c++20 -Werror
-Wall -Wextra -Wobjc-missing-property-synthesis -Wnullability-completeness -I engine`, together with a file that
repeats `ArktBrowserWindow`'s and `ArktPlaceholderWindowHost`'s uses of the moved protocol (`@synthesize` of the
optional `activateTab`, `tabListChanged:` with `NSArray<ArktTabEvent*>*`, block assignments and `nil` resets through
`id<ArktWindowHost>`). The header is not yet in a `BUILD.gn` target; W3-3 creates `engine/arkt/api/BUILD.gn` and its
first incremental `out/Spike` build is the real check.

Binary check without the framework (the app-binary variant stays with W3-3), with `-F` as W3-0a recorded:

```
$ nm -u <scratch>/out/Products/Debug/ArktEngineABITests.xctest/Contents/MacOS/ArktEngineABITests | grep -cF '_OBJC_CLASS_$_Arkt'
0
$ nm -m <same binary> | grep -F 'OBJC_CLASS_$_Arkt'
000000000004e218 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktEngineABITestEmbedder
```

The conformance tests reference no engine class; the only `Arkt` class symbol is the test's own embedder, defined.

Plan: contract rules 9 and 10 now exist on `main` (#81, pull request #238: history and `duplicateTab`), so the plan's
new rules are renumbered 11-16 (W3-1, W3-6 and W3-9 updated; the runner's target is 16/16), in a separate commit.
