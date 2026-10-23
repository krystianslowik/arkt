# Week-1 results

## Track A: engine spike

| Task | Result | Notes |
|---|---|---|
| 1 Baseline build | PASS | Chromium 156.0.8078.48 component build (~75k objects); launches and renders headless. Fixes: LiteRT LFS skip, removed enable_nacl, Xcode Metal toolchain. |
| 2 Engine overlay + patch workflow | PASS | `engine/README.md`; reviewed twice, data-loss paths in export/apply fixed. |
| 3 In-process hook | PASS | `arkt::ArktBrowserMainExtraParts::PostBrowserStart` logs `ARKT: in-process hook alive` ~7 s after launch. Registered in `ChromeBrowserMainParts::Create` (`chrome/browser/chrome_browser_main.cc`, Mac block after `ChromeBrowserMainExtraPartsMac`), not `chrome_content_browser_client.cc` (no `AddParts` there at 156). Dep: `//chrome/browser:core` -> `//arkt/browser` -> `//chrome/browser:main_extra_parts`. Patch 0001; incremental build 38 s. |
| 4 Page content in our AppKit layout | PASS | 6/6 items pass; needed patch 0002 (content) plus two fixes in our code. See "Task 4 details". |
| 5 120 Hz page container animation | PASS | ProMotion (built-in XDR, maxFPS 120). Gated runs at load1 7.9-8.6 < 10 cores: video 5/5 runs 0 of 1199 intervals over 8.6 ms, static 0 of 240; max 8.33 ms. See "Task 5 details". |
| 6 Extension install, action and popup | PASS | uBO Lite installed via Chrome Web Store + default Views prompt; action listed from our code; popup in an NSPopover on our sidebar button; mode change works and persists. No upstream patch. See "Task 6 details". |
| 7 Extension APIs see our tabs | PASS | tabs-probe SW: `ARKT tabs.query count=2 active=1` with 2 tabs open; the active tab is the one shown in our window. See "Task 7 details". |
| 8 1Password desktop integration | PENDING (needs user) | Bundle signed (Apple Development) and verified. macOS privacy prompts (keychain, removable volume) must be accepted once; extension install and the 1Password "Add Browser" step are in the user steps below. See "Task 8". |

### Task 4 details

Active tab's `WebContentsViewCocoa` moved into an Arkt `NSWindow` (190 pt sidebar placeholder, inset card with a
10 pt corner radius). Test page: local `file://` page with a link, an `<input>`, a 4000 px tall block. Real input came from
cliclick and CGEvent scroll-wheel events. The test checked that Chromium was frontmost before every step. Results
were read back over CDP (`--remote-debugging-port`) and checked against `screencapture -l<window>` screenshots.

| Item | Result | Evidence |
|---|---|---|
| Page renders in the rounded card, 190 pt from the left | PASS | viewport 1200x880 = 1400-190-10 x 900-20; screenshot shows the card at x=190 with rounded corners |
| Link click navigates | PASS | click on "GO TO PAGE B" -> `b.html`, title `ArktB`, screenshot shows page B |
| Typing in a page text field | PASS | `activeElement` = `inp`, value `hello arkt` (exactly once, after the double-key fix) |
| Scrolling | PASS | 10 wheel events: `scrollY` 0 -> 2000, screenshot shows the lower gradient |
| Cmd-C / Cmd-V in the page | PASS | page selection + real Cmd-C -> system pasteboard `COPYME123`; real Cmd-V into the input -> `COPYME123` |
| Resizing our window resizes the page | PASS | window 1400x900 -> 1000x700: viewport 800x680, page fills the card |

Symbols at 156: `BrowserList`/`chrome::FindLastActive` are gone. The code uses
`GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser()` (`BrowserWindowInterface*`),
`GetTabStripModel()->GetActiveWebContents()`, `GetWindow()->GetNativeWindow().GetNativeNSWindow()`, and
`WebContents::GetNativeView().GetNativeNSView()`. The mount runs from a task posted in `PostBrowserStart`, retrying
every 250 ms (max 40 tries). It succeeded on the first try.

What it took, in order of discovery:
1. **Order of operations.** `orderOut:` on Chrome's window after the reparent makes Chrome's view host mark the
   view hidden (page `visibilityState` "hidden", blank card). Now Chrome's window is hidden first, then the view is
   moved and `hidden = NO` is set.
2. **Detach from Views.** Under Chrome views the RWHV draws into the Chrome widget's `ui::Layer`
   (`SetParentUiLayer(views_host_->GetUiLayer())`), i.e. into the hidden Chrome window. Calling
   `ViewsHostableDetach()` on the view's `ViewsHostableView` switches `BrowserCompositorMac` to `HasOwnCompositor`.
3. **Patch 0002 (content).** `RenderWidgetHostViewMac::SetParentUiLayer()` calls `DisableDisplay()` the first time
   a view is Views-hosted. That *permanently* drops the NSView's `DisplayCALayerTree`. The compositor ran (a CDP
   screenshot had the full page) but nothing reached the NSView. Fix: new `EnableDisplay()` on the
   `RenderWidgetHostNSView` mojom/bridge, called on `SetParentUiLayer(nullptr)`. The re-created tree's flipped child
   layer must be sized to the current bounds (it only autoresizes correctly when created at 0x0; without this it sat
   at 0x61 off-view).
4. **Double keys (focus risk, section 9.6 risk 1).** `makeFirstResponder:` on the `RenderWidgetHostViewCocoa`
   worked straight away (keys reach the page). But each printable key arrived twice. Chrome sends unconsumed
   RawKeyDowns back through `BrowserNativeWidgetMac::HandleKeyboardEvent` -> `CommandDispatcher
   redispatchKeyEvent:`. That retargets the event at Chrome's hidden window, and `[NSApp sendEvent:]` delivers it to
   the key window, which is ours. Fixed in our code: `ArktWindow` drops key events whose `windowNumber` is not its
   own and offers Cmd-key ones to the main menu, as CommandDispatcher does for redispatches. Cmd-C/V go through
   that path.

Known hazards, deferred: Chrome's `NativeViewHostMac` still holds the hostable pointer. A later BrowserView layout,
tab switch or window close may push bounds or visibility onto our view or detach it again. The clean release is
from the Views side (the contents `WebView` drops the WebContents). The unhandled-key path still goes through the
hidden Chrome browser window; the native `BrowserWindow` (week 2+) replaces both. Patch 0002 changes behaviour for all
Views-hosted web content on Mac: stock Chrome also calls `SetParentUiLayer(nullptr)` on every detach (tab switch,
WebContents swap), which now re-creates the Cocoa display tree. Only the Arkt mount path was tested; the stale
content race the original comment cites (crbug 845807) is unverified on the stock path. `_webContents` is a
`raw_ptr` that dangles if the tab closes while our window is open. Test harness note: right after
programmatic activation the first click was once swallowed; a second click focused the field.

### Task 5 details

The card slides 300 pt right and back, with a `CASpringAnimation` on `transform.translation.x`: damping ratio 1.0,
response 0.35 s (stiffness (2*pi/0.35)^2, damping 4*pi/0.35, settling 0.6 s per leg). A display link
(`-[NSView displayLinkWithTarget:selector:]`, `preferredFrameRateRange` 120) records timestamps for 2 s. Triggers:
Ctrl-Opt-A (local monitor, as planned) and a launch switch, `--arkt-animate-runs=N`. The switch was used for every
measurement, so no synthetic input was needed. Each run also logs the peak on-screen offset (presentation layer)
and `load1`/cores. The gate is asserted only when load1 < cores.

Display: built-in Liquid Retina XDR, `NSScreen.maximumFramesPerSecond` = 120. Test pages: local VP9 1080p60
`testsrc2` video (autoplay, muted, loop) and a static text page.

| Session | load1 / cores | frames (2 s) | max_ms | over_8_6ms | Gate |
|---|---|---|---|---|---|
| Video, run 1-5 | 8.63, 8.50, 8.50, 8.46, 8.46 / 10 | 240, 240, 239, 240, 240 | 8.33 | 0, 0, 0, 0, 0 | asserted: PASS |
| Static, run 1 | 7.89 / 10 | 240 | 8.33 | 0 | asserted: PASS |
| Video, earlier (busy machine) | 14.9-17.4 / 10 | 239-240 | 8.33 | 0 | recorded only |

Every run reached a peak offset of 299.9 pt, so the slide was on screen. Video playback was confirmed over CDP in
the same page in earlier sessions (playing, 1458 frames decoded, 0 dropped). The CDP check was left out of the
gated sessions to keep them quiet. Visual check: 45 back-to-back `screencapture -l` shots across 3 slides on the
video page. Mid-slide frames show the card shifted up to about 300 pt with the video intact, rounded corners kept,
and no tearing or blank page. In that screenshot session one run had a 20.8 ms interval, from the capture load,
which is why the gated runs take no screenshots.

Limit of the measurement: the display-link timestamps show that our main thread and Core Animation keep a 120 Hz
cadence during the slide. They do not prove that every Chromium content frame was presented on time. The page
moves as a layer, so it slides even if a page frame is late. A per-frame check of Chromium presentation (e.g.
compositor frame timing or Instruments) is a follow-up if the go/no-go needs it.

### Task 6 details

Symbols at 156 (all present): `ToolbarActionsModel::Get(profile)` / `actions_initialized()` / `action_ids()`,
`extensions::ExtensionActionRunner::RunAction(extension, grant_tab_permissions)`,
`ExtensionAction::GetPopupUrl(tab_id)`, `extensions::ExtensionViewHostFactory::CreatePopupHost(extension, url,
BrowserWindowInterface*)`, `extensions::ExtensionView` (the per-platform view interface of `ExtensionViewHost`),
and `ExtensionInstallPrompt`. `ExtensionActionViewModel` is the Views-side controller. It was not needed: the bridge
does what a toolbar click does (`RunAction` with activeTab grant), then hosts the popup itself.

| Step | Result | Evidence |
|---|---|---|
| Install uBO Lite with Chrome's default UI | PASS | Our window loaded the CWS detail page. The Google consent interstitial was rejected over CDP. "Add to Chrome" was clicked over CDP with `userGesture`. Chrome's Views prompt appeared ("Add "uBlock Origin Lite"? Read and change all your data on all websites"). It was accepted with one guarded click (Chromium frontmost, the prompt the main window, click point inside its bounds). Result: service worker `chrome-extension://ddkjiahejlhfcafbddmgiahcphecmpfh/js/background.js` running, CWS button now "Remove from Chrome". |
| List extension actions from our code | PASS | `ARKT: toolbar actions 1` / `ARKT action ddkjiahejlhfcafbddmgiahcphecmpfh uBlock Origin Lite` |
| Popup in an NSPopover on our placeholder button | PASS | `ARKT: opening popup chrome-extension://.../popup.html`, `popup loaded`. Auto-resize drove the popover to 273x374. Screenshot: uBO Lite popup (example.com, filtering mode) anchored to the "Extensions" button in our sidebar. |
| Popup toggle works | PASS | Trusted mouse events sent over CDP (`Input.dispatchMouseEvent`) to the popup's slider level 0 changed the mode for example.com from "optimal" to "no filtering". After a relaunch, the reopened popup still shows "no filtering" (screenshot). |
| Placeholder button opens the popup | PASS | AXPress on our `NSButton` "Extensions" -> second `opening popup` + `popup loaded` |

Implementation (`engine/arkt/browser/arkt_extensions_bridge.{h,mm}`):
- `PopoverExtensionView` implements `extensions::ExtensionView`. It owns the `ExtensionViewHost`, puts
  `host_contents()`'s NSView in an `NSPopover`, enables renderer auto-resize (`kExtensionPopupMinSize`/`MaxSize`) in
  `RenderFrameCreated`, follows `ResizeDueToAutoResize`, and shows the popover in `OnLoaded`.
- A fresh popup `WebContents` was never Views-hosted, so it draws into its NSView without patch 0002.
- `--arkt-extensions-demo=<id>|list` runs the list and popup without input.

Notes:
- The Views install prompt draws a dark band over its title (its parent browser window is hidden). It still works.
  A native install sheet is week 3.
- Popup keyboard events: `HandleKeyboardEvent` returns false (no unhandled-key routing yet).
- `NSPopoverBehaviorApplicationDefined` keeps the popup open for testing. Transient dismissal is UI work for later.
- The Views AX tree of the install prompt exposed no children to System Events (Chromium enables it lazily). That is
  why the prompt took one guarded coordinate click rather than an AXPress.

### Task 7 details

`engine/test-extensions/tabs-probe` (manifest and `sw.js` exactly as planned), loaded with `--load-extension`. This
works as-is in this Chromium build; no feature flag was needed. Two tabs were opened (`b.html`, `a.html`) and the
active one (`b.html`) was mounted in our window. The service worker console reached the browser log through
`--enable-logging=stderr`:

    INFO:CONSOLE:2] "ARKT tabs.query count=2 active=1", source: chrome-extension://pdkpbcbonpfldpgkpmkndjnnnjbplhad/sw.js (2)

Cross-check from the service worker over DevTools (`chrome.tabs.query({})`):
`[[..425, window ..424, active, "b.html", "ArktB"], [..426, window ..424, inactive, "a.html", "ArktA"]]`. Our
window shows page B (screenshot). Note for week 2+: extensions see our tab inside Chrome's (hidden) browser window,
whose `windowId` is ..424. With a native `BrowserWindow`, `windows.*` and `tabs.*` window ids must map to Arkt windows.

### Task 8: 1Password (extension installed, desktop connection blocked; needs the user)

#### What is done

- **Signed** `out/Spike/Chromium.app` with `$SIGNING_IDENTITY` (an Apple Development identity)
  (TeamIdentifier `$TEAM_ID`), hardened runtime. This is a component build: the app loads 518 dylibs from `out/Spike/`
  (rpath `@loader_path/../../../../../..`), so those are signed with the same identity too (library validation).
  The bundle was signed inside-out, like Chrome's own signing, not with `--deep`: Renderer/GPU helpers with
  `chrome/app/helper-{renderer,gpu}-entitlements.plist` (`allow-jit`), other helpers without entitlements, the
  framework, then the app with `chrome/app/app-entitlements.plist`.
  - `codesign --verify --deep --strict --verbose=2` -> `valid on disk`, `satisfies its Designated Requirement`.
  - `spctl -a -vv` -> `rejected, origin=Apple Development: ...` (expected: Apple Development is not for
    distribution; 1Password checks the code signature, not Gatekeeper).
  - Designated requirement: `identifier "org.chromium.Chromium" and anchor apple generic and certificate
    leaf[subject.CN] = "$SIGNING_IDENTITY" ...`.
  - Any rebuild replaces relinked binaries with ad-hoc ones: re-run the signing block below after building.
- **Native messaging (read-only check).** Chrome's `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
  com.1password.1password.json` exists. Its host is `/Applications/1Password.app/Contents/Library/LoginItems/1Password
  Browser Helper.app/Contents/MacOS/1Password-BrowserSupport` and its `allowed_origins` already include the Web Store
  1Password extension `aeblfdkhhhdcdjpifhhbdiojplfjncoa`. Our Chromium reads per-user manifests from
  `<user-data-dir>/NativeMessagingHosts/` (`chrome::DIR_USER_NATIVE_MESSAGING` = `DIR_USER_DATA` +
  `NativeMessagingHosts`, `chrome/common/chrome_paths.cc`), plus the system-wide
  `/Library/Application Support/Chromium/NativeMessagingHosts/` (absent). With a dedicated `--user-data-dir`, the
  manifest only needs a copy inside that test profile; no real user directory is touched.
  (`~/Library/Application Support/Chromium/NativeMessagingHosts/` exists, but only holds an unrelated manifest, and
  is only used with the default profile location.)
- **Privacy prompts.** macOS privacy prompts (keychain, removable volume) must be accepted once. After that the
  signed build behaves normally: startup in about 1 s, example.com renders in the Arkt card
  (window screenshot), and the Web Store's "Add to Chrome" is enabled. The pending TCC prompts were the root cause of
  the earlier no-frames / disabled-button / GPU-timeout behaviour.
- **Test profile** `$CHROMIUM_ROOT/profiles/1password-test`, with a copy of Chrome's
  `com.1password.1password.json` in its `NativeMessagingHosts/`.
- **1Password extension installed** from the Web Store (`aeblfdkhhhdcdjpifhhbdiojplfjncoa`, 8.12.42.36) at
  11:21:21. The user did the consent page and the "Add to Chrome" / "Add extension" clicks in the window. The toast
  said "has been added to Chromium", and the store button now says "Remove from Chrome".
- **Native messaging works.** The background worker launches `1Password-BrowserSupport` from the copied manifest
  and gets an answer from it:

      [AppIntegration] Received Modern Notification:<BrowserVerificationFailed> from the native core
      [AppIntegration] Disconnected from Desktop app due to UnknownBrowser

  1Password's own log (`.../1Password/Data/logs`, no vault data) shows why. It cannot read our code signature at
  all; it never gets as far as an untrusted-browser check:

      Verifying browser "$CHROMIUM_ROOT/chromium/src/out/Spike/Chromium.app/Contents/MacOS/Chromium"
      [swift] ProcessValidation.swift:97: codeSignature(for:) Failed to grab code signature for <pid> - status 100001
      [1P:.../browser_verification/apple.rs:53] parent browser was not valid
      Browser support error: UnsupportedBrowser, happened in: .../browser_verification/apple.rs:61

  For Arc, the same path goes straight on to `XPC connected to 2BUA8C4S2C.com.1password.browser-helper`. Our
  signature is fine from our side: `codesign --verify -v <pid>` -> `dynamically valid`, `valid on disk`,
  `satisfies its Designated Requirement`. Possible causes (unverified; the unified log is not readable from the
  build session):
  (a) `1Password-BrowserSupport` is a background helper that reads the browser executable on the external disk holding `$CHROMIUM_ROOT`. macOS
  treats that disk as a removable volume (Chromium itself had to ask). The helper cannot show the TCC prompt, so the
  read is silently denied.
  (b) 1Password refuses to inspect browsers it does not know until they are added under Settings > Browser.
- **Popup in the Arkt window.** `--arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa` lists the action
  (`ARKT action aeblfdkhhhdcdjpifhhbdiojplfjncoa 1Password – Password Manager`), opens
  `chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup/index.html` in the NSPopover (600x450), and logs
  `popup loaded`. The popup shows only the 1Password logo splash, with no text or buttons. A CDP capture of the
  popup's renderer shows the same frame, so the popover draws what the page draws. Reloading the popup after the
  background had initialized gave the same splash. That fits a disconnected extension with no account. It is not a
  hosting bug.
- **Findings for later (not fixed now):**
  - Pages an extension opens (1Password's welcome page `app/app.html#/page/welcome`) land in Chrome's own browser
    window, which shows up with a tab strip and omnibox. Same root as the Task 7 note: extensions see Chrome's
    window. Week 2+ must route `chrome.tabs.create` and extension pages into Arkt.
  - While that happens, the Arkt card goes black. Reproduced: opening any new tab in Chrome's window makes our
    mounted tab `document.visibilityState == "hidden"`, so the page draws no frames. Closing the tab brings it back
    to `visible`. The card follows Chrome's active tab, not ours.
  - The sidebar "Extensions" button is hard-wired to uBO Lite (`arkt_browser_main_extra_parts.mm`, `kUBlockLiteId`).
    In the 1Password profile it logs `extension not installed ddkjiahejlhfcafbddmgiahcphecmpfh`. Only the
    `--arkt-extensions-demo=<id>` flag opens the 1Password popup.

#### Steps for the user

Steps 1, 2 and 4 of the earlier list are done (privacy prompts accepted, profile and manifest in place, extension
installed). Left:

1. **Trust the browser in 1Password.** Open and unlock 1Password > Settings > **Browser** > **Add Browser**. In the
   file picker press Cmd-Shift-G, paste `$CHROMIUM_ROOT/chromium/src/out/Spike/Chromium.app`, choose
   it, and authorize when asked. If it refuses the external-disk path, try this link instead:

       ln -s $CHROMIUM_ROOT/chromium/src/out/Spike/Chromium.app "/Applications/Arkt Spike.app"

   Note the exact message if 1Password rejects both.
2. **Open the popup:**

       $CHROMIUM_ROOT/chromium/src/out/Spike/Chromium.app/Contents/MacOS/Chromium \
         --user-data-dir=$CHROMIUM_ROOT/profiles/1password-test --use-mock-keychain \
         --no-first-run --no-default-browser-check --enable-logging=stderr \
         --arkt-extensions-demo=aeblfdkhhhdcdjpifhhbdiojplfjncoa https://example.com \
         2>&1 | tee $CHROMIUM_ROOT/profiles/1password-popup.log

   - **PASS:** the popup shows your account(s) and offers to unlock with Touch ID / the app, or it is already
     unlocked.
   - **FAIL:** still the logo splash, or a sign-in form asking for the Secret Key. Do not sign in there.
3. **If it still fails, check signature access.** Run:

       grep -hE "Verifying browser|code signature|Browser support error" ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/Library/Application\ Support/1Password/Data/logs/*.log | tail -8

   If it still says `Failed to grab code signature ... status 100001`, try cause (a): System Settings > Privacy &
   Security > Files and Folders (or Full Disk Access) > enable **1Password** / "1Password Browser Helper" if listed,
   quit 1Password completely, reopen it, and repeat step 2. If that does not help, the build has to run from the
   internal disk. That needs a non-component (`is_component_build=false`) build copied to /Applications, which is
   contributor work.
4. **Send back:** PASS/FAIL, a screenshot of the popup, the exact 1Password message from step 1, and the output
   of the grep in step 3.

#### Re-signing after a rebuild

Run in `$CHROMIUM_ROOT/chromium/src/out/Spike` (no keychain prompt; about 1 min):

    ID=$SIGNING_IDENTITY; ENT=../../chrome/app
    F="Chromium.app/Contents/Frameworks/Chromium Framework.framework/Versions/Current"
    ls *.dylib | xargs -P 8 -n 20 codesign --force --sign $ID
    for b in "$F"/Helpers/chrome_crashpad_handler "$F"/Helpers/app_mode_loader "$F"/Helpers/web_app_shortcut_copier; do codesign --force --sign $ID --options runtime "$b"; done
    for h in "$F"/Helpers/*.app; do case "$h" in *Renderer*) e="--entitlements $ENT/helper-renderer-entitlements.plist";; *GPU*) e="--entitlements $ENT/helper-gpu-entitlements.plist";; *) e="";; esac; codesign --force --sign $ID --options runtime ${=e} "$h"; done
    codesign --force --sign $ID "Chromium.app/Contents/Frameworks/Chromium Framework.framework"
    codesign --force --sign $ID --options runtime --entitlements $ENT/app-entitlements.plist Chromium.app
    codesign --verify --deep --strict --verbose=2 Chromium.app

## Track B: sidebar model and Arc import

| Task | Result | Notes |
|---|---|---|
| B1 Package scaffold | PASS | `app/ArktCore` |
| B2 Decoding helpers | PASS | 15 tests; review fixes: non-object enum bodies throw, exact Int64, Sendable, duplicate keys throw |
| B3 Sidebar model | PASS | 19 tests; move index convention, destination validation, TabItem/FolderItem/SplitItem |
| B4 Decode StorableSidebar.json | PASS | Review caught item bodies having no `_0` wrapper; per-item failure isolation. Real file decodes all spaces, items and tabs (counts only) |
| B6 Favicon lookup | PASS | md5(itemID) file names |
| B5 Importer | PASS | Every Arc item is accounted for (container, imported, or skipped with reason); unreachable sweep; per-key container fallback |
| B7 Real-file import check | PASS | Read-only CLI, counts only: nothing skipped |

### B7 real-file check

`swift run -j 2 arkt-import-check` against the real `StorableSidebar.json` (read-only, counts only):

```
spaces: N (report: N)
favorites: tabs N, folders N, splits N
pinned: tabs N, folders N, splits N
today: tabs N, folders N, splits N
imported totals (report): tabs N, folders N, splits N
skipped: 0
warnings: 0
favicons (imported tabs): found N, missing N
```

Consistent with data-model doc 1.2. Section counts sum to the report totals. Favicon coverage is over imported tabs, by Arc item id.

## Track D: persistence and archive

| Task | Result | Notes |
|---|---|---|
| D1a Node snapshots | PASS | |
| D1b Storage format | PASS | depth cap is a model invariant |
| D2a GRDB store | PASS | GRDB 7.11.1 exact |
| D2b Backups + launch | PASS | review caught a backup-retention data-loss path and corruption misclassification; both fixed |
| D3 Autosaver | PASS | 500 ms debounce, bounded 1 s flush, needsFlush for termination |
| D4a Archive model | PASS | origin section recorded |
| D4b Auto-archive policy | PASS | Arc thresholds, BH-cited |
| D5a Arc archive import | PASS | lossy per entry; stable ids for non-UUID keys |
| D4c Archive store | PASS | STRICT table, section columns, conflict policy (.replace for app, .keepExisting for re-import), readable paging |
| D5b Real-file archive check | PASS | counts only: all but a few entries imported, 0 warnings |
| D6 Archive settings | PASS | 12 h tabs / 6 h Little Arc, per-profile with Default inheritance, v3-settings STRICT |

### D5b real-file archive check

`swift run -j 2 arkt-import-check` against the real `StorableArchiveItems.json` (read-only, counts only; the sidebar
lines printed before these are omitted here):

```
archive entries: N
archive imported: N (manual N, auto N)
archive sources: space N, little arc N, unknown N
archive skipped: N
  decodeFailed: N
archive warnings: 0
```

Same order of magnitude as data-model 2.2. No warnings: no
archived folder named children (`archivedFolderChildrenDropped` 0), every `space` source mapped to an imported
Space, every reason was known. The unknown sources are Arc's own `unknown` case, not unmapped Spaces. The
`decodeFailed` entries are the only losses (under 1 %); their cause cannot be inspected without reading the file, so a
counts-only breakdown of decode failures (by failing field) is a follow-up.

## Track C: native app shell

| Task | Result | Notes |
|---|---|---|
| Plan | PASS | XcodeGen app + ShellKit package |
| C0 Scaffold | PASS | XcodeGen app builds and launches |
| C1 EngineClient + FakeEngine | PASS | 6 contract rules on both engines; non-reentrant hub; `internal import WebKit` enforced |
| C4 Motion springs | PASS | closed-form solver verified against RK4; interruptible driver; placeholder values pending parity measurement. Follow-up before C6: completion restart loop guard; confirm `isolated deinit` back-deploys to the macOS floor |
| C2 Window chrome | PASS | traffic lights in sidebar, inset card, titlebar narrowed to sidebar |
| C3 Sidebar | PASS | NSOutlineView + favorites grid, Arc metrics/opacities, multicast observer, one-row reloads, shadow paths, a11y |
| C5 Command bar | PASS | Cmd-T/Cmd-L/+ wired; show() CPU p95 ~1 ms; earliest-frame asserted only on an unloaded machine; URL/IP/IDN parsing |
| C6 Space paging + theme | PASS | interactive swipe + spring settle, theme/grain crossfade, Ctrl-1..9, Cmd-Opt-arrows |
| C7 Smoke + pacing | PASS (with open items) | functional smoke PASS; SF Symbol bitmap cache, changed-row pushes, command bar ordered-in + reload-only-on-change; warm-show p95 15-18 ms; swipe 0 hitches/700 interactions on a quieter machine. Merged 38ca799. Open: one late frame per ~100 interactions under load (cause not named), command bar makeKey latency tail, manual checks for the user (10 trackpad swipes, Cmd-T in fullscreen and on a 2nd desktop, 1x/2x display move). Details: track-c-results.md |

### Track D review follow-ups (later)
- Unicode case/diacritic-insensitive archive search (search_text or FTS5), incl. tabs inside archived folders (BH-087).
- Deterministic launch-only leftover-sweep test.
- Counts-only breakdown of the 8 archive decodeFailed entries by DecodingError case (allowlisted keys only).
- Pin ImportCheckSummary.caseName assumption (summarized enums must not be CustomStringConvertible).
- Document: settings rows don't count as backup content; unreadable settings group is overwritten on next save.
- resetAutoArchiveStart after Arc import once open question 6 is decided.
- UI: editing the Default profile's threshold 'only this Profile' still changes inheriting profiles.
