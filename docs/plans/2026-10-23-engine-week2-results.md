# Engine week 2 results

Plan: `docs/plans/2026-10-23-engine-week2.md`. Variables (`$REPO`, `$CR`, `$OUT`, `$REL`, `$PROF`) as in the plan's
Rules. `$REPO` is the engine worktree `arkt-wt/engine` on branch `engine-week2`.

## Tasks

| Task | Title | Status | Notes |
|---|---|---|---|
| W0 | Branch, baselines, results file, CDP helper, key-window log | DONE | see below |
| W1 | Arkt-branded non-component build | TODO | |
| W2 | Sign `Arkt.app`, install in /Applications, smoke | TODO | |
| W3 | Inventory of non-`BrowserView` window seams, variant decision | TODO | |
| W4 | Extensions menu lists every action (finding 1) | TODO | |
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
| 0004+ | Non-`BrowserView` normal window seams (W5b), grouped by theme | new, measured in W3/W5b | W3 estimate | W3 estimate |
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
     Framework.framework/Versions/156.0.8078.48` (18 times; 10 more for `(Aperitif Renderer)`).
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
  with the sandbox on. Zero `FATAL` and zero `ERROR` lines other than
  `ARKT: extension not installed ddkjiahejlhfcafbddmgiahcphecmpfh` (fresh profile).

**Run C: warm relaunch of the Run B layout.** Log `$PROF/w2-we-c-warm.log`. Hook alive 2.9 s after launch, process
alive at 30 s, zero `FATAL`/`ERROR` lines.

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
