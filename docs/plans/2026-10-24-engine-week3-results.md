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
| W3-4 | Host mode for ShellUI windows | DONE | embedder hosts own Arkt windows, `createBrowserWithHost:`, request kinds from the call site, self-test embedder; all acceptance rows pass on `Chromium.app`; see "W3-4" below |
| W3-5 | Tab facade | DONE (W3-5a #256, W3-5b) | W3-5a: pending-handle queue, close modes and reasons, CloseCancelled, stable containers, state events, held-window state. W3-5b: history and duplicate, extension actions for embedder windows, the test API; page context menu still blocked. See "W3-5a" and "W3-5b" below |
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
| - | Web identity (#9): stock reduced UA, `Chromium` + GREASE brands | upstream default, no patch, no overlay code | 0 | 0 |

Current (W3-0): 7 patch files, 17 upstream files, 0 hot-file hunks. Projection after week 3: the same, or 8 patch files
if the framework is renamed by patch.

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
  `client`; nil for a closed, pending or non-duplicable tab. Inside a nested loop it is deferred like `createTab`
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

Decision 12 gaps (W3-5a, plus follow-up (a) above); tab-modal dialog positioning on the container; audible state (no
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
