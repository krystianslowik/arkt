# Arkt - Arc 1:1 parity spec (target Arc for macOS 1.168.0)

Status: authoritative merge of the two Arc behavior catalogs. Every row cites evidence; nothing here is invented.
Rows that the sources cannot settle are NEEDS-RUNTIME-CHECK and are collected in section 6 for the fresh-Arc test user.

Inputs:
- A catalog of Arc's published behavior (help center, release notes, community). Cited as `P` plus the
  catalog's own source keys (KS, PK, RN23 v1.3.0, ...) and its rule ids (`B-W1`, `B-PK1`, ...).
- A catalog of Arc 1.168.0's default menu shortcuts, UI strings and settings. Cited as `[O default]` (default menu
  shortcuts), `[S]` (UI strings), `[I]` (inference), and by section as "strings catalog x.y".
- Data-model notes: Arc's menu bar (as shown in the app) cited as `[O menu]`, other sections as `DM x.y` or
  "data-model x.y". Their claim that Ctrl-Tab = `cycleTabForward` is wrong (see CF-01).

The source catalogs are private working notes and are not part of this repository; the citation keys are kept so
every row stays traceable.

Arc is frozen: v1.110.1 (Sep 2025) to v1.169.0 are Chromium bumps only, so an un-reversed release note still describes
1.168.0 [P RN24].

## 0. Rules for reading this spec

### 0.1 Precedence (highest first)

1. `[O menu]` Arc's menu bar (as shown in the app). Where it differs from the default menu shortcuts, the menu bar
   wins: Arc remaps key equivalents at launch, so the defaults are only the starting point.
2. `[O default]` Arc's default menu shortcuts, and `[O]` values from the defaults domain / storage files.
3. Official docs, newest first (current help-center article > newer release note > older release note).
4. `[S]` UI strings shipped in the app (label or description present, wiring not proven).
5. Community write-ups `(C)`.
6. `[I]` inference.

The losing claim of every resolved conflict is recorded in section 7.

### 0.2 Status

| Status | Meaning |
|---|---|
| CONFIRMED | Backed by `[O ...]`, or by two independent sources. Independent = two distinct documents: a help-center article, a release-note entry of a different version or date, the default menu shortcuts, the menu bar, the shipped UI strings. Community counts only as the second source next to an official or shipped-strings one, never two community sources alone |
| SINGLE-SOURCE | One official or shipped-string source, nothing contradicting it |
| NEEDS-RUNTIME-CHECK | Community-only, inference-only, sources conflict without a decisive `[O]`, or a value (default, key, timing) is unknown. Listed in section 6 |

A CONFIRMED row can still carry an open sub-question (for example a default value); that sub-question is a separate
NEEDS-RUNTIME-CHECK row.

### 0.3 Notation

- Keys: Cmd, Opt, Ctrl, Shift. `Ctrl-Shift-=` is the key labelled "=/+" with Ctrl and Shift.
- "Today" = unpinned tabs section. "Archive" = Arc's restorable closed-tab store.
- Rebindable action id: the action name Arc uses for a remappable shortcut (DM 5.2). It differs from the menu
  item's own action. `(I)` = mapped by name, not proven. `none found` = no matching id in DM 5.2 (the list is
  string-derived and may be incomplete). `dynamic` = generated per index, no single id.

---

## 1. Keyboard shortcuts (defaults)

All shortcuts are user-remappable (see BH-198). Mouse modifier-clicks are in section 3.

### 1.1 Tabs, windows, sidebar, navigation (global)

| ID | Action | Default shortcut | Context | Rebindable action id | Evidence | Status |
|---|---|---|---|---|---|---|
| KB-001 | New tab: open command bar; result opens as a new Today tab | Cmd-T | global | `newTab` | [O default]; [O menu]; P KS, CBA | CONFIRMED |
| KB-002 | Open command bar prefilled with current URL; Enter replaces current page | Cmd-L | global | `addressBar` (I) | [O default]; [O menu]; P KS | CONFIRMED |
| KB-003 | Dismiss open command bar | Cmd-T or Cmd-L (while bar open) | command bar | none found | P RN23 v0.107 | SINGLE-SOURCE |
| KB-004 | Reload current page via command bar | Cmd-L then Enter (no edit) | command bar | none found | P RN23 v0.107, RN24 v1.32.0 | CONFIRMED |
| KB-005 | New window (same Spaces and tabs) | Cmd-N | global | `newWindow` | [O menu]; P KS, CBA, RN23 Jan 12 2023 | CONFIRMED |
| KB-006 | Blank window | Ctrl-Cmd-N | global | `newBlankWindow` | [O default]; [O menu]; P RN23 Jan 12 2023 | CONFIRMED |
| KB-007 | New incognito window | Cmd-Shift-N | global | none found | [O menu]; P KS. Default menu also maps New Folder here; menu bar wins (CF-02) | CONFIRMED |
| KB-008 | Archive Tab (close current tab; unpinned tab goes to Archive) | Cmd-W | global | `archiveTab` (I) | [O default] "Archive Tab"; P KS | CONFIRMED |
| KB-009 | Close window | Cmd-Shift-W | global | `closeWindow` | [O default]; [O menu] | CONFIRMED |
| KB-010 | Restore last closed tab (also reopens a closed Peek) | Cmd-Shift-T | global | none found | [O default]; [O menu]; P KS, RN23 v1.3.0 | CONFIRMED |
| KB-011 | Undo last sidebar action (reopens closed tab / Peek) | Cmd-Z | global | none found | P RN23 v1.3.0; P CBA "Undo [Last Action]" | CONFIRMED |
| KB-012 | Pin / unpin current (or selected) tab | Cmd-D | global | `pinTab` | [O default]; [O menu]; P KS, PT | CONFIRMED |
| KB-013 | Copy URL (tracker-stripped; all selected tabs if multi-selected) | Cmd-Shift-C | global, Peek | `copyCurrentURL` | [O default]; [O menu]; P KS | CONFIRMED |
| KB-014 | Copy URL as Markdown | Cmd-Shift-Opt-C | global, Peek | none found | [O default]; [O menu]; P KS, RN23 v1.5.0 | CONFIRMED |
| KB-015 | Copy URL as Quote | Ctrl-Shift-Cmd-C | global | none found | [O default]; [O menu] | CONFIRMED |
| KB-016 | Paste clipboard URL as new tab | Cmd-Opt-V | global | none found | P RN23 v1.1.0 | SINGLE-SOURCE |
| KB-017 | Show / hide sidebar | Cmd-S | global | `showSidebar` | [O default]; [O menu]; P KS, HS | CONFIRMED |
| KB-018 | Show / hide Toolbar | Cmd-Shift-D | global | `toggleToolbar` | [O default]; [O menu] | CONFIRMED |
| KB-019 | Clear Unpinned (Today) tabs of current Space | Cmd-Shift-K | global | `clearExplore` | [O default]; [O menu]; P KS, RN23 v1.17.2 | CONFIRMED |
| KB-020 | Go to sidebar item 1..8 (Favorites counted first by default) | Cmd-1 ... Cmd-8 | global | dynamic | P KS, RN22 Oct 6 2022; [S] "Go to Sidebar Item N" descriptions (Cmd modifier [I]) | CONFIRMED |
| KB-021 | Go to last sidebar item (9th item only if "Switch to ninth tab" is on) | Cmd-9 | global | dynamic | [S] "Go to last Sidebar Item" unless `switchToNinthSidebarItemEnabled`; P RN22 v0.80.0 (configurable). Default per known resolution (CF-07) | CONFIRMED |
| KB-022 | Recent-tab (MRU) switcher forward | Ctrl-Tab | global | `cycleNextTab` (I) | [O default] "Tab Switcher"; P KS, TS | CONFIRMED |
| KB-023 | Recent-tab switcher backward | Ctrl-Shift-Tab | global, switcher | none found | [O default]; P RN23 Apr 13 2023 | CONFIRMED |
| KB-024 | Recent-tab switcher backward (alternate) | Ctrl-` | switcher | none found | P RN23 Apr 27 2023; [S] alternate-shortcut string (key not proven) | SINGLE-SOURCE |
| KB-025 | Close highlighted tab inside switcher | W (Ctrl still held) | switcher | none found | P RN23 Jan 12 2023 | SINGLE-SOURCE |
| KB-026 | Cycle Tab Forward ("through tabs you've previously visited") | Ctrl-Cmd-Right | global | `cycleTabForward` | [O default] | CONFIRMED |
| KB-027 | Cycle Tab Backward | Ctrl-Cmd-Left | global | none found | [O default] | CONFIRMED |
| KB-028 | Next tab in sidebar order | Cmd-Opt-Down | global | `nextTab` | [O default]; [O menu]; P KS, TS | CONFIRMED |
| KB-029 | Previous tab in sidebar order | Cmd-Opt-Up | global | `previousTab` | [O default]; [O menu]; P KS, TS | CONFIRMED |
| KB-030 | Next / previous tab (alternate) | Cmd-} / Cmd-{ | global | none found | P HK, APC (C); ATH (C) lists them as back/forward; not in the default menu | NEEDS-RUNTIME-CHECK |
| KB-031 | Back | Cmd-[ and Cmd-Left | page | `goBack` | [O default]; [O menu]; P KS | CONFIRMED |
| KB-032 | Forward | Cmd-] and Cmd-Right | page | `goForward` | [O default]; [O menu]; P KS | CONFIRMED |
| KB-033 | Next Space | Cmd-Opt-Right | global | `focusNextSpace` | [O default]; [O menu]; P KS, SP | CONFIRMED |
| KB-034 | Previous Space | Cmd-Opt-Left | global | none found | [O default]; [O menu]; P KS, SP | CONFIRMED |
| KB-035 | Go to Space N (by Space order) | Ctrl-1 ... Ctrl-9 | global | dynamic | [O menu]; P KS, SP; [S] "Jumps over to your %@ Space" | CONFIRMED |
| KB-036 | Reveal Current Tab (focus sidebar, scroll to current tab) | Ctrl-Space | global | `focusSidebar` | [O default] "Reveals the current tab in your Sidebar." | CONFIRMED |
| KB-037 | Reveal Tab in Sidebar | unbound | global | none found | [O default] no key | CONFIRMED |
| KB-038 | Type Travel (menu search inside command bar) | unknown | global | `typeTravel` | [S] `typeTravel`, `controlKeyShowsTypeTravel`; default key not proven | NEEDS-RUNTIME-CHECK |
| KB-039 | Exit current context (close Peek, exit full screen) | Esc | context | `exit` | [O default] description | CONFIRMED |
| KB-040 | New Folder | unknown at runtime (the default menu maps Cmd-Shift-N, which the menu bar gives to Incognito) | global | `newFolder` | [O default]; [O menu] (CF-02) | NEEDS-RUNTIME-CHECK |
| KB-041 | Reset tab to pinned URL | unbound | global | `resetTab` | [O default] no key; P RN22 v0.75.0 | CONFIRMED |
| KB-042 | Duplicate selected tabs | unbound | global | `duplicate` | [O default] no key; P RN22 v0.70.1 | CONFIRMED |
| KB-043 | Unbound by default: Show Archive, Clear Archive, Rename, Cast, Capture Full Page, Pretty Screenshot, Collapse/Expand All Folders, Collapse/Expand Pinned Section, Space Manager, New Space, Reset (visible) Pinned Tabs, Clear Cookies and Refresh, Clear Cache and Refresh, Network Inspector, Share | unbound | global | `viewArchive`, `clearArchive`, `rename`, `cast`, `captureFullPage`, `newSpace`, `resetSpace` (I), `clearCookies`, `share`; others none found | [O default] unbound menu items | CONFIRMED |

### 1.2 App, page, tools

| ID | Action | Default shortcut | Context | Rebindable action id | Evidence | Status |
|---|---|---|---|---|---|---|
| KB-044 | New Little Arc Window (in-app menu item) | Cmd-Opt-N | Arc frontmost | `showLittleArc` (I) | [O default]; [O menu] | CONFIRMED |
| KB-045 | Open Little Arc from any app (system-wide hotkey) | Cmd-Opt-N | any app | `showLittleArc` | P KS, LA; [S] system-wide hotkey gated by `globalLittleBrowserHotkeyEnabled`, combo not stated in shipped strings | CONFIRMED |
| KB-046 | Join Meeting (next event's meeting link) | Ctrl-Cmd-J | global | `joinLiveMeeting` | [O default]; P RN24 v1.48.0 | CONFIRMED |
| KB-047 | Cycle through pinned extensions (hold Cmd, tap E) | Cmd-E | global | none found | P RN22 v0.79.0, RN23 v1.6.0 (hold-modifier interaction, so absence from the default menu is not counter-evidence) | CONFIRMED |
| KB-048 | Toggle Developer Mode for the current host | Ctrl-D | global | none found | [O default]; P RN23 v1.2.0 | CONFIRMED |
| KB-049 | Developer Tools | Opt-Cmd-I and F12 | global | `developerTools` | [O default] both keys; [O menu]; P RN24 v1.35.0 | CONFIRMED |
| KB-050 | Inspect element / JavaScript console / View source | Opt-Cmd-C / Opt-Cmd-J / Opt-Cmd-U | page | `inspectElements` / none found / `viewSource` | [O menu]; [O default] | CONFIRMED |
| KB-051 | Toggle full screen | Ctrl-Cmd-F | global | `fullscreen` | [O default]; [O menu] | CONFIRMED |
| KB-052 | Toggle full screen (alternate) | Fn-F | global | none found | P RN23 v1.9.1 | SINGLE-SOURCE |
| KB-053 | Exit full screen (single Esc goes to the website) | hold Esc, or Esc twice | full screen | `exit` | P RN23 v1.11.0, v1.15.0; [S] "To exit full screen, press ..." | CONFIRMED |
| KB-054 | Stop loading | Cmd-. | page | `stopLoading` | [O menu] | CONFIRMED |
| KB-055 | Stop loading | Esc | page (loading) | `exit` (I) | P RN23 v1.10.1 | SINGLE-SOURCE |
| KB-056 | Reload / Force reload | Cmd-R / Cmd-Shift-R | page | `reloadPage` / `forceReloadPage` | [O menu]; P KS (CF-08) | CONFIRMED |
| KB-057 | Actual size / zoom in / zoom out (Cmd-0 also resets trackpad zoom) | Cmd-0 / Cmd-+ / Cmd-- | page | `resetZoom` / `zoomIn` / `zoomOut` | [O menu]; P KS, RN23 v1.2.0 | CONFIRMED |
| KB-058 | Find / Find and Replace / Find Previous / Jump to Selection | Cmd-F / Opt-Cmd-F / Cmd-Shift-G / Cmd-J | page | `find` / `findAndReplace` / `findPrevious` / `jumpToSelection` | [O menu]; P KS | CONFIRMED |
| KB-059 | Find next | Cmd-G | page | `findNext` | P (Chromium default, [I]); not in menu bar | NEEDS-RUNTIME-CHECK |
| KB-060 | Save page as / Print | Cmd-Shift-S / Cmd-P | page | `savePageAs` / `printPage` | [O menu]; P RN23 v0.107 | CONFIRMED |
| KB-061 | Capture (region) | Cmd-Shift-2 | global | `capturePage` | [O default]; [O menu]; P RN24 v1.28.0 | CONFIRMED |
| KB-062 | New Easel | Ctrl-Shift-E | global | `newEasel` | [O default]; [O menu]; P EA. SCOPE: user decision (section 5) | CONFIRMED |
| KB-063 | New Note (opens default notes app since Notes deprecation) | Ctrl-Shift-N | global | `newNote` | [O default]; P RN23 v1.8.0, RN24 v1.39.0. SCOPE: user decision | CONFIRMED |
| KB-064 | New Note in Split | Ctrl-Opt-N | global | none found | [O default]; P ATH (C). SCOPE: user decision | CONFIRMED |
| KB-065 | View Library / Downloads / History | Cmd-Shift-L / Cmd-Shift-J / Cmd-Y | global | `viewLibrary` / `viewDownloads` / `viewHistory` | [O default]; [O menu]; P KS | CONFIRMED |
| KB-066 | Settings | Cmd-, | global | `viewPreferences` | [O menu]; P CS | CONFIRMED |
| KB-067 | New ChatGPT Message (Arc Max) | Cmd-Opt-G | global | `gptMessage` | [O default]; P MX. SCOPE: user decision; feature status unconfirmed (OS-02) | CONFIRMED |
| KB-068 | Peek Email (latest email from the site in Peek; needs Gmail as Favorite) | Cmd-Shift-E | global | `peekEmail` | [O default] | CONFIRMED |
| KB-069 | Minimize / Minimize All / Hide / Hide Others / Quit | Cmd-M / Opt-Cmd-M / Cmd-H / Opt-Cmd-H / Cmd-Q | app | `minimize` / none / `hideArc` / `hideOthers` / `quitArc` | [O menu] | CONFIRMED |

### 1.3 Split View

| ID | Action | Default shortcut | Context | Rebindable action id | Evidence | Status |
|---|---|---|---|---|---|---|
| KB-070 | Add Split View pane (max 4) | Ctrl-Shift-= | global | `addSplitView` | [O default]; [O menu]; P KS (CF-05) | CONFIRMED |
| KB-071 | Close this Split Pane (focused) | Ctrl-Shift-- | split | `removeSplitView` | [O default]; [O menu]; P KS | CONFIRMED |
| KB-072 | Focus split pane N | Ctrl-Shift-1 ... Ctrl-Shift-4 | split | none found | P KS; [S] "Switch to Split View N" action exists, key not proven | SINGLE-SOURCE |
| KB-073 | Focus next / previous split pane (wraparound) | Ctrl-Shift-] / Ctrl-Shift-[ | split | none found | P HK (C); ATH (C) gives the reverse; [S] action "next adjacent window pane with wraparound", key not proven | NEEDS-RUNTIME-CHECK |
| KB-074 | Edit URL of focused pane | Cmd-L | split | `addressBar` (I) | P SV; [O default] | CONFIRMED |
| KB-075 | Expand Current Split / Separate Page from Split View | unbound / unbound | split | none found | [O default], no key; P CBA | CONFIRMED |

### 1.4 Peek, Little Arc, command bar, PiP

| ID | Action | Default shortcut | Context | Rebindable action id | Evidence | Status |
|---|---|---|---|---|---|---|
| KB-076 | Open Little Arc or Peek content in current (most recent) Space as a tab | Cmd-O | Peek, Little Arc | `openTabIn` (I) | [O default]; P PK, LA | CONFIRMED |
| KB-077 | Little Arc: "Open In" menu (choose Space) | Cmd-Opt-O | Little Arc | `openTabIn` (I) | P LA (current); P RN22 v0.67.0, HK say Cmd-Shift-O; default menu silent (CF-13) | NEEDS-RUNTIME-CHECK |
| KB-078 | Close Peek | Cmd-W or Esc | Peek | `archiveTab` (I) / `exit` | P PK, RN23 v1.6.0; [O default] description | CONFIRMED |
| KB-079 | Reopen closed Peek | Cmd-Shift-T or Cmd-Z | global | none found | P RN23 v1.3.0; [S] "Undo prompt for re-opening a closed Peek" | CONFIRMED |
| KB-080 | Close Little Arc window and its quick-lookup bar | Cmd-W | Little Arc | `archiveTab` (I) | P RN24 v1.26.0; [S] "Click 'Open in' ... or Cmd-W to close" | CONFIRMED |
| KB-081 | Enter action search | Tab immediately after Cmd-T | command bar | none found | P RN23 v0.105, RN24 v1.36.0 | CONFIRMED |
| KB-082 | Scope query to a site-search engine | type alias (e.g. "yt") then Tab | command bar | none found | P RN23 Apr 13 2023, v1.13.0; [O] `migratedToTabOnlySiteSearchTrigger` | CONFIRMED |
| KB-083 | Delete selected suggestion | Cmd-Opt-Delete | command bar | none found | P RN23 v1.12.0 | SINGLE-SOURCE |
| KB-084 | Close command bar | Esc | command bar | `exit` (I) | P B-CB15 [I]; not published | NEEDS-RUNTIME-CHECK |
| KB-085 | Command bar Cmd-Enter, Opt-Enter, arrow-key wrap | unknown | command bar | none found | P gaps list (unpublished) | NEEDS-RUNTIME-CHECK |
| KB-086 | Instant Links: open top result directly (Arc Max) | Shift-Enter | command bar | none found | P MX, RN24 v1.28.0, v1.47.1; Max status after Aug 2025 unconfirmed | NEEDS-RUNTIME-CHECK |
| KB-087 | PiP seek / play-pause (PiP selected) | Left / Right, Space | PiP | none found | P RN23 v1.14.0 | SINGLE-SOURCE |
| KB-088 | PiP play / pause | hardware Play/Pause key | PiP | none found | P RN22 v0.81.0 | SINGLE-SOURCE |
| KB-089 | Esc closes the print dialog | Esc | print dialog | none found | P RN23 v0.107 | SINGLE-SOURCE |

---

## 2. Behavior rules (acceptance tests)

Each rule is one test: Given (state) / When (action) / Then (observable result). Arc Max, Easels, Notes and Boosts
rules are in section 5, not here.

### 2.1 Sidebar

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-001 | Given the sidebar is visible, when the user presses Cmd-S, then the sidebar hides and the web content takes the full width; pressing Cmd-S again shows it. | P B-SB1 (KS, HS); [O default] | CONFIRMED |
| BH-002 | Given the sidebar is visible, when the user drags the sidebar edge fully to the left, then the sidebar hides. | P B-SB2 (RN24 v1.28.0); [S] `hasHiddenSidebarWithGesture` | CONFIRMED |
| BH-003 | Given a resized sidebar, when the user double-clicks the sidebar edge, then the sidebar returns to its default width. | P B-SB2 (RN22 Feb 16 2022) | SINGLE-SOURCE |
| BH-004 | Given the sidebar is hidden, when the pointer reaches the left window edge, then the sidebar slides out as an overlay over the content (delay and dismissal rules unknown). | P B-SB3 (HTG, RY, WR, all C) | NEEDS-RUNTIME-CHECK |
| BH-005 | Given the sidebar is hidden, when the user briefly presses Option, then (2021 behavior) the sidebar shows. Expected absent in 1.168.0. | P B-SB5 (RN21 May 5 2021) | NEEDS-RUNTIME-CHECK |
| BH-006 | Given the sidebar is hidden, when a new tab or Space is created, then a clickable toast ("New Tab Created" / "New Space Created") appears. | P B-SB4 (RN22 May 19 2022, RN23 Feb 2 2023); [S] "New Space Created" | CONFIRMED |
| BH-007 | Given at least two tabs were viewed, when the user taps Ctrl-Tab once and releases, then the previously viewed tab becomes active with no switcher UI; tapping again returns to the original tab. | P B-CT1 (TB23, RN23 v1.13.0); [O default] | CONFIRMED |
| BH-008 | Given at least two viewed tabs, when the user presses Ctrl-Tab and keeps Ctrl held, then a switcher overlay shows the five most recently viewed tabs with titles and previews; each further Tab advances the highlight. | P B-CT2 (TS, TB23) | CONFIRMED |
| BH-009 | Given the switcher is open, when the user presses Ctrl-Shift-Tab or Ctrl-`, then the highlight moves backwards. | P B-CT3 (RN23 Apr 13, Apr 27 2023); [O default] | CONFIRMED |
| BH-010 | Given the switcher is open with Ctrl held, when the user presses W, then the highlighted tab closes and the switcher stays open. | P B-CT4 (RN23 Jan 12 2023) | SINGLE-SOURCE |
| BH-011 | Given the switcher is open, then it shows Space theme colors and camera/recording indicators, and the page behind is not dimmed. | P B-CT5 (RN22 v0.68.1, RN23 Jan 26 2023, v1.5.0) | CONFIRMED |
| BH-012 | Given tabs viewed in two Spaces and two windows, when the user opens the switcher, then it lists tabs across Spaces (expected) - window scope unknown. | P B-CT6 [I]; P conflict 18 | NEEDS-RUNTIME-CHECK |
| BH-013 | Given several previously visited tabs, when the user presses Ctrl-Cmd-Right / Ctrl-Cmd-Left, then Arc cycles forwards / backwards through tabs previously visited. How this differs from Ctrl-Tab (overlay, order, wrap) is unknown. | [O default] / description only | NEEDS-RUNTIME-CHECK |
| BH-014 | Given N Favorites and sidebar tabs, when the user presses Cmd-K (K = 1..8), then the K-th sidebar item counting Favorites first becomes active; with "Include Favorites in ordering" off, counting starts after Favorites. | P B-N1 (RN22 Oct 6 2022, KS); [S] descriptions and `excludeFavoritesInSwitchToNthTab` | CONFIRMED |
| BH-015 | Given a default install, when the user presses Cmd-9, then the last sidebar item becomes active; with "Switch to ninth tab" on, the 9th item becomes active. | [S] "Go to last Sidebar Item", `switchToNinthSidebarItemEnabled`; P B-N2 (RN22 v0.80.0) | CONFIRMED |
| BH-016 | Given tabs in the sidebar, when the user presses Cmd-Opt-Down / Cmd-Opt-Up, then the next / previous tab in sidebar order (not MRU order) becomes active. | P B-N3 (TS); [O default] / | CONFIRMED |
| BH-017 | Given the Pinned section is collapsed, when the user presses Cmd-Opt-Down / Up, then pinned tabs are skipped. | P B-N4 (RN24 v1.28.0) | SINGLE-SOURCE |
| BH-018 | Given the target tab is scrolled out of view, when it is selected by keyboard, then the sidebar scrolls to it and an overflow indicator is shown. | P B-N5 (RN23 v0.111, v1.3.0) | CONFIRMED |
| BH-019 | Given the current tab is scrolled out of view or inside a closed folder, when the user presses Ctrl-Space, then the sidebar reveals and focuses the current tab. | [O default] description | CONFIRMED |
| BH-020 | Given the sidebar has keyboard focus (after Ctrl-Space), when the user presses arrow keys / Return, then (unknown) selection moves / item opens. | P gaps list; [S] `focusSidebar` | NEEDS-RUNTIME-CHECK |
| BH-021 | Given empty sidebar space, when the user double-clicks it, then the command bar opens for a new tab. | P B-TD4 (RN23 v0.111) | SINGLE-SOURCE |
| BH-022 | Given selected text, when the user drags it into the sidebar, then a new tab searching that text with the default engine is created. | P B-TD5 (RN23 v1.9.1) | SINGLE-SOURCE |
| BH-023 | Given empty sidebar space, when the user drags it, then the window moves. | P B-DR6 (RN22 v0.67.0) | SINGLE-SOURCE |
| BH-024 | Given a Force Touch trackpad and "Haptic feedback when reordering tabs" on (default), when the user reorders tabs, then haptic feedback plays; with the setting off, none. | P B-DR7 (RN23 v1.3.0, v1.5.0); [S] `tabReorderingHapticsDisabled` | CONFIRMED |
| BH-025 | Given two windows, when a window is not key, then its sidebar is dimmed. | P B-WN4 (RN23 v1.12.0) | SINGLE-SOURCE |
| BH-026 | Given a tab, when the user double-clicks it (or right-click > Rename), then an inline rename field opens; the custom title persists. Moving tabs between Spaces does not open rename. | P B-RN1 (RN24 v1.33.0, RN23 v1.20.0); [S] "Double-click to rename" | CONFIRMED |
| BH-027 | Given a tab with back/forward history, when the user duplicates it (right-click > Duplicate, command bar, Opt-drag, or Cmd-click reload), then a copy appears including its history. | P B-RN2 (PT, RN23 v1.5.0, Mar 16 2023) | CONFIRMED |
| BH-028 | Given sidebar tabs, when the user Cmd-clicks tabs, then each is added to a multi-selection; Shift-click selects a contiguous range. | P 1.4 (RN22 v0.69.0, v0.77.0, Mar 31 2022, RN23 v1.10.1) | CONFIRMED |
| BH-029 | Given a sidebar tab, when the user drags it out of the sidebar beyond a threshold, then a new window holding that tab opens (short accidental drags do nothing). | P B-DR5 (RN23 v0.109, v1.12.0) | CONFIRMED |
| BH-030 | Given a pinned or Favorite Gmail, Outlook mail/calendar, Google Calendar, Notion, Confluence, Figma or Linear tab, when the user hovers it, then a Preview card shows; no GitHub preview. Each preview type has its own toggle. | P B-PV1 (PV, RN24 v1.44.1); [S] `*PreviewEnabled` keys | CONFIRMED |
| BH-031 | Given the sidebar URL bar, when the user right-clicks it, then a menu offers show/hide Toolbar. | P gestures (RN23 v1.9.1) | SINGLE-SOURCE |
| BH-032 | Given the Toolbar is hidden, when the user presses Cmd-Shift-D, then a Toolbar with the URL appears above content (setting `topBarURLEnabled`); again hides it. | [O default]; [O] key `topBarURLEnabled`; P STL | CONFIRMED |
| BH-033 | Given the sidebar bottom bar, then it offers "Clear Today tabs", "Clear unselected Today tabs" and (Max) "Organize Today Tabs". | [S] sidebar bottom action strings | SINGLE-SOURCE |

### 2.2 Spaces

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-034 | Given a Space, then it has its own Pinned and Today sections, theme, icon, and exactly one Profile; Favorites are those of its Profile. | P B-SP1 (SP, PR); DM 1.3 [O] | CONFIRMED |
| BH-035 | Given two or more Spaces, when the user clicks a Space icon at the sidebar bottom, swipes two fingers horizontally in the sidebar, presses Ctrl-1..9 or Cmd-Opt-Left/Right, presses mouse buttons 3 / 4 (numbering as published), or picks "Focus on [Space]" in the command bar, then that Space becomes active. | P B-SP2 (SP, KS, RN22 Mar 31 2022) | CONFIRMED |
| BH-036 | Given a Space whose last active tab was T, when the user switches to that Space, then T becomes active. | P B-SP3 (RN23 v1.3.0) | SINGLE-SOURCE |
| BH-037 | Given Spaces A, B, C with B active, when the user creates a new Space, then it is inserted directly after B. | P B-SP4 (RN23 Apr 27 2023) | SINGLE-SOURCE |
| BH-038 | Given a Space header, when the user clicks the Space title, then it becomes editable; hovering the header shows an edit icon and a "..." menu for theme and Profile. | P B-SP5 (RN23 v1.3.0, v0.110, SP); [S] header tooltips | CONFIRMED |
| BH-039 | Given several Spaces, when the user drags a Space header ("Drag to Reorder Space"), then Space order (and Ctrl-N mapping) changes. | [S] tooltip; P B-SP7 (KS, RN23 v1.19.1) | CONFIRMED |
| BH-040 | Given a Space swipe, then the Space icon animates during the swipe. | P B-SP6 (RN23 v1.17.2) | SINGLE-SOURCE |
| BH-041 | Given Spaces in order 1..N, when the user presses Ctrl-K, then the K-th Space activates (K = 1..9); user-customized Space shortcuts persist across restarts. | P B-SP7 (KS, RN23 v1.19.1); [O menu] | CONFIRMED |
| BH-042 | Given two Spaces, when the user drags a tab sideways past the sidebar edge into another Space, then the tab moves to that Space; if the Profiles differ, a Profile-change prompt appears first. | P B-DR2 (RN22 v0.81.0, PR video) | CONFIRMED |
| BH-043 | Given a single unnamed Space, then the Space header visibility follows `showSpaceHeaderOnSingleUnnamedSpaces` (default unknown). | [S] key | NEEDS-RUNTIME-CHECK |
| BH-044 | Given the Library Space Viewer, when the user drops a tab on an empty Space, then the tab moves there. | P B-DR8 (RN23 v1.19.1) | SINGLE-SOURCE |

### 2.3 Favorites

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-045 | Given two Spaces using the same Profile, then both show the same Favorites as icon tiles above the Space title; a Space with another Profile shows that Profile's Favorites. | P B-FV1 (FV, PR) | CONFIRMED |
| BH-046 | Given 12 Favorites in a Profile, when the user tries to add a 13th, then it is refused; zero Favorites is allowed. | P B-FV2 (FV, RN23 Jan 12 2023, RN22 Jun 30 2022); absence from the shipped strings is not counter-evidence | CONFIRMED |
| BH-047 | Given a tab, when the user drags it above the Space title, or uses command bar "Favorite Tab" / "Move To Favorites", or right-click > Move To > Favorites, then it becomes a Favorite; dragging a Favorite below the Space title un-favorites it. | P B-FV3 (FV, ATHF); [S] onboarding "Drag to add Favorites" | CONFIRMED |
| BH-048 | Given a Favorite, then it keeps a pinned URL, opens cross-site links in Peek, and never auto-archives. | P B-FV4 (FV, PK); [S] Peek setting note "only affects Favorites and Pinned tabs" | CONFIRMED |
| BH-049 | Given many Favorites, then only recently used Favorites stay loaded; others unload. | P B-FV5 (RN23 Feb 9 2023) | SINGLE-SOURCE |
| BH-050 | Given more than 4 Favorites, then the tile grid layout changes (exact layout unpublished). | P B-FV6 (RN23 v1.5.0, M) | NEEDS-RUNTIME-CHECK |
| BH-051 | Given a Favorite playing audio, then it animates music notes; Slack, X, Google Calendar, Gmail (and WhatsApp) Favorites show unread badges; a Google Calendar Favorite shows a Live Calendar "Join" control. | P B-FV7 (RN22 Mar 31/Mar 17 2022, RN23 v0.109, RN24 v1.47.1); [S] `twitterBadgeEnabled`, `whatsAppBadgeEnabled` | CONFIRMED |
| BH-052 | Given a Favorite, when the user changes its icon, then the tile shows the new icon. | P B-FV8 (RN24 v1.30.0) | SINGLE-SOURCE |
| BH-053 | Given a Favorite playing in PiP or audio, when the Favorite is closed, then playback stops. | P B-FV9 (RN23 v0.108) | SINGLE-SOURCE |

### 2.4 Pinned tabs

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-054 | Given a pinned tab, then it belongs to one Space, sits above the Pinned/Today divider, and never auto-archives. | P B-PN1 (PT); DM 1.5 [O] | CONFIRMED |
| BH-055 | Given a Today tab, when the user presses Cmd-D, uses "Pin Tab" / "Pin to [Space or Folder]", drags it above the divider, or right-click > Pin, then it becomes pinned and a toast "Pinned Tab to <Space>" shows; Cmd-D on a pinned tab unpins it ("Un-Pinned Tab from <Space>"). | P B-PN2 (PT, CBA, RN22 Apr 14 2022); [O default]; [S] toasts | CONFIRMED |
| BH-056 | Given a pinned tab, when the user clicks a same-site link, then it navigates in place; a link to another site opens in Peek (see BH-144). | P B-PN3 (PT); [S] Peek setting note | CONFIRMED |
| BH-057 | Given a pinned tab navigated away from its pinned URL, when the user clicks its favicon, or runs "Reset Tab" / "Back to Pinned URL", then it returns to the pinned URL. | P B-PN4 (PT, CBA, RN22 v0.75.0); [S] "Back to Pinned URL" | CONFIRMED |
| BH-058 | Given a navigated pinned tab, when the user Cmd-clicks its favicon, then the tab resets to the pinned URL and the page it was on opens in a new tab. | P B-PN5 (RN24 v1.31.0) | SINGLE-SOURCE |
| BH-059 | Given several navigated pinned tabs in a Space, when the user runs "Reset Space", then every pinned tab in that Space returns to its pinned URL. | P B-PN6 (CBA); [O default] | CONFIRMED |
| BH-060 | Given a navigated pinned tab, when the user runs "Replace Pin with Current Page" or "Edit Pinned URL", then the stored pinned URL changes. | P B-PN7 (CBA, RN23 Jan 12 2023, TB23) | CONFIRMED |
| BH-061 | Given a navigated pinned tab, when the user chooses "Separate From Pinned Tab" (hover affordance), then (expected) the current page detaches into its own tab and the pin resets. | [S] hover string | SINGLE-SOURCE |
| BH-062 | Given a pinned URL that redirects, then the tab title shows the post-redirect page title. | P B-PN8 (RN23 v1.4.0) | SINGLE-SOURCE |
| BH-063 | Given a pinned tab navigated away from its pinned URL, then (per community) no "URL changed" indicator is shown. | P B-PN9 (HE1, C) | NEEDS-RUNTIME-CHECK |
| BH-064 | Given a tab, when it is pinned, then no rename prompt opens. | P B-PN10 (RN24 v1.33.0) | SINGLE-SOURCE |
| BH-065 | Given a named Space with pinned tabs, when the user clicks the caret next to the Space title (or the title, per TB24) or runs "Collapse Pinned" / "Expand Pinned", then the Pinned section collapses / expands; while collapsed the Space header is bold when the last pinned tab is in view; the collapsed state is stored per window. | P B-PN12 (PT, RN24 v1.25.1, v1.27.2, v1.28.0, v1.30.0); [O default]; DM 3.1 `spacesWithCollapsedPinnedSections` | CONFIRMED |
| BH-066 | Given two windows showing the same Space, then pinned and Today tabs appear in both, and a tab's web content is loaded in only one window at a time (Tab Handoff). | P B-PN13 (RN23 v1.5.0, v1.19.1) | CONFIRMED |
| BH-067 | Given the active tab is pinned, when the user presses Cmd-W, then the tab closes but stays pinned in the sidebar ("Close and Keep Pinned"); it is not archived. | P B-W6 (CBA "Close Tab - closes current Pinned tab"); [S] hover "Close and Keep Pinned" | CONFIRMED |
| BH-068 | Given a pinned tab closed with Cmd-W after navigating away, when the user clicks it again, then it reloads at the pinned URL (not the last page). | P B-W6 (HE1, HE2, ZN, all C) | NEEDS-RUNTIME-CHECK |
| BH-069 | Given an already-closed pinned tab is active/selected, when the user presses Cmd-W again, then (per community) the pin is removed and the tab goes to Archive. | P B-W7 (HE2, C) | NEEDS-RUNTIME-CHECK |
| BH-070 | Given a pinned tab, when the user clicks the hover X, then either the tab closes and stays pinned ([S] "Close and Keep Pinned") or the pin is removed (ZN2, C). | P B-W11 (ZN2, C); [S] hover strings | NEEDS-RUNTIME-CHECK |

### 2.5 Today and Archive

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-071 | Given the active tab is a Today tab, when the user presses Cmd-W, then it leaves the sidebar and appears in the Archive (reason manual), restorable. | P B-W1 (KS, AA); [O default] "Archive Tab"; DM 2.2 [O] reason "manual" | CONFIRMED |
| BH-072 | Given several tabs multi-selected, when the user presses Cmd-W, then all selected tabs close at once. | P B-W2 (RN22 v0.81.0) | SINGLE-SOURCE |
| BH-073 | Given a Space with one Today tab and no pinned tabs, when the user archives it, then the window stays open on the empty Space (no window close). | P B-W8 (APC, C) | NEEDS-RUNTIME-CHECK |
| BH-074 | Given tabs or Peeks were closed, when the user presses Cmd-Shift-T or Cmd-Z, then the most recently closed one reopens; repeating walks back further. | P B-W9 (KS, RN23 v1.3.0, APC); [O default] | CONFIRMED |
| BH-075 | Given Today tabs in the current Space, when the user presses Cmd-Shift-K or clicks "Clear" above Today, then every Today tab in that Space is archived with an animation. | P B-TD1 (KS, RN23 v1.17.2); [O default] | CONFIRMED |
| BH-076 | Given a Today tab playing media, when Clear or auto-archive runs, then that tab is not archived. | P B-TD2, B-AA5 (RN22 v0.75.0, v0.76.0) | CONFIRMED |
| BH-077 | Given Today tabs, when the user right-clicks a tab > "Archive Below", then all tabs below it are archived. | P B-TD3 (RN22 Apr 21 2022, RN23 v1.14.0) | CONFIRMED |
| BH-078 | Given Today tabs with some selected, when the user runs "Clear unselected Today tabs", then only the unselected Today tabs are archived. | [S] sidebar action string | SINGLE-SOURCE |
| BH-079 | Given Today tabs, when a new tab opens (command bar, external link), then its position in Today (top or bottom) is unknown; sources disagree by entry point. | P conflict 16 (MX/ATHT vs WWL) | NEEDS-RUNTIME-CHECK |
| BH-080 | Given a fresh install, when a Today tab has not been viewed for 12 hours, then it is auto-archived (reason auto); viewing or clicking a tab resets its timer. | P B-AA1 (AA); [S] banner "Arc archives tabs that you haven't used in the past 12 hours" | CONFIRMED |
| BH-081 | Given Settings > Profiles > "Archive tabs after", then the options are 1 hour, 6 hours, 12 hours, 24 hours, 7 days, 30 days, and never. | [S] threshold strings Arc writes in its settings (known resolution, CF-04) | SINGLE-SOURCE |
| BH-082 | Given a fresh install (no feature flags), when the user opens the "Archive tabs after" picker, then "never" is present or absent - it is gated by an internal flag. | [S] flag; P B-AA6 (AA "cannot be disabled") | NEEDS-RUNTIME-CHECK |
| BH-083 | Given two Profiles, when the user changes "Archive tabs after" for one, then Arc asks whether to apply to all Profiles or only this one; new Profiles inherit the Default Profile's value. | P B-AA2 (AA, RN24 v1.26.0); [S] prompt string; [O] `autoArchiveTimeThresholdsPerProfile` | CONFIRMED |
| BH-084 | Given pinned, Favorite, and foldered tabs idle past the threshold, then none is auto-archived. | P B-AA3 (PT, FO) | CONFIRMED |
| BH-085 | Given auto-archive archives tabs, then a toast "Auto archived N tabs" reports the count. | [S] toast string | SINGLE-SOURCE |
| BH-086 | Given an archived tab or folder, when the user restores it, then it returns to its original Space (obeying Air Traffic Control routes) and a toast "Tab restored to <Space>. Click to view." / "Folder restored to ..." appears; clicking it focuses the item. | P B-AA7 (RN23 v1.19.1, v1.17.2); [S] toasts | CONFIRMED |
| BH-087 | Given archived items, when the user searches the Library Archive or the command bar, then archived items match; "Clear Archive" asks for confirmation and then shows a confirmation toast. | P B-AA8 (LB, RN23 v1.17.2); [S] "Confirmation the Archive has been cleared." | CONFIRMED |
| BH-088 | Given the Archive view, then it can filter by Space, by Little Arc, and by close type (manual vs auto). | [S] filter strings; P B-LA9 (RN24 v1.35.0); DM 2.2 [O] `reason`, `source` | CONFIRMED |
| BH-089 | Given a first auto-archive context, then an auto-archive education banner is shown once and not again after dismissal. | P B-AA9 (RN24 v1.42.0); [S] banner; [O] dismissal counters | CONFIRMED |

### 2.6 Folders

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-090 | Given a folder, then it lives in the Pinned section, its tabs never auto-archive, and folders can nest. | P B-FO1 (FO, RN23 v1.10.1) | CONFIRMED |
| BH-091 | Given a closed folder, when the user drags a tab into it, then the folder stays closed. | P B-FO2 (RN22 v0.72.0) | SINGLE-SOURCE |
| BH-092 | Given a closed folder, when a tab is moved into it, then that tab is shown peeking out under the closed folder. | P B-FO3 (RN23 v1.3.0) | SINGLE-SOURCE |
| BH-093 | Given a closed folder, when the user hovers its title, then a Folder Preview with a search field shows; typing selects the first match; choosing a tab activates it and shows it peeking out under the folder. | P B-FO4 (FO, RN23 v1.7.0); [S] `folderPreviewEnabled` | CONFIRMED |
| BH-094 | Given multi-selected tabs, when the user right-clicks > New Folder (or "New Folder"), then the selection is pinned into a new folder; Shift-selected tabs inside a folder can form a nested folder. | P B-FO5 (RN23 v1.10.1, RN22 v0.77.0) | CONFIRMED |
| BH-095 | Given a folder, when the user right-clicks it, then the menu offers Rename, Change Icon, Duplicate, Share, Copy All Links (includes nested), Paste URL as New Tab, Delete, Move; Opt-right-click adds "Copy All as Markdown Links". | P B-FO6 (FO, RN23 v1.17.2, Apr 13 2023, Jan 19 2023, v0.112; WWF C) | CONFIRMED |
| BH-096 | Given a folder rename field, when the user clicks outside it, then the new name is saved. | P B-FO7 (RN24 v1.27.2) | SINGLE-SOURCE |
| BH-097 | Given folders, when the user runs "Collapse All Folders" / "Expand All Folders", then every folder closes / opens. | P B-FO8 (WR, C); [O default], | CONFIRMED |
| BH-098 | Given two windows, then each window keeps its own set of expanded folders. | DM 3.1 [O] `expandedItems` per window | SINGLE-SOURCE |
| BH-099 | Given a connected GitHub account, when the user creates a GitHub Live Folder, then it auto-populates with PRs and review requests. | P B-FO9 (RN24 v1.38.0, v1.52.0) | CONFIRMED |

### 2.7 Command bar

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-100 | Given any window, when the user presses Cmd-T, then the command bar opens centered in the window; Enter on a URL or query opens it in a new Today tab. | P B-CB1 (CBA, RN21 May 5 2021, RY); [O default] | CONFIRMED |
| BH-101 | Given an active tab, when the user presses Cmd-L, then the bar opens prefilled with the current URL; Enter navigates the current tab (in Split View, the focused pane). | P B-CB2 (KS, SV, RY) | CONFIRMED |
| BH-102 | Given Cmd-L opened, when the user presses Enter without editing, then the page reloads. | P B-CB3 (RN23 v0.107, RN24 v1.32.0) | CONFIRMED |
| BH-103 | Given the bar is open, when the user presses Cmd-T or Cmd-L, then the bar closes. | P B-CB4 (RN23 v0.107) | SINGLE-SOURCE |
| BH-104 | Given a query, then results include open tabs in any Space (choosing one switches to it, caption "Switch to Tab" / "Switch to Split View"), archived tabs, history, Arc actions, extensions, folders and Spaces. | P B-CB5 (MM, CBA, RY); [S] captions | CONFIRMED |
| BH-105 | Given a matching tab inside a closed folder, when the user switches to it, then only that tab is shown under the closed folder. | P B-CB6 (RN23 v0.106) | SINGLE-SOURCE |
| BH-106 | Given the bar just opened with Cmd-T, when the user presses Tab, then the bar enters action search. | P B-CB7 (RN23 v0.105, RN24 v1.36.0) | CONFIRMED |
| BH-107 | Given a site-search alias (e.g. "yt"), when the user types it and presses Tab, then the query is scoped to that engine; Tab is the trigger (Space trigger is behind flags). Popular site searches are seeded on first run. | P B-CB8 (RN23 Apr 13 2023, v1.13.0); [O] `migratedToTabOnlySiteSearchTrigger`, `seededPopularSiteSearches`; [S] flags | CONFIRMED |
| BH-108 | Given a URL on the clipboard, when the bar opens, then "Paste and Go" is a top suggestion. | P B-CB10 (RN23 v1.13.0) | SINGLE-SOURCE |
| BH-109 | Given a suggestion, when the user hovers it and clicks X, or selects it and presses Cmd-Opt-Delete, then it is removed. | P B-CB11 (RN23 v0.104, v1.12.0) | CONFIRMED |
| BH-110 | Given the bar is open, when the user clicks a sidebar item, then the click works (sidebar is not blocked). | P B-CB12 (RN24 v1.27.2) | SINGLE-SOURCE |
| BH-111 | Given the bar is open, when the user switches Space, then suggestions refresh for the new Space/Profile. | P B-CB13 (RN24 v1.48.0, v1.39.0) | CONFIRMED |
| BH-112 | Given a new window opens, then its command bar appears in the centered position. | P B-CB14 (RN23 v1.15.0) | SINGLE-SOURCE |
| BH-113 | Given search suggestions are on, then a dismissable notice "We talk to your search engine to help us suggest results." is shown until explicitly dismissed. | [S] string and `commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed` | SINGLE-SOURCE |
| BH-114 | Given `commandKeyShowsCommandBar` / `controlKeyShowsTypeTravel`, when the user holds Cmd / Ctrl alone, then the command bar / Type Travel opens. Defaults and timing unknown. | [S] keys | NEEDS-RUNTIME-CHECK |

### 2.8 Split View

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-115 | Given a Split View, then it is one sidebar item ("Split Tab") that can be pinned, favorited, renamed, shared and moved. | P B-SV1 (SV, RN22 Jul 14 2022); DM 1.4 [O] `splitView` item | CONFIRMED |
| BH-116 | Given a Split View with 4 panes, when the user tries to add a pane, then no pane is added and a toast "Cannot Add New Pane" appears. | [S] `splitViewMaximumPanesExceeded`, toast, "fourth Split View page"; P B-SV2 (ATH, HK, APC, RN24 v1.33.0) | CONFIRMED |
| BH-117 | Given tabs, when the user presses Ctrl-Shift-=, drags a sidebar tab to the content center (top/bottom center for vertical), drags a tab onto another sidebar tab, runs "Add Right/Left/Top/Bottom Split", uses "+" > New Split, right-clicks multi-selected tabs > "Open in Split View", Opt-clicks the current tab (duplicates it into a split), or clicks Peek's Split button, then a Split View is created. | P B-SV3 (SV, MM, RN23 Feb 9 2023, v1.15.0, v1.19.1, v1.0.1; RN24 v1.27.2, v1.25.1; TB23); [S] onboarding string | CONFIRMED |
| BH-118 | Given a tab dragged onto another sidebar tab, when it is dropped on the left / right half, then it becomes the left / right pane. | P B-SV4 (RN24 v1.28.0) | SINGLE-SOURCE |
| BH-119 | Given two tabs in the Pinned section, when the user creates a split by drag there, then the Split Tab stays in Pinned (does not move to Today). | P B-SV5 (RN24 v1.34.0) | SINGLE-SOURCE |
| BH-120 | Given a Split View, when the user uses the Split Controls button above a pane ("Convert to Horizontal/Vertical Split View"), then orientation flips between side-by-side and top-bottom. | P B-SV6 (RN23 v1.21.0); [S] convert strings | CONFIRMED |
| BH-121 | Given a Split View, when the user right-clicks the Split Tab > "Separate All Tabs", Opt-clicks the Split Tab, or clicks the X above a pane or next to a pane in the sidebar, then the split is separated / that pane is removed. | P B-SV7 (SV, RN23 v1.17.2, CBA); [S] "Remove Tab from Split View" | CONFIRMED |
| BH-122 | Given a Split View, when the user presses Ctrl-Shift--, then the focused pane is removed from the split; per CBA its tab is not closed - where that tab goes (Today, archived) is unknown. | P B-SV7 (CBA "without closing its tab"); [O default] | NEEDS-RUNTIME-CHECK |
| BH-123 | Given a Split View, when the user presses Cmd-W, then the focused pane's tab is archived and the remaining pane(s) expand. | P B-W5 (TB23, C) | NEEDS-RUNTIME-CHECK |
| BH-124 | Given a Split View, when the user runs "Expand Current Split", then the focused pane stays and the other panes leave the split. | P B-SV8 (CBA); [O default] | CONFIRMED |
| BH-125 | Given a Split View with the Toolbar on, then each pane shows its URL; Cmd-L edits the focused pane. | P B-SV9 (RN23 v1.15.0, SV) | CONFIRMED |
| BH-126 | Given a split pane in the sidebar, when the user right-clicks it, then the menu offers Mute (per pane), Duplicate split, Archive Below, Share. | P B-SV10 (RN23 v1.19.1, v1.14.0, v1.21.0); [S] "Share Split View" | CONFIRMED |
| BH-127 | Given a Split Tab, when the user Opt-clicks its close button, then it unsplits instead of closing. Gated by flag `optionClickSplitTabCloseButtonToUnsplitEnabled`. | P B-SV11 (DM 4.3); [S] flag | NEEDS-RUNTIME-CHECK |
| BH-128 | Given a Split View, when the user runs "Switch to Split View N" (N = 1..4) or next/previous pane, then that pane gets focus; next/previous wraps around. | [S] action descriptions; P KS (Ctrl-Shift-N keys) | CONFIRMED |

### 2.9 Little Arc

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-129 | Given Arc is the default browser, ATC default destination is Little Arc and "Links from other apps open in Little Arc" is on, when a link is opened from another app, then it opens in a Little Arc window (no sidebar). | P B-LA1 (LA, ATC); [O] `openExternalLinksInLittleBrowserEnabled`; [S] NUX "Links Open in Little Arc" | CONFIRMED |
| BH-130 | Given any app is frontmost (including Arc in full screen), when the user presses Cmd-Opt-N, then a Little Arc command bar opens above full-screen windows on the current macOS desktop; the result opens in Little Arc. | P B-LA2 (LA, TB23, RN23 Jan 19 2023, v1.8.0, v1.11.0); [S] global hotkey registration | CONFIRMED |
| BH-131 | Given a fresh install, then the global hotkey setting "Open Little Arc when I press <shortcut>" is on or off (default unknown) and fires when Arc is not frontmost. | [S] `globalLittleBrowserHotkeyEnabled`; P KS | NEEDS-RUNTIME-CHECK |
| BH-132 | Given "Open Little Arc when clicking on links with Opt-Cmd held" is on, when the user Opt-Cmd-clicks a link, then it opens in Little Arc; Opt-Cmd-clicking a sidebar tab opens that tab in a Little Arc window. | P B-LA3 (LA, RN22 Oct 6 2022); [O] `optionCommandClickLittleArcEntryPointEnabled` | CONFIRMED |
| BH-133 | Given one Little Arc window, when another external link opens, then a second Little Arc window opens (multiple allowed). | P B-LA4 (RN23 v1.12.0) | SINGLE-SOURCE |
| BH-134 | Given a Little Arc window for link L, when the same link L is clicked again in an external app, then the existing window comes forward; no duplicate. | P B-LA5 (RN23 v1.15.0) | SINGLE-SOURCE |
| BH-135 | Given the user chose Profile P for a domain in Little Arc, when a later link from that domain opens, then P is preselected. | P B-LA6 (RN23 v1.15.0); [S] `domainToProfilePreferences` | CONFIRMED |
| BH-136 | Given a Little Arc window, when the user clicks "Open In" or presses Cmd-O (most recent Space) or Cmd-Opt-O (choose Space), then the page moves into that Space as a Today tab; a Profile-confirm dialog may appear (skippable). | P B-LA7 (LA); [O default]; [S] `shouldBypassConfirmLittleBrowserProfileDialog`, "Move to main window" | CONFIRMED |
| BH-137 | Given an open Little Arc window idle for 6 hours (default, separate setting "Archive Little Arcs after:"), then it is closed and archived. | P B-LA8, B-AA4 (LA, RN23 v1.19.1); [S] label | CONFIRMED |
| BH-138 | Given a Little Arc window is frontmost, when the user presses Cmd-W, then it closes (with its quick-lookup bar) and the page goes to the Archive under the Little Arc filter. | P B-W4, B-LA9 (RN24 v1.26.0, v1.35.0, WWL); DM 2.2 [O] `source.littleArc` | CONFIRMED |
| BH-139 | Given Little Arc windows exist, when the user right-clicks the Dock icon, then "Show/Hide All Little Arc Windows" is offered. | P B-LA10 (LA); [S] "Show Little Arc Windows" / "Close Little Arc Windows" | CONFIRMED |
| BH-140 | Given an ATC rule matches an external link, then the rule's destination wins over Little Arc. | P B-LA11 (ATC, MED C) | CONFIRMED |
| BH-141 | Given a Little Arc window, then extensions, Capture and full-screen video work in it. | P B-LA12 (RN22 Aug 18, Aug 26, Sep 22 2022; RN23 Feb 2 2023) | CONFIRMED |
| BH-142 | Given the user resized a Little Arc window, when a new one opens, then it uses the last size. | DM 4.1 [O] `LittleBrowserWindow_size` | SINGLE-SOURCE |
| BH-143 | Given a fresh install, then the default Little Arc window size and position are unknown. | P gaps list | NEEDS-RUNTIME-CHECK |

### 2.10 Peek

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-144 | Given "Open a Peek window when clicking on links to other sites" is on (default), when the user clicks a link to another site in a pinned or Favorite tab, then it opens in a Peek over the tab; same-site links navigate in place; Today tabs are unaffected. | P B-PK1 (PK, PT); [S] `modalEnabled` label and note | CONFIRMED |
| BH-145 | Given "Open a Peek window when clicking on links with Shift held" is on (default), when the user Shift-clicks any link in any tab, then it opens in Peek. | P B-PK2 (RN23 v0.111); [S] `disableShiftClickToOpenLinksInModal` | CONFIRMED |
| BH-146 | Given a meeting link in a pinned tab, when clicked, then it opens in a new tab, not Peek. | P B-PK4 (RN23 v1.2.0) | SINGLE-SOURCE |
| BH-147 | Given an ATC rule matching a Peek's URL, when the Peek opens, then the rule's destination is used. | P B-PK5 (RN24 v1.25.1) | SINGLE-SOURCE |
| BH-148 | Given a Peek, then its top-right controls are expand (Cmd-O; opens as a Today tab), Split (makes a Split View with the source tab) and close (X). | P B-PK6 (PK, RN24 v1.25.1); [O default] | CONFIRMED |
| BH-149 | Given a Peek, when the user clicks outside it, clicks X, presses Cmd-W or Esc, or drags it to dismiss, then the Peek closes and the source tab stays. | P B-PK7, B-W3 (PK, RN23 v1.6.0, Mar 16 2023); [O default] description | CONFIRMED |
| BH-150 | Given a Peek was just closed, when the user presses Cmd-Shift-T or Cmd-Z, then it reopens. | P B-PK8 (RN23 v1.3.0); [S] undo prompt string | CONFIRMED |
| BH-151 | Given a Peek with "Show Toolbar", then the Toolbar renders inside it; Copy URL and Copy URL as Markdown act on the Peek's URL. | P B-PK9 (RN24 v1.39.0, RN23 Mar 2 2023, v1.5.0) | CONFIRMED |
| BH-152 | Given a Peek, then it is not saved as a sidebar item and does not survive a restart. | P B-PK10 (PK); DM 4.2 | CONFIRMED |
| BH-153 | Given Gmail is a Favorite, when the user presses Cmd-Shift-E, then the latest email from the current site opens in Peek. | [O default] description | CONFIRMED |
| BH-154 | Given a Peek, then its size and position are unpublished. | P gaps list | NEEDS-RUNTIME-CHECK |

### 2.11 Air Traffic Control

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-155 | Given Settings > Links, when the user adds a route, then its condition is a URL that "contains" text or "matches" (is equal to) a URL, and its destination is a Space (or Little Arc / Most Recent Space / a Profile). | P B-ATC1 (ATC); [S] `contains`/`matches`, `LinkDestination` cases | CONFIRMED |
| BH-156 | Given no route matches, when a link opens from another app, then it goes to the default destination: Little Arc (default), Most Recent Space, or a chosen Space. | P B-ATC2 (ATC, DM 4.5); [S] `LinkDestination` | CONFIRMED |
| BH-157 | Given a route, then it applies to external links, Peeks and archive restores. | P B-ATC3 (ATC, RN24 v1.25.1, RN23 v1.17.2) | CONFIRMED |
| BH-158 | Given a route to Space S, when S is deleted, then the route is deleted. | P B-ATC4 (ATC, SP) | CONFIRMED |
| BH-159 | Given a fresh install, when a Google Meet link opens from another app, then it opens in the current (most recent) Space and a toast "Meet links now open in your current Space!" with "Choose where they open" appears (limited number of times). | P B-ATC5 (RN23 v0.111); [O] `didSetDefaultGoogleMeetRoute`, `showAutoRouteMeetToastCount`; [S] toast | CONFIRMED |
| BH-160 | Given two routes match the same link, then which wins is unpublished. | P B-ATC6 (gap) | NEEDS-RUNTIME-CHECK |
| BH-161 | Given a routed link lands in a non-active Space, then a toast ("Tab moved! Click to go there." or equivalent) offers to jump there. String sits among debug strings. | [S/I] toast | NEEDS-RUNTIME-CHECK |

### 2.12 Links and clicks

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-162 | Given a page, when the user Cmd-clicks a link, then it opens in a new background tab (Today). | P 1.4 (MC, STL; C) | NEEDS-RUNTIME-CHECK |
| BH-163 | Given a page / sidebar, when the user middle-clicks a link / a sidebar tab, then the link opens in a background tab / the tab closes. | P 1.4 (MC; C) | NEEDS-RUNTIME-CHECK |
| BH-164 | Given a page, when the user Opt-clicks a link, then (Chromium default: download) - unpublished for Arc. | P gaps list [I] | NEEDS-RUNTIME-CHECK |
| BH-165 | Given a tab with history, when the user Cmd-clicks or middle-clicks Back / Forward, then that history entry opens in a new tab. | P 1.4 (RN23 v1.6.0) | SINGLE-SOURCE |
| BH-166 | Given a tab with history, when the user long-presses or right-clicks Back, then the tab history list appears. | P 1.4 (RN23 v1.3.0, v1.5.0) | CONFIRMED |
| BH-167 | Given a link, when the user hovers it for 1.5 s, then the status pill shows the full URL; when the pointer approaches the pill, the pill moves away. | P gestures (RN23 Apr 20 2023 for the pill; RN24 v1.25.1 for moving away; one note each) | SINGLE-SOURCE |
| BH-168 | Given "Allow window dragging from the top of webpages" is on, when the user drags the top bar area of a page, then the window moves; holding Cmd while dragging opts out. | P B-WN7 (RN23 v0.102); [S] `contentWindowDraggingEnabled` | CONFIRMED |
| BH-169 | Given a page opens an external-protocol link, when the user chooses "always allow" for that site, then later links of that scheme from the site open without prompting. | [O] `arcAlwaysAllowedLinkToSchemesPerSite` | SINGLE-SOURCE |

### 2.13 Windows, Incognito, Profiles

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-170 | Given a window, when the user presses Cmd-N, then a second window opens showing the same Spaces and tabs; Ctrl-Cmd-N opens a Blank Window with no sidebar items. | P B-WN1 (CBA, RN23 Jan 12 2023); [O menu] | CONFIRMED |
| BH-171 | Given Arc is full screen, when a new window opens, then it opens full screen. | P B-WN2 (RN23 v1.6.0, RN24 v1.28.0) | CONFIRMED |
| BH-172 | Given two windows, then Today tabs are shared across windows (not per window). | P B-WN3 (RN23 v1.5.0, v1.19.1) | CONFIRMED |
| BH-173 | Given windows open at quit and "When opening Arc, restore windows from previous session" on, when Arc relaunches, then the previous session's windows and tabs are restored. | P B-WN5 (RN24 v1.42.0); [S] `windowRestorationSetting` | CONFIRMED |
| BH-174 | Given any window, when the user presses Cmd-Shift-N (or Dock menu > New Incognito Window), then an Incognito window opens: no cookies or history persist, an "Incognito" label shows only in the sidebar, extensions run only if enabled for incognito. | P B-WN6 (CBA, RN22 Jun 16 2022, RN23 v1.3.0, v1.6.0); [O menu] | CONFIRMED |
| BH-175 | Given a window in full screen, when the user presses Esc once, then the key goes to the website; holding Esc or pressing it twice exits full screen, and a hint "To exit full screen, press ..." is shown on entry. | P 1.1 Exit full screen (RN23 v1.11.0, v1.15.0); [S] hint | CONFIRMED |
| BH-176 | Given a page locks the pointer, then a hint "Your cursor is hidden. Press 'esc' to show cursor." appears. | [S] hint | SINGLE-SOURCE |
| BH-177 | Given "Warn before quitting" is on, when the user presses Cmd-Q, then Arc asks for confirmation before quitting. | [O] `shouldWarnBeforeQuitting`; P 1.5 (data-model 4.4) | CONFIRMED |
| BH-178 | Given Profiles, then any Profile can serve one or more Spaces; only Profiles not assigned to any Space can be deleted; the Default Profile cannot be deleted. | [S] three strings; P PR | CONFIRMED |
| BH-179 | Given two Profiles, then each has its own Favorites and its own auto-archive threshold. | P B-FV1, B-AA2 (FV, PR, AA) | CONFIRMED |

### 2.14 Downloads and Library

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-180 | Given a download, then it goes to the Library (not a tab); progress, size, time left and cancel show at the bottom of the sidebar; hovering the Library icon lists recent files. | P B-DL1 (RN23 Feb 23 2023, v1.17.2, LB) | CONFIRMED |
| BH-181 | Given the Library was last on section X, when the user opens it again, then it opens on X. | P B-DL2 (RN23 v1.19.1) | SINGLE-SOURCE |
| BH-182 | Given the download-location setting, then downloads either prompt for a location or save to a chosen folder. | [S] `arc.promptForDownload`, `arc.folder`, `arc.other` | SINGLE-SOURCE |

### 2.15 Media and Picture in Picture

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-183 | Given "Enable Picture in Picture when you leave a video tab" is on (default) and the tab is not muted, when the user leaves a tab playing video, then a floating PiP window appears (bottom right on first use). | P B-MP1 (MP); [S] `autoPipGloballyDisabled` | CONFIRMED |
| BH-184 | Given a tab playing audio, when the user leaves it, then an audio controller appears at the bottom of the sidebar; multiple players stack in a media tray; long titles marquee; a "Back to PiP" control exists. | P B-MP2, B-MP6 (MP, RN22 Oct 20 2022, RN24 v1.36.0, RN23 v1.19.1) | CONFIRMED |
| BH-185 | Given a site, when the user disables auto-PiP for it in the Site Control Center (or globally in Settings > Advanced), then leaving its video tab does not open PiP. | P B-MP3 (MP, RN23 v1.9.1); [S] `autoPipDisabledForHosts` | CONFIRMED |
| BH-186 | Given a PiP window, when the user drags a corner or pinches, then it resizes; two-finger scroll while hovering moves it; double-click returns to the source tab and closes PiP; YouTube does not auto-replay. | P B-MP4 (MP, RN22 v0.81.0, v0.79.0, RN23 Jan 12 2023) | CONFIRMED |
| BH-187 | Given the user moved a PiP window, when PiP opens again, then it appears at the last position. | [O] `LastPiPPosition`; [S] video/document variants | CONFIRMED |
| BH-188 | Given a Google Meet call, when the user leaves its tab, then an auto-PiP with meeting controls and chat appears. | P B-MP5 (RN23 v0.112, v1.3.0, RN24 v1.30.0) | CONFIRMED |
| BH-189 | Given a tab using camera or microphone, then the tab shows an indicator ("This tab is using your camera or microphone"). | [S] string; P B-CT5 shows the indicator only for the switcher | SINGLE-SOURCE |

### 2.16 Toasts and notifications

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-190 | Given a toast, then it uses the current Space theme colors and, in a Split View, appears above the pane it concerns. | P B-TS1 (RN24 v1.25.1, RN22 v0.76.0) | CONFIRMED |
| BH-191 | Given a page, when the user presses Cmd-Shift-C, then the clean URL (trackers stripped) is copied and a toast confirms ("Copied a clean link without trackers"; plural "Copied clean links without trackers" for multi-select). Toast duration unknown. | P KS, RN22 v0.69.0, RN24 v1.27.2, v1.53.1; [S] toast strings | CONFIRMED |
| BH-192 | Given the copy toast, then its exact text when no trackers were stripped ("Copied Current URL" vs "Copied a clean link...") and its duration are unknown. | P B-TS3 (gap); [S] both strings | NEEDS-RUNTIME-CHECK |
| BH-193 | Given text is selected on a page, when the user copies the URL, then a toast offers "Share a link directly to this text instead?". | [S] string | SINGLE-SOURCE |
| BH-194 | Given a web notification, when the user clicks it, then Arc focuses the tab that sent it. | P B-TS2 (RN23 v0.111, v1.8.0) | CONFIRMED |
| BH-195 | Given a web page consumes an Arc shortcut, then a toast offers "Edit the shortcut". | [S] toast and comment | SINGLE-SOURCE |
| BH-196 | Given repeated manual use of a feature (copying links, site search, capture), then a one-off education toast suggests the shortcut ("Copy links faster by pressing ...", "... faster with Site Search"). | [S] strings; [O] `superCopyUpsellLastSeen` etc. | SINGLE-SOURCE |
| BH-197 | Given a fresh install, then the JSON Formatter extension is auto-installed and a toast says so. | [S] string; [O] `hasAutoInstalledJsonFormatterExtension` | SINGLE-SOURCE |

### 2.17 Settings and shortcut system

| ID | Rule | Evidence | Status |
|---|---|---|---|
| BH-198 | Given Settings > Shortcuts, when the user records a new key for an action, then it replaces the default; right-click > "Reset Shortcut to Default" restores it; "Reset All Shortcuts" restores all; only user overrides are stored. | P (CS, RN23 v1.19.1, WR); [S] editor strings; DM 4.5 [O] `StorableKeyBindings.json` | CONFIRMED |
| BH-199 | Given the user records a key already used, then the editor says "... is already in use by X" (or "and N other actions") and offers "Remove Conflicting Shortcut(s)"; for system shortcuts it warns "System shortcuts may take priority over this shortcut". | [S] editor strings | SINGLE-SOURCE |
| BH-200 | Given an Arc shortcut that a website also uses, then the per-shortcut mode is one of "Arc wins", "website wins", or "press once for website, twice for Arc". | P (CS, RN23 v1.19.1: "Prefer Websites" / "Prefer Arc"); [S] three option strings, `arcKeyBindingPriority` | CONFIRMED |
| BH-201 | Given a fresh install, then the default priority mode for each action is unknown. | [S] (default not in strings) | NEEDS-RUNTIME-CHECK |
| BH-202 | Given the shortcut editor, then its search accepts a feature name or a shortcut ("like Command E") and lists "Customized Shortcuts" and "Default Shortcuts" sections plus "Extension Shortcuts". | [S] strings | SINGLE-SOURCE |
| BH-203 | Given Settings, then the panes are Account, General, Profiles, Links, Shortcuts, Max, App Icon, Advanced. | [S] pane titles | SINGLE-SOURCE |
| BH-204 | Given the appearance menu "Websites, Easels, and Notes will use:", when the user picks Light, Dark or Automatic, then web content follows it. | [O] `appearance`; [S] menu string | CONFIRMED |
| BH-205 | Given Settings > App Icon, then the icons are original, candy, hologram, neon, flutedGlass, schoolbook, colorful; some are locked behind referrals ("Refer N friends to unlock"). | [O] `availableAppIconNames`; [S] string | CONFIRMED |
| BH-206 | Given "Use Arc's built-in protection against ads, pop-ups, and trackers" is on, then the native blocker is active and other ad-block extensions are disabled. | [O] `nativeAdBlockEnabled`; [S] label | CONFIRMED |
| BH-207 | Given "Play Arc sound effects" is on (default), then UI sounds play. | [S] `playUserInterfaceSoundsDisabled` | SINGLE-SOURCE |
| BH-208 | Given a host, when the user presses Ctrl-D, then Developer Mode toggles for that host only. | [O default]; [S] `developerModeEnabledForHosts`; P RN23 v1.2.0 | CONFIRMED |
| BH-209 | Given a foreign-language page, when translated, then toasts show "Translated to X" / "Translated back to X" / "Translation error"; "Never translate" hosts are remembered. | [S] toasts; [O] `translateNeverHosts` | CONFIRMED |
| BH-210 | Given drag-to-capture is enabled, when the user holds Cmd and Shift and drags, then a capture region starts. | [O default] note; [S] "Hold Command and Shift to start a Capture.", `dragToCaptureDisabled` | CONFIRMED |
| BH-211 | Given a first launch, then the Arc101 onboarding runs: "Open your first tab", "Pin tabs to save for later", "Spaces for work and life", "Multitask with Split View", "Favorites keep your most used sites and apps close" / "Drag to add Favorites". Order and gating unknown. | [S] onboarding strings | SINGLE-SOURCE |
| BH-212 | Given Settings, then a "Block Cookie Banners" option exists with the warning that it "may cause pages to load incorrectly" (key not identified). | [S] strings | SINGLE-SOURCE |
| BH-213 | Given "Automatically update my Arc" is on, then Arc updates itself. | [S] `shouldAutomaticallyUpdate` | SINGLE-SOURCE |

---

## 3. Mouse, trackpad and modifier-click gestures

| ID | Gesture | Where | Result | Related rules | Evidence | Status |
|---|---|---|---|---|---|---|
| GS-001 | Two-finger horizontal swipe | sidebar | previous / next Space; Space icon animates | BH-035, BH-040 | P (SP, RN23 v1.17.2) | CONFIRMED |
| GS-002 | Mouse button 3 / 4 (as published) | anywhere | previous / next Space | BH-035 | P (RN22 Mar 31 2022) | SINGLE-SOURCE |
| GS-003 | Double-click empty area | sidebar | new tab (command bar) | BH-021 | P (RN23 v0.111) | SINGLE-SOURCE |
| GS-004 | Double-click a tab | sidebar | rename | BH-026 | P (RN24 v1.33.0); [S] "Double-click to rename" | CONFIRMED |
| GS-005 | Click a pinned tab's favicon | sidebar | reset to pinned URL | BH-057 | P (PT); [S] "Back to Pinned URL" | CONFIRMED |
| GS-006 | Cmd-click a pinned tab's favicon | sidebar | reset; current page to a new tab | BH-058 | P (RN24 v1.31.0) | SINGLE-SOURCE |
| GS-007 | Drag tab above / below the divider | sidebar | pin / unpin | BH-055 | P (PT) ; P B-DR1 (FV) | CONFIRMED |
| GS-008 | Drag tab above the Space title | sidebar | favorite | BH-047 | P (FV); [S] "Drag to add Favorites" | CONFIRMED |
| GS-009 | Drag tab onto a folder | sidebar | add to folder (closed folder stays closed) | BH-091 | P B-DR3 (FO), B-FO2 (RN22 v0.72.0) | CONFIRMED |
| GS-010 | Drag tab onto another tab (left/right half) | sidebar | Split View, pane order by half | BH-117, BH-118 | P (RN24 v1.27.2, v1.28.0) | CONFIRMED |
| GS-011 | Drag tab to content center (top/bottom center = vertical) | window | Split View | BH-117 | P (SV, RN23 Feb 9 2023); [S] onboarding string | CONFIRMED |
| GS-012 | Drag tab sideways past the sidebar edge | sidebar | move tab to another Space (Profile prompt if needed) | BH-042 | P (RN22 v0.81.0, PR) | CONFIRMED |
| GS-013 | Drag tab out of the sidebar | sidebar | new window with that tab | BH-029 | P (RN23 v0.109, v1.12.0) | CONFIRMED |
| GS-014 | Opt-drag tab | sidebar | duplicate | BH-027 | P (PT, RN22 Oct 6 2022) | CONFIRMED |
| GS-015 | Drag text into the sidebar | sidebar | search tab | BH-022 | P (RN23 v1.9.1) | SINGLE-SOURCE |
| GS-016 | Drag empty sidebar area / page top bar | sidebar / page | move window (Cmd opts out on page) | BH-023, BH-168 | P (RN22 v0.67.0, RN23 v0.102); [S] `contentWindowDraggingEnabled` | CONFIRMED |
| GS-017 | Drag sidebar edge; double-click edge | sidebar | resize (fully left hides); reset width | BH-002, BH-003 | P (RN22 Feb 16 2022, RN24 v1.28.0) | CONFIRMED |
| GS-018 | Hover left window edge with sidebar hidden | window | sidebar slides out | BH-004 | P (HTG, RY; C) | NEEDS-RUNTIME-CHECK |
| GS-019 | Hover folder title | sidebar | Folder Preview with search | BH-093 | P (FO, RN23 v1.7.0) | CONFIRMED |
| GS-020 | Hover pinned / Favorite tile | sidebar | site Preview card | BH-030 | P (PV) ; [S] preview keys | CONFIRMED |
| GS-021 | Hover a link 1.5 s; pointer near status pill | page | full URL in pill; pill moves away | BH-167 | P (RN23 Apr 20 2023, RN24 v1.25.1) | SINGLE-SOURCE |
| GS-022 | Interactive drag-to-dismiss | Peek | close Peek | BH-149 | P (RN23 Mar 16 2023) | SINGLE-SOURCE |
| GS-023 | Click outside the Peek | Peek | close Peek | BH-149 | P (PK, RN23 v1.6.0) | CONFIRMED |
| GS-024 | Long-press or right-click Back | toolbar | tab history menu | BH-166 | P (RN23 v1.3.0, v1.5.0) | CONFIRMED |
| GS-025 | Cmd-click or middle-click Back / Forward | toolbar | history entry in a new tab | BH-165 | P (RN23 v1.6.0) | SINGLE-SOURCE |
| GS-026 | Cmd-click Reload | toolbar | duplicate current tab | BH-027 | P (RN23 Mar 16 2023) | SINGLE-SOURCE |
| GS-027 | Shift-click link | page | open in Peek | BH-145 | P (RN23 v0.111); [S] setting label | CONFIRMED |
| GS-028 | Opt-Cmd-click link / sidebar tab | page / sidebar | open in Little Arc | BH-132 | P (RN22 Oct 6 2022, LA, TB23); [O] key | CONFIRMED |
| GS-029 | Cmd-click link | page | new background tab | BH-162 | P (MC, STL; C) | NEEDS-RUNTIME-CHECK |
| GS-030 | Middle-click link / sidebar tab | page / sidebar | background tab / close tab | BH-163 | P (MC; C) | NEEDS-RUNTIME-CHECK |
| GS-031 | Cmd-click tabs; Shift-click tabs | sidebar | multi-select; range-select | BH-028 | P (RN22 v0.69.0, v0.77.0, Mar 31 2022, RN23 v1.10.1) | CONFIRMED |
| GS-032 | Opt-click current tab | sidebar | duplicate it into a Split View | BH-117 | P (RN23 v1.0.1) | SINGLE-SOURCE |
| GS-033 | Opt-click a Split Tab | sidebar | separate the split into tabs | BH-121 | P (RN23 v1.17.2) | SINGLE-SOURCE |
| GS-034 | Opt-right-click a folder | sidebar | menu adds "Copy All as Markdown Links" | BH-095 | P (RN23 v1.17.2) | SINGLE-SOURCE |
| GS-035 | Hover "+ New Tab" with Cmd held | sidebar | "Paste and Go" | BH-108 | P (RN23 v1.13.0, M) | SINGLE-SOURCE |
| GS-036 | Opt-click "Capture the full page" | Site Control Center | portrait full-page capture | BH-210 | P (RN24 v1.46.0) | SINGLE-SOURCE |
| GS-037 | Hold Cmd-Shift and drag | page | start a Capture region | BH-210 | [S] "Hold Command and Shift to start a Capture."; [O default] note | CONFIRMED |
| GS-038 | Pinch / corner drag; two-finger hover-drag | PiP | resize; move | BH-186 | P (RN22 v0.81.0, RN23 v1.5.0) | CONFIRMED |
| GS-039 | Double-click | PiP | close PiP, return to source tab | BH-186 | P (RN22 v0.81.0) | SINGLE-SOURCE |
| GS-040 | Cmd + scroll | PiP | zoom | BH-186 | P (RN23 Mar 2 2023) | SINGLE-SOURCE |
| GS-041 | Right-click Dock icon | Dock | Show/Hide All Little Arc Windows, New Incognito Window | BH-139, BH-174 | P (LA, RN22 Jun 16 2022); [S] strings | CONFIRMED |
| GS-042 | Right-click sidebar URL bar | sidebar | show / hide Toolbar | BH-031 | P (RN23 v1.9.1) | SINGLE-SOURCE |
| GS-043 | Hover a tab: X / "Archive this tab"; on pinned: "Close and Keep Pinned" | sidebar | archive Today tab; close pinned tab, keep pin | BH-071, BH-067, BH-070 | [S] hover strings; P B-W11 (ZN2, C) disagrees for pinned | NEEDS-RUNTIME-CHECK |
| GS-044 | Shift + hover link (Arc Max) | page | 5-second preview | OS-02 | P (MX); [S] `hoverCardsEnabled` label; Max status after Aug 2025 unconfirmed (P B-MX3) | NEEDS-RUNTIME-CHECK |

---

## 4. Settings

Persisted user settings only (keys Arc registers in UserDefaults, or observed in the defaults domain).
"Default" uses the same evidence tags; `unknown` defaults are NEEDS-RUNTIME-CHECK items (section 6, RT-30).
Values observed in the research user's plist are that user's choices, not defaults, and are not recorded here.

| Key | Label | Type | Default | Affects |
|---|---|---|---|---|
| `autoArchiveTimeThresholdsPerProfile` | "Archive tabs after" (Settings > Profiles) | String (JSON) [O] | 12 hours [S banner] | BH-080, BH-081, BH-082, BH-083 |
| `autoArchiveTimeThreshold` | legacy global threshold | [S] | n/a (migrated) | BH-080 |
| `autoArchiveLittleArcTimeThreshold` | "Archive Little Arcs after:" | [S] | 6 hours (P LA) | BH-137 |
| `excludeFavoritesInSwitchToNthTab` | "Include Favorites in ordering" (inverted) | Bool [S] | false (Favorites included; P KS) | BH-014, KB-020 |
| `switchToNinthSidebarItemEnabled` | "Switch to ninth tab." | Bool [S] | false (Cmd-9 = last item) [S/I] | BH-015, KB-021 |
| `tabReorderingHapticsDisabled` | "Haptic feedback when reordering tabs" (inverted) | Bool [S] | false (haptics on) [I] | BH-024 |
| `showSpaceHeaderOnSingleUnnamedSpaces` | Space header with one unnamed Space | [S] | unknown | BH-043 |
| `modalEnabled` | "Open a Peek window when clicking on links to other sites" ("only affects Favorites and Pinned tabs") | Bool [S] | true [I] | BH-144, BH-056 |
| `disableShiftClickToOpenLinksInModal` | "Open a Peek window when clicking on links with Shift held" (inverted) | Bool [S] | false (Shift-click Peek on) [I] | BH-145 |
| `globalLittleBrowserHotkeyEnabled` | "Open Little Arc when I press <shortcut>" | Bool [O] | unknown | BH-130, BH-131, KB-045 |
| `openExternalLinksInLittleBrowserEnabled` | "Links from other apps open in Little Arc" | Bool [O] | true (P LA, ATC) | BH-129, BH-156 |
| `optionCommandClickLittleArcEntryPointEnabled` | "Open Little Arc when clicking on links with Opt-Cmd held" | Bool [O] | unknown | BH-132 |
| `shouldBypassConfirmLittleBrowserProfileDialog` | skip Profile confirm when moving Little Arc content | Bool [S] | false [I] | BH-136 |
| `arcAlwaysAllowedLinkToSchemesPerSite` | external-protocol "always allow" per site | Dict [O] | empty [I] | BH-169 |
| `searchSuggestEnabled` | "Include search engine suggestions" (Profile pane) | [S] per-profile (likely Chromium pref) | unknown | BH-113 |
| `gptSiteSearchEnabled` | Max: "ChatGPT in the Command Bar" | Bool [O] | unknown | OS-02 |
| `commandKeyShowsCommandBar` | Cmd alone shows command bar | [S] | unknown | BH-114 |
| `controlKeyShowsTypeTravel` | Ctrl alone shows Type Travel | [S] | unknown | BH-114, KB-038 |
| `shouldWarnBeforeQuitting` | "Warn before quitting" | Bool [O] | unknown | BH-177 |
| `windowRestorationSetting` / `restoreWindowsOnNextLaunch` | "When opening Arc, restore windows from previous session" | [S] | unknown (P RN24 v1.42.0 says Arc restores) | BH-173 |
| `contentWindowDraggingEnabled` | "Allow window dragging from the top of webpages" | [S] | unknown | BH-168 |
| `topBarURLEnabled` | Toolbar on/off (Cmd-Shift-D) | Bool [O] | unknown | BH-032, KB-018 |
| `toolbarShowFullURLsEnabledPreference` | "Show full URL when Toolbar is enabled" | [S] | unknown | BH-032 |
| `themeToCSSSharingAllowed` | "Allow websites to get your theme data" | [S] | unknown | (no behavior rule; settings only) |
| `appearance` | "Websites, Easels, and Notes will use:" Light / Dark / Automatic | String [O] | unknown | BH-204 |
| `currentAppIconName` | App Icon | String [O] | `original` [I] | BH-205 |
| `nativeAdBlockEnabled` | "Use Arc's built-in protection against ads, pop-ups, and trackers." | Bool [O] | unknown | BH-206 |
| `translateNeverHosts` | never-translate hosts | Array [O] | empty [I] | BH-209 |
| `playUserInterfaceSoundsDisabled` | "Play Arc sound effects" (inverted) | Bool [S] | false (sounds on) [I] | BH-207 |
| `calendarPreviewEnabled`, `gmailPreviewEnabled`, `outlookEmailPreviewEnabled`, `outlookCalendarPreviewEnabled`, `recentPagesPreviewEnabled`, `folderPreviewEnabled`, `cronPreviewEnabled` | "Show Arc Previews:" per type | Bool [S] | unknown | BH-030, BH-093 |
| `twitterBadgeEnabled`, `whatsAppBadgeEnabled` | Favorite badges | Bool [S] | unknown | BH-051 |
| `autoPipGloballyDisabled` | "Enable Picture in Picture when you leave a video tab" (inverted) | Bool [S] | false (PiP on) [I] | BH-183, BH-185 |
| `autoPipDisabledForHosts` | per-site PiP off | [S] | empty [I] | BH-185 |
| `developerModeEnabledForHosts` | Developer Mode per host | [S] | empty [I] | BH-208 |
| `dragToCaptureDisabled` | Cmd-Shift drag capture (inverted) | [S] | unknown | BH-210, GS-037 |
| `saveCaptureToLibrary` | save captures to Library | [S] | unknown | BH-210 |
| `arc.promptForDownload` / `arc.folder` / `arc.other` | download location | [S] | unknown | BH-182 |
| `shouldAutomaticallyUpdate` | "Automatically update my Arc" | [S] | unknown | BH-213 |
| `shareQuoteLinkEnabled` | "Enable Shared Quotes when highlighting text" | [S] | unknown | BH-193 |
| per-binding `arcKeyBindingPriority` | shortcut conflict mode | [S] | unknown per action | BH-200, BH-201 |
| `renamePinnedTabsEnabled` | Max "Tidy Tab Titles" | Bool [O] | unknown | OS-02 |
| `tidyTabsEnabled` | Max "Tidy Tabs" | Bool [O] | unknown | OS-02 |
| `hoverCardsEnabled` | Max "5-Second Previews" | Bool [O] | unknown | OS-02, GS-044 |
| `instantLinksEnabled` | Max "Instant Links" | Bool [O] | unknown | OS-02, KB-086 |
| `renameDownloadsEnabled` | Max "Tidy Downloads" | [S] | unknown | OS-02 |
| `arcMaxAutoOptInEnabled` | "Automatically enable future Arc Max features" | [S] | unknown | OS-02 |
| `askOnPageEnabled` | "Press Command + F on any page to ask a question" | Bool [O] | n/a (feature removed) | OS-01 |
| `hasDisabledBoostsInPreferences` | "Enable Boosts on websites you visit" (inverted) | [S] | false (Boosts on) [I] | OS-05 |
| `defaultNoteDocumentApp` | "Default Document App" (New Note target) | [S] | unknown | OS-04 |
| `firebaseSyncEnabled`, `cloudKitSyncEnabled` | sync | Bool [O] | unknown | OS-07 |

Feature flags and state fields (not user settings; do not expose as settings, listed so the rebuild does not treat them
as preferences): an internal flag that gates "never", `allowDebugArchivePreference` (internal),
`autoArchiveLittleArcWindowsEnabled`, `autoCleanInactiveTabsEnabled` / `autoCleanInactiveTabsThreshold` (newer
"Clean tabs" path), `tabSuspensionStateIndicatorsEnabled`, `dragToCombineTabsIntoSplitEnabled`,
`optionClickSplitTabCloseButtonToUnsplitEnabled`, `collapsePinnedSectionEnabled`, `colorCodedSyncedSidebarItemsEnabled`,
`littleArcShowsUnderCommandBarEnabled`, `siteSearchSpaceTriggerEnabled`, `keywordSearchSpaceTriggeringEnabled`,
`sidebarDragToSplitPreviewUIEnabled`, `newSplitSeparationMechanismsEnabled`, `escKeyClosesSettingsEnabled`,
`shiftClickModalEntryPointEnabled` (state mirror of the Shift-click setting), `hasHiddenSidebarWithGesture`,
`migratedToTabOnlySiteSearchTrigger`, `seededPopularSiteSearches`, `didSetDefaultGoogleMeetRoute`,
`showAutoRouteMeetToastCount`, `domainToProfilePreferences`, `profileOrdering`, `LastPiPPosition`,
`LittleBrowserWindow_size`, `useChromiumAutoPiP`, `useChromiumAutoPiPForGMeetOnly`, `autoPictureInPictureOnWindowOccluded`, `*UpsellLastSeen`, `*DismissalCount`, `*PresentationCount`. [S]/[O] per strings catalog 2.x.

---

## 5. Out of scope / removed / status-unclear features

Arkt does not decide scope here. Every row is `SCOPE: user decision`.

| ID | Feature | Status in 1.168.0 | Related shortcuts / rules | Evidence | Scope |
|---|---|---|---|---|---|
| OS-01 | Ask On Page (Arc Max) | Removed v1.110.0 (Aug 28 2025); setting key still present in 1.168.0 | `askOnPageEnabled` | P B-MX2 (RN24); [O] key | SCOPE: user decision |
| OS-02 | Arc Max (umbrella): Tidy Tab Titles (pin renames tab to a shorter generated title), Tidy Downloads (rename with "Download renamed!" / "Download name reverted!" undo toast), Tidy Tabs ("Organize Today Tabs", broom on divider when more than 6 Today tabs, "No tab groups found"), Instant Links (Shift-Enter, "Folder of <query>"), 5-Second Previews (Shift-hover), ChatGPT in command bar ("gpt"/"ChatGPT" + Tab, Cmd-Opt-G); org policy `arcMaxDisabledByOrgPolicy` can disable Max | Live per Aug 2025 note: Tidy Tab Titles, Tidy Downloads. Unconfirmed after Aug 2025: Tidy Tabs, Instant Links, 5-Second Previews, ChatGPT | KB-067, KB-086, GS-044, BH-033 | P B-MX1, B-MX3, B-MX4, B-PN11, B-TD6, B-TD7, B-DL3, B-LA13, B-CB9 (MX, MXW, RN24 v1.110.0, v1.43.0, v1.36.0); [O]/[S] Max keys and toasts | SCOPE: user decision |
| OS-03 | Easels (New Easel Ctrl-Shift-E; links to Easels open in Peek) | Shipped (menu item live), no recent changes | KB-062 | P EA, B-PK3 (RN23 Apr 20 2023); [O default]; [O menu] | SCOPE: user decision |
| OS-04 | Arc Notes (Ctrl-Shift-N; New Note in Split Ctrl-Opt-N; empty Note closes by deletion) | Deprecated v1.39.0 (Apr 2024); New Note now opens the default notes app (`defaultNoteDocumentApp`) | KB-063, KB-064 | P B-W10, B-PK3 (RN23 v1.8.0, v1.14.0; RN24 v1.39.0); [O default] | SCOPE: user decision |
| OS-05 | Boosts (per-domain, all Profiles; Site Control Center paintbrush; global toggle in Advanced; disabled in Incognito) | Shipped; Boost sharing and Legacy builder deprecated v1.63.1; JS Boosts not auto-enabled across devices | none | P B-BO1..3 (BO, RN24 v1.61.2, v1.63.1); [S] Incognito string | SCOPE: user decision |
| OS-06 | Live Calendars / Join Meeting (Ctrl-Cmd-J), GitHub Live Folders | Shipped; Live Calendar fix in a Chromium-141 build | KB-046, BH-099, BH-051 | P RN24 v1.48.0, v1.38.0, v1.52.0; [O default] | SCOPE: user decision |
| OS-07 | Sync (Firebase sidebar sync; iCloud sync) | iCloud sync removed v1.48.0; Firebase sync keys present | `firebaseSyncEnabled`, `cloudKitSyncEnabled` | P 2.23 (RN24 v1.48.0); [O] keys | SCOPE: user decision |
| OS-08 | Reader Mode (old Cmd-Shift-R / Opt-Cmd-R) | Removed v1.46.0; `readerMode` action id only, no label or menu item | KB-056 | P 2.23, conflict 9 (RN24 v1.46.0); [S/I] | SCOPE: user decision |
| OS-09 | Sidebar "Recent Tab indicator" | Removed v1.32.0 | none | P B-CT7 (RN24 v1.32.0) | SCOPE: user decision |
| OS-10 | GitHub Preview card | Removed v1.44.1 | BH-030 | P B-PV1 (RN24 v1.44.1) | SCOPE: user decision |
| OS-11 | Share button on Space header | Removed v1.25.1 | none | P 2.23 (RN24 v1.25.1) | SCOPE: user decision |
| OS-12 | Instant Links education hint | Removed v1.47.1 | none | P 2.23 (RN24 v1.47.1) | SCOPE: user decision |

---

## 6. NEEDS-RUNTIME-CHECK list (fresh Arc test user)

Setup for every check: a new macOS user account, a fresh install of Arc 1.168.0, no sign-in data imported, Arc set as
default browser only where the step says so. Record the observed result next to the RT id, then update the spec row's
status to CONFIRMED (or rewrite the rule) and move any losing claim to section 7.

| RT | Spec rows | Question | Test steps |
|---|---|---|---|
| RT-01 | BH-013, KB-026 | Ctrl-Cmd-Right/Left vs Ctrl-Tab | View tabs A, B, C in that order; press Ctrl-Cmd-Right once, then again, then hold; repeat with Ctrl-Cmd-Left; compare to Ctrl-Tab: overlay shown? order? wraps? |
| RT-02 | KB-030, CF-15 | Do Cmd-} / Cmd-{ switch tabs, navigate, or do nothing? | Open 3 tabs; activate the middle one; press Cmd-Shift-] then Cmd-Shift-[; note active tab and URL. Repeat on a page with history |
| RT-03 | KB-038, BH-114 | Type Travel default key; do Cmd-alone / Ctrl-alone open anything? | Settings > Shortcuts, search "Type Travel"; note key. Then tap and hold Cmd alone 1 s, Ctrl alone 1 s, with a page focused; note what opens |
| RT-04 | KB-040, CF-02 | New Folder default key | Settings > Shortcuts, search "New Folder"; note key. Check File menu shows Cmd-Shift-N on New Incognito Window |
| RT-05 | KB-059 | Is Cmd-G find next? | Cmd-F, type a word present twice, Esc focus to page, press Cmd-G; note whether highlight advances |
| RT-06 | KB-073, CF-16 | Next / previous pane keys and direction | Create a 3-pane split; focus pane 1; press Ctrl-Shift-] and Ctrl-Shift-[; note focused pane; check Settings > Shortcuts for "Switch to next/previous Split View" |
| RT-07 | KB-077, CF-13 | Little Arc "Open In" key | From another app press Cmd-Opt-N, open a page; press Cmd-Opt-O, then (new Little Arc) Cmd-Shift-O; note which opens the Space chooser |
| RT-08 | KB-084, KB-085 | Esc, Cmd-Enter, Opt-Enter, arrow wrap in command bar | Cmd-T, type "arc", press Esc (closes?); reopen, press Down past last result (wraps?); type a query, press Cmd-Enter and Opt-Enter separately; note where the result opens |
| RT-09 | KB-086, GS-044, OS-02 | Which Arc Max features are live | Settings > Max: list toggles present. Enable each; test Shift-Enter on a query, Shift-hover a link, "gpt"+Tab, Cmd-Opt-G, broom icon with 7 Today tabs |
| RT-10 | BH-004, GS-018 | Hidden-sidebar reveal on hover | Cmd-S to hide; move pointer to left edge; note reveal, delay (screen recording), overlay vs push, and how it dismisses |
| RT-11 | BH-005 | Option-press reveal | Sidebar hidden; tap Option alone; note whether sidebar shows |
| RT-12 | BH-012 | Switcher scope across Spaces / windows | Space A tab 1, Space B tab 2, second window tab 3, view in that order; hold Ctrl-Tab; note listed tabs and order |
| RT-13 | BH-020 | Sidebar keyboard navigation | Press Ctrl-Space; press Down, Up, Return, Esc; note selection and focus behavior |
| RT-14 | BH-043 | Space header with one unnamed Space | Fresh install with one Space before naming it; note whether the header/title row shows |
| RT-15 | BH-050 | Favorites layout above 4 | Add 1..12 Favorites one at a time; screenshot sidebar at each count and at two sidebar widths |
| RT-16 | BH-063 | "URL changed" indicator on pinned tab | Pin a site, navigate within it to another page; screenshot tab row and hover state |
| RT-17 | BH-068, BH-069, BH-070, GS-043, CF-19, CF-20 | Cmd-W and hover X on pinned tabs | Pin a site, navigate away, press Cmd-W; note sidebar state and Archive; click tab, note loaded URL; with it selected press Cmd-W twice; note pin and Archive. Repeat with hover X on a pinned and on a Today tab |
| RT-18 | BH-073 | Archiving the last tab of a Space | One Space with one Today tab, no pins; Cmd-W; note window state |
| RT-19 | BH-079 | New Today tab position | With 3 Today tabs: open a tab via Cmd-T, via Cmd-click link, and via a link from another app routed to a Space; note position of each |
| RT-20 | BH-082, CF-04 | Options in "Archive tabs after" | Settings > Profiles > Archive tabs after: list all options shown; repeat for "Archive Little Arcs after:" |
| RT-21 | BH-122, BH-123, CF-18 | Ctrl-Shift-- vs Cmd-W in a split | 2-pane split; Ctrl-Shift--: note where the removed tab goes (Today, gone, Archive). Recreate; Cmd-W: note archived tab and remaining layout |
| RT-22 | BH-127 | Opt-click Split Tab close button | Create a split; hover the Split Tab; Opt-click its close button; note unsplit vs close |
| RT-23 | BH-131, BH-143 | Little Arc global hotkey default and geometry | Fresh install, Finder frontmost: press Cmd-Opt-N; note whether it fires. Check Settings > Links toggle state. Note Little Arc window size and position (screenshot) |
| RT-24 | BH-154 | Peek size and position | Pin a site, click an external link; screenshot at 2 window sizes; note insets |
| RT-25 | BH-160 | Route precedence | Create route 1 "contains example" -> Space A, route 2 "contains example.com" -> Space B; open an example.com link from another app; swap rule order and repeat |
| RT-26 | BH-161 | Toast when routed link lands in another Space | Route a domain to Space B while Space A is active; open a link from another app; note toast text |
| RT-27 | BH-162, BH-163, BH-164, GS-029, GS-030 | Modifier and middle clicks on links / tabs | On a page: Cmd-click a link, middle-click a link, Opt-click a link; in sidebar: middle-click a Today tab; note result and tab position |
| RT-28 | BH-192 | Copy URL toast text and duration | Cmd-Shift-C on a URL with no tracking params and on one with `utm_source`; record toast text and duration |
| RT-29 | BH-201 | Default shortcut priority per action | Settings > Shortcuts: for each action, open the conflict-mode menu and record the default |
| RT-30 | section 4 rows with `unknown` default | Default value of each setting | Fresh install: open every Settings pane and record each toggle/picker; run `defaults read company.thebrowser.Browser` before and after first launch |

---

## 7. Conflicts appendix

Each row: the claim kept, the claim rejected, and why (section 0.1 precedence unless stated).

| CF | Topic | Kept | Rejected | Why | Rows |
|---|---|---|---|---|---|
| CF-01 | Ctrl-Tab action | Ctrl-Tab = MRU Tab Switcher; `cycleTabForward` = Ctrl-Cmd-Right ([O default]; P KS, TS) | Ctrl-Tab = `cycleTabForward` (data-model 5.2 note, [I]) | [O] beats inference | KB-022, KB-026 |
| CF-02 | Cmd-Shift-N | New Incognito Window ([O menu]; P KS) | New Folder on Cmd-Shift-N ([O default] default) | The menu bar shows the result; Arc remaps the default. New Folder key itself is unknown | KB-007, KB-040 |
| CF-03 | Cmd-W meaning | "Archive Tab" ([O default]) | "Close current tab or window" (P KS wording) | [O] beats docs; the two agree for Today tabs (close = archive) | KB-008, BH-071 |
| CF-04 | Auto-archive options | Default 12 h; options 1 h, 6 h, 12 h, 24 h, 7 d, 30 d, never ([S] enum cases, banner) | "Auto-archive cannot be disabled" (P AA); options 12 h / 24 h / 7 d / 30 d only (data-model 2.1) | Stated resolution: shipped strings win for 1.168.0. Note: under the generic order [S] ranks below official docs, and "never" is gated by an internal flag, so its visibility stays a runtime check | BH-081, BH-082 |
| CF-05 | Add Split View key | Ctrl-Shift-= ([O default]; [O menu]; P KS) | Cmd-Shift-Plus (P SV article) | [O] plus a second official source; SV article treated as a typo | KB-070 |
| CF-06 | Split pane limit | 4 ([S] "fourth Split View page", toast; P ATH, HK, APC, RN24 v1.33.0) | value unknown (data-model 4.3) | Gap filled by [S] plus community | BH-116 |
| CF-07 | Cmd-9 default | Last sidebar item ([S] "Go to last Sidebar Item" unless `switchToNinthSidebarItemEnabled`) | "default not published" (P B-N2) | Stated resolution; [S] is the only evidence of the default | KB-021, BH-015 |
| CF-08 | Cmd-Shift-R | Force Reload ([O menu]) | Reader Mode (P HK, C) | [O] beats community; Reader Mode removed v1.46.0, `readerMode` id has no menu item | KB-056, OS-08 |
| CF-09 | Double-click a tab | Rename (P RN24 v1.33.0; [S] "Double-click to rename") | Reset to pinned URL (P ZN2, HE1, C) | Official + [S] beat community | BH-026, GS-004 |
| CF-10 | Shift-click link | Peek (P RN23 v0.111; [S] setting label) | Little Arc (P MED, C) | Official + [S] beat community | BH-145, GS-027 |
| CF-11 | Cmd-N | Second window with Spaces and tabs; Blank Window on Ctrl-Cmd-N (P RN23 Jan 12 2023; [O menu]) | Fresh window without tabs (Mar 2022); options menu (Apr 2022) | Newest official note plus [O] | KB-005, KB-006, BH-170 |
| CF-12 | Today tabs across windows | Shared + Tab Handoff (P RN23 v1.5.0, v1.19.1) | Per-window Today (P RN23 v0.106) | Newer note reversed the older | BH-172, BH-066 |
| CF-13 | Little Arc "Open In" key | Cmd-Opt-O provisionally (P LA, current article) | Cmd-Shift-O (P RN22 v0.67.0, HK) | Newest official doc; default menu silent, so runtime check stays open | KB-077 |
| CF-14 | New Easel / New Note keys | Ctrl-Shift-E / Ctrl-Shift-N ([O default]; P EA, RN23 v1.8.0) | Ctrl-Shift-L / Ctrl-N (P ATH, C) | [O] beats community | KB-062, KB-063 |
| CF-15 | Cmd-{ / Cmd-} | unresolved | HK, APC: next/previous tab; ATH: back/forward | Community only and contradictory; not in the default menu | KB-030 |
| CF-16 | Next / previous split pane keys | unresolved (Ctrl-Shift-1..4 kept from P KS) | HK: Ctrl-Shift-] = next; ATH: reversed | Community only and contradictory; [S] proves the action, not the key | KB-072, KB-073 |
| CF-17 | Max Favorites | 12 per Profile (P FV, RN23 Jan 12 2023, RN22 Jun 30 2022) | "not found" in strings (strings catalog 4) | Absence is not evidence: short strings and numbers need not appear in the strings catalog | BH-046 |
| CF-18 | Closing a pane | Two distinct actions kept separate: Ctrl-Shift-- removes the pane "without closing its tab" (P CBA); Cmd-W archives the focused pane's tab and the rest expand (P TB23, C) | merging the two into one rule | Different actions (`removeSplitView` vs `archiveTab`); both still runtime checks | BH-122, BH-123 |
| CF-19 | Cmd-W on pinned tab | Tab closes and stays pinned (P CBA "Close Tab"; [S] "Close and Keep Pinned") | none rejected; unload/reset-on-reopen and second-press-unpins (P HE1, HE2, ZN, C) left open | Community details not corroborated | BH-067, BH-068, BH-069 |
| CF-20 | Hover X on pinned tab | open | Unpins (P ZN2, C) vs closes and keeps pin ([S] hover string) | [S] beats community by precedence, but the [S] string may belong to a different control; runtime check | BH-070, GS-043 |
| CF-21 | Little Arc global hotkey | Cmd-Opt-N (P KS, LA; [O] in-app menu item uses the same combo) | "default not recoverable" (strings catalog 1.3) | Not a contradiction, a gap; enablement default is a runtime check | KB-045, BH-131 |
| CF-22 | Peek setting keys | `modalEnabled`, `disableShiftClickToOpenLinksInModal` (strings catalog 2.4, [S]/[I]) | key names unknown (data-model 4.2) | Gap filled; labels co-located in strings | BH-144, BH-145 |
| CF-23 | ATC model | destinations `space`, `littleArc`, `mostRecent`, `profile`; match styles `contains`, `matches` ([S]) | "other destination cases unknown" (data-model 4.5); help wording "is equal to" | Gap filled; "matches" is the internal name for "is equal to" [I] | BH-155, BH-156 |
| CF-24 | Data-model 5.2 "unknown from menu bar" list | Cmd-W = Archive Tab, Ctrl-Space = Reveal Current Tab (`focusSidebar`), Duplicate unbound, Ctrl-Tab = MRU ([O default]); Cmd-1..9 ([S] + P KS) | "unknown" | Default menu fills them | KB-008, KB-036, KB-042, KB-022, KB-020 |
| CF-25 | Arc Max roster | Tidy Tab Titles, Tidy Downloads live (P RN24 v1.110.0) | MX lists six features, MXW four | Newest official note; the rest stay unconfirmed | OS-02 |
| CF-26 | Option-press shows sidebar | open (expected removed) | 2021 note (P RN21) | No later mention either way | BH-005 |
| CF-27 | New Today tab position | open | top (P MX, ATHT implication) vs bottom for external links (P WWL, C) | Not stated officially | BH-079 |
| CF-28 | Ctrl-Tab scope | open | "across Spaces" (P B-CT6, [I]) | Inference only | BH-012 |
