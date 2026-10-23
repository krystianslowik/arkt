# Engine week 2 results

Plan: `docs/plans/2026-10-23-engine-week2.md`. Variables (`$REPO`, `$CR`, `$OUT`, `$REL`, `$PROF`) as in the plan's
Rules. `$REPO` is the engine worktree `arkt-wt/engine` on branch `engine-week2`.

## Tasks

| Task | Title | Status | Notes |
|---|---|---|---|
| W0 | Branch, baselines, results file, CDP helper, key-window log | DONE | see below |
| W1 | Arkt-branded non-component build | STOPPED | build stopped on low swap; config done, see below |
| W2 | Sign `Arkt.app`, install in /Applications, smoke | TODO | |
| W3 | Inventory of non-`BrowserView` window seams, variant decision | TODO | |
| W4 | Extensions menu lists every action (finding 1) | DONE | no upstream patch; see below |
| W5a | `ArktBrowserWindow` skeleton behind `--arkt-native-window` | TODO | |
| W5b | Seam fixes found by the smoke matrix (GATE) | TODO | |
| W5c | Arkt-owned tab list and visibility (finding 2) | TODO | |
| W6 | Extension window identity, extension-created tabs and windows (finding 3) | TODO | |
| W7 | Web Store install on the native window | TODO | |
| W8 | Keychain: mock in tests, "Arkt Safe Storage" in the product (finding 5) | DONE (user steps open) | patch 0003; see below |
| W9 | Native window as default; try dropping patch 0002 | TODO | |
| W10 | Release bundle rebuild, re-sign, final smoke, housekeeping | TODO | |
| WE | Embedding spike (lane C) | DONE: GO (framework copied into the app bundle) | see below; branch `spike/embedding` |

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 | 0 |
| 0002 | Let a WebContents view draw again after leaving Views | exists; W9 tries to drop it | 4 | 0 |
| 0003 | `BrowserWindow` factory hook for Arkt (W5a) | new | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) | 0 |
| 0004+ | Non-`BrowserView` normal window seams (W5b), grouped by theme | new, measured in W3/W5b | W3 estimate | W3 estimate |
| 0003 | Arkt keychain item name (W8) | exists | 1 (`keychain_password_mac.mm`) | 0 |

Current totals: 3 patch files, 7 upstream files, 0 hot-file hunks. The W5a factory hook takes the next free number.

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

### Needs the user (open)

1. Decide about the existing "Chromium Safe Storage" item (created 2026-10-23 08:04:51Z, account `Chromium`). It was
   not deleted. If you know only Arkt test builds created it, delete it yourself in Keychain Access.
2. After W10 installs the rebuilt `/Applications/Arkt.app`, launch it once without `--use-mock-keychain` (plan W8,
   "Needs the user" step 2). Expected: no prompt about "Chromium Safe Storage", and an "Arkt Safe Storage" item
   (account `Arkt`) afterwards.
