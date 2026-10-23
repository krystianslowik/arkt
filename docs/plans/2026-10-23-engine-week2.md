# Engine Week 2 Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** Close the five engine findings from week 1 (`docs/plans/2026-10-22-week1-results.md`, Tasks 6-8):
(1) the sidebar Extensions control lists every installed extension action and opens the chosen popup in our
`NSPopover`; (2) Arkt, not Chrome's tab strip, decides which page is visible; (3) extension-created tabs and windows
(`chrome.tabs.create`, welcome pages, `window.open`, `chrome.windows.create`) land in Arkt windows, and extensions
see Arkt windows as their `windowId`; (4) a self-contained, signed, Arkt-branded non-component build that can live in
`/Applications` exists as the 1Password fallback; (5) test runs never touch the user's login keychain, and the
product uses its own keychain item, "Arkt Safe Storage".

**Architecture:** Finding 3 is solved by the design doc's `ArktBrowserWindow` (an AppKit implementation of Chromium's
`BrowserWindow`), created by Chromium's own `BrowserWindow::CreateBrowserWindow` factory for `TYPE_NORMAL` browsers
through one small hook patch. Each Arkt window keeps a real `Browser` and its `TabStripModel`; that model is the tab
list for extensions (`tabs.*`, `windows.*`) and Arkt observes it. `BrowserView` no longer exists for normal windows,
so nothing in Views can hide our mounted pages (finding 2 goes away structurally) and new tabs have nowhere to go but
Arkt. Findings 1 and 5 are small: the extension menu uses Chromium's `ToolbarActionsModel` and
`ExtensionActionViewModel` with our own `ExtensionActionDelegate` (no patch); the keychain item name is one patch.
Finding 4 is a second output directory, `out/Arkt`, built with `is_component_build=false` and a GN-arg branding file
(no patch). The week-1 mount path stays runnable behind the absence of `--arkt-native-window` until W9 removes it.

**Tech Stack:** Chromium 156.0.8078.48 (GN + Siso), ObjC++ in `//arkt/browser`, AppKit, git `format-patch`/`am -3`
patch workflow (`engine/README.md`), Node 26 (built-in `WebSocket`) for the CDP helper, `codesign`, `screencapture`.

---

## Rules (read before every task)

| Name | Path |
|---|---|
| `$REPO` | root of this repo ( branch `engine-week2`, see W0) |
| `$CR` | `$CHROMIUM_ROOT/chromium/src` (Chromium checkout, branch `arkt` on 156.0.8078.48) |
| `$OUT` | `$CR/out/Spike` (component build, fast incremental; all engine work) |
| `$REL` | `$CR/out/Arkt` (non-component, Arkt-branded; W1, W2, W10) |
| `$PROF` | `$CHROMIUM_ROOT/profiles` (test profiles for `out/Spike`) |
| `$IPROF` | `$HOME/Library/Application Support/ArktTest` (test profiles for `/Applications/Arkt.app`) |
| `$RES` | `$REPO/docs/plans/2026-10-23-engine-week2-results.md` (results; created in W0) |

- Shell is zsh. Set once per shell:
  `export PATH=$CHROMIUM_ROOT/depot_tools:$PATH; REPO=/path/to/arkt; CR=$CHROMIUM_ROOT/chromium/src; OUT=$CR/out/Spike; REL=$CR/out/Arkt; PROF=$CHROMIUM_ROOT/profiles; IPROF="$HOME/Library/Application Support/ArktTest"; RES=$REPO/docs/plans/2026-10-23-engine-week2-results.md`
- **Disk.** Never touch anything on the Chromium disk outside `$CHROMIUM_ROOT`. The Chromium checkout is edited
  only through the patch workflow in `engine/README.md`: commit on branch `arkt`, then run Export. Never leave
  unexported commits; Apply refuses to run over them.
- **Worktree.** Work in `$REPO` itself on branch `engine-week2`, not in a worktree: `$CR/arkt` is a symlink to
  `$REPO/engine/arkt`, so a worktree would build stale sources. Other tracks use worktrees under `arkt-wt/`; do not
  touch them.
- **Capacity.** At most one Chromium build runs at a time. The long `out/Arkt` build (W1) runs at `nice -n 15`;
  an incremental `out/Spike` build may run alongside it (both are slower; that is accepted). While any Chromium
  build runs, at most two Swift builds may run, at `nice -n 20`. No other heavy jobs during a build.
- **Incremental build command** (background, log to file, check the tail):
  `cd $CR && autoninja -C out/Spike chrome > $PROF/../build-w2.log 2>&1; tail -3 $PROF/../build-w2.log`
  Expected: `The build has finished successfully.` and no `FAILED:` lines.
- **Upstream header rule.** Never edit a widely included upstream header (`browser_window.h`, `browser.h`,
  `tab_strip_model.h`, ...): it recompiles thousands of files. Hooks go into `.cc`/`.mm` files and small targets.
- **Symbols.** Every Chromium name below was checked against 156 when this plan was written (file:line given where
  it matters). Before relying on one, confirm with `git -C $CR grep -n '<symbol>'` and adapt to what is there.
- **Launching.** Every test launch passes `--user-data-dir` (a profile under `$PROF` or `$IPROF`, never a real user
  profile), `--use-mock-keychain`, `--no-first-run`, `--no-default-browser-check`, `--enable-logging=stderr`.
  Launch in the background with output redirected to a file and record the PID from `$!`, never through a pipe
  (`$!` would then be `tee`'s PID):
  `"$OUT/Chromium.app/Contents/MacOS/Chromium" <flags> > $PROF/w2-<task>.log 2>&1 & PID=$!; echo $PID`
- **Stopping.** Kill only by that exact PID (`kill $PID`, then `ps -p $PID` must print no process row). Never
  `pkill`/`killall`, never kill by name. Before reporting a task done, list leftovers with
  `ps -axo pid,command | grep -F "$OUT/Chromium.app" | grep -v grep` and kill each of this task's PIDs explicitly.
- **Synthetic input** goes only into our own window, and only after checking both:
  1. our process is frontmost:
     `osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true'`
     prints `$PID`;
  2. our window is key: the log's last `ARKT: key window <n>` line (added in W0) names our window number.
  If either check fails, do not send input; re-activate with `osascript -e "tell application \"System Events\" to set frontmost of first process whose unix id is $PID to true"` and check again. Never type into
  other apps. Prefer, in order: launch switches and CDP (no input at all), `AXPress` through System Events, then
  `cliclick` only at coordinates inside our window's frame.
- **Screenshots** are window-only: `screencapture -o -x -l <window number> $PROF/shots/<task>-<n>.png`. The window
  number comes from our log (`ARKT: window number <n>`). Never full-screen captures.
- **CDP.** Launch with `--remote-debugging-port=9333` when a task reads page or extension state. Use the helper from
  W0: `node $REPO/engine/tools/cdp.mjs <url-substring|type:service_worker> '<js expression>'`.
  Match service workers by extension id, never by bare `type:service_worker` (several extensions run workers):
  `PROBE_SW=<action-probe id>/sw.js`, the id taken from the `ARKT action <id> Arkt action probe` log line (an unpacked
  extension's id is stable per path). MV3 workers stop after about 30 s idle and then vanish from `/json/list`;
  the probe workers keep themselves alive (W4 Step 1), and when the popover is open the `popup.html` page target
  (full `chrome.*` API, kept open by `NSPopoverBehaviorApplicationDefined`) is an equally good driver.
- **Mock keychain.** `--use-mock-keychain` uses an in-memory fake keychain, so treat encrypted profile data
  (cookies, saved passwords) as not surviving a relaunch of a test profile. Extension installs and extension state
  do survive. This is expected, not a regression.
- **User data.** Test profiles may hold the user's 1Password extension state; logs and results record counts, ids,
  enum names and states only. Never print vault content, cookies or keychain secrets. `security` commands in this plan
  never use `-w`/`-g` (they would print or prompt for secrets).
- **Steps that need the user** are under a "Needs the user" heading and only there. Everything else must be
  verifiable by the contributor alone.
- **Time-box.** Each task has one. When it runs out, stop, record what is known in `$RES` with the exact error, and
  move to the next independent task. Gates (W3, W5b) stop the dependent tasks, not the whole plan.
- **Commits.** One per task unless listed otherwise. Stage with explicit pathspecs (`git add <paths>`; never
  `git add -A` or `git add .`: the checkout may hold untracked local tool directories). Plain commit messages. Exported patch files and `.patches` are committed together with the overlay
  change that needs them.
- No emojis anywhere (code, comments, logs, commit messages).

## Decisions fixed for this track

1. **Finding 3: Arkt implements `BrowserWindow` (`ArktBrowserWindow`); we do not keep a hidden `BrowserView`
   window per Arkt window.** Both options keep one `Browser` + `TabStripModel` per Arkt window, so `windowId`/`tabId`
   come from Chromium either way. The difference is who implements the window:
   - *Hidden `BrowserView` + mirrored tab strip* (rejected). It keeps the owner that caused findings 2 and 3:
     `BrowserView`'s contents `WebView` swaps WebContents on every active-tab change, and
     `NativeViewHostMac::NativeViewDetaching` calls `ViewsHostableDetach()` on the old view, which runs
     `in_process_ns_view_bridge_->SetVisible(false)` (`content/browser/web_contents/web_contents_view_mac.mm`
     ~line 840) and hides our mounted page. `chrome::Navigate` shows the Views window for new foreground tabs. Every
     fix is a hook that races `BrowserView` layout (the deferred hazard in week-1 Task 4), and split view (2-4 tabs
     visible at once) cannot work while `BrowserView` keeps only its active tab attached. It also needs patches:
     suppress `BrowserView::Show`, keep its `WebView` from re-hosting our views, and route its unhandled keys.
   - *`ArktBrowserWindow`* (chosen). Upstream already branches this factory to a non-Views window:
     `BrowserWindow::CreateBrowserWindow` (`chrome/browser/ui/views/frame/browser_window_factory.cc:32`) returns
     `WebUIBrowserWindow` ("Webium") for `TYPE_NORMAL` when `kWebium` is on. Webium is our template: 56 of its
     methods are `NOTIMPLEMENTED()` stubs, it registers its own `ExtensionsContainer` through
     `ui::ScopedUnownedUserData<ExtensionsContainer>` (`webui_browser_window.cc:194`), and
     `BrowserView::GetBrowserViewForBrowser` already returns nullptr for windows that are not `BrowserView`.
     `BrowserWindowFeatures` creates `BrowserExtensionWindowController` for every `Browser`
     (`browser_window_features.cc:847`), so `chrome.windows.*` sees Arkt windows with no extra work. The test-only
     `custom_window` path in `Browser` is `CHECK_IS_TEST()`, so the factory hook patch is required.
   - **Patch impact.** One hook patch (W5a). Seam patches that tolerate a non-Views normal window are measured, not
     guessed: W3 inventories them (8 direct `GetBrowserViewForBrowser(...)->` dereferences in non-test code at 156;
     14 non-Webium files branch on `IsWebUIBrowserEnabled()`, among them `BrowserElementsViewsImpl` in
     `browser_window_features.cc:352`), W5b fixes the ones the smoke run hits, grouped into one patch file per
     theme. Patch 0002 (re-enable display after leaving Views) should become unnecessary, because normal-window
     WebContents are never Views-hosted; W9 tests dropping it. Projection in the patch budget below.
   - **Scope this week:** `TYPE_NORMAL` only. Popups (`window.open` with features, `chrome.windows.create({type:
     'popup'})`), app, DevTools and picture-in-picture windows stay Views windows (open question 2).
2. **Tab list direction.** Chromium's `TabStripModel` per Arkt window is the engine's tab list. Arkt observes it
   (`TabStripModelObserver::OnTabStripModelChanged`) and never keeps a second list that it pushes into Chromium.
   User actions in Arkt call the model (`ActivateTabAt`, `CloseWebContentsAt`, `chrome::AddTabAt`). Tabs that an
   extension or a page adds appear in Arkt as new Today tabs. Activation from an extension (`tabs.update({active:
   true})`, `tabs.create({active: true})`) is honoured.
3. **Visibility is Arkt's.** Exactly the WebContents views Arkt mounts in a visible window are in the view hierarchy;
   every other tab's view is removed from its superview, which makes `WebContentsViewCocoa` report `kHidden`
   (`updateWebContentsVisibility`, `web_contents_view_cocoa.mm:525`). Occlusion still comes from Chromium's
   `WebContentsOcclusionCheckerMac`. The `TabStripModel` active index follows Arkt's selection so extension
   `active` flags stay true.
4. **One `Browser` per Arkt window; all of its Spaces' tabs live in that window's `TabStripModel`.** Space switching
   is an Arkt concept; extensions see one window with all its tabs, as Arc does.
5. **Extension actions** come from `ToolbarActionsModel` (`chrome/browser/ui/toolbar/toolbar_actions_model.h`, its
   `Observer` for add/remove/update) and run through `ExtensionActionViewModel::Create(id, browser, delegate)`
   (`chrome/browser/ui/extensions/extension_action_view_model.h:61`) with our `ArktExtensionActionDelegate`. The
   delegate's `TriggerPopup(host, ...)` hands the `ExtensionViewHost` to the existing `PopoverExtensionView`, and its
   `GetActiveWebContents()` returns Arkt's selected tab. Pinning and ordering are later work.
6. **Branding without patches.** `branding_file_path` is a GN arg (`build/config/chrome_build.gni:109`). Pointing it at
   `//arkt/branding/BRANDING` renames the app, framework, helpers and bundle id. Icons and UI strings stay Chromium's
   for now. Bundle id `com.arkt.Arkt` is a placeholder (open question 1); changing it later resets TCC grants,
   keychain ACLs and 1Password's browser trust for that build.
7. **Keychain.** Every test run uses `--use-mock-keychain`, which the keychain key provider honours
   (`components/os_crypt/async/browser/keychain_key_provider.mm:42`). The product name is set by one patch to
   `components/os_crypt/common/keychain_password_mac.mm` (`kDefaultServiceName` "Arkt Safe Storage",
   `kDefaultAccountName` "Arkt"). The runtime-configurable variant (`ALLOW_RUNTIME_CONFIGURABLE_KEY_STORAGE`) needs a
   GN define patch plus ordering against OSCrypt init in `browser_process_impl.cc:1651`; it buys nothing for us.
   The existing "Chromium Safe Storage" item in the user's login keychain is not ours to delete: it may belong to
   another Chromium-based app (open question 3).

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files |
|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 |
| 0002 | Let a WebContents view draw again after leaving Views | exists; W9 tries to drop it | 1-4 |
| 0003 | `BrowserWindow` factory hook for Arkt (W5a) | new | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) |
| 0004+ | Non-Views normal window seams (W5b), grouped by theme | new, measured in W3/W5b | W3 estimate |
| next | Arkt keychain item name (W8) | new | 1 |

Projection after week 2: 4 patch files plus the seam patches. The W5b gate stops the track if seam patches would
exceed 8 patch files or 25 upstream files; at that point the remaining budget (target < 30 overall, with week-3+
needs: framework rename, extension install UI, behaviour tweaks) would be at risk. `$RES` keeps this table current
(patch files and upstream files touched, both).

---

### Task W0: Branch, baselines, results file, CDP helper, key-window log

**Files:**
- Create: `$RES`
- Create: `engine/tools/cdp.mjs`
- Modify: `engine/arkt/browser/arkt_window_controller.mm` (log key-window changes)

**Step 1: Branch and state**

```zsh
cd $REPO && git status --short --untracked-files=no   # must print nothing; otherwise ask who owns the changes
git switch -c engine-week2 spike/week1
git -C $CR branch --show-current; git -C $CR rev-list --count 156.0.8078.48..arkt; wc -l < $REPO/engine/patches/chromium/.patches
ls -l $CR/arkt
```
Expected: `arkt`, `2`, `2`, and the symlink points at `$REPO/engine/arkt`. If the counts differ, stop: Export first
(`engine/README.md`).

**Step 2: Key-window log** (needed by the input rule). In `ArktWindowController`, observe
`NSWindowDidBecomeKeyNotification` for its window and log `ARKT: key window <windowNumber>`; also log
`ARKT: window number <n>` once after `showWindow:` (it already logs the number inside the first-responder line; make
it a separate line so scripts can grep it).

**Step 3: CDP helper** (`engine/tools/cdp.mjs`, one reusable tool, no shell wrappers). Usage:
`node cdp.mjs <match> '<expression>' [--port 9333]`, where `<match>` is a substring of the target URL or
`type:<target type>` (`page`, `service_worker`, `background_page`). It reads `http://127.0.0.1:<port>/json/list`,
picks the first matching target, opens its `webSocketDebuggerUrl` with Node's global `WebSocket`, sends
`Runtime.evaluate` with `{expression, awaitPromise: true, returnByValue: true}`, prints `JSON.stringify(result.value)`,
and exits non-zero with the CDP error text on failure. No dependencies.

**Step 4: Build and baseline run**

Build (Rules command). Then:
```zsh
mkdir -p $PROF/shots $PROF/week2
"$OUT/Chromium.app/Contents/MacOS/Chromium" --user-data-dir=$PROF/week2 --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9333 \
  --load-extension=$REPO/engine/test-extensions/tabs-probe file://$REPO/engine/test-extensions/tabs-probe/manifest.json \
  > $PROF/w2-w0.log 2>&1 & PID=$!
```
Wait until `grep -c "ARKT: mounted active tab" $PROF/w2-w0.log` is 1 (poll every 2 s, max 60 s), then:
`node $REPO/engine/tools/cdp.mjs manifest.json 'document.visibilityState'` prints `"visible"`, and
`grep -E "ARKT: (key window|window number)" $PROF/w2-w0.log` prints both lines. Kill `$PID` (Rules).

**Step 5: Results file.** Create `$RES` with a header, the task table (W0-W10, all `TODO`), the patch budget table
copied from this plan, and W0's evidence (commands above and their output lines).

**Step 6: Commit**

```zsh
git add docs/plans/2026-10-23-engine-week2-results.md engine/tools/cdp.mjs engine/arkt/browser/arkt_window_controller.mm
git commit -m "Engine week 2 baseline: results file, CDP helper, key-window log"
```

Time-box: 1.5 h (most of it the incremental build).

---

### Task W1: Arkt-branded non-component build (start early; runs for hours)

Finding 4. Starts right after W0 so the build runs while W3-W5 proceed. It uses the overlay and patches as they are
at start time (the week-1 code); W10 rebuilds it incrementally at the end.

**Files:**
- Create: `engine/arkt/branding/BRANDING`
- Modify: `engine/README.md` (section "Release build (out/Arkt)")

**Step 1: Branding file** (`engine/arkt/branding/BRANDING`; same keys as `chrome/app/theme/chromium/BRANDING`)

```
COMPANY_FULLNAME=Arkt
COMPANY_SHORTNAME=Arkt
PRODUCT_FULLNAME=Arkt
PRODUCT_SHORTNAME=Arkt
PRODUCT_INSTALLER_FULLNAME=Arkt Installer
PRODUCT_INSTALLER_SHORTNAME=Arkt Installer
COPYRIGHT=Copyright @LASTCHANGE_YEAR@ Arkt. Portions copyright The Chromium Authors. All rights reserved.
MAC_BUNDLE_ID=com.arkt.Arkt
MAC_CREATOR_CODE=Arkt
MAC_TEAM_ID=$TEAM_ID
```

**Step 2: Args** (`$REL/args.gn`)

```gn
is_debug = false
is_component_build = false
is_official_build = false     # official turns on PGO/ThinLTO and adds hours; not needed for the 1Password check
chrome_pgo_phase = 0
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
dcheck_always_on = false
target_cpu = "arm64"
use_siso = true
branding_file_path = "//arkt/branding/BRANDING"
```

**Step 3: Generate and confirm the branding took**

```zsh
cd $CR && gn gen out/Arkt && gn args out/Arkt --list=branding_file_path --short
grep -m3 -E 'Arkt\.app|Arkt Framework' out/Arkt/toolchain.ninja out/Arkt/obj/chrome/*.ninja 2>/dev/null | head -3
```
Expected: `branding_file_path = "//arkt/branding/BRANDING"` and at least one line naming `Arkt.app` or
`Arkt Framework`. If `gn gen` rejects the source-absolute path, retry once with the system-absolute path
`branding_file_path = "$REPO/engine/arkt/branding/BRANDING"` (with `$REPO` expanded) (GN accepts
paths starting with `/`). If that fails too, record the exact error in `$RES` and stop W1; do not patch
`chrome/app/theme/chromium/BRANDING` instead.

**Step 4: Disk and start the build** (background; `out/Arkt` shares no objects with `out/Spike`)

```zsh
df -h $CHROMIUM_ROOT | tail -1    # need >= 40 GB free; 2.0 TB free when this plan was written
cd $CR && (time nice -n 15 autoninja -C out/Arkt chrome) > $CHROMIUM_ROOT/build-arkt.log 2>&1 &
echo $! > $CHROMIUM_ROOT/build-arkt.pid
```
Expected cost: a full compile of about 75k objects plus one large framework link. The component build on this Mac
(10 cores, 32 GB) ran from about 21:03 to past 01:39 while other builds were busy, and an earlier note records it
slipping to about 11:00 under heavy parallel load. Budget 5-7 h on a quiet machine, up to 14 h under load. The
non-component link of `Arkt Framework` is memory-heavy (several GB, single process); do not run other heavy jobs or a second
Chromium link at the same time. Disk: `out/Spike` is 6.1 GB; expect `out/Arkt` at 10-15 GB.

**Step 5: Verify when it finishes**

```zsh
tail -3 $CHROMIUM_ROOT/build-arkt.log; grep -c FAILED: $CHROMIUM_ROOT/build-arkt.log
ls "$REL/Arkt.app/Contents/Frameworks/Arkt Framework.framework/Versions/Current/Helpers"
otool -L "$REL/Arkt.app/Contents/Frameworks/Arkt Framework.framework/Arkt Framework" | grep -c '@rpath/lib.*\.dylib'
plutil -extract CFBundleIdentifier raw "$REL/Arkt.app/Contents/Info.plist"
du -sh "$REL/Arkt.app" $REL
```
Expected: build finished, `0` FAILED, helpers named `Arkt Helper*.app`, `0` component dylibs linked through `@rpath`
(only system libraries and the framework's own `Libraries/` such as `libEGL.dylib`), `com.arkt.Arkt`, and the sizes
(record both; bundle expected 400-600 MB).

`out/Arkt` compiles the same `$CR` tree (and the `$CR/arkt` symlink) that W4-W8 edit while it builds. If any overlay
change or patch commit landed during the build, run the same `nice -n 15 autoninja -C out/Arkt chrome` once more
(incremental) before W2, and record which overlay commit the bundle contains. Never run `git am`/Export on `$CR`
while `out/Arkt` is in its final framework link.

**Step 6: README section.** Add "Release build (out/Arkt)" to `engine/README.md`: the args above, the build command,
and that `out/Arkt` must be re-signed after every rebuild (W2).

**Step 7: Commit** (after Step 3; Step 5 results go into `$RES` and are committed with W2)

```zsh
git add engine/arkt/branding/BRANDING engine/README.md docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Add Arkt branding and the non-component release build config"
```

Time-box: 1 h of working time (the build itself runs unattended; check it every hour, do not poll faster).

---

### Task W2: Sign `Arkt.app`, install it in /Applications, smoke it from the internal disk

Runs when W1's build has finished. Skip Steps 4-5 only if the user reports that week-1 Task 8 already PASSES with the
external-disk build; Steps 1-3 still run (the signed self-contained bundle is the release smoke for every later rebase).

**Files:**
- Modify: `engine/README.md` (signing block for `out/Arkt`)
- Modify: `$RES`

**Step 1: Sign inside-out** (in `$REL`; same identity and entitlements as week-1 Task 8, no 518 dylibs this time)

```zsh
cd $REL
ID=$SIGNING_IDENTITY; ENT=../../chrome/app
F="Arkt.app/Contents/Frameworks/Arkt Framework.framework/Versions/Current"
for l in "$F"/Libraries/*.dylib(N); do codesign --force --sign $ID "$l"; done
for b in "$F"/Helpers/chrome_crashpad_handler "$F"/Helpers/app_mode_loader "$F"/Helpers/web_app_shortcut_copier; do
  [[ -e "$b" ]] && codesign --force --sign $ID --options runtime "$b"; done
for h in "$F"/Helpers/*.app; do case "$h" in *Renderer*) e="--entitlements $ENT/helper-renderer-entitlements.plist";; *GPU*) e="--entitlements $ENT/helper-gpu-entitlements.plist";; *) e="";; esac; codesign --force --sign $ID --options runtime ${=e} "$h"; done
codesign --force --sign $ID "Arkt.app/Contents/Frameworks/Arkt Framework.framework"
codesign --force --sign $ID --options runtime --entitlements $ENT/app-entitlements.plist Arkt.app
codesign --verify --deep --strict --verbose=2 Arkt.app
codesign -dv --verbose=2 Arkt.app 2>&1 | grep -E '^(Identifier|TeamIdentifier|Runtime Version|Authority)'
```
Expected: `valid on disk`, `satisfies its Designated Requirement`, `Identifier=com.arkt.Arkt`,
`TeamIdentifier=$TEAM_ID`, hardened runtime present. List `"$F"/Helpers` first and sign every executable found there
(the list above is week 1's; a non-component build may add or drop helpers). The identity hash is the one week 1 used;
if `security find-identity -v -p codesigning` no longer lists it, stop and ask the user.

**Step 2: Install**

```zsh
df -h / | tail -1                                   # need >= 2 GB free
ls -d /Applications/Arkt.app 2>/dev/null && echo EXISTS   # if it exists, stop and ask the user
ditto "$REL/Arkt.app" /Applications/Arkt.app
codesign --verify --deep --strict --verbose=2 /Applications/Arkt.app
```

**Step 3: Smoke from the internal disk** (profile on the internal disk so the browser itself needs no
removable-volume grant)

```zsh
mkdir -p "$IPROF/smoke"
/Applications/Arkt.app/Contents/MacOS/Arkt --user-data-dir="$IPROF/smoke" --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9333 https://example.com \
  > "$IPROF/w2-smoke.log" 2>&1 & PID=$!
```
Expected within 30 s: `ARKT: in-process hook alive`, `ARKT: mounted active tab`, and
`node $REPO/engine/tools/cdp.mjs example.com 'document.title'` prints `"Example Domain"`. Window-only screenshot of
the Arkt window to `$PROF/shots/w2-smoke.png`. Kill `$PID`.

**Step 4: Prepare the 1Password profile on the internal disk.** Copy the week-1 profile (it holds the installed
1Password extension and the native messaging manifest):
`ditto $PROF/1password-test "$IPROF/1password"` then
`ls "$IPROF/1password/NativeMessagingHosts/com.1password.1password.json"`.

**Step 5: Record and commit**

```zsh
git add engine/README.md docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Sign the Arkt release build and record the install smoke"
```

#### Needs the user (only if week-1 Task 8 still fails)

1. 1Password > Settings > Browser > Add Browser > choose `/Applications/Arkt.app` (authorize when asked). Note the
   exact message if it refuses.
2. Run:

       /Applications/Arkt.app/Contents/MacOS/Arkt --user-data-dir="$HOME/Library/Application Support/ArktTest/1password" \
         --use-mock-keychain --no-first-run --no-default-browser-check --enable-logging=stderr \
         --arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa https://example.com \
         > "$HOME/Library/Application Support/ArktTest/1password-popup.log" 2>&1

   PASS: the popup shows your account(s) or offers unlock with Touch ID / the app. FAIL: logo splash only, or a
   sign-in form asking for the Secret Key (do not sign in there).
3. Then run and send back the output:

       grep -hE "Verifying browser|code signature|Browser support error|XPC connected" ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/Library/Application\ Support/1Password/Data/logs/*.log | tail -8

   PASS evidence is `Verifying browser "/Applications/Arkt.app/..."` followed by `XPC connected`, with no
   `status 100001`.
4. If week 1 created `/Applications/Arkt Spike.app` (a symlink), remove it yourself if you no longer want it.

Time-box: 1.5 h working time, after the build.

---

### Task W3: Inventory of non-Views window seams (doc only, no build)

Runs while W1 builds. Produces the evidence for the W5b gate and the patch projection.

**Files:**
- Modify: `$RES` (section "Seam inventory")

**Steps** (all read-only on `$CR`):

```zsh
cd $CR
# 1. Direct dereferences of GetBrowserViewForBrowser (crash if the window is not a BrowserView).
git grep -n 'GetBrowserViewForBrowser([^;]*)->' -- chrome ':!*test*'
# 2. Assigned-then-used sites: list files, then read each call site and classify null-checked / CHECKed / unchecked.
git grep -n 'GetBrowserViewForBrowser' -- chrome ':!*test*' ':!*browsertest*' | wc -l
# 3. Webium-gated seams: what Webium had to special-case for a non-BrowserView normal window.
git grep -n 'IsWebUIBrowserEnabled()' -- chrome ':!*test*' ':!chrome/browser/ui/webui_browser/*'
# 4. Widget lookups on a browser window followed by a dereference.
git grep -n 'GetWidgetForNativeWindow(.*GetNativeWindow' -- chrome/browser ':!*test*'
# 5. Static casts of BrowserWindow to BrowserView.
git grep -n 'static_cast<BrowserView\*>' -- chrome ':!*test*'
```

Classify each hit into: (a) reached on normal-window startup, tab add/close/activate, extension popup/action,
`chrome.tabs`/`chrome.windows` APIs, Web Store install, or keyboard shortcuts (must handle in W5b); (b) reached only
by features Arkt does not use this week (side panel, tab groups UI, toolbar buttons, HaTS, cast, labs); (c)
null-safe already. For category (a), note whether a single upstream predicate would cover it (for example extending
`IsWebUIBrowserEnabled()`-style branches with an Arkt check) and how many files that touches.

At 156 this plan found: 165 `GetBrowserViewForBrowser` calls in 119 non-test files; 8 direct dereferences
(`extension_dialog_utils_views.cc:90`, `popup_base_view.cc:179`, `file_system_access_usage_bubble_view.cc:457`,
`hats_next_web_dialog.cc:82`, `cast_dialog_coordinator.cc:90`, `back_forward_button.cc:99`,
`chrome_labs_coordinator.cc:178`, `ambient_signin_controller.cc:120`); 14 non-Webium files gated on
`IsWebUIBrowserEnabled()`. Record the classification table, the count of category (a) files, and the projected seam
patch files (one per theme: browser features init, tab features, dialogs/anchoring).

**Verification:** `$RES` has the five command outputs (counts), the classification table, and a projected number.

**Commit**

```zsh
git add docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Record the non-Views browser window seam inventory"
```

Time-box: 2 h.

---

### Task W4: Extensions menu lists every action (finding 1)

No upstream patch. Works on the week-1 mount path now and on `ArktBrowserWindow` later (W6).

**Files:**
- Create: `engine/test-extensions/action-probe/manifest.json`, `popup.html`, `popup.js`, `sw.js`
- Modify: `engine/test-extensions/tabs-probe/sw.js` (keep-alive line)
- Create: `engine/arkt/browser/arkt_extensions_menu.h`, `arkt_extensions_menu.mm`
- Modify: `engine/arkt/browser/arkt_extensions_bridge.{h,mm}` (popup is created from `TriggerPopup`, not by hand)
- Modify: `engine/arkt/browser/arkt_browser_main_extra_parts.mm` (remove `kUBlockLiteId`, wire the menu)
- Modify: `engine/arkt/browser/BUILD.gn`

**Step 1: Test extension `action-probe`** (MV3, also used by W6 and W7)

`manifest.json`:
```json
{
  "manifest_version": 3,
  "name": "Arkt action probe",
  "version": "1.0",
  "permissions": ["tabs"],
  "action": { "default_title": "Arkt action probe", "default_popup": "popup.html" },
  "background": { "service_worker": "sw.js" }
}
```
`popup.html` shows the text `ARKT action-probe popup` and three buttons with ids `create`, `open`, `window` that call
`chrome.tabs.create({url: 'about:blank#probe-create', active: false})`,
`window.open('about:blank#probe-open')`, and `chrome.windows.create({url: 'about:blank#probe-window'})`. `sw.js` logs
`ARKT action-probe sw ready` and exposes `self.probe = {create, open, window}` doing the same from the service worker
(`window.open` is not available there; `open` uses `chrome.tabs.create({url, active: true})` and the popup button is
the real `window.open` test), so W5b-W6 can drive them over CDP without input. Both `action-probe/sw.js` and
`tabs-probe/sw.js` (add one line there) keep their worker alive with
`setInterval(() => chrome.runtime.getPlatformInfo(), 20000)`, so the CDP target does not disappear mid-sequence.
No icon file: Chromium draws a default
letter icon, which exercises the vector/letter icon path.

**Step 2: Write the failing check first.** Launch the current build with two action extensions:

```zsh
"$OUT/Chromium.app/Contents/MacOS/Chromium" --user-data-dir=$PROF/week2 --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr \
  --load-extension=$REPO/engine/test-extensions/action-probe,$REPO/engine/test-extensions/tabs-probe \
  --arkt-extensions-demo=list https://example.com > $PROF/w2-w4-before.log 2>&1 & PID=$!
```
Expected now: `ARKT: toolbar actions 2` (tabs-probe has no `action` key but MV3 extensions still get a toolbar
action; record the real number), and AXPress on the Extensions button logs `extension not installed
ddkjiahejlhfcafbddmgiahcphecmpfh`. That is the failure to fix. Kill `$PID`.

**Step 3: `ArktExtensionActionDelegate`** (in `arkt_extensions_menu.mm`), implementing
`ExtensionActionDelegate` (`chrome/browser/ui/extensions/extension_action_delegate.h`):
- `AttachToModel`/`DetachFromModel`: keep the model pointer.
- `RegisterCommand`/`UnregisterCommand`: no-op this week (keyboard commands for actions are later work; log once).
- `IsShowingPopup`/`HidePopup`/`GetPopupNativeView`: answer from the one current `PopoverExtensionView`.
- `TriggerPopup(std::unique_ptr<ExtensionViewHost> host, PopupShowAction, bool by_user, ShowPopupCallback cb)`:
  replace the current popup with `PopoverExtensionView(std::move(host), anchor)`; run `cb` with the host once
  `OnLoaded` fires (check the `ShowPopupCallback` signature in `extension_popup_types.h`).
- `ShowContextMenuAsFallback`, `CloseExtensionsMenuIfOpen`: log, no-op.
- `GetActiveWebContents()`: return the WebContents Arkt shows (week-1 path: the mounted tab; W6: the window's
  selected tab). This is what makes the action run against our tab, not Chrome's active tab.

**Step 4: `ArktExtensionsMenu`** (`arkt_extensions_menu.{h,mm}`): one per Arkt window.
- Observes `ToolbarActionsModel::Get(profile)` (`AddObserver`; handle `OnToolbarModelInitialized`,
  `OnToolbarActionAdded/Removed/Updated`, `OnToolbarActionsModelShutdown`). Keeps one
  `ExtensionActionViewModel` per `action_ids()` entry, created with `ExtensionActionViewModel::Create(id, browser,
  std::make_unique<ArktExtensionActionDelegate>(...))`.
- The sidebar "Extensions" button shows an `NSMenu` built on click: one item per action, title
  `GetActionName()`, image from `GetIcon(web_contents, gfx::Size(16, 16))`. `GetIcon` returns `ui::ImageModel`;
  if it is a vector icon, rasterize with `image_model.Rasterize(&web_contents->GetColorProvider())`
  (`ui/base/models/image_model.h:118`, `content/public/browser/web_contents.h:703`), then
  `gfx::Image(image_skia).ToNSImage()`. Disabled actions (`IsEnabled(web_contents)` false) are shown disabled.
- Choosing an item calls `ExecuteUserAction(ToolbarActionViewModel::InvocationSource::kMenuEntry)`; the view model
  decides popup vs. click event and calls `TriggerPopup` on our delegate.
- With no actions the menu shows one disabled item "No extensions".
- Log `ARKT: toolbar actions <n>` and `ARKT action <id> <name>` on every model change (keeps week-1 log lines).

**Step 5: Remove the hard-coding.** Delete `kUBlockLiteId` and the direct `RunAction` + `CreatePopupHost` path in
`ShowExtensionPopup`; `--arkt-extensions-demo=<id>` now looks up that action's view model and calls
`ExecuteUserAction(kToolbarButton)`; `--arkt-extensions-demo=list` only logs.

**Step 6: Build and verify without input**

```zsh
"$OUT/Chromium.app/Contents/MacOS/Chromium" --user-data-dir=$PROF/week2 --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9333 \
  --load-extension=$REPO/engine/test-extensions/action-probe,$REPO/engine/test-extensions/tabs-probe \
  --arkt-extensions-demo=<action-probe id from the list line> https://example.com > $PROF/w2-w4.log 2>&1 & PID=$!
grep -E "ARKT: toolbar actions|ARKT action |TriggerPopup|popup loaded" $PROF/w2-w4.log
node $REPO/engine/tools/cdp.mjs popup.html 'document.body.innerText.includes("ARKT action-probe popup")'
```
Expected: the action count and one `ARKT action` line per action; `TriggerPopup` and `popup loaded
chrome-extension://<id>/popup.html`; CDP prints `true`. Window-only screenshot `w2-w4-popup.png` shows the popover at
the Extensions button.

**Step 7: Verify the menu with AX** (no keystrokes). After the frontmost and key-window checks (Rules):

```zsh
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to click button \"Extensions\" of window 1"
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get name of every menu item of menu 1 of window 1"
```
Expected: the names list equals the `ARKT action` names, in model order. Then `click menu item "Arkt action probe"`
(same AX path) logs a second `popup loaded`. If the menu is not reachable at that AX path, print the AX tree of
window 1 once (`entire contents`) and adapt the path; do not fall back to coordinates for menus.

**Step 8: Real extensions.** Repeat Step 6 with `--user-data-dir=$PROF/1password-test` (1Password installed) and
`--load-extension=$REPO/engine/test-extensions/action-probe`: the list must contain 1Password and the probe. Opening
1Password's popup through `--arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa` must log `popup loaded
chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup/index.html`.

**Step 9: Commit**

```zsh
git add engine/test-extensions/action-probe engine/test-extensions/tabs-probe/sw.js engine/arkt/browser docs/plans/2026-10-23-engine-week2-results.md
git commit -m "List all extension actions in a native menu and open the chosen popup"
```

Time-box: 4 h.

---

### Task W5a: `ArktBrowserWindow` skeleton behind `--arkt-native-window` (factory hook, patch 0003)

**Files:**
- Create: `engine/arkt/browser/arkt_browser_window_factory_hook.{h,cc}` (tiny target, no Chrome UI deps)
- Create: `engine/arkt/browser/arkt_browser_window.{h,mm}`
- Modify: `engine/arkt/browser/BUILD.gn` (new `source_set("window_factory_hook")`; `arkt_browser_window.mm` in
  `//arkt/browser`)
- Modify: `engine/arkt/browser/arkt_browser_main_extra_parts.{h,mm}` (register the factory in `PreProfileInit`)
- Upstream (patch 0003): `chrome/browser/ui/views/frame/browser_window_factory.cc`,
  `chrome/browser/ui/views/frame/BUILD.gn`

**Why a registration hook and not a direct dependency:** `//arkt/browser` depends on large Chrome UI targets and is a
dependency of `//chrome/browser:core` (patch 0001). Making `:browser_window_factory` depend on it risks a GN cycle.
A function pointer in a dependency-free target breaks the cycle, and the registration happens before the first
`Browser` is created (profile init precedes the startup browser).

**Step 1: Hook target** (`arkt_browser_window_factory_hook.h`)

```cpp
namespace arkt {
using CreateBrowserWindowFn = std::unique_ptr<BrowserWindow, BrowserWindowDeleter> (*)(
    BrowserWindowInterface* browser);
// Set once at startup by //arkt/browser; nullptr means "use Chromium's window".
void SetCreateBrowserWindowOverride(CreateBrowserWindowFn fn);
CreateBrowserWindowFn GetCreateBrowserWindowOverride();
}  // namespace arkt
```
Deps: `//chrome/browser/ui:browser_window_deleter` only (check the exact target with
`git -C $CR grep -n browser_window_deleter -- chrome/browser/ui/BUILD.gn`).

**Step 2: Upstream patch 0003.** In `BrowserWindow::CreateBrowserWindow`, before the Webium branch:

```cpp
  if (auto fn = arkt::GetCreateBrowserWindowOverride()) {
    if (auto window = fn(browser)) {
      return window;
    }
  }
```
plus `"//arkt/browser:window_factory_hook"` in `source_set("browser_window_factory")` deps. The override returns
nullptr for anything Arkt does not take (non-normal types, switch absent), so Chromium's path is unchanged then.
Commit on `$CR` branch `arkt` with subject `Arkt: let Arkt create normal browser windows`, then Export
(`engine/README.md`).

**Step 3: `ArktBrowserWindow`.** `class ArktBrowserWindow : public BrowserWindow`. Model the method list on
`chrome/browser/ui/webui_browser/webui_browser_window.{h,cc}` (its `BrowserWindow` overrides and its stubs):
- Real this step: `GetNativeWindow` (our `ArktWindow` NSWindow), `Show`, `ShowInactive`, `Close` (orderOut, then
  `BrowserWindowDeleter` contract as Webium does), `Activate`, `Deactivate`, `IsActive`, `GetBounds`,
  `GetRestoredBounds`, `SetBounds`, `IsMaximized`, `IsMinimized`, `IsFullscreen`, `IsVisible`,
  `IsOnCurrentWorkspace`, `IsVisibleOnScreen`, `GetContentsSize`, `GetNativeTheme`, `GetThemeProvider`,
  `GetColorProvider`, `HandleKeyboardEvent` (Cmd-key equivalents to `NSApp.mainMenu`, like `ArktWindow` does today),
  `PreHandleKeyboardEvent` (not handled), `IsToolbarVisible` (true, so `chrome.action.openPopup` is allowed).
- Every other override: a stub that logs `ARKT: stub <method>` once per method (a function-local static set), and
  returns the neutral value Webium returns. Do not copy Webium code verbatim beyond method signatures; read it for
  what each method must return to be safe.
- The window is an `ArktWindowController`-style NSWindow (reuse `ArktWindow` and the layout: 190 pt sidebar
  placeholder with the Extensions button, inset rounded card). Content mounting is minimal in this step: on
  `OnTabStripModelChanged` with a selection change, put the active tab's `WebContents::GetNativeView()` NSView in the
  card (W5c replaces this with the real tab list). No `ViewsHostableDetach()` is needed: these views were never
  Views-hosted. Log `ARKT: native window mounted tab <tab id>`.

**Step 4: Register.** In `ArktBrowserMainExtraParts::PreProfileInit()` (`chrome_browser_main_extra_parts.h:40`):
if the command line has `arkt-native-window`, call `SetCreateBrowserWindowOverride` with a function that returns
`new ArktBrowserWindow(browser)` for `TYPE_NORMAL` and nullptr otherwise. In `PostBrowserStart`, skip
`MountActiveTab` when the switch is present, and log a census:
`ARKT: browsers normal=<n> arkt=<n> views=<n>` (iterate `GlobalBrowserCollection`; a browser is `arkt` if
`BrowserWindow::FromBrowser(b)` is an `ArktBrowserWindow`).

**Step 5: Build and smoke** (no input)

```zsh
"$OUT/Chromium.app/Contents/MacOS/Chromium" --user-data-dir=$PROF/week2-native --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9333 --arkt-native-window \
  https://example.com > $PROF/w2-w5a.log 2>&1 & PID=$!
grep -E "ARKT: (browsers|native window mounted|stub)" $PROF/w2-w5a.log | sort | uniq -c
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState + " " + document.title'
```
Expected: `ARKT: browsers normal=1 arkt=1 views=0`, one `native window mounted tab`, CDP prints
`"visible Example Domain"`, the process is alive after 30 s (`ps -p $PID`). Window-only screenshot shows example.com
in the card. A crash or `CHECK` here goes to W5b, not into this task's time-box beyond one attempt.

**Step 6: Commit** (overlay + exported patch together)

```zsh
git add engine/arkt/browser engine/patches/chromium docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Add the ArktBrowserWindow skeleton behind --arkt-native-window"
```

Time-box: 6 h.

---

### Task W5b: Seam fixes found by the smoke matrix (GATE)

**Files:**
- Upstream: only the files the smoke matrix hits, one commit (= one patch file) per theme
- Modify: `engine/arkt/browser/arkt_browser_window.mm` (prefer fixing on our side when the caller has a seam)
- Modify: `$RES`

**Step 1: Smoke matrix.** With `--arkt-native-window`, run each scenario in a fresh launch (profile
`$PROF/week2-native`, `--load-extension=$REPO/engine/test-extensions/action-probe,$REPO/engine/test-extensions/tabs-probe`,
`--remote-debugging-port=9333`), driving it with launch switches and CDP only:

| # | Scenario | Driver |
|---|---|---|
| 1 | Startup, idle 30 s | launch |
| 2 | Navigate the tab | `cdp.mjs example.com 'location.href="https://example.org"'` |
| 3 | Extension adds a background tab | `cdp.mjs $PROBE_SW 'probe.create()'` |
| 4 | Extension opens a popup | `--arkt-extensions-demo=<action-probe id>` (a "no container" style failure here is ordering: W6 registers `ExtensionsContainer`; not a seam) |
| 5 | `chrome.windows.create` | `cdp.mjs $PROBE_SW 'probe.window()'` |
| 6 | Close a tab | `cdp.mjs $PROBE_SW 'chrome.tabs.query({}).then(t=>chrome.tabs.remove(t.at(-1).id))'` |
| 7 | Close the window, quit | `cdp.mjs $PROBE_SW 'chrome.windows.getAll().then(w=>Promise.all(w.map(x=>chrome.windows.remove(x.id))))'` |
| 8 | Page `window.open` (no features) | `cdp.mjs example.com 'window.open("about:blank#page-open")'` |

Pass for each: process alive (except 7, which must exit with status 0 within 10 s), no `FATAL`/`CHECK failed`
in the log. For a crash, the stack trace in the log (symbol-table names; `symbol_level=0` gives no line numbers) names
the seam. If the trace is not enough, run once under `lldb` and use `bt`.

**Step 2: Fix order.** For each crash: (1) can `ArktBrowserWindow` return something that makes the caller safe (a
non-null object, a stub `LocationBar`/`StatusBubble` as Webium uses `WebUIStubLocationBar`)? Do that, no patch. (2)
Otherwise patch the caller to tolerate a non-`BrowserView` window, using the predicate the caller already uses for
Webium where one exists. Group fixes into one upstream commit per theme (`Arkt: tolerate a non-Views window in
browser features`, `... in tab features`, `... in dialogs`), Export after each.

**Step 3: GATE.** Stop W5c-W7 and write a decision note in `$RES` if any of these holds: more than 8 seam patch
files would be needed; more than 25 upstream files touched by seam patches; a seam needs a change to a widely included
header. The note lists the remaining crashes and the cheapest alternative, which is to back `ArktBrowserWindow` with a
frameless `views::Widget` (as Webium does) so Widget-based callers work, while Arkt's AppKit views fill its
`NSWindow`. That alternative is still `ArktBrowserWindow`; it is not the hidden-`BrowserView` option.

**Verification:** all 8 scenarios pass; `$RES` lists every seam (file, symptom, fix: our side or patch N) and the
updated patch budget table.

**Commit:** one commit per theme, each with its exported patch file and `.patches`, plus `$RES`. Message per theme,
e.g. `Tolerate a non-Views normal window in browser features`.

Time-box: 1.5 days. If not done by then, the gate note is mandatory.

---

### Task W5c: Arkt-owned tab list and visibility (finding 2)

**Files:**
- Create: `engine/arkt/browser/arkt_tab_list_view.{h,mm}` (placeholder tab list in the sidebar, AppKit)
- Modify: `engine/arkt/browser/arkt_browser_window.{h,mm}`

**Step 1: Tab list.** `ArktBrowserWindow` implements `TabStripModelObserver::OnTabStripModelChanged`
(`tab_strip_model_observer.h:521`) and keeps an ordered list of tab entries (`tabs::TabHandle` or the tab's
`SessionID` from `sessions::SessionTabHelper::IdForTab`, title, URL). The sidebar placeholder shows them as an
`NSTableView` (one row per tab, title text; this is an engine test surface, not the real ShellKit sidebar). Clicking a
row calls `TabStripModel::ActivateTabAt(index)`.

**Step 2: Visibility.** On a selection change (from Arkt or from Chromium), Arkt mounts the new active tab's view in
the card and removes the previous one with `removeFromSuperview` (Decision 3). Arkt never calls
`WasHidden`/`WasShown` directly; the view hierarchy drives it. Keep a debug switch `--arkt-trace-visibility` that logs
`ARKT: visibility <tab id> <visible|hidden|occluded>` from each tab's `WebContents::GetVisibility()` after every
change.

**Step 3: Verify** (no input)

```zsh
# launch as in W5b with --arkt-trace-visibility, page https://example.com
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'probe.create()'          # background tab
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState'          # must stay "visible"
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'chrome.tabs.query({url:"about:blank"}).then(t=>chrome.tabs.update(t[0].id,{active:true}))'
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState'          # now "hidden"
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'chrome.tabs.query({url:"https://example.com/*"}).then(t=>chrome.tabs.update(t[0].id,{active:true}))'
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState'          # "visible" again
```
Expected exactly as commented, with matching `ARKT: visibility` log lines, and the table shows 2 rows. This is the
week-1 reproduction (opening any tab blacked out our card) turned into a passing check. Then the input check: after the
frontmost/key checks, AXPress row 2 of the table (`select row 2 of table 1 of scroll area 1 of window 1`, adapt the AX
path once) and confirm with CDP that the about:blank tab is `visible` and example.com is `hidden`. Window-only
screenshot after each switch.

**Step 4: Commit**

```zsh
git add engine/arkt/browser docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Drive tab visibility from the Arkt window, not Chrome's tab strip"
```

Time-box: 5 h.

---

### Task W6: Extension window identity, extension-created tabs and windows (finding 3)

**Files:**
- Create: `engine/arkt/browser/arkt_extensions_container.{h,mm}`
- Modify: `engine/arkt/browser/arkt_browser_window.{h,mm}`, `arkt_extensions_menu.mm`
- Modify: `engine/test-extensions/tabs-probe/sw.js` (also log window ids)

**Step 1: `ArktExtensionsContainer`** implements `ExtensionsContainer`
(`chrome/browser/ui/extensions/extensions_container.h`: `GetActionForId`, `HideActivePopup`,
`CloseExtensionsMenuIfOpen`, `ShowToolbarActionPopupForAPICall`, `ToggleExtensionsMenu`, `HasAnyExtensions`,
`GetActiveWebContents`) on top of the window's `ArktExtensionsMenu` view models. `ArktBrowserWindow` registers it with
`ui::ScopedUnownedUserData<ExtensionsContainer>` on `browser->GetUnownedUserDataHost()`, as Webium does
(`webui_browser_window.cc:194`). This makes `chrome.action.openPopup()` open our popover
(`extension_action_api.cc:156`).

**Step 2: tabs-probe logs ids.** `sw.js` additionally logs
`ARKT tabs.query windows=<distinct windowIds joined by ,>`.

**Step 3: Verify identity** (no input). Launch with `--arkt-native-window --arkt-trace-visibility`, both test
extensions, `https://example.com`.

```zsh
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'chrome.windows.getAll({populate:true}).then(w=>w.map(x=>[x.id,x.type,x.tabs.length]))'
grep "ARKT: native window session id" $PROF/w2-w6.log
```
`ArktBrowserWindow` logs `ARKT: native window session id <browser->GetSessionID().id()>` at creation. Expected:
one window, its id equals the logged session id, type `normal`, tab count equals the table rows.

**Step 4: Verify extension-created tabs and windows** (each must land in Arkt; no Views browser may appear)

| Action | Expected |
|---|---|
| `probe.create()` (background tab) | new row in our table; census `views=0`; example.com stays visible |
| `chrome.tabs.create({url:"about:blank#fg", active:true})` | new row, selected, mounted, visible |
| popup button `open` (`window.open` from the popup, via `cdp.mjs popup.html 'document.getElementById("open").click()'`) | new row in our window |
| `probe.window()` (`chrome.windows.create`) | a second Arkt window; census `normal=2 arkt=2 views=0`; `windows.getAll` returns 2 ids matching the two logged session ids |
| `chrome.action.openPopup()` from the worker (needs a focused Arkt window) | `popup loaded` for action-probe in our popover |
| Reinstall-style welcome page: `chrome.tabs.create({url: chrome.runtime.getURL("popup.html")})` | new row showing the extension page in our card |

After each action re-run the census grep and `windows.getAll`. Window-only screenshot of each Arkt window after the
table.

**Step 5: Real extension.** Launch with `$PROF/1password-test` and `--arkt-native-window`, then from the 1Password
service worker over CDP open its welcome page: `chrome.tabs.create({url: chrome.runtime.getURL("app/app.html#/page/welcome")})`
(the page week 1 saw land in Chrome's window). Expected: a new row in our table and census `views=0`. Do not interact
with the page.

**Step 6: Commit**

```zsh
git add engine/arkt/browser engine/test-extensions/tabs-probe docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Route extension-created tabs and windows into Arkt windows"
```

Time-box: 5 h.

---

### Task W7: Web Store install on the native window

The install prompt is a Views browser-modal dialog parented to the browser's `gfx::NativeWindow`
(`extension_install_dialog_view.cc` ~line 104, `constrained_window::CreateBrowserModalDialogViews`). With
`ArktBrowserWindow` that parent is our plain `NSWindow`. This task proves it still works (or records what breaks);
a native sheet through `ShowDialogCallback` is week 3.

**Files:**
- Modify: `$RES` (and `arkt_browser_window.mm` only if a fix is on our side)

**Steps:**
1. Launch with `--arkt-native-window`, a fresh profile `$PROF/week2-cws`, `--remote-debugging-port=9333`, and the uBO
   Lite Web Store detail page URL. Reject the Google consent interstitial over CDP and press "Add to Chrome" over CDP
   with `userGesture: true`, as week-1 Task 6 did.
2. Expected: the prompt appears as a window (record its owner and position with a window-only screenshot), the census
   still says `views=0`. Accept it with one guarded click (frontmost + key checks, click point inside the prompt's
   bounds read from `osascript ... get {position, size} of window 1`), as week 1 did.
3. Expected: `ARKT: toolbar actions` count goes up by one and the menu lists uBlock Origin Lite; its popup opens through
   the menu path (W4 Step 7).

If the prompt crashes or never shows, record the stack in `$RES`, fix on our side if the window can provide what is
missing (for example a `web_modal::WebContentsModalDialogHost`), otherwise add the seam to W5b's theme patch and
re-run the gate check.

**Commit**

```zsh
git add docs/plans/2026-10-23-engine-week2-results.md engine/arkt/browser
git commit -m "Verify Web Store install with the native browser window"
```

Time-box: 3 h.

---

### Task W8: Keychain: no login-keychain access in tests; "Arkt Safe Storage" in the product (finding 5)

**Files:**
- Upstream (one patch): `components/os_crypt/common/keychain_password_mac.mm`
- Modify: `engine/README.md` (launch flags section: `--use-mock-keychain` is mandatory for test runs)
- Modify: `$RES`

**Step 1: Audit test runs (read-only, no prompts).** Record the item's metadata only (no `-w`, no `-g`):

```zsh
security find-generic-password -s "Chromium Safe Storage" 2>/dev/null | grep -E '"mdat"|"acct"' ; echo "exit $?"
security find-generic-password -s "Arkt Safe Storage" >/dev/null 2>&1; echo "arkt item exit $?"
```
Run a W5a-style launch (with `--use-mock-keychain`) for 30 s, kill it, and run the commands again. Expected: the
"Chromium Safe Storage" `mdat` is unchanged and no "Arkt Safe Storage" item exists. Then add a "Launch flags"
section to `engine/README.md` that makes `--use-mock-keychain` and `--user-data-dir` mandatory for every test launch,
and check that every launch command in the README carries both:
`grep -n 'Contents/MacOS/' $REPO/engine/README.md` and read each hit.

**Step 2: Patch** (on `$CR` branch `arkt`, subject `Arkt: use the Arkt Safe Storage keychain item`): in
`keychain_password_mac.mm` replace the non-Chrome-branded constants:

```cpp
#else
const char kDefaultServiceName[] = "Arkt Safe Storage";
const char kDefaultAccountName[] = "Arkt";
#endif
```
Export. Build `out/Spike`.

**Step 3: Verify without touching the keychain**

```zsh
F="$OUT/Chromium.app/Contents/Frameworks/Chromium Framework.framework/Versions/Current"
for b in "$F/Chromium Framework" $OUT/libos_crypt*.dylib(N) $OUT/lib*os_crypt*.dylib(N); do strings -a "$b" | grep -E "^(Arkt|Chromium) Safe Storage$"; done | sort | uniq -c
```
Expected: `Arkt Safe Storage` present, `Chromium Safe Storage` absent from `keychain_password_mac`'s library (in a
component build the constant lives in the os_crypt dylib; find it with
`grep -l "Safe Storage" $OUT/*.dylib` if the names differ). The Linux `freedesktop_secret_key_provider.h` constant is
not built on Mac and may be ignored. Note in `$RES`: existing test profiles encrypted with the mock keychain are
unaffected; any profile created without the mock flag before this patch can no longer decrypt its saved passwords
and cookies (throwaway test data).

**Step 4: Commit**

```zsh
git add engine/patches/chromium engine/README.md docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Use the Arkt Safe Storage keychain item"
```

#### Needs the user

1. Decide about the existing "Chromium Safe Storage" item in your login keychain. It may belong to another
   Chromium-based app you use, so the contributor will not delete it. If you know it came only from Arkt test builds, delete
   it yourself in Keychain Access.
2. Once, after W10 installs the rebuilt `/Applications/Arkt.app`: launch it WITHOUT `--use-mock-keychain`:

       /Applications/Arkt.app/Contents/MacOS/Arkt --user-data-dir="$HOME/Library/Application Support/ArktTest/keychain" --no-first-run

   Expected: no keychain prompt mentioning "Chromium Safe Storage"; afterwards Keychain Access shows an
   "Arkt Safe Storage" item (account "Arkt"). If macOS asks for access to "Arkt Safe Storage", answer Always Allow and
   tell the contributor running the plan (that would mean the item's ACL does not match the signed app).

Time-box: 2 h (plus one incremental build).

---

### Task W9: Make the native window the default; try dropping patch 0002

**Files:**
- Modify: `engine/arkt/browser/arkt_browser_main_extra_parts.mm` (switch inverted: `--arkt-views-window` keeps the
  week-1 path for one more week, then delete it)
- Possibly delete: `engine/patches/chromium/0002-*.patch` and its `.patches` line
- Modify: `$RES`

**Steps:**
1. Make `ArktBrowserWindow` the default for `TYPE_NORMAL`. Re-run the W5b smoke matrix and W5c/W6 verifications
   without any switch. All must pass.
2. Patch 0002 test: on `$CR` branch `arkt`, `git revert` the 0002 commit, build, re-run W5c Step 3 and W6 Step 4.
   If all pass and pages draw (window-only screenshots non-blank, CDP `visibilityState` as expected), Export (0002
   disappears, later patches renumber) and record "0002 dropped". If anything fails, `git reset --hard HEAD~1` on
   `arkt` (only the revert commit, which was never exported), rebuild, and record why 0002 stays.
3. Update the patch budget table in `$RES` with final numbers (patch files, upstream files).

**Verification:** `wc -l < $REPO/engine/patches/chromium/.patches` equals `git -C $CR rev-list --count
156.0.8078.48..arkt`, and the full matrix passes on the default path.

**Commit**

```zsh
git add engine/arkt/browser engine/patches/chromium docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Use ArktBrowserWindow for normal windows by default"
```

Time-box: 4 h (two incremental builds).

---

### Task W10: Rebuild the release bundle with week-2 changes, re-sign, final smoke, housekeeping

**Files:**
- Modify: `$RES` (final table, open items)

**Steps:**
1. Incremental `out/Arkt` build (`nice -n 15 autoninja -C out/Arkt chrome`, background). Re-sign with W2 Step 1.
   Replace the installed copy: `rm -rf /Applications/Arkt.app && ditto $REL/Arkt.app /Applications/Arkt.app` (only the
   bundle W2 installed; check `codesign -dv /Applications/Arkt.app 2>&1 | grep Identifier=com.arkt.Arkt` first).
2. Smoke from `/Applications` with `$IPROF/smoke`: page renders, census `views=0`, `probe.create()` adds a row, the
   Extensions menu lists the loaded probes, keychain strings check from W8 Step 3 on `Arkt Framework`
   (non-component: the constant is inside the framework binary).
3. Housekeeping: kill every PID this track started that is still alive (list them from `$RES`), confirm no
   `Chromium`/`Arkt` process from `$OUT`, `$REL` or `/Applications/Arkt.app` remains
   (`ps -axo pid,command | grep -E "out/Spike|out/Arkt|/Applications/Arkt.app" | grep -v grep`), leave
   `$PROF`/`$IPROF` profiles in place (they hold the 1Password test state), and confirm the patch counts match.
4. Fill the results table: PASS/FAIL per task with evidence, patch budget, open items.

**Commit**

```zsh
git add docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Record engine week 2 results"
```

#### Needs the user

Run W8's keychain step 2 and, if 1Password was still failing, repeat W2's 1Password steps against the rebuilt
`/Applications/Arkt.app` (the signature changed, so 1Password may ask to authorize it again).

Time-box: 3 h working time plus the incremental build.

---

## Order and parallelism

1. W0, then start W1's build (hours, background).
2. While W1 builds: W3 (doc only), W4 (incremental `out/Spike` builds), then W5a, W5b (gate), W5c, W6, W7.
3. W8 any time after W0 (independent; one patch, one incremental build).
4. W2 when W1's build is done. W9 after W5c-W7 pass. W10 last.

W4 and W8 are independent of the native window and can be split to a second contributor, as long as only one Chromium build
runs at a time; their patch exports must be serialized (the `arkt` branch is shared).

## Out of scope (next weeks)

- Native extension install sheet via `ExtensionInstallPrompt`'s `ShowDialogCallback`; extension context menus;
  action pinning and order; keyboard commands for actions.
- `TYPE_POPUP`, app, DevTools and picture-in-picture windows as Arkt windows; Little Arkt and Peek windows.
- Replacing other Views bubbles (permission prompts, page info, downloads, autofill dropdowns).
- The real ObjC/Swift engine API (`ArktBrowser`, `ArktWebContents`) and wiring into ShellKit's `EngineClient`.
- Framework rename (`arkt_framework` target), icons and UI strings, notarization, default user-data-dir name
  (`chrome_paths_mac.mm` still says "Chromium"; every launch passes `--user-data-dir` until then).

## Open questions (product decisions)

1. Bundle id for the product. `com.arkt.Arkt` is a placeholder. It must be settled before the first build a user
   relies on: changing it later resets TCC grants, the keychain item's ACL owner and 1Password's browser trust.
2. Where `window.open` popups with features and `chrome.windows.create({type:'popup'})` should go (Little Arkt-style
   floating window, Peek, or a normal Arkt window). Until decided they stay Chromium Views popup windows.
3. The existing "Chromium Safe Storage" item in the login keychain: keep or delete (user decides, W8).
4. If W5b's gate trips: accept a `views::Widget`-backed `ArktBrowserWindow` (fewer patches, a Views widget owns the
   `NSWindow`, Arkt's AppKit views fill it) or spend more of the patch budget on seams.
