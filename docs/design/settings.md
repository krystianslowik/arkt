# Settings window design

Design issue: #305 (part of #304). Implementation issue: #307.
Prototype: [`design/settings/prototype.html`](../../design/settings/prototype.html). Screenshots:
[`design/settings/screens/`](../../design/settings/screens/). Restyled to the brand direction (#304); the before and
after list is in [`design/settings/README.md`](../../design/settings/README.md).

## 1. The look in one paragraph

Settings is everyday chrome, so it follows the Archive window (`design/archive-search/archive-search.md`, section 2)
instead of System Settings: the system font at Arc's sidebar density, the porcelain (graphite in dark) surface, and
rows that are sidebar rows. What lifts it above a stock preferences sheet:

- **One bar on top.** The title and the seven pane items sit on the window surface (unified, 84 pt), with no toolbar
  strip and no hairline under it. A pane item is an SF Symbol over its short name; the selected one lifts in
  `tabCurrent` with `tabCurrentShadow`, exactly as the current tab does in the sidebar. No tiles, no mustard.
- **Groups are recessed fields, rows are sidebar rows.** Each group is the Archive's recessed list field (radius 10,
  4 pt padding); its rows are radius 9, 2 pt apart, hover `sidebarItemBackground`, with no hairlines between them.
  Section titles are the sidebar's section titles (12 semibold `secondaryText`). Add actions ("New Profile...",
  "Add Route...") are the sidebar's New Tab row: a plus glyph and the label in `sidebarForeground`.
- **One primary per pane.** The only mustard on a pane is its one primary action, a mustard pill with graphite text
  (Make Default; Open Chrome Web Store when no extension is installed; Use Command-E in a shortcut conflict). Panes
  without a primary have no mustard at all. Secondary actions are neutral pills (`sidebarItemHovered`, no edge) or
  quiet text links. Destructive actions (Reset..., Clear..., Reset All Shortcuts...) are quiet red text links.
- **Switches are graphite, not mustard.** On is a graphite fill with a white knob (a porcelain fill with a graphite
  knob in dark), so twenty switches never compete with the one primary.
- **Space color carries meaning.** A Space row leads with its theme swatch (the theme's own gradient); the Appearance
  preview is drawn in the Work Space's theme.
- **Focus is the system's.** Every focus ring, the shortcut recorder included, is the system focus ring
  (`NSColor.keyboardFocusIndicatorColor`). Mustard is a fill only: never text, never a stroke.

Type is SF Pro (the system font), on purpose. Sizes: window title 13 semibold, pane labels 11 medium, section titles
12 semibold, row labels 13 medium, captions and notes 12 regular, buttons 13 semibold (12 small).

## 2. Setting inventory

Status: **exists** (in code today), **planned** (designed here, built when the feature lands; the BH/KB rows of
`docs/spec/arc-parity-spec.md` give the behavior), **engine** (a Chromium preference read and written through the
engine bridge), **out** (deliberately not offered; see section 9).

| Pane | Label (final copy) | Control | Key | Default | Status | Spec |
|---|---|---|---|---|---|---|
| General | Arkt is (not) your default browser | button "Make Default" / "Default" seal | none (LaunchServices) | n/a | planned | onboarding #303 |
| General | When Arkt opens | popup: Restore last windows / Open a new window | `windowRestorationSetting` | Restore last windows | planned | BH-173, RT-30 |
| General | Warn before quitting | toggle | `shouldWarnBeforeQuitting` | off | planned | BH-177, RT-30 |
| General | Open a Peek window when clicking on links to other sites (note "Only affects Favorites and pinned tabs") | toggle | `modalEnabled` | on | **exists** (#348) | BH-144, BH-056 |
| General | Open a Peek window when clicking on links with Shift held | toggle | `disableShiftClickToOpenLinksInModal` (inverted) | on | **exists** (#348) | BH-145 |
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
| Privacy | Send crash reports | toggle (Crash reports section) | `crashReportsEnabled` | off | built (#129); engine crashes follow in #447 | section 5 of the design plan |
| Privacy | Send a crash report | pill "Send Crash Report", enabled while the switch is on and a report is kept; opens a prefilled GitHub issue in the browser | local reports in `<data folder>/CrashReports` | n/a | built (#129) | section 5 of the design plan |
| Advanced | Save downloads to | popup with folder, Other... | `arc.folder` / Chromium `download.default_directory` | Downloads | engine, planned (#132) | BH-182 |
| Advanced | Ask where to save each file | toggle | `arc.promptForDownload` / `download.prompt_for_download` | off | engine, planned (#132) | BH-182 |
| Advanced | Open Picture in Picture when you leave a video tab | toggle | `autoPipGloballyDisabled` (inverted) | on | planned | BH-183, BH-185 |
| Advanced | Drag the window from the top of web pages | toggle | `contentWindowDraggingEnabled` | on | planned | BH-168 |
| Advanced | Import browser data | neutral pill "Import..." (same action as File > Import Browser Data...) | none | n/a | **exists** (E4c) | import |
| Advanced | Arkt's data folder | button "Show in Finder" (same action as the recovery toast's Show Files) | none | n/a | **exists** (action) | decision 4 |
| Advanced | Reset all settings | red text link "Reset...", confirmation sheet | all keys above | n/a | planned | none |

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
  `SettingsWindowController` implements `closeTab:` as `close()` and validates the item's title to "Close Window". Escape closes the window too (decision 2), after any field that uses it: in the Shortcuts
  search field Escape first clears a non-empty search (standard `NSSearchField` behavior) and closes Settings only when
  the field is empty; inside a shortcut recorder
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
| `general` | Arkt is not the default browser; "Make Default" is the pane's one primary (mustard pill) |
| `general-default` | Arkt is the default browser: a neutral "Default" capsule with a check instead of the button; the pane has no mustard |
| `spaces` | three Spaces with their theme swatch and icon, a profile popup each; archive, profiles, link routing |
| `appearance` | live preview with the Toolbar on; websites segmented control; Toolbar and sidebar toggles |
| `shortcuts` | search, the Customized section, the Tabs and Spaces section, Reset All Shortcuts |
| `shortcuts-recording` | a row's keys replaced by a focused recorder: "Type a shortcut" |
| `shortcuts-conflict` | the typed key is taken: inline warning, "Use Command-E" (primary) or "Keep Command-S" |
| `extensions` | three installed extensions: icon, version and access summary, pin, toggle; Web Store, Developer mode |
| `extensions-empty` | no extensions: an invitation to the Chrome Web Store |
| `privacy` | tracking, site permissions with disclosures, data |
| `advanced` | downloads, pages, data (Import browser data, data folder), reset as a red link |
| `general-today`, `appearance-today` | the first build: rows whose feature is not built yet are shown disabled with "Not available yet." (decision 4) |

Default browser: "Make Default" calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for `http`; macOS
then shows its own confirmation, which Arkt does not draw. The row updates when the app becomes active again
(`NSApplication.didBecomeActiveNotification`), not on a timer.

Clear browsing data and Reset all settings open a sheet on the Settings window, built from the shared dialog sheet
in `docs/design/alerts-sheets-toasts.md` (destructive button: "Clear Data" / "Reset Settings").

## 4. Layout spec (pt)

| Element | Value | Token / source |
|---|---|---|
| Window width | 680, fixed | decision 5 |
| Window height | chrome + pane content, at most the screen's visible height minus 120; the content scrolls past that | |
| Window corner radius | system (titled window) | |
| Chrome | unified, 84 high (`titlebarAppearsTransparent`, `.fullSizeContentView`): traffic lights at their standard inset, title 13 semibold centered `primaryText`, pane bar 36 from the top; no hairline below | the Archive window's title bar |
| Chrome material | `.titlebar` vibrancy behind `toolbarMaterial`, only visible while content scrolls under it; Reduce Transparency: opaque `surfaceBrand` | SettingsTokens.toolbarMaterial |
| Pane item | 84 x 44, radius 9, 2 apart, centered; SF Symbol 16 pt `sidebarForeground`, 3 above the label, label 11 medium `secondaryText`; hover `sidebarItemBackground` | SidebarMetrics.rowCornerRadius |
| Pane item, selected | `tabCurrent` fill + `tabCurrentShadow`; glyph and label `primaryText` | ShellTokens, the current tab |
| Pane SF Symbols | gearshape, square.on.square, circle.lefthalf.filled, command, puzzlepiece.extension, checkmark.shield, slider.horizontal.3 | |
| Content background | `surfaceBrand` | BrandTokens.surfaceBrand |
| Content inset | 8 top, 16 sides, 20 bottom | |
| Section title | 12 semibold `secondaryText`, 10 leading, 6 below | the sidebar's section title |
| Section gap | 18 | |
| Group | recessed field: radius 10, padding 4, `SettingsTokens.groupField`, no edge | ArchiveTokens.listField |
| Row | min height 36, radius 9, padding 6 / 8 / 6 / 10, 2 between rows, gap 12; label 13 medium `primaryText`; caption 12 `secondaryText`, 1 below; hover `sidebarItemBackground`; no separators | SidebarMetrics, adapted |
| Leading glyph | 20 x 20: Space theme swatch (radius 6, the theme's gradient), profile monogram (radius 5), extension icon; the app icon 32 on the default-browser row; 12 to the label | |
| Add row | 34 high, 14 leading, plus glyph 12 pt and label 13 in `sidebarForeground`, hover `primaryText` | the sidebar's New Tab row |
| Note under a group | 12 `secondaryText`, 8 below, 10 leading, max 560 wide | |
| Switch | 32 x 20, knob 16; off: fill `sidebarItemHovered`, white knob; on: fill `SettingsTokens.switchOn`, white knob (dark: porcelain fill, graphite knob) | new SettingsTokens.switchOn |
| Pop-up button | 26 high, radius 8, fill `sidebarItemHovered`, no edge, chevron.up.chevron.down 9 pt `sidebarForeground` | the sidebar URL pill's shape |
| Pill (neutral) | 28 high, radius 14, padding 16, min width 76, 13 semibold `primaryText`, fill `sidebarItemHovered`, hover `sidebarItemBackground`, no edge | the Archive window's pills |
| Pill, small | 24 high, radius 12, padding 12, 12 semibold | |
| Primary pill | one per pane: `accent` fill, `onAccent` text; hover `accentHighlight`; pressed `accentPressed` | BrandTokens |
| Text link | 13 regular `secondaryText`, hover `primaryText`; destructive: `destructiveText`, underlined on hover | AlertTokens.destructiveText |
| Segmented control | track radius 9, 2 inset, fill `sidebarItemHovered`; segments 80 x 24; plate radius 7 in `tabCurrent` + `tabCurrentShadow` (dark: white 18 %) | |
| Keycaps | 22 high, min 22 wide, radius 6, 12 medium, fill `sidebarItemHovered`, no edge | |
| Shortcut recorder | 26 high, min 150 wide, radius 8, `tabCurrent` fill, the system focus ring | |
| Conflict notice | a row-shaped block inside the group: radius 9, `sidebarItemBackground`, 16 pt exclamationmark.circle in `primaryText`, message 13, caption 12, actions 10 below (primary pill, then the text link 14 after it) | |
| Search field | 32 high, radius 9, `sidebarItemBackground`, magnifier 14 pt `sidebarForeground`, 14 below | the Archive search field |
| Default capsule | 24 high, radius 12, `sidebarItemHovered`, check 12 pt and "Default" 12 semibold `primaryText` | |
| Empty state | 44 pt tile radius 12 `sidebarItemBackground` with a 22 pt glyph, title 15 semibold, detail 12 `secondaryText` max 320 wide, primary pill 16 below | the Archive's empty states |
| Focus ring | the system focus ring (`focusRingType = .default`, `NSColor.keyboardFocusIndicatorColor`); never mustard, never graphite | AppKit |

New tokens (to add to `ShellUI/Theme`, with contrast tests next to `BrandTokensTests`):

| Token | Light | Dark | Use |
|---|---|---|---|
| `SettingsTokens.groupField` | `ArchiveTokens.listField` (p3 #0E0F10 0.035) | black 0.14 | recessed row groups |
| `SettingsTokens.switchOn` | sRGB #202321 (graphite) | sRGB #F4F3EF (porcelain) | switch on fill; the knob is the opposite |
| `SettingsTokens.toolbarMaterial` | `surfaceBrand` 0.82 over the vibrancy view | `surfaceBrand` 0.80 | chrome over scrolled content |
| `AlertTokens.destructiveText` | sRGB #B3261E (6.20:1 on porcelain) | sRGB #FFAAA2 (8.71:1 on graphite) | destructive links and titles |
| `SettingsTokens.separatorIncreasedContrast` | black 0.20 | white 0.20 | group edges with Increase Contrast |

`SettingsTokens.groupFill` and `SettingsTokens.tabTileIdle` from the first pass are dropped. `BrandTokens.focusRing`
is not used by Settings.

Contrast (WCAG 2.x, fills composited over the surface):

| Placement | Light | Dark |
|---|---|---|
| destructive link on the surface | 6.20:1 | 8.71:1 |
| destructive link on the group field | 5.77:1 | 9.20:1 |
| same, row hovered | 5.21:1 | 6.87:1 |
| `secondaryText` caption on the group field | 6.42:1 | 10.12:1 |
| switch on fill against the group field (non-text, 3:1 needed) | 14.01:1 | 15.11:1 |
| graphite on mustard (primary pill) | 8.4:1 | 8.4:1 |

## 5. Motion spec

Gate first (how often is it seen, and why does it move):

| Moment | Frequency | Purpose | Motion |
|---|---|---|---|
| Window opens / closes | occasional | system | AppKit's own window animation; nothing custom |
| Pane switch by click | occasional | spatial continuity | window frame resizes to the new pane, `NSAnimationContext` 0.25 s, timing (0.23, 1, 0.32, 1); old pane fades out over 0.08 s; new pane opacity 0 to 1 and translateY 4 to 0 on `SpringPreset.firm` (0.90 / 0.25 s) |
| Pane switch by keyboard (Cmd-1 to Cmd-7) | frequent for keyboard users | none | instant: new pane and new frame in one step |
| Pane item selection | with the pane switch | state | by click: the `tabCurrent` plate fades in over 0.12 s; by keyboard (Cmd-1 to Cmd-7): instant; no sliding highlight (toolbar items are separate views) |
| Pane item press | occasional | feedback | item scale 0.96 on mouse down, `springyExtraFast` back |
| Switch | occasional | state | knob translateX on `springyFast` (0.80 / 0.18 s, a slight overshoot); the graphite on-fill layer cross-fades 0.15 s |
| Switch press | occasional | feedback | knob stretches to scaleX 1.12 from its leading edge while the mouse is down |
| Segmented control | occasional | state | plate translateX on `firm` |
| Appearance preview | occasional | explanation | toolbar strip translateY -100 % to 0 and page translateY by the strip height, both on `firm`; the sidebar URL pill fades 0.15 s |
| Pill press | occasional | feedback | scale 0.97, 160 ms ease-out; the primary also shows `accentPressed` |
| Shortcut recorder, conflict warning | keyboard-driven | none | instant, no animation |

Rules: transform and opacity only. The one exception is the window frame on a pane switch: that is the NSWindow
itself, resized by AppKit (`setFrame(_:display:animate:)` semantics inside an `NSAnimationContext` group), not a view
animating its bounds. The pane's own layout never animates. Every spring is interruptible: a second click mid-switch
retargets from the presentation values (`SpringDriver` reads `layer.presentation()`).

Reduce Motion: no translate, no overshoot, no animated window frame (the frame jumps); content cross-fades 0.15 s;
toggles and the segmented plate jump to their end state while the fill still cross-fades.
Reduce Transparency: the toolbar material becomes opaque `surfaceBrand`; groups are already opaque.

## 6. Light and dark

Every color above is a `TokenPair`; the prototype's `#<state>&dark` screenshots show the dark side. The window follows
the system appearance (it belongs to no Space, like the Archive). In dark the surface is graphite, groups recess into
black 14 %, the selected pane item lifts in white 20 % (`tabCurrent` dark), switches turn porcelain with a graphite
knob, and the focus ring stays the system's. Mustard appears only as the pane's one primary pill, in both
appearances. Increase Contrast: groups, pop-ups and the search field gain a 1 pt
`SettingsTokens.separatorIncreasedContrast` edge (light black 0.20, dark white 0.20), and the selected pane item's
shadow becomes that edge in dark.

## 7. Keyboard and VoiceOver

- Tab bar: an `NSToolbar` with `selectedItemIdentifier`; each item is a toolbar item with a custom view (the glyph and
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
  window restoration exists), Appearance (Toolbar, full URL), Shortcuts (read-only list) and Advanced (Import browser data,
  data folder) rows; the rest are disabled. Each later feature enables its row and adds its UI test.
- As built (#307): panes are frame-laid-out blocks (`SettingsPaneView`, `SettingsGroupView`, `SettingsRowView`) rather
  than `NSStackView`s, so the window height is exact for each pane; the pane bar is custom item views in a tab group
  rather than an `NSToolbar` (section 1: no toolbar strip). The store is `AppSettings` in ShellUI (next to
  `ToolbarSetting` and `PeekLinkSettings`, which it wraps unchanged), so its tests run without the app; the app passes
  its defaults suite. Besides the rows above, the first build also enables Settings > General > Links (the Peek
  switches, #348) and Appearance > Count Favorites and Command-9 (#351), whose features exist. The window position is
  kept in the same suite (`settingsWindowTopLeft`) instead of AppKit's frame autosave, which writes the standard
  defaults.

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
2. Escape closes Settings: **yes** (inside a shortcut recorder, Escape cancels the recording first; in the Shortcuts
   search field it clears a non-empty search first).
3. Native ad and tracker blocking (BH-206): **not offered now**; no row.
4. Rows for features not built yet: **shown disabled**, not hidden. Label in `secondaryText`, control at 42 % and not
   enabled, the caption ends with "Not available yet." (prototype flag `&today`, screenshots `general-today`,
   `appearance-today`).
5. Window width: **680 pt**.
6. "Update Arkt automatically": **not before the release work** (#128); shown disabled per decision 4, off.

## 11. Screenshots

Rendered at 2x with the project's Chromium in headless mode from the prototype (`--window-size=760,<window height +
80>`, the height read from the prototype's `data-h`, `--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`), into `design/settings/screens/<state>-<light|dark>.png`:
general, general-default, spaces, appearance, shortcuts, shortcuts-recording, shortcuts-conflict, extensions,
extensions-empty, privacy, advanced, plus general-today and appearance-today (disabled rows, hash `&today`) (26 files).
