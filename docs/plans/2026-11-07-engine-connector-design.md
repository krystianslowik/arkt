# Engine connector design

Status: proposal, 2026-11-07. Lane: `lane:engine`. Inputs: the engine options research (section 9.7, "Chromium
built as a framework with an ObjC/Swift API"), `docs/plans/2026-10-24-engine-week3-results.md` (#575, #577, #583,
#768), and a read-only audit of Chromium 156.0.8078.48 with patches 0001-0012 applied (summarised in section 1.3).

Paths below are relative to `$CR/chrome/browser/` unless they start with `components/`, `engine/` or another top-level
directory. Line numbers are from the pinned checkout. Overlay files are under `engine/arkt/browser/`.

## 1. Context

### 1.1 Where we are

Arkt runs Chromium in-process with Chrome's `Browser` and `TabStripModel`, and its own `BrowserWindow`
(`ArktBrowserWindow`, a plain `NSWindow`, no `views::Widget`). Section 9.7 of the research set the shape: Webium
(`WebUIBrowserWindow`) as the template, null-safe patches where Chromium hard-casts to `BrowserView`, and fewer than 30
patch files. Twelve patch files exist today (`engine/patches/chromium/.patches`). Five of them touch the window seam:
0004 (factory hook), 0005 (sad tab), 0006 (permission anchor, exclusive-access chip, post-install hint), 0007
(extension dialogs as sheets) and 0012 (`FindBrowserWindowWithWebContents`).

Week 3 showed the pattern that works. #575 registered `ArktAutofillBubbleHandler` as unowned user data with no
patch. #583 did page info with no patch. #768 needed one patch (0012) to generalize a window lookup. #577 found that
the crashed bubble needs a `BrowserView` and replaced it with a facade event.

### 1.2 Decisions (maintainer, 2026-11-07)

1. **Thicken the connector.** `ArktBrowserWindow` and the overlay grow to provide what Chrome's window provides. The
   maintainer accepts a much bigger overlay.
2. **Patch Chromium only to generalize or guard its window lookups**, in the shape of 0005, 0006 and 0012. No other
   kind of patch is added for the connector.
3. **Every Chromium prompt is native Arkt UI from day one**: extension popups, permission prompts, choosers, password
   and card save, and the rest. A prompt with no native UI yet is switched off or guarded to a no-op. It is never shown
   as a Views widget floating unparented next to an Arkt window.
4. **No hidden Chrome window.** No hidden `BrowserView` per Arkt window. CEF and content-only embedding stay rejected.

### 1.3 What the audit found

Scope: `chrome/browser` without tests, the pattern `GetBrowserViewForBrowser | FindBrowserWindowWithWebContents |
AsBrowserView() | GetBrowserViewForNativeWindow | static_cast<BrowserView | AsViewsBrowserWindow | BrowserView::From`.
218 hits in 142 files; 32 are definitions or other platforms, which leaves **186 hits**.

| Category | Meaning | Hits | Dereference or `CHECK` |
|---|---|---|---|
| a | the overlay can satisfy it, or an Arkt patch already does (13 already fixed by 0005, 0006, 0012 and #575) | 24 | 0 |
| b | needs a patch that guards or generalizes the lookup | 13 | 5 |
| c | Arkt has to draw UI it does not have yet | 35 | 16 |
| u | unreachable on an Arkt window (Views internals, app and PiP windows, other platforms, Google-only features) | 114 | 58 |
| total | | **186** | **79** |

- Of the 79 dereferences, 46 are Views internals Arkt never builds. **5 unchecked dereferences are reachable without a
  flag, policy or sign-in.** One is live today: `ui/views/storage/storage_pressure_bubble_view.cc:47`, reached on low
  disk (`storage/storage_notification_service_impl.cc:66`) when the last active `TYPE_NORMAL` browser is an Arkt
  window. The other four are latent: `ui/browser_commands.cc:1515` (`CloseTab` with every selected tab pinned) and
  `ui/browser_actions.cc:2270`, `:2288`, `:2306` (Cut, Copy, Paste). Arkt does not send those commands today.
- 15 more dereferences are gated by a flag, policy, branding or sign-in (glic, Lens region search, WebAuthn ambient
  sign-in, relaunch and idle bubbles, web app update review, DICE interception, batch upload, media remoting, iOS
  promos).
- `BrowserView::GetBrowserViewForBrowser` resolves through the native window's widget (`ui/views/frame/browser_view.cc:1198-1221`),
  so it is always nullptr on an Arkt window. `BrowserWindow::FromBrowser` is safe: it falls back to `browser->GetWindow()`
  (`ui/views/frame/browser_window_factory.cc:97-120`), and 155 call sites in 83 files already reach Arkt's virtuals
  through it.
- `BrowserWindowFeatures::InitPostWindowConstruction` (`ui/browser_window/internal/browser_window_features.cc:686-1125`)
  dispatches inline on `BrowserView` or `WebUIBrowserWindow`. An Arkt window gets neither leg, so it never gets docked
  DevTools (:793), the extension keybinding registry (:832-838), the extension side panel manager (:841), the find bar
  owner (:850-856), the fullscreen exit control (:860), the side panel coordinator (:910-915) or the Cast controller
  (:1002).
- Upstream is splitting by window type, not abstracting the lookups away (`ui/browser_window.h:139-146`,
  `browser_window_features.cc:705-708`). What it is generalizing is `Browser::window()` into
  `BrowserWindow::FromBrowser` (crbug.com/496674143), and window behaviour into features found with `X::From(browser)`
  ("Project Bedrock"). Null guards match upstream's own Webium precedent (`ui/views/permissions/exclusive_access_permission_prompt.cc:22`,
  `ui/views/profiles/dice_web_signin_interception_bubble_view.cc:61-63`, `ui/views/session_crashed_bubble_view.cc:281-283`).
- A hidden `BrowserView` per Arkt window is blocked in source: a child widget of a hidden parent never shows on Mac
  (`components/remote_cocoa/app_shim/native_widget_ns_window_bridge.mm:1052-1058`), lookups cannot point at both
  windows (`browser_window_factory.cc:107-109`), and `BrowserView` reparents the tab's view into Views on every tab
  change (`browser_view.cc:2035-2036`). Decision 4 stands on source, not only on preference.

## 2. Architecture

### 2.1 Arkt's own `BrowserWindow`, thickened in the overlay

`ArktBrowserWindow` stays the only window type for `TYPE_NORMAL` browsers (patch 0004, `arkt_browser_window.h:38`).
It grows in three ways, all in the overlay:

1. **Real implementations for virtuals that are stubs today.** First `GetAcceleratorProvider`, an `ARKT_STUB` at
   `arkt_browser_window.mm:1461`. Two of the b sites (`CloseTab`, context-menu accelerator labels) generalize to it, so
   it must return Arkt's real key equivalents before those hunks land. The remaining `ARKT_STUB("BrowserWindow")`
   entries are classified by #589.
2. **Per-window feature objects that `BrowserWindowFeatures` would have built for a `BrowserView`** (section 2.2).
3. **Facade events for UI the shell draws** (section 3.4). The engine side raises the event and holds Chromium's
   callback; the shell draws and answers. This is the shape #400, #577 and #583 already use.

No third `else if (arkt)` leg goes into `browser_window_features.cc`. It is a 1281-line file under active Bedrock
refactoring, and it is one of the two hot files in the patch budget gate (`engine/REBASE.md`, section 6).

### 2.2 Per-window objects registered by key

Upstream's declared pattern is unowned user data: "Do not add more public accessors. Instead use the UnownedUserData
design pattern" (`ui/browser_window/public/browser_window_features.h:276-279`). Arkt already does this three times from
the `ArktBrowserWindow` constructor: `ExtensionsContainer`, `SidePanelUI` and `AutofillBubbleHandler`
(`arkt_browser_window.h:341-346`). The connector extends the same list:

| Object | Who looks it up | Arkt implementation | Batch |
|---|---|---|---|
| `ExtensionKeybindingRegistry` subclass | extension commands; the Views one needs a `views::FocusManager` (BWF :832-838) | overlay registry fed by `NSEvent` key equivalents before the main menu | E3 |
| `ExtensionSidePanelManager` | `SidePanelService::OpenSidePanelForWindow` / `ForTab` (`extensions/api/side_panel/side_panel_service.cc:252-302`) | created in the overlay (BWF :841) | E3 |
| `SidePanelUI` (exists as `ArktSidePanelUI`, all `ARKT_STUB`, `arkt_browser_window_parts.mm:553-573`) | 60 `SidePanelUI::From` sites | real implementation hosting the panel `WebContents` in the shell | E2 |
| `FindBarOwner` | `FindBarOwner::From` (null today, BWF :850-856) | thin owner over `ArktFindBar`, only if a caller needs it | E2 |
| fullscreen exit control | BWF :860 | facade event; the shell draws the hover control (#613) | E2 |
| Cast browser controller | BWF :1002 | overlay controller; device list through the facade (#653) | E2 |
| DevTools UI controller | BWF :793 | docked DevTools in the tab container | E3 |

Rule: an object is registered from the `ArktBrowserWindow` constructor and unregistered in its destructor, with a
`ui::ScopedUnownedUserData` member, as `scoped_extensions_container_` does. A batch that registers a new object adds
one no-crash smoke row that opens and closes an Arkt window with the feature in use.

### 2.3 The bounded (b) patch set

Thirteen sites in eight files. Sizes use the measured rates from 0005, 0006 and 0012: about 5 lines per guard and
about 8-12 lines per generalization. Estimates, not measured diffs.

| # | Site | Reach | Shape | Change | Est. lines |
|---|---|---|---|---|---|
| 1 | `ui/views/storage/storage_pressure_bubble_view.cc:47` | live | guard | return early when there is no `BrowserView`; Arkt shows its own notice from a facade event | 4 |
| 2 | `ui/browser_commands.cc:1515` (`CloseTab`) | latent | generalization | take the accelerator from `BrowserWindow::FromBrowser(browser)->GetAcceleratorProvider()` (`ui/browser_window.h:266`) | 6 |
| 3 | `ui/browser_actions.cc:2270` (Cut) | latent | guard | without a `BrowserView`, call the active tab's `WebContents::Cut()` | 4 |
| 4 | `ui/browser_actions.cc:2288` (Copy) | latent | guard | same, `Copy()` | 4 |
| 5 | `ui/browser_actions.cc:2306` (Paste) | latent | guard | same, `Paste()` | 4 |
| 6 | `ui/cocoa/share_menu_controller.mm:210` | reachable, silent | generalization | File > Share takes the snapshot rect from the `BrowserWindow`, not the `BrowserView` | 10 |
| 7 | `media/webrtc/display_media_access_handler.cc:547` | reachable, silent | generalization | pick the picker's parent contents by `BrowserWindow` activity | 8 |
| 8 | `picture_in_picture/auto_picture_in_picture_window_occlusion_helper_widget.cc:56` | reachable, silent | generalization | count Arkt windows in occlusion, through one shared helper | 9 |
| 9 | same file, :110 | reachable, silent | generalization | uses the helper from row 8 | 5 |
| 10 | same file, :156 | reachable, silent | generalization | uses the helper | 5 |
| 11 | same file, :171 | reachable, silent | generalization | uses the helper | 5 |
| 12 | `ui/browser_web_contents_delegate/browser_web_contents_delegate.cc:1193` (`SetResizableFromWebAPI`) | reachable, silent | generalization | route through `BrowserWindow`; if the call has no `BrowserWindow` virtual, guard it and raise a facade event | 8 |
| 13 | `ui/views/renderer_context_menu/render_view_context_menu_views.cc:385` | reachable, silent | generalization | accelerator labels from `BrowserWindow::GetAcceleratorProvider` | 6 |
| | **total** | | 4 guards, 9 generalizations | | **about 78** (audit range 60-90) |

Two patch files, one per theme as the week-2 plan asks: rows 1 and 3-5 (`Arkt: guard window lookups that crash on a
non-BrowserView window`) and rows 2 and 6-13 (`Arkt: find the BrowserWindow where a BrowserView was assumed`). Rebase
risk: `browser_actions.cc` (5369 lines) and `browser_commands.cc` (3118) are large and often edited; the other six
files are small and quiet (113 to 475 lines). The checkout is shallow, so churn could not be measured from history;
#222 measures it.

**The 15 gated dereferences** get no patch by default. Each feature is switched off by feature flag, policy or build
flag (glic, Lens region search, HaTS, iOS promos, relaunch notification, idle timeout, media remoting). A guard of
about 5 lines is added only for a gated site that cannot be switched off and that a user can reach in the preview
(candidates: WebAuthn ambient sign-in, `webauthn/ambient/ambient_signin_controller.cc:120`; web app update review,
`ui/views/web_apps/web_app_update_review_dialog.cc:143`, `:148`, `:262`). Guarding all of them would cost about 50
lines in 10 files.

### 2.4 The `EmbedderBrowserWindowFeatures` hook

`EmbedderBrowserWindowFeatures` (`ui/browser_window/public/embedder_browser_window_features.h`) is documented as "should
only be used by Chromium embedders". Its `Init` and `InitPostWindowConstruction` run for every window
(`browser_window_features.cc:680-683`, `:1124`). The `.cc` is a 39-line stub of empty bodies compiled from
`ui/browser_window/internal/BUILD.gn:68`, so wiring it takes a patch of one hook call per method in 1-2 files. Upstream
does not edit those bodies, so conflict risk is close to nil.

**Decision proposed: do not wire it now.** It adds value over the `ArktBrowserWindow` constructor only in two cases:
the pre-window `Init` phase, and windows that are not Arkt windows (popups, app windows, DevTools windows). No batch
below needs either. Wire it, as one patch slot already counted in the budget, if the popup-window decision (section
3.5) keeps `TYPE_POPUP` on Chrome's Views window and those windows then need an Arkt per-window object, or if a feature
must exist before the window is built.

### 2.5 Patch budget

| Patch | What | Files | Status |
|---|---|---|---|
| 0001-0012 | today | 24 upstream files | exist |
| 0013 | guard theme (rows 1, 3-5) | 2 | E1 |
| 0014 | generalization theme (rows 2, 6-13) | 6 | E1 (row 2), E2 (rows 6-13) |
| 0015 | page context menu on Arkt windows (#588), only if no delegate seam works | 1-2 | E2, pending approval |
| 0016 | beforeunload to the shell (#585), only if no overlay seam works | 1 | E4, pending approval |
| 0017 | named prompt factory hook replacing `set_view_factory_for_testing` (section 6) | 1 | E4, proposed |
| 0018-0019 | named hooks for prompts with no factory seam (chooser bubble `ui/views/permissions/chooser_bubble_ui.cc:303`, embedded permission element), if the E4 gate finds none | 1-2 | E4, only if needed |
| 0020 | gated-site guards that cannot be switched off | 0-10 | E1, only if needed |
| 0021 | `EmbedderBrowserWindowFeatures` hook | 1-2 | reserved, not wired |
| | **likely total** | | **about 20-22 patch files, under 30** |

#585 and #588 name their patches "tentatively 0011" and "tentatively 0012". Both numbers are taken (history sync and
window lookup), so they become 0015 and 0016 or whatever is next when they land.

Extending the factory override to `TYPE_POPUP` (section 3.5, option B) edits 0004 and adds no file.

**The week-2 gate trips before this plan completes.** `engine/REBASE.md`, section 6, requires the week-2 seam limits to
hold: at most 8 seam patch files, 25 upstream files (not counting 0001-0004) and 6 hunks in the hot files. The week-2
plan defines the seam set as its tolerate-a-non-BrowserView themes plus the dialog hook; it does not say whether
behaviour patches count. Two readings:

| Reading | Seam patch files today | After 0013-0014 | Upstream files today | After 0013-0014 | After gated guards |
|---|---|---|---|---|---|
| seam patches only (0005, 0006, 0007, 0012) | 4 | 6 | 10 | 18 | up to 28 |
| every patch after 0004 (0005-0012) | 8 | 10 | 15 | 23 | up to 33 |

Under the narrow reading, E1 and E2 pass the gate, and the file limit trips with the E4 hooks (0015-0019); the
upstream-file limit trips only if the gated sites are guarded instead of switched off. Under the broad reading, 0013
trips the file limit at once. The gate's own fallback, a
widget-backed `ArktBrowserWindow` (variant W in the week-2 plan), does not apply: decision 3 draws every prompt
natively, so Views bubbles anchored on a widget are not wanted. This design proposes new limits (under "Needs the
maintainer" in the pull request): fewer than 30 patch files in total, at most 40 upstream files outside 0001-0004, and
the hot-file hunk limit unchanged at 6. "Hot" there means `browser_window_features.cc` and `tab_features.cc`, and no
batch below adds a hunk to either. `browser_actions.cc` and `browser_commands.cc` are large, not hot in the gate's
sense; the budget table tracks them separately.

## 3. Batches

Five `lane:engine` work packages, each one issue and one engine branch, with a results section per batch. Composition is
given as (a) overlay work with no patch, (b) a hunk of the bounded patch set, (c) native UI the shell builds against
a facade event. Order follows the existing lane rule: #122's engine work before #121's.

### E1. Crash guards (first)

Composition: (b) rows 1-5; (a) a real `GetAcceleratorProvider`; (c) one low-disk notice; feature switches for the
gated sites.

1. Storage pressure first: patch row 1, then a facade event the shell shows as a native notice.
2. `GetAcceleratorProvider` returns Arkt's key equivalents (needed by row 2 here and row 13 in E2).
3. Rows 2-5 (`CloseTab`, Cut, Copy, Paste).
4. Switch off glic, Lens region search, HaTS, iOS promos, relaunch notification, idle timeout and media remoting in the
   Arkt build; record the switch for each. Guard only what cannot be switched off.

Acceptance:

- Low disk (simulated through the storage notification service or a test switch) on an Arkt window: no crash, one
  facade event, the shell's notice appears once.
- `IDC_CLOSE_TAB` with every selected tab pinned, and `IDC_CUT`, `IDC_COPY`, `IDC_PASTE` sent through
  `executeCommand`: no crash; the clipboard commands act on the focused page.
- Each gated site: the feature is off in the Arkt build (with the switch named), or guarded, with a no-crash check.
- Each hunk breaks the right way when reverted (run once with the hunk removed, record the crash).
- `.patches` in sync, header copies `cmp` identical, results section with the budget table.

### E2. Per-window features Arkt lacks, and the silent lookups

Composition: (a) `FindBarOwner`, `ArktSidePanelUI` made real, Cast controller, the #586 overlay items, the #589 stub
sweep; (b) rows 6-13; (c) side panel host, fullscreen exit control, Cast device list, page context menu.

1. Find bar owner, only if a caller of `FindBarOwner::From` is reachable; otherwise record that none is.
2. Fullscreen exit control: facade event, shell control (shell half is #613).
3. Cast: overlay controller in place of BWF :1002, device list and start/stop through the facade (design and shell
   half in #653). The Views Cast dialog's contents-anchored fallback (`ui/views/media_router/media_router_dialog_controller_views.cc:120-135`)
   is not acceptable under decision 3; Arkt opens its own list instead.
4. Side panel coordinator: `ArktSidePanelUI` hosts the panel `WebContents` in the shell (reading mode, page info side
   panels, extension panels from E3).
5. Rows 6-13 of the patch set: share menu, display media picker parent, auto picture-in-picture occlusion,
   `SetResizableFromWebAPI`, context-menu accelerator labels.
6. Page context menu on Arkt windows (#588; its patch question stays open).
7. #586: tab-modal dialogs below infobar rows, file chooser parent. #589: stub classification, close with pending
   downloads, eyedropper.

Acceptance:

- Each per-window object is registered and unregistered with the window; open and close 3 windows with the feature in
  use, no crash.
- File > Share works on an Arkt window; screen-share picker parents to the Arkt window; auto picture-in-picture
  triggers when an Arkt window covers the video tab.
- The side panel shows reading mode in an Arkt window and closes cleanly.
- Cast lists devices natively, starts and stops casting; no crash when no device exists.
- The #586, #588 and #589 acceptance criteria, as written in those issues.

### E3. Extensions

Composition: (a) keybinding registry, `ExtensionSidePanelManager`, context menu model, `ToolbarActionsModel` pin and
order, DevTools UI controller; (c) right-click menu, side panel, site access, message bubbles, Inspect.

From the audit's missing list (`arkt_extensions_menu.mm:71-77`, `:105-107`, `:112-114`):

1. Keyboard commands: overlay `ExtensionKeybindingRegistry` subclass; `RegisterCommand` stops logging "not
   supported"; `_execute_action` opens the popup. Chrome model per the 2026-11-05 decision.
2. Action context menu: `ExtensionContextMenuModel` rendered as an `NSMenu`; replaces the `ShowContextMenuAsFallback`
   stub.
3. Side panel: create `ExtensionSidePanelManager`; host through E2's side panel.
4. Pinning and site access, and the request-access button, over `ToolbarActionsModel` and `SitePermissionsHelper`.
5. Extension message bubbles (settings overridden, developer mode) as native UI.
6. Popup "Inspect" and docked DevTools (BWF :793). Today Inspect is unsupported and DevTools stays undocked.
7. Post-install event instead of Chromium's dialog (#592).

Acceptance: the acceptance criteria of #592, #593 and #598, plus:

- `chrome.sidePanel.open` from a test extension shows its panel in an Arkt window.
- A settings-override extension shows the native message bubble once.
- Inspect on a popup opens DevTools for the popup; DevTools docks right and bottom in an Arkt tab, Cmd-Shift-D toggles.

### E4. Prompt seams for native UI

Composition: mostly (c), with an engine seam per prompt; (b) only where no factory seam exists (0016-0019 above). Each
surface needs a design pick first (`arkt-design-first`); the engine batch can land the seam and a facade event before
the shell draws it, but the prompt stays switched off until the shell answers it.

The (c) list the shell must build, from the audit and the open issues:

| Prompt | Where Chromium shows it | Today on an Arkt window |
|---|---|---|
| Device chooser (WebUSB, HID, Serial, Bluetooth) | `ui/views/permissions/chooser_bubble_ui.cc:303` | silently not shown |
| Embedded permission element | `ui/views/permissions/embedded_permission_prompt_content_scrim_view.cc:232` | Views, unparented (#265) |
| File System Access usage | `ui/views/file_system_access/file_system_access_usage_bubble_view.cc:457`, `:548` | not reachable without a page action; dereferences |
| Pointer and keyboard lock prompts, quiet permission indicator | #265 | Views, or the full prompt |
| beforeunload ("Leave site?") | `TabModalDialogManager::RunBeforeUnloadDialog` (#585) | app-modal |
| Password save and update, passkeys | #632 | not checked |
| Card and address save | `AutofillBubbleHandler`, `ArktAutofillBubbleHandler` is a no-op (#575) | nothing shown |
| WebAuthn ambient sign-in | `webauthn/ambient/ambient_signin_controller.cc:120` | gated; dereferences |
| Default browser prompt | `ui/startup/default_browser_prompt/default_browser_bubble_dialog_manager.cc:33` | skipped; Arkt draws its own |
| Memory saver | `ui/performance_controls/memory_saver_bubble_controller.cc:46` | only if surfaced |
| Touch Bar for text fields | `ui/cocoa/touchbar/web_textfield_touch_bar_controller.mm:22` | none |

Sign-in and profile bubbles (9 hits) stay off while sign-in is off. Web app windows stay `BrowserView`.

Acceptance:

- Each prompt in the table: a facade event and a response path, a contract rule on `InMemoryEngine`, and a real-engine
  check with a loopback page; or a recorded switch that keeps it off, with a no-crash check.
- No Views widget appears unparented next to an Arkt window during the check matrix (window census `views=0`, as in
  `engine/REBASE.md` verification step 4).
- The permission prompt no longer depends on `set_view_factory_for_testing` (section 6).

### E5. Popup windows: open question for the maintainer

`chrome.windows.create({type:"popup"})` makes a `TYPE_POPUP` browser. Arkt's factory takes `TYPE_NORMAL` only (patch
0004), so those windows (password-manager pop-outs, for example) open as Chrome Views windows today. Under decision 3
that is a Chrome surface in an Arkt session.

- **A. Accept it** for the preview: popups stay Chrome Views windows. No work; it is a known gap.
- **B. Extend the factory override to `TYPE_POPUP`:** an Arkt popup window (no sidebar, one tab), an edit to 0004 and
  an overlay window class. Every per-window object in section 2.2 then has to tolerate a popup.
- **C. Open the popup as an Arkt window or Peek** by turning the create into `TYPE_NORMAL`. Breaks extensions that
  expect `type: "popup"` back from `chrome.windows.get`.

Recommended default: B, after E3. No issue is filed until the maintainer answers.

## 4. Upstreaming the guard and 0012 shapes (optional proposal)

This is an external contribution to Chromium. It is a proposal for the maintainer only; nothing here is done by this
design or by any batch.

- **Null guards (0005, 0006 shape)** match upstream's Webium precedent (section 1.3). Where a `TODO(webium)` sits at
  the same site, a guard is a likely accepted fix; once upstream has it, Arkt's hunk drops out at the next rebase.
- **0012 (`FindBrowserWindowWithWebContents` returns any `BrowserWindow`)** is not enough alone for Webium: it would
  return the `WebUIBrowserWindow`, whose `GetAutofillBubbleHandler` is nullptr, so the crash moves. It is upstreamable
  together with the TODO at `ui/autofill/address_bubbles_controller.cc:84-85` (crbug.com/381390420, expose
  `AutofillBubbleHandler` through `BrowserWindowInterface`).
- **Not upstreamable:** hunks that add a non-widget fallback inside Views code, such as the `GetPageInfoAnchorRect` hunk
  of 0006. Webium has a widget, so upstream never needs them. Keep them few.

If the maintainer wants this, the maintainer files the changes under their own account and contributor agreement.
Absorbed patches cost nothing at rebase.

## 5. Rebase cost and process

**Batch instead of one seam per issue.** Each engine pull request today costs an Export, a `.patches` sync, an
`out/Spike` build and a smoke run with a fresh profile. Five batches put related hunks into one theme patch each and
one build-and-smoke cycle each, and the budget table changes five times instead of once per seam. Each batch still
lands as reviewable commits inside one pull request; a batch may be split into two pull requests if review asks.

**Rebase.** The overlay and the Swift side cost nothing at rebase. Patch hunks do: cold files about 1 per hunk, the
two large files about 2 (audit's weighting). The proposed set is about 150 patch lines, about 150-250 weighted. #222
(dry-run rebase) should run after E1 so the first real number includes the new theme patches.

**A second engine worktree.** `arkt-engine-lane`, checklist item 1, allows one engine worktree per contributor. A
second one needs:

- its own Chromium `src` checkout with its own `gclient sync` (well over 100 GB, `engine/README.md`) and its own
  `out/Spike` (10-15 GB), because `$CR/arkt` links one overlay per checkout;
- free disk: the Chromium disk had 1.9 TiB free on 2026-11-07, the internal disk 39 GiB (it holds swap, so builds need
  at least 8 GiB free there);
- builds kept serial: swap, not CPU, is the measured limit on this machine (`engine/README.md`, release build notes),
  so two Chromium builds at once are not allowed. The second worktree is for overlay and facade edits, reviews and smoke
  runs while the first builds.

This changes a repo rule, so it waits for the maintainer.

## 6. Risks

| Risk | Where | Mitigation |
|---|---|---|
| A `*_for_testing` setter in production | `arkt_permission_prompt.mm:480`, `PermissionRequestManager::set_view_factory_for_testing`, installed on tab insert | a named factory hook (0017) in E4; until then a rebase check that the setter still exists. Tracked by #265's first item |
| Test-only user-data factory | `GetUserDataFactoryForTesting()` (`browser_window_features.h:304-305`) | do not use it; register from the constructor (section 2.2) |
| Non-absorbable hunks | the `GetPageInfoAnchorRect` hunk of 0006, and any non-widget fallback in Views code | re-applied every rebase; keep them few, prefer facade events |
| Bedrock moves features out of BWF | `browser_window_features.cc` and per-feature `X::From` | user data rather than a BWF leg; re-run the audit grep on each milestone |
| Second lookup layer | `ToolbarButtonProvider::From` (34 sites), `BrowserElementsViews::From` (41), `GetWidgetForNativeWindow` (86), `ExtensionsToolbarDesktop` (13): also null on Arkt windows, not audited site by site | E1 adds a grep of these to the batch checklist; a reachable dereference becomes a guard row |
| Large, busy upstream files | `browser_actions.cc` (5369 lines), `browser_commands.cc` (3118) | one small hunk each per theme; measured in #222 |
| Gate numbers | the week-2 limits in `engine/REBASE.md`, section 6 | new limits proposed (section 2.5) |
| Native prompts from day one widen the preview scope | E4 table | prompts without native UI are switched off, never shown as Views |
| Shallow checkout | upstream churn not measured from history | #222 |
