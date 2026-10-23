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
through one small hook patch. Each Arkt window keeps one real `Browser` per profile shown in it (Decision 4) and its
`TabStripModel`; that model is the tab list for extensions (`tabs.*`, `windows.*`) and Arkt observes it.
`BrowserView` no longer exists for normal windows, and tab WebContents are never hosted through `views::WebView` /
`NativeViewHost`, so nothing in Views can hide our mounted pages (finding 2 goes away structurally) and new tabs have
nowhere to go but Arkt. Whether `ArktBrowserWindow` sits on a plain `NSWindow` or on a frameless `views::Widget` is
decided after W3 (Decision 1, "Strategy decision point"). Findings 1 and 5 are small: the extension menu uses Chromium's `ToolbarActionsModel` and
`ExtensionActionViewModel` with our own `ExtensionActionDelegate` (no patch); the keychain item name is one patch.
Finding 4 is a second output directory, `out/Arkt`, built with `is_component_build=false` and a GN-arg branding file
(no patch). The week-1 mount path stays runnable behind the absence of `--arkt-native-window` until W9 removes it.

**Tech Stack:** Chromium 156.0.8078.48 (GN + Siso), ObjC++ in `//arkt/browser`, AppKit, git `format-patch`/`am -3`
patch workflow (`engine/README.md`), Node 26 (built-in `WebSocket`) for the CDP helper, `codesign`, `screencapture`.

---

## Rules (read before every task)

| Name | Path |
|---|---|
| `$REPO` | the dedicated engine worktree of this repo (`arkt-wt/engine-week2`, branch `engine-week2`, see W0); `$CR/arkt` points here |
| `$CR` | `$CHROMIUM_ROOT/chromium/src` (Chromium checkout, branch `arkt` on 156.0.8078.48) |
| `$OUT` | `$CR/out/Spike` (component build, fast incremental; all engine work) |
| `$REL` | `$CR/out/Arkt` (non-component, Arkt-branded; W1, W2, W10) |
| `$PROF` | `$CHROMIUM_ROOT/profiles` (test profiles for `out/Spike`) |
| `$IPROF` | `$HOME/Library/Application Support/ArktTest` (test profiles for `/Applications/Arkt.app`) |
| `$RES` | `$REPO/docs/plans/2026-10-23-engine-week2-results.md` (results; created in W0) |

- Shell is zsh. Set once per shell:
  `export PATH=$CHROMIUM_ROOT/depot_tools:$PATH; REPO=/path/to/arkt-wt/engine-week2; CR=$CHROMIUM_ROOT/chromium/src; OUT=$CR/out/Spike; REL=$CR/out/Arkt; PROF=$CHROMIUM_ROOT/profiles; IPROF="$HOME/Library/Application Support/ArktTest"; RES=$REPO/docs/plans/2026-10-23-engine-week2-results.md`
- **Disk.** Never touch anything on the Chromium disk outside `$CHROMIUM_ROOT`. The Chromium checkout is edited
  only through the patch workflow in `engine/README.md`: commit on branch `arkt`, then run Export. Never leave
  unexported commits; Apply refuses to run over them.
- **Worktree.** All engine work happens in one dedicated worktree, `$REPO`, on branch `engine-week2` (created in W0).
  `$CR/arkt` is a symlink to `$REPO/engine/arkt`, so the Chromium build always compiles that worktree's overlay; the
  main checkout and every other worktree keep their own branches and are never built from. Other tracks use
  worktrees under `arkt-wt/`; do not touch them. If the symlink target is wrong, every build is stale: W0 checks it,
  and so does every task that builds (`readlink $CR/arkt` equals `$REPO/engine/arkt`).
- **Capacity.** One `out/Spike` build at a time. It may overlap the background `out/Arkt` build (W1, W10; runs at
  `nice -n 15`; both are slower, that is accepted), except while `out/Arkt` is in its final `Arkt Framework` link:
  then no `out/Spike` build, no Swift builds, no other heavy jobs (quiet machine, see "Internal disk and memory").
  While any Chromium build runs, at most two Swift builds may run, at `nice -n 20`. W4 and W5a run in sequence (both
  edit `arkt_browser_main_extra_parts.mm` and `BUILD.gn` and need `out/Spike` builds), or W4 runs alongside W5a only
  with new files plus a one-line wiring commit after W5a has landed ("Parallel lanes").
- **Internal disk and memory.** The internal disk holds swap and `/Applications`. Before starting W1, W2 or W10, and
  at every hourly check of a running `out/Arkt` build: `df -h / | tail -1` must show at least 8 GiB free, and record
  `sysctl vm.swapusage`. Below about 4 GiB free, stop the `out/Arkt` build by its recorded PID
  (`kill $(cat $CHROMIUM_ROOT/build-arkt.pid)`), record the numbers in `$RES` and ask the user; never delete files to
  make room. A swap `used` that keeps growing between checks during the framework link means the machine is not
  quiet: close other heavy jobs, do not start new ones.
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
  W0: `node $REPO/engine/tools/cdp.mjs [--user-gesture] <url-substring|type:service_worker> '<js expression>'`.
  Anything the popup blocker or a user-activation check guards (`window.open`, `requestFullscreen`, `showPicker`,
  file inputs, downloads, "Add to Chrome") needs `--user-gesture`; without it the call is blocked and the scenario
  tests nothing.
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
- **Commits.** One per task unless listed otherwise. Stage with file-level pathspecs: name each file
  (`git add engine/arkt/browser/arkt_browser_window.mm ...`, `git add engine/patches/chromium/.patches
  engine/patches/chromium/0003-*.patch`); no directory pathspecs, never `git add -A` or `git add .` (the checkout may
  hold untracked local tool directories and build leftovers). Check `git diff --cached --stat` before committing.
  Plain commit messages. Exported patch files and `.patches` are committed together with the overlay change that
  needs them.
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
   - *`ArktBrowserWindow`* (chosen). Upstream already branches this factory to a second `BrowserWindow`
     implementation: `BrowserWindow::CreateBrowserWindow` (`chrome/browser/ui/views/frame/browser_window_factory.cc:32`)
     returns `WebUIBrowserWindow` ("Webium") for `TYPE_NORMAL` when `kWebium` is on. Webium is a template for the
     method list, not proof that a non-Views window works: it is **Widget-backed** ("It still uses views::Widget for
     windowing management", `webui_browser_window.h:42-43`), so every caller that looks up a `views::Widget` from the
     browser's native window still finds one. 56 of its methods are `NOTIMPLEMENTED()` stubs, it registers its own
     `ExtensionsContainer` through `ui::ScopedUnownedUserData<ExtensionsContainer>` (`webui_browser_window.cc:194`),
     and `BrowserView::GetBrowserViewForBrowser` returns nullptr for windows that are not `BrowserView` (it reads
     `kBrowserViewKey` from the widget, `browser_view.cc:1193`). `BrowserWindowFeatures` creates
     `BrowserExtensionWindowController` for every `Browser` (`browser_window_features.cc:847`), so `chrome.windows.*`
     sees Arkt windows with no extra work. The test-only `custom_window` path in `Browser` is `CHECK_IS_TEST()`, so
     the factory hook patch is required.
   - **What a window that is neither `BrowserView` nor Webium does not get.** `BrowserWindowFeatures::Init`
     (`browser_window_features.cc:691-694`) computes `browser_view` and `webui_browser_window`
     (`WebUIBrowserWindow::FromBrowser`, which reads Webium's own native-window property) and creates these only
     under `if (browser_view)` / `else if (webui_browser_window)`, so `ArktBrowserWindow` gets none of them in either
     variant below unless it supplies an equivalent or a seam patch adds an Arkt arm:
     find bar owner (`FindBarOwnerViews` / `FindBarOwnerWebUIBrowser`, :849-856: Cmd-F has no owner);
     `ZoomBubbleManager` and zoom bubble coordinator (:952-963); `FullscreenControlHost` (:859, `browser_view` only);
     `DevtoolsUIController` (:792, `browser_view` only: docked DevTools); `ColorProviderBrowserHelper` (:742,
     `browser_view` only); the focus manager (:695-700, null for us), so no `ExtensionKeybindingRegistryViews`
     (:833: extension keyboard commands are absent) and `StubBrowserFocusController` (:726); the Webium exclusive
     access context (:801, created before `ExclusiveAccessManager` at :809, which otherwise takes
     `BrowserWindow::GetExclusiveAccessContext()`: ours must be real, W5a Step 3); bookmark bar delegate (:709),
     download toolbar UI controller (:823), side panel (:909-916), scrim, contents border, new tab footer, data
     protection UI. `tab_features.cc` has exactly one such arm and no `browser_view` arm: `SadTabHelper` is created
     whenever Webium is off (:646), so Arkt tabs get it, and `SadTabController` then does
     `GetBrowserViewForBrowser(browser)` + `DCHECK(browser_view)` + dereference (`sad_tab_controller.cc:31-34`):
     a crashed renderer is a known seam (W5b scenario 9).
   - **Strategy decision point (after W3, before W5a).** Two variants of `ArktBrowserWindow`; W3 counts seams for
     both and `$RES` records the choice with the counts:
     - *Plain `NSWindow`* (variant P, the default). `GetNativeWindow` is Arkt's own `NSWindow`; there is no
       `views::Widget` for the browser window. Every `GetWidgetForNativeWindow(...GetNativeWindow())`,
       `GetTopLevelWidgetForNativeView(...GetNativeView())` and `GetBrowserViewForNativeWindow` caller gets nullptr.
       Fewest moving parts, and it matches window ownership: the shipping ShellUI (ShellKit) owns its own borderless
       `NSWindow` (window chrome, sidebar, traffic lights, 120 Hz animations) and must keep owning it; the engine
       is handed that window, it does not create it.
     - *Frameless `views::Widget`-backed* (variant W, as Webium). Widget-based callers (anchored bubbles, tab-modal
       dialogs, `GetTopLevelWidgetForNativeView`) keep working, so fewer seam patches. Cost: `NativeWidgetMac`
       creates and owns the `NSWindow` (`NativeWidgetMac::CreateNSWindow`, a virtual at `native_widget_mac.h:261`),
       so either ShellUI's views are reparented into a Views-owned window, or a `NativeWidgetMac` subclass returns
       an Arkt `NSWindow` subclass from `CreateNSWindow` (W3 checks whether that is feasible without upstream
       changes). In both cases the Widget only provides windowing and anchoring; tab WebContents views are still
       mounted by Arkt in the card, never through `views::WebView`/`NativeViewHost` (otherwise finding 2's cause
       returns). Arkt identifies its window by `widget->SetNativeWindowProperty(kArktBrowserWindowKey, this)`, as
       `BrowserView` (`browser_view.cc:5018`) and Webium (`webui_browser_window.cc:284`) do.
     Choose P unless W3 projects that P exceeds the W5b gate and W stays inside it. The W5b gate (Step 3) switches
     P to W once if P trips it during the smoke run.
   - **Patch impact.** One hook patch (W5a). Seam patches that tolerate a non-`BrowserView` normal window are
     measured, not guessed: W3 inventories them (at 156, non-test code outside `webui_browser/`: 166 `GetBrowserViewForBrowser` calls in
     119 files, 8 of them direct `GetBrowserViewForBrowser(...)->` dereferences in 8 files; 13 `IsWebUIBrowserEnabled()`
     branches in 12 files outside `webui_browser/`, among them `BrowserElementsViewsImpl` in
     `browser_window_features.cc:352`; plus the assigned-then-dereferenced sites such as the sad tab above), W5b
     fixes the ones the smoke run hits, grouped into one patch file per theme. Patch 0002 (re-enable display after
     leaving Views) should become unnecessary, because normal-window WebContents are never Views-hosted; W9 tests
     dropping it. Projection in the patch budget below.
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
4. **One `Browser` per (Arkt window, profile).** A `Browser` belongs to exactly one profile, and Arc Spaces can use
   different profiles. All tabs of the Spaces that share a profile in one Arkt window live in that `Browser`'s
   `TabStripModel`; a Space on a second profile in the same window gets a second `Browser` (and a second
   `ArktBrowserWindow` facade over the same `NSWindow`). Space switching is an Arkt concept; extensions of a profile
   see one window with all of that profile's tabs in it, as Arc does. This week's smokes use one profile, so the
   census expectations (`normal=1 arkt=1`) count one `Browser` per Arkt window.
5. **Extension actions** come from `ToolbarActionsModel` (`chrome/browser/ui/toolbar/toolbar_actions_model.h`, its
   `Observer` for add/remove/update) and run through `ExtensionActionViewModel::Create(id, browser, delegate)`
   (`chrome/browser/ui/extensions/extension_action_view_model.h:61`) with our `ArktExtensionActionDelegate`. The
   delegate's `TriggerPopup(host, ...)` hands the `ExtensionViewHost` to the existing `PopoverExtensionView`, and its
   `GetActiveWebContents()` returns Arkt's selected tab. Pinning and ordering are later work.
6. **Branding without patches.** `branding_file_path` is a GN arg (`build/config/chrome_build.gni:109`). Pointing it at
   `//arkt/branding/BRANDING` renames the app, framework, helpers and bundle id. Icons and UI strings stay Chromium's
   for now. Bundle id `com.arkt.Arkt` is a placeholder (open question 1); changing it later resets TCC grants,
   keychain ACLs and 1Password's browser trust for that build. That is acceptable here: the GN-built `Arkt.app` is a
   throwaway test bundle, and any trust granted to it (1Password, TCC, keychain ACL) is discarded. The shipping app
   is the Swift `ArktShell` bundle that loads the engine framework (section "Week-3 entry"); its bundle id is the one
   that matters. With `PRODUCT_FULLNAME=Arkt` the framework is named `Arkt Framework`
   (`chrome_framework_name = chrome_product_full_name + " Framework"`, `chrome/BUILD.gn:489`); the final framework
   name is settled in week 3 (open question 5).
7. **Keychain.** Every test run uses `--use-mock-keychain`, which the keychain key provider honours
   (`components/os_crypt/async/browser/keychain_key_provider.mm:42`). The product name is set by one patch to
   `components/os_crypt/common/keychain_password_mac.mm` (`kDefaultServiceName` "Arkt Safe Storage",
   `kDefaultAccountName` "Arkt"). The runtime-configurable variant (`ALLOW_RUNTIME_CONFIGURABLE_KEY_STORAGE`) needs a
   GN define patch plus ordering against OSCrypt init in `browser_process_impl.cc:1651`; it buys nothing for us.
   The existing "Chromium Safe Storage" item in the user's login keychain is not ours to delete: it may belong to
   another Chromium-based app (open question 3).

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 | W0 records |
| 0002 | Let a WebContents view draw again after leaving Views | exists; W9 tries to drop it | 1-4 | W0 records |
| 0003 | `BrowserWindow` factory hook for Arkt (W5a) | new | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) | 0 |
| 0004+ | Non-`BrowserView` normal window seams (W5b), grouped by theme | new, measured in W3/W5b | W3 estimate | W3 estimate |
| next | Arkt keychain item name (W8) | new | 1 | 0 |

"Hot files" are the two files every upstream feature touches and that conflict on almost every rebase:
`chrome/browser/ui/browser_window/internal/browser_window_features.cc` and `chrome/browser/ui/tabs/tab_features.cc`.
Count their hunks across the whole patch set with
`git -C $CR diff 156.0.8078.48..arkt -- chrome/browser/ui/browser_window/internal/browser_window_features.cc chrome/browser/ui/tabs/tab_features.cc | grep -c '^@@'`.

Projection after week 2: 4 patch files plus the seam patches. The W5b gate stops the track (or switches the
variant) if seam patches would exceed 8 patch files, 25 upstream files, or 6 hunks in the hot files; at that point
the remaining budget (target < 30 overall, with week-3+ needs: framework rename, extension install UI, behaviour
tweaks) would be at risk. `$RES` keeps this table current (patch files, upstream files touched, hot-file hunks).

---

### Task W0: Branch, baselines, results file, CDP helper, key-window log

**Files:**
- Create: `$RES`
- Create: `engine/tools/cdp.mjs`
- Modify: `engine/arkt/browser/arkt_window_controller.mm` (log key-window changes)

**Step 1: Branch and state**

```zsh
MAIN=/path/to/arkt                                    # the main checkout; stays on its own branch
git -C $MAIN status --short --untracked-files=no       # must print nothing; otherwise ask who owns the changes
git -C $MAIN worktree add ../arkt-wt/engine-week2 -b engine-week2 spike/week1
REPO=${MAIN:h}/arkt-wt/engine-week2
ls -l $CR/arkt                                         # record the old target in $RES (Step 5)
ln -sfn $REPO/engine/arkt $CR/arkt && readlink $CR/arkt
git -C $CR branch --show-current; git -C $CR rev-list --count 156.0.8078.48..arkt; wc -l < $REPO/engine/patches/chromium/.patches
```
Expected: `readlink` prints `$REPO/engine/arkt` (expanded), then `arkt`, `2`, `2`. If the counts differ, stop: Export
first (`engine/README.md`). The symlink is the only thing that tells the build which overlay to compile; repoint it
only here, and never while a build runs.

**Step 2: Key-window log** (needed by the input rule). In `ArktWindowController`, observe
`NSWindowDidBecomeKeyNotification` for its window and log `ARKT: key window <windowNumber>`; also log
`ARKT: window number <n>` once after `showWindow:` (it already logs the number inside the first-responder line; make
it a separate line so scripts can grep it).

**Step 3: CDP helper** (`engine/tools/cdp.mjs`, one reusable tool, no shell wrappers). Usage:
`node cdp.mjs [--port 9333] [--user-gesture] [--navigate] <match> '<expression or url>'`, where `<match>` is a
substring of the target URL or `type:<target type>` (`page`, `service_worker`, `background_page`). It reads
`http://127.0.0.1:<port>/json/list`, picks the first matching target, opens its `webSocketDebuggerUrl` with Node's
global `WebSocket`, sends `Runtime.evaluate` with `{expression, awaitPromise: true, returnByValue: true}` (plus
`userGesture: true` with `--user-gesture`, so the call counts as a user activation: popup blocker, fullscreen,
pickers), prints `JSON.stringify(result.value)`, and exits non-zero with the CDP error text (or the exception
description) on failure. With `--navigate` it sends `Page.navigate {url}` instead: a browser-initiated navigation,
needed for `chrome://crash` (pages and extensions cannot navigate there; `ExtensionTabUtil::IsKillURL` blocks it).
No dependencies.

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
`node $REPO/engine/tools/cdp.mjs manifest.json 'document.visibilityState'` prints `"visible"`,
`node $REPO/engine/tools/cdp.mjs --user-gesture manifest.json 'navigator.userActivation.isActive'` prints `true`
(and `false` without the flag), and `grep -E "ARKT: (key window|window number)" $PROF/w2-w0.log` prints both lines.
Kill `$PID` (Rules). Record the hot-file hunk count of the existing patches (patch budget command) in `$RES`.

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

**Step 4: README section.** Add "Release build (out/Arkt)" to `engine/README.md`: the args above, the build command
(Step 6), the disk and swap checks (Rules, "Internal disk and memory"), and that `out/Arkt` must be re-signed after
every rebuild (W2).

**Step 5: Commit** (before the build starts, so the bundle's overlay commit is known; Step 7 results go into `$RES`
and are committed with W2)

```zsh
git add engine/arkt/branding/BRANDING engine/README.md docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Add Arkt branding and the non-component release build config"
```

**Step 6: Disk, memory and start the build** (background; `out/Arkt` shares no objects with `out/Spike`)

```zsh
df -h $CHROMIUM_ROOT | tail -1    # need >= 40 GB free on the Chromium disk
df -h / | tail -1                 # internal disk: need >= 8 GiB free (swap lives here)
sysctl vm.swapusage
cd $CR && (time nice -n 15 autoninja -C out/Arkt chrome) > $CHROMIUM_ROOT/build-arkt.log 2>&1 &
echo $! > $CHROMIUM_ROOT/build-arkt.pid
```
Expected cost: a full compile of about 75k objects plus one large framework link. The component build on this Mac
(10 cores, 32 GB) ran from about 21:03 to past 01:39 while other builds were busy, and an earlier note records it
slipping to about 11:00 under heavy parallel load. Budget 5-7 h on a quiet machine, up to 14 h under load. Disk:
`out/Spike` is 6.1 GB; expect `out/Arkt` at 10-15 GB.

Hourly check (do not poll faster): `tail -1 $CHROMIUM_ROOT/build-arkt.log`, `df -h / | tail -1` and
`sysctl vm.swapusage`; record each in `$RES`. Abort rule from Rules (below about 4 GiB free on `/`: kill the build by
its PID, record, ask the user). The non-component link of `Arkt Framework` is memory-heavy (several GB, single
process) and can push the machine into swap on the internal disk: once the last log line names the `Arkt Framework`
link step, quiet the machine: no `out/Spike` build, no Swift builds, no other heavy jobs until it finishes.

**Step 7: Verify when it finishes**

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
df -h / | tail -1                                   # need >= 4 GB free after the copy: bundle size (W1 Step 7) + 4 GB
sysctl vm.swapusage
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
the Arkt window to `$PROF/shots/w2-smoke.png`.

Framework entry point and web identity (the release bundle is what sites see; issue "Chrome-compatible user agent
and client hints" owns the product side):

```zsh
nm -gU "/Applications/Arkt.app/Contents/Frameworks/Arkt Framework.framework/Arkt Framework" | grep -c ' T _ChromeMain'
node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgent'
node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.brands.map(b=>b.brand)'
node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.getHighEntropyValues(["fullVersionList"]).then(v=>v.fullVersionList.map(b=>b.brand))'
```
Expected: `1` (the framework exports `ChromeMain`, which the week-3 embedding loads); the UA contains
`Chrome/156.0.0.0 Safari/537.36` (reduced UA, `version_info_with_user_agent.cc:13`) and no `Arkt`; neither brand list
contains `Arkt` (with a custom branding file the build is `CHROMIUM_BRANDING`, so the brands are `Chromium`, a GREASE
brand and no product brand, `user_agent_utils.cc:166`). Never pass `--user-agent` in any launch: it would hide what
the build really sends. Kill `$PID`.

**Step 4: Prepare the 1Password profile on the internal disk.** Copy the week-1 profile (it holds the installed
1Password extension and the native messaging manifest). Size it first: `du -sh $PROF/1password-test` and
`df -h / | tail -1`; copy only if at least that size plus 4 GB stays free on `/`, otherwise record and ask the user.
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

### Task W3: Inventory of non-`BrowserView` window seams and the variant decision (doc only, no build)

Runs while W1 builds. Produces the evidence for the strategy decision (Decision 1), the W5b gate and the patch
projection.

**Files:**
- Modify: `$RES` (section "Seam inventory")

**Steps** (all read-only on `$CR`):

```zsh
cd $CR
X=(-- chrome ':!*test*' ':!chrome/browser/ui/webui_browser/*')
# 1. Direct dereferences of GetBrowserViewForBrowser (crash if the window is not a BrowserView).
git grep -n 'GetBrowserViewForBrowser([^;]*)->' $X
# 2. Assigned-then-used sites: list files, then read each call site and classify null-checked / CHECKed /
#    DCHECKed-then-dereferenced (sad_tab_controller.cc:31-34 is one) / unchecked.
git grep -n 'GetBrowserViewForBrowser' $X | wc -l
# 3. Webium-gated seams: what Webium had to special-case for a non-BrowserView normal window.
git grep -n 'IsWebUIBrowserEnabled()' $X
# 4. Widget lookups on a browser window followed by a dereference (null for variant P).
git grep -n 'GetWidgetForNativeWindow(.*GetNativeWindow' $X
# 5. Static casts of BrowserWindow to BrowserView.
git grep -n 'static_cast<BrowserView\*>' $X
# 6. Window lookups from a WebContents or a native window (callers then expect a BrowserView or a Widget).
git grep -n 'FindBrowserWindowWithWebContents' $X
git grep -n 'GetBrowserViewForNativeWindow' $X
# 7. Top-level widget of a WebContents view (the argument is usually on the next line, so grep with context).
git grep -n -A1 'GetTopLevelWidgetForNativeView' $X | grep 'GetNativeView'
# 8. Every BrowserView / Webium arm in the two hot files: these are features a third window type does not get.
git grep -n -E 'if \(browser_view|browser_view &&|webui_browser_window\)|IsWebUIBrowserEnabled' -- \
  chrome/browser/ui/browser_window/internal/browser_window_features.cc chrome/browser/ui/tabs/tab_features.cc
```

Counts at 156 when this revision was written (record yours; drift is expected after a rebase): (1) 8 hits in 8
files; (2) 166 calls in 119 files; (3) 13 hits in 12 files; (4) 11 hits in 10 files; (5) 1; (6) 11 hits in 8 files
and 30 hits in 16 files; (7) 13; (8) 39 lines: 27 `browser_view` arms, 10 Webium arms and the `IsWebUIBrowserEnabled()` branch at :352 in
`browser_window_features.cc`, and in `tab_features.cc` one Webium-gated arm and no `browser_view` arm
(`SadTabHelper`, :646). An earlier draft of this plan counted 165 calls and 14 Webium-gated files; the numbers above
were re-checked with the exact commands.

Classify each hit into: (a) reached on normal-window startup, tab add/close/activate, extension popup/action,
`chrome.tabs`/`chrome.windows` APIs, Web Store install, keyboard shortcuts, or W5b scenarios 9-17 (must handle in
W5b, or record as a known gap if the feature is only "not shown"); (b) reached only by features Arkt does not use
this week (side panel, tab groups UI, toolbar buttons, HaTS, cast, labs); (c) null-safe already. For category (a),
note whether a single upstream predicate would cover it (for example extending `IsWebUIBrowserEnabled()`-style
branches with an Arkt check) and how many files and hot-file hunks that touches.

**BrowserWindow overrides where Webium returns real objects.** Go through
`chrome/browser/ui/webui_browser/webui_browser_window.h` and list every override that does not return a neutral
value (null, false, empty) in `webui_browser_window.cc`: at least `GetNativeWindow` (:419), `GetLocationBar` (:858,
`WebUIStubLocationBar`), `GetWebContentsModalDialogHost` (:1104) and `GetWebContentsModalDialogHostFor`,
`GetExclusiveAccessContext` (:1138), plus its `ExtensionsContainer`. (`GetStatusBubbles`, :756, returns an empty
vector in Webium; Arkt makes it real anyway, W5a Step 3.) For each, write what `ArktBrowserWindow` returns (W5a
Step 3) and which callers need it.

**Seams for both variants.** For each category (a) hit, mark whether it is a seam under variant P (plain `NSWindow`:
greps 4, 6 and 7 return nullptr) and under variant W (frameless Widget: those find a Widget, but not a `BrowserView`
and not Webium's property). Also check whether a `NativeWidgetMac` subclass can return an existing Arkt `NSWindow`
from `CreateNSWindow` (`ui/views/widget/native_widget_mac.h:261`) without upstream changes. Record per variant:
category (a) files, projected seam patch files (one per theme: browser features init, tab features,
dialogs/anchoring), upstream files, hot-file hunks.

**Decision.** Write the variant choice into `$RES` ("Strategy decision", Decision 1): P unless P's projection exceeds
the W5b gate and W's does not. W5a builds the chosen variant.

**Verification:** `$RES` has the eight command outputs (counts), the overrides table, the classification table with
both variant columns, the per-variant projection and the decision.

**Commit**

```zsh
git add docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Record the browser window seam inventory and the window variant decision"
```

Time-box: 2 h.

---

### Task W4: Extensions menu lists every action (finding 1)

No upstream patch. Works on the week-1 mount path now and on `ArktBrowserWindow` later (W6). Runs in lane B
("Parallel lanes"): either before or after W5a, or alongside W5a with only its new files (`action-probe/`,
`arkt_extensions_menu.{h,mm}`) until W5a has landed, then the `arkt_extensions_bridge`, `BUILD.gn` and
`arkt_browser_main_extra_parts.mm` wiring as one small commit on top.

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

**Step 7: Verify the menu without blocking on it.** An AX `click` on a button that pops up an `NSMenu` does not
return while the menu is open (menu tracking runs a nested event loop in our process), so `osascript` hangs and the
next AX query never runs. Verify the menu contents through a debug switch instead, and keep AX for the button only:

- Add `--arkt-extensions-menu-dump`: after the toolbar model is initialized (and again on every model change), build
  the same `NSMenu` the button would show, without showing it, and log one line per item
  `ARKT: menu item <index> <title> enabled=<0|1>` (plus `ARKT: menu item 0 No extensions enabled=0` when empty).
- Launch as in Step 6 with `--arkt-extensions-menu-dump` added (no `--arkt-extensions-demo`), then:
  `grep "ARKT: menu item" $PROF/w2-w4.log`. Expected: the titles equal the `ARKT action` names, in model order.
- Button wiring (one AX press, run in the background so a hang cannot block the task), after the frontmost and
  key-window checks (Rules):

```zsh
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to click button \"Extensions\" of window 1" & OSA=$!
grep "ARKT: extensions menu" $PROF/w2-w4.log   # after 5 s: "shown <n> items", then "closed"
```
  The menu closes itself: with `--arkt-extensions-menu-dump`, `ArktExtensionsMenu` logs
  `ARKT: extensions menu shown <n> items` when it opens, calls `[menu cancelTracking]` 3 s later and logs
  `ARKT: extensions menu closed`; `<n>` must equal the dump's item count. Then `ps -p $OSA` must
  print no process row (kill `$OSA` by PID if it does). Choosing an item is covered by `--arkt-extensions-demo`
  (Step 6), which runs the same `ExecuteUserAction` path as a menu click.
- If the button is not reachable at that AX path, print the AX tree of window 1 once (`entire contents`) and adapt
  the path; do not fall back to coordinates for menus.

**Step 8: Real extensions.** Repeat Step 6 with `--user-data-dir=$PROF/1password-test` (1Password installed) and
`--load-extension=$REPO/engine/test-extensions/action-probe`: the list must contain 1Password and the probe. Opening
1Password's popup through `--arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa` must log `popup loaded
chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup/index.html`.

**Step 9: Commit**

```zsh
git add engine/test-extensions/action-probe/{manifest.json,popup.html,popup.js,sw.js} engine/test-extensions/tabs-probe/sw.js \
  engine/arkt/browser/{arkt_extensions_menu.h,arkt_extensions_menu.mm,arkt_extensions_bridge.h,arkt_extensions_bridge.mm} \
  engine/arkt/browser/{arkt_browser_main_extra_parts.mm,BUILD.gn} docs/plans/2026-10-23-engine-week2-results.md
git commit -m "List all extension actions in a native menu and open the chosen popup"
```

Time-box: 4 h.

---

### Task W5a: `ArktBrowserWindow` skeleton behind `--arkt-native-window` (factory hook, patch 0003)

**Files:**
- Create: `engine/arkt/browser/arkt_browser_window_factory_hook.{h,cc}` (tiny target, no Chrome UI deps)
- Create: `engine/arkt/browser/arkt_browser_window.{h,mm}` (the window, `ArktWindowHost` protocol,
  `ArktPlaceholderWindowHost`, and the small window-side objects: exclusive access context, modal dialog host,
  stub location bar, status bubble; split into more files only if one grows past a few hundred lines, and then name
  them in the commit)
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
// Deliberately narrower than BrowserWindow::CreateBrowserWindow(browser, user_gesture, in_tab_dragging): an
// Arkt window is never created by a tab drag (there is no Views tab strip to drag from), and user_gesture is
// only consumed on Aura (kCreatedByUserGesture, browser_window_factory.cc:76), never on Mac. The patch passes only
// `browser`.
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

**Step 3: `ArktBrowserWindow`.** `class ArktBrowserWindow : public BrowserWindow`, in the variant chosen after W3
(Decision 1; the steps below describe variant P, plain `NSWindow`; for variant W the window comes from a frameless
`views::Widget` and the same methods apply). Model the method list on
`chrome/browser/ui/webui_browser/webui_browser_window.{h,cc}` (its `BrowserWindow` overrides and its stubs):
- Real this step: `GetNativeWindow` (the host's `NSWindow`, see `ArktWindowHost` below), `Show`, `ShowInactive`,
  `Close` (orderOut, then `BrowserWindowDeleter` contract as Webium does), `Activate`, `Deactivate`, `IsActive`,
  `GetBounds`, `GetRestoredBounds`, `SetBounds`, `IsMaximized`, `IsMinimized`, `IsFullscreen`, `IsVisible`,
  `IsOnCurrentWorkspace`, `IsVisibleOnScreen`, `GetContentsSize`, `GetNativeTheme`, `GetThemeProvider`,
  `GetColorProvider`, `HandleKeyboardEvent` (Cmd-key equivalents to `NSApp.mainMenu`, like `ArktWindow` does today),
  `PreHandleKeyboardEvent` (not handled), `IsToolbarVisible` (true, so `chrome.action.openPopup` is allowed).
- Also real (W3 overrides table; the first three are real in Webium too):
  - `GetExclusiveAccessContext`: an `ArktExclusiveAccessContext` owned by the window, created in the constructor
    (before `BrowserWindowFeatures::Init` builds `ExclusiveAccessManager` from it, `browser_window_features.cc:809`).
    Fullscreen enter/exit calls `-[NSWindow toggleFullScreen:]` on the host window and reports state from
    `NSWindowStyleMaskFullScreen`; the exclusive access bubble is a logged no-op this week.
  - `GetWebContentsModalDialogHost` and `GetWebContentsModalDialogHostFor(web_contents)`: an Arkt
    `web_modal::WebContentsModalDialogHost` over the card view (host view = the card's `NSView`, maximum size = card
    size, position = top centre of the card, observers notified on resize), so tab-modal dialogs (JS alert/confirm,
    install prompt parent) have a host.
  - `GetLocationBar`: our own stub `LocationBar` (log-once methods, neutral values; written for Arkt, modelled on
    what `WebUIStubLocationBar` returns, not copied).
  - `GetStatusBubbles`: Webium returns an empty vector (`webui_browser_window.cc:756`), which callers
    (`browser_ui_controller.cc:86`, `browser_web_contents_delegate.cc:800`) tolerate. Arkt returns one
    `ArktStatusBubble` that records the status and hovered URL and forwards them to the host, so the shell can show
    link targets later; it draws nothing this week.
- Destructor: first `browser_->GetFeatures().TearDownPreBrowserWindowDestruction()` (as Webium does,
  `webui_browser_window.cc:233`), then drop the exclusive access context, the modal host and the tab strip
  observation.
- Every other override: a stub that logs `ARKT: stub <method>` once per method (a function-local static set), and
  returns the neutral value Webium returns. Do not copy Webium code verbatim beyond method signatures; read it for
  what each method must return to be safe.
- **Embedder seam: `ArktWindowHost`** (ObjC protocol in `arkt_browser_window.h`): `- (NSWindow*)window` and
  `- (NSView*)cardView` (the view tab content is mounted in), plus `- (void)tabListChanged:(NSArray*)events` for the
  tab events below. `ArktBrowserWindow` never creates or lays out the window itself; it asks its host. This week's
  implementation is `ArktPlaceholderWindowHost`: an `ArktWindowController`-style `NSWindow` (reuse `ArktWindow` and
  the layout: 190 pt sidebar placeholder with the Extensions button, inset rounded card). In week 3 ShellUI is a
  second implementation that hands over its own borderless window and card ("Week-3 entry").
- **Tab events are separate from any engine-side table.** `ArktBrowserWindow` implements
  `TabStripModelObserver::OnTabStripModelChanged` and turns each change into plain events (inserted, removed,
  moved, selection changed, with tab ids and indices) that it hands to the host. The engine-side `NSTableView`
  (W5c) is only one consumer of those events inside the placeholder host; nothing in the observer knows about it.
- Content mounting is minimal in this step: on a selection change, put the active tab's
  `WebContents::GetNativeView()` NSView in the host's card view (W5c replaces this with the real tab list). No
  `ViewsHostableDetach()` is needed: these views were never Views-hosted. Log `ARKT: native window mounted tab <tab
  id>`.

**Step 4: Register.** In `ArktBrowserMainExtraParts::PreProfileInit()` (`chrome_browser_main_extra_parts.h:40`):
if the command line has `arkt-native-window`, call `SetCreateBrowserWindowOverride` with a function that returns
`new ArktBrowserWindow(browser, [ArktPlaceholderWindowHost new])` for `TYPE_NORMAL` and nullptr otherwise. In
`PostBrowserStart`, skip `MountActiveTab` when the switch is present, and log a census on every browser add and
remove: `ARKT: browsers normal=<n> arkt=<n> views=<n>` (iterate `GlobalBrowserCollection`). Chromium is built
without RTTI, so `dynamic_cast` is not available: a browser is `arkt` if `ArktBrowserWindow::FromBrowser(b)` is
non-null, which looks `b->GetWindow()` up in a live-instance set (`base::flat_set<ArktBrowserWindow*>` of
constructed, not yet destroyed windows; variant W uses the Widget's native-window property
`kArktBrowserWindowKey` instead, as `BrowserView` and Webium do).

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
git add engine/arkt/browser/{arkt_browser_window_factory_hook.h,arkt_browser_window_factory_hook.cc} \
  engine/arkt/browser/{arkt_browser_window.h,arkt_browser_window.mm,BUILD.gn} \
  engine/arkt/browser/{arkt_browser_main_extra_parts.h,arkt_browser_main_extra_parts.mm} \
  engine/patches/chromium/.patches engine/patches/chromium/0003-*.patch docs/plans/2026-10-23-engine-week2-results.md
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
`--remote-debugging-port=9333`, start page `https://example.com`), driving it with launch switches and CDP only
(scenario 13 uses one AX menu press). Before the first launch, point downloads into the test area: with the profile
not running, set `download.default_directory` to `$PROF/downloads` and `download.prompt_for_download` to `false` in
`$PROF/week2-native/Default/Preferences` (a `node -e` one-liner that reads, edits and writes the JSON), so scenario
14 never writes to the user's Downloads folder.

| # | Scenario | Driver |
|---|---|---|
| 1 | Startup, idle 30 s | launch |
| 2 | Navigate the tab | `cdp.mjs example.com 'location.href="https://example.org"'` |
| 3 | Extension adds a background tab | `cdp.mjs $PROBE_SW 'probe.create()'` |
| 4 | Extension opens a popup | `--arkt-extensions-demo=<action-probe id>` (a "no container" style failure here is ordering: W6 registers `ExtensionsContainer`; not a seam) |
| 5 | `chrome.windows.create` | `cdp.mjs $PROBE_SW 'probe.window()'` |
| 6 | Close a tab | `cdp.mjs $PROBE_SW 'chrome.tabs.query({}).then(t=>chrome.tabs.remove(t.at(-1).id))'` |
| 7 | Close every window, then quit | `cdp.mjs $PROBE_SW 'chrome.windows.getAll().then(w=>Promise.all(w.map(x=>chrome.windows.remove(x.id))))'`, then `kill -TERM $PID` |
| 8 | Page `window.open` (no features) | `cdp.mjs --user-gesture example.com 'window.open("about:blank#page-open") !== null'` |
| 9 | Renderer crash (sad tab) | `cdp.mjs --navigate example.com 'chrome://crash'` |
| 10 | `alert` and `confirm` | `cdp.mjs example.com 'setTimeout(()=>alert("arkt"),0); 1'`; then, in a second fresh launch, the same with `confirm("arkt")` |
| 11 | Permission prompt | `cdp.mjs --user-gesture example.com 'Notification.requestPermission(); 1'` |
| 12 | `requestFullscreen` with a gesture | `cdp.mjs --user-gesture example.com 'document.documentElement.requestFullscreen().then(()=>"ok",e=>e.name)'`, then `cdp.mjs example.com 'document.exitFullscreen().then(()=>"ok",e=>e.name)'` |
| 13 | Find (Cmd-F) | after the frontmost and key-window checks: AX `click menu item "Find..." of menu 1 of menu item "Find" of menu "Edit" of menu bar 1` (adapt the path once from the menu bar's AX tree; the title may use the ellipsis character) |
| 14 | A download | `cdp.mjs --user-gesture example.com 'const a=document.createElement("a");a.href=URL.createObjectURL(new Blob(["arkt"]));a.download="arkt-w5b.txt";document.body.append(a);a.click();1'` |
| 15 | `<input type=file>` | `cdp.mjs --user-gesture example.com 'const i=document.createElement("input");i.type="file";document.body.append(i);i.click();1'` |
| 16 | Docked DevTools | launch with `--auto-open-devtools-for-tabs` |
| 17 | Autofill / `<datalist>` dropdown | `cdp.mjs --user-gesture example.com 'document.body.innerHTML="<input id=i list=d><datalist id=d><option value=arkt1><option value=arkt2></datalist>";i.focus();i.showPicker();1'` |

Pass for each: process alive 10 s after the driver, no `FATAL`/`CHECK failed` in the log, no new crash dump.
Crash reports are always stored under the default user data directory, not `--user-data-dir`
(`chrome/common/chrome_paths.cc:216-221`), which for these builds is still `Chromium`: compare
`find "$HOME/Library/Application Support/Chromium/Crashpad" -type f 2>/dev/null | wc -l` before and after and record
the counts. Count only: never open, move or delete anything in that directory (it may belong to another
Chromium-based app). Scenario 8
additionally prints `true` and the new tab lands in the Arkt window (census `views=0`); without `--user-gesture` the
popup blocker would block it and the scenario would test nothing. Scenario 7 does not end in an exit: on macOS the
browser keeps running with no windows, so after the `windows.remove` call assert the census
`ARKT: browsers normal=0 arkt=0 views=0` and `ps -p $PID` still shows the process; then `kill -TERM $PID`, and within
10 s the process is gone (`ps -p $PID` prints no process row), the log has no `FATAL`/`CHECK failed`, and no new
crash dump exists.

Scenarios 9-17 exercise features whose window-side objects `ArktBrowserWindow` does not have this week (Decision
1: no find bar owner, zoom bubble, fullscreen control host, DevTools UI controller, color provider helper, download
toolbar controller; anchored bubbles need a location bar or toolbar). For them, pass is "no crash"; whether the UI
was shown (sad tab page, dialog, permission bubble, fullscreen state, find bar, download in `$PROF/downloads` and a
download bubble, open panel, docked or undocked DevTools, dropdown) is recorded per scenario in `$RES` as `shown` or
`not shown`, and every `not shown` is listed as a known gap for week 3, not fixed here. Scenario 9 is an expected
seam: `SadTabController` dereferences `GetBrowserViewForBrowser` behind a `DCHECK` (`sad_tab_controller.cc:31-34`).
Scenario 15 leaves an open panel in our process; do not interact with it, kill `$PID` after recording.

For a crash, the stack trace in the log (symbol-table names; `symbol_level=0` gives no line numbers) names the
seam. If the trace is not enough, run once under `lldb` and use `bt`.

**Step 2: Fix order.** For each crash: (1) can `ArktBrowserWindow` return something that makes the caller safe (a
non-null object, a stub `LocationBar`/`StatusBubble` as Webium uses `WebUIStubLocationBar`)? Do that, no patch. (2)
Otherwise patch the caller to tolerate a non-`BrowserView` window, using the predicate the caller already uses for
Webium where one exists. Group fixes into one upstream commit per theme (`Arkt: tolerate a non-BrowserView window
in browser features`, `... in tab features`, `... in dialogs`), Export after each. Prefer fixes outside the hot files;
an Arkt arm in `browser_window_features.cc` counts against the hot-file hunk limit (Step 3).

**Step 3: GATE.** Measure after every theme commit, then decide. The gate trips if any of these holds for the seam
patches (W5b, plus any W7 adds): more than 8 seam patch files; more than 25 upstream files touched
(`git -C $CR diff --stat 156.0.8078.48..arkt | tail -1`, minus the files of patches 0001-0003 and the keychain
patch); more than 6 hunks in the hot files (patch budget command; one hunk in either file is one rebase conflict
waiting to happen); or a seam needs a change to a widely included header. Patch-file count alone is not the gate:
one theme patch that edits 15 files or adds 6 arms to `browser_window_features.cc` is worse than three small ones.
When it trips:
- If the current variant is P (plain `NSWindow`) and W3 projected variant W inside the gate: switch to W once
  (frameless `views::Widget`-backed `ArktBrowserWindow`, Decision 1), re-run the matrix, and record both measurements.
  That is still `ArktBrowserWindow`; it is not the hidden-`BrowserView` option.
- Otherwise stop W5c-W7 and write a decision note in `$RES`: the remaining crashes, the measurements, and the
  cheapest way forward (open question 4).

**Verification:** all 17 scenarios pass (scenarios 9-17: no crash, shown/not shown recorded); `$RES` lists every seam
(file, symptom, fix: our side or patch N), the known gaps, and the updated patch budget table with upstream files and
hot-file hunks.

**Commit:** one commit per theme, each with its exported patch file and `.patches` (`git add
engine/patches/chromium/.patches engine/patches/chromium/00NN-*.patch`), the overlay files it changed, named one by
one, plus `$RES`. Message per theme, e.g. `Tolerate a non-BrowserView normal window in browser features`.

Time-box: 1.5 days. If not done by then, the gate note is mandatory.

---

### Task W5c: Arkt-owned tab list and visibility (finding 2)

**Files:**
- Create: `engine/arkt/browser/arkt_tab_list_view.{h,mm}` (placeholder tab list in the sidebar, AppKit)
- Modify: `engine/arkt/browser/arkt_browser_window.{h,mm}`

**Step 1: Tab list.** `ArktBrowserWindow`'s `TabStripModelObserver::OnTabStripModelChanged`
(`tab_strip_model_observer.h:521`, W5a Step 3) keeps an ordered list of tab entries (`tabs::TabHandle` or the tab's
`SessionID` from `sessions::SessionTabHelper::IdForTab`, title, URL) and emits tab events to its `ArktWindowHost`.
The placeholder host turns those events into an `NSTableView` in its sidebar (one row per tab, title text; this is
an engine test surface, not the real ShellKit sidebar). The table is a consumer of the events, never their source:
the observer and the event list do not reference it, so the ShellUI host can replace it without engine changes.
Clicking a row asks the window to activate that tab, which calls `TabStripModel::ActivateTabAt(index)`.

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
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'chrome.tabs.query({}).then(t=>chrome.tabs.update(t.find(x=>x.url.startsWith("about:blank")).id,{active:true}))'
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState'          # now "hidden"
node $REPO/engine/tools/cdp.mjs $PROBE_SW 'chrome.tabs.query({}).then(t=>chrome.tabs.update(t.find(x=>x.url.startsWith("https://example.com/")).id,{active:true}))'
node $REPO/engine/tools/cdp.mjs example.com 'document.visibilityState'          # "visible" again
```
`about:` is not a valid scheme in an extension match pattern (`extensions/common/url_pattern.cc:34`, `kValidSchemes`),
so `tabs.query({url: "about:blank"})` fails; the commands query all tabs and filter in JS, and do the same for
https for consistency. Expected exactly as commented, with matching `ARKT: visibility` log lines, and the table shows 2 rows. This is the
week-1 reproduction (opening any tab blacked out our card) turned into a passing check. Then the input check: after the
frontmost/key checks, AXPress row 2 of the table (`select row 2 of table 1 of scroll area 1 of window 1`, adapt the AX
path once) and confirm with CDP that the about:blank tab is `visible` and example.com is `hidden`. Window-only
screenshot after each switch.

**Step 4: Commit**

```zsh
git add engine/arkt/browser/{arkt_tab_list_view.h,arkt_tab_list_view.mm,arkt_browser_window.h,arkt_browser_window.mm,BUILD.gn} \
  docs/plans/2026-10-23-engine-week2-results.md
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
| popup button `open` (`window.open` from the popup, via `cdp.mjs --user-gesture popup.html 'document.getElementById("open").click()'`; without the gesture the popup blocker stops it) | new row in our window, census `views=0`, the popover may close (record it) |
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
git add engine/arkt/browser/{arkt_extensions_container.h,arkt_extensions_container.mm,arkt_browser_window.h,arkt_browser_window.mm} \
  engine/arkt/browser/{arkt_extensions_menu.mm,BUILD.gn} engine/test-extensions/tabs-probe/sw.js \
  docs/plans/2026-10-23-engine-week2-results.md
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
   Lite Web Store detail page URL. Reject the Google consent interstitial over CDP and press "Add to Chrome" with
   `cdp.mjs --user-gesture` (`userGesture: true`), as week-1 Task 6 did.
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
git add docs/plans/2026-10-23-engine-week2-results.md   # plus each overlay file a fix changed, named one by one
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
git add engine/patches/chromium/.patches engine/patches/chromium/00NN-Arkt-use-the-Arkt-Safe-Storage-keychain-item.patch \
  engine/README.md docs/plans/2026-10-23-engine-week2-results.md   # NN: the number Export assigned
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
git status --short engine/patches/chromium   # if 0002 was dropped: D lines (old names) and ?? lines (renumbered)
git rm --cached -q <each D path, by name>; git add <each ?? path, by name>
git add engine/arkt/browser/arkt_browser_main_extra_parts.mm engine/patches/chromium/.patches \
  docs/plans/2026-10-23-engine-week2-results.md
git commit -m "Use ArktBrowserWindow for normal windows by default"
```

Time-box: 4 h (two incremental builds).

---

### Task W10: Rebuild the release bundle with week-2 changes, re-sign, final smoke, housekeeping

**Files:**
- Modify: `$RES` (final table, open items)

**Steps:**
1. Disk and memory first (Rules, "Internal disk and memory"): `df -h / | tail -1` at least 8 GiB free,
   `sysctl vm.swapusage` recorded; same checks hourly while it builds, abort below about 4 GiB, quiet the machine
   during the `Arkt Framework` link. Incremental `out/Arkt` build (`nice -n 15 autoninja -C out/Arkt chrome`,
   background). Re-sign with W2 Step 1. Replace the installed copy: `rm -rf /Applications/Arkt.app && ditto $REL/Arkt.app /Applications/Arkt.app` (only the
   bundle W2 installed; check `codesign -dv /Applications/Arkt.app 2>&1 | grep Identifier=com.arkt.Arkt` first).
2. Smoke from `/Applications` with `$IPROF/smoke`: page renders, census `views=0`, `probe.create()` adds a row, the
   Extensions menu lists the loaded probes (`--arkt-extensions-menu-dump`), keychain strings check from W8 Step 3 on
   `Arkt Framework` (non-component: the constant is inside the framework binary), and the W2 Step 3 identity checks
   on the rebuilt bundle: `nm -gU "/Applications/Arkt.app/Contents/Frameworks/Arkt Framework.framework/Arkt Framework" | grep -c ' T _ChromeMain'`
   prints `1`; over `cdp.mjs`, `navigator.userAgent` contains `Chrome/156.0.0.0 Safari/537.36`, and neither
   `navigator.userAgentData.brands` nor `getHighEntropyValues(['fullVersionList'])` contains a brand named `Arkt`.
   No `--user-agent` switch in the launch.
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

## Parallel lanes

| Lane | Sequence | Builds |
|---|---|---|
| Background | W1's `out/Arkt` build starts right after W0 and runs for hours; W2 and W10 consume it | `out/Arkt`, `nice -n 15` |
| A (native window) | W0 -> W3 -> strategy decision (Decision 1) -> W5a -> W5b (gate) -> W5c -> W6 -> W7 -> W9 -> W10 | `out/Spike` |
| B (independent engine work) | W4 -> W8 -> W2 (W2 once W1's build has finished) | `out/Spike`, then signing |
| C (embedding) | Task WE, embedding spike ("Week-3 entry"), any time after W0 | none (Swift app build only) |

Rules for running lanes at the same time:
- One `out/Spike` build at a time across lanes A and B; either may overlap the background `out/Arkt` build except
  during its framework link (Rules, "Capacity"). Lane C's Swift build counts against the two-Swift-builds limit.
- Lanes A and B share `$REPO` (the `$CR/arkt` symlink can point at only one overlay) and the Chromium branch `arkt`:
  file-level pathspec commits keep each lane's commits to its own files, and patch exports (`git am`/Export on
  `$CR`) are serialized: announce, export, commit, then the other lane may export.
- W4 and W5a both touch `arkt_browser_main_extra_parts.mm` and `engine/arkt/browser/BUILD.gn`. Either run them in
  sequence, or while W5a is open W4 only adds new files (`engine/test-extensions/action-probe/*`,
  `arkt_extensions_menu.{h,mm}`) and lands its wiring (`BUILD.gn` source list, one call in
  `arkt_browser_main_extra_parts.mm`, the bridge change) as one small commit after W5a's commit.
- Lane C works in its own worktree (`arkt-wt/embed-spike`, branch `spike/embedding`) and changes only `app/`; it
  never repoints `$CR/arkt` and never builds Chromium.
- W10 starts only when lanes A and B are done.

## Week-3 entry: embedding and ChromiumEngine

Week 2 proves the engine side inside a GN-built `Arkt.app`. Week 3 moves the engine into the shipping app: the Swift
`ArktShell` bundle loads the Chromium framework and the UI talks to it through ShellKit's `EngineClient`. This
section fixes the facts week 3 starts from; Task WE de-risks the first of them during week 2.

**Framework layout.** Chromium's own app is a stub: `chrome_exe_main_mac.cc` builds the path
`../Frameworks/<PRODUCT_FULLNAME> Framework.framework/Versions/<version>/<PRODUCT_FULLNAME> Framework` (:186-192),
`dlopen`s it with `RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST` (:211) and calls the exported `ChromeMain(argc, argv)`
(:184, :216-218). The framework finds itself from the main executable: `GetFrameworkBundlePath`
(`chrome/common/chrome_paths_mac.mm:133-177`) goes from `FILE_EXE` up to `Contents`, then down to
`Frameworks/<kFrameworkName>/Versions/<kChromeVersion>`, and `DCHECK`s every component, including that the
outermost directory ends in `.app`. `kFrameworkName` (`chrome_constants.cc:83`) and the framework target name
(`chrome_framework_name = chrome_product_full_name + " Framework"`, `chrome/BUILD.gn:489`) both come from
`PRODUCT_FULLNAME`, so with W1's branding file the framework is `Arkt Framework.framework`. The Swift app therefore
ships `Contents/Frameworks/<that name>.framework` with its `Versions/<version>/{Helpers,Libraries,Resources}` intact,
and its main executable sits in `Contents/MacOS` like Chromium's stub.

**Framework name.** The design doc calls the engine `ArktCore.framework`, which clashes with the `app/ArktCore`
SwiftPM package (model, import, persistence). Pick a distinct name, for example "Arkt Engine" (`Arkt
Engine.framework`) or `ArktEngine.framework`. Getting there from `PRODUCT_FULLNAME=Arkt` needs either a different
`PRODUCT_FULLNAME` (which also renames the GN app and helpers) or one patch to `chrome/BUILD.gn:489` and
`chrome_constants.cc:83` (open question 5).

**`ChromeMain` handoff.** Today `app/ArktShell/App/main.swift` creates `NSApplication.shared` and runs it, and
`project.yml` sets `NSPrincipalClass: NSApplication`. Chromium needs its own application class: it calls
`[BrowserCrApplication sharedApplication]` and `CHECK`s `[NSApp isKindOfClass:[BrowserCrApplication class]]`
(`chrome/browser/chrome_browser_application_mac.mm:40-45`; Chromium's `app-Info.plist:220-221` sets
`NSPrincipalClass` to `BrowserCrApplication`). So in the engine build, `main.swift` must not touch `NSApplication`
at all: its first statement loads the framework and calls `ChromeMain(argc, argv)`, which owns the run loop and
does not return until quit. Arkt's Swift UI is started from inside the browser process (the in-process hook,
`ArktBrowserMainExtraParts`), not from `main.swift`. The engine build's Info.plist sets `NSPrincipalClass` to
`BrowserCrApplication`; the FakeEngine dev build keeps today's `main.swift` and plist.

**Main menu.** Chromium builds its main menu itself (`chrome::BuildMainMenu(NSApp, app_controller, ...)` in
`chrome_browser_main_mac.mm:162`, `chrome/browser/ui/cocoa/main_menu_builder.mm`) and routes menu commands through
`AppController` to the last active `Browser`. `app/ArktShell/App/MainMenu.swift` is the shell's menu. Week 3
decides one owner: either Arkt replaces the menu after startup and routes every command itself, or it keeps
Chromium's menu and edits items. Inventory first: for each Chromium menu command (new tab, new window, close tab,
reopen closed tab, find, zoom, print, developer tools, history, downloads, extensions), record whether it reaches
the Arkt `Browser` (it does when `AppController`'s last active browser is the one whose `ArktBrowserWindow` owns the
key window) and what Arc does for the same shortcut (`docs/spec`).

**`EngineClient` additions** (`app/ArktShell/ShellKit/Sources/EngineAPI/EngineClient.swift`; the protocol today has
tabs only):
- windows: an engine window per Arkt window and profile (Decision 4), tabs created in a given window, a tab's window;
- activation: `activateTab(_:)` and the active tab per window;
- an `activeTabChanged(window, TabID)` event for engine-initiated activation (`tabs.update({active: true})`,
  `tabs.create({active: true})`), plus tab-created events that carry window, opener and whether it is active, so
  extension- and page-created tabs land as Today tabs;
- extension surfaces: the action list and its updates (W4), popup presentation anchored to a shell view, and
  extension-created windows (W6).

**Facade and engine.** An ObjC++ facade in `//arkt` exposes `ArktBrowser` (a `Browser` plus its
`ArktBrowserWindow`: tabs, create, close, activate, observe) and `ArktWebContents` (url, title, favicon, loading
through a `WebContentsObserver`; the container view), with no C++ types in its headers. A Swift `ChromiumEngine:
EngineClient` in ShellKit wraps the facade and passes the shared `EngineContract` tests. The ShellUI window is a
second `ArktWindowHost` implementation (W5a Step 3), handing the engine its own borderless window and card.

**Stable container view per tab.** `contentView(for:)` must return the same `NSView` for the tab's whole life
(`EngineClient.swift`), but the `TabStripModel` can replace a tab's `WebContents` (discard and reload, prerender
activation: `TabStripModelChange::kReplaced`). The facade gives each tab an Arkt-owned container `NSView` and
re-parents the current `WebContents` native view into it on every replacement; the shell only ever sees the
container.

**Infobars.** Chromium's infobars are drawn by `BrowserView`'s infobar container; `ArktBrowserWindow` has none, so
infobars (for example crash restore and unsupported command-line flag warnings) are not shown. Week 3 draws
them natively from each tab's `infobars::ContentInfoBarManager`.

### Task WE: Embedding spike (lane C; any time after W0)

Goal: prove that the Swift `ArktShell` app can load the existing `out/Spike` framework and hand control to
`ChromeMain`, with Arkt's in-process hook reporting in. No Chromium build; one Swift build.

**Files** (worktree `arkt-wt/embed-spike`, branch `spike/embedding`; not merged this week):
- Create: `app/ArktShell/App/ChromiumSpikeMain.swift` (compiled only when the `ARKT_CHROMIUM_SPIKE` Swift flag is set)
- Modify: `app/ArktShell/App/main.swift` (under `#if ARKT_CHROMIUM_SPIKE`, call the spike entry point first and
  nothing else), `app/ArktShell/project.yml` (a `Spike` configuration with the flag, `NSPrincipalClass` set to
  `BrowserCrApplication`, hardened runtime off)
- Create: `docs/plans/2026-10-23-embedding-spike-results.md`

**Step 1: Preconditions.**
```zsh
FW="$OUT/Chromium.app/Contents/Frameworks/Chromium Framework.framework"
nm -gU "$FW/Chromium Framework" | grep -c ' T _ChromeMain'      # expect 1
ls "$FW/Versions"                                                # expect 156.0.8078.48 and Current
otool -l "$FW/Chromium Framework" | grep -A2 LC_RPATH            # where the component dylibs are looked up
```
`out/Spike` is a component build, so its framework is named `Chromium Framework` (that is the `kFrameworkName`
compiled into it) and links hundreds of `@rpath` dylibs. Record the `LC_RPATH` entries.

**Step 2: Entry point.** `ChromiumSpikeMain.swift`: build the framework path from `Bundle.main.privateFrameworksPath`
(`Chromium Framework.framework/Versions/156.0.8078.48/Chromium Framework`), `dlopen` it with
`RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST`, `dlsym` `ChromeMain`, and call it with `CommandLine.argc` and
`CommandLine.unsafeArgv`; print `dlerror()` and exit 1 on failure. `main.swift` calls this before anything else and
never touches `NSApplication.shared` in the spike configuration.

**Step 3: Bundle.** Build the `Spike` configuration (`xcodebuild ... -configuration Spike`, `nice -n 20` while a
Chromium build runs), then create `ArktShell.app/Contents/Frameworks/Chromium Framework.framework` as a symlink to
`$FW`. Run `DYLD_PRINT_RPATHS=1` on the first launch (Step 4) to see whether the component dylibs resolve through the
symlink; if they do not, record the failing path and try once with a copy of the framework directory instead of the
symlink (`du -sh "$FW"` and the disk floor first).

**Step 4: Launch.**
```zsh
APP=<built ArktShell.app>
"$APP/Contents/MacOS/ArktShell" --user-data-dir=$PROF/embed-spike --use-mock-keychain --no-first-run \
  --no-default-browser-check --enable-logging=stderr https://example.com > $PROF/w2-we.log 2>&1 & PID=$!
```
Expected within 30 s: `ARKT: in-process hook alive` in the log, the process alive (`ps -p $PID`). Record what else
happens (which window appears, any `DCHECK` from `chrome_paths_mac.mm`, helper launch errors, code-signing or
library-validation refusals) in the spike results file. Kill `$PID`; check for leftovers as in Rules.

**Verification:** the hook line is present, or the results file names the first blocking error with its log lines.
Commit the spike files and the results file on `spike/embedding` (file-level pathspecs).

Time-box: 3 h.

## Out of scope (next weeks)

- Native extension install sheet via `ExtensionInstallPrompt`'s `ShowDialogCallback`; extension context menus;
  action pinning and order; keyboard commands for actions (no `ExtensionKeybindingRegistryViews` without a focus
  manager, Decision 1).
- `TYPE_POPUP`, app, DevTools and picture-in-picture windows as Arkt windows; Little Arkt and Peek windows.
- Replacing other Views bubbles and window features recorded as "not shown" in W5b (sad tab, JS dialogs if not
  shown, permission prompts, page info, find bar, zoom bubble, downloads, file chooser, docked DevTools, autofill
  dropdowns).
- The real ObjC/Swift engine API (`ArktBrowser`, `ArktWebContents`), `ChromiumEngine` and the embedding in the Swift
  app: see "Week-3 entry" (Task WE is the only part done this week).
- Framework rename (open question 5), icons and UI strings, notarization, default user-data-dir name
  (`chrome_paths_mac.mm` still says "Chromium"; every launch passes `--user-data-dir` until then).

## Open questions (product decisions)

1. Bundle id for the product. `com.arkt.Arkt` is a placeholder for the GN-built test bundle, whose trust grants are
   throwaway. The id that matters is the shipping Swift app's ("Week-3 entry"); it must be settled before the first
   build a user relies on: changing it later resets TCC grants, the keychain item's ACL owner and 1Password's
   browser trust.
2. Where `window.open` popups with features and `chrome.windows.create({type:'popup'})` should go (Little Arkt-style
   floating window, Peek, or a normal Arkt window). Until decided they stay Chromium Views popup windows.
3. The existing "Chromium Safe Storage" item in the login keychain: keep or delete (user decides, W8).
4. If W5b's gate trips in both variants (plain `NSWindow` and frameless `views::Widget`): spend more of the patch
   budget on seams, or accept a Views-owned `NSWindow` for the browser window and host ShellUI inside it (Decision 1,
   window ownership).
5. Engine framework name: "Arkt Engine" / `ArktEngine.framework` (or another name distinct from the `app/ArktCore`
   package), and whether to get there with `PRODUCT_FULLNAME` or one build patch ("Week-3 entry").
6. Brand list for site compatibility: with a custom branding file the build sends `Chromium` and a GREASE brand,
   no product brand (`user_agent_utils.cc:166`). Google Chrome sends a "Google Chrome" brand; sending it for parity
   would take one patch. Decide whether parity is worth it (see the issue "Chrome-compatible user agent and client
   hints").
