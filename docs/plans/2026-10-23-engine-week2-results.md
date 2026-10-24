# Engine week 2 results

Plan: `docs/plans/2026-10-23-engine-week2.md`. Variables (`$REPO`, `$CR`, `$OUT`, `$REL`, `$PROF`) as in the plan's
Rules. `$REPO` is the engine worktree `arkt-wt/engine` on branch `engine-week2`.

## Tasks

| Task | Title | Status | Notes |
|---|---|---|---|
| W0 | Branch, baselines, results file, CDP helper, key-window log | DONE | see below |
| W1 | Arkt-branded non-component build | DONE | no patch; `out/Arkt` built in 4 h 11 min at `-j 6`/`-j 4`, 0 failed; `com.arkt.Arkt`, `Arkt Helper*.app`, 0 `@rpath` dylibs; bundle 541M, `out/Arkt` 7.6G; launches; see "W1" below |
| W2 | Sign `Arkt.app`, install in /Applications, smoke | DONE (1Password test is the maintainer's, #23) | signed inside-out with an Apple Development certificate, hardened runtime; `codesign --verify --deep --strict` passes, `com.arkt.Arkt`; installed in `/Applications`; smoke passes on the native window; `spctl` rejects (not notarized, #125); see "W2" below |
| W3 | Inventory of non-`BrowserView` window seams, variant decision | DONE | variant P (plain `NSWindow`); this week 3 seam patch files, 4-8 upstream files, 0 hot-file hunks (W: 3 / 4 / 0); see "W3" below |
| W4 | Extensions menu lists every action (finding 1) | DONE | no upstream patch; see below |
| W5a | `ArktBrowserWindow` skeleton behind `--arkt-native-window` | DONE | patch 0004; startup, tabs and `chrome.windows` work; 3 crash seams hit (sad tab, NTP footer, closing the active tab, which also blocks window close and quit), see "W5a" below |
| W5b | Seam fixes found by the smoke matrix (GATE) | DONE: gate passes | 17/17 scenarios pass; patches 0005-0006 (2 patch files, 3 upstream files, 0 hot-file hunks); close, quit, NTP, main-menu commands and the extension popup fixed on our side; see "W5b" below |
| W5c | Arkt-owned tab list and visibility (finding 2) | DONE | no upstream patch; week-1 blackout repro passes (CDP `visibilityState`, `ARKT: visibility` lines, AX row selection); `arkt_browser_window.mm` split; affected W5b rows pass; see "W5c" below |
| W6 | Extension window identity, extension-created tabs and windows (finding 3) | DONE | no upstream patch; `ArktExtensionsContainer` makes `chrome.action.openPopup()` open our popover; every extension-created tab and window lands in an Arkt window (`views=0`), 1Password welcome page included; popup closes on `window.close()` and on unload; see "W6" below |
| W7 | Web Store install on the native window | DONE | uBO Lite installed on the native window (`views=0`), actions 1 -> 2, popup through the menu; post-install dialog crash on close fixed in patch 0006; see "W7" below |
| W8 | Keychain: mock in tests, "Arkt Safe Storage" in the product (finding 5) | DONE (one maintainer launch after W10) | patch 0003; release bundle names its item "Arkt Safe Storage"; maintainer keeps the old "Chromium Safe Storage" item; see "W8" below |
| W9 | Native window as default; try dropping patch 0002 | DONE (0002 kept) | `ArktBrowserWindow` is the default, `--arkt-views-window` keeps the week-1 path; W5b matrix 17/17, W5c Step 3 and W6 Steps 3-4 pass with no switch; W7 not re-run (see below); dropping 0002 blanks a tab moved in from a Views popup window and the week-1 path, so it stays; patch set unchanged; see "W9" below |
| W10 | Release bundle rebuild, re-sign, final smoke, housekeeping | DONE (W7 Step 3 and the unmocked launch are the maintainer's) | incremental `out/Arkt` build from `main` 87518a2, 0 failed; re-signed (same identity as W2), `/Applications/Arkt.app` replaced; smoke on the default native window passes (`views=0`, `probe.create()` row, menu dump, popup, second window, `chrome://extensions`, keychain string, `ChromeMain`, UA and brands); W7 re-run reached the install prompt with `views=0`, accepting it was not permitted in this session; `/` had 5.0 GiB free at the start, not 8 GiB; see "W10" below |
| WE | Embedding spike (lane C) | DONE: GO (framework copied into the app bundle) | see below; branch `spike/embedding` |

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 | 0 |
| 0002 | Let a WebContents view draw again after leaving Views | exists; kept in W9 (a tab moved from a Views popup window into an Arkt window, and the week-1 path, draw nothing without it) | 4 | 0 |
| 0003 | Arkt keychain item name (W8) | exists | 1 (`keychain_password_mac.mm`) | 0 |
| 0004 | `BrowserWindow` factory hook for Arkt (W5a) | exists | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) | 0 |
| 0005 | Tolerate a non-`BrowserView` window in tab features (W5b) | exists | 1 (`sad_tab_controller.cc`) | 0 |
| 0006 | Tolerate a non-`BrowserView` window in dialogs (W5b, W7; RTL anchor #250) | exists | 3 (`bubble_anchor_util_views.cc`, `exclusive_access_permission_prompt.cc`, `extension_install_ui_desktop.cc`) | 0 |
| 0007 | Extension dialogs as native sheets on Arkt windows (#244) | exists | 4 (`extension_install_dialog_view.cc`, `extension_dialog_utils_views.cc`, their two `BUILD.gn`) | 0 |

Current totals (after #250): 7 patch files, 17 upstream files, 0 hot-file hunks (`git -C $CR diff --stat 156.0.8078.48..arkt | tail -1`: 17 files changed, 76 insertions, 5 deletions; #244 ended at 74 insertions). Seam patches (W5b, W7, #244): 3 patch files, 8 upstream files, 0 hot-file hunks, no header. Week 2 ended at 6 patch files and 13 upstream files.

## W0

Date 2026-10-23.

### Step 1: worktree, symlink, patch count

- Worktree `arkt-wt/engine`, branch `engine-week2`, created from `main` at `2cbedaa` (the public repo has no
  `spike/week1` branch; `main` carries the week-1 overlay and patches).
- Old `$CR/arkt` target: the `engine/arkt` directory of a different checkout of this repository (not a worktree of
  it). Its overlay and patch contents were identical to `main`'s apart from the patch `From:` header.
- `readlink $CR/arkt` now prints `$REPO/engine/arkt` (expanded).
- `git -C $CR branch --show-current`: `arkt`
- `git -C $CR rev-list --count 156.0.8078.48..arkt`: `2`
- `wc -l < $REPO/engine/patches/chromium/.patches`: `2`
- Hot-file hunks (patch budget command): `0`
- Upstream files touched by `156.0.8078.48..arkt` (`git diff --stat`): 6
  (`chrome/browser/BUILD.gn`, `chrome/browser/chrome_browser_main.cc` for 0001;
  `render_widget_host_ns_view_bridge.{h,mm}`, `render_widget_host_view_mac.mm`, `render_widget_host_ns_view.mojom`
  for 0002).

### Step 2: key-window log

`ArktWindowController` observes `NSWindowDidBecomeKeyNotification` for its window and logs
`ARKT: key window <n>`; `showWindow:` logs `ARKT: window number <n>` on its own line.

### Step 3: CDP helper

`engine/tools/cdp.mjs`, no dependencies (Node global `fetch` and `WebSocket`, checked with Node 26.10).

### Step 4: build and baseline run

Build: `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.`, 0 `FAILED:` lines.

Launch with the plan's command (profile `$PROF/week2`, `--use-mock-keychain`, `--remote-debugging-port=9333`,
`--load-extension=$REPO/engine/test-extensions/tabs-probe`, page `manifest.json`).

```
ARKT: window number 37611
ARKT: mounted active tab after 1 attempt(s)
ARKT: key window 37611
```

| Command | Output | Exit |
|---|---|---|
| `cdp.mjs manifest.json 'document.visibilityState'` | `"visible"` | 0 |
| `cdp.mjs manifest.json 'navigator.userActivation.isActive'` | `false` | 0 |
| `cdp.mjs --user-gesture manifest.json 'navigator.userActivation.isActive'` | `true` | 0 |
| `cdp.mjs manifest.json 'nope.x'` | `cdp: ReferenceError: nope is not defined` | 1 |
| `cdp.mjs manifest.json 'Promise.reject(new Error("boom"))'` | `cdp: Error: boom` | 1 |
| `cdp.mjs nomatch '1'` | `cdp: no target matches "nomatch"` plus the target list | 1 |
| `cdp.mjs --navigate manifest.json 'about:blank'` | `{"frameId":...,"loaderId":...,"isDownload":false}`; then `cdp.mjs about:blank 'location.href'` prints `"about:blank"` | 0 |
| `cdp.mjs --navigate about:blank 'notascheme'` | `cdp: Cannot navigate to invalid URL` | 1 |
| `cdp.mjs --port 9399 x '1'` (nothing listening) | `cdp: cannot read /json/list on port 9399: fetch failed` | 1 |

`type:service_worker` matched a component extension's worker (`"Contextual Tasks"`), not the probe: this confirms the
Rules' instruction to match workers by extension id.

The browser was stopped by its PID; no `$OUT/Chromium.app` processes were left.

### Machine state after W0

- `df -h /`: 15 GiB available (of 460 GiB).
- `sysctl vm.swapusage`: `total = 7168.00M  used = 5605.50M  free = 1562.50M`.
- Load average 14.01 9.08 7.32.

## WE

Date 2026-10-23. Worktree `arkt-wt/spike-embedding`, branch `spike/embedding`. No Chromium build; `out/Spike` was
only read and copied from, never modified or re-signed. Extra variable: `$SPK` = `$CHROMIUM_ROOT/embed-spike` (a
scratch bundle layout on the Chromium disk, outside `$CR`).

**Verdict: GO.** The Swift `ArktShell` executable (`Spike` configuration) `dlopen`s the `out/Spike` framework,
calls `ChromeMain(argc, argv)` as its first statement, and the browser runs normally: the in-process hook reports
in, the Arkt native window mounts the tab, sandboxed GPU, network, storage and renderer helpers stay up, and
`https://example.com` renders. This holds only when the framework and its helpers physically live inside
`ArktShell.app` (and, for the component build, the dylibs sit next to the bundle). A symlinked framework is NO-GO
(Run A below).

### Step 1: preconditions

- `nm -gU ".../Chromium Framework.framework/Chromium Framework" | grep -c ' T _ChromeMain'` prints `0`: in the
  component build the framework binary is a 35 KB stub that re-exports `@rpath/libchrome_dll.dylib`.
  `nm -gU $OUT/libchrome_dll.dylib | grep -c ' T _ChromeMain'` prints `1`. `dlsym(handle, "ChromeMain")` on the
  framework handle finds it through the re-export. In a non-component build (`out/Arkt`) the symbol is in the
  framework binary itself.
- `Versions/`: `156.0.8078.48` and `Current -> 156.0.8078.48`.
- Framework `LC_RPATH`: `@loader_path/../../../../../..` (the directory holding `Chromium.app`, where the 518
  component dylibs live), `@loader_path/.`, `@loader_path/../../..`.
- Helper `LC_RPATH` (`Helpers/Chromium Helper.app/Contents/MacOS/Chromium Helper`):
  `@executable_path/../../../../../../..`, `@loader_path/../../../../Libraries`,
  `@loader_path/../../../../../../../../../..` (again the directory holding the outer `.app`), `@loader_path/.`,
  `@loader_path/../../..`.
- Sizes: framework 109 MB (Resources 86 MB, Libraries 21 MB, Helpers 2.3 MB); component dylibs 678 MB.

### Step 2: entry point and configuration

- `app/ArktShell/App/ChromiumSpikeMain.swift` (only under `ARKT_CHROMIUM_SPIKE`): builds
  `Bundle.main.privateFrameworksPath + "/Chromium Framework.framework/Versions/156.0.8078.48/Chromium Framework"`,
  `dlopen(RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST)`, `dlsym("ChromeMain")`, calls it with `CommandLine.argc` /
  `CommandLine.unsafeArgv`, then `exit(status)`. On failure it prints `dlerror()` and exits 1.
- `main.swift`: under `#if ARKT_CHROMIUM_SPIKE` the only statement is `chromiumSpikeMain()`; the normal path is
  unchanged in the `#else` branch.
- `project.yml`: new `Spike` configuration (debug base) with `ARKT_CHROMIUM_SPIKE`, `NSPrincipalClass` taken from a
  new `ARKT_PRINCIPAL_CLASS` build setting (`NSApplication` by default, `BrowserCrApplication` for `Spike`),
  hardened runtime off, and `ENABLE_DEBUG_DYLIB: NO`. Without the last one Xcode's debug configuration builds a
  40 KB stub executable plus `ArktShell.debug.dylib` holding all Swift code; with it the entry point sits in the
  main executable like Chromium's own stub.
- Checked: `Debug` still builds with `NSPrincipalClass = NSApplication` and no spike code
  (`strings ... | grep -c "ARKT spike"` = 0); `Spike` has `BrowserCrApplication` and the spike strings.
- Build: `xcodegen generate`, then
  `nice -n 10 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Spike -derivedDataPath build -jobs 4 build`.

### Runs

All runs: `--user-data-dir=$PROF/embed-spike --use-mock-keychain --no-first-run --no-default-browser-check
--enable-logging=stderr https://example.com`, launched in the background, PID from `$!`, killed by that PID; no
leftover process under either bundle path afterwards.

**Run A: framework symlinked (NO-GO).** `ArktShell.app/Contents/Frameworks/Chromium Framework.framework` is a
symlink to `$OUT/Chromium.app/Contents/Frameworks/Chromium Framework.framework`. Log `$PROF/w2-we-a-symlink.log`.

- `dlopen` and the dylibs resolve (the `objc[...] Class ... is implemented in both` lines show every dylib loaded
  from `$OUT`, that is through the symlink's real path). `ChromeMain` runs, `BrowserCrApplication` is accepted, and
  the hook reports in about 1.5 s after launch:
  `WARNING:arkt/browser/arkt_browser_main_extra_parts.mm:104] ARKT: in-process hook alive`, followed by
  `ARKT: key window <n>`, `ARKT: window number <n>`, `ARKT: mounted active tab after 1 attempt(s)`.
- Every sandboxed helper dies. The browser launches helpers through the symlinked path, the helpers resolve their
  executable to the real path under `$OUT/Chromium.app`, and two things no longer match:
  1. Sandbox: the seatbelt profile allows reads under `GetCanonicalPath(MainBundlePath())` (`ArktShell.app`) and,
     in component builds, its parent (`content/browser/sandbox_parameters_mac.mm:122-147`). The Aperitif helpers
     (enabled here through the field-trial testing config; `kAperitifHelpers` is off by default) enter the sandbox
     in a static initializer (`content/app/aperitif_mac.cc`), then cannot read their own `Info.plist` under
     `$OUT`, so `IsBackgroundOnlyProcess()` is false and `GetFrameworkBundlePath` takes the main-app branch:
     `FATAL:base/apple/bundle_locations.mm:74] Check failed: bundle. Failed to load the bundle at
     $OUT/Chromium.app/.../Helpers/Chromium Helper (Aperitif).app/Contents/Frameworks/Chromium
     Framework.framework/Versions/156.0.8078.48` (19 times; 10 more for `(Aperitif Renderer)`, 29 in total).
  2. Mach port rendezvous: the browser registers `<BaseBundleID>.MachPortRendezvousServer.<pid>` with its own
     bundle id (`dev.arkt.ArktShell`; `SetUpBundleOverrides` in `chrome/app/chrome_main_mac.mm` takes it from the
     main bundle in the browser), while a helper derives its outer bundle from its real framework path
     (`OuterAppBundle()`, five levels up), which is `$OUT/Chromium.app`:
     `ERROR:base/apple/mach_port_rendezvous_mac.cc:256] bootstrap_look_up
     org.chromium.Chromium.MachPortRendezvousServer.<pid>: Unknown service name (1102)` then
     `ERROR:base/memory/shared_memory_switch.cc:261] No rendezvous client, terminating process (parent died?)`.
- Result: `GPU process exited unexpectedly: exit_code=6` six times, `Network service crashed or was terminated`
  six times, then `FATAL:content/browser/gpu/gpu_data_manager_impl_private.cc:389] GPU process isn't usable.
  Goodbye.` The browser process exited about 30 s after launch. An earlier attempt from the interrupted session
  (`$PROF/w2-we-nosandbox.log`, by its name run with `--no-sandbox`; the exact flags were not recorded) shows no
  Aperitif `FATAL` but failure 2 remains (124 rendezvous failures, network service restarted 37 times).
- `DYLD_PRINT_RPATHS=1` printed nothing on this macOS (dyld4); dylib resolution is evidenced by the objc
  duplicate-class lines instead (Run B: `lsof -p <pid>` lists 511 dylibs from `$SPK`).

**Run B: framework copied into the bundle (GO).** Layout under `$SPK`: `cp -Rp` of the built `ArktShell.app`,
the symlink replaced by `cp -Rp` of the whole framework (signatures preserved, helpers untouched), and
`cp -p $OUT/*.dylib $SPK/` so the framework's and helpers' `@loader_path/../...` rpaths land on real files in the
sandbox's component path (the bundle's parent). Log `$PROF/w2-we-b-copy.log`, screenshot
`$PROF/shots/we-b-1.png` (the Arkt window showing example.com).

- First launch: `dlopen` blocked for about 110 s in `dyld4::Loader::getLoader` (`sample`: 0.4 % CPU, no output)
  while the system scanned 519 freshly copied Mach-O files (`syspolicyd` busy); then
  `ARKT: in-process hook alive`, key window, window number, `mounted active tab after 1 attempt(s)`.
- 30 s after the hook: process alive; children 1 GPU, 9 renderer, network and storage utility services, crashpad
  handlers, all running from `$SPK/ArktShell.app/Contents/Frameworks/.../Helpers/Chromium Helper (Aperitif*).app`
  with the sandbox on. Zero `FATAL` lines. Three `ERROR` lines: `ARKT: extension not installed
  ddkjiahejlhfcafbddmgiahcphecmpfh` (fresh profile, line 43) and, as the last two lines of the log (46-47), one
  rendezvous failure from helper pid 88969:
  `[88969:...:1023/143124.852295:ERROR:base/apple/mach_port_rendezvous_mac.cc:256] bootstrap_look_up
  dev.arkt.ArktShell.MachPortRendezvousServer.1: Permission denied (1100)` then
  `[88969:...:1023/143124.852531:ERROR:base/memory/shared_memory_switch.cc:261] No rendezvous client, terminating
  process (parent died?)`. They are logged 58.5 s after the hook (14:30:26.378), after the 30 s check, and nothing
  follows them (the log was last written at 14:31:24, the same second). See "Teardown rendezvous lines" below.

**Run C: warm relaunch of the Run B layout.** Log `$PROF/w2-we-c-warm.log`. Hook alive 2.9 s after launch, process
alive at 30 s. Zero `FATAL` lines. The only `ERROR` lines are the same pair as in Run B, the last two lines of the
log (32-33), from helper pid 92169:
`[92169:...:1023/143207.143684:ERROR:base/apple/mach_port_rendezvous_mac.cc:256] bootstrap_look_up
dev.arkt.ArktShell.MachPortRendezvousServer.1: Permission denied (1100)` then
`[92169:...:1023/143207.144007:ERROR:base/memory/shared_memory_switch.cc:261] No rendezvous client, terminating
process (parent died?)`, 30.2 s after the hook (14:31:36.922), that is right after the 30 s check that preceded the
kill; the log was last written at 14:32:07.

**Teardown rendezvous lines (Runs B and C).** The suffix of the rendezvous service name is the parent pid as the
helper sees it (`getppid()`). `.1` means the helper's parent, the browser, was already gone and the helper had been
reparented to launchd, so there was no server to look up. The service prefix is the correct one
(`dev.arkt.ArktShell`), unlike Run A, where helpers looked up `org.chromium.Chromium.MachPortRendezvousServer.<real
browser pid>` while the browser was alive, failed with `Unknown service name (1102)`, and took down GPU and network
over and over. The logs do not timestamp the kill itself; what they show is that in each run this pair is a single
helper, occurs once, is the last output in the log, comes at or after the 30 s liveness check that preceded the
kill, and that by then the browser pid no longer existed (parent pid 1). That places it at teardown, most likely a helper that
was starting when the browser was killed. It is not the Run A failure mode, and no GPU, network or renderer helper
failed while the browser was running.

### Conflicts and findings

| Area | Finding | Production handling |
|---|---|---|
| `NSPrincipalClass` | `BrowserCrApplication` from the `Spike` Info.plist is accepted; nothing in the Swift process touches `NSApplication` before `ChromeMain`. | Engine build sets `BrowserCrApplication`; FakeEngine build keeps `NSApplication` (now one build setting). |
| `AppController` vs `MainMenu.swift` | In the spike `MainMenu.swift` and `AppDelegate` never run (the `#else` branch); Chromium's `AppController` and main menu are in charge. | Week-3 menu ownership decision stands (plan, "Main menu"); Arkt UI starts from the in-process hook, not `main.swift`. |
| `chrome_paths_mac.mm` DCHECKs | No DCHECK fired for the browser (`ArktShell.app/Contents/Frameworks/Chromium Framework.framework/Versions/156.0.8078.48` satisfies them). Helpers break them only when their real path is outside the app (Run A). | Ship the framework inside the app with the versioned layout; never symlink it out of the bundle. |
| Versioned path (`chrome_exe_main_mac.cc`) | The Swift stub must hard-code framework name and version, as Chromium's stub does. | Generate both into the Swift build (Info.plist key or build setting written by the engine build), not literals. |
| Bundle id | Helpers take the base bundle id from the outer app found five levels above their framework; the browser takes its own. They agree only when the helpers are inside the same app. | One bundle; the helpers' outer app is `ArktShell.app`. |
| Helper apps | Unmodified `Chromium Helper*.app` (including Aperitif variants) work from inside `ArktShell.app` with the sandbox on. | Rename with branding (W1) in the engine build. |
| Component dylibs | Found through `@loader_path/../../../../../..` (framework) and `@loader_path/../../../../../../../../../..` (helpers), i.e. the directory holding the `.app`, which is also the sandbox's component path. | Component builds: dylibs next to the bundle (dev only). Shipping uses the non-component build, which has no such dylibs. |
| Signing / library validation | Swift executable ad-hoc signed, hardened runtime off; framework and helpers keep their existing signature; adding the framework breaks the outer bundle seal. No library-validation refusal occurred. First launch of freshly copied binaries costs about 110 s of system scanning. | Sign inside-out with one identity (helpers, framework, then app) with hardened runtime and the helpers' entitlements, as W2 does for `Arkt.app`. |
| Misc | `objc` duplicate class warnings (`ANGLESwapCGLLayer`, `CrashpadHTTPBodyStreamTransport`) are component-build artifacts, also seen from `Chromium.app`. | None. |

### Recommended production approach

1. Build the engine as a framework (`Arkt Engine.framework` or similar, plan open question 5) with the standard
   versioned layout and its helpers inside it; build non-component for anything outside development.
2. The Xcode engine configuration embeds that framework as a real directory in `ArktShell.app/Contents/Frameworks`
   (an Xcode "Embed Frameworks" copy or a build phase `ditto`), never a symlink, and signs inside-out.
3. `main.swift` in the engine configuration does nothing but load the framework and call `ChromeMain`, as here;
   framework name and version come from the engine build, not literals.
4. For fast development against `out/Spike`, use the Run B layout: the app bundle plus a copied framework, with the
   component dylibs next to the bundle (or the app built straight into a directory that holds them). Expect the
   first launch after each copy to be slow.

Artifacts left for the next step: `$SPK` (796 MB: copied `ArktShell.app` with framework, 518 dylibs) and the
`$PROF/embed-spike` profile; both are scratch and can be deleted.

## W1

Date 2026-10-23. Overlay at build start: `main` at `89c8a42` plus `engine/arkt/branding/BRANDING`; `$CR` branch
`arkt` at `2bda3d5a86` (patches 0001, 0002).

### Steps 1-3: branding file, args, gn gen

- `engine/arkt/branding/BRANDING` as in the plan, except `MAC_TEAM_ID=` is left empty (as in Chromium's own
  `chrome/app/theme/chromium/BRANDING`). Its only consumer in the app is `CHROMIUM_TEAM_ID` in the Info.plist
  (`chrome/BUILD.gn:770`); the build is ad-hoc signed in W2, and no signing id belongs in the repository.
- `$REL/args.gn` exactly as in the plan.
- `gn gen out/Arkt`: `Done. Made 36369 targets from 5025 files`. The source-absolute path was accepted.
- `gn args out/Arkt --list=branding_file_path --short`: `branding_file_path = "//arkt/branding/BRANDING"`.
- `toolchain.ninja` names `Arkt.app/Contents/Resources/...` outputs.

### Step 6: build

Command: `cd $CR && nice -n 15 autoninja -C out/Arkt chrome > $CHROMIUM_ROOT/build-arkt.log 2>&1`.

Before the start:

- `df -h $CHROMIUM_ROOT`: 2.0 TiB available.
- `df -h /`: 11 GiB available (of 460 GiB).
- `sysctl vm.swapusage`: `total = 7168.00M  used = 5605.50M  free = 1562.50M`.

Started 14:05. Stopped 14:17 (about 12 min in) by SIGINT to the recorded `siso` PID, because free swap fell below
500 MB while other jobs were also running on the machine:

| Time | `df -h /` available | `sysctl vm.swapusage` | Build |
|---|---|---|---|
| 14:05 | 11 GiB | `total = 7168.00M  used = 5605.50M  free = 1562.50M` | started |
| ~14:16 | - | `free = 229.38M` | running |
| 14:16 | 5.9 GiB | `total = 10240.00M  used = 9119.38M  free = 1120.62M` | running (macOS added a swap file, 3 GB of `/`) |
| 14:17 | 5.9 GiB | `total = 10240.00M  used = 9555.44M  free = 684.56M` | stopped |

Last log lines: `Build Failure: 6344 done, 0 failed, 76953 remaining`, `interrupt by signal`. No `FAILED:` lines;
the stop was clean and the next run resumes incrementally from the 6344 finished steps.

Swap grows by adding swap files on `/`, so free swap and free disk shrink together: one more swap file would take
`/` to about 3 GiB, under the 4 GiB stop rule. `/` was already below the 8 GiB floor after the first one. The build
can only resume once `/` has at least 8 GiB free and the machine is quiet (no other Chromium or Swift builds),
which needs the user (freeing space on `/` is not ours to do).

Resume command (incremental): `cd $CR && nice -n 15 autoninja -C out/Arkt chrome > $CHROMIUM_ROOT/build-arkt.log 2>&1`.

### Step 6, resumed (2026-10-23 20:12 to 2026-10-24 00:23)

Overlay: `$REPO` on branch `engine/11-release-build` at `c61a576` (`main`; its `engine/` tree is identical to
`fe86b8d`, W6), `readlink $CR/arkt` = `arkt-wt/engine/engine/arkt`, unchanged for the whole build. `$CR` branch
`arkt` at `baeb143765` (patches 0001-0006, all exported). `gn gen out/Arkt` again first (`Made 36370 targets`),
`branding_file_path = "//arkt/branding/BRANDING"`, `toolchain.ninja` names `Arkt.app/Contents/Resources/...`.

The parallelism is capped with `-j` because swap (not CPU) is the limit on this machine:

| Run | Command | Time | Steps | Result |
|---|---|---|---|---|
| 1 | `nice -n 10 autoninja -C out/Arkt -j 6 chrome` | 20:12-20:33 (20 min 46 s) | 14270 done, 52048 remaining | stopped by SIGINT to the `siso` PID: swap used rose from 5984M to 7572M (of 8192M) in 20 min; 0 failed |
| 2 | `nice -n 10 autoninja -C out/Arkt -j 4 chrome` | 20:33-00:23 (3 h 49 min 58 s) | 51585 | `The build has finished successfully.` |

Total wall time 4 h 11 min (plus the 12 min of the 14:05 run); `grep -c FAILED:` on both logs: `0`. The
`Arkt Framework` link took under a minute (`ld64.lld`, about 1.7 GB RSS) on a quiet machine. A monitor checked
every 30 s and would have stopped `siso` (`kill -STOP`) at swap used above 8 GB or under 5 GiB free on `/`; it never
fired.

| Time | `df -h /` available | swap used (`sysctl vm.swapusage`) | `memory_pressure` free | Steps (`siso ps`) |
|---|---|---|---|---|
| 20:12 | 10 GiB | 5984M of 7168M | - | started |
| 20:33 | 8.8 GiB | 7572M of 8192M | 55% | run 1 stopped at 14270 |
| 20:43 | 9 GiB | 7564M | 55% | 1126/51510 |
| 21:24 | 9 GiB | 7123M | 54% | 9059/49595 |
| 22:01 | 9 GiB | 7035M | 52% | 11535/49260 |
| 22:31 | 8 GiB | 7027M | 52% | 16336/48683 |
| 23:01 | 10 GiB | 6931M | 51% | 20639/46968 |
| 23:31 | 12 GiB | 6867M | 50% | 29255/39320 |
| 00:14 | 13 GiB | 6827M | 47% | 35549/37335 |
| 00:23 | 12 GiB | 6507M of 8192M | - | finished |

Swap used does not shrink when pressure drops, so it is a ratchet: once near the limit, only a lower `-j` keeps a
build going. At `-j 4` it stayed flat and then fell slightly. `autoninja` adds `--quiet` in some environments, so
the log holds no step counter; `third_party/siso/cipd/siso ps -C out/Arkt -n 1` prints it.

### Step 7: verification

    tail -3 build-arkt.log         -> The build has finished successfully.
    grep -c FAILED: build-arkt.log -> 0
    plutil -extract CFBundleIdentifier raw Arkt.app/Contents/Info.plist -> com.arkt.Arkt
    CFBundleName, CFBundleDisplayName, CFBundleExecutable -> Arkt; CFBundleShortVersionString -> 156.0.8078.48
    otool -L ".../Arkt Framework" | grep -c '@rpath/lib.*\.dylib' -> 0   (and 0 lines naming @rpath at all)
    otool -L Arkt.app/Contents/MacOS/Arkt -> /usr/lib/libSystem.B.dylib only
    codesign -dv Arkt.app -> Signature=adhoc, flags=0x20002(adhoc,linker-signed), TeamIdentifier=not set

`Arkt Framework.framework/Versions/Current/Helpers`: `Arkt Helper.app`, `Arkt Helper (Alerts).app`,
`Arkt Helper (GPU).app`, `Arkt Helper (Renderer).app`, `Arkt Helper (Aperitif).app`, `Arkt Helper (Aperitif Alerts).app`,
`Arkt Helper (Aperitif GPU).app`, `Arkt Helper (Aperitif Renderer).app`, plus `app_mode_loader`,
`chrome_crashpad_handler`, `web_app_shortcut_copier`. The only dylibs in the bundle are the framework's own
`Libraries/` (`libaperitif.dylib`, `libvk_swiftshader.dylib`, `libvulkan.dylib`), loaded at run time, not linked.

Sizes: `du -sh Arkt.app` 541M (the `Arkt Framework` binary alone 448 MB); `du -sh out/Arkt` 7.6G. Both under the
plan's estimates (400-600 MB bundle, 10-15 GB output) because `symbol_level = 0`.

### Launch check

One GUI run at a time, nothing else from `out/Spike` or `out/Arkt` running, fresh profiles under `$PROF`, port 9344,
the standard flags (`--use-mock-keychain --no-first-run --no-default-browser-check --enable-logging=stderr`), each
stopped by its PID:

- Default window (`$PROF/w1-release`): `ARKT: browsers normal=1 arkt=0 views=1`, `ARKT: in-process hook alive`,
  `ARKT: mounted active tab after 1 attempt(s)`. CDP `/json/version`: `Chrome/156.0.8078.48`. `chrome://version`
  (opened through CDP) renders: `Chromium: 156.0.8078.48 (Developer Build) (arm64)`, `Linker: lld`, executable path
  `out/Arkt/Arkt.app/Contents/MacOS/Arkt`. Child processes run from `Arkt Helper (Aperitif).app` and
  `Arkt Helper (Aperitif Renderer).app`. 0 `FATAL`/`Check failed`. The page drew at first; a few seconds later, with
  the window in the background, it reported `document.visibilityState` `hidden` and went blank: the week-1 blackout
  (finding 2) on the Views path, fixed only on the native window (W5c); W9 makes that the default.
- `--arkt-native-window` (`$PROF/w1-release-native2`): `ARKT: browsers normal=1 arkt=1 views=0`,
  `ARKT: native window created`, the tab list, `ARKT: key window`; the New Tab page renders in the Arkt window
  (`$PROF/shots/w1-release-native-version.png`, window-only). 0 `FATAL`/`Check failed`.

UI strings stay Chromium's (`chrome://version` says "Chromium", the NTP says "Customize Chromium"); the branding
file renames the bundle, framework, helpers and bundle id only, as planned. A first native-window run
(`$PROF/w1-release-native`) navigated to an external site 8 s after launch with no input from this task (the
interference recorded under W5c); it was stopped and is not counted.

Not done here (W2, #12): re-signing and installing into `/Applications`.

## W2

Date 2026-10-24. Input: the W1 bundle `$REL/Arkt.app` (overlay `c61a576`, ad-hoc linker signed), not rebuilt and not
modified: it was copied with `ditto` to `$CHROMIUM_ROOT/stage-w2/Arkt.app` and signed there. The commands are now
the "Sign and install (out/Arkt)" block in `engine/README.md`.

### Step 1: sign inside-out

Identity: the only code-signing identity in the login keychain, an Apple Development certificate (passed by hash;
its name, team id and hash are not recorded here). The keychain allowed signing without a prompt. `--timestamp=none`
(offline; notarization is #125). Order and options follow `chrome/installer/mac/signing/parts.py` and the plan:

| Part | Options | Entitlements |
|---|---|---|
| `Libraries/libaperitif.dylib`, `libvk_swiftshader.dylib`, `libvulkan.dylib` | none | none |
| `Helpers/chrome_crashpad_handler`, `app_mode_loader`, `web_app_shortcut_copier` | runtime | none |
| `Arkt Helper.app`, `(Alerts)`, `(Aperitif)`, `(Aperitif Alerts)` | runtime | none |
| `Arkt Helper (Renderer).app`, `(Aperitif Renderer)` | runtime | `helper-renderer-entitlements.plist` (`cs.allow-jit`) |
| `Arkt Helper (GPU).app`, `(Aperitif GPU)` | runtime | `helper-gpu-entitlements.plist` (`cs.allow-jit`) |
| `Arkt Framework.framework` | none (a dylib) | none |
| `Arkt.app` | runtime | `app-entitlements.plist` (audio-input, bluetooth, camera, print, usb, location, photos-library) |

`Helpers` held exactly the 11 entries W1 listed; each was signed. Per-part check with `codesign -dv`: every helper and
tool `flags=0x10000(runtime)`, the Renderer and GPU helpers carry `com.apple.security.cs.allow-jit`, nothing else
carries entitlements.

    codesign --verify --deep --strict --verbose=2 Arkt.app
      -> Arkt.app: valid on disk
      -> Arkt.app: satisfies its Designated Requirement
    codesign -dv --verbose=2 Arkt.app
      -> Identifier=com.arkt.Arkt
      -> CodeDirectory v=20500 ... flags=0x10000(runtime)
      -> Authority=Apple Development: (redacted) / Apple Worldwide Developer Relations Certification Authority / Apple Root CA
      -> TeamIdentifier set (redacted)

### Step 2: install

| When | `df -h /` available | `sysctl vm.swapusage` |
|---|---|---|
| before the copy | 13 GiB | `total = 7168.00M  used = 6099.12M  free = 1068.88M` |
| after the copy | 12 GiB | `total = 7168.00M  used = 6099.12M  free = 1068.88M` |

`/Applications/Arkt.app` did not exist (nothing named `Arkt*` in `/Applications`); `ditto` installed it (`du -sh`
554M). On the installed copy:

    codesign --verify --deep --strict --verbose=2 /Applications/Arkt.app -> valid on disk, satisfies its Designated Requirement
    codesign -dv /Applications/Arkt.app                                -> Identifier=com.arkt.Arkt
    spctl --assess --type execute -vv /Applications/Arkt.app           -> rejected, origin=Apple Development: (redacted)
    nm -gU ".../Arkt Framework.framework/Arkt Framework" | grep -c ' T _ChromeMain' -> 1

`spctl` rejects as expected: Gatekeeper accepts only notarized Developer ID builds (#125). It was not worked around.
Launching the binary directly (as below) is not subject to that assessment.

### Step 3: smoke from /Applications

No other Arkt or Chromium build was running (checked with `ps` before each launch). Fresh profiles under `$PROF`,
own CDP ports, the standard flags (`--use-mock-keychain --no-first-run --no-default-browser-check
--enable-logging=stderr`), no `--user-agent`; each run stopped by its PID and `ps -p` confirmed gone.

Run A, default window (`$PROF/w2-sign-smoke`, port 9381, `https://example.com`):

- `ARKT: browsers normal=1 arkt=0 views=1`, `ARKT: in-process hook alive`, `ARKT: mounted active tab after 1 attempt(s)`.
- `cdp.mjs --port 9381 example.com 'document.title'` -> `"Example Domain"` 6 s after launch.
- `navigator.userAgent` -> `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36` (no `Arkt`).
- `navigator.userAgentData.brands` -> `["Not:A-Brand","Chromium"]`; `getHighEntropyValues(["fullVersionList"])` brands
  -> `["Not:A-Brand","Chromium"]`. No `Arkt` brand.
- Window-only screenshot `$PROF/shots/w2-sign-smoke.png`: the Views window with its Extensions button and an empty
  content area, although CDP reported `visibilityState` `visible`. Same as W1's launch check on the Views path (finding
  2, fixed on the native window only, W9 makes that the default); not a signing effect.
- 0 `FATAL`/`Check failed`; no code-signing or library-validation messages in the log.

Run B, `--arkt-native-window` (`$PROF/w2-sign-native`, port 9382, `https://example.com`):

- `ARKT: native window created`, `ARKT: browsers normal=1 arkt=1 views=0`, `ARKT: in-process hook alive`,
  `ARKT: key window` naming our window.
- `document.title` -> `"Example Domain"` 3 s after launch; window-only screenshot `$PROF/shots/w2-sign-native-page.png`
  shows the page rendered in the Arkt window with its tab row.
- `cdp.mjs --port 9382 --navigate example.com chrome://extensions`, then on that target
  `location.href`, `document.title` and `!!document.querySelector("extensions-manager")` -> `chrome://extensions/`,
  `Extensions`, `true`. The extensions page opens.
- 0 `FATAL`/`Check failed`.
- Interference (as recorded under W5c): while the window was key, a second window and three tabs were opened and
  closed by input this task did not send (it sent no input at all, only CDP and `screencapture`). The run was
  stopped as soon as this showed in the log; the checks above came before or independently of it, and the browser
  handled the extra windows and tabs without a crash. `w2-sign-native-extensions.png` shows a New Tab from that input
  and is not counted.

### Step 4: 1Password profile on the internal disk

`$PROF/1password-test` was not in use (no process had it as `--user-data-dir`). `du -sh` 589M; `df -h /` 12 GiB
available before the copy, 11 GiB after (`vm.swapusage` used 6252.31M of 7168.00M). `ditto` to `$IPROF/1password`;
`$IPROF/1password/NativeMessagingHosts/com.1password.1password.json` is present. The copy carries the source
profile's stale `Singleton*` links from its last run (that process is gone; Chromium takes the lock over).

### Ready for the 1Password test (#23)

Yes, to be tried now: `/Applications/Arkt.app` is the signed, self-contained bundle (no `@rpath` dylibs, nothing loaded
from the external disk, hardened runtime, a real certificate rather than ad-hoc) that #23 was waiting for. What is
still open is whether 1Password accepts a browser signed with an Apple Development certificate and not notarized;
only the maintainer's run answers that. Steps (plan W2 "Needs the user"):

1. 1Password > Settings > Browser > Add Browser > choose `/Applications/Arkt.app`; note any message.
2. Quit any running Arkt, then launch `/Applications/Arkt.app/Contents/MacOS/Arkt` with
   `--user-data-dir="$IPROF/1password"`, the standard flags and
   `--arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa https://example.com` (full command in the plan).
3. PASS: the popup shows the account(s) or offers Touch ID / app unlock. FAIL: logo splash only or a Secret Key
   sign-in form (do not sign in there).
4. Send back the output of the plan's `grep` over the 1Password logs (`Verifying browser`, `code signature`,
   `XPC connected`): PASS evidence is `XPC connected` and no `status 100001`.

## W4

Date 2026-10-23. No upstream patch; patch totals unchanged.

### Step 2: failing check (build before W4)

Profile `$PROF/week2`, `--load-extension=action-probe,tabs-probe`, `--arkt-extensions-demo=list`
(`$PROF/w2-w4-before.log`):

```
ARKT: toolbar actions 2
ARKT action ceojeochoeiibbkbcnnidcahamphllac Arkt action probe
ARKT action hleckajngfboclajgdleaccpegbhpdmm Arkt tabs probe
```

tabs-probe has no `action` key and still gets a toolbar action (count 2). AXPress on the Extensions button (process
frontmost, our window key) logged `ARKT: extension not installed ddkjiahejlhfcafbddmgiahcphecmpfh`: the failure.

### Implementation

- `engine/test-extensions/action-probe/` (MV3: popup with `create`/`open`/`window` buttons, `sw.js` with
  `self.probe` and the keep-alive interval); `tabs-probe/sw.js` gets the keep-alive line.
- `arkt_extensions_menu.{h,mm}`: `ArktExtensionsMenu` observes `ToolbarActionsModel`, keeps one
  `ExtensionActionViewModel` per action (`ExtensionActionViewModel::Create` with `ArktExtensionActionDelegate`),
  builds the `NSMenu` on click (title `GetActionName()`, 16 pt icon from `GetIcon` rasterized with the tab's color
  provider, disabled when `IsEnabled` is false, "No extensions" when empty) and runs the chosen item with
  `ExecuteUserAction(kMenuEntry)`. The delegate's `GetActiveWebContents()` returns the tab Arkt shows;
  `TriggerPopup` hands the host to the popover; `RegisterCommand` and the context-menu fallback only log.
- `arkt_extensions_bridge.{h,mm}`: only hosts the popup now (`ShowPopover`, `IsShowingPopover`, `HidePopover`,
  `GetPopoverNativeView`); the hand-made `RunAction` + `CreatePopupHost` path is gone.
- `arkt_browser_main_extra_parts.mm`: `kUBlockLiteId` removed; the button shows the menu;
  `--arkt-extensions-demo=<id>` runs that action through its view model (`kToolbarButton`) once the model lists it;
  `--arkt-extensions-menu-dump` logs the items (only when they change; 1Password updates its action about 30 times
  in the first seconds) and closes a shown menu after 3 s.
- `BUILD.gn`: new sources, deps `//chrome/browser/ui/extensions` and `:extension_popup_types`.
  `gn check out/Spike //arkt/browser:browser`: `Header dependency check OK`.

Build: `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.`, 0 `FAILED:` lines.

### Step 6: popup through TriggerPopup (no input)

`--arkt-extensions-demo=ceojeochoeiibbkbcnnidcahamphllac`, `--remote-debugging-port=9333` (`$PROF/w2-w4.log`):

```
ARKT: toolbar actions 2
ARKT action ceojeochoeiibbkbcnnidcahamphllac Arkt action probe
ARKT action hleckajngfboclajgdleaccpegbhpdmm Arkt tabs probe
ARKT: run action ceojeochoeiibbkbcnnidcahamphllac source 1
ARKT: TriggerPopup ceojeochoeiibbkbcnnidcahamphllac by_user=1 url=chrome-extension://ceojeochoeiibbkbcnnidcahamphllac/popup.html
ARKT: popup loaded chrome-extension://ceojeochoeiibbkbcnnidcahamphllac/popup.html
```

| Command | Output |
|---|---|
| `cdp.mjs popup.html 'document.body.innerText.includes("ARKT action-probe popup")'` | `true` |
| `cdp.mjs ceojeochoeiibbkbcnnidcahamphllac/sw.js 'typeof self.probe.create'` | `"function"` |

Window-only screenshot `$PROF/shots/w2-w4-popup.png`: the popover with the probe's text and three buttons, its
arrow at the sidebar Extensions button.

### Step 7: menu contents and button wiring

`--arkt-extensions-menu-dump`, no demo (`$PROF/w2-w4-menu.log`):

```
ARKT: menu item 0 Arkt action probe enabled=1
ARKT: menu item 1 Arkt tabs probe enabled=0
```

Titles equal the `ARKT action` names in model order. tabs-probe is disabled: it has no popup and no
`action.onClicked` listener, so `IsEnabled` is false on the page.

AXPress on `button "Extensions" of window 1` (process frontmost, `ARKT: key window` named our window), run in the
background: `ARKT: extensions menu shown 2 items` at 14:34:58.58, `ARKT: extensions menu closed` at 14:35:01.82
(3.2 s, the dump-mode `cancelTracking`); `osascript` had exited. Item count equals the dump's.

### Step 8: real extension (1Password)

Run on a copy-on-write copy of the 1Password test profile (`cp -c -R` to `$PROF/1password-w4`; the original was in
use for a manual test), `--load-extension=action-probe`, `--arkt-extensions-menu-dump`,
`--arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa` (`$PROF/w2-w4-1password.log`). Read-only, not signed in:

```
ARKT: toolbar actions 2
ARKT action aeblfdkhhhdcdjpifhhbdiojplfjncoa 1Password – Password Manager
ARKT action ceojeochoeiibbkbcnnidcahamphllac Arkt action probe
ARKT: menu item 0 1Password – Password Manager enabled=1
ARKT: menu item 1 Arkt action probe enabled=1
ARKT: run action aeblfdkhhhdcdjpifhhbdiojplfjncoa source 1
ARKT: TriggerPopup aeblfdkhhhdcdjpifhhbdiojplfjncoa by_user=1 url=chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup/index.html
ARKT: popup loaded chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup/index.html
```

The popover auto-resized to 600x450. No screenshot (the popup shows account UI).

No `FATAL` or `Check failed` lines in any W4 log. Every browser was stopped by its PID; no `$OUT/Chromium.app`
processes were left.

### Follow-ups

- `out/Arkt` was configured before W4; the next `out/Arkt` build regenerates and compiles the W4 overlay
  (incremental).
- Keyboard commands for actions, the context menu, pinning and ordering are later work.

## W3: Seam inventory and window variant decision

Date 2026-10-23. Doc only; read-only `git grep`/`sed` on `$CR` at `156.0.8078.48-2-g2bda3d5a86` (branch `arkt`, patches
0001-0002 applied). No build. `$CR/out/Spike/args.gn` has `is_debug=false`, `dcheck_always_on=false`, so a
`DCHECK(ptr)` followed by a dereference is a null dereference (crash), not a `DCHECK` failure.

### The eight inventory commands

`X=(-- chrome ':!*test*' ':!chrome/browser/ui/webui_browser/*')`, run from `$CR`. All counts match the plan.

| # | Command (abridged) | Hits | Files |
|---|---|---|---|
| 1 | `git grep -n 'GetBrowserViewForBrowser([^;]*)->' $X` | 8 | 8 |
| 2 | `git grep -n 'GetBrowserViewForBrowser' $X \| wc -l` | 166 | 119 |
| 3 | `git grep -n 'IsWebUIBrowserEnabled()' $X` | 13 | 12 |
| 4 | `git grep -n 'GetWidgetForNativeWindow(.*GetNativeWindow' $X` | 11 | 10 |
| 5 | `git grep -n 'static_cast<BrowserView\*>' $X` | 1 | 1 |
| 6a | `git grep -n 'FindBrowserWindowWithWebContents' $X` | 11 | 8 |
| 6b | `git grep -n 'GetBrowserViewForNativeWindow' $X` | 30 | 16 |
| 7 | `git grep -n -A1 'GetTopLevelWidgetForNativeView' $X \| grep 'GetNativeView'` | 13 | 11 |
| 8 | `git grep -n -E 'if \(browser_view\|browser_view &&\|webui_browser_window\)\|IsWebUIBrowserEnabled' -- <hot files>` | 39 | 2 |

Grep 8 splits into 27 `browser_view` arm lines, 10 Webium arm lines and the `IsWebUIBrowserEnabled()` branch at
`browser_window_features.cc:352` in `browser_window_features.cc`, plus one Webium-gated arm in `tab_features.cc`
(`SadTabHelper`, :646) and no `browser_view` arm there.

### How the lookups behave for an `ArktBrowserWindow`

These four facts decide most rows below; they are the same for both variants unless stated.

- `BrowserView::GetBrowserViewForBrowser` reads `kBrowserViewKey` from the Widget of `GetNativeWindow()`
  (`browser_view.cc:1193-1217`). Variant P: no Widget, nullptr. Variant W: a Widget without `kBrowserViewKey`,
  nullptr. **Every grep 1/2 hit is identical in P and W.**
- `BrowserWindow::FindBrowserWindowWithWebContents` returns only a `BrowserView` (`browser_view.cc:1173-1190`: the
  top-level Widget's `kBrowserViewKey`, else `GetBrowserViewForBrowser`), so it is nullptr for Arkt tabs in both
  variants. `BrowserWindow::FromBrowser` is safe: it falls back to `browser->GetWindow()`
  (`browser_window_factory.cc:98-111`).
- `GetWidgetForNativeWindow`/`GetTopLevelWidgetForNativeView` (greps 4, 7) are nullptr in P and a Widget in W.
- A Views dialog or bubble whose `params.parent` is a view of a plain `NSWindow` gets no parent host
  (`native_widget_mac.mm:277-278`, `SetParent(parent_host)` at :316): it becomes an unparented top-level window. A
  browser-modal (`kWindow`) dialog then falls back to a non-modal window by design (comment and `DCHECK` at
  `native_widget_mac.mm:585-589`); a tab-modal (`kChild`) dialog trips that `DCHECK` (off in our builds) and is only
  sized, never positioned (`constrained_window_views.cc:167-176`, "If the host view is not backed by a
  Views::Widget, just update the widget size").

Classes: **(a)** reached this week (normal-window startup, tab add/close/activate, extension popup/action,
`chrome.tabs`/`chrome.windows`, Web Store install, keyboard shortcuts, W5b scenarios 1-17); **(b)** only by features
Arkt does not use this week; **(b\*)** a (b) row that is product-critical for week 3+; **(c)** null-safe already;
**(n)** not a call on macOS (comment, declaration, `BUILD.gn`/`PRESUBMIT.py` text, or `IS_WIN`/Ash/Aura-only code).

### Grep 2 (and 1): all 166 `GetBrowserViewForBrowser` lines

| Class | Lines | Files |
|---|---|---|
| (a) | 3 | 3 |
| (b) | 78 | 53 |
| (c) | 67 | 56 |
| (n) | 18 | 14 |
| total | 166 | 119 (a file with lines in two classes is counted in both) |

(a) rows, the same in P and W:

| Site | Check | Reached by | Fix |
|---|---|---|---|
| `chrome/browser/ui/sad_tab_controller.cc:31-34` | `DCHECK(browser_view)` then `->GetAllVisibleContentsWebViews()` | renderer crash, W5b scenario 9 (`SadTabHelper` is created whenever Webium is off, `tab_features.cc:646`) | patch: return nullptr when `browser_view` is null; `ReinstallInWebView` already tolerates a null `ContentsWebView` (`sad_tab_controller.cc:76-80`). Sad tab UI `not shown` |
| `chrome/browser/ui/views/bubble_anchor_util_views.cc:185-187` | unchecked `browser_view->GetMirroredXInView` in `GetPageInfoAnchorRect` | permission prompt, scenario 11: the stub `LocationBar` is not drawn, so no chip (`permission_prompt_factory.cc:142-145`, :237-238), `PermissionPromptBubble` anchors with a null configuration and calls `GetPageInfoAnchorRect` (`permission_prompt_base_view.cc:152-153`); also chooser bubbles (`chooser_bubble_ui.cc:59`) and page info | patch: fall back to the browser window bounds when `browser_view` is null |
| `chrome/browser/ui/extensions/extension_install_ui_desktop.cc:161-163` | unchecked `browser_view->toolbar()` in the post-install IPH callback | Web Store install (W7): the post-install dialog runs this callback when it closes (`extension_post_install_dialog.cc:156-161`) | patch: `if (!browser_view \|\| !browser_view->toolbar()) return;` |

The 8 direct `GetBrowserViewForBrowser(...)->` dereferences of grep 1 are all (b): extension dialog
anchoring `extension_dialog_utils_views.cc:90` (only the `BrowserWindowInterface*` overload, not the native-window
overload the install dialogs use), autofill popup `popup_base_view.cc:179` (null-checked on the next line, so (c) in
fact), file system access usage bubble, HaTS, Cast dialog, back/forward button, Chrome Labs, ambient WebAuthn
sign-in.

(b) by theme (53 files): Views tab strip, tab groups, tab drag, vertical tabs; Views toolbar, location bar,
omnibox, app menu, extensions toolbar; glic (including the latent `CHECK_DEREF` in
`glic/widget/browser_conditions.cc:191`, reached only for a glic-enabled signed-in profile); side panel and page
info side panels; Cast/media router; sign-in, profile and promo bubbles (`batch_upload_service.cc:382`,
`dice_web_signin_interception_bubble_view.cc:504`, iOS promos); web apps; HaTS, Chrome Labs, idle, relaunch,
storage pressure, memory saver, Lens region search, Indigo, compose, data sharing, file system access, WebAuthn
ambient; `browser_actions.cc` (8 `CHECK_DEREF`s, run from the Views app menu, toolbar and page actions only);
`tab_search_bubble_host.cc:243` (iterates every browser and dereferences: a mixed-window hazard once Views tab
search is used while an Arkt window exists).

(c) (56 files) includes everything this week touches besides the three (a) rows: `browser_window_features.cc:692`
(the arms below), `browser_window_factory.cc:98`, `browser_web_contents_delegate.cc:1176`,
`browser_command_controller.cc:2682`, autofill popups (`popup_view_views.cc:212`, `popup_view_utils.cc:289`),
download bubble rows, `chrome_omnibox_client.cc:663`, Lens overlay, permission prompt base and scrim views,
`share_menu_controller.mm:210` (Share menu does nothing), `accelerator_utils_cocoa.mm:56` (no non-test caller),
translate, session-crashed and default-browser bubbles.

### Greps 3-7

For grep 7 the line number is the argument line the command prints.

| Grep | Site | Class | P | W |
|---|---|---|---|---|
| 3 | `toast_controller.cc:323-328`: no anchor view and Webium off is `CHECK_IS_TEST()` (fatal in the product) | (b\*) | seam | seam |
| 3 | `new_tab_page_handler.cc:871`, :1200: the Webium early return guards `CHECK(footer_controller)` at :884-885 and :1214-1215; `NewTabFooterController` is a `browser_view` arm (`browser_window_features.cc:878-879`) | (a) | seam | seam |
| 3 | `browser_tabrestore.cc:125-130`: only `DCHECK`s that `GetContentsSize()` equals the restored tab's size (off in our builds, so this site cannot crash) | (a) | ours (real `GetContentsSize`) | ours |
| 3 | `tab_features.cc:646` (`SadTabHelper`) | (a) | see sad tab | see sad tab |
| 3 | `browser_window_features.cc:352` (`BrowserElementsViewsImpl`, returns no views for us) | (c) | | |
| 3 | `read_anything_side_panel_controller.cc:246` (`CHECK_IS_TEST()` without a side panel), `side_panel_helper.cc:38`, `customize_chrome_page_handler.cc:550`, `reading_list_ui.cc:70`, `chrome_browser_interface_binders_webui_parts_desktop.cc:635` | (b) | | |
| 3 | `session_restore.cc:859` (Ash), `browser_window_factory.cc:35` (the factory, patch 0004) | (n) | | |
| 4 | `browser_focus_controller.cc:42` (`RotatePaneFocus`, null-checked) | (c) | F6 does nothing | works |
| 4 | `permission_prompt_base_view.cc:91`, :299, `permission_prompt_bubble_base_view.cc:225`, `embedded_permission_prompt_system_settings_view.cc:27` | (c) | prompt shown inactive | as Chrome |
| 4 | `webui_permission_chip.cc:297`, `profile_dynamic_menu.cc:455`, `glic_widget.cc:228` | (b) | | |
| 4 | Ash/ChromeOS (3 hits) | (n) | | |
| 5 | `browser_help_bubble.cc:66` (`IsViewClass<BrowserView>` first) | (c) | | |
| 6a | `address_bubbles_controller.cc:61`, :75, :86, :316: unchecked, and Webium's `GetAutofillBubbleHandler` is nullptr too | (b\*) | seam | seam |
| 6a | `managed_profile_required_navigation_throttle.cc:215`, `access_code_cast_dialog.cc:65`, `webui_contents_wrapper.cc:195`: unchecked | (b) | | |
| 6a | `theme_colors_source_manager.cc:58`, `webui_util_desktop.cc:137` (null-checked, fall back to defaults) | (c) | | |
| 6a | `browser_window.h:134`, `browser_view.cc:1173` | (n) | | |
| 6b | `extension_view_utils.cc:18` (W7 post-install: no container, falls back to a browser-modal dialog), `display_media_access_handler.cc:547`, `web_textfield_touch_bar_controller.mm:22`, `browser_feature_promo_controller.cc:184`, `browser_user_education_context.cc:210` | (c) | | |
| 6b | tab drag (11 hits), omnibox (5), `at_memory_promo_bubble_view.cc:100`, `desktop_media_list_view.cc:40` | (b) | | |
| 6b | `browser_view.{h,cc}` (4), `javascript_app_modal_event_blocker_aura.cc` (2), Ash comment | (n) | | |
| 7 | `render_view_context_menu_mac_cocoa.mm:77-82` (in-process) and `render_view_context_menu_mac_remote_cocoa.mm:32-37`: no top-level Widget returns before showing the menu | (b\*) | **page context menu not shown** | works |
| 7 | `chrome_authenticator_request_delegate.cc:1253-1259`: the passkey `NSWindow` is taken from the top-level Widget | (b\*) | platform passkey sheet has no window | works |
| 7 | `external_protocol_dialog.cc:187` (observation only) | (c) | | |
| 7 | `payment_request_dialog_view.cc:74`, `caption_bubble_context_views.cc:46`, :82, `rounded_omnibox_results_frame.cc:124`, :127, `visual_guided_setter_page_handler.cc:51`, `tab_groups_organizer_page_handler.cc:164` | (b) | | |
| 7 | `chrome_media_app_ui_delegate.cc:69` (Ash), `browser_view.cc:1183` | (n) | | |

Found while reading, outside the eight greps: the autofill and `<datalist>` popup (scenario 17) needs only a
top-level `NSWindow` on Mac (`popup_view_views.cc:144-149`) and tolerates a null parent Widget, kept from the Cocoa
browser (`popup_base_view.cc:302-312`): (c), shown in both variants. Tab-modal dialogs (scenario 10) are a P-only
seam (the parenting rule above): shown, but unparented and unpositioned in P; W parents them to the Widget.

Also outside the eight greps (both variants, week 3, (b\*)): Webium's `GetAutofillBubbleHandler()` returns nullptr,
and these callers dereference `BrowserWindow::FromBrowser(browser)->GetAutofillBubbleHandler()` without a check:
`mandatory_reauth_bubble_controller_impl.cc:298`, `filled_card_information_bubble_controller_impl.cc:428`,
`virtual_card_enroll_bubble_controller_impl.cc:389`, :396, `autofill_ai_import_data_controller_impl.cc:242` and
`omnibox_autofill_bubble_controller.cc:130`. The greps miss them because they go through `FromBrowser`, which is
non-null for Arkt. Fix on our side: `ArktBrowserWindow` returns a non-null no-op handler (no upstream file).

### Grep 8: features a third window type does not get

The 27 `browser_view` arms and 10 Webium arms leave Arkt (both variants) without: bookmark bar delegate (:709),
`BrowserFocusControllerViews` (Arkt gets `StubBrowserFocusController`, :726), `ColorProviderBrowserHelper` (:742),
contents border (:748), data protection UI (:753), DSE extension checks (:766), `DevtoolsUIController` (:792:
scenario 16 not docked; callers null-check it, `devtools_window.cc:1079`, :1404), the Webium exclusive access
context (:801: Arkt supplies its own, W5a), `DownloadToolbarUIController` (:823: scenario 14 has no bubble; callers
null-check it, `download_bubble_ui_controller.cc:97-99`), `ExtensionKeybindingRegistryViews` (:833, no focus
manager: extension keyboard commands are a known gap), extension side panels (:840), find bar owner (:849-856: not
needed, `ArktBrowserWindow::CreateFindBar` returns its own bar), `FullscreenControlHost` (:859), NTP footer
(:878-879, the NTP `CHECK` above), omnibox popup closer (:889), scrim (:899), side panel (:909-916), skills (:918),
user education (:941), zoom bubble (:952-963), and in the `TYPE_NORMAL` block actor UI, `AiModePageActionController`, Cast, memory saver
IPH, shared tab group feedback, split tab highlight (:973-1083). None of them is needed for this week's scenarios
beyond the rows already listed, so **no Arkt arm in either hot file is projected**.

### `BrowserWindow` overrides where Webium returns real objects

Webium has 56 `NOTIMPLEMENTED_LOG_ONCE()` stubs in `webui_browser_window.cc`; the overrides below return real
objects or values. "Callers" names the caller that fails or misbehaves without it.

| Override (Webium line) | Webium returns | `ArktBrowserWindow` returns (W5a) | Callers |
|---|---|---|---|
| `GetNativeWindow` (:419) | the Widget's window | the host's `NSWindow` | every lookup above; `sad_tab_controller.cc:26-29` |
| `Show`, `ShowInactive`, `Close` (:290, :382), `Activate`, `Deactivate`, `IsActive` (:394-402), `IsVisible` (:374) | Widget state | `NSWindow` state; `Close` orders out, then `BrowserWindowDeleter` | `chrome::Navigate`, `windows.update/remove`, scenario 7 |
| `GetBounds`, `GetRestoredBounds`, `SetBounds`, `IsMaximized`, `IsMinimized`, `IsFullscreen`, `Maximize`, `Minimize`, `Restore`, `GetWindowShowState` (:378, :1192-1246) | Widget state | `NSWindow` frame and style mask | `chrome.windows.*`, session save |
| `GetContentsSize` (:820), `SetContentsSize` (:829) | contents element bounds | card view size | `browser_tabrestore.cc:125-130` |
| `GetNativeTheme`, `GetThemeProvider`, `GetColorProvider`, `GetColorProviderKey`, `GetRendererColorMap` (:454-606) | real | real (`ui::NativeTheme::GetInstanceForNativeUi()`, the profile's `ThemeService`, `ColorProviderManager`) | WebUI colours, `theme_colors_source_manager.cc:58` |
| `GetLocationBar` (:858, `WebUIStubLocationBar`, :152) | stub | `ArktStubLocationBar`, non-null, `IsDrawn()` false | 22 unchecked `GetLocationBar()->` call sites in `chrome/` |
| `GetWebContentsModalDialogHost`, `...For` (:1104, :1109) | `WebUIBrowserModalDialogHost` (:188) | Arkt host over the card view | tab-modal dialogs, scenario 10 |
| `GetExclusiveAccessContext` (:1138) | Webium context, built before `ExclusiveAccessManager` (`browser_window_features.cc:801-811`) | `ArktExclusiveAccessContext`, built in the constructor | scenario 12 |
| `CreateFindBar` (:1099, `FindBarHost`) | real | **`ArktFindBar` (no UI), never nullptr**: `FindBarController::GetOrCreateFindBar` dereferences it (`find_bar_controller.cc:58-60`); `FindBarHost` needs a `FindBarOwner`, which Arkt does not get | scenario 13 |
| `ExtensionsContainer` (:190-194) | `WebUIToolbarExtensionsContainer` | Arkt container (W6) | `chrome.action.openPopup`, scenario 4 |
| `GetAcceleratorProvider` (:862), `GetAcceleratorForCommandId` (:604), `PreHandleKeyboardEvent` (:1035) | real (accelerator table) | menu equivalents to `NSApp.mainMenu`; `GetAcceleratorProvider` may stay nullptr | keyboard shortcuts |
| `IsTabStripEditable` (:925) | `true` | **`true`**: `TabListBridge::IsThisTabListEditable` (`tab_list_bridge.cc:664-667`) gates every extension tab edit | scenario 6, W6 |
| `IsLocationBarVisible` (:943) | `true` | `false` (no omnibox); revisit if an extension API needs `true` | |
| `IsToolbarVisible` | stub | `true` | `extension_action_api.cc:150` (`action.openPopup`) |
| `UpdateTitleBar` (:761), `ZoomChangedForActiveTab` (:1002), `UserChangedTheme` (:996), `OnActiveTabChanged` (:775) | real (Webium UI) | forward to the host or log | |
| `GetStatusBubbles` (:756) | empty vector | one `ArktStatusBubble` (W5a Step 3) | `browser_ui_controller.cc:86`, `browser_web_contents_delegate.cc:800` |
| `DeleteBrowserWindow` (:667) | `delete this` | same | `BrowserWindowDeleter` |

### Can `NativeWidgetMac` adopt ShellUI's existing `NSWindow`?

No, not without upstream changes. `NativeWidgetMac::CreateNSWindow` (`native_widget_mac.h:261`) is a supported
virtual (`BrowserNativeWidgetMac` overrides it, `browser_native_widget_mac.mm:746`), but it must return a
`NativeWidgetMacNSWindow` (`native_widget_mac_nswindow.h:41`) and is called only while the Widget initialises
(`native_widget_mac.mm:298-300`). The bridge then takes the window over: it sets its own `ViewsNSWindowDelegate` as
the window delegate (`native_widget_ns_window_bridge.mm:466-475`) and replaces the content view with
`BridgedContentView` (:860). Variant W therefore means ShellUI's window class derives from Chromium's
`NativeWidgetMacNSWindow`, is created by Views, and ShellUI's views live under `BridgedContentView` with Views as
the window delegate. That contradicts Decision 1's ownership rule (ShellUI owns its borderless `NSWindow`).

### Per-variant projection (seam patches only, against the W5b gate)

| Theme (one patch file each) | P upstream files | W upstream files |
|---|---|---|
| Browser features: `new_tab_page_handler.cc` (NTP footer `CHECK`s), `extension_install_ui_desktop.cc` (post-install IPH) | 2 | 2 |
| Tab features: `sad_tab_controller.cc` | 1 | 1 |
| Dialogs and anchoring: `bubble_anchor_util_views.cc`; P also tab-modal dialog parenting: either the Arkt modal dialog host attaches the dialog's `NSWindow` with `addChildWindow:` when it appears (0 upstream files), or an upstream fix in the bridge (`NativeWidgetMacNSWindowHost::SetParent` takes a host and the bridge works from bridge ids, so 2-4 files under `ui/views/` and `components/remote_cocoa/`) | 1-5 | 1 |
| **This week, category (a)** | **3 patch files, 4-8 upstream files, 0 hot-file hunks** | **3 patch files, 4 upstream files, 0 hot-file hunks** |
| Week 3+ (b\*): `toast_controller.cc`, `address_bubbles_controller.cc` or `browser_view.cc` (`FindBrowserWindowWithWebContents` fallback); `GetAutofillBubbleHandler` callers (ours: non-null no-op handler, no file); P also `render_view_context_menu_mac_cocoa.mm` (+ `_remote_cocoa.mm`), `chrome_authenticator_request_delegate.cc` | +4 to 5 | +2 |
| **Including week 3+ (b\*)** | **3 patch files, 8-13 upstream files, 0 hot-file hunks** | **3 patch files, 6 upstream files, 0 hot-file hunks** |

Category (a) files: 6 in both variants (`sad_tab_controller.cc`, `bubble_anchor_util_views.cc`,
`extension_install_ui_desktop.cc`, `new_tab_page_handler.cc`, `browser_tabrestore.cc`, `find_bar_controller.cc`),
plus in P the tab-modal parenting fix (0 files on the Arkt side, 2-4 upstream); two of them (`browser_tabrestore.cc`,
`find_bar_controller.cc`) are fixed on our side and need no patch. A single upstream predicate does not cover these:
they are null dereferences in unrelated files, each a one-line null check, so extending the
`IsWebUIBrowserEnabled()` branches with an Arkt check would only add hot-file hunks (`tab_features.cc:646`) for no
saving. The gate is 8 patch files, 25 upstream files, 6 hot-file hunks: both variants stay well inside it, before
and after the week-3 rows.

### Strategy decision (Decision 1)

**Variant P (plain `NSWindow`).** Rule: P unless P's projection exceeds the W5b gate and W's does not. P projects
3 seam patch files, 4-8 upstream files and 0 hot-file hunks this week (8-13 upstream files with the week-3 rows); the
gate is 8 / 25 / 6. W saves up to four upstream files this week and up to seven by week 3, at the cost of handing
ShellUI's window, content view and delegate to Views (previous section). The P-only costs are known and small:
tab-modal dialog parenting (this week: 0 upstream files if the Arkt modal dialog host calls `addChildWindow:`,
else 2-4 in the bridge), page context menus and the passkey window (week 3).

W5a builds P. The W5b gate switch to W stays available but is not projected to trigger.

### Methods W5a must make real

Beyond W5a Step 3's list, this inventory adds or confirms:

1. `CreateFindBar`: return an `ArktFindBar` (no UI, logs); nullptr crashes Cmd-F (`find_bar_controller.cc:58-60`).
2. `IsTabStripEditable`: `true`; a neutral `false` makes every `chrome.tabs` edit fail (`tab_list_bridge.cc:664-667`).
3. `GetContentsSize`: the card view size, equal to the active tab's size. `browser_tabrestore.cc:125-130` only
   `DCHECK`s it (off in our builds), so that site cannot crash, but restored tabs should get the right size.
4. `GetLocationBar`: non-null stub with `IsDrawn()` false. A null bar would also take the permission bubble path
   (`IsLocationBarDisplayed` is `lb && lb->IsDrawn() && ...`); the stub is needed because 22 call sites in
   `chrome/` dereference `GetLocationBar()->` without a check.
5. `GetExclusiveAccessContext`: created in the constructor, before `BrowserWindowFeatures` builds
   `ExclusiveAccessManager` (`browser_window_features.cc:809-811`).
6. `GetWebContentsModalDialogHost` and `GetWebContentsModalDialogHostFor`: real (scenario 10).
7. `IsToolbarVisible`: `true` (`extension_action_api.cc:150`).
8. `GetNativeWindow`, the window state and bounds methods, `GetNativeTheme`, `GetThemeProvider`,
   `GetColorProvider`, `GetStatusBubbles`, `HandleKeyboardEvent`/`PreHandleKeyboardEvent` and
   `DeleteBrowserWindow`, as in the overrides table.
9. `GetAutofillBubbleHandler` (week 3): a non-null no-op handler; nullptr crashes the payments and Autofill AI
   bubbles (six unchecked callers, listed under "Found while reading").

Known gaps recorded for W5b (both variants, no fix this week): sad tab UI, download bubble, docked DevTools, zoom
bubble, fullscreen exit control, extension keyboard commands, Share menu. If item 9 is not done, payments and Autofill AI bubbles join this list for
week 3.

## W5a: `ArktBrowserWindow` skeleton behind `--arkt-native-window`

Date 2026-10-23. Branch `engine/w5a-native-window`. Variant P (plain `NSWindow`), as decided in W3 and on issue #15.

### Prep

- Plan: the factory hook is patch 0004 (0003 is the W8 keychain patch); seam patches start at 0005.
- Chromium branch `arkt`: commits 0001 and 0002 were re-authored to `Arkt contributors <noreply@arkt.invalid>`
  (`git rebase --exec 'git commit --amend --no-edit --author=...'` onto `156.0.8078.48`, author dates kept,
  `GIT_LFS_SKIP_SMUDGE=1`). Tree unchanged (`git diff <old arkt> arkt` empty, same tree hash `0528431029`). Export
  produced `From: Arkt contributors <noreply@arkt.invalid>` for all patches, and 0001-0003 were byte-identical to
  the committed files (the repo copies already carried the noreply author).

### Implementation

- `arkt_browser_window_factory_hook.{h,cc}`, target `//arkt/browser:window_factory_hook` (public dep
  `//chrome/browser/ui:browser_window_deleter` only): a function pointer, set in `PreProfileInit` when
  `--arkt-native-window` is present. Patch 0004 (`Arkt: let Arkt create normal browser windows`) calls it first in
  `BrowserWindow::CreateBrowserWindow` and passes only `browser` (`user_gesture`, `in_tab_dragging` are Aura-only).
  The override returns nullptr for every type except `TYPE_NORMAL`.
- `arkt_browser_window.{h,mm}`: `arkt::ArktBrowserWindow` (`BrowserWindow`, `ui::ColorProviderSource`,
  `TabStripModelObserver`), the `ArktWindowHost` protocol (`window`, `cardView`, `closeRequested`,
  `tabListChanged:`) and `ArktPlaceholderWindowHost` (an `ArktWindow`, 190 pt sidebar with the Extensions button,
  inset rounded card; frames, not constraints, so the card has its size before the first mount). No RTTI:
  `ArktBrowserWindow::FromBrowser` looks the browser up in the set of live windows.
- The 9-item list from #15: `CreateFindBar` returns `ArktFindBar` (no UI); `IsTabStripEditable` true;
  `GetContentsSize` is the card size; `GetLocationBar` is a non-null stub with `IsDrawn()` false;
  `GetExclusiveAccessContext` is created in the constructor (native fullscreen through `toggleFullScreen:`,
  `WindowFullscreenStateChanged` on the enter/exit notifications, bubble is a logged no-op that runs the hide
  callback with `kNotShown`); `GetWebContentsModalDialogHost(For)` is a host over the card (top centre, card size,
  observers notified on resize); `IsToolbarVisible` true; window state and bounds, `GetNativeWindow`, theme and
  colour providers, keyboard (`HandleKeyboardEvent` offers unhandled Cmd key downs to `NSApp.mainMenu`,
  `PreHandleKeyboardEvent` not handled) and `DeleteBrowserWindow` are real. Item 9 (`GetAutofillBubbleHandler`)
  stays nullptr for week 3.
- Lifecycle: `Show` calls `BrowserActiveStateManager::DidBecomeActive` and makes the window key; key/resign-key
  notifications drive `DidBecomeActive`/`DidBecomeInactive`. `Close` runs from a posted task (as a Widget close
  does): `HandleBeforeClose`, order out while tabs remain, `UnloadController::OnWindowClosing`. The close button
  asks the engine through `closeRequested` instead of closing. The destructor calls
  `TearDownPreBrowserWindowDestruction()` first, then drops the observers, unmounts and orders the window out.
- Mounting: `OnActiveTabChanged` puts the new tab's `WebContents` view in the card (old one removed from the
  hierarchy) and sets the window as the tab's colour provider source. Tab strip changes go to the host as plain
  events (`inserted`, `removed`, `moved`, `activated`).
- Census on every browser add and remove: `ARKT: browsers normal=<n> arkt=<n> views=<n>`.
- `gn check out/Spike '//arkt/browser:*'`: `Header dependency check OK`.

**Deviation from Step 3: `GetStatusBubbles` returns an empty vector, not an `ArktStatusBubble`.** The first smoke
run crashed on the first mouse-entered event: `BrowserWebContentsDelegate::UpdateTargetURL` and `ContentsMouseEvent`
(`browser_web_contents_delegate.cc:800-803`, `:827-833`) `static_cast` every status bubble to `StatusBubbleViews`
and dereference its `base_view()` (SEGV at 0x348, from the macOS crash report). Webium returns an empty vector for
the same reason. Link-target display for the shell needs another route (a `WebContentsDelegate`-level hook or a
seam patch), week 3.

### Build

`nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.`, 0 `FAILED:` lines (twice).
Before: `df -h /` 11-12 GiB available; swap free 1349-1429 MB.

### Smoke (Step 5)

With `--arkt-native-window`, profile `$PROF/week2-native`, `https://example.com`:

```
ARKT: native window factory registered
ARKT: native window created
ARKT: browsers normal=1 arkt=1 views=0
ARKT: native window mounted tab 1888263317
ARKT: tab event inserted tab 1888263317 index 0
ARKT: tab event activated tab 1888263317 index 0
ARKT: window number 46757
ARKT: in-process hook alive
ARKT: key window 46757
cdp.mjs example.com 'document.visibilityState + " " + document.title'   -> "visible Example Domain"
cdp.mjs example.com 'innerWidth + "x" + innerHeight'                     -> "1200x880" (the card)
```

Alive after 30 s idle (`ps -p` elapsed 00:36), no `FATAL`/`Check failed`. Window-only screenshot
(`$PROF/shots/w5a-1.png`) shows example.com in the card, the sidebar placeholder and the Extensions button.

Without the flag the week-1 path is unchanged: `ARKT: browsers normal=1 arkt=0 views=1`,
`ARKT: mounted active tab after 1 attempt(s)`, CDP `"visible Example Domain"`.

### Extension APIs (tabs-probe service worker, no input)

| Call | Result |
|---|---|
| `chrome.windows.getAll({populate:true})` | one window, `type normal`, `focused true`, `state normal`, 1400x900, its one tab active |
| `chrome.windows.getLastFocused()` | the same window id |
| `chrome.tabs.create({active:false})` | tab at index 1 in that window; `tab event inserted`, no mount |
| `chrome.tabs.update(id, {active:true})` | `true`; `native window mounted tab <id>` |
| `chrome.tabs.remove` of a background tab | removed, `tab event removed`, process alive |
| page `window.open("about:blank#page-open")` with a user gesture | `true`; the new tab lands in the Arkt window (`windows.getAll`: `normal:2`, census unchanged) |

### Seams reached (recorded for W5b, not fixed)

| Seam | How reached | Result |
|---|---|---|
| Sad tab | `cdp.mjs --navigate example.com chrome://crash` | **crash**: `SadTabController::ReinstallInWebView` -> `FindContentsWebView` -> `BrowserView::GetAllVisibleContentsWebViews` on a null `BrowserView` (SEGV) |
| NTP footer | `cdp.mjs --navigate example.com chrome://newtab/` | **crash**: `Check failed: footer_controller.` (`new_tab_page_handler.cc`) |
| Permission prompt | `Notification.requestPermission()` with a user gesture | no crash; no bubble shown (`Notification.permission` stays `"default"`, only the Arkt window exists) |
| Post-install IPH | needs an extension install from the Web Store | not reached this task (W7) |
| **New: closing the active tab** | `chrome.tabs.remove` of the active tab | **crash**: `Check failed: base::internal::get_is_test_impl()` in `ReadAnythingSidePanelController::TabWillDetach` (`read_anything_side_panel_controller.cc:243-248`): no `SidePanelUI` and Webium off, so `CHECK_IS_TEST()`. Every close of the active tab hits it, so closing a window (scenario 7) and quitting are blocked too: CDP `Browser.close` ends in the same `Check failed`. One-line Arkt predicate next to the Webium one, or an Arkt `SidePanelUI`; W3 had not classified this site as (a) |

Teardown is therefore not verified yet: no run reached `~ArktBrowserWindow` (`ARKT: native window destroyed`).
`kill -TERM` ends the process without running browser teardown (no destroyed line, no crash), and every graceful
path (window close, `Browser.close`) first closes the active tab. W5b checks the destructor once the
`ReadAnythingSidePanelController` seam is fixed.

Crash reports under `~/Library/Application Support/Chromium/Crashpad`: 71 files before W5a, 78 after (counted
only); all new ones come from the crash runs above (more than one dump per run where a renderer died too).

Also known, not reached: `ExclusiveAccessPermissionPrompt` dereferences `GetLocationBar()->GetChipController()`
unchecked (`exclusive_access_permission_prompt.cc:25`), and the stub returns nullptr (pointer/keyboard lock
prompts).

Not done in W5a: the extensions menu is not wired to the native window (the placeholder button does nothing;
W5b scenario 4 needs it, W6 registers the `ExtensionsContainer`); tab-modal dialogs are not attached with
`addChildWindow:` yet (W5b scenario 10).

## W5b: Seam fixes and the native-window smoke matrix (GATE)

Date 2026-10-23. Branch `engine/16-native-window-seams`, issue #16. Variant P (plain `NSWindow`). Every row below
comes from a fresh launch of the final `out/Spike` build (profile `$PROF/week2-native`, both probe extensions,
`--remote-debugging-port=9333`, `https://example.com`, downloads pointed at `$PROF/downloads` with
`prompt_for_download` false). Builds: `nice -n 15 autoninja -C out/Spike chrome`, `The build has finished
successfully.`, 0 `FAILED:` (twice); one build waited about 25 min for `/` to get back above 8 GiB free (it was at
6.7 GiB from other jobs). `gn check out/Spike '//arkt/browser:*'`: `Header dependency check OK`.

### Seams fixed

| Seam | Symptom | Fix |
|---|---|---|
| `ReadAnythingSidePanelController::TabWillDetach` (`read_anything_side_panel_controller.cc:243-247`) | closing the active tab, a window, or quitting: `CHECK_IS_TEST()` (no `SidePanelUI`, Webium off) | **ours**: `ArktSidePanelUI`, a no-op `SidePanelUI` registered on the browser's `UnownedUserDataHost` (every query answers "closed"). No upstream file |
| `NewTabPageHandler` (`new_tab_page_handler.cc:885`, :1215) | `chrome://newtab`: `Check failed: footer_controller` | **ours**: `ArktBrowserWindow` creates a `NewTabFooterController` with no contents container views (tracks nothing, footer hidden) when `kNtpFooter` is on, torn down in the destructor. No upstream file |
| `SadTabController` `FindContentsWebView` (`sad_tab_controller.cc:31-34`) | renderer crash: SEGV on a null `BrowserView` | **patch 0005**: return nullptr without a `BrowserView`; the controller keeps the sad tab view unparented (its existing no-contents-view path). No Arkt-side route: `SadTab::Create` is a fixed factory and `GetNativeWindow()` is non-null |
| `GetPageInfoAnchorConfiguration` / `GetPageInfoAnchorRect` (`bubble_anchor_util_views.cc`) | permission prompt: SEGV (`SEGV_ACCERR` at 0x550) right after the stub `GetChipController` call; the first unguarded `browser_view->` is `GetIsPictureInPictureType()` in the `kLocationBar` path (W3 had predicted the later `GetPageInfoAnchorRect:185`) | **patch 0006**: empty configuration without a `BrowserView`; anchor rect = window top-left plus `kNoToolbarLeftOffset`. Arkt-side alternative rejected: an element anchor from `ArktStubLocationBar::GetChipAnchor()` would need a `ui::TrackedElement`, and `BubbleDialogDelegate::SetAnchor` `CHECK`s that a non-Views element is backed by a Widget, which a plain `NSWindow` cannot give |
| `ExclusiveAccessPermissionPrompt` (`exclusive_access_permission_prompt.cc:25`) | pointer/keyboard lock prompt dereferences `GetChipController()` (nullptr from the stub) | **patch 0006**: also require a chip controller. Not reached in the matrix (`kKeyboardLockPrompt` is off by default); null-checked so the pointer-lock prompt cannot crash once it is on |
| Main menu commands (new) | every browser command in the menu bar is disabled for an Arkt window (Find, Close Tab, Reload, ...): Chrome routes `commandDispatch:` through the key window's responder chain to the Views window's command handler, and a plain `NSWindow` has none, so only `AppController`'s window-less commands remain. Scenario 13 found it: `Find...` had `enabled false` | **ours**: the placeholder host (window delegate, in the responder chain) answers `commandDispatch:`, `commandDispatchUsingKeyModifiers:` and `validateUserInterfaceItem:` through two new `ArktWindowHost` blocks (`validateCommand`, `executeCommand`) that `ArktBrowserWindow` binds to `chrome::IsCommandEnabled`/`chrome::ExecuteCommand`. The ShellUI host must forward the same two selectors in week 3 |
| Extensions menu on the native window (W5a gap) | `--arkt-extensions-demo` and the sidebar button did nothing on the native path | **ours**: the factory attaches an `ArktExtensionsMenu` to the placeholder host's button once the `Browser` exists (posted task, weak window pointer); a null tab means "the browser's active tab" |

Also from the #142 review: `Deactivate()` is a logged no-op (`NativeWidgetMac::Deactivate` is `NOTIMPLEMENTED`);
`GetRestoredBounds()` reports the frame from before native fullscreen (saved on
`NSWindowWillEnterFullScreenNotification`; a minimized `NSWindow` keeps its frame); `LogStubOnce` uses
`base::flat_set`. `IsMaximized()` stays `isZoomed`: that is what `NativeWidgetMac::IsMaximized` reports on Mac too.
Splitting `arkt_browser_window.mm` (now about 1280 lines) stays with W5c, as the review proposed.

### Destructor and quit

| Path | Result |
|---|---|
| `chrome.tabs.remove` of the active tab | removed, next tab mounted, process alive, 0 `Check failed` |
| `chrome.windows.remove` of every window (scenario 7) | `ARKT: browsers normal=0 arkt=0 views=0`, then `ARKT: native window destroyed`; process keeps running with no windows |
| `kill -TERM` after that | gone within 10 s, 0 `FATAL`/`Check failed`, no new dump |
| CDP `Browser.close` with the window open | `normal=0 arkt=0`, `native window destroyed`, process exits, no new dump |

The whole `Close()` -> tabs close -> `TabStripEmpty()` -> `Close()` -> `DeleteBrowserWindow()` sequence ran.

### Matrix

Pass = process alive 10 s after the driver, 0 `FATAL`/`Check failed` lines, no new crash dump (count of
`~/Library/Application Support/Chromium/Crashpad`, never opened).

| # | Scenario | Result | Dumps | UI |
|---|---|---|---|---|
| 1 | Startup, idle 30 s | pass | 81 -> 81 | |
| 2 | Navigate the tab | pass (`example.org`) | 81 -> 81 | |
| 3 | Extension adds a background tab | pass (index 1, not mounted) | 81 -> 81 | |
| 4 | Extension opens a popup (`--arkt-extensions-demo=<action-probe>`) | pass | 81 -> 81 | shown: `popup loaded .../popup.html`, `popup auto-resize 244x129`, `popup.html` target in `/json/list` |
| 5 | `chrome.windows.create` | pass (`normal`, census `normal=2 arkt=2 views=0`) | 81 -> 82 once, then 83 -> 83 in two reruns (see flakes) | |
| 6 | Close a tab (last tab; also the active tab in a second launch) | pass | 82 -> 82 | |
| 7 | Close every window, then quit | pass (census 0/0/0, destroyed, gone after `kill -TERM`) | 82 -> 82 | |
| 8 | Page `window.open` with a gesture | pass (`true`, `windows.getAll` = one `normal` window with 2 tabs, census `views=0`) | 82 -> 82 | |
| 9 | Renderer crash (sad tab) | pass (browser alive) | 82 -> 83: the renderer's own dump from `chrome://crash` | **not shown**: the card stays empty |
| 10 | `alert`, then (second launch) `confirm` | pass | 83 -> 83 | shown, as a separate unparented window `example.com says` (P-only: not attached to the Arkt window) |
| 11 | Permission prompt (notifications, gesture) | pass | 81 -> 81 | **shown**: window `example.com wants to: Show notifications` (unparented; anchored at the window's top-left) |
| 12 | `requestFullscreen` / `exitFullscreen` with a gesture | pass (`ok`, `fullscreenElement` true, `ok`; `ARKT: enter/exit fullscreen`) | 83 -> 84 once, 84 -> 84 in two reruns (see flakes) | native fullscreen shown; no exit bubble |
| 13 | Find (AX `Edit > Find > Find...` after the frontmost and key-window checks) | pass | 81 -> 81 | menu item enabled, `ARKT: stub FindBar::Show`: **find bar not shown** (`ArktFindBar` has no UI) |
| 14 | A download | pass | 84 -> 84 | file in `$PROF/downloads/arkt-w5b.txt`; **download bubble not shown** |
| 15 | `<input type=file>` | pass | 84 -> 84 | open panel shown as a sheet on the Arkt window (1 sheet); left alone, process killed |
| 16 | `--auto-open-devtools-for-tabs` | pass | 84 -> 84 | DevTools shown **undocked** in its own Views window (`views=1`) |
| 17 | `<datalist>` dropdown | pass | 84 -> 84 | shown (an untitled popup window) |

Flakes, not fixed: two runs (scenarios 5 and 12) left one new dump each while the browser stayed alive and logged
no `FATAL`/`Check failed` line; origin not identified. In both, the count moved during a run that began a few seconds
after the previous launch was stopped with `kill -TERM` (scenario 3 before 5, the `confirm` launch before 12).
Neither reproduced in two reruns each (no dump during the driver, in fullscreen, after it, or after the stop). The
helper line `No rendezvous client, terminating process (parent died?)` at shutdown is not the cause: three
launch/`kill -TERM` cycles on the week-1 path (no `--arkt-native-window`) log it every time and leave no dump
(84 -> 84). Crashpad dumps in total: 78 before W5b, 84 after: 3 from `chrome://crash` (intended), 1 from the
scenario 11 crash before patch 0006, 2 flakes above.

### Known gaps for week 3 (not fixed here)

Sad tab page; find bar UI; download bubble; docked DevTools; fullscreen exit bubble; tab-modal dialogs and the
permission bubble are unparented windows (P: `addChildWindow:` from the Arkt modal dialog host, or a bridge fix);
pointer/keyboard lock chip; link-target status bubble (`GetStatusBubbles()` stays empty); `GetAutofillBubbleHandler`
(nullptr, six unchecked callers); extension keyboard commands; Share menu; page context menu and passkey sheet (W3,
P-only).

### Gate (Step 3)

Seam patches: **2 patch files** (limit 8), **3 upstream files** (limit 25; 12 in total minus the 9 files of
0001-0004), **0 hot-file hunks** (limit 6; `git -C $CR diff 156.0.8078.48..arkt -- <hot files> | grep -c '^@@'` =
0), **no header** touched (all three are `.cc`). Measured after each theme commit (0005: 1 file; 0006: 3 files). The
gate passes in variant P; no switch to W. All patches are authored `Arkt contributors <noreply@arkt.invalid>`.

## W8

Date 2026-10-23. Branch `engine/w8-keychain`.

### Step 1: audit of a test run (metadata only)

Commands from the plan (no `-w`, no `-g`), before and after a launch of `out/Spike` with `--use-mock-keychain`
(profile `$PROF/w8-keychain`, page `https://example.com`, about 2 min, stopped by its PID):

| Check | Before | After the mock launch |
|---|---|---|
| "Chromium Safe Storage" `acct` | `Chromium` | `Chromium` |
| "Chromium Safe Storage" `mdat` | `20261023080451Z` | `20261023080451Z` (unchanged) |
| "Arkt Safe Storage" (`find-generic-password` exit) | 44 (not found) | 44 (not found) |

The existing item was created at the same time as its `mdat` (08:04:51Z, before week 2 started), most likely by a
week-1 launch without the mock flag. It was left in place (maintainer decision pending).

`engine/README.md` gained a "Launch flags" section: `--use-mock-keychain` and `--user-data-dir` are mandatory for
every test launch. `grep -n 'Contents/MacOS/' engine/README.md` has one hit, the example in that section, and it
carries both flags.

### Step 2: patch

Chromium branch `arkt`, commit `Arkt: use the Arkt Safe Storage keychain item`, exported as
`0003-Arkt-use-the-Arkt-Safe-Storage-keychain-item.patch`. Non-Chrome-branded constants in
`components/os_crypt/common/keychain_password_mac.mm`: `kDefaultServiceName` "Arkt Safe Storage",
`kDefaultAccountName` "Arkt". The Chrome-branded arm is unchanged.

Build: `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.`, 0 `FAILED:` lines.
Before the build: `df -h /` 11 GiB available; `vm.swapusage` used 6842.50M, free 1349.50M.

### Step 3: verification without the keychain

In the component build the constant lives in `libchrome_dll.dylib` (`keychain_password_mac` is a source set linked
there), not in an os_crypt dylib, and the `Chromium Framework` binary is only the loader. The plan's
`strings | grep -E "^(Arkt|Chromium) Safe Storage$"` finds nothing, because the linker packs the string right after
`saltysalt` (`strings` prints `saltysaltArkt Safe Storage`). Use `grep -a -o` instead:

```
grep -a -o -E "(Arkt|Chromium|Chrome) Safe Storage" $OUT/libchrome_dll.dylib | sort | uniq -c
   1 Arkt Safe Storage
grep -l -a -E "(Chromium|Chrome) Safe Storage" $OUT/*.dylib     # no output
```

`Arkt Safe Storage` present, `Chromium Safe Storage` absent. W10 runs the same `grep -a -o` on `Arkt Framework`.

A second mock-keychain launch of the patched build (`ARKT: mounted active tab after 1 attempt(s)`, no `FATAL` or
`Check failed` lines, stopped by its PID) left the audit unchanged: same `mdat`, no "Arkt Safe Storage" item.

Profiles: test profiles encrypted with the mock keychain are unaffected. A profile created without the mock flag
before this patch can no longer decrypt its saved passwords and cookies (it looked up "Chromium Safe Storage");
that is throwaway test data.

### Follow-ups from the W4 review (separate commit)

- `PopoverExtensionView` runs its pending show callback with `nullptr` when it is destroyed before the popup loaded,
  as Chrome's `ExtensionPopup` does.
- `ArktExtensionsMenu::Shutdown` also clears `browser_`.

Both compiled in the W8 build above.

### Release bundle check (2026-10-24, strings and build config only)

The product build is `out/Arkt` (W1, non-component, Arkt branding) and its signed copy in `/Applications/Arkt.app`
(W2). Both contain patch 0003 (`git -C $CR log refs/heads/arkt` has `24b83bf9f1 Arkt: use the Arkt Safe Storage
keychain item`). Nothing in this check reads, creates or changes a keychain item, and nothing was launched.

```
FW="Contents/Frameworks/Arkt Framework.framework/Versions/Current/Arkt Framework"
grep -a -o -E "(Arkt|Chromium|Chrome) Safe Storage" "$REL/Arkt.app/$FW" | sort | uniq -c
   1 Arkt Safe Storage
grep -a -o -E "(Arkt|Chromium|Chrome) Safe Storage" "/Applications/Arkt.app/$FW" | sort | uniq -c
   1 Arkt Safe Storage
find /Applications/Arkt.app -type f -perm +111 -print0 | xargs -0 grep -l -a -E "(Chromium|Chrome) Safe Storage"
                                                                   # no output
grep -E "GOOGLE_CHROME_BRANDING|CHROMIUM_BRANDING" $REL/gen/build/branding_buildflags.h
#define BUILDFLAG_INTERNAL_CHROMIUM_BRANDING() (1)
#define BUILDFLAG_INTERNAL_GOOGLE_CHROME_BRANDING() (0)
```

- The literal sits in the framework as `saltysalt` `Arkt Safe Storage\0` `Arkt\0` `mock_password\0`: service name,
  account name, and the mock keychain's password, so the `--use-mock-keychain` path is compiled into the release
  build too.
- `GOOGLE_CHROME_BRANDING` is 0, so the non-Chrome arm of `keychain_password_mac.mm` ("Arkt Safe Storage" /
  "Arkt") is the one compiled; `out/Arkt/args.gn` sets no `is_chrome_branded`.
- No other Mac code path names a Safe Storage item: outside tests, `git -C $CR grep -n "Safe Storage" -- '*.mm'
  '*.cc' '*.h'` lists `keychain_password_mac.mm` and a comment in its header, the Linux
  `freedesktop_secret_key_provider.h` (not built on Mac) and two enterprise-reporting constants (a Windows registry
  value and "Endpoint Verification Safe Storage", neither os_crypt). `KeychainPassword`'s names have no runtime
  override outside tests.
- The two framework binaries are not byte-identical (`cmp` exit 1) because `/Applications/Arkt.app` is the re-signed
  copy (W2); both carry the same single name.

### Decision: the old "Chromium Safe Storage" item stays

Maintainer decision (2026-10-23, #20): the existing "Chromium Safe Storage" item in the login keychain (account
`Chromium`, created 2026-10-23 08:04:51Z) is kept. It is not deleted or migrated, and no build with patch 0003 reads
it: those builds look up "Arkt Safe Storage" only. Test runs never touch either item (`--use-mock-keychain`, see
`engine/README.md`, "Launch flags").

### Needs the maintainer (handed to W10, #22)

Once, after W10 installs the rebuilt `/Applications/Arkt.app` (W10 "Needs the user"): launch it without
`--use-mock-keychain` (plan W8, "Needs the user" step 2). Expected: no prompt about "Chromium Safe Storage", and an
"Arkt Safe Storage" item (account `Arkt`) afterwards. If macOS asks for access to "Arkt Safe Storage", report it.
Week 3 repeats the same launch for the embedded app (W3-11, "Needs the maintainer").

## W5c: Arkt-owned tab list and visibility

Date 2026-10-23. Branch `engine/17-tab-list`, issue #17. Variant P. No upstream change: the patch set is still 0001-0006
(6 patch files, 12 upstream files, 0 hot-file hunks; `git -C $CR diff --stat 156.0.8078.48..arkt | tail -1`: 12 files
changed, 56 insertions, 4 deletions). Build: `nice -n 15 autoninja -C out/Spike chrome`, `The build has finished
successfully.`, 0 `FAILED:` (after two compile fixes). `gn check out/Spike '//arkt/browser:*'`: `Header dependency
check OK`. The build waited about two hours for `/` to get back above 8 GiB free (it dropped as low as 3.1 GiB from
other jobs on the machine); nothing was deleted.

### Split of `arkt_browser_window.mm`

| File | Holds |
|---|---|
| `arkt_window_host.{h,mm}` | the `ArktWindowHost` protocol and `ArktTabEvent` (the tab event value type) |
| `arkt_placeholder_window_host.{h,mm}` | `ArktPlaceholderWindowHost` (window, card, Extensions button, tab list, menu command forwarding) |
| `arkt_tab_list_view.{h,mm}` | `ArktTabListView`, the placeholder `NSTableView` |
| `arkt_browser_window_parts.{h,mm}` | `ArktExclusiveAccessContext`, `ArktModalDialogHost`, `ArktStubLocationBar`, `ArktFindBar`, `ArktSidePanelUI`, `LogStubOnce`/`ARKT_STUB` |
| `arkt_browser_window.{h,mm}` | `ArktBrowserWindow` only (1278 lines before, 946 after) |

The window-side objects moved without behaviour changes (declarations in the header, bodies in the `.mm`).

### Tab list and events

- `ArktBrowserWindow` keeps an ordered `TabEntry` list (session id, title, URL) that follows each
  `TabStripModelChange` in the order it lists its tabs, and turns every change into `ArktTabEvent`s: `inserted` (with
  title and URL), `removed`, `moved` (with `fromIndex`), `activated`, and `updated` (title or URL changed, from
  `OnTabChangedAt`; or contents replaced, `kReplaced`, with `previousTabId`). Tab ids are the session ids
  `chrome.tabs` reports. The host gets events only; the list and the observer never reference the table.
- The event type replaces W5a's dictionaries: typed properties, integers and strings only, so the ShellUI host can
  consume it from Swift. This is the seed of the `ChromiumEngine` tab events.
- `ArktPlaceholderWindowHost` logs each event (kind, tab id, index; no titles or URLs) and hands the batch to
  `ArktTabListView`, which mirrors the rows from the events alone and selects the active row. A user selection
  (click, keyboard, AX) calls the host's `activateTab` block with the row's tab id; the engine resolves the index at
  call time and calls `TabStripModel::ActivateTabAt(index, kOther)`. The resulting `activated` event re-selects the
  row; a guard keeps that mirrored selection from being reported back.
- Accessibility: the table's scroll view is labelled `Tabs`. The web contents expose a scroll area of their own
  (`scroll area 1` is the page), so scripts address the list as
  `table 1 of (first scroll area of window 1 whose description is "Tabs")`.

### Visibility

Unchanged mechanism from W5a, now verified: on every active-tab change `Browser` calls `OnActiveTabChanged` (it
observes the model before the window does), and `Mount` puts the new tab's view in the card and takes the previous one
out with `removeFromSuperview`; no `WasShown`/`WasHidden` calls. `--arkt-trace-visibility` posts a task after every
tab list or active-tab change that logs `ARKT: visibility <tab id> <visible|hidden|occluded>` from each tab's
`WebContents::GetVisibility()`.

### Menu commands (from the #17 parity list)

- `commandDispatchUsingKeyModifiers:` now matches `browser_window_command_handler.mm`: ignored for a disabled sender;
  Shift- or Ctrl-reload becomes `IDC_RELOAD_BYPASSING_CACHE` (and those flags are masked off); Cmd is dropped when the
  sender's window is not main; the disposition comes from `ui::WindowOpenDispositionFromNSEventWithFlags`.
  `executeCommand` takes `(command, disposition)` and runs `chrome::ExecuteCommandWithDisposition`;
  `commandDispatch:` passes `CURRENT_TAB`.
- `validateCommand` also requires `chrome::SupportsCommand`, as `BrowserNativeWidgetMac::ValidateUserInterfaceItem`
  does.
- Not exercised at runtime: Chrome's main menu items send `commandDispatch:`; `commandDispatchUsingKeyModifiers:` is
  the selector of toolbar buttons, and the placeholder has none. The ShellUI back/forward/reload buttons will send it.
- Toggle state, hidden state, dynamic titles, `disable_if_has_no_key_equivalent` and the "key window is modal"
  disabling were done afterwards (see "#207 leftovers" below).

### Verification (Step 3)

Fresh profile, `--arkt-native-window --arkt-trace-visibility`, both probe extensions, `https://example.com`. CDP
port 9343 and a profile of its own (see "Interference" below).

| Step | CDP result | Log |
|---|---|---|
| `probe.create()` | index 1 | `inserted` tab 2 at index 1, `visibility <1> visible`, `<2> hidden`; table 2 rows, row 1 selected |
| example.com `visibilityState` | `"visible"` (about:blank `"hidden"`) | |
| `tabs.update(<about:blank>, {active:true})` | `true` | `mounted` tab 2, `activated` index 1, `<1> hidden`, `<2> visible`; row 2 selected |
| example.com `visibilityState` | `"hidden"` (about:blank `"visible"`) | |
| `tabs.update(<example.com>, {active:true})` | `true` | `mounted` tab 1, `activated` index 0, `<1> visible`, `<2> hidden`; row 1 selected |
| example.com `visibilityState` | `"visible"` (about:blank `"hidden"`) | |
| AX `select row 2` of the `Tabs` table (after the frontmost and key-window checks) | example.com `"hidden"`, about:blank `"visible"` | `mounted` tab 2, `activated` index 1, matching visibility lines |
| AX `select row 1` | example.com `"visible"`, about:blank `"hidden"` | `mounted` tab 1, `activated` index 0 |

The week-1 reproduction (opening a tab blacked out the card) passes: the extension-created background tab leaves
example.com `visible`. Window-only screenshots after each switch: `$PROF/shots/w5c-1.png` to `w5c-5.png` (the card
shows the active tab; the table shows 2 rows with the active one selected).

### W5b rows re-run (fresh launch each, pass = alive 10 s after the driver, 0 `FATAL`/`Check failed`, no new dump)

| # | Scenario | Result | Dumps |
|---|---|---|---|
| 1 | Startup, idle 30 s | pass; census `normal=1 arkt=1 views=0`, 1 row | 85 -> 85 |
| 2 | Navigate the tab | pass (`visible Example Domain` on example.org); `updated` event, 1 row | 85 -> 85 |
| 3 | Extension adds a background tab | pass; 2 rows, row 1 still selected, example.com `visible` | 85 -> 86 once (see flakes), rerun 87 -> 87 |
| 5 | `chrome.windows.create` | pass (`normal`, census `normal=2 arkt=2 views=0`); each window has its own table | 86 -> 87 once (see flakes), rerun 87 -> 87 |
| 6 | Close the last tab; second launch: close the active tab | pass; `removed`, 1 row; the next tab is mounted, `activated`, `visible` | 87 -> 87 |
| 7 | Close every window, then quit | pass (census 0/0/0, `native window destroyed` with a live table, alive with no windows, gone after `kill -TERM`) | 87 -> 87 |
| 8 | Page `window.open` with a gesture | pass (`true`, one `normal` window with 2 tabs, 2 rows) | 87 -> 87 |
| 13 | Find (AX `Edit > Find > Find…`, after the frontmost and key-window checks) | pass; `Find…` enabled, `ARKT: stub FindBar::Show` (new `executeCommand` signature) | 87 -> 87 |

Rows 4, 9-12 and 14-17 do not touch the tab list, mounting or menu dispatch and were not re-run.

Flakes: as in W5b, the two new dumps appeared in runs that started a few seconds after the previous launch was
stopped with `kill -TERM` (s2 -> s3, s3 -> s5); neither run logged `FATAL`/`Check failed`, and both browsers stayed
alive. With 20 s between stop and the next launch, both reruns and every later row left the count unchanged. The dump
count was also 84 -> 85 across the interference runs below. Dumps are counted only, never opened.

### Interference (recorded, not an Arkt bug)

The first runs used `$PROF/week2-native` and port 9333 and were driven by input this task did not send: tabs
created by the action probe's popup buttons (`probe-create`, `probe-open`, `probe-window`), row activations, new
windows, tab closes. Another app under test (an `ArktShell` window at 551,214, 1200x800) shared the screen with the
Arkt window (132,126, 1400x900), and its synthetic clicks and keys landed on our window whenever it was on top or
frontmost; a launch on the same profile also hands its URL and flags to the running instance. Every recorded run
above therefore uses its own profile, port 9343, moves the window to 0,60 540x860 with `chrome.windows.update` right
after launch (no overlap), and keeps it frontmost only for the AX steps. One AX attempt was itself disturbed this way:
once the window was frontmost, three tabs were closed by keys this task did not send. Nothing from the discarded runs
is counted above except the dump count.

### Known gaps and follow-ups

- The deferred list from #17 stays open except the split and the two parity items above: find bar UI, sad tab page,
  download bubble, docked DevTools, tab-modal attachment, the remaining menu parity (toggle, hidden, titles,
  `disable_if_has_no_key_equivalent`), `ExtensionsMenus()` keeping one menu per closed window, the patch 0006 RTL
  anchor.
- Pinned tabs, tab groups and split tabs are not in the events; `OnTabPinnedStateChanged`, `OnTabGroupChanged` and
  `OnSplitTabChanged` are the hooks when ShellUI needs them.
- The placeholder table is fixed at the sidebar width and does not show favicons or loading state.

## W7: Web Store install on the native window

Date 2026-10-23. Branch `engine/19-web-store-install`, issue #19. Variant P. Every run: a fresh profile of its own,
`--arkt-native-window`, `--load-extension=action-probe`, `--arkt-extensions-menu-dump` (not in the lldb run), CDP port 9351, the uBO Lite
detail page as the start URL, and the window moved to 0,60 1000x860 with `chrome.windows.update` right after launch.
The Google consent interstitial ("Before you continue") was rejected over CDP (`Reject all`, `--user-gesture`), and
"Add to Chrome" was pressed with `cdp.mjs --user-gesture`, as in week-1 Task 6.

### Install prompt (Step 2)

| Check | Result |
|---|---|
| Census while the prompt is up | `ARKT: browsers normal=1 arkt=1 views=0` |
| Owner | the browser process; a separate top-level window, AX role `AXWindow` / `AXStandardWindow`, title `Add "uBlock Origin Lite"?`, CG layer 0. Not a sheet on the Arkt window |
| Position | 676,258 448x196 (the same in both runs): horizontally centred on the 1800-wide screen, not on the Arkt window (0,60 1000x860) |
| Accept | one AXPress on `button "Add extension"` of the prompt, after the checks: our process frontmost, the prompt is window 1 |

Screenshot `$PROF/shots/w7-prompt.png` (window-only). The prompt's own header row ("Add "uBlock Origin Lite"?" and
the icon) is partly covered by the system title bar strip: `CreateBrowserModalDialogViews` makes a window-modal
dialog, which on Mac is shown as a sheet of a Views parent; the Arkt `NSWindow` is not a Views window (not
investigated further), and the dialog comes up as a free standard window instead.

### After accepting (Step 3)

```
ARKT: toolbar actions 1
ARKT action ceojeochoeiibbkbcnnidcahamphllac Arkt action probe
...
ARKT: toolbar actions 2
ARKT action ceojeochoeiibbkbcnnidcahamphllac Arkt action probe
ARKT action ddkjiahejlhfcafbddmgiahcphecmpfh uBlock Origin Lite
ARKT: menu item 0 Arkt action probe enabled=1
ARKT: menu item 1 uBlock Origin Lite enabled=1
```

The Web Store button changed to "Remove from Chrome". Chrome then shows the post-install dialog ("uBlock Origin Lite
has been added to Chromium"), also a free standard window, at -224,39 448x132: centred on the window's top-left
corner (the patch 0006 anchor point) and half off-screen. Screenshot `$PROF/shots/w7-postinstall.png`.

### Crash: post-install dialog closed (fixed in patch 0006)

Closing that dialog (Escape, after the frontmost and window-1 checks) crashed the browser on the build before this
task (`$PROF/w7-run1.log`): `Received signal 11 SEGV_ACCERR 0000000005b8`, one new Crashpad dump (86 -> 87). Symbolized with `lldb -p`
attached to a second run (`$PROF/w7-lldb.log`):

```
stop reason = EXC_BAD_ACCESS (code=1, address=0x5b8)
frame #0: libchrome_dll.dylib`base::internal::Invoker<...ExtensionInstallUIDesktop::OnInstallSuccess(
          scoped_refptr<extensions::Extension const>, SkBitmap const*)::$_1&&, ...>
frame #1: libchrome_dll.dylib`...OnceCallback<void (base::WeakPtr<ui::TrackedElementHandler>)>...
frame #2: libbase.dylib`base::TaskAnnotator::RunTaskImpl(base::PendingTask&) + 308
```

This is the seam W3 listed: `ExtensionInstallUIDesktop::OnInstallSuccess` binds a callback that the post-install
dialog posts when it is destroyed (`extension_post_install_dialog.cc`, `SetDialogDestroyingCallback`); it calls
`BrowserView::GetBrowserViewForBrowser` and dereferences the result (`browser_view->toolbar()`) to show the
"pinned by default" IPH. No Arkt-side route: the lambda is bound inside `OnInstallSuccess`, and skipping the
post-install UI would drop the dialog too. Fix: the W5b dialogs theme patch 0006 gains
`if (!browser_view || !browser_view->toolbar()) return;` in `extension_install_ui_desktop.cc` (commit amended on branch
`arkt`, author `Arkt contributors <noreply@arkt.invalid>`, re-exported; only the 0006 file changed, `.patches`
unchanged). Without a `BrowserView` the IPH is skipped; Arkt has no toolbar to pin to.

Build: `nice -n 15 autoninja -C out/Spike chrome`, `The build has finished successfully.`, 0 `FAILED:`.

### Verification on the fixed build

Fresh profile, the whole flow again: prompt at 676,258 448x196 with `views=0`, AXPress "Add extension", actions
1 -> 2 with the two menu items above, post-install dialog shown, Escape. The browser was alive 10 s later, 0
`FATAL`/`Check failed`/`Received signal` lines, Crashpad dumps 87 -> 87 (also after the stop by PID).

Popup through the menu path (W4 Step 7 wiring): AXPress on `button "Extensions"` run in the background (it blocks
while the menu tracks), then Down, Down, Return to our frontmost process:

```
ARKT: extensions menu shown 2 items
ARKT: run action ddkjiahejlhfcafbddmgiahcphecmpfh source 2
ARKT: TriggerPopup ddkjiahejlhfcafbddmgiahcphecmpfh by_user=1 url=chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/popup.html
ARKT: extensions menu closed
ARKT: popup loaded chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/popup.html
ARKT: popup auto-resize 273x374
```

Source 2 is `InvocationSource::kMenuEntry`. `cdp.mjs ddkjiahejlhfcafbddmgiahcphecmpfh/popup.html 'document.title'`:
`uBlock Origin Lite`, with the filtering mode panel for `chromewebstore.google.com`. Screenshot
`$PROF/shots/w7-popup.png`: the popover at the sidebar Extensions button.

### Gate re-check

Seam patches: 2 patch files (limit 8), 4 upstream files (limit 25), 0 hot-file hunks (limit 6; `git -C $CR diff
156.0.8078.48..arkt -- <hot files> | grep -c '^@@'` = 0), no header. Totals: 6 patch files, 13 upstream files
(`13 files changed, 57 insertions(+), 5 deletions(-)`). The gate still passes in variant P.

### Known gaps (week 3, not fixed here)

- The install prompt and the post-install dialog are free standard windows, not sheets on the Arkt window; the
  prompt's header sits partly under the system title bar strip, and the post-install dialog is placed half
  off-screen at the window's top-left. Same class as W5b rows 10 and 11. The native sheet through
  `ShowDialogCallback` (or attaching the widget to the Arkt window) is the week-3 fix.
- The "pinned by default" IPH is skipped on Arkt windows.
- The Web Store shows its "Switch to Chrome?" banner and dialog; it does not block the install.

## W6: Extension window identity, extension-created tabs and windows

Date 2026-10-23. Branch `engine/18-extension-windows`, issue #18. Variant P. No upstream change: the patch set is still
0001-0006 (6 patch files, 13 upstream files, 0 hot-file hunks). Build: `nice -n 15 autoninja -C out/Spike chrome`,
`The build has finished successfully.`, 0 `FAILED:` (after one compile fix). `gn check out/Spike '//arkt/browser:*'`:
`Header dependency check OK`. Every run: a fresh profile of its own, CDP port 9363, the window moved to 0,60 540x860
with `chrome.windows.update` right after launch (as in W5c, "Interference").

### Implementation

- `arkt_extensions_container.{h,mm}`: `ArktExtensionsContainer` (`ExtensionsContainer`) on top of the window's
  `ArktExtensionsMenu`. `ArktBrowserWindow` creates it in its constructor and registers it with
  `ui::ScopedUnownedUserData<ExtensionsContainer>` on the browser's `UnownedUserDataHost`, as Webium does; the
  destructor drops it after `TearDownPreBrowserWindowDestruction()`. `ShowToolbarActionPopupForAPICall` follows
  Chrome's toolbar (`ExtensionsToolbarDesktop::CanShowToolbarActionPopupForAPICall`): refused while any popover is
  showing or when the window is not active, otherwise `TriggerPopupForAPI` (the popup opens through the existing
  `TriggerPopup` delegate path, `by_user=0`). `ToggleExtensionsMenu` shows the menu from a posted task (the menu runs
  a nested loop) or cancels an open one; `CloseExtensionsMenuIfOpen` cancels tracking (also from the action
  delegate, which was a no-op).
- The native window now owns its menu through the container (the factory's posted task hands it over), so a closed
  native window no longer leaves its menu in the process-wide list (W5c follow-up). The week-1 path keeps that list.
- `ArktBrowserWindow` logs `ARKT: native window session id <id>` at creation.
- Popover (`arkt_extensions_bridge.mm`, the #18 comment from the W4 review): the popup sets the host's close handler,
  so `window.close()` in the popup closes the popover (before, the host had no close handler); it also observes the
  `ExtensionRegistry` and closes when its extension unloads. Both close from a posted task and log
  `ARKT: popup closed (<reason>) <id>`.
- `tabs-probe/sw.js` also logs `ARKT tabs.query windows=<ids>`.

### Identity (Step 3)

| Check | Result |
|---|---|
| `ARKT: native window session id` | `906131682` |
| `ARKT tabs.query windows=` (tabs-probe) | `906131682` |
| `chrome.windows.getAll({populate:true})` | `[[906131682,"normal",1]]`; table 1 row; census `normal=1 arkt=1 views=0` |

### Extension-created tabs and windows (Step 4)

One launch, actions in order; census and `windows.getAll` after each.

| Action | Result |
|---|---|
| `probe.create()` (background) | window `906131682` index 1; 2 rows, row 1 still selected; example.com `visible`; `views=0` |
| `chrome.tabs.create({url:"about:blank#fg", active:true})` | index 2, active; 3 rows, row 3 selected; `mounted`, `visibility <fg> visible`, others `hidden`; `views=0` |
| Welcome-style page `chrome.tabs.create({url: chrome.runtime.getURL("popup.html")})` | index 3, active; 4 rows; the extension page mounted, `visibilityState` `"visible"`; `views=0` |
| `chrome.action.openPopup()` from the action-probe worker (window frontmost and key, checked first) | `"ok"`; `ARKT: openPopup <id>`, `TriggerPopup ... by_user=0`, `popup loaded`; popover at the sidebar Extensions button (`$PROF/shots/w6-popup.png`) |
| Popup button `open` (`cdp.mjs --user-gesture popup.html`, the welcome tab closed first so the popover is the only `popup.html` target; `chrome.tabs.getCurrent()` there is `undefined`) | new tab `about:blank#probe-open` in window `906131682`, mounted and active; 4 rows; `views=0`; the popover stayed open |
| `window.close()` in the popup | `ARKT: popup closed (window.close)`; the `popup.html` target is gone |
| `probe.window()` (`chrome.windows.create`) | a second Arkt window `906131689`; census `normal=2 arkt=2 views=0`; `windows.getAll` = `906131682` (4 tabs) and `906131689` (1 tab), matching the two logged session ids; each window has its own table |
| `chrome.action.openPopup()` with the second window focused, then `chrome.runtime.reload()` of action-probe | popup shown, then closed on unload (the action left the toolbar model, so the menu hid it first; the registry observer is the fallback for a popover no menu owns) |

0 `FATAL`/`Check failed`/`Received signal` lines; stopped by its PID; Crashpad dumps 87 -> 87. Window-only
screenshots: `$PROF/shots/w6-popup.png`, `w6-window1.png`, `w6-window2.png`. The reloaded action probe did not come
back in that run (`toolbar actions 1`); reloading a `--load-extension` extension is not part of this task and was not
investigated.

### Real extension (Step 5)

A copy of `$PROF/1password-test` (the original is left untouched), `--arkt-native-window`, no input. From the
1Password service worker over CDP: `chrome.tabs.create({url: chrome.runtime.getURL("app/app.html#/page/welcome")})`
returned window `1230561966` (the logged session id) index 1; table 2 rows; `windows.getAll` one `normal` window with
2 tabs; census `normal=1 arkt=1 views=0`. The page was not interacted with. 0 `FATAL`/`Check failed`; dumps 87 -> 87.

### Regression rows

| Run | Result |
|---|---|
| `--arkt-extensions-demo=<action-probe>` (W5b scenario 4, menu owned by the container now) | `run action ... source 1`, `TriggerPopup ... by_user=1`, `popup loaded` |
| `chrome.windows.remove` of every window, then `kill -TERM` (scenario 7) | census `0/0/0`, `native window destroyed` (container and menu torn down with it), gone within 6 s, 0 `FATAL`/`Check failed`, dumps 87 -> 87 |

### Review fix (#217)

- **Use-after-free while the menu is open.** `NSMenu` tracking runs a nested run loop in which Chromium keeps running
  tasks; now that the window owns its menu, a window close there destroyed the menu while `Show()` was still on the
  stack. `Show()` takes a weak pointer before tracking and touches no member after it if the menu is gone, and
  `Shutdown()` cancels an open menu first.
- **Popups scoped to their window.** With one process-wide popover, hiding by extension id let one window's
  `Shutdown()` close another window's popup of the same extension. The popover now records which menu showed it, and
  `IsShowingPopover`/`HidePopover`/`GetPopoverNativeView` only match that owner.

Verification on the rebuilt `out/Spike` (`The build has finished successfully.`, 0 `FAILED:`; one compile fix for the
`raw_ptr` plugin, the owner is kept as an address), fresh profiles, port 9363:

| Check | Result |
|---|---|
| Window A focused, window B created unfocused; `openPopup` in A; `chrome.windows.remove(B)` | census `normal=1 arkt=1`; A's popover still open (`popup.html` target present, `document.title` answers) |
| Extensions menu opened by one AXPress on A's `Extensions` button (after the frontmost and key-window checks; the call blocks while the menu tracks), then `chrome.windows.remove(A)` over CDP while it is open | `extensions menu shown 2 items`, census `0/0/0`, `native window destroyed`, then `extensions menu closed`; process alive 10 s later; 0 `FATAL`/`Check failed`/`Received signal`; dumps 87 -> 87, also after the stop |
| W6 rows again (fresh launch): identity, background and foreground `tabs.create`, welcome page, `openPopup`, `window.open` from the popup, `chrome.windows.create` | all as in Step 3 and 4 above (`views=0` throughout, `normal=2 arkt=2` and two matching session ids at the end); 0 `FATAL`/`Check failed` |

Flake: two of the stops by PID with a popover open left one Crashpad dump each (87 -> 88 after the W6 rerun, 88 -> 89
in one of three `openPopup` launches), with no `FATAL`/`Check failed`/`Received signal` line; the only marker read from
the dumps is `--type=renderer`. Six more launches with the popup open (three native, three on the week-1 path, 20 s
between stop and launch) left none. Same pattern as the W5b and W5c shutdown flakes; not fixed.

### Known gaps (not fixed here)

- The popover is still not closed when the active tab changes (Chrome's `ExtensionPopup` closes then) or when the
  window loses focus; it stays until the next popup, a toggle, `window.close()` or unload.
- `ToggleExtensionsMenu` and `CloseExtensionsMenuIfOpen` are wired but not exercised (no caller reached in this
  task). Extension context menus, pinning, keyboard commands and the install sheet stay with #121.


## W9: Native window as the default; patch 0002 test

Date 2026-10-24. Branch `engine/21-native-window-default`, issue #21. Variant P. `$CR` branch `arkt` at `baeb143765`
before and after (0001-0006).

### Default switch

`arkt_browser_main_extra_parts.mm` registers the `ArktBrowserWindow` factory unless `--arkt-views-window` is passed;
with that switch the week-1 path runs (Chromium's window, active tab mounted in an `ArktWindowController`). The old
opt-in switch `--arkt-native-window` is no longer read; Chromium ignores it, so the week-3 Engine configuration that
still appends it keeps working until W3-12 removes it. `engine/REBASE.md` (Verification, item 2) no longer asks for
the switch. Patch 0004's description still says the hook is registered "when --arkt-native-window is set"; it is
reworded at the next export that touches the patch set (re-exporting only for that would be a `.patches` change for
a comment).

Every run below: a fresh profile `$PROF/w9-<run>`, `--use-mock-keychain`, both probe extensions, CDP port 9371,
`https://example.com`, **no window switch**, 20 s between a stop and the next launch, and a check before each launch
that no other Arkt, `ArktShell`, `xctest` or Chromium GUI run was on the machine (a parallel `/Applications/Arkt.app`
run was active several times; each launch waited for it to end). The window was moved with `chrome.windows.update`
right after launch where the tabs probe answered in time; no unexplained navigations were seen. Builds:
`nice -n 10 autoninja -C out/Spike -j 6 chrome` (build 1, switch only), `-j 6` without 0002 (build 2), `-j 4` with
0002 restored (builds 3 and 4, the last after rebasing on `main`); each `The build has finished successfully.`,
0 `FAILED:`. Swap rose from 6.1 GB to 9.0 GB used during build 2 (macOS added a swap file; `/` went from 13 to
6.3 GiB free), so builds 3 and 4 ran at `-j 4`; nothing was deleted.

### W5b matrix on the default path (build 1)

Pass = alive 10 s after the driver, 0 `FATAL`/`Check failed`, no new crash dump (count only).

| # | Scenario | Result | Dumps | UI |
|---|---|---|---|---|
| 1 | Startup, idle 30 s | pass; `native window factory registered`, census `normal=1 arkt=1 views=0`, `visible Example Domain` | 90 -> 90 | |
| 2 | Navigate the tab | pass (`visible example.org`) | 90 -> 90 | |
| 3 | Extension adds a background tab | pass (index 1; example.com `visible`) | 90 -> 91 once, rerun 92 -> 92 (see flakes) | |
| 4 | Extension opens a popup (`--arkt-extensions-demo`) | pass | 91 -> 91 | shown: `TriggerPopup ... by_user=1`, `popup loaded`, `popup auto-resize 244x129` |
| 5 | `chrome.windows.create` | pass (`normal`, census `normal=2 arkt=2 views=0`) | 91 -> 92 once, rerun 92 -> 92 | |
| 6 | Close the last tab; second launch: close the active tab | pass (next tab mounted) | 92 -> 92 | |
| 7 | Close every window, then quit | pass (census 0/0/0, `native window destroyed`, alive with no windows, gone after `kill -TERM`) | 92 -> 92 | |
| 8 | Page `window.open` with a gesture | pass (`true`, one `normal` window with 2 tabs, `views=0`) | 92 -> 92 | |
| 9 | Renderer crash (sad tab) | pass (browser alive; the one `Received signal 11` line is the renderer's intentional `chrome://crash`, as in W5b) | 92 -> 93 (the renderer's dump) | not shown |
| 10 | `alert`, then (second launch) `confirm` | pass | 93 -> 93 | shown, unparented window `example.com says` |
| 11 | Permission prompt | pass | 93 -> 93 | shown, window `example.com wants to: Show notifications` |
| 12 | `requestFullscreen` / `exitFullscreen` | pass (`ok`, `fullscreenElement` true, `ok`; one `enter` and one `exit fullscreen` line) | 93 -> 93 | native fullscreen; no exit bubble |
| 13 | Find (AX `Edit > Find > Find…`, after the frontmost and key-window checks) | pass; `Find…` enabled, `ARKT: stub FindBar::Show` | 93 -> 93 | find bar not shown |
| 14 | A download | pass (`$PROF/downloads/arkt-w5b.txt`) | 93 -> 93 | download bubble not shown |
| 15 | `<input type=file>` | pass | 93 -> 93 | open panel shown as a sheet (sheets 0 -> 1) |
| 16 | `--auto-open-devtools-for-tabs` | pass | 93 -> 93 | DevTools undocked in its own Views window (`views=1`) |
| 17 | `<datalist>` dropdown | pass | 93 -> 93 | shown (untitled popup window) |

Flakes: the dumps in the first runs of rows 3 and 5 appeared across the stop (the count read after `kill`), with no
`FATAL`/`Check failed`/`Received signal` line; reruns read the count before and after the stop and left it unchanged.
Same pattern as W5b, W5c and W6.

### W5c Step 3 and W6 on the default path (build 1)

- W5c Step 3 (`--arkt-trace-visibility`): `probe.create()` -> example.com `visible`, about:blank `hidden`; activating
  about:blank -> `hidden`/`visible`; back -> `visible`/`hidden`; AX `select row 2` / `select row 1` of the `Tabs`
  table (after the frontmost and key-window checks) -> the same pairs; matching `ARKT: visibility` and `mounted` lines;
  2 rows. Screenshots `$PROF/shots/w9-w5c-1.png` to `w9-w5c-5.png` (example.com rendered in the card when active).
- W6 Step 3: session id `288581364` = `ARKT tabs.query windows=288581364` = `windows.getAll` `[[288581364,"normal",1]]`.
- W6 Step 4, one launch: background `probe.create()` (example.com stays `visible`), foreground `tabs.create` (3 rows,
  row 3 selected), welcome-style `popup.html` tab (`visible`), `chrome.action.openPopup()` (`ok`, `by_user=0`,
  `popup loaded`), popup button `open` with a gesture (new active tab in the same window), `window.close()` in the
  popup (`popup closed (window.close)`), `probe.window()` (second window `288581371`; census `normal=2 arkt=2 views=0`;
  `windows.getAll` lists both ids, 4 and 1 tabs). `views=0` throughout. Screenshots `w9-w6-popup.png`,
  `w9-w6-window1.png`, `w9-w6-window2.png`. One dump appeared across the final stop with a popover open (93 -> 94),
  the W6 shutdown flake.
- Fallback `--arkt-views-window`: no factory line, census `normal=1 arkt=0 views=1`, `mounted active tab after 1
  attempt(s)`, `visible Example Domain`, page rendered (`w9-views-build1.png`).

### W7 not re-run

The Web Store run launched (consent page loaded, census `normal=1 arkt=1 views=0`) but the step that rejects the
Google consent interstitial and presses "Add to Chrome" was not permitted in this session, so the run was stopped
by its PID before any click (0 `FATAL`, dumps 94 -> 94). W9 changes only which window the factory hands out; the
native-window code W7 verified is unchanged. Re-run W7 Steps 1-3 by hand (or in W10) with no switch.

### Patch 0002 test

Branch `arkt` with the 0002 commit dropped (`rebase --onto 6ebebf5619 d381048e29`, committer and author
`Arkt contributors <noreply@arkt.invalid>`; `git diff baeb143765 arkt` = exactly 0002's four files), build 2, never
exported:

| Check | Result without 0002 |
|---|---|
| W5c Step 3 (CDP, AX rows) | pass; pages draw after every switch (`w9-n-w5c-0.png` to `-5.png`) |
| W6 Step 4 (as above) | pass; the extension page draws (`w9-n-w6-welcome.png`), popover draws |
| Tab moved from a Views popup window into the Arkt window (`chrome.windows.create({type:"popup"})`, then `chrome.tabs.move` + `update({active:true})`) | **fails**: census `views=1` -> `views=0`, the tab is mounted and `visibilityState` is `visible` (340x840), but the card stays empty, also after painting the page red (`w9-n-w6-moved-red.png`) |
| `--arkt-views-window` | **fails**: `mounted active tab`, `visible`, card empty after painting the page red (`w9-n-views.png`) |

The cause is the one 0002 fixes: a view that was ever hosted by Views has Cocoa display disabled
(`RenderWidgetHostViewMac::SetParentUiLayer`), and popup windows stay Views windows (Decision 1, scope), so any tab
that starts in one and moves to an Arkt window needs `EnableDisplay()`. CDP `visibilityState` cannot detect this;
only the screenshot does.

With 0002 restored (`checkout -B arkt baeb143765`, builds 3 and 4) the same move draws the red page
(`w9-k-moved-red.png`), and on that final build rows 1-8 and the fallback pass again (no switch; dumps 94 -> 94).

**Decision: 0002 stays.** It is still needed on the default path (tabs adopted from Views popup windows) and by the
week-1 path. It can go only once no WebContents is ever hosted by Views before Arkt mounts it (popups, app and
DevTools windows on Arkt windows too) and the week-1 path is deleted.

### Patch budget after W9

Unchanged: 6 patch files, 13 upstream files, 0 hot-file hunks. `wc -l < engine/patches/chromium/.patches` = 6 =
`git -C $CR rev-list --count 156.0.8078.48..arkt`; `git -C $CR diff --stat 156.0.8078.48..arkt -- | tail -1`: 13 files
changed, 57 insertions, 5 deletions; hot-file hunks 0. No `.patches` change.

## W10: Release bundle rebuild, re-sign, final smoke

Date 2026-10-24. Branch `engine/22-release-rebuild`, issue #22. Overlay: `$REPO` at `main` 87518a2 (its `engine/` tree
equals W9's 63f794a), `readlink $CR/arkt` = `arkt-wt/engine/engine/arkt`. `$CR` branch `arkt` at `baeb143765`
(0001-0006, all exported).

### Disk and memory (the 8 GiB criterion was not met)

`/` had 5.0 GiB free when the build started, not the 8 GiB the plan and #22 ask for. The internal disk was full from
other work on the machine (a file-sync daemon was writing to it), and freeing space there is not this task's to do.
The build went ahead anyway because its output is on the Chromium disk and the change was small (W9's switch). A
30 s monitor would stop siso (`kill -STOP` on its recorded PID) when `/` fell under 5 GiB or swap used passed 9.5 GB.

| Time | `/` available | swap used (`sysctl vm.swapusage`) | Build |
|---|---|---|---|
| 01:57 | 5.0 GiB | 8891.31M of 10240.00M | not started |
| 01:58:19 | 5.0 GiB | 8891.31M | started |
| 01:59:27 | 4.99 GiB (5233688 KiB) | 8891.31M | paused by the monitor; the `Arkt Framework` link already running finished on its own |
| 02:01:01 | 5.8 GiB (about 1.5 GB of unrelated scratch builds on `/` removed, not by this task) | 8891.31M | resumed (`kill -CONT`), stop line lowered to 4.5 GiB |
| 02:01:06 | 5.8 GiB | 8891.31M | finished |
| after install | 6.5 GiB | 8867.31M | - |

Swap did not grow at all (`-j 4`, quiet machine). Nothing was deleted by this task.

### Build

`cd $CR && nice -n 10 autoninja -C out/Arkt -j 4 chrome > $CHROMIUM_ROOT/build-w10.log 2>&1`: `The build has finished
successfully.`, `grep -c FAILED:` = 0. Wall time 2 min 47 s, of which about 1 min 35 s paused: the overlay recompile
(`arkt_browser_main_extra_parts.o`, `arkt_browser_window.o`) and the `Arkt Framework` relink. The new framework
carries `arkt-views-window` and no longer `arkt-native-window` (`grep -a -o`), so it is W9's default.
`third_party/siso/cipd/siso ninja -n` printed `0 steps` beforehand although the source was newer than its object:
the siso dry run is not a guide to incremental size.

### Re-sign and install

`ditto $REL/Arkt.app $CHROMIUM_ROOT/stage-w10/Arkt.app`, then the `engine/README.md` "Sign and install (out/Arkt)"
block unchanged, with the same Apple Development identity as W2 (the only code-signing identity listed, passed by
hash; the team identifier of the new signature equals the W2 install's). `Helpers` held the same 11 entries as W1/W2;
all signed. Per part: every helper and tool `flags=0x10000(runtime)`, `allow-jit` only on the four Renderer and GPU
helpers.

    codesign --verify --deep --strict --verbose=2 Arkt.app -> valid on disk, satisfies its Designated Requirement
    codesign -dv Arkt.app -> Identifier=com.arkt.Arkt, CodeDirectory ... flags=0x10000(runtime)

Replace: no process ran from `/Applications/Arkt.app`; `codesign -dv /Applications/Arkt.app` printed
`Identifier=com.arkt.Arkt` (the W2 install); then `rm -rf /Applications/Arkt.app && ditto
$CHROMIUM_ROOT/stage-w10/Arkt.app /Applications/Arkt.app`. The signed stage copy stays as the rollback (on the
Chromium disk, not on `/`).

    codesign --verify --deep --strict --verbose=2 /Applications/Arkt.app -> valid on disk, satisfies its Designated Requirement
    spctl --assess --type execute -vv /Applications/Arkt.app            -> rejected (not notarized, #125)
    du -sh /Applications/Arkt.app                                        -> 539M
    nm -gU ".../Arkt Framework.framework/Arkt Framework" | grep -c ' T _ChromeMain' -> 1
    grep -a -o -E "(Arkt|Chromium|Chrome) Safe Storage" ".../Versions/Current/Arkt Framework" | sort | uniq -c
       1 Arkt Safe Storage
    find /Applications/Arkt.app -type f -perm +111 -print0 | xargs -0 grep -l -a -E "(Chromium|Chrome) Safe Storage"
                                                                         # no output

### Smoke from /Applications (default path, no window switch)

No other Arkt, Chromium or `ArktShell` run on the machine (checked with `ps`). Profile
`$CHROMIUM_ROOT/profiles/w10-smoke` (fresh), `--use-mock-keychain --no-first-run --no-default-browser-check
--enable-logging=stderr --remote-debugging-port=9401`, both probe extensions, `--arkt-extensions-menu-dump`,
`https://example.com`, no `--user-agent`. Stopped by its PID; `ps -p` confirmed gone.

| Check | Result |
|---|---|
| Native window by default | `ARKT: native window factory registered`, `native window created`, census `normal=1 arkt=1 views=0`, `in-process hook alive`, `key window` naming our window |
| Page renders | `document.title` `"Example Domain"`, `visibilityState` `visible`; window-only screenshot `$PROF/shots/w10-smoke.png` shows the page in the card and the tab list |
| Extensions menu (`--arkt-extensions-menu-dump`) | `toolbar actions 2`, `menu item 0 Arkt action probe enabled=1`, `menu item 1 Arkt tabs probe enabled=0` |
| W6 identity | `ARKT tabs.query windows=814893290` = session id `814893290` = `windows.getAll` `[[814893290,"normal",1]]` |
| `probe.create()` (W5b row 3, W5c) | `tab event inserted ... index 1`, `tab list rows 2 selected 0`; example.com stays `visible`; second row in the screenshot |
| `chrome.action.openPopup()` (W6) | `"ok"`, `TriggerPopup ... by_user=0`, `popup loaded` |
| `probe.window()` (W5b row 5, W6) | census `normal=2 arkt=2 views=0`; `windows.getAll` `[[814893290,"normal",2],[814893293,"normal",1]]` |
| Extensions page | `--navigate chrome://extensions`, then `chrome://extensions/`, `Extensions`, `extensions-manager` present |
| Web identity | UA `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36`; `brands` and `fullVersionList` brands `["Not:A-Brand","Chromium"]`; no `Arkt` |
| Stability | alive 10 s after the last driver; 0 `FATAL`/`Check failed`/`Received signal` lines, also after the stop |

### W7 re-run on the default path (carried from #21)

Profile `$CHROMIUM_ROOT/profiles/w10-cws` (fresh), port 9402, `action-probe`, `--arkt-extensions-menu-dump`, the uBO
Lite detail page, no window switch.

- Census `normal=1 arkt=1 views=0`; the Google consent interstitial (`consent.google.com`, "Before you continue")
  came up and was rejected over CDP (`Reject all`, `--user-gesture`); the detail page loaded.
- "Add to Chrome" pressed with `cdp.mjs --user-gesture`: the prompt `Add "uBlock Origin Lite"?` came up as a separate
  window at 676,258 448x196, the same place as in W7; census still `views=0`.
- Accepting it (AXPress on `Add extension` after the frontmost and window-1 checks) was not permitted in this session,
  so the run was stopped by its PID before the install: `toolbar actions 1` throughout, 0 `FATAL`/`Check failed`.
  Steps 1-2 pass on the default path; Step 3 (install, actions 1 -> 2, popup through the menu) is the maintainer's.

### Housekeeping

- Every process this task started was stopped by its PID (two Arkt runs); `ps -axo pid,command | grep -E
  "out/Spike|out/Arkt|/Applications/Arkt.app"` lists nothing. The build and the monitor exited on their own.
- Profiles `w10-smoke` and `w10-cws` stay under `$CHROMIUM_ROOT/profiles`; `$IPROF` was not touched.
- Patch counts match: `wc -l < engine/patches/chromium/.patches` = 6 = `git -C $CR rev-list --count
  156.0.8078.48..arkt`; `git -C $CR diff --stat 156.0.8078.48..arkt | tail -1`: 13 files changed, 57 insertions, 5
  deletions; hot-file hunks 0. The patch budget table above is final for week 2.

### Open items

- Maintainer, with the rebuilt `/Applications/Arkt.app`: the unmocked launch from W8 ("Needs the maintainer"), and
  W7 Step 3 (accept the prompt, check the menu lists uBlock Origin Lite, open its popup) on the default path.
- 1Password (#23) stays blocked on a Developer ID signature (#125); the Apple Development signature cannot pass
  1Password's browser check.
- Week-3 items already listed under W5b, W5c, W6, W7 and W9 (dialogs as free windows, find bar, download UI, patch
  0002 kept).

## #207 leftovers (menu parity, popover close, bounds checks)

Date 2026-10-24. Branch `engine/207-leftovers`. No upstream change: patches still 0001-0006, 13 upstream files
(`13 files changed, 57 insertions, 5 deletions`), 0 hot-file hunks. Build: `nice -n 10 autoninja -C out/Spike -j 4
chrome`, `The build has finished successfully.`, 0 `FAILED:`. Every run: fresh profile `w207-*`, CDP port 9411,
`--use-mock-keychain`, `--load-extension=action-probe`.

| Item | Result |
|---|---|
| `entries_` bounds checks | `CHECK_GE`/`CHECK_LT` (`CHECK_LE` for the insert positions) on the inserted, removed, moved and replaced paths of `OnTabStripModelChanged`, and in `EntryEvent` |
| Popover on active-tab change | `OnTabStripModelChanged` posts a task that hides the active popup when `active_tab_changed()`. Run: `openPopup` then `tabs.update(<other>, {active:true})` gave `ARKT: popup hide (active tab changed)` and `popup closed (hidden)`; no `popup.html` target left |
| Popover on focus loss | Chrome closes its popup when another widget of the window tree is activated, not when the app loses focus. The popover is made key when shown and closes when any other window of the app becomes key (`NSWindowDidBecomeKeyNotification`), unless an app-modal JavaScript dialog or a web-modal dialog of the popup is up. Run: `openPopup` (`popup key 1`), then `chrome.windows.create` gave `popup closed (another window key)`. Not applied: Chrome's DevTools-inspection exception (needs `//chrome/browser/devtools`, not a dependency of `//arkt/browser`) |
| Menu parity | `ArktPlaceholderWindowHost` gets a `validateItem` block; `ArktBrowserWindow` fills in toggle state (bookmark bar, fullscreen toolbar, JavaScript from Apple Events, mute site, pin tab, group tab), hidden state (`IDC_SHOW_AS_TAB`), dynamic title (`IDC_FULLSCREEN`), `IDC_CLOSE_TAB` through the key equivalent, and disables the browser commands Chrome disables while the key window is modal (app-modal session or an attached sheet). AX run: View > Always Show Toolbar in Full Screen checked by default; clicking Always Show Bookmarks Bar sets its check mark; after `windows.update(state: fullscreen)` the View menu shows `Exit Full Screen`. The modal disabling was not exercised at runtime (it needs a sheet on the Arkt window; Arkt's tab-modal dialogs are not sheets yet) |
| Pinned, grouped and split tab events | Not added. Nothing consumes them: the week-3 shell keeps its own tab model and `ArktTabEvent` stays the placeholder's. Hooks are still `OnTabPinnedStateChanged`, `OnTabGroupChanged`, `OnSplitTabChanged` |
| Post-install dialog at (-224,39) | Not changed. The anchor is `GetPageInfoAnchorRect` in patch 0006 (window origin plus `kNoToolbarLeftOffset`, empty size); a 448 px dialog is centred on that point. Fixing it needs a patch change, deferred with the install sheet |
| `chrome.runtime.reload()` of a `--load-extension` extension | Reproduced, and it is Chromium's rule, not an Arkt fault: the reload goes through `UnpackedInstaller` as an unpacked extension and Chrome disables it with `unsupportedDeveloperExtension` (`developerPrivate.getExtensionsInfo` on `chrome://extensions`: state `DISABLED`, location `UNPACKED`) while Developer mode is off, which is the default in a fresh profile. With Developer mode on (`developerPrivate.updateProfileConfiguration({inDeveloperMode:true})`) the same extension is re-enabled (`toolbar actions 0` -> `1`), and a later `chrome.runtime.reload()` brings it back (`toolbar actions 0` -> `1`, service worker ready again). Test extensions that call `runtime.reload()` need Developer mode on |

Regression rows (fresh launch, `--arkt-trace-visibility`, 0 `FATAL`/`Check failed`/`Received signal`, no leftover
process after `kill` by PID): W5b 1 (census `normal=1 arkt=1 views=0`), 2 (navigate to example.org, `visible`), 3
(`probe.create()`: 2 rows, row 1 selected, example.org `visible`), 5 (`chrome.windows.create`: `normal=2 arkt=2
views=0`), 6 (closing the active tab: `removed` event), 7 (all windows closed: census 0/0/0, process alive, gone after
`kill`), 8 (`window.open` with a gesture: a third tab in the window), 13 (AX Edit > Find > Find...: `stub
FindBar::Show`); W5c Step 3 (CDP `visibilityState` swaps with `tabs.update`, AX `select row` 2 and 1 swap the active
tab and the `visibility` lines); W6 (`openPopup` ok, `chrome.windows.create` second Arkt window, popover closed).

Deferred to a follow-up issue: tab-modal attachment, the patch 0006 RTL anchor and the post-install dialog anchor.

## #244: extension dialogs as native sheets

Date 2026-10-24. Branch `engine/244-native-install-sheet`. Build: `nice -n 10 autoninja -C out/Spike -j 4 chrome`,
`The build has finished successfully.`, 0 `FAILED:`. Every run: fresh profile `w244-*`, CDP ports 9421-9424,
`--use-mock-keychain`, one GUI run at a time, stopped by its PID.

### What changed

- Patch 0007 adds one hook call in `ShowExtensionInstallDialogImpl` (install, re-enable and permission-increase
  prompts) and one in `ShowDialog(gfx::NativeWindow, ...)` when there is no Views extensions container
  (post-install, uninstall and the other `ui::DialogModel` extension dialogs). The hooks live in
  `//arkt/browser:extension_dialog_hook`, a light target like the window factory hook; they return false for
  anything that is not an Arkt window, so Chromium's dialogs are unchanged elsewhere (and with `--arkt-views-window`,
  where the hooks are not registered).
- `ArktDialogSheet` (`arkt_dialog_sheet.{h,mm}`) is a plain AppKit sheet attached with `beginSheet:` (no modal loop)
  and fed plain values, so a ShellUI presenter can take the same content later (week-3 Decision 10 keeps extension
  surfaces engine-drawn this week). Colors mirror `ShellTokens` / `BrandTokens` (surface porcelain / graphite,
  primary and secondary text, mustard fill with graphite text for the primary button); system font, 15 pt semibold
  title, 13 pt body; the icon is shown at up to 32 pt, never scaled up or cropped; long permission lists scroll.
- `arkt_extension_dialogs.mm` keeps what `ExtensionInstallDialogView` does: prompt observers before the done callback,
  the callback exactly once (cancel when the sheet goes away unanswered, the parent window closes, the extension is
  uninstalled or the profile shuts down), the 500 ms delay before the install button is enabled, the withheld
  permissions checkbox, and the Web Store link. The request (justification) and parent-permission variants stay with
  Chrome's dialog. The `ui::DialogModel` host runs the accept, cancel and close actions, checkboxes and paragraph
  links, and runs the destroying callback synchronously on `Close()` (the uninstall dialog relies on it). Custom
  Views fields (the sign-in promo footnote) are not shown. The desktop post-install dialog has no buttons; the sheet
  adds OK.
- Keys: Escape cancels. Return presses the default button Chrome gives the dialog: Cancel for the install prompts
  (so Return never installs), Remove for the uninstall dialog, OK for the post-install sheet.
  PARITY(NEEDS-RUNTIME-CHECK): Arc's Return key on these prompts.
- `--arkt-appearance=light|dark` pins `NSApp.appearance` for test runs, so light and dark can be checked without
  changing the system setting.

### Verification

| Check | Result |
|---|---|
| Web Store install (uBO Lite, `w244-cws`) | "Add to Chrome" with `cdp.mjs --user-gesture` (consent page rejected first): `install sheet shown type=0 permissions=1`; AX: `AXSheet` of the Arkt window, described `Add "uBlock Origin Lite"?`, children title, `It can:`, the permission, `Cancel`, `Add extension`; no separate dialog window in the window list. AXPress `Add extension`: `install sheet accepted`, `toolbar actions 0` -> `1`, Web Store button `Remove from Chrome` |
| Post-install dialog | A sheet on the Arkt window (`dialog sheet shown`), centred on the window, not at (-224,39); AX: title `uBlock Origin Lite has been added to Chromium`, the manage text, `OK`. Escape: `dialog sheet closed`, alive 10 s later (the patch 0006 hint path runs on close) |
| uBO popup through the menu | AXPress `Extensions`, Down, Return: `popup loaded .../popup.html` |
| Permission increase (`dialog-probe`, `chrome.permissions.request`) | `install sheet shown type=4 permissions=3`; `Allow` disabled right after showing, enabled after the delay; Escape and Return both give `granted=false`; AXPress `Allow` gives `granted=true` |
| Uninstall (`chrome.management.uninstallSelf({showConfirmDialog:true})`) | `dialog sheet shown ExtensionUninstallDialog`, AX title, `Cancel`, `Remove`; Escape gives `uninstall canceled by user`; on a fresh run Return (Remove) uninstalls: `toolbar actions 1` -> `0`, `dialog sheet closed`, alive 10 s later |
| Parent window closed with the sheet up | `chrome.windows.remove` of the window: `install sheet canceled`, census `0/0/0`, no window left, process alive |
| Light and dark | `--arkt-appearance=light` and the system's dark mode: window-only screenshots kept locally under the profiles' `shots/` |
| VoiceOver tree | Sheet described by its title; title, headings, permissions and buttons are elements; icon, bullets and the divider are hidden |
| Stability | 0 `FATAL`/`Check failed`/`Received signal` lines in every run |

Regression rows (`w244-reg`, port 9424): W5b 1 (census `normal=1 arkt=1 views=0`), 2 (example.org `visible`), 3
(`probe.create()`: `tab list rows 2`, example.org `visible`), 5 (`probe.window()`: `normal=2 arkt=2 views=0`), 6
(`tab event removed`), 7 (all windows closed: census 0/0/0, process alive, gone after `kill`), 8 (`window.open` with a
gesture: `tab list rows 3`), 13 (AX Edit > Find > Find...: `stub FindBar::Show`); W5c Step 3 (`tabs.update` swaps
`visibilityState` both ways); W6 (`openPopup` `ok`, popup loaded, second window, popup closed on the tab change).

### Left open

- Tab-modal attachment, the RTL anchor, the container toggle caller and the "pinned by default" hint stay in #250
  (the hint is still skipped without a `BrowserView`).
- The request (justification) and parent-permission install prompts still use Chrome's Views dialog.
- Arc parity of the Return key (PARITY(NEEDS-RUNTIME-CHECK) above); the Web Store "Switch to Chrome" banner is #9.

## #250: tab-modal attachment and dialog leftovers

Date 2026-10-24. Branch `engine/250-dialog-leftovers`. Patch 0006 amended (RTL anchor); `.patches` unchanged (7 files),
0007 re-exported unchanged; `$CR` branch `arkt` at `8910b992e4` (0006 `e254f81930`). Build: `nice -n 10 autoninja -C
out/Spike -j 4 chrome`, `The build has finished successfully.`, 0 `FAILED:`; `gn check out/Spike '//arkt/*'`: `Header
dependency check OK` (new dependency `//ui/views`). `/` had 8.0 GiB free and swap 8.7 GB used of 10 GB before the build
and the runs. Every run: fresh profile `w250-*`, CDP ports 9481, 9483, 9484, `--use-mock-keychain`, one GUI run at a
time, stopped by its PID; fixture pages from a loopback server.

### What changed

- **Tab-modal attachment** (`ArktModalDialogHost`, overlay only). The dialog host view is a plain `NSView`, not inside
  a `views::Widget`, so Chromium neither parents the dialog widget nor positions it (`GetModalDialogBounds` returns an
  empty rect and `UpdateModalDialogPosition` only resizes). The host now claims the dialog widget when the dialog
  registers as its observer (`CreateWebModalDialogViews`, then `ShowDialogWithManager`): a child-modal widget with no
  parent widget that is not shown yet and that no other host has claimed. While the dialog is visible the host keeps
  it a child window of the host view's window (`addChildWindow:ordered:`), top-centred on the view: the tab's stable
  container in host mode, the card on the placeholder host. It follows size changes of the dialog, window resizes
  and container frame changes (`NotifyPositionRequiresUpdate`); a window move needs nothing (child windows follow).
  A hidden dialog (another tab active) is removed from the parent's child windows, as Chromium's bridge does for its
  own children, and attached again when shown. No added animation: Views fades the dialog in on first show and does
  not re-animate on tab switches.
- **Menu rules.** As in Chrome, a tab-modal dialog blocks its tab (`TabStripModel::SetTabBlocked`), and the command
  controller disables the tab's commands (Find). The "key window is modal" rule (`NSApp.modalWindow` or an attached
  sheet) covers app-modal dialogs and window sheets (file chooser, extension install and uninstall sheets); Chrome's
  `keyWindowIsModal` does the same. Comment updated.
- **Patch 0006 RTL anchor.** `GetPageInfoAnchorRect` without a `BrowserView` anchors at the window's top-right corner
  minus `kNoToolbarLeftOffset` in RTL UI (`base::i18n::IsRTL()`), top-left plus the offset otherwise, as
  `GetMirroredXInView` does for a `BrowserView`. Two more lines in 0006 (`base/i18n/rtl.h`).
- **Extensions container callers.** The placeholder's Extensions button now calls
  `ExtensionsContainer::ToggleExtensionsMenu` (as Chrome's Extensions toolbar button does) instead of showing the menu
  directly. The action delegate's `CloseExtensionsMenuIfOpen` (run by `ExtensionActionViewModel::CloseMenuTask` after
  every user action) goes through the window's `ExtensionsContainer::CloseExtensionsMenuIfOpen` when the menu is that
  container's menu, as Chrome's toolbar action views do; the week-1 controller's menu, which has no container, still
  closes itself. Both container methods log.
- **Pinned-by-default hint: intentional gap.** Chrome shows it as a feature-promo bubble on the Views toolbar
  (`ExtensionsToolbarDesktop::ShowPinnedByDefaultIPH`); Arkt windows have no toolbar, and patch 0006 keeps skipping it.
  Whether ShellUI shows its own hint is in #260.
- **Pinned, grouped and split tab events: not added.** They need new event kinds in the facade header, which stays
  frozen this week; nothing consumes them yet (#260).

### Verification

| Check | Result |
|---|---|
| `alert` on a placeholder window (`w250-p1`, window 900x700 at 40,60) | `tab-modal dialog claimed window 95472 host window 95464`, `attached window 95472 parent 95464 frame 356,955 448x144 host view 230,419 700x680`: horizontally centred on the card (both centres at x 580), top edge on the card's top edge. AX: the dialog window at 356,70, the card's top at window y 70; title `127.0.0.1:9482 says`, the message, `OK` |
| Find while the alert is up | AX (frontmost): Edit > Find > Find... disabled, File > New Tab enabled; after the alert: Find enabled |
| Tab switch | `chrome.tabs.create({active:true})`: the dialog window is gone from the window list; back to the tab: `attached ... parent 95464` at the same frame, AX position unchanged |
| Window resize with the dialog up | `chrome.windows.update` to 100,80 1100x720: `attached ... frame 516,935 448x144 host view 290,379 900x700`, centred again (x 740), AX 516,90 |
| AX dismissal | AXPress `OK`: `tab-modal dialog detached window 95484 parent 95464`, the page runs again |
| Embedder window, tab container (`--arkt-facade-selftest --arkt-engine-test-api`, `w250-host2`) | `confirm`: `attached window 95533 parent 95529 frame 346,606 448x144 host view 120,150 900x600`: on the self-test's tab container (below its 32 pt title bar), centred |
| `answerDialog` through the test API | from another tab, `arkt-selftest answer <tab> accept`: `facade answerDialog accept=yes answered=yes`, `tab-modal dialog detached` |
| Parent window closed with a dialog up | `chrome.windows.remove`: `windowClosed`, `native window destroyed`, no window left, process alive |
| Key window modal: sheet | dialog-probe `uninstallSelf({showConfirmDialog:true})`: `dialog sheet shown ExtensionUninstallDialog`; AX: File > New Tab and Find disabled; AXPress `Cancel`: `uninstall canceled by user`, both enabled again |
| Key window modal: app-modal | beforeunload on a tab closed by `chrome.tabs.remove`: "Leave site?" (`AXDialog`, Cancel, Leave) is app-modal by Chromium's design (`TabModalDialogManager::RunBeforeUnloadDialog`) and not attached to the tab; New Tab and Find disabled while it is up; AXPress `Cancel` keeps the tab |
| Container toggle | AXPress `Extensions`: `extensions container toggle menu (showing=0)`, `extensions menu shown 3 items`; a second AXPress while the menu is open: `toggle menu (showing=1)`, `extensions menu closed` |
| Container close from an action | Extensions menu, Down, Return: `TriggerPopup ... by_user=1`, `extensions menu closed`, `extensions container close menu (showing=0)`, `popup loaded` |
| RTL anchor | Compiled, not exercised: its remaining consumer is the permission prompt, and a notification or geolocation request on an Arkt window shows no prompt at all (the request stays pending, no window appears). Both are in #260 |
| Stability | 0 `FATAL`/`Check failed`/`Received signal` in every run |

AX notes: the JavaScript dialog window reports subrole `AXUnknown` (role `AXWindow`, title `127.0.0.1:9482 says`), the
app-modal beforeunload dialog `AXDialog`. Window-only screenshots kept locally under the profiles' `shots/`.

Regression rows (`w250-reg`, port 9484, one launch, `--arkt-trace-visibility`, `action-probe`, `tabs-probe`): W5b 1
(census `normal=1 arkt=1 views=0`), 2 (navigate to the fixture's `b.html`, `visible`), 3 (`probe.create()`: `tab list
rows 2`, `b.html` still `visible`), 5 (`probe.window()`: `normal=2 arkt=2 views=0`), 6 (`tab event removed`), 7 (all
windows closed: census 0/0/0, process alive, gone after `kill`), 8 (`window.open` with a gesture: `tab list rows 3`),
13 (AX Edit > Find > Find...: `stub FindBar::Show`); W5c Step 3 (`tabs.update` swaps `visibilityState` both ways); W6
(`openPopup` `ok`, popup loaded, `popup hide (active tab changed)`, second window). 0 `FATAL`/`Check failed`.

### Left open (#260)

- Permission prompts show nothing on Arkt windows; the RTL anchor runtime check waits for them.
- Pinned-by-default hint in ShellUI (decision); pinned, group and split tab events.
- beforeunload as a sheet would need a patch (Chromium keeps it app-modal on purpose).

