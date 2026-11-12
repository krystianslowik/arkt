# Engine connector design

Status: proposal, 2026-11-07, revised after review; open questions answered 2026-11-08 (section 1.2). Lane:
`lane:engine`. Inputs: the engine options research (section 9.7, "Chromium built as a framework with an ObjC/Swift
API"), `docs/plans/2026-10-24-engine-week3-results.md` (#575, #577, #583, #768), and a read-only audit of Chromium
156.0.8078.48 with patches 0001-0012 applied (summarised in section 1.3).

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

The questions that followed from these decisions were answered by the maintainer on 2026-11-08 (the last three at
22:46 CET):

5. **Hooks: allowed, capped.** Hook patches are allowed, capped at about 12 hook and seam patch files in total and
   under 30 upstream files. A seam that needs no patch still comes first. The question named four native prompts with
   no seam: leave-site (beforeunload), the device pickers, the permission prompt factory and low disk. Those are the
   planned hooks (E3a). They were examples, not a closed list: other hooks (in-tab sheets, toasts, the page context
   menu) are allowed as long as they fit the cap. This unblocks #585 (the leave-site panel) and #588 (the page context
   menu). Hunk limits: at most 4 hunks each in `browser_actions.cc` and `browser_commands.cc`, and at most 6 in the
   hot files. Section 2.4 lists each hook; section 2.5 has the budget.
6. **In-tab sheets: native from day one, no carve-out.** The in-tab sheets (39 files call `ShowWebModalDialogViews`:
   HTTP login, open-app, certificate picker and the rest; FedCM has its own bubble and modal) go native or are
   switched off. A Chromium-drawn sheet is not accepted for the preview, even when it is parented on the Arkt window.
   Section 3 (E3b) carries the inventory and the plan, including a second tab-modal path that does not go through
   `ShowWebModalDialogViews`. Two follow-up answers: the in-tab sheet hooks (E3b's route 4 hooks and both choke-point
   guards) may take the upstream-file total up to 40, while everything else stays under 30; and Payment Request and
   secure payment confirmation are drawn natively in E3b.

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
3. **Facade events for UI the shell draws** (E3a, E3b). The engine side raises the event and holds Chromium's
   callback; the shell draws and answers. This is the shape #400, #577 and #583 already use.

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
- gated (sign-in, enterprise, Google-only features, sharing): `actor/`, `glic/` (3), `dictation/`, `indigo/`,
  `skills/`, `record_replay/`, `enterprise/connectors/analysis/`, `enterprise/data_protection/`, `ui/autofill/email_verifier/`,
  `ui/send_tab_to_self/` (2), `ui/signin/dice_migration_service.cc`, `ui/tabs/saved_tab_groups/`,
  `ui/tabs/shared_tab_group_version_upgrade_modal.cc`, `ui/views/scheduled_restart/`, `ui/webui/watermark/` (18 files).

Whether the reachable ones crash today depends on `BrowserElementsViews::From` on an Arkt window; E1 checks it first.
Toasts are dropped by the guard. A hook in `ToastController` that routes them to the shell is allowed (decision 5),
but none is planned; it is taken only if a batch shows a need, and it counts against the cap.

**The 15 gated dereferences** get no patch by default. Each feature is switched off in the Arkt build by feature flag,
policy or build flag: glic, Lens region search, iOS promos, relaunch notification, idle timeout, media remoting, DICE
web sign-in interception, batch upload, web app update review and WebAuthn ambient sign-in (the last until E3a draws it
natively). HaTS needs nothing: Arkt overrides `ShowHatsDialog`. A guard of about 5 lines is added only for a site that
cannot be switched off.

### 2.4 Hooks, and the `EmbedderBrowserWindowFeatures` hook

Hooks are allowed within the cap (decision 5). A seam that needs no patch still comes first. Every item that is not a
guard or a generalization, classified:

| Item | Class | Batch | Status |
|---|---|---|---|
| Low-disk notice | hook (planned) | E3a | E1 landed the guard only (0013, row 1). The hook goes in `storage_pressure_bubble_view.cc`, the file 0013 already patches: instead of returning early, it hands the notice to the overlay. No new upstream file. The overlay's own disk watcher is the fallback |
| beforeunload ("Leave site?", #585) | seam (no patch) | E3a | landed with #585: the overlay wraps `AppModalDialogManager`'s native dialog factory, so no hook was needed |
| Named permission prompt factory, replacing `set_view_factory_for_testing` (section 6) | hook (planned) | E3a | planned |
| Device pickers (`ui/views/permissions/chooser_bubble_ui.cc:303`), embedded permission element | hook (planned), only if the E3a gate finds no factory seam | E3a | planned |
| In-tab sheets: a guard and hook at each of the two tab-modal choke points, plus hooks in sheet factories | guard + hook | E3b | planned (decision 6). The `TabDialogManager` guard landed early as 0015 (#852). Up to 40 upstream files in total (section 2.5) |
| Toast routing to the shell | hook | none planned | allowed, not planned. Row T drops toasts; taken only if a batch shows a need, and counted against the cap |
| `SetResizableFromWebAPI` | hook | E2 | allowed, not planned. Accept the gap (row 8) |
| Page context menu on Arkt windows (#588) | generalization (no delegate seam works) | E2 | landed as 0016: Chromium's own menu as a native `NSMenu` on the page's window, items whose follow-up UI is Views hidden (maintainer, 2026-11-12). Counted against the cap |
| `EmbedderBrowserWindowFeatures` | hook | reserved | not wired (below) |

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
(`browser_window_features.cc`, `tab_features.cc`), or a change to a widely included header. Before E1: 4 seam patch
files, 15 upstream files outside 0001-0004 (24 in all, 9 of them in 0001-0004), 0 hot-file hunks. On main now
(0001-0016): 16 patch files, 8 seam and hook patch files, 22 upstream files outside 0001-0004, 4 hunks in
`browser_actions.cc` and `browser_commands.cc` (3 and 1), 0 hot-file hunks.

| Step | Patch files | Upstream files outside 0001-0004 | Seam and hook patch files | Status |
|---|---|---|---|---|
| before E1 (0001-0012) | 12 | 15 | 4 | exist |
| E1: guard theme (rows 1, 3-5, T) and generalization theme (row 2) | 14 | 19 | 6 | landed (#800, 0013 and 0014) |
| E3b's `TabDialogManager` guard, landed early (#846) | 15 | 20 (sheet file) | 7 | landed (#852, 0015) |
| E2: rows 6-7 added to the generalization theme | 15 | 21-22 | 7 | planned |
| E2: page context menu (#588): the window lookup generalized and the Views-only items hidden, in one patch (2 files) | 16 | 22 | 8 | landed (0016) |
| E3a: planned hooks: permission prompt factory, device pickers and permission element, low disk (low disk adds no file); beforeunload landed as a seam with #585 (no patch file) | 16-18 | 23-27 | 8-10 | allowed (decision 5) |
| E3b: `ShowWebModalDialogViews` guard and hook (1 file), the `TabDialogManager` hook (in 0015's file, no new file), sheet hooks (about 5-8 files) | 17-20 | 29-36 | 9-12 | allowed (decision 6), up to 40 |
| toast routing and `SetResizable` hooks | | | | not planned; only within the cap |
| gated sites that cannot be switched off | | | | only if needed, within the cap |
| `EmbedderBrowserWindowFeatures`, if ever wired | | | | reserved, within the cap |
| **likely total** | **about 17-20, under 30** | **about 22-26 non-sheet files (under 30), about 29-36 in all (at most 40)** | **about 9-12, at most 12** | |

Limits, set by the maintainer's answers (decisions 5 and 6) and kept in the gate's mixed definition:

- at most about 12 seam and hook patch files;
- under 30 upstream files outside 0001-0004, not counting the in-tab sheet files;
- up to 40 upstream files outside 0001-0004 in total, where the files above 30 are in-tab sheet files only (E3b's
  route 4 hooks and both choke-point guards, including 0015's `tab_dialog_manager.cc`);
- under 30 patch files in total;
- at most 4 hunks each in `browser_actions.cc` and `browser_commands.cc` (today 3 and 1);
- at most 6 hot-file hunks (no batch adds one), and no change to a widely included header.

After 0016, 22 upstream files are used, one of them a sheet file. The rest of E2 and E3a take about 1-5 more, so the
non-sheet files end at about 22-26, under 30. E3b's sheet files then take the total to about 29-36, under 40. At 40 E3b stops
and asks the maintainer. With the 40-file allowance, the seam and hook patch file cap (12) is now the tighter one:
E3b keeps all its sheet hooks in one or two theme patch files.

`engine/REBASE.md` section 6 states these limits.

The gate's own fallback, a widget-backed `ArktBrowserWindow` (variant W in the week-2 plan), does not apply: decisions
3 and 6 draw prompts and sheets natively, so Views bubbles and sheets anchored on a widget are not wanted.

## 3. Batches

Five `lane:engine` work packages, each one issue and one engine branch, with a results section per batch. Order:
**E1, E2, E3a, E3b, E4**, following the lane rule that #122's engine work comes before #121's. E3 is split in two
because decision 6 adds the in-tab sheets to it. E1 has landed (#800). Composition: (a) overlay work
with no patch, (b) a patch hunk, (c) native UI the shell builds against a facade event.

Before E2 starts, the audit grep is extended to `BrowserElementsViews::From`, `GetView(` and `CHECK_IS_TEST`, with the
same Mac-build and reachability checks; new reachable crash sites join E1 or E2.

### E1. Crash guards (first)

Landed in #800 (0013 and 0014): guards and one generalization, no hook. Results:
`docs/plans/2026-10-24-engine-week3-results.md`, "E1: crash guards". The native low-disk notice (the second half of
step 1 and its acceptance row) moves to E3a, where the low-disk hook is one of the planned hooks.

Composition: (b) rows 1-5 and T; (a) a real `GetAcceleratorProvider`, the overlay disk watcher, the comment follow-ups
of section 2.1; (c) one low-disk notice (design first, `arkt-design-first`); feature switches for the gated sites.

1. Storage pressure first: row 1, then the overlay's low-disk facade event and the shell's notice.
2. Toasts: check whether a reachable toast caller crashes on an Arkt window today (trigger one, for example a
   clear-browsing-data or translate toast); add row T.
3. `GetAcceleratorProvider` returns Arkt's key equivalents.
4. Rows 2-5 (`CloseTab`, Cut, Copy, Paste).
5. Switch off the gated features (section 2.3); record the switch for each.

Acceptance:

- Low disk (simulated through the storage notification service or a test switch) on an Arkt window: no crash. The
  facade event and the shell's notice moved to E3a.
- A toast triggered on an Arkt window: no crash; dropped.
- `IDC_CLOSE_TAB` with every selected tab pinned, with and without an `IDC_CLOSE_TAB` accelerator in Arkt's provider,
  and `IDC_CUT`, `IDC_COPY`, `IDC_PASTE` sent through `executeCommand`: no crash; the clipboard commands act on the
  focused page.
- Each gated site: the feature is off in the Arkt build, with the switch named, and a no-crash check.
- Each hunk breaks the right way when reverted (run once without it, record the crash).
- `.patches` in sync, header copies `cmp` identical, results section with the budget table.

### E2. Per-window features Arkt lacks, and the silent lookups

Composition: (a) `FindBarOwner`, a real `ArktSidePanelUI`, the Cast controller, the #586 overlay items, the #589 stub
sweep; (b) rows 6-7 (row 8 stays an accepted gap); (c) side panel host, fullscreen exit control, Cast device list,
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
7. Page context menu on Arkt windows (#588), unblocked by decision 5: a hook if no delegate seam works.
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

### E3. Native prompts and in-tab sheets (split: E3a, E3b)

Decision 6 adds the in-tab sheets to E3. Before, E3 was about 12 bubble and prompt surfaces. With the sheets it is about
12 prompt surfaces, about 20 page-facing sheet files on the `ShowWebModalDialogViews` path plus the `TabDialogManager`
callers, a new census and two new guards. Each native surface needs a design pick first (`arkt-design-first`). That is
about twice the old E3 and too big for one pull request, so it splits:

- **E3a: prompts and the planned hooks.** The bubble and prompt table below, and the four planned hooks of
  decision 5.
- **E3b: in-tab sheets.** The two choke-point guards and hooks, the sheet routes and the sheet inventory below.

Rough size, as a guide only: E3a is close to the old E3 (12 surfaces, 2-4 hook sites, 1-2 hook patch files). E3b is
larger in shell work (about 10-14 native sheets, Payment Request among them) but smaller in patch files (2 guards and
about 5-8 sheet hooks, in 1-2 patch files). E3b starts once E3a's hooks have landed, so it knows how much of the cap is
left. Either may split again into two pull requests if review asks (section 5).

The rule for both: the engine seam can land before the shell draws the surface, but the prompt or sheet stays switched
off until the shell answers it. Nothing Chromium-drawn is shown in the meantime.

#### E3a. Prompts and the planned hooks

Composition: mostly (c), with an engine seam per prompt; (b) the four planned hooks of decision 5 (section 2.4), each
only where no seam exists.

1. Permission prompt factory: a hook in place of `set_view_factory_for_testing` (section 6).
2. Device pickers (WebUSB, HID, Serial, Bluetooth) and the embedded permission element: a factory seam if the gate
   finds one; otherwise a hook at `chooser_bubble_ui.cc:303`.
3. beforeunload ("Leave site?", #585, unblocked by decision 5): an overlay seam if one works; otherwise a hook.
   Landed as a seam: the overlay wraps the app-modal native dialog factory (#585).
4. Low disk: the hook in `storage_pressure_bubble_view.cc` (already patched by 0013) hands the notice to the overlay;
   the shell draws it.
5. The rest of the table below, each through a facade event.

Bubbles and prompts the shell must build:

| Prompt | Where Chromium shows it | Today on an Arkt window |
|---|---|---|
| Device chooser (WebUSB, HID, Serial, Bluetooth) | `ui/views/permissions/chooser_bubble_ui.cc:303` | silently not shown |
| Embedded permission element | `ui/views/permissions/embedded_permission_prompt_content_scrim_view.cc:232` | Views, unparented (#265) |
| File System Access usage | `ui/views/file_system_access/file_system_access_usage_bubble_view.cc:457`, `:548` | only from a page action; dereferences |
| Pointer and keyboard lock prompts, quiet permission indicator | #265 | Views, or the full prompt |
| beforeunload ("Leave site?") | `TabModalDialogManager::RunBeforeUnloadDialog` (#585) | the shell's panel (#585), through the app-modal factory seam |
| Low-disk notice | `ui/views/storage/storage_pressure_bubble_view.cc` | dropped by 0013's guard |
| Password save and update, passkeys | #632 | not checked |
| Card and address save | `AutofillBubbleHandler`; `ArktAutofillBubbleHandler` is a no-op (#575) | nothing shown |
| WebAuthn ambient sign-in | `webauthn/ambient/ambient_signin_controller.cc:120` | switched off (E1) |
| FedCM account chooser (bubble; ships in E3b with the modal) | `ui/views/webid/fedcm_account_selection_view_desktop.cc:1165` | not checked |
| Default browser prompt | `ui/startup/default_browser_prompt/default_browser_bubble_dialog_manager.cc:33` | skipped; Arkt draws its own |
| Memory saver | `ui/performance_controls/memory_saver_bubble_controller.cc:46` | only if surfaced |
| Touch Bar for text fields | `ui/cocoa/touchbar/web_textfield_touch_bar_controller.mm:22` | none |

FedCM has a bubble here and a modal in E3b. Both are drawn by the same native surface, so they ship together in E3b.

Acceptance:

- Each prompt in the table: a facade event and a response path, a contract rule on `InMemoryEngine`, and a real-engine
  check with a loopback page; or a recorded switch that keeps it off, with a no-crash check.
- Low disk (simulated with Simulate on `chrome://quota-internals`, the method E1's results used) on an Arkt window:
  no crash, one facade event, the shell's notice appears once.
- The permission prompt no longer depends on `set_view_factory_for_testing` (section 6).
- A widget census: the existing census (`ARKT: browsers normal= arkt= views=`, `arkt_browser_main_extra_parts.mm:199-238`)
  counts Views browser windows only, not bubbles or sheets. E3a adds a count of open `views::Widget`s per Arkt window,
  and E3a and E3b use it. No Views widget appears next to an Arkt window during the check matrix.
- Budget after E3a recorded in its results section: patch files, upstream files, seam and hook patch files.

#### E3b. In-tab sheets

Composition: (b) a guard and hook at each of the two choke points, and a few sheet hooks; (a) overlay sheet handlers;
(c) the native sheets.

Chromium shows a tab-modal sheet through two paths:

- **`constrained_window::ShowWebModalDialogViews`** (`components/constrained_window/constrained_window_views.cc:257`).
  It creates the Views widget and shows it as a sheet through `GetWebContentsModalDialogHost`. 39 non-test files
  under `chrome/browser` call it (`grep -rl ShowWebModalDialogViews`, `*.cc` and `*.mm`, tests excluded).
- **`TabDialogManager`** (`ui/tabs/tab_dialog_manager.cc`, 621 lines). `CreateAndShowDialog` (`:371`) calls
  `CreateTabScopedDialog` (`:303`), which builds its own widget (`:313-314`) and skips `ShowWebModalDialogViews`.
  23 non-test files match `CreateAndShowDialog(` or `CreateShowDialogAndBlockTabInteraction` (the same grep shape;
  a few are a dialog class's own static of the same name, such as `DeprecatedAppsDialogView::CreateAndShowDialog`,
  and one is `tab_dialog_manager.cc` itself). `CreateTabScopedDialog` does `CHECK(host)` on `GetHostWidget()`
  (`:306-307`), which is `BrowserElementsViews::GetPrimaryWindowWidget()` (`:435-445`). On an Arkt window that widget
  is null (E1 results, row T), so a caller that reaches this path on an Arkt window would crash today, not draw a
  sheet. That crash was engine bug #846. Patch 0015 (#852) guards it: with no host widget, the dialog's widget is
  parented to the tab's view, not shown, and closed on the next turn, so the caller sees an ordinary dismissal.

The E3b gate greps both paths (`ShowWebModalDialogViews`, `CreateAndShowDialog(`,
`CreateShowDialogAndBlockTabInteraction` and `CreateTabScopedDialog(`), with the Mac-build and reachability checks of
section 2.3.

How a sheet goes native, in order of preference:

1. **A guard and hook at each choke point (two patch sites, two upstream files).** In `ShowWebModalDialogViews`, and
   in `TabDialogManager` (the guard there is 0015; E3b adds the hook in the same file): when the WebContents is in an
   Arkt window, the Views widget is never shown. The sheet is offered to the overlay (the hook). If no handler takes
   it, it is cancelled and logged with its delegate's class name (the guard). Once both are in place, no Chromium-drawn sheet appears on
   an Arkt window, and a sheet that is not handled yet shows up in the logs and the widget census, not on screen.
   Until both exist, decision 6 rests on the switches of route 5 and on 0015.
2. **An existing seam, no patch.** A model or controller the overlay can already reach. Examples already in place:
   JavaScript dialogs (#400) and the extension dialogs of 0007.
3. **A generic `ui::DialogModel` sheet.** Some sheets are built from a `ui::DialogModel` (title, text, fields,
   buttons). The shell draws those with one native sheet renderer, as 0007 does for extension dialogs. A grep finds
   `DialogModel` in 7 of the page-facing files below; the gate checks which of them build the whole sheet that way.
4. **A hook in the sheet's own factory.** One hook site in the file that creates the sheet, in the shape of 0007's
   hook (ask the overlay first). All sheet hooks go into one theme patch file. Each one costs an upstream file. Sheet
   files may take the total to 40 (decision 6), which leaves room for about 5-8 of them (section 2.5).
5. **Switched off for the preview.** For a feature that is gated, unreachable, or not worth a native sheet yet. The
   switch is recorded with a no-crash check. The choke-point guards cover it too.

Inventory, with the proposed route per row. The E3b gate confirms each route against the pinned source before any
work:

| Group | Sheet (path under `ui/views/`; a path starting with `actor/`, `enterprise/`, `glic/`, `policy/`, `skills/`, `ssl/` or `ui/` is under `chrome/browser/`) | Proposed route |
|---|---|---|
| page-facing, must be native | HTTP login (`login_handler_views.cc`) | 4: hook in `LoginHandler::Create` |
| | Open-app, external protocol (`external_protocol_dialog.cc`) | 4: hook in `RunExternalProtocolDialog` |
| | Client certificate picker (`certificate_selector.cc`) | 4, or 2 if `ChromeContentBrowserClient::SelectClientCertificate` can be reached without a patch |
| | WebAuthn and passkeys (`webauthn/authenticator_request_dialog_view_controller_views.cc`) | 2 or 4: the sheet is drawn from `AuthenticatorRequestDialogModel` |
| | FedCM modal (`webid/account_selection_modal_view.cc`) and the FedCM bubble (E3a) | 4: one hook at the account selection view factory covers both |
| | Generic tab-modal confirm (`tab_modal_confirm_dialog_views.cc`) | 2: drawn from its `TabModalConfirmDialogDelegate`, if its callers are reachable; otherwise 5 |
| | Bluetooth credentials and pairing (`bluetooth_device_credentials_view.cc`, `bluetooth_device_pair_confirm_view.cc`) | 3 for credentials if the gate confirms; native with the device pickers (E3a), or 5 with Web Bluetooth |
| | Share this tab, media picker (`desktop_capture/share_this_tab_dialog_views.cc`, `media_picker_utils.cc`) | 2 or 4, together with E2 row 7 (the screen-share picker) |
| | Constrained web dialogs (`constrained_web_dialog_delegate_views.cc`) | to check: which callers are reachable on Mac; a WebUI page in a native sheet, or 5 |
| passwords and payments | Account chooser, auto sign-in first run, combined selector (`passwords/`, 3 files) | native with password save (#632, E3a); 5 until then |
| | Card unmask and OTP, payments consent (`autofill/payments/`, 3 files) | 5: server cards need a Google Payments account |
| | Payment Request and secure payment confirmation (`payments/`, 2 files) | native in E3b (decision 6): 4, a hook at the dialog factory, or 2 if the payment request delegate can be reached without a patch. The largest native set in E3b (payment sheet, shipping, contact, payment method) |
| gated or off | Digital credentials (`digital_credentials/digital_identity_multi_step_dialog.cc`), extension chooser and media galleries (`extensions/chooser_dialog_view.cc`, `extensions/media_galleries_dialog_views.cc`) | 5: behind a flag or reachable only from Chrome Apps |
| | Web apps (`web_apps/`, 10 files, plus `shortcuts/create_desktop_shortcut.cc` and `apps/app_info_dialog/`), enterprise (`enterprise/connectors/analysis/`, `enterprise/data_controls/`), Google-only features (`actor/`, `skills/`), Safe Browsing tailored security (`safe_browsing/tailored_security_unconsented_modal.cc`) | 5: off or unreachable in Arkt |
| already native | JavaScript dialogs (`javascript_tab_modal_dialog_view_views.cc`) | 2: #400 |
| `TabDialogManager` path, page-facing | Ask before HTTP (`ssl/ask_before_http_dialog_controller.cc`, built from a `ui::DialogModel`) | switched off by #846 until the `TabDialogManager` hook lands; then 3 through that hook |
| | Edit address profile (`autofill/edit_address_profile_view.cc`) | native with address save (E3a), or 5 until then |
| | Credential leak warning (`passwords/credential_leak_dialog_view.cc`) | to check: whether leak checks run without sign-in; native with password save (#632), or 5 |
| `TabDialogManager` path, gated or off | Autofill payments (`autofill/payments/`, 7 files: error, progress, BNPL terms and issuer, unmask authentication selection, save and fill, card WebAuthn) | 5: server cards and BNPL need a Google Payments account |
| | Password change (`ui/passwords/password_change_ui_controller.cc`), save to Drive (`save_to_drive/`), Lens permission (`ui/lens/`), glic opt-in (`glic/`), dictation onboarding (`dictation/`) | 5: Google-only, sign-in or unbranded builds |
| | Enterprise (`policy/chrome_browser_cloud_management_register_watcher.cc`, `ui/views/policy/enterprise_startup_dialog_view.cc`), web apps (`web_apps/`, 4 files, and `tab_dialogs_views.cc`, which only forwards to them) | 5: off or unreachable in Arkt |

Proposed counts: about 5-8 route 4 hooks (HTTP login, open-app, FedCM, Payment Request, and maybe the certificate
picker, WebAuthn, secure payment confirmation and share this tab), about 10-14 native sheets in the shell, and the
rest switched off. The gate still tries routes 2 and 3 for every candidate first. Route 4 hooks and the
`ShowWebModalDialogViews` guard may take the upstream-file total up to 40; within that, E3b goes on without asking.
If E3b would pass 40, it stops and asks the maintainer. A Chromium-drawn sheet is never the fallback.

Order inside E3b:

1. Gate: confirm each route against the source; record the budget after E3a.
2. The two choke-point guards and hooks. From here on, no Views sheet shows on an Arkt window.
3. HTTP login, open-app and the certificate picker: the sheets a normal browsing session hits first.
4. FedCM, WebAuthn and passkeys.
5. Payment Request and secure payment confirmation.
6. The rest of the native rows, then the switches.

Acceptance:

- Each sheet row: a facade event and a response path, a contract rule on `InMemoryEngine`, and a real-engine check with
  a loopback page (HTTP 401 for login, a custom scheme link for open-app, a test client certificate, a FedCM test
  provider, a virtual WebAuthn authenticator, a Payment Request test page with a test payment method); or a recorded
  switch with a no-crash check.
- With the `ShowWebModalDialogViews` guard reverted, each checked page on that path shows a Views sheet again (the
  break check); with 0015 reverted, its checked caller hits `CHECK(host)` again. With both in
  place, the widget census stays at zero during the check matrix.
- An unhandled sheet is cancelled, not left pending: the page gets the same result as when the user dismisses it.
- Budget after E3b recorded: seam and hook patch files at most about 12; upstream files outside 0001-0004 under 30
  without the sheet files and at most 40 with them.

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
`out/Spike` build and a smoke run with a fresh profile. Five batches put related hunks into theme patches and one
build-and-smoke cycle each. Each batch still lands as reviewable commits inside one pull request; a batch may be split
into two pull requests if review asks.

**Rebase.** The overlay and the Swift side cost nothing at rebase. Patch hunks do: weight 1 per hunk in small files and
2 in `browser_actions.cc` and `browser_commands.cc` (the audit's weighting). The two themes of section 2.3 are about 48
lines in 9 hunks, about 68 weighted (lines times weight); the hooks of section 2.4 (E3a, E3b) add to that, within the
cap of section 2.5. #222 (dry-run rebase) runs right after E1, so the first measured number includes the new themes.

**One engine worktree.** `arkt-engine-lane` (checklist item 1) stays as it is: one engine worktree with the `$CR/arkt`
link and one Chromium build at a time (swap, not CPU, is the measured limit, `engine/README.md`). Reviews, overlay edits
that do not need a build, and docs use a plain repo worktree without the `$CR` link.

## 6. Risks

| Risk | Where | Mitigation |
|---|---|---|
| A `*_for_testing` setter in production | `arkt_permission_prompt.mm:480`, `PermissionRequestManager::set_view_factory_for_testing`, installed on tab insert | a named factory hook in E3a (decision 5). Tracked by #265's first item, which moves to E3a |
| Test-only user-data factory | `GetUserDataFactoryForTesting()` (`browser_window_features.h:304-305`) | do not use it; register from the constructor (section 2.2) |
| Toasts on Arkt windows | `ui/toasts/toast_controller.cc:323-329`, `:442-452`; 15 probably reachable caller files | E1 checks and guards first |
| Non-absorbable hunks | the `GetPageInfoAnchorRect` hunk of 0006, and any non-widget fallback in Views code | re-applied every rebase; keep them few, prefer facade events |
| Bedrock moves features out of BWF | `browser_window_features.cc` and per-feature `X::From` | user data rather than a BWF leg; re-run the audit grep on each milestone |
| Second lookup layer | `ToolbarButtonProvider::From` (34 sites), `BrowserElementsViews::From` (41), `GetWidgetForNativeWindow` (86), `ExtensionsToolbarDesktop` (13): also null on Arkt windows, not audited site by site | the extended grep before E2 |
| Patched files edited often upstream | `browser_actions.cc` (5369 lines), `browser_commands.cc` (3118); `browser_web_contents_delegate.cc` (1537, two Arkt hunks already) if the row 8 hook is added | the hunk cap in section 2.5; measured in #222 |
| Gate numbers | the patch budget limits in `engine/REBASE.md`, section 6 | set (section 2.5, REBASE.md §6) |
| Native prompts and sheets from day one widen the preview scope | E3a and E3b tables | E3 split in two; prompts and sheets without native UI are switched off, never shown as Views; the two E3b choke-point guards cancel any sheet not handled yet |
| A second tab-modal path | `TabDialogManager::CreateTabScopedDialog` (`ui/tabs/tab_dialog_manager.cc:303-314`), 23 matching files; `CHECK(host)` on an Arkt window | guarded by 0015 (#852); E3b adds the hook in the same file; both paths in the E3b gate's grep |
| Sheet hooks outgrow the cap | E3b route 4: sheet files may take the total to 40 | the choke points and existing seams first; E3b stops for a maintainer call only at 40 |
| Seam and hook patch files reach 12 | about 9-12 after E3b | sheet hooks share one or two theme patch files |
| Shallow checkout | upstream churn not measured from history | #222 |
