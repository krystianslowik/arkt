# Settings window design

Design issue: #305 (part of #304). Implementation issue: #307.
Prototype: [`design/settings/prototype.html`](../../design/settings/prototype.html). Screenshots:
[`design/settings/screens/`](../../design/settings/screens/).

## 1. The look in one paragraph

A native macOS Settings window that looks like part of the system, then has one Arkt moment. Seven toolbar tabs sit
under the window title. Each tab is an SF Symbol on a 28 pt rounded tile. The selected tile fills with mustard and its
glyph turns graphite. That is the only mustard in the chrome, so the brand color tells you where you are. Content is
grouped System Settings style: porcelain (graphite in dark) behind groups of rows with hairline separators, one
control per row on the trailing edge, a short caption under the label where the label alone is not enough. Toggles
fill with mustard when on, primary buttons are mustard with graphite text, and nothing else is colored. The
Appearance pane has a small live preview of an Arkt window at the top, so toolbar and website appearance changes are
visible before you close Settings.

Type is SF Pro (the system font), on purpose: this is system UI and should read like it. Sizes: window title 13
semibold, tab labels 11 medium, section headings 13 semibold, row labels 13 regular, captions 11 regular.

## 2. Setting inventory

Status: **exists** (in code today), **planned** (designed here, built when the feature lands; the BH/KB rows of
`docs/spec/arc-parity-spec.md` give the behavior), **engine** (a Chromium preference read and written through the
engine bridge), **out** (deliberately not offered; see section 9).

| Pane | Label (final copy) | Control | Key | Default | Status | Spec |
|---|---|---|---|---|---|---|
| General | Arkt is (not) your default browser | button "Make Default" / "Default" seal | none (LaunchServices) | n/a | planned | onboarding #303 |
| General | When Arkt opens | popup: Restore last windows / Open a new window | `windowRestorationSetting` | Restore last windows | planned | BH-173, RT-30 |
| General | Warn before quitting | toggle | `shouldWarnBeforeQuitting` | off | planned | BH-177, RT-30 |
| General | Open a Peek for links to other sites | toggle | `modalEnabled` | on | planned | BH-144, BH-056 |
| General | Shift-click a link to open it in a Peek | toggle | `disableShiftClickToOpenLinksInModal` (inverted) | on | planned | BH-145 |
| General | Update Arkt automatically | toggle, disabled until the release work (decision 6) | `shouldAutomaticallyUpdate` | off | planned (#128 release) | BH-213 |
| Spaces | Profile per Space | popup per Space row | model (Space -> profile) | Default | planned | BH-034 |
| Spaces | Space name, icon, theme | not here: edited in the sidebar header | model | n/a | exists (#287) | BH-038 |
| Spaces | Archive Today tabs after | popup: 1 hour, 6 hours, 12 hours, 24 hours, 7 days, 30 days, Never | `autoArchiveTimeThresholdsPerProfile` | 12 hours | planned (policy exists, fixed at 12 h) | BH-080, BH-081, BH-083 |
| Spaces | Archive Little Arkt windows after | popup, same options | `autoArchiveLittleArcTimeThreshold` | 6 hours | planned (#28) | BH-137 |
| Spaces | Profiles list, New Profile... | rows with disclosure, button | profiles | Default | planned | BH-034, 2.13 |
| Spaces | Links from other apps open in | popup: Current Space / Little Arkt | `openExternalLinksInLittleBrowserEnabled` | Little Arkt | planned (#28) | BH-129, BH-156 |
| Spaces | Link routes ("contains" / "is") | rows, Edit, Add Route... | routes | none | planned | BH-155 |
| Appearance | Websites use | segmented: Light / Dark / Automatic | `appearance` | Automatic | engine, planned | BH-204 |
| Appearance | Show Toolbar | toggle (also Cmd-Shift-D) | `topBarURLEnabled` | off | **exists** (`ToolbarSetting.isVisible`) | BH-032, KB-018 |
| Appearance | Show the full URL | toggle, disabled while the Toolbar is off | `toolbarShowFullURLsEnabledPreference` | on | **exists** (`ToolbarSetting.showsFullURL`) | BH-032 |
| Appearance | Count Favorites in Command-1 to Command-8 | toggle | `excludeFavoritesInSwitchToNthTab` (inverted) | on | planned | BH-014 |
| Appearance | Command-9 opens the ninth tab | toggle | `switchToNinthSidebarItemEnabled` | off | planned | BH-015 |
| Appearance | Haptic feedback when reordering tabs | toggle | `tabReorderingHapticsDisabled` (inverted) | on | planned | BH-024 |
| Appearance | Play sound effects | toggle | `playUserInterfaceSoundsDisabled` (inverted) | on | planned (Arkt has no sounds yet) | BH-207 |
| Shortcuts | Every menu action: view, record, reset | recorder per row | `StorableKeyBindings` (overrides only) | menu defaults | view: exists as menus; rebind: planned | BH-198, BH-199, BH-202 |
| Shortcuts | Arkt first / Website first / Press twice for Arkt | popup per customized row and in the row's context menu | per-binding priority | Arkt first | planned | BH-200, BH-201 |
| Extensions | Installed list: enable, pin, details | toggle, pin button, row click | Chromium extension prefs | n/a | engine, planned (#121) | 2.x extensions |
| Extensions | Developer mode | toggle | Chromium `extensions.ui.developer_mode` | off | engine, planned | none |
| Privacy | Block third-party cookies | toggle | Chromium cookie controls | on | engine, planned | none (Chromium) |
| Privacy | Block cookie banners | toggle | not identified in Arc | off | planned | BH-212 |
| Privacy | Safe Browsing | popup: Enhanced / Standard / No protection | Chromium `safebrowsing.*` | Standard protection | engine, planned | none (Chromium) |
| Privacy | Site permissions (Location, Camera, Microphone, Notifications, Pop-ups and redirects) | popup Ask / Allow / Block, disclosure to the site list | Chromium content settings | Ask (Pop-ups: Block) | engine, planned | none (Chromium) |
| Privacy | Let websites read your Space's theme colors | toggle | `themeToCSSSharingAllowed` | off | planned | section 4 |
| Privacy | Clear browsing data | button "Clear..." (opens a sheet: time range + kinds) | Chromium browsing data remover | n/a | engine, planned | none |
| Advanced | Save downloads to | popup with folder, Other... | `arc.folder` / Chromium `download.default_directory` | Downloads | engine, planned (#132) | BH-182 |
| Advanced | Ask where to save each file | toggle | `arc.promptForDownload` / `download.prompt_for_download` | off | engine, planned (#132) | BH-182 |
| Advanced | Open Picture in Picture when you leave a video tab | toggle | `autoPipGloballyDisabled` (inverted) | on | planned | BH-183, BH-185 |
| Advanced | Drag the window from the top of web pages | toggle | `contentWindowDraggingEnabled` | on | planned | BH-168 |
| Advanced | Import from Arc | button "Import..." (same action as File > Import from Arc...) | none | n/a | **exists** (E4c) | import |
| Advanced | Arkt's data folder | button "Show in Finder" (same action as the recovery toast's Show Files) | none | n/a | **exists** (action) | decision 4 |
| Advanced | Reset all settings | button "Reset...", destructive, confirmation sheet | all keys above | n/a | planned | none |

Not shown as settings (state, not preference, as section 4 of the spec says): `hasHiddenSidebarWithGesture`, upsell
counters, `LastPiPPosition`, window sizes, collapsed sections, per-host Developer Mode (Ctrl-D, BH-208), per-host PiP
and translate exceptions (they live in the page's site controls).

## 3. Window and flow

- **Open**: Arkt > Settings... (Cmd-,, KB-066) opens the window, or brings it forward when it is open. The menu item
  is enabled once the window exists in code; it stays Arkt's (decision 9 keeps Chromium's settings page off Cmd-,).
- **One window**, not a sheet, not per browser window. Title is the pane name ("General", "Spaces and Profiles",
  "Appearance", "Shortcuts", "Extensions", "Privacy and Security", "Advanced"); the tab labels are the short names.
- **Remembers** the last pane (`settingsLastPane`) and its frame origin (`NSWindow.setFrameAutosaveName("Settings")`).
  First open: General, centered on the screen of the key browser window.
- **Close**: the close button and Cmd-W close it. Arkt's File menu maps Cmd-W to Archive Tab; while Settings is
  key the item would otherwise be disabled (its `closeTab:` action targets the first responder), so
  `SettingsWindowController` implements `closeTab:` as `close()` and validates the item's title to "Close Window". Escape closes the window too (decision 2); inside a shortcut recorder
  Escape cancels the recording and leaves the window open. PARITY(NEEDS-RUNTIME-CHECK): Arc has
  `escKeyClosesSettingsEnabled` as a feature flag, its default is unknown.
- **Pane keys**: Cmd-1 to Cmd-7 select panes. KB-020 gives Cmd-1 to Cmd-8 to Go to Sidebar Item; those menu items
  must validate false while Settings is key (the Cmd-W pattern), so the keys reach the Settings window (decision 1).
- **Changes apply at once**; there is no Save or Cancel. Every value is observed by every window (the
  `ToolbarSetting` pattern: one shared store, weak observers).
- **Deep links**: other surfaces open a pane directly: the "Edit the shortcut" toast (BH-195) opens Shortcuts with the
  row selected; the extensions menu's Manage Extensions opens Extensions; the recovery toast keeps Show Files.

States designed (each is a prototype hash and a screenshot pair):

| State | What it shows |
|---|---|
| `general` | Arkt is not the default browser; "Make Default" is the one primary button |
| `general-default` | Arkt is the default browser: a mustard check seal and "Default" instead of the button |
| `spaces` | three Spaces with their theme swatch and icon, a profile popup each; archive, profiles, link routing |
| `appearance` | live preview with the Toolbar on; websites segmented control; Toolbar and sidebar toggles |
| `shortcuts` | search, the Customized section, the Tabs and Spaces section, Reset All Shortcuts |
| `shortcuts-recording` | a row's keys replaced by a focused recorder: "Type a shortcut" |
| `shortcuts-conflict` | the typed key is taken: inline warning, "Use Command-E" (primary) or "Keep Command-S" |
| `extensions` | three installed extensions: icon, version and access summary, pin, toggle; Web Store, Developer mode |
| `extensions-empty` | no extensions: an invitation to the Chrome Web Store |
| `privacy` | tracking, site permissions with disclosures, data |
| `advanced` | downloads, pages, data (Import from Arc, data folder), reset |
| `general-today`, `appearance-today` | the first build: rows whose feature is not built yet are shown disabled with "Not available yet." (decision 4) |

Default browser: "Make Default" calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for `http`; macOS
then shows its own confirmation, which Arkt does not draw. The row updates when the app becomes active again
(`NSApplication.didBecomeActiveNotification`), not on a timer.

Clear browsing data and Reset all settings open a sheet on the Settings window, built from the shared dialog sheet
in `docs/design/alerts-sheets-toasts.md` (destructive button: "Clear Data" / "Reset Settings").

## 4. Layout spec (pt)

| Element | Value | Token / source |
|---|---|---|
| Window width | 680, fixed | new; PARITY(NEEDS-RUNTIME-CHECK) Arc's width unmeasured |
| Window height | chrome + pane content, at most the screen's visible height minus 120; the content scrolls past that | |
| Window corner radius | system (titled window) | |
| Title row | 28 high, title 13 semibold centered, `primaryText` | ShellTokens.primaryText |
| Toolbar row | 58 high (tabs 50 + 8 bottom); chrome total 86 incl. 1 pt hairline | |
| Toolbar material | `.titlebar` vibrancy behind `toolbarMaterial`; Reduce Transparency: opaque `surfaceBrand` | new SettingsTokens.toolbarMaterial |
| Chrome hairline | 1, `sidebarDivider` | ShellTokens.sidebarDivider |
| Tab item | 82 x 50, radius 8, tile 28 x 28 radius 8, gap 4, label 11 medium | |
| Tab tile, idle | fill `tabTileIdle`, glyph `secondaryText` 16 pt SF Symbol (regular) | new SettingsTokens.tabTileIdle |
| Tab tile, selected | fill `accent`, glyph `onAccent`, label `primaryText` | BrandTokens.accent, onAccent |
| Tab SF Symbols | gearshape, square.on.square, circle.lefthalf.filled, command, puzzlepiece.extension, hand.raised (or checkmark.shield), slider.horizontal.3 | |
| Content background | `surfaceBrand` | BrandTokens.surfaceBrand |
| Content inset | 20 top, 24 sides, 24 bottom | brand spacing scale 8/16/24 |
| Section heading | 13 semibold `primaryText`, 8 below, 2 leading nudge | |
| Section gap | 20 | |
| Group | radius 10, fill `groupFill`, 1 pt inner border `sidebarDivider` | new SettingsTokens.groupFill |
| Row | min height 44, padding 8 x 14, gap 12; label 13 `primaryText`; caption 11 `secondaryText`, 2 below | |
| Row separator | 1 pt `sidebarDivider`, inset 14 leading (50 when the row has a 28 pt leading glyph) | |
| Note under a group | 11 `secondaryText`, 6 below, max 560 wide | |
| Toggle | 38 x 22, knob 18 white with 0.5 pt edge and 1 pt shadow; off fill `sidebarItemHovered`, on fill `accent` | BrandTokens.accent |
| Popup button | 24 high, radius 6, fill `sidebarItemBackground`, 0.5 pt `sidebarDivider` edge, chevron.up.chevron.down 10 pt at 55 % | |
| Push button | 28 high (24 small), radius 7 (6 small), min width 80, padding 14 (10 small), 13 medium | engine sheet values (kButtonHeight 28, kButtonRadius 7) |
| Primary button | `accent` fill, `onAccent` text; hover `accentHighlight`; pressed `accentPressed` | BrandTokens |
| Destructive button | neutral fill, `destructiveText` | new AlertTokens.destructiveText |
| Segmented control | 2 pt inset track, segments 84 x 22, plate radius 5 (white in light, white 18 % in dark) | |
| Keycaps | 22 high, min 22 wide, radius 5, 12 medium, fill `sidebarItemBackground` | |
| Shortcut recorder | 24 high, min 150 wide, radius 6, `surfaceBrand` fill, 2 pt `focusRing` | BrandTokens.focusRing |
| Search field | 28 high, radius 7, `sidebarItemBackground`, 16 below | |
| Focus ring | 2 pt `focusRing` (graphite light, mustard dark), outset 2 | BrandTokens.focusRing |

New tokens (to add to `ShellUI/Theme`, with contrast tests next to `BrandTokensTests`):

| Token | Light | Dark | Use |
|---|---|---|---|
| `SettingsTokens.groupFill` | white 0.85 (the `tabCurrent` level) | p3 #FAFBFF 0.06 | row groups |
| `SettingsTokens.tabTileIdle` | p3 #0E0F10 0.06 | p3 #FAFBFF 0.08 | unselected tab tiles |
| `SettingsTokens.toolbarMaterial` | `surfaceBrand` 0.82 over the vibrancy view | `surfaceBrand` 0.80 | chrome over scrolled content |
| `AlertTokens.destructiveText` | sRGB #B3261E (6.2:1 on porcelain) | sRGB #FF7A6E (6.2:1 on graphite) | destructive button titles |

Contrast checked: graphite on mustard 8.4:1; `secondaryText` captions on `groupFill` over porcelain stay above 4.5:1
(black 0.64 over near-white); destructive text on the neutral button fill stays above 5.5:1 in both appearances.

## 5. Motion spec

Gate first (how often is it seen, and why does it move):

| Moment | Frequency | Purpose | Motion |
|---|---|---|---|
| Window opens / closes | occasional | system | AppKit's own window animation; nothing custom |
| Pane switch by click | occasional | spatial continuity | window frame resizes to the new pane, `NSAnimationContext` 0.25 s, timing (0.23, 1, 0.32, 1); old pane fades out over 0.08 s; new pane opacity 0 to 1 and translateY 4 to 0 on `SpringPreset.firm` (0.90 / 0.25 s) |
| Pane switch by keyboard (Cmd-1 to Cmd-7) | frequent for keyboard users | none | instant: new pane and new frame in one step |
| Tab tile selection | with the pane switch | state | mustard layer opacity 0 to 1 over 0.12 s; no sliding highlight (toolbar items are separate views) |
| Tab press | occasional | feedback | tile scale 0.96 on mouse down, `springyExtraFast` back |
| Toggle | occasional | state | knob translateX on `springyFast` (0.80 / 0.18 s, a slight overshoot); the on-fill layer cross-fades 0.15 s |
| Toggle press | occasional | feedback | knob stretches to scaleX 1.12 from its leading edge while the mouse is down |
| Segmented control | occasional | state | plate translateX on `firm` |
| Appearance preview | occasional | explanation | toolbar strip translateY -100 % to 0 and page translateY by the strip height, both on `firm`; the sidebar URL pill fades 0.15 s |
| Push button press | occasional | feedback | scale 0.97, 0.12 s ease-out |
| Shortcut recorder, conflict warning | keyboard-driven | none | instant, no animation |

Rules: transform and opacity only. The one exception is the window frame on a pane switch: that is the NSWindow
itself, resized by AppKit (`setFrame(_:display:animate:)` semantics inside an `NSAnimationContext` group), not a view
animating its bounds. The pane's own layout never animates. Every spring is interruptible: a second click mid-switch
retargets from the presentation values (`SpringDriver` reads `layer.presentation()`).

Reduce Motion: no translate, no overshoot, no animated window frame (the frame jumps); content cross-fades 0.15 s;
toggles and the segmented plate jump to their end state while the fill still cross-fades.
Reduce Transparency: the toolbar material becomes opaque `surfaceBrand`; groups are already opaque.

## 6. Light and dark

Every color above is a `TokenPair`; the prototype's `#<state>&dark` screenshots show the dark side. In dark the
content is graphite, groups lift by 6 % white, the focus ring and accent text switch to mustard, the selected tile
stays mustard with a graphite glyph. Increase Contrast: group borders and separators use `cardBorder` instead of
`sidebarDivider` (light black 0.10 to 0.10, dark 0.075 to 0.20).

## 7. Keyboard and VoiceOver

- Tab bar: an `NSToolbar` with `selectedItemIdentifier`; each item is a toolbar item with a custom view (the tile and
  label). Cmd-1 to Cmd-7 select panes. With Full Keyboard Access, Tab reaches the toolbar items, Space selects.
- Panes: the key view loop runs top to bottom, leading to trailing; every toggle, popup and button is reachable; row
  captions are not focusable.
- Shortcut recorder: Return or Space on a row starts recording; the next key combination is captured; Escape cancels;
  Delete clears the shortcut (the action stays in the list, unbound); Tab leaves the recorder without changing it. In
  the conflict state, focus moves to "Use Command-E"; Escape answers "Keep Command-S".
- VoiceOver: the window is "Settings, General" (title). Toolbar items are radio buttons in a tab group ("General, tab,
  1 of 7, selected"). Each row's control carries the row label as its accessibility label and the caption as its help
  (`setAccessibilityHelp`). Toggles are switches ("Warn before quitting, switch, off"). Keycaps read as words
  ("Shift Command D"). The recorder announces "Recording shortcut for Show or Hide Sidebar"; the conflict warning is
  posted as an announcement with high priority. Space theme swatches are decorative; the Space row reads "Work, 11
  pinned, 7 in Today, profile Work, pop-up button".
- Identifiers follow `AXID`: `settings.window`, `settings.tab.<pane>`, `settings.<pane>.<setting>` for UI tests.

## 8. Implementation notes

- `SettingsWindowController` (ShellUI) with one `NSViewController` per pane, lazily built; panes are vertical
  `NSStackView`s of group views, rows built from small helpers (label, caption, trailing control) so copy and spacing
  live in one place.
- A `Settings` store in the app target generalizes `ToolbarSetting`: typed keys, `UserDefaults` (the
  `ARKT_DEFAULTS_SUITE` override keeps working), weak observers. `ToolbarSetting` becomes two keys of it without
  changing its defaults keys, so existing users keep their values.
- Engine-backed rows go through a preferences bridge (plain values, like the extension list in Decision 10). Until it
  exists those rows are shown disabled.
- Planned rows are shown disabled until their feature works (decision 4): label in `secondaryText`, control at 42 %
  opacity with `isEnabled = false`, caption ending "Not available yet.", VoiceOver reads the control as dimmed. The
  first build enables General (default browser, startup if
  window restoration exists), Appearance (Toolbar, full URL), Shortcuts (read-only list) and Advanced (Import from Arc,
  data folder) rows; the rest are disabled. Each later feature enables its row and adds its UI test.

## 9. Parity notes

- Arc's panes are Account, General, Profiles, Links, Shortcuts, Max, App Icon, Advanced (BH-203). Arkt's are General,
  Spaces and Profiles, Appearance, Shortcuts, Extensions, Privacy and Security, Advanced. Deliberate: no account, no
  Max, no app icon referrals; Links (Air Traffic Control) moves into Spaces and Profiles, next to the Spaces it routes
  to; Chromium's extension, privacy and permission settings get native panes instead of chrome://settings.
- Out of scope, not offered: Arc Max toggles (OS-02), Boosts (OS-05), Easels and Notes (OS-04), sync (OS-07), App
  Icon referrals (BH-205), Twitter and WhatsApp badges (BH-051). Arc's "Allow websites to get your theme data" is kept (Privacy).
  Native ad blocking (BH-206) is not offered now (decision 3).
- Defaults marked unknown in section 4 of the spec are PARITY(NEEDS-RUNTIME-CHECK RT-30); the defaults chosen here
  (warn before quitting off, restore windows on, Peek on) are Arkt's until RT-30 is run.
- Shortcut priority labels: Arc's three modes (BH-200) are named "Arkt first", "Website first", "Press twice for Arkt".
  PARITY(NEEDS-RUNTIME-CHECK RT-29): Arc's per-action default.
- Copy uses "Arkt" with a capital A, as every in-app string does today; the lowercase rule in
  `design/brand/README.md` applies to the wordmark and lockups.

## 10. Decisions (maintainer, 2026-10-25)

1. Cmd-1 to Cmd-7 switch Settings panes while Settings is key: **yes**. Go to Sidebar Item (KB-020) validates false
   while Settings is key.
2. Escape closes Settings: **yes** (inside a shortcut recorder, Escape cancels the recording first).
3. Native ad and tracker blocking (BH-206): **not offered now**; no row.
4. Rows for features not built yet: **shown disabled**, not hidden. Label in `secondaryText`, control at 42 % and not
   enabled, the caption ends with "Not available yet." (prototype flag `&today`, screenshots `general-today`,
   `appearance-today`).
5. Window width: **680 pt**.
6. "Update Arkt automatically": **not before the release work** (#128); shown disabled per decision 4, off.

## 11. Screenshots

Rendered at 2x with the project's Chromium in headless mode from the prototype (`--window-size=760,<window height +
80>`, `--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`), into `design/settings/screens/<state>-<light|dark>.png`:
general, general-default, spaces, appearance, shortcuts, shortcuts-recording, shortcuts-conflict, extensions,
extensions-empty, privacy, advanced, plus general-today and appearance-today (disabled rows, hash `&today`) (26 files).
