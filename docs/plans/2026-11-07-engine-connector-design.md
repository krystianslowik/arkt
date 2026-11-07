# Engine connector design

Status: proposal, 2026-11-07, revised after review. Lane: `lane:engine`. Inputs: the engine options research
(section 9.7, "Chromium built as a framework with an ObjC/Swift API"), `docs/plans/2026-10-24-engine-week3-results.md`
(#575, #577, #583, #768), and a read-only audit of Chromium 156.0.8078.48 with patches 0001-0012 applied (summarised in
section 1.3).

Paths below are relative to `$CR/chrome/browser/` unless they start with `components/`, `engine/` or another top-level
directory. Line numbers are from the pinned checkout. Overlay files are under `engine/arkt/browser/` unless they start
with `engine/arkt/api/`.

## 1. Context

### 1.1 Where we are

Arkt runs Chromium in-process with Chrome's `Browser` and `TabStripModel`, and its own `BrowserWindow`
(`ArktBrowserWindow`, a plain `NSWindow`, no `views::Widget`). Section 9.7 of the research set the shape: Webium
(`WebUIBrowserWindow`) as the template, null-safe patches where Chromium hard-casts to `BrowserView`, and fewer than 30
patch files. Twelve patch files exist today (`engine/patches/chromium/.patches`). Five of them touch the window seam:
0004 (factory hook), 0005 (sad tab), 0006 (permission anchor, exclusive-access chip, post-install hint), 0007
(extension dialogs as sheets) and 0012 (`FindBrowserWindowWithWebContents`).

Arkt takes three browser types (`arkt_browser_main_extra_parts.mm:138-150`): `TYPE_NORMAL`, `TYPE_POPUP` (a page's
`window.open` with window features) and `TYPE_APP_POPUP` (`chrome.windows.create({type: "popup"})`). The embedder routes
both popup types to Little Arkt (`engine/arkt/api/arkt_embedder.mm:453-465`, #357). App, DevTools and
picture-in-picture windows stay Chrome Views windows.

Week 3 showed the pattern that works. #575 registered `ArktAutofillBubbleHandler` as unowned user data with no
patch. #583 did page info with no patch. #768 needed one patch (0012) to generalize a window lookup. #577 found that
the crashed bubble needs a `BrowserView` and replaced it with a facade event.

### 1.2 Decisions (maintainer, 2026-11-07)

1. **Thicken the connector.** `ArktBrowserWindow` and the overlay grow to provide what Chrome's window provides. The
   maintainer accepts a much bigger overlay.
2. **Patch Chromium only to generalize or guard its window lookups**, in the shape of 0005, 0006 and 0012.
3. **Every Chromium prompt is native Arkt UI from day one**: extension popups, permission prompts, choosers, password
   and card save, and the rest. A prompt with no native UI yet is switched off or guarded to a no-op. It is never shown
   as a Views widget floating unparented next to an Arkt window.
4. **No hidden Chrome window.** No hidden `BrowserView` per Arkt window. CEF and content-only embedding stay rejected.

Two questions follow from these decisions and are with the maintainer:

- **Hooks under decision 2. PENDING: maintainer answer.** Several items below are neither a guard nor a
  generalization: they are named hooks that hand a Chromium request to the overlay (section 2.4 lists each one). If
  hooks are not allowed, each hook row falls back to the "without a hook" column of that table.
- **Views tab-modal dialogs under decision 3. PENDING: maintainer answer.** Tab-modal Views dialogs are parented as
  sheets on the Arkt window through `GetWebContentsModalDialogHost`, so they are not unparented, but they are Views.
  The question is whether they get a carve-out for the preview (section 3, E3, tab-modal inventory).

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
  disk (`storage/storage_notification_service_impl.cc:66`) when the last active browser is an Arkt window. The other
  four are latent: `ui/browser_commands.cc:1515` (`CloseTab` with every selected tab pinned) and
  `ui/browser_actions.cc:2270`, `:2288`, `:2306` (Cut, Copy, Paste). Arkt does not send those commands today.
- 15 more dereferences are gated by a flag, policy, branding or sign-in.
- The audit's 13 b sites were classified by reachability, not by whether the file compiles on Mac. Five of them do not
  (section 2.3), so the Mac patch set is smaller than the audit's.
- `BrowserView::GetBrowserViewForBrowser` resolves through the native window's widget (`ui/views/frame/browser_view.cc:1198-1221`),
  so it is always nullptr on an Arkt window. `BrowserWindow::FromBrowser` is safe: it falls back to `browser->GetWindow()`
  (`ui/views/frame/browser_window_factory.cc:97-120`), and 155 call sites in 83 files already reach Arkt's virtuals
  through it.
- `BrowserWindowFeatures::InitPostWindowConstruction` (`ui/browser_window/internal/browser_window_features.cc:686-1125`)
  dispatches inline on `BrowserView` or `WebUIBrowserWindow`. An Arkt window gets neither leg, so it never gets docked
  DevTools (:793), the extension keybinding registry (:832-838), the extension side panel manager (:841), the find bar
  owner (:850-856), the fullscreen exit control (:860), the side panel coordinator (:910-915) or the Cast controller
  (:1002). It does get `toast_service_` (:930), which matters for section 2.3.
- Upstream is splitting by window type, not abstracting the lookups away (`ui/browser_window.h:139-146`,
  `browser_window_features.cc:705-708`). What it is generalizing is `Browser::window()` into
  `BrowserWindow::FromBrowser` (crbug.com/496674143), and window behaviour into features found with `X::From(browser)`
  ("Project Bedrock"). Null guards match upstream's Webium precedent: `ui/views/profiles/dice_web_signin_interception_bubble_view.cc:61-63`,
  `ui/views/session_crashed_bubble_view.cc:281-283`, and the `TODO(webium)` branch in `ToastController::CreateToast`
  (`ui/toasts/toast_controller.cc:323-329`). The audit also cited `ui/views/permissions/exclusive_access_permission_prompt.cc:22`,
  but that file carries 0006's own hunk, so it is not clean upstream precedent.
- A hidden `BrowserView` per Arkt window is blocked in source: a child widget of a hidden parent never shows on Mac
  (`components/remote_cocoa/app_shim/native_widget_ns_window_bridge.mm:1052-1058`), lookups cannot point at both
  windows (`browser_window_factory.cc:107-109`), and `BrowserView` reparents the tab's view into Views on every tab
  change (`browser_view.cc:2035-2036`). Decision 4 stands on source, not only on preference.

## 2. Architecture

### 2.1 Arkt's own `BrowserWindow`, thickened in the overlay

`ArktBrowserWindow` is the window for every browser Arkt takes: `TYPE_NORMAL` in a main window, `TYPE_POPUP` and
`TYPE_APP_POPUP` in Little Arkt (section 1.1). It grows in three ways, all in the overlay:

1. **Real implementations for virtuals that are stubs today.** First `GetAcceleratorProvider`, an `ARKT_STUB` at
   `arkt_browser_window.mm:1461-1464`. The `CloseTab` site generalizes to it (section 2.3), so it must return Arkt's
   real key equivalents before that hunk lands. The remaining `ARKT_STUB("BrowserWindow")` entries are classified in
   E2 (from #589).
2. **Per-window feature objects that `BrowserWindowFeatures` would have built for a `BrowserView`** (section 2.2).
3. **Facade events for UI the shell draws** (E3). The engine side raises the event and holds Chromium's callback; the
   shell draws and answers. This is the shape #400, #577 and #583 already use.

No third `else if (arkt)` leg goes into `browser_window_features.cc`. It is a 1281-line file under active Bedrock
refactoring, and it is one of the two hot files in the patch budget gate (`engine/REBASE.md`, section 6).

Two comments still say Arkt takes normal windows only. Follow-up, in E1: fix `arkt_browser_window.h:38` ("for a
`TYPE_NORMAL` Browser") in the overlay, and the comment and subject of 0004 ("normal windows") at its next Export.

### 2.2 Per-window objects registered by key

Upstream's declared pattern is unowned user data: "Do not add more public accessors. Instead use the UnownedUserData
design pattern" (`ui/browser_window/public/browser_window_features.h:276-279`). Arkt already does this three times from
the `ArktBrowserWindow` constructor: `ExtensionsContainer`, `SidePanelUI` and `AutofillBubbleHandler`
(`arkt_browser_window.h:341-346`). The connector extends the same list:

| Object | Who looks it up | Arkt implementation | Batch |
|---|---|---|---|
| `SidePanelUI` (exists as `ArktSidePanelUI`, all `ARKT_STUB`, `arkt_browser_window_parts.mm:553-573`) | 60 `SidePanelUI::From` sites | real implementation hosting the panel `WebContents` in the shell | E2 |
| `FindBarOwner` | `FindBarOwner::From` (null today, BWF :850-856) | thin owner over `ArktFindBar`, only if a caller needs it | E2 |
| fullscreen exit control | BWF :860 | facade event; the shell draws the hover control (#613) | E2 |
| Cast browser controller | BWF :1002 | overlay controller; device list through the facade (#653) | E2 |
| `ExtensionKeybindingRegistry` subclass | extension commands; the Views one needs a `views::FocusManager` (BWF :832-838) | overlay registry fed by `NSEvent` key equivalents before the main menu | E4 |
| `ExtensionSidePanelManager` | `SidePanelService::OpenSidePanelForWindow` / `ForTab` (`extensions/api/side_panel/side_panel_service.cc:252-302`) | created in the overlay (BWF :841) | E4 |
| DevTools UI controller | BWF :793 | docked DevTools in the tab container | E4 |

Rules:

- An object is registered from the `ArktBrowserWindow` constructor and unregistered in its destructor, with a
  `ui::ScopedUnownedUserData` member, as `scoped_extensions_container_` does.
- **Every per-window object must behave on Little Arkt windows** (`TYPE_POPUP` and `TYPE_APP_POPUP`): it either works
  there or declines cleanly (no side panel in Little Arkt, for example), never crashes and never acts on the main window
  instead.
- Each object adds two smoke rows: open and close 3 main windows with the feature in use; and open a Little Arkt window
  by `window.open` with window features and by `chrome.windows.create({type: "popup"})`, use the feature there, close
  it.

### 2.3 The bounded patch set

Method: for each audit b site, (1) check that its source file compiles on Mac (find it in its `BUILD.gn` and read the
conditions around it: `use_aura`, `is_linux`, `is_mac`), (2) check reachability on an Arkt window, (3) classify it as a
guard, a generalization or a hook (section 2.4). Sizes use the measured rates from 0005, 0006 and 0012: about 5 lines
per guard and about 8-12 per generalization. Estimates, not measured diffs.

Not compiled on Mac, dropped from the set:

- `ui/views/renderer_context_menu/render_view_context_menu_views.cc:385` (the audit's context-menu accelerator row): its
  `BUILD.gn` has `assert(use_aura)` and says Mac uses the Cocoa variant; it is only depended on under `if (use_aura)`
  (`ui/BUILD.gn:4509-4518`).
- `picture_in_picture/auto_picture_in_picture_window_occlusion_helper_widget.cc:56`, `:110`, `:156`, `:171`: built only
  when `use_widget_occlusion_helper = is_linux` (`picture_in_picture/BUILD.gn:14`, `:175-177`). Mac builds the
  WebContents helper instead (`use_web_contents_occlusion_helper`, `:13`). Auto picture-in-picture on Arkt windows
  becomes a verification in E2, not a patch.

The Mac set:

| # | Site | File lines | Reach | Shape | Change | Est. lines |
|---|---|---|---|---|---|---|
| 1 | `ui/views/storage/storage_pressure_bubble_view.cc:47` | 113 | live | guard | return early when there is no `BrowserView`. The native notice comes from the overlay (section 2.4), not from this hunk | 4 |
| 2 | `ui/browser_commands.cc:1515` (`CloseTab`) | 3118 | latent | generalization | replace `CHECK(browser_view)` and the `CHECK` on `GetAcceleratorForCommandId` with `BrowserWindow::FromBrowser(browser)->GetAcceleratorProvider()` (`ui/browser_window.h:266`). Arkt binds Cmd-W to Archive, so its provider may have no `IDC_CLOSE_TAB` accelerator: then close without the confirmation toast | 8 |
| 3 | `ui/browser_actions.cc:2270` (Cut) | 5369 | latent | guard | without a `BrowserView`, call the active tab's `WebContents::Cut()` | 4 |
| 4 | `ui/browser_actions.cc:2288` (Copy) | | latent | guard | same, `Copy()` | 4 |
| 5 | `ui/browser_actions.cc:2306` (Paste) | | latent | guard | same, `Paste()` | 4 |
| 6 | `ui/cocoa/share_menu_controller.mm:210` | 344 | to check: Arkt owns the main menu (W3-8) and may never reach Chromium's share controller | generalization | take the transition rect from the `BrowserWindow`; drop the row if unreachable | 10 or 0 |
| 7 | `media/webrtc/display_media_access_handler.cc:547` | 848 | reachable, silent | generalization | pick the picker's parent contents by `BrowserWindow` activity, not by `BrowserView`'s widget | 8 |
| 8 | `ui/browser_web_contents_delegate/browser_web_contents_delegate.cc:1193` (`SetResizableFromWebAPI`) | 1537, already carries hunks of 0009 and 0010 | reachable, already null-checked | hook, or accept | no crash today. `SetResizableFromWebApi` is not a `BrowserWindow` virtual, and adding one edits `ui/browser_window.h`, a widely included header the gate excludes. Default: accept the gap and record it | 0 (hook about 6) |
| T | `ui/toasts/toast_controller.cc:442-452` (`GetAnchorView`) and `:320-329` (`CreateToast`) | | reachable once row 2 lands; see "Toasts" | guard (Webium shape) | `GetAnchorView` dereferences `BrowserElementsViews::From` (null on Arkt windows) before `CreateToast` reaches its `TODO(webium)` branch and `CHECK_IS_TEST()`. Guard both: no anchor, no toast, no `CHECK` | 6 |
| | **total** | | | | 5 guards, 3 generalizations, 1 hook-or-accept | **about 48** |

Files: 6 (storage pressure, `browser_commands.cc`, `browser_actions.cc`, share menu, display media, toast controller),
none of them patched today. Two patch files, one per theme as the week-2 plan asks: guards (rows 1, 3-5, T) and
generalizations (rows 2, 6, 7). E1 creates both; E2 adds rows 6-7 to the generalization patch. Rebase risk:
`browser_actions.cc` and `browser_commands.cc` are large and often edited; the others are small.

**Toasts.** `toast_service_` exists for every `TYPE_NORMAL` window (BWF :930), so every `MaybeShowToast` caller can
reach row T on an Arkt window, not only `CloseTab`. Non-test callers in 156, 33 files outside `ui/toasts/`, grouped:

- probably reachable without a flag (E1 confirms): `renderer_context_menu/render_view_context_menu.cc`,
  `renderer_context_menu/link_to_text_menu_observer.cc`, `translate/chrome_translate_client.cc`,
  `ui/autofill/chrome_autofill_client.cc`, `ui/passwords/manage_passwords_auto_signin_toast_delegate.cc`,
  `ssl/https_first_mode_settings_tracker.cc`, `safe_browsing/safe_browsing_pref_change_handler.cc`,
  `safe_browsing/security_settings_bundle_pref_change_handler.cc`, `safe_browsing/security_settings_bundle_toast_helper.cc`,
  `default_browser/default_browser_controller.cc`, `ui/startup/startup_browser_creator_impl.cc`,
  `ui/webui/settings/settings_clear_browsing_data_handler.cc`, `ui/webui/feedback/feedback_ui.cc`,
  `ui/tabs/vertical_tab_strip_state_controller_impl.cc`, `ui/browser_commands.cc` (15 files);
- gated (sign-in, enterprise, Google AI, sharing): `actor/`, `glic/` (3), `dictation/`, `indigo/`, `skills/`,
  `record_replay/`, `enterprise/connectors/analysis/`, `enterprise/data_protection/`, `ui/autofill/email_verifier/`,
  `ui/send_tab_to_self/` (2), `ui/signin/dice_migration_service.cc`, `ui/tabs/saved_tab_groups/`,
  `ui/tabs/shared_tab_group_version_upgrade_modal.cc`, `ui/views/scheduled_restart/`, `ui/webui/watermark/` (18 files).

Whether the reachable ones crash today depends on `BrowserElementsViews::From` on an Arkt window; E1 checks it first.
Toasts are dropped by the guard, or routed to the shell by a hook in `ToastController` if hooks are allowed.

**The 15 gated dereferences** get no patch by default. Each feature is switched off in the Arkt build by feature flag,
policy or build flag: glic, Lens region search, iOS promos, relaunch notification, idle timeout, media remoting, DICE
web sign-in interception, batch upload, web app update review and WebAuthn ambient sign-in (the last until E3 draws it
natively). HaTS needs nothing: Arkt overrides `ShowHatsDialog`. A guard of about 5 lines is added only for a site that
cannot be switched off.

### 2.4 Hooks, and the `EmbedderBrowserWindowFeatures` hook

**PENDING: maintainer answer on whether named hooks are allowed under decision 2.** Every item that is not a guard or
a generalization, classified:

| Item | Class | Batch | Without a hook |
|---|---|---|---|
| Storage pressure notice | guard + overlay | E1 | row 1 only stops the crash. The overlay watches free disk itself and raises the facade event; Chromium's per-origin trigger is not used. Needs no hook either way |
| Toast routing to the shell | hook | E1 | row T drops toasts on Arkt windows |
| `SetResizableFromWebAPI` | hook | E2 | accept the gap (row 8) |
| Page context menu on Arkt windows (#588) | hook, only if no delegate seam works | E2 | no page context menu |
| beforeunload to the shell (#585) | hook, only if no overlay seam works | E3 | Chrome's app-modal dialog |
| Named permission prompt factory, replacing `set_view_factory_for_testing` (section 6) | hook | E3 | keep the test setter, with a rebase check |
| Device chooser (`ui/views/permissions/chooser_bubble_ui.cc:303`), embedded permission element | hook, only if the E3 gate finds no factory seam | E3 | switched off |
| `EmbedderBrowserWindowFeatures` | hook | reserved | the `ArktBrowserWindow` constructor |

`EmbedderBrowserWindowFeatures` (`ui/browser_window/public/embedder_browser_window_features.h`) is documented as "should
only be used by Chromium embedders". Its `Init` and `InitPostWindowConstruction` run for every window
(`browser_window_features.cc:680-683`, `:1124`). The `.cc` is a 39-line stub of empty bodies compiled from
`ui/browser_window/internal/BUILD.gn:68`, so wiring it takes one hook call per method in 1-2 files, with conflict risk
close to nil.

**Proposed: do not wire it now.** Popups are already Arkt windows and get every object from the `ArktBrowserWindow`
constructor. The hook is worth wiring only for app windows or DevTools windows (both stay Views), or for a feature that
must exist in the pre-window `Init` phase. No batch below needs any of those.

### 2.5 Patch budget

Patch numbers are not pre-assigned: each patch takes the next free number at Export. #585 and #588 name theirs
"tentatively 0011" and "tentatively 0012"; both numbers are taken (history sync and window lookup), so those notes are
struck.

The week-2 gate (`docs/plans/2026-10-23-engine-week2.md:947-951`, applied by `engine/REBASE.md` section 6) uses a mixed
definition. It counts **seam patch files** (the tolerate-a-non-BrowserView themes and the dialog hook: 0005, 0006,
0007, and 0012 in the same shape), but **upstream files across the whole diff** above the pin, minus the files of
0001-0004. It trips on more than 8 seam patch files, more than 25 upstream files, more than 6 hunks in the hot files
(`browser_window_features.cc`, `tab_features.cc`), or a change to a widely included header. Today: 4 seam patch files,
15 upstream files outside 0001-0004 (24 in all, 9 of them in 0001-0004), 0 hot-file hunks.

| Step | Patch files | Upstream files outside 0001-0004 | Seam and hook patch files | Status |
|---|---|---|---|---|
| today (0001-0012) | 12 | 15 | 4 | exist |
| E1: guard theme (rows 1, 3-5, T) and generalization theme (row 2) | 14 | 19 | 6 | proposed |
| E2: rows 6-7 added to the generalization theme | 14 | 20-21 | 6 | proposed |
| E2: page context menu hook (#588), if needed | 15 | 21-23 | 7 | pending hooks answer |
| E3: permission factory, beforeunload, chooser and permission element hooks | 17-18 | 24-27 | 9-10 | pending hooks answer |
| toast routing and `SetResizable` hooks (files already counted) | 17-20 | 24-27 | 9-12 | pending hooks answer |
| gated sites that cannot be switched off | 17-21 | 24-31 | 9-13 | only if needed |
| `EmbedderBrowserWindowFeatures`, if ever wired | 17-22 | 24-33 | 9-14 | reserved |
| **likely total** (no gated guards, hook not wired) | **about 17-20, under 30** | **about 24-27** | **about 9-12** | |

Under today's limits, the seam-file limit (more than 8) trips with the E3 hooks, and the upstream-file limit (more than
25) can trip at the upper end of E3. Proposed new limits, keeping the mixed definition:

- under 30 patch files in total;
- about 30 upstream files outside 0001-0004 (so the gated sites are switched off, not guarded);
- at most 12 seam and hook patch files;
- at most 4 hunks in total in `browser_actions.cc` and `browser_commands.cc` (today 0; E1 adds 4);
- hot-file hunks unchanged at 6 (no batch adds one), and no change to a widely included header.

The gate's own fallback, a widget-backed `ArktBrowserWindow` (variant W in the week-2 plan), does not apply: decision 3
draws prompts natively, so Views bubbles anchored on a widget are not wanted.

## 3. Batches

Four `lane:engine` work packages, each one issue and one engine branch, with a results section per batch. Order:
**E1, E2, E3, E4**, following the lane rule that #122's engine work comes before #121's. Composition: (a) overlay work
with no patch, (b) a patch hunk, (c) native UI the shell builds against a facade event.

Before E2 starts, the audit grep is extended to `BrowserElementsViews::From`, `GetView(` and `CHECK_IS_TEST`, with the
same Mac-build and reachability checks; new reachable crash sites join E1 or E2.

### E1. Crash guards (first)

Composition: (b) rows 1-5 and T; (a) a real `GetAcceleratorProvider`, the overlay disk watcher, the comment follow-ups
of section 2.1; (c) one low-disk notice (design first, `arkt-design-first`); feature switches for the gated sites.

1. Storage pressure first: row 1, then the overlay's low-disk facade event and the shell's notice.
2. Toasts: check whether a reachable toast caller crashes on an Arkt window today (trigger one, for example a
   clear-browsing-data or translate toast); add row T.
3. `GetAcceleratorProvider` returns Arkt's key equivalents.
4. Rows 2-5 (`CloseTab`, Cut, Copy, Paste).
5. Switch off the gated features (section 2.3); record the switch for each.

Acceptance:

- Low disk (simulated through the storage notification service or a test switch) on an Arkt window: no crash, one
  facade event, the shell's notice appears once.
- A toast triggered on an Arkt window: no crash; dropped, or shown by the shell if hooks are allowed.
- `IDC_CLOSE_TAB` with every selected tab pinned, with and without an `IDC_CLOSE_TAB` accelerator in Arkt's provider,
  and `IDC_CUT`, `IDC_COPY`, `IDC_PASTE` sent through `executeCommand`: no crash; the clipboard commands act on the
  focused page.
- Each gated site: the feature is off in the Arkt build, with the switch named, and a no-crash check.
- Each hunk breaks the right way when reverted (run once without it, record the crash).
- `.patches` in sync, header copies `cmp` identical, results section with the budget table.

### E2. Per-window features Arkt lacks, and the silent lookups

Composition: (a) `FindBarOwner`, a real `ArktSidePanelUI`, the Cast controller, the #586 overlay items, the #589 stub
sweep; (b) rows 6-7 (and the row 8 hook if allowed); (c) side panel host, fullscreen exit control, Cast device list,
page context menu.

Shell design dependencies: Cast (#653, waiting on a design pick), the fullscreen exit control (#613) and the page
context menu (#588). The engine seam can land first, but each feature stays off until the shell draws it.

1. Find bar owner, only if a caller of `FindBarOwner::From` is reachable; otherwise record that none is.
2. Fullscreen exit control: facade event, shell control (#613).
3. Cast: overlay controller in place of BWF :1002, device list and start/stop through the facade. The Views Cast
   dialog's contents-anchored fallback (`ui/views/media_router/media_router_dialog_controller_views.cc:120-135`) does
   not meet decision 3; Arkt opens its own list instead.
4. Side panel: `ArktSidePanelUI` hosts the panel `WebContents` in the shell (reading mode, page info side panels,
   extension panels from E4).
5. Rows 6-7: share menu (after the reachability check), display media picker parent.
6. Auto picture-in-picture: verify that Mac's WebContents occlusion helper sees Arkt windows; patch nothing unless it
   fails.
7. Page context menu on Arkt windows (#588).
8. From #586: tab-modal dialogs below infobar rows, file chooser parent. From #589: stub classification, close with
   pending downloads, eyedropper.

Acceptance:

- Each per-window object passes the section 2.2 smoke rows in main windows and Little Arkt.
- Screen-share picker parents to the Arkt window. File > Share works, or is recorded as unreachable with the evidence.
- Auto picture-in-picture triggers when another window covers a playing video in an Arkt window, or the failure is
  recorded with the helper's trace.
- The side panel shows reading mode in an Arkt window and closes cleanly.
- Cast lists devices natively, starts and stops casting; no crash when no device exists.
- The acceptance criteria of #586 (without its docked DevTools item, which moves to E4), #588 and #589.

### E3. Prompt seams for native UI

Composition: mostly (c), with an engine seam per prompt; hooks only where no factory seam exists (section 2.4). Each
surface needs a design pick first (`arkt-design-first`). The engine seam can land before the shell draws it, but the
prompt stays switched off until the shell answers it.

Bubbles and prompts the shell must build:

| Prompt | Where Chromium shows it | Today on an Arkt window |
|---|---|---|
| Device chooser (WebUSB, HID, Serial, Bluetooth) | `ui/views/permissions/chooser_bubble_ui.cc:303` | silently not shown |
| Embedded permission element | `ui/views/permissions/embedded_permission_prompt_content_scrim_view.cc:232` | Views, unparented (#265) |
| File System Access usage | `ui/views/file_system_access/file_system_access_usage_bubble_view.cc:457`, `:548` | only from a page action; dereferences |
| Pointer and keyboard lock prompts, quiet permission indicator | #265 | Views, or the full prompt |
| beforeunload ("Leave site?") | `TabModalDialogManager::RunBeforeUnloadDialog` (#585) | app-modal |
| Password save and update, passkeys | #632 | not checked |
| Card and address save | `AutofillBubbleHandler`; `ArktAutofillBubbleHandler` is a no-op (#575) | nothing shown |
| WebAuthn ambient sign-in | `webauthn/ambient/ambient_signin_controller.cc:120` | switched off (E1) |
| FedCM account chooser | `ui/views/webid/fedcm_account_selection_view_desktop.cc:1165` (bubble), `ui/views/webid/account_selection_modal_view.cc` | not checked |
| Default browser prompt | `ui/startup/default_browser_prompt/default_browser_bubble_dialog_manager.cc:33` | skipped; Arkt draws its own |
| Memory saver | `ui/performance_controls/memory_saver_bubble_controller.cc:46` | only if surfaced |
| Touch Bar for text fields | `ui/cocoa/touchbar/web_textfield_touch_bar_controller.mm:22` | none |

**Tab-modal inventory. PENDING: maintainer answer on a preview carve-out.** `ShowWebModalDialogViews` appears in 39
non-test files under `chrome/browser` (`grep -rl ShowWebModalDialogViews`, `*.cc` and `*.mm`, tests excluded). Arkt
parents these as sheets on the Arkt window through `GetWebContentsModalDialogHost`, but they are Views. Grouped:

- page-facing, reachable: HTTP auth (`ui/views/login_handler_views.cc`), external protocol
  (`ui/views/external_protocol_dialog.cc`), client certificate (`ui/views/certificate_selector.cc`), generic tab-modal
  confirm (`ui/views/tab_modal_confirm_dialog_views.cc`), constrained web dialogs
  (`ui/views/constrained_web_dialog_delegate_views.cc`), share this tab
  (`ui/views/desktop_capture/share_this_tab_dialog_views.cc`), media picker (`ui/views/media_picker_utils.cc`),
  Bluetooth credentials and pairing (`ui/views/bluetooth_device_credentials_view.cc`,
  `ui/views/bluetooth_device_pair_confirm_view.cc`), WebAuthn
  (`ui/views/webauthn/authenticator_request_dialog_view_controller_views.cc`), digital credentials
  (`ui/views/digital_credentials/digital_identity_multi_step_dialog.cc`), extension chooser and media galleries
  (`ui/views/extensions/chooser_dialog_view.cc`, `ui/views/extensions/media_galleries_dialog_views.cc`);
- payments and passwords: card unmask and OTP (`ui/views/autofill/payments/`, 3 files), Payment Request and secure
  payment confirmation (`ui/views/payments/`, 2 files), account chooser, auto sign-in first run and combined selector
  (`ui/views/passwords/`, 3 files);
- already native in Arkt: JavaScript dialogs (`ui/views/javascript_tab_modal_dialog_view_views.cc`, #400);
- off or unreachable in Arkt: web apps (`ui/views/web_apps/`, 10 files, plus `ui/views/shortcuts/create_desktop_shortcut.cc`
  and `ui/views/apps/app_info_dialog/`), enterprise (`enterprise/connectors/analysis/`, `enterprise/data_controls/`),
  Google AI (`actor/`, `skills/`), Safe Browsing tailored security (`ui/views/safe_browsing/tailored_security_unconsented_modal.cc`).

Without a carve-out, every reachable row above needs native UI or a switch before the preview.

Acceptance:

- Each prompt in the tables: a facade event and a response path, a contract rule on `InMemoryEngine`, and a real-engine
  check with a loopback page; or a recorded switch that keeps it off, with a no-crash check. Tab-modal rows follow the
  carve-out answer.
- No Views widget appears next to an Arkt window during the check matrix. The existing census (`ARKT: browsers normal=
  arkt= views=`, `arkt_browser_main_extra_parts.mm:199-238`) counts Views browser windows only, not bubbles or sheets,
  so E3 adds a widget census (open `views::Widget`s per Arkt window) and uses that.
- The permission prompt no longer depends on `set_view_factory_for_testing`, or a rebase check guards it (section 6).

### E4. Extensions

Composition: (a) keybinding registry, `ExtensionSidePanelManager`, context menu model, `ToolbarActionsModel` pin and
order, DevTools UI controller, tab events; (c) right-click menu, side panel, site access, message bubbles, Inspect.

From the audit's missing list (`arkt_extensions_menu.mm:72-78` `RegisterCommand`, `:105-107` Inspect, `:111-113`
`ShowContextMenuAsFallback`):

1. Keyboard commands: overlay `ExtensionKeybindingRegistry` subclass; `RegisterCommand` stops logging "not
   supported"; `_execute_action` opens the popup. Chrome model per the 2026-11-05 decision.
2. Action context menu: `ExtensionContextMenuModel` rendered as an `NSMenu`.
3. Side panel: create `ExtensionSidePanelManager`; host through E2's side panel.
4. Pinning and site access, and the request-access button, over `ToolbarActionsModel` and `SitePermissionsHelper`;
   the pinned-by-default hint (from #265).
5. Extension message bubbles (settings overridden, developer mode) as native UI.
6. Popup Inspect and docked DevTools (BWF :793, from #586).
7. Post-install event instead of Chromium's dialog (#592).
8. Pinned, group and split tab events to the facade (`OnTabPinnedStateChanged`, `OnTabGroupChanged`,
   `OnSplitTabChanged`, from #265).

Acceptance: the acceptance criteria of #592, #593 and #598, including the criteria written in their comments, plus:

- Commands, the context menu and popups work in Little Arkt as well as in main windows (section 2.2).
- `chrome.sidePanel.open` from a test extension shows its panel in an Arkt window.
- A settings-override extension shows the native message bubble once.
- Inspect on a popup opens DevTools for the popup; DevTools docks right and bottom in an Arkt tab, Cmd-Shift-D toggles.
- Pinned, group and split tab changes each raise one facade event.

### Moving issue criteria

Before a replaced issue is closed, its criteria are copied into the new issue, including those written only in issue
comments: #585's seven Swift-side criteria, #592's `.browserImport` case, and #598's `kKeyTab` note. The old issue is
closed with a link only after that copy is checked.

## 4. Upstreaming the guard and 0012 shapes (optional proposal)

This is an external contribution to Chromium. It is a proposal for the maintainer only; nothing here is done by this
design or by any batch.

- **Null guards (0005, 0006 shape, and row T)** match upstream's Webium precedent (section 1.3). Where a `TODO(webium)`
  sits at the same site, such as `ToastController::CreateToast`, a guard is a likely accepted fix; once upstream has
  it, Arkt's hunk drops out at the next rebase.
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
`out/Spike` build and a smoke run with a fresh profile. Four batches put related hunks into theme patches and one
build-and-smoke cycle each. Each batch still lands as reviewable commits inside one pull request; a batch may be split
into two pull requests if review asks.

**Rebase.** The overlay and the Swift side cost nothing at rebase. Patch hunks do: weight 1 per hunk in small files and
2 in `browser_actions.cc` and `browser_commands.cc` (the audit's weighting). The two themes of section 2.3 are about 48
lines in 9 hunks, about 68 weighted (lines times weight); the hooks of section 2.4 add to that only if allowed. #222
(dry-run rebase) runs right after E1, so the first measured number includes the new themes.

**One engine worktree.** `arkt-engine-lane` (checklist item 1) stays as it is: one engine worktree with the `$CR/arkt`
link and one Chromium build at a time (swap, not CPU, is the measured limit, `engine/README.md`). Reviews, overlay edits
that do not need a build, and docs use a plain repo worktree without the `$CR` link.

## 6. Risks

| Risk | Where | Mitigation |
|---|---|---|
| A `*_for_testing` setter in production | `arkt_permission_prompt.mm:480`, `PermissionRequestManager::set_view_factory_for_testing`, installed on tab insert | a named factory hook in E3 if hooks are allowed; otherwise a rebase check that the setter still exists. Tracked by #265's first item, which moves to E3 |
| Test-only user-data factory | `GetUserDataFactoryForTesting()` (`browser_window_features.h:304-305`) | do not use it; register from the constructor (section 2.2) |
| Toasts on Arkt windows | `ui/toasts/toast_controller.cc:323-329`, `:442-452`; 15 probably reachable caller files | E1 checks and guards first |
| Non-absorbable hunks | the `GetPageInfoAnchorRect` hunk of 0006, and any non-widget fallback in Views code | re-applied every rebase; keep them few, prefer facade events |
| Bedrock moves features out of BWF | `browser_window_features.cc` and per-feature `X::From` | user data rather than a BWF leg; re-run the audit grep on each milestone |
| Second lookup layer | `ToolbarButtonProvider::From` (34 sites), `BrowserElementsViews::From` (41), `GetWidgetForNativeWindow` (86), `ExtensionsToolbarDesktop` (13): also null on Arkt windows, not audited site by site | the extended grep before E2 |
| Patched files edited often upstream | `browser_actions.cc` (5369 lines), `browser_commands.cc` (3118); `browser_web_contents_delegate.cc` (1537, two Arkt hunks already) if the row 8 hook is added | the hunk cap in section 2.5; measured in #222 |
| Gate numbers | the week-2 limits in `engine/REBASE.md`, section 6 | new limits proposed (section 2.5) |
| Native prompts from day one widen the preview scope | E3 tables | prompts without native UI are switched off, never shown as Views |
| Shallow checkout | upstream churn not measured from history | #222 |
