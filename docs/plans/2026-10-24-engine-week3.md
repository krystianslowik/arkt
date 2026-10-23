# Engine Week 3 Implementation Plan: ChromiumEngine

> Implement this plan task-by-task, with a review checkpoint after each task. Issue: #33.

**Goal:** The shipping Swift app runs on the real engine. `ArktShell.app` (a new `Engine` build configuration) loads
the Chromium framework, hands the process to `ChromeMain`, and the existing ShellUI talks to Chromium only through
ShellKit's `EngineClient`, implemented by a Swift `ChromiumEngine` over an ObjC facade in `//arkt`. ShellUI's own
borderless window and card host the engine's tabs (it becomes the second `ArktWindowHost`), extension-created tabs
land as Today tabs, and `ChromiumEngine` passes the shared `EngineContract`. The FakeEngine dev build is unchanged.

**Architecture:** One process model, three layers, two lanes.

- *Process.* `main.swift` (Engine configuration) does nothing but load `Arkt Framework.framework` (or `Chromium
  Framework` from `out/Spike` in development), register the Swift embedder and call `ChromeMain`, which creates
  `BrowserCrApplication`, owns the run loop and never returns. Chromium's `AppController` is the application
  delegate. Arkt's Swift UI is started by the in-process hook (`ArktBrowserMainExtraParts`) once the browser has
  started, not by `AppDelegate`.
- *Engine side (ObjC++, `//arkt`).* `ArktBrowserWindow` (week 2) keeps one `Browser` per Arkt window and profile. A new
  facade (`ArktEngineFacade`, `ArktBrowserHandle`, `ArktTabHandle`) exposes windows, tabs, navigation, per-tab state
  and extension actions through ObjC protocols declared in one header with no C++ and no Chromium includes.
- *Swift side.* `ChromiumEngineKit` (a ShellKit target) implements `EngineClient` (and the week-3 additions) over those
  protocols. ShellUI never sees the header: it only knows `EngineAPI`. The app's composition root picks FakeEngine or
  ChromiumEngine.

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
| `$EMB` | `$CHROMIUM_ROOT/embed-week3`: the development bundle layout (W3-3), on the Chromium disk |
| `$RES` | `$REPO/docs/plans/2026-10-24-engine-week3-results.md` (created in W3-0) |

- **Two lanes, one owner each.** The engine lane owns `engine/`, the `Engine` configuration in `project.yml`,
  `app/ArktShell/App/Engine/` and the `ChromiumEngineKit` target. The Swift lane owns `EngineAPI`,
  `EngineAPITestSupport`, `FakeEngineKit`, `ShellUI`, `CoreBridge` and the rest of `app/ArktShell/App`. A change to the
  other lane's files goes through that lane's review. The interface between them is the table in "Interface
  boundary"; it changes only by a pull request both lanes approve.
- **Engine worktree.** Only the engine lane uses `$REPO` and builds `out/Spike`. It starts after #18 (pull request
  #217) has merged and its worktree is released: #18 edits `arkt_browser_window.{h,mm}`, the extensions files,
  `arkt_browser_main_extra_parts.mm` and `BUILD.gn`, which W3-3 to W3-5 also edit.
- **Swift builds.** While a Chromium build runs, at most two Swift builds, at `nice -n 20` (week-2 Capacity). Swift-lane
  tasks run `swift test` and the Debug app build only; they never need a Chromium build.
- **FakeEngine build unchanged.** Every task that touches `project.yml`, `main.swift` or the composition root checks that
  the `Debug` build still has `NSPrincipalClass = NSApplication` and contains no engine code
  (`strings <Debug app binary> | grep -c "ARKT engine"` prints `0`), as Task WE did.
- **Development bundle.** `out/Spike` is a component build: the framework must be a real directory inside the app and
  the 518 component dylibs must sit next to the app bundle (Task WE, Run B). The `Engine` configuration builds into
  `$EMB` and copies the framework only when it changed (W3-3). Expect about 110 s of system scanning on the first launch
  after each fresh copy; warm launches reach the hook in about 3 s.
- **Launching the app on the engine.** Same flags as week 2 (`--user-data-dir` under `$PROF`, `--use-mock-keychain`,
  `--no-first-run`, `--no-default-browser-check`, `--enable-logging=stderr`), PID from `$!`, killed by PID. Each run
  uses its own profile and CDP port, and moves its window clear of other apps under test right after launch
  (week-2 results, "Interference").
- **Contract runs.** `ChromiumEngine` is checked twice: in `swift test` against a scripted facade (W3-6, no
  Chromium), and in the app against the real engine (W3-9, the contract runner).
- **No personal paths, ids or names** in code, docs, logs that are committed, commits or pull requests.

## Decisions fixed for this track

1. **Handshake without exported symbols.** The framework links with `chrome/app/framework.exports`, which keeps only
   `_ChromeMain` (and a few others) global; every other symbol, `//arkt` included, is hidden. So nothing in Swift links
   against or `dlsym`s a facade symbol. Instead both sides meet through the Objective-C runtime, which registers every
   class of a loaded image whatever its linker visibility:
   - The Swift app defines `@objc(ArktShellEmbedder) final class` conforming to the ObjC protocol `ArktEngineEmbedder`
     (in the main executable, `app/ArktShell/App/Engine/`).
   - The hook (`ArktBrowserMainExtraParts`) calls `NSClassFromString(@"ArktShellEmbedder")`. Present: it creates the
     facade and calls `-engineDidStart:` on the embedder. Absent (the GN-built `Chromium.app`, every week-2 check): it
     keeps today's behaviour, the placeholder host, so engine-lane checks never need the Swift app.
   - Swift receives the facade as `any ArktEngine` (a protocol), never by class name.
   Patch cost: 0. Fallback if W3-3 shows the class lookup fails: one patch adding an entry function to
   `framework.exports` (1 upstream file, 0 hot-file hunks).
2. **The shell creates the windows.** The Engine configuration appends `--no-startup-window`
   (`startup_browser_creator.cc:346`, `:1001`, `:1173`) to `argv` before `ChromeMain`, unless the caller passed it, so
   Chromium creates no startup `Browser` and no session-restore window; Arkt owns tab persistence (#116). Windows then
   come from two places, both ending in an Arkt window with a ShellUI host:
   - *Shell-initiated* (launch, Cmd-N): Swift builds its `ShellWindowController`, then asks the engine for a `Browser`
     in that window (`createWindow(host:)`); the facade creates the `Browser` with the host already chosen.
   - *Engine-initiated* (`chrome.windows.create`, `window.open` into a new window, Dock reopen through
     `AppController`, links opened from other apps): the factory override asks the embedder for a host synchronously. The
     Swift provider may only build the window and return its host; it must not call the engine until the posted
     `windowOpened` event (Chromium is inside `Browser` construction).
   Until #21 lands, the Engine configuration also appends `--arkt-native-window`.
3. **Threading.** On macOS Chromium's browser UI thread is the main thread (`MessagePumpNSApplication`), so
   `MainActor` and the UI thread are the same thread. The header marks every protocol `NS_SWIFT_UI_ACTOR`; the facade
   `DCHECK_CURRENTLY_ON(content::BrowserThread::UI)` on entry. The facade never calls into Swift from inside a Chromium
   notification (`TabStripModelObserver`, `WebContentsObserver`): it records plain-value events and delivers them in one
   batch from a posted task (`base::SequencedTaskRunner::GetCurrentDefault()->PostTask`), in order. That keeps Swift
   handlers free to call back into the model (close, navigate, activate) without tripping `TabStripModel`'s reentrancy
   checks or destroying a `WebContents` inside its own observer. W3-3 verifies that Swift's main-actor executor runs
   under Chromium's pump (a `Task { @MainActor in }` with `Task.sleep` resumes), because `EngineContract` relies on it.
4. **Synchronous parts of the contract stay in Swift.** Contract rule 1 (`.tabCreated` before anything else, visible
   right after `createTab` returns) and rule 4 (`closeTab` is terminal at once) need synchronous answers, while engine
   events arrive one task later (Decision 3). `ChromiumEngine` therefore emits `.tabCreated` itself when the facade's
   `createTab` returns the new handle, and `.tabClosed` itself in `closeTab`, through `EngineEventHub`, and drops the
   matching facade events. Tabs the engine creates on its own (extensions, `window.open`) are announced when their
   facade event arrives. `snapshot(of:)`, `tabIDs` and `contentView(for:)` read Swift-side tables kept current from
   facade events, as FakeEngine does.
5. **Tab identity.** A `TabID` maps to one `ArktTabHandle`, which wraps a `tabs::TabInterface` (stable across
   `TabStripModelChange::kReplaced` and across a move between windows through `DetachTabAtForInsertion`). The Chromium
   session id (what `chrome.tabs` reports) is a property of the handle that can change on replacement; it is never the
   Swift identity.
6. **One stable container per tab; the host mounts.** Each `ArktTabHandle` owns an Arkt `NSView` container. The current
   `WebContents` native view fills it; on `kReplaced` the facade swaps the subview, so `contentView(for:)` keeps its
   identity. For ShellUI hosts `ArktBrowserWindow` stops mounting the active tab in `cardView`; the shell puts
   containers in its card (one, or two to four in Split View) and removes them, and visibility still follows the view
   hierarchy (week-2 Decision 3). The `TabStripModel` active index follows the shell's focused tab (focused pane in a
   split) through `activateTab`, so extension `active` flags stay true. The placeholder host keeps auto-mounting.
   Tab-modal dialogs use the tab's container as their `WebContentsModalDialogHost` view; `GetContentsSize` reports the
   focused container's size.
7. **Framework name: keep `Arkt Framework.framework`.** #33 asks for a name distinct from the `app/ArktCore` package;
   the name the branding file already produces (`PRODUCT_FULLNAME=Arkt`, `chrome/BUILD.gn:489`,
   `chrome_constants.cc:83`) is distinct and costs no patch. A different name ("Arkt Engine") needs either a different
   `PRODUCT_FULLNAME` (renames helpers too) or one patch; open question 1.
8. **User data directory without a patch.** `chrome_paths_mac.mm:26-69` reads `CrProductDirName` from the *outer* app's
   Info.plist (`base::apple::OuterBundle()`), falling back to `Chromium`. The Engine configuration sets it, so the
   default profile lives under `~/Library/Application Support/<CrProductDirName>`. Proposed value `Arkt/Engine`, next to
   the shell's database folder `Arkt` (`DatabaseLocation.applicationSupport()`) without mixing Chromium's `Local State`
   and `Default/` into it (open question 2; #128 applies the final bundle id and folder). Crash reports follow the
   default user data directory, so engine-config runs count dumps under that folder, not under `Chromium/Crashpad`.
   Test launches still always pass `--user-data-dir`.
9. **Main menu owner (proposed): Arkt.** Arc's defaults collide with Chromium's on about ten shortcuts (Cmd-T opens the
   command bar, Cmd-W archives, Cmd-S toggles the sidebar, Cmd-D pins, Cmd-Opt-Left/Right switch Spaces, Cmd-L,
   Cmd-Shift-D, Cmd-Y; `docs/spec/arc-parity-spec.md` section 1), and Arkt has menus Chromium lacks (Spaces, Archive).
   Proposal: after `AppController` has built Chromium's menu, the shell installs its own `MainMenu` (extended); page
   commands that are Chromium's (zoom, print, save as, find, developer tools, view source, history, downloads) are
   Arkt items that send `commandDispatch:` with the `IDC_*` tag, which the ShellUI host forwards to
   `chrome::ExecuteCommandWithDisposition` (week-2 W5b/W5c). `AppController` stays the application delegate (quit,
   Dock menu, reopen, URL open events). W3-8 confirms this with an inventory before W3-7 wires it; the risk is
   `AppController` code that looks up its own menu items by tag (History, Profiles), which W3-8 checks for nil-safety.
10. **Extension surfaces stay engine-drawn this week.** The action list comes from `ToolbarActionsModel` through the
    facade as plain values (id, name, 16 pt icon PNG, enabled); running an action passes the shell's anchor `NSView`,
    and the popup is the existing `PopoverExtensionView` anchored to it. Extension-created windows follow Decision 2.
    Context menus, pinning, keyboard commands and the native install sheet stay in #121.

## Interface boundary (Swift lane vs engine lane)

The second developer owns the Swift lane. These are the only artifacts that cross the boundary; each is frozen by an
early task so both lanes can work in parallel.

| Artifact | Owner | Consumer | Frozen in |
|---|---|---|---|
| `EngineAPI` additions: windows, activation, tab origin, engine-initiated closes, `EngineWindowHosting`, `EngineExtensions` (below) and contract rules 9-13 | Swift lane | engine lane (`ChromiumEngine`) | W3-1 |
| `InMemoryEngine` and `FakeEngine` implementing the additions | Swift lane | ShellUI tests, the FakeEngine app | W3-1 |
| `engine/arkt/api/arkt_engine.h`: ObjC protocols `ArktEngineEmbedder`, `ArktEngine`, `ArktBrowserHandle`, `ArktTabHandle`, `ArktWindowHostDelegate`, event value classes; no C++, no Chromium includes | engine lane | `ChromiumEngineKit` only (isolation test) | W3-2 |
| `ChromiumEngineKit` (`ChromiumEngine: EngineClient, EngineExtensions`) | engine lane | composition root only | W3-6 |
| Composition entry `AppComposition.start(engine:windowHostProvider:)` and `AppComposition.prepareToTerminate() async` | Swift lane | `ArktShellEmbedder` (engine lane) | W3-7 |
| `ShellWindowController` as `EngineWindowHosting` (window, card, command forwarding, close request) | Swift lane | `ChromiumEngine` | W3-7 |

**Proposed `EngineAPI` additions** (W3-1 settles names; all additive, existing call sites keep compiling):

- `EngineWindowID` (opaque, `Hashable, Sendable`); `var windowIDs: [EngineWindowID]`;
  `func createWindow(host: any EngineWindowHosting) -> EngineWindowID`; `func closeWindow(_:)`.
- `func createTab(url: URL?, in window: EngineWindowID) -> TabID`; the existing `createTab(url:)` uses the most recently
  active window (engines with one implicit window behave as today).
- `func activateTab(_ id: TabID)`; `func activeTab(in window: EngineWindowID) -> TabID?`.
- `TabSnapshot` gains `window: EngineWindowID?`, `opener: TabID?`, `origin: TabOrigin` (`.client` for tabs this client
  created, `.engine` for tabs an extension or a page created) and `isActive: Bool`, all with defaults.
- `EngineEvent` gains `.activeTabChanged(TabID)` (the window is in the snapshot). `.tabCreated(TabID)` keeps its shape;
  the snapshot is readable when it is delivered.
- Window events on their own stream (an `EngineEvent` always has a tab):
  `observeWindows(_ handler: @MainActor (EngineWindowEvent) -> Void) -> EngineObservation` with
  `.windowOpened(EngineWindowID)`, `.windowClosed(EngineWindowID)`, `.extensionActionsChanged(EngineWindowID)`.
- `EngineWindowHosting` (`@MainActor` protocol, AppKit types only): `window: NSWindow`, `cardView: NSView`,
  `onCloseRequested`, `validateCommand(_ id: Int) -> Bool?` and `executeCommand(_ id: Int, disposition: Int) -> Bool`
  hooks the host calls before forwarding (so the shell can claim Arc commands), and a `forwardCommand` sink the engine
  sets. The host must not close its window itself; the engine closes the `Browser`, then reports `.windowClosed`.
- `EngineWindowHostProvider`: `@MainActor (EngineWindowRequest) -> any EngineWindowHosting` for engine-initiated windows
  (Decision 2); must not call the engine.
- `EngineExtensions` (separate protocol; FakeEngine does not adopt it, the shell checks `engine as? EngineExtensions`):
  `extensionActions(in:) -> [ExtensionAction]` (`id`, `name`, `iconPNG: Data?`, `isEnabled`),
  `runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView)`.

**New contract rules** (in `EngineAPITestSupport/EngineContract.swift`, run by every engine):

9. A window from `createWindow(host:)` is listed in `windowIDs` and announced with `.windowOpened`; every tab's
   snapshot names its window; `closeWindow` closes its tabs (`.tabClosed` each) and then reports `.windowClosed`.
10. `activateTab` makes the tab its window's active tab: `.activeTabChanged(id)` and `isActive` in the snapshot, with
    exactly one active tab per window that has tabs.
11. A tab the engine creates on its own is announced with `.tabCreated` and its snapshot has `origin == .engine`, its
    window, its opener (when there is one) and `isActive`; an engine-side activation is announced with
    `.activeTabChanged`.
12. A tab the engine closes on its own (`chrome.tabs.remove`, `window.close()`) ends with one `.tabClosed`, exactly as
    a `closeTab` does (rule 4).
13. `createTab(url:)` without a window lands in the most recently active window.

`InMemoryEngine` gains test drivers for engine-side behaviour (`engineCreateTab(in:opener:active:)`,
`engineCloseTab(_:)`, `engineActivate(_:)`), so ShellUI tests cover rules 11 and 12 without Chromium.

## What the Swift side (shell) needs

- Treat `.tabCreated` with `origin == .engine` as a new Today tab in the Space shown in that window (selected when the
  snapshot says `isActive`), and `.activeTabChanged` from the engine as a selection change.
- Handle `.tabClosed` it did not ask for (today `ShellWindowController` only sees closes it caused).
- Mount `contentView(for:)` containers and remove them; never assume one mounted tab per window (Split View).
- Call `activateTab` when the focused tab or pane changes.
- Be an `EngineWindowHosting`: `ShellWindow` forwards `commandDispatch:`, `commandDispatchUsingKeyModifiers:` and
  `validateUserInterfaceItem:` (the W5b note: without them every Chromium menu command is disabled for the window),
  routes its close button through `onCloseRequested`, and claims the Arc commands it implements before forwarding.
- Start from `AppComposition.start` (FakeEngine: `AppDelegate`; engine: `ArktShellEmbedder`), and flush the database
  from `AppComposition.prepareToTerminate()` (engine: called from the hook at quit, W3-7).
- An Extensions control in the sidebar when `engine is EngineExtensions`.

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001-0006 | week 2 (hook, draw, keychain, factory hook, tab features, dialogs) | exist | 13 | 0 |
| - | Handshake (Decision 1) | ObjC runtime lookup, no patch; fallback 1 patch (`chrome/app/framework.exports`) | 0 (1) | 0 |
| - | Framework name (Decision 7) | no patch unless open question 1 asks for another name | 0 (1-2) | 0 |
| - | User data directory (Decision 8), `--no-startup-window` (Decision 2) | Info.plist key and argv, no patch | 0 | 0 |
| - | Facade, host mode, infobars, menu routing | overlay only | 0 | 0 |

Projection after week 3: 6 patch files, 13 upstream files, 0 hot-file hunks; at worst 8 patch files and 15 upstream
files if both fallbacks are taken. Not this week (recorded so it is not mistaken for scope): the link-target status pill
(#114) needs a seam for `BrowserWebContentsDelegate::UpdateTargetURL`, whose status bubbles must stay empty (W5a).
`$RES` keeps the table current with the week-2 commands.

## Risks

1. **Main-actor executor under Chromium's pump.** Swift concurrency's main executor relies on the main dispatch queue
   being drained by the run loop. If `MessagePumpNSApplication` does not service it, `Task.sleep` on the main actor never
   resumes and neither the contract runner nor ShellUI's async launch works. Checked first, in W3-3 (go/no-go for the
   approach).
2. **Event order versus the contract.** Rule 2 (title before load end) and rule 6 (favicon cleared before load end on a
   host change) depend on the order of `TitleWasSet`, `DidFinishNavigation`, `DidStopLoading` and favicon callbacks.
   FakeEngine needed a bounded title wait (`titleTimeout`). The facade emits per-tab events in Chromium's order and
   `ChromiumEngine` reorders only within one batch, with the same bounded wait if W3-9 shows it is needed.
3. **Reentrancy.** A Swift handler that closes a tab or window must never run inside a Chromium notification
   (Decision 3). Window creation is the one synchronous call into Swift (the host provider); it must not call the
   engine. Both are asserted: the facade `CHECK`s that no facade call arrives while it is inside a notification.
4. **Shell window versus Chromium expectations.** `ShellWindow` is borderless with its own traffic lights and key
   handling. Chromium calls `toggleFullScreen:`, reads occlusion, and offers unhandled page keys to `NSApp.mainMenu`
   (`HandleKeyboardEvent`). The command bar's key handling must coexist with pages that have focus. Checked in W3-9.
5. **AppController is the delegate.** `applicationDidFinishLaunching`, `applicationShouldTerminate` (`.terminateLater`
   flush), Dock reopen and URL open events belong to `AppController`. The hook must give the shell a start point and a
   quit point that can wait for the database flush without blocking the main thread (`ScopedKeepAlive` held until the
   flush completes). W3-7 implements, W3-9 verifies quit with pending writes.
6. **Profile loading with `--no-startup-window`.** The facade needs a loaded `Profile` when the shell asks for its
   first window. If the last-used profile is not loaded yet at `PostBrowserStart`, `createWindow` waits for it
   (`ProfileManager` async load) and reports the window later. Checked in W3-4.
7. **Development loop cost.** Each fresh framework copy costs about 110 s of scanning; the 518 dylibs (678 MB) next to
   the bundle cost disk. W3-3 copies only on change and clones (`cp -c`) on the Chromium disk.
8. **Menu takeover.** Replacing `NSApp.mainMenu` may break `AppController` code that expects its own items. W3-8
   decides with evidence; the fallback is Chromium's menu with Arkt edits.
9. **Interference.** Other apps under test share the screen (week-2 "Interference"): own profile, own port, window
   moved clear, AX input only after the frontmost and key-window checks.

---

### Task W3-0: Engine worktree, baselines, results file (engine lane)

**Depends on:** #18 merged (pull request #217) and its worktree released.

**Files:** Create `$RES`.

**Steps:**
1. `git worktree add ../arkt-wt/engine-week3 -b engine/33-chromium-engine origin/main`; repoint `$CR/arkt` (week-2 W0
   Step 1, never while a build runs); `readlink $CR/arkt` equals `$REPO/engine/arkt`.
2. `git -C $CR rev-list --count 156.0.8078.48..arkt` equals `wc -l < $REPO/engine/patches/chromium/.patches` (6); hot-file
   hunks 0 (week-2 command).
3. Incremental `out/Spike` build; W5c Step 3 (visibility) and the W6 identity check pass on the placeholder path with
   `--arkt-native-window` (or without it if #21 has landed).
4. Swift baselines (any worktree): `cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests` and
   `cd app/ArktCore && swift test` test counts, recorded as the baseline for "baseline + N".
5. `$RES`: header, task table W3-0..W3-12 (all `TODO`), the patch budget table above, the baselines.

**Verification:** `$RES` holds the counts and command outputs; no leftover processes.

**Commit:** `git add docs/plans/2026-10-24-engine-week3-results.md`; "Engine week 3 baseline and results file".

Time-box: 1.5 h.

---

### Task W3-1: `EngineAPI` additions and contract rules 9-13 (Swift lane)

No Chromium. Can start at once.

**Files:**
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPI/EngineClient.swift` (and new files beside it for windows,
  hosting, extensions)
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPI/EngineEventHub.swift` (window stream; same non-reentrant FIFO)
- Modify: `app/ArktShell/ShellKit/Sources/EngineAPITestSupport/{EngineContract,InMemoryEngine,EventRecorder}.swift`
- Modify: `app/ArktShell/ShellKit/Sources/FakeEngineKit/FakeEngine.swift` (one implicit window per `createWindow`,
  WKWebView tabs created by pages stay out of scope: FakeEngine reports `origin == .client` only)
- Modify: `app/ArktShell/ShellKit/Tests/EngineAPITests/*`, `Tests/FakeEngineKitTests/*`

**Steps:** write rules 9-13 as `EngineContract` functions first (failing against `InMemoryEngine`), then implement in
`InMemoryEngine` (with the engine-side test drivers) and `FakeEngine`. Shapes as in "Interface boundary"; W3-1's pull
request is where both lanes agree on names. Keep every existing call site compiling (additive API, defaults).

**Acceptance criteria:** rules 1-13 pass for `InMemoryEngine`; rules 1-10 and 13 for `FakeEngine` (11 and 12 are
engine-initiated; FakeEngine documents them as not applicable); `EngineEventHub` tests cover the window stream;
the engine lane has approved the pull request.

**Verification:** `swift test --skip ShellKitGUITests` (baseline + N); FakeEngine GUI contract tests
(`--filter ShellKitGUITests`) still pass.

Time-box: 1 day.

---

### Task W3-2: The facade header and its Swift module (engine lane; no build)

Needs no engine worktree: the header is authored and syntax-checked anywhere; GN compiles it in W3-3.

**Files:**
- Create: `engine/arkt/api/arkt_engine.h` (ObjC only: `Foundation`, `AppKit`)
- Create: `app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h` (a byte-identical copy) and
  `module.modulemap`
- Modify: `app/ArktShell/ShellKit/Package.swift` (C target `ArktEngineABI`, no sources besides the header)
- Modify: `app/ArktShell/ShellKit/Tests/IsolationTests/` (new `EngineABIIsolationTests.swift`)

**Contents of the header:**
- `ArktEngineEmbedder` (implemented in Swift): `+sharedEmbedder`, `-engineDidStart:(id<ArktEngine>)`,
  `-hostForEngineWindowRequest:(ArktWindowRequest*)` returning `id<ArktWindowHostDelegate>`, `-engineWillTerminate:`
  with a completion block.
- `ArktEngine`: `browsers`, `createBrowserWithHost:`, `extensionActionsForBrowser:`,
  `runExtensionAction:inBrowser:anchor:`, `addEventSink:` (batched events), test-only `evaluateScript:inTab:completion:`.
- `ArktBrowserHandle`: `windowId` (session id), `tabs`, `activeTab`, `createTabWithURL:active:`, `close`.
- `ArktTabHandle`: `containerView`, `sessionId`, `url`, `title`, `faviconPNG`, `isLoading`, `canGoBack`, `canGoForward`,
  `opener`, `navigateToURL:`, `reload`, `goBack`, `goForward`, `activate`, `close`, `focus`.
- `ArktWindowHostDelegate` (what the engine needs from a host; the week-2 `ArktWindowHost` minus the placeholder's
  `activateTab`): `window`, `cardView`, `closeRequested`, `validateCommand`, `executeCommand`.
- Event value classes (`ArktEngineEvent`: kind, tab handle, browser handle, plain values), all `NS_SWIFT_UI_ACTOR`,
  nullability annotated, `NS_SWIFT_NAME` where the Swift name should differ.

**Acceptance criteria:** the header compiles standalone as Objective-C and Objective-C++
(`clang -fsyntax-only -fobjc-arc -x objective-c` and `-x objective-c++`, with `-isysroot $(xcrun --show-sdk-path)`);
`grep -E '#include|namespace|std::|template'` finds nothing; the isolation test fails if any target other than
`ChromiumEngineKit` imports `ArktEngineABI`, and fails if the two header copies differ (it reads both files, like
`WebKitIsolationTests` reads sources).

**Verification:** both `clang` commands exit 0; `swift build` and `swift test --filter IsolationTests` pass.

Time-box: 4 h.

---

### Task W3-3: Engine configuration, embedder handshake and the main-actor probe (engine lane; GATE)

**Depends on:** W3-0, W3-2.

**Files:**
- Modify: `app/ArktShell/project.yml` (configuration `Engine` replaces `Spike`: Swift flag `ARKT_CHROMIUM_ENGINE`,
  `ARKT_PRINCIPAL_CLASS: BrowserCrApplication`, hardened runtime off for development, `ENABLE_DEBUG_DYLIB: NO`,
  Info.plist keys `ArktEngineFrameworkName`, `ArktEngineFrameworkVersion`, `CrProductDirName`; a run-script phase,
  only in `Engine`, that copies the framework when it changed and writes the two framework keys from the framework's
  own `Info.plist` and `Versions/Current`, never from literals)
- Create: `app/ArktShell/App/Engine/EngineMain.swift` (replaces `ChromiumSpikeMain.swift`), `ArktShellEmbedder.swift`
- Modify: `app/ArktShell/App/main.swift` (`#if ARKT_CHROMIUM_ENGINE`: `engineMain()` and nothing else)
- Modify: `engine/arkt/browser/arkt_browser_main_extra_parts.mm`, `BUILD.gn` (new `arkt_embedder.{h,mm}`: class lookup,
  `engineDidStart:` from `PostBrowserStart`, terminate callback)
- Local only (gitignored): an xcconfig naming the engine output directory (`ARKT_ENGINE_OUT`), so no path is committed

**Steps:**
1. `EngineMain.swift`: read the two keys from `Bundle.main`, build the versioned path as `chrome_exe_main_mac.cc`
   does, `dlopen(RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST)`, append `--no-startup-window` and (until #21)
   `--arkt-native-window` to a copy of `argv` when absent, call `ChromeMain`, `exit` with its status. Nothing touches
   `NSApplication` before `ChromeMain`.
2. `ArktShellEmbedder` (`@objc(ArktShellEmbedder)`, conforms to `ArktEngineEmbedder`): this task only logs
   `ARKT embedder: engine started <n> browsers` and runs the probe: `Task { @MainActor in try await Task.sleep(for:
   .milliseconds(200)); log("ARKT embedder: main actor resumed") }`, plus one `DispatchQueue.main.async` log line.
3. Hook: `NSClassFromString(@"ArktShellEmbedder")`; when present and conforming, create `ArktEngineFacade` (empty for
   now) and call `engineDidStart:`; log `ARKT: embedder found` or `ARKT: no embedder`.
4. Build `out/Spike`; build the `Engine` configuration into `$EMB` (`nice -n 20` if a Chromium build runs); clone the
   component dylibs next to the bundle once (`cp -c`, same volume).

**Acceptance criteria (GATE):** launched from `$EMB` with a fresh profile under `$PROF`: `ARKT: embedder found`,
`ARKT embedder: engine started 0 browsers` (no startup window), both probe lines within 2 s of the hook, process alive
30 s, 0 `FATAL`/`Check failed`. `out/Spike/Chromium.app` logs `ARKT: no embedder` and the W5c checks still pass.
`Debug` app unchanged (Rules). The profile folder is the one passed with `--user-data-dir`; a launch without it (one
time, with `--use-mock-keychain`) creates `~/Library/Application Support/<CrProductDirName>`, recorded and then left
for the maintainer (never deleted by the task).

If the probe line `main actor resumed` never appears: stop, record, and raise it with the maintainer before W3-4
(Risk 1; the alternative is driving Swift work only from posted engine callbacks, which changes W3-6 and W3-9). If the
class lookup fails: take the Decision 1 fallback patch and record it in the budget.

**Commit:** project, app and overlay files named one by one, plus `$RES`; "Embed the engine in the Engine
configuration and register the Swift embedder".

Time-box: 1 day (including one fresh-copy launch at about 110 s).

---

### Task W3-4: Host mode for ShellUI windows (engine lane)

**Depends on:** W3-3.

**Files:**
- Modify: `engine/arkt/browser/arkt_browser_window.{h,mm}`, `arkt_browser_window_parts.{h,mm}` (modal host per tab
  container), `arkt_browser_main_extra_parts.mm` (factory: embedder host first, placeholder otherwise)
- Create: `engine/arkt/api/arkt_engine_facade.{h,mm}` (browser part: `createBrowserWithHost:`, `browsers`, window
  events), `engine/arkt/api/BUILD.gn` (or a source set in `//arkt/browser`)

**Steps:**
1. `createBrowserWithHost:` creates a `TYPE_NORMAL` `Browser` for the last-used profile (waiting for its load if
   needed, Risk 6) with the host chosen up front; the factory override uses it.
2. Engine-initiated `TYPE_NORMAL` browsers ask `-hostForEngineWindowRequest:`; no embedder or a nil host: the
   placeholder host (week-2 behaviour).
3. Host mode: no auto-mount for embedder hosts (Decision 6); `GetContentsSize` and the modal dialog host follow the
   focused tab's container; `closeRequested` closes the `Browser`; the facade reports `windowOpened` / `windowClosed`
   from posted tasks (Decision 3).
4. A self-test embedder inside the overlay, behind `--arkt-facade-selftest` (an ObjC class used only when the switch is
   present and no Swift embedder exists): it supplies plain `NSWindow` hosts and logs every facade event as
   `ARKT selftest <event>`. This is how the engine lane checks W3-4 and W3-5 on `Chromium.app` without the Swift app.

**Acceptance criteria:** with `--arkt-facade-selftest`: a shell-initiated window opens (`windowOpened`, census
`normal=1 arkt=1 views=0`); `chrome.windows.create` from the tabs probe asks the provider and opens a second host
window (`normal=2 arkt=2 views=0`); closing a host window closes its `Browser` (`windowClosed`, `native window
destroyed`); Dock-style reopen (`chrome::NewEmptyWindow` via a debug switch) lands in a provider window. Without the
switch every W5b row re-run in W3-0 still passes.

**Verification:** logs and census lines; CDP `chrome.windows.getAll` ids equal the facade's window ids; window-only
screenshots.

Time-box: 1 day.

---

### Task W3-5: Tab facade: handles, containers, state, extension actions (engine lane)

**Depends on:** W3-4.

**Files:**
- Modify/create: `engine/arkt/api/arkt_engine_facade.{h,mm}`, `engine/arkt/api/arkt_tab_handle.{h,mm}`
  (`tabs::TabInterface` wrapper, `WebContentsObserver`, `favicon::FaviconDriverObserver`, container view)
- Modify: `engine/arkt/browser/arkt_browser_window.mm` (tab list feeds the facade), `arkt_extensions_menu.{h,mm}`
  (action list and run-with-anchor for the facade; the sidebar placeholder keeps its menu)

**Steps:**
1. `ArktTabHandle` per `TabInterface`, created on insertion, kept across `kReplaced` and cross-window moves (Decision 5);
   container `NSView` with the current `WebContents` view as its only subview, swapped on replacement; `focus` makes
   the contents first responder.
2. Per-tab state from `WebContentsObserver` (`DidStartLoading`, `DidStopLoading`, `DidFinishNavigation`,
   `TitleWasSet`, `NavigationEntryCommitted` for back/forward availability) and `FaviconDriverObserver` (PNG bytes;
   cleared on a committed navigation to another host before that load ends). Events carry plain values, in Chromium's
   order, posted in batches.
3. Calls: `createTabWithURL:active:` (`chrome::AddTabAt`), `navigateToURL:`, `reload`, `goBack`, `goForward`,
   `activate` (`ActivateTabAt`), `close` (`CloseWebContentsAt`, user-gesture close type), opener from
   `TabInterface`/`WebContents::GetOpener`, origin flag (created through the facade or not).
4. Extension actions: list (id, name, 16 pt icon rasterized as in W4, enabled) per browser, change events, run with an
   anchor view (popover anchored to it).
5. Test-only `evaluateScript:inTab:completion:` (compiled in only for the contract runner's switch).

**Acceptance criteria (self-test embedder):** the W5c sequence (`probe.create()`, `tabs.update` activation both ways)
produces `tabCreated` with `origin=engine`, `activeTabChanged`, and `visibilityState` as in W5c when the self-test host
mounts containers; a navigation logs url, loading start, title, loading end in that order; a host change logs the
favicon clear before load end; `chrome://crash` then reload keeps the same container (no new handle); the action list
equals `--arkt-extensions-menu-dump`'s items; running action-probe logs `popup loaded` anchored to the self-test view.

**Verification:** logs, CDP, window-only screenshots; `gn check out/Spike '//arkt/*'`.

Time-box: 1.5 days.

---

### Task W3-6: `ChromiumEngineKit` over the facade, tested against a scripted facade (engine lane, Swift)

**Depends on:** W3-1, W3-2. Needs no engine worktree; runs in parallel with W3-3 to W3-5.

**Files:**
- Create: `app/ArktShell/ShellKit/Sources/ChromiumEngineKit/ChromiumEngine.swift` (+ small helpers)
- Create: `app/ArktShell/ShellKit/Tests/ChromiumEngineKitTests/` (a scripted Swift implementation of the
  `ArktEngine`/`ArktBrowserHandle`/`ArktTabHandle` protocols that delivers batches on the next main-actor turn, like the
  real facade; contract tests 1-13 against it)
- Modify: `Package.swift`, `Tests/IsolationTests/` (only the app's composition root may import `ChromiumEngineKit`)

**Steps:** map `TabID` to tab handles and `EngineWindowID` to browser handles; synchronous `.tabCreated` / `.tabClosed`
for client calls with deduplication of the facade's later events (Decision 4); snapshots from events; window stream;
`EngineWindowHosting` wrapped into an `ArktWindowHostDelegate` object; `EngineExtensions` over the action calls.

**Acceptance criteria:** contract rules 1-13 pass against the scripted facade, including a script that reorders title
and load end within one batch and one that replaces a tab's contents; isolation tests pass; no `@unchecked Sendable`
or `nonisolated(unsafe)`.

**Verification:** `swift test --skip ShellKitGUITests` (baseline + N).

Time-box: 1.5 days.

---

### Task W3-7: The shell as engine host, and a composition root for two engines (Swift lane)

**Depends on:** W3-1 (W3-8's decision for the menu part; the rest can start before it).

**Files:**
- Modify: `ShellUI/Window/ShellWindowController*.swift`, `ShellUI/Window/ShellWindow.swift` (hosting, command
  forwarding, engine-initiated tabs and closes, `activateTab` on focus changes, Split View mounting through
  `contentView(for:)`)
- Create: `ShellUI/Sidebar/ExtensionsButton.swift` (shown when `engine is EngineExtensions`)
- Create: `app/ArktShell/App/AppComposition.swift`; modify `AppDelegate.swift`, `AppSession.swift`, `MainMenu.swift`
- Tests: `ShellUITests`, `ShellKitGUITests` against `InMemoryEngine` (engine drivers from W3-1)

**Steps:**
1. `ShellWindowController` conforms to `EngineWindowHosting`; `ShellWindow` forwards the three command selectors;
   the close button calls `onCloseRequested`; Arc commands (`IDC_NEW_TAB` to the command bar, `IDC_CLOSE_TAB` to
   archive or close, and the others in the W3-8 table) are claimed before forwarding.
2. Engine-created tabs become Today tabs in the window's current Space; engine activations select the row; engine
   closes clear the card and the row state.
3. `AppComposition.start(engine:windowHostProvider:)` holds what `AppDelegate.launch()` does today (data folder, load,
   `AppSession`), and `prepareToTerminate()` holds the `.terminateLater` flush; `AppDelegate` calls both for FakeEngine.
4. Menu per W3-8.

**Acceptance criteria:** ShellUI tests cover: an engine-created tab appears as a Today tab and is selected when active;
an engine close removes it once; `activateTab` follows the focused pane in a split; the host claims Cmd-T and Cmd-W
and forwards an unclaimed command id; the close button never closes the window directly. The FakeEngine app behaves as
before (UI tests and the smoke pass).

**Verification:** `swift test --skip ShellKitGUITests`, `--filter ShellKitGUITests`, Debug app build and smoke; the
UI test suite where it is required.

Time-box: 2 days.

---

### Task W3-8: Main menu inventory and owner decision (engine lane inventory, Swift lane implementation)

The inventory is read-only on `$CR` and needs no engine worktree; the runtime column waits for W3-9.

**Files:** Modify `$RES` (section "Main menu"); the implementation is in W3-7 (`MainMenu.swift`) and
`app/ArktShell/App/Engine/` (installing the menu after `AppController` built its own).

**Steps:**
1. List every item `chrome::BuildMainMenu` builds (`chrome/browser/ui/cocoa/main_menu_builder.mm`) with its command id
   and shortcut, and, for each, the Arc row in `docs/spec/arc-parity-spec.md` section 1 (same shortcut, other action,
   or none).
2. Read `app_controller_mac.mm` and the menu bridges (History, Profiles, Share) for lookups of their own items
   (`itemWithTag:`, `mainMenu` walks) and record whether each tolerates a missing item.
3. Decide (Decision 9 unless step 2 finds a non-tolerated lookup): the owner, and per command: Arkt action, forwarded
   to Chromium, or dropped.
4. After W3-9's first run: for each forwarded command, record whether it reaches the Arkt `Browser` (enabled in the
   menu, `ARKT:` execute log line, observable effect).

**Acceptance criteria:** the table covers every Chromium menu command with "reaches the Arkt Browser: yes/no" and the
Arkt mapping; the decision and its evidence are in `$RES` and on #33.

Time-box: 4 h (inventory) plus 1 h after W3-9.

---

### Task W3-9: Integration: ShellUI on ChromiumEngine, contract runner, smoke (both lanes)

**Depends on:** W3-5, W3-6, W3-7.

**Files:**
- Modify: `app/ArktShell/App/Engine/ArktShellEmbedder.swift` (creates `ChromiumEngine`, calls `AppComposition.start`,
  provides hosts, forwards terminate)
- Create: `app/ArktShell/App/Engine/EngineContractRunner.swift` (only with `-ArktEngineContract YES`, Engine
  configuration only; links `EngineAPITestSupport`)
- Modify: `$RES`

**Steps:**
1. Contract runner, modelled on `SmokeRunner`: runs `EngineContract` rules 1-13 against a fresh `ChromiumEngine` per
   rule, each in its own window; `pageURL` and `pagesOnTwoHosts` from the loopback fixture server of #170 (two host
   names on the loopback address, favicons served); `settle` waits for `loadingChanged(false)`; `retitle` uses the
   facade's test-only script call. Prints one line per rule and exits non-zero on any failure.
2. Smoke on the shell (fresh profile, both probe extensions, CDP port of its own): first window shows the restored
   Space; navigate; `probe.create()` adds a Today tab and the shown page stays `visible`; `tabs.update({active:true})`
   selects it in the sidebar; `chrome.windows.create` opens a second shell window; the action probe popup opens from
   the sidebar Extensions button (AX, after the frontmost and key-window checks); Split View with two engine tabs shows
   both `visible`; Cmd-W archives; Find, zoom and developer tools reach the `Browser` (W3-8 step 4); quit with a pending
   sidebar write flushes it (relaunch shows it).
3. Web identity on the embedded app (#9): `navigator.userAgent` contains `Chrome/156.0.0.0 Safari/537.36`, no `Arkt`
   in either brand list, no `--user-agent` switch.

**Acceptance criteria:** the runner passes 13/13 on the engine; every smoke step passes or is recorded with its log
lines as a known gap with an issue; 0 `FATAL`/`Check failed`; no new crash dump in the engine configuration's crash
folder; the FakeEngine build still passes its own contract and UI tests.

**Verification:** runner output, logs, CDP, window-only screenshots, dump counts.

Time-box: 2 days.

---

### Task W3-10: Infobars from `ContentInfoBarManager`, or a recorded gap (engine lane, Swift lane draws)

**Depends on:** W3-5 (engine), W3-7 (shell).

**Steps:** list the infobars Arkt can still show (unsupported command-line flag warning, the automation and
`--no-sandbox` warnings, session-crashed bubble path, any `ConfirmInfoBarDelegate` a feature adds); the facade
observes `infobars::InfoBarManager::Observer` per tab and exposes a plain list (message, buttons, link) with an
action call; the shell draws a native bar above the tab's container. If the time-box ends first: the facade logs
`ARKT: infobar <identifier>` and every infobar is recorded as a gap in #122.

**Acceptance criteria:** launching with an unsupported flag (for example `--no-sandbox` in a throwaway profile) shows the
warning natively above the page with a working close button; or the gap is recorded with the identifier list.

Time-box: 1 day.

---

### Task W3-11: Self-contained bundle with the release framework (engine lane)

**Depends on:** #11 and #12 (`out/Arkt` built and signable). If they have not finished by W3-9, this task is deferred
and recorded; development continues on `out/Spike`.

**Steps:** run the `Engine` configuration against `out/Arkt`'s `Arkt Framework.framework` (no dylibs next to the
bundle), sign inside-out with one identity (helpers with their entitlements, framework, app; hardened runtime on),
`codesign --verify --deep --strict`, run the W3-9 smoke and the #9 checks from the internal disk with a profile under
`~/Library/Application Support/ArktTest`. Record the bundle size and the rendezvous service name
(`<app bundle id>.MachPortRendezvousServer.<pid>` in the log).

**Acceptance criteria:** signed bundle verifies; smoke and identity checks pass; no helper `FATAL`.

Time-box: 4 h plus the build.

---

### Task W3-12: Results, patch budget, issue updates, housekeeping (engine lane)

**Steps:** fill `$RES` (PASS/FAIL per task with evidence, patch budget with the week-2 commands, known gaps with
issues); kill every PID the track started; check that no engine process remains from `$OUT`, `$EMB` or `/Applications`;
leave test profiles in place; comment the outcome on #33 and on the issues this week touched (#9, #21, #121, #122,
#128, #207). Merged branches and worktrees are removed, unmerged ones are kept and listed.

Time-box: 2 h.

---

## Parallel lanes

| Lane | Sequence | Needs the engine worktree |
|---|---|---|
| Swift (second developer) | W3-1 -> W3-7 (menu part after W3-8 step 3) -> W3-9 (shell side) -> W3-10 (drawing) | no |
| Engine, Swift part | W3-2 -> W3-6 (any time after W3-1 and W3-2) | no |
| Engine, Chromium part | W3-0 (after #18) -> W3-3 (gate) -> W3-4 -> W3-5 -> W3-9 (runs) -> W3-10 -> W3-11 -> W3-12 | yes |
| Read-only | W3-8 steps 1-3 (reads `$CR`, never builds) | no |

- Without the engine worktree: W3-1, W3-2, W3-6, W3-7, W3-8 steps 1-3. These can all start now, before #18 merges.
- W3-1 and W3-2 are the two freezes; W3-6 and W3-7 code against them. A change to either after it has merged is a new
  pull request both lanes approve.
- `project.yml` is touched by W3-3 (engine lane: the `Engine` configuration) and possibly W3-7 (Swift lane: sources).
  Announce on the issue before editing it, and keep the `Engine` block in one place.
- Only one `out/Spike` build at a time; Swift builds at `nice -n 20` while it runs.

## Dependencies on open issues

| Issue | Effect on week 3 |
|---|---|
| #18 (W6, pull request #217) | Blocks W3-0 and every engine-worktree task: same files, and extension-created windows need `ArktExtensionsContainer`. Swift-lane tasks are not blocked. |
| #21 (W9, native window default) | Not blocking: the Engine configuration passes `--arkt-native-window` until #21 lands; W3-12 removes it then. #21's patch 0002 test is independent. |
| #9 (UA and client hints) | No code dependency; W3-9 and W3-11 repeat the identity checks on the embedded app. |
| #11, #12 (release build, signing) | Gate W3-11 only. |
| #22 (W10 rebuild) | Independent; W3 overlay changes enter the next `out/Arkt` build. Do not run the W10 framework link while W3 builds run (week-2 Capacity). |
| #128 (bundle id, data folder) | W3-3 sets `CrProductDirName` in the Engine configuration; #128 applies the final bundle id (`dev.arkt.Arkt`) to the app and the branding file. Rendezvous name and keychain item follow the bundle id; W3-11 records them. |
| #207 (W5b/W5c leftovers) | Menu parity items move into W3-8; tab-modal attachment now attaches to the tab container's window (W3-4). |
| #121, #122 | Stay out of scope except infobars (W3-10); W3-9 records new gaps there. |

## Out of scope (next weeks)

- Session restore of windows and tabs across relaunch (#116); Cmd-N "same Spaces and tabs" and Incognito (#115).
- Popup, app, DevTools and picture-in-picture windows as Arkt windows; Little Arc and Peek.
- Native replacements for Views surfaces (#122), extension context menus, pinning, keyboard commands, install sheet
  (#121), find bar (#134), downloads (#132), permission prompts (#133).
- Link-target status pill (#114, needs a seam), crash reporting (#129), notarization (#125).

## Open questions (for the maintainer)

1. Framework name: keep `Arkt Framework.framework` (no patch, Decision 7), or rename (one patch or a different
   `PRODUCT_FULLNAME`, which also renames the helpers users see in Activity Monitor)?
2. Engine data folder: `CrProductDirName = Arkt/Engine` (inside the shell's `Arkt` folder) or a sibling such as
   `Arkt Engine`? It must be fixed before the first build a user relies on, with #128.
3. Main menu owner: Arkt's menu with Chromium commands forwarded (Decision 9), unless W3-8 finds `AppController`
   needs its own items?
4. Should a shell-initiated window without any Space (first run) still create an engine `Browser` at once, or only when
   the first tab is shown? (Affects whether extensions see a window with zero tabs.)
5. Ownership of `ChromiumEngineKit`: engine lane (this plan), or Swift lane once W3-9 has passed?
