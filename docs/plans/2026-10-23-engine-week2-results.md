# Engine week 2 results

Plan: `docs/plans/2026-10-23-engine-week2.md`. Variables (`$REPO`, `$CR`, `$OUT`, `$REL`, `$PROF`) as in the plan's
Rules. `$REPO` is the engine worktree `arkt-wt/engine` on branch `engine-week2`.

## Tasks

| Task | Title | Status | Notes |
|---|---|---|---|
| W0 | Branch, baselines, results file, CDP helper, key-window log | DONE | see below |
| W1 | Arkt-branded non-component build | STOPPED | build stopped on low swap; config done, see below |
| W2 | Sign `Arkt.app`, install in /Applications, smoke | TODO | |
| W3 | Inventory of non-`BrowserView` window seams, variant decision | DONE | variant P (plain `NSWindow`); this week 3 seam patch files, 4-8 upstream files, 0 hot-file hunks (W: 3 / 4 / 0); see "W3" below |
| W4 | Extensions menu lists every action (finding 1) | DONE | no upstream patch; see below |
| W5a | `ArktBrowserWindow` skeleton behind `--arkt-native-window` | TODO | |
| W5b | Seam fixes found by the smoke matrix (GATE) | TODO | |
| W5c | Arkt-owned tab list and visibility (finding 2) | TODO | |
| W6 | Extension window identity, extension-created tabs and windows (finding 3) | TODO | |
| W7 | Web Store install on the native window | TODO | |
| W8 | Keychain: mock in tests, "Arkt Safe Storage" in the product (finding 5) | TODO | |
| W9 | Native window as default; try dropping patch 0002 | TODO | |
| W10 | Release bundle rebuild, re-sign, final smoke, housekeeping | TODO | |
| WE | Embedding spike (lane C) | DONE: GO (framework copied into the app bundle) | see below; branch `spike/embedding` |

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 | 0 |
| 0002 | Let a WebContents view draw again after leaving Views | exists; W9 tries to drop it | 4 | 0 |
| 0003 | `BrowserWindow` factory hook for Arkt (W5a) | new | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) | 0 |
| 0004+ | Non-`BrowserView` normal window seams (W5b), grouped by theme | new; W3 projects 3 patch files (P) | 4-8 (W3 estimate, P; 8-13 with week-3 rows) | 0 (W3 estimate) |
| next | Arkt keychain item name (W8) | new | 1 | 0 |

Current totals: 2 patch files, 6 upstream files, 0 hot-file hunks.

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
Step 7 (verification) has not run.

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
| 3 | `session_restore.cc:859` (Ash), `browser_window_factory.cc:35` (the factory, patch 0003) | (n) | | |
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
