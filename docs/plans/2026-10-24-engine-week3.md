# Engine Week 3 Implementation Plan: ChromiumEngine

> Implement this plan task-by-task, with a review checkpoint after each task. Issue: #33.

**Goal:** The shipping Swift app runs on the real engine. `ArktShell.app` (a new `Engine` build configuration) loads
the Chromium framework, hands the process to `ChromeMain`, and the existing ShellUI talks to Chromium only through
ShellKit's `EngineClient`, implemented by a Swift `ChromiumEngine` over an ObjC facade in `//arkt`. ShellUI's own
borderless window and card host the engine's tabs (it becomes the second `ArktWindowHost`), extension-created tabs
land as Today tabs, and `ChromiumEngine` passes the shared `EngineContract`. The FakeEngine dev build is unchanged.

**Architecture:** One process model, three layers, two lanes.

- *Process.* `main.swift` (Engine configuration) does nothing but load `Arkt Framework.framework` (or `Chromium
  Framework` from `out/Spike` in development), keep the Swift embedder class alive and call `ChromeMain`, which creates
  `BrowserCrApplication`, owns the run loop and never returns. Chromium's `AppController` is the application
  delegate. Arkt's Swift UI is started by the in-process hook (`ArktBrowserMainExtraParts::PostBrowserStart`), not by
  `AppDelegate`. That hook runs inside `ChromeBrowserMainParts::PreMainMessageLoopRunImpl`
  (`chrome_browser_main.cc:2167`): after the initial profile has loaded and `browser_creator_->Start` has run, but
  before `[NSApp run]`, so before `-applicationDidFinishLaunching:` (`app_controller_mac.mm:1293`).
- *Engine side (ObjC++, `//arkt`).* `ArktBrowserWindow` (week 2) keeps one `Browser` per Arkt window and profile. A new
  facade exposes windows, tabs, navigation, per-tab state and extension actions through ObjC **protocols only**,
  declared in one header with no C++, no Chromium includes and no ObjC classes (Decision 1).
- *Swift side.* `ChromiumEngineKit` (a ShellKit target) implements `EngineClient` (and the week-3 additions) over those
  protocols. ShellUI never sees the header: it only knows `EngineAPI`. The app's composition root picks FakeEngine or
  ChromiumEngine.

**How `EngineClient` maps to Chromium** (facade on the UI thread; every name is checked against 156 in the task that
uses it, week-2 "Symbols" rule):

| `EngineClient` | Chromium | Event source |
|---|---|---|
| `createTab(url:in:)` | `chrome::AddTabAt(browser, url, -1, active)` (no URL: `about:blank`), returns the new tab handle at once | `.tabCreated` emitted by `ChromiumEngine` (Decision 4) |
| `closeTab(_:mode:)` | `TabStripModel::CloseWebContentsAt(index, CLOSE_USER_GESTURE)`; for `.skipUnloadHandlers` a close that does not dispatch `beforeunload` (the 156 call is chosen and verified in W3-5, Decision 11); result `closed` or `held` | `.tabClosed(reason: .client)` from `ChromiumEngine` (closed) or from the facade's removal event (held, then closed) |
| `navigate` | `NavigationController::LoadURLWithParams` (transition `PAGE_TRANSITION_TYPED`) | `.urlChanged` with the pending URL from `DidStartNavigation` (`GetVisibleURL`), then `.loadingChanged(true)` from `DidStartLoading` (rule 2 order) |
| `reload` | `NavigationController::Reload(ReloadType::NORMAL, true)` | `DidStartLoading` / `DidStopLoading` |
| `goBack`, `goForward` | `GoBack` / `GoForward`, guarded by `CanGoBack` / `CanGoForward` (rule 7 no-op) | `.urlChanged` from `DidStartNavigation` |
| `history(of:)`, `goToHistory(_:offset:)`, `duplicateTab(_:)` (#81, pull request #238; rules 9 and 10) | the tab handle's `backEntries` / `forwardEntries` (nearest first) from `NavigationController` entries, `GoToOffset` guarded by `CanGoToOffset`, `chrome::DuplicateTabAt` | `.urlChanged` from `DidStartNavigation`; the duplicate as `.tabCreated` (`origin == .client`) |
| `activateTab` | `TabStripModel::ActivateTabAt(index)` | `.activeTabChanged` from `OnTabStripModelChanged` selection |
| `snapshot(of:)` | Swift table fed by: `GetVisibleURL`, `GetTitle`, `IsLoading`, `CanGoBack` / `CanGoForward`, favicon PNG | `TitleWasSet`, `DidStopLoading`, `NavigationEntryCommitted` / `NavigationListPruned` (`.historyChanged`), `FaviconDriverObserver::OnFaviconUpdated` (`.faviconChanged`), cleared on `DidFinishNavigation` committed to another host |
| `contentView(for:)` | the handle's container `NSView` around `WebContents::GetNativeView()` | swapped on `TabStripModelChange::kReplaced` |
| `createWindow(host:)` | `Browser::Create(Browser::CreateParams(profile, true))` with the host chosen first; synchronous (the initial profile is loaded before the hook runs) | `.windowOpened` posted after construction |
| engine-created tabs and closes | `TabStripModelObserver::OnTabStripModelChanged` (`kInserted`, `kRemoved`), opener from `TabInterface` / `WebContents::GetOpener`, close reason from the facade's bookkeeping (Decision 12) | `.tabCreated` (`origin == .engine`), `.tabClosed(reason:)` |
| `extensionActions(in:)`, `runExtensionAction` | `ToolbarActionsModel`, `ExtensionActionViewModel::ExecuteUserAction` (week-2 W4) | `.extensionActionsChanged` |

**Tech Stack:** Chromium 156.0.8078.48 (GN + Siso, `out/Spike` component build), ObjC++ in `//arkt`, Swift 6 (strict
concurrency) in ShellKit and the app, XcodeGen, `xcodebuild`, Node 26 (`engine/tools/cdp.mjs`), `codesign` (ad hoc).

---

## Rules (read before every task)

The week-2 Rules apply unchanged (`docs/plans/2026-10-23-engine-week2.md`, "Rules"): disk, the patch workflow,
capacity, internal disk and memory, the upstream header rule, symbol checks, launching, stopping, synthetic input,
window-only screenshots, CDP, mock keychain, user data, time-boxes, file-level commits, no emojis. Additions:

| Name | Path |
|---|---|
| `$REPO` | the engine-lane worktree `arkt-wt/engine-week3` (W3-0); `$CR/arkt` points at `$REPO/engine/arkt` |
| `$SWT` | a Swift-lane worktree under `arkt-wt/` (one per task, branch per issue); never repoints `$CR/arkt` |
| `$CR`, `$OUT`, `$PROF` | as in week 2 (`$OUT` = `$CR/out/Spike`) |
| `$EMB` | `$CHROMIUM_ROOT/embed-week3`: the development bundle layout (W3-0a, W3-3), on the Chromium disk |
| `$RES` | `$REPO/docs/plans/2026-10-24-engine-week3-results.md` (created by W3-0a, pull request #229) |

- **Two lanes, one owner each.** The engine lane owns `engine/`, the `Engine` configuration in `project.yml`,
  `app/ArktShell/App/Engine/` and the `ChromiumEngineKit` target (until W3-9, decision 5). The Swift lane owns
  `EngineAPI`, `EngineAPITestSupport`, `FakeEngineKit`, `ShellUI`, `CoreBridge` and the rest of `app/ArktShell/App`; the engine lane takes W3-1's changes to the first three. A
  change to the other lane's files goes through that lane's review. The interface between them is the table in
  "Interface boundary"; it changes only by a pull request both lanes approve.
- **Engine worktree.** Only the engine lane uses `$REPO` and builds `out/Spike`. It starts after #18 (pull request
  #217) has merged and its worktree is released: #18 edits `arkt_browser_window.{h,mm}`, the extensions files,
  `arkt_browser_main_extra_parts.mm` and `BUILD.gn`, which W3-0 and W3-3 to W3-5 also edit.
- **Swift builds.** While a Chromium build runs, at most two Swift builds, at `nice -n 20` (week-2 Capacity). Swift-lane
  tasks run `swift test` and the Debug app build only; they never need a Chromium build.
- **FakeEngine build unchanged.** Every task that touches `project.yml`, `main.swift` or the composition root checks that
  the `Debug` build still has `NSPrincipalClass = NSApplication` and contains no engine code
  (`strings <Debug app binary> | grep -c "ARKT engine"` prints `0`), as Task WE did. `Local.xcconfig` is an optional
  include (`#include?`), so a clean checkout and CI build `Debug` without it.
- **Development bundle.** `out/Spike` is a component build: the framework must be a real directory inside the app and
  the 518 component dylibs must sit next to the app bundle (Task WE, Run B). The `Engine` configuration builds into
  `$EMB`; its copy phase runs before Xcode's code-sign step, copies the framework only when it changed, and Xcode must
  not re-sign the framework (checked with `codesign -dv` on the framework after each build). Expect about 110 s of
  system scanning on the first launch after each fresh copy; warm launches reach the hook in about 3 s.
- **Launching the app on the engine.** Same flags as week 2 (`--user-data-dir` under `$PROF`, `--use-mock-keychain`,
  `--no-first-run`, `--no-default-browser-check`, `--enable-logging=stderr`), PID from `$!`, killed by PID. Each run
  uses its own profile and CDP port, and moves its window clear of other apps under test right after launch
  (week-2 results, "Interference"). Never launch without `--user-data-dir`.
- **No nested loops in engine handlers.** No Swift code runs a modal session, `NSMenu` tracking or any nested run loop
  from inside an engine event handler or a host-provider call (Decision 3). Open menus and alerts from an AppKit action
  or event callout, as a sheet (`beginSheetModal`), or through `RunLoop.main.perform(inModes: [.common])`; never
  synchronously from a `Task` or a `DispatchQueue.main.async` block (a loop opened there starves the main queue,
  W3-0a).
- **Contract runs.** `ChromiumEngine` is checked twice: in `swift test` against a scripted facade (W3-6, no
  Chromium), and in the app against the real engine (W3-9, the contract runner).
- **No personal paths, ids or names** in code, docs, logs that are committed, commits or pull requests.

## Decisions fixed for this track

1. **Handshake without exported symbols; the header has protocols only.** The framework links with
   `chrome/app/framework.exports`, which keeps only `_ChromeMain` and two app-mode entry points global; every other
   symbol, `//arkt` included, is hidden, and the app never links the framework (it is `dlopen`ed). So nothing in Swift
   may reference an engine class symbol (`_OBJC_CLASS_$_Arkt*`): no ObjC classes cross the boundary, only protocols
   and Foundation/AppKit types. Both sides meet through the Objective-C runtime, which registers every class of a loaded
   image whatever its linker visibility (`__objc_classlist`):
   - The Swift app defines `@objc(ArktShellEmbedder) final class` conforming to the ObjC protocol `ArktEngineEmbedder`
     (in the main executable, `app/ArktShell/App/Engine/`). `engineMain()` references it (`_ = ArktShellEmbedder.self`)
     before `ChromeMain`, so dead stripping can never drop it; W3-0a checks the class symbol is defined in the binary.
   - The hook (`ArktBrowserMainExtraParts`) calls `NSClassFromString(@"ArktShellEmbedder")`. Present: it creates the
     facade and calls `-engineDidStart:` on the embedder. Absent (the GN-built `Chromium.app`, every week-2 check): it
     keeps today's behaviour, the placeholder host, so engine-lane checks never need the Swift app.
   - Swift receives the facade as `any ArktEngine`, tabs as `any ArktTabHandle`, events as `any ArktEngineEvent`,
     window requests as `any ArktWindowRequest`: protocols, never classes. `arkt_window_host.h` keeps `ArktTabEvent`
     (a class) for the placeholder host only.
   Patch cost: 0. W3-0 runs the class lookup before W3-2 freezes the header. There is no cheap fallback for the
   protocol rule (an exported C function would not make class symbols visible), so if the lookup fails, W3-0 stops and
   the handshake is redesigned with the maintainer.
2. **The shell creates the windows, after it is ready.** The Engine configuration appends `--no-startup-window`
   (`startup_browser_creator.cc:346`, `:1001`, `:1173`) to `argv` before `ChromeMain`, unless the caller passed it, so
   Chromium creates no startup `Browser` and no session-restore window; Arkt owns tab persistence (#116).
   - **Readiness handshake.** The hook runs before `-applicationDidFinishLaunching:`, while the shell's start is async
     (data folder, database load). `-engineDidStart:` only records the facade and starts `AppComposition.start`. The
     shell calls `-[ArktEngine embedderReady]` once its session exists. Until then the facade **queues** every
     engine-initiated window request (startup URLs that `AppController` replays from `_startupTabs` after launch, Dock
     reopen, `chrome.windows.create` from an extension's `runtime.onStartup`): it records the request and creates the
     `Browser` only after `embedderReady`, replaying requests in order. A startup failure (`AppComposition.start`
     throws) calls `-[ArktEngine embedderFailed]`: the facade drops the queue and the shell shows its launch-failure
     alert, then quits through `chrome::AttemptExit()` (not `NSApp.terminate`).
   - *Shell-initiated* windows (launch, Cmd-N): Swift builds its `ShellWindowController`, then asks for a `Browser` in
     that window (`createWindow(host:)`); the facade creates it synchronously with the host already chosen. Whether the
     first window gets its `Browser` at once or on its first tab is decision 4 (on the first tab; a local
     change in `ShellWindowController`).
   - *Engine-initiated* windows after readiness: the factory override asks the embedder for a host synchronously
     (`-hostForEngineWindowRequest:`). The Swift provider may only build the window and return its host; it must not
     call the engine until the posted `windowOpened` event (Chromium is inside `Browser` construction).
   Until #21 lands, the Engine configuration also appends `--arkt-native-window`.
3. **Threading and re-entrancy.** On macOS Chromium's browser UI thread is the main thread (`MessagePumpNSApplication`),
   so `MainActor` and the UI thread are the same thread. The header marks every protocol `NS_SWIFT_UI_ACTOR`; the facade
   `DCHECK_CURRENTLY_ON(content::BrowserThread::UI)` on entry.
   - *Notifications.* The facade never calls into Swift from inside a Chromium notification (`TabStripModelObserver`,
     `WebContentsObserver`): it records plain-value events and delivers them in one batch from a posted task
     (`base::SequencedTaskRunner::GetCurrentDefault()->PostTask`), in order. A facade call that arrives while the facade
     is inside a notification `CHECK`s.
   - *Nested run loops* (measured in W3-0a, results file). Swift main-actor jobs run from the main dispatch queue. A
     nested loop opened from an AppKit event, timer or Chromium-source callout (`NSMenu` tracking, `NSAlert`
     `runModal`) drains it: about 30 main-actor and main-queue ticks in 3 s. A nested loop opened from inside a
     main-actor job (a `Task` or `DispatchQueue.main.async` block) does not: 0 ticks for the whole menu or alert.
     Chromium tasks keep running in all four cases (CDP calls never over 33 ms). So Swift code can run while Chromium
     code that opened a native loop is on the stack (context menus, `NSAlert`, live resize; Chromium bans its own tasks
     there, `thread_controller_with_message_pump_impl.cc:389`, `:448`); the engine-opened context menu case could not
     be measured in the spike and stays in the W3-3 gate. Facade mutators (`close`, `navigate`, `activate`, `createTab`, `createBrowser`, `closeBrowser`) check
     `base::RunLoop::IsNestedOnCurrentThread()` and the pump's native nesting; while nested they defer the work through
     `PostTask` and answer accordingly (`close` answers `held`; `createTab` still returns a handle at once and inserts
     it when the posted task runs). Read-only calls are always allowed.
   - *Swift menus and modals.* Facade batches are posted Chromium tasks, and Chromium tasks keep running while a Swift
     menu or modal is up, so engine event handlers can run on the stack of a Swift `NSMenu` or `NSAlert`. Handlers must
     tolerate that (no assumption that the shell is idle), and the W3-3 gate tests a batch arriving while a Swift
     `NSAlert` is up. A Swift handler must never open a modal itself inside a batch (Rules, "No nested loops in engine
     handlers").
   - W3-0a showed that Swift's main-actor executor runs under Chromium's pump (Risk 1 retired); W3-3's gate measures
     the remaining nested cases.
4. **Synchronous parts of the contract stay in Swift.** Contract rule 1 (`.tabCreated` before anything else, visible
   right after `createTab` returns) and rule 4 (`closeTab` is terminal at once when the close is not held) need
   synchronous answers, while engine events arrive one task later (Decision 3). `ChromiumEngine` therefore emits
   `.tabCreated` itself when the facade's `createTab` returns the new handle, and `.tabClosed(reason: .client)` itself
   when `close` answers `closed`, through `EngineEventHub`, and drops the matching facade events. Tabs the engine creates
   on its own are announced when their facade event arrives. `snapshot(of:)`, `tabIDs` and `contentView(for:)` read
   Swift-side tables kept current from facade events, as FakeEngine does.
5. **Tab identity.** A `TabID` maps to one tab handle, which wraps a `tabs::TabInterface` (stable across
   `TabStripModelChange::kReplaced` and across a move between windows through `DetachTabAtForInsertion`). The Chromium
   session id (what `chrome.tabs` reports) is a property of the handle that can change on replacement; it is never the
   Swift identity.
6. **One stable container per tab; the host mounts.** Each tab handle owns an Arkt `NSView` container. The current
   `WebContents` native view fills it; on `kReplaced` the facade swaps the subview, so `contentView(for:)` keeps its
   identity. For ShellUI hosts `ArktBrowserWindow` stops mounting the active tab; the shell puts containers in its card
   (one, or two to four in Split View) and removes them, and visibility still follows the view hierarchy (week-2
   Decision 3). The `TabStripModel` active index follows the shell's focused tab (focused pane in a split) through
   `activateTab`, so extension `active` flags stay true. The placeholder host keeps auto-mounting. Tab-modal dialogs use
   the tab's container as their `WebContentsModalDialogHost` view. The host's `cardView` is only the fallback for that
   dialog host and for `GetContentsSize` when no tab is mounted; it is never a mount point the engine fills.
7. **Framework name: keep `Arkt Framework.framework`** (decision 1). #33 asks for a name distinct from the
   `app/ArktCore` package; the name the branding file already produces (`PRODUCT_FULLNAME=Arkt`, `chrome/BUILD.gn:489`,
   `chrome_constants.cc:83`) is distinct and costs no patch. The Swift stub reads name and version from Info.plist keys
   written by the copy phase, so a rename touches only the branding file (or one patch) and nothing in Swift.
8. **User data directory without a patch.** `chrome_paths_mac.mm:26-69` reads `CrProductDirName` from the *outer* app's
   Info.plist (`base::apple::OuterBundle()`), falling back to `Chromium`. Crash dumps are stored relative to that default
   folder whatever `--user-data-dir` says (`chrome_paths.cc:216-219`), so the value matters even for test runs.
   - The `Engine` configuration (development) uses `Arkt Dev Engine`, so test runs never create or write inside the
     shell's real `Arkt` folder (and never create `Arkt` before `DatabaseLocation` applies its permissions). Its crash
     dumps are counted under `~/Library/Application Support/Arkt Dev Engine/Crashpad`.
   - The product value is decision 2 (`Arkt/Engine`), applied with #128 in a release configuration; it is
     one Info.plist key.
9. **Main menu owner: Arkt** (decision 3). Arc's defaults collide with Chromium's on about ten shortcuts
   (Cmd-T, Cmd-W, Cmd-S, Cmd-D, Cmd-L, Cmd-Shift-D, Cmd-Y, Cmd-Opt-Left/Right; `docs/spec/arc-parity-spec.md` section 1),
   and Arkt has menus Chromium lacks (Spaces, Archive).
   - The shell installs its own `MainMenu` on `NSApplicationDidFinishLaunchingNotification` (after `AppController` has
     built Chromium's menu and set its File menu delegate), not in `engineDidStart`.
   - `AppController` does more than look items up: a pre-search block installed in its `init`
     (`app_controller_mac.mm:812-817`) runs `updateMenuItemKeyEquivalents` (`:2419-2461`) before every key-equivalent
     search and rewrites the titles and actions of the Cmd-W and Shift-Cmd-W items in the submenu tagged
     `IDC_FILE_MENU`; `MenuCommandForKeyEvent` (`global_keyboard_shortcuts_mac.mm:46-67`) derives `IDC_EXIT` and the
     reserved commands from menu tags and actions, and `confirmQuitIfNeeded` depends on it. Arkt's menus therefore never
     use the `IDC_FILE_MENU`, `IDC_TAB_MENU` or `IDC_HISTORY_MENU` tags (W3-8 measured the rewrite: with the File tag,
     Archive Tab becomes Chromium's Close Tab and Cmd-W stops resolving), and Quit keeps Chromium's `IDC_EXIT` tag and
     `terminate:` action.
   - Arkt's menu carries a hidden top-level item tagged `IDC_BOOKMARKS_MENU` (57333) with an empty submenu:
     `-[AppController setLastProfile:]`, run when the first Arkt window becomes main, builds a `BookmarkMenuBridge` from
     that item and `CHECK`s it (`bookmark_menu_bridge.mm:62`); without it the browser crashes (W3-8, run A).
   - Chromium page commands (zoom, print, save as, find, developer tools, view source, history, downloads) are Arkt items
     that send `commandDispatch:` with their `EngineCommand` id (the `IDC_*` value), which the ShellUI host forwards to
     `chrome::ExecuteCommandWithDisposition` (week-2 W5b/W5c).
   - App-level Arkt items (Import from Arc, Show Archive, Settings) target an explicit object owned by the composition
     root, never a nil target: under the Engine configuration the application delegate is `AppController`, so items
     that relied on `AppDelegate` in the responder chain would stay disabled.
   - Reserved keys (W3-8): Cmd-T, Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q, Cmd-Opt-Right and Cmd-Opt-Left, so a
     focused page cannot swallow them. They are reserved in `ShellWindow.performKeyEquivalent(with:)` before `super`
     (where Chromium's own window-level dispatcher reserves on macOS), not in `ArktBrowserWindow::PreHandleKeyboardEvent`,
     which runs inside `RenderWidgetHostImpl`'s forwarding of the same event, where an archive or window close would
     destroy the `WebContents` under it; `PreHandleKeyboardEvent` keeps returning `NOT_HANDLED`.
   W3-8 found one non-tolerated dependency (the bookmarks `CHECK`) and the placeholder satisfies it, so Arkt keeps the
   menu. Were another to appear, the fallback is Chromium's menu with Arkt edits; that is a change confined to
   `App/Engine/` and `MainMenu.swift`.
10. **Extension surfaces stay engine-drawn this week.** The action list comes from `ToolbarActionsModel` through the
    facade as plain values (id, name, 16 pt icon PNG, enabled); running an action passes the shell's anchor `NSView`,
    and the popup is the existing `PopoverExtensionView` anchored to it. Extension-created windows follow Decision 2.
    Context menus, pinning, keyboard commands and the native install sheet stay in #121.
11. **Held closes and archiving** (decision 6). `CloseWebContentsAt` runs unload processing whatever
    the close type (`tab_strip_model.cc:4129-4191`). `RunUnloadEventsHelper` (`unload_controller.cc:328-399`) holds the
    close whenever `NeedToFireBeforeUnloadOrUnloadEvents()` is true, which covers `beforeunload` **or unload-time**
    handlers in any frame (`web_contents_impl.cc:3356-3376`), and also whenever DevTools is attached. So `held` is common,
    not an edge case, and a hold does not always show a dialog.
    - The facade's `close(mode:)` takes `.honourUnloadHandlers` (Chrome's behaviour) or `.skipUnloadHandlers` (closes
      without firing `beforeunload`; unload handlers still run without blocking), and answers `closed` or `held`.
    - Policy: **Cmd-W honours** leave-site prompts; **auto-archive skips** a tab that would hold
      (`wouldHoldClose` on the snapshot) and retries on its next pass.
    - The shell archives only after `.tabClosed`. While a close is held the row stays and the tab's container stays
      mounted (the dialog is tab-modal on that container), the row shows a "closing" state, and on a cancelled close
      (`.closeCancelled(TabID)`) the tab simply stays. The shell never removes a row and leaves a live tab behind.
    - Contract rule 16 states this; `InMemoryEngine` gets drivers for a held close and its outcome.
12. **Close reasons.** Every `.tabClosed` carries a reason: `.client` (this client asked), `.page` (`window.close()`),
    `.extension` (`chrome.tabs.remove`, `chrome.windows.remove`), `.windowClosing` (its window is being closed),
    `.appTerminating` (quit). The facade knows which: it marks tabs it closes, marks a window's tabs when the window
    closes, and marks every tab once quitting starts (Decision 13); a close it did not start is `.page` when the tab's
    `WebContentsDelegate::CloseContents` ran, otherwise `.extension`. The shell removes a sidebar row only for `.page`
    and `.extension`; `.windowClosing` and `.appTerminating` only unload (the stored sidebar is unchanged).
    The attribution gap (popups, options and persistent pages, and Close Tab, report `page`; an unrelated in-flight
    `tabs.remove` can be misattributed) is accepted without a patch.
13. **Quit and process lifetime.** `-[BrowserCrApplication terminate:]` goes to `tryToTerminateApplication`;
    `-applicationShouldTerminate:` is not supported (`chrome_browser_application_mac.mm:289-321`). Quit closes every
    `Browser` first (`CloseAllBrowsersAndQuit`, `application_lifetime_desktop.cc:335-358`), and `NotifyAppTerminating`
    fires only after the last one is gone (`:300-326`). The hook names two seams:
    - **Quit start.** The seam subscribes `chrome::AddClosingAllBrowsersCallback` (156 has no
      `BrowserListObserver::OnBrowserClosing` on desktop; W3-3): the first `true`, which `tryToTerminateApplication`
      sends before `CloseAllBrowsersAndQuit`, calls `-[ArktEngineEmbedder engineWillBeginTerminating]`, and the
      shell runs `prepareForTermination()` (stamps visible tabs, decision 10 of the shell plan) while its windows still
      exist. A cancelled quit (`stopTryingToTerminateApplication`, a held `beforeunload`; Chromium then sends `false`,
      once per browser) calls `-engineDidCancelTerminating` once.
    - **Terminating.** At `engineDidStart:` the facade registers one `ScopedKeepAlive` with an existing non-`BROWSER`
      `KeepAliveOrigin` (adding one would be a patch; `applicationWillTerminate` `CHECK`s on `BROWSER`, `:1055`), held
      for the life of the process, so the keep-alive is never registered late (`KeepAliveRegistry::Register` `CHECK`s
      `!is_shutting_down_`, `keep_alive_registry.cc:135`). It also subscribes `browser_shutdown::AddAppTerminatingCallback`;
      that callback calls `-engineWillTerminate:` and releases the keep-alive in the completion, or after a 5 s upper
      bound. Logout and SIGTERM take the time-limited `SessionEnding` path; there the flush gets whatever time it gets,
      and W3-9 records it.
    - **Last window.** The engine build keeps running with no windows (`AppController`'s keep-alive,
      `app_controller_mac.mm:824`, and macOS convention). The FakeEngine build quits on its last window today
      (`AppDelegate.swift:115`); the maintainer decided (#241) to keep the app running when the last window closes, so FakeEngine is aligned to the engine build
      (a one-line follow-up, not part of this week).
    W3-0a and W3-3 verify the seams fire in this order; W3-9 tests Cmd-Q, Dock Quit and logout.

## Interface boundary (Swift lane vs engine lane)

The second developer owns the Swift lane. These are the only artifacts that cross the boundary; each is frozen by an
early task so both lanes can work in parallel.

| Artifact | Owner | Consumer | Frozen in |
|---|---|---|---|
| `EngineAPI` additions (below), harness drivers and contract rules 11-16 | engine lane | engine lane (`ChromiumEngine`) | W3-1 |
| `InMemoryEngine` and `FakeEngine` implementing the additions | engine lane | ShellUI tests, the FakeEngine app | W3-1 |
| `engine/arkt/api/arkt_engine.h`: protocols `ArktEngineEmbedder`, `ArktEngine`, `ArktBrowserHandle`, `ArktTabHandle`, `ArktWindowHost`, `ArktWindowRequest`, `ArktEngineEvent`; enums; no classes, no C++, no Chromium includes | engine lane | `ChromiumEngineKit` only (isolation test) | W3-2, after W3-0's class lookup |
| `ChromiumEngineKit` (`ChromiumEngine: EngineClient, EngineExtensions`) | engine lane until W3-9 | composition root only | W3-6 |
| `AppComposition`: `start(engine:windowHostProvider:) async throws`, `prepareForTermination()`, `flush() async`, the app-menu target object | Swift lane | `ArktShellEmbedder` (engine lane) | W3-7 (start and quit part after W3-3) |
| `ShellWindowController` as `EngineWindowHosting` | Swift lane | `ChromiumEngine` | W3-7 |

**Proposed `EngineAPI` additions** (W3-1 settles names). Mostly additive; two changes are not, and W3-1 fixes their
call sites in the same pull request: `EngineEvent` gains cases (exhaustive switches, starting with `EngineEvent.tabID`
in `EngineClient.swift`), and `.tabClosed` gains a reason.

- Windows: `EngineWindowID` (opaque, `Hashable, Sendable`); `var windowIDs: [EngineWindowID]`;
  `func createWindow(host: any EngineWindowHosting) -> EngineWindowID` (synchronous); `func closeWindow(_:)`.
- Tabs: `func createTab(url: URL?, in window: EngineWindowID) -> TabID`. The window-less `createTab(url:)` stays for the
  existing contract tests and lands in the most recently active window (rule 15), **but W3-7 moves every shell call
  site to `createTab(url:in:)`** (`ShellWindowController.openEngineTab` today, `ShellWindowController.swift:371`), so
  with two windows a tab can never land in the wrong `Browser`. A lint test in ShellUITests fails on any ShellUI call to
  the window-less form.
- `func closeTab(_ id: TabID, mode: CloseMode)` (`.honourUnloadHandlers`, `.skipUnloadHandlers`); the existing
  `closeTab(_:)` means `.honourUnloadHandlers`.
- Activation: `func activateTab(_ id: TabID)`; `func activeTab(in window: EngineWindowID) -> TabID?`.
- `TabSnapshot` gains `window: EngineWindowID?`, `opener: TabID?`, `origin: TabOrigin` (`.client`, `.engine`),
  `isActive: Bool`, `isClosing: Bool` (a held close is pending) and `wouldHoldClose: Bool`, all with defaults.
- `EngineEvent` gains `.activeTabChanged(TabID)` and `.closeCancelled(TabID)`; `.tabClosed(TabID, reason: CloseReason)`
  with `CloseReason` = `.client`, `.page`, `.extension`, `.windowClosing`, `.appTerminating` (Decision 12).
- Window events on their own stream (an `EngineEvent` always has a tab):
  `observeWindows(_ handler: @MainActor (EngineWindowEvent) -> Void) -> EngineObservation` with
  `.windowOpened(EngineWindowID)`, `.windowClosed(EngineWindowID)`, `.extensionActionsChanged(EngineWindowID)`.
- **Per-window routing.** Every `ShellWindowController` observes all events today (`ShellWindowController.swift:114`).
  The rule: a window handles an engine-origin `.tabCreated` only when `snapshot.window` is its own window, and an
  `.activeTabChanged` only for its own tabs. W3-1 adds `observe(window:_:)`, a filtered variant, so the rule is not
  re-implemented per call site.
- `EngineCommand`: a `RawRepresentable` struct over `Int` with named constants for every command the shell sends or
  claims (`newTab`, `closeTab`, `closeWindow`, `reload`, `back`, `forward`, `find`, `zoomIn`, `zoomOut`, `zoomReset`,
  `print`, `savePage`, `devTools`, `viewSource`, `history`, `downloads`, `exit`, ...). Values are Chromium's `IDC_*`
  numbers; the engine lane fills them in W3-1's pull request and W3-0 adds a check that compares each constant with
  `chrome/app/chrome_command_ids.h` (a script-free `git grep` recorded in `$RES`, repeated on every rebase). Also
  `EngineDisposition` (`currentTab`, `newForegroundTab`, `newBackgroundTab`, `newWindow`) with
  `WindowOpenDisposition` values, checked the same way.
- `EngineWindowHosting` (`@MainActor` protocol, AppKit types only): `window: NSWindow`; `cardView: NSView` (fallback
  host for tab-modal dialogs and content size when no tab is mounted; never filled by the engine, Decision 6);
  `claim(_ command: EngineCommand) -> CommandClaim?` (the shell's answer for commands it implements: enabled state, or
  nil to let the engine decide) and `perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool`
  (true when the shell handled it); `var forward: EngineCommandForwarding?` (set by the engine: `validate` and
  `execute` for unclaimed commands); `onCloseRequested` (set by the engine; the host calls it and never closes its
  window itself).
- **Window close while a tab holds.** The engine closes the `Browser`; Chromium runs unload processing for every tab
  first. If any tab holds and the user cancels, the window stays open and `.closeCancelled` arrives for that tab; no
  `.windowClosed`. The shell keeps the window and its rows as they were.
- `EngineWindowRequest` (for engine-initiated windows): `kind` (`.extension`, `.page`, `.reopen`, `.startupURL`),
  `openerWindow: EngineWindowID?`, `bounds: CGRect?` (requested frame in screen coordinates, may be nil), `profile`
  (an opaque `EngineProfileID`; one profile this week), `initialURL: URL?`. The target Space is the shell's choice: the
  Space shown in `openerWindow`, else the last active Space.
- `EngineWindowHostProvider`: `@MainActor (EngineWindowRequest) -> any EngineWindowHosting`; must not call the engine.
- `EngineExtensions` (separate protocol; FakeEngine does not adopt it, the shell checks `engine as? EngineExtensions`):
  `extensionActions(in:) -> [ExtensionAction]` (`id`, `name`, `iconPNG: Data?`, `isEnabled`),
  `runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView)`.

**Harness drivers** (`EngineHarness` gains optional closures; a rule whose driver is nil is reported as **not
applicable**, never as passed): `engineCreateTab(engine, window, opener, active)`, `engineCloseTab(engine, id)`,
`engineActivate(engine, id)`, `holdClose(engine, id)` (makes the page register a `beforeunload` handler with sticky
user activation), `answerDialog(engine, id, accept)`. `InMemoryEngine` implements them directly; the Chromium harness
(W3-9) implements them through the facade's test API (script with a user gesture, dialog answer).

**New contract rules** (in `EngineAPITestSupport/EngineContract.swift`, run by every engine). Rules 1-10 exist
already: rule 9 (`history(of:)`, `goToHistory(_:offset:)`) and rule 10 (`duplicateTab(_:)`) landed with #81 in pull
request #238, so the new rules start at 11.

11. A window from `createWindow(host:)` is listed in `windowIDs` and announced with `.windowOpened`; every tab's
    snapshot names its window; `closeWindow` closes its tabs (`.tabClosed(reason: .windowClosing)` each) and then
    reports `.windowClosed`.
12. `activateTab` makes the tab its window's active tab: `.activeTabChanged(id)` and `isActive` in the snapshot, with
    exactly one active tab per window that has tabs.
13. A tab the engine creates on its own is announced with `.tabCreated` and its snapshot has `origin == .engine`, its
    window, its opener (when there is one) and `isActive`; an engine-side activation is announced with
    `.activeTabChanged`.
14. A tab the engine closes on its own ends with one `.tabClosed` with reason `.page` or `.extension`, and nothing after
    it, as rule 4.
15. `createTab(url:)` without a window lands in the most recently active window.
16. A held close keeps the tab listed with `isClosing` until `.tabClosed(reason: .client)`; a cancelled close reports
    `.closeCancelled` and leaves the tab open with no `.tabClosed`; `.skipUnloadHandlers` never holds on a
    `beforeunload` page.

## What the Swift side (shell) needs

- Route by window: handle engine-origin `.tabCreated` only for its own window, as a new Today tab in the Space that
  window shows (selected when `isActive`); `.activeTabChanged` as a selection change for its own tabs.
- Handle `.tabClosed` by reason: remove the row only for `.page` and `.extension`; for `.windowClosing` and
  `.appTerminating` only unload. A quit and a window close leave the stored sidebar unchanged.
- Archive only after `.tabClosed`; while `isClosing`, keep the row (closing state) and the container mounted; on
  `.closeCancelled` keep the tab. Auto-archive skips `wouldHoldClose` tabs until its next pass.
- Mount `contentView(for:)` containers and remove them; never assume one mounted tab per window (Split View).
- Call `activateTab` when the focused tab or pane changes; call `createTab(url:in:)`, never the window-less form.
- Be an `EngineWindowHosting`: `ShellWindow` forwards `commandDispatch:`, `commandDispatchUsingKeyModifiers:` and
  `validateUserInterfaceItem:` (the W5b note: without them every Chromium menu command is disabled for the window),
  routes its close button through `onCloseRequested`, and claims the Arc commands it implements before forwarding.
- Start from `AppComposition.start` (FakeEngine: `AppDelegate`; engine: `ArktShellEmbedder`, which then calls
  `embedderReady` or `embedderFailed`), stamp from `prepareForTermination()` at quit start, flush from `flush()` at
  terminating (Decision 13).
- App-level menu items target the composition root's object (Decision 9).
- An Extensions control in the sidebar when `engine is EngineExtensions`.
- No modal or nested loop inside engine handlers or the host provider (Rules).

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001-0006 | week 2 (hook, draw, keychain, factory hook, tab features, dialogs) | exist | 13 | 0 |
| 0007 | extension dialogs as native sheets (#244, pull request #252) | exists | 4 | 0 |
| 0008 | link activation throttle for Peek (#313): one call in `chrome_content_browser_client_navigation_throttles.cc` | exists | 1 | 0 |
| - | Handshake (Decision 1) | ObjC runtime lookup, no patch | 0 | 0 |
| - | Framework name (Decision 7) | no patch unless decision 1 is reopened | 0 (1-2) | 0 |
| - | User data directory (Decision 8), `--no-startup-window` (Decision 2) | Info.plist key and argv, no patch | 0 | 0 |
| - | Quit seams (Decision 13) | existing observers, callback list and `KeepAliveOrigin`, no patch | 0 | 0 |
| - | Facade, host mode, infobars, menu routing, reserved keys | overlay only | 0 | 0 |

Projection after week 3: 7 patch files, 17 upstream files, 0 hot-file hunks (0007 landed with #244 after this plan was
written); at worst 8 patch files if the framework is renamed by patch. Not this week (recorded so it is not mistaken for scope): the link-target status pill (#114) needs
a seam for `BrowserWebContentsDelegate::UpdateTargetURL`, whose status bubbles must stay empty (W5a). `$RES` keeps the
table current with the week-2 commands.

## Risks

1. **Main-actor executor under Chromium's pump. Retired by W3-0a (pull request #229):** main-actor tasks and the main
   queue run under `MessagePumpNSApplication`; the remaining nested-loop cases are in Decision 3 and the W3-3 gate.
2. **Event order versus the contract.** Rule 2 (title before load end) and rule 6 (favicon cleared before load end on a
   host change) depend on the order of `TitleWasSet`, `DidFinishNavigation`, `DidStopLoading` and favicon callbacks.
   FakeEngine needed a bounded title wait (`titleTimeout`). The facade emits per-tab events in Chromium's order and
   `ChromiumEngine` reorders only within one batch, with the same bounded wait if W3-9 shows it is needed.
3. **Re-entrancy** (Decision 3): notifications, nested native loops, and Swift modals inside batches. Guarded in the
   facade and measured in the W3-3 gate.
4. **Startup ordering** (Decision 2): engine-initiated window requests before the shell is ready. Queued; tested with
   a cold launch with a URL and an extension that opens a window on startup (W3-9).
5. **Quit seams** (Decision 13): the stamp must run while windows exist, the flush before the process exits, and the
   keep-alive must never be registered late. Verified in W3-3 and W3-9.
6. **Shell window versus Chromium expectations.** `ShellWindow` is borderless with its own traffic lights and key
   handling. Chromium calls `toggleFullScreen:`, reads occlusion, and offers unhandled page keys to `NSApp.mainMenu`
   (`HandleKeyboardEvent`). Reserved keys (Decision 9) keep Arc shortcuts out of pages. Checked in W3-9.
7. **Development loop cost.** Each fresh framework copy costs about 110 s of scanning; the 518 dylibs (678 MB) next to
   the bundle cost disk. The copy phase copies only on change and clones (`cp -c`) on the Chromium disk.
8. **Menu takeover** (Decision 9). W3-8 decides with evidence; the fallback is local.
9. **Mixed bundle ids.** The framework is branded `com.arkt.Arkt` (helpers `com.arkt.Arkt.helper*`) while the app is
   `dev.arkt.ArktShell`. The Mach rendezvous follows the outer app id and works (Task WE), but notifications (alerts
   helper), TCC attribution and the keychain ACL see mixed ids. W3-11 records them; #128 aligns both.
10. **Interference.** Other apps under test share the screen (week-2 "Interference"): own profile, own port, window
    moved clear, AX input only after the frontmost and key-window checks.

---

### Task W3-0a: Main-actor probe on the existing `Spike` configuration (engine lane; now)

Needs no engine worktree and no Chromium build: it uses the `Spike` configuration from Task WE and the existing
`out/Spike` framework copy layout. Answers Risk 1 before anything is built on it.

**Files:**
- Modify: `app/ArktShell/App/ChromiumSpikeMain.swift` (probe lines only, under `ARKT_CHROMIUM_SPIKE`)
- Create: `$RES` (done in #229)

**Steps:**
1. In `chromiumSpikeMain()`, before `ChromeMain`: `_ = ArktShellEmbedderProbe.self` for a tiny
   `@objc(ArktShellEmbedderProbe)` class, then schedule `Task { @MainActor in try await Task.sleep(for:
   .milliseconds(500)); log("ARKT probe: main actor resumed") }` and
   `DispatchQueue.main.async { log("ARKT probe: main queue drained") }`. Nothing touches `NSApplication`.
2. Build the `Spike` configuration, copy into the Run B layout under `$EMB`, launch with a fresh profile.
3. `nm -m <app binary> | grep -F 'OBJC_CLASS_$_ArktShellEmbedderProbe'` shows the class defined in the binary (dead-strip
   safeguard works).

**Acceptance criteria:** both probe lines appear within 3 s of `ARKT: in-process hook alive`; the process stays alive
30 s; the class symbol is defined. If `main actor resumed` never appears: stop, record, and raise it with the
maintainer before W3-2 and W3-6 continue (the alternative is driving Swift work only from posted engine callbacks).

**Verification:** log lines with timestamps, `nm` output, in `$RES`.

**Commit:** `ChromiumSpikeMain.swift`, `$RES`; "Probe the Swift main actor under Chromium's run loop".

Time-box: 3 h (including one fresh-copy launch).

---

### Task W3-0: Engine worktree, baselines, class lookup, command ids (engine lane)

**Depends on:** #18 merged (pull request #217) and its worktree released.

**Files:** Extend `$RES` (`docs/plans/2026-10-24-engine-week3-results.md`, created by #229); modify `engine/arkt/browser/arkt_browser_main_extra_parts.mm` (lookup log only).

**Steps:**
1. `git worktree add ../arkt-wt/engine-week3 -b engine/33-chromium-engine origin/main`; repoint `$CR/arkt` (week-2 W0
   Step 1, never while a build runs); `readlink $CR/arkt` equals `$REPO/engine/arkt`.
2. `git -C $CR rev-list --count 156.0.8078.48..arkt` equals `wc -l < $REPO/engine/patches/chromium/.patches` (7); hot-file
   hunks 0 (week-2 command).
3. Class lookup: the hook logs `ARKT: embedder class <found|absent>` for `NSClassFromString(@"ArktShellEmbedderProbe")`
   and whether it responds to a selector. Incremental `out/Spike` build; launch the W3-0a app (expect `found`) and
   `Chromium.app` (expect `absent`). W3-2 freezes only after this result.
4. W5c Step 3 (visibility) and the W6 identity check pass on the placeholder path with `--arkt-native-window` (or
   without it if #21 has landed).
5. Command ids: record each `EngineCommand` and `EngineDisposition` value from W3-1's proposal against
   `chrome/app/chrome_command_ids.h` and `ui/base/window_open_disposition.h` (`git -C $CR grep -n`).
6. Swift baselines: `swift test --skip ShellKitGUITests` in ShellKit and `swift test` in ArktCore, counts recorded as
   "baseline + N".
7. `$RES`: header, task table (all `TODO`), the patch budget table above, the baselines.

**Acceptance criteria:** lookup `found` in the app and `absent` in `Chromium.app`; patch counts match; W5c and W6 checks
pass; the command-id table is complete.

**Verification:** `$RES` holds the counts and command outputs; no leftover processes.

**Commit:** the hook file, `$RES`; "Engine week 3 baseline and embedder class lookup".

Time-box: 2 h.

---

### Task W3-1: `EngineAPI` additions, harness drivers and contract rules 11-16 (engine lane)

No Chromium. Can start at once. The `EngineCommand` values come from the engine lane in this pull request.

**Files:**
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPI/EngineClient.swift` (and new files beside it for windows,
  hosting, commands, extensions)
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPI/EngineEventHub.swift` (window stream, `observe(window:)`; same
  non-reentrant FIFO)
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPITestSupport/{EngineContract,InMemoryEngine,EventRecorder}.swift`
- Modify: `app/ArktShell/ShellKit/Sources/FakeEngineKit/FakeEngine.swift` (windows; `origin == .client` only; closes
  never hold)
- Modify: every exhaustive `switch` over `EngineEvent` and every `.tabClosed` match in ShellUI (the non-additive part)
- Modify: `app/ArktShell/ShellKit/Tests/EngineAPITests/*`, `Tests/FakeEngineKitTests/*`

**Steps:** write rules 11-16 and the harness drivers first (failing against `InMemoryEngine`), then implement in
`InMemoryEngine` and `FakeEngine`. Shapes as in "Interface boundary"; this pull request is where both lanes agree on
names. Decision 11 (decision 6) is part of the freeze; the maintainer's answer is final.

**Acceptance criteria:** rules 1-16 pass for `InMemoryEngine`; FakeEngine passes 1-12 and 15 and reports 13, 14 and 16
as not applicable (no drivers); `EngineEventHub` tests cover the window stream and `observe(window:)`; the existing
ShellUI tests still pass after the switch and `.tabClosed` updates; the engine lane has approved the pull request.

**Verification:** `swift test --skip ShellKitGUITests` (baseline + N); FakeEngine GUI contract tests
(`--filter ShellKitGUITests`) still pass.

**Commit:** files named one by one; "Add windows, activation, close reasons and contract rules 11-16 to EngineAPI".

Time-box: 1 day.

---

### Task W3-2: The facade header and its Swift module (engine lane; no build)

Drafting can start at once; the header **freezes only after W3-0's class lookup**. Needs no engine worktree.

**Files:**
- Create: `engine/arkt/api/arkt_engine.h` (ObjC only: `Foundation`, `AppKit`)
- Create: `app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h` (a byte-identical copy) and
  `module.modulemap`
- Modify: `app/ArktShell/ShellKit/Package.swift` (C target `ArktEngineABI`, header only)
- Create: `app/ArktShell/ShellKit/Tests/ArktEngineABITests/ConformanceTests.swift` (Swift types implementing every
  protocol, building an event batch and a window request)
- Modify: `app/ArktShell/ShellKit/Tests/IsolationTests/` (new `EngineABIIsolationTests.swift`)

**Contents of the header** (protocols and `NS_ENUM`s only; every protocol `NS_SWIFT_UI_ACTOR`, nullability annotated):
- `ArktEngineEmbedder` (implemented in Swift): `+sharedEmbedder`, `-engineDidStart:(id<ArktEngine>)`,
  `-hostForEngineWindowRequest:(id<ArktWindowRequest>)` returning `id<ArktWindowHost>`,
  `-engineWillBeginTerminating`, `-engineDidCancelTerminating`, `-engineWillTerminate:` with a completion block.
- `ArktEngine`: `embedderReady`, `embedderFailed`, `browsers`, `createBrowserWithHost:`, `extensionActionsForBrowser:`
  (array of `id<ArktExtensionAction>`), `runExtensionAction:inBrowser:anchor:`, `addEventSink:` (a block receiving
  `NSArray<id<ArktEngineEvent>>`), and the test API (Task W3-5 step 5).
- `ArktBrowserHandle`: `windowId` (session id), `tabs`, `activeTab`, `createTabWithURL:active:`, `close`.
- `ArktTabHandle`: `containerView`, `sessionId`, `url`, `title`, `faviconPNG`, `isLoading`, `canGoBack`, `canGoForward`,
  `opener`, `isClosing`, `wouldHoldClose`, `backEntries` / `forwardEntries` (`ArktHistoryEntry`, nearest first),
  `navigateToURL:`, `reload`, `goBack`, `goForward`, `goToHistoryOffset:`, `activate`, `closeWithMode:` (returns
  `ArktCloseResult`), `focus`, `duplicate` (history and duplicate serve rules 9 and 10, landed in #238).
- `ArktWindowHost`: the week-2 protocol from `arkt_window_host.h` (pure ObjC, AppKit), moved here; the placeholder-only
  `activateTab` block becomes optional. `ArktTabEvent` stays a class in `arkt_window_host.h`, used by the placeholder only.
- `ArktWindowRequest`, `ArktEngineEvent` (kind, tab, browser, close reason, plain values), `ArktExtensionAction`:
  protocols; the facade implements them with private classes.

**Acceptance criteria:**
- The header compiles standalone as Objective-C and Objective-C++ (`clang -fsyntax-only -fobjc-arc -x objective-c`
  and `-x objective-c++`, `-isysroot $(xcrun --show-sdk-path)`); `grep -E '#include|namespace|std::|template|@interface'`
  finds nothing.
- `ArktEngineABITests` implements every protocol in Swift, builds an event batch and a request, and links without the
  framework.
- The isolation test fails if any target other than `ChromiumEngineKit` (and its tests) imports `ArktEngineABI`, and if
  the two header copies differ.

**Verification:** both `clang` commands exit 0; `swift test --filter 'IsolationTests|ArktEngineABITests'` passes.
W3-3 adds the binary check (`nm -u <app binary> | grep -cF '_OBJC_CLASS_$_Arkt'` prints `0`).

**Commit:** the two header copies, the module map, `Package.swift`, the two test files, `arkt_window_host.h`; "Add the
engine facade header and its Swift module".

Time-box: 5 h.

---

### Task W3-3: Engine configuration, readiness and quit seams, re-entrancy gate (engine lane; GATE)

**Depends on:** W3-0a, W3-0, W3-2.

**Decided (maintainer, 2026-10-24):** windows requested before readiness are created hidden, without a patch; the CDP
port blocks Quit, so quit tests run without it; the stand-in embedder moves into `ChromiumEngineKit` in W3-6.

**Files:**
- Modify: `app/ArktShell/project.yml` (configuration `Engine` replaces `Spike`: Swift flag `ARKT_CHROMIUM_ENGINE`,
  `ARKT_PRINCIPAL_CLASS: BrowserCrApplication`, hardened runtime off for development, `ENABLE_DEBUG_DYLIB: NO`,
  Info.plist keys `ArktEngineFrameworkName`, `ArktEngineFrameworkVersion`, `CrProductDirName = Arkt Dev Engine`; a
  run-script phase, only in `Engine` and ordered before code signing, that copies the framework when it changed and
  writes the two framework keys from the framework's own `Info.plist` and `Versions/Current`, never from literals;
  optional `#include? "Local.xcconfig"`)
- Create: `app/ArktShell/App/Engine/EngineMain.swift` (replaces `ChromiumSpikeMain.swift`), `ArktShellEmbedder.swift`
- Modify: `app/ArktShell/App/main.swift` (`#if ARKT_CHROMIUM_ENGINE`: `engineMain()` and nothing else)
- Create: `engine/arkt/api/arkt_embedder.{h,mm}` (lookup, readiness queue, quit seams, keep-alive, nesting guard),
  `engine/arkt/api/BUILD.gn`; modify `arkt_browser_main_extra_parts.mm`, `engine/arkt/browser/BUILD.gn`
- Modify: `.gitignore` (one line for `app/ArktShell/Local.xcconfig`, which names `ARKT_ENGINE_OUT` locally)

**Steps:**
1. `EngineMain.swift`: `_ = ArktShellEmbedder.self`; read the two keys from `Bundle.main`, build the versioned path as
   `chrome_exe_main_mac.cc` does, `dlopen(RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST)`, append `--no-startup-window` and
   (until #21) `--arkt-native-window` to a copy of `argv` when absent, call `ChromeMain`, `exit` with its status.
2. `ArktShellEmbedder`: this task logs each callback (`engineDidStart`, `hostForEngineWindowRequest`,
   `engineWillBeginTerminating`, `engineDidCancelTerminating`, `engineWillTerminate`) and calls `embedderReady` after a
   simulated 2 s async start (`Task { @MainActor in try await Task.sleep(...) }`).
3. Hook: lookup and `engineDidStart:`; the readiness queue (Decision 2); the quit seams and the lifetime keep-alive
   (Decision 13; record which existing `KeepAliveOrigin` is used); the nesting guard (Decision 3); the hook logs
   `ARKT: default user data dir <path>` from `chrome::GetDefaultUserDataDirectory`.
4. Re-entrancy probes behind `--arkt-reentrancy-probe` (engine side, posted Chromium tasks): (a) open an `NSMenu`
   (`popUpMenuPositioningItem:`) and, 300 ms later from a Swift `Task`, call `createTab` and `close` on a facade tab;
   record whether the main-actor job ran during menu tracking and whether the facade deferred it; (b) the same with an
   `NSAlert` `runModal`; (c) a Swift event handler that runs `NSAlert.runModal` inside a batch (the forbidden case):
   record how long Chromium UI tasks stall. Cancel the menu and alert programmatically after 2 s.
5. Build `out/Spike`; build `Engine` into `$EMB`; clone the component dylibs next to the bundle once (`cp -c`).

**Acceptance criteria (GATE):**
- Launch from `$EMB`: `ARKT: embedder class found`, `engineDidStart`, no startup window, `embedderReady` after about
  2 s, process alive 30 s, 0 `FATAL`/`Check failed`; `ARKT: default user data dir` ends in `Arkt Dev Engine`.
- `nm -u <app binary> | grep -cF '_OBJC_CLASS_$_Arkt'` prints `0`; `nm -m <app binary> | grep -F 'OBJC_CLASS_$_ArktShellEmbedder'` shows it defined (`grep -F`: the `$` is literal).
- Readiness: a launch with a URL argument and a Dock-style reopen (debug switch calling `chrome::NewEmptyWindow`)
  before `embedderReady` are queued and replayed after it (log order: request queued, ready, host asked).
- Quit: Cmd-Q (CDP `Browser.close` is not the same path; use the menu item through AX after the checks) logs
  `engineWillBeginTerminating` before any `native window destroyed`, then `engineWillTerminate`, then the process exits
  after the completion; a quit cancelled by a held `beforeunload` logs `engineDidCancelTerminating` and the process
  stays. No `Check failed` from the keep-alive registry.
- Re-entrancy probes recorded; facade mutators called during menu tracking or an alert are deferred (no crash, no
  `CHECK`), and the forbidden case is documented with its stall time; a facade batch that arrives while a Swift `NSAlert` (opened from
  an AppKit action) is up runs its handlers without a crash and the shell state stays consistent; the engine-opened page
  context menu case (not measurable in W3-0a) is measured here.
- `out/Spike/Chromium.app` logs `embedder class absent` and the W5c checks still pass; `Debug` unchanged (Rules).

If any readiness or quit seam does not fire as described, stop and record before W3-7 wires the start and quit part.

**Verification:** logs, `nm` output, window-only screenshots; dump count under `Arkt Dev Engine/Crashpad`.

**Commit:** project, app and overlay files named one by one, plus `$RES`; "Embed the engine and add the embedder
readiness and quit seams".

Time-box: 1.5 days (including one fresh-copy launch at about 110 s).

---

### Task W3-4: Host mode for ShellUI windows (engine lane)

**Depends on:** W3-3.

**Files:**
- Modify: `engine/arkt/browser/arkt_browser_window.{h,mm}`, `arkt_browser_window_parts.{h,mm}` (modal host per tab
  container), `arkt_browser_main_extra_parts.mm` (factory: embedder host first, placeholder otherwise)
- Create: `engine/arkt/api/arkt_engine_facade.{h,mm}` (browser part: `createBrowserWithHost:`, `browsers`, window events,
  close reasons for windows)

**Steps:**
1. `createBrowserWithHost:` creates a `TYPE_NORMAL` `Browser` synchronously for the initial profile, which is loaded
   before the hook runs (`chrome_browser_main.cc:1919`, `:2167`); `CHECK` that it is (profile-picker mode is out of
   scope).
2. Engine-initiated `TYPE_NORMAL` browsers ask `-hostForEngineWindowRequest:` with the request fields (Interface
   boundary); before `embedderReady` they are queued (W3-3); no embedder or a nil host: the placeholder host.
3. Host mode: no auto-mount for embedder hosts (Decision 6); `GetContentsSize` and the modal dialog host follow the
   focused tab's container, `cardView` only as fallback; `closeRequested` closes the `Browser` (tabs get
   `.windowClosing`); a window close cancelled by a held tab leaves the window and reports `closeCancelled`; the facade
   reports `windowOpened` / `windowClosed` from posted tasks.
4. A self-test embedder inside the overlay, behind `--arkt-facade-selftest` (an ObjC class used only when the switch is
   present and no Swift embedder exists): it supplies plain `NSWindow` hosts, calls `embedderReady` at once, and logs
   every facade event as `ARKT selftest <event>`. This is how the engine lane checks W3-4 and W3-5 on `Chromium.app`.

**Acceptance criteria:** with `--arkt-facade-selftest`: a shell-initiated window opens (`windowOpened`, census
`normal=1 arkt=1 views=0`); `chrome.windows.create` from the tabs probe asks the provider with `kind=extension` and
opens a second host window (`normal=2 arkt=2 views=0`); closing a host window closes its `Browser` (`windowClosed`, tabs
closed with `windowClosing`, `native window destroyed`); Dock-style reopen lands in a provider window with
`kind=reopen`. Without the switch every W5b row re-run in W3-0 still passes.

**Verification:** logs and census lines; CDP `chrome.windows.getAll` ids equal the facade's window ids; window-only
screenshots.

**Commit:** overlay files named one by one, plus `$RES`; "Let embedder hosts own Arkt browser windows".

Time-box: 1 day.

---

### Task W3-5: Tab facade: handles, containers, state, closes, extension actions (engine lane)

**Depends on:** W3-4.

**Files:**
- Modify/create: `engine/arkt/api/arkt_engine_facade.{h,mm}`, `engine/arkt/api/arkt_tab_handle.{h,mm}`
  (`tabs::TabInterface` wrapper, `WebContentsObserver`, `favicon::FaviconDriverObserver`, container view)
- Modify: `engine/arkt/browser/arkt_browser_window.mm` (tab list feeds the facade), `arkt_extensions_menu.{h,mm}`
  (action list and run-with-anchor for the facade; the sidebar placeholder keeps its menu)

**Steps:**
1. Tab handle per `TabInterface`, created on insertion, kept across `kReplaced` and cross-window moves (Decision 5);
   container `NSView` with the current `WebContents` view as its only subview, swapped on replacement; `focus` makes
   the contents first responder.
2. Per-tab state from `WebContentsObserver` and `FaviconDriverObserver` as in the mapping table; events carry plain
   values, in Chromium's order, posted in batches.
3. Calls as in the mapping table; `closeWithMode:` (Decision 11) answers `closed` or `held`, sets `isClosing`, reports
   `closeCancelled` on cancel; `wouldHoldClose` from `NeedToFireBeforeUnloadOrUnloadEvents()` and DevTools attachment;
   close reasons (Decision 12).
4. Extension actions: list per browser, change events, run with an anchor view.
5. Test API, compiled into every `//arkt` build but **enabled only at run time** by `--arkt-engine-test-api` (the runner
   passes it; without the switch every test call is a logged no-op): `evaluateScript:inTab:userGesture:completion:`
   (CDP-style `Runtime.evaluate` semantics through `ExecuteJavaScriptForTests`/user-gesture variant, checked against
   156) and `answerDialogInTab:accept:` (the JavaScript dialog manager's pending dialog).

**Acceptance criteria (self-test embedder):** the W5c sequence produces `tabCreated` with `origin=engine`,
`activeTabChanged`, and `visibilityState` as in W5c when the self-test host mounts containers; a navigation logs url,
loading start, title, loading end in that order; a host change logs the favicon clear before load end; `chrome://crash`
then reload keeps the same container; the action list equals `--arkt-extensions-menu-dump`'s items; running
action-probe logs `popup loaded` anchored to the self-test view. Closes:
- a page with `onbeforeunload` (set with a user gesture): `held`, dialog shown on the container, removal only after
  accept, `closeCancelled` after cancel; `.skipUnloadHandlers` closes at once;
- a page with only an `unload` handler: record whether it answers `held` and for how long (no dialog);
- a tab with DevTools attached: record `held` and when it completes;
- `chrome.tabs.remove` logs reason `extension`; `window.close()` from a page logs `page`.

**Verification:** logs, CDP, window-only screenshots; `gn check out/Spike '//arkt/*'`.

**Commit:** overlay files named one by one, plus `$RES`; "Add the tab facade: handles, containers, state, closes,
actions".

Time-box: 2 days.

---

### Task W3-6: `ChromiumEngineKit` over the facade, tested against a scripted facade (engine lane, Swift)

**Depends on:** W3-0a, W3-1, W3-2 (frozen). Needs no engine worktree; runs in parallel with W3-3 to W3-5. If W3-3's gate
changes a seam, the affected part is revised before W3-9.

**Files:**
- Create: `app/ArktShell/ShellKit/Sources/ChromiumEngineKit/ChromiumEngine.swift` (+ small helpers)
- Create: `app/ArktShell/ShellKit/Tests/ChromiumEngineKitTests/` (a scripted Swift implementation of the facade
  protocols that delivers batches on the next main-actor turn, like the real facade; contract tests 1-16 against it with
  all harness drivers)
- Modify: `Package.swift`, `Tests/IsolationTests/` (only the app's composition root may import `ChromiumEngineKit`)

**Steps:** map `TabID` to tab handles and `EngineWindowID` to browser handles; synchronous `.tabCreated` /
`.tabClosed(.client)` for client calls with deduplication of the facade's later events (Decision 4); held closes and
cancellations; close reasons; snapshots from events; window stream and `observe(window:)`; `EngineWindowHosting`
wrapped into an `ArktWindowHost` object (claims first, then `forward`); `EngineCommand` passed through as its raw value;
`EngineExtensions` over the action calls.

**Acceptance criteria:** contract rules 1-16 pass against the scripted facade, including scripts that reorder title and
load end within one batch, replace a tab's contents, hold and cancel a close, and close a window while a tab holds;
isolation tests pass; no `@unchecked Sendable` or `nonisolated(unsafe)`. Instance scoping is defined and tested: a
`ChromiumEngine` lists only the windows it created or was handed through its host provider, and only their tabs, so
several instances over one facade (the W3-9 runner) never see each other's tabs; `createTab(url:)` on an instance with
no window is a precondition failure, and the runner's `makeEngine` creates the instance's window first.

**Verification:** `swift test --skip ShellKitGUITests` (baseline + N).

**Commit:** the new target, its tests, `Package.swift`, the isolation test; "Add ChromiumEngine over the engine
facade".

Time-box: 1.5 days.

---

### Task W3-7: The shell as engine host, and a composition root for two engines (Swift lane)

**Depends on:** W3-1. Parts A and B can start at once; part C (start and quit) waits for W3-3's gate result on the
readiness and quit seams; part D (menu) waits for W3-8 step 3.

**Files:**
- Modify: `ShellUI/Window/ShellWindowController*.swift`, `ShellUI/Window/ShellWindow.swift`
- Create: `ShellUI/Sidebar/ExtensionsButton.swift` (shown when `engine is EngineExtensions`)
- Create: `app/ArktShell/App/AppComposition.swift`; modify `AppDelegate.swift`, `AppSession.swift`, `MainMenu.swift`
- Tests: `ShellUITests`, `ShellKitGUITests` against `InMemoryEngine` (drivers from W3-1)

**Steps:**
- **A. Hosting.** `ShellWindowController` conforms to `EngineWindowHosting`; `ShellWindow` forwards the three command
  selectors; the close button calls `onCloseRequested`; Arc commands (`EngineCommand.newTab` to the command bar,
  `.closeTab` to archive or close, and the others in the W3-8 table) are claimed before forwarding.
- **B. Tabs.** Every shell call site uses `createTab(url:in:)`; per-window routing (`observe(window:)`); engine-created
  tabs become Today tabs in the window's Space; engine activations select the row; closes by reason (Decision 12);
  archive after `.tabClosed`, closing state while held, `.closeCancelled` keeps the tab; auto-archive skips
  `wouldHoldClose` tabs; Split View mounts containers and calls `activateTab` for the focused pane.
- **C. Start and quit.** `AppComposition.start(engine:windowHostProvider:) async throws` holds what
  `AppDelegate.launch()` does today; `prepareForTermination()` stamps visible tabs; `flush() async` writes pending
  changes. FakeEngine: `AppDelegate` calls `start`, and its `.terminateLater` path calls `prepareForTermination()` then
  `flush()`. Engine: `ArktShellEmbedder` calls `start` then `embedderReady` (or `embedderFailed` and the failure alert,
  then `chrome::AttemptExit()` through the facade), `prepareForTermination()` from `engineWillBeginTerminating`,
  `flush()` from `engineWillTerminate:`. `presentLaunchFailure` no longer calls `NSApp.terminate` directly; it calls a
  quit closure the composition root supplies.
- **D. Menu.** Per W3-8 (`$RES`, "W3-8", step 3 table). Both builds use the same `MainMenu`; only the install point
  differs.
  1. Targets: Import from Arc, Show Archive and Settings target an object the composition root owns (it answers
     `validateMenuItem` from the session), never `AppDelegate` through a nil target. About, Hide, Hide Others, Show All
     and Bring All to Front target `NSApp`. Quit: `terminate:` to `NSApp`, tag `IDC_EXIT` (34031), in the first
     top-level menu. Never a nil-target `showPreferences:`, `orderFrontStandardAboutPanel:` to the delegate,
     `commandDispatch:` app item or `toggleConfirmToQuit:` (AppController answers those with Chromium's behaviour).
  2. Tags: no top-level `IDC_FILE_MENU` (57326), `IDC_TAB_MENU` (57323) or `IDC_HISTORY_MENU` (57324); add a hidden
     top-level item tagged `IDC_BOOKMARKS_MENU` (57333) with an empty submenu, and a test that the built menu has it and
     none of the three (a constant table in the test, values from `$RES` W3-0 Step 5 and W3-8).
  3. Page commands: Reload, Force Reload, Stop, Back, Forward, Find, Find Next, Find Previous, Actual Size, Zoom In,
     Zoom Out, Save Page As (Shift-Cmd-S), Print, View Source, Developer Tools, Inspect Elements, JavaScript Console,
     History, Downloads, as `commandDispatch:` items with a nil target and `tag` = the `EngineCommand` raw value (the
     six without a constant, `EngineCommand(rawValue:)` with the values in `$RES` until a joint pull request names
     them). `ShellWindow` forwards `commandDispatch:` / `validateUserInterfaceItem:` to its host (part A). In the
     FakeEngine build the host executes what FakeEngine supports and disables the rest.
  4. Shell items: add New Window (Cmd-N; the host claims `IDC_NEW_WINDOW` 34000), Close Window (Shift-Cmd-W,
     `performClose:` on `ShellWindow`, which calls `onCloseRequested`), Enter Full Screen (`toggleFullScreen:`),
     Minimize / Zoom (`performMiniaturize:` / `performZoom:`, check they work on the borderless `ShellWindow`), Jump to
     Selection (`centerSelectionInVisibleArea:`). Keep the existing items and keys; Cmd-Left / Cmd-Right are not menu
     keys.
  5. Set `NSApp.servicesMenu` (an App menu Services submenu), `NSApp.windowsMenu` (as today) and `NSApp.helpMenu` (a
     Help menu) every time the menu is installed; Chromium's values point into its own menu after the swap.
  6. Reserved keys: `ShellWindow.performKeyEquivalent(with:)` first checks a `ReservedKeys` value (key code plus
     device-independent modifiers: Cmd-T, Cmd-L, Cmd-W, Shift-Cmd-W, Cmd-N, Cmd-Q, Cmd-Opt-Right, Cmd-Opt-Left) and,
     on a match, returns `NSApp.mainMenu?.performKeyEquivalent(with:)` when that is true; otherwise `super`. Unit tests
     for the matcher (layout-independent key codes, extra modifiers do not match) and a ShellKitGUITests case that a
     focused first responder which swallows key equivalents does not get Cmd-W.
  7. Install: FakeEngine build as today (`AppDelegate`); Engine build from `ArktShellEmbedder` (engine lane,
     `App/Engine/`), which observes `NSApplicationDidFinishLaunchingNotification` and installs the menu one turn later
     (`RunLoop.main.perform`), after AppController's own handler. Never from `engineDidStart`.

**Acceptance criteria:** ShellUI tests cover: an engine-created tab appears as a Today tab only in its own window and is
selected when active; an `.extension` close removes the row once; a `.windowClosing` or `.appTerminating` close leaves
the stored sidebar byte-identical (compare the persisted snapshot before and after; only loaded state changes); a held
Cmd-W keeps the row until `.tabClosed`, and a cancelled one keeps the tab and does not archive; auto-archive skips a
`wouldHoldClose` tab; `activateTab` follows the focused pane in a split; the host claims Cmd-T and Cmd-W and forwards
an unclaimed command; the close button never closes the window directly; no ShellUI call to the window-less
`createTab(url:)` (lint test). The FakeEngine app behaves as before (UI tests and the smoke pass; quit flush intact).

**Verification:** `swift test --skip ShellKitGUITests`, `--filter ShellKitGUITests`, Debug app build and smoke; the
UI test suite where it is required.

**Commit:** one commit per part, files named one by one; "Host engine windows in ShellUI", "Route engine tabs by window
and close reason", "Add the composition root for two engines", "Install the Arkt menu for the engine build".

Time-box: 2.5 days.

---

### Task W3-8: Main menu inventory and owner decision (engine lane inventory, Swift lane implementation)

Steps 1-3 are read-only on `$CR` and need no engine worktree; step 4 waits for W3-9.

**Files:** Modify `$RES` (section "Main menu"); the implementation is W3-7 part D and `app/ArktShell/App/Engine/`.

**Steps:**
1. List every item `chrome::BuildMainMenu` builds (`chrome/browser/ui/cocoa/main_menu_builder.mm`) with its command id,
   tag and shortcut, and, for each, the Arc row in `docs/spec/arc-parity-spec.md` section 1 (same shortcut, other
   action, or none).
2. Every `AppController` and menu-bridge interaction with `NSApp.mainMenu`, in two lists: **lookups** (`itemWithTag:`,
   `fileMenu` at `:835`, `:2240`, History, Profiles, Share bridges), each marked tolerant or not of a missing item; and
   **mutations** (the pre-search block `:812-817`, `updateMenuItemKeyEquivalents` `:2419-2461`, File menu delegate,
   dynamic History and Profiles items), each with what it would do to Arkt's menu. Also `MenuCommandForKeyEvent`
   (`global_keyboard_shortcuts_mac.mm:46-67`) and `confirmQuitIfNeeded`: which tags and actions Arkt's menu must keep.
3. Decide (Decision 9 unless step 2 finds a non-tolerated dependency): the owner; per command: Arkt action, forwarded
   to Chromium, or dropped; the tags Arkt's menus avoid; the reserved-key set for `PreHandleKeyboardEvent`; the install
   point (after launch). Post the decision on #33.
4. After W3-9's first run: for each forwarded command, record whether it reaches the Arkt `Browser` (enabled in the
   menu, `ARKT:` execute log line, observable effect); check that Cmd-W on a page with focus archives (reserved key) and
   that Quit asks for confirmation when Chromium would.

**Acceptance criteria:** both lists and the command table are complete; every command has "reaches the Arkt Browser:
yes/no" and the Arkt mapping; the decision, tags and reserved keys are in `$RES` and on #33.

**Verification:** the item count in the table equals the count of `IDC_` items in `main_menu_builder.mm`
(`git -C $CR grep -c 'IDC_' -- chrome/browser/ui/cocoa/main_menu_builder.mm`, adjusted for non-item uses, recorded);
`git -C $CR grep -n 'mainMenu' -- chrome/browser/app_controller_mac.mm chrome/browser/ui/cocoa` hit count equals the
rows of the two lists; every "reaches" cell cites a log line or an observed effect from W3-9.

**Commit:** `$RES`; "Record the main menu inventory and owner".

**Result (steps 1-3):** `$RES`, "W3-8". Arkt owns the menu; no engine change is needed; the reserved keys live in
`ShellWindow` (Decision 9); a test-only `--arkt-menu-probe` in the self-test embedder measures the conditions.

Time-box: 6 h (inventory) plus 1 h after W3-9.

---

### Task W3-9: Integration: ShellUI on ChromiumEngine, contract runner, smoke (both lanes)

**Depends on:** W3-5, W3-6, W3-7 (all parts), W3-8 step 3.

**Files:**
- Modify: `app/ArktShell/App/Engine/ArktShellEmbedder.swift` (creates `ChromiumEngine`, calls `AppComposition`,
  provides hosts, forwards the quit seams)
- Create: `app/ArktShell/App/Engine/EngineContractRunner.swift` (only with `-ArktEngineContract YES`, Engine
  configuration only; links `EngineAPITestSupport`; launches with `--arkt-engine-test-api`)
- Modify: `$RES`

**Steps:**
1. Contract runner, modelled on `SmokeRunner`: runs rules 1-16 against a fresh `ChromiumEngine` per rule, each in its
   own window. Harness: `pageURL` and `pagesOnTwoHosts` from the loopback fixture server (#170, or the runner's own,
   see Dependencies); `settle` waits for `loadingChanged(false)`; `retitle` through `evaluateScript`; drivers:
   `engineCreateTab` = `window.open(url)` with a user gesture in a tab of that window, `engineCloseTab` =
   `chrome.tabs.remove` through the test extension (`tabs-probe` loaded by the runner) or `window.close()` on a
   script-opened tab, `engineActivate` = `chrome.tabs.update({active:true})`, `holdClose` = set `onbeforeunload` with a
   user gesture (sticky activation), `answerDialog` = `answerDialogInTab:accept:`. Prints one line per rule and exits
   non-zero on any failure or any rule reported not applicable.
2. Smoke on the shell (fresh profile, both probe extensions, CDP port of its own): first window shows the restored
   Space; navigate; `probe.create()` adds a Today tab in that window only and the shown page stays `visible`;
   `tabs.update({active:true})` selects it; `chrome.windows.create` opens a second shell window; the action probe popup
   opens from the sidebar Extensions button (AX, after the checks); Split View with two engine tabs shows both
   `visible`; Cmd-W archives (also with page focus); Cmd-W on a `beforeunload` page shows the dialog on the card and
   archives only after Leave; Find, zoom and developer tools reach the `Browser` (W3-8 step 4).
3. Startup: a cold launch with a URL (the URL as a launch argument, and once through `open -a <app bundle> <url>`) lands in a shell window after readiness; an
   extension that calls `chrome.windows.create` from `runtime.onStartup` lands in a shell window; a Dock reopen with no
   windows opens one.
4. Quit: Cmd-Q, Dock Quit, and `kill -TERM` for the session-ending path (a real logout is not simulated; it would log
   the user out; record it as a maintainer check): with a pending sidebar write,
   relaunch shows the write; the stored sidebar is otherwise unchanged (no Today rows lost); visible tabs got their
   stamp.
5. Web identity on the embedded app (#9): `navigator.userAgent` contains `Chrome/156.0.0.0 Safari/537.36`, no `Arkt`
   in either brand list, no `--user-agent` switch.
6. 120 Hz: the week-1 display-link measurement (week-1 plan Task 5) on the shell card with a live engine page, once
   in a single tab and once with a Split View pane sliding; same gate (at most 1 % of intervals over 8.6 ms), or 16.8 ms
   on a 60 Hz display with a note.

**Acceptance criteria:** the runner passes 16/16 with no rule reported not applicable; every smoke, startup and quit
step passes or is recorded with its log lines as a known gap with an issue; 0 `FATAL`/`Check failed`; no new crash dump
under `Arkt Dev Engine/Crashpad`; the 120 Hz gate holds or is recorded; the FakeEngine build still passes its own
contract and UI tests.

**Verification:** runner output, logs, CDP, window-only screenshots, dump counts, frame statistics.

**Commit:** the embedder and runner files, `$RES`; "Run ShellUI and the engine contract on ChromiumEngine".

Time-box: 2.5 days.

---

### Task W3-10: Infobars from `ContentInfoBarManager`, or a recorded gap (engine lane, Swift lane draws)

**Depends on:** W3-5 (engine), W3-7 (shell).

**Files:**
- Create: `engine/arkt/api/arkt_infobar_bridge.{h,mm}`; modify `arkt_engine.h` (both copies, through a joint pull
  request like W3-2's), `arkt_tab_handle.mm`
- Modify: `ChromiumEngineKit` and `EngineAPI` (an `infobars` list on the snapshot or a small protocol, agreed in that
  pull request); create `ShellUI/Card/InfobarView.swift`

**Steps:** list the infobars Arkt can still show (unsupported command-line flag warning, the automation and
`--no-sandbox` warnings, session-crashed bubble path, any `ConfirmInfoBarDelegate` a feature adds); the facade
observes `infobars::InfoBarManager::Observer` per tab and exposes a plain list (message, buttons, link) with an action
call; the shell draws a native bar above the tab's container. If the time-box ends first: the facade logs
`ARKT: infobar <identifier>` and every infobar is recorded as a gap in #122.

**Acceptance criteria:** launching with an unsupported flag (for example `--no-sandbox` in a throwaway profile) shows
the warning natively above the page with a working close button; or the gap is recorded with the identifier list.

**Verification:** window-only screenshot of the bar; `ARKT: infobar` log lines; ShellUI test for the bar against
`InMemoryEngine`.

**Commit:** files named one by one, plus `$RES`; "Draw engine infobars natively".

Time-box: 1 day.

---

### Task W3-11: Self-contained bundle with the release framework (engine lane)

**Depends on:** #11 and #12 (`out/Arkt` built and signable). If they have not finished by W3-9, this task is deferred
and recorded; development continues on `out/Spike`.

**Files:** Modify `engine/README.md` (section "Embedding in the app": layout, signing order, launch), `$RES`.

**Steps:**
1. Run the `Engine` configuration against `out/Arkt`'s `Arkt Framework.framework` (no dylibs next to the bundle).
2. Sign inside-out with one identity, taking each helper's options and entitlements from Chromium's signing tooling
   (`chrome/installer/mac/signing`: renderer JIT, plugin library validation; `chrome/app/helper-gpu-entitlements.plist`,
   `helper-renderer-entitlements.plist`), including the Crashpad handler in the framework's `Helpers`; then the
   framework; then the app with the hardened runtime. Keep the helpers' sandbox profiles unchanged.
3. `codesign --verify --deep --strict`; run the W3-9 smoke and the #9 checks from the internal disk with a profile
   under `~/Library/Application Support/ArktTest`.
4. Under the hardened runtime: the GPU process is alive and hardware-accelerated (no software-compositing fallback in
   `chrome://gpu`, read over CDP), the log has no seatbelt denials, no renderer or GPU process restarts in 2 minutes.
5. Record the bundle size, the rendezvous service name (`<app bundle id>.MachPortRendezvousServer.<pid>`) and the
   helper and app bundle ids (Risk 9).

**Acceptance criteria:** signed bundle verifies; smoke, identity and hardened-runtime checks pass; no helper `FATAL`.

**Verification:** `codesign --verify --deep --strict --verbose=2` output, `codesign -dv` identifier and runtime lines,
smoke log lines, CDP output (`chrome://gpu` feature status).

**Commit:** `engine/README.md`, `$RES`; "Embed and sign the release framework in the app".

#### Needs the maintainer

Once, after this task: launch the signed app without `--user-data-dir` and without `--use-mock-keychain` (the real
default folder and the "Arkt Safe Storage" item), and report any keychain prompt.

Time-box: 5 h plus the build.

---

### Task W3-12: Results, patch budget, issue updates, housekeeping (engine lane)

**Files:** Modify `$RES`.

**Steps:** fill `$RES` (PASS/FAIL per task with evidence, patch budget with the week-2 commands, known gaps with
issues); kill every PID the track started; check that no engine process remains from `$OUT`, `$EMB` or `/Applications`;
leave test profiles in place; comment the outcome on #33 and on the issues this week touched (#9, #21, #121, #122,
#128, #207); remove `--arkt-native-window` from the Engine configuration if #21 has landed. Merged branches and
worktrees are removed, unmerged ones are kept and listed.

**Verification:** `ps -axo pid,command | grep -E "out/Spike|embed-week3|/Applications/Arkt" | grep -v grep` prints
nothing; `wc -l < $REPO/engine/patches/chromium/.patches` equals `git -C $CR rev-list --count 156.0.8078.48..arkt`.

**Commit:** `$RES`; "Record engine week 3 results".

Time-box: 2 h.

---

## Parallel lanes

| Lane | Sequence | Needs the engine worktree |
|---|---|---|
| Swift (second developer) | W3-7 A, B -> (after W3-3 gate) W3-7 C -> (after W3-8 step 3) W3-7 D -> W3-9 (shell side) -> W3-10 (drawing) | no |
| Engine, no worktree | W3-1, W3-0a (now) -> W3-2 draft -> (after W3-0 lookup) W3-2 freeze -> W3-6 | no |
| Engine, Chromium part | W3-0 (after #18) -> W3-3 (gate) -> W3-4 -> W3-5 -> W3-9 (runs) -> W3-10 -> W3-11 -> W3-12 | yes |
| Read-only | W3-8 steps 1-3 (reads `$CR`, never builds) | no |

- Can start now, before #18 merges: W3-0a, W3-1, W3-2 (draft), W3-7 parts A and B, W3-8 steps 1-3.
- Waits for a gate: W3-2's freeze and W3-6 wait for W3-0a and W3-0's lookup; W3-7 part C waits for W3-3's readiness and
  quit results; everything that builds on Swift concurrency under Chromium waits for W3-0a.
- W3-1 and W3-2 are the two freezes; a change to either after it has merged is a new pull request both lanes approve.
- `project.yml` is touched by W3-0a and W3-3 (engine lane: `Spike`/`Engine`) and possibly W3-7 (Swift lane: sources).
  Announce on the issue before editing it, and keep the `Engine` block in one place.
- Only one `out/Spike` build at a time; Swift builds at `nice -n 20` while it runs.

## Dependencies on open issues

| Issue | Effect on week 3 |
|---|---|
| #18 (W6, pull request #217) | Blocks W3-0 and every engine-worktree task: same files, and extension-created windows need `ArktExtensionsContainer`. Swift-lane tasks and W3-0a are not blocked. |
| #21 (W9, native window default) | Not blocking: the Engine configuration passes `--arkt-native-window` until #21 lands; W3-12 removes it then. |
| #170 (loopback fixture server, pull request #215) | W3-9's harness serves its pages and favicons from it. If it has not merged by then, the runner starts a minimal loopback server of its own (two host names on the loopback address, a title page and a favicon per host). |
| #9 (UA and client hints) | No code dependency; W3-9 and W3-11 repeat the identity checks on the embedded app. |
| #11, #12 (release build, signing) | Gate W3-11 only. |
| #22 (W10 rebuild) | Independent; W3 overlay changes enter the next `out/Arkt` build. Do not run the W10 framework link while W3 builds run (week-2 Capacity). |
| #128 (bundle id, data folder) | W3-3 sets the development `CrProductDirName`; #128 applies the product value (decision 2), the final bundle id (`dev.arkt.Arkt`) to the app, and aligns the branding file's id (Risk 9). |
| #207 (W5b/W5c leftovers) | Menu parity items move into W3-8; tab-modal attachment now attaches to the tab container's window (W3-4). |
| #116 (session restore) | Out of scope; Decision 12's close reasons keep quit from touching the stored sidebar, which #116 builds on. |
| #121, #122 | Stay out of scope except infobars (W3-10); W3-9 records new gaps there. |

## Out of scope (next weeks)

- Session restore of windows and tabs across relaunch (#116); Cmd-N "same Spaces and tabs" and Incognito (#115).
- Popup, app, DevTools and picture-in-picture windows as Arkt windows; Little Arc and Peek; profile-picker mode.
- Native replacements for Views surfaces (#122), extension context menus, pinning, keyboard commands, install sheet
  (#121), find bar (#134), downloads (#132), permission prompts (#133).
- Link-target status pill (#114, needs a seam), crash reporting (#129), notarization (#125).
- Aligning the FakeEngine build's last-window behaviour with the engine build (Decision 13).

## Decisions (maintainer, 2026-10-24)

All six are decided as the plan's defaults (#33); a different answer later is a local change, named in the last column.

| # | Question | Decision | Where a different answer lands |
|---|---|---|---|
| 1 | Framework name | keep `Arkt Framework.framework` (no patch) | branding file or one patch; Swift reads the name from Info.plist (Decision 7) |
| 2 | Product engine data folder | `Arkt/Engine` inside the shell's `Arkt` folder; development uses `Arkt Dev Engine` | one Info.plist key, applied with #128 (Decision 8) |
| 3 | Main menu owner | Arkt's menu, Chromium page commands forwarded (Decision 9) | `App/Engine/` and `MainMenu.swift`; fallback is Chromium's menu with Arkt edits |
| 4 | Engine window for a shell window without tabs (first run, no Space) | create the `Browser` lazily on the first tab | `ShellWindowController` only (when it calls `createWindow`) |
| 5 | `ChromiumEngineKit` owner | engine lane until W3-9 passes, then revisit | ownership table in Rules |
| 6 | Archiving and leave-site prompts | Cmd-W honours them; auto-archive skips tabs that would prompt until the next pass | the `CloseMode` the shell passes, and the auto-archive filter (Decision 11) |
