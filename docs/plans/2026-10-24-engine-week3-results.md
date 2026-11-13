# Engine Week 3 Results

Plan: `docs/plans/2026-10-24-engine-week3.md` (pull request #220). Issue: #33. Variables as in the plan's Rules
(`$CHROMIUM_ROOT`, `$CR`, `$OUT` = `$CR/out/Spike`, `$PROF` = `$CHROMIUM_ROOT/profiles`, `$EMB` =
`$CHROMIUM_ROOT/embed-week3`).

| Task | What | Status | Result |
|---|---|---|---|
| W3-0a | Main-actor probe on the `Spike` configuration | DONE (#229) | GO; nested loops opened from a main-actor job starve the main actor (below) |
| W3-0 | Engine worktree, baselines, class lookup, command ids | DONE | lookup `found` in the app, `absent` in `Chromium.app`; 7 patch files, 17 upstream files, 0 hot-file hunks; W5c Step 3 and W6 Step 3 pass; command-id table; Swift baselines ShellKit 481, ArktCore 349; see "W3-0" below |
| W3-1 | `EngineAPI` additions, harness drivers, contract rules 11-16 (engine lane, by decision) | DONE | windows, activation, origin, close modes and reasons, hosting, commands, extensions, per-window routing; rules 11-16 pass on `InMemoryEngine`, FakeEngine passes 11, 12, 15 and skips 13, 14, 16; ShellKit 481 + 28; see "W3-1" below |
| W3-2 | Facade header and its Swift module | DONE (#246) | see "W3-2" below |
| W3-3 | Engine configuration, readiness and quit seams, re-entrancy gate (GATE) | DONE | **GATE PASS** with recorded deviations (readiness queue for Chromium-created windows, quit-start seam, CDP keep-alive); see "W3-3" below |
| W3-4 | Host mode for ShellUI windows | DONE | embedder hosts own Arkt windows, `createBrowserWithHost:`, request kinds from the call site, self-test embedder; all acceptance rows pass on `Chromium.app`; see "W3-4" below |
| W3-5 | Tab facade | DONE (W3-5a #256, W3-5b) | W3-5a: pending-handle queue, close modes and reasons, CloseCancelled, stable containers, state events, held-window state. W3-5b: history and duplicate, extension actions for embedder windows, the test API; page context menu still blocked. See "W3-5a" and "W3-5b" below; review follow-ups in "#258" |
| W3-6 | `ChromiumEngineKit` over the facade | DONE | `ChromiumEngine: EngineClient, EngineExtensions` and the typed `ArktShellEmbedder` in `ChromiumEngineKit`; contract rules 1-16 pass against a scripted facade with every driver (24 checks x 2 event orders, none not applicable); ShellKit 509 + 28; see "W3-6" below |
| W3-7 | The shell as engine host, composition root (Swift lane) | DONE | A, B: `ShellEngineHost`, engine window on the first tab, `createTab(url:in:)`, commands, close button, per-window routing, close reasons, held closes, Extensions control, #241. C, D: `AppComposition` for both engines, `ShellWindowSet` with host-matched provider windows, quit seams, the W3-8 menu in both builds, reserved keys in `ShellWindow`; see "W3-7 C and D" and "W3-7 A and B" below |
| W3-8 | Main menu inventory and owner decision | DONE (steps 1-3; step 4 after W3-9) | Arkt owns the menu; conditions: a hidden `IDC_BOOKMARKS_MENU` placeholder (without it the first window crashes, measured), no `IDC_FILE_MENU` / `IDC_TAB_MENU` tags, Quit `IDC_EXIT` + `terminate:`; reserved keys in `ShellWindow`; no engine change; see "W3-8" below |
| W3-9 | Integration: ShellUI on ChromiumEngine, contract runner, smoke | DONE except logout (maintainer check); SIGTERM session end fixed by #298 | contract 16/16 in the app; smoke, startup and quit checks pass; 120 Hz gate holds (0 % over 8.6 ms); #9 holds; seven fixes, gaps #298-#301; see "W3-9" below |
| W3-10 | Infobars, or a recorded gap | DONE | native rows on the tab container for every confirm infobar (every confirm type on Mac, triggered from `chrome://infobar-internals`), `--no-sandbox` acceptance passes; tab sharing and sign-in QR (own Views) recorded in #122; no patch; see "W3-10" below |
| W3-11 | Self-contained bundle with the release framework | DONE except the real-keychain launch (maintainer check) | Engine app on `out/Arkt`'s framework, signed inside-out with one Apple Development identity and Chromium's options and entitlements, hardened runtime; `codesign --verify --deep --strict` valid; contract 16/16, smoke, #9 and quit pass from the internal disk; GPU hardware-accelerated, 0 seatbelt denials, no GPU or utility restarts in 2 min; 549 MB; the bundle still carries the test-only code W3-9 links (left open); see "W3-11" below |
| W3-12 | Results, patch budget, issue updates, housekeeping | DONE | all tasks PASS (two maintainer checks open); patch budget 7 = 7; no process of this track left; see "W3-12" below |

## Patch budget

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001-0006 | week 2 (hook, draw, keychain, factory hook, tab features, dialogs) | exist | 13 | 0 |
| 0007 | extension dialogs as native sheets (#244, pull request #252) | exists | 4 | 0 |
| 0008 | link activation throttle for Peek (#313, pull request #349) | exists | 1 | 0 |
| 0009 | modified link clicks asked in `OpenURLFromTab` (#345) | exists | 2 | 0 |
| 0012 | `FindBrowserWindowWithWebContents` finds a non-BrowserView window; no iOS address promo on it (#768) | exists | 2 | 0 |
| - | Handshake (Decision 1) | ObjC runtime lookup, no patch (W3-0: lookup works) | 0 | 0 |
| - | Framework name (Decision 7) | no patch unless open decision 1 changes | 0 (1-2) | 0 |
| - | User data directory (Decision 8), `--no-startup-window` (Decision 2) | Info.plist key and argv, no patch | 0 | 0 |
| - | Quit seams (Decision 13) | existing observers, callback list and `KeepAliveOrigin`, no patch | 0 | 0 |
| - | Facade, host mode, infobars (W3-10: `ContentInfoBarManager` observer, no patch), menu routing, reserved keys | overlay only | 0 | 0 |
| - | Web identity (#9): stock reduced UA, `Chromium` + GREASE brands | upstream default, no patch, no overlay code | 0 | 0 |

Current (W3-0): 7 patch files, 17 upstream files, 0 hot-file hunks. Projection after week 3: the same, or 8 patch files
if the framework is renamed by patch.
After #313: 8 patch files, 18 upstream files, 0 hot-file hunks.
After #345: 9 patch files, 20 upstream files, 0 hot-file hunks.
After #768: 12 patch files; 0012 adds 2 upstream files (`browser_view.cc`, `address_bubbles_controller.cc`), 0 hot-file hunks.

## W3-12: Results, patch budget, issue updates, housekeeping

Recorded on 2026-10-26 at `origin/main` d797225.

### PASS / FAIL per task

PASS means the task's acceptance criteria hold; a maintainer-only check or a recorded gap that the plan allows is
listed in the last column and does not turn a PASS into a FAIL. No task is FAIL.

| Task | Verdict | Pull requests | Open on this task |
|---|---|---|---|
| W3-0a | PASS | #229 | none |
| W3-0 | PASS | #253 | none |
| W3-1 | PASS | #264 | none |
| W3-2 | PASS | #246, #319 (six page command constants, refs #272) | none |
| W3-3 (gate) | PASS | #254 | recorded deviations (readiness queue, quit-start seam, CDP keep-alive) |
| W3-4 | PASS | #255 | none |
| W3-5 | PASS | #256, #257, #262 (review follow-ups, #258) | page context menu needs context menus on Arkt windows (#122); permission prompts, leave-site sheet, pinned hint, tab events (#265) |
| W3-6 | PASS | #267 | `ChromiumEngineKit` is linked in every configuration (#268) |
| W3-7 | PASS | #274 (A, B), #294 (C, D) | none |
| W3-8 | PASS | #271 | none |
| W3-9 | PASS | #302; fixes #320 (SIGTERM flush, #298), #323 (#301), #326 (#299) | logout is a maintainer check; #300 (row live in another window loads twice); #328 (reopen kind for a URL from another app); #331 (sidebar width and hidden state per window) |
| W3-10 | PASS | #281 | tab sharing and sign-in QR (own Views) stay in #122 |
| W3-11 | PASS | #333; fix #332 (first-run startup URL, #327) | real-keychain launch (maintainer check); the bundle is the test configuration, release configuration is #334; mixed bundle ids (#128) |
| W3-12 | PASS | this pull request | none |

Plan and decision pull requests: #220 (plan), #263 (decisions), #44 (window seam inventory). Related: #247 (#21,
native window default), #261 (tab-modal attachment, #207).

### Known gaps

| Issue | Gap | Status |
|---|---|---|
| #328 | A URL from another app while Arkt runs with no window reports `kind=reopen`; telling it apart needs `creation_source` in `OpenStartupTabsInBrowserWithProfile` (a patch) or another signal | open, no status label |
| #334 | Release configuration without `EngineAPITestSupport`, `--arkt-engine-contract`, `--arkt-engine-test-api` and the `ARKT_*` overrides | open, `status:ready` |
| #331 | Sidebar width and hidden state are not persisted per window | open, `status:ready` |
| #268 | `ChromiumEngineKit` is linked in every configuration; it should link only in the Engine configuration | open, no labels |
| #265 | Permission prompt follow-ups, leave-site sheet, pinned hint and tab events | open, `status:ready` |
| #313, #314 | Peek and Little Arkt: out of scope for week 3 | open, `status:ready` |
| #128 | Product bundle id (`dev.arkt.Arkt`), data folder, engine user-data-dir, branding (see "#128" below) | in review |
| #300 | Selecting a row that is live in another window loads the page a second time | open, `status:ready` |
| #121, #122 | Extension context menus, pinning, keyboard commands, install sheet (#121); native replacements for the remaining Views surfaces, including the page context menu, tab sharing and sign-in QR (#122) | open, `status:blocked` |

Open items on #33 (its acceptance boxes are still unticked; the maintainer closes them on review):

- Maintainer check: launch `~/Applications/ArktTest/ArktShell.app` once without `--user-data-dir` and without
  `--use-mock-keychain` and report any keychain prompt (W3-11).
- Maintainer check: logout (W3-9).
- Release configuration without test-only code (#334) and product bundle id (#128).
- Follow-ups #265, #268, #300, #328, #331.

### Patch budget

Week-2 commands:

```zsh
wc -l < $REPO/engine/patches/chromium/.patches
git -C /Volumes/SSD_2/arkt-chromium/chromium/src rev-list --count 156.0.8078.48..arkt
```

| Source | Count |
|---|---|
| `.patches` lines | 7 |
| `arkt` commits above `156.0.8078.48` | 7 |

Equal. Seven patch files (0001-0007), 17 upstream files, 0 hunks in hot files, as in the W3-0 baseline: week 3 added
no patch beyond 0007 (#244). The read-only `rev-list` was the only command run on `SSD_2`.

### Process check

`ps -axo pid,command | grep -E "out/Spike|embed-week3|/Applications/Arkt" | grep -v grep` prints only the
maintainer's `/Applications/Arkt.app` (main process 42259 with its crashpad handlers, GPU, network and storage
helpers, and renderers 10296, 10297, 10415, 10502). Those are not this track's processes and were left running. The
check cannot print nothing while that app is open.

No process from `out/Spike`, `embed-week3`, `$PROF` or `~/Library/Application Support/ArktTest` was running, so
nothing was killed. Two processes of other lanes were left alone: `xctest` 69621 (ShellKit GUI tests) and
`ArktShell` 69874 (from the `310-onboarding` worktree). Test profiles under `$PROF` and `ArktTest` stay in place.

### `--arkt-native-window`

#21 is closed (pull request #247: native window is the default, the switch is a no-op). The Engine configuration
already passes no `--arkt-native-window` (W3-3, W3-0 step 4), and no source file outside the plans and patch 0004's
description mentions it, so no configuration change was needed.

### Issue comments

Posted on #33, #9, #21, #121, #122, #128 and #207 with the outcome for each.

### Worktrees

| Worktree | Branch | State | Action |
|---|---|---|---|
| `arkt-wt/103-tab-switcher` | `feat/103-tab-switcher` | merged into `main`; clean when checked, then modified files appeared (in use) | kept |
| `arkt-wt/engine` | detached, now `engine/33-w3-12-results` | clean | kept (shared engine worktree) |
| `arkt-wt/website` | website branch | merged into `main`, 3 uncommitted files | kept |
| `arkt-wt/107-favorites` | `feat/107-favorites` | 2 commits ahead, 6 uncommitted files | kept |
| `arkt-wt/112-command-bar` | `feat/112-command-bar` | pull request #322 open, 8 commits ahead | kept |
| `arkt-wt/310-onboarding` | `feat/310-onboarding` | 5 commits ahead, 17 uncommitted files | kept |
| `arkt-wt/readme-brand` | `readme` | pull request #284 merged, 1 commit ahead (not in `main`), 1 uncommitted file | kept |

## W3-11: Self-contained bundle with the release framework

Date 2026-10-26. Branch `engine/33-w3-11-signed-bundle` off `main` at `22a2b12`. No code change: `engine/README.md`
(new section "Embedding in the app") and this file. `.patches` unchanged (7), `git -C $CR rev-list --count
156.0.8078.48..arkt` 7. `$REL` = `$CR/out/Arkt`.

### Build

- **`out/Arkt`, incremental** (it had not been rebuilt since the overlay changes up to #326; `$CR/arkt` already
  pointed at the engine worktree, `ln -sfn` as in "Link the overlay"): `autoninja -C out/Arkt -j 4 chrome` at normal
  priority (`-j 4` because swap was already at 15.5 GB), **1 min 27 s**, `The build has finished successfully.`,
  0 `FAILED:`; 22 `//arkt` objects recompiled and `Arkt Framework` relinked (448 MB); a second run had nothing to do;
  `gn check out/Arkt '//arkt/*'`: `Header dependency check OK`. Internal disk 34 GiB free before, 30 GiB after the
  task; swap 15.5 GB used before, 18.6 GB at the end (Swift builds of other tracks ran at the same time).
- **Engine configuration on the release framework:** `xcodebuild -scheme ArktShell -configuration Engine
  ARKT_ENGINE_APP=$REL/Arkt.app CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-w3-11 -derivedDataPath
  $CHROMIUM_ROOT/arkt-shell-dd/w3-11 build` (no change to `Local.xcconfig`, which keeps `out/Spike` for
  development), 1 min 25 s, `BUILD SUCCEEDED`, `Engine framework copied: Arkt Framework.framework 156.0.8078.48`.
  Info.plist: `ArktEngineFrameworkName = Arkt Framework`, `ArktEngineFrameworkVersion = 156.0.8078.48`,
  `CrProductDirName = Arkt Dev Engine`, `NSPrincipalClass = BrowserCrApplication`. The app binary is arm64 only.
  No dylib next to the bundle.
- **Inventory before signing:** the only Mach-O files outside the framework are `Contents/MacOS/ArktShell`;
  `otool -L` lists only `/System` and `/usr/lib`; `Resources/GRDB_GRDB.bundle` holds an Info.plist and
  `PrivacyInfo.xcprivacy` (no code). The framework still had the linker's ad-hoc signature after the Xcode build
  (`flags=0x20002(adhoc,linker-signed)`): Xcode did not re-sign it.

### Signing

A copy in `$CHROMIUM_ROOT/stage-w3-11`, signed inside-out with one Apple Development identity and
`--timestamp=none`, options and entitlements from `chrome/installer/mac/signing/parts.py` and `chrome/app/*.plist`
(the table and commands are in `engine/README.md`, "Embedding in the app"). 11 of 11 entries of `Helpers` covered.

```
$ codesign --verify --deep --strict --verbose=2 ArktShell.app
--validated:.../ArktShell.app/Contents/Frameworks/Arkt Framework.framework/Versions/Current/.
ArktShell.app: valid on disk
ArktShell.app: satisfies its Designated Requirement
```

The same on the installed copy (`~/Applications/ArktTest/ArktShell.app`). `spctl --assess`: `rejected` (not
notarized, #125), as expected.

| Part | `codesign -dv` Identifier | CodeDirectory flags | Entitlements |
|---|---|---|---|
| `ArktShell.app` | `dev.arkt.ArktShell` | `0x12a00(kill,restrict,library-validation,runtime)` | `app-entitlements.plist` (7 device and personal-information keys) |
| `Arkt Framework.framework` | `com.arkt.Arkt.framework` | `0x0(none)` | none |
| `Libraries/*.dylib` (3) | `libaperitif`, `libvk_swiftshader`, `libvulkan` | `0x0(none)` | none |
| `chrome_crashpad_handler`, `app_mode_loader`, `web_app_shortcut_copier` | own names | `0x12a00(kill,restrict,library-validation,runtime)` | none |
| `Arkt Helper.app`, `(Aperitif)` | `com.arkt.Arkt.helper` | `0x12a00(kill,restrict,library-validation,runtime)` | none |
| `(GPU)`, `(Aperitif GPU)` | `com.arkt.Arkt.helper` | `0x10a00(kill,restrict,runtime)` | `com.apple.security.cs.allow-jit` |
| `(Renderer)`, `(Aperitif Renderer)` | `com.arkt.Arkt.helper.renderer` | `0x10a00(kill,restrict,runtime)` | `com.apple.security.cs.allow-jit` |
| `(Alerts)`, `(Aperitif Alerts)` | `com.arkt.Arkt.framework.AlertNotificationService` | `0x12a00(kill,restrict,library-validation,runtime)` | none |

**Bundle size:** 549 MB (`du -sh`), of which the framework 538 MB and `Contents/MacOS` 12 MB.

**Ids (Risk 9):** app `dev.arkt.ArktShell`; framework `com.arkt.Arkt.framework`; helpers as in the table. The
rendezvous service follows the outer app: `launchctl print gui/<uid>` listed
`dev.arkt.ArktShell.MachPortRendezvousServer.<browser pid>` while the smoke run was up, and every helper ran from the
bundle's own `Helpers` with no rendezvous error. Mixed ids (`dev.arkt.*` app, `com.arkt.*` framework and helpers)
stay for #128.

### Runs

All from `~/Applications/ArktTest/ArktShell.app` (internal disk; launched by executable path, so no
removable-volume prompt), each with its own profile under `~/Library/Application Support/ArktTest/w3-11/<run>`,
scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, `--use-mock-keychain --no-first-run
--no-default-browser-check --enable-logging=stderr`, pages from a loopback server on `127.0.0.1:8691`, stopped by
PID or by the app's own Quit. No macOS permission or keychain prompt appeared in any run. Self-contained: in the
smoke run no process of the app had a file open under `/Volumes`; the loaded images outside the system were the
framework and its resources inside the bundle.

**Contract** (`contract`, `--arkt-engine-contract --arkt-engine-test-api`, tabs probe): 24 checks PASS,
`ARKT_CONTRACT result 16/16`, `ARKT_CONTRACT exit 0`, 9 s from launch; 0 `FATAL`/`Check failed`. The only
`ERROR` lines are the `Message ... rejected by interface blink.mojom.Widget(Host)` pairs at window closes that the
W3-9 contract runs on `out/Spike` also log.

**Smoke** (`smoke`, CDP port of its own, tabs and action probes):

| Check | Result | Evidence |
|---|---|---|
| Start, first window | PASS | `engineDidStart`, `main menu installed`, `session ready`, `embedderReady (0 queued request(s))`, `launch finished (0 window(s) from queued requests)` 3 s after launch |
| New Tab (File menu), command bar, page loads | PASS | `Alpha visible` (CDP) |
| Cmd-L navigates the current tab | PASS | `Gamma visible`, still one page target |
| `chrome.tabs.create({active:false})` | PASS | Beta `hidden`, Gamma stays `visible` |
| `chrome.tabs.update({active:true})` | PASS | Beta `visible`, Gamma `hidden` |
| Cmd-W | PASS | `facade tab closed ... reason client`, Beta's target gone |
| `chrome.windows.create` with bounds | PASS | `window request kind extension`, shell window at 400,150 900x650 |
| Split View (View > Add Split View, URL typed into the new pane) | PASS | Delta and Epsilon both `visible` in one window |
| Extension popup | PASS (programmatic) | `chrome.action.openPopup()` from the action probe: `TriggerPopup ... by_user=0`, `popup loaded ... popup.html`, `popup auto-resize 244x129`; the sidebar Extensions button was not clicked |
| Held close | PASS | `beforeunload` set with a user gesture, Cmd-W: the row dims, "Leave site?" dialog (its own window, AX dialog Cancel / Leave); Cancel: `facade close cancelled`, batch `CloseCancelled`; Leave on a one-tab window: its tabs closed with `reason windowClosing` |
| Quit (`quit`, no CDP port) | PASS | App menu Quit: `quit started`, `engineWillBeginTerminating`, `quit-start flush succeeded true`, `app terminating`, `engineWillTerminate`, `termination flush succeeded true`, `lifetime keep-alive released`, process exited in 2 s |
| Web Store install, Services, Edit menu, Dock reopen, page commands | not run | covered in W3-9 on the same code; nothing in them depends on signing |

**Web identity (#9)**, loopback page and echo page loaded twice: `navigator.userAgent` and `user-agent`
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0
Safari/537.36`; brands `Not:A-Brand 8, Chromium 156`; full version list `Not:A-Brand 8.0.0.0, Chromium
156.0.8078.48`; `sec-ch-ua` `"Not:A-Brand";v="8", "Chromium";v="156"`; `sec-ch-ua-full-version-list`
`"Not:A-Brand";v="8.0.0.0", "Chromium";v="156.0.8078.48"`; platform `macOS 27.0.0`, arch `arm`. No `Arkt`, no
`--user-agent` in any process. PASS.

### Hardened runtime (`hr`, `--enable-sandbox-logging`, startup URL, CDP port of its own)

- **GPU:** `chrome://gpu` over CDP (`info-view` shadow root), in both the smoke and the hr run: Canvas, Compositing,
  Rasterization, Video Decode, Video Encode, WebGL, WebGPU `Hardware accelerated`; OpenGL, Direct Rendering Display
  Compositor, Skia Graphite `Enabled`; Skia backend `GraphiteDawnMetal`; `GL_RENDERER ANGLE (Apple, ANGLE Metal
  Renderer: Apple M2 Pro ...)`. "Problems Detected" lists only Chromium's stock workarounds. In a page: WebGL2
  `UNMASKED_RENDERER_WEBGL` is the ANGLE Metal renderer, `navigator.gpu.requestAdapter()` returns `apple metal-3`.
  The GPU process runs in `Arkt Helper (Aperitif).app` (Chromium's choice on 156).
- **Seatbelt:** Chromium's profiles do not log denials unless `--enable-sandbox-logging` (`common.sb`: `deny default
  (with no-log)`); all 6 helpers got the switch. `/usr/bin/log show --start <launch> --predicate 'sender ==
  "Sandbox"'` over the run: 6 lines, all from other processes, 0 from the app or its helpers.
- **Restarts:** helpers at 15 s and at 2 min 27 s: the GPU process, the network service and the storage service kept
  their PIDs; the three renderers that left were replaced on navigations (startup page, `chrome://gpu`, a new page),
  with no `exited unexpectedly`, `crashed` or `was terminated` line. 0 `FATAL`/`Check failed`, 0 rendezvous errors;
  the only `ERROR` lines (2) are `services/on_device_model/ml/gpu_blocklist.cc ... Unable to get gpu adapter`, which
  the W3-9 smoke on `out/Spike` also logs. No new crash dump under `Arkt Dev Engine/Crashpad`, no new
  `ArktShell`/`Arkt Helper` report in `~/Library/Logs/DiagnosticReports`.

### Left open

- **Test-only code in the bundle** (recorded with W3-9): the Engine configuration links `EngineAPITestSupport`, honours
  `--arkt-engine-contract` and `--arkt-engine-test-api`, and reads the `ARKT_*` overrides (`ArktEnvironmentOverrides
  = YES`). The bundle signed here is that configuration, so it is a test bundle, not a shippable one. A release
  configuration without them (and with the product `CrProductDirName`) is still to do.
- **Mixed bundle ids** (Risk 9): app `dev.arkt.ArktShell`, framework and helpers `com.arkt.Arkt.*`; #128.
- The "Leave site?" dialog shows the generic app icon: the shell app has no icon yet.

### Needs the maintainer

Once: launch `~/Applications/ArktTest/ArktShell.app` without `--user-data-dir` and without `--use-mock-keychain`
(the real default folder, `Arkt Dev Engine` for this configuration, and the "Arkt Safe Storage" keychain item), and
report any keychain prompt.

### Verification

`codesign --verify --deep --strict --verbose=2` and `codesign -dv` output above; contract `16/16`; smoke, #9 and quit
lines above; `chrome://gpu` feature status above. No Swift or engine source changed, so no `swift test` run.

## W3-9: ShellUI on ChromiumEngine, contract runner, smoke

Date 2026-10-25. Branch `engine/33-w3-9-real-ui` off `main` at `a22acbb`. Overlay and Swift only: no patch, `.patches`
unchanged (7 files); every engine change is under `engine/arkt`. Builds: `nice -n 10 autoninja -C out/Spike -j 6 chrome`
(`The build has finished successfully.` for each change; `gn check out/Spike '//arkt/*'`: `Header dependency check OK`),
changed component dylibs re-cloned next to the bundle in `$EMB`, the app built with `xcodebuild -scheme ArktShell
-configuration Engine CONFIGURATION_BUILD_DIR=$EMB`. Every GUI run: one at a time, own windows only, a scratch shell data
folder (`ARKT_DATA_DIR`, `ARKT_ARC_DIR`, `ARKT_DEFAULTS_SUITE` under `$PROF/w3-9-*`), `--user-data-dir` under `$PROF`,
`--use-mock-keychain`, pages from a loopback server on `127.0.0.1:8691`, stopped by PID or by the app's own Quit.

**The Chromium disk went away at 18:39:11** (unmounted by the system, not by any command of this task), during the third
cold `open -a <app> <url>` launch. `$CR`, `$EMB`, the profiles, logs and window-only screenshots of this task are on it;
the log lines below were copied before. **It was mounted again at about 19:10** and everything on it was intact: `$CR`
clean on branch `arkt` at `8910b992e4`, `git -C $CR rev-list --count 156.0.8078.48..HEAD` 7 (= `.patches` 7), `$EMB`
with all 518 component dylibs equal to `out/Spike`'s (`cmp`), an incremental `autoninja` with nothing to rebuild, the
`w3-9-*` profiles present, 0 crash dumps in the startup run's user data folder (the run in flight when the disk went) and
under `Arkt Dev Engine/Crashpad`. The steps the loss had cut short were then run ("Second session" below).

### What landed

- **Contract runner** (`App/Engine/EngineContractRunner.swift`, `ContractPageServer.swift`; Engine configuration only).
  `--arkt-engine-contract` (with `--arkt-engine-test-api` and `--load-extension=<tabs-probe>`) runs every check of rules
  1-16 against a fresh `ChromiumEngine` from `ChromiumEmbedding.makeEngine()`, each with its own windows (the engine's
  window is created first). The shell session is not started. Harness: pages from a loopback server of the runner's own
  (`/page/<title>?n=<serial>`, a PNG favicon; `127.0.0.1` and `localhost` as the two hosts of rule 6); `settle` waits for
  a `loadingChanged(false)` on a page other than the initial `about:blank`; `retitle`, `holdClose` (a `beforeunload`
  handler set with a user gesture, sticky activation checked) and `engineCreateTab` (`window.open` with a gesture) through
  the test API; `engineCloseTab` / `engineActivate` through `chrome.tabs.remove` / `chrome.tabs.update`, run from the
  tabs probe's new `control.html` page in a control engine's window (the tab found by its unique URL); `answerDialog`
  retried until the dialog is up. One `ARKT_CONTRACT` line per check and per rule, `result n/16`, exit 0 only when every
  rule passed (a rule reported not applicable fails). `--arkt-engine-contract=<check>,...` runs a subset.
  **Deviation:** the plan's `-ArktEngineContract YES` cannot be used: Chromium reads every non-switch argument as a
  startup URL (`YES` became a queued startup window).
- `ContractCheck` (the list of the 24 checks with their rule numbers) moved from the kit's tests to
  `EngineAPITestSupport`, which becomes a library product the app links (the runner). The Debug app links it unused,
  as it links `ChromiumEngineKit` (#268).
- Fixes found by the runner and the smoke:
  1. **Crash with two windows closing together** (run 1, `FATAL ... global_browser_collection.cc:70 Check failed: it !=
     browsers_activation_order_.end()` from `BrowserActiveStateManager::DidBecomeActive` <- `-[NSWindow becomeKeyWindow]`
     <- `ArktBrowserWindow::UnbindHost` <- `~Browser`). A Browser whose close completed is out of the collection but keeps
     its window until its posted deletion; when another closing window is ordered out first, this one became key and was
     activated. The window's key observer now ignores a Browser with `IsDeleteScheduled()`. The same shape is reachable
     from the shell (Quit or closing two windows), not only from the runner.
  2. **Initial `about:blank` reported as a load** (run 1, rule 2: `tabCreated, loadingChanged(true), activeTabChanged,
     urlChanged(page), urlChanged(about:blank), urlChanged(page), titleChanged, loadingChanged(false)`). A tab created
     without a URL loads Chromium's `about:blank`; its load start arrives before the first navigation's URL and its commit
     after it. `ChromiumEngine` no longer reports that load or that URL: the first page's URL is reported with its load
     start, and `about:blank` URLs are dropped until the first page loaded. Scripted tests for both cases (checked to fail
     without the change).
  3. **A held window close did not show its tabs closing** (run 2, rule 16 `cancelledWindowCloseKeepsTheWindow`: timed
     out waiting for `isClosing`). A window close runs every tab's `beforeunload` through `UnloadController` without
     marking the tabs; `isClosing` is now also true for every tab of a window whose close is in progress. So that a tab the
     shell drops while such a close is held still closes, `ChromiumEngine.closeTab(_:mode: .skipUnloadHandlers)` no longer
     returns early for a closing tab (scripted test, checked to fail first). Effect on the shell: during a held window
     close, Cmd-W and a row's X do nothing for that window's tabs, and auto-archive skips all of them.
  4. **Cold launch with a URL showed two windows** (startup run 1: `launch finished (0 window(s) from queued requests)`,
     then `window request kind startupURL`, two windows). The facade replayed the queued requests from a posted task, which
     ran after the shell's launch-window decision. `embedderReady` now replays before it returns (inside a nested loop it is
     still posted); the shell's `host(for:)` is re-entered inside the `Task` that called `embedderReady`. This changes the
     W3-3 design ("replayed from a posted task").
  5. **Cmd-Q did not quit.** Chromium 156 registers `kConfirmToQuitEnabled` (Warn Before Quitting) as `true`
     (`confirm_quit.cc`), so a short Cmd-Q only shows the hold-to-quit panel, and Arkt's menu has no item to turn it off
     (W3-8). The hook sets its default to `false` (`SetDefaultPrefValue`: a policy or a stored value still wins). Parity
     with Arc is a maintainer decision.
  6. **Window title stayed on a closed tab's title** (Window menu showed "Gamma" while "Alpha" was shown). The title now
     also follows active-tab changes (`UpdateTitleBar()` from the window's `TabStripModelObserver`; it only sets the
     `NSWindow` title).
  7. **A URL opened by another app at a cold launch got a Today row but no page** (second session, `open -a <app>
     <url>`: row added, card empty, twice). Chromium builds that window before the embedder is ready; when the facade
     adopts it at replay, its tab is already active and no selection change announces it. The facade now records
     `ActiveTabChanged` for the active tab of a window adopted with tabs (`WindowOpened,TabCreated,LoadingChanged,
     ActiveTabChanged`), and the shell shows the page.
  8. Review follow-ups (#302): `--arkt-engine-contract=<checks>` with an unknown name or an empty list exits 2 with
     `ARKT_CONTRACT setup failed: --arkt-engine-contract= names no check: unknown <name>` (it ran nothing and passed
     before); the runner logs windows left open after a check; the scripted facade closes a tab with
     `.skipUnloadHandlers` while a window close shows its dialog, as the real facade does (script test); `BUILD.gn`
     gn-formatted.

### Contract (run 5, `$PROF/w3-9-contract5`, final build)

```
ARKT_CONTRACT setup pages=127.0.0.1:<port> tabs-probe=<id>
rule 1 createdTabIsListedAndAnnounced PASS (48 ms)        rule 1 tabIDsKeepCreationOrder PASS (36 ms)
rule 2 navigateReportsURLLoadingAndTitle PASS (1619 ms)   rule 2 titleChangedAfterLoadIsReported PASS (64 ms)
rule 3 contentViewIsStable PASS (40 ms)
rule 4 closeIsTerminal PASS (69 ms)                       rule 4 closeInsideObserverKeepsOrder PASS (1616 ms)
rule 5 cancelledObservationStopsDelivery PASS (48 ms)     rule 5 droppedObservationStopsDelivery PASS (40 ms)
rule 6 hostChangeClearsFavicon PASS (2019 ms)
rule 7 historyMovesBackAndForward PASS (203 ms)           rule 8 historyAvailabilityIsReported PASS (125 ms)
rule 9 historyEntriesAndOffsetNavigation PASS (1452 ms)   rule 10 duplicateTabCopiesURLTitleAndHistory PASS (138 ms)
rule 11 windowIsListedAndAnnounced PASS (85 ms)           rule 11 closeWindowClosesItsTabsThenReportsWindowClosed PASS (118 ms)
rule 11 hostCloseRequestClosesTheWindow PASS (62 ms)      rule 12 activationIsOneTabPerWindow PASS (116 ms)
rule 13 engineCreatedTabIsAnnounced PASS (160 ms)         rule 14 engineCloseIsTerminal PASS (163 ms)
rule 15 windowlessCreateTabLandsInMostRecentlyActiveWindow PASS (100 ms)
rule 16 heldCloseKeepsTheTabUntilAnswered PASS (381 ms)   rule 16 skipUnloadHandlersNeverHolds PASS (99 ms)
rule 16 cancelledWindowCloseKeepsTheWindow PASS (2599 ms)
ARKT_CONTRACT result 16/16
ARKT_CONTRACT exit 0
```

16/16, none not applicable, 0 `FATAL`/`Check failed` in the run, no crash dump. Runs 1-4 are the failures above (run 1:
14/16 with the crash; run 2: 15/16; run 4: the window-close check alone after fix 3).

### Smoke on the shell (run A, `$PROF/w3-9-smoke-a`, tabs probe and action probe, CDP port of its own)

| Check | Result | Evidence |
|---|---|---|
| Start with scratch data, first window | PASS | `engineDidStart`, `main menu installed`, `session ready`, `launch finished (0 window(s) from queued requests)`; first run shows the welcome card; New Space (AX) |
| Cmd-T, command bar, page loads | PASS | `Alpha visible` (CDP); row "Alpha" in Today |
| Cmd-L navigates the current tab | PASS | the tab's URL `p/Gamma`, favicon drawn on the row |
| `chrome.tabs.create({active:false})` | PASS | Today row "Beta" in the same window, the shown page stays `visible` |
| `chrome.tabs.update({active:true})` | PASS | Beta `visible`, Alpha `hidden`, Beta's row selected |
| Cmd-W with page focus (reserved key) | PASS | page focused (`document.hasFocus()` true, a page `keydown` listener saw the typed key), Cmd-W: `facade tab closed ... reason client`, the row archived (stored archive: `Gamma|manual`) |
| At most one engine pick within the 1 s grace after a close | PASS | after the close: one batch `TabClosed,ActiveTabChanged,...` (Chromium's pick); with a different successor (archive of the held tab below), the shell's activation follows in the next batch and wins; no further engine pick |
| `chrome.windows.create` with bounds | PASS | `window request kind extension`, adopted shell window at the requested 400,150 900x650, in the opener's Space, row "Delta" |
| Extension popup from the sidebar Extensions button | PASS | AX menu lists both probes; `TriggerPopup ... by_user=1`, `anchor restored`, `popup loaded ... popup.html` |
| Split View with two engine pages | PASS | View > Add Split View: both panes `visible` (CDP) |
| Held close by the page | PASS | `beforeunload` with a gesture, Cmd-W: the row dims, "Leave site?" dialog over the card; Cancel: `facade close cancelled`, batch `CloseCancelled`, row back; Cmd-W, Leave: `tab closed ... reason client`, archived (`Alpha-third|manual`) |
| Web Store install from the real UI | PASS | uBlock Origin Lite detail page (consent "Reject all", no sign-in), Add to Chrome: `install sheet shown type=0 permissions=1`, AX "Add extension": `install sheet accepted`, the extension in the sidebar Extensions menu; the confirmation copy names Chromium and a menu item Arkt does not have (#121 comment) |
| Services submenu under Arkt's App menu | PASS | 23 items with text selected in the page |
| Edit menu with page focus | PASS | Select All selects the page field's text; Cut, Copy, Paste enabled |
| Dock reopen with no window | PASS (gap #299) | both windows closed (`browsers normal=0`), `open -a` on the running app: `window request kind reopen`, an adopted shell window on Space 1; Chromium's `chrome://newtab/` became a Today row (#299) |
| Two windows on one Space | gap #300 | selecting a row live in the other window loads it again (fixed: the #300 section below) |
| Empty Space, Space title, stale tooltip | gap #301 | |

**Page commands (W3-8 step 4)**, AX menu clicks, window frontmost, page focused:

| Command | Reaches the `Browser` | Evidence |
|---|---|---|
| Reload, Force Reload | yes | a page variable set before is gone after each |
| Stop | enabled state only | disabled while idle; not clicked during a load |
| Back, Forward | yes | after a navigation with a user gesture: `p/Alpha-third` -> `p/Alpha-next` -> `p/Alpha-third`; after a script navigation without one, Back does nothing (Chromium's history intervention skips that entry; `history.back()` from the page works) |
| Zoom In, Zoom Out, Actual Size | yes | `devicePixelRatio` 2 -> 2.2 -> 1.8 -> 2 (Actual Size validated a moment after the zoom change) |
| Find | yes | `stub FindBar::Show` (find bar is #134) |
| Find Next, Find Previous | enabled, no visible effect | no find bar (#134) |
| Save Page As | yes | the save panel as a sheet on the shell window, name "Alpha-third"; cancelled |
| Print | yes | Chromium's print preview over the card; cancelled with Escape |
| View Source | yes | new active tab `view-source:...`, the shell selects its Today row |
| Developer Tools, JavaScript Console, Inspect Elements | yes | DevTools window (`views=1`), closed again |
| Show All History, Downloads | yes | Today rows "History" (`chrome://history/`) and "Download History" (`chrome://downloads/`) |
| Quit | yes | menu: `quit started`, `engineWillBeginTerminating`, `app terminating`, `engineWillTerminate`, `termination flush succeeded true`, `lifetime keep-alive released`; with the CDP port the process then stays (W3-3), stopped by PID |

### Startup

| Check | Result | Evidence |
|---|---|---|
| First window shows the restored Space | PASS | quit run B1: the stored Space with its split shown |
| Cold launch, URL as argument | PASS after fix 4 | `window request queued kind=startupURL`, `embedderReady (1 queued request(s))`, `window request kind startupURL`, `launch finished (1 window(s) from queued requests)`; one window, the URL's Today row selected |
| Cold launch, `open -a <app> <url>` | PASS after fix 7 (gap #299) | one window, the URL's page shown and its row selected; reported as `kind=reopen` |
| Extension opening a window at startup | PASS (see the note) | `startup-probe` (new, `engine/test-extensions/startup-probe`): `embedderReady (0 queued request(s))`, `launch finished (0 window(s) ...)`, 2.7 s later `window request kind extension`, `host asked kind=extension`, an adopted shell window with the probe's page as a Today row next to the launch window. `runtime.onStartup` itself does not reach an extension loaded with `--load-extension` (it is installed again at each launch; a first try logged no request), so the probe opens its window on its first service worker start of the session; on this machine that came after readiness, so the before-readiness queue was not exercised by an extension |

### Quit (no CDP port, `ARKT_AUTOSAVE_DELAY_MS=600000`, a new Today row created right before quitting)

| Path | Result | Evidence |
|---|---|---|
| Cmd-Q (after fix 5) | PASS | `quit started`, `engineWillBeginTerminating`, `app terminating`, `engineWillTerminate`, `termination flush succeeded true`, process exited; the stored snapshot (unchanged since launch: `saved_at` the same before the quit) then had the new row, every earlier row unchanged, the shown split's `lastActiveAt` stamped |
| Quit Apple event (Dock Quit) | PASS | the same seam lines; the pending row stored |
| `kill -TERM` (session end) | FAIL, then PASS after #298 | before: `quit started`, `engineWillBeginTerminating`, then the process is gone: `chrome::SessionEnding()` ends with `TerminateCurrentProcessImmediately`, no `engineWillTerminate`; the pending row lost. After #298 (the shell writes at quit start while the main thread waits): `quit-start flush succeeded true` 8 ms after `engineWillBeginTerminating`, the process exits, the stored snapshot has the new row and `saved_at` is the quit time |
| Logout | maintainer check | |

### Web identity (#9)

Loopback echo page in the shell: `User-Agent` and `navigator.userAgent` `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36`; `Sec-CH-UA` `"Not:A-Brand";v="8",
"Chromium";v="156"`; full version list `Not:A-Brand 8.0.0.0, Chromium 156.0.8078.48`; platform `macOS` `27.0.0`, arch
`arm`. No `Arkt` in either brand list; no `--user-agent` in any of the app's 18 processes. PASS.

### 120 Hz (shell card with live engine pages)

Built-in Liquid Retina XDR display, `screenMaxFPS=120`; the shell's display-link pacer (`dev.arkt.shell` / `perf`,
`pacing` lines), pages with a running CSS animation:

| Interaction | Sessions | Frames each | Intervals over 8.6 ms | Max |
|---|---|---|---|---|
| Space switch (Ctrl-1 / Ctrl-2): the window showing a Split View of two live pages, and the window showing one live page | 40 | 59-60 | 0 | 8.33 ms |
| Split View divider drag between two live pages | 3 | 129-133 | 0 | 8.33 ms |

Gate (at most 1 % over 8.6 ms) holds: 0 %.

### Second session (disk back, final build)

| Check | Result | Evidence |
|---|---|---|
| Cmd-N with page focus | PASS | page field focused (`document.hasFocus()` true), Cmd-N: a new shell window, the page's `keydown` listener saw nothing |
| Shift-Cmd-W with page focus | PASS | page "Kappa" focused, Shift-Cmd-W: batch `TabClosed,WindowClosed`, `native window destroyed`, the other window stays |
| Stop during a load | PASS | a page whose response stays open 15 s: `document.readyState` `loading`, Stop enabled; View > Stop: `complete` 0.8 s later, Stop disabled |
| Page command with the Archive window key (W3-8 M7) | PASS | Archive window key: Reload and Zoom disabled, a page marker survives a click on Reload (nothing reached a `Browser`) |
| Page command with no window (M7) | recorded | Reload and Zoom disabled; Show All History and the Developer items stay enabled and reach AppController, which creates a `Browser`: `window request kind reopen`, an adopted shell window with History |
| Cold `open -a <app> <url>` | PASS after fix 7 | above |
| Contract on the final build | 16/16 | run 7: 24 checks PASS, `result 16/16`, exit 0, 0 `FATAL`, 0 dumps; `--arkt-engine-contract=closeIsTerminl`: exit 2 with the message above |
| Relaunch shows the quit writes | PASS | the rows written at quit (B1 "Zeta", B2 "Eta") are in the sidebar of every later launch on that data folder |

Unexplained, recorded: in the startup-probe run the probe's page went on to `/p/StartupProbe-next` with a `LINK`
transition (Chromium's history) while no input was sent to the app; not reproduced.

Logout stays a maintainer check. SIGTERM is fixed by #298.

### Verification

- Contract: above. Crash dumps: 0 in each run's user data folder and under `Arkt Dev Engine/Crashpad`.
- Second session, on the Chromium disk (`arkt-shell-dd/w3-9-spm`): ShellKit `--filter ShellKitGUITests` 491, 5 skipped,
  0 failures; `--skip ShellKitGUITests` 581, all pass (one more script test).
- First session, on the internal disk after the Chromium disk was lost (scratch and derived data in a temporary folder): ShellKit `swift test --skip ShellKitGUITests` 580 tests, all pass (new: the two `about:blank`
  scripts and the skip-unload close script; `everyContractCheckIsListed` also checks the rule numbers cover 1-16).
  ShellKit `--filter ShellKitGUITests` 491, 5 skipped, one failing test: `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch`
  (2 frames over 8.6 ms), the load-dependent flake recorded in "W3-7 A and B"; alone it then passed twice (once skipped by
  its load gate). ArktCore `swift test` 366, all pass.
- Debug app (`xcodebuild -configuration Debug CODE_SIGNING_ALLOWED=NO`): `BUILD SUCCEEDED`, `NSPrincipalClass`
  `NSApplication`, `strings | grep -c "ARKT engine"` 0 in each binary, no `Contents/Frameworks`. The Debug app now also
  links `EngineAPITestSupport` (unused there), next to `ChromiumEngineKit` (#268).
- Patch budget: `wc -l < engine/patches/chromium/.patches` 7, `git -C $CR rev-list --count 156.0.8078.48..HEAD` 7; no file
  outside `engine/arkt` changed in the engine.

## #299: Dock reopen without a New Tab row, startupURL for a URL from another app

Date 2026-10-25. Branch `fix/299-reopen-newtab` off `main` at `3a4b050`. Overlay and Swift only: no patch, `.patches`
unchanged (7). `nice -n 10 autoninja -C out/Spike -j 6 chrome`: `The build has finished successfully.`;
`gn check out/Spike '//arkt/*'`: `Header dependency check OK`; only `libchrome_dll.dylib` changed and was re-cloned into
`$EMB`; the Engine app built with `xcodebuild -scheme ArktShell -configuration Engine CONFIGURATION_BUILD_DIR=$EMB`.
`out/Arkt` not rebuilt.

### Root causes

1. **New Tab row.** A Dock reopen with no window runs `AppController` `CreateBrowser` -> `chrome::NewEmptyWindow`, which
   adds Chromium's New Tab page (`chrome://newtab/`) to the new `Browser`. `ChromiumEngine` listed it like any engine tab,
   so the shell made a Today row. Closing it is not enough: a `Browser` closes with its last tab, and the shell window
   with it. The first Dock reopen of a session can also take `AppController`'s session restore attempt, then
   `StartupBrowserCreator` (`kStartupCreator`, so `kind=startupURL`), with the same New Tab page.
2. **Kind of a URL from another app.** The W3-4 table names `kStartupCreator` for it; Chromium 156 does not use it.
   `-application:openURLs:` (or, at a cold launch, the URLs it queued, from `-applicationDidFinishLaunching:`) ends in
   `OpenStartupTabsInBrowserWithProfile`, which builds the window with default params
   (`CreateBrowserWindow(BrowserWindowCreateParams(profile, true))`, `app_controller_mac.mm`), the same params as a
   Dock reopen's, so the factory reported `reopen`. The Apple event is not current while the window is built (checked
   on a warm `open -a <app> <url>`: no event), so it cannot be told from a reopen at construction without a patch.

### What changed

- `ChromiumEngine` (`ChromiumEngine+NewTabPage.swift`): in a `.reopen` or `.startupURL` window, a first tab that is the
  New Tab page, or has no page yet, is kept out of the tables: not listed, not announced, its events dropped. The shell
  adopts the window with no tabs and shows an empty window. The page keeps the `Browser` open until another tab joins
  the window (the first tab the user opens, or an extension's), then closes with `.skipUnloadHandlers` and no event. If
  it navigates to another page (Show All History with no window opens there), it is listed then, with that URL, as the
  window's active tab. Other kinds (`chrome.windows.create`) are unchanged.
- `arkt_embedder.mm`: a window with default params that was held before readiness is looked at again at replay
  (`ReclassifyHeld`): no page can open a window before readiness and a Dock reopen gets the New Tab page, so a held
  window that already shows a page reports `startupURL` with that URL. After readiness the request is answered inside
  construction, before the window has a tab, so a URL from another app sent to the running app still reports `reopen`;
  with the change above it still gets exactly one Today row.

### Checks (Engine app, profile `$PROF/299-try`, scratch `ARKT_*` folders and defaults suite, loopback pages)

| Check | Result | Evidence |
|---|---|---|
| Dock reopen with no window | PASS | Close Window (menu, by PID), `browsers normal=0`; `open -a <app>`: `host asked kind=reopen (default params ...)`, `facade batch 4 event(s) WindowOpened,TabCreated,LoadingChanged,ActiveTabChanged`, one shown shell window with an empty card, no Today row (stored snapshot unchanged) |
| First Dock reopen of the session (startup path) | PASS | `host asked kind=startupURL (startup browser creator)`, empty window, no Today row |
| URL from another app before readiness | PASS | the GURL event sent to the process before readiness: `window request queued kind=reopen (default params ...) (window held hidden)`, `embedderReady (1 queued request(s))`, `host asked kind=startupURL (default params, held before ready with a page (URL from another application))`, `launch finished (1 window(s) from queued requests)`; one window, one Today row with the page's URL |
| URL from another app, running app, no window | PASS (kind stays `reopen`) | `open -a <app> <url>`: one window, one Today row "Alpha", the page shown |
| Cold `open -a <app> <url>` through LaunchServices | maintainer check | a rebuilt ad-hoc bundle on the Chromium disk asks for removable-volume access first; the runs above launched the executable from a terminal that has it, and sent the GURL event to the process by PID |

Found on the way: the window and row of a URL opened at a cold launch with no Space yet (first run) show an empty card
and no selected row; with a Space the page is shown. Not changed here.

### Verification

- ShellKit `swift test --skip ShellKitGUITests`: 607 tests, all pass, on `main` at `5117b90` (599 there + 8 new `ChromiumEngineScriptTests`). GUI tests not
  run (no ShellUI change). ArktCore `swift test`: 378, all pass.
- Patch budget: `.patches` 7; no file outside `engine/arkt` changed in the engine.

## W3-7 C and D: start, quit and the main menu

Date 2026-10-25. Branch `engine/33-w3-7cd-start-quit-menu` off `main` (rebased onto `46f3729`), Swift lane. Swift only:
no engine worktree, `$CR` and `$EMB` not touched, no `EngineAPI`, facade header or `Package.swift` change, no app
launch (part C's acceptance is the FakeEngine app; the real-engine run is W3-9).

### Part C: start and quit

- **`AppComposition`** (`App/AppComposition.swift`) holds what `AppDelegate.launch()` did: data folder, load, session.
  `start(engine:hostLookup:defersWindows:) async throws` replaces the plan's `start(engine:windowHostProvider:)`: the
  embedder already wires the engine's provider to the delegate, so the composition needs only the engine's
  `host(of:)` to pair windows, and the Chromium engine defers the launch window. A failed launch shows the alert from
  a run-loop callout (never a modal inside a main-actor job, W3-0a); Try Again loops inside `start`, Quit throws. So
  `embedderReady` is called only once a session exists, and `startFailed` (after `embedderFailed` dropped the queue)
  only quits.
- **Quit without a facade call.** The header has no `chrome::AttemptExit()`; none is needed. The composition's quit
  closure is `NSApp.terminate(nil)` in both builds; in the Engine build `NSApp` is `BrowserCrApplication`, whose
  `terminate:` is Chromium's own quit path (W3-8 run B: Quit through `terminate:` gives `engineWillBeginTerminating`,
  the `.appTerminating` closes and `engineWillTerminate`).
- **FakeEngine:** `AppDelegate` installs the menu, calls `start`, and its `.terminateLater` path calls
  `prepareForTermination()` then `flush()`, as before. **Engine:** `ChromiumShell` (`App/Engine/`, Engine
  configuration only) is the `ChromiumEmbedderDelegate`: `start` runs `AppComposition.start` with deferred windows;
  one run-loop turn after `embedderReady` it opens the launch window unless the engine's queued requests (a startup
  URL, an extension's `chrome.windows.create`) built one; `host(for:in:)` is the window set's provider;
  `engineWillBeginTerminating` is `prepareForTermination()`, `engineDidCancelTerminating` restarts auto-archive (the
  stamps written at quit start stay), `engineWillTerminate` awaits `flush()`. `StandInShell` stays only for the
  engine lane's `--arkt-reentrancy-probe` and `--arkt-embedder-fail` runs.
- **`ShellWindowSet`** (ShellUI) holds every browser window: launch, New Window (without a page, so no row is shown
  in two windows; its engine window comes with the first tab), FakeEngine's Dock reopen (#241), and windows for engine
  requests. A provider window is built without calling the engine, in the opener's Space (else the primary window's)
  with the requested frame, and is neither shown nor adopted until its `.windowOpened`; it is matched by host
  (`hostLookup`), not by order, because a shell window's own `createWindow(host:)` announces its window before
  `attach` records the id. Under Chromium a Dock reopen arrives as a `.reopen` request (`AppSession.reopenWindow` is
  FakeEngine only now): an open window that never got an engine window is reused, otherwise a new one is built.
  Quit stamps, auto-archive exemptions, favicons and import availability cover every open window.
- **Host claims:** `IDC_NEW_WINDOW` (34000, through the set) and `IDC_CLOSE_WINDOW` (the close button's path), next to
  `.newTab` and `.closeTab`.
- **PR #274 review (LOW):** the close button no longer stamps the shown tabs before the engine answers; the stamp runs
  on the first `.tabClosed(reason: .windowClosing)` of a requested close, still before any page leaves, so a close
  cancelled at a leave-site prompt leaves the stored sidebar byte-identical (ShellUI cannot read `lastActiveAt` back,
  so deferring replaces restoring). A cancelled quit does not undo `prepareForTermination`'s stamps.
- **Engine build data:** the Engine configuration builds without `DEBUG`, so it ignored `ARKT_DATA_DIR`; it now
  accepts the overrides like Debug and Profile (`ArktEnvironmentOverrides` YES). Without them an Engine run opens the
  real Arkt data folder. **W3-11 must ship the engine bundle from a configuration that does not accept the overrides**
  (no `ARKT_CHROMIUM_ENGINE`-style condition in `AppEnvironment`, `ArktEnvironmentOverrides` NO).

### Part D: the menu

`App/MainMenu.swift`, the same menu in both builds; `install(commands:)` sets it. FakeEngine installs it at launch,
the Engine build one turn after `NSApplicationDidFinishLaunchingNotification` (observer registered in `engineMain()`
before `ChromeMain`; nothing touches `NSApplication` there).

1. Targets: About, Hide, Hide Others, Show All, Bring All to Front and Quit target `NSApp`; New Window, Settings,
   Import from Arc and Show Archive target `AppCommands`, which validates from the session (nothing enabled before it
   exists). Quit is `terminate:` with tag 34031 in the first menu. Settings (Cmd-,) is a disabled placeholder until
   Arkt has a Settings window; it keeps the key from Chromium's settings page.
2. Tags: a hidden top-level `IDC_BOOKMARKS_MENU` (57333) item with an empty submenu; no 57326, 57323 or 57324 anywhere.
   The History menu is untagged.
3. Page commands: 19 `commandDispatch:` items, nil target, tag = command id: Reload, Force Reload, Stop, Back, Forward,
   Find, Find Next, Find Previous, Actual Size, Zoom In, Zoom Out, Save Page As (Shift-Cmd-S), Print, View Source,
   Developer Tools, Inspect Elements, JavaScript Console, Show All History, Downloads. The six ids without an
   `EngineCommand` constant (#272) and `IDC_NEW_WINDOW` are in `ShellUI.PendingEngineCommands`, the one place to delete
   when #272 lands. FakeEngine's `forward` runs what WKWebView can (reload, force reload, stop, back and forward with
   history, zoom) and disables the rest.
4. Shell items: New Window (Cmd-N), Close Window (Shift-Cmd-W, `performClose:`), Enter Full Screen (Ctrl-Cmd-F),
   Minimize (Cmd-M) and Zoom (checked to work on `ShellWindow`), Jump to Selection (Cmd-J). Existing items and keys kept.
5. `servicesMenu`, `windowsMenu`, `helpMenu` are set on every install. AppKit keeps the first Services menu it was
   given (a later assignment is ignored, measured on macOS 27), so an existing one (Chromium's) is moved under Arkt's
   App menu; `windowsMenu` is replaced only by a menu inside the main menu, which Arkt's is.
6. Reserved keys: `ShellWindow.performKeyEquivalent(with:)` sends Cmd-T, Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q and
   Cmd-Opt-Right / Left to `NSApp.mainMenu` before the view hierarchy, and goes the usual way when the menu has no item
   for the key. `ReservedKeys` matches the virtual key code (Cyrillic layouts) or the unmodified character (AZERTY,
   Dvorak) with exactly these modifiers (`.function`, `.numericPad`, Caps Lock ignored); the menu then decides the item.
7. Install point as above; never from `engineDidStart`.

### Verification

`nice -n 10`, `-j 4`, scratch and derived data under `arkt-shell-dd/w3-7cd` on the Chromium disk.

- ShellKit `swift test --skip ShellKitGUITests`: **551**, all pass (new: `ReservedKeysTests`).
- ShellKit `--filter ShellKitGUITests`: **459**, 5 skipped, 0 failures. New: `ShellWindowSetTests` 11,
  `ShellWindowKeyTests` 6, `MainMenuInventoryTests` 9, `FakeEnginePageCommandTests` 2, `EngineHostingTests` +3 (a
  cancelled close and an unheld close stamp correctly, Close Window claimed).
- ArktCore `swift test`: 355, all pass.
- Debug app: `BUILD SUCCEEDED`, `NSPrincipalClass` `NSApplication`, `strings | grep -c "ARKT engine"` 0 in each
  binary, no `Contents/Frameworks`.
- Engine configuration (`ARKT_ENGINE_APP` = `out/Spike/Chromium.app` read-only, build directory on the scratch path,
  `$EMB` not written): `BUILD SUCCEEDED`, `Engine framework copied`, framework CDHash equal to `out/Spike`'s,
  `NSPrincipalClass` `BrowserCrApplication`, `nm -u | grep -cF '_OBJC_CLASS_$_Arkt'` 0, `ArktShellEmbedder` defined.
- Checked to fail first: the reserved-key window test (Cmd-W reached the swallowing view), the cancelled-close test
  (stamped at request).
- On this machine a user key equivalent (`NSUserKeyEquivalents`) blanks "Find Next"; the menu test skips the key check
  for titles the user rebound.

### What W3-9 needs

- Launch the Engine app with `ARKT_DATA_DIR` (and `ARKT_DEFAULTS_SUITE`) pointing at a scratch folder.
- Startup replay: the launch window opens one turn after `embedderReady` unless the queued requests built a window. If
  the facade replays asynchronously, a cold launch with a URL shows two windows; step 3 shows which.
- Check that Chromium's Services submenu appears under Arkt's App menu, that Quit, Cmd-W with page focus and the page
  commands reach the `Browser` (W3-8 step 4), and that a Dock reopen and `chrome.windows.create` land in adopted
  windows in the right Space.
- Unchanged gaps: nil-target page commands with the Archive window key (or no window) reach AppController (W3-8 M7);
  Cmd-Left / Cmd-Right as Back / Forward; #272.

## W3-10: infobars on Arkt windows

Date 2026-10-24. Branch `engine/33-w3-10-infobars` off `main` at `7e5d409`. Overlay only: no patch changed,
`.patches` unchanged (7 files), `$CR` branch `arkt` at `8910b992e4` before and after (`git -C $CR diff --stat
156.0.8078.48..arkt | tail -1`: 17 files changed, 76 insertions, 5 deletions). New dependencies of
`//arkt/browser:window`: `//components/infobars/content`, `//components/infobars/core`, `//chrome/browser/ui:ui_features`;
`gn check out/Spike '//arkt/*'`: `Header dependency check OK`. Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome`,
`The build has finished successfully.`, 0 `FAILED:`. `/` had 6.1 GiB free and swap 8.6 GB used of 10 GB before each
build and run. Every run: fresh profile `w3-10-*`, CDP ports 9521-9531, `--use-mock-keychain`, one GUI run at a time,
stopped by its PID; pages from a loopback server on `127.0.0.1:8611`. Window-only screenshots of the test window kept
locally under `$PROF/w3-10-shots`. The runs below were made on `main` at `01e68c3`; after the rebase onto `7e5d409`
(whose engine change is the self-test embedder) the build was redone and the host-mode row run again (`w3-10-host2`,
same results). The `w3-10-ax` run is on the final build.

### Where infobars went before

Chromium adds every infobar to the tab's `infobars::ContentInfoBarManager` (directly, through
`GlobalConfirmInfoBar` for the browser-wide ones, or through `BrowserInfoBarManager::Show`/`ShowGlobally` when
`kCentralizedInfoBarFramework` is on; it is off by default and lands in the same per-tab manager). Only `BrowserView`'s
`InfoBarContainerView` shows them. On the build before this change (`w3-10-base`, `--no-sandbox --enable-automation`)
the Arkt window showed nothing: no bar in the window, no other window in the on-screen window list for the process,
no `FATAL`. The infobar objects (Views `ConfirmInfoBar`s that never get a widget) sat in the manager, and their
delegates never ran. Note: `--enable-automation` returns from `AddInfoBarsIfNecessary` before the bad-flags prompt, so
the two flags were run separately below.

### Inventory (Chromium 156, macOS desktop)

`chrome://infobar-internals` (enabled through `internal_only_uis_enabled` in a throwaway profile's Local State) can
show every desktop infobar type on demand; all 20 Mac types were triggered on an Arkt window (`w3-10-auto`). The log
line is `ARKT: infobar <InfoBarIdentifier> shown ...`.

| Infobar (identifier) | When on Arkt windows | Delegate | Result |
|---|---|---|---|
| Unsupported command-line flag (`BAD_FLAGS` 43) | startup with a flag of `kBadFlags` (`--no-sandbox`, `--disable-web-security`, ...) | confirm, no buttons | drawn |
| Automation (`AUTOMATION` 73) | startup with `--enable-automation`, every tab of every window | confirm (global) | drawn |
| Google API keys missing (`GOOGLE_API_KEYS` 45) | startup when `google_apis::HasAPIKeyConfigured()` is false (not seen at startup on this build) | confirm, link | drawn |
| Obsolete system (`OBSOLETE_SYSTEM` 46) | startup on an old macOS | confirm, link | drawn |
| Session restore (`SESSION_RESTORE` 128) | startup (`kSessionRestoreInfobar`, on by default) unless `--no-first-run`/`--no-default-browser-check` | confirm, link, template | drawn |
| Default browser (`DEFAULT_BROWSER` 44), PDF viewer (`PDF` 123) | startup after first run | confirm (global) | drawn |
| OSCrypt availability | startup, encryption unavailable | confirm | drawn (same path; not triggerable from the page) |
| DevTools "started debugging" (`EXTENSION_DEV_TOOLS` 13, `DEV_TOOLS` 12), shared process (120) | `chrome.debugger.attach`, DevTools | confirm (global) | drawn |
| Collected cookies / page info reload (`COLLECTED_COOKIES` 40) | site settings changed | confirm | drawn |
| Alternate URL ("Did you mean", `ALTERNATE_NAV` 42) | omnibox intranet guesses (no omnibox in Arkt: not reached in practice) | confirm, inline link | drawn |
| Link capturing (119), theme installed (`THEME_INSTALLED` 15), installation error (41), incognito connectability (14), web auth flow (113), known interception (96), local test policies (115, not closeable) | as in Chrome | confirm | drawn |
| Tab sharing (`TAB_SHARING` 93) | `getDisplayMedia` tab capture | own Views (`TabSharingInfoBar`) | not drawn: gap |
| Sign-in QR code | sign-in promo | own Views | not drawn: gap |
| Keystone promotion | branded builds with the updater only | confirm | not built in `Chromium.app` |
| Translate | desktop uses the bubble (`ShowTranslateBubble`), not an infobar | - | not an Arkt-window case |
| Session crashed "Restore pages?" | `SessionCrashedBubble`, a Views bubble, not an infobar | - | #122 (bubble) |

### What changed

- **Presenter** (`arkt_infobars.{h,mm}`, `ArktInfobarPresenter`). `ArktBrowserWindow` makes one per tab when the tab
  enters the window (insert or contents replacement) and drops it when the tab leaves; it observes the tab's
  `ContentInfoBarManager` (`InfoBarManager::Observer`: added, removed, replaced, manager destroyed) and picks up
  infobars that were there before the tab arrived. Each `ConfirmInfoBarDelegate` infobar gets a native row; the rows
  keep the manager's order. Actions run the delegate exactly as `ConfirmInfoBar` and `InfoBarView` do: OK
  `Accept()`, Cancel `Cancel()`, the link `LinkClicked(disposition)`, an inline link
  `InlineSubstitutionLinkClicked(index, disposition)`, each followed by `RemoveSelf()` when the delegate returns
  true; close runs `InfoBarDismissed()` then `RemoveSelf()`. Every action first checks that the row is still drawn and
  the infobar still has its owner. The disposition comes from the click's modifiers
  (`ui::WindowOpenDispositionFromNSEvent`). Infobars without a confirm delegate are logged (`not drawn (not a confirm
  infobar)`).
- **Content** as `ConfirmInfoBar` builds it: the message template with its substitutions and link ranges when
  `kInfoBarInlineLinks` is on (default), else `GetMessageText`; the icon (`GetIcon` rasterized with the window's color
  provider, 20 pt); the link before the buttons or at the trailing edge (`ShouldShowLinkBeforeButton`); OK and Cancel
  with their labels, enabled state and tooltips, OK (or the only button) prominent unless `GetButtonStyle` says
  otherwise; the close button only when `IsCloseable`.
- **Rows** (`arkt_infobar_view.{h,mm}`, plain AppKit values). 40 pt high as Chrome's, one line, truncated at the end
  with the full message as tooltip; surface, text, divider and accent-link colors and the filled buttons from
  `ArktDialogSheet` (its color functions, `ArktSheetButton` and `ArktSheetLinkButton` are now in its header). A 1 px
  divider under each row. Mirrored in right-to-left UI. Motion: a 140 ms opacity fade on a row that appears while the
  bar is on screen (custom ease-out, as the permission panel), no height animation (it would resize the page every
  frame), no exit animation.
- **Placement.** The rows sit above the page and push it down, as Chrome's infobar container does. Host mode:
  `ArktTabContainerView` takes a top bar (`setTopBarView:`), keeps it when the contents view is swapped and lays the
  contents view out below it; the facade tells the window when it put a contents view in its container
  (`OnTabContentsViewAdopted`), so a bar added before that is placed then. Placeholder host: the card gets the same
  layout for the mounted tab (`ArktLayoutBelowTopBar`). Window resizes follow through autoresizing. Each tab's bar is
  its own, so a tab switch shows the new tab's infobars. `GetContentsSize` now reports the page's size (the host view
  less the bar).
- **VoiceOver.** Each row is an `AXGroup` named by its message, with the message (`AXStaticText`, or a text area with
  `AXLink` children when it has inline links), the link (`AXLink`), the buttons and `Close` (`IDS_ACCNAME_CLOSE`), in
  reading order; the icon is hidden.

### Verification

| Check | Result |
|---|---|
| Acceptance: `--no-sandbox` (`w3-10-flags`, placeholder) | `infobar 43 shown buttons=0 link=0 closeable=1 ... message="You are using an unsupported command-line flag: --no-sandbox. Stability and security will suffer."`; screenshot: the bar above the page, the page's top edge right under it; AX `AXGroup` with the message and `Close`; AXPress `Close`: `infobar 43 close`, `removed rows=0`, `innerHeight` 840 -> 880, the bar gone |
| `--enable-automation` (`w3-10-auto`) | `infobar 73 shown` on the first tab and again on a tab created later (global) |
| All 20 types (`w3-10-auto`, `chrome://infobar-internals`) | 19 rows on the tab, 0 `FATAL`: two triggers add nothing new because the manager keeps one of each (`EqualsDelegate`): automation was already up, and "Page info" asks for the same reload infobar (40) as "Collected cookies" |
| OK button | AXPress `Reload` (infobar 40): `infobar 40 ok`, the page reloads and the manager removes the expiring infobars |
| Cancel button | AXPress `Deny` (infobar 12): `infobar 12 cancel`, the global debugging infobars removed from every tab |
| Link | AXPress `Learn more` (infobar 96): `infobar 96 link`, a new foreground tab with `chrome://connection-monitoring-detected/` |
| Inline link | AXPress the `AXLink` inside the "Did you mean" message (42): `infobar 42 message-link`, removed, the tab navigated (to the delegate's target, see the note below) |
| Tab switch | the other tab shows only its own rows (AX tree), `innerHeight` 720 with four rows, 880 with none |
| Light and dark | `--arkt-appearance=light` (`w3-10-light2`) and the system's dark mode: screenshots |
| Right-to-left (`w3-10-rtl`, `--force-ui-direction=rtl --no-sandbox`) | `Close` at the leading (left) edge at x 401 in a row at x 390, the message right-aligned |
| Host mode (`w3-10-host`, `--no-startup-window --arkt-facade-selftest`) | two infobars on the self-test's tab container: rows at y 419 (container top, under the 32 pt title bar), page `innerHeight` 600 -> 520; the other tab: no rows, 600; back: rows again; `Close`: 560 |
| Window and tab closed with infobars up (`w3-10-final`) | `tab event removed`, `native window destroyed`, census `0/0/0`, process alive, 0 `FATAL` |
| Message roles (`w3-10-ax`, after the last change) | session restore (a plain substitution and a separate link): `AXStaticText` then `AXLink` `Settings.`; "Did you mean" (an inline link): `AXTextArea` with an `AXLink` child |
| Permission panel (#260) after the `ArktDialogSheet` header change (`w3-10-ax`) | notification request with a gesture: `permission prompt shown ... child=1`; AXPress `Block`: `denied` |
| Stability | 0 `FATAL`/`Check failed`/`Received signal` in every run |

The automation row reads "Chrome is being controlled by automated test software": that is Chromium's own string
(`IDS_CONTROLLED_BY_AUTOMATION`), not Arkt text. `Mount` now adds the contents view below the card's other subviews
(it was added on top) so the bar stays above it; the placeholder card has no other subviews over the page.

Note on the inline-link row: the alternate-URL infobar triggered from the internals page points at
`https://google.com/`, and pressing its link navigated the test tab there once before it was sent back to the loopback
page. The other link rows used Chromium's own pages.

Regression rows (`w3-10-reg`, port 9528, `--arkt-trace-visibility --no-sandbox`, `tabs-probe`, `action-probe`; row 5
on `w3-10-reg3`, port 9530): W5b 1 (alive after 30 s, census `normal=1 arkt=1 views=0`, the bad-flags row up), 2
(navigate to `b.html`: `visible`), 8 (`window.open` with a gesture: `true`, `tab list rows 2`), 3 (`probe.create()`:
index 2, `tab list rows 3`, the page still `visible`), 5 (`probe.window()`: `normal`, census `normal=2 arkt=2 views=0`),
6 (`tab event removed`), 7 (every window removed: census `0/0/0`, `native window destroyed`, process alive 10 s later,
gone after `kill`), 13 (Edit > Find > Find... after the frontmost check: `stub FindBar::Show`); W5c Step 3
(`tabs.update` to the other tab: `hidden`, back: `visible`); W6 (`chrome.action.openPopup()`: `"ok"`, `TriggerPopup
... by_user=0`, `popup loaded`). 0 `FATAL`/`Check failed`.

### Deviations from the plan

- The plan's split (the facade exposes a plain infobar list, ShellUI draws `InfobarView.swift`, a ShellUI test against
  `InMemoryEngine`) is not done: the facade header is frozen this week and W3-7's shell side is in progress, so the
  bar is engine-drawn on the tab's container, as Decision 10 keeps the other engine surfaces. The row content is
  plain AppKit values (`ArktInfobarContent`), so a ShellUI presenter can take it later through a header change both
  lanes approve.

### Left open (#122)

- Infobars with their own Views are not drawn: tab sharing (`TAB_SHARING_INFOBAR_DELEGATE`, 93, during
  `getDisplayMedia` tab capture) and the sign-in QR code infobar; they are logged.
- Tab-modal dialogs and the permission panel still anchor to the top of the tab's container (or card), so they sit
  over the infobar rows instead of below them; anchoring them to the page needs `DialogHostViewFor` to change, which
  the #250/#260 rows depend on.
- Infobars stay visible in HTML fullscreen (Chrome hides them when the manager says so, `ShouldHideInFullscreen`).
- No open/close height animation (by choice, above); Chrome animates the container height.
- The session-crashed "Restore pages?" prompt is a Views bubble, not an infobar: it stays in #122 with the bubbles.

## W3-8: main menu inventory and owner

Date 2026-10-24. Branch `engine/33-w3-8-menu` off `main` at `5673197`, rebased onto `a182151` (#267). Steps 1-3 of the
plan; step 4 (each forwarded command reaching the Arkt `Browser`) waits for W3-9. `$CR` (branch `arkt` at `8910b992e4`,
0001-0007) was read only. One overlay change, test-only: `--arkt-menu-probe` in the self-test embedder (below), built in
`out/Spike` and run on `Chromium.app`. No patch; no change to `MainMenu.swift` or ShellUI (W3-7 holds them; their steps
are in the plan, W3-7 part D).

**Decision (step 3): Arkt owns the main menu** (maintainer decision 3 stands). Every Chromium dependency on the menu
is either tolerant of a missing item or satisfied by an item Arkt can carry without a patch. Two of them are not
tolerant, so they are conditions on Arkt's menu, not optional polish:

1. **A hidden item tagged `IDC_BOOKMARKS_MENU` (57333) with an empty submenu.** Without it the first Arkt window
   that becomes main crashes the browser: `windowDidBecomeMain:` (`app_controller_mac.mm:1164`) calls
   `setLastProfile:`, which builds a `BookmarkMenuBridge` from `[[NSApp.mainMenu itemWithTag:IDC_BOOKMARKS_MENU]
   submenu]` (`:2274`, `:2300-2311`) and its constructor `CHECK`s the menu (`bookmark_menu_bridge.mm:62`). With
   `--no-startup-window` the first `setLastProfile:` comes after Arkt's menu is installed, and with
   `kDestroyProfileOnBrowserClose` (on by default on macOS, `browser_features.cc:75-77`) the bridge is rebuilt after
   the last window of a profile closes, so this is the normal path, not an edge case. Measured: run A crashed with
   `Check failed: menu_root_` (`BookmarkMenuBridge::BookmarkMenuBridge` <- `-[AppController setLastProfile:]` <-
   `-[AppController windowDidBecomeMain:]` <- `_NXShowKeyAndMain`) the moment its window became main; runs B and C,
   with the placeholder, did not, and the bridge took the placeholder over (`submenu replaced=yes delegate=set`, still
   `hidden=yes`).
2. **No `IDC_FILE_MENU` (57326) tag on Arkt's File menu, and no `IDC_TAB_MENU` (57323) tag anywhere.** With the File
   tag, AppController's pre-search block rewrites the items that own Cmd-W and Shift-Cmd-W before every key-equivalent
   search (`app_controller_mac.mm:812-817`, `:2419-2461`; an item qualifies when its tag is 0, `IDC_CLOSE_WINDOW` or
   `IDC_CLOSE_TAB`, `:838-893`). Measured in run C: "Archive Tab" became "Close Tab" (`tag=34015
   action=commandDispatch:`), "Close Window" became `tag=34012 action=performClose:`, and the same search then found no
   item for Cmd-W or Shift-Cmd-W at all. Without the tag (runs A and B) both items stayed as built and resolved to
   Arkt's actions.

Also kept: Quit has tag `IDC_EXIT` (34031) and action `terminate:` with target `NSApp`, in the first top-level menu
(the confirm-to-quit panel looks for it there, `confirm_quit_panel_controller.mm:420-431`); run B quit through it (AX
menu click): `quit started`, `engineWillBeginTerminating`, `tabClosed ... reason=appTerminating`, `windowClosed`,
`engineWillTerminate`, the same seams as Chromium's own menu (W3-3).

Install point: on `NSApplicationDidFinishLaunchingNotification`, deferred one turn so `AppController`'s own
`-applicationDidFinishLaunching:` (which sets the File menu delegate, `:1309`) has run first. Run A logged
`file delegate is app delegate=yes` on Chromium's menu at that point. Installing earlier is not unsafe with the tag
rules above, but it is not needed and later is what was measured.

### Step 1: Chromium's main menu (`chrome::BuildMainMenu`, `main_menu_builder.mm:614-641`)

Built in `ChromeBrowserMainPartsMac::PostCreateMainMessageLoop` (`chrome_browser_main_mac.mm:145-166`) before the hook
runs, then `-[AppController mainMenuCreated]`. Shortcuts come from `AcceleratorsCocoa` (`accelerators_cocoa.mm:33-119`)
unless an item sets its own (`key_equivalent`). Arc column: same key and action, other action on the same key (Arkt
follows Arc), or none; KB numbers from `docs/spec/arc-parity-spec.md` section 1.

| Menu (tag) | Item | Id / tag, action | Key | Arc |
|---|---|---|---|---|
| App (`IDC_CHROME_MENU`) | About | tag `IDC_ABOUT`, `orderFrontStandardAboutPanel:` to AppController | - | none |
| | Settings | tag `IDC_OPTIONS`, `showPreferences:` to AppController | Cmd-, | same (KB-066) |
| | Settings (PWA only, removed) | `IDC_WEB_APP_SETTINGS` | Cmd-, | none |
| | Clear Browsing Data | `IDC_CLEAR_BROWSING_DATA` | Shift-Cmd-Delete | none |
| | Import Bookmarks and Settings | `IDC_IMPORT_SETTINGS` | - | none (Arkt: Import from Arc) |
| | Services | submenu, `NSApp.servicesMenu` | - | same |
| | Hide / Hide Others / Show All | tag `IDC_HIDE_APP` `hide:`; `hideOtherApplications:`; `unhideAllApplications:` | Cmd-H / Opt-Cmd-H / - | same (KB-069) |
| | Warn Before Quitting | `toggleConfirmToQuit:` to AppController | - | none |
| | Quit | tag `IDC_EXIT`, `terminate:` to NSApp | Cmd-Q | same (KB-069) |
| File (`IDC_FILE_MENU`) | New Tab | `IDC_NEW_TAB` | Cmd-T | other: command bar (KB-001) |
| | New Window | `IDC_NEW_WINDOW` | Cmd-N | other: same Spaces (KB-005) |
| | New Incognito Window | `IDC_NEW_INCOGNITO_WINDOW` | Shift-Cmd-N | same key (KB-007), out of scope (#115) |
| | New Isolated Window (policy, hidden) | `IDC_NEW_ISOLATED_WINDOW` | (takes Shift-Cmd-N under policy) | none |
| | Reopen Closed Tab | `IDC_RESTORE_TAB` | Shift-Cmd-T | same key (KB-010) |
| | Open File | `IDC_OPEN_FILE` | Cmd-O | other: Peek/Little Arc open in Space (KB-076) |
| | Open Location | `IDC_FOCUS_LOCATION` | Cmd-L | other: command bar (KB-002) |
| | Close Window | tag `IDC_CLOSE_WINDOW`, `performClose:` | Shift-Cmd-W (Cmd-W without tabs) | same (KB-009) |
| | Close All (alternate) | `closeAll:` | Opt-Shift-Cmd-W | none |
| | Close Tab | `IDC_CLOSE_TAB` | Cmd-W | other: Archive Tab (KB-008) |
| | Save Page As | `IDC_SAVE_PAGE` | Cmd-S | other: Cmd-S sidebar (KB-017); Arc saves on Shift-Cmd-S (KB-060) |
| | Share | submenu (ShareMenuController) | - | none |
| | Print / Print Using System Dialog (alternate) | `IDC_PRINT` / `IDC_BASIC_PRINT` | Cmd-P / Opt-Cmd-P | same (KB-060) / none |
| Edit (`IDC_EDIT_MENU`) | Undo / Redo | tags `IDC_CONTENT_CONTEXT_UNDO` / `_REDO`, `undo:` / `redo:` | Cmd-Z / Shift-Cmd-Z | same keys; Arc's Cmd-Z also undoes sidebar actions (KB-011) |
| | Cut / Copy / Paste | tags `IDC_CONTENT_CONTEXT_CUT` / `_COPY` / `_PASTE` | Cmd-X / C / V | same |
| | Paste and Match Style (+ alternate) | tag `IDC_CONTENT_CONTEXT_PASTE_AND_MATCH_STYLE`, `pasteAndMatchStyle:` | Shift-Cmd-V (alternate Opt-Shift-Cmd-V) | Arc Cmd-Opt-V pastes a URL as a tab (KB-016) |
| | Delete / Select All | tags `IDC_CONTENT_CONTEXT_DELETE` / `_SELECTALL` | - / Cmd-A | same |
| | Find (`IDC_FIND_MENU`): Search the Web | `IDC_FOCUS_SEARCH` | Opt-Cmd-F | other: Find and Replace (KB-058) |
| | Find / Find Next / Find Previous | `IDC_FIND` / `IDC_FIND_NEXT` / `IDC_FIND_PREVIOUS` | Cmd-F / Cmd-G / Shift-Cmd-G | same (KB-058, KB-059) |
| | Use Selection for Find / Jump to Selection | `copyToFindPboard:` / `centerSelectionInVisibleArea:` | Cmd-E / Cmd-J | other: Cmd-E cycles extensions (KB-047) / same (KB-058) |
| | Spelling and Grammar (`IDC_SPELLCHECK_MENU`) | `showGuessPanel:`, `checkSpelling:`, two toggles | Cmd-: / Cmd-; | none recorded |
| | Substitutions, Transformations, Speech | 4 + 3 + 2 AppKit selectors, no tags | - | none recorded |
| View (`IDC_VIEW_MENU`) | Always Show Bookmarks Bar | `IDC_SHOW_BOOKMARK_BAR` | Shift-Cmd-B | none |
| | Always Show Toolbar in Full Screen | `IDC_TOGGLE_FULLSCREEN_TOOLBAR` | Shift-Cmd-F | none |
| | Full URLs, Lens shortcut, AI mode button, search tools | `IDC_SHOW_FULL_URLS`, `IDC_SHOW_GOOGLE_LENS_SHORTCUT`, `IDC_SHOW_AI_MODE_OMNIBOX_BUTTON`, `IDC_SHOW_SEARCH_TOOLS` | - | none |
| | Vertical tabs / collapse | `IDC_TOGGLE_VERTICAL_TABS` / `IDC_TOGGLE_VERTICAL_TABS_COLLAPSE` | - / Shift-Cmd-L | other: Library (KB-065) |
| | Customize Touch Bar | tag `IDC_CUSTOMIZE_TOUCH_BAR` | - | none |
| | Stop / Reload / Force Reload (alternate) | `IDC_STOP` / `IDC_RELOAD` / `IDC_RELOAD_BYPASSING_CACHE` | Cmd-. / Cmd-R / Shift-Cmd-R | same (KB-054, KB-056) |
| | Enter Full Screen (+ alternate) | tag `IDC_FULLSCREEN`, `toggleFullScreen:` | Fn-Ctrl-Cmd-F (alternate Ctrl-Cmd-F) | same (KB-051) |
| | Actual Size / Zoom In / Zoom Out | `IDC_ZOOM_NORMAL` / `IDC_ZOOM_PLUS` / `IDC_ZOOM_MINUS` | Cmd-0 / Shift-Cmd-= / Cmd-- | same (KB-057) |
| | Cast | `IDC_ROUTE_MEDIA` | - | same, unbound (KB-043) |
| | Developer (`IDC_DEVELOPER_MENU`): View Source, Developer Tools, Inspect Elements, JavaScript Console | `IDC_VIEW_SOURCE`, `IDC_DEV_TOOLS`, `IDC_DEV_TOOLS_INSPECT`, `IDC_DEV_TOOLS_CONSOLE` | Opt-Cmd-U / I / C / J | same (KB-049, KB-050) |
| | Allow JavaScript from Apple Events | `IDC_TOGGLE_JAVASCRIPT_APPLE_EVENTS` | - | none |
| History (`IDC_HISTORY_MENU`) | Home | `IDC_HOME` | Shift-Cmd-H | none |
| | Back / Forward | `IDC_BACK` / `IDC_FORWARD` | Cmd-[ / Cmd-] | same; Arc also Cmd-Left / Cmd-Right (KB-031, KB-032) |
| | Recently Closed, Recently Visited | headers and separators tagged `HistoryMenuBridge::k*` (not `IDC_`); rows added by HistoryMenuBridge | - | none |
| | Show Full History | `IDC_SHOW_HISTORY` | Cmd-Y | same (KB-065) |
| Bookmarks (`IDC_BOOKMARKS_MENU`, as `AppMenuModel::kBookmarksMenuPlaceholder`) | Bookmark Manager | `IDC_SHOW_BOOKMARK_MANAGER` | Opt-Cmd-B | none |
| | two separators | tag `IDC_BOOKMARK_THIS_TAB` | - | - |
| | Bookmark This Tab / Bookmark All Tabs | `IDC_BOOKMARK_THIS_TAB` / `IDC_BOOKMARK_ALL_TABS` | Cmd-D / Shift-Cmd-D | other: pin (KB-012) / toolbar (KB-018) |
| Profiles (`IDC_PROFILE_MAIN_MENU`) | (filled by ProfileMenuController) | - | - | none |
| Tab (`IDC_TAB_MENU`) | New Tab to Right (+ hidden "below") | `IDC_NEW_TAB_TO_RIGHT` x2 | - | none |
| | Select Next / Previous Tab | `IDC_CYCLE_TO_NEXT_TAB` / `IDC_CYCLE_TO_PREV_TAB` | Ctrl-Tab / Ctrl-Shift-Tab | other: MRU switcher (KB-022, KB-023) |
| | Duplicate (+ target alternate) | `IDC_DUPLICATE_TAB` / `IDC_DUPLICATE_TARGET_TAB` | - | same, unbound (KB-042) |
| | Mute, Pin, Group (each + target alternate) | `IDC_WINDOW_MUTE_SITE` / `IDC_MUTE_TARGET_SITE`, `IDC_WINDOW_PIN_TAB` / `IDC_PIN_TARGET_TAB`, `IDC_WINDOW_GROUP_TAB` / `IDC_GROUP_TARGET_TAB` | - | Arc pins on Cmd-D (KB-012) |
| | Close Other Tabs, Close Tabs to Right (+ hidden "below") | `IDC_WINDOW_CLOSE_OTHER_TABS`, `IDC_WINDOW_CLOSE_TABS_TO_RIGHT` x2 | - | none |
| | Move Tab to New Window | `IDC_MOVE_TAB_TO_NEW_WINDOW` | - | none |
| | Add Tab to New Split | `IDC_NEW_SPLIT_TAB` | Opt-Cmd-N | other: Little Arc (KB-044) |
| | Search Tabs | `IDC_TAB_SEARCH` | Shift-Cmd-A | none |
| Window (`IDC_WINDOW_MENU`) | Minimize / Zoom | tags `IDC_MINIMIZE_WINDOW` `performMiniaturize:` / `IDC_MAXIMIZE_WINDOW` `performZoom:` | Cmd-M / - | same (KB-069) |
| | Show as Tab, Name Window | `IDC_SHOW_AS_TAB`, `IDC_NAME_WINDOW` | - | none |
| | Downloads / Extensions / Task Manager | `IDC_SHOW_DOWNLOADS` / `IDC_MANAGE_EXTENSIONS` / `IDC_TASK_MANAGER_MAIN_MENU` | Shift-Cmd-J / - / - | same (KB-065) / none / none |
| | Bring All to Front | tag `IDC_ALL_WINDOWS_FRONT`, `arrangeInFront:` | - | same |
| | (submenu is `NSApp.windowsMenu`) | | | |
| Help (no tag; `NSApp.helpMenu`) | Report an Issue, Report Unsafe Site (Google Chrome branding only), Help | `IDC_FEEDBACK`, `IDC_REPORT_UNSAFE_SITE`, `IDC_HELP_PAGE_VIA_MENU` | Opt-Shift-Cmd-I / - / Shift-Cmd-/ | none |

Count check: `git -C $CR grep -c 'IDC_' -- chrome/browser/ui/cocoa/main_menu_builder.mm` prints 102 = 71
`.command_id(IDC_...)` + 31 `.tag(IDC_...)`. The 31 tags are 11 submenu holders (`CHROME`, `FILE`, `EDIT`,
`FIND_MENU`, `SPELLCHECK_MENU`, `VIEW`, `DEVELOPER_MENU`, `HISTORY`, `PROFILE_MAIN_MENU`, `WINDOW`, `TAB`), 2 separators
(`IDC_BOOKMARK_THIS_TAB`) and 18 items; the Bookmarks holder's tag is `IDC_BOOKMARKS_MENU` through
`kBookmarksMenuPlaceholder` (`app_menu_model.h:251`) and is not in the count. The table names all 89 tagged or
commanded items (71 + 18), grouped where the row says so.

### Step 2: everything that reads, rewrites or validates the menu

`git -C $CR grep -n 'mainMenu' -- chrome/browser/app_controller_mac.mm chrome/browser/ui/cocoa` prints 38 lines: 22 in
product code (rows L1-L9 and M1-M4 below, plus `main_menu_builder.mm:640/646/651`, which build it, and the
`_mainMenuItem` ivar uses in `profile_menu_controller.mm:99/105/107/232/305`, row M4), 16 in tests
(`accelerators_cocoa_browsertest.mm` 4, `browser_window_mac_browsertest.mm` 7, `main_menu_builder_unittest.mm` 4,
`tab_group_menu_bridge_browsertest.mm` 1). Readers outside those paths are listed too (K rows).

**Lookups** (what Chromium finds in `NSApp.mainMenu`, and what happens when Arkt's menu does not have it):

| # | Where | Looks up | Without the item | Arkt |
|---|---|---|---|---|
| L1 | `-[AppController fileMenu]` `app_controller_mac.mm:834-836`, used by `cmdWMenuItem` / `shiftCmdWMenuItem` `:838-893`, `menuNeedsUpdate:` `:1109-1112`, `initShareMenu` `:1976-1985`, File delegate `:1309` | top-level item tagged `IDC_FILE_MENU` | nil: the Cmd-W shuffle returns early, the delegate and Share menu land on nil (all ObjC nil sends) | tolerant; Arkt must not use the tag (condition 2) |
| L2 | `-[AppController setLastProfile:]` `:2240-2271` | `IDC_FILE_MENU`, then `IDC_NEW_INCOGNITO_WINDOW` / `IDC_NEW_ISOLATED_WINDOW` in it | skipped (`if (fileMenuItem && ...)`) | tolerant |
| L3 | `-[AppController setLastProfile:]` `:2274-2318` | top-level `IDC_BOOKMARKS_MENU` | **`CHECK` in `BookmarkMenuBridge`** (`bookmark_menu_bridge.mm:62`) on the first window that becomes main and after a profile reload | **not tolerant**: hidden placeholder (condition 1); measured, runs A-C |
| L4 | `-[AppController windowDidBecomeMain:]` `:1137-1141`, `onVerticalTabStripModeChanged:` `:1173-1176` | `IDC_TAB_MENU` | `TabMenuBridge` with a nil item (every use is a nil send or a guarded return; the `CHECK_EQ(matchingItems.count, 2u)` at `:1190` is behind the nil-submenu return) | tolerant; Arkt must not use the tag (it would fill Arkt's menu with Chromium's tab list) |
| L5 | `-[AppController initProfileMenu]` `:1960-1974` | `IDC_PROFILE_MAIN_MENU` | runs at `mainMenuCreated`, before Arkt's menu exists: it binds to Chromium's (detached) Profiles item | tolerant; Dock menu profiles still come from it (D1) |
| L6 | `HistoryMenuBridge::HistoryMenu()` `history_menu_bridge.mm:264-268`, on every rebuild | `IDC_HISTORY_MENU` | nil: rebuilds run on a nil menu | tolerant; Arkt does not use the tag (it would get Chromium's history rows) |
| L7 | `TabGroupMenuBridge::TabGroupsMenu()` `tab_group_menu_bridge.mm:90-94` | `kSavedTabGroupsMenuPlaceholder` | nil | tolerant |
| L8 | `+[ConfirmQuitPanelController quitMenuItem]` `confirm_quit_panel_controller.mm:420-431` | item tagged `IDC_EXIT` in the first top-level submenu, for the hold-to-quit text | falls back to Cmd-Q | tolerant; Arkt keeps the tag (the panel only runs with the "Warn Before Quitting" pref, off by default) |
| L9 | `IsCommandTriggeredFromMacMenu` `browser_native_widget_mac.mm:124-135` (`IDC_VIEW_MENU`, `IDC_TAB_MENU`) | parent and command items | false | Views windows only (DevTools, popups); tolerant |
| K1 | `MenuCommandForKeyEvent` `global_keyboard_shortcuts_mac.mm:46-67` (via `cr_menuItemForKeyEquivalentEvent:`) | the item for a key: `commandDispatch:` with tag > 0 gives the tag; `performClose:` gives `IDC_CLOSE_WINDOW`; `terminate:` gives `IDC_EXIT` | `NO_COMMAND` | used by `confirmQuitIfNeeded` (`app_controller_mac.mm:1009-1047`, needs Cmd-Q -> `terminate:`), `ChromeCommandDispatcherDelegate` (`chrome_command_dispatcher_delegate.mm:98`, `:153`) and `BrowserNativeWidgetMac::PreHandleKeyboardEvent` (`:865-884`), the last two in Views windows only. Run A-C: Cmd-Q -> `command=34031` |
| K2 | `-[RenderWidgetHostViewCocoa keyEvent:wasKeyEquivalent:]` `render_widget_host_view_cocoa.mm:1594-1606` | any item for the key (Function-key system shortcuts go to the menu first) | event goes to the page | tolerant |
| K3 | `ArktBrowserWindow::HandleKeyboardEvent` `arkt_browser_window.mm:1315-1332` (overlay) | `[NSApp.mainMenu performKeyEquivalent:]` for a Cmd key the page did not handle | not handled | this is how Arkt's non-reserved items get page keys |
| K4 | `PopupWindowMac` `popup_window_mac.mm:70-88` | observes `NSMenuDidBeginTrackingNotification` on the menu current at popup creation | an HTML `<select>` popup opened before the swap keeps the old menu | harmless: Arkt swaps once, at launch |
| K5 | `+[NSMenu flashMenuForChromeCommand:]` `nsmenu_additions.mm:86-109`, `MenuItemWithTag` `:36-59` (recursive) | an item whose tag is the command | NO, no flash | Views windows only |
| K6 | menu bar height (`browser_frame_view_mac.mm:554`, `immersive_mode_controller_cocoa.mm:200`), `ScopedMenuBarLock` (`scoped_menu_bar_lock.mm:16-22`) | the bar itself | - | not item lookups |

**Mutations** (what Chromium changes, and what it would do to Arkt's menu):

| # | Where | Mutates | Effect on Arkt's menu |
|---|---|---|---|
| M1 | pre-search block, installed in `-[AppController init]` `:812-817`, run by `cr_menuItemForKeyEquivalentEvent:` (`nsmenu_additions.mm:72-82`) before every K1/K2 search; `updateMenuItemKeyEquivalents` `:2419-2461` (also from `menuNeedsUpdate:` on the File menu) | titles, tags, actions and `hidden` of the Cmd-W and Shift-Cmd-W items in the `IDC_FILE_MENU` submenu (tag 0 counts as Chromium's), then `[fileMenu update]` | none without the tag (runs A, B); with it, Archive Tab is replaced by Chromium's Close Tab and both keys stop resolving (run C) |
| M2 | `-[AppController setLastProfile:]` `:2253-2271` | moves Shift-Cmd-N between the Incognito and Isolated items of `IDC_FILE_MENU` | none (no tag) |
| M3 | `-[AppController setLastProfile:]` `:2283-2318` | replaces the `IDC_BOOKMARKS_MENU` item's submenu with the bridge's copy, restores `hidden` | swaps the placeholder's empty submenu for the bridge's (runs B, C: `submenu replaced=yes`, `hidden=yes`) |
| M4 | ProfileMenuController (`profile_menu_controller.mm:99-107`, `:232`, `:305`), ShareMenuController (`initShareMenu` `:1976-1985`), TabMenuBridge, HistoryMenuBridge, TabGroupMenuBridge | their own submenus, found by L1/L4-L7 | none: bound to Chromium's detached menu or to nil |
| M5 | `BuildAppMenu` `main_menu_builder.mm:108`, `BuildWindowMenu` `:503`, `BuildHelpMenu` `:608` | `NSApp.servicesMenu`, `NSApp.windowsMenu`, `NSApp.helpMenu` | they still point into Chromium's menu after the swap (run A-C: `servicesMenu in main menu=no helpMenu in main menu=no`); Arkt sets all three |
| M6 | `-[BrowserCrApplication _customizeFileMenuIfNeeded]` `chrome_browser_application_mac.mm:226-251` | stops AppKit adding Close All / Quit and Keep Windows alternates | applies to Arkt's menu too: Arkt adds any alternates it wants itself |
| M7 | `-[AppController validateUserInterfaceItem:]` `:1584-1671` and `commandDispatch:` / `commandDispatchUsingKeyModifiers:` `:1673-1850` | validates and runs `commandDispatch:`, `terminate:`, `showPreferences:`, `orderFrontStandardAboutPanel:`, `toggleConfirmToQuit:` items that reach the end of the responder chain (it is `NSApp.delegate`) | a nil-target `commandDispatch:` item with no Arkt window key (the Archive window, a sheet, no window) is validated from `_menuState` and run by Chromium: `IDC_NEW_TAB` / `IDC_NEW_WINDOW` / `IDC_SHOW_HISTORY` etc. then create or activate a `Browser` (an engine-initiated window through the host provider). Arkt items that are app-level therefore target the composition root's object; page-command items keep nil targets (the key `ShellWindow` must answer them) and the host's `validate` disables them when no Arkt window is key |

**Dock menu** (D1): `-[AppController applicationDockMenu:]` `:2144-2198` builds its own menu on every Dock click
(profiles from ProfileMenuController, New Window `IDC_NEW_WINDOW`, New Incognito / Isolated Window), all
`commandFromDock:` to AppController, which creates a `Browser` (`CreateBrowser`, `:1755`), so an Arkt window arrives
through the host provider as an engine-initiated request. Arkt's menu cannot change it without a patch (AppController
must stay `NSApp.delegate`, `:796-803`). Accepted this week: New Window works through the provider; New Incognito
Window is the incognito gap of #115 (the provider receives an off-the-record request). W3-9 records what the provider
gets for both.

**Key path in Arkt windows** (why reserved keys need work): an Arkt `ShellWindow` is a plain `NSWindow`, not a
`CommandDispatchingWindow`, so Chromium's reservation in `-[ChromeCommandDispatcherDelegate prePerformKeyEquivalent:]`
(`IsReservedCommandOrKey`, `browser_command_controller.cc`: close tab, close window, new tab, new window, new
incognito/isolated window, restore tab, select next/previous tab, cycle tabs, exit) never runs there. AppKit offers a
Cmd key to the key window first; the focused `RenderWidgetHostViewCocoa` takes every key equivalent
(`performKeyEquivalent:` `:1354-1405`) and sends it to the page; only an unhandled key comes back through
`ArktBrowserWindow::HandleKeyboardEvent` to the menu (K3). Today a page can therefore swallow Cmd-T, Cmd-W and Cmd-Q.
Chromium's shortcuts that are not menu items (`GetShortcutsNotPresentInMainMenu`, Cmd-1...9, Cmd-Opt-Arrows,
Ctrl-PageUp/Down; `GetDelayedShortcutsNotPresentInMainMenu`, Cmd-Left / Cmd-Right back and forward) are run only by
the Views command dispatcher and do nothing in Arkt windows.

### Step 3: Arkt's commands and how each reaches the engine

Current `App/MainMenu.swift` (and ShellUI's `SplitMenu`), and the items the Engine configuration adds. "Shell" means
the shell implements it and the engine is called only through `EngineClient` as the shell's behaviour needs; "page
command" means a `commandDispatch:` item, nil target, `tag` = the `EngineCommand` raw value, which the key
`ShellWindow` forwards to its host and the host passes to `forward.execute(command, .currentTab)` (validation through
`forward.validate`) unless it claims it.

| Arkt item | Key | Today | Engine configuration | `EngineCommand` / disposition | Reserved |
|---|---|---|---|---|---|
| Quit Arkt Shell | Cmd-Q | `terminate:`, nil target | `terminate:` to `NSApp`, tag `IDC_EXIT` | none (`BrowserCrApplication` -> quit seams; run B) | yes |
| New Tab | Cmd-T | `ShellWindowController.newTab:` | shell (command bar); the host also claims `.newTab` | `.newTab` claimed | yes |
| Open Command Bar | Cmd-L | `openLocation:` | shell | none | yes |
| Archive Tab | Cmd-W | `closeTab:` | shell archive, then `closeTab(_:mode: .honourUnloadHandlers)` (decision 6); the host claims `.closeTab` | `.closeTab` claimed | yes |
| Import from Arc... | - | `AppDelegate.importFromArc:`, nil target | composition root's menu target | none | no |
| Undo, Redo, Cut, Copy, Paste, Select All | Cmd-Z, Shift-Cmd-Z, X, C, V, A | AppKit selectors, nil target | unchanged: the responder chain reaches the page's `RenderWidgetHostViewCocoa` or the shell's text views | none | no |
| Show / Hide Toolbar | Shift-Cmd-D | `toggleToolbar:` | shell | none | no |
| Split View items (`SplitMenu`, 13) | Ctrl-Shift-=, -, ], [, 1-4 | `ShellWindowController` split actions | shell; panes use `createTab(url:in:)` and `activateTab` | none | no |
| Next / Previous Space | Cmd-Opt-Right / Left | `nextSpace:` / `previousSpace:` | shell | none (Chromium binds these keys to select next/previous tab, reserved there) | yes |
| Space 1-9 | Ctrl-1...9 | `goToSpace:` (submenu tags 0-8, harmless: not top level, far below `IDC_` values) | shell | none | no |
| Delete Space... | - | `deleteSpace:` | shell | none | no |
| Show Archive | - | `AppDelegate.showArchive:`, nil target | composition root's menu target | none | no |
| *add* New Window | Cmd-N | - | shell (`ShellWindowController` first, then `createWindow(host:)`, decision 4); the host claims `IDC_NEW_WINDOW` (34000) | claimed | yes |
| *add* Close Window | Shift-Cmd-W | - | shell: `performClose:` on `ShellWindow` -> `onCloseRequested` | none (`performClose:`) | yes |
| *add* Reload / Force Reload / Stop | Cmd-R / Shift-Cmd-R / Cmd-. | - | page command | `.reload`, `.reloadBypassingCache`, `.stop` (named in #272) | no |
| *add* Back / Forward | Cmd-[ / Cmd-] | - | page command (Cmd-Left / Cmd-Right are not menu keys: a menu item would steal them from text fields; gap below) | `.back`, `.forward` | no |
| *add* Find / Find Next / Find Previous | Cmd-F / Cmd-G / Shift-Cmd-G | - | page command (find bar is #134; until then Chromium's) | `.find`, `.findNext`, `.findPrevious` (named in #272) | no |
| *add* Jump to Selection | Cmd-J | - | `centerSelectionInVisibleArea:`, nil target (the page view) | none | no |
| *add* Actual Size / Zoom In / Zoom Out | Cmd-0 / Cmd-+ / Cmd-- | - | page command | `.zoomReset`, `.zoomIn`, `.zoomOut` | no |
| *add* Save Page As / Print | Shift-Cmd-S (Arc) / Cmd-P | - | page command | `.savePage`, `.print` | no |
| *add* View Source / Developer Tools / Inspect Elements / JavaScript Console | Opt-Cmd-U / I / C / J | - | page command | `.viewSource`, `.devTools`, `.inspect`, `.console` (named in #272) | no |
| *add* History / Downloads | Cmd-Y / Shift-Cmd-J | - | page command | `.history`, `.downloads` | no |
| *add* Enter Full Screen | Ctrl-Cmd-F | - | `toggleFullScreen:`, nil target (window) | none | no |
| *add* Minimize / Zoom / Bring All to Front | Cmd-M / - / - | - | `performMiniaturize:` / `performZoom:` nil target; `arrangeInFront:` to `NSApp` | none | no |
| *add* About / Settings / Hide / Hide Others / Show All / Services | - / Cmd-, / Cmd-H / Opt-Cmd-H / - / - | - | About and Hide items to `NSApp`; Settings to the composition root's target (never a nil-target `showPreferences:`, which AppController answers with Chromium's settings) | none | no |
| *add* hidden Bookmarks placeholder | - | - | tag `IDC_BOOKMARKS_MENU`, empty submenu, `hidden` | none | - |
| *dropped* | | | Chromium's New Incognito Window (#115), Reopen Closed Tab (until Arkt has one), Open File, Clear Browsing Data, Import Settings, Bookmarks items, Tab menu, Profiles menu, Cast, Search the Web, Use Selection for Find (Cmd-E is Arc's), Warn Before Quitting, Task Manager, Extensions page (the sidebar Extensions control is Decision 10) | | |

**Reserved keys** (Arkt handles them before the page sees them): Cmd-T, Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q,
Cmd-Opt-Right, Cmd-Opt-Left. They are the Arkt items whose keys Chromium reserves for the same purpose (new tab, close
tab, close window, new window, exit, select next/previous tab), plus Cmd-L, which Chromium does not reserve but Arkt
must (Arkt has no in-window location field to fall back on; Arc's behaviour is a runtime check). When Arkt adds
Reopen (Shift-Cmd-T), the tab switcher (Ctrl-Tab, Ctrl-Shift-Tab) or Incognito (Shift-Cmd-N), they join the set;
nothing else is reserved, so pages keep Cmd-S, Cmd-D, Cmd-Z and the rest, as in Chrome.

Where: **`ShellWindow.performKeyEquivalent(with:)`, before `super`**, not
`ArktBrowserWindow::PreHandleKeyboardEvent` as Decision 9 proposed. That is where Chromium reserves on macOS (the
window's command dispatcher runs before the first responder). `PreHandleKeyboardEvent` runs inside
`RenderWidgetHostImpl::ForwardKeyboardEventWithCommands` for that very event (`render_widget_host_impl.cc:1912-1923`)
with `RenderWidgetHostViewCocoa -keyEvent:` still on the stack, and an Archive or Close Window from there would destroy
the `WebContents` under both; the window-level check also covers the FakeEngine build. Not matched: a page holding
the Keyboard Lock API in full screen (Chromium lets such a page have reserved keys, `isKeyLocked:`); recorded, not
handled this week. So the engine needs no change for reserved keys, and `PreHandleKeyboardEvent` keeps returning
`NOT_HANDLED`.

**Engine-side changes needed for Arkt's menu: none.** The menu works in the Engine configuration with the conditions
above, all on the shell side. Gaps recorded for later (not menu blockers): Cmd-Left / Cmd-Right as Back / Forward
(KB-031, KB-032) after the page declines them would need `ArktBrowserWindow::HandleKeyboardEvent` to run
`DelayedWebContentsCommandForKeyEvent`'s commands (overlay only, needs a key-input check); the six `EngineCommand`
constants named above went into `EngineAPI` with #272 (the frozen-API change both lanes approve; W3-1 froze it), so
nothing uses `EngineCommand(rawValue:)` for them anymore.

### The probe (`--arkt-menu-probe`)

Self-test embedder only (`arkt_selftest_embedder.{h,mm}`, active with `--arkt-facade-selftest`, never in the app).
With the switch, the embedder waits for `NSApplicationDidFinishLaunchingNotification`, defers one turn, replaces the
main menu with an Arkt-shaped one (App menu with Quit tagged `IDC_EXIT`, `terminate:` to `NSApp`; File with Archive
Tab Cmd-W, Close Window Shift-Cmd-W and New Tab Cmd-T, all targeting the embedder with tag 0; Window), and becomes
ready. Options: `filetag` tags File `IDC_FILE_MENU`, `bookmarks` adds the hidden placeholder. The page command
`menu-check` resolves Cmd-W, Shift-Cmd-W, Cmd-Q and Cmd-T with `cr_menuItemForKeyEquivalentEvent:` (so AppController's
pre-search block runs) and logs each item, the command `MenuCommandForKeyEvent` would derive, and the menu state.

All runs: `out/Spike` `Chromium.app`, `--no-startup-window --arkt-facade-selftest`, fresh profiles
`$PROF/w3-8-{a,b,c}`, ports 9511-9513, one at a time, stopped by PID; `menu-check` through CDP (page title); the only
input was activating the app (run A, B) and one AX click on Quit (run B), after the frontmost check.

| Run | Options | Result |
|---|---|---|
| A | none | menu installed after launch (Chromium's File delegate was AppController); `menu-check`: Cmd-W -> "Archive Tab" `tag=0 action=menuProbeArchive:`, Shift-Cmd-W -> "Close Window", Cmd-Q -> "Quit Arkt Probe" `command=34031`, Cmd-T -> "New Tab"; File items unchanged after the search. On activation, `FATAL ... bookmark_menu_bridge.mm:62] Check failed: menu_root_.` from `windowDidBecomeMain:` -> `setLastProfile:` |
| B | `bookmarks` | activation: no crash; placeholder `hidden=yes submenu replaced=yes delegate=set`; `menu-check` as run A; AX Quit: `quit started`, `engineWillBeginTerminating`, `tabClosed ... reason=appTerminating`, `windowClosed`, `engineWillTerminate` (the process then stays up with the CDP port and `--no-startup-window`, Chromium's `REMOTE_DEBUGGING` keep-alive, as in W3-3; stopped by PID) |
| C | `filetag,bookmarks` | `menu-check`: Cmd-W and Shift-Cmd-W resolve to no item; File now "Close Tab" `key=w tag=34015 action=commandDispatch:` and "Close Window" `key=W tag=34012 action=performClose:` |

Also logged in every run: after the swap `NSApp.servicesMenu` and `NSApp.helpMenu` are not in the main menu,
`windowsMenu` is (the probe set it).

Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome`, incremental (the self-test embedder and the framework link),
`The build has finished successfully.`; `/` had 6.3 GiB free and swap 8.6 GB used before and after. No `Chromium`
process left afterwards.

## W3-7 A and B: the Arkt window as the engine's window host

Date 2026-10-24. Branch `engine/33-w3-7-shell-host` off `main` at `0710668`, Swift lane (assigned by the maintainer
on 2026-10-24). Swift only: no engine worktree, `$CR` not touched; no `EngineAPI`, `Package.swift` or `App/Engine/`
change. Parts C (start and quit, after W3-3's gate) and D (menu, after W3-8) are not in it.

### Part A: hosting

- **`ShellEngineHost`** (`ShellUI/Window/ShellEngineHost.swift`) is the `EngineWindowHosting` of a
  `ShellWindowController` (`controller.engineHost`): `window` is the `ShellWindow`, `cardView` the content card. A
  separate object rather than a conformance on the controller, because `NSWindowController.window` is optional and the
  protocol's is not. It holds the controller weakly. `ChromiumEngine` (W3-6) receives `controller.engineHost`.
- **Engine window on the first tab** (decision 4). `openEngineTab` calls `createWindow(host:)` once, then
  `createTab(url:in:)` for every tab, so no ShellUI call uses the window-less form; the `CreateTabLintTests` allowance is
  removed. A window that never showed a tab has no engine window and closes as before.
- **Commands.** `ShellWindow` implements `commandDispatch:` and `commandDispatchUsingKeyModifiers:` (sender tag =
  `EngineCommand` id; the second maps Cmd, Cmd-Shift and Shift to `newBackgroundTab`, `newForegroundTab`, `newWindow`
  as `ui::DispositionFromEventFlags` does) and validates them in `validateUserInterfaceItem`. The shell claims
  `.newTab` (command bar) and `.closeTab` (archive or close the current tab; enabled with a current tab); every other
  command goes to the engine's `forward`, and is disabled while the window has no engine window. The rest of the W3-8
  table joins with part D.
- **Close button.** `windowShouldClose` reports the shown tabs hidden (decision 10, the `lastActiveAt` stamp, as
  `prepareForTermination` does before quit), calls `onCloseRequested` and answers false; the window closes when its
  `.windowClosed` arrives. A held prompt keeps the window, a cancelled one keeps it and its rows. A tab the engine opens
  while the window's close is held is closed without a row.
- **Extensions control** (`ShellUI/Sidebar/ExtensionsButton.swift`): a bottom-bar button left of New Tab, present only
  when `engine is EngineExtensions` (not for FakeEngine). It lists the window's `extensionActions(in:)` in a native
  menu (icon, name, enabled state), is disabled with none, refreshes on `.extensionActionsChanged`, and runs an action
  with itself as anchor. No animation of its own.

### Part B: tabs

- **Per-window routing.** A window observes its engine window only (`observe(window:)`, `observeWindows` filtered by
  id) from the moment the window exists; the global observer is gone.
- **Engine tabs** (`origin == .engine`, unmapped) become Today tabs in the window's current Space (a placeholder
  `about:blank` until the first `.urlChanged`), and are shown when the engine makes them active. A tab the sidebar
  refuses is closed with `.skipUnloadHandlers`, so no live tab is left without a row.
- **Activation.** `currentTab` drives `activateTab` (the focused pane in a split too); an engine activation of another
  tab selects its row. After the engine's active tab closes, the engine's own pick is not followed (the shell picks
  the successor, as before) and is answered with the shell's tab (`expectsEngineReactivation`). In-process engines
  report their pick after the shell's own activation, Chromium one task later, and no engine reports a pick that is
  already the active tab, so the expectation also lapses after 1 s (`reactivationGrace`, [I]); an engine activation
  inside that second (an extension's `chrome.tabs.update` right after a close) is answered with the shell's tab.
- **Close reasons** (Decision 12). `.windowClosing` and `.appTerminating` only unload: no sidebar write, nothing else
  shown or created (a closing window never gets a new tab); the stamps happen before the closes (close button,
  `prepareForTermination`), so the tests compare the stored sidebar byte for byte with the app's `markInactive` wiring.
  A window the engine closes on its own (`chrome.windows.remove`) stamps nothing. `.page` and `.extension` archive a
  Today row once and leave a Pinned or Favorite row unloaded (maintainer question: Decision 12 can be read as removing
  those rows too). `.client` is what the shell asked.
- **Held closes** (Decision 11). Cmd-W and the row X close the pages first with `.honourUnloadHandlers` and archive a
  Today node only after its last page reported `.tabClosed` (`pendingArchives`, registered before the first close
  since an unheld close reports synchronously); a split row archives once all its panes closed. While held the row is
  dimmed (`SidebarController.closingNodes`, opacity 0.45, no X, accessibility value "Closing", no animation) and its
  page stays mounted; `.closeCancelled` keeps the tab and drops the archive; another Cmd-W while held does nothing.
  Rows removed by anything else (auto-archive, Delete Space, an import merge) close their pages with
  `.skipUnloadHandlers`: no prompt can belong to a row that is gone. A row removed while its prompt is up: a
  cancelled prompt then closes the page the same way, an accepted one archives nothing more. Clicking another row
  while a prompt is up shows that row's page; the held page, its prompt and the dimmed row stay until the user comes
  back (accepted; the prompt is tab-modal on the held page).
- **Auto-archive** skips `nodesHoldingClose` (tabs with `wouldHoldClose` or `isClosing`, and their split) through
  `AutoArchiveTimer.exempt`, re-read every pass; CoreBridge is unchanged.
- **Engine-initiated windows.** `ShellWindowController(..., opensFirstTab: false)` builds a window without calling the
  engine (for a host provider) and `adopt(engineWindow:)` attaches it once its `.windowOpened` arrived, turning the
  engine's tabs in it into Today tabs. The engine does not tell a host its id, so the provider's owner pairs hosts with
  `.windowOpened` in order; that pairing is part C's composition root (the test pairs them itself).
- **#241.** `applicationShouldTerminateAfterLastWindowClosed` is false; a Dock click with the browser window closed or
  minimized brings it back (`AppSession.reopenWindow`, a new controller when the old one closed, wired like the first,
  its favicons reloaded). The import summary and the restore and import toasts build the window again first when it
  was closed, so they are never shown in a closed window.

### Verification

`nice -n 10`, `-j 4`, scratch and derived data under `/Volumes/SSD_2/arkt-chromium/arkt-shell-dd/w3-7`.

- Rebased on `main` at `01e68c3` (W3-6 #267, #270). ShellKit `swift test --skip ShellKitGUITests`: 536, all pass
  (537 on `main` minus the removed known-issue lint test).
- ShellKit `--filter ShellKitGUITests`: 413 (383 + 30 new in `EngineHostingTests.swift`: 10 hosting, 17 routing, 3
  Extensions), 6 skipped, 0 failures. Before the rebase one full run failed
  `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` (2 frames over 8.6 ms, 1-minute load 23.7 with another
  lane building); alone it then passed 6 of 7 here, and `main` at `0710668`, run interleaved under the same load,
  hitched the same way once in 7 (`space-key`, 9@20.97 ms). Load, not this change.
- ArktCore `swift test`: 349, all pass.
- Debug app (`xcodegen generate`, `xcodebuild -configuration Debug`): `BUILD SUCCEEDED`. Not launched.
- Checked to fail: dropping the reactivation guard fails `testTheEnginesPickAfterAClosedTabIsNotFollowed`, never
  letting it lapse fails `testAnEngineActivationIsFollowedAfterAgreeingSuccessors`; archiving before the close fails
  the held and cancelled Cmd-W tests; not closing a cancelled tab whose row is gone, and giving engine tabs a row while
  the window close is held, fail their tests.
- Reviewed in a separate pass; its two high findings (the reactivation expectation that could stay set, a live tab
  left after a cancelled prompt whose row was removed) and three medium ones are fixed above with tests.

### What part C and W3-9 need

- Part C: the composition root's `windowHostProvider` builds `ShellWindowController(..., opensFirstTab: false)`,
  returns `engineHost`, and pairs pending controllers with `.windowOpened` in order (calling `adopt(engineWindow:)`),
  skipping ids of windows the shell created itself; `AppSession.reopenWindow` then becomes the composition root's job
  (with the Chromium engine a Dock reopen arrives as a `.reopen` request instead of `applicationShouldHandleReopen`).
- W3-9: `ChromiumEngine` delivers `.activeTabChanged` one task later; the reactivation guard expects at most one
  engine pick within `reactivationGrace` after the active tab closes; W3-9 checks that on the real engine. Engine-initiated
  held closes (a page or extension close that holds) show no closing state, as no event announces them.
- The Favorites grid shows no closing state for a held Favorite (the page stays, the tile is unchanged).

## W3-6: ChromiumEngineKit over the facade

Date 2026-10-24. Branch `engine/33-w3-6-chromiumenginekit` off `main` at `0710668`. Swift only: no Chromium build, no
engine worktree, `$CR` not touched, no app launch; the facade header is unchanged. Builds at `nice -n 10`, `-j 4`,
scratch and derived data on the Chromium disk.

### What landed

- **`ChromiumEngineKit`** (ShellKit target and product; `internal import ArktEngineABI`, so no facade type is part of
  its public API). `ChromiumEngine: EngineClient, EngineExtensions` over `any ArktEngine`:
  - Decision 4: `createTab(url:in:)`, `duplicateTab` and `createWindow(host:)` announce `.tabCreated` /
    `.windowOpened` before they return, and a close the facade answers `closed` emits `.tabClosed(reason: .client)`
    at once; the facade's later `TabCreated`, `WindowOpened` and `TabClosed` for those calls are dropped (a retired
    handle is released by the facade's own `TabClosed`). A close answered `held`, a deferred insert that never
    happens and every engine-started close are forwarded from the facade with its reason.
  - Tables from events (url, title, favicon, loading, history flags, window, opener, origin, activation), updated
    before each event is emitted. `isClosing`, `wouldHoldClose` and the history entries have no facade event and are
    read from the handle. `EngineEventHub.assign(_:to:)` runs before every `.tabCreated` (with the window the caller
    named, as a deferred handle has no browser yet) and on every `TabMoved`.
  - Batches: within one batch, a title or favicon clear the facade recorded after the same load's end is delivered
    before it (rules 2 and 6, Risk 2); nothing moves across batches. Handlers may call back into the engine; the rest
    of the batch drops events for a tab closed meanwhile.
  - Windows: `EngineWindowHosting` is wrapped in an `ArktWindowHost` object (`WindowHostAdapter`); the facade's
    blocks become the host's `onCloseRequested` and `forward`, and `forward` asks the host's claims first, then the
    engine (`IDC_*` and `WindowOpenDisposition` raw values passed through). Engine-initiated windows: the facade's
    `-hostForEngineWindowRequest:` goes to `windowHostProvider` (an `EngineWindowRequest`, opener mapped when it is
    this instance's window); the window is listed and announced when the facade's `WindowOpened` names that host.
    A closed window leaves its host no engine closures.
  - Instance scoping: an instance lists only the windows it created or got through its provider, and their tabs;
    a tab moved into another instance's window ends with `.tabClosed(reason: .extension)` here and is adopted there.
    `createTab(url:)` with no window is a precondition failure (tested as an exit test).
  - `EngineExtensions` over `extensionActions(in:)` / `runExtensionAction`, `.extensionActionsChanged` from the
    facade. `host(of:)` returns a window's host. Test API for W3-9's runner, which cannot see the header:
    `testAPIEnabled`, `evaluateScript(_:in:userGesture:) async throws -> ScriptValue?`, `answerDialog(in:accept:)`.
  - The event sink is removed when the instance is released (`isolated deinit`).
- **Typed `@objc(ArktShellEmbedder)`** (moved from `App/Engine/`, decided 2026-10-24): `ArktEngineEmbedder` in
  `ChromiumEngineKit`, driven by a `ChromiumEmbedderDelegate` (`start(engine:) async throws`, `startFailed`,
  `host(for:in:)`, the three quit seams). `-engineDidStart:` makes the `ChromiumEngine`, runs `start`, then
  `embedderReady`; a throwing start calls `embedderFailed` and then `startFailed` from a run-loop callout
  (`RunLoop.main.perform(inModes: [.common])`, never a modal from a main-actor job). `-engineWillTerminate:` calls the
  completion after the delegate's flush. `ChromiumEmbedding.install(_:)` (called by `engineMain()` before
  `ChromeMain`) references the class: the dead-strip safeguard. `ChromiumEmbedding.makeEngine()` gives a further
  instance over the same facade (the runner).
- **App** (`App/Engine/`, Engine configuration only): `FacadeStandIn.swift` and the app's `ArktShellEmbedder.swift`
  are gone. `StandInShell.swift` is the delegate until W3-7 part C and W3-9: the 2 s simulated start (and
  `--arkt-embedder-fail`), plain windows for engine window requests that mount the active tab's container, logged quit
  seams and a 300 ms simulated flush. `ReentrancyProbe.swift` drives `ChromiumEngine` instead of selectors.
  `project.yml` gains the `ChromiumEngineKit` product for the app target.
- **Tests** (`ChromiumEngineKitTests`, plain `swift test`, no Chromium): a scripted facade (`ScriptedFacade.swift`)
  that records plain-value events and delivers one batch on the next main-actor turn, holds closes on a
  `beforeunload` page, defers calls while "nested" (pending handle, `held`), and answers the drivers' scripts through
  the test API. The harness's `makeEngine` creates the instance's window first; drivers: `retitle`, `holdClose` and
  `engineCreateTab` (with an opener) through `evaluateScript`, `answerDialog` through the test API,
  `engineCloseTab` and `engineActivate` as an extension would. Every `EngineContract` check runs twice: Chromium's
  event order and title/favicon-clear after the load end.
- **Isolation** (`ChromiumEngineKitIsolationTests`): only `App/Engine/` and the kit's tests import
  `ChromiumEngineKit`, every app importer starts with `#if ARKT_CHROMIUM_ENGINE`, and only `ChromiumEngineKitTests`
  depends on it in `Package.swift`. `EngineABIIsolationTests` unchanged and passing (the kit is its allowed importer).

### Contract results

| Rules | Checks | Chromium order | Title after load end |
|---|---|---|---|
| 1-10 | 14 | pass | pass |
| 11 | `windowIsListedAndAnnounced`, `closeWindowClosesItsTabsThenReportsWindowClosed`, `hostCloseRequestClosesTheWindow` | pass | pass |
| 12 | `activationIsOneTabPerWindow` | pass | pass |
| 13 | `engineCreatedTabIsAnnounced` | pass | pass |
| 14 | `engineCloseIsTerminal` | pass | pass |
| 15 | `windowlessCreateTabLandsInMostRecentlyActiveWindow` | pass | pass |
| 16 | `heldCloseKeepsTheTabUntilAnswered`, `skipUnloadHandlersNeverHolds`, `cancelledWindowCloseKeepsTheWindow` | pass | pass |

16/16 rules, 24 checks x 2 = 48 cases, none not applicable (`everyDriverIsPresent`; `everyContractCheckIsListed` reads
the check names from `EngineContract`'s sources). Scripts beyond the contract (`ChromiumEngineScriptTests`, 16): batch
reordering and its bound, Decision 4 deduplication, a second close while held, deferred calls behind a pending insert,
a deferred insert into a closed window, contents replacement (same container and ID, new session id), moves between
own and foreign windows, a provider window listed only after `WindowOpened`, two instances over one facade, the
window-less precondition (exit test), sink removal, host claims before forwarding, extension actions, quit
(`.appTerminating`), the test API. Embedder (`ArktShellEmbedderTests`, 4): lookup by runtime name and protocol
conformance, ready after start, window requests to the delegate, a failed start, the quit seams. Checked to fail:
without the reordering, both reorder-mode contract cases for rules 2 and 6 and the reorder script fail.

### Verification

- ShellKit `swift test --skip ShellKitGUITests`: baseline 509 (W3-1), now **537** (509 + 28: ChromiumEngineKitTests
  23 with the contract as one parameterized test of 48 cases, IsolationTests 23 to 28), all pass, 1 known issue (the
  W3-1 lint allowance). GUI tests not run: no ShellUI or other GUI-visible file changed.
- ArktCore `swift test`: 349, all pass.
- Debug app (`xcodegen generate`, `xcodebuild -configuration Debug CODE_SIGNING_ALLOWED=NO`): `BUILD SUCCEEDED`;
  `NSPrincipalClass` `NSApplication`; `strings` counts 0 `ARKT engine` in each binary; no `Contents/Frameworks`.
  The Debug app now links the `ChromiumEngineKit` product (one dependency list per target), unreferenced:
  `ArktShell.debug.dylib` exports its Swift symbols and contains the `ArktShellEmbedder` class, which nothing in
  Debug looks up (only the engine's hook does).
- Engine configuration (build only, into a scratch directory on the Chromium disk, `ARKT_ENGINE_APP` =
  `out/Spike/Chromium.app` read-only; `$EMB` not written): `BUILD SUCCEEDED`, `Engine framework copied`, the three
  Info.plist keys, framework CDHash equal to `out/Spike`'s (not re-signed). `nm -u <app binary> | grep -cF
  '_OBJC_CLASS_$_Arkt'` prints `0`; `nm -m` shows `(__DATA,__objc_data) non-external _OBJC_CLASS_$_ArktShellEmbedder`
  (internal Swift class; the hook uses `NSClassFromString`, which the embedder test checks in-process).

### What W3-7 and W3-9 need

- W3-7 part C: `AppComposition` adopts `ChromiumEmbedderDelegate` (or `StandInShell` forwards to it):
  `start(engine:)` is `AppComposition.start(engine:windowHostProvider:)`, `host(for:in:)` builds a
  `ShellWindowController`, `startFailed` shows the launch-failure alert and quits through the engine
  (`chrome::AttemptExit()` has no facade call yet; the header needs one, or the shell keeps `NSApp.terminate` under
  Chromium's `terminate:`), `engineWillBeginTerminating` / `engineWillTerminate` are `prepareForTermination()` /
  `flush()`.
- W3-9: replace `StandInShell` in `EngineMain.swift`; the runner gets instances from `ChromiumEmbedding.makeEngine()`
  (each creates its window first) and drives `holdClose`, `retitle`, `window.open` and `answerDialog` through
  `ChromiumEngine`'s test API; `engineCloseTab` / `engineActivate` need the tabs probe extension. On the real facade,
  a client tab without a URL may report about:blank loading events after `TabCreated`, which rule 2's order check
  (first `loadingChanged(true)`) would see; the scripted facade models the initial about:blank without a load.

## W3-1: EngineAPI additions and contract rules 11-16

Date 2026-10-24. Branch `engine/33-w3-1-engineapi` off `main`. Taken by the engine lane (maintainer decision on #33,
2026-10-24). Swift only: no Chromium build, no engine worktree, `$CR` not touched; the facade header is unchanged.

### API (names settled here; W3-6 maps them onto the frozen header)

| Area | `EngineAPI` | Header counterpart |
|---|---|---|
| Windows | `EngineWindowID`; `windowIDs`; `createWindow(host:) -> EngineWindowID` (synchronous); `closeWindow(_:)` | `ArktEngine.browsers`, `createBrowser(host:)`, `ArktBrowserHandle.close` |
| Window events | `observeWindows(_:)` with `EngineWindowEvent` `.windowOpened`, `.windowClosed`, `.extensionActionsChanged` | `WindowOpened`, `WindowClosed`, `ExtensionActionsChanged` |
| Per-window routing | `observe(window:_:)`: events of tabs in that window at emit time, `.tabCreated` and `.tabClosed` included | `ArktEngineEvent.browser` |
| Tabs | `createTab(url:in:)`; `createTab(url:)` lands in the most recently active window (rule 15), or has no window when the engine has none (in-process engines only) | `createTab(url:active:)` |
| Closes | `closeTab(_:mode:)` with `CloseMode` `.honourUnloadHandlers` (what `closeTab(_:)` does) and `.skipUnloadHandlers`; a second close while held does nothing | `close(mode:)`, `ArktCloseResult` |
| Close reasons | `.tabClosed(TabID, reason: CloseReason)`: `.client`, `.page`, `.extension`, `.windowClosing`, `.appTerminating` | `ArktCloseReason` |
| Activation | `activateTab(_:)`, `activeTab(in:)`, `.activeTabChanged(TabID)`; the first tab of a window is active, later client tabs leave it alone, closing the active tab activates its right neighbour (else the left) | `activate`, `ActiveTabChanged` |
| Held closes | `.closeCancelled(TabID)`; `TabSnapshot.isClosing`, `.wouldHoldClose` | `CloseCancelled`, `isClosing`, `wouldHoldClose` |
| Snapshot | `window`, `opener`, `origin` (`TabOrigin` `.client`, `.engine`), `isActive`, `isClosing`, `wouldHoldClose`, all defaulted | `ArktTabHandle` properties |
| Hosting | `EngineWindowHosting` (`window`, `cardView`, `claim(_:) -> CommandClaim?`, `perform(_:disposition:) -> Bool`, `forward: EngineCommandForwarding?`, `onCloseRequested`); every member is required, as `createBrowser(host:)` CHECK-fails on a host missing one | `ArktWindowHost` (`closeRequested`, `validateCommand`, `executeCommand`) |
| Requests | `EngineWindowRequest` (`kind` `.extension`, `.page`, `.reopen`, `.startupURL`; `openerWindow`, `bounds: CGRect?`, `profile: EngineProfileID`, `initialURL`); `EngineWindowHostProvider`. `.page` is unused this week: a page's new window reports `.reopen` (W3-4) | `ArktWindowRequest` |
| Commands | `EngineCommand` and `EngineDisposition`, `RawRepresentable` over `Int` with the values of "W3-0", Step 5 (names unchanged, so that table is the check; `InMemoryEngineWindowTests.commandConstantsMatchChromiumIDs` pins the values) | `IDC_*`, `WindowOpenDisposition` |
| Extensions | `EngineExtensions` (separate protocol): `extensionActions(in:) -> [ExtensionAction]` (`id`, `name`, `iconPNG`, `isEnabled`), `runExtensionAction(_:in:anchor:)`. `InMemoryEngine` adopts it, FakeEngine does not | `extensionActions(in:)`, `runExtensionAction(_:in:anchor:)` |

`EngineEventHub` keeps one non-reentrant FIFO for tab and window events (a window's `.windowClosed` follows its tabs'
`.tabClosed`, nothing follows `.windowClosed`), and routes per window by `assign(_:to:)`, which an engine calls before a
tab's `.tabCreated` and on a move. The window is read when the event is emitted, so a filtered observer still gets the
`.tabClosed` of a tab whose snapshot is gone.

### Contract rules 11-16 and drivers

`EngineHarness` gains `makeWindowHost` (default `StubWindowHost`, whose window is built only on first use) and the
optional drivers `engineCreateTab`, `engineCloseTab`, `engineActivate`, `holdClose`, `answerDialog`. A rule whose driver
is nil throws `ContractNotApplicable`; the FakeEngine XCTest runner turns it into a skip, so it is never reported as
passed. Rules 11-16 wait for events and snapshot values (the Chromium engine delivers most events one task later).

| Rule | Checks | InMemoryEngine | FakeEngine |
|---|---|---|---|
| 11 | `windowIsListedAndAnnounced`, `closeWindowClosesItsTabsThenReportsWindowClosed`, `hostCloseRequestClosesTheWindow` | pass | pass |
| 12 | `activationIsOneTabPerWindow` | pass | pass |
| 13 | `engineCreatedTabIsAnnounced` | pass | skipped (no driver) |
| 14 | `engineCloseIsTerminal` | pass | skipped (no driver) |
| 15 | `windowlessCreateTabLandsInMostRecentlyActiveWindow` | pass | pass |
| 16 | `heldCloseKeepsTheTabUntilAnswered`, `skipUnloadHandlersNeverHolds`, `cancelledWindowCloseKeepsTheWindow` | pass | skipped (no driver) |

Checked to fail: an `InMemoryEngine` that never reactivates after closing the active tab, puts window-less tabs in the
first window, or closes a window without holding fails rules 12, 15 and 16 respectively. "Most recently active window"
is the last window that got `createWindow`, `createTab(url:in:)` or an activation (client or engine).

`InMemoryEngine` test drivers for W3-7: `engineCreateTab(url:in:opener:active:)`, `engineCloseTab(_:reason:)`,
`engineActivate`, `holdClose`, `answerDialog(_:accept:)`, `openEngineWindow(_:)` with `windowHostProvider`,
`setExtensionActions(_:in:)`, `host(of:)`, and the records `executedCommands` (commands forwarded by a host) and
`ranExtensionActions`. A cancelled window close reports `.closeCancelled` for every held tab of that window;
`wouldHoldClose` stays true after a cancel (the handler stays registered).

### Non-additive changes

- `.tabClosed(TabID)` became `.tabClosed(TabID, reason:)`, and `EngineEvent` gained `.activeTabChanged` and
  `.closeCancelled`. Call sites: `EngineEvent.tabID`, `EngineEventHub`, the contract's rule 4 checks, and in ShellUI
  only `ShellWindowController.handle(_:)` (`.tabClosed(let tab, _)`; its `default:` covers the new cases). No
  behaviour change: routing by reason, `observe(window:)` and activation are W3-7. CoreBridge and App had no match.
- `EngineClient` gained requirements (windows, `createTab(url:in:)`, `closeTab(_:mode:)`, activation, both observe
  forms), so the `EagerEngine` test double in `ShellKitGUITests/SidebarViewTests.swift` forwards them.
- `EventRecorder` records window events too (`log`, `windowEvents`); `events` is unchanged for callers.

### Lint test

`ShellUITests/CreateTabLintTests` fails on any ShellUI call to the window-less `createTab(url:)`. The one existing call
(`ShellWindowController.openEngineTab`, which W3-7 moves) is held as a known issue (`withKnownIssue`), so the test
turns red once W3-7 removes it and the allowance can be dropped.

### Verification

`nice -n 10`, `-j 4`, scratch and derived data on the Chromium disk.

- ShellKit `swift test --skip ShellKitGUITests`: baseline 481 (`main` at `3b8df3a`), now **509** (481 + 28: EngineAPITests
  24 to 48, ShellUITests 208 to 212 with 1 known issue), all pass.
- ShellKit `--filter ShellKitGUITests`: 383 tests, 5 skipped (FakeEngine rules 13, 14, 16), 1 failure,
  `SidebarReviewTests.testAccessibility` (`SidebarViewTests.swift`, the divider's `isAccessibilityElement`), which fails
  the same way on `main` at `3b8df3a` on this machine; not touched here. The FakeEngine contract suite: 27 tests, 5
  skipped, 0 failures.
- ArktCore `swift test`: 349, all pass (unchanged).
- Debug app (`xcodegen generate`, `xcodebuild -configuration Debug`): `BUILD SUCCEEDED`; `NSPrincipalClass` is
  `NSApplication`; `strings` on the binary counts 0 `ARKT engine`.

### What W3-6 and W3-7 can start

- W3-6: `ChromiumEngine: EngineClient, EngineExtensions` over the facade, run against the scripted facade with all five
  drivers (the scripted facade answers `holdClose` and `answerDialog` like the test API). It emits through
  `EngineEventHub` and calls `assign(_:to:)` from each tab handle's `browser`.
- W3-7 parts A and B: `ShellWindowController` as `EngineWindowHosting`, `createTab(url:in:)` at `openEngineTab` (then
  drop the lint allowance), `observe(window:)`, closes by reason, held closes and `.closeCancelled`, auto-archive on
  `wouldHoldClose`, all against `InMemoryEngine`'s drivers; the Extensions control against `InMemoryEngine` as an
  `EngineExtensions`.

## #9: Web identity (user agent and client hints)

Date 2026-10-24. Branch `engine/9-chrome-ua` off `main` at `e3971d0`. `$CR` branch `arkt` at `e4a2ca5cca` (0001-0007)
before and after: no patch, no overlay change, no build. Checked on the existing `$OUT` build (`Chromium.app`,
`Chrome/156.0.8078.48`, built from the same overlay), fresh profiles, `--use-mock-keychain`, CDP ports 9471/9472, no
`--user-agent`. `out/Arkt` and `/Applications/Arkt.app` were not touched; the release bundle sends the same identity
(W2 Step 3 and W10 Step 2 in the week-2 results recorded the same UA and brands on it).

### What the engine sends (unchanged by this work)

| Surface | Value |
|---|---|
| `User-Agent`, `navigator.userAgent` | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36` |
| `Sec-CH-UA`, `navigator.userAgentData.brands` | `"Not:A-Brand";v="8", "Chromium";v="156"` |
| `Sec-CH-UA-Full-Version-List`, `fullVersionList` | `"Not:A-Brand";v="8.0.0.0", "Chromium";v="156.0.8078.48"` |
| Other hints (after `Accept-CH`) | platform `"macOS"`, platform version `"27.0.0"`, arch `"arm"`, bitness `"64"`, model `""`, mobile `?0`, form factors `"Desktop"` |

No `Arkt` token anywhere. The request headers came from a loopback echo page (a Node `http` server on
`127.0.0.1:9480` that prints the request headers and sends `Accept-CH` for the high-entropy hints); no external echo
service. google.com serves its current page (the search `textarea`, no legacy `input`), with no "Switch to Chrome" promo.

### Where the brand list comes from

`components/embedder_support/user_agent_utils.cc`, `GetUserAgentBrandList`: the product brand is
`version_info::GetProductName()` only when `!BUILDFLAG(CHROMIUM_BRANDING)`; `GenerateBrandVersionList` always adds
`Chromium` and a GREASE brand and shuffles by the major version. `CHROMIUM_BRANDING` is false only with
`is_chrome_branded = true` (`build/BUILD.gn`, `branding_buildflags`), which turns on Google-only code paths and is not
an option. With any custom `BRANDING` file the product name would be `PRODUCT_FULLNAME` ("Arkt"), so the
patch-free knobs (`branding_file_path`, GN args) can only add an `Arkt` brand, never a "Google Chrome" one. The one
embedder seam that sets arbitrary brands is `ContentBrowserClient::GetUserAgentMetadata`, implemented by
`ChromeContentBrowserClient` (`chrome/browser/chrome_content_browser_client.cc`), which the overlay cannot replace
without a patch. Per-tab `WebContents::SetUserAgentOverride` would miss workers and disagree with the default, so it
is not a fix either. Result: a "Google Chrome" brand costs one patch; everything else needed is the upstream default.

### Web Store banner: the brand list is not the trigger

The Web Store detail page for uBlock Origin Lite shows the "Switch to Chrome?" dialog and the "Switch to Chrome to
install extensions and themes / Install Chrome" banner on the stock brands (the "Add to Chrome" button is still there,
and the install itself works: week-2 W7). Experiment, CDP `Emulation.setUserAgentOverride` with the same UA and a
brand list of `Not:A-Brand`, `Chromium`, `Google Chrome` (major and full versions), applied before the first request:

| Run | `Sec-CH-UA` on the document request (not from a service worker) | `navigator.userAgentData.brands` | Banner and dialog |
|---|---|---|---|
| Stock, fresh profile | `Not:A-Brand`, `Chromium` | same | shown |
| "Google Chrome" added, same profile, service workers and cache cleared | `Not:A-Brand`, `Chromium`, `Google Chrome` | same | shown |
| "Google Chrome" added, second fresh profile, first request already carried it | `Not:A-Brand`, `Chromium`, `Google Chrome` | same | shown |

The page scripts loaded at that point read `userAgentData.brands` only for generic library checks; the one literal
`"Google Chrome"` check gates something on versions 115/116, not the banner. The mechanism was not identified further
(it is not the UA and not the brand list). Google consent was answered "Reject all" in the throwaway profiles; no
sign-in, no install. Screenshots are kept locally, not committed.

### Decision

Keep the upstream brands (`Chromium` + GREASE), no "Google Chrome" brand, no patch. Reasons: it would not remove the
banner (above); it costs a patch kept on every rebase; and claiming another vendor's product brand is a different
thing from sending the Chromium identity the engine really has. Sites that test for Chrome (`brands` containing
`Chromium`, or `Chrome/` in the UA) already match. The comparison with the brand list Arc sent could not be made:
nothing is recorded in the repository and Arc itself is not inspected (clean room); the question goes to the
maintainer on #9.

## #258: facade follow-ups from the W3-5 reviews

Date 2026-10-24. Branch `engine/258-facade-followups` off `main` at `3b8df3a`. `$CR` branch `arkt` at `8910b992e4`
(0001-0007) before and after: no patch. Overlay only; the facade header, `app/` and `project.yml` are unchanged. New
dependencies `//mojo/public/cpp/bindings` (`//arkt/api:embedder`) and `//components/constrained_window`
(`//arkt/browser:window`); `gn check out/Spike '//arkt/*'`: `Header dependency check OK`. Build: `nice -n 10 autoninja
-C out/Spike -j 4 chrome`, `The build has finished successfully.`, 0 `FAILED:`. `/` had 7.9 GiB free and swap 8.7 GB
used of 10 GB before each build and run. Runs: fresh profiles `w258-run1`, `-run2`, `-run3`, `-reg`, CDP ports
9491-9494, `--use-mock-keychain`, one GUI run at a time, each stopped by its PID; fixture pages from a loopback server
on `127.0.0.1` and `localhost` (port 8491). The pull requests #256, #257 and #261 carry no inline review comments; the
items below are the #258 acceptance criteria and the four #261 review items added to #258.

### What changed

- **`evaluateScript` always completes.** The reply callback is wrapped with `mojo::WrapCallbackWithDropHandler`: when
  the frame's connection drops the callback unrun (renderer gone, tab closed), the completion is posted with an error
  `The page went away before the script answered` (posted, because the drop runs while the frame is torn down).
- **Kept state dropped by a direct request.** A state kept after a held release with no show (`held state kept until
  shown`) is cleared by a later direct `Maximize`, `Minimize`, `Restore` or fullscreen entry (`DropKeptState`), so a
  later `Show()` no longer applies the older one.
- **History positions.** `backEntries` / `forwardEntries` count from `GetCurrentEntryIndex()` (the pending entry while
  a history navigation is pending), as `GoToOffset` does (`GetIndexForOffset`), and an entry without a valid URL keeps
  its place as `about:blank` (the header's `url` is non-null), so entry *i* is offset `±(i + 1)`.
- **Duplicate.** A deferred duplicate inserts into the window the source is in when the insert runs (it may have moved
  since the call). A duplicate of a pending tab returns a pending handle and queues behind the source's insert like the
  other calls (W3-5b answered nil); if the source's insert is dropped, or the source is closed by an earlier queued
  call, the copy gets its own terminal `TabClosed` (drop handler on the queued call). Pending handles remember the
  window they are for.
- **Inserted flag.** `InsertClientTab` decides "inserted" by whether the facade's insert binding was taken (`EndBinding`),
  not by the handle still having a tab: a tab inserted and closed within the same call gets only the `TabClosed` of its
  removal.
- **Shell anchor.** `runExtensionAction` restores the window's own anchor after the action ran (the popover takes the
  anchor synchronously in `TriggerPopup`), so a later `chrome.action.openPopup` does not anchor to a view the shell
  passed for one call.
- **Icon cache.** `ArktExtensionsMenu` caches each action's rasterized icon per tab (`WebContents` weak pointer),
  dropped on `OnToolbarActionUpdated(id)`, on added, removed, initialized and shutdown, and when the action's icon
  finishes loading (`RegisterIconUpdateObserver`, which also reports `ExtensionActionsChanged`). The facade reuses the
  PNG for an icon backed by the same image.
- **Decision: `ExtensionActionsChanged` fires on active-tab change** in embedder windows that have an actions menu.
  The list's icons and enabled states are for the active tab, so a shell that does not re-list on a tab switch would
  show the previous tab's state. Deduplicated per window per batch as before.
- **Dialogs follow the container** (#261 review, medium). Each `ArktModalDialogHost` observes
  `NSViewFrameDidChangeNotification` of the view it currently resolves (the tab's container in host mode, the card
  otherwise) and repositions its dialogs when the embedder lays the container out anew without a window resize.
- **Claim filter** (#261 review, low). `ClaimNewDialogs` claims only constrained-window widgets
  (`kWidgetIdentifierKey == kConstrainedWindowWidgetIdentifier`).
- **Hidden parent** (#261 review, low). A dialog raised while its window is ordered out or on another Space attaches
  when the window becomes visible: `Show()`, `ShowInactive()`, `NSWindowDidChangeOcclusionStateNotification`,
  `NSWindowDidDeminiaturizeNotification` and `NSWorkspaceActiveSpaceDidChangeNotification` retry the attachment.
  Measured on the way: Chromium does not show such a dialog at all (the manager's delegate checks that the view's
  window is visible), and ordering the window out and in leaves the contents' visibility `visible`, so the manager
  never gets the transition that would show it. The window now replays that transition for the active tab's
  manager (through its `WebContentsObserver` interface, no patch) when the host has a claimed dialog that is not
  shown.
- **Double toggle** (#261 review, low). A second `ToggleExtensionsMenu` before the posted `Show` ran cancels it;
  `CloseExtensionsMenuIfOpen` cancels a posted show too, and `Show` returns at once while the menu is already tracking.
- **Self-test commands** `goto-history <offset>`, `eval-hang`, `layout <inset>`, `hide`, `show`, `pending dup`,
  `pending dup-close`; `actions` logs the PNG object; `--arkt-trace-visibility` also logs window placement changes.

### Acceptance

| Item | Result | Evidence |
|---|---|---|
| `evaluateScript` completes when the page goes away first | PASS | run 1: `eval-hang` (20 s busy loop), tab closed after 2 s: `facade evaluateScript: the page went away before it answered`, `eval hang ... result=nil error=The page went away before the script answered` |
| Kept state cleared by a direct Maximize/Minimize/Restore | by inspection | no scripted path releases a held window without a show; `DropKeptState` in the non-held branches |
| History positions match `goToHistory` offsets | PASS | run 1, below |
| Duplicate of a pending source | PASS | run 1, `pending dup` and `pending dup-close` |
| Deferred duplicate after the source moved windows | by inspection | the facade has no move call to place a move between a deferred call and its task; the insert resolves `source.browser` when it runs |
| One `TabClosed` for a tab inserted and closed in one call | by inspection | not reproducible without a patch; `EndBinding` |
| Shell anchor cleared after `runExtensionAction` | PASS | run 3: `TriggerPopup ... anchor=<call anchor>`, `anchor restored <window anchor> (call anchor <call anchor>)`, `popup loaded` |
| Action icons cached | PASS | run 1: repeated `actions` answer the same PNG objects; a tab switch gives new ones, repeated again the same |
| `ExtensionActionsChanged` on active-tab change | PASS (decision: yes) | run 1: `activate` -> batch `ActiveTabChanged,ExtensionActionsChanged`, both directions |
| Dialog follows a container frame change | PASS | run 1, below |
| Claim only constrained-window widgets | PASS | runs 1, 3: alerts still claimed and attached |
| Dialog raised while the window is hidden | PASS (after the replay fix) | runs 2, 3, below |
| Two toggles before the posted Show | by inspection | two AX presses are two events, the posted task runs between them; the single-toggle open and close still pass (regression launch) |

**Run 1** (`--no-startup-window --arkt-facade-selftest --arkt-engine-test-api`, `tabs-probe`, `action-probe`, port
9491; commands from a control tab on `localhost` with `@<session id>`).

- History: after `a.html`, `b.html`, `a.html?h3`, `history` -> `back=[b.html|Page B, a.html|Page A] forward=[]`;
  `goto-history -1` (lists read right after the call, the entry still pending, `url` still `a.html?h3`) -> `back=[a.html]
  forward=[a.html?h3]`; from `b.html`, `goto-history 1` -> `back=[b.html, a.html] forward=[]` while `url` is still
  `b.html`. Before #258 the lists counted from the last committed entry.
- `pending dup`: `duplicate queued behind the insert`, `pending duplicate copy=handle session id -1`; after the menu:
  `running 2 call(s) queued behind the insert`, `client tab inserted` for the copy, batch `TabCreated,...,TabCreated,
  ActiveTabChanged,...`, the copy `origin=client active=yes`. `pending dup-close`: navigate, close and duplicate queued;
  `running 3 call(s)`, the source `tabClosed reason=client`, the copy `insert dropped (nothing inserted), TabClosed reason
  page` (`tab=-1`: never inserted).
- Actions: `actions` twice -> the same `png=` objects; `activate` another tab -> `ExtensionActionsChanged`, new objects
  (per-tab key); `actions` again -> the same objects as after the switch.
- Container: an `alert` on a `127.0.0.1` tab: `claimed`, `attached ... frame 346,606 448x144 host view 120,150
  900x600`. `layout 80` (the container 80 pt shorter, no window resize): `attached ... frame 346,526 448x144 host view
  120,150 900x520`; Quartz window list: the dialog's top moved from y 419 to 499, the host window unchanged.
- 0 `FATAL`/`Check failed`.

**Run 2** (as run 1 plus `--arkt-trace-visibility`, port 9492): `hide` (the self-test orders its window out), then an
`alert`: `claimed` but never shown (the dialog window not on screen); `show`: `placement changed visible=1
onActiveSpace=1`, `visibility <tab> visible` before, while and after hidden: no transition, so the dialog stayed
unshown. This is what the replay fix addresses.

**Run 3** (the fix, port 9493): `hide`, `alert`, `show`: `tab-modal dialog held while the window was hidden, shown now`,
`attached window ... frame 346,606 448x144 host view 120,150 900x600`. `answer <tab> accept` -> `answered=yes`,
`detached`. `run <action-probe>` (anchor log above). `eval`: values, gestures, promise and exception as in W3-5b. One
`Check failed: url_.IsValid()` in `worker_global_scope.cc:190`, the extension renderer's known CHECK when a worker
target is evaluated over CDP before it has started (W3-4, run 2); the browser process logged none.

### Regression rows

One launch without the self-test switch (`w258-reg`, port 9494, `--arkt-trace-visibility`, `tabs-probe`,
`action-probe`, a fixture page): W5b 1 (alive after 30 s, census `normal=1 arkt=1 views=0`), 2 (navigate to `b.html`,
`visible`), 3 (`chrome.tabs.create` in the background: index 1, `b.html` still `visible`), 5 (`chrome.windows.create`:
`normal`, census `normal=2 arkt=2 views=0`), 6 (`chrome.tabs.remove`: `tab event removed`, `tab list rows 2`), 7 (every
window removed: census 0/0/0, two `native window destroyed`, process alive, gone after `kill`), 8 (`window.open` with a
gesture: `true`, `tab list rows 3`), 13 (AX Edit > Find > Find... after the frontmost check: `stub FindBar::Show`); W5c
Step 3 (`tabs.update` to the background tab: `b.html` `hidden`, back: `visible`); W6 (`chrome.action.openPopup()`
with the window frontmost: `"ok"`, `TriggerPopup ... by_user=0`, `popup loaded`; second window in row 5). Placeholder
Extensions button through AX twice: `toggle menu (showing=0)`, `menu shown 2 items`, `toggle menu (showing=1)`, `menu
closed`. 0 `FATAL`/`Check failed`.

Placeholder alert with the claim filter (final build, `w258-ph2`, port 9496, a fixture page, `alert` over CDP): `tab-modal
dialog claimed window 95644 host window 95636`, `attached ... frame 766,933 448x144 host view 390,197 1200x880`; the
Quartz window list shows the dialog `127.0.0.1:8491 says` at the card's top, centred. 0 `FATAL`/`Check failed`.

### #262 review fixes

- **Replay only when no dialog of the tab is shown** (medium). The manager shows only its front dialog, so a second
  claimed dialog stays hidden behind a shown one; the replay now runs only when the host has dialogs and none is
  visible (`HasDialogs`, `HasVisibleDialog`). Run 4 (`w258-run4`, port 9497): a Basic-auth `Sign in` dialog (from a
  `fetch` of a 401 fixture) shown and a JavaScript `alert` queued behind it (claimed, not on screen); `hide`, `show`
  and bringing the app frontmost logged four `placement changed` lines and no replay, detach or attach; the `Sign in`
  window stayed on screen. The hidden-window case on another tab still passes (`held while the window was hidden,
  shown now`, `attached`). A comment records that the replay runs whatever `OnVisibilityChanged` does.
- **Includes** (low): the duplicate `content/public/browser/visibility.h` removed, the `web_modal` include in order.
- **Icon caches** (low): the menu observes `ThemeService` and the native-UI `NativeTheme`, and drops its rasterized
  icons (and reports `ExtensionActionsChanged`) on a theme or color-scheme change. The PNG cache moved from one
  process-wide map to each window's handle, pruned of actions no longer listed and cleared when the window closes.
  Repeated `actions` still answer the same PNG objects (run 4).
- Regression (`w258-reg2`, port 9498): W5c Step 3 (`visible`, `hidden`, `visible`), W6 (`openPopup` `"ok"`, `popup
  loaded`, second window `normal=2 arkt=2 views=0`). 0 `FATAL`/`Check failed` in runs 4 and `reg2`.

### Patch budget

Unchanged: 7 patch files, 17 upstream files, 0 hot-file hunks.

## W3-5b: History, duplicate, extension actions and the test API

Date 2026-10-24. Branch `engine/33-w3-5b-history-extensions` off `main` at `ee5d7fb` (#256 merged). `$CR` branch `arkt`
at `e4a2ca5cca` (0001-0007) before and after: no patch. Overlay only; the facade header, `app/` and `project.yml` are
unchanged. `/` had 8.5 GiB free and swap 8.7 GB used of 10 GB before each build.

### What landed

- **History** (contract rule 9). `backEntries` / `forwardEntries`: the `NavigationController` entries before and after
  the last committed one, nearest first, with `GetURL()` and `GetTitleForDisplay()`. `goToHistory(offset:)` was already
  in place (`GoToOffset` behind `CanGoToOffset`; 0 and out of range are no-ops).
- **Duplicate** (rule 10). `chrome::DuplicateTabAt` (`WebContents::Clone`, so the copy has the source's entries and
  loads the current one), inserted next to the source, active (`ADD_ACTIVE`), reported as `TabCreated` with origin
  `client`; nil for a closed or non-duplicable tab (a pending tab's duplicate queues behind its insert since #258). Inside a nested loop it is deferred like `createTab`
  (pending handle, calls queue behind the insert). `ADD_INHERIT_OPENER` makes the active tab its opener.
- **Inserts that do not happen** (#256 review). `createTab` and `duplicate` share one insert path: a window gone before
  a deferred insert, or an insert that added nothing to a live window, gives the handle a terminal `TabClosed`
  (`client` if the client had asked to close it meanwhile, else `windowClosing` or `page`) and drops its queued calls.
- **Extension actions** (Decision 10). Each embedder host's window gets an `ArktExtensionsMenu` as its
  `ExtensionsContainer` menu (attached from a posted task after `WindowOpened`, or on the first call), so
  `chrome.action.openPopup` also works there. `extensionActions(in:)` returns id, name, the 16 pt icon as a 2x PNG and
  the enabled state for the active tab, in `ToolbarActionsModel` order (the placeholder's sidebar menu is listed as is).
  `ExtensionActionsChanged` is recorded on every model change (added, removed, updated, initialized), at most once per
  window per batch, and once after the menu is attached. `runExtensionAction(_:in:anchor:)` sets the shell's view as
  the anchor and runs the action as a toolbar click (`ExecuteUserAction`); the popup is the existing
  `PopoverExtensionView` (NSPopover) anchored to that view. `ArktExtensionsMenu` gains `GetActions`, `SetAnchor`,
  `RunAction` and `SetOnChanged`; the sidebar menu is unchanged.
- **Test API** (Task W3-5 step 5), enabled only by `--arkt-engine-test-api` (`testAPIEnabled`); without it both calls
  log and answer an error or NO. `evaluateScript(_:in:userGesture:completion:)` runs in the page's main world through
  `RenderFrameHost::ExecuteJavaScriptForTests` or `ExecuteJavaScriptWithUserGestureForTests` and converts the result
  to Foundation values (`NSNumber`, `NSString`, `NSArray`, `NSDictionary`; null and undefined become nil or `NSNull`).
  **Deviation from "Runtime.evaluate semantics":** the public API passes `resolve_promises=false`, so a promise
  answers an empty dictionary instead of its value, and a thrown exception answers nil without an error. The W3-9
  harness drivers need neither (`holdClose`, `retitle` and `window.open` are synchronous). `answerDialog(in:accept:)`
  closes the tab's pending JavaScript dialog (alert, confirm, prompt, beforeunload) through
  `TabModalDialogManager::HandleJavaScriptDialog`, with an empty prompt override (a prompt is answered with an empty
  string; a dialog still pending has no view to read input from).
- **Self-test commands** `history`, `goto <offset>`, `duplicate`, `actions`, `run <action id>` (anchored to a view above
  the card), `eval`, `hold`, `answer <session id> accept|cancel`; `@<session id>` as the last word targets another tab
  (a page restored from the back-forward cache shows its old title again, which repeated a command in a first try).
- **LOW items from the #256 review**: new contents without a favicon clear the old one at `TabReplaced`; a held
  maximize, minimize, restore or fullscreen is kept until the window is shown instead of being applied to a window
  nobody asked to show.

### #256 review follow-ups

- (a) A page close while an unrelated `tabs.remove` is in flight reports `extension`. **Not scoped to the tab:** the
  keepalive records only the function name, and the patch-free sources that carry the arguments do not fit:
  `extensions::activity_monitor` has one global function pointer that `ActivityLog::SetActivityHandlers` expects to own
  (`DCHECK(!current || current == &LogApiFunction)`), and the function object itself is not reachable. A tab-exact
  signal needs a patch (for example a hook in `TabsRemoveFunction::RemoveTab`). Recorded as a known gap with the other
  Decision 12 gaps (W3-5a); the maintainer decides between the gap and a patch.
- (b) Done (above).

### Acceptance (self-test embedder, `Chromium.app`)

| Criterion | Result | Evidence |
|---|---|---|
| History entries nearest first; `goToHistory` across entries; 0 and out of range are no-ops | PASS | run 6 |
| Duplicate: URL, title, back and forward stacks; listed after the original; origin client; independent | PASS | run 6 |
| Action list equals `--arkt-extensions-menu-dump`'s items | PASS | run 5 |
| Running action-probe logs `popup loaded` anchored to the self-test view | PASS | run 5 |
| `ExtensionActionsChanged` for an embedder window | PASS | run 5 |
| Test API: values, user gesture, holdClose, answerDialog cancel and accept | PASS (promise and exception deviations) | run 5 |
| Page context menu re-measured for real | still blocked | run 6 |

**Run 5** (`--arkt-facade-selftest --arkt-engine-test-api --arkt-extensions-menu-dump`, `action-probe` and
`tabs-probe`, profile `$PROF/w3-5-run5`, port 9464). The menu dump (`menu item 0 Arkt action probe enabled=1`, `menu
item 1 Arkt tabs probe enabled=0`) and the facade list (`facade actions menu attached`, then `ExtensionActionsChanged`,
`actions count=2`: action-probe `enabled=1 icon=631 bytes`, tabs-probe `enabled=0 icon=625 bytes`) agree in order,
names and state. `run <action-probe>`: `facade runExtensionAction`, `run action ... source 1`, `TriggerPopup ...
by_user=1`, `popup loaded chrome-extension://<id>/popup.html`, `popup auto-resize 244x129`; the popover's anchor is the
self-test's view (the menu's anchor was set from the call, logged pointer). `eval`: `testAPIEnabled=yes`; an object
literal came back as an `NSDictionary` (`sum = 3`, `list = (1, two, <null>)`, `ok = 1`, the title);
`navigator.userActivation.isActive` `0` without and `1` with the gesture; `Promise.resolve(7)` an empty dictionary; a
`ReferenceError` nil, no error. Held close driven by the test API: `hold` (a `beforeunload` handler set with a user
gesture, `hasBeenActive` true), `close honour` -> `held`; `answer <tab> cancel` from another tab -> `answerDialog
accept=no answered=yes`, `closeCancelled ... isClosing=no`; `close honour` again, `answer <tab> accept` -> `tab closed
... reason client after 2214 ms`. 0 `FATAL`/`Check failed`.

**Run 6** (profile `$PROF/w3-5-run6`, port 9465; commands from a control tab with `@<session id>`). A tab at
`a.html?h1`, then `b.html?h2` and `a.html?h3` (CDP `Page.navigate`):

```
history  url=a.html?h3 back=[b.html?h2|Page B, a.html?h1|Page A] forward=[]
goto -2  -> urlChanged a.html?h1; history back=[] forward=[b.html?h2|Page B, a.html?h3|Page A]
goto 2   -> urlChanged a.html?h3
goto -1  -> urlChanged b.html?h2; history back=[a.html?h1] forward=[a.html?h3]
goto 0, goto 5, goto -9 -> no event; history unchanged
duplicate -> copy origin=client, history back=[a.html?h1] forward=[a.html?h3], tabCreated active=yes url=b.html?h2
```

`chrome.tabs.query`: original at index 1, the copy at 2. `goto -1` on the copy moved only the copy (`a.html?h1`; the
original stayed on `b.html?h2`). 0 `FATAL`/`Check failed`.

Page context menu: AX `AXShowMenu` on the page's web area (after the frontmost check) opened no menu (`count of menus`
0). `RenderViewContextMenuMacCocoa::Show` still returns without a top-level `views::Widget`
(`render_view_context_menu_mac_cocoa.mm:78-83`), so the case cannot be measured for real until Arkt windows show page
context menus; the W3-3 model (an `NSMenu` tracked from a Chromium task that allows application tasks) stands.

All processes were stopped by PID; the fixture server was stopped.

### Remaining after W3-5

Decision 12 gaps (W3-5a, plus follow-up (a) above); tab-modal dialog positioning on the container (done in #250: child
windows over the tab's container, see the week-2 results, "#250"); audible state (no
header event); a page's `NEW_WINDOW` window reports `reopen`; initial show state for windows shown at once; the test
API's promise and exception semantics; the page context menu (needs context menus on Arkt windows).

## W3-5a: Tab facade, correctness part

Date 2026-10-24. Branch `engine/33-w3-5-tab-facade` off `main` at `39d0f5d`. Split per the plan's time-box: W3-5a
(this section) takes the correctness items; W3-5b takes history and duplicate, extension actions for embedder windows,
the test API and the page context menu re-measure. `$CR` branch `arkt` at `e4a2ca5cca` (0001-0007) before and after:
no patch. Overlay only; the facade header, `app/` and `project.yml` are unchanged. `/` had 9.2 GiB free and swap 8.7 GB
used of 10 GB before each build.

### What landed

- **Pending handles** (W3-3 review, must fix). A client `createTab` deferred inside a nested loop marks its handle
  pending; `navigate`, `reload`, `goBack`, `goForward`, `goToHistoryOffset`, `activate` and `close` on a pending handle
  queue behind the insert and run, in order, right after it. `close` on a pending handle answers `held` (`isClosing`
  yes) and ends with `TabClosed(client)`. If the window is gone when the deferred insert runs, the handle gets a
  terminal `TabClosed(windowClosing)` (ChromiumEngine announced it at `createTab`, Decision 4) and its queue is dropped.
  `createBrowser(host:)` inside a nested loop still creates at once (W3-4 deviation, kept: a deferred creation could
  not return the handle).
- **Close modes** (Decision 11). `.skipUnloadHandlers` sets `UnloadController::set_force_skip_warning_user_on_close`
  for the one `CloseWebContentsAt` call (RAII, restored after; the flag is browser-wide). `wouldHoldClose` is
  `NeedToFireBeforeUnloadOrUnloadEvents()` or `UnloadController::ShouldRunUnloadListenerBeforeClosing` (attached
  DevTools, a custom confirmation), which is TabStripModel's own test.
- **CloseCancelled**. W3-4's `beforeUnloadFired:` reset covers a cancelled single-tab client close (verified below). New:
  a held close the engine started (`chrome.tabs.remove`, `window.close()`), which TabStripModel marks with
  `TabCloseTypesData`, reports `CloseCancelled` too; the facade removes the stale marker Chromium leaves after a cancel.
  `isClosing` is true while the facade's own close or such a marked close is pending.
- **Close reasons** (Decision 12). Order: `client` (the facade closed it), `appTerminating` (quit started), then a
  window close (`closing_all()`): `extension` when `chrome.windows.remove` asked, else `windowClosing`; a single tab
  the facade did not close: `extension` while an extension's `tabs.remove` call is in flight, else `page`.
  **Deviation from Decision 12:** in 156 `chrome.tabs.remove` calls `WebContents::Close()` (`tabs_api.cc:3340`), which
  ends in `WebContentsDelegate::CloseContents` exactly as `window.close()` does (`RequestClose` ->
  `ClosePageIgnoringUnloadEvents` -> `WebContentsImpl::Close`), so "CloseContents ran" cannot tell them apart. The
  patch-free signal is the extension function's keepalive: `ProcessManager` records an `Activity::API_FUNCTION` keepalive
  named `tabs.remove` / `windows.remove` from before the function runs until it responds (`tabs.remove` responds only
  after `WebContentsDestroyed`, so a held and later accepted close still reads it). `arkt_extension_calls.{h,cc}` reads
  it (`GetServiceWorkerKeepaliveDataForRecords`, `GetLazyKeepaliveActivities`). `chrome.windows.remove` responds at
  once, so `ArktBrowserWindow::Close()` reads it synchronously and keeps the answer for that close
  (`IsClosedByExtension`). Gaps: calls from extension pages that hold no keepalive (popups, options pages, MV2
  persistent background pages) report `page`; Chromium's own Close Tab command (Cmd-W through Chromium's menu) reports
  `page`; an unrelated `tabs.remove` in flight while a page calls `window.close()` would report `extension`.
- **Stable containers** (Decision 6). Each handle owns an `ArktTabContainerView` (`arkt/browser`, so the window code can
  recognise it) for its whole life. In an embedder host's window the current contents view is its only subview; on a
  contents replacement the subview is swapped. The placeholder host keeps mounting contents views in its card itself,
  so there the container stays empty; a held window moved to the embedder's host at replay fills its containers
  through `AdoptHeldBrowser`. `DialogHostViewFor` (dialog host, `GetContentsSize`) follows the tab's container when it
  is mounted in the window. `GetWebContentsModalDialogHostFor` gives a per-tab host only to this window's tabs (#255
  review, low).
- **Events**. `TabMoved` for an index move (`kMoved`) and for a move between windows (same handle, same container);
  `TabReplaced` on `kReplaced`; per-tab `URLChanged`, `TitleChanged`, `LoadingChanged`, `HistoryChanged`,
  `FaviconChanged` from a `WebContentsObserver` and a `FaviconDriverObserver` (16 DIP icon, PNG at 2x when available),
  each only when its value changed. Order: Chromium starts loading a browser-initiated navigation before
  `DidStartNavigation`; the pending URL is already visible then, so `DidStartLoading` reports the URL first (rule 2).
  A commit to another host clears the favicon (when there was one) before the load ends (rule 6). `TabCreated` carries
  the opener (`TabStripModel::GetOpenerOfTabAt`); a tab inserted while loading or with history reports both right
  after `TabCreated`. Audible state is not reported: the frozen header has no event kind for it.
- **Closed handle** keeps its last session id (W3-4 logged `tab=-1` for closed tabs).
- **Held windows** (#255 review). While the show is held, Maximize, Minimize, Restore and entering fullscreen are
  recorded (last wins) and applied after the replayed show; bounds set while held are applied again at release (after
  `ReplaceHost`). A held window with no recorded state takes the initial show state from its create params
  (`chrome.windows.create({state})` on Mac asks only through them). A window shown at once still ignores the initial
  show state (known gap, unchanged).
- **Request classification** (#255 review). `kLastAndUrlsStartupPref` -> `startupURL`, `kSessionRestore` and
  `kDeskTemplate` -> `reopen`, named before the bounds check.
- **UI thread**: `DCHECK_CURRENTLY_ON(BrowserThread::UI)` on every facade entry point (tab, browser and engine
  protocols). `out/Spike` has `dcheck_always_on = false`, so these were compiled, not exercised.
- **Self-test embedder**: logs every event kind; a page title `arkt-selftest <command>` (set over CDP) runs a facade
  call on its tab: `close honour|skip`, `close-other`, `state`, `navigate`, `reload [<session id>]`, `activate`,
  `devtools`, `pending` (the pending-handle check).

`gn check out/Spike '//arkt/*'`: `Header dependency check OK` (new dependencies `//chrome/browser/ui:unload_controller`,
`//components/favicon/{content,core}`, `//ui/gfx/codec`, `//skia`, `//chrome/app:command_ids`,
`//chrome/browser/ui:browser_init_state`; no `nogncheck` added). Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome`,
two compile fixes, then `The build has finished successfully.`

### Acceptance (self-test embedder, `Chromium.app`)

| Criterion | Result | Evidence |
|---|---|---|
| W5c sequence: `tabCreated` with `origin=engine`, `activeTabChanged`, visibility when the self-test mounts containers | PASS | run 1 |
| Navigation logs url, loading start, title, loading end in that order | PASS (after the `DidStartLoading` fix) | run 2 |
| Host change logs the favicon clear before load end | PASS | runs 1, 2 |
| `chrome://crash` then reload keeps the same container | PASS | runs 1, 2 |
| `onbeforeunload` page (user gesture): `held`, dialog shown, removal only after accept, `closeCancelled` after cancel | PASS (dialog not on the container, below) | run 1 |
| `.skipUnloadHandlers` closes at once | PASS | run 1 |
| Unload-only page: held or not, how long | recorded: not held | run 1 |
| DevTools-attached tab: held, when it completes | recorded: held, 4 ms | run 1 |
| `chrome.tabs.remove` logs `extension`; `window.close()` logs `page` | PASS | run 1 |
| Pending handle: close/navigate/activate queued behind the insert | PASS | run 1 |
| `chrome.windows.remove` reports `extension`; close button `windowClosing` | PASS | run 1 |
| Held window state and bounds applied at replay | PASS | runs 2, 3 |
| Stand-in Engine app (placeholder host with the facade present) unchanged | PASS | run 4 |
| Action list and action-probe popup | W3-5b | |

**Run 1** (`--no-startup-window --arkt-facade-selftest --arkt-facade-selftest-url=<loopback a.html>
--arkt-trace-visibility`, `tabs-probe`, profile `$PROF/w3-5-run1`, port 9461). Fixture pages from a loopback HTTP server
on two host names (`127.0.0.1`, `localhost`), each with its own favicon. `ARKT` prefixes shortened.

- W5c: `chrome.tabs.create` from the probe -> `tabCreated ... origin=engine active=yes`, `mounted ... subviews=1`,
  `activeTabChanged`; CDP `visibilityState`: new tab `visible`, previous tab `hidden`.
- Host change (`navigate http://localhost:8461/b.html` on a `127.0.0.1` page with a favicon): `historyChanged
  back=yes`, `faviconChanged png=none`, `titleChanged Page B`, `loadingChanged no`, `faviconChanged png=118 bytes`.
  (This first build logged loading before the URL; fixed and re-checked in run 2.)
- Held close: `onbeforeunload` set with `cdp.mjs --user-gesture` (`hasBeenActive` true); `state` showed
  `wouldHoldClose=yes`; `close honour` -> `result=held isClosing=yes`; AX showed an `AXDialog` window "Leave site?"
  (Cancel, Leave). AX Cancel (after the frontmost check): `facade close cancelled`, `closeCancelled ... isClosing=no`,
  the tab stays (`state closing=no`). Again, AX Leave after 11 s: `tab closed ... reason client`, `tabClosed ...
  reason=client after 11557 ms`. The dialog is a separate window at the screen position Chromium gives an unpositioned
  dialog (W3-4 note: `GetModalDialogBounds` returns an empty rect without a Views host), not over the tab's container;
  the window-only screenshot of the host window shows the page only. Positioning stays open for W3-9 or later.
- Skip: same page setup, `close skip` -> `tab closed ... reason client`, `result=closed`, no dialog.
- Unload-only page (`addEventListener("unload", ...)` sending a beacon): `wouldHoldClose=no`, `close honour` ->
  `result=closed` at once; the fixture server got no beacon. In 156 a page with only an `unload` handler does not hold
  a close here (`NeedToFireBeforeUnloadOrUnloadEvents()` false), and the handler did not reach the network.
- DevTools: `devtools` (IDC_DEV_TOOLS through the host) opened an undocked DevTools window (`views=1`); `state
  wouldHoldClose=yes`; `close honour` -> `result=held`, then `tabClosed ... reason=client after 4 ms`; DevTools closed
  with it (`views=0`).
- Reasons: `chrome.tabs.remove(id)` -> `reason extension`; a tab opened by a link click with a user gesture
  (`tabCreated ... opener=<opener tab>`, `state opener=<id>`) calling `window.close()` -> `reason page`; an
  extension-started held close (`tabs.remove` on a `beforeunload` page): AX Cancel -> `closeCancelled ...
  isClosing=no`; again with Leave -> `reason extension`.
- Moves and windows: `chrome.windows.create` (bounds) -> provider window; `chrome.tabs.move` to it -> `tabMoved
  window=<new>`, the same container pointer before and after; `chrome.windows.remove` -> `native window close by
  chrome.windows.remove`, both tabs `reason extension`, `windowClosed`. Another window's close button (AX) -> `reason
  windowClosing`.
- Crash: `navigate chrome://crash` (renderer crashed), recovery by a navigation: same container pointer.
- Pending: `pending` -> `createTab deferred (... run loop mode NSEventTrackingRunLoopMode)`, `session id -1`, menu
  closed, `navigate queued behind the insert`, `activate queued ...`, `close queued ...`, `pending close result=held
  isClosing=yes`, then `createTab inserted`, `running 3 call(s) queued behind the insert`, `tab closed ... reason
  client`, one batch `TabCreated,LoadingChanged,URLChanged,ActiveTabChanged,TabClosed,ActiveTabChanged`.
- `TabReplaced` was not triggered: `chrome.tabs.discard` discards in place in 156 (no `kReplaced`), and prerender
  activation keeps the WebContents. The path is implemented (rebind, container swap, event) and unexercised.
- 0 `FATAL`/`Check failed`.

**Run 2** (`--arkt-facade-selftest=hold`, port 9462, profile `$PROF/w3-5-run2`). Before ready, `chrome.windows.create`
with bounds 600x400 and `chrome.windows.update` to 320,260 650x420: `native window bounds deferred (show held)`;
after ready: `host replaced (Placeholder -> SelfTest)`, `native window held bounds applied 320,260 650x420`;
`chrome.windows.get` -> `[320,260,650,420,"normal"]`. The replayed window's tab was mounted from its container
(`subviews=1`), the placeholder-to-embedder path. Navigation after the fix: one batch `URLChanged,LoadingChanged`, then
`HistoryChanged,FaviconChanged(none)`, `TitleChanged`, `LoadingChanged(no)`, `FaviconChanged(118 bytes)`. Crash then
`reload <session id>` from another tab (facade `reload`): same container pointer, `url`, `loading yes`, `loading no`.
0 `FATAL`/`Check failed`.

**Run 3** (hold, port 9463, profile `$PROF/w3-5-run3`): `chrome.windows.create({state: "maximized"})` before ready ->
held; after replay `native window held maximize applied`; `chrome.windows.get` -> `"maximized"`. Fullscreen and
minimized were not run (they would take over a Space or the Dock on a shared screen); they use the same path.

**Run 4** (Engine app from `$EMB`, the W3-3 stand-in, no CDP port, a `data:` URL argument; `libchrome_dll.dylib`
re-cloned next to the bundle, the only changed dylib): the stand-in's host is unusable, so the placeholder host is
kept; the window-only screenshot shows the page in the placeholder's card (the container stays empty there, as
designed). Quit through the menu (AX): `quit started`, `engineWillBeginTerminating`, `tab closed ... reason
appTerminating`, `native window destroyed`, `app terminating`, `engineWillTerminate`, keep-alive released, process
exited. 0 `FATAL`/`Check failed`.

All processes were stopped by PID; the fixture server was stopped. Screenshots kept locally.

### Carried items

Closed here: pending-handle queue; CloseCancelled after a cancelled held close (client and engine-started); page and
extension reasons and the `chrome.windows.remove` split; close modes; stable containers in the dialog host and the
self-test mount; `TabReplaced`, `TabMoved`, per-tab state events; closed handle's session id; held-window state and
bounds; request classification; per-tab dialog hosts only for own tabs; `createBrowser(host:)` in a nested loop
confirmed as created at once; UI-thread DCHECKs.

Open for W3-5b: history entries and `duplicate` (rules 9, 10), extension actions for embedder windows
(`extensionActions(in:)`, `runExtensionAction`, `ExtensionActionsChanged`), the test API (`evaluateScript`,
`answerDialog`), and the page context menu re-measure (still blocked: `RenderViewContextMenuMacCocoa::Show` returns
without a Views widget). Open beyond W3-5: tab-modal dialog positioning on the container; audible state (no header
event); a page's `NEW_WINDOW` window still reports `reopen`; initial show state for windows shown at once.

## W3-4: Host mode for ShellUI windows

Date 2026-10-24. Branch `engine/33-w3-4-host-mode` off `main` at `f3d9e0b`. `$CR` branch `arkt` at `e4a2ca5cca`
(0001-0007) before and after: no patch. Overlay only; no `app/` or `project.yml` change. `/` had 9.5 GiB free and swap
8.7 GB used of 10 GB before each build and run.

### What landed

- **Factory: embedder host first** (`arkt_browser_main_extra_parts.mm`). The window factory asks
  `HostForArktBrowserWindow` before it builds the window: the host passed to `createBrowserWithHost:`, or, once the
  embedder is ready, its answer to `-hostForEngineWindowRequest:`. A nil answer, or a host without `window`,
  `cardView`, `setCloseRequested:`, `setValidateCommand:` or `setExecuteCommand:` (or with a nil window or card), keeps
  the placeholder host and logs why. Only placeholder windows get the sidebar Extensions menu.
- **Host mode** (`arkt_browser_window.{h,mm}`). `host_mode()` is true for every host that is not the placeholder:
  no auto-mount (Decision 6; the colour provider is still set on activation); `GetContentsSize` and the window's
  dialog host follow the active tab's view when the embedder has mounted it in the window, the card otherwise; one
  `ArktModalDialogHost` per tab (`GetWebContentsModalDialogHostFor`), resolved per call (its tab's view, the card as
  fallback), dropped when the tab leaves; `activateTab` and `tabListChanged:` only when the host responds to them
  (#246 review). Until W3-5's stable containers a tab's container is its contents view (one function,
  `DialogHostViewFor`). `closeRequested` closes the `Browser` as before.
- **Held windows** (W3-3 review). The pending show is `none`, `show` or `showInactive`; a held `ShowInactive` is
  replayed as `ShowInactive`. While held, `Minimize`, `Maximize`, `Restore` and entering fullscreen are ignored and
  logged. At replay the window moves to the embedder's host (`ReplaceHost`: the old host's blocks and observers are
  removed, its window ordered out, the placeholder's Extensions menu dropped, tab dialog hosts rebuilt) and is then
  shown. A held window is not listed and not announced (`WindowOpened`) until replay has given it the embedder's host.
  After `embedderFailed`, a window Chromium creates is held and closed (it was shown with the placeholder host).
- **Request kinds from the call site** (`arkt_embedder.mm`), no patch. The factory reads the `Browser`'s create params
  (`BrowserInitState`, built before the window, `browser.cc:291` and `:315`); the kind is stored with the queued
  request instead of being guessed from the first tab at replay:

  | Signal | Kind |
  |---|---|
  | the seam's own creation (startup URL replay, debug reopen) | as named there |
  | `creation_source == kStartupCreator` (startup creator, also a URL opened by another app) | `startupURL` |
  | a show state or bounds in the params (`chrome.windows.create` always sets `kNormal`, `tabs_api.cc:189-190`) | `extension` |
  | default params (Dock reopen, New Window, and a page's `NEW_WINDOW` navigation) | `reopen` |

  `bounds` carries the requested frame when given. Gaps: a page's `NEW_WINDOW` window (shift-click, `noopener` with
  `NEW_WINDOW` disposition) reports `reopen`: its params are the same as reopen's and no signal tells them apart
  without a patch (`kind=page` is unused this week); `opener` is nil for every kind; `initialURL` is known only for
  the seam's own creations (the tab is added after the window exists).
- **Facade** (`arkt_engine_facade.{h,mm}`). `createBrowserWithHost:` creates a `TYPE_NORMAL` `Browser` for the initial
  profile synchronously (`CHECK`s the profile, the host, and that the factory took it), does not show it (the shell
  owns the window) and returns the handle adopted inside construction. `ArktBrowserHandle.host` follows the window's
  current host. Close reasons for windows: a tab removed while its tab strip closes all tabs (`closing_all()`: host
  close button, `close`, Close Window, `chrome.windows.remove`) reports `windowClosing`; quitting keeps
  `appTerminating`; a client close keeps `client`. `CloseCancelled`: each tab handle observes its contents
  (`WebContentsObserver::BeforeUnloadFired(false)`) while its own close or its window's close is pending, resets
  `isClosing` and records `CloseCancelled`. Checked here for a window close; the same path should cover a cancelled
  single-tab `close(mode:)` (the W3-3 review item "never reset"), which W3-5 verifies. `DCHECK_CURRENTLY_ON(UI)`
  on `embedderReady`, `embedderFailed`, `createBrowser` and every deferred mutator.
- **Self-test embedder** (`arkt_selftest_embedder.{h,mm}`), used only when `--arkt-facade-selftest` is present and no
  `ArktShellEmbedder` class exists. It conforms to `ArktEngineEmbedder`, supplies plain `NSWindow` hosts (the close
  button calls `closeRequested`), opens one shell-initiated window after ready (`createBrowserWithHost:`, then a tab),
  mounts each window's active tab in its card, and logs every event as `ARKT selftest <event>`. Values: none (ready at
  once), `hold` (ready after 5 s), `fail` (`embedderFailed` after 5 s).

`gn check out/Spike '//arkt/*'`: `Header dependency check OK` (new dependency `//chrome/browser/ui:browser_init_state`,
a separate target, no `nogncheck`). Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome`, one include fix, then
`The build has finished successfully.`

### Acceptance

| Criterion | Result | Evidence |
|---|---|---|
| Shell-initiated window opens: `windowOpened`, census `normal=1 arkt=1 views=0` | PASS | run 1 |
| `chrome.windows.create` from the tabs probe asks the provider with `kind=extension`, opens a second host window (`normal=2 arkt=2 views=0`) | PASS | run 1 |
| Closing a host window closes its `Browser`: `windowClosed`, tabs closed with `windowClosing`, `native window destroyed` | PASS | run 1 (close button through AX; also `chrome.windows.remove`) |
| Dock-style reopen lands in a provider window with `kind=reopen` | PASS | run 1 (a real reopen Apple event), run 2 (debug reopen before ready) |
| CDP `chrome.windows.getAll` ids equal the facade's window ids | PASS | run 1 |
| Without the switch the W3-0 rows still pass (W6 Step 3, W5c Step 3; the plan says "W5b rows") | PASS | run 4 |

**Run 1** (`Chromium.app`, `--no-startup-window --arkt-facade-selftest`, `tabs-probe`, profile `$PROF/w3-4-run1`, port
9451). `ARKT:` prefixes shortened:

```
embedder class ArktShellEmbedder absent
self-test embedder in use (--arkt-facade-selftest)
selftest embedderReady
window host from createBrowser(host:) ArktSelfTestWindowHost window session id 235937695
native window created (embedder host ArktSelfTestWindowHost)
browsers normal=1 arkt=1 views=0
facade batch 3 event(s) WindowOpened,TabCreated,ActiveTabChanged
selftest windowOpened window=235937695 host=ArktSelfTestWindowHost
selftest tabCreated window=235937695 tab=235937696 origin=client active=yes url=data:text/html,...
selftest windows ids=235937695
tabs.query windows=235937695                                  (tabs-probe)
```

`chrome.windows.create({url, left: 300, top: 200, width: 700, height: 500})` from the probe's worker answered
`[235937697,"normal",1]`:

```
selftest host requested kind=extension url=none bounds={{300, 469}, {700, 500}} opener=-1
host asked kind=extension (show state or bounds given (chrome.windows.create)) window session id 235937697 bounds 300,200 700x500 answered ArktSelfTestWindowHost
browsers normal=2 arkt=2 views=0
selftest tabCreated window=235937697 tab=235937698 origin=engine active=yes
selftest windows ids=235937695,235937697
```

`chrome.windows.getAll` -> `[[235937695,"normal",1],[235937697,"normal",1]]`, the facade's ids. Window-only
screenshots of both pages show the mounted contents (`$PROF/shots/w3-4-shell-window.png`, `-ext-window.png`, kept
locally). Close button of the extension window (AX, after the frontmost check): `selftest close button`, `browsers
normal=1`, batch `TabClosed,WindowClosed`, `tabClosed ... reason=windowClosing`, `windowClosed window=235937697`,
`native window destroyed`.

Held window close: `onbeforeunload` set with a user gesture on the shell window, close button: Chromium's "Leave
site?" dialog; AX `Cancel`: `facade close cancelled session id 235937696`, batch `CloseCancelled`, the window stays, no
`WindowClosed`. Handler cleared, close button again: `windowClosing`, `WindowClosed`, census `normal=0`. Then, with no
window, `open -a` on the running `Chromium.app` (the reopen Apple event, `applicationShouldHandleReopen:` ->
`CreateBrowser`): `host asked kind=reopen (default params ...)`, `native window created (embedder host ...)`,
`tabCreated ... url=chrome://newtab/`. `chrome.windows.remove` of that window: `reason=windowClosing` (Decision 12
lists `chrome.windows.remove` under `extension`; W3-5 owns the split). 0 `FATAL`/`Check failed`.

**Run 2** (`--arkt-facade-selftest=hold --arkt-debug-reopen-before-ready`, a `data:` URL argument, and
`chrome.windows.create({focused: false})` from the probe before ready; profile `$PROF/w3-4-run2b`, port 9453):

```
window request queued kind=startupURL url=data:text/html,...
debug reopen (chrome::NewEmptyWindow) before ready
window request queued kind=reopen (seam call site) window session id 2127451843 (window held hidden)
native window show held
window request queued kind=extension (show state or bounds given (chrome.windows.create)) window session id 2127451845 (window held hidden)
native window show inactive held
selftest embedderReady
embedderReady (3 queued request(s))
window host from createBrowser(host:) ArktSelfTestWindowHost window session id 2127451847
host asked kind=startupURL (seam call site) window session id 2127451849 answered ArktSelfTestWindowHost
host asked kind=reopen (seam call site) window session id 2127451843 answered ArktSelfTestWindowHost
native window host replaced (ArktPlaceholderWindowHost -> ArktSelfTestWindowHost) session id 2127451843
window number 95276
host asked kind=extension (...) window session id 2127451845 bounds 222,104 1400x900 answered ArktSelfTestWindowHost
native window host replaced (ArktPlaceholderWindowHost -> ArktSelfTestWindowHost) session id 2127451845
window number 95277 (shown inactive)
facade batch 10 event(s) WindowOpened,TabCreated,ActiveTabChanged,WindowOpened,TabCreated,ActiveTabChanged,WindowOpened,TabCreated,WindowOpened,TabCreated
```

The held windows are announced only after replay, with the self-test host. On the replaced window (2127451843): a
JavaScript `alert` (tab-modal) showed and was dismissed through AX; `requestFullscreen` with a user gesture logged
`enter fullscreen` and `exitFullscreen` `exit fullscreen` on the new host window; the close button closed it
(`windowClosing`, `native window destroyed`). 0 `FATAL`/`Check failed`. A first attempt of this run (`w3-4-run2`)
polled the probe's worker over CDP before it had started; that evaluation hit a renderer `CHECK` in
`WorkerGlobalScope::Url` (`worker_global_scope.cc:190`, the extension renderer, not the browser process); the rerun
waits until `chrome.windows` exists. That attempt also showed held windows announced with the placeholder host before
ready, which is why they are now announced at replay.

**Run 3** (`--arkt-facade-selftest=fail --arkt-debug-reopen-before-ready`, a URL argument, no port):
`embedderFailed (dropping 2 queued request(s))`, the held reopen window destroyed; then `open -a` (reopen):
`window after embedderFailed held and closed`, `native window show held`, `native window destroyed`; no window
visible. 0 `FATAL`/`Check failed`.

**Run 4** (no switch; `Chromium.app` with `--arkt-trace-visibility`, `action-probe`, `tabs-probe`,
`https://example.com`, port 9454): `embedder class ArktShellEmbedder absent`, `native window created (placeholder
host ...)`, census `normal=1 arkt=1 views=0`. W6 Step 3: `native window session id 1467694354` = `tabs.query
windows=1467694354` = `windows.getAll` `[[1467694354,"normal",1]]`. W5c Step 3 over CDP: `probe.create()` ->
`"visible"` (`tab list rows 2`), activate about:blank -> `"hidden"`, back -> `"visible"`, with matching `visibility`
and `native window mounted tab` lines. `probe.window()` then removing every window: `normal=2`, then 0, two `native
window destroyed`. 0 `FATAL`/`Check failed`.

**Run 5** (Engine app from `$EMB`, the W3-3 stand-in, no CDP port; `libchrome_dll.dylib` re-cloned next to the
bundle, the only changed dylib; the framework binary and the app are unchanged): the stand-in's
`ArktShellStandInWindowHost` has only `window` and `cardView`, so both replayed requests log `answered
ArktShellStandInWindowHost; unusable (no setCloseRequested:), placeholder host kept` and the windows show with the
placeholder host, as in W3-3. Quit through the menu (AX): `quit started`, `engineWillBeginTerminating`, two `native
window destroyed`, `app terminating`, `engineWillTerminate`, `lifetime keep-alive released (embedder flushed)`, the
process exited. 0 `FATAL`/`Check failed`/unrecognized selector.

### Notes

- Dialog placement: `GetModalDialogBounds` (`constrained_window_views.cc:104-112`) needs a Views widget for the host
  view and returns an empty rect for a plain `NSView`, so Arkt's tab-modal dialogs open where Chromium places an
  unpositioned dialog, with the placeholder host as with an embedder host (week-2 behaviour, unchanged here). The
  dialog host now names the tab's view; placing the dialog on it is W3-5 (containers) or W3-9.
- `createBrowser(host:)` inside a nested run loop creates the `Browser` at once and logs it: a deferred creation could
  not return the handle (Decision 3 lists `createBrowser` among the deferred mutators).
- `UnloadController::CancelWindowClose` also sends `chrome::OnClosingAllBrowsers(false)` for a cancelled window close
  outside a quit; the quit seam ignores it (no quit started), as run 1 shows (no `quit cancelled`).
- `TabClosed` events log `tab=-1` in the self-test: the handle's session id is read from its contents, which are gone
  when the batch arrives. W3-5's handle keeps the last value.

### What W3-5 needs

- Stable containers (Decision 6) replace "a tab's container is its contents view" in `DialogHostViewFor` and the
  self-test's `mountTab:`; the dialog host then follows the container.
- `TabReplaced` (the handle already re-observes the new contents on `kReplaced`), `TabMoved`, per-tab state events.
- Close reasons `page` / `extension` for single tabs, and whether `chrome.windows.remove` reports `extension`
  (today `windowClosing`, from `closing_all()`).
- The W3-3 review items still open: closes, navigation and activation of a pending handle queue behind its insert;
  re-measure the page context menu.
- `sessionId` of a closed handle (last value instead of -1).

### Dependencies on #33 (Swift lane)

- The stand-in host (`App/Engine/FacadeStandIn.swift`) has no `closeRequested`, `validateCommand`, `executeCommand`, so
  the Engine app keeps placeholder hosts until W3-6/W3-9 replace the stand-in with the typed embedder in
  `ChromiumEngineKit` and W3-7's `ShellWindowController` becomes an `EngineWindowHosting` (`ArktWindowHost` through
  `ChromiumEngine`). No Swift was changed here.
- W3-1's `EngineWindowRequest.kind` should expect `.reopen` for page-initiated normal windows this week.

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
3. **Readiness queue for Chromium-created windows** (W3-9 changed the replay below from a posted task to a synchronous
   one inside `embedderReady`; see "W3-9", fix 4). A URL argument is a real queued request: `--no-startup-window`
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

## W3-9 follow-up: empty Spaces and sidebar titles (#301)

Items 1 and 2 of #301, fixed and checked in the FakeEngine build. Item 3 (the stale tooltip window after closing the
shell windows) is engine-only and stays open in #301. The Chromium build still needs the same two smoke checks.

- Empty Space: a Space switch activated a restorable tab when one existed but never cleared the previous page when
  none did. `SidebarController.onEmptySpace` now reports that transition and the window clears selection, mounted
  plain or split content and the address bars. Loaded tabs and per-Space focus survive the round trip.
- Late engine events: after the switch, an older activation report or a held archive close could reopen the departed
  Space. Activations are checked against `EngineClient.latestActiveTab(in:)` (default: `activeTab(in:)`; Chromium reads
  the live browser selection, its event-backed `activeTab(in:)` and snapshots are unchanged), and a held close
  restores a successor only while its Space is still selected.
- Space title: the truncating label's intrinsic width omitted the cell's text inset, so "Space 1" showed as "Spac...".
  The header now measures the whole cell and still reserves room for the hover controls. Layout stays frame-based.

Verification:

- Red first: with the old `SpacePageView` the title test fails (expansion tooltip rect 50 x 16 instead of empty);
  without `onEmptySpace` the empty-Space tests fail; the `latestActiveTab` tests failed to compile before the API existed.
- `cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests`: 588 passed.
- `swift test --filter ShellKitGUITests`: 511 run, 5 skipped (FakeEngine lacks those contract drivers), 0 failures.
- `app/ArktCore` is untouched. `xcodebuild` Debug build of `ArktShell` and `build-for-testing` of `ArktShellUITests`
  succeed. The new XCUITest (`SpaceSwitchTests`) was compiled, not run.

## Engine follow-up: first-run URL card (#327) and stale tooltip (#301 item 3)

Date 2026-10-26. Branch `fix/327-first-run-url-card` off `main` at `7a68572`. Swift only: no patch, `.patches` unchanged
(7), no Chromium rebuild; the Engine app built with `xcodebuild -scheme ArktShell -configuration Engine
CONFIGURATION_BUILD_DIR=$EMB`.

### Root causes

- **#327.** On a first run the held startup window's batch (`WindowOpened, TabCreated, LoadingChanged,
  ActiveTabChanged`) reaches `engineDidCreateTab` with no Space. Creating Space 1 shows it while it is still empty, and
  `showEmptySpace()` records the engine's latest selection as acknowledged (the #301 guard against late reports). The
  Chromium engine's `latestActiveTab(in:)` already returns the new tab, so its queued `.activeTabChanged` was then taken
  for an acknowledgement and never reached `show(node:)`. Creating the first Space for an engine tab now keeps the
  acknowledgement from before; the batch's own activation shows the page.
- **#301 item 3.** The stale window is the Space title's tool tip ("Drag to Reorder Space", 131 x 20 pt, layer 103):
  shown when the window closed (Close Window while the pointer rests on the header), it stayed on screen after both
  shell windows were gone. `windowWillClose` now removes the tool tips of the window's views (the `toolTip` strings
  and the header's rect tool tip), which takes a shown one down.

### Checks (Engine app, profile `$PROF/327-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, no Space)

| Check | Result | Evidence |
|---|---|---|
| Cold launch with a URL, first run | PASS | executable started from the terminal, the GURL event sent to the process by PID before readiness: `launch finished (1 window(s) from queued requests)`; Space 1 created, the Today row selected and the page shown in the card (window-only screenshot) |
| Stale tooltip, before the fix | reproduced | Space title tool tip on screen (layer 103, 131 x 20), Close Window: the tool tip stayed on screen with no shell window, also after the pointer moved |
| No stray windows after closing both windows | PASS | two windows, the title tool tip shown at each Close Window; afterwards `CGWindowListCopyWindowInfo` for the app's PID lists no on-screen window |

The removable-volume prompt did not appear: the app ran from the terminal (the LaunchServices path stays a maintainer
check, as for #299).

### Verification

- Red first: `testFirstRunEngineTabInABatchShowsItsPageInTheNewSpace` failed (no selected row) and
  `testClosingTheWindowRemovesEveryToolTipOfItsViews` failed (10 tool tips left after the close).
- ShellKit `swift test --skip ShellKitGUITests`: 608 passed. `swift test --filter ShellKitGUITests`: 517 run (515 + 2
  new), 5 skipped, 0 failures. ArktCore `swift test`: 378 passed.

## #313: Peek

Date 2026-10-26. Branch `feat/313-peek`, rebased on `main` at `dbbef68`. Design: `docs/design/peek.md`, `design/peek/`.

### What landed

- **Engine seam.** `EngineWindowHosting` gains `decideLinkActivation(_:)` (a user link activation before the engine
  navigates; the host answers navigate or cancel without calling the engine) and `handleUnhandledKeyDown(_:in:)` (a
  key the page did not use), both with defaults. `EngineClient.focusPage(of:)` focuses a tab's page (the Chromium
  container is not the page). The facade header gains `ArktLinkActivation`, `ArktLinkDecision` and two optional
  `ArktWindowHost` members (both copies). InMemoryEngine has test drivers for both; FakeEngine asks the host from
  `decidePolicyFor` (WKWebView runs a Shift-click in the same frame, so FakeEngine reports Shift-clicks too).
- **Overlay.** `//arkt/browser:link_activation`: a navigation throttle that asks the facade about renderer-initiated
  primary main-frame navigations with a user gesture and a link transition (HTTP(S), not POST, not history);
  `CANCEL_AND_IGNORE` on a cancel. `ArktBrowserWindow::HandleKeyboardEvent` hands an Esc the page did not handle to
  the host from a posted task.
- **Patch 0008** (one upstream file, two hunks, no hot file): the throttle is added at the end of
  `CreateAndAddChromeThrottlesForNavigation`. Justification: a renderer-initiated same-tab link navigation can only be
  stopped before its request starts by a throttle, and `NavigationHandle::RegisterThrottleForTesting` needs content's
  internal throttle registry.
- **Shell.** `ShellUI/Peek`: `PeekLayout` (insets 56 / 34 / 26, controls outside in the right gutter, the small-window
  fallback below 600 pt, the split-pane layout 24 / 34 / 26 / 52 for a pane of 600 pt or more), `PeekRouting`
  (BH-144, BH-145, BH-146, BH-056; same-site by registrable domain), `PeekMotion` (the design's spring table with the
  Reduce Motion variants, drag thresholds 120 pt / 800 pt/s, rubber band offset^0.7) over `PeekSpringSet` (every
  channel retargets from its current value and velocity), `PeekAnimator` (display link, one `FramePacer` session and
  one Points of Interest interval per transition), `PeekOverlayView`, `PeekController`. Tokens `peekScrim`,
  `peekShadow`, `peekGrabber` in `ShellTokens+Peek.swift`.

### Checks (Engine app, profile `$PROF/313-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` with a synthetic Arc sidebar on loopback URLs, defaults suite, loopback pages on `127.0.0.1` and `localhost`)

| Check | Result | Evidence |
|---|---|---|
| Cross-site link in a Favorite opens a Peek; the source does not navigate | PASS | `link activation answered cancel`; CDP lists the source at its URL and the Peek page; window-only screenshots mid-open and at rest |
| Esc goes to the page first | PASS | page `keydown` with `preventDefault`: `usedEsc=1`, the Peek stays; the next Esc logs `peek unhandled Esc` and `peek close keyboard` |
| Close by control, scrim, Cmd-W | PASS | `peek close control`, `peek close scrim`, Cmd-W closes the Peek and the source tab stays |
| Cmd-O opens as a Today tab | PASS | "Peek Page" row at the top of Today, selected; the same page shown in the content card; mid-expand screenshot shows the mask growing around the page held in place |
| Add to Split View | PASS | sidebar split row "Source Page \| Peek Page", the Peek's page in the right pane |
| Peek inside a split, pane under 600 pt | PASS | Peek over the whole content area, scrim and recede on both panes |
| Peek inside a split, pane of 600 pt or more | PASS | Peek over the source pane only, controls in the 52 pt gutter; a click on the other pane logs `peek close scrim` |
| Drag down to dismiss | PASS | card follows the pointer, scales, scrim fades, controls gone; release past 120 pt logs `peek close fling` |

Found by the check and fixed with a failing test first: the controls were in reverse order (an unflipped container),
and the Peek's page never got the keyboard (`document.hasFocus()` false), so an Esc the page used still closed the
Peek through the responder chain; the Peek now focuses its page with `focusPage(of:)`. Reduce Motion was not toggled
on the shared machine; its variants are covered by the unit and GUI tests.

### Verification

- `gn check out/Spike '//arkt/*'` and `gn check out/Spike '//chrome/browser:core'`: `Header dependency check OK`.
  `nice -n 10 autoninja -C out/Spike -j 4 chrome`: `The build has finished successfully.` (one fix for explicit
  property synthesis first).
- Debug and Engine apps: `BUILD SUCCEEDED`.
- Frame-time gate: `PeekMotionOnScreenTests.testOpenAndCloseStayInsideTheFrameTimeGate` measured on this machine
  (120 Hz, load below the core count): 0 hitches over 8.6 ms for the open and the close in every run alone (9 runs)
  and with the other Peek GUI tests (3 runs). It failed twice at load 6 to 8 (other builds): once with the
  other Peek GUI tests (2 intervals over 8.6 ms, max 20.8 ms) and once in a full-suite run, where the existing
  `SpacePagerTests` pacing gate failed too, with main-thread passes of 9 to 14 ms. The last full run passed, with the
  timing gates skipped as NOT-MEASURABLE once the load passed the core count. A run on a quiet machine is still due.
- Red first: every new test was run failing (a compile error for the new seams and models, the control order and the
  page focus found by the real-app check).
- After the rebase on `dbbef68`: ShellKit `swift test --skip ShellKitGUITests`: 791 passed (736 + 55).
  `swift test --filter ShellKitGUITests`: 610 run (580 + 30), 9 skipped (5 not applicable to FakeEngine, 4 timing
  gates NOT-MEASURABLE under load), 0 failures. Debug and Engine apps: `BUILD SUCCEEDED`. ArktCore is not touched.

### Deviations from the plan

- Add to Split View commits the split at rest: the Peek's mask grows into the new right pane and the source card is
  re-laid out when the split appears, instead of both cards sliding together.
- Reduce Motion's Open as Tab and Add to Split View fade the Peek out, then fade the content in (opacity animation on
  the card), as the design's table says.
- A Peek closes when its source leaves the content area (a tab or Space switch) instead of staying hidden (#348).
- Keyboard closes keep the design's `firmFast` in-place close (0.15 s) rather than no animation.

### Deferred (follow-up issues)

- #345: Shift-click and `target=_blank` links in the Chromium engine (they go through `Browser::OpenURLFromTab`).
- #346: the "Peek closed" toast, Cmd-Z and Cmd-Shift-T reopen with history (BH-150, KB-079).
- #347: the Toolbar inside the Peek (BH-151), Copy URL on the Peek (KB-013, KB-014), Cmd-L.
- #348: Settings > Links UI, the full VoiceOver and keyboard path, XCUITest flows, Peek across tab and Space
  switches, an Instruments trace.
- BH-147 waits on #113; BH-153 and OS-03 stay out of scope.

## #314: Little Arkt (core)

Branch `feat/314-little-arkt`. Design: `docs/design/little-arkt.md`. Follow-ups: #352 (the Open in flight), #353
(links from other apps, nudge, profile), #354 (quick lookup and hotkey), #355 (archive), #356 (Dock and Window
menus, Opt-Cmd-click, UI tests).

### What landed

- **Overlay, no Chromium patch.** The window factory (`CreateArktBrowserWindow`) kept every Browser that is not
  `TYPE_NORMAL` as a Views window, so popups never reached the shell; `TYPE_POPUP` and `TYPE_APP_POPUP` now get an
  `ArktBrowserWindow` and the embedder's host. `ClassifyRequest` tells popups by their Browser type: a page's
  `window.open` with features (`NEW_POPUP`, `browser_navigator.cc`) is `TYPE_POPUP`, reported as `page`;
  `chrome.windows.create({type: "popup"})` is `TYPE_APP_POPUP` (`tabs_api.cc`), reported as `extension`; both carry
  the new `isPopup`. A size-only request (no left and top features) is centered over the last active window.
- **Tab move.** `ArktTabHandle.move(to:)` (facade, `DetachTabAtForInsertion` + `InsertDetachedTabAt`, active) and
  `EngineClient.moveTab(_:to:)`. The facade already reported a cross-window insert as `TabMoved` with the same handle
  and container; Chromium closes the emptied Browser (`WindowClosed`, no `TabClosed`). FakeEngine and InMemoryEngine
  do the same. Header change in both copies of `arkt_engine.h`.
- **Shell.** `LittleArktWindowController` (an `EngineWindowHosting` through `LittleArktEngineHost`), picked by
  `ShellWindowSet.host(for:)` for `.page` and `isPopup` requests: brand frame (`surfaceBrand`), 40 pt top bar with
  the host (lock only for https), Copy Link, the split button (mustard "Open in <Space>", quiet "Open as Tab" for a
  popup) and the Space chooser (Cmd-Opt-O); the requested page frame or 480 x 620 at the top-right with a 28 pt
  cascade; Open in (Cmd-O) fades the window out, then the main window adds the first Today row, maps it to the tab
  and calls `moveTab`; close by button, Cmd-W or Close Window goes through the engine; a page's `window.close()`
  fades the window out. Motion: `LittleArktMotion` on `SpringChannelSet` (Motion), transform on the content layer and
  opacity on the window (the system shadow fades with it), interruptible, fade-only Reduce Motion.

### Checks (Engine app on `out/Spike`, profile `$PROF/314-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, loopback pages on `127.0.0.1`, clicks in the page through CDP with a user gesture)

| Check | Result | Evidence |
|---|---|---|
| `window.open` with width and height opens in Little Arkt | PASS | `host asked kind=page popup ... bounds 660,227 480x560 answered ChromiumEngineKit.WindowHostAdapter`; window 492 x 606 centered over the opener; window-only screenshot |
| `left` and `top` honoured | PASS | `bounds 160,140 520x420`; the page's top-left at 160,140 under the top bar |
| Size-less popups cascade | PASS | 480 x 620, each 28 pt left and down from the frontmost Little Arkt window; first at 24 pt from the right, 20 pt under the menu bar |
| Page closes its popup (`window.close()`) | PASS | `browsers ... arkt=3`, the window and its target gone |
| Close button | PASS | real click (cliclick) on the red light; window and target gone |
| Open as Tab (click) and Cmd-O | PASS | `facade moving session id ...`, then `TabMoved,ActiveTabChanged,...,WindowClosed`; same DevTools target, an in-page marker and typed text kept (no reload), `window.opener` kept; "Sign In Popup" first in Today, selected |
| Space chooser | PASS after a fix | opens below the chevron with "Open in", the Space with Cmd-O, Copy Link |
| Extension popup window (`action-probe` worker over CDP: `chrome.windows.create({type: "popup"})`) | PASS | `host asked kind=extension popup (app popup Browser ...) bounds 322,129 420x520`; a 432 x 566 Little Arkt window |
| Extension normal window (`chrome.windows.create({url})`) | PASS | `kind=extension (show state or bounds given ...)`; a browser window, not Little Arkt |
| Cmd-W and Cmd-Shift-W in a Little Arkt window (real keys through the main menu) | PASS | each closed the frontmost Little Arkt window and its target |

Found by the check and fixed (tests first where testable): popups were Views windows (the factory filter), the chevron
drew NSButton's default title, the lock showed for http, the chooser opened over the chevron (a flipped button). An
instant synthetic first click (cliclick down and up together) on a top bar control of a window that is not key stays
in AppKit's tracking until another mouse-up; a held click and a quick click on the key window work. To recheck by
hand with a trackpad. Reduce Motion was not toggled on the shared machine; covered by unit and GUI tests.

### Verification

- `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.` (three incremental builds).
- Debug and Engine apps: `BUILD SUCCEEDED` (after the rebase on `56de14b`).
- ShellKit `swift test --skip ShellKitGUITests`: 823 passed (798 + 25). `swift test --filter ShellKitGUITests`:
  659 run (645 + 14), 5 skipped (not applicable to FakeEngine). The frame-time gates `PeekMotionOnScreenTests` and
  `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` failed in the full run beside two app builds and
  intermittently alone at load 6 on 10 cores (other builds); both passed in a run alone. Neither touches
  Little Arkt. ArktCore is not touched.
- Red first: the engine seams, the pure models and the window tests were written first and run failing (compile
  errors, then the close race and the test timing). The checks for the chevron title, the http lock and the chooser
  anchor were added together with their fixes after the real-app check and did not run red.

### Deviations from the plan

- Open in takes the design's no-flight path (fade out, then move) in every case; the flight with a snapshot is #352.
- Opacity is the window's (`alphaValue`) rather than the content layer's, so the system shadow fades with the
  content instead of a stand-in layer shadow.
- Reduce Motion's nudge dips the whole window to about 60 %, not only the frame (no nudge trigger until #353).
- A popup without a position is centered over the last active window by the engine, not over its opener window: the
  request does not carry the opener.
- The remembered size lasts for the session (#353 persists it).

## #300: one loaded copy (Tab Handoff, BH-066)

Date 2026-10-26. Branch `fix/300-one-loaded-copy` off `main` at `751efac`. Swift only: no patch, no overlay change,
`.patches` unchanged (7), no Chromium rebuild.

### Behaviour

BH-066 (CONFIRMED): two windows show the same Space, and a tab's web content is loaded in only one window at a time
(Tab Handoff). Selecting a row whose page is live in another window now moves that page into the selecting window
with #314's no-reload move (`EngineClient.moveTab`), with its history and state; nothing loads again. The window the
page left keeps the row (no longer selected there) and, where it showed the page, shows a placeholder ("This tab is
open in another window." and Move Here [I]); selecting the row there, or Move Here, moves the page back. The engine's
own pick of a next active tab in that window is not followed. A window whose last page moved out stays open without
an engine window, as after New Window; its next page makes a new one. A page whose close is held behind a leave-site
prompt stays where it is and nothing loads.

### What landed

- `ShellWindowController.openEngineTab(for:)`, the one place every window creates engine tabs (click, keyboard, the
  archive successor, split panes), asks the window set first (`onTakeOverLiveTab`, wired by `ShellWindowSet`). The
  holding window lets go (`releaseLiveTab(of:)`: mappings, row state, shown nodes, a shown pane closes as when its
  page closed), then the taker maps the tab and calls `moveTab` (`adoptHandedOffTab`).
- `.windowClosed` after a handoff of the last page keeps the shell window (`handsOffEngineWindow`).
- `WindowHostAdapter.detach()` gives the facade a never-shown stand-in window: Chromium orders its host window out in
  `ArktBrowserWindow::UnbindHost` when it destroys a closed window, after `.windowClosed`, which hid the shell window
  whose last page moved out. The shell already closes its own windows on `.windowClosed` (main and Little Arkt).
- `HandoffPlaceholderView` (`AXID.Handoff`).

### Checks (Engine app on `out/Spike`, `$CHROMIUM_ROOT/embed-300`, profile `$PROF/300-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, loopback pages on `127.0.0.1`, keys through System Events into the app's frontmost window)

| Check | Result | Evidence |
|---|---|---|
| Select in window B the row shown in window A | PASS | CDP page targets before and after the same 3 ids; `facade moving session id ... to window ...`, `TabMoved`, no `client tab inserted`; the page's marker, typed field text and `performance.timeOrigin` unchanged (no reload); window A shows the placeholder (window-only screenshots) |
| Move every page of A into B | PASS after a fix | before the adapter fix window A left the screen (`native window destroyed` ordered the host out); after it, A stays on screen with the placeholder, `browsers normal=1` |
| Select the row again in A | PASS | `facade createBrowser(host:)` for A's new engine window, `facade moving session id ...`; same target id, marker and `timeOrigin`; 3 page targets |

### Verification

- Red first: `TabHandoffTests` (8 GUI tests) failed to compile before the seam existed; a ninth, added with the
  real-app check (every page moved out one by one), passed at once on `InMemoryEngine`;
  `ChromiumMoveTabTests.aClosedWindowsTeardownCannotHideTheHostWindow` failed (the facade still saw the host's window).
- ShellKit `swift test --skip ShellKitGUITests`: 863 passed (862 + 1). `swift test --filter ShellKitGUITests`: 711 run
  (702 + 9), 5 skipped, 0 failures apart from the frame-time gates `PeekMotionOnScreenTests` and
  `SpacePagerTests.testFramePacingDuringSwipeAndKeyboardSwitch` at load 4 with other worktrees' work running; the
  pacing gate fails the same way on `main` without this change, and the Peek gate passed alone. ArktCore is not
  touched. Debug and Engine apps: `BUILD SUCCEEDED`.

## #345: Peek for Shift-click and `target=_blank` links

Date 2026-10-26. Branch `feat/345-peek-modifier-links` off `main` at `55fb137`. Design: `docs/design/peek.md`
("When a Peek opens", "Popups").

### What landed

- **Patch 0009** (two upstream files, `chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.cc`
  and its `BUILD.gn`; no hot file): `BrowserWebContentsDelegate::OpenURLFromTab` asks
  `arkt::ShouldDropLinkOpenedFromTab` before it builds its `NavigateParams` and returns `nullptr` when Arkt takes the
  link (the popup-blocked branch of the same function already returns `nullptr`). Justification: Blink turns a Shift-,
  Command- or middle-click into a `NEW_WINDOW`, `NEW_FOREGROUND_TAB` or `NEW_BACKGROUND_TAB` OpenURL, which never
  reaches the link activation throttle of patch 0008; for `NEW_WINDOW`, `chrome::Navigate` creates the window before
  any navigation starts, so no throttle can stop it. `BrowserWebContentsDelegate` is created inside
  `BrowserWindowFeatures` with no factory or override, so there is no seam without a patch.
- **Overlay.** `//arkt/browser:link_activation`: the decider takes a plain `LinkActivation` (source contents, URL,
  disposition) from both the throttle and the new check. The check asks only for a user-gesture, renderer-initiated
  link transition to HTTP(S), not POST, not from the context menu, with one of the three dispositions above. The
  facade reports the disposition and the modifiers Blink derived it from (`NEW_WINDOW` Shift, `NEW_BACKGROUND_TAB`
  Command, `NEW_FOREGROUND_TAB` Command-Shift). NEEDS-RUNTIME-CHECK: a middle click reads as Command and Shift-Option
  as Shift, because the browser only gets the disposition. No facade header change.
- **`target=_blank` without a patch.** A `target=_blank` link (or `window.open` without window features) arrives as an
  engine tab with an opener: `chrome::Navigate` sets the tab strip opener for a user gesture and the facade reports it.
  The window decides one main-actor turn after `.tabCreated`, once the tab's URL and activation have arrived in the
  same batch: `PeekRouting.routeOpenedTab` takes an active tab opened by a pinned tab or a Favorite to another site
  into the Peek (the engine's tab itself, with its page, history and opener; no second load); every other engine tab
  stays a Today row, selected when the engine made it active. A Command-Shift-click the window already answered with
  navigate is remembered for 2 s, so its foreground tab is not taken for a `target=_blank` link.

### Checks (Engine app, profile `$PROF/345-try`, scratch `ARKT_DATA_DIR` and defaults suite, loopback pages on `127.0.0.1` and `localhost`, input through CDP `Input.dispatchMouseEvent`)

| Check | Result | Evidence |
|---|---|---|
| `target=_blank` to the other host in a pinned tab opens a Peek | PASS | the engine's `b.html` tab shown in the Peek, no Today row, the source stays at `a.html`; window-only screenshot |
| Shift-click inside the Peek opens a Today tab | PASS | `link activation (disposition 6) answered cancel`; the Peek closes, a selected Today row with the page |
| Shift-click on a plain link in a pinned tab opens a Peek | PASS | `disposition 6` cancel; one window only, the Peek over the source |
| Command-click opens a background Today tab | PASS | `disposition 4` answered navigate; a new unselected row, the source stays shown |
| Command-Shift-click opens a foreground Today tab | PASS | `disposition 3` answered navigate; a new selected row, no Peek |
| `target=_blank` to the same host opens a Today tab | PASS | a new selected row, no Peek |
| `window.open(url)` without features in a pinned tab opens a Peek that keeps its opener | PASS | the engine's tab in the Peek, `window.opener` true in it (after a relaunch with the same profile) |

### Verification

- `gn check out/Spike '//arkt/*'` and `gn check out/Spike '//chrome/browser/ui/browser_web_contents_delegate/*'`:
  `Header dependency check OK`. `nice -n 10 autoninja -C out/Spike -j 4 chrome`: `The build has finished
  successfully.` `git -C $CR rev-list --count 156.0.8078.48..arkt` 9 = `.patches` 9.
- Debug and Engine apps: `BUILD SUCCEEDED`.
- Red first: the new routing tests failed to compile (`routeOpenedTab` missing).
- ShellKit `swift test --skip ShellKitGUITests`: 909 passed (902 + 7); after the rebase on #365, 936 passed
  (929 + 7). `swift test --filter ShellKitGUITests`: 747 run (743 + 4), 9 skipped, 0 failures (before the rebase).

### Deviations and checks still open

- Command-Shift-click on a `target=_blank` link goes through `AddNewContents`, not `OpenURLFromTab`, so it reaches
  the window as an active tab with an opener, like a plain `target=_blank` click, and opens a Peek from a pinned tab or
  a Favorite. NEEDS-RUNTIME-CHECK against Arc.
- The window remembers, for 2 s, a source whose modified click it answered with navigate, because no disposition
  reaches `.tabCreated`; that is what keeps a Command-Shift-click on a plain link a foreground Today tab.
- A `window.open` whose URL arrives after the tab's creation batch would see `about:blank` and stay a Today row; in
  the check above the URL was in the batch.
- The `link activation (disposition 1) answered navigate` line right after a `target=_blank` click is patch 0008's
  throttle asking about the new tab's own first navigation; it navigates because the shell does not list that tab yet.
- A `target=_blank` tab taken into a Peek replaces a Peek that is already open, whatever its source (one Peek per
  window at a time, as before).
- The window cannot tell a link from other engine tabs with an opener: `chrome.tabs.create` with `openerTabId` sets
  the tab strip opener too, so an extension that opens a cross-site tab from a
  pinned tab or a Favorite gets a Peek. This bends the popup decision ("Peek is only for link clicks").
  NEEDS-RUNTIME-CHECK against Arc; fixing it needs the facade to report how a tab was opened.
- Why patch 0009 has no alternative without a patch: `Browser::SetAsDelegate` sets `BrowserWebContentsDelegate` on
  every tab insert, detach and replace, so a forwarding delegate the facade installed would be overwritten on every
  tab strip change and would have to forward the whole `WebContentsDelegate` interface.


## #364: tab and pane Mute (BH-126), and a hidden Peek's sound (#348)

Date 2026-10-26. Branch `feat/364-tab-mute` off `main` at `6fd5738`, rebased on `4e15213`. Design:
`design/tab-context-menus/tab-context-menus.md` (3.6, section 10), `docs/design/peek.md` (Edge cases).

### What landed

- **Engine API.** `EngineClient.setMuted(_:muted:)`; `TabSnapshot.isAudible` and `isMuted`; events
  `.audibleChanged(_, isAudible:)` and `.mutedChanged(_, isMuted:)`, each reported once per change. Contract rule 17:
  `muteIsReportedOnce` (no driver) and `audibleStateIsReported` (driver `makeAudible`: `EngineContract.toneScript`, a
  Web Audio oscillator run with a user gesture). Chromium keeps reporting a muted page that plays as audible; the shell
  shows muted first.
- **Facade header (both copies, additive).** Event kinds `AudibleChanged = 14` and `MutedChanged = 15`; `isAudible`
  and `isMuted` on `ArktEngineEvent` and `ArktTabHandle`; `-[ArktTabHandle setMuted:]`. Justification: the frozen
  header had no way to report sound or mute (this file, W3-5a: "Audible state is not reported: the frozen header has no
  event kind for it"), and both #364 and #348 need it. Existing values and members are unchanged.
- **Facade.** `TabObserver` reports `WebContentsObserver::OnAudioStateChanged` and `DidUpdateAudioMutingState` (and
  re-reports both on a contents replacement); `setMuted:` calls `WebContents::SetAudioMuted` through `runOrQueue`.
  The self-test embedder logs both kinds. **No Chromium patch**; `.patches` 9 = `rev-list --count` 9.
- **ChromiumEngine** lists a tab with the handle's live sound state and drops a facade report of the value it already
  has. **InMemoryEngine** gains the `setAudible` driver. **FakeEngine** keeps `isMuted` and suspends media playback
  while muted (`setAllMediaPlaybackSuspended`; HTML media only, WKWebView has no public mute) and reports no audible
  state (no public signal).
- **Shell.** A row whose page plays or is muted shows an audio button (`speaker.wave.2.fill` / `speaker.slash.fill`,
  12 pt in a 20 pt box) left of the hover close slot, so the hover X never moves it; it fades in and out over 0.18 s
  when the sound starts or stops (at once under Reduce Motion) and swaps its glyph at once on a click. A click, the
  row's VoiceOver action ("Mute" / "Unmute") and the menu item all flip the tab's mute through the engine. The pane
  menu's Mute is enabled for a loaded pane and reads Unmute while muted. Today and pinned tab menus show Mute / Unmute
  only while the tab plays or is muted (see Deviations). Mute toggles are logged (`dev.arkt.shell`, category `audio`).
- **Peek (#348).** Hiding a Peek records its mute and mutes it; restoring puts the recorded mute back, so a Peek the
  user muted stays muted. A parked copy (`WebContents::Clone`) starts unmuted. Open as Tab and Add to Split View show
  the Peek's sound on the new row.
- **Cells.** A live sound change updates a realized cell's button in place (the only animated path); `configure` and
  reuse set it without a fade, so a reloaded or recycled cell never fades another row's state.

### Checks (Engine app on `out/Spike`, `$CHROMIUM_ROOT/embed-364`, profile `$PROF/364-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, tabs probe loaded, loopback pages on `127.0.0.1` and `localhost`, tone started through CDP with a user gesture, state read with `chrome.tabs.query` in the probe's worker)

| Check | Result | Evidence |
|---|---|---|
| A playing tab shows the audio button | PASS | `sidebar.row.audio` with label "Mute" on the Tone row; `audible: true` |
| Mute from the row's context menu | PASS | the menu shows Mute in its own group; `mute toggle: muted true`, `muted: true`, label "Unmute" |
| Unmute from the menu | PASS | the menu reads Unmute; `muted: false` |
| Mute from the menu of a row that is not the current tab | PASS | `muted: true` |
| The audio button mutes (AXPress) | PASS | `muted: true`, label "Unmute"; the engine keeps `audible: true` |
| A hidden Peek goes silent | PASS | Shift-click opened a Peek on the `localhost` tone page; after a tab switch `muted: true`, no `peek.card` |
| Restoring the Peek unmutes it | PASS | back on the source: `peek.card` again, `muted: false`, `audible: true` |
| A Peek muted before it was hidden stays muted | PASS | muted by `chrome.tabs.update`; hidden and restored: `muted: true` |
| Contract on real Chromium | PASS | `--arkt-engine-contract --arkt-engine-test-api` with the tabs probe: `ARKT_CONTRACT result 17/17` |

Before a relaunch, menu clicks on Mute / Unmute did not reach the shell in four attempts (one of them with the click
point confirmed as this app's by `AXUIElementCopyElementAtPosition` and no other GUI run on screen), while Copy Link
through the same clicks worked; part of that time another worktree's UI test run had windows on the same screen.
The cause was not found. After a relaunch with the `dev.arkt.shell:audio` log, all three menu attempts reached
`toggleMute` and the engine. To recheck by hand (Manual checks).

### Verification

- `nice -n 10 autoninja -C out/Spike -j 4 chrome`: `The build has finished successfully.` `git -C $CR rev-list --count
  156.0.8078.48..arkt` 9 = `.patches` 9.
- Debug and Engine apps: `BUILD SUCCEEDED`.
- Red first: the new tests failed to compile (`setMuted`, the event cases, `TabAudio`, `audioButton`,
  `HiddenPeek.wasMuted` missing), then passed.
- ShellKit `swift test --skip ShellKitGUITests`: 1066 passed (1047 + 19).
- ShellKit `swift test --filter ShellKitGUITests`: 902 run (886 + 16), 10 skipped (6 not applicable to FakeEngine,
  rule 17's audible check among them; 4 frame-time gates NOT-MEASURABLE at load 16 to 23 on 10 cores), 0 failures
  (897 in the full run; the 5 tests added after it, run with their suites: FakeEngine's two rule-17 tests, the
  reload and reuse tests of the audio button, and the Open as Tab one).
- Not run red first: FakeEngine's rule-17 tests and the audio button's reload and reuse tests (added with their fix
  after a review of the cell's reuse path). The Open as Tab test ran red (the adopted row showed no sound).

### Deviations

- Tab rows: BH-126 confirms Mute only on panes; the Today and pinned menus offer it only while the tab plays or is
  muted, and Favorites not at all (their playing indicator, BH-051, and the media tray, BH-184, stay with #117).
  PARITY(NEEDS-RUNTIME-CHECK) for the audio button's place and glyphs.
- A hidden Peek's video keeps decoding, muted; pausing it would need the page.

## #401: why an engine window closed

Date 2026-10-26. Branch `feat/401-window-close-reason` off `main` at `fbe0e5a`, rebased on `8e44130`. Follow-up from
#386 (#392, "Known limitation").

### What landed

- **Engine API.** `.windowClosed(EngineWindowID, reason: WindowCloseReason)` with `userClose` (`closeWindow`, the
  host's `onCloseRequested`, the engine's own Close Window), `extension` (`chrome.windows.remove`), `lastTabClosed`
  (the engine closed a window emptied by a tab close or a tab moved out) and `appQuit`. Contract rule 11 checks the
  reason: `closeWindow` and the host's close request report `.userClose`, a window whose last tab moved out
  `.lastTabClosed` (new check `emptiedWindowReportsLastTabClosed`), and an extension's close reports its tabs and
  itself with `.extension` (new check `extensionWindowCloseReportsExtension`, driver `engineCloseWindow`).
- **Facade header (both copies, additive).** `ArktWindowCloseReason` (`None`, `User`, `Extension`, `LastTabClosed`,
  `AppTerminating`) and `windowCloseReason` on `ArktEngineEvent`, set on `WindowClosed` only. Justification: the
  header had no way to tell a window close the user or an extension asked for from Chromium closing an emptied
  `Browser`, and #378's parked copies made the difference reach the shell. Existing values and members are unchanged.
- **Facade.** `OnBrowserClosed` (from `BrowserDidClose`, the `Browser` and `ArktBrowserWindow` still alive) reads the
  reason: quitting wins, then `ArktBrowserWindow::IsClosedByExtension()` (already used for the tabs' reason), then
  `TabStripModel::closing_all()` (a window close: `user`), else `lastTabClosed`. Logged as `facade window closed,
  reason ...`; the self-test embedder logs it too. **No Chromium patch**; `.patches` 9 = `rev-list --count` 9.
- **Engines.** `ChromiumEngine` maps the facade value (`None` maps to `userClose`, so a close the facade did not
  classify takes the shell window with it). `InMemoryEngine` reports all four and gains the
  `engineCloseWindow(_:reason:)` driver; `FakeEngine` reports `userClose` and `lastTabClosed` (no extensions).
- **Shell.** On `.windowClosed` the window stays without an engine window only for `.lastTabClosed` (with
  `keepsWindowWithoutEngine` set and no close request of its own). An extension's close, the user's and quitting
  take it with them, which closes #392's known gap.
- **Contract runner and tabs probe.** The runner's `engineCloseWindow` asks the probe's service worker to call
  `chrome.windows.remove`: the facade tells an extension call by its keepalive, which a worker call holds and a call
  from the probe's control page does not (a first run from the control page reported `user`).

### Checks (Engine app on `out/Spike`, built into `$CHROMIUM_ROOT/embed-364`, profile `$PROF/401-try`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, tabs probe loaded, loopback pages on `127.0.0.1`, Cmd-W through System Events into the app's own frontmost window, `chrome.windows.remove` through CDP in the probe's worker)

| Check | Result | Evidence |
|---|---|---|
| Contract on real Chromium | PASS | `--arkt-engine-contract --arkt-engine-test-api` with the tabs probe: 28 checks, `ARKT_CONTRACT result 17/17`; `native window close by chrome.windows.remove`, both tabs `reason extension`, `facade window closed, reason extension` |
| Cmd-W on the last loaded Today tab keeps the window | PASS | three Today rows, one loaded: `tab closed ... reason client`, the sibling shown, the window stays (the parked copy keeps the `Browser`, so no `WindowClosed`) |
| `chrome.windows.remove` right after that Today close | PASS | `reason extension` for both tabs and the window; the shell window is gone (no window left for the process), the app keeps running |
| Cmd-W down to the last Today tab | PASS | two Cmd-W: the window stays on the empty card of the Space |

A first launch showed onboarding (the Engine configuration is not `DEBUG`, so `ARKT_SKIP_ONBOARDING` is ignored);
it was finished through AX presses. One launch lost its window to a `user` close eight seconds in, with no input of
this check in flight while another worktree's first-run check had an app on the same screen; the cause was not found
and the next launches did not repeat it.

### Verification

- `nice -n 15 autoninja -j 4 -C out/Spike chrome`: `The build has finished successfully.` `git -C $CR rev-list
  --count 156.0.8078.48..arkt` 9 = `.patches` 9.
- Debug and Engine apps: `BUILD SUCCEEDED`.
- Red first: the new tests failed to compile (`ArktWindowCloseReason`, `WindowCloseReason`, `engineCloseWindow`
  missing). With the reason gate taken out of the shell again, the 4 new `LastTabCloseTests` failed (the window
  stayed), then passed.
- ShellKit `swift test --skip ShellKitGUITests`: 1137 passed (1129 + 8).
- ShellKit `swift test --filter ShellKitGUITests`: 996 run (990 + 6), 10 skipped (7 not applicable to FakeEngine,
  `extensionWindowCloseReportsExtension` among them), 3 frame-time gates failed at load 7 to 10 on 10 cores
  (`PeekMotionOnScreenTests`, `SidebarHideTests.testRevealPacing`, `SpacePagerTests` frame pacing) and passed when
  run again on their own (7 tests, 0 failures); no other failure.

### Deviations

- A window the user closes with no tab at all reads as `lastTabClosed` at the facade (no `CloseAllTabs` ran). The
  shell's own close request covers the close button and Close Window; Chromium's own Close Window command on an
  emptied window that keeps itself would keep the shell window.
- FakeEngine has no extensions: `extensionWindowCloseReportsExtension` is not applicable there.
- An extension call from an extension page that holds no keepalive (a popup, an options page) is still told apart
  only as `user` (week-3 Decision 12's limit, `arkt_extension_calls.h`).

## #370: page thumbnails for the command bar preview (shared with #352)

Date 2026-10-26. Branch `feat/370-page-thumbnails` off `main` at `c68bf21`. Design: `design/command-bar/` (Preview
column). One snapshot call serves both #370 and #352 (shape posted on #352).

### What landed

- **Facade header (both copies, additive).** `-[ArktTabHandle copyFrameWithMaxPixelSize:completion:]`: the tab's
  current frame as PNG with its pixel size and its pixels per point; `NSZeroSize` copies the full frame at the backing
  scale. Existing members are unchanged.
- **Facade.** `RenderWidgetHostView::CopyFromSurface` with the output size computed from the view bounds and the device
  scale, so viz scales on the GPU; 2 s copy timeout; the answer is posted back to the UI thread, the PNG is encoded on
  the thread pool (`PNGCodec::FastEncodeBGRASkBitmap`), and the completion runs on the UI thread, never inside the call.
  A discarded tab, a pending or closed handle, or a view whose surface is not available for copy answers nil; the tab
  is never shown, woken or reloaded. `//components/viz/common` added to the overlay's deps. **No Chromium patch**;
  `.patches` 9 = `rev-list --count` 9; `gn check out/Spike '//arkt/api:*'` OK.
- **Engine API.** `EngineClient.pageImage(of:_:) async -> PageImage?` with `PageImageRequest.thumbnail` (600 x 360 px,
  80 KB) and `.fullFrame` (no caps, PNG, for #352). `PageImage` is `Data` (PNG or JPEG) plus pixel size and scale, so it
  stays `Sendable`. `PageImageEncoder` (`@concurrent`) applies the caps: never upscales, keeps the aspect, steps the JPEG
  quality down (0.8 to 0.2) and then halves the size until the byte cap holds, else nil; a facade PNG that already fits
  passes through.
- **History cache.** `PageImageCache` (actor): the last thumbnail per page, keyed by SHA-256 of the URL (no URL part in
  a file name), at most 200 entries and 20 MB, oldest stored evicted first, kept across launches. `PageThumbnails`
  combines engine and cache: a live tab's image is stored under the URL it still shows after the copy; a tab without a
  frame gives its cached image or nil; a history item gives its cached image or nil, never a fetch.
- **Engines.** ChromiumEngine through the facade (logs size and time, never the URL). FakeEngine through WKWebView
  `takeSnapshot` at the width that fits the cap (nil for a tab not in a window). InMemoryEngine draws a deterministic
  image per URL (`setFrameAvailable` driver for the no-frame case), for command bar tests with no engine.
- **App.** The session owns `pageThumbnails` (for #372) over `<Caches>/<bundle id>/PageImages`, or
  `<ARKT_DATA_DIR>/Caches/PageImages` in development and test runs; Clear Archive empties it
  (`ArchiveListModel.onCleared`). Contract rule 18 (`pageImageFitsTheCaps`, `pageImageOfAClosedTabIsNil`, driver
  `showPage`); the in-app runner prints the thumbnail's size and time.

### Checks (Engine app on `out/Spike`, `$CHROMIUM_ROOT/embed-370`, bundle id `dev.arkt.ArktShell.try370`, profile `$PROF/370-try` with `--use-mock-keychain`, scratch `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and defaults suite, tabs probe loaded, loopback pages)

| Check | Result | Evidence |
|---|---|---|
| Contract on real Chromium, all rules | PASS | `--arkt-engine-contract --arkt-engine-test-api`: `ARKT_CONTRACT result 18/18` |
| Live thumbnail of a loaded, shown page | PASS | `ARKT_CONTRACT page image png 498x360 px @0.69, 5640 bytes in 12 ms` (a 720 x 520 pt runner window at 2x: 1440 x 1040 px scaled to fit 600 x 360); decodes to the size it reports |
| Full frame of the same page | PASS | at least as large as the thumbnail (rule 18) |
| Closed and unknown tab | PASS | nil (`pageImageOfAClosedTabIsNil`, 69 ms) |

### Verification

- `nice -n 10 autoninja -C out/Spike -j 4 chrome`: `The build has finished successfully.` (facade object and
  `libchrome_dll.dylib` rebuilt).
- Debug and Engine apps: `BUILD SUCCEEDED`.
- Red first: the new tests failed to compile (`PageImage`, `PageImageRequest`, `pageImage(of:_:)`,
  `copyFrame(maxPixelSize:completion:)` missing), then passed. The two `onCleared` tests were written with the hook and
  not run red.
- ShellKit `swift test --skip ShellKitGUITests`: 1277 passed (1236 + 41; the baseline is 1277 minus the 41 tests
  added, not a run on `main`). ArktCore `swift test`: 428 passed (unchanged).
- ShellKit `swift test --filter ShellKitGUITests.FakeEngineContractTests`: 34 run (31 + 3), 7 skipped (not applicable
  to FakeEngine), 0 failures. The rest of the GUI suite was not run: no shell UI changed.

### Deviations

- The issue asks FakeEngine for deterministic synthetic images; FakeEngine is the WKWebView stand-in and returns real
  snapshots, and InMemoryEngine (what the command bar tests use) returns the deterministic ones.
- A hidden tab whose surface Chromium still holds gives that last frame (no wake-up); one whose surface was evicted
  gives nil, and `PageThumbnails` falls back to the cache. Not checked on real Chromium: rule 18 covers shown tabs.
- "History clearing" has no command yet; only Clear Archive empties the cache. The preview UI (#371, #372) is not part
  of this change.

## #268: ChromiumEngineKit linked only in the Engine configuration

### What landed

- `project.yml`: the `ChromiumEngineKit` and `EngineAPITestSupport` package dependencies say `link: false`. Xcode
  still builds both products in every configuration (the Engine compile needs their modules), but only the Engine
  configuration links them, through `OTHER_LDFLAGS` naming `$(BUILT_PRODUCTS_DIR)/<product>.o`.
- The Engine configuration also passes the facade header's module map (`OTHER_SWIFT_FLAGS`, `-fmodule-map-file`). A
  linked product used to pass it; without it the explicit module scan of `App/Engine` failed ("Unable to resolve module
  dependency"), because the kit's swiftmodule loads the facade module for its `internal import`.
- Isolation tests: the two products are the only ones with `link: false`, their objects appear in exactly one
  `OTHER_LDFLAGS`, under `Engine`, and only `App/Engine` imports them. The facade module check on `project.yml` is
  narrowed from "never named" to "named only in the Engine module map flag, and never a dependency".

### Verification

- `xcodegen generate` (2.46.0): the two products are target dependencies and absent from the Frameworks phase.
- Debug, Release and Profile builds: `BUILD SUCCEEDED`. `nm` on the Debug stub, `ArktShell.debug.dylib`, the Release
  and the Profile binary: 0 `ArktShellEmbedder` or `ChromiumEngineKit` symbols, 0 `EngineAPITestSupport` symbols,
  `strings` finds no `ArktShellEmbedder`; `otool -L` lists no engine framework. Before the change, a Debug
  `ArktShell.debug.dylib` built from `main` defined `_OBJC_CLASS_$_ArktShellEmbedder`.
- Engine build (`ARKT_ENGINE_APP` set to `out/Spike/Chromium.app`, derived data outside the Chromium disk):
  `BUILD SUCCEEDED`; the binary defines `_OBJC_CLASS_$_ArktShellEmbedder` and lists it in its Objective-C class list
  (`otool -ov`), which is what `NSClassFromString` reads. The app was not launched.
- ShellKit `swift test --skip ShellKitGUITests`, rebased on `5ebda1f`: 1284 passed; isolation suites 34 (28 + 6).
  ArktCore `swift test`: 428 passed (428 + 0).

### Deviations

- The facade module map flag in `project.yml` (above), and the narrowed isolation check that allows it.

## #128: product bundle id, data folder, engine user-data-dir and branding

Date 2026-10-26. Branch `engine/128-product-bundle-id` off `main` at `7940026`. Decision: #73 (`dev.arkt.*`).

### What landed

- **Bundle id.** `engine/arkt/branding/BRANDING` `MAC_BUNDLE_ID` `com.arkt.Arkt` -> `dev.arkt.Arkt`; the app's
  `PRODUCT_BUNDLE_IDENTIFIER` `dev.arkt.ArktShell` -> `dev.arkt.Arkt`. The framework and helpers derive from the
  branding file, so no `com.arkt.*` id remains. `ProductIdentityTests` pins both ids to each other.
- **Branding strings.** `CFBundleName` and `CFBundleDisplayName` `Arkt Shell` -> `Arkt` (the keychain prompt text, W3-11).
  The executable and bundle file name stay `ArktShell`.
- **Data folder.** Unchanged: `~/Library/Application Support/Arkt` (`DatabaseLocation.productFolderName`, now a named
  constant with a test). The engine's default user-data-dir lives inside it, as `Arkt/Engine`.
- **`CrProductDirName`.** The Engine build phase writes it from the build setting `ARKT_PRODUCT_DIR_NAME`
  (`Engine.xcconfig`, default `Arkt Dev Engine`, so the development path is unchanged). A product build passes
  `ARKT_PRODUCT_DIR_NAME=Arkt/Engine`; the release configuration (#334) sets it in its own xcconfig. The build phase fails
  on an empty value. Chromium reads the key from the outer bundle (`chrome_paths_mac.mm`), so it is a seam: **no
  Chromium patch**, `.patches` 9 = `rev-list --count 156.0.8078.48..arkt` 9.
- **Keychain.** Untouched. Patch 0003 keeps the product item "Arkt Safe Storage"; the maintainer keeps the existing
  "Chromium Safe Storage" item (#20). `grep -a -c` on `Arkt Framework`: `Arkt Safe Storage` 1, `Chromium Safe Storage` 0.
  Nothing read or wrote the keychain (`--use-mock-keychain`).
- **Facade header:** not changed; both copies byte-identical (`cmp`).

### Checks

Engine app on the rebuilt `out/Arkt` framework, bundle id `dev.arkt.ArktShell.try128` (own id, never installed),
`ARKT_PRODUCT_DIR_NAME=Arkt/Engine`, copy on the internal disk, `CFFIXED_USER_HOME` pointing at an empty throwaway home
so the defaults resolve there and not in the real `~/Library/Application Support`, `--use-mock-keychain`, no
`--user-data-dir` and no `ARKT_DATA_DIR`.

| Check | Result | Evidence |
|---|---|---|
| Ids in the rebuilt `out/Arkt` | PASS | app `dev.arkt.Arkt`; framework `dev.arkt.Arkt.framework`; helpers `dev.arkt.Arkt.helper` (Helper, GPU, Aperitif, Aperitif GPU), `dev.arkt.Arkt.helper.renderer` (Renderer, Aperitif Renderer), `dev.arkt.Arkt.framework.AlertNotificationService` (Alerts, Aperitif Alerts); no `com.arkt` string in the framework binary |
| App Info.plist | PASS | `CFBundleIdentifier=dev.arkt.ArktShell.try128`, `CFBundleName=Arkt`, `CFBundleDisplayName=Arkt`, `CrProductDirName=Arkt/Engine`, `ArktEngineFrameworkName=Arkt Framework` |
| Development path | PASS | the Engine build on `out/Spike` gives `CrProductDirName=Arkt Dev Engine` |
| Shell data folder | PASS | `<home>/Library/Application Support/Arkt/Arkt.sqlite` |
| Engine user-data-dir | PASS | `<home>/Library/Application Support/Arkt/Engine` holding `Default`, `Local State`, `Crashpad`; cache `<home>/Library/Caches/Arkt/Engine` |
| Mach rendezvous | PASS | `launchctl print gui/<uid>`: `dev.arkt.ArktShell.try128.MachPortRendezvousServer.<browser pid>` (follows the outer app); 7 helpers ran from the bundle with no rendezvous error |
| Real folders | PASS | `~/Library/Application Support/Arkt/Engine` still absent after the run; the real `Arkt` and `Arkt Dev Engine` folders untouched |
| Quit | PASS | `kill <browser pid>`; the browser and all 7 helper pids gone after 6 s |

One `ERROR:net/disk_cache/disk_cache.cc: Unable to create cache` line appeared in the throwaway-home run (the cache
folder sits under the long scratch path); not investigated further, no effect on the checks.

### Verification

- Red first: `ProductIdentityTests` failed on the old ids and `DatabaseLocationTests` did not compile
  (`productFolderName` missing), then both passed.
- ShellKit `swift test --skip ShellKitGUITests`: 1292 passed (baseline 1287 + the 5 `ProductIdentityTests`). ArktCore `swift test`: 429 passed (428 + `DatabaseLocationTests`).
- `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.` (nothing to rebuild; the overlay
  is unchanged). `nice -n 15 autoninja -C out/Arkt chrome -j 4`: `The build has finished successfully.` (branding
  change).
- Engine app: `xcodebuild -scheme ArktShell -configuration Engine`: `BUILD SUCCEEDED` on `out/Spike` (development
  value) and on `out/Arkt` (product value, own bundle id).

### Cleanup

Test copy, throwaway home, embed folders and probe removed. The test bundle was registered with LaunchServices by the
launch itself; `lsregister -u` was run, but one record for the deleted path (`dev.arkt.ArktShell.try128`, unique id) is
still listed and will be dropped by LaunchServices' own cleanup. It cannot take over any real app's links.

### Left open

- The release configuration (no test-only code, product `ARKT_PRODUCT_DIR_NAME`) is #334; signing is #125.
- Existing installs of the placeholder id: none ship; the maintainer's `~/Applications/ArktTest` bundle keeps its old id
  until it is rebuilt.

## #400: slice 1, JavaScript alert, confirm and prompt in the shell's dialog panel

Date 2026-10-26. Branch `engine/400-dialog-restyle` off `main` at `db420d5`. Plan: the engine plan comment on #400. This is
the first of three slices (JavaScript dialogs, then permission prompts, then infobars); the pull request is `Refs #400`.

### What landed

- **Hook, no patch.** `TabModalDialogManager` decides everything about a page's dialog (foremost tab, a background
  `alert()` staying pending, auto-dismissal of a confirm or prompt when its tab is hidden, a navigation, a later dialog,
  the tab closing). Its delegate is private and set when `TabHelpers` creates the manager, but
  `JavaScriptTabModalDialogManagerDelegateDesktop::CreateNewDialog` is virtual and `RemoveUserData(UserDataKey())` plus
  `CreateForWebContents` are public. `arkt_javascript_dialog.{h,mm}` subclasses the desktop delegate and swaps it in per
  tab where `UseArktPermissionPrompts` is called (insert and contents replacement; a marker makes a second call a no-op).
  Per request the subclass hands the dialog to the facade when the tab is in an embedder-host window and the facade
  takes it; every other case falls back to Chromium's own Views dialog. The dialog object (`ArktJavaScriptDialog`) is the
  manager's `TabModalDialogView`, owns itself, holds the tab's `ScopedTabModalUI` as the Views dialog does, and ends once.
  `.patches` stays 9 = `git rev-list --count 156.0.8078.48..arkt` 9.
- **Facade header (both copies, additive; `cmp` identical).** `ArktDialogKind`, event kinds `DialogRequested` (16) and
  `DialogEnded` (17), `dialog` on `ArktEngineEvent`, and the `ArktJavaScriptDialog` protocol (kind, tab, title,
  message, default prompt text, accept and cancel titles, `isEnded`, `-respondAccepted:userInput:`). The strings are
  Chromium's (`IDS_APP_OK`, `IDS_APP_CANCEL`, the manager's "origin says" title). One `DialogEnded` per request, however
  it ends; an answer after the end returns NO and does nothing.
- **EngineAPI.** `JavaScriptDialog`, `DialogID`, `EngineEvent.dialogRequested` / `.dialogEnded`, and
  `EngineClient.respond(to:accepted:userInput:)` (default no-op). Contract rule 19 (two checks): a request carries the
  engine's strings, an answer ends it once, and a pending dialog ends before its tab's `.tabClosed`. `ChromiumEngine`
  ends a tab's pending dialog before it reports the tab closed even when the facade reports the end after `TabClosed`
  (the real order, scripted in `ScriptedFacade`). `InMemoryEngine` gains the `raiseDialog` driver and `dialogAnswers`.
- **ShellUI.** `JavaScriptDialogPresenter` shows each pending dialog of a shown tab as the anchored `DialogPanel`
  (top-leading corner 12 pt inside the page, key focus on show, since the page is blocked) and answers the engine. A tab
  that is not on screen keeps its dialog pending without a panel and gets it back when shown (`setShown` calls
  `refresh()`); the engine's own end closes the panel with no answer. `DialogContent` gains an optional text field (a
  prompt: focus starts in it, text selected) and `bodyMaxHeight` (the body scrolls past 240 pt, since Chromium allows 24
  lines of 80 characters). Escape answers Cancel; an `alert()` has only OK, so Escape accepts it as Chrome does.

### Checks (Engine app on the rebuilt `out/Arkt`, bundle id `dev.arkt.Arkt.try400` (own id), copy on the internal disk, throwaway data folders and defaults suite, `--use-mock-keychain`, a loopback page on `127.0.0.1` with one button per dialog, keys and clicks only into the app's own frontmost window)

| Check | Result | Evidence |
|---|---|---|
| `alert()` | PASS | panel "127.0.0.1:18400 says" with OK as the focused mustard default; Return; the page continued (title `alert-returned`) |
| `confirm()` Escape / Return | PASS | Escape: page got `false`; Return: `true` |
| `prompt()` typed text, Return | PASS | field started with the default text selected; typing "Grace" and pressing Return while editing: page got `Grace` |
| `prompt()` Escape | PASS | page got `null` |
| Long `alert()` (40 lines) | PASS | the body is capped and scrolls; OK stays visible |
| One panel, no Chromium dialog | PASS | window list of the browser pid while a dialog was up: the main window plus exactly one 420 pt panel; none after the answer |
| Stderr | PASS | `facade dialog requested kind=0,1,1,2,2,0,1` for the seven dialogs raised, one `DialogEnded` batch per answer |
| Confirm, then switch tab | PASS (re-checked, see "Review follow-up") | see the follow-up below; the first run only lacked a pointer move before its synthetic clicks |

### Verification

- Red first: `JavaScriptDialogTests` did not compile before the engine types existed (the shell's event switch was
  not exhaustive). With `javaScriptDialogs.refresh()` taken out of `ShellWindowController.setShown`,
  `JavaScriptDialogWindowTests.testSwitchingTabsHidesTheDialogWithoutAnsweringAndShowingTheTabBringsItBack` failed
  (the panel stayed up), then passed.
- ShellKit `swift test --skip ShellKitGUITests`: 1339 passed after merging `main` at `6c5a9cd` (baseline 1312 + 27: 9 `JavaScriptDialogTests`, 5
  `JavaScriptDialogContentTests`, 6 `ChromiumDialogTests`, 1 `JavaScriptDialogABITests`, 4 contract checks over the two
  scripted orders, 2 in-memory contract checks; the baseline is the total minus the new tests, not a run on `main`).
  ArktCore `swift test`: 429 passed (unchanged).
- GUI tests run: `JavaScriptDialogPresenterTests` (11), `JavaScriptDialogWindowTests` (3), `DialogTests`,
  `DeleteSpaceTests`, `AccessibilityIdentifierTests`, `FakeEngineContractTests` (rule 19 not applicable to FakeEngine, 2
  skipped); 0 failures. The rest of the GUI suite was not run.
- `nice -n 15 autoninja -C out/Spike chrome -j 4` and `-C out/Arkt chrome -j 4`: `The build has finished successfully.`
  Engine app: `xcodebuild -scheme ArktShell -configuration Engine` with `PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try400`:
  `BUILD SUCCEEDED` (after `xcodegen generate`: the ignored project was older than `main`).

### Deviations

- The self-test embedder (`--arkt-facade-selftest`) is an embedder host with a sink, so it receives `DialogRequested`
  and draws nothing; the page waits until the self-test's `answer` command ends it. The plan said the engine-drawn UI
  stays the fallback while no embedder presents a surface; for this slice the Views dialog is the fallback only when
  the window has no embedder host or the facade has no sink.
- The in-app contract runner has no `raiseDialog` driver (a real tab must be foremost for Chromium to show it), so
  rule 19 is reported as not applicable there; real Chromium is covered by the checks above.
- `ArktJavaScriptDialog::GetUserInput` returns the default text; it is read only when the engine itself accepts the
  dialog without an override (the test API passes one).
- The first run's synthetic clicks on the sidebar did not switch tabs; the cause was the input, not the panel (see "Review follow-up").

### Left open

- Slice 2: permission prompts through the facade (same panel, `PermissionRequested` / `PermissionEnded`).
- Slice 3: infobars (`InfobarsChanged`, a shell row from the design's `infobar` state).
- `beforeunload` stays Chromium's app-modal dialog (#265).
- Cleanup: test copy, throwaway data, embed folder and derived data removed; `lsregister -u` was run, and records for the
  deleted `dev.arkt.Arkt.try400` path are still listed (LaunchServices drops them itself, as noted for #128).

### Review follow-up (head after 1f5e4cd)

- **Decision (also on #400):** JavaScript dialogs keep Chromium's behaviour. Return accepts at once, with no
  input-protection delay, as in Chrome and Safari. The 0.5 s protection is only for permission prompts (slice 2).
- **Tab switch with a dialog up: no behaviour change was needed.** Real app (below): one click on a sidebar row and the
  Previous Tab shortcut switch tabs with an alert up and with a confirm up. The earlier failures came from `cliclick`
  pressing without moving the pointer first (such a press is also lost with no dialog up); with `m:x,y w:300` before
  the press every click lands. The panel is key, so the shell window is not, and the sidebar outline accepts the first
  click (`acceptsFirstMouse` is true for `NSOutlineView`); a test pins it (`testOneClickOnARowSwitchesTabsWithADialogUp`,
  alert and confirm, `NSWindow.sendEvent` level). A confirm ends false on switch-away (`kTabHidden`), an alert stays
  attached and reappears on return.
- **Bug found by the real-app run, fixed:** after a mouse answer (a click on OK) the panel stayed ordered in at opacity 0
  over the page, because the 0.10 s fade's completion block held the `DialogPanel` weakly and the presenter drops it at
  the answer. Keyboard answers (instant) never showed it, and the unit tests held the panel strongly. The completion now
  captures the window. Test: `testAMouseAnswerLeavesNoPanelBehind` (red before the fix, 5 s timeout).
- **Dialog that arrives with nothing to show it on:** the presenter refreshes on `didDeminiaturize`,
  `didChangeOcclusionState`, `NSApplication.didUnhide`, and after the next layout of the window when a pending dialog
  found no page view (`ShellRootView.onLayout`). The window state is injected (`windowIsVisible`); a test per event.
- **Contract rule 19, third check** `hiddenTabEndsItsConfirmAndPrompt`: a confirm or prompt ends when its tab stops
  being active. `InMemoryEngine` ends it; the scripted facade models `kTabHidden`; FakeEngine reports it not
  applicable. Red first with `InMemoryEngine`'s end taken out (timeout). The `Task.sleep(100 ms)` in
  `dialogIsReportedAnsweredAndEndedOnce` is replaced by waiting for the end, then for a later request: events arrive in
  order, so a second end would show up before it.
- **Reduce Motion:** `testReduceMotionPanelFadesWithoutTravel` (fade without a transform animation, against the usual
  entrance with one).
- Not done: finding 3 (a tab moved to another window with a pending alert) and finding 6 (panel width fixed at
  creation); left for a later slice.

#### Real-app check (`dev.arkt.Arkt.try400`, Engine configuration on `out/Spike`, throwaway profile and data folders,
`--use-mock-keychain`, a loopback page on `127.0.0.1:18400`, real `cliclick` input with a pointer move first)

| Check | Result |
|---|---|
| Baseline, no dialog: one click on a row | PASS, three of three switched (window key) |
| Confirm up, one click on a row | PASS: switched, the confirm ended false (`A confirm-false`), no panel left |
| Alert up, one click on a row | PASS: switched, panel hidden, back on the tab the panel reappears |
| Previous Tab shortcut with an alert, and with a confirm, up | PASS: switched, panel gone |
| Click on OK (mouse), before the fix | FAIL: invisible panel left (4 after four dialogs) |
| Click on OK (mouse), after the fix | PASS: no panel window left |

## #352: Little Arkt's Open in flight

Branch `feat/352-little-arkt-flight`. Design: `docs/design/little-arkt.md`, Motion (`la-kf-promote-*`,
`la-kf-interrupt-220ms`). Shell only: the snapshot is `EngineClient.pageImage(of:_:)` with `.fullFrame` (#370); no
Chromium patch, no facade change.

### What changed

- `LittleArktFlight` draws the page's snapshot on its plate on `LittleArktFlightOverlay`, a transparent, click-through
  borderless window spanning both windows, above both. Nothing changes until the first display frame; the card then
  flies with its center, mask size and scale on `firmSlow` and its opacity back to 1, from wherever the appear has it.
- The small frame fades at once (`fadeOut`, 0.12 s) and the main window comes forward. A snapshot that misses the first
  frame fades in on the plate (critical 0.16 s).
- The Today row is added at the start, drawn by the flight's clock: the rows below hold their place, make room after
  200 ms and the row fades in from 0.96 at 290 ms (`springyFast`, `SidebarArrivalLayout` through the folder motion row
  styles). At rest the page moves once (`moveTab`), is selected and mounted at its final size; the next display frame
  starts the 0.1 s crossfade, and the overlay is removed.
- No flight (today's fade-out path): Reduce Motion, no open main window, or one minimized, on another desktop, in full
  screen or off every screen (`LittleArktFlightConditions`).
- A flight that cannot land by itself ends with `LittleArktFlight.abort(_:)`, which orders the overlay out and tells
  the window controller what to do with the page: the main window miniaturizing, the main window's display link
  stopping (two quiet checks of a watchdog on an injected clock, counted in frames, never seconds), the app
  terminating, the small window closing, and Cmd-W or the close button land the page in the main window at once,
  without the flight; the main window closing keeps the page in the small window and drops the row made for it; the
  page closing itself (`window.close()`) drops the row and lets the engine close the window, with no appear on it.
  Cmd-W mid-flight lands first and then closes (it is never ignored). A released flight orders its overlay out.
- `LittleArktAnimator.run` reads its clock once per run (#450); `beginFlight` reads the window's clock once.
- An arrival frame reads one row height (the arriving row's) instead of all of them.

### Verification

- Red first: the motion and flight tests failed to compile (types missing), then passed. Break check: landing on the
  first flying frame instead of at rest (`LittleArktFlight.tick`, the `isSettled` gate) turned three flight tests red;
  restored.
- ArktCore `swift test`: 428 passed (unchanged).
- ShellKit `swift test --skip ShellKitGUITests`: 1299 passed (1298 before the abort fixes + 1; the earlier baseline
  is 1298 minus the 11 tests added, not a run on `main`).
- ShellKit `swift test --filter ShellKitGUITests` before the abort fixes (not re-run after them; the Little Arkt
  suites above were): 1103 run, 18 skipped, 0 failures (load average 22.6). An earlier run
  before the merge of `main` had one failure, the `SpaceSwipeHitchTests` main-thread CPU gate at load average 44
  (10.6 ms against 8.34 ms); it passed alone.
- `swift test --filter "LittleArktFlight|LittleArktWindowTests"` 20 times in a row: 20 of 20 passed, 39 XCTest
  (2 skipped: the screenshot and measurement tests) and 12 Swift Testing each, load average 22.6 at the start and
  18.8 at the end.
- Abort break check: removing the `abort` calls in `LittleArktWindowController` (`windowWillClose`, `requestClose`,
  the `.tabClosed` case) turned the Cmd-W and page-closed tests red (flight still `flying`, overlay still up, page
  not landed, row held back). The old animator (two clock reads) fails the three clock tests. Restored.
- One arrival frame with 509 rows (Debug, load average about 23, `ARKT_FLIGHT_MEASURE=1`, 600 frames): mean 460 us
  before (458 to 474 over 4 runs), 296 us after (293 to 299 over 4 runs).

### Deviations

- Open in with no main window open takes the fade-out path (the window it opens has no laid-out card yet).
- The engine reports no first frame for a page in its new window; the crossfade starts on the next display frame after
  the page is mounted. A check with real Chromium is #454.
- The selection moves to the new row when the page lands; the design's fade of the old selection and fade-in of the new
  one is not drawn (#455).
- No card shadow during the flight (a shadow path per frame would be extra per-frame work; #456).
- If the main window goes away mid-flight, the page stays in the Little Arkt window.

## #455: Little Arkt's Open in selection fades

Branch `feat/455-little-arkt-selection-fades`. Design: `docs/design/little-arkt.md`, Motion (Open in Space).

### What changed

- The old selection's fill fades out on the arrival's `room` spring (0 to 1): `FolderMotionLayout.RowStyle` gains
  `selectionAlpha`, and `SidebarArrivalLayout` multiplies it by `1 - clamp(room)`. Only the row view's
  `backgroundLayer` opacity changes, so the text, favicon and hover X stay drawn; the current fill's shadow fades with
  it.
- The arriving row draws `.current` while it is arriving; its whole-row alpha already fades the row in on the `row`
  spring, so its selection fades in without a second channel or a second fade. The outline's accessibility selection
  is unchanged.
- The old row is the `selectionSeed` captured on the first `presentArrival` (a pane's split; nil for a Favorite with
  no row). It is captured once: a first frame with no old selection does not start fading a row that becomes current
  later. Arrival frames are routed to the outline of the row's Space, so a Space switch mid-flight keeps drawing the
  arrival on its own outline instead of freezing it there and leaving its row drawn as the selection.
- `endArrival` reports whether it ended an arrival. On the flight's landing,
  `finishReceiving(clearingPrevious: true)` clears the previous role after `activate` only when it did, so the old row
  does not pop back to the 32% previous fill. A landing before the first arrival frame (an abort such as frames
  stopping) keeps the previous fill, like the no-flight path (Reduce Motion, no visible main window), which keeps the
  instant change.
- No new timers, wall-clock waits, per-frame layout or reloads: arrival frames set layer transform, opacity and
  selection opacity only.
- Known gap: a current Favorite draws its selection in the Favorites grid, which has no outline row, so its tile's
  fill does not fade yet. Follow-up #465.

### Verification

- Red first: the two pure fade tests failed to compile (`oldSelectionRow` missing), then the two GUI fade tests failed
  to compile (`selectionAlpha` missing). The capture-once, abort and Space-switch tests were added after the mechanism
  existed; their deliberate breaks are below.
- Focused non-GUI: `LittleArktFlightMotionTests` + `FolderMotionLayoutTests`: 21 passed (19 before), after the
  rebase.
- Full non-GUI suite on the rebased branch: 1409 tests in 177 suites passed (1407 before).
- Focused GUI `LittleArktFlightTests`: 37 run, 2 skipped, 0 failures (32 before on the rebased base, which includes
  #463's shadow tests); `SidebarViewTests`: 21 run, 0 failures (19 before).
- Full GUI suite on the rebased branch: 1158 run, 25 skipped, 5 failing test cases (2740 assertion failures): the
  same four known ones in `PeekWindowTests` and `SpaceSwitchTextTests`, plus
  `SplitDragTests.testDropFavoriteOnPlainTabMovesItIntoSplitAndClickVsDrag`, which passed 5/5 alone (a click that
  missed under load, not the change); not green.
- 20 runs each under four load generators, after the rebase: the six GUI tests 20/20 each and the two pure fade tests
  20/20 (load average 4.75 before, 10.46 after); the page-closed test 20/20 on its own (load average 3.12).
- Deliberate break: removing the old-selection fade made the pure test fail (`selectionAlpha` 1.0 instead of 0.5) and
  the GUI test fail (`1.0` not less than `1.0`). Putting the capture back to `arrival?.fadingOut ?? selectionSeed`
  made `testTheArrivalCapturesTheOldSelectionOnItsFirstFrame` fail (`selectionAlpha` 0.5 instead of 1.0). Clearing the
  previous role unconditionally made `testAFlightAbortedBeforeItsFirstFrameKeepsThePreviousFill` fail (`normal`
  instead of `previous`). Routing the arrival through `currentPage` made
  `testASpaceSwitchMidFlightKeepsTheArrivalOnItsOwnOutline` fail (arriving row alpha 0.0, old fill 1.0). Removing
  `endArrival` from `cancelReceiving` made `testAPageClosedMidFlightLeavesTheOldSelectionAtFullOpacity` fail (fill
  0.295 instead of 1.0, style not rest). Restored, all pass.
- Coverage: the pane-to-split mapping now has a GUI test (`testTheSplitRowFadesWhenTheOldSelectionIsAPane`), the
  200 ms edge and the landed fill at rest are asserted, and a page that closes itself mid-flight is tested to leave the
  old row current at full opacity. Not covered: an old row above the arrival (Pinned), a scrolled-out row, a
  closed-folder peek row and the Favorite tile (#465). A selection change mid-flight (another row becoming current)
  would draw the arriving row as current next to it; no user path does that within the 0.5 s flight and it is not
  tested. The no-per-frame-reconfigure assertion checks `rowConfigureCount`, not layout.
- These are local runs with a downloaded toolchain and a local XCTest runner, not CI. CI on the branch: Swift
  tests, ShellKit tests, App build and lint pass; the informative GUI job ran 1162 tests with 27 skipped and one
  failure, the `SplitDragTests` Favorite-tile click that also fails on #460 and #467 and is filed as #473.

## #400: slice 2, permission prompts in the shell's dialog panel

Date 2026-10-27. Branch `engine/400-permission-prompts` off `main` at `b56a582`. Plan: the engine plan comment on #400.
Second of three slices (JavaScript dialogs, permission prompts, infobars); the pull request is `Refs #400`.

### What landed

- **Hook, no patch.** `arkt_permission_prompt.mm` already owns the `PermissionPrompt` factory. Its prompt now builds the
  request's values once (origin, title, one phrase and kind per request, the allow, allow-this-time and block titles; all
  Chromium's strings) and, when the tab's window has an embedder host and the facade has a sink, hands them to a new
  presenter seam (`SetPermissionPresenter`, as the JavaScript dialogs do). The presented prompt draws nothing; the
  engine-drawn `ArktDialogSheet` stays the fallback (placeholder host, self-test host without a sink). The prompt owns an
  `ArktPermissionAsk`; the manager deletes the prompt on a tab switch (request stays pending), a navigation, a withdrawn
  request, an answer or the tab closing, and the prompt's destructor ends the ask, so exactly one `PermissionEnded`
  follows every `PermissionRequested`, and the delegate is called only from the shell's one answer (a second answer or an
  answer after the end returns NO). `.patches` stays 9 = `git rev-list --count 156.0.8078.48..arkt` 9. No `BUILD.gn` change.
- **Facade header (both copies, additive; `cmp` identical).** Event kinds `PermissionRequested` (18) and
  `PermissionEnded` (19), `permission` on `ArktEngineEvent`, `ArktPermissionKind` (other, geolocation, notifications,
  camera, microphone), `ArktPermissionChoice` (allow, allow this time, block, dismiss) and the `ArktPermissionRequest`
  protocol (tab, origin, kinds, title, items, the three titles, `isEnded`, `-respondWithChoice:`).
- **EngineAPI.** `PermissionRequest`, `PermissionRequestID`, `PermissionKind`, `PermissionChoice`,
  `EngineEvent.permissionRequested` / `.permissionEnded`, `EngineClient.respond(toPermission:choice:)` (default no-op).
  Contract rule 20 (four checks): a request carries the engine's values and ends once when answered; it ends before its
  tab's `.tabClosed`; a navigation ends it; a hidden tab ends it unanswered and asks again with a new request when shown.
  `ChromiumEngine` ends a tab's pending requests before it reports the tab closed even when the facade reports the end
  after `TabClosed`. `InMemoryEngine` gains the `askPermission` / `withdrawPermission` drivers and `permissionAnswers`;
  `ScriptedFacade` models the manager (hide keeps the ask, show asks again). FakeEngine reports rule 20 as not applicable
  (WKWebView asks through its own delegates), as for rule 19.
- **ShellUI.** `PermissionPresenter` shows each pending request of a shown tab as the slice 1 `DialogPanel`
  (top-leading corner 12 pt inside the page, 320 pt wide, no key focus: the page keeps its field until the panel is
  clicked), stacked full-width neutral pills (Allow while visiting the site, Allow this time, Never allow; notifications:
  Allow, Block), the origin in the title, what it wants as the recessed list, no Return default. `DialogContent` gains
  `stackedButtons`, `neutralPrimary`, `escapeDismisses` and `inputProtection`; `DialogPanel` gains `onDismiss` and an
  injected `clock`. Input protection: for 0.5 s after the panel is shown, presses on any answer button (and so Return,
  though nothing is the default) answer nothing; Escape still dismisses. The panel's own clock is injected, so the tests
  step it by hand.

### Checks (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try400p` (own id), copy on the internal disk in a throwaway folder, throwaway shell data folder and profile, defaults suite `arkt-test-400p`, `--use-mock-keychain`, a loopback page on `127.0.0.1:18401` and `localhost:18401`, keys and clicks only while the test app was the frontmost process, pointer moved before each press)

| Check | Result | Evidence |
|---|---|---|
| Notifications request | PASS | Arkt panel "http://127.0.0.1:18401 wants to", "Show notifications", Allow and Block; `permission prompt presented to the shell requests=1 one_time=0 quiet=0` |
| Allow reaches the page | PASS | Allow: page title `notif-granted`; engine log `answer 0` then one `PermissionEnded` |
| Block reaches the page | PASS | camera Never allow: page `cam-NotAllowedError`; notifications Block on `localhost`; `answer 2` |
| Quiet request | PASS | the geolocation ask after a camera answer logged `quiet=1` and showed the full panel (#265 decision) |
| Tab switched away | PASS | new tab: panel gone, `PermissionEnded` in the same batch as `TabCreated`; the page still waiting (`cam-asking`) |
| Tab switched back | PASS | the panel came back at once (a second `PermissionRequested`), as Chromium re-shows a pending ask |
| Input protection | PASS (second run; see the note below the table) | a button placed under the panel's Never allow spot: click 1 (page asks), click 2 about 0.1 s later hits the panel: page title stays `mic-asking-1` (the click did not reach the page), no answer logged; a click 2 s after the request answers (`answer 2`, page `mic-NotAllowedError`) |
| No Chromium bubble | PASS | System Events window list of the browser process with the panel up: the main window and one 320 x 179 panel; no other window; one window after the answer |
| Stderr | PASS | no `FATAL`, no `NOTREACHED` in the permission runs |

The first input-protection attempt was not clean: a tab opened by Cmd-T a few seconds earlier showed no panel in a
screenshot 0.4 s after `presented`, and a click about 1.6 s after the request reached the page, not the panel; the panel
was up by the next screenshot. It did not repeat after a reload of the page (the run in the table). Cause not found; the
engine log shows the request, the facade event and the batch within a millisecond of each other, so the delay is on the
shell side (panel creation or the window layout of a new tab). Worth a look when the real-app check is repeated.

### Verification

- Red first: the new tests did not compile before the types existed (`ScriptedEvent` and `TestEvent` had no `permission`,
  `EngineEvent` switches were not exhaustive). Then broken on purpose and restored: taking the press guard out of
  `DialogSheetView.primaryPressed` failed `testPressesAreIgnoredForHalfASecondAndWorkAfter` and
  `testEachNewPanelStartsItsOwnProtection`; taking `endPermissions(of:)` out of `ChromiumEngine.removeTab` failed
  `closingTheTabEndsTheRequestBeforeTabClosedEvenWhenTheFacadeReportsItAfter` and the contract check
  `pendingPermissionEndsBeforeItsTabCloses` (both scripted orders).
- ShellKit `swift test --skip ShellKitGUITests`: 1436 passed (9 test runs: 812, 38, 43, 4, 134, 49, 256, 82, 18), 0
  failed: baseline 1399 + 37 (6 `PermissionContentTests`, 11 `PermissionRequestTests`, 7 `ChromiumPermissionTests`, 1
  `PermissionRequestABITests`, 4 in-memory contract checks, 8 scripted contract checks: 4 over the two scripted orders;
  the baseline is the total minus the new tests, not a run on `main`). ArktCore `swift test`: 429 passed (144, 117, 70, 98), unchanged.
- GUI tests run: `PermissionPresenterTests` (15), `PermissionWindowTests` (3), `DialogTests`, `DeleteSpaceTests`,
  `JavaScriptDialog*`, `AccessibilityIdentifierTests`, `FakeEngineContractTests` (rule 20 not applicable: skipped);
  112 run, 14 skipped, 0 failures. The rest of the GUI suite was not run.
- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodegen generate`, then
  `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try400p`: `BUILD SUCCEEDED`.
  `out/Arkt` was not rebuilt for this slice (nothing in the release build differs from `out/Spike`'s sources).
- `cmp` of the two header copies: identical. `.patches` 9 = `rev-list` 9.

### Deviations

- The 0.5 s protection ignores all three answers and Return, not only the allow ones as the engine panel does, and it
  does not dim the buttons (no timer: the clock is read on each press, which keeps it testable by hand). Escape is not
  held back.
- Escape dismisses without choosing (Chromium counts it as ignored), as the engine's panel and the plan comment; the
  design doc's section 3.3 line "Escape answers Never Allow" is the older wording.
- Copy is Chromium's, not shell-authored ("wants to", "Know your location", the allow and block titles); the origin is
  Chromium's own formatting, scheme and port included for a loopback page.
- The in-app contract runner has no `raisePermission` driver (Chromium needs a foremost tab and a user gesture), so rule
  20 is not applicable there; real Chromium is covered by the checks above.
- `PermissionPresenter` repeats the anchor, visibility and layout-retry handling of `JavaScriptDialogPresenter`; a shared
  anchored-panel helper is a clean-up for slice 3 once infobars show whether a third user exists.

### Found while checking, not part of this change

- On the very first launch with empty data, `Skip setup` on the first-run flow crashed the app (`NOTREACHED`, "Attempted
  to access a context that was ShutDown()", from `CreateBrowserWindow` through `OnboardingController.finish` and
  `ShellWindowController.openEngineTab`): the engine's startup window had been closed before any shell window existed.
  Relaunching with the same data folder resumed the flow and everything worked. It happens before any permission code
  runs; not filed from this branch, described in the pull request for the maintainer to file.
- Grant of location, camera or microphone for real still goes through macOS's own prompts (TCC); this slice answers
  Chromium's ask only. That is #133.

### Left open

- Slice 3: infobars (`InfobarsChanged`, a shell row from the design's `infobar` state).
- Per-site remembered settings and the Site Control Center are #133; Chromium's own content settings keep the answer.
- The `<permission>` element and pointer and keyboard lock prompts keep Chromium's prompt (#265).
- Cleanup: the test copy, throwaway data, the 518 cloned dylibs, `embed-400p` and the app's derived data on the Chromium
  disk are removed. Launching by path had registered the two app copies with LaunchServices under
  `dev.arkt.Arkt.try400p` (8 records); `lsregister -u` on both paths left none (`lsregister -dump` counts 0).

## #400: slice 3, infobars as shell rows

Date 2026-10-27. Branch `engine/400-infobars` off `main` at `fb1738c` (with #476's anchoring helper and #475). Plan: the
engine plan comment on #400. Third and last slice; the pull request is `Closes #400`.

### What landed

- **Hook, no patch.** `arkt_infobars.mm` already observes each tab's `InfoBarManager` and draws one `ArktInfobarView` per
  `ConfirmInfoBarDelegate`. After every change of the list the presenter now calls a sink (`SetInfobarSink`, as the
  permission and dialog seams) with plain values: an id, a kind (debugger, automation, reload, other, from
  `GetIdentifier()`), the message and its inline link ranges, the trailing link, the OK and Cancel titles, tooltips and
  enabled state, the close label and the icon as a 2x PNG. When the facade takes the list (the tab has a handle and a sink
  listens) the engine's rows stay in the presenter but are hidden: the stack keeps its height, so `ArktTabContainerView`
  still lays the page out below the strip and the page moves down once, in the card, a split pane, the Peek and Little
  Arkt alike. Without a sink (placeholder host, self-test) the engine row is drawn as before. Actions come back through
  `Perform(id, action, index)`, which runs the delegate exactly as the row's click does; the delegate decides whether the
  infobar leaves, and the next list says so. `.patches` stays 9 = `git rev-list --count 156.0.8078.48..arkt` 9. No
  `BUILD.gn` change.
- **Facade header (both copies, additive; `cmp` identical).** Event kind `InfobarsChanged` (20), `infobars` on
  `ArktEngineEvent`, `ArktInfobarKind`, `ArktInfobarAction` and the `ArktInfobar` protocol, whose `-act:linkIndex:` is the
  action entry (the object is the handle, as for dialogs and permission requests; it refuses every action once the
  infobar is gone). One event per tab per batch (a later change replaces the list of the pending one); the same infobar
  keeps its object across lists; a tab moved to another window comes back with a new list of new objects.
- **EngineAPI.** `Infobar`, `InfobarID`, `InfobarKind`, `InfobarButton`, `InfobarLink`, `InfobarAction`,
  `EngineEvent.infobarsChanged(TabID, [Infobar])`, `EngineClient.act(on:action:)` (default no-op). Contract rule 21 (three
  checks): a list carries the engine's values and `act` removes the infobar through a shorter list, once; a tab keeps its
  list while hidden and the other tab's list is independent; a tab's list is reported empty before its `.tabClosed`.
  `ChromiumEngine` keeps ids stable per facade object and empties the list in `removeTab` before the close, even though
  the real facade reports nothing for a closing tab. `InMemoryEngine` gains `raiseInfobar`, `removeInfobar` and
  `infobarActions`; `ScriptedFacade` models the list, the objects and the move. FakeEngine reports rule 21 as not
  applicable (WKWebView has no infobars).
- **ShellUI.** `InfobarPresenter` shows each tab's list as `InfobarPanel`: one full-width, non-activating child panel flush
  with the top of the page view, 40 pt per infobar on the brand surface (no hairline), the page card's top corners, no key
  focus. A row is the design's: 20 pt icon (the engine's, else a glyph for the debugger, automation and reload kinds), one
  line of message in `primaryText` with quiet inline links, the trailing link, the engine's OK and Cancel as 24 pt neutral
  pills, a 22 pt round close button; mirrored for right-to-left. It uses `AnchoredPanelHost` from #476, generalised
  to any panel (`AnchoredPanel`) and given a `fullWidth` placement and a `topInset`, so dialogs and permission prompts
  anchor below the strip. Windows: `ShellWindowController` and `LittleArktWindowController` own a presenter and route
  `.infobarsChanged`; a presenter shows only the pages in its own window. A list change updates the same panel and keeps
  its top edge; a new row fades in over 0.14 s, none fades out, Reduce Motion shows both at once. VoiceOver: the row is an
  `AXGroup` labelled with the message, its children the link, OK, Cancel and close, in that order; a new infobar is
  announced.

### Infobars covered

Every `ConfirmInfoBarDelegate` of Chromium 156 on macOS desktop takes the one row shape, so the list below is what the code
can show, by `InfoBarIdentifier`, minus the delegates with views of their own:

- Common: extension debugger (`chrome.debugger`), DevTools, DevTools remote debugging, process sharing, automation
  ("controlled by automated test software"), Page Info reload ("To apply your updated settings, reload"), session
  restore, default browser and pin, the missing Google API keys, bad command-line flags, theme installed, extension
  install error, web auth flow, incognito connectability, link capturing, PDF.
- Also by the same path: collected cookies, known interception disclosure, JS optimizations, web app blocked migration,
  startup launch, oscrypt availability, obsolete system, keystone, simple alert.
- Deferred, not drawn and logged as today (`not a confirm infobar`): tab sharing, and any infobar whose delegate is not a
  confirm delegate. The mobile and iOS delegates do not exist on desktop.

### Checks (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try400i` (own id), copy on the internal disk in a scratch
folder, throwaway shell data folder, profile and defaults suite `arkt-test-400i`, `--use-mock-keychain`, two throwaway
extensions that call `chrome.debugger.attach` on a loopback page, loopback pages on `127.0.0.1:18402`, keys and clicks only
while the test app was the frontmost process, pointer moved before each press)

| Check | Result | Evidence |
|---|---|---|
| A local page triggers an infobar | PASS | opening `attach-a.html` made the extension attach; the shell drew one row "Inspector a started debugging this browser" with a bug glyph, Cancel and close; the page sat 40 pt lower; log `facade infobars changed count=1` |
| No second row | PASS | System Events: one window "system dialog" (the strip) and the main window; the main window has no group labelled with the message; the engine row is hidden (`stack_.hidden`) |
| Cancel acts | PASS | a click: `ARKT: infobar 13 ok`, the extension detached, the list went to 0 and the strip window left |
| Two infobars stack | PASS | a second extension: two 40 pt rows, the page 80 pt lower |
| Close acts | PASS | the AX press on the first row's close button: `infobar 13 close`, one row left, the page moved up 40 pt |
| Stays with the tab across switches | PASS | switching to another tab and back kept a strip over each tab (the debugger infobar is global, so every tab has one) |
| Light and dark | PASS | system dark: graphite strip, light text; `-NSRequiresAquaSystemAppearance YES`: porcelain strip |
| VoiceOver tree | PASS | after the fix below: the group's children are Cancel and Close; before it the bug glyph was a child ("Ladybug") |
| Stderr | PASS | no `FATAL`, no `NOTREACHED` in the three runs |
| Not checked | | a tab moved between windows with an infobar (covered by `ChromiumInfobarTests` only), Reduce Motion in the real app (tests), the close button under a system notification banner (it was pressed through accessibility), inline message links (no 156 delegate used here has them) |

### Verification

- Red first: the new tests did not compile before the types existed. Then broken on purpose and restored: taking
  `endInfobars(of:)` out of `ChromiumEngine.removeTab` failed
  `closingTheTabEmptiesItsListBeforeTabClosedEvenWhenTheFacadeReportsNothing` and the contract check
  `pendingInfobarsEndBeforeTheirTabCloses` (both scripted orders); taking the list update out of
  `InfobarPresenter.present` failed `testEveryInfobarIsA40PointRowAndTheStripKeepsItsTopEdge` and
  `testNonLatinTextAndEmojiAndASingleLetterLayOut`.
- ShellKit `swift test --skip ShellKitGUITests`: 1467 passed (9 test runs: 814, 38, 43, 4, 145, 49, 256, 99, 19), 0 failed;
  32 of them are new (10 `InfobarTests`, 12 `ChromiumInfobarTests`, 1 `InfobarABITests`, 3 in-memory and 6 scripted contract
  checks); the baseline is the total minus the new tests, not a run on `main`. ArktCore `swift test`: 429 passed (144, 117,
  70, 98), unchanged.
- GUI tests run: `InfobarPresenterTests` (27), `InfobarWindowTests` (4), `PermissionPresenterTests`,
  `PermissionWindowTests`, `JavaScriptDialog*`, `LittleArktDialogTests`, `DialogTests`, `DeleteSpaceTests`,
  `AccessibilityIdentifierTests`, `FakeEngineContractTests` (rules 19 to 21 not applicable: skipped): 186 run, 17 skipped, 0
  failures. The rest of the GUI suite was not run.
- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodegen generate`,
  then `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try400i`: `BUILD
  SUCCEEDED`.
- `cmp` of the two header copies: identical. `.patches` 9 = `rev-list` 9.

### Deviations

- The design and the plan say "above the page like the engine row". The row is a child panel over a band the engine
  reserves, not a view in the page card: the shell cannot reach the engine's container layout, and a view added to the
  container is dropped when the contents view is swapped. The band is the engine's, so every place that mounts a tab
  container (card, panes, Peek, Little Arkt) gets the page placement for free; the cost is a child window that has to
  follow the page (the anchoring helper does that), and a blank band in any window that mounts a tab but runs no
  presenter.
- Inline message links are drawn as text with attributes in a one-line `NSTextView`; no delegate used in the real-app
  check has them.
- The strip's surface follows the system appearance, as the dialogs do, not the Space theme: a light Space under a dark
  system shows a graphite strip over a light page.
- Keyboard focus into the strip (F6, Tab from the page) is not added; VoiceOver and the mouse reach every control.

### Found while checking, not part of this change

- The first launches were blocked by an old "ArktShell quit unexpectedly" system dialog on the screen (not from this
  run), which kept a window sheet from taking clicks; `ARKT_SKIP_ONBOARDING` only works in Debug builds, so the first run
  was skipped through its Skip setup sheet once the sheet could be clicked.
- `xcodebuild` registers the product in its `CONFIGURATION_BUILD_DIR` with LaunchServices, as launching by path does.

### Left open

- Tab sharing and other non-confirm infobars (see above), keyboard focus into the strip.
- Cleanup: the test copy, the throwaway data and extensions, `embed-400i` and the derived data on the Chromium disk are
  removed. `lsregister -u` on the three paths (the copy, its Aperitif alerts helper, and the `embed-400i` product) left
  `lsregister -dump` with 0 records for `dev.arkt.Arkt.try400i`.

## #380: parked closed-tab copies hidden from chrome.tabs

Date 2026-10-27. Branch `engine/380-hide-parked-tabs` off `main` at `5c4d696`. Plan: the issue body. The pull request is `Closes #380`.

### Seam chosen: no patch, no window

A parked copy (`EngineClient.duplicateTab`, #378) is now a bare `WebContents` clone held by its `ArktFacadeTab` handle **outside every tab
strip**. Extensions reach tabs only through tab strips (`WindowControllerList`, `TabsEventRouter`, `ExtensionTabUtil::GetTabById`), so
the copy is not listed by `tabs.query` or `windows.get(populate)`, fires no `chrome.tabs` event, and has no tab id to guess. It joins its
window (`TabStripModel::InsertWebContentsAt`, not active) the first time the shell shows it: `containerView`, `activate`, `navigate`,
`reload`, back, forward, history jump or `moveToBrowser` on the handle. Until then it never loads. Closing a parked copy, or its window
closing, destroys the clone and reports `TabClosed` (`client`, `windowClosing`, `appTerminating`); a window's copies end before its
`WindowClosed`.

Why not the hidden holder window the issue names first. A devtools-type Browser is the only type `ExtensionTabUtil::BrowserSupportsTabs`
and `TabsEventRouter::ShouldTrackBrowser` leave out, and it is not enough alone: `ExtensionTabUtil::GetTabById` walks every
`WindowControllerList` entry with no type filter, and `TabsReloadFunction` and `TabsGetFunction` do not check
`BrowserSupportsTabs` (only `tabs.update` does), so an extension that guesses the id still reloads a tab in the holder. Closing that gap
needs `WindowControllerList::RemoveExtensionWindow` on the holder, a hidden `ArktBrowserWindow` host for a devtools Browser (the
factory returns a Views window for that type), an unannounced window in the facade and per-window cleanup, which is more surface than
leaving the copy out of any strip. No Chromium patch: `.patches` 9 = `git rev-list --count 156.0.8078.48..arkt` 9. Facade header
unchanged, `cmp` of both copies identical. `ArktFacadeTab` gains private methods only.

### Tests first

- `engine/test-extensions/parked-probe` (load-unpacked fixture, `tabs` permission): records `onCreated`, `onRemoved`, `onAttached`,
  `onDetached`, `onActivated`; `report()` counts `tabs.query`, `windows.getAll({populate: true})` and the ids `tabs.get`, `tabs.update` and
  `tabs.reload` reach when it guesses ids near the listed ones (it skips listed tabs for update and reload).
- `ChromiumEngineScriptTests.duplicateIsParkedUntilItIsShown` (scripted facade now models the parked copy): red against the old
  duplicate (active, loading at once: `engine.activeTab(in:)` was the copy), green after. Contract rule 10 gains: the copy is not active,
  and the contract shows (activates) it before it waits for the copy's load.

### Real app (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try380` (own id), scratch folder on the internal disk, throwaway shell data folder, profile and defaults suite, `--use-mock-keychain`, the probe extension, loopback pages on `127.0.0.1:18380`, keys and clicks only while the test app was the frontmost process)

Two tabs (`b` with a history of `a`, then `b`; `c`), Cmd-W on `c`:

| | before (old build) | after |
|---|---|---|
| `tabs.query` count, user has 1 tab | 2 (`[b, copy of c]`, ids 800669760, 800669762) | 1 (`[b]`) |
| `windows.getAll(populate)` ids | same as query | same as query |
| events since the close | `onCreated` 1, `onRemoved` 1, `onActivated` 2 | `onCreated` 0, `onRemoved` 1, `onActivated` 1 |
| ids reached by guessing (`get`, `update`, `reload`) outside the listed ones | none | none (the copy has no tab id until shown) |

Reopen (File > Reopen Closed Tab): the copy joined the window, `tabs.query` listed 2 tabs, `onCreated` 1 (the page appears as a new
tab), the page was `c.html`. History: `c` navigated to `a` (history length 2), closed and reopened: `history.length` 2 and `history.back()`
returned to `c.html`. Log: `facade duplicate parked outside the tab strip` at the close, `facade parked copy shown` at the reopen. A
Close Window with parked copies, and a SIGTERM (by PID) with one parked copy: no `Check failed`, no `FATAL`, process ended, no new
crash report. In-app contract runner (`--arkt-engine-contract --arkt-engine-test-api`, tabs probe): rule 10 PASS, `18/21` before and
after; rules 19 to 21 fail on both builds because the runner has no `raiseDialog`, `raisePermission` or `raiseInfobar` driver (they
report NOT-APPLICABLE), unrelated to this change.

### Verification

- `swift test --skip ShellKitGUITests` in ShellKit: 1469 passed (814, 38, 43, 4, 145, 49, 256, 101, 19), 0 failed: the previous total
  plus 2 new tests. ArktCore `swift test`: 429 passed (144, 117, 70, 98), unchanged.
- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodegen generate`, then `xcodebuild
  -scheme ArktShell -configuration Engine`: `BUILD SUCCEEDED`.
- GUI tests (`ShellKitGUITests`) were not run: the FakeEngine and InMemoryEngine they use are unchanged.

### Review follow-up

Showing a parked copy (`-unpark`) now runs from a posted task when it is reached inside a Chromium notification or a nested run loop
(Decision 3), and keeps the copy parked while its window is closing (it ends with the window). `parkedCopyEndsWithItsWindowAndIsNotShownAfterwards`
is the scripted case. Real-app check repeated (close: `tabs.query` 1, `onCreated` 0; reopen: 2 tabs, `onCreated` 1, history length 2, Back works).

### Deviations and limits

- A duplicate is no longer "next to this one" in the window's tab order and not active until shown; the header comment on
  `-duplicate` was left as is (both header copies must stay identical) and rule 10 in `EngineContract` says so.
- A parked copy is still a DevTools target (`type: other` in the remote-debugging target list), so an extension with the `debugger`
  permission can list and attach to it through `chrome.debugger.getTargets`; `chrome.tabs`, `chrome.windows` and `chrome.webNavigation`
  cannot. Not changed here.
- Peek (a closed Peek reopens over its source) was not driven in the real app; it takes the same `containerView` then `activate` path.
- The extension sees a reopened page as a new tab (`onCreated`, a new id), not as the tab it saw close.

## #134 and #114: engine halves of find in page and the link hover target URL

Date 2026-10-27. Branch `engine/134-114-find-and-target-url` off `main` at `b6ce219`. Engine only, no shell UI (tracking issue
#481); the UI follows after the maintainer picks a design. `/Volumes/SSD_2` had 1.9 TiB free, `/` 61 GiB, swap 13 GB used of 14 GB
(builds ran at `nice -n 15`, `-j 4`; no other Chromium build was running).

### Gate

1. Task: report find replies and the hovered link's URL to the shell through the facade. Find needs no patch:
   `find_in_page::FindTabHelper` is attached to Arkt tabs, `StartFinding` and `StopFinding` are public, and its
   `FindResultObserver` receives only replies the helper accepted (stopped and replaced searches are dropped, `-1` values are
   filled from the last result). The target URL has no seam: `WebContentsObserver` has no target URL callback (`grep -i
   target_url content/public/browser/*.h` finds only navigation parameters), the only receiver is
   `WebContentsDelegate::UpdateTargetURL`, the delegate is `BrowserWebContentsDelegate`, and its override casts every status
   bubble to `StatusBubbleViews` and `ContentsWebView`, so a non-Views bubble from `ArktBrowserWindow::GetStatusBubbles` (empty,
   see the comment in `arkt_browser_window.mm`) would be undefined behaviour. With no bubbles the override does nothing, so
   the report is lost. Patch 0010 is therefore necessary.
2. Facade header: additive (event kinds 21 and 22, `ArktFindAction`, four `ArktEngineEvent` properties, two `ArktTabHandle`
   methods). Both copies identical.
3. `.patches`: 9 to 10, patch 0010; no open engine pull request touches patches.
4. Build and smoke: `autoninja -C out/Spike chrome -j 4`, Engine app, the in-app contract runner.

### What landed

- **Facade (`arkt_engine_facade.mm`).** `TabObserver` is also a `FindResultObserver` of the contents' `FindTabHelper` (created on
  the first find if the tab has none; observed from `SetContents` when it exists). `-findInPageWithText:forward:matchCase:` calls
  `StartFinding(text, forward, matchCase, find_match=true)`: the helper starts a new search for a new text or case, or after a
  stop, and moves to the next or previous match for the same text and case, so Cmd-G and Shift-Cmd-G are the same text with
  `forward` flipped. `-stopFindingWithAction:` maps Clear, Keep, Activate to `SelectionAction`. Replies become
  `FindResult` events (request id, 1-based ordinal, count, final); empty text arrives from `OnFindEmptyText` as one 0-of-0
  final reply with request id 0. Stopping reports nothing. `ReportTargetURL` records `TargetURLChanged` for changes only,
  and clears when a new document commits.
- **Patch 0010** `Arkt: report the link under the pointer from UpdateTargetURL`: `browser_web_contents_delegate.cc`, one hunk, five
  lines under `BUILDFLAG(IS_MAC)`, calling `arkt::NotifyTargetURLChanged` before the bubble loop. The hook lives in the existing
  `arkt/browser:link_activation` target (`arkt_link_activation.{h,cc}`, `SetTargetURLObserver`, `NotifyTargetURLChanged`); the
  dependency and include of patch 0009 are reused, so no `BUILD.gn` change. Export touched no earlier patch file.
- **EngineAPI.** `EngineClient.findInPage(_:text:forward:matchCase:)`, `stopFinding(_:action:)` (`FindStopAction`: `clear`, `keep`,
  `activate`), both with no-op defaults; events `.findResult(TabID, requestID:, ordinal:, count:, isFinal:)` and
  `.targetURLChanged(TabID, URL?)`. The engine delays and merges nothing. The only shell change is the two cases in
  `ShellWindowController.handle(_:)`, which ignore them.
- **Engines.** `ChromiumEngine` forwards the calls and the two events. `FakeEngine` (WKWebView): `window.find` selects the match
  and page script counts the matches (WKWebView's own find reports no count); the hovered link comes from a user script that
  posts `mouseover` and `mouseout` of links from every frame. `InMemoryEngine`: scripted pages (`findPageURL`), ordinal with
  wrap, selection model, `hoverLink` and `leaveLink` drivers. The scripted facade (test double) models the interim reply of a new
  search.
- **Contract rules 22 and 23** (`EngineContract+Find.swift`): `findCountsMatchesAndMovesTheOrdinal` (needle x3: 1 of 3, next 2,
  stop then the search starts again at 1, previous wraps to 3, previous 2, match case finds no capitals, ignoring case finds 3,
  request ids never go back, empty text reported once as 0 of 0), `stopFindingKeepsClearsOrActivatesTheMatch` (Keep leaves the
  match selected, Clear leaves nothing, Activate follows the matched link), `hoveredLinkReportsItsTargetURL` (URL once, nil
  once, again once, nothing in between). New harness drivers `findPage`, `selectedText`, `hoverLink`, `leaveLink` (nil: not
  applicable).

### Tests first

The contract checks and harness drivers were written before the engines: `swift build --build-tests` failed on the missing
`InMemoryEngine.findPageURL`, `selectedText`, `hoverLink`, `leaveLink` (red), then green. Breaking InMemoryEngine's backward wrap
(`max(ordinal - 1, 1)`) fails `findCountsMatchesAndMovesTheOrdinal` with `find previous from the first match wraps to the last:
expected match 3 of 3, got 1 of 3`; restored.

### Real app (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try134` (own id), throwaway profile, shell data folder and defaults suite on the Chromium disk, `--use-mock-keychain`, the tabs probe extension, loopback pages)

In-app contract runner (`--arkt-engine-contract --arkt-engine-test-api`): `20/23`, the same as before this change plus the
three new checks; rules 19 to 21 are NOT-APPLICABLE for lack of runner drivers, as before. Rule 22 `findCountsMatchesAndMovesTheOrdinal` PASS
(273 ms), `stopFindingKeepsClearsOrActivatesTheMatch` PASS (150 ms), rule 23 `hoveredLinkReportsItsTargetURL` PASS (217 ms). No
`Check failed` or `FATAL` in the log. The runner is the existing test hook, so no debug menu was added.

Limits: the runner's hover driver focuses and blurs the link, which makes Blink send the same `UpdateTargetURL` a hover does
(Chromium's `WebContentsImplBrowserTest.UpdateTargetURL` drives it that way). A synthetic `mouseMoved` sent to the page view
reached it (hit view `RenderWidgetHostViewCocoa`) but produced no report: Blink ignores mouse moves for a window that is not
key, and making the window key means activating the app while another lane's test app was frontmost, which the local-app rules
forbid. A real pointer over a link is therefore not verified here; it needs the shell window (UI step). One more shell-side
point: `Browser::OnTabStripModelChanged` creates the Views find bar for a tab inserted into a window while its find session is
active, so the shell should `stopFinding` before it moves a tab.

LaunchServices: the build registered the test bundle; every `try134` path was removed with `lsregister -u`, the count of
`try134` entries is 0. The embed folder, profile and derived data were deleted; no process was left.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 10 |
| `arkt` commits above `156.0.8078.48` | 10 |

Equal (`in sync`). Ten patch files, 17 upstream files (0010 edits a file 0009 already touches), 0 hot-file hunks; the facade headers are `cmp` identical.

### Verification

- `swift test --skip ShellKitGUITests` in ShellKit: 1474 passed (814, 38, 43, 4, 148, 49, 256, 101, 21), 0 failed: the 1469 recorded
  at #380 plus 5 tests (3 InMemory contract, 2 ABI), and 6 new parameterized cases of `ChromiumEngineContractTests` (3 checks x 2
  scripts) inside existing tests. ArktCore `swift test`: 429 passed (144, 117, 70, 98), 0 failed.
- `FakeEngineContractTests` rules 22 and 23 (`swift test --filter`, run on its own): 3 passed. The rest of `ShellKitGUITests` was not run.
- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodegen generate`, then
  `xcodebuild -scheme ArktShell -configuration Engine`: `BUILD SUCCEEDED`.

### #134 and #114: review follow-up

- `moveToBrowser` ends a running find (`StopFinding(kClear)`, only when a session is active, nothing reported) before the detach, so
  `Browser::OnTabStripModelChanged` never builds the Views find bar for the moved tab. Documented on `findInPage`/`stopFinding` in
  the facade header (both copies identical) and on `EngineClient.findInPage` and `moveTab`. Tests: `ChromiumMoveTabTests.moveEndsARunningFind`
  (scripted facade) and `MoveTabTests.moveEndsARunningFind` (InMemory): no reply after the move, the next search starts at match 1.
- InMemoryEngine no longer spends a request id on empty text (`emptyFindTextUsesNoRequestID`).
- `engine/REBASE.md`: rebase-risk note for patch 0010.
- Verification: ShellKit `swift test --skip ShellKitGUITests` 1477 passed (814, 38, 43, 4, 150, 49, 256, 102, 21), 0 failed. `out/Spike`
  incremental build and Engine app build succeeded. Real app (`dev.arkt.Arkt.try134`, throwaway profile, mock keychain): rules 22 and
  23 PASS (2/2). Bundle unregistered (0 `try134` entries), folders removed, no process left. The move path itself was not driven in
  the real app (the contract runner has no moveTab driver).

## #502: location allowed in the panel now asks macOS

Date 2026-10-27. Branch `engine/502-location-system-prompt` off `main` at `2e2cf7e`. Overlay only: no Chromium patch, `.patches`
unchanged, facade header untouched.

Cause (from the issue): Chromium starts the macOS location request only from `system_permission_settings::Request(GEOLOCATION)`,
called by `content_setting_image_model.cc:907` and `embedded_permission_prompt.cc:276`. The panel only called `Accept` or
`AcceptThisTime`, so the system status stayed not determined and the page waited until its own timeout.

Change: `ArktPermissionPrompt::Answer` (`arkt_permission_prompt.mm`) records whether the answered requests include
`ContentSettingsType::GEOLOCATION` before the delegate call (which may delete the prompt and the requests). After `Accept` or
`AcceptThisTime`, when it did and `system_permission_settings::CanPrompt(GEOLOCATION)` is true (status not determined), it calls
`system_permission_settings::Request(GEOLOCATION, base::DoNothing())`, as the location bar chip does. The call is a static member, so
it is safe after the prompt is gone. `BUILD.gn` gains `//chrome/browser/permissions/system` in `window` deps. Block and dismiss do not call it.

Denied path, read in Chromium and not patched: `GeolocationPermissionContextSystem::GetPermissionStatusInternal` maps a denied
system status to block, so with the system already denied no prompt shows and the page gets its error at once. After the system
prompt, `GeolocationProviderImpl::OnSystemPermissionUpdated` delivers the position, or the error on Don't Allow. Nothing else was needed.

### Real app (`dev.arkt.Arkt.try502`, Engine app on `out/Spike`, throwaway profile, shell data folder and defaults suite under `profiles/502-20261027`, `--use-mock-keychain`, loopback page on `127.0.0.1:8692`)

Launched by `posix_spawn` with `responsibility_spawnattrs_setdisclaim` (rc 0), so Arkt is the responsible process. Quiet location
prompt (no gesture) shown in the shell, `Allow while visiting the site` clicked: `permission prompt answer 0`, then
`ARKT: asking the system for location access`, and the macOS prompt "Arkt would like to use your current location." appeared.
`Don't Allow` clicked: the page got `ERROR 1:User denied Geolocation` within the 4 s check, not `3:Timeout expired`. Before the change
the page got `3:Timeout expired`. Location was never granted. The Allow branch of the system prompt was not run (never grant real
location); Chromium's own flow delivers the position there.

Limits: no scripted or contract test, the in-app contract runner has no location driver and a fake `GeolocationSystemPermissionManager`
is not reachable from the overlay. Cleanup: processes stopped by PID, `tccutil reset All dev.arkt.Arkt.try502` succeeded;
`tccutil reset Location` prints `Failed to reset Location approval status` (location is kept by locationd, which tccutil does not
reset here), so the Don't Allow answer for the throwaway id stays in locationd. Bundle unregistered (0 `try502` entries), embed folder,
profile, derived data and logs deleted.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 10 |
| `arkt` commits above `156.0.8078.48` | 10 |

Equal (in sync). Facade header copies `cmp` identical.

### Verification

- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodebuild -scheme ArktShell
  -configuration Engine`: `BUILD SUCCEEDED`.
- ShellKit `swift test --skip ShellKitGUITests`: 1587 passed (905, 38, 60, 4, 150, 49, 257, 103, 21), 0 failed. No Swift source changed;
  the count differs from the #134 run only by tests other lanes merged since.

## #512: write imported cookies and passwords (engine seam for #131)

Date 2026-10-27. Branch `engine/512-import-cookies-passwords` off `main` at `324257c`. Overlay and Swift only: no Chromium patch,
`.patches` unchanged.

### What landed

- **Facade header (both copies, additive; `cmp` identical).** Protocols `ArktImportCookie`, `ArktImportLogin` (the shell implements
  them; the secret is lent through an `NS_NOESCAPE` block, never copied into an object) and `ArktImportResult` (written, skipped,
  failed, failure reasons with counts). `ArktEngine` gains `importCookies:completion:` and `importPasswords:completion:`; the
  completion runs later on the main thread, also for an empty batch.
- **Engine (`arkt_import_writer.{h,cc}`, called from `arkt_engine_facade.mm`).** Into the profile the hook started with
  (`EmbedderProfile()`).
  - Cookies: `GetAllCookies` once per batch, then `SetCanonicalCookie` per cookie with `CookieOptions` including HttpOnly and
    `SameSiteCookieContext::MakeInclusiveForSet()`, then `FlushCookieStore` before the completion. The cookie is built with
    `CanonicalCookie::FromStorage` (kCookieManager) from the record's host key (a leading dot is a domain cookie), path, expiry,
    secure, httponly, samesite, priority, source scheme and source port; the source URL is built from the host (https for a secure
    cookie or source scheme 2) and the recorded port. Dedupe by (name, domain, path): the newest last access wins, then creation,
    then the later entry. Skipped: a partitioned cookie (non-empty `top_frame_site_key`; written without its partition key it
    would be readable in every top-level context), an expired cookie, and one the profile holds that was last used at or after the imported one's
    last access (so a second import of the same batch writes nothing). Failures are counted by reason (the cookie inclusion status).
  - Passwords: `ProfilePasswordStoreFactory` store, `AddLogins` of `StoredCredential`s (Chromium 156 replaced `PasswordForm` in this
    API). Dedupe by (signon realm, username, action), later entry wins. The store is read first (`GetAllLogins`): a login it already
    holds under that key is skipped unless the imported one is newer (the later of last use and creation). `written` counts after
    `AddLogins` answered. An invalid origin URL or empty signon realm fails with a reason. The engine logs how many logins its store
    holds (counts only), also for an empty batch.
- **Swift.** `EngineImporting` in `EngineAPI` (`importCookies([ArcCookie]) async` and `importPasswords([ArcLogin]) async`, result
  `ImportWriteResult`), a separate protocol like `EngineExtensions`. `ChromiumEngine` implements it over the facade and zeroes every
  `SecretBytes` of the batch after the call. Zeroing covers the batch buffers (ours and the engine's copies of them); the
  `CanonicalCookie` Chromium builds, its mojo message and the password store's copies are Chromium's and are not zeroed. `InMemoryEngine` and `FakeEngine` record what they were given (`ImportRecording`, the
  same dedupe rules) and zero the secrets. `EngineAPI` now depends on `ArcImport` for the reader records (deliberate: ShellUI
  still imports no core module; `IsolationTests` pass).
- **Two Chromium facts found by the real run.**
  1. `CookieManager::SetCanonicalCookie` (network service) caps an expiry at 400 days after the creation date. A cookie created
     long ago with a long expiry arrived already expired: `INCLUDE` was reported, the cookie was dropped, the profile held nothing.
     The writer keeps the creation date and moves it forward only as far as `expiry - 400 days`, never past now.
  2. Expired cookies are only deleted again, so they are skipped and counted.
- **Test support.** Public `init`s on `ArcCookie` and `ArcLogin` (the reader fills every field; engine tests and previews build
  records), `FakeChromiumProfile.Options.extraCookies` and `extraLogins` (with public `init`s on the fixture `Cookie` and `Login`):
  the fixed fixture cookies expire in 2024 and 2025, so an engine check needs one for 127.0.0.1 that does not.
- **Engine check runner.** `--arkt-import-check=import|verify` (Engine configuration only, with `--arkt-engine-test-api`):
  `ImportCheckRunner` reads a `FakeChromiumProfile` folder (`ARKT_IMPORT_FIXTURE_DIR`) with `CookieReader` and `LoginReader` and the
  fixture's fake key, writes through the new API, loads a loopback page and prints `document.cookie`. `verify` skips the import.

### Real engine (`dev.arkt.Arkt.try512`, Engine app on `out/Spike`, embed folder, throwaway profile and shell data folder under `profiles/512-20261027`, `--use-mock-keychain`, loopback page from `ContractPageServer`)

Fixture: the `FakeChromiumProfile` files plus two extra cookies for `127.0.0.1` (one HttpOnly, expiry 2100) and one login; nothing
from a real profile. Run 1 `import`, then run 2 `verify` on the same profile folder.

| Check | Result | Evidence |
|---|---|---|
| Cookies written | PASS | `written=2 skipped=3 failed=0`: the two fixed cookies (2024, 2025) skipped as expired, and a partitioned cookie handed to the engine by hand skipped; the session cookie and the fixture's own partitioned row were not delivered by the reader (`session 1`, `partitioned 1` in its counts) |
| Same batch again | PASS | cookies `written=0 skipped=4`, logins `written=0 skipped=4`: nothing newer than what the profile holds |
| Encrypted at rest | PASS | after run 1, read-only `sqlite3` on the profile's Cookies: for `imported`, `imported-httponly` and `control` the `value` column is empty and `encrypted_value` is non-empty with the `v10` prefix (hex `763130`, 51 and 67 bytes); Login Data `password_value` is 19 bytes with the same prefix for all 4 logins; neither file contains the plaintext (`from-fixture`, `local-pass-512`: 0 hits) |
| Page sees an imported cookie | PASS | page on `http://127.0.0.1:<port>`: `document.cookie` is `imported=from-fixture`; the HttpOnly one is not in it |
| HttpOnly kept | PASS | Cookies table: `imported-httponly` has `is_httponly=1`, `imported` 0 |
| Persists on disk | PASS | after run 1 quit (before the relaunch) the Cookies table holds `imported`, `imported-httponly` and the page's `control` cookie |
| Persists after relaunch | PASS | run 2, same profile: `document.cookie` is `imported=from-fixture; control=page-set` |
| Passwords written | PASS | `written=4 skipped=0 failed=0`; engine log `the store holds 4 logins`; Login Data holds 4 rows with encrypted passwords |
| Passwords after relaunch | PASS | run 2, empty batch: engine log `the store holds 4 logins` |
| Stderr | PASS | no `FATAL`, no `NOTREACHED`, no `Check failed` |

Not run: the `chrome://password-manager` page (the store count above is the evidence), and a cookie from a secure origin or with
`SameSite` set (the fixture writer fixes `samesite` at -1; the `SameSite` context is the inclusive one, as written). The README claimed that encrypted data does not survive a relaunch under the mock keychain; the README was wrong, not the code:
`FakeKeychainV2::FindGenericPassword` returns the fixed password `mock_password`, so the key is the same on every launch (the
README is corrected). A real-keychain relaunch stays a maintainer check.

LaunchServices: the build and the launch registered the test bundle under `dev.arkt.Arkt.try512`; every path was removed with
`lsregister -u` and the count of `try512` entries is 0. No process of this run was left; the embed folder, derived data, throwaway
profile, fixture and logs were deleted.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 10 |
| `arkt` commits above `156.0.8078.48` | 10 |

Equal (in sync). Facade header copies `cmp` identical. `//arkt/api:embedder` gains `arkt_import_writer.{cc,h}` and deps on `//net`,
`//services/network/public/mojom`, `//components/keyed_service/core` and the password store and form targets; the password store
factory is included with `// nogncheck`, as `browser_tabstrip.h` is.

### Verification

- Red first: the new tests did not compile before the types existed. Then broken on purpose and restored: taking the `wipe()` out of
  `ChromiumEngine.importCookies` failed `cookieSecretsAreZeroedAfterTheCall`; reversing the recency test in `ImportRecording`
  failed the contract on both stubs (`same cookie again`).
- ShellKit `swift test --skip ShellKitGUITests`: 1598 passed (905, 38, 60, 6, 153, 49, 257, 108, 22), 0 failed: baseline 1587 + 11
  (3 `InMemoryEngineImportTests`, 2 `FakeEngineImportTests`, 5 `ChromiumImportTests`, 1 ABI conformance test). ArktCore `swift test`:
  all suites passed, including the new fixture extras test.
- `nice -n 15 autoninja -C out/Spike chrome -j 4`: `The build has finished successfully.` Engine app: `xcodegen generate`, then
  `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try512`: `BUILD SUCCEEDED`.

### Review follow-up (PR #528)

- Partitioned cookies skipped (reader: `top_frame_site_key` column-probed, `partitioned` count; `ArcCookie.partitionKey`; facade
  `partitionKey`; engine and both stubs refuse them; fixture row `topFrameSiteKey`; tests in `CookieReaderTests` and the shared
  `EngineImportContract`, which fails on both stubs when the refusal is removed).
- Logins: store read first, skip unless newer, `written` after the store answered. Cookies: drop handlers on `GetAllCookies`,
  `SetCanonicalCookie` and `FlushCookieStore`, so a dropped answer fails the batch.
- Encryption at rest proven (table above); README corrected.

### Left open

- The coordinator (#515) calls these methods and decides what the user is told for skipped and failed counts.
- Partitioned cookies are skipped, not imported (the reader reads `top_frame_site_key` and counts them; the engine and both stubs
  refuse one they are handed). Importing them with their partition key is a later decision.
- A missing answer from the cookie manager (profile teardown) fails the batch with a reason instead of hanging.

## #511: write imported history and bookmarks (engine seam for #131)

Date 2026-10-27. Branch `engine/511-import-history` off `main` at `00cfdae` (after #528). Overlay and Swift only: no Chromium patch,
`.patches` unchanged.

### What landed

- **Facade header (both copies, additive; `cmp` identical).** Protocols `ArktImportHistoryEntry` (url, title, `visitTimes` and
  `visitTransitions` as parallel arrays) and `ArktImportBookmark` (url, title, guid, dateAdded, folderPath); `ArktImportResult`
  gains `lastVisitTime`; `ArktEngine` gains `importHistory:after:completion:` and `importBookmarks:completion:`.
- **History (`ImportHistory`).** `HistoryService::AddPage(HistoryAddPageArgs)` per visit, not `AddPagesWithDetails`: that call fakes one
  LINK visit at `last_visit` and ignores a URL that exists. Each visit keeps its time and core transition; the title goes in with
  the visit; source `SOURCE_OS_MIGRATION_IMPORTED`; `hidden` for subframe transitions; not counted for Most Visited. `visit_count`
  and `typed_count` follow from the visits written (Chromium's own rule: typed visits count, reloads do not add to `visit_count`),
  so Arc's stored `typed_count` is not copied separately. Completion is a `HistoryDBTask` barrier on the history thread, so `done`
  runs after the queued writes. Counts are in visits.
  - Dedupe: the watermark is an input (`after`): a visit at or before it is skipped; the result's `latestVisit` is the newest visit
    written (nil when none). The coordinator (#515) keeps the larger of it and its watermark.
  - Skipped as well: a visit older than 90 days (`HistoryBackend::kExpireDaysThreshold`; the expirer would delete it again) and a
    URL the history refuses (not http, https, ftp, file). An invalid URL fails its visits.
- **Bookmarks (`ImportBookmarks`).** `BookmarkModel` (waits for load), folder "Imported" under Other bookmarks (reused when present),
  nested folders created below it. The record's root (bar, other, synced) is not kept: a decision, everything lands under
  Imported. Dedupe by guid (any node of the profile; case-insensitive), else by url and title inside the target folder; the
  guid and date added are kept. Invalid URL fails.
- **Swift.** `EngineImporting` gains `importHistory(_:after:)` and `importBookmarks(_:)`, result `ImportWriteResult` with a new
  `latestVisit`. `ImportedHistoryEntry` aliases Arc's `HistoryEntry` (EngineAPI already has a back-forward `HistoryEntry`).
  `HistoryTransition.coreValue` is the inverse of `init(webKitValue:)`. `ChromiumEngine`, `InMemoryEngine` and `FakeEngine`
  implement it; the stubs apply the same rules (`ImportRecording`); the shared `EngineImportContract.runHistory` and
  `runBookmarks` run on both stubs.

### Product fact for #131

Chromium keeps 90 days of history. The maintainer's 1016 visits are mostly older: those are skipped (counted), not written.

### Real engine (`dev.arkt.Arkt.try511`, Engine app on `out/Spike`, throwaway profile, `--use-mock-keychain`, `FakeChromiumProfile` fixture)

The fixture's visits are from 2024, so the runner moves them to the last day (gaps kept) and adds one 2024 visit that must be
skipped as stale.

| Check | Result | Evidence |
|---|---|---|
| History written | PASS | `written=5 skipped=1 failed=0` (3 URLs, 5 visits; the stale visit skipped) |
| Re-import with the watermark | PASS | `written=0 skipped=5`, `latest=none` |
| Counts in the profile | PASS | read-only `sqlite3` on `History`: `urls` 4, `visits` 6 (the fixture's 3 and 5, plus the runner's loopback page) |
| Counts per URL | PASS | `example.com`: visit_count 2, typed_count 1 (typed, link, reload); the other two 1 and typed 0 and 1, as Chromium counts |
| Bookmarks written | PASS | `written=5`; `Bookmarks` file: `other` holds `Imported` with Example, Docs, Reading/Article, Other item, Synced item |
| Bookmarks again | PASS | `written=0 skipped=5` |
| Stderr | PASS | no `FATAL`, `NOTREACHED`, `Check failed` |

Not run: `chrome://history` (the `sqlite3` counts are the evidence). LaunchServices: the helpers registered under the `try511` build were
unregistered (`lsregister -u`, count 0); embed folder, derived data, profile and fixture deleted.

### Patch budget

`.patches` lines 10, `arkt` commits above `156.0.8078.48` 10: in sync. Header copies `cmp` identical. `//arkt/api:embedder` gains
deps on `//components/history/core/browser` and `//components/bookmarks/browser`; the two factories are included with `// nogncheck`.

### Verification

- ShellKit `swift test --skip ShellKitGUITests`: 961, 38, 60, 7, 155, 49, 257, 111, 23 passed (1661), 0 failed. ArktCore
  `swift test --filter ArcImportTests`: 218 passed.
- `nice autoninja -C out/Spike chrome -j 4`: finished successfully. Engine app: `xcodebuild -scheme ArktShell -configuration Engine`:
  `BUILD SUCCEEDED`.

### Left open

- The coordinator (#515) stores the watermark and the "Imported" folder is not user-configurable.
- Arc's own `typed_count` is not forced; it is derived from the typed visits.

## #465: the current Favorite tile's selection fades during Open in

Date 2026-10-28. Branch `feat/465-favorite-tile-fade` off `main` at `08db486`. Design: `docs/design/little-arkt.md`, Motion, Open in Space. Follow-up to #455 (the outline-row fade). Closes the known gap recorded in the #455 section: a current Favorite has no outline row, so its tile fill stayed at full strength.

### What changed

- The tile's selection fill and its shadow live on `FavoriteTileView.fillLayer`. `selectionAlpha` sets that layer's opacity, and only while the tile is current. The view layer stays clear at opacity 1, so the favicon (a subview) does not fade. The title is the tile's accessibility label, not a text view, and it is not faded.
- The flight's existing room value is the only clock. `presentArrival` already receives `room` on each flying frame and now also calls `fadeCurrentFavoriteSelection`. The current Favorite is captured once on the first frame (nil when the current tab is not a Favorite; a later current does not start a fade). Fill opacity is `1 - clamp(room, 0, 1)`, the same formula as the outline row.
- Landing (`finishReceiving`) and an abort (`cancelReceiving`) end the fade before the selection moves, so the same turn leaves the tile at fill opacity 1. Reduce Motion never starts a flight, so the tile changes at once and the fade is a no-op. No new timer and no per-frame layout: a frame sets one layer's opacity. A reload mid-flight reapplies the stored fade in `configure`.

### Verification

- Red first, before the fade was wired: `testTheCurrentFavoriteTilesSelectionFadesOnTheRoomSpring` failed because the fill stayed at full strength (`XCTAssertEqualWithAccuracy failed: ("1.0") is not equal to ("0.29524988")` at the stepped 0.26 s room, and `("1.0") is not equal to ("0.0")` at 0.36 s). The same run also failed an assertion on the favicon image view's layer opacity (`("0.0") is not equal to ("1.0")`): AppKit reports that layer at 0 while the view's `alphaValue` is 1. That assertion was removed; the view's `alphaValue`, the tile's `alphaValue` and the tile layer opacity stay the content checks.
- Focused GUI, after the wiring, `nice -n 20 swift test -j 2 --filter 'LittleArktFlightTests|SidebarViewTests'` (window tests, under the GUI lock):
  - `LittleArktFlightTests`: Executed 39 tests, with 2 tests skipped and 0 failures (0 unexpected) in 8.322 (8.327) seconds
  - `SidebarViewTests`: Executed 21 tests, with 0 failures (0 unexpected) in 2.181 (2.183) seconds
  - `ShellKitGUITests` selected: Executed 60 tests, with 2 tests skipped and 0 failures (0 unexpected) in 10.503 (10.510) seconds
  - The new tests are `testTheCurrentFavoriteTilesSelectionFadesOnTheRoomSpring` (ticks the flight at 0, `roomDelay`, 0.26 and 0.36, then steps to landing; expected opacity comes from a separate `LittleArktFlightSpringSet`, not the production helper) and `testReduceMotionKeepsTheFavoriteTileChangeInstant` (flight is nil, tile not current, fill opacity 1).
- `cd app/ArktShell/ShellKit && nice -n 20 swift test -j 2 --skip ShellKitGUITests`: 1095, 38, 60, 7, 181, 49, 257, 111, 23 passed (1821), 0 failed. This change adds no non-GUI tests.
- Not run: ArktCore (`swift test`), the app build and the XCUITest suite. `app/ArktShell/App` and `project.yml` were not touched. The full GUI suite was not run; only the two classes above.

### Deviations

- The issue says the favicon and the title stay at full opacity. The title is the accessibility label, so the test checks that label and the favicon view's `alphaValue`, not a title layer.
- The selection shadow moved onto `fillLayer` with the fill, matching the outline row (the shadow fades with the selection). `testTileShadowPathAndDarkOpacity` now reads `fillLayer`.

### Not covered

- A reload of the tile while it is fading (`configure` reapplies the stored alpha; no dedicated test).
- A page closed mid-flight restoring this tile's fill (wired in `cancelReceiving`; the outline abort tests still pass; no favorite-specific abort assertion).
- These are local runs, not CI.

## #132: downloads wired to Chromium (engine half)

Date 2026-10-28. Branch `engine/132-downloads-wiring` off `main` at `12c91f7`. The shell half (Library, ring, popover, location setting) is #532.

### What landed

- **Facade header (both copies, additive; `cmp` identical).** Event kinds `DownloadCreated` (23), `DownloadUpdated` (24), `DownloadRemoved` (25) with a `download` snapshot (`ArktDownloadItem`: guid, url, filename, target, total and received bytes, state, interrupt reason and danger type as raw Chromium integers, mime type, start and end time, speed, canResume). On `ArktEngine`: `downloads`, `perform(download:on:)` (cancel, pause, resume, open, show in Finder, retry, keep, discard, remove, by guid), `startDownload(from:)`, `downloadPromptsForLocation`, `downloadDirectory`, `defaultDownloadDirectory` and `downloadDestinationHandler`.
- **Overlay, no Chromium patch.** `arkt/api/arkt_downloads.{h,cc}`: `DownloadWatcher` is a `DownloadManager::Observer` plus a `DownloadItem::Observer` on the embedder profile's manager. The facade turns its snapshots into events and merges the updates of one download in a batch into the last one. Commands call `Cancel(true)`, `Pause`, `Resume(true)`, `OpenDownload` (only complete and not dangerous), `ShowDownloadInShell`, `ValidateDangerousDownload` (only while `IsDangerous()` and not blocked), discard (cancel, or delete the finished target, then `Remove`) and `Remove`. Retry resumes in place when `CanResume()`, else `DownloadUrl` with `DownloadRequestUtils::CreateDownloadForWebContentsMainFrame` (an Arkt tab) and removes the old item. The save location is `DownloadPrefs::SetDownloadPath` and `download.prompt_for_download`. The `.ask` panel: `ui::SelectFileDialog::SetFactory` while a handler is set; `SELECT_SAVEAS_FILE` goes to the shell's chooser, every other dialog to the platform dialog (created by stepping the factory aside, because `ui::CreateSelectFileDialog` is not exported from the component).
- **No Chromium download UI.** No change was needed: Arkt windows have no `BrowserView`, so `BrowserWindowFeatures` never creates `DownloadToolbarUIController` (guarded by `if (browser_view)`), `ArktBrowserWindow::GetDownloadBubbleUIController` is null, and 156 has no shelf. `ShowDownloads` (`IDC_SHOW_DOWNLOADS`) opens `chrome://downloads` as a tab; the shell does not call it.
- **Swift.** `ChromiumEngine+Downloads.swift` keeps the list from the events (a repeated update with equal values is dropped, so completion is reported once; an update for an unlisted download lists it; downloads present at start are seeded from `facade.downloads`). Gates run here before the facade: open needs `canBeOpened`, keep needs `canKeep`, discard needs `isHeldForDecision`. A save folder that is missing or not writable is replaced by the default folder before it reaches the prefs (Chromium would create it). `.ask` without a chooser saves to the default folder under the suggested name.

### Deviations and gaps

- While a chooser is set (`.ask`), Save Page As and other `SELECT_SAVEAS_FILE` dialogs also go to the shell's chooser.
- Closing the last window with an active download still waits: `ArktBrowserWindow::ConfirmBrowserCloseWithPendingDownloads` is the old stub. In the real-app check a SIGTERM with a download running ended the process in under 8 s, so it did not hang there; the in-app quit path is not exercised.
- The in-app contract runner has no download driver (rule 24 is not applicable there, as rules 19 to 21); the scripted facade runs rule 24 in plain `swift test`.

### Checks

Red first: with the rule 24 skip removed and no driver, `ChromiumEngineContractTests` failed 14 issues (`the harness has no downloads driver`).

| Check | Result | Evidence |
|---|---|---|
| Contract rule 24 on `ChromiumEngine` | PASS | `ScriptedHarness` `downloads: .scripted()`, both facade scripts: 100 cases, 0 failed; the skip is removed |
| ShellKit `swift test --skip ShellKitGUITests` | PASS | 1100, 38, 60, 7, 181, 49, 257, 119, 25 = 1836 passed, 0 failed (`nice -n 20`, `-j 2`) |
| New tests | PASS | `ChromiumDownloadTests` 8, `DownloadABITests` 2, plus the 14 rule-24 contract checks over two scripts |
| `out/Spike` incremental | PASS | `nice -n 15 autoninja -C out/Spike chrome -j 4`: finished successfully |
| Engine app | PASS | `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try132 -jobs 2`: `BUILD SUCCEEDED` |
| `.patches` | in sync | 10 = `git rev-list --count 156.0.8078.48..arkt` 10 |
| Header copies | identical | `cmp` |

Real app (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try132`, copy on the internal disk, throwaway shell data, profile and defaults suite `arkt-test-132`, `--use-mock-keychain`, loopback server on `127.0.0.1:18432`, save folder a temp folder set through the shell's location pref):

| Check | Result | Evidence |
|---|---|---|
| Download is reported and completes | PASS | facade batches `DownloadCreated`, `DownloadUpdated` (log); `small.bin` 262144 bytes in the chosen temp folder, nothing in `~/Downloads` |
| Ring | PASS | window screenshot: the Library button shows the download ring while a 16 MB download runs |
| Slow download in progress | PASS | `Unconfirmed N.crdownload` grew to 14 MB in the chosen folder |
| Held download | PARTIAL | a no-referrer, no-gesture `.dmg` from a host never visited created a download and wrote no `evil.dmg` (a download from a visited page or with a gesture is not held: `.dmg` is `ALLOW_ON_USER_GESTURE`); the held state was not read in the shell |
| No Chromium bubble | PASS | the window list of the app process had one on-screen window |
| Popover, Cancel, Open, Show in Finder | NOT RUN | the sandbox denies assistive access (`osascript is not allowed assistive access`), so no click or key could be sent to the app; Cancel, Open and Show in Finder are covered by the contract (scripted) and the gates, not by the real app |
| Stderr | PASS | no `FATAL`, `NOTREACHED`, `Check failed` |

Cleanup: the app (SIGTERM) and the loopback server were stopped by PID; `lsregister -u` on both app paths (0 records for `dev.arkt.Arkt.try132`); the copy, the 518 dylib copies, the embed folder, derived data, logs, the defaults suite and the saved files were deleted.

### #132 review fixes

- Save panel: the shell's answer now carries the file type index the caller offered, so Save Page As (which reads its save type from it) no longer gets index 0 (`SAVE_PAGE_TYPE_UNKNOWN`). Plain download saves pass their own index.
- Keep and Discard: Discard acts on every type the shell holds (`IsHeld`, the same set as `isHeldForDecision`) or that Chromium reports dangerous. Keep still calls `ValidateDangerousDownload` only for what `IsDangerous()` reports, because Chromium can validate nothing else: a failed deep scan or maybe-dangerous content stays held in the shell with Discard only in effect.
- A persisted `.ask` preference installs the panel handler in init; `ChromiumDownloadTests` covers it.
- `OnDownloadRemoved` removes the observer before untracking.
- Checks: `ChromiumDownloadTests` and `ChromiumEngineContractTests` pass; `out/Spike` incremental build and the Engine app build succeed. `.patches` 10 = rev-list 10.
- Not run: Cmd-S in the real app. This session has no assistive access, so no key can be sent; the index pass-through is checked by reading `SavePackageFilePicker::FileSelected` (the index is its 1-based `save_types_` position, the same one passed to `SelectFile`), not by a run.

## #513: Install extensions by Web Store id (Import from Arc, #131)

Date 2026-10-29. Branch `engine/513-install-extensions` off `main` at `b5e1fc9`. `$CR` branch `arkt` at 10 commits (0001-0010) before and
after: no patch. Overlay and facade only. `ProfileImportCoordinator` (#545) already calls `EngineImporting.installExtensions(ids:)`;
`ExtensionListReader` (#523) supplies the ids.

### Gate

1. Task: install Web Store extensions by id, with a confirmation, one result per id, skipping what is installed. A seam does it:
   `WebstoreStandaloneInstaller` (the class behind a Web Store "Add to Chrome" click, #121) has virtual hooks for the prompt, so a
   subclass in `//arkt/browser` needs no upstream edit.
2. Facade header: additive only. New `ArktExtensionInstallStatus`, `ArktExtensionInstallResult` and
   `-installExtensions:completion:`; both header copies identical (`cmp`).
3. `.patches`: no change, no patch number claimed.
4. Build and checks: `out/Spike` incremental, the Engine app, ShellKit tests, one real run.

### Decision: one confirmation for the import, then silent installs

Per-extension prompts would show one sheet per extension (an Arc profile often has 10 or more), each asking the same thing after the user
already chose to import. Chromium's `WebstoreInstallWithPrompt` always prompts; but `WebstoreStandaloneInstaller` skips the prompt when
`CreateInstallPrompt()` returns null (`ProceedWithInstallPrompt` then accepts at once), and parks in `OnManifestParsed()` after the listing
is fetched. So `BatchInstaller` (`engine/arkt/browser/arkt_extension_batch_install.mm`) keeps the whole Web Store path (listing fetch,
CRX download, unpack, `CrxInstaller`, blocklist and policy checks) and replaces only the prompt:

1. Every id that the profile does not have starts its fetch in parallel and stops at `OnManifestParsed()`.
2. When all fetches are done, one `ArktDialogSheet` on the key window (else the main, else the frontmost visible window) lists each
   extension found with its permission warnings under its name, and Install and Not now (Not now is the default button, Escape
   cancels). The warnings are Chrome's own: the install prompt's permission set (`GetInstallPromptPermissionSetForExtension`) goes
   through `InstallPromptPermissions::LoadFromPermissionSet` (the `PermissionMessages`), so the strings are the ones Chrome shows
   ("Read and change all your data on all websites"), sub-messages after their warning, "No special permissions" for none. The
   list scrolls inside the sheet when it is long (the sheet's list area is 260 pt high, light and dark colors come from the sheet).
3. Install: `ProceedWithInstallPrompt()` on each, no further prompt, no post-install tab. Not now, a dismissed sheet or no window:
   every waiting id fails with "not confirmed".

Maintainer decision (PR #548): the batch sheet must show each extension's permission warnings, like Chrome's own prompt; done as above.
The first version only named the extensions.

### Cancel and deadline (review of #548)

- `ChromiumEngine.installExtensionResults` wraps the facade call in `withTaskCancellationHandler`. Cancelling the task calls the new
  facade method `-cancelExtensionInstalls`: the sheet closes, listing fetches stop (`AbortInstall`), and every id that is not being
  installed yet fails with "cancelled"; the batch completion still runs once, so the continuation resumes exactly once. An id already
  confirmed finishes with its real result (its download is not stopped).
- Each listing fetch has a 30 s deadline (a timer per id, stopped when the listing arrives): the id fails with "the Web Store did not
  answer" and the others go on to the sheet.
- `ProfileImportCoordinator` checks cancellation before the install and marks the type cancelled after it; a cancelled batch has failed
  ids, so nothing is recorded as handled.

### Contract

| Layer | Change |
|---|---|
| Facade (`arkt_engine.h`, both copies) | `-installExtensions:(NSArray<NSString*>*)ids completion:` with one `ArktExtensionInstallResult` per distinct id (`extensionID`, `status` installed / alreadyInstalled / failed, `failureReason`), main thread, never inside the call, also for an empty array |
| `EngineAPI` | `ExtensionInstallOutcome` (`.installed`, `.alreadyInstalled`, `.failed(String)`), `ExtensionInstallResult`, `EngineImporting.installExtensionResults(ids:) -> [ExtensionInstallResult]?` (default nil). `installExtensions(ids:)` keeps its signature for the coordinator and now defaults to counting the results (`written` installed, `skipped` already installed, `failed` by reason) |
| `ChromiumEngine` | `installExtensionResults` over the facade |
| `InMemoryEngine`, `FakeEngine` | record installed ids; `unavailableExtensionIDs` stands in for ids the store lacks; `EngineImportContract.runExtensions` (order, duplicates, already installed, bad id fails alone, counts) |

Reasons carry no id or name: "not a Web Store id", "not available from the Web Store", "not confirmed", "blocked by policy", "flagged as unsafe",
"already being installed", "not supported on this Mac", "the Web Store listing could not be read", "install failed". A missing item (HTTP 404)
and an unreachable store both reach `WebstoreStandaloneInstaller` as `WEBSTORE_REQUEST_ERROR`, so they share one reason. There is no
batch timeout: a hung fetch holds its own result until the network layer gives up (not seen in the checks).

### Checks

| Check | Result | Evidence |
|---|---|---|
| New tests | PASS | `FakeEngineImportTests` and `InMemoryEngineImportTests` +2 each (contract, unavailable id), `ChromiumImportTests` +6 (results per id, coordinator counts, failed without reason, empty batch, cancelling the task cancels the facade batch and resolves the ids as "cancelled", no cancel without a cancellation), `ProfileImportCoordinatorTests` +1 (cancel during the install; fails without the coordinator change) |
| ShellKit `swift test --skip ShellKitGUITests` | PASS | 1100, 38, 60, 9, 183, 49, 287, 125, 25 = 1876 passed, 0 failed (`nice -n 20`, `-j 2`) |
| `out/Spike` incremental | PASS | `nice -n 20 autoninja -C out/Spike chrome -j 4`: finished successfully (twice: after the files, after the window fallback) |
| Engine app | PASS | `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try513 -jobs 2`: `BUILD SUCCEEDED` |
| `.patches` | in sync | 10 = `git rev-list --count 156.0.8078.48..arkt` 10 |
| Header copies | identical | `cmp` |

Real engine (Engine app on `out/Spike`, bundle id `dev.arkt.Arkt.try513`, throwaway profile, shell data folder and defaults suite under
`profiles/513-*`, `--use-mock-keychain`, `--arkt-import-check=extensions` with `ARKT_EXTENSION_IDS`; the runner presses the sheet's
Install button inside the process, so no synthetic input reached any other app):

| Check | Result | Evidence |
|---|---|---|
| Valid id installs after one confirmation | PASS | ids: uBlock Origin Lite, `not-an-id`, 32 `a`; log `extension install sheet shown count=1`; sheet text "Install 1 extension?" with the one name (the other two failed before the sheet); result `installed` |
| Permission warnings in the sheet (after the maintainer decision) | PASS | sheet text read from the live window: "Install 1 extension? \| These extensions came with your browser data. ... \| Extensions and what they can do \| uBlock Origin Lite \| Read and change all your data on all websites"; result `installed`, 1 extension action |
| Hung Web Store fetch | PASS | `--proxy-server` to a local socket that accepts and never answers: round 1 `failed("the Web Store did not answer")` after 30 s (`extension listing fetch timed out`), no sheet |
| Cancel ends the step | PASS | same setup, the runner cancels the task 3 s in: `failed("cancelled")`, round took 3 s, no sheet, exit 0 |
| Invalid id fails cleanly | PASS | `failed("not a Web Store id")` at once, no sheet row, the other ids unaffected |
| Well-formed id the store lacks | PASS | `failed("not available from the Web Store")` (`result=6`) |
| Installed for real | PASS | extension actions of the window: 1, "uBlock Origin Lite"; profile folder `Default/Extensions/<id>` exists after the run |
| Second call skips | PASS | round 2: `alreadyInstalled`, no sheet, same two failures |
| Store unreachable | PASS | second run with `--proxy-server=http://127.0.0.1:9`: `failed("not available from the Web Store")` in both rounds, no `Extensions` folder, exit 0, no `FATAL`, `NOTREACHED` or `Check failed` |
| Stderr | PASS | 0 hits of `FATAL`, `NOTREACHED`, `Check failed` in the first run |

Not taken: a window capture of the sheet (the text above was read from the window; no screen-recording permission was used). Not run: many extensions in the sheet (the 260 pt list scrolls; the ten-extension layout was not looked at), light and dark by eye (colors come from the shared sheet), the decline path in the real app (scripted facade only), the sidebar import flow end to end (#514 and #545 are the shell side).

Cleanup (both rounds of checks): every app process exited by itself and the local hanging socket was stopped by its PID, confirmed with `ps -p`; `lsregister -u` on the embed copy (4 records for `dev.arkt.Arkt.try513`
before, 0 after); the two profiles, the embed folder with its 518 dylib copies, derived data, build logs and the two defaults suites were
deleted. Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

## #531: history import always answers (PR #565)

Date 2026-11-07. Branch `engine/531-history-import-drop`, `origin/main` merged in at `06275a6`. Overlay and Swift only: no Chromium
patch, `.patches` unchanged.

### What landed

- `HistoryBarrier` answers `false` from its destructor when it is destroyed without having run its reply; `HistoryImport` also
  observes `HistoryServiceBeingDeleted`. Either way the pending visits are counted failed ("no answer from the history store"),
  `done` runs once, posted, and the engine logs `history import: <n> visits got no answer from the history store` (warning).
- `written` and `latestVisit` are counted when the barrier answers, not when the visits are submitted.
- Swift: the continuation in `ChromiumEngine+Importing.swift` resumes for the first answer only.
- Runner phase `--arkt-import-check=history-shutdown` (Engine configuration only): queues 4000 URLs with 10 visits each and quits
  200 ms later, while the history thread is still writing.

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 4 h 16 min (15385 s), 63939 steps: an almost full rebuild after `out/Spike` had last been built on 2026-10-23; swap flat at 3.0 GB, at least 49 GB free on `/` |
| Same command again | `ninja: no work to do.` | 12 s; `arkt_import_writer.o` holds the new warning string |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try531 -jobs 2` (`nice -n 20`) | `BUILD SUCCEEDED` | 174 s; the 518 component dylibs cloned next to the bundle (`cp -c`) |
| ChromiumEngineKit `swift test --filter ChromiumEngineKitTests` after the merge (`nice -n 20`, `-j 2`) | passed | 130 tests in 18 suites (127 in 16 before the merge) |

### Real engine (`dev.arkt.Arkt.try531`, Engine app on `out/Spike`, throwaway profiles under `profiles/531-*`, `ARKT_DATA_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`, `FakeChromiumProfile` fixture)

| Check | Result | Evidence |
|---|---|---|
| Normal import, counted on confirmation | PASS | `--arkt-import-check=import`: `history written=5 skipped=1 failed=0` (the stale visit skipped), `latest` set; same as #511 |
| Re-import with the watermark | PASS | `history again written=0 skipped=5`, `latest=none` |
| Counts in the profile | PASS | read-only `sqlite3` on `History`: `urls` 4, `visits` 6, `visit_source` 5 rows with source 7 (`SOURCE_OS_MIGRATION_IMPORTED`) |
| Service deleted mid-import | PASS | `--arkt-import-check=history-shutdown`: engine log `history import: 40000 visits got no answer from the history store` during shutdown; exit 0 after 5 s, no hang |
| Dropped barrier alone | not run | no shell-reachable way to drop the barrier without the service going away; covered by the scripted-facade double-answer test only |
| Stderr | PASS | 0 hits of `FATAL`, `NOTREACHED`, `Check failed` in both runs |

Finding: in the shutdown run all 40000 visits were on disk afterwards (`visits` 40000, `visit_source` 40000), although the
answer counted them failed. "No answer" means "not confirmed", not "not written". A retry after such a failure has no watermark
from it (`latestVisit` stays nil), so it would write those visits again. The coordinator (#515) has to decide whether to retry;
the answer may also never reach the shell when the run loop has already stopped (it did not print in this run).

Cookies in the same `import` run: `written=0 skipped=3`. The default fixture has no unexpired 127.0.0.1 cookie (the #512 run used
`Options.extraCookies`); not part of this change.

### History sync (#566)

Checked in the pinned sources: `HistorySyncBridge::MaybeCommit` (`components/history/core/browser/sync/history_sync_bridge.cc`)
skips only `SOURCE_ACTOR` visits, a redirect-chain middle and visits from another device. A `SOURCE_OS_MIGRATION_IMPORTED` visit
written by `AddPage` with no redirects is a chain end, so it would be committed when history sync is active. #566 stays open for
the fix.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 10 |
| `arkt` commits above `156.0.8078.48` | 10 |

In sync. Facade header copies `cmp` identical.

### Cleanup

Every app run exited by itself (PIDs checked with `ps -p`). `lsregister -u` on the embed copy and its helpers: 0 records for
`dev.arkt.Arkt.try531` and 0 paths under the embed folder after. Deleted: the embed folder with its 518 dylib clones, derived data,
the four throwaway profiles, the fixture, the two defaults suites and the bundle's empty preferences file, the run and build logs.
Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

## #566: imported visits stay out of history sync

Date 2026-11-07. Branch `engine/566-imported-visits-sync` from `origin/main` (`d323a55`). One Chromium patch (0011), one
overlay test target; facade header and Swift unchanged.

### Why a patch

`HistorySyncBridge::MaybeCommit` is reached from `OnURLVisited`, `OnURLsModified` and `OnVisitUpdated` and skips only
`SOURCE_ACTOR`, a redirect-chain middle and foreign visits. Seams checked in the pinned sources:

| Seam | Why it does not work |
|---|---|
| Write imports as `SOURCE_ACTOR` | actor visits are left out of history queries and the NTP (`visit_database.cc`), so imports would vanish from the History page |
| Write them without `PAGE_TRANSITION_CHAIN_END` | `AddPage` always sets it for a visit with no redirects; `TransitionIsVisible` needs it, so the visits would be hidden too |
| Mark them foreign (`originator_cache_guid`, `AddSyncedVisit`) | turning history sync off runs `DeleteAllForeignVisitsAndResetIsKnownToSync`: the imported history would be deleted |
| Write rows into `HistoryDatabase` from a DB task | no `OnURLVisited`, but `OnURLsModified` still commits the URL's most recent visit later; the omnibox indexes (`InMemoryURLIndex`, `InMemoryHistoryBackend`) see the URLs only after a relaunch; `AddPageVisit`'s URL-row bookkeeping would be duplicated |

### What landed

- Patch 0011 `Arkt: keep imported visits out of history sync`: `MaybeCommit` also returns for
  `SOURCE_OS_MIGRATION_IMPORTED`, right after the `SOURCE_ACTOR` check (4 lines), so all three entry points are covered.
  Not guarded by `IS_MAC`: the upstream importer (`stable_portability_data_importer.cc`) writes the same source.
  Only source 7 is skipped. The older `SOURCE_FIREFOX_IMPORTED`, `SOURCE_IE_IMPORTED` and `SOURCE_SAFARI_IMPORTED`
  (3 to 5) still sync; Arkt never writes them.
  `GetDataForCommit` only serves keys that were tracked, so it needs nothing.
- Test `HistorySyncBridgeTest.ImportedVisitsNotSynced` in the same patch: an imported visit through `OnURLVisited`,
  `OnURLsModified` and `OnVisitUpdated` leaves the processor empty. `NonActorInitiatedVisitsAreSynced` still checks that
  browsed and extension visits are committed.
- Overlay: `//arkt/browser:arkt_patch_unittests` links `//components/history/core/browser:unit_tests` with
  `run_all_unittests`, so the check does not need `components_unittests` (never built in `out/Spike`). It lives in
  `arkt/browser/BUILD.gn` because GN never loads `arkt/BUILD.gn` (nothing depends on `//arkt:arkt`).

### Build and tests

| Step | Result | Numbers |
|---|---|---|
| `nice -n 20 autoninja -C out/Spike arkt_patch_unittests -j 4` (first) | `The build has finished successfully.`, `FAILED:` 0 | 234 s |
| `arkt_patch_unittests --gtest_filter='HistorySyncBridgeTest.*' --test-launcher-jobs=2` | `SUCCESS: all tests passed.` | 37 tests, 9 s |
| Deliberate break: bridge change reverted, test target rebuilt | `HistorySyncBridgeTest.ImportedVisitsNotSynced` FAILED: `processor()->GetEntities().empty()` is false | 13 s build |
| `nice -n 20 autoninja -C out/Spike chrome -j 4` (fix restored) | `The build has finished successfully.`, `FAILED:` 0 | 28 s; `history_sync_bridge.o` recompiled |
| Same command again with the test target | nothing to rebuild | 11 s; the 37 bridge tests pass again |
| `gn check out/Spike //arkt/browser:arkt_patch_unittests` | `Header dependency check OK` | `gn check '//arkt/*'` reports 5 include errors in `arkt/api/arkt_engine_facade.mm` and `arkt/browser/arkt_extension_batch_install.mm`, files this change does not touch |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try566 -jobs 2` (`nice -n 20`) | `BUILD SUCCEEDED`, `Engine framework copied: Chromium Framework.framework 156.0.8078.48` | 176 s; 522 component dylibs cloned next to the bundle (`cp -c`) |

Load average while building: 5 to 8 (other lanes' work; nothing added).

### Real engine, sync off (`dev.arkt.Arkt.try566`, embed folder on `out/Spike`, throwaway profile `profiles/566-20261107/run1`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`, `FakeChromiumProfile` fixture)

| Check | Result | Evidence |
|---|---|---|
| Import with sync off | PASS | `--arkt-import-check=import`: `history written=5 skipped=1 failed=0`, `latest` set; again `written=0 skipped=5` |
| Visits stored | PASS | read-only `sqlite3` on `History`: `urls` 4, `visits` 6, `visit_source` 5 rows with source 7 |
| Nothing tracked for sync | PASS | `history_sync_metadata` 0 rows, 0 visits with `is_known_to_sync` |
| Run | PASS | exit 0 by itself after about 110 s; 0 hits of `FATAL`, `NOTREACHED`, `Check failed` |

Not run: an upload with history sync active. That needs a signed-in account, which test runs never use; the bridge test
is the evidence that an imported visit is not committed.

Limit: visits imported with history sync on before this patch keep their server copies. They are not retracted, and
later updates to them are skipped, so those copies go stale. Accepted, since no build has shipped sync-on imports.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 11 |
| `arkt` commits above `156.0.8078.48` | 11 |

In sync. Export changed only the new patch (patches 0001 to 0010 byte-identical). Facade header copies `cmp` identical.

### Cleanup

The run exited by itself (`ps -p`). `lsregister -u` on the embed copy and its helpers: 0 records for `try566` and 0 paths
under the embed folder after. Deleted: the embed folder with its dylib clones, derived data, the throwaway profile and
fixture, the bundle's preferences file (`dev.arkt.Arkt.try566.plist`) and the logs; the defaults suite had never been
written. Nothing under `~/Applications/ArktTest` or
`/Applications/Arkt.app` was touched.

## #575: a no-op autofill bubble handler

Date 2026-11-07. Branch `engine/575-autofill-bubble-handler` from `origin/main` (`ad916ba`). Overlay only: no patch,
facade header and Swift unchanged.

### Gate

- Seam: the overlay. `ArktBrowserWindow` owns an `ArktAutofillBubbleHandler`
  (`engine/arkt/browser/arkt_autofill_bubble_handler.{h,cc}`) and returns it from `GetAutofillBubbleHandler()`.
- Facade header: unchanged. `.patches`: unchanged (11).
- Build: `nice -n 20 autoninja -C out/Spike chrome -j 4`; disk 1.9 TB free on the Chromium disk, 45 GB internal.

### Caller audit (pinned sources)

Two things the issue text did not have:

1. Half of the callers do not go through `BrowserWindow::GetAutofillBubbleHandler()`. Save card, IBAN, offer
   notification, churned users and wallet reminder call `AutofillBubbleHandler::Get(browser->GetUnownedUserDataHost())`,
   the user data `AutofillBubbleHandlerImpl` registers in its constructor. Without that registration they find no
   handler; churned users (`payments_churned_users_bubble_controller.cc:150`, :218) dereferences `Get()` unchecked.
   The handler registers itself the same way (`ui::ScopedUnownedUserData`).
2. Most callers dereference the returned bubble: `SetBubbleView(*handler->Show...())`, several followed by
   `CHECK(bubble_view())`. So the plan's nullptr return would crash them. Those methods return one process-wide no-op
   `AutofillBubbleBase` (`Hide()` does nothing, `IsMouseHovered()` is false). It is a `base::NoDestructor`, not a
   handler member: each controller belongs to its tab (`WebContentsUserData`), not to the window, and keeps the raw
   pointer until it calls `Hide()` or hears the bubble closed. A tab can move to another window and outlive this one,
   so a bubble that died with the handler could dangle. Only the three callers that check the result get nullptr.
3. Review fix: save card, IBAN and the address bubbles are told in a posted task that the bubble closed untouched,
   so they let go of the no-op bubble (see "Review fix: close notifications" below).

Every `Show*` logs `ARKT: autofill bubble <name> not shown` on each call.

| Caller | Reaches the handler through | Uses the returned bubble | Handler returns | Result |
|---|---|---|---|---|
| `save_card_bubble_controller_impl.cc:845`, :848 (save card, save card confirmation) | `Get()`, null-checked at :126, :173 | `*`, `CHECK` at :851 | no-op bubble, then a posted `OnBubbleClosed(kNotInteracted)` | no crash, not shown (smoke) |
| `iban_bubble_controller_impl.cc:156`, :494 (IBAN, IBAN confirmation) | `Get()`, null-checked at :56, :75 | `*`, `CHECK` at :497 | no-op bubble, then a posted `OnBubbleClosed(kNotInteracted)` | no crash, not shown (smoke) |
| `offer_notification_bubble_controller_impl.cc:239` | `Get()`, unchecked | `*` | no-op bubble | no crash, not shown (by construction) |
| `mandatory_reauth_bubble_controller_impl.cc:298` | `GetAutofillBubbleHandler()`, unchecked | `*` | no-op bubble | no crash, not shown (by construction) |
| `filled_card_information_bubble_controller_impl.cc:428` | `GetAutofillBubbleHandler()`, unchecked | `*`, `DCHECK` | no-op bubble | no crash, not shown (by construction) |
| `virtual_card_enroll_bubble_controller_impl.cc:389`, :396 (enroll, confirmation) | `GetAutofillBubbleHandler()`, unchecked | `*`, `DCHECK` | no-op bubble | no crash, not shown (by construction) |
| `autofill_ai_import_data_controller_impl.cc:242` (save, local save notification) | `GetAutofillBubbleHandler()`, unchecked | `*` | no-op bubble | no crash, not shown (by construction) |
| `omnibox_autofill_bubble_controller.cc:130` | `GetAutofillBubbleHandler()`, unchecked | null-checked | nullptr | no crash, not shown (by construction) |
| `payments_churned_users_bubble_controller.cc:150`, :218 (bubble, confirmation) | `Get()`, unchecked | null-checked | nullptr | no crash, not shown (by construction) |
| `wallet_reminder_notice_bubble_controller.cc:139` | `Get()`, null-checked | null-checked | nullptr | no crash, not shown (by construction) |
| `address_bubbles_controller.cc:61`, :75, :86 (save, update, sign-in promo) | `FindBrowserWindowWithWebContents()`, unchecked | `*`, `CHECK` at :248, :344 | no-op bubble; save and update then post the owned controller's `OnBubbleClosed()` | crashed before the handler (smoke). Since #768 (patch 0012): save and update reach the handler, no crash, not shown, posted close runs (smoke); sign-in promo not reached (needs DICE sign-in) |

"By construction" rows were not reached in a fresh profile: they need a signed-in account, server cards, offers,
Autofill AI data or the omnibox autofill flow. The handler and the bubble are non-null for them, and the table records
whether each dereferences the result.

The address bubbles never reach the handler. `BrowserWindow::FindBrowserWindowWithWebContents`
(`browser_view.cc:1173-1190`) returns only a `BrowserView`, so it is nullptr on an Arkt window, and the crash is the
`->GetAutofillBubbleHandler()` on it. No overlay seam changes that lookup. #768 asks which patch to take.

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 46 s |
| `gn check out/Spike //arkt/browser:window` | 1 error, in `arkt_extension_batch_install.mm:29` (already listed under #566); none in the files this change touches | |
| Deliberate break: registration removed (`scoped_user_data_`), rebuilt | card save logs nothing (0 `ARKT: autofill` lines) | 29 s build |
| Fix restored, rebuilt | `The build has finished successfully.`, `FAILED:` 0; card save logs again | 28 s build |

Load average while building and running: 2 to 5 (other lanes' work; nothing added).

### Smoke, first version (`out/Spike/Chromium.app`, throwaway profiles under `profiles/575-20261107/`, `--use-mock-keychain`, forms served from `127.0.0.1`, typed and submitted over the DevTools protocol)

| Run | Check | Before (`origin/main` build) | After |
|---|---|---|---|
| card | Luhn-valid card, future expiry, submitted | no crash, nothing logged: save card finds no handler and gives up | `ARKT: autofill bubble SaveCreditCard not shown`, no crash |
| card, same tab | a second card on the same tab | | not logged: the save-card controller still holds the no-op bubble |
| IBAN, same tab | `DE89370400440532013000` on the tab of the two cards | | not logged |
| tab switch and close | new tab opened, the card tab hidden and closed | | no crash (`Hide()` on the no-op bubble from `OnVisibilityChanged` and the controller destructor) |
| IBAN | `DE89370400440532013000` on a fresh tab | | `ARKT: autofill bubble Iban not shown`, no crash |
| card after IBAN | another card on that tab | | `ARKT: autofill bubble SaveCreditCard not shown`, no crash |
| window close | last tab closed | | `ARKT: native window destroyed`, no crash |
| address | full US address with country, phone and email | `Received signal 11 SEGV_ACCERR 000000000000`, top frame `autofill::(anonymous namespace)::ShowSaveBubble` | same crash, same frame: unchanged by this task |

`FATAL`, `NOTREACHED` and `Check failed` lines in the card, IBAN and window runs: 0.

In this first version a controller that received the no-op bubble reported `IsShowingBubble()` until its tab was
hidden or closed, and a later autofill prompt on that tab could be skipped, of the same kind or another (the two "same
tab" rows). The review fix below removes that for save card, IBAN and the address bubbles.

### Review fix: close notifications

The limit is not inherent to a handler that shows nothing: a controller lets go of its bubble when it hears that the
bubble closed. The handler now tells it, in a posted task, because the caller stores the returned bubble and CHECKs it
after `Show*` returns (`save_card_bubble_controller_impl.cc:845-851`, `iban_bubble_controller_impl.cc:494-497`):

- Save card, save card confirmation, IBAN, IBAN confirmation: the controller's `GetOnBubbleClosedCallback()` (bound
  to a weak pointer, `save_card_bubble_controller_impl.cc:422-424`, `iban_bubble_controller_impl.cc:259-261`) runs
  with `PaymentsUiClosedReason::kNotInteracted`. That reason records no user decision
  (`save_card_bubble_controller_impl.cc:669-672`, `iban_bubble_controller_impl.cc:373-383`).
- Save and update address: the handler owns the controller it is given, so it moves it into the posted task and calls
  its `OnBubbleClosed()`, which reaches `AddressBubblesController` through the controller's weak delegate
  (`save_address_bubble_controller.cc:250-252`). Not reachable until #768: the address flow crashes before the
  handler.

The limit remains for the five controllers that keep the no-op bubble until their tab is hidden or closed: offer
notification, filled card, mandatory re-auth, virtual card enroll and Autofill AI. None of them is reachable in a
fresh profile.

| Step | Result | Numbers |
|---|---|---|
| `git merge origin/main` (1 commit behind, Swift only) | merged, no conflicts | |
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 36 s |
| `gn check out/Spike //arkt/browser:window` | the same single error in `arkt_extension_batch_install.mm:29`; none in the files this change touches | |
| Smoke, one tab: card, a second card, an IBAN after the cards | `SaveCreditCard not shown` twice, then `Iban not shown`; no crash | |
| Same run: a second IBAN, a new tab, both tabs closed | `Iban not shown`, `ARKT: native window destroyed`; no crash | |
| Deliberate break: posted close removed from the card and IBAN methods, rebuilt | one tab, card, card, IBAN: only the first `SaveCreditCard not shown` is logged | 27 s build |
| Fix restored, rebuilt, same three submissions | `SaveCreditCard not shown` twice, `Iban not shown`; `FAILED:` 0 | 27 s build |

`FATAL`, `NOTREACHED`, `Check failed` and `Received signal` lines in these runs: 0. Load average 3 to 6 (other lanes'
work; nothing added).

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 11 |
| `arkt` commits above `156.0.8078.48` | 11 |

In sync; nothing exported. Facade header copies `cmp` identical.

### Cleanup

Every Chromium run stopped by exact PID or crashed (`ps -p` prints nothing); the local HTTP server stopped by PID.
Deleted: the throwaway profiles under `profiles/575-20261107/`, the logs, and the two crash reports the address runs
wrote. Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

## #577: tab state seams in the facade (crash, zoom, HTML fullscreen, crashed session)

Date 2026-11-07. Branch `engine/577-tab-state-seams` from `origin/main` (`d10ec13`). Engine side of #576 (PR #660).
Overlay and facade only: no patch.

### Gate

- Seams: the facade's per-tab `TabObserver` (crash, recovery, zoom, fullscreen), the facade engine (crashed session),
  `ArktInfobarPresenter` and `ArktBrowserWindow::LayoutInfobars` (no infobar height while a tab is fullscreen).
- Facade header: additive only, both copies `cmp` identical. Four event kinds after 25 (`TabCrashed` 26,
  `TabRecovered` 27, `ZoomChanged` 28, `TabFullscreenChanged` 29), two enums (`ArktTerminationStatus`,
  `ArktZoomCommand`), five event values, four tab handle values and `zoomWithCommand:`, and on `ArktEngine`
  `lastSessionCrashed` and `dismissLastSession`. Required members, as #364 added sound: the Swift doubles
  (`ScriptedFacade`, the ABI conformance doubles) grew them.
- `.patches`: unchanged (11). `//components/zoom` added to `//arkt/api:embedder`; `exit_type_service.h` is included with
  `nogncheck` (it is built into `//chrome/browser`).
- Build: `nice -n 20 autoninja -C out/Spike chrome -j 4`; 1.9 TB free on the Chromium disk, 42 GB on `/`, swap 2.9 GB
  used before and after.

### What landed

- **Crash.** `PrimaryMainFrameRenderProcessGone`: fullscreen left and the load ended (both reported only if they still
  differ), then one `TabCrashed` with the folded status. `RenderViewTerminated` exits fullscreen before it notifies, and
  resets the load progress without a load end, so the facade reports `LoadingChanged NO` itself; the later
  `DidStopLoading` finds nothing new. `EVICTED_FOR_MEMORY` folds to out of memory (it is in `IsCrashed()`'s set but was
  not in #576's list).
- **Recovery.** No observer hears `WebContentsImpl::NotifyPrimaryMainFrameProcessIsAlive`, so the facade checks
  `IsCrashed()` at `RenderFrameCreated` and `RenderFrameHostChanged` of the primary main frame (both come right after it)
  and at the commit as a fallback, and reports `TabRecovered` once.
- **Zoom.** The tab's `zoom::ZoomController` is observed (attached by the tab helpers; observed once it exists).
  `ZoomChanged` is recorded only when the percent or the default flag changed. User initiated means the change came
  from this tab's controller (old level differs from new in the event data): the facade's own `zoomWithCommand:`,
  Chromium's zoom commands, `chrome.tabs.setZoom`. A host zoom map change reaches the other tabs of the host with the
  current level twice: not user initiated. `can_show_bubble` was not used: it is false for an empty host.
  `zoomWithCommand:` runs `zoom::PageZoom::Zoom` synchronously, so ChromiumEngine reports the change when its
  `zoomIn`/`zoomOut`/`resetZoom` returns (contract rule 25) and drops the facade's later event for it (it maps
  `ZoomChanged` from the handle's live zoom).
- **`ZoomChangedForActiveTab` (pinned sources).** 156 no longer calls it on `BrowserWindow`: `BrowserView` subscribes to
  `BrowserWindowZoomObserver` (`browser_view.cc:1072-1076`) and forwards to its toolbar. Nothing reaches
  `ArktBrowserWindow`; the per-tab controller is the seam.
- **HTML fullscreen.** `DidToggleFullscreenModeForTab` (with `WebContents::IsFullscreen()`, so a pending enter counts).
  `ArktInfobarPresenter` now also observes its contents and asks for a layout when fullscreen toggles;
  `LayoutInfobars` takes the stack out while `contents->IsFullscreen()`, and puts it back after.
- **Crashed session.** The facade reads `ExitTypeService::GetLastSessionExitType(profile) == kCrashed` once when it
  starts (the value is fixed when the service is made) and keeps the shell's dismissal for the run. Chromium's own
  acknowledgement cannot be used: the first tab of a window created outside the startup flow acknowledges the crash
  (`ExitTypeService::BrowserTabObserverImpl`), and every shell window is one, so Chromium's flag is already cleared
  when the shell asks. Chromium's bubble needs a `BrowserView` (`SessionCrashedBubbleView::ShowBubble` returns early),
  so it never shows on an engine window: no double prompt.
- **ChromiumEngine** (`ChromiumEngine+TabState.swift`): maps the four kinds (snapshot written before the event, the
  #581 note), seeds a listed tab's snapshot from the handle, forwards the three zoom calls and vends
  `ChromiumSessionRecovery` (one object; a dismiss when nothing crashed does not reach the facade).
- **Contract runner and kit tests:** rule 25 runs against Chromium (`chromiumChecks` is every rule below 26). The
  scripted harness's `crashTab` records a RenderProcessGone batch; the app runner's navigates the tab to
  `chrome://crash`. With the plain switch the runner prints `ARKT_CONTRACT rule 26 <check> DEFERRED (#583)` for each
  check it does not run. Header comment fixed (it said "all 18 rules").
- Self-test embedder: logs the four events and the tab state in `state`; commands `zoom in|out|reset`,
  `zoom-command plus|minus|normal` (the host's `executeCommand` with `IDC_ZOOM_PLUS`/`MINUS`/`NORMAL`, what the main
  menu's Cmd-+ and Cmd-0 send), `fullscreen [exit]` and `session [dismiss]`.

### Tests first

`ChromiumTabStateTests` (14 cases) and `TabStateABITests` (3) were written against the new header before ChromiumEngine
mapped anything: 13 issues failed for the right reason (no events, `sessionRecovery` nil). `ChromiumTabStateDefaultsTests`
(which asserted that ChromiumEngine reports nothing) was replaced by them. Deliberate breaks: with ChromiumEngine's
`hub.emit(.tabRecovered(id))` commented out, two `ChromiumTabStateTests` and the contract case
`reloadRecoversACrashedTabOnce` fail (`recovery reported 0 times, want 1`); with the facade's `TabRecovered` emit
removed, a self-test reload of a crashed tab logs no `tabRecovered`. Both restored and green again.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` (first version) | 141 + 28 + 279 passed, 0 failed: ChromiumEngineKitTests (14 new `ChromiumTabStateTests`, the rule 25 contract cases over both facade scripts, 1 defaults test removed), ArktEngineABITests (3 new `TabStateABITests`), EngineAPITests (1 new `TabStateTests` case: the snapshot inside the `.tabFullscreenChanged` handler) |
| Full suite (`swift test --skip ShellKitGUITests`) | not run locally (several lanes building on this Mac); CI's Swift tests job |

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 42 s |
| `gn check out/Spike //arkt/api:embedder`, `//arkt/browser:window` | the pre-existing errors only (`find_in_page` headers in the facade, `webstore_install_result.h`); none for the new includes | |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try577 -jobs 2` (`nice -n 20`, `CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-577`) | `BUILD SUCCEEDED`, `Engine framework copied: Chromium Framework.framework 156.0.8078.48` | 3 min; 522 component dylibs cloned next to the bundle (`cp -c`) |

Load average 2 to 9 while building and running (other lanes' work; nothing added).

### Self-test runs (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api`, fresh profiles under `profiles/577-20261107/`, `--use-mock-keychain`, pages from a loopback server, commands through the page title over the DevTools protocol)

| Check | Result | Evidence |
|---|---|---|
| Zoom through the facade | PASS | `zoom in` x3: `zoomChanged percent=110`, `125`, `150`, each `user=yes`; `zoom out`: `125`; `zoom reset`: `100 default=yes`; a second reset: nothing |
| Chromium's zoom commands (Cmd-+, Cmd-0 path) | PASS | `zoom-command plus` x2: `110`, `125` `user=yes`; `normal`: `100 default=yes`; a second `normal`: `enabled=no`, nothing |
| Zoom per host | PASS | a `window.open` tab on the same host starts with `zoomChanged percent=110 user=no`; zooming the first tab to 125 reports `125 user=no` on the second; the second navigating to `localhost`: `100 default=yes user=no` |
| `chrome://crash` | PASS | `loadingChanged loading=no`, then `tabCrashed status=1` (crashed) `loading=no listed=yes`; a second crash of the tab before recovery reports nothing |
| Zoom of a crashed tab | PASS | `zoom in` on it: no event, zoom stays 100 (Chromium does not zoom a page without a live frame) |
| Recovery | PASS | `reload` of the crashed tab: `tabRecovered live=0 loading=yes`, before the reload's `urlChanged` and `loadingChanged`; a navigation of a crashed tab: `tabRecovered`, then the new URL |
| `requestFullscreen` with an infobar | PASS | automation infobar raised from `chrome://infobar-internals` (`internal_only_uis_enabled` set in the fresh profile's Local State): `innerHeight` 600 -> 560, container subviews 2; `fullscreen`: `ARKT: enter fullscreen`, `tabFullscreenChanged fullscreen=yes`, container subviews 1 (no infobar height), page 1130x1800; `fullscreen exit`: `fullscreen=no`, subviews 2, page 560x900 again |
| Crash while fullscreen | PASS | `ARKT: exit fullscreen`, `loadingChanged no`, `tabFullscreenChanged fullscreen=no`, then `tabCrashed` |
| `chrome://gpucrash` | NOT REACHED | a facade navigation is `PAGE_TRANSITION_TYPED` without `FROM_ADDRESS_BAR`, and content handles browser debug URLs only for an explicit navigation (`ContentBrowserClient::IsExplicitNavigation`); the DevTools `Page.navigate` is not one either (`net::ERR_ABORTED`, the GPU process kept its pid). See "Needs the maintainer" below |
| GPU process exits (the GPU helper of the test build killed by PID, 6 times) | PASS to 5 | after each of exits 1-5: `GPU process exited unexpectedly`, `Reinitialized the GPU process after a crash`, the window and both tabs listed, no tab or window event. Exit 6: `GPU process isn't usable. Goodbye.`, the browser ends (Chromium's limit; exits 4-5 already reinitialized in 0 ms, the software fallback) |
| Killed browser, relaunch (`relaunch` profile, SIGKILL by PID) | PASS | killed 15 s after start (`exit_type` `Crashed` on disk), relaunched: `facade last session crashed`, `embedderReady lastSessionCrashed=yes`, `0 queued request(s)` and one window (Chromium restored nothing and showed no bubble); `session`: yes; `session dismiss`: `crashed session dismissed`, no; a second dismiss: no; SIGTERM: `exit_type` `SessionEnded`; relaunch: clean |
| Killed 7 s after a fresh start | finding | relaunch reported clean: the first `Preferences` write had not happened yet, so no `Crashed` mark was on disk |
| Crash, relaunch, quit without answering | finding | the next relaunch reports clean: Chromium acknowledged the crash itself when the shell's first window got its tab, so a clean quit writes `SessionEnded`. Chrome's own behaviour (the crash stays until the bubble is answered) would need the facade to keep the mark; see "Needs the maintainer" |

`FATAL`, `NOTREACHED`, `Check failed` lines: 0 in every run except the sixth GPU exit (Chromium's own fatal, above).

### In-app contract (`dev.arkt.Arkt.try577`, Engine app on `out/Spike`, `--arkt-engine-contract --arkt-engine-test-api`, tabs probe, throwaway profile, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`)

| Check | Result |
|---|---|
| Rule 25 `zoomStepIsReportedOnceAndNothingAtTheEnds` | PASS (89 ms) |
| Rule 25 `crashedTabStaysListed` (`chrome://crash`) | PASS (691 ms) |
| Rule 25 `reloadRecoversACrashedTabOnce` | PASS (3841 ms) |
| Rule 26 (3 checks) | `DEFERRED (#583)` |
| Result | `21/25`, exit 1: rules 19, 20, 21 and 24 are NOT-APPLICABLE as before (the runner has no `raiseDialog`, `raisePermission`, `raiseInfobar` or `downloads` driver); every other rule PASS, 0 `FATAL` |

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 11 |
| `arkt` commits above `156.0.8078.48` | 11 |

In sync; nothing exported. Facade header copies `cmp` identical.

### Left open

- `chrome://gpucrash` from the shell, and the unanswered crashed session across runs (maintainer questions in the pull
  request).
- The shell side: #578 (crash panel), #579 (zoom), #581 (fullscreen), #580 / #690 (restore).

### #577 review fixes (PR #770)

- **Replaced contents clear a crash.** `ReportAll` (new contents after `TabReplaced`) now calls `ReportRecovery()` after
  `ReportCrash`: live new contents end the crash, so the tab's next real crash is reported. The scripted facade models
  it (`replaceContents(live:)` records `TabRecovered` after `TabReplaced`); `ChromiumTabStateTests` checks crash,
  live replacement, crash again (`tabCrashed`, `tabRecovered`, `tabCrashed`) and that crashed replacement contents
  keep the crash. Deliberate break: without the recovery in `replaceContents`, the second crash is lost and the test
  fails (2 issues); restored. A replacement of a crashed tab's contents was not reachable in the self-test, so the
  real path is covered by the scripted model only.
- **Scripted order.** The scripted facade reports `TabRecovered` before the URL and the load start of the reload or
  navigation, as the real facade does (`RenderFrameCreated` comes first, seen in the self-test runs above).
- **Zoom batch rule: the last event wins.** ChromiumEngine reports one change per tab and batch, from the live zoom,
  with the user flag of the batch's last `ZoomChanged` for that tab (the event that set the live zoom). Tested both
  ways; with the event's own flag instead, both cases fail; restored.
- **Header:** the `ZoomChanged` comment notes that in an isolated or manual zoom mode a navigation can report user
  initiated (both copies, `cmp` identical).
- `ContractCheck.chromiumDeferred` reads a rule-to-issue map (`chromiumDeferredRules`, `[26: 583]`); doc comments moved
  to the members they describe (`lastSessionCrashed`, `isFiltered`).

| Check | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` (`nice -n 20`, `-j 2`) | 144 + 28 + 279 passed, 0 failed (3 new ChromiumTabStateTests cases plus the 2-argument batch test) |
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | finished successfully, `FAILED:` 0; `gn check` only the pre-existing errors |
| Self-test, fresh profile: zoom in, then `chrome://crash`, reload, `chrome://crash`, reload | `zoomChanged 110 user=yes`; `tabCrashed`, `tabRecovered`, `tabCrashed`, `tabRecovered`; 0 `FATAL` |
| `.patches` | 11 = 11, in sync |

Cleanup: the self-test and the loopback server stopped by PID; the profiles, the build log and the three crash dumps
of the run deleted.

## #768: address bubbles find the Arkt window (patch 0012)

Date 2026-11-07. Branch `engine/768-address-bubble-window` from `origin/main` (`659a70d`). One Chromium patch (0012),
option A as decided in the issue; overlay, facade header and Swift unchanged.

### Gate

- Why a patch: `BrowserWindow::FindBrowserWindowWithWebContents` (`browser_view.cc:1173-1190`) returned only a
  `BrowserView`, and the address bubbles dereference its result before any handler is asked (`address_bubbles_controller.cc:61`,
  :75, :86). No overlay seam changes that static lookup.
- Facade header: unchanged (`cmp` identical). `.patches`: 11 to 12, number 0012 claimed in the issue; no open engine
  pull request touches either file, and no earlier patch touches them.
- Build: `nice -n 15 autoninja -j 4 -C out/Spike chrome`; Chromium disk 1.9 TB free, internal 37 GB, swap 2.9 of 4 GB.
  Overlay link checked: `$CR/arkt` points at this worktree's `engine/arkt`.

### What landed

Patch 0012 `Arkt: find a non-BrowserView window for a WebContents`, 2 files, 13 insertions, 4 deletions (after the
review rework below; the first version had 14 and 8):

- `FindBrowserWindowWithWebContents`, tab lookup: before the old return line, the tab's window from
  `BrowserWindow::FromBrowser(browser)` is returned when it is not a `BrowserView` (the `browser` local is no longer
  const). `FromBrowser` ends in `GetWindow()`, the Arkt window. A `BrowserView` window, including one being torn down
  (when `FromBrowser` reaches it through `GetWindow()`), takes the old return line. A `WebUIBrowserWindow` also
  changes: it was nullptr from the tab lookup and is now returned.
- The widget branch is not patched. Arkt tabs sit in Arkt's own `NSWindow`, not in a Views widget, so their lookup
  reaches the tab branch: the smoke below passes without a widget hunk. Contents that are not a tab (WebUI bubbles,
  dialogs) in a non-`BrowserView` widget still get nullptr.
- `MaybeShowIOSDektopAddressPromo`: returns when `AsBrowserView()` is nullptr instead of dereferencing it. Only reached
  after the user accepts the save prompt (`OnUserDecision`, kAccepted), which the no-op handler never does, so it is
  covered by construction, not by the smoke.

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 15 autoninja -j 4 -C out/Spike chrome` (first version) | `The build has finished successfully.`, `FAILED:` 0 | incremental |
| Deliberate break 1: `browser_view.cc` back to the pinned version (`git checkout HEAD~1 --`), rebuilt | finished, `FAILED:` 0 | 47 s |
| Deliberate break 2: patch in, overlay `PostAddressClosed` returning before it posts, rebuilt | finished, `FAILED:` 0 | 46 s |
| Both restored, rebuilt | finished, `FAILED:` 0; `git status` clean in both trees | 30 s |
| Review rework: tab-lookup hunk reworked, widget hunk dropped (arkt commit amended), rebuilt | finished, `FAILED:` 0 | 47 s |
| Break 3: `browser_view.cc` back to the pinned version, rebuilt | finished, `FAILED:` 0 | 44 s |
| Restored, rebuilt | finished, `FAILED:` 0; `git status` clean | 46 s |

Load average 3 to 6 (other lanes' work; nothing added).

### Smoke (run1, run2, break 1 and break 2 on the first version; run3 and break 3 on the reworked patch; `out/Spike/Chromium.app`, fresh profiles under `profiles/768-20261107/`, `--use-mock-keychain`, form on `127.0.0.1:8768`, fields typed with `Input.insertText` over the DevTools protocol)

Every run starts with `ARKT: browsers normal=1 arkt=1 views=0`: the form tab is on an Arkt window. Saved addresses for
the update rows are written through `chrome.autofillPrivate.saveAddress` on `chrome://settings/addresses` (no phone),
then the form is submitted with the same name and address plus a phone. All submissions in one tab.

| Run | Check | Result |
|---|---|---|
| run1, run2, run3 | full US address (name, street, city, state, ZIP, country, phone, email) | `ARKT: autofill bubble SaveAddressProfile not shown`, no crash |
| run1, run2, run3 | second and third different addresses, same tab | `SaveAddressProfile not shown` each time: the posted `OnBubbleClosed()` ran and the controller let go of the no-op bubble |
| run1, run2, run3 | stored address submitted again with a new phone | `ARKT: autofill bubble UpdateAddressProfile not shown`, no crash |
| run2, run3 | the same update a second time, same tab | `UpdateAddressProfile not shown` again |
| run1, run2, run3 | tab closed | `ARKT: native window destroyed`, no crash |
| break 1 | first address submit | `Received signal 11 SEGV_ACCERR 000000000000`; crash report top frame `autofill::(anonymous namespace)::ShowSaveBubble`, then `AddressBubblesController::DoShowBubble` |
| break 3 (tab-lookup change reverted) | first address submit | the same crash: `Received signal 11 SEGV_ACCERR 000000000000`, top frame `ShowSaveBubble`, then `AddressBubblesController::DoShowBubble` |
| break 2 | three different addresses, same tab | only the first `SaveAddressProfile not shown`; the next two prompts are not shown: without the posted close the controller keeps the no-op bubble |

`FATAL`, `NOTREACHED`, `Check failed` and `Received signal` lines in run1, run2 and run3: 0. In run1 and break 1 the submit was a
synthetic mouse click; in the later runs the window was occluded (`visibilityState` hidden) and dropped synthetic
clicks, so the button was clicked from script (`click()` with a user gesture); the typed values are the same.

### Other callers of `FindBrowserWindowWithWebContents`

The three unchecked callers named in the issue were not reachable in a fresh profile, and the patch helps them only
when the contents are a tab of an Arkt window:

| Caller | Needs | On an Arkt window |
|---|---|---|
| `managed_profile_required_navigation_throttle.cc:213-215` (`->Show()`) | an enterprise sign-in that creates a managed profile | the enterprise action tab now finds the Arkt window (by construction) |
| `access_code_cast_dialog.cc:65-66` (`->GetBounds()`) | the access code Cast policy | if `web_contents` is a tab of an Arkt window, the lookup now finds the Arkt window; not checked (by construction) |
| `webui_contents_wrapper.cc:195-196` (`->OpenEyeDropper()`) | a WebUI bubble with an eye dropper | still nullptr: bubble contents are not a tab |

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 12 |
| `arkt` commits above `156.0.8078.48` | 12 |

In sync. Export changed only `.patches` and the new patch (patches 0001 to 0011 byte-identical). Facade header copies
`cmp` identical.

### Cleanup

Every Chromium run stopped by exact PID or exited when its last tab closed, and the break 1 run crashed (`ps -p` prints
nothing); the loopback server stopped by PID. Deleted: the throwaway profiles under `profiles/768-20261107/`, the build
logs and the one crash report break 1 wrote. Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was
touched.

## #583: page info and per-site permissions in the facade

Date 2026-11-07. Branch `engine/583-page-info-seam` from `origin/main` (`a1f49a5`). Engine side of #582 (PR #691).
Overlay and facade only: no patch. Contract rule 26, deferred to this issue by #770, now runs against Chromium.

### Gate

- Seams: a new overlay file pair `arkt/api/arkt_page_info.{h,cc}` (`PageInfoHub`), reached from the facade's tab handle
  and engine; the facade's `TabObserver` for the security state. No upstream file is touched.
- Facade header: additive only, both copies `cmp` identical. One event kind after 29 (`PageInfoChanged` 30, no values),
  three enums (`ArktPageConnection`, `ArktPermissionSetting`, `ArktSitePermissionKind`, the last in `SitePermissionKind`
  order), three value protocols (`ArktSitePermission`, `ArktPageInfo`, `ArktSitePermissions`), on the tab handle
  `pageInfo`, `setPermission:toSetting:forOrigin:`, `resetPermissionsForOrigin:`, `pageInfoDidClose` and
  `openSiteSettingsForOrigin:`, on the engine `sitesWithPermissions`. Required members, as #577 added its own: the
  Swift doubles (`ScriptedFacade`, the ABI conformance doubles) grew them.
- `.patches`: unchanged (12). New deps of `//arkt/api:embedder`: `//components/browsing_data/content`,
  `//components/content_settings/{browser,core/browser,core/common}`, `//components/page_info`,
  `//components/permissions`, `//components/security_state/core`, `//components/strings`, `//components/url_formatter`.
  The `chrome/browser` headers (`ChromePageInfoDelegate`, `ChromeBrowsingDataModelDelegate`, the content settings and
  auto blocker factories, `chrome_security_state_util.h`, `profile_observer.h`) are included with `nogncheck`, as the
  facade already does for `//chrome/browser` code.
- Build: `nice -n 20 autoninja -C out/Spike chrome -j 4`; 1.9 TB free on the Chromium disk, 40 GB on `/`.

### What landed

- **Reads are plain reads** (`PageInfoHub::Read`), cheap enough for the shell's pill, which reads the current tab's page
  info on every address refresh. Nothing is created per read: no Chromium `PageInfo`, no metrics.
  - Connection: `chrome_security_state::GetSecurityLevel` and `GetVisibleSecurityState` of the tab, folded as the
    header says (`SECURE` secure; `DANGEROUS` with a Safe Browsing status flagged, with a certificate error
    certificate error; `NONE`/`WARNING` on https with mixed content not fully secure, else not secure). `file:` is a
    local file; every scheme other than http and https is a page of the browser itself.
  - Host: `url_formatter::IDNToUnicode` (punycode when its spoof checks decline). Origin: `url::Origin::Serialize()`,
    the same string `sitesWithPermissions` uses, so the two can be matched.
  - Certificate of a secure page: subject common name, issuer organization (else common name), expiry.
  - Permissions: each kind's `HostContentSettingsMap::GetContentSetting` for the origin; default when the rule is
    the wildcard pair (as `PageInfo::PopulatePermissionInfo`); an embargoed Ask reads Block; options from the content
    settings registry's valid settings; titles from `PageInfoUI::PermissionTypeToUIString` (insecure content has no
    page info row, so it takes the site settings label `IDS_SITE_SETTINGS_TYPE_INSECURE_CONTENT`). Listed: location,
    camera, microphone and notifications always, then every other kind with an exception, an embargo, in use
    (`PageSpecificContentSettings::IsInUse`), or sound once the tab played audio, as page info lists them.
  - Site data: as `chrome://settings/content/siteDetails` totals it (`BrowsingDataModel::BuildFromDisk`, entries
    matching the origin, their storage bytes and first-party cookies). The model is per profile and reused for 10 s; a
    read of an older one starts a new count, keeps answering the old one meanwhile, and the tab hears
    `PageInfoChanged` when the new count differs from what it read. Before the first count the value is absent
    (`siteData` nil in Swift, "still counting").
- **Changes go through Chromium's own page info.** The first change from a tab to its own site opens a `PageInfo` for
  it (with `ChromePageInfoDelegate` and a page info UI that is never shown) and calls `OnSitePermissionChanged`: the
  narrowest pattern, embargo cleared, constraints, and the reload infobar bookkeeping (any kind but sound needs it).
  `pageInfoDidClose` calls `OnUIClosing`, which adds Chromium's `PageInfoInfoBarDelegate` to the tab once
  (`ArktInfobarKindReload`, already mapped since #400); the session ends there, so a second close adds nothing. A
  change to another site (Settings' per-site list, #133) writes the same setting directly and raises no infobar. The
  default setting removes the exception. Reset sets every kind with an exception or an embargo back to the default
  (the origin-scoped exceptions; a broader `[*.]host` user exception stays, as with Chromium's page info).
  `openSiteSettings` runs `ChromePageInfoDelegate::ShowSiteSettings` (siteDetails in a tab of the Arkt window).
- **Announcements.** Each profile's `HostContentSettingsMap` is observed once read. A change from one facade call is
  reported once per tab of the matching origin, after the call (a reset of 21 kinds is one event). A change made
  elsewhere (siteDetails, an extension) comes as one notification per kind; the tabs it touched are reported once,
  from a posted task. Tabs of other origins hear nothing. The connection's security state is reported when the
  folded connection changes (`DidChangeVisibleSecurityState`).
- **ChromiumEngine** (`ChromiumEngine+PageInfo.swift`): `siteSettings` is the engine; maps the values and the four
  calls, and `PageInfoChanged` to `.pageInfoChanged`. A permission kind this build does not know is left out.
  `ContractCheck.chromiumDeferredRules` is empty: `chromiumChecks` is rules 1 to 26, and the app runner prints no
  `DEFERRED` line.
- Self-test embedder: logs `pageInfoChanged`; commands `pageinfo`, `setperm <kind> allow|ask|block`, `resetperm`,
  `pageinfo-close`, `sitesettings` and `sites`.

### Tests first

`ChromiumPageInfoTests` (16 cases), the scripted facade's page info (`ScriptedPageInfo.swift`) and `PageInfoABITests`
(3) were written against the new header. Without `ChromiumEngine+PageInfo.swift` the test target does not compile
(`ChromiumEngine` has no `pageInfo(of:)`, no `siteSettings`): the red run. The mapping itself was written before the
tests, not after them (deviation). `ChromiumPageInfoDefaultsTests` (ChromiumEngine has no site settings, rule 26 not
applicable) is removed. Deliberate break: with ChromiumEngine's `hub.emit(.pageInfoChanged(id))` replaced by `break`,
three `ChromiumPageInfoTests` and four contract cases of rule 26 fail (8 issues); restored and green again.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` | 158 + 31 + 279 passed, 0 failed. ChromiumEngineKitTests: 16 new `ChromiumPageInfoTests` (one with 5 arguments), rule 26 in `contract(_:_:)` over both facade scripts (112 cases, was 106), 2 defaults tests removed. ArktEngineABITests: 3 new `PageInfoABITests` |
| Full suite (`swift test --skip ShellKitGUITests`) | not run locally (several lanes building on this Mac); CI's Swift tests job |

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 (first tries failed on a missing `switch` case in the self-test, `-Wunsafe-buffer-usage` on C array indexing and a refcounted bound argument; fixed) | 30 s for the last full step |
| `gn check out/Spike //arkt/api:embedder` | the 4 pre-existing errors only (`find_in_page` headers in the facade); none for the new file | |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try583 -jobs 2` (`nice -n 20`, `CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-583`) | `BUILD SUCCEEDED`, `Engine framework copied: Chromium Framework.framework 156.0.8078.48` | 522 component dylibs cloned next to the bundle (`cp -c`) |

Load average 3 to 6 while building and running (other lanes' work; nothing added).

### Self-test runs (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port=9333`, fresh profiles under `profiles/583-20261107/`, `--use-mock-keychain`, pages from a loopback server on `127.0.0.1:8583` that sets two cookies and 2 KB of local storage, commands through the page title over the DevTools protocol)

| Check | Result | Evidence |
|---|---|---|
| Read on `http://127.0.0.1:8583/a` | PASS | `origin=http://127.0.0.1:8583 host=127.0.0.1 connection=1` (not secure), location, camera, microphone, notifications at Ask, default, options Allow, Ask, Block; `siteData=counting`, then one `pageInfoChanged` with `2 cookies 2055 bytes` |
| Two changes (location Allow, camera Block) | PASS | read back at once (`setting=0 default=no`, `setting=2 default=no`), one `pageInfoChanged` per change on the tab; the `localhost:8583` tab of the same window hears nothing |
| No-ops | PASS | camera Block again, and Ask for pop-ups (not offered): nothing changes, no event |
| Per-site list | PASS | `sites count=1`: `http://127.0.0.1:8583` with location Allow and camera Block |
| Values against `chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A8583` (opened by `sitesettings`, a tab of the Arkt window; read with the page's own `getOriginPermissions` and `fetchUsageTotal`) | PASS, one difference | camera, microphone, notifications, pop-ups, sound and JavaScript as changed or default agree, each `preference` where page info says not default and `default` where it says default; usage `2,055 B`, `2 cookies` = page info's count. Location: siteDetails `ask (preference)`, page info Allow. siteDetails asks the permission controller, and `GeolocationPermissionContextSystem` turns an Allow into Ask while macOS has not decided location access for the app (`kNotDetermined`, the test build never asked); page info, Chromium's bubble included, shows the stored setting. See "Needs the maintainer" |
| Reload infobar | PASS | close with no change: nothing. Location Allow and notifications Block, then close: `infobarsChanged count=1`, the tab's page 600 -> 560 high; a second close: nothing. Sound Block on the other tab, then close: no infobar (Chromium needs no reload for sound) |
| Changes made in siteDetails | PASS | one kind (`setOriginPermissions` for the microphone): one `pageInfoChanged` on the site's tab; every kind reset from there (22 notifications): one `pageInfoChanged`; the other site's tab: nothing |
| Reset from the facade | PASS | after 21 kinds were blocked: one `pageInfoChanged`, the four common kinds at their default, `sites count=0` |
| Local file, internal page, certificate error | PASS | `file://.../Local%20Notes.html`: `origin=file:// host=Local Notes.html connection=5`, no permissions, no site data; `chrome://version/`: `connection=6`, no permissions; `https://127.0.0.1:8584/` with a self-signed certificate (the interstitial): `connection=3` (certificate error) |

`FATAL`, `NOTREACHED`, `Check failed` lines: 0 in the final runs. Earlier runs found two things: the first version asked
`PageInfoUI::PermissionTypeToUIString` for insecure content, which page info has no row for (`NOTREACHED`, fixed with
the site settings label); and one run was ended by the smoke itself, which passed siteDetails a type name it does not
know (`geolocation` for `location`, a `CHECK` in the settings handler, not in the facade). A command sent while the
first navigation had not committed yet read no page info (`GetLastCommittedURL` empty), as it should; the runs wait
for the commit first.

### In-app contract (`dev.arkt.Arkt.try583`, Engine app on `out/Spike`, `--arkt-engine-contract --arkt-engine-test-api`, tabs probe, throwaway profile, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`)

| Check | Result |
|---|---|
| Rule 26 `pageInfoNamesTheSiteItShows` (`127.0.0.1` and `localhost` pages) | PASS (109 ms) |
| Rule 26 `permissionChangeIsReadBackAndResetRestoresTheDefault` | PASS (116 ms) |
| Rule 26 `permissionChangeRaisesTheReloadInfobarOnce` | PASS (147 ms) |
| Rule 25 (3 checks) | PASS (92, 599, 3750 ms) |
| Result | `22/26`, exit 1: rules 19, 20, 21 and 24 are NOT-APPLICABLE as before (no `raiseDialog`, `raisePermission`, `raiseInfobar` or `downloads` driver in the runner); every other rule PASS; no `DEFERRED` line; 0 `FATAL` |

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 12 |
| `arkt` commits above `156.0.8078.48` | 12 |

In sync, and the 12 commits export to the committed patch files unchanged; nothing exported. Facade header copies
`cmp` identical.

### Left open

- Location while macOS has not decided location access: page info shows the stored setting, siteDetails the effective
  one (maintainer question in the pull request).
- Site data is counted from the whole profile's `BrowsingDataModel`, at most once per 10 s, when the pill or the
  panel reads page info; an open signal from the shell would let the engine count only for an open panel.
- A host-scoped exception (a `[*.]host` pattern) lists under `http://host` in `sitesWithPermissions`, the origin its
  pattern stands for; exceptions this facade writes are origin-scoped.

### Cleanup

Every Chromium and app run stopped by exact PID or exited on its own (the contract runner exits; two self-test runs
crashed as described above); `ps -p` prints nothing for any of them. The loopback and TLS servers stopped by PID.
Deleted: the throwaway profiles under `profiles/583-20261107/` (with the crash reports the two crashed runs wrote), the
`embed-583` folder, the build logs and the run's defaults suite. Nothing under `~/Applications/ArktTest` or
`/Applications/Arkt.app` was touched.

### #583 review fixes (PR #778)

- **A page info session ends with its page.** `Session` now also ends on `PrimaryPageChanged` (a committed
  cross-document navigation of the primary main frame: reload, link, back and forward, an activation), without
  `OnUIClosing`, so closing the panel after a change and a navigation adds no reload infobar. The scripted facade ends
  its pending reload when a new page commits; `ChromiumPageInfoTests.aNewPageEndsThePanelsChangesSoACloseRaisesNoInfobar`
  covers it. Deliberate breaks: without the scripted end the test fails; with the facade's `PrimaryPageChanged` body
  emptied, the self-test's change, `reload`, `pageinfo-close` adds `infobarsChanged count=1`. Restored: nothing.
- **The connection is seeded when the tab is bound** (`TabObserver::Seed`), so the first security state change that
  differs is reported (the first commit after the initial empty document is one: `pageInfoChanged connection=1` right
  after the load starts). Scripted case `theConnectionIsSeededWhenTheTabIsBound`; with the scripted seed removed it
  fails.
- Comments: `ArktPageConnection` (both header copies) and `PageConnection` now say what the code does (`DANGEROUS`
  with neither a Safe Browsing verdict nor a certificate error is not secure; `ran_mixed_content` counts);
  `hasSiteData` says the old count is reported while a recount runs; reset says it removes origin-scoped exceptions
  only. `cmp` identical.
- `TabStateTests.defaultsKeepAnEngineWithoutTabStateUnchanged` checks that an engine without page info has no
  `siteSettings`.
- `engine/REBASE.md`, section 5: a check of `kApproximateGeolocationPermission` (`GEOLOCATION` vs
  `GEOLOCATION_WITH_OPTIONS`) and of the page info string table for every listed kind.
- `origin/main` merged (`ced72fd`, no conflicts).

| Check | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` (`nice -n 20`, `-j 2`) | 160 + 31 + 279 passed, 0 failed (2 new `ChromiumPageInfoTests`; the `siteSettings` default check is in an existing test) |
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | finished successfully, `FAILED:` 0 |
| Self-test, fresh profiles: location Allow, `reload`, close; then notifications Block, close | no infobar after the reload; `infobarsChanged count=1` after the second close; 0 `FATAL` |
| Engine app and in-app contract (`dev.arkt.Arkt.try583`, throwaway profile, `--use-mock-keychain`) | `BUILD SUCCEEDED`; rule 26 PASS (105, 108, 139 ms), rule 25 PASS, `22/26` with the same four NOT-APPLICABLE rules |
| `.patches` | 12 = 12, in sync |

Cleanup: every run stopped by PID or exited; the loopback server stopped by PID; the profiles, the `embed-583` folder,
the build logs and the defaults suite deleted.

## #721: uninstall an extension through the facade

Date 2026-11-07. Branch `engine/721-uninstall-extension` from `origin/main` (`03d6c58`). Engine side of #720 (the
remove sheet and `EngineExtensions.uninstallExtension`). Overlay and facade only: no patch.

### Gate

- Seam: `ExtensionRegistrar::UninstallExtension` with `UNINSTALL_REASON_USER_INITIATED`, the public call
  `ExtensionUninstallDialog` makes once its dialog is accepted, from a new overlay file pair
  `arkt/browser/arkt_extension_uninstall.{h,cc}`. The report page is `NavigateParams` with
  `extension_urls::GetWebstoreReportAbuseUrl` and `NEW_FOREGROUND_TAB`, as `ExtensionUninstallDialog::HandleReportAbuse`.
  No upstream file is touched; `arkt_extension_dialogs.mm` (the dialog hook) is unchanged.
- Facade header: additive only, both copies `cmp` identical. One required member on the engine,
  `uninstallExtension:reportAbuse:completion:` (`completion(BOOL uninstalled, NSString* failureReason)`); the Swift
  doubles (`ScriptedFacade`, the ABI `TestEngine`) grew it. No new event kind: the removal is the existing
  `ExtensionActionsChanged`.
- `.patches`: unchanged (12). New dep of `//arkt/browser:window`: `//chrome/browser/ui/navigator`.
- Build: `nice -n 20 autoninja -C out/Spike chrome -j 4`; 1.9 TB free on the Chromium disk, 36 GB on `/`, swap 2.9 GB
  used.

### What landed

- **`arkt::UninstallExtensionForUser`.** An id the registry does not have (`GetInstalledExtension`, enabled or not)
  fails with "unknown extension" before the registrar is called (it `CHECK`s on an unknown id). A refusal of the
  management policy (policy-installed, component, `MustRemainInstalled`) fails with "not removable"; the policy's
  error names the extension, so it is neither returned nor logged. Neither changes anything.
- **Report abuse.** After a successful uninstall, so the report page is the active tab even when the extension set an
  uninstall URL. Only for an extension whose update URL is the Web Store's (`ExtensionManagement::UpdatesFromWebstore`,
  read before the uninstall), the condition for Chrome's own checkbox; otherwise no tab opens and a line is logged. The
  navigation names only the profile, as Chrome's does, so the tab lands in the last active window: the one the
  shell's sheet hangs from. The shell's call carries no window to name instead.
- **Facade.** `uninstallExtension:reportAbuse:completion:` runs through `RunOrDefer` like the other mutators and
  posts the completion, so it never runs inside the call.
- **ChromiumEngine** (`ChromiumEngine+Uninstall.swift`): `uninstallExtension(_:reportAbuse:)` calls the facade once;
  a refusal is logged (`dev.arkt.shell`, `ChromiumExtensions`), as the shell's call has no answer. The action leaves
  through the window's `.extensionActionsChanged`, which ChromiumEngine already maps.
- Self-test embedder: command `uninstall <id> [abuse]`, which logs the answer and whether it came inside the call.

### Tests first

`ChromiumExtensionUninstallTests` (3 tests, 5 cases) and `ConformanceTests.uninstallReachesTheFacadeWithItsFlagAndAnswers`
were written against the new header and the scripted facade's `uninstallExtension` before ChromiumEngine had the
method. Red run: ChromiumEngine fell back to `EngineExtensions`' default no-op, and all 5 cases failed (15 issues:
the facade saw no call, the action stayed, no event). With `ChromiumEngine+Uninstall.swift` all pass.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` | 163 + 32 + 279 passed, 0 failed (baseline 160 + 31 + 279): 3 new `ChromiumExtensionUninstallTests` (5 cases), 1 new ABI test |
| Full suite (`swift test --skip ShellKitGUITests`) | not run locally (several lanes building on this Mac); CI's Swift tests job |

### Build

| Step | Result |
|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 |
| `gn check out/Spike //arkt/browser:window` | 1 error, pre-existing (`arkt_extension_batch_install.mm:29`, `webstore_installer`); none for the new files |
| `gn check out/Spike //arkt/api:embedder` | the 4 pre-existing errors only |

Load average 2.5 to 3.5 while building and running (other lanes' work; nothing added).

### Self-test runs (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port=9333`, fresh profiles `profiles/721-20261107/run1` and `run2`, `--use-mock-keychain`, unpacked copies of the action probe loaded with `--load-extension` (one with the Web Store's `update_url`), commands through the page title over the DevTools protocol)

| Check | Result | Evidence |
|---|---|---|
| Unknown id (`aaaa...`, with abuse) | PASS | `answered failed reason=unknown extension insideCall=no`; no event, 1 page |
| Component extensions (`mhjfbmdgcfjbbpaeojofohoefgiehjai` PDF viewer, `glbjnfimcajjenihimblfaponejbkoph`, with abuse) | PASS | `uninstall refused by the management policy`, `answered failed reason=not removable insideCall=no`; the listing still has its 3 actions, no tab |
| Plain unpacked extension, with abuse | PASS | `uninstalled`, one `ExtensionActionsChanged`, the listing drops to 2, `report page skipped: the extension does not update from the Web Store`, no tab; its `extensions.settings` entry is empty after quit |
| Web Store extension, with abuse, two windows (window 2 opened last by `chrome.windows.create`; the command sent from window 1's tab) | PASS | `ExtensionActionsChanged` for both windows, both listings drop the action, ONE `tabCreated` in window 2 with `https://chromewebstore.google.com/detail/<id>/report?utm_source=chrome-remove-extension-dialog`, active |
| Web Store extension, abuse off (run2) | PASS | `uninstalled`, listing drops it, no tab |
| Web Store extension, with abuse, one window (run2) | PASS | one report tab in that window; the run created 2 tabs in all (the first page and the report) |
| No Chromium dialog on the facade path | PASS | `dialog sheet shown`: 0 in run2, and in run1 only the one below |
| Other uninstall paths keep their dialog: `chrome.management.uninstallSelf({showConfirmDialog: true})` from the probe's page (user gesture) | PASS | `ARKT: dialog sheet shown ExtensionUninstallDialog` (patch 0007's native sheet); the extension stays installed until it is answered |

`FATAL`, `NOTREACHED`, `Check failed` lines: 0 in both runs.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 12 |
| `arkt` commits above `156.0.8078.48` | 12 |

In sync, and the 12 commits export to the committed patch files unchanged; nothing exported. Facade header copies
`cmp` identical.

### Left open

- The shell's Remove from Arkt... end to end in an Engine app build (criterion 4) was not run: it needs clicks in the
  shell's window, and this lane sends no synthetic input it cannot check against the frontmost app. The facade path
  under it is covered by the self-test runs; the sheet by #720's GUI tests.
- Pins and commands: ChromiumEngine has no engine-backed `pinnedExtensionIDs` or `extensionCommands` yet (the facade
  has no surface for them), so an uninstall emits no `.commandsChanged` and only the action's removal is verified.
- Report abuse for an extension that does not update from the Web Store opens nothing, while the shell's sheet shows
  the checkbox for every extension (maintainer question in the pull request).
- The report tab goes to the last active window; the shell's call names no window.

### Cleanup

Both Chromium runs stopped by exact PID (`ps -p` prints nothing). Deleted: the throwaway profiles under
`profiles/721-20261107/` and the build log. The fixtures and run logs lived in a temporary folder outside the repo.
Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

### #721 review fixes (PR #792)

Same branch, `origin/main` merged (`d3a9120`, no conflicts). Still no patch; `.patches` 12, in sync.

- **What the user may do is listed.** `ArktExtensionAction` gains `canUninstall` (the management policy's
  `UserMayModifySettings` and not `MustRemainInstalled`, no error text) and `canReportAbuse`
  (`ExtensionManagement::UpdatesFromWebstore`), both copies `cmp` identical. One helper
  (`arkt::GetUninstallAbility`) answers the listing and the uninstall gate, so they cannot drift; the gate stays as the
  safety net. `ExtensionAction` mirrors both (default true, so FakeEngine, which has no extensions, and existing
  callers keep their behaviour); InMemoryEngine refuses an action whose `canUninstall` is false. The shell leaves
  Remove from Arkt... out of the context menu and does not open the sheet when `canUninstall` is false, and builds
  the sheet without the Report abuse checkbox when `canReportAbuse` is false.
- **The window is named.** The facade method is now `uninstallExtension:reportAbuse:inBrowser:completion:` (nullable
  browser), and `EngineExtensions` gains `uninstallExtension(_:reportAbuse:in:)`, whose default forwards to the call
  without a window. The panel passes its engine window; ChromiumEngine maps it to the browser handle. The report
  page uses `NavigateParams(browser, url, ...)`; a nil browser, one of another profile, or one closed during a
  deferral falls back to the last active window. The window is not brought forward, as with Chrome's dialog.
- Header: the completion "always arrives except when the engine shuts down first".
- `TestEngine` (ABI conformance) posts its completion; its test waits for it and checks it did not run inside the
  call. `ScriptedFacade` documents its "unknown extension" model (a window lists the action; the real facade asks the
  profile's registry).
- **Rule 27** (`uninstallRemovesTheExtensionFromEveryWindow`, `ContractCheck` 57 checks, rules 1 to 27): two windows
  list a removable extension (driver `removableExtension`); an unknown id changes nothing; the uninstall from the
  first window takes the action out of both, announced on each, and opens no tab. InMemoryEngine, the scripted facade
  and the app's runner (which now also loads `engine/test-extensions/action-probe`, uninstalled by the rule) provide
  the driver.

#### Tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "ChromiumEngineKitTests\|ArktEngineABITests\|EngineAPITests"` | 168 + 33 + 285 passed, 0 failed (was 163 + 32 + 279): ChromiumExtensionUninstallTests 8 tests (flags, window, closed window, no report page), ABI flag test, InMemoryEngine window, refusal and default-forwarding tests, rule 27 on InMemoryEngine and over both facade scripts |
| `swift test --filter "ExtensionRemoveSheetTests\|ExtensionContextMenu"` | 15 passed (3 new: Remove left out, sheet not opened, no checkbox); existing checks now include the sheet's window |
| `swift test --filter ExtensionsPanelTests` | 36 passed |

Deliberate breaks, each restored and green again:

| Break | Fails |
|---|---|
| `ExtensionContextMenu`'s filter returns `true` | `testRemoveFromArktIsLeftOutForAnExtensionTheUserMayNotRemove` |
| `FacadeValues.swift` maps `canUninstall: true` | `theListingCarriesWhatTheUserMayDo` (2 of 4 cases) |
| InMemoryEngine records `window: nil` | 3 `ExtensionRemoveSheetTests` (the window the sheet names) |

#### Build

| Step | Result |
|---|---|
| `nice -n 20 autoninja -C out/Spike chrome -j 4` | finished successfully, `FAILED:` 0 |
| `gn check` (`//arkt/browser:window`, `//arkt/api:embedder`) | the pre-existing errors only |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try721 -jobs 2` (`nice -n 20`, `CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-721`, component dylibs cloned next to it) | `BUILD SUCCEEDED`, `Engine framework copied: Chromium Framework.framework 156.0.8078.48` |

#### Self-test run 3 (`out/Spike`, fresh profile `profiles/721-20261107/run3`, `--use-mock-keychain`, four unpacked probes: one plain, three with the Web Store `update_url`, one of them calling `chrome.runtime.setUninstallURL("http://127.0.0.1:8721/bye")`)

| Check | Result |
|---|---|
| Listing flags | plain `canUninstall=1 canReportAbuse=0`; the three store copies `1 1` |
| Two windows, window 2 last active (`chrome.windows.create`), uninstall with Report abuse naming window 1 | `report page in the given window`; ONE report tab in window 1, active; nothing in window 2 |
| Extension with an uninstall URL, Report abuse, naming window 1 | the uninstall URL tab opens first in the last active window (window 2; Chromium's `RuntimeAPI`, user-initiated reason), then the report tab in window 1, active |
| No window named (`nowin`) | the report tab goes to the last active window (window 2) |
| Plain extension, Report abuse | uninstalled, `report page skipped`, no tab |
| Unknown id; component extension (PDF viewer) | `unknown extension`; `uninstall refused: the user may not remove it`, `not removable` (the new gate, before the registrar) |

6 tabs in all (the first page, window 2's, three report pages, the uninstall URL); 0 `FATAL`, `NOTREACHED` or
`Check failed`; 0 `dialog sheet shown`.

#### In-app contract (`dev.arkt.Arkt.try721`, Engine app on `out/Spike`, `--arkt-engine-contract --arkt-engine-test-api`, tabs probe and action probe, throwaway profile, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`)

| Check | Result |
|---|---|
| Rule 27 `uninstallRemovesTheExtensionFromEveryWindow` | PASS (167 ms): `ChromiumEngine.uninstallExtension(_:reportAbuse:in:)` through EngineAPI, no clicks |
| Rules 25, 26 | PASS |
| Result | `23/27`, exit 1: rules 19, 20, 21 and 24 NOT-APPLICABLE as before; 40 checks PASS, 0 FAIL; no `DEFERRED` line; 0 `FATAL` |

#### Gaps recorded

- **Forced-install policy.** Not reproduced: `ExtensionManagement` loads `ExtensionInstallForcelist` only from a
  managed preference (`LoadPreference(..., force_managed = true)` needs `pref->IsManaged()`), which on macOS needs MDM
  or root-owned managed preferences; a user-level `defaults` value is only recommended, and the command-line policy
  provider exists only on Android. The refusal path is the same gate (`UserMayModifySettings`), shown with a component
  extension. No extension with a toolbar action and `canUninstall` false exists in a test profile, so the false flag
  is covered by the Swift tests only.
- **Criterion 4 in a Chromium build.** ChromiumEngine has no `extensionContextMenu` yet, so the shell's context menu,
  and with it Remove from Arkt..., does not exist in a Chromium build. The click path is covered by
  `ExtensionRemoveSheetTests` against InMemoryEngine and the engine side by rule 27 in the app; the end-to-end click
  waits for the Chromium context menu (the engine side of #596).
- **Pins and commands** (criterion 1) moved to #591 as the acceptance check "uninstall leaves no pin and no command".

#### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 12 |
| `arkt` commits above `156.0.8078.48` | 12 |

#### Cleanup

Run 3 stopped by exact PID; the contract run exited on its own (`ps` shows no `embed-721` process). Deleted: the
profiles under `profiles/721-20261107/`, the `embed-721` folder, the derived data folder `arkt-shell-dd/721`, the
build logs and the run's defaults suite.

## E1: crash guards (patches 0013 and 0014)

Date 2026-11-07. Branch `engine/e1-crash-guards` from `origin/main` (`e7bccbf`). Batch E1 of the engine connector
design (`docs/plans/2026-11-07-engine-connector-design.md`, PR #795, sections 2.3 and 3 "E1. Crash guards"). No issue
yet; the batch issue list waits for the maintainer. Guards and one generalization only, no hook: the hooks question
(design section 1.2) is still open.

### Gate

- Why patches: the five crash sites dereference `BrowserView::GetBrowserViewForBrowser`, which is always nullptr on
  an Arkt window; no overlay seam reaches inside them. The toast site `CHECK`s that only tests lack an anchor.
- Facade header: unchanged (`cmp` identical). `.patches`: 12 to 14; no open engine pull request touches it.
- Overlay link checked before every build: `$CR/arkt` points at this worktree's `engine/arkt`; branch `arkt` in
  sync with `.patches` before the work (12 = 12).
- Build: `nice -n 15 autoninja -j 4 -C out/Spike chrome`; Chromium disk 1.9 TB free, internal 36 GB, swap 2.9 of
  4 GB. Load average 2 to 6 (other lanes' work; nothing added).

### What landed

Two patch files, one per theme (design section 2.3), 4 upstream files, 59 insertions, 9 deletions (after the review
fixes below):

| Patch | Site | Change |
|---|---|---|
| 0013 guards | `ui/views/storage/storage_pressure_bubble_view.cc` (row 1) | `ShowBubble` returns when the last active window has no `BrowserView` (4 lines) |
| 0013 | `ui/browser_actions.cc` Cut, Copy, Paste (rows 3-5) | without a `BrowserView`, the action calls the active tab's `WebContents::Cut/Copy/Paste` (3 hunks, 8 lines each) |
| 0013 | `ui/toasts/toast_controller.cc` `CreateToast` (row T) | no anchor and a `BrowserElementsViews` with no primary window widget (an embedder's window): the toast is dropped as if its widget closed at once, in `OnWidgetDestroyed`'s order (timer stopped, close callback run, widget-destroyed subscribers notified, current id cleared) instead of `CHECK_IS_TEST()`. Webium keeps its path, and so do unit tests with no browser (the `ToastController` unit tests). Tests that do have a `BrowserElementsViews` but no widget (a `TestBrowserWindow`) now take the drop path too |
| 0014 generalization | `ui/browser_commands.cc` `CloseTab` (row 2) | the Close Tab accelerator comes from `BrowserWindow::FromBrowser(browser)->GetAcceleratorProvider()`; no provider or no `IDC_CLOSE_TAB` shortcut: close without the confirmation toast; a toast the window could not show: close too. `kClosePinnedTab` is actionable, so in Chrome a toast is always showing or queued after `MaybeShowToast` and the last branch never runs there |

- `GetAnchorView` needed no guard: `BrowserElementsViewsImpl` exists for every window (`browser_window_features.cc:357`)
  and returns no view on an Arkt window, so the crash was in `CreateToast` (`toast_controller.cc:327`), not where the
  design expected (`:442-452`).
- Why the toast state is cleared: the first version only skipped the `CHECK`. `ShowToast` sets the current toast id
  before `CreateToast`, and only the widget's destruction clears it, so after one dropped toast every later toast was
  queued forever, and a pinned tab could never be closed with `IDC_CLOSE_TAB` (run `after-a` v1: two Copy URL toasts,
  then close-tab twice, tab still open).
- Cut, Copy and Paste on an Arkt window behave like Chrome on Windows and Linux, not like Chrome on Mac: they act on
  the page (`WebContents::Cut/Copy/Paste` on the focused frame), not on the focused native view through
  `NSApp`. Today nothing in the app sends these commands (the shell's Edit menu uses `cut:`, `copy:` and `paste:`
  through the responder chain). If E2 routes these commands to the engine, the guard should forward them to `NSApp`
  as `BrowserView::CutCopyPaste` does on Mac.
- The other `CHECK_DEREF(BrowserView::GetBrowserViewForBrowser(bwi))` sites in `browser_actions.cc` are unreachable on
  an Arkt window. Each action is invoked only from a Views page action icon, the Views toolbar or the WebUI toolbar,
  never from a browser command, and an Arkt window has none of those:
  - `:812` `kActionShowJsOptimizationsIcon`: the JS optimizations page action icon.
  - `:1485` `kActionShowCookieControls`: the cookie controls page action icon (location bar).
  - `:2014` `kActionShowCollaborationRecentActivity`: the collaboration messaging page action icon.
  - `:2152` `kActionPinActionToToolbar` and `:2176` `kActionUnpinActionFromToolbar`: the pinned toolbar button's
    context menu (`pinned_action_toolbar_button_menu_model.cc`).
- Overlay: `ArktAcceleratorProvider` (`arkt_browser_window_parts`), returned by `ArktBrowserWindow::GetAcceleratorProvider`
  (was an `ARKT_STUB`). It reads the main menu: the first `commandDispatch:` item tagged with the command id that has
  a key equivalent (the shell's page commands, `MainMenu.swift`). The app's Cmd-W is Archive Tab, so the app has no
  `IDC_CLOSE_TAB` accelerator and a pinned tab closes without a toast.
- Overlay comment: `arkt_browser_window.h` now names the three browser types Arkt takes (design section 2.1).
- Self-test (test-only): `arkt-selftest chrome-command copy-url|close-tab|cut|copy|paste|pin` sends the Chromium
  command through the host's `executeCommand`, as a menu item would.

### Gated sites (design section 2.3, "The 15 gated dereferences")

No patch. Checked against the pinned source with a fresh profile, no sign-in and no policy:

| Site | Switch | Evidence |
|---|---|---|
| WebAuthn ambient sign-in (`ambient_signin_controller.cc:120`) | `--disable-features=WebAuthenticationAmbientSignin` (shell launch list) | already `FEATURE_DISABLED_BY_DEFAULT` (`device/fido/public/features.cc:92-94`); the switch also wins over `--enable-experimental-web-platform-features` |
| Media remoting dialog (`media_remoting_dialog_view.cc:49`) | `--disable-features=MediaRouter` (shell launch list) | reached while casting a tab; `kMediaRouter` is enabled by default. The remoting pref cannot be set by a default value (`cast_remoting_connector.cc:447-452`). This turns Cast off until E2 draws its device list (#653) |
| glic (`browser_conditions.cc:191`, `glic_metrics.cc:1003`, `context_sharing_border_view.cc:109`) | `--disable-features=Glic` (shell launch list) | `kGlic` is enabled by default on Mac; glic stays inert without a capable signed-in account, the switch removes it |
| iOS promos (`ios_promo_controller.cc:125`, `ios_promos_utils.cc:172`) | local-state default `browser.promotions_enabled` = false (`PreProfileInit`, next to the quit confirmation default; the PromotionsEnabled policy still wins) | needs active sync otherwise. See the next row for what else the pref turns off |
| `browser.promotions_enabled` = false, side effects | the same default | it acts as the PromotionsEnabled policy. It also skips Chromium's profile first-run and the sign-in intercept first-run dialog (`IsFirstRunDisabledByPolicy`, `profile_picker.cc:51-55`), the avatar promos, the startup infobar promos, the app menu promos and the extensions zero-state promo. Arkt shows none of those surfaces: it has its own onboarding and no avatar, toolbar or app menu |
| Lens region search (`lens_region_search_controller.cc:40`) | none needed | not compiled: `ENABLE_LENS_DESKTOP_GOOGLE_BRANDED_FEATURES` is 0 in an unbranded build |
| Relaunch notification (`relaunch_recommended_bubble_view.cc:47`) | none needed | `browser.relaunch_notification` defaults to 0, which never shows the bubble |
| Idle timeout (`idle_bubble.cc:67`) | none needed | `idle_timeout` defaults to zero: no polling |
| DICE interception (`dice_web_signin_interception_bubble_view.cc:504`) | none needed | the support check returns false without a `BrowserView` and the interceptor aborts before the bubble |
| Batch upload (`batch_upload_service.cc:382`) | none needed | needs a signed-in primary account |
| Web app update review (`web_app_update_review_dialog.cc:143`, `:148`, `:262`) | none needed on Arkt windows | only app windows (`TYPE_APP`) reach it, and those stay Views windows with a `BrowserView` |
| HaTS | none needed | Arkt overrides `ShowHatsDialog` (design) |

The three feature names join `DestroyProfileOnBrowserClose` in `EngineLaunchArguments.requiredDisabledFeatures`,
so every engine launch from the shell carries them; a caller's own `--disable-features` list is extended.

### Tests first

`EngineLaunchArgumentsTests` (ChromiumEngineKitTests): the expected list gained the three names, and two tests were
added (`keepsFeaturesWithoutNativeUIOff`, `addsOnlyTheFeaturesACallerDidNotName`). Before the change:
`nice -n 20 swift test -j 2 --filter EngineLaunchArgumentsTests` failed with 7 issues; after: 9 tests in 1 suite
passed. The full suite is left to CI.

### Build

| Step | Result | Time |
|---|---|---|
| Before: `main` plus the self-test command, no new patch | `The build has finished successfully.`, `FAILED:` 0 (one earlier attempt failed on `-Wexit-time-destructors` in the self-test command, fixed) | 35 s |
| Patches 0013 and 0014 (first toast guard) and the overlay | finished, `FAILED:` 0 | 50 s |
| Toast state cleared, CloseTab falls back when no toast shows | finished, `FAILED:` 0 | 40 s |
| Break 1: 0013's three files back to 0012 (working tree only) | finished, `FAILED:` 0 | 43 s |
| Break 2: 0013 restored, `browser_commands.cc` back to 0013 | finished, `FAILED:` 0 | 42 s |
| Restored, promotions default added | finished, `FAILED:` 0; `git status` clean in `$CR` | 41 s |

### Smoke (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port=9333`, fresh profiles under `profiles/e1-20261107/`, `--use-mock-keychain`, a page with two text fields on `127.0.0.1:8791`, commands through the page title over the DevTools protocol; Chromium's main menu unless `--arkt-menu-probe` is named)

Every run starts with `ARKT: browsers normal=1 arkt=1 views=0`.

| Run | Check | Result |
|---|---|---|
| before | `chrome-command copy-url` (Copy URL toast) | `FATAL toast_controller.cc:327 Check failed: base::internal::get_is_test_impl()`, stack `CreateToast` < `ShowToast` < `MaybeShowToast` < `chrome::CopyURL` |
| before | Clear Browsing Data from `chrome://settings` (`clearBrowsingData` message) | no crash, no toast: `kClearBrowsingDataToast` is disabled by default |
| before | storage pressure (`chrome://quota-internals`, Simulate) | `Received signal 11 SEGV_ACCERR`; crash report top frames `BrowserView::toolbar_button_provider()` < `StoragePressureBubbleView::ShowBubble` |
| before | `pin`, then `close-tab` | `FATAL browser_commands.cc:1516 Check failed: browser_view.` |
| before | `cut`, `copy`, `paste` (one launch each, text selected in a field) | `FATAL browser_actions.cc:2270`, `:2288`, `:2306 Check failed: *BrowserView::GetBrowserViewForBrowser(bwi).` |
| after-a | `copy-url` twice | no crash; the clipboard holds the page URL |
| after-a | `copy`, `paste`, `cut`, twice each | clipboard `alpha`, second field `alpha`, clipboard `beta` and the first field `alpha `: the commands act on the focused field |
| after-a | storage pressure twice | no crash (the second is inside the throttling interval) |
| after-a | `pin`, then `close-tab` once (after two dropped toasts) | `facade tab closed ... reason page`, `native window destroyed`: closed on the first command, no crash |
| after-b (`--arkt-menu-probe`: Cmd-W is Archive Tab, no `IDC_CLOSE_TAB` item) | `copy-url`, `pin`, `close-tab` | closed on the first command, no crash |
| after-final (with `--disable-features=DestroyProfileOnBrowserClose,WebAuthenticationAmbientSignin,MediaRouter,Glic`, as the shell launches) | every check of after-a once, then pin and close | the same results, 0 `FATAL`, `Check failed`, `NOTREACHED` or `Received signal` lines |
| break 1, Chromium menu | `pin`, `close-tab` | `Check failed: base::internal::get_is_test_impl()`: the provider found Cmd-W in Chromium's menu and the toast path ran |
| break 1, probe menu | `pin`, `close-tab` | closed, no crash: the provider found no `IDC_CLOSE_TAB` item and the tab closed before the toast |
| break 1 | `copy-url`; `cut`; `copy`; `paste`; storage pressure (one launch each) | the before crashes again: `toast_controller.cc` `CHECK_IS_TEST`; `browser_actions.cc` `CHECK_DEREF` for each; `SEGV_ACCERR` |
| break 2, both menus | `pin`, `close-tab` | `Check failed: browser_view.` |

`after-a` v1 (the first toast guard, which only skipped the `CHECK`) is the run that found the stuck toast id: two
Copy URL toasts, then `close-tab` twice, and the pinned tab stayed open with no crash.

Not checked directly: that the three disabled features and the promotions default are off at run time
(`chrome://local-state` lists only changed values, and the debug pages are disabled); they rest on the switch
reaching the command line and on the code paths in the table above.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 14 |
| `arkt` commits above `156.0.8078.48` | 14 |

In sync. Export added 0013 and 0014 and changed only `.patches` otherwise (0001 to 0012 byte-identical). Facade header
copies `cmp` identical.

| Gate (design section 2.5) | Before | After E1 |
|---|---|---|
| Patch files | 12 | 14 |
| Upstream files outside 0001-0004 | 15 | 19 |
| Seam patch files | 4 | 6 |
| Hunks in `browser_actions.cc` and `browser_commands.cc` | 0 | 4 (3 and 1; the proposed cap) |
| Hot-file hunks (`browser_window_features.cc`, `tab_features.cc`) | 0 | 0 |
| Widely included headers changed | 0 | 0 |

### Left open

- **Low-disk notice.** Patch 0013 only stops the crash; nothing tells the user. The overlay disk watcher needs a
  facade event (an additive header change both lanes agree to in an issue) and a native notice designed first
  (`arkt-design-first`). Follow-up, with the E1 issue.
- **Toasts are dropped, not shown.** Routing them to the shell is a hook in `ToastController` and waits for the hooks
  answer (design section 2.4).
- **0004's subject** still says "normal windows" (design section 2.1); rewording it rewrites the `arkt` history under
  eight later commits, so it waits for the next rebase.
- **Cast is off** with `MediaRouter` until E2 draws the device list (#653). The alternative from design section 2.3
  (a guard of about 5 lines for a site no switch can stop): guard `media_remoting_dialog_view.cc:49` in 0013, one more
  upstream file, and leave Cast on. For the maintainer to choose.
- **Upstream unit tests** that have a `BrowserElementsViews` but no widget (a `TestBrowserWindow`) and a real
  `CreateToast` now take the drop path instead of a toast that stays current; none were run (they are not part of
  `arkt_patch_unittests`).
- **MediaRouter** stays disabled (agreed in review); E2 removes it from `requiredDisabledFeatures` once #653's native
  device picker lands.

### Cleanup

Every Chromium run stopped by exact PID or exited when it crashed or closed its last tab (`ps -p` prints nothing for
each); the loopback server stopped by PID. Deleted: the throwaway profiles under `profiles/e1-20261107/`, the build
logs, and the crash reports the crashing runs wrote. The runs wrote to the system clipboard (it held no text before);
it was cleared afterwards. Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

### #800 review fixes

- 0013, toast drop path: `on_widget_destroyed_callbacks_.Notify(*currently_showing_toast_id_)` now runs between the
  close callback and clearing the id, in `OnWidgetDestroyed`'s order. Without it, subscribers such as
  `ManagePasswordsAutoSigninToastDelegate` never hear that the toast is gone, and the tab stays in `AUTO_SIGNIN_STATE`
  instead of moving to `MANAGE_STATE`.
- 0014, `CloseTab`: `BrowserWindow::FromBrowser` is null-checked; with no window the tab closes without the toast.
- Results: Cut, Copy and Paste semantics, the remaining `CHECK_DEREF` sites, row T for unit tests with a
  `BrowserElementsViews` but no widget, and the side effects of `promotions_enabled` (above).
- Build: `nice -n 15 autoninja -j 4 -C out/Spike chrome`, `FAILED:` 0, 40 s; the overlay link was checked first.
- Re-smoke (`out/Spike`, fresh profiles under `profiles/e1r-20261107/`, the shell's `--disable-features` list,
  `--use-mock-keychain`): Copy URL three times, then pin and close-tab, once with Chromium's menu and once with
  `--arkt-menu-probe`. Both runs: 3 of 3 Copy URL commands completed, the pinned tab closed on the first command,
  `native window destroyed`, 0 `FATAL`, `Check failed`, `NOTREACHED` or `Received signal` lines. The notification
  itself was not observed: auto sign-in needs a saved credential with auto sign-in on, so `MANAGE_STATE` holds by
  construction.
- Export: `.patches` 14 lines, 14 `arkt` commits, in sync; 0001 to 0012 byte-identical; only 0013 and 0014 changed.
- Cleanup: both runs and the loopback server stopped by exact PID; profiles and build log deleted; no crash report.
  The clipboard held text this time and the run replaced it with the page URL; it was cleared afterwards and the
  earlier text was not restored.

### Restore pages Swift boundary (#580)

The Swift recovery contract carries only non-private Little Arkt and Peek page titles, URLs and kinds, and supplies the list to the shell, which requests reopening outside the sidebar. The shell presents the offer after its own window
session restoration; an empty offer acknowledges the crash and shows the status notice. The crashed-session state seam shipped in #577; recoverable-page data integration and
feature-level killed-process validation remain unverified.

Test-first CI run 42112475936 at 75b3800 failed to compile the missing model in ShellKit tests (job 127543462923)
and GUI tests (job 127543462890); the Swift tests gate (job 127547434337) consequently failed. No tests executed in
those jobs. Local builds and tests were not run: the installed toolchain cannot compile the baseline. Syntax parsing
and diff checks are recorded in the pull request. GUI, accessibility, motion, app and real-engine validation remain
pending.

### Restore pages review fixes (#580)

The window set retains an unanswered decision across regular-window closure and presents it when another window is
available. The panel remains above the content in Split View. The shell requests the pages before acknowledging; an unavailable shell path retains the offer and crash. Crash-only providers expose no page capability. A persistent
database-recovery notice remains underneath the six-second crash notice and reappears after dismissal or expiry.

Regression coverage exercises the production window-set coordinator and window lifecycle, capability and unavailable shell paths,
Split View, and notice ordering. These additions have not run locally because the installed toolchain cannot compile the
baseline; syntax parsing alone does not validate behavior. Direct `AppSession.finishLaunch`, GUI, keyboard, accessibility,
motion and real-engine killed-process validation remain pending. The crashed-session state seam shipped in #577; recoverable-page data integration remains unverified.

### Restore pages privacy routing (#580)

Only ordinary regular windows may host the decision. The window set selects an eligible window even when the primary
window is private, retains the unanswered offer while only private windows exist, and classifies Blank and Incognito
windows before considering presentation. A host changing to private mode relinquishes the offer before that mode is
shown. Little Arkt and popup requests use separate hosts.

New GUI regressions cover both private modes, transfer with a private primary, deferred presentation after the last
regular host closes, private creation while an offer is pending, and a host changing mode. They were written before
the fix but not run locally: the installed toolchain cannot compile the baseline. CI must validate compilation and
behavior on the new head; syntax parsing and source checks do not establish test results.

### Maintainer feedback on restore pages (#580)

The provider supplies a list only; the shell reopens Little Arkt and Peek pages using the host's current tab for Peek.
A missing source or multiple Peek pages retain the offer: the current Peek controller replaces an existing Peek from
the same source, so multiple Peek recovery requires a further shell solution. Closing windows are ineligible and a
cancelled close retries pending presentation. New regression tests and the private-routing suite are not run locally;
CI must validate the merged head. Recoverable-page data integration and feature-level killed-process validation remain unverified; the crashed-session state seam shipped in #577.

### Restore pages Peek preservation (#580)

Recovery declines a Peek when the host has any live or hidden Peek, and attempts its one supported Peek before
opening Little Arkt windows. A missing Peek content view closes the new tab and retains the unanswered offer. Ordinary
link opening retains its replacement behavior. Little Arkt's API does not report presentation success; the shell
can only report that its opening was requested. Multiple recovered Peeks remain unanswered pending the maintainer's
routing decision. The crashed-session state seam shipped in #577; recoverable-page data integration and feature-level killed-process validation remain unverified.

GUI regressions cover live and hidden Peek preservation, missing-view cleanup and retry, and Find closing on Escape.
They were written before the fix but not run locally because the installed toolchain cannot compile the baseline.
Syntax parsing is not a runtime test. CI on the new head, GUI appearance, VoiceOver, Reduce Motion and UI tests remain
unverified.

### Restore pages CI evidence and remaining decision (#580)

CI run [42364783894](https://github.com/krystianslowik/arkt/actions/runs/42364783894) applies only to commit
`4158a3411c5a5e286b2f05b7f7b4ebfd8592c0b7`: all 8 reported checks passed. ShellKit pure tests ran 2,454 tests
across 278 suites; GUI tests executed 2,025, skipped 48 and had 0 failures. The app build, lint and required Swift gate
passed; Core and optional UI tests were skipped. The held-close and recovery-window suite passed. These results do not
validate the subsequent merge head, which requires new CI.

The multi-Peek routing decision is tracked in [#776](https://github.com/krystianslowik/arkt/issues/776)
(`status:needs-user`); the maximum-one-Peek safety remains in place. #577 shipped crash state and dismissal, but
recoverable page payload and source grouping integration and feature-level killed-process validation remain missing.

Test-first integration of #777: private-window reopen coverage observes recovery routing during creation and checks
that a separate empty-crash notice remains available to a regular window. Both private kinds are covered. The current
`makePrivateWindow` creates a regular window before converting it, so CI is expected to expose the regression; this
has not yet been observed. Production routing remains unchanged pending that red run. Local tests were not executed:
the installed toolchain cannot compile baseline ShellKit. Swift source parsing and diff checks passed. The prior green
for this integration is attributable only to `22d4906e12ddb3cd053b4f836e3be00810c0e1d1`: 2,454 pure tests in 278
suites, 2,038 GUI tests executed, 51 skipped, zero failures, and all eight reported checks passed. Those results do not
validate this test-first merge. The PR stays draft while #776 awaits the maintainer; maximum-one-Peek safety remains.

### Private reopen creation routing (#777)

Blank and Incognito reopen windows now receive their final kind during construction, before recovery routing runs.
The private-window handover still precedes `isClosed`, and recovery reassignment follows it. The existing synchronous
GUI regressions were not run locally because the installed toolchain cannot compile baseline ShellKit. Swift source
parsing and `git diff --check` passed; they do not establish compilation or runtime behavior. The shell-owned
recovery migration remains incomplete and the test-first APIs at `781c729` remain missing.


### Restore pages combined migration and live recording (#580)

The local combined head includes the App/Persistence snapshot adapter, shell-owned recovery records and source-node
routing, removal of the engine page payload, and live Little Arkt and Peek recording. Controller events track opens,
navigation, titles and actual closes, including hidden Peeks. Private windows and sidebar pages are excluded. The
initial offer remains immutable; at offer time missing or archived Peek sources are excluded and duplicates keep the
last. Empty offers show the notice and acknowledge. Confirmed clean quit clears and stops further shell writes; a
cancelled quit resumes tracking. The App suspends writes during teardown and resumes them after the outcome.

There is no final confirmed-termination hook for SIGTERM: its flush retains the snapshot. Normal confirmed quit
requests a clear; a failed flush is logged and the existing quit flow allows failure. Neither durable clearing nor
feature completion is guaranteed by this change. Killed-process validation and App adapter integration remain open.

No migration tests or builds were executed locally: the installed toolchain cannot compile the baseline. Source
parsing, diff and import checks are static checks only; CI on this combined head is pending. Prior CI green at
`22d4906` (2,454 pure tests; 2,038 GUI executed, 51 skipped) does not validate this head. The `da223` GUI run had
eight assertion failures; the private creation path was fixed in `b203`, but has not been runtime verified locally.

### Restore pages cancellation snapshot refresh (#580)

The combined migration at `0fdd51c` passed CI run 42377016354: ArktCore 579 tests in 47 suites, ShellKit pure
2,489 tests in 281 suites, and GUI 2,068 executed with 53 skipped and no failures. The app build, lint and required
Swift gate passed; optional UI tests were skipped. These counts apply to that revision.

Independent review found that changes ignored during a cancellable quit left stale recovery records after
cancellation. The test-first GUI run 42378422902 at `8a9f1df` executed 2,069 tests, with 53 skipped and one failure:
`testCancelledQuitRebuildsRecordsAfterSuspendedChanges` retained a closed Little Arkt and the old metadata of a
surviving page. Cancellation now immediately rebuilds records after tracking resumes, without waiting for another
page event. Current main is merged with both results histories preserved. At `98e63f7`, [CI run 42380522535](https://github.com/krystianslowik/arkt/actions/runs/42380522535) passed all eight reported checks: ArktCore 579 tests in 47 suites, ShellKit pure 2,508 tests in 282 suites, GUI 2,075 executed, 53 skipped and zero failures (including the cancellation regression), app build, lint and the required gate. Optional UI tests were skipped. These results apply to `98e63f7`; the subsequent screenshot fixture head requires fresh CI and a manual workflow for XCUITest. Manual appearance, VoiceOver, Reduce Motion and
killed-process validation, plus the documented SIGTERM and failed-flush limits, remain outstanding.


### Restore pages screenshot evidence (#580)

`RestorePagesScreenshotTests` exports synthetic light and dark window captures with a long title and overflow when
`ARKT_RESTORE_SHOTS_DIR` is set. The existing GUI CI job exports `restore-pages-screenshots` as a seven-day artifact.
Rendering, visual inspection and the manually dispatched XCUITest workflow remain pending on the evidence head.

### Restore pages final CI and screenshots (#580)

CI run 42385504787 at `1c110df` passed all eight reported checks: ArktCore 579 tests in 47 suites, ShellKit pure
2,508 tests in 282 suites, and GUI 2,077 executed with 54 skipped and zero failures. The cancellation regression
and screenshot fixture passed; the app build, lint and required gate passed. Optional UI tests were skipped.
The light/dark synthetic 1000 × 674 window-content PNGs are preserved in `docs/evidence/restore-pages/` and
were visually inspected for the panel, long-title truncation, overflow and action count. This evidence applies
to `1c110df`; the subsequent evidence commit changes documentation and images only.

Manual XCUITest run 42382637990 at `dd8e937` built the app but did not complete: import/onboarding consent queries
timed out and a command-bar accessibility snapshot was interrupted before the 40-minute job limit cancelled it.
The preceding main nightly run 42357672719 has the same signature; #799 tracks the import/onboarding diagnosis.
This is not a complete XCUITest pass. Real killed-process, VoiceOver, appearance and motion checks remain for
maintainer validation, together with review of the documented SIGTERM and failed-flush limits. #580 remains open.

### Restore pages full-review cleanup (#580)

The full review of `844074a` found no blocking issue. The engine protocol comment now describes the shell's offer,
and the noted Swift declarations and expressions are wrapped. Main is merged with both results histories retained,
main's sections first. Source parsing and diff checks validate syntax and whitespace only; fresh CI must validate the
integrated revision. The GUI screenshot upload step and committed PNGs remain unchanged pending the maintainer's
answer. Manual killed-process, VoiceOver and motion checks, and the documented quit limits, remain outstanding.

### Unanswered restore offer contract tests (#580)

The maintainer follow-up requires retaining the crashed snapshot through live page changes and a clean quit until the
offer is answered, matching the marker behavior proposed in [#803](https://github.com/krystianslowik/arkt/pull/803).
The test-first GUI cases cover repeated offers using the same record store and persisted sidebar NodeID with fresh fake
engines, independent overwrite and clear assertions, and resumed recording and clearing after Restore or Dismiss. This
is a Shell contract test, not a real Chromium or database roundtrip; Core Persistence already tests database reopening.
The empty filtered offer notice remains covered. At test-first head `912443b`, [GUI run 42422178440](https://github.com/krystianslowik/arkt/actions/runs/42422178440/job/128552912724) executed 2,081 tests, skipped 54 and reported 9 assertion failures in the four unanswered-offer regressions. The earlier `4beeeec` compile error was not a behavioral red.

The window set now protects the captured crashed records from initialization through an unanswered offer, including
live changes, cancelled quit and confirmed clean quit. Restore, Dismiss and the empty notice release protection and
immediately rebuild the live snapshot; a failed Restore retains the offer. A pre-offer and cancelled-quit boundary
regression and an immediate empty-notice refresh assertion supplement the existing tests. The fake engine models the
retained marker; this is not a Chromium relaunch. #803 remains unmerged.

Swift 6.2.4 source parsing and scoped diff/import checks are static only. Local full builds and tests were not run
because the baseline cannot compile; CI on the implementation head is pending. Earlier green run 42407828692 at
`004e3ca` reported Core 579 tests/47 suites, pure ShellKit 2,510/282 and GUI 2,077 executed/54 skipped/0 failures;
those results predate these regressions and the fix.

## #846: an HTTP-only site crashes the engine at `TabDialogManager`'s `CHECK(host)`

Date 2026-11-08. Branch `engine/846-https-first-dialog` from `origin/main` (`3a0263c`). Found while reviewing #795.

### Gate

- Seam: no patch. The mitigation is one more name in the shell's `--disable-features` list
  (`EngineLaunchArguments.requiredDisabledFeatures`, where `MediaRouter`, `Glic` and the others are switched off).
  The check adds test-only code to the self-test embedder.
- Facade header: unchanged (`cmp` identical). `.patches`: unchanged, 14 lines, 14 `arkt` commits above
  `156.0.8078.48` (`in sync`).
- Overlay link checked before each build: `$CR/arkt` points at this worktree's `engine/arkt`.
- Build: `nice -n 10 autoninja -j 4 -C out/Arkt chrome`, incremental. Chromium disk 1.9 TB free, internal 73 GB,
  swap 5.5 to 5.7 GB of 7 GB (under the 6.5 GB stop line), load average 4 to 7 from other lanes' work.
- Test bundle: `out/Arkt/Arkt.app` (`dev.arkt.Arkt`), launched by path; the installed app is `com.arkt.Arkt` and the
  ArktTest copies are `dev.arkt.ArktShell`. Nothing under `/Applications` or `~/Applications/ArktTest` was touched.

### What triggers it

`HttpsOnlyModeTabHelper::DidFinishNavigation` shows the ask-before-HTTP dialog when an HTTPS-First navigation falls
back to HTTP and `HttpsFirstDialogUi` is on (on by default). The dialog goes through
`TabDialogManager::CreateAndShowDialog`, whose `CreateTabScopedDialog` checks the host widget, which an Arkt window
does not have. Loopback hosts never reach it: `HttpsUpgradesInterceptor` exempts `localhost` and loopback addresses by
name, non-strict modes exempt non-unique hostnames and URLs with a port. So the page is served on `127.0.0.1:8846` but
loaded as `http://http-only.example.com/`, with
`--host-resolver-rules=MAP http-only.example.com:80 127.0.0.1:8846, MAP http-only.example.com:443 127.0.0.1:8846`.
The HTTPS attempt reaches the plain HTTP server, fails the TLS handshake (the server logged three `400` client
hellos), and the navigation falls back to HTTP.

An off-the-record Arkt window comes from Chromium's New Incognito Window command sent through the host (the facade's
`createBrowser(host:)` always uses the profile the engine started with, #705); the shell's private windows run on
that regular profile today.

### What landed

- `HttpsFirstDialogUi` joins the shell's `--disable-features` list, with its reason in the doc comment, and
  `EngineLaunchArgumentsTests` follows (`keepsTheHttpsFirstDialogOff`, the expected lists).
- Self-test embedder: `arkt-selftest private-window <url> [ms]` sends `IDC_NEW_INCOGNITO_WINDOW` through the host,
  loads `url` in the new window's tab and, after `ms` (3000 by default), logs the tab's `state` and evaluates
  `document.title` plus the interstitial's `#primary-button` text.

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api`, fresh profiles in a scratch folder, `--use-mock-keychain`, the host rules above)

"Old list" is the shell's list before this change (`DestroyProfileOnBrowserClose,WebAuthenticationAmbientSignin,
MediaRouter,Glic`); "new list" adds `HttpsFirstDialogUi`. Each run lasted 20 s unless it crashed first.

| Run | Window | List | Result |
|---|---|---|---|
| a-repro | off the record (`private-window`, driver page on `127.0.0.1:8846/private`) | old | CRASH: `FATAL:chrome/browser/ui/tabs/tab_dialog_manager.cc:307] Check failed: host.`, `Received signal 6`, exit 134, 0.36 s after `urlChanged ... url=http://http-only.example.com/` |
| a-mitigated | off the record | new | PASS: `titleChanged ... title=Site is not secure`, `state ... url=http://http-only.example.com/ title=Site is not secure loading=no crash=0`, `eval private-window page ... result=Site is not secure \| Go back`; process alive, stopped by PID |
| b-repro | regular, `https_only_mode_enabled: true` written into the fresh profile ("Always use secure connections") | old | CRASH: the same `Check failed: host.`, exit 134 |
| b-mitigated | the same | new | PASS: `title=Site is not secure`, alive |
| c-control | regular, fresh profile, default settings | old | CRASH: the same `Check failed: host.`, exit 134 |
| c-mitigated | the same | new | PASS: `title=Site is not secure`, alive |

The crash report's crashing thread (symbolized from the framework):
`HttpsOnlyModeTabHelper::DidFinishNavigation` -> `AskBeforeHttpDialogController::ShowDialog` ->
`TabDialogManager::CreateAndShowDialog` -> `TabDialogManager::CreateTabScopedDialog` -> `CheckLogMessage` -> `abort`.

The control was meant to load the HTTP page quietly; instead a fresh regular profile also gets the HTTPS-First warning
on this host, so the crash is not limited to private windows: any HTTP-only site with a public hostname took down the
engine in a normal window with default settings. No Arkt patch or overlay file touches HTTPS-First, and the
profile held no HTTPS-First pref, so this is stock 156 behaviour; which heuristic turns the warning on for a fresh
profile was not traced. With the dialog off, every case shows the interstitial in the tab and the engine stays up.

The old/new pairs are the deliberate break: the same build and page, with and without the one feature name.

| Step | Result |
|---|---|
| Build with the self-test command | `The build has finished successfully.`, `FAILED:` 0, under 2 min |
| Format-only rebuild (clang-format on the added lines) | finished, `FAILED:` 0, 71 s; `git status` in `$CR` clean apart from the untracked `build/util/MINIBRANCH` |
| `swift test --filter EngineLaunchArgumentsTests` (ShellKit, `nice -n 20 -j 2`) | 10 tests passed |

### Not done here

- The guard before `CHECK(host)` (acceptance 4): left to the maintainer. It would be E3b's choke-point guard landing
  early and costs one upstream file (`tab_dialog_manager.cc`); with the dialog off, nothing in these runs reaches it.
- The #795 doc's E3b inventory row for ask-before-HTTP (acceptance 5) lives on the open #795 branch; it should say
  "switched off by #846" when that doc lands.
- The Engine app itself was not launched: it builds the same `--disable-features` value through
  `EngineLaunchArguments`, which the Swift tests cover; the self-test runs pass the list by hand.

### Patch budget

Unchanged: 14 patch files, 14 `arkt` commits, in sync. No upstream file touched.

### Cleanup

Every engine run and the loopback server stopped by exact PID (`ps -p` prints nothing for each). The throwaway
profiles were deleted. The two macOS crash reports the crashing runs wrote (bundle `dev.arkt.Arkt`) were copied to the
artifacts folder and removed from `DiagnosticReports`. The runs did not use the clipboard.


### Restore pages integration with current main (#580)

Merged main `4d40f38` into the recovery branch. The sole conflict was this shared results document; both the
complete recovery history and main's #846 engine diagnosis/results were retained. ToastView's automatic merge
keeps the recovery-specific multiline decision and main's radius/type roles. The unanswered-offer coordinator,
AppSession recording guard and their existing regression files are byte-identical to the previously tested recovery
head `aa72ced6a94c478b9c83cead32f09804b19c88c7`.

#810 is now merged. The recovery panel uses `ShellRadius.sheet` and its recessed list uses `ShellRadius.field`,
preserving their 14 pt and 10 pt values. A source scan mirroring CornerRadiusLintTests' exact regex and exemptions
found two offending assignments before that correction and zero afterward. This is a static source check, not an
executed Swift Testing result. No screenshots were regenerated; the existing captures remain historical evidence.

Swift 6.2.4 frontend parsing passed for all 80 changed Swift files. The workflow import/UI-source checks, actionlint
and whitespace/conflict-marker checks passed. No full local package/App build, GUI, engine or manual accessibility
run was performed. CI must validate the merged head; the last full green remains run 42424301771 at `aa72ced`.
#803 remains open, so production-engine repeated unanswered recovery and cross-launch validation still depend on
that retained crash marker. Native killed-process recovery, quit/cancellation and VoiceOver remain unverified.

## #851: a tab-modal dialog on an Arkt window is cancelled, not a crash (patch 0015)

Date 2026-11-08. Branch `engine/851-tab-dialog-guard` from `engine/846-https-first-dialog` (PR #849, not merged
yet). The maintainer chose to land E3b's one-file guard now (#851, acceptance 2).

### Gate

- Why a patch: `TabDialogManager::CreateTabScopedDialog` does `CHECK(host)` on the tab's Views host widget, which an
  Arkt window does not have. Every tab-modal dialog reaches it (`CreateAndShowDialog`, and the direct
  `CreateTabScopedDialog` callers `chrome_webui_dialog.cc:93` and `indigo_onboarding_dialog.cc:199`), and no overlay
  seam sits in front of it. #849's switch closes only the HTTPS-First dialog.
- Facade header: unchanged (`cmp` identical). `.patches`: 14 to 15, number 0015 claimed in the pull request; no open
  engine pull request touches `engine/patches` and no earlier patch touches `tab_dialog_manager.cc`.
- Overlay link checked before each build: `$CR/arkt` points at this worktree's `engine/arkt`.
- Builds: `nice -n 10 autoninja -j 4 -C out/Arkt chrome`. Chromium disk 1.9 TB free, internal 72 GB, swap 5.7 GB of
  7 GB throughout (under the 6.5 GB stop line), load average 4 to 5.

### Why the guard returns a widget, not nothing

Patch 0013's toast guard drops the toast and returns. Here that would move the crash one line: most callers
dereference the returned widget at once (`dialog_widget_->MakeCloseSynchronous(...)` in the ask-before-HTTP, credential
leak, Lens permission, password change, autofill progress, account chooser and Indigo callers). So patch 0015:

- `CreateTabScopedDialog`: with no host widget, the dialog widget is created as usual but parented to the tab's own
  view (`GetContents()->GetNativeView()`, inside the Arkt window). It is not shown.
- `ShowDialog` (every path, including the two direct callers' own calls): with no host widget it logs
  `ARKT: tab-modal dialog cancelled, the window has no Views widget`, posts `Close()` through the widget's weak
  pointer and returns. The close runs on the next turn, after the caller has set its close handling, so the caller
  sees an ordinary dismissal (its `MakeCloseSynchronous` callback, or the delegate's close callback).

One file, 27 insertions and 1 deletion.

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api`, fresh profiles in a scratch folder, `--use-mock-keychain`, the #846 page `http://http-only.example.com/` mapped to `127.0.0.1:8851`)

"Old list" is the shell's list without `HttpsFirstDialogUi`, so the HTTPS-First dialog is on for that run only;
"new list" is the shipping list from #849.

| Run | Window | List | Patch 0015 | Result |
|---|---|---|---|---|
| g-private-old | off the record (`private-window`) | old | in | PASS: `ARKT: tab-modal dialog cancelled, the window has no Views widget`, then `state ... url=http://http-only.example.com/ title=http-only.example.com loading=no crash=0`; engine alive 20 s, stopped by PID |
| g-strict-old | regular, "Always use secure connections" | old | in | PASS: the same log line, engine alive |
| g-default-old | regular, fresh profile, defaults | old | in | PASS: the same log line, engine alive |
| g-private-new | off the record | new | in | PASS: unchanged from #849, `Site is not secure \| Go back`, no cancel line |
| break-private-old | off the record | old | removed (`tab_dialog_manager.cc` back to the pin, rebuilt) | CRASH: `Check failed: host.`, `Received signal 6`, exit 134 |
| break-default-old | regular, defaults | old | removed | CRASH: the same, exit 134 |

`FATAL`, `NOTREACHED` and `DumpWithoutCrashing` lines in the g-runs: 0. With the dialog cancelled, the tab stays on an
empty page at the HTTP URL: the HTTPS-First throttle has already stopped the navigation, and the dialog that would
have let the user go on is gone. So the guard is a backstop against the crash, not the user path; the user path stays
#849's interstitial.

| Step | Result |
|---|---|
| Build with patch 0015 | `The build has finished successfully.`, `FAILED:` 0, 75 s |
| Break build (file back to `156.0.8078.48`) | finished, `FAILED:` 0, 69 s |
| Restore build | finished, `FAILED:` 0, 69 s; `git status` in `$CR` clean apart from the untracked `build/util/MINIBRANCH` |

### Reachability of the credential leak and edit address dialogs (acceptance 1)

One probe run on the patched build with the new list: a normal window, loopback forms on `127.0.0.1:8851`, values
typed with DevTools `Input.insertText` (`--remote-debugging-port=9851`), then the button clicked from script with a
user gesture; `--log-net-log` into the artifacts folder.

- **Edit address: not reachable on an Arkt window.** The only way in is `AddressBubblesController::ShowEditor`, from
  the Edit button of the save and update address bubbles (`save_address_bubble_controller.cc:244`,
  `update_address_bubble_controller.cc:124`). The overlay's `ArktAutofillBubbleHandler` closes those prompts without
  showing them (#768), so there is no Edit button to press. Runtime: a full US address submitted logged
  `ARKT: autofill bubble SaveAddressProfile not shown`, no tab-modal line, no crash.
- **Credential leak: the check runs, the warning cannot come back on this build.** Signed out, a sign-in form
  submitted with a well-known leaked test pair started the lookup: the net log shows
  `passwordsleakcheck-pa.googleapis.com/v1/leaks:lookupSingle`, which this run sent to `~NOTFOUND`
  (`--host-resolver-rules`) so nothing left the machine. A signed-out lookup carries the build's Google API key, and
  this build has none: the framework holds only the `dummytoken` placeholder, not a valid key (the rejection itself was
  not observed, since nothing was sent). So no leak answer and no dialog here. It becomes reachable in a build with Google API keys, or once a user signs in to a
  Google account in the engine. With patch 0015 it would then be cancelled rather than crash; drawing it natively,
  or switching the warning off (the `profile.password_manager_leak_detection` pref), is the follow-up's call.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 15 |
| `arkt` commits above `156.0.8078.48` | 15 |

In sync. Export added 0015 and its `.patches` line; 0001 to 0014 byte-identical. Facade header copies `cmp` identical.

| Gate (design section 2.5) | Before | After #851 |
|---|---|---|
| Patch files | 14 | 15 |
| Upstream files outside 0001-0004 | 19 | 20 |
| Hunks in `browser_actions.cc` and `browser_commands.cc` | 4 | 4 |
| Hot-file hunks (`browser_window_features.cc`, `tab_features.cc`) | 0 | 0 |
| Widely included headers changed | 0 | 0 |

### Left open

- #795's E3b gate grep should also match `CreateTabScopedDialog(` (#851, acceptance 3); #795 is still open, so the
  line is noted in this pull request instead of edited on that branch.
- Upstream unit tests for `TabDialogManager` were not run; tests whose tab has no host widget would now get a
  cancelled dialog instead of the CHECK.
- The leak warning above, once a build has API keys or sign-in.

### Cleanup

Every engine run and the loopback server stopped by exact PID (`ps -p` prints nothing for each); nothing listens on
8851 or 9851. The throwaway profiles were deleted. Three macOS crash reports from these runs (the two break runs, and
one renderer helper that failed to set up its sandbox while g-strict-old was quitting after its `kill`) were copied
to the artifacts folder and removed from `DiagnosticReports`. The runs did not use the clipboard.

## #785: ask again about an unanswered crashed-session prompt

Date 2026-11-07. Branch `engine/785-unanswered-crash-prompt` from `origin/main` (`e8380ee`). Facade only: no patch,
no `EngineAPI` change.

### Gate

- Seam: the facade engine's crashed-session state (#577). A patch is not needed: the facade keeps its own marker.
- Facade header: the doc comment on `lastSessionCrashed` and `dismissLastSession` only; no declaration changes. Both
  copies `cmp` identical.
- `.patches`: unchanged (14).
- Build: `nice -n 15 autoninja -C out/Spike chrome -j 4`; 1.9 TB free on the Chromium disk, 29 GB on `/`, swap 3.8 of
  5 GB used before the build.

### Why Chromium's own mechanism cannot be used

`ExitTypeService` keeps the last exit `Crashed` across runs only while it waits for the user to acknowledge the crash.
The first tab added to a window made outside the startup flow acknowledges it (`BrowserTabObserverImpl`,
`OnTabAddedToNonStartupBrowser`), and every shell window is one. A `CrashedLock` (what Chrome's bubble holds) does not
help: `DidUserAckCrash` passes once the tab observer is gone, whatever the lock count. After the acknowledgement a
clean quit writes `SessionEnded`, so the next run read a clean exit.

### What landed

- **Marker.** A file `Arkt Unanswered Crash` in the profile folder (next to `Preferences`). When the facade starts it
  reads the last exit type as before; `lastSessionCrashed` is YES when that is `kCrashed` or the marker exists. A
  crashed last session writes the marker at once, so a quit or a kill before the shell's prompt is answered keeps it.
- **Answer.** `dismissLastSession` removes the marker (thread pool, `MayBlock`, `BLOCK_SHUTDOWN`, so an answer
  followed at once by Quit is kept). It is the only thing that removes it. A dismiss when nothing is pending does
  nothing, as before.
- **Blocking.** The read and the write run when the facade is made, in `PostBrowserStart`, which is inside
  `BrowserMainLoop::PreMainMessageLoopRun` before it calls `DisallowUnresponsiveTasks`; blocking is still allowed
  there. Only the removal runs later, off the UI thread. `out/Spike` has DCHECKs off, so the runs below do not prove
  the blocking rule; the ordering above does.
- **Log.** `ARKT: facade last session crashed (unanswered from an earlier run)` when only the marker asks.
- **#690.** The shell API is unchanged: `EngineSessionRecovery.lastSessionCrashed` and `dismissLastSession()` keep their
  shape, and #690's `RestorePagesModel` and its doubles compile as they are. Its behaviour changes in the right way: an
  offer that is neither restored nor dismissed comes back on the next launch. Two points for #690: its `.notice`
  path (no pages to offer) dismisses at once, which also clears the marker; and the recovery pages must survive a
  launch that did not answer, or the repeated prompt has nothing to offer.

### Tests first

The failing case is a smoke run, as the code is Chromium-side and the Swift doubles do not change. Before the change
(`out/Spike` as built from `e8380ee`, profile `profiles/785-20261107/base`):

| Run | Result |
|---|---|
| Start, SIGKILL once `exit_type` `Crashed` is on disk | `facade last session clean` (fresh profile) |
| Relaunch, SIGTERM 4 s after `embedderReady` without answering | `embedderReady lastSessionCrashed=yes`; on disk `SessionEnded` |
| Relaunch | `facade last session clean`, `lastSessionCrashed=no`: the bug |

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "ArktEngineABITests\|ChromiumTabStateTests\|TabStateTests"` | 4 test runs, 3 + 23 + 15 + 33 = 74 passed, 0 failed; no Swift source changed, the header copy changed in comments only |
| Full suite | not run locally (memory pressure on this Mac); CI's Swift tests job |

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 15 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 45 s; again after a comment and include-order edit, 41 s |

### Self-test runs (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api`, fresh profiles under `profiles/785-20261107/`, `--use-mock-keychain`; the answer is the self-test's `session dismiss` command, set as the start page title through `--arkt-facade-selftest-url`)

| Check | Result | Evidence |
|---|---|---|
| Crash, relaunch | PASS | SIGKILL with `Crashed` on disk; relaunch: `facade last session crashed`, `embedderReady lastSessionCrashed=yes`, marker written |
| Quit without answering, relaunch | PASS (was the bug) | SIGTERM, on disk `SessionEnded`, marker kept; relaunch: `crashed (unanswered from an earlier run)`, `lastSessionCrashed=yes` |
| Quit unanswered again | PASS | same again on the next relaunch; the prompt stays until answered |
| SIGKILL 2 s after a relaunch | PASS | marker kept (on disk `exit_type` still `SessionEnded`, the run's own write had not happened); next relaunch still asks |
| Answer, quit | PASS | `embedderReady lastSessionCrashed=yes`, `session dismiss`: `crashed session dismissed`, `lastSessionCrashed=no`; SIGTERM about 0.3 s later; marker removed |
| Relaunch after the answer | PASS | `facade last session clean`, `lastSessionCrashed=no` |
| Final binary (after the last build), crash, two unanswered quits, answer, relaunch | PASS | `no`, `yes`, `yes`, `yes` then `no`, `no` |

`FATAL` and `Check failed` lines: 0 in every run.

### Known limit: the first Preferences write

A run killed before the profile's first `Preferences` write leaves no `Crashed` mark on disk, so the next run reports
a clean exit and no marker is written. Fresh profile, SIGKILL 2 s after start: no `Preferences` file; relaunch:
`lastSessionCrashed=no`. Time to `exit_type` `Crashed` on disk from a fresh start, polled every 0.25 s: 15.7 s,
12.4 s, 15.5 s (load average 6 to 9; #577 saw about 7 s). Chromium writes prefs through `ImportantFileWriter` on its
commit interval, so this is Chromium's behaviour too; closing it would need the facade to write `Preferences` early,
which this change does not do. Once a crash has been seen the marker is written at start, so a second early kill does
not lose the prompt (row 4 above). Recorded in the header comment on `lastSessionCrashed`.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 14 |
| `arkt` commits above `156.0.8078.48` | 14 |

In sync; nothing exported. Facade header copies `cmp` identical.

### Left open

- The shell prompt itself is #690 (#580). Its `.notice` path and its recovery pages across an unanswered launch (above).

### Cleanup

Every run stopped by exact PID (SIGKILL or SIGTERM; `ps -p` printed nothing for each). The throwaway profiles under
`profiles/785-20261107/` and the run logs were deleted. No clipboard use. Nothing under `~/Applications/ArktTest` or
`/Applications/Arkt.app` was touched.

## #782: count site data only while the page info panel is open

### Gate

1. Seam, no patch. Before, every `pageInfo` read more than 10 s after the last count started
   `BrowsingDataModel::BuildFromDisk` over the whole profile; the address pill reads page info on every refresh.
2. Facade header: additive. `ArktTabHandle` gains `-pageInfoDidOpen` next to `-pageInfoDidClose`. The comments of
   `pageInfo`, `hasSiteData` and `ArktEngineEventKindPageInfoChanged` now say when the engine counts. Both copies
   `cmp` identical.
3. `.patches` unchanged (14).
4. `out/Spike` only, `nice -n 15`, 4 jobs; self-test smoke on a fresh profile with `--use-mock-keychain`.

### What landed

- **`PageInfoHub`** (`arkt_page_info.cc`): keeps the tabs whose panel is open (weak pointers, so a closed tab drops
  out). `PageInfoOpened` records the tab and starts the count when the profile's count is stale or missing;
  `PageInfoClosed` removes it. `SiteData` starts `BuildFromDisk` only for an open tab. With no panel open, a read
  returns the profile's last count, however old, or none. When a count arrives, only tabs that are still open get
  `PageInfoChanged`. A `VLOG(1)` line gives the entry count and the build time (`--vmodule=arkt_page_info=1`).
- **Facade**: `-pageInfoDidOpen` runs through `runOrQueue`, as `-pageInfoDidClose` does. The self-test embedder adds a
  `pageinfo-open` command.
- **EngineAPI**: `EngineSiteSettings.pageInfoDidOpen(tab:)`, with an empty default in a protocol extension.
  `ChromiumEngine` forwards it to the handle. `InMemoryEngine` records `openPageInfoPanels`; its site data is a test
  driver that costs nothing to read, so it is still reported with no panel open. `FakeEngine` has an explicit no-op
  (WebKit's site data is not counted). The scripted facade and `ConformanceTests.TestTab` implement the new method.
  Contract rule 26's reload-infobar check now opens the panel first, as the shell does.
- **Shell**: `PageInfoPanelController.show(for:anchoredTo:)` calls `pageInfoDidOpen(tab:)` once the panel is
  committed to a tab. Every close path already went through `hide`, which calls `pageInfoDidClose(tab:)`.

### Tests first

New: `PageInfoTests.openAndCloseAreRecordedPerTab` (EngineAPITests),
`ChromiumPageInfoTests.openingThePanelTellsTheFacade`, the open call in `callsForAnUnknownTabDoNothing`,
`FakeEnginePageInfoTests.engineOffersSiteSettings` calling it, and
`PageInfoPanelTests.testTheEngineCountsSiteDataOnlyWhileThePanelIsOpen` (GUI). Red run: `swift build --build-tests`
failed to compile (`InMemoryEngine` has no member `openPageInfoPanels`). Deliberate break: with
the controller's `pageInfoDidOpen` call commented out, the GUI test fails ("the panel tells the engine it opened");
restored.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

| Command | Result |
|---|---|
| `swift test --filter "EngineAPITests\|ChromiumEngineKitTests\|ArktEngineABITests\|FakeEngineKitTests.FakeEnginePageInfoTests"` | 286 + 171 + 33 + 6 passed, 0 failed (EngineAPITests +1, ChromiumEngineKitTests +1) |
| `swift test --filter "ShellKitGUITests.PageInfoPanelTests"` | 28 passed, 0 failed (+1) |
| Full suite (`swift test --skip ShellKitGUITests`) | not run locally (other lanes building on this Mac); CI's Swift tests job |

### Build

| Step | Result |
|---|---|
| `nice -n 15 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`; the header change rebuilt the 15 overlay objects and relinked `libchrome_dll.dylib` (41 s) |

### Smoke (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --vmodule=arkt_page_info=1`, fresh profile `profiles/782-20261107/`, `--use-mock-keychain`)

A synthetic profile: a loopback server on `127.0.0.1:8782` led one tab through 400 origins
(`s0.localhost` to `s399.localhost`), each writing three cookies, 8 KB of local storage and a 32 KB IndexedDB record,
then to a test page on `127.0.0.1:8782` (two cookies, 2 KB of local storage) whose title ran the commands on a timer.
The profile was 519 MB on disk afterwards, most of it caches.

| Time | Command | Panel | Result |
|---|---|---|---|
| 0 s | `pageinfo` | closed | `siteData=counting`, no count started |
| 11 s | `pageinfo` | closed | `siteData=counting`, no count started |
| 12 s | `pageinfo-open` | open | `site data counted entries=1603 in 37 ms`, then `pageInfoChanged siteData=2 cookies 2003 bytes` |
| 19 s | `pageinfo` | open | `2 cookies 2003 bytes` (fresh, no count) |
| 25 s | `pageinfo` | open | the old count at once, then `entries=1603 in 12 ms` (older than 10 s); same count, so no `pageInfoChanged` |
| 27 s | `pageinfo-close` | closed | |
| 39 s | `pageinfo` | closed | the last count, no count started though it is 14 s old |
| 40 s | `pageinfo-open` | open | `entries=1603 in 11 ms`; a read at 47 s reports the count |
| 48 s | `pageinfo-close` | closed | |

Three counts in the run, each after a `pageinfo-open`; none for the closed reads, nor for the reads the self-test
makes on each `pageInfoChanged` while the 400 pages loaded. `FATAL`, `Check failed`, `NOTREACHED`: 0.

`BuildFromDisk` on this profile: 37 ms for the first count, 11 to 12 ms after that. This is a synthetic profile of 1603
entries on an SSD; a real profile with years of data was not measured (only throwaway profiles are used here).

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 14 |
| `arkt` commits above `156.0.8078.48` | 14 |

In sync; nothing exported. Facade header copies `cmp` identical.

### Left open

- `BuildFromDisk` on a large real profile: the number above is from a synthetic one. A maintainer run on a copy of a
  real profile would confirm it.
- The profile's model stays in memory after the last panel closes, as before; it could be dropped then.

### Cleanup

Chromium and the loopback server were stopped by exact PID; `ps -p` prints nothing for either. The profile
`profiles/782-20261107/` and the build log were deleted. Nothing else on the Chromium volume was touched.

## #754: a history batch sent again after "no answer" is stored once

Date 2026-11-07. Branch `engine/754-history-import-dedupe` from `origin/main` (`e8380ee`). Overlay and Swift only: no
Chromium patch, `.patches` unchanged, facade header unchanged.

### Cause

#565 found that a batch the history store never confirmed ("no answer from the history store", for example when the
history service goes away mid-import) can already be on disk. The coordinator freezes the watermark at such a batch,
so the next import sends it again with every batch after it, and `HistoryBackend::AddPageVisit` checks the URL row but
not the visit time, so `AddPage` stored each visit a second time. The same resend happens after a visit the engine
refused (an invalid URL), so confirmed batches behind a refused one were duplicated too. Only the engine can tell what
is already stored, so the fix is there and the coordinator keeps resending.

### What landed

- `arkt_import_writer.cc`: `HistoryImport` first runs a `HistoryLookup` (a `HistoryDBTask`) that reads, per URL,
  `GetRowForURL` and `GetVisitsForURL` and marks each visit whose URL and visit time the history already holds (or
  that came earlier in the same batch). Back on the main thread, held visits are counted skipped and count toward
  `latest_visit`; the rest go through `HistoryService::AddPage` as before (visited links and `CanAddURL` unchanged),
  followed by the barrier from #531. A lookup destroyed without answering, or the service going away first, counts
  every unconfirmed visit failed, as before, so the import still always answers.
- `latest_visit` (Swift `latestVisit`) is the newest visit written or already held, so a batch that turns out fully
  held still moves the watermark past it. The facade header still says "newest visit written"; it was left alone
  because #803 and #811 edit that header.
- `ImportRecording` (the stub behind `InMemoryEngine` and `FakeEngine`) applies the same rule and takes an injectable
  clock. `EngineImportContract.runHistory` gains the step "the same batch without a watermark writes nothing".
- Runner phase `--arkt-import-check=history-retry`: sends the synthetic `history-shutdown` batch (4000 URLs, 10 visits
  each) with no watermark and waits for the answer. Both phases now count the visit times back from the start of the
  day, so runs on the same day send the same visits.

### Tests (ShellKit, `nice -n 20 swift test -j 2 --filter ...`)

| Step | Result |
|---|---|
| Before the fix: `InMemoryEngineImportTests`, `FakeEngineImportTests`, `ProfileImportCoordinatorTests` | failed: `keepsTheHistoryAndBookmarkContract` in both engines (`same batch again: written: 4`), `aBatchThatGotNoAnswerIsStoredOnceWhenALaterImportSendsItAgain` (10 visits stored, not 5) |
| After the fix, same filter plus `ChromiumImportTests` | passed: 5, 7, 31 (30 before) and 16 tests |
| Deliberate break: the held-visit skip in `ImportRecording` disabled | the same three tests fail again; restored |
| `EngineAPITests`, `FakeEngineKitTests`, `CoreBridgeTests`, `ChromiumEngineKitTests` | passed: four test runs of 29, 285, 343 and 170 tests |
| Scripted facade: `aBatchTheHistoryAlreadyHoldsComesBackSkippedWithItsNewestVisit` (`ChromiumImportTests`) | passed: 17 tests (16 before); pins that a `written 0, skipped N` answer keeps its `lastVisitTime`. It passes without the engine change too: the facade only carries the answer, the dedupe itself runs in the engine (smoke below) |
| `IsolationTests` | passed: 60 tests in 7 suites |

### Build

| Step | Result | Numbers |
|---|---|---|
| `nice -n 15 autoninja -C out/Spike chrome -j 4` | `The build has finished successfully.`, `FAILED:` 0 | 68 s; `libchrome_dll.dylib` relinked |
| Engine app, `xcodebuild -scheme ArktShell -configuration Engine PRODUCT_BUNDLE_IDENTIFIER=dev.arkt.Arkt.try754 -jobs 2` (`nice -n 20`, `CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-754`) | `BUILD SUCCEEDED`, `Engine framework copied: Chromium Framework.framework 156.0.8078.48` | 226 s; 522 component dylibs cloned next to the bundle (`cp -c`) |

Load average 7 to 13 while building and running (other lanes' work; nothing added).

### Real engine (`dev.arkt.Arkt.try754`, embed folder on `out/Spike`, throwaway profiles under `profiles/754-20261107/`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR` and `ARKT_DEFAULTS_SUITE` per run, `--use-mock-keychain`, `--arkt-engine-test-api`)

Counts are read-only `sqlite3` on the profile's `History` after the process exited: `urls`, `visits`, `visit_source`
rows with source 7, and (url, visit_time) pairs stored more than once.

| Run | Result | Evidence |
|---|---|---|
| Before the fix (`out/Spike` as built for the previous engine task): `history-retry` twice on one profile | FAIL, reproduced | both runs `written=40000 skipped=0`; `urls` 4000, `visits` 80000, source 7 80000, 40000 pairs twice |
| Fixed: `history-retry` twice on a fresh profile | PASS | run 1 `written=40000`; run 2 `written=0 skipped=40000 failed=0`, `latest` set; `visits` 40000, 0 pairs twice |
| Fixed: `history-shutdown`, then `history-retry` on a fresh profile | PASS | run 1: `history import: 40000 visits got no answer from the history store`, exit 0 after 6 s, `visits` 40000 already on disk; run 2: `written=0 skipped=40000 failed=0`; `visits` 40000, 0 pairs twice |
| Deliberate break: the held check in `HistoryImport::Write` disabled, rebuilt (35 s), `history-retry` on the shutdown profile | FAIL as expected | `written=40000 skipped=0`; `visits` 80000 |
| Fix restored, rebuilt (33 s), `history-retry` again | PASS | `written=0 skipped=40000`; `visits` stays 80000 (the break's copies remain, nothing new) |
| Stderr | PASS | 0 `FATAL`, `NOTREACHED`, `Check failed` lines in every run; every run exited by itself (exit 0) |

Not run: the fixture `import` phase (unchanged path; the synthetic batch covers the write), and a batch that mixes
held and new visits on the real engine (covered by the stub contract only).

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 14 |
| `arkt` commits above `156.0.8078.48` | 14 |

In sync. Facade header copies `cmp` identical.

### Cleanup

Every app run exited by itself (exit 0; no process left under the embed folder). `lsregister -u` on the app and its 8
helpers: 0 records for `dev.arkt.Arkt.try754` and 0 paths under the embed folder after. Deleted: the embed folder with
its dylib clones, derived data, the three throwaway profiles, the three defaults suites and the bundle's preferences
file, the build logs. No clipboard use. Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was
touched. `out/Spike` now holds this branch's overlay (built from `origin/main` plus this change).

## #759: gn check under //arkt

### Gate

1. Task: declare the dependencies behind the header-include errors that `gn check out/Spike '//arkt/*'` reports.
   An overlay `BUILD.gn` change is enough; no Chromium patch.
2. Facade header: unchanged. `arkt_engine_facade.mm`: unchanged.
3. `.patches`: unchanged, no patch number claimed.
4. Commands: `gn check out/Spike '//arkt/*'` before and after, `nice -n 15 autoninja -j 4 -C out/Spike chrome`, and
   the engine ABI Swift tests. Chromium disk 1.9 TiB free.

### Before

`gn check out/Spike '//arkt/*'` reported 5 errors in 2 targets (4 in `//arkt/api:embedder`, 1 in
`//arkt/browser:window`), so the count reads as 4 when only the first target is counted:

- `arkt/api/arkt_engine_facade.mm`, lines 71 to 74: `find_notification_details.h`, `find_result_observer.h`,
  `find_tab_helper.h` and `find_types.h`, from `//components/find_in_page`. The target reached it only through
  `//arkt/browser:window`, which depends privately on `//chrome/browser/ui/find_bar`.
- `arkt/browser/arkt_extension_batch_install.mm:29`: `extensions/browser/webstore_install_result.h`, from
  `//extensions/browser:webstore_installer`, reached only privately through `//chrome/browser/extensions`.

### What landed

- `//arkt/api:embedder` depends on `//components/find_in_page`.
- `//arkt/browser:window` depends on `//extensions/browser:webstore_installer`.

Neither upstream target sets `visibility`. No include line, source file or patch changed.

### After

- `gn check out/Spike '//arkt/*'`: `Header dependency check OK`.
- `gn check out/Arkt '//arkt/*'`: `Header dependency check OK`.
- Overlay link: `readlink $CR/arkt` prints the engine worktree's `engine/arkt`.
- Sync check: `.patches` 14 lines, 14 `arkt` commits, in sync.
- `cmp` of the two facade header copies: identical (header untouched).

### Build

`nice -n 15 autoninja -j 4 -C out/Spike chrome`: `The build has finished successfully.`, 58 s. GN regenerated
`build.ninja`, both target files now list the new dependency, and `libchrome_dll.dylib` was relinked.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

`swift test -j 2 --filter 'ArktEngineABITests|ChromiumEngineKitTests'`: `Test run with 33 tests in 11 suites
passed`. No Swift file changed; the run confirms the ABI targets still build and pass on this branch.

### Patch budget

Unchanged: 14 patches.

### Cleanup

No Chromium run was launched, so there is no profile, process or crash report to remove. The build log stayed
outside the repo and the Chromium disk.

## #755: an Esc the page did not use reaches the host and stops loading

Date 2026-11-08. Branch `engine/755-escape-stop` from `origin/main` (`e8380ee`). Follow-up of #614 (shell side, PRs
#756 and #760), which could not be checked on an engine build at the time.

### Gate

- Seam: no patch. The overlay already hands an Esc the page did not handle to the host
  (`ArktBrowserWindow::HandleKeyboardEvent` -> `ForwardUnhandledKeyDown` -> `unhandledKeyDown:inTab:` from a posted
  task, #313). The check adds test-only code to the self-test embedder.
- Facade header: unchanged (`cmp` identical). `.patches`: unchanged, 14 lines, 14 `arkt` commits above
  `156.0.8078.48`; the 14 exported patches match the repo files apart from `From:` lines.
- Overlay link checked before every build: `$CR/arkt` points at this worktree's `engine/arkt`.
- Build: `nice -n 15 autoninja -j 4 -C out/Spike chrome`. Chromium disk 1.9 TB free, internal 47 GB. Load average 7
  to 13 from other lanes' work; nothing added.

### Answer to the issue's open question

The week-3 note that Chromium's delayed shortcuts do not run in Arkt windows is about Cmd key equivalents (the
Views focus manager path). A bare Esc never takes that path: the overlay takes it in `HandleKeyboardEvent` once the
renderer reports it unhandled. #313's Engine app check already showed it reaching the shell (`peek unhandled Esc`).
What was not checked was the loading half: `IDC_STOP` being enabled on an Arkt window while a page loads, and the
stop taking effect. This run checks both. No key-routing fix is needed.

### What landed (self-test embedder only)

- `ArktSelfTestWindowHost` implements the optional `unhandledKeyDown:inTab:` as `ShellEngineHost` does for a tab
  that is not in a Peek: a bare Esc, the shown tab loading, the window's first responder inside that tab's container
  (the overlay names no tab, so the shell checks this too), and `validateCommand(IDC_STOP)`; then
  `executeCommand(IDC_STOP, CURRENT_TAB)`, as the shell's `.stop` reaches the engine. It logs
  `unhandledKeyDown ... inPage loading stopEnabled` and `stop sent`.
- `arkt-selftest esc [ms]`: focuses the tab's page (`-focus`), then on a later turn builds an Esc key down and key up
  and hands them to the tab's own window with `-[NSWindow sendEvent:]`, in process. The events never enter the system
  event queue, so no other window or app can receive them; the test window did not need to be key or frontmost
  (every run logged `appActive=no key=no`, with the page's `RenderWidgetHostViewCocoa` as first responder). This is
  the real AppKit key path (the page's view, the renderer, the unhandled-key return), not DevTools input.

### Smoke (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest --arkt-facade-selftest-url=<page>`, the shell's `--disable-features` list, fresh profiles under `profiles/755-20261108/`, `--use-mock-keychain`, loopback pages on `127.0.0.1:8795`)

Each page drives itself by setting its title (`state`, then `esc`, then `state`), so one launch per page runs the
check with no DevTools session. `/slow` and `/hang` answer after 30 s.

| Page | Check | Result |
|---|---|---|
| `/loading`: an `<img src=/slow>` keeps the page loading | Esc stops it | PASS: `state ... loading=yes`, `unhandledKeyDown key=53 tab=-1 inPage=yes loading=yes stopEnabled=yes`, `stop sent`, `loadingChanged loading=no`, `state ... loading=no` |
| `/uses-esc`: the same image, a focused field whose `keydown` calls `preventDefault()` on Escape | the page keeps the Esc | PASS: title `#used=1 #focus=1`, no `unhandledKeyDown` line, `state ... loading=yes` afterwards |
| `/idle`: loaded page | nothing new | PASS: `unhandledKeyDown ... loading=no stopEnabled=no`, no `stop sent`, no navigation |
| `/nav`: loaded page navigates to `/hang` (no response yet) | Esc cancels the pending navigation | PASS: `state url=.../hang loading=yes`, `unhandledKeyDown ... stopEnabled=yes`, `stop sent`, `state url=.../nav loading=no` |
| break: `ForwardUnhandledKeyDown`'s key code changed (working tree only) | `/loading` | the check fails: `esc send ... inPage=yes`, no `unhandledKeyDown`, `state ... loading=yes` afterwards |
| restored | `/loading`, `/uses-esc` | PASS again, the same lines as the first rows |

No `FATAL`, `Check failed` or `Received signal` lines in any run.

| Step | Result |
|---|---|
| Build with the self-test changes | `The build has finished successfully.`, `FAILED:` 0, 38 s |
| Break build, restore build, format-only rebuild | each finished, `FAILED:` 0; `git status` in `$CR` clean apart from the untracked `build/util/MINIBRANCH` |
| `gn check out/Spike '//arkt/*'` | fails on `main` with the include errors #759 fixes (PR #820); none in the self-test embedder |

### Not checked here

- **Peek closes on Esc on the Engine app.** The self-test host has no Peek. #313 recorded it as PASS on the Engine
  app (`peek unhandled Esc`, `peek close keyboard`), and #614 left the order unchanged: `handleUnhandledKeyDown`
  asks `peek.handleEscape` before `stopLoadingOnEscape`, and `escapeStopsLoading(peekOpen:)` yields while a Peek is
  open (InMemoryEngine tests). Not re-run on the Engine app, because that needs an app build and input into the app
  window, while this check has the same overlay path end to end.
- The shell's own `stopLoadingOnEscape` on the Engine app; the self-test host repeats its conditions.

### Patch budget

Unchanged: 14 patch files, 14 `arkt` commits, in sync. No upstream file touched.

### Cleanup

Every Chromium run stopped by exact PID (`ps -p` prints nothing for each) and the loopback server by its PID. The
throwaway profiles under `profiles/755-20261108/` and the build logs were deleted. The runs did not use the clipboard.

## #784: a dedicated address-bar navigation call

Date 2026-11-08. Branch `engine/784-address-bar-navigation` from `origin/main` (`e8380ee`). Follow-up of #577 / #770
(the maintainer decision of 2026-11-07 on `chrome://gpucrash`). Facade, overlay and shell only; no patch.

### Gate

- Seam: the facade's tab handle. Chromium takes the transition from `LoadURLParams`; no patch is needed.
- Facade header: additive. One new `ArktTabHandle` method, `navigateFromAddressBarToURL:`
  (`navigate(fromAddressBarTo:)` in Swift), next to `navigateToURL:`. Both copies `cmp` identical.
- `.patches`: unchanged, 14 lines, 14 `arkt` commits above `156.0.8078.48`, in sync before and after.
- Overlay link checked before every build: `$CR/arkt` points at this worktree's `engine/arkt`.
- Build: `nice -n 15 autoninja -j 4 -C out/Spike chrome`. Chromium disk 1.9 TB free, internal 49 GB, swap 5.6 of
  7 GB used, load average 6 to 10 from other lanes (nothing added).

### What landed

- `arkt_engine_facade.mm`: `navigateToURL:` and the new call share one `loadURL:transition:call:` (same queueing,
  unparking and closed-tab handling). The new call sends `PAGE_TRANSITION_TYPED | PAGE_TRANSITION_FROM_ADDRESS_BAR`,
  as Chrome's omnibox does.
- Browser debug URLs: `IsBrowserDebugURL` mirrors content's `IsDebugURL` and `IsAsanDebugURL`
  (`content/browser/renderer_host/debug_urls.cc`, not exported): `chrome://inducebrowsercrashforrealz`,
  `chrome://inducebrowserdcheckforrealz`, `chrome://uithreadhang`, `chrome://delayeduithreadhang`, `chrome://gpuclean`,
  `chrome://gpucrash`, `chrome://gpuhang`, the two memory-pressure URLs, and `chrome://crash/browser/...` and
  `chrome://crash/gpu/...` (`blink::ParseCrashURL`). Without `--arkt-engine-test-api` such a URL keeps `TYPED` alone,
  which is what `navigateToURL:` sends: Chromium's `HandleDebugURL` returns without running it, and no navigation
  starts. The constants come from `third_party/blink/public/common/chrome_debug_urls.h`, a public dependency of
  `//content/public/common`, so `BUILD.gn` is unchanged.
- Renderer debug URLs (`chrome://crash`, `chrome://kill`, `chrome://hang`) are not gated: Chromium runs them for any
  transition, and the contract runner already reaches `chrome://crash` through `navigateToURL:`. Nothing changes there.
- `EngineClient.navigateFromAddressBar(_:to:)`, with a default that calls `navigate(_:to:)`. ChromiumEngine calls the
  facade; InMemoryEngine records each call in `addressBarNavigations` and loads as `navigate` does; FakeEngine loads as
  `navigate` does (WebKit has no address-bar transition).
- Shell: `ShellWindowController.open(_:inNewTab:)`, the Cmd-L branch, and the private-window path
  (`openPrivately(_:fromAddressBar:)`, set by the command bar's `onOpen` in a blank or incognito window) use the new
  call. Every other navigation keeps `navigate` (pinned reset, Peek, reopened private pages, Paste and Go).
- Self-test (test-only): `arkt-selftest navigate-typed <url>`.

### What the transition changes (measured on `out/Spike`)

The issue expected typed-visit counting to differ. It does not: Chromium records the converted reload with core type
`TYPED` too, so `typed_count` grows by one for every visit, whichever call made it.

| Navigation | Page's navigation type | `history.length` | History visit (core, qualifier) | `typed_count` of `p.html` after |
|---|---|---|---|---|
| `navigate` to `p.html` from `start` | `navigate` | 2 | TYPED, none | 1 |
| `navigate` to `p.html` again | `reload` | 2 | TYPED, none | 2 |
| `navigate-typed` to `p.html` again | `navigate` | 2 | TYPED, `FROM_ADDRESS_BAR` (`0x32000001`) | 3 |
| `navigate-typed` to `q.html` | `navigate` | 3 | TYPED, `FROM_ADDRESS_BAR` | (q: 1) |

So the differences are: the same URL loads as a new navigation that replaces the entry instead of a reload; the visit
carries `FROM_ADDRESS_BAR` (which Chromium's history sync, the webNavigation API's `transitionQualifiers` and a few
other observers read); and browser debug URLs.

### Tests first

- `ChromiumAddressBarTests` (8, ChromiumEngineKitTests) against the scripted facade, whose model
  (`ScriptedAddressBar.swift`) follows the table above: the transition each call sends, same-URL reload against a new
  navigation, typed counts, the back list, the debug URL gate with and without the test API, which URLs count as
  browser debug URLs, and a call queued behind a deferred insert. Red first, before ChromiumEngine called the
  facade (the default sent plain `navigate`): 4 of the first 7 failed with 5 issues. The smoke then showed that a
  converted reload counts as typed too; the model and two tests were corrected to that (8 tests now).
- `ConformanceTests.addressBarNavigationIsItsOwnSelector` (ArktEngineABITests): the Objective-C name the facade
  implements, and the Swift name.
- `AddressBarNavigationTests` (6, ShellKitGUITests, InMemoryEngine): Cmd-L typed text, the URL on screen retyped, the
  untouched prefill (reload, no navigation), Cmd-T, a private window's Cmd-L, private pages opened in code. Before the
  shell change: compile error (no `addressBarNavigations`); with the two call sites put back to `navigate`: 3 of 6
  failed (5 assertions); restored, 6 of 6 pass.

### Swift tests (`nice -n 20`, `-j 2`, in `app/ArktShell/ShellKit`)

`swift test --filter "ChromiumEngineKitTests|ArktEngineABITests|EngineAPITests|FakeEngineKitTests|ShellUITests"`: all
passed. ChromiumEngineKitTests 178 (170 + 8), ArktEngineABITests 34 (33 + 1), EngineAPITests 285, FakeEngineKitTests
29, ShellUITests 1493. GUI, filtered to the new tests and the suites that reach the changed call sites
(`AddressBarNavigationTests`, `CommandBar*`, `PrivatePages*`, `PrivateReopenTests`, `EmptySpaceContentTests`,
`EmptyStateTests`, `SplitShortcutTests`, `SplitWindowTests`, `URLBarTests`): 275 executed, 3 skipped, 0 failures. The
full suite is left to CI.

### Build

| Step | Result | Time |
|---|---|---|
| The facade call, the gate and the self-test command | `The build has finished successfully.`, `FAILED:` 0 | 46 s |
| Break: the gate's condition made always false (`&& url.is_empty()`, working tree only) | finished, `FAILED:` 0 (a first try with `false &&` failed on `-Wunreachable-code`) | 34 s |
| Restored | finished, `FAILED:` 0 | 33 s |
| Final (header and doc comments) | finished, `FAILED:` 0; `git status` in `$CR` shows only the `build/util/MINIBRANCH` that was there before | 38 s |

`gn check out/Spike //arkt/api:embedder`: the 4 errors that were already there (the `find_in_page` includes, lines
71 to 74); none for the two new includes.

### Smoke (`out/Spike/Chromium.app`, `--no-startup-window --arkt-facade-selftest`, fresh profiles under `profiles/784-20261108/`, `--use-mock-keychain`, pages from a loopback server on `127.0.0.1:8784` that drive themselves: each load writes its `performance` navigation type and `history.length` into the title, then sets the next `arkt-selftest` command; the visits read afterwards from the run's own `Default/History` with `sqlite3` in read-only mode)

| Run | Check | Result |
|---|---|---|
| A (`--arkt-engine-test-api`) | the four navigations of the table above | as in the table: `reload` for plain `navigate`, `navigate` for the address bar, back list `[start]` after both same-URL loads |
| A | History | `p.html` visit_count 3, typed_count 3; visits `0x30000001`, `0x30000001`, `0x32000001`; `q.html` `0x32000001` |
| A | `navigate chrome://gpucrash` | nothing: no GPU exit, URL stays `q.html` |
| A | `navigate-typed chrome://gpucrash` | `GPU process exited unexpectedly: exit_code=11`, then `Reinitialized the GPU process after a crash`; the tab stays on `q.html`, its back list unchanged |
| B (no test API) | the same four navigations | the same types, lengths and History rows as A |
| B | `navigate-typed` `chrome://gpucrash`, `chrome://gpuhang`, `chrome://inducebrowsercrashforrealz`, `chrome://uithreadhang`, `chrome://crash/browser/use-after-free`, 1.5 s apart | none ran: 0 GPU exits, 0 `Received signal`, the browser kept answering (each next command arrived on time), then `close` |
| C (break, no test API) | `navigate-typed chrome://gpucrash` | `GPU process exited unexpectedly: exit_code=11`: the gate is what stops it |
| final A and B (restored build) | everything of A and B again, fresh profiles | identical results |
| D (no test API) | `navigate-typed chrome://crash` (a renderer debug URL, not gated) | the page's renderer crashed (`tabCrashed status=1 listed=yes`), the browser stayed up, as with `navigate` |

Not driven: `chrome://inducebrowsercrashforrealz` and the hang URLs with the test API (they would end or freeze the
run). Their gate is the same check as `chrome://gpucrash`'s.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 14 |
| `arkt` commits above `156.0.8078.48` | 14 |

In sync; no patch file changed. Facade header copies `cmp` identical.

### Left open

- Cmd-T and the new-tab path create the tab with its URL (`createTab(url:in:)`); Chromium loads that with its own
  transition, not `FROM_ADDRESS_BAR`. Typing in a new tab therefore still does not run a browser debug URL and does not
  carry the qualifier. Follow-up if wanted.
- A search, a history suggestion or a site search committed with Cmd-L uses the new call too (the field is the address
  field). Chrome's omnibox sends `GENERATED | FROM_ADDRESS_BAR` for a search; the facade offers only `TYPED`, which
  `navigate` already sent for searches before this change.

### Cleanup

Every Chromium run stopped by exact PID (`ps -p` prints nothing for each); the loopback server stopped by PID; the
profiles under `profiles/784-20261108/` deleted. The three GPU crashes (runs A, C and final A) and run D's renderer
crash wrote their dumps to Chromium's shared `Crashpad/pending` folder, not to the profile; those four files (matched
by time) were deleted, nothing else there. Nothing touched the clipboard (no copy or
paste command was sent). Nothing under `~/Applications/ArktTest` or `/Applications/Arkt.app` was touched.

## #806: Unity audio decoding fails (Space Waves)

Date 2026-11-09. Branch `engine/806-unity-audio` from `origin/main` (`801383c`). No overlay, patch or facade
change. The maintainer chose option 1 below the same day: `out/Arkt` now builds with `proprietary_codecs = true` and
`ffmpeg_branding = "Chrome"` (`engine/README.md`). The maintainer accepted shipping the AAC and H.264 decoders on
2026-11-09; patent licensing is the maintainer's call. Results in "Fix" below.

### Gate

- Seam: none needed to diagnose. The cause is two GN args, so a fix would be an `args.gn` change, not a patch.
- Facade header: unchanged; both copies `cmp` identical.
- `.patches`: unchanged, 15 lines, 15 `arkt` commits above `156.0.8078.48`, in sync.
- Overlay link: `$CR/arkt` points at this worktree's `engine/arkt`.
- Build: none. The existing `out/Spike` (`$CR` at `bd284c54bd`, patch 0015) was run as is. Chromium disk 1.9 TB
  free, internal 71 GB, swap 7.6 of 9 GB used at the start and at the end.
- Environment: macOS 27.0, Mac14,9 (arm64).

### Cause

Unity's web build stores every compressed `AudioClip` as AAC in an MP4 container (Unity manual, "Audio in Web":
AAC is the only compression it uses there) and decodes it in the page with `decodeAudioData`. Our builds cannot
decode AAC:

- Both `out/Spike` and `out/Arkt` leave the codec args at their defaults
  (`gn args out/<dir> --list=proprietary_codecs --short` and `--list=ffmpeg_branding`): `proprietary_codecs = false`
  (it defaults to `is_chrome_branded`) and `ffmpeg_branding = "Chromium"`.
- `decodeAudioData` runs through `media::AudioFileReader` (`content/renderer/media/audio_decoder.cc`), which is FFmpeg
  only. There is no platform-decoder path for it.
- `ffmpeg_branding = "Chromium"` compiles FFmpeg without the AAC decoder:
  `third_party/ffmpeg/chromium/config/Chromium/mac/arm64/config_components.h` has `CONFIG_AAC_DECODER 0` and
  `CONFIG_AAC_DEMUXER 0`; the `Chrome` config has both at `1`. `CONFIG_MOV_DEMUXER` is `1` in both, so the MP4 opens
  and the decode fails.
- `proprietary_codecs = false` also keeps `aac` out of FFmpeg's allow lists at run time
  (`GetAllowedAudioDecoders` in `media/ffmpeg/ffmpeg_common.cc`, `GetAllowedDemuxers` in `media/filters/ffmpeg_glue.cc`).
  A fix needs both args; either one alone still fails.

Not the cause: delivery and Content-Encoding (Vorbis decodes when served with `br` and `gzip`, AAC fails in every
form), the sandbox or audio service (WAV, MP3, Vorbis and Opus decode in the same page), and Arkt windows (the failure
is in the renderer's decoder, before any window code).

### The game's own audio

The game's `.data.br` (`files.crazygames.com/space-waves/114/Build/`, 9.1 MB, 18.4 MB after `brotli -d`) holds four
MP4 files (`ftyp mp42`, four `mp4a` tracks; no `OggS`, no `FSB5`). `ffprobe` on each: `aac`, profile `LC`, 44100 Hz,
three stereo and one mono. Four clips, matching the four `Loading FSB failed` lines.

### Reproduction (`out/Spike/Chromium.app`, fresh profiles under `arkt-artifacts/806/`, `--use-mock-keychain`)

| Run | Result |
|---|---|
| The game, `https://www.crazygames.com/game/space-waves`, 60 s, `--enable-logging=stderr --log-level=0` | the reported log exactly: `Creating WebGL 2.0 context.`, four `Decode error: EncodingError: Unable to decode audio data`, `Loading FSB failed for audio clip` for `music_race_mode`, `music`, `music_endless_mode`, `explosion`, four `Uncaught (in promise) EncodingError: Unable to decode audio data` |
| `engine/tools/audio-decode` (new, loopback `127.0.0.1:8806`) | server exit `1`. `canPlayType` empty for `audio/mp4; codecs="mp4a.40.2"` and `audio/aac`, `probably` for MP3, Vorbis, Opus. WAV, MP3, Vorbis, Opus decode; `aac.m4a`, `aac.aac` (ADTS) and `aac.m4a` with `br` and `gzip` fail with `EncodingError: Unable to decode audio data`; Vorbis with `br` and `gzip` decodes |

Comparison: Chrome for Testing 158.0.8127.18 (the copy Playwright keeps in its cache, its own bundle id, a throwaway
profile; the maintainer's own Chrome was not launched), same page: server exit `0`, every case decodes, `canPlayType`
`probably` for both AAC types. Chrome for Testing is built with `ffmpeg_branding = "Chrome"` and proprietary codecs.

Not established: whether gameplay continues without sound. The 60 s run had no user gesture, so the game never left
its start screen (the `AudioContext was not allowed to start` lines are the autoplay policy, not this bug).

### Regression fixture

`engine/tools/audio-decode/`: `server.mjs`, `index.html` and six 0.25 s fixtures (72 KB: WAV, MP3, Vorbis, Opus,
AAC in MP4, AAC in ADTS; AAC made with `afconvert`, the rest with `ffmpeg`). The server serves the fixtures as
`application/octet-stream`, optionally with `Content-Encoding` `br` or `gzip` as Unity's loader receives them, prints
the page's result and exits `0` only when every case decodes. Today it fails on the engine and passes on Chrome for
Testing; once AAC is in the build it is the check that it works. Usage is in the file's header.

### Options for the maintainer

1. `proprietary_codecs = true` and `ffmpeg_branding = "Chrome"` in both `args.gn` (and `engine/README.md`). No patch.
   Brings AAC and H.264 (and the HEVC and Dolby paths those args gate) into FFmpeg, as every major Chromium-based
   browser ships. Costs a full rebuild of `out/Arkt` (4-7 h, swap-bound, `README`) and most of `out/Spike`. Shipping
   AAC and H.264 decoders in a distributed binary raises patent licensing questions that are the maintainer's to
   weigh.
2. Platform decoders (AudioToolbox for AAC) behind `proprietary_codecs = true` with `ffmpeg_branding = "Chromium"`:
   keeps the patented decoders out of our binary, but `decodeAudioData` has no platform path today, so this is a
   patch series in `media/`, not a seam.
3. Leave it: document that AAC and H.264 do not play (Unity web games silent, many MP4 videos fail). Not a fix.

### Fix (`out/Arkt`, maintainer decision 2026-11-09)

Option 1. `$CR/out/Arkt/args.gn` gained `proprietary_codecs = true` and `ffmpeg_branding = "Chrome"`; `gn gen` and
`gn args --list` confirm both, `branding_file_path` unchanged. `.patches` unchanged.

| Step | Result |
|---|---|
| Build, run 1: `nice -n 10 autoninja -j 4 -C out/Arkt chrome`, 12:55 | 10,162 steps (incremental on the 2026-10-23 `out/Arkt`, not a full rebuild). Stopped by its `siso` PID after 2,006 steps, 0 failed: swap used reached 9.3 GB (load average 18 from other work) |
| Build, run 2: same at `-j 2`, about 13:05, guarded by `memory_pressure` (stop below 20 % free) | `The build has finished successfully.`, `exit=0`, `FAILED:` 0; framework linked 17:29. Free memory stayed 45-52 % |
| `engine/tools/audio-decode` on `out/Arkt/Arkt.app` (bundle id `dev.arkt.Arkt`, by path, fresh profile, `--use-mock-keychain`) | server exit `0`. All ten cases decode, among them `aac.m4a`, `aac.aac` and `aac.m4a` over `br` and `gzip`. `canPlayType` `probably` for `audio/mp4; codecs="mp4a.40.2"`, `audio/aac`, `video/mp4; codecs="avc1.42E01E"` and `video/mp4; codecs="avc1.42E01E, mp4a.40.2"` |
| Space Waves on the same bundle, fresh profile, `--enable-logging=stderr --log-level=0`, input sent as CDP `Input.dispatchMouseEvent` into the test page only (no OS input) | `EncodingError` 0 and `Loading FSB failed` 0 (were 4 + 4 + 4 on the old build). After the input: `IngameCurrencyEarned ... Placement: levelProgressReward_tutorial`, `Game successfully saved!`, then `Audio context resumed after 43.268 seconds.` The game runs, takes input and its audio context starts |

Not checked: listening to the output (the run was not muted; later runs should pass `--mute-audio`). Gameplay beyond the
tutorial step. `out/Spike` still has the old args and still fails the fixture; rebuild it with the same two args when it
is next rebuilt.

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 15 |
| `arkt` commits above `156.0.8078.48` | 15 |

In sync; no patch file changed. Facade header copies `cmp` identical.

### Cleanup

Every browser and loopback server stopped by exact PID (`ps -p` prints nothing for each), the fix runs included. The
throwaway profiles, the downloaded game data, the scratch fixtures and the run logs under `arkt-artifacts/806/` deleted. Nothing touched the clipboard,
the Keychain (mock keychain only) or `/Applications/Arkt.app`.

## #588: page context menu on Arkt windows (patch 0016)

Date 2026-11-12. Branch `engine/588-page-context-menu` from `main` at `4024dff5`. `$CR` branch `arkt` at `bd284c54bd`
(0001-0015) before, `f970895cc9` (0001-0016) after.

### Gate

- Why a patch: `RenderViewContextMenuMacCocoa::Show()` returns when the page's window has no top-level Views widget
  (week-2 results, seam 7; run 6 above). No delegate-level seam sits in front of it:
  - `WebContentsDelegate::HandleContextMenu`: the delegate is `Browser`, which does not override it, and the overlay
    cannot take `Browser`'s place as the delegate.
  - The `WebContentsViewDelegate` comes from the single free function `CreateWebContentsViewDelegate`
    (`chrome_web_contents_view_delegate_views_mac.mm`), reached from `ChromeContentBrowserClient`, which the overlay
    does not subclass.
  - `RenderViewContextMenuBase` offers only `*ForTesting` callbacks.
- Shape: the maintainer chose (2026-11-12) Chromium's own menu as a native `NSMenu` on the page view's own window, with
  the items whose follow-up UI is Views hidden in the same pull request (decision 3). No facade change.
- Item hiding: no overlay seam hides single items. The prefs and feature switches that remove some of them (QR code
  policy pref, Translate, Cast, printing) switch the whole feature off everywhere, so the hiding is in the same patch.
- Facade header: unchanged (`cmp` identical). `.patches`: 15 to 16, number 0016 claimed in the pull request; no open
  engine pull request touches `engine/patches`, and no earlier patch touches these files.
- Overlay link checked before each build: `$CR/arkt` points at this worktree's `engine/arkt`.
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome` in the background with a bounded wait. Chromium disk 1.9 TB
  free; internal disk 48 GB free at the start, 37 GB at the end; swap 11.7 of 12 GB at the start and 16.3 of 17.4 GB
  at the end (other lanes were building; `-j 4` as the README says above 6 GB); load average 4 to 25.

### What patch 0016 does

Two files, `render_view_context_menu_mac_cocoa.h` and `.mm` (one patch):

- `Show()`: with no Views widget (and not headless), the menu is shown on `parent_view_`'s own window, and returns
  only if that view has no window. The `MenuControllerCocoa` params (badge font, colours, radius) are built as
  `views::MenuControllerParamsForWidget` builds them, with the colours from the page's color provider; the element
  context is empty. Positioning and `ui::ShowContextMenu(..., allow_nested_tasks=true)` are upstream's, unchanged. It
  logs `ARKT: page context menu on a window without a Views widget`.
- On such a window, `IsCommandIdVisible` returns false for the commands whose follow-up UI is a Views bubble, dialog,
  side panel, popup or tab-modal sheet: QR code, send to devices, click to call, Translate and partial translate,
  every Lens and region search entry, Print, Cast, reading mode, Listen to This Page, Open Link in Split View, image
  descriptions, Live Caption, compose, the Glic and contextual-task entries, Ask Google about this page, generate
  password, passkey from another device, the password and autofill fallbacks that open a popup, and autofill
  feedback. The override reaches
  submenus, since their models use the menu as delegate. `UpdateToolkitMenuItem` keeps them hidden when an observer
  updates them later.
- Submenus left with no visible item are hidden. `MenuControllerCocoa` shows every separator, so after it builds the
  menu, the separators that would lead, trail or double up are hidden as `NSMenuItem`s, in submenus too (review of
  #904). A separator left over when an observer hides an item later is not tidied (looks only).

The engine self-test embedder gained a probe (`--arkt-facade-selftest` only): it logs a context menu's items once
validated (`ARKT selftest context menu open items=[...]`, `(off)` for disabled items) and its close, and the commands
`ctx-pick <title prefix>` and `ctx-cancel` run an item or close the menu; after the close they find no menu
(`ctx-pick "Reload" menu=none`). Scripted runs need no Accessibility access.

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port`, a fresh profile per run, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a loopback fixture page and an unpacked probe extension with one `contextMenus` item)

Right-clicks and Ctrl-clicks were sent with DevTools `Input.dispatchMouseEvent`. The machine allows no synthetic OS
input or Accessibility access for these runs, and none was granted.

Menus on the final build, as the probe logs them:

| Context | Items |
|---|---|
| Page | Back (off), Forward (off), Reload, -, Save As..., -, probe extension item, -, View Page Source, Inspect |
| Link (right-click and Ctrl-click) | Open Link in New Tab, in New Window, in Incognito Window, -, Save Link As..., Copy Link Address, Add Link to Reading List, -, Copy, Copy Link to "..." , Search Google for "...", -, probe extension item, -, Inspect, -, Speech |
| Image | Open Image in New Tab, Save Image As..., Copy Image, Copy Image Address, -, probe extension item, -, Inspect |
| Selected text | Look Up "...", -, Copy, Copy Link to "...", -, Search Google for "...", -, probe extension item, -, Inspect, -, Speech |
| Editable field | Look Up "...", -, Emoji & Symbols, -, Undo, Redo, -, Cut, Copy, Paste, Paste and Match Style, Select All, -, Search Google for "...", -, Language Settings, Writing Direction, -, probe extension item, -, Inspect, -, Speech |
| Password field | Emoji & Symbols, -, Import Passwords, -, Undo, Redo, -, Cut, Copy, Paste, Paste and Match Style, Select All, -, Writing Direction, -, probe extension item, -, Inspect |

Per item. "Live" means the item was run from the menu (`ctx-pick`) and the result checked; each risky item ran on its
own fresh instance. Clipboard items ran with the general pasteboard saved first (every item and type) and restored
after; each restore compared byte-identical.

| Item | Shown | Live | Result |
|---|---|---|---|
| Open Link in New Tab | shown | yes | background tab in the same window, opener set (`tabCreated ... active=no opener=<tab> url=.../b.html`) |
| Open Link in New Window | shown | yes | new Arkt window, tab active, opener set |
| Open Link in Incognito Window | shown | yes | new off-the-record Arkt window |
| Copy (selection) | shown | yes | pasteboard `serendipity`, plain text and HTML types |
| Copy Link Address, Copy Image Address | shown | yes | the URL on the pasteboard |
| Copy Link to Highlight | shown | yes | the page URL with a `#:~:text=` fragment |
| Copy Image | shown | yes | PNG and HTML types on the pasteboard |
| Cut (editable) | shown | yes | the field's text on the pasteboard |
| Inspect | shown | yes | DevTools opens on the page (`devtools://` target) |
| Probe extension item | shown | yes | `contextMenus.onClicked` in the extension with the menu item id, page URL and tab id |
| View Page Source, Open Image in New Tab, Search Google for | shown | yes | new tab with the expected URL (Google was not reached) |
| Language Settings | shown | yes | `chrome://settings/languages` tab |
| Reload, Back, Undo, Select All | shown | yes | no crash |
| Save As, Save Link As, Save Image As | shown | ran | no crash; the save panel was not observed (the test window is never key) |
| Add Link to Reading List | shown | ran | no crash, no UI |
| Look Up | shown | ran | no crash; the Look Up panel was not observed (the test window is never key) |
| Emoji & Symbols, Dictation, Redo, Paste, Paste and Match Style, Writing Direction, Speech, Import Passwords | shown | no | not run: they open system UI over the user's screen, use the microphone, or would paste the user's clipboard |
| Spelling suggestions, Spelling and Grammar | shown when present | no | none appeared: the renderer did not mark misspellings in the hidden, unfocused test window (with focus emulation either); the patch does not touch that path |
| Services | system | no | not observable without Accessibility access |
| Create QR Code | hidden | yes | before hiding: SIGSEGV 3 of 5 runs in `QRCodeWindowController::ShowBubble` (`ToolbarButtonProvider::From(browser)` is null); hidden: `ctx-pick` finds no such item |
| Search with Image Search (Lens) | hidden | yes | before hiding: `Check failed: contents_web_view` in `OverlayBaseController::CloseUI`, 3 of 3 runs; hidden now |
| Search This Image with Image Search (Lens) | hidden | yes | before hiding: the tab-modal was cancelled by 0015; hidden now |
| Print, Print Text Selection | hidden | yes | before hiding: Chromium's print preview as a tab-modal on the Arkt window (the #250 path, as Cmd-P today); hidden now |
| Translate, Cast, Open in Reading Mode, Listen to This Page | hidden | yes | before hiding: no crash and nothing shown; hidden now |
| Open Link in Split View | hidden | yes | before hiding: only a background tab (Chromium's split view needs the Views tab strip); hidden now |
| Send to devices, click to call, partial translate, region search, video frame Lens, image descriptions, Live Caption, compose, Glic, contextual tasks, generate password, passkey from another device, password and autofill fallbacks, autofill feedback | hidden | no | not offered on the fixture (signed out, no saved passwords, no video) |
| Picture in Picture, Open Link as another profile, Open Link With, Paste from clipboard | shown when present | no | not offered on the fixture; Picture in Picture opens Chromium's own overlay window (E2 item 6) |

Not verified here: that the menu opens exactly at a real pointer (the positioning code is upstream's and unchanged; the
DevTools clicks moved the menu linearly with the click point); Main window, Split View pane, Peek, Little Arkt and
"Open Link in New Tab lands in the right Space", which are shell surfaces the self-test cannot reach.

Nested loop: commands sent over DevTools while a menu was open (title changes, `ctx-pick`, `ctx-cancel`, script
evaluation) ran inside it, and facade batches were delivered in it: the W3-3 model (an `NSMenu` tracked from a Chromium
task with application tasks allowed).

| Step | Result |
|---|---|
| Build, first version | `The build has finished successfully.`, `FAILED:` 0, about 80 s |
| Break build (`.mm` back to `156.0.8078.48`) | finished, `FAILED:` 0, 125 s. Three right-clicks reached the page (`contextmenu` count 3); `ARKT: page context menu` lines 0, menus 0 |
| Restore build | finished, `FAILED:` 0, 85 s; the menu is back |
| Build with item hiding | finished, `FAILED:` 0, 85 s and 75 s |
| Build after the #904 review (Ask Google item, separators in submenus, probe) | finished, `FAILED:` 0, 75 s; the smoke above re-run on it: same menus, every hidden item `index=-1`, Open Link in New Tab, Copy (restored identical), Inspect and the extension item pass; FATAL, `Check failed` and signal lines 0 |
| `gn check out/Arkt "//chrome/browser/ui/cocoa:*"` and `"//arkt/*"` | `Header dependency check OK` (both) |

### Patch budget

| Source | Count |
|---|---|
| `.patches` lines | 16 |
| `arkt` commits above `156.0.8078.48` | 16 |

In sync. Export added 0016 and its `.patches` line; 0001 to 0015 byte-identical. Facade header copies `cmp` identical.

| Gate (design section 2.5) | Before | After #588 |
|---|---|---|
| Patch files | 15 | 16 |
| Seam and hook patch files | 7 | 8 |
| Upstream files outside 0001-0004 | 20 | 22 |
| Hunks in `browser_actions.cc` and `browser_commands.cc` | 4 | 4 |
| Hot-file hunks (`browser_window_features.cc`, `tab_features.cc`) | 0 | 0 |
| Widely included headers changed | 0 | 0 (`render_view_context_menu_mac_cocoa.h` has 2 includers) |

### Left open

- #905 (needs the user): the acceptance items not verifiable here, once the shell hosts this build, with real input:
  the menu at the pointer in a main window, a Split View pane, a Peek and Little Arkt; Open Link in New Tab landing in
  the right Space; spelling suggestions, Look Up and Services; the save panels.
- Hidden items to bring back natively (not preview must-haves; they stay hidden for the preview): #906 Print (Cmd-P
  still shows Chromium's preview sheet), #907 Open Link in Split View mapped to Arkt's split, #908 Translate, #909
  Cast. Reading mode has no issue yet.
- The QR code and Lens crashes stay reachable from other entry points if any calls them on an Arkt window; none is
  wired today.
- Upstream unit tests for the Mac context menu were not run.

### Cleanup

Every engine run and the loopback server stopped by exact PID (`ps -p` prints nothing for each). Seven macOS crash
reports from the test build (QR code and Lens) were moved from `DiagnosticReports` to the artifacts folder. The
throwaway profiles and run logs were deleted. Clipboard runs saved and restored the general pasteboard, every item and
type, and each restore compared identical. Nothing touched the Keychain (mock keychain only) or
`/Applications/Arkt.app`.

## #585: leave-site dialog to the shell panel (seam, no patch)

Date 2026-11-12. Branch `engine/585-beforeunload-panel` from `main` at `ceb2afd1`. `$CR` branch `arkt` unchanged at
`e483001f98` (0001-0016).

### Gate

- Seam, no patch. `TabModalDialogManager::RunBeforeUnloadDialog` hands every beforeunload dialog to
  `AppModalDialogManager`, whose native dialog factory is public (`SetNativeDialogFactory`). Chromium installs its
  Cocoa factory in `ChromeBrowserMainParts::PreProfileInit`, after the extra parts' `PreProfileInit`, so the overlay
  wraps it in `PreBrowserStart`. A leave-site dialog of a tab in an Arkt window with an embedder host becomes an
  `ArktBeforeUnloadDialog` that goes to the facade as a dialog request; every other app-modal dialog, and one the
  facade declines, goes to the saved Chromium factory.
- Facade header: additive. `ArktDialogKindBeforeUnload = 3`, and the comments that said beforeunload is not a dialog
  updated. Both copies `cmp` identical. Lanes-agree note on #585.
- `.patches` unchanged (16 lines, 16 commits above `156.0.8078.48`: in sync).
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome` (swap above 6 GB). Chromium disk 1.9 TB free throughout;
  internal disk 37 GB free at the start, 35 GB at the end; swap 15.0 of 16.4 GB at the start, 18.1 of 18.4 GB at the
  end (other lanes building); load average 8 to 62.

### What landed

- `arkt_javascript_dialog.{h,mm}`: `ArktPageDialog`, the dialog the facade reads and answers, now a base of the
  tab-modal `ArktJavaScriptDialog` and the new `ArktBeforeUnloadDialog` (an `AppModalDialogView` that owns its
  controller). The factory activates the tab when the dialog is created (as Chromium's Cocoa dialog does), so the
  prompt is always on the shown tab and `ActiveTabChanged` comes before `DialogRequested`. The answer records
  `DialogEnded` first and then reaches the controller (`OnAccept`, or `CancelTerminate` and `OnCancel`), so the shell
  sees the end before the `TabClosed` or `CloseCancelled` it brings. `CloseAppModalDialog` (the queue ending it: a
  navigation, the tab closing, shutdown) ends it without an answer. `HandleJavaScriptDialog` (the test API, DevTools)
  answers through the same path. Strings are Chromium's: "Leave site?" or "Reload site?", "Changes you made may not
  be saved.", Leave or Reload. No decline title (`cancelTitle` nil, the header allows it for this kind): Chromium's
  decline button is a plain Cancel and has no "Stay", and the shell's panel from #584 was designed as Stay / Leave, so
  the shell draws Stay (decision on #585, 2026-11-12).
- The app-modal queue keeps Chromium's accounting: one prompt at a time across all windows, a window close or a quit
  prompting its held tabs in turn, the next one only after Leave, Stay cancelling the whole close or quit.
- Facade: `ArktFacadeJavaScriptDialog` reads any `ArktPageDialog`. On a cancelled window close or quit, Chromium tells
  only the prompted tab (`BeforeUnloadFired`); the facade now reports `CloseCancelled` for every other tab that showed
  closing: the window's tabs, and for a quit the tabs of every window the quit had reached
  (`RecordWindowCloseCancelled`). A quit is told by the facade's own terminating flag (set at
  `OnClosingAllBrowsers(true)`, cleared by the cancel notification after this call), not by
  `browser_shutdown::IsTryingToQuit()`: the #911 review found that the second window's Stay missed the first window's
  tabs, and a diagnostic run observed `IsTryingToQuit()` false when that Stay was answered, cause not confirmed
  (the dialog's `CancelTerminate` resets it too).
- Swift: `ChromiumEngine+Dialogs.swift` maps the kind to `.beforeUnload`; a leave-site dialog nobody can show is answered
  Leave (#897 review); a `CloseCancelled` ends the tab's pending leave-site dialog first. `ChromiumEngine` keeps its
  own close as `TabLifecycle` (`live`, `closeHeld`) and the kept New Tab page as `NewTabPageSlot`; `.skipUnloadHandlers`
  now closes a tab whose own close is held (below). `ScriptedHarness` maps `.beforeUnload`; `ScriptedFacade` can report
  leave-site dialogs (`reportsLeaveSiteDialogs`).
- Self-test embedder: `respond <session id> leave|stay` (answers through the reported dialog object, the shell's path),
  `close-window`, `quit`, `new-tab <url>`, `new-window <url>`; `dialogRequested` logs the strings and whether the tab
  is active.

The two pinned tests (#877 finding): `skipUnloadHandlersClosesATabShowingTheWindowCloseDialog` states the intended rule.
`.skipUnloadHandlers` closes a tab whatever close holds it; the shell sends it when the row is gone (Delete Space, an
import merge) while the prompt is up, and the real facade closes under `ScopedSkipUnloadHandlers` (run 1, step 5).
`secondCloseWhileHeldDoesNothing` now covers a second honouring close only. The new
`skipUnloadHandlersClosesATabWhoseOwnCloseIsHeld` failed on `main` (5 issues: the tab stayed listed, and a Stay
afterwards would have cancelled the close of a tab with no row).

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port`, fresh profiles under `profiles/585-20261112/`, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a loopback fixture server, commands through page titles over DevTools; `hold` sets a beforeunload handler with a user gesture)

| Step | Result |
|---|---|
| 1. Client close (`close`), Stay (`respond stay`); re-run on the final build (no decline title) | `held`, `dialogRequested kind=3 active=yes title="Leave site?" message="Changes you made may not be saved." accept="Leave" cancel="(none)"`; then `dialogEnded`, `closeCancelled isClosing=no` (separate batches, in that order); `state` closing=no |
| 1. Again, Leave | `dialogEnded`, then `tabClosed reason=client` |
| 2. Held reload, Stay | `title="Reload site?" accept="Reload"`; Stay: `dialogEnded`, no `closeCancelled`, the old page stays |
| 2. Held reload, Leave | `dialogEnded`, then the page reloads (title back to the fixture's) |
| 3. Window close, two held tabs (the active one and a background one) | one prompt: `activeTabChanged` for the background tab, then its `dialogRequested`; Stay: `dialogEnded`, then `closeCancelled` for both tabs (`close cancelled with its window` for the other), the window stays |
| 3. Window close again, Leave, Leave | the second tab is activated and prompted only after the first Leave; then both `tabClosed reason=windowClosing`, `windowClosed` |
| 4. Extension `chrome.tabs.remove` on a held tab (tabs probe) | prompt; Stay: `closeCancelled`; again with Leave: `tabClosed reason=extension` |
| 5. `close skip` while the tab's own close shows its prompt | `result=closed`, `tabClosed reason=client`, then `dialogEnded`; no `closeCancelled`; a Stay sent afterwards `answered=no` |
| 6. Quit with held tabs in two windows, Stay | prompt in the first window; Stay: `closeCancelled` for both tabs of that window, `quit cancelled`, the process stays |
| 6. Quit again, Leave, Leave | the second window's tab is prompted after the first Leave; every tab `tabClosed reason=appTerminating`, both windows closed |
| 6b. Quit, held tabs in two windows, Leave in the first, Stay in the second (#911 review) | before the fix: `closeCancelled` only for the second window's tab; the first window's two tabs, which showed closing, got none. After: `closeCancelled` for all three, `quit cancelled` |
| 6c. Window close Stay with a second window open | `closeCancelled` for the closing window's two tabs only; the other window's tab gets none |
| 7. Test API `answer <id> cancel` | the same path: `leave-site dialog answered stay`, `dialogEnded`, `closeCancelled` |
| No engine-drawn dialog | the process's on-screen windows while a prompt is up: only the 900x632 host window (CoreGraphics window list) |
| `FATAL`, `Check failed`, signals | 0 in every run |

After the quit in step 6 (and in a baseline run that quit with no held tab), the self-test process stayed up after
`app terminating` and the keep-alive release; it was stopped by its PID. Not related to this change.

### Deliberate break

`UseArktBeforeUnloadDialogs()` commented out in `PreBrowserStart`, rebuilt (89 s, `FAILED:` 0): `close` on a held tab
gave `result=held` and no `dialogRequested`, and Chromium's own Cocoa alert came up (a layer-8 260x218 window of the
process); `answer cancel` dismissed it. Restored and rebuilt (74 s, `FAILED:` 0): the prompt is the shell's again, no
second window.

| Step | Result |
|---|---|
| Builds | first two stopped on compile errors (Chromium style: inline virtual bodies; a reference to a temporary), then `The build has finished successfully.`, `FAILED:` 0 on every later build |
| `gn check out/Arkt "//arkt/*"` | `Header dependency check OK` (new dependency `//chrome/browser:chrome_browser_application_mac`) |

### Patch budget

Unchanged: 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004. `.patches` 16 lines, 16
`arkt` commits: in sync. Facade header copies `cmp` identical. Design section 3 (E3a) records beforeunload as a seam.

### Left open

- The shell panel itself (Cmd-W, the window close button and Quit in the real app, Stay as the primary, Escape) needs
  the shell build that hosts this engine and real input: #910 (needs the user).
- #889 (one phase for `ArktFacadeTab`) stays its own change; this one did not need those fields reshaped.

### Cleanup

Every engine run and the fixture server stopped by exact PID (`ps -p` prints nothing for each). No crash reports from
these runs. Throwaway profiles under `profiles/585-20261112/` deleted after the runs. Nothing touched the Keychain
(mock keychain only), the clipboard or `/Applications/Arkt.app`.

## #593: pinned order, extension context menu and site access (seam, no patch)

Date 2026-11-12. Branch `engine/593-extension-pins-menu` from `main` at `2fa0783f`. `$CR` branch `arkt` unchanged at
`e483001f98` (0001-0016).

### Gate

- Seam, no patch. Pins and order are `ToolbarActionsModel`'s (`SetActionVisibility`, `MovePinnedAction`,
  `pinned_action_ids()`), stored in the profile's `extensions.pinned_extensions`, which is also what
  `chrome://extensions` reads and writes (`developerPrivate` `pinnedToToolbar`). The context menu is
  `extensions::ExtensionContextMenuModel`, built for the window's `BrowserWindowInterface`: its active tab comes from
  `TabListInterface`, and `SidePanelUI::From` is null on an Arkt window, so it needs no Views browser. On desktop
  `kExtensionsMenuAccessControl` is off (the `InitMenu` path). Site access is `PermissionsManager` and
  `SitePermissionsHelper`, reached through the model's own `ExecuteCommand`.
- Facade header: additive. `ArktExtensionSiteAccess`, `ArktExtensionContextCommand` (the shell's
  `ExtensionContextCommand` values), `ArktMenuItemKind` and the `ArktMenuItem` protocol; `ArktExtensionAction` gains
  `isPinned`, `hasOptionsPage`, `siteAccess`; `ArktEngine` gains `pinnedExtensionIDs`, `setExtensionPinned:pinned:`,
  `movePinnedExtension:toIndex:`, `extensionContextMenuForAction:inBrowser:`,
  `performExtensionContextCommand:forAction:inBrowser:`. No existing member changed. Both copies `cmp` identical.
  Gate and lanes note on #593.
- `.patches` unchanged (16 lines, 16 commits above `156.0.8078.48`: in sync).
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome` (swap above 6 GB). Chromium disk 1.9 TB free throughout;
  internal disk 34 GB free at the start and the end; swap 17.6 of 18.4 GB at the start, 17.6 at the end; load
  average 4 to 9.

### What landed

- `arkt_extension_context_menu.{h,mm}` (new): `PinnedExtensionIds`, `SetExtensionPinned` and `MovePinnedExtension`
  guard every case the model `CHECK`s or `DCHECK`s (no such action, already in that state, policy-pinned, off the
  record, not pinned) and clamp the index. `GetExtensionSiteAccess` reports the user's site access under the same
  conditions the model shows its submenu (none on a page the extension may not run on). `ArktExtensionContextMenu`
  builds the model once and emits the items design/extensions fixes: the name as a disabled header, Options...
  (enabled with an options page), Pin or Unpin, Move Up and Move Down (pinned only, each disabled at its end), the
  site access submenu with the model's enabled and checked state, Manage Extension..., Remove from Arkt... (only when
  the model offers Uninstall). Titles are the design's; the site item reads "On <host>" with the host the model
  derives (Chromium's Mac string reads "Always on <host>"). Options and site access run through the model's
  `ExecuteCommand`; Pin and the moves go straight to `ToolbarActionsModel` (the model's `TOGGLE_VISIBILITY` also
  notifies the Views element tracker). A site choice after the tab left the origin the menu was built for is
  ignored, as in Chrome.
- `ArktExtensionsMenu`: actions listed pinned first in pin order, then the rest; `OnToolbarPinnedActionsChanged`
  (an empty body until now, so a pin change never reached the shell) raises the change; observes
  `PermissionsManager`, so a site access change from `chrome://extensions` reaches the shell too; keeps the last built
  context menu per window for the shell's choice. `ShowContextMenuAsFallback` (a click on an action disabled on the
  tab) used to log "no context menu yet"; it now shows the same items as a native menu at the action's anchor, on a
  later task. There Manage and Remove run through the model (`chrome://extensions/?id=`, and the uninstall dialog
  through the 0007 hook), as #593 asks; the shell's own menu keeps running them itself.
- Facade: the listing fields, the five members, the menu item values. Swift: `ChromiumEngine+ExtensionPins.swift` maps
  them onto the `EngineExtensions` members from #591; `FacadeValues.swift` maps site access and menu items.
- Self-test embedder: `pin`, `unpin`, `move-pin <id> <index>`, `ext-menu <id>`, `ext-pick <id> <command>`; the
  actions log prints `pinned`, `options`, `siteAccess` and the pinned list.
- `engine/test-extensions/site-probe` (new): `<all_urls>` host permissions, an options page, a content script that
  marks the page, a badge counting completed loads, and the action disabled on a page whose path holds "disabled".

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --remote-debugging-port`, fresh profiles under `profiles/593-20261112/`, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a loopback fixture server, `site-probe` and `action-probe` unpacked, commands through page titles over DevTools)

| Step | Result |
|---|---|
| 1. Listing on the http page | site probe `options=1 siteAccess=3` (all sites), action probe `options=0 siteAccess=0`; `pinned []` |
| 2. `pin` site, `pin` action, `move-pin` action 0, `unpin` site, `pin` site | each change one `extensionActionsChanged`; listing and `pinned` follow: `[site,action]`, `[action,site]`, `[action]`, `[action,site]` |
| 3. `chrome://extensions` (`developerPrivate.getExtensionInfo`) | both `pinnedToToolbar=true`; site probe `hostAccess=ON_ALL_SITES` |
| 3. Unpin from `chrome://extensions` (`updateExtensionConfiguration`) | `extensionActionsChanged`, site probe `pinned=0`, `pinned [action]` |
| 4. Persistence: quit, relaunch on the same profile | `Preferences` `extensions.pinned_extensions` `[action, site]`; after relaunch `pinned [action,site]` in that order |
| 5. `ext-menu` site probe on the http page | 9 items: name (off), Options..., Unpin, Move Up, Move Down (off, last), This Can Read and Change Site Data > When You Click the Extension, On 127.0.0.1, On All Sites (checked), -, Manage Extension..., Remove from Arkt... |
| 5. `ext-menu` action probe | 8 items: no site submenu, Options... off, Move Up off (first) |
| 5. `ext-menu` on the options page (an extension page) | 8 items, no site submenu |
| 6. Site access: When You Click the Extension | `siteAccess=1`; `chrome://extensions` `ON_CLICK`; after a reload the content script did not run (`siteProbe=none`) |
| 6. On 127.0.0.1 | `siteAccess=2`; `ON_SPECIFIC_SITES` with `http://127.0.0.1:8593/*`; after a reload the script ran |
| 6. On All Sites | `siteAccess=3`; `ON_ALL_SITES` |
| 6. `ON_CLICK` set from `chrome://extensions` | `extensionActionsChanged`, `siteAccess=1` |
| 7. Stale menu: built on the http page, tab moved to a `data:` URL, then On click picked | `site access choice after the tab left http://127.0.0.1:8593`, `ignored`; `chrome://extensions` still `ON_ALL_SITES` |
| 8. Menu Move Up, Move Down, Unpin, Pin; a second Pin from the same menu | order and pins follow; the second Pin `ignored` (already pinned), no `CHECK` |
| 9. Options... | engine tab `chrome-extension://<site probe>/options.html`, active, opener the page |
| 10. Badge (`chrome.action.setBadgeText` on each load) | a reload gives 2 `extensionActionsChanged`; badge text 4; the icon PNG changes size with each count |
| 11. `run` on `disabled.html` (action `enabled=0`) | `extension context menu fallback ... 9 items`, the same items as step 5 at the action's anchor; closed by the dump timer |
| `FATAL`, `Check failed`, `DCHECK`, signals | 0 in every run |

Not exercised live: choosing Manage or Remove in the engine-drawn fallback menu. The self-test chooses menu items by
page-title commands, which the facade defers out of a nested run loop, so they arrive after the menu closed. The
shell's own menu runs Manage and Remove itself (#596, #720) and never sends them to the engine.

### Deliberate break

`OnToolbarPinnedActionsChanged` emptied again (its state on `main`), rebuilt (72 s, `FAILED:` 0): `pin` logged
`setExtensionPinned ... changed` and `pinned [site]`, and no `extensionActionsChanged` reached the shell. Restored
and rebuilt (80 s, `FAILED:` 0): the same `pin` gives `extensionActionsChanged`.

| Step | Result |
|---|---|
| Builds | first two stopped on compile errors (a header path that moved to `ui/base/models/`, an incomplete `PermissionsData`), then `The build has finished successfully.`, `FAILED:` 0 on every later build (86 s, 76 s) |
| `gn check out/Arkt "//arkt/*"` | `Header dependency check OK` (new dependency `//components/url_formatter`) |

### Patch budget

Unchanged: 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004. `.patches` 16 lines, 16
`arkt` commits: in sync. Facade header copies `cmp` identical.

### Left open

- Which of Chromium's other action menu items belong in the menu: the extension's own `chrome.contextMenus` items
  for the `action` context, Rate, View web permissions, Inspect popup (developer mode), the side panel toggle. The
  design table lists none of them; question on #593.
- Revoking access to On click marks the page as needing a reload (`TabHelper::SetReloadRequired`); Chrome shows that
  in its toolbar, Arkt shows nothing yet.
- The shell's menu and panel against this engine with real input (right-click, Ctrl-click, VoiceOver show-menu) need
  the shell build that hosts the engine.

### Cleanup

Every engine run and the fixture server stopped by exact PID (`ps -p` prints nothing for each). No crash reports from
these runs. Throwaway profiles under `profiles/593-20261112/` deleted after the runs. Nothing touched the Keychain
(mock keychain only), the clipboard or `/Applications/Arkt.app`.

## #592: post-install event instead of Chromium's dialog (seam, no patch)

Date 2026-11-13. Branch `engine/592-post-install-event` from `main` at `aaa87844`. `$CR` branch `arkt` unchanged at
`e483001f98` (0001-0016).

### Gate

- Seam, no patch. The event comes from an `ExtensionRegistryObserver` on the embedder profile
  (`OnExtensionInstalled`), as the `EngineExtensionEvent.installed` doc from #591 already describes. Chromium's
  post-install dialog reaches the overlay through the 0007 hook (`ShowDialog(gfx::NativeWindow, ...)` without a Views
  container). The hook receives no extension id and the dialog sets no internal name, so the overlay recognises it by
  its title: `IDS_EXTENSION_INSTALLED_HEADING` with the display name of an extension the window's profile has
  (`GetFixupExtensionNameForUIDisplay`, `AdjustStringForLocaleDirection`, as `ConfigurePostInstallDialogModel` builds
  it), and neither OK nor Cancel (the desktop dialog has none). It is dropped only when the matched extension is an
  install the facade reported and whose dialog has not come yet (review of #919, finding 1), so a dropped dialog
  always has its event; any other dialog model, an update's post-install dialog included, still gets the sheet.
- Facade header: additive. `ArktEngineEventKindExtensionInstalled = 31`; `ArktEngineEvent` gains `extensionID` and
  `extensionName` (nil on every other kind). No existing member changed. Both copies `cmp` identical. Gate note on
  #592.
- `.patches` unchanged (16 lines, 16 commits above `156.0.8078.48`: in sync).
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome` (swap 16.5 of 17.4 GB at the start). Chromium disk 1.9 TB
  free throughout; internal disk 44 GB free at the start; load average 5 to 7. First build 97 s, `FAILED:` 0.
- `gn check out/Arkt "//arkt/*"`: first `Can't include this header` for `crx_installer.h`; with the
  `//extensions/browser:crx_installer` dependency `Header dependency check OK`; rebuilt (16 s, `FAILED:` 0). Line
  wraps only after run 3, rebuilt (68 s, `FAILED:` 0).
- Review round (pending gate, `prompt` option): the first build stopped on the `chromium-rawptr` plugin (a raw
  `const void*` member; now an integer key), then 75 s and 82 s, `FAILED:` 0; `gn check` OK.

### What landed

- `arkt_extension_installs.{h,cc}` (new, `//arkt/browser:window`): `ReportsExtensionInstall` (a first install at
  `ManifestLocation::kInternal`, not a theme and not an app: the installs Chromium follows with its post-install
  dialog, which are the Web Store, a user's .crx and the import batch), `ExtensionInstallWatcher` (the registry
  observer) and `InstallCrxForSelfTest` (below).
- Facade: the watcher on the embedder profile, created with the download watcher; each accepted install records one
  profile-wide `ExtensionInstalled` (no tab, no browser) from inside the notification, delivered in the next batch.
- `arkt_extension_dialogs.mm`: `ShowModalDialog` drops the post-install model on an Arkt window when one of the
  extensions its title names (more than one when installed extensions share a name) is a pending reported install,
  uses that up (`TakeReportedInstall`), and logs `post-install dialog not shown <id>`. The watcher adds each reported
  id to the pending set; an update or an uninstall of that extension, or the registry's shutdown, removes it, so a
  report whose install showed no dialog (a batch) cannot later swallow an update's dialog. The model goes without a
  host, so its destroying callback (the pinned-by-default hint, which needs a `BrowserView` and which 0006 guards)
  never runs. Chromium's "has been added ... Window menu" text is gone.
- Swift: `ChromiumEngine.observeExtensions` (the protocol default delivered nothing until now, so neither `.installed`
  nor `.commandsChanged` could reach the shell from this engine) and the `.installed` mapping. Ids of an
  `installExtensionResults` batch are tagged `.browserImport` (#594): every id is tagged when the batch starts, an id
  the batch did not install loses its tag when the batch answers, and an installed id keeps it until its event
  arrives, because the facade's batch can be delivered after the import's completion has resumed. A tag is used once.
- Batch (#513): one event per installed id (the decision the acceptance item leaves to this pull request; the shell's
  toast already skips `.browserImport`).
- Self-test embedder: `install-crx <path>` installs a packed .crx the way chrome://extensions installs a dropped one
  (`CrxInstaller` with an `ExtensionInstallPrompt`, off-store allowed from the settings page); the prompt is accepted
  by a `ScopedTestDialogAutoConfirm` held until the installer finishes, so Chromium continues to
  `ExtensionInstallUI::OnInstallSuccess` and its post-install dialog, the same path a Web Store install takes. That
  path updates an installed extension without a prompt or post-install UI (`CheckUpdateFromSettingsPage`, which is why
  run 2 saw no dialog for the reinstall); `install-crx <path> prompt` allows off-store as for a test instead, so an
  update also goes through the prompt and `OnInstallSuccess`, as a Web Store update does. The auto-confirm is
  process-wide while held. The events log prints `extensionInstalled`.
- `engine/test-extensions/install-probe` (new): an action and nothing else; packed locally for each run with the
  engine's own `--pack-extension` (the .crx and key stay under `arkt-artifacts/592/`).

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest`, fresh profiles under `profiles/592-20261113/`, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a local `file://` drive page that sends commands through its title, no network)

| Run | Steps | Result |
|---|---|---|
| 1 | `--load-extension` action probe (unpacked), then `install-crx` install probe | unpacked: `extension installed ... location=8 update=0 not reported`; crx: `location=1 update=0 reported`, one batch `ExtensionActionsChanged,ExtensionInstalled`, `extensionInstalled id=bmjf... name=Arkt install probe tab=nil browser=nil`, `post-install dialog not shown bmjf...`; no `dialog sheet shown` |
| 2 | `install-crx` twice (the second is an update of the same version) | first as run 1, one `ExtensionInstalled`; second `update=1 not reported`, no dialog reached the hook, no sheet; 1 `ExtensionInstalled` in the whole run |
| 4 (pending gate) | unpacked probe, `install-crx` v1, v1 again, v2 (same key) | v1: one `ExtensionInstalled`, `post-install dialog not shown`; v1 again and v2 (`update=1 not reported`): no dialog reached the hook (the chrome://extensions update path) |
| 5 (pending gate) | as run 4, each `install-crx ... prompt` | v1: one `ExtensionInstalled`, dialog dropped; v1 again and v2: `update=1 not reported`, `dialog sheet shown` each time (Chromium's post-install text kept), no event |
| 3 (restored build) | as run 1 | the same as run 1: unpacked `not reported`, crx `reported`, one `ExtensionInstalled`, `post-install dialog not shown`, no `dialog sheet shown` |
| all | `FATAL`, `Check failed`, `DCHECK` | 0 |

Component extensions on a fresh profile fire no `OnExtensionInstalled` (none logged in any run).

Not exercised live: an install from the Chrome Web Store and a live import batch. Both need the network, which these
runs do not use; they reach the same observer (`kInternal`) and, for the Web Store, the same
`ExtensionInstallUI::OnInstallSuccess` path as the .crx. Tracked in #918 (needs the maintainer).

### Deliberate break

The title match made to fail (`+ u"BREAK"` on the expected heading), rebuilt (68 s, `FAILED:` 0): the same
`install-crx` still reported one `ExtensionInstalled`, and `dialog sheet shown` came back (Chromium's post-install text
as a sheet). Restored and rebuilt (72 s, `FAILED:` 0): run 3 above. A first attempt (`if (false && ...)`) stopped on
`-Wunreachable-code`.

Swift: releasing every tag when the batch answers (the naive rule) fails
`anEventThatLandsAfterTheBatchCompletedIsStillBrowserImport` and `aTagIsConsumedByItsEvent` (the event arrives as
`.user`); restored, all pass.

### Patch budget

Unchanged: 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004. `.patches` 16 lines, 16
`arkt` commits: in sync. Facade header copies `cmp` identical.

### Left open

- Decided on #919: first installs at `kInternal` except themes and apps report; external (sideloaded),
  policy-installed, unpacked, command-line and component installs report nothing.
- No icon (decided on #919, for now): the registry path has no decoded bitmap, `InstalledExtension.iconPNG` stays nil
  (the toast shows none).
- An update (a newer version, or the same version again) reports nothing. From chrome://extensions it shows nothing
  (Chromium's own path); through a prompt (run 5, as a Web Store update) it keeps Chromium's sheet. Decision on #919:
  updates keep the native sheet for now.
- The shell's toast against this engine with a real Web Store install needs the shell build that hosts the engine.

### Cleanup

Every engine run ended by its own `quit` command under a 60 s `alarm`; `pgrep` on each profile path prints nothing. No
crash reports from these runs. Throwaway profiles under `profiles/592-20261113*/` deleted after the runs. Nothing
touched the Keychain (mock keychain only), the clipboard or `/Applications/Arkt.app`.

## #915: the extension's own `chrome.contextMenus` items in the action context menu (seam, no patch)

Date 2026-11-13. Branch `engine/915-action-context-items` from `main` at `03018350`. `$CR` branch `arkt` unchanged at
`e483001f98` (0001-0016).

### Gate

- Seam, no patch. The items are already in the model the overlay keeps for the menu (#593):
  `ExtensionContextMenuModel::InitMenu` calls `AppendExtensionItems` right after the name, and its `ContextMenuMatcher`
  adds the extension's items for the action (`MenuItemMatchesAction`, at most `ACTION_MENU_TOP_LEVEL_LIMIT`, six, at
  the top) to the model itself, with nested `SimpleMenuModel`s for submenus. Running one through the model's
  `ExecuteCommand` reaches `MenuManager::ExecuteCommand`, which computes `checked` and `wasChecked`, adds the tab and
  dispatches `chrome.contextMenus.onClicked`.
- Facade header: additive. `ArktExtensionContextCommand` gains `CustomFirst = 1000` and `CustomLast = 2000`; the
  extension's item n (Chromium's `IDC_EXTENSIONS_CONTEXT_CUSTOM_FIRST + n`) is `1000 + n`. Chromium's 49000-based ids
  never cross the facade. No existing member changed. Both copies `cmp` identical. Gate note on #915.
- `.patches` unchanged (16 lines, 16 commits above `156.0.8078.48`: in sync).
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome` (swap 16.5 of 17.4 GB at the start, 16.6 at the end).
  Chromium disk 1.9 TB free throughout; internal disk 43 GB free; load average 5 to 7.

### What landed

- `arkt_extension_context_menu.{h,mm}`: `ArktExtensionContextMenu` walks the model's top level from its first to its
  last custom command (`ContextMenuMatcher::IsExtensionsCustomCommandId`), separators between them included, and
  recurses into submenus. Each item carries the model's state: title, type (normal, checkbox, radio, separator,
  submenu), enabled, checked; invisible items are left out, and leading, trailing and doubled separators are dropped.
  Titles go through `l10n_util::FixUpWindowsStyleLabel`, as Chrome's Mac menu controller does for every label (a
  single `&` is a mnemonic marker, `&&` a literal `&`). The items come right after the header, between two
  separators, only when the extension has any. The engine-drawn fallback menu (an action disabled on the tab) gets
  them through the same list.
- Running one (`Execute` with a custom command): it must be an enabled command item of the menu as built (submenus
  searched too), the tab active when the menu was built must still be the active one (otherwise ignored and logged:
  Chrome's model sends `onClicked` with the tab active at the time of the choice), and the model must still report
  it visible and enabled (the matcher reports a removed item as invisible). Then the model's `ExecuteCommand`.
- Facade: the argument for `performExtensionContextCommand` outside `[0, CustomLast]` becomes -1 (no command) instead
  of being clamped to `[-1, 1000]`, which would have landed on a real item. `static_assert`s tie the overlay's range
  to the header's.
- Swift: `ExtensionContextCommand.customRange`, `custom(_:)`, `isCustom(_:)`; `ChromiumEngine` passes the commands
  through unchanged (as before); `InMemoryEngine.setExtensionContextItems(_:forExtension:)` stands in for
  `chrome.contextMenus` in shell tests. The shell's `ExtensionContextMenu` already sent every command other than
  Manage and Remove to the engine.
- `engine/test-extensions/menu-probe` (new): a normal item, a checkbox, a radio group, a submenu with a separator, an
  enabled and a disabled child and a `&&` title, and a hidden item; `onClicked` records `menuItemId`,
  `parentMenuItemId`, `checked`, `wasChecked`, the tab id and URL in `storage.local` and counts them on the badge.
- Design: `design/extensions/README.md`, "The context menu", gains the row for the extension's own items.
- Separate commit (carry-over from the #919 review): `ExtensionInstallWatcher` erases its profile's pending ids in its
  destructor too, and the pending set checks `DCHECK_CURRENTLY_ON(content::BrowserThread::UI)`.

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-engine-test-api --arkt-extensions-menu-dump --remote-debugging-port`, fresh profiles under `profiles/915-20261113/`, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a loopback fixture server, `menu-probe` unpacked, `ext-menu` / `ext-pick` through page titles over DevTools, the probe driven and read through its service worker)

| Step | Result |
|---|---|
| 1. `ext-menu` on the http page | 15 items: name (off), -, Run Probe, Follow This Site (checked), - (Chromium's separator before a radio group), Mode A (checked), Mode B, -, More > [Child One, -, Save & Share, Child Off (off)], -, Options... (off), Pin, -, Manage Extension..., Remove from Arkt.... Hidden Item absent; `&&` shows as `&` |
| 1. Commands | Run Probe 1000, Follow 1001, Mode A 1002, Mode B 1003, Child One 1005, Save & Share 1007, Child Off 1008 (More is 1004, a holder) |
| 2. `ext-pick` 1000, 1001, 1003, 1005, 1007 | one `onClicked` each, tab 1126602057 (the page), in order: `run`; `follow` `checked=false wasChecked=true`; `mode-b` `checked=true wasChecked=false`; `more-one` `parentMenuItemId=more`; `more-save` |
| 2. `ext-pick` 1008 (disabled), 1004 (submenu holder), 2001 and -5 (out of range) | `not offered` / `ignored`, no `onClicked` |
| 3. `ext-menu` again | Follow unchecked, Mode B checked, Mode A unchecked |
| 2b. Checkbox picked again (run 2) | `follow` `checked=true wasChecked=false` |
| 4. Menu built on the page, a second tab made active, then `ext-pick` 1000 | `chosen after the active tab changed`, `ignored`, click count unchanged (5) |
| 5. Menu built on the second tab, `ext-pick` 1000 | `run` with tab 1126602058, `two.html` |
| 6. While closed: `update` (title, `checked: false`, `enabled: true`, `visible: true`), `remove("mode-b")`, `create("added")`; `ext-menu` | 16 items: Pause Probe, Follow unchecked, Mode A only, Child Off enabled, Hidden Item shown, Added Later; ids renumbered for the new menu |
| 7. Menu built, `added` removed, then `ext-pick` 1009 | `gone, hidden or disabled since the menu was built`, `ignored`, no `onClicked` |
| 8. `removeAll`, `ext-menu` | 6 items, the #593 layout: name, Options..., Pin, -, Manage Extension..., Remove from Arkt... |
| 9. Action disabled on the tab, `run` | `extension context menu fallback ... 15 items`: the same items as a native menu at the action's anchor, closed by the dump timer |
| Chromium's top-level cap (run 1, an older probe with six visible top-level items before More) | More and everything after it left out by the matcher, as in Chrome |
| `FATAL`, `Check failed`, `DCHECK`, signals | 0 in every run |

With these flags the self-test's `quit` left the process running after `lifetime keep-alive released`, also with no
extension loaded and no menu built (runs 4 to 7; cause not investigated, every run had `--remote-debugging-port`, which
#592's quitting runs did not); those runs were stopped by PID. Run 2 was stopped by PID while its fallback menu was still open (no dump flag): the SIGTERM watchdog wrote a
crash report, which I deleted; every later run used `--arkt-extensions-menu-dump`.

### Deliberate break

`ArktExtensionContextMenu::Execute` returned `false` for a custom command instead of calling `ExecuteCustom`, rebuilt
(71 s, `FAILED:` 0): `ext-menu` still listed 15 items, `ext-pick` 1000 and 1001 were `ignored` and the probe recorded
no click. Restored and rebuilt (68 s, `FAILED:` 0): both `ran`, two clicks with the page's tab. A first attempt
(`if (false && ...)`) stopped on `-Wunreachable-code`.

| Step | Result |
|---|---|
| Builds | 83 s, 79 s (live check tightened), break 71 s, restore 68 s, final (format only) 68 s; `FAILED:` 0 each |
| `gn check out/Arkt "//arkt/*"` | `Header dependency check OK` |

### Patch budget

Unchanged: 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004. `.patches` 16 lines, 16
`arkt` commits: in sync. Facade header copies `cmp` identical.

### Left open

- The shell's menu against this engine with real input (right-click on an action in the Extensions panel) needs the
  shell build that hosts the engine (#912).
- Icons: Chrome's action menu shows no icons for these items either; none are drawn.

### Cleanup

Every engine run and the fixture server stopped by exact PID (`ps -p` prints nothing for each). The one crash report
(run 2, SIGTERM watchdog with a native menu open) deleted. Throwaway profiles under `profiles/915-20261113/` deleted
after the runs. Nothing touched the Keychain (mock keychain only), the clipboard or `/Applications/Arkt.app`.

## #598: chrome.commands in Arkt windows (seam, no patch)

Date 2026-11-13. Branch `engine/598-extension-commands` from `main` at `6fc585e1`. `$CR` branch `arkt` unchanged
(0001-0016).

### Gate

- Seam, no patch. Chrome keeps a window's extension shortcuts in `ExtensionKeybindingRegistryViews`, which needs a
  `views::FocusManager` (week-2 grep 8). The overlay subclasses the platform-independent
  `extensions::ExtensionKeybindingRegistry` the way Android does (`extension_keybinding_registry_android.cc`): named
  commands and the action command, both from `CommandService`. Global commands stay with the profile's
  `ExtensionCommandsGlobalRegistry`, a profile-keyed service created with the profile, which does not depend on Views.
- Facade header: additive. `ArktExtensionCommand`, `ArktExtensionShortcutChange`, `ArktExtensionShortcutResult`,
  `-extensionCommands`, `-setExtensionCommandShortcut:forCommand:ofExtension:global:replacingConflict:` and event kind
  `ExtensionCommandsChanged = 32`. No existing member changed. Both copies `cmp` identical. Gate note on #598.
- `.patches` unchanged (16 lines, 16 `arkt` commits: in sync).
- Builds: `nice -n 15 autoninja -j 4 -C out/Arkt chrome`; swap 16.6 of 17.4 GB at the start, 16.9 at the end;
  Chromium disk 1.9 TB free, internal disk 43 GB free; load average 4.5 to 6.2.
- #591 review note: `kKeyTab` is in `ui::Command::ParseImpl` at the pin (`command.cc`, lines 282 and 318), so `.tab`
  is exposed. User-set global shortcuts are not limited: only `CommandService::CanAutoAssign` (a manifest suggestion)
  restricts a global one to Cmd+Shift+[0-9]. Global listening on the Mac is Carbon `RegisterEventHotKey` (and the
  media keys listener): no Accessibility permission, released when the process exits.

### What landed

- `arkt_extension_keybinding_registry.{h,mm}` (new): `ArktExtensionKeybindingRegistry`, owned by `ArktBrowserWindow`
  (made when the window first becomes key or sees a key), with `TabListInterface::From(browser)` for
  `onCommand`'s tab. A named command goes to `NotifyEventTargets`; the action command runs the window's action view
  model (`TryHandleAcceleratorPress`: the popup, or closes the open one), found through the window's
  `ExtensionsContainer`. Key window changes set it as the global registry's `registry_for_active_window`, as
  `ExtensionKeybindingRegistryViews` does. `MainMenuHasAccelerator`: whether a main-menu item (enabled or not) has the
  key as its key equivalent.
- `ArktBrowserWindow`: `PreHandleKeyboardEvent` asks the registry for a raw key down with the page focused (before the
  page, where Chrome's `BrowserView` processes extension accelerators). A local key-down monitor, installed with the
  host and removed with it, asks the registry for a key down of this window whose first responder is not inside a tab's
  page view (the sidebar, a shell field), with Command, Control or Option held. Neither path takes a key the main
  menu holds.
- `arkt_extensions_menu.mm`: the `RegisterCommand()` stub and its "not supported" warning are gone; the delegate's
  `RegisterCommand`/`UnregisterCommand` are documented no-ops (the window registry lists the action command).
- `arkt_extension_commands.{h,mm}` (new): the listing (as Chrome's shortcuts page builds it, `ConstructCommands`:
  action command first, "Activate the extension" as its description, named commands with the saved shortcut and
  scope), the setter (through `CommandService`: `RemoveKeybindingPrefs` + `AddKeybindingPref`, and
  `UpdateKeybindingPrefs` with no keystroke to clear, as `developerPrivate.updateExtensionCommand` does), and
  `ExtensionCommandsWatcher` (changes merged into one event per task; a shortcut `CommandService` assigns on its own,
  a manifest suggestion or Chrome's shortcuts page, that a main-menu item holds is cleared the way the user clears
  one, so it stays unassigned across updates). Chrome on the Mac already refuses a suggestion its own menu holds
  (`IsChromeAccelerator`), but only for items carrying Chrome command tags; Arkt's shell items do not.
- Facade: the two calls and the event; the self-test gains `ext-commands`, `ext-set` and `ext-key` (a key down made in
  this process: `-[NSWindow sendEvent:]` with the page focused, `-[NSApp postEvent:atStart:]` with the window itself
  as first responder, so the window's monitor sees it).
- Swift: `ChromiumEngine+ExtensionCommands.swift` (`extensionCommands`, `setExtensionCommandShortcut`, Chromium's
  shortcut form both ways), `.extensionCommandsChanged` becomes `.commandsChanged`. Tests:
  `ChromiumExtensionCommandTests` (new, 10 tests, every key times every modifier set round trips), two
  `ConformanceTests`.
- `engine/test-extensions/commands-probe` (new): `_execute_action` (Control+Shift+U), `run-probe` (Control+Shift+Y),
  `menu-key` (asks for Command+T), `unset` (no suggestion); records each `onCommand` with its tab and each popup
  opening in `storage.local`.
- Separate commit (carry-over from the #920 review): the `customRange` comment, `MayHaveMnemonicsAt` before the title
  fixup, the redundant condition in `CustomItems` dropped, a bounds check in `custom(_:)`, a comment that a disabled
  submenu holder's children are not reachable.

### Smoke (`out/Arkt/Arkt.app`, `--no-startup-window --arkt-facade-selftest --arkt-menu-probe=bookmarks --arkt-engine-test-api --remote-debugging-port`, fresh profiles under `profiles/598-20261113/`, `--use-mock-keychain --mute-audio`, `--host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"`, a loopback drive page, `commands-probe` packed and installed with `install-crx`, commands through page titles over DevTools, the probe read through its service worker)

`--arkt-menu-probe` puts in a shell-like main menu (Archive Tab Cmd-W, Close Window Shift-Cmd-W, New Tab Cmd-T, Quit
Cmd-Q, none with Chrome command tags). Without `=bookmarks` that probe stops on `bookmark_menu_bridge.mm:62`
(`menu_root_`; the bookmark menu bridge needs the Bookmarks item, nothing this change touches); the one crash report from that run is in `598/crash/`.

| Step | Result |
|---|---|
| Registry for the window | `tab list=yes global registry=yes` |
| 1. Install v1.0 | one `ExtensionInstalled`, one `ExtensionCommandsChanged`; `menu-key`'s Command+T `is a main-menu key; left unassigned`; listing: `_execute_action` Ctrl+Shift+U, `menu-key` none, `run-probe` Ctrl+Shift+Y, `unset` none |
| 2. Ctrl+Shift+Y, page focused / window focused | `dispatched` both; probe: two `run-probe` with the page's tab id and URL; the page's own keydown listener saw neither |
| 3. Ctrl+Shift+U (page), again (page), again (window) | popup opens (`TriggerPopup ... by_user=1`, probe records `popup`), closes (`popup closed (hidden)`), opens |
| 4. Set `run-probe` Ctrl+Shift+J | Applied, one change event; J dispatches at once (no relaunch); Y now reaches the page |
| 5. Set `unset` Ctrl+Shift+J, then with replace | Conflict naming `run-probe`; then Applied, `run-probe` none |
| 6. Alt+Command+Y; `_execute_action` global; `_execute_action` MediaPlayPause; unknown id; unknown command | NotAllowed, NotAllowed, NotAllowed, UnknownCommand, UnknownCommand |
| 7. `run-probe` Ctrl+Tab; MediaPlayPause | Applied each; Ctrl+Tab dispatches page and window focused |
| 8. `run-probe` Command+T (the shell's choice) | Applied and kept; the key is `left to the main menu`, New Tab runs (both paths) |
| 9. `run-probe` Ctrl+Shift+9 global, then cleared | Applied (registered with the global listener), cleared about 3 s later; in-window the key reached the page (a global command is the global listener's) |
| 10. Clear `run-probe`, set `unset` Ctrl+Shift+J, `menu-key` cleared at install; install v1.1 (update) | after the update: `run-probe` none, `menu-key` none, `unset` Ctrl+Shift+J; version 1.1 |
| 11. `chrome.runtime.reload()` | listing unchanged; J dispatches (page, window); U opens and closes the popup |
| 12. Relaunch on the same profile | listing unchanged; J dispatches |
| 13. Clean quit (run 6, no `--remote-debugging-port`, a `file://` page that sends its own commands): install, Ctrl+Shift+Y page and window, Ctrl+Shift+U (popup open), `quit` | Command+T cleared, two `dispatched`, popup opened; the process exited 0 after `keep-alive released (embedder flushed)` |
| `FATAL`, `Check failed`, `DCHECK`, signals | 0 in runs 1 to 6 |

A first version of the clear used `RemoveKeybindingPrefs` alone: an update then brought a cleared suggestion back
(`run-probe` Ctrl+Shift+Y after v1.1, run 1), because removal also clears the suggestion's "was assigned" mark. Chrome's
page clears through `UpdateKeybindingPrefs` with no keystroke, which keeps the mark; the engine now does the same
(step 10).

### Deliberate break

`PreHandleKeyboardEvent` asked `keyCode == 0xFFFF` instead of the registry, rebuilt (71 s, `FAILED:` 0): Ctrl+Shift+J
with the page focused reached the page (`CSKeyJ`) and dispatched nothing; with the window focused it still dispatched.
Restored and rebuilt (69 s, `FAILED:` 0): both paths dispatch, the page sees nothing. Swift: `facadeForm` wrote
"Option" for `.option`: `everyKeyAndModifierSetRoundTripsThroughChromiumsForm` (432 issues) and
`theFormListsModifiersInChromiumsOrder` failed; restored, all pass.

| Step | Result |
|---|---|
| Builds | first 68 s after one include fix, nits 68 s, clear fix 68 s, break 71 s, restore 69 s; `FAILED:` 0 each |
| `gn check out/Arkt "//arkt/*"` | `Header dependency check OK` |

### Patch budget

Unchanged: 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004. `.patches` 16 lines, 16
`arkt` commits: in sync. Facade header copies `cmp` identical.

### Left open

- Real key presses: the shell window with the engine (#912) and a physical keyboard, for the page path, the sidebar
  path, and a global shortcut pressed in another app (synthetic input cannot reach Carbon hot keys).
- The shell's Settings recorder (#597) needs shortcut handling suspended while recording, or a global shortcut fires
  while the user types it (Chrome's `developerPrivate.setShortcutHandlingSuspended`); not in `EngineExtensions` yet.
- `ArktExtensionShortcutResultGlobalShortcutTaken` is reported only when the engine's global listener refuses the
  registration (another profile of this process holds it); Carbon's non-exclusive registration does not tell whether
  another application has the same hot key.
- `MainMenuHasAccelerator` folds an upper-case letter into Shift, but not a shifted digit or symbol: a menu item
  written as "1" with Command and Shift does not match Cmd+Shift+1 (Chromium spells it "!" with Command). The shell's
  menu has no such item today (every Shift item is a letter).
- An action command in a host window whose shell has not listed the window's actions yet (no action menu) does
  nothing and logs `has no action in this window`.

### Cleanup

Every engine run and the loopback server stopped by exact PID. Throwaway profiles under `profiles/598-20261113/`
deleted after the runs. No global hot key left registered (step 9 cleared it, and the process exited). Nothing touched
the Keychain (mock keychain only), the clipboard or `/Applications/Arkt.app`.
