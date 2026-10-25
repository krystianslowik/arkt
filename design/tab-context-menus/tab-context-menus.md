# Tab context menus design

Design issue: #105 (part of #304). Implementation issue: not filed yet (open question OQ13).
Prototype: [`design/tab-context-menus/prototype.html`](../../design/tab-context-menus/prototype.html).
Screenshots: [`design/tab-context-menus/screens/`](../../design/tab-context-menus/screens/).

## 1. The system in one paragraph

One mechanism, seven menus. Every sidebar row kind (Today tab, pinned tab, Favorite, folder, Split Tab, split
pane, a multi-selection) and the empty sidebar area get a right-click menu, drawn by AppKit as a plain `NSMenu`
exactly like the split row's menu today (`SidebarOutlineController.menu(forRow:)`); the design fixes the items,
their Arc titles, order, key equivalents and enabled rules, not pixels. The bar is "context menu items match
Arc's titles": every title below carries its evidence, and anything the spec cannot confirm is marked
PARITY(NEEDS-RUNTIME-CHECK) instead of being invented. Around the menus sit three small behaviors from the same
issue: double-click a tab to rename it inline (BH-026), double-click empty sidebar space for a new tab (BH-021)
while a drag from the same space moves the window (BH-023), and a dimmed sidebar in a non-key window (BH-025).

## 2. Where the menus open

Right-click and Ctrl-click both open the menu (the existing Ctrl-click branch in `SidebarOutlineView`); plain
tabs and folders, which return nil today, get menus for the first time. The menu opens at the click point,
top-leading corner there, flipping up near the window's bottom edge (AppKit's own placement). Right-clicking an
unselected row selects that row alone before the menu opens (open question OQ10). The URL pill keeps its own
one-item menu (show/hide Toolbar, BH-031) and is out of scope here.

| Target | Menu | Prototype state |
|---|---|---|
| Today tab | Today tab menu (3.1) | `today-menu` |
| Pinned tab | Pinned tab menu (3.2) | `pinned-menu` (with the Move To submenu open) |
| Favorite tile | Favorite menu (3.3) | `favorite-menu` |
| Folder row | Folder menu (3.4) | `folder-menu`, `folder-menu-opt` (Option held) |
| Split Tab row | Split menu (3.5) | `split-menu` |
| Split pane row | Pane menu (3.6) | `pane-menu` |
| 2 or more selected rows | Multi-selection menu (3.7) | `multi-menu` |
| Empty sidebar area | Empty-area menu (3.8) | `empty-menu` |

## 3. The menus

Key equivalents are the defaults from the spec's KB table. The menus are native `NSMenu`s, so the same
equivalents the menu bar shows appear here too; whether Arc's context menus print them is
PARITY(NEEDS-RUNTIME-CHECK) (OQ4). Separator placement is ours; Arc's exact grouping is unverified (OQ11).

### 3.1 Today tab

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Rename | | always | BH-026, KB-043 (`rename` unbound) | CONFIRMED item; opens the inline field (4.1) |
| Duplicate | | always | BH-027, KB-042 (`duplicate` unbound) | CONFIRMED; copy keeps back/forward history |
| Pin Tab | Cmd-D | always | BH-055, KB-012 | title PARITY (OQ1); toast "Pinned Tab to <Space>" (BH-055) |
| Move To > | | always | BH-047 (Favorites), BH-042 (Spaces) | submenu: Favorites, separator, every Space in order; current Space disabled. Contents PARITY (OQ3) |
| Copy Link | Cmd-Shift-C | always | KB-013 | tracker-stripped, as the menu-bar item |
| Archive Below | | at least one Today tab below this one in the Space | BH-077 | CONFIRMED title |
| Archive | Cmd-W | always | KB-008, BH-071 | title PARITY (OQ1): "Archive" vs "Archive Tab" |

Hidden alternates (Option held): Copy Link becomes Copy Link as Markdown (Cmd-Shift-Opt-C, KB-014) and possibly
Copy Link as Quote (Ctrl-Shift-Cmd-C, KB-015). The folder's markdown alternate is CONFIRMED (GS-034); the tab
one is PARITY (OQ5).

### 3.2 Pinned tab

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Rename | | always | BH-026 | CONFIRMED item; pinning itself never opens rename (BH-064) |
| Duplicate | | always | BH-027 | CONFIRMED |
| Unpin Tab | Cmd-D | always | BH-055, KB-012 | title PARITY (OQ1); toast "Un-Pinned Tab from <Space>" |
| Back to Pinned URL | | tab has navigated away from its pinned URL | BH-057, KB-041 (`resetTab`) | [S] title CONFIRMED |
| Replace Pin with Current Page | | tab has navigated away | BH-060 | command bar action; menu presence PARITY |
| Edit Pinned URL | | always | BH-060 | command bar action; menu presence PARITY |
| Move To > | | always | BH-047 | as 3.1 |
| Copy Link | Cmd-Shift-C | always | KB-013 | |
| Close and Keep Pinned | Cmd-W | always | BH-067 | [S] hover string; as a menu title PARITY (OQ1). The tab closes but stays pinned; it is not archived |

### 3.3 Favorite

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Rename | | always | BH-026 | |
| Change Icon | | always | BH-052 | CONFIRMED action; menu title from the folder list (BH-095) |
| Back to Pinned URL | | Favorite has navigated away from its pinned URL | BH-048, BH-057 | PARITY for Favorites (shown disabled in the screenshots) |
| Edit Pinned URL | | always | BH-048 | PARITY |
| Copy Link | Cmd-Shift-C | always | KB-013 | |
| Remove from Favorites | | always | BH-047 (the inverse action) | title [I] PARITY (OQ1) |
| Close and Keep Favorite | Cmd-W | always | BH-053 (closing stops playback) | title [I] PARITY (OQ12) |

### 3.4 Folder

Item set and order are BH-095 (CONFIRMED); separators are ours.

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Rename | | always | BH-095 | CONFIRMED |
| Change Icon | | always | BH-095 | CONFIRMED |
| Duplicate | | always | BH-095 | CONFIRMED |
| Share | | disabled until share support exists | BH-095 | CONFIRMED item; shown disabled per the unbuilt-rows precedent (OQ6) |
| Copy All Links | | always | BH-095 | CONFIRMED; includes nested folders |
| Paste URL as New Tab | Cmd-Opt-V | clipboard holds a URL | BH-095, KB-016 | CONFIRMED; pastes into the folder |
| Move To > | | always | BH-095 ("Move") | Space list, as 3.1 |
| Delete | | always | BH-095 | CONFIRMED; styling plain vs red is OQ7 |

Option held: Copy All Links becomes Copy All as Markdown Links (BH-095, GS-034, CONFIRMED). Both folder states
are screenshot (`folder-menu`, `folder-menu-opt`).

### 3.5 Split Tab row

The first three action items are already built (#56); this design adds the rest per BH-115 (a Split Tab can be
pinned, favorited, renamed, shared and moved).

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Rename | | always | BH-115, BH-026 | |
| Duplicate Split View | | always | BH-126 | [I] title, already shipped |
| Separate All Tabs | | always | BH-121 | CONFIRMED, already shipped |
| Convert to Vertical Split View | | always | BH-120 | CONFIRMED, already shipped; retitled for the current orientation (Horizontal when vertical) |
| Pin Tab | Cmd-D | always | BH-115, KB-012 | title PARITY (OQ1) |
| Move To > | | always | BH-115, BH-047 | includes Favorites (a split can be a Favorite, BH-115) |
| Share Split View | | disabled until share support exists | BH-126 | [S] title; disabled per the unbuilt-rows precedent (OQ6) |

Whether the menu also offers Archive on a Split Tab, and what it would archive, is open (OQ2).

### 3.6 Split pane row

Item set is BH-126 (CONFIRMED: Mute per pane, Duplicate split, Archive Below, Share) plus the removal pair
already shipped (BH-121, BH-123).

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Mute | | always | BH-126 | title PARITY (OQ1: "Mute" vs "Mute Site"); toggles to Unmute while the pane is muted |
| Duplicate Split View | | always | BH-126 | [I] title, already shipped |
| Archive Below | | a pane sits below this one in the split | BH-126 | CONFIRMED title |
| Share | | disabled until share support exists | BH-126 | (OQ6) |
| Remove Tab from Split View | | always | BH-121 | [S] title, already shipped; the pane leaves as its own tab |
| Archive | Cmd-W | always | BH-123 | the pane's tab is archived, the rest expand |

### 3.7 Multi-selection

Right-click any selected row with 2 or more rows selected (BH-028, GS-031 for the gestures).

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| Open in Split View | | 2 to 4 tabs selected | BH-117; BH-116 caps panes at 4 | CONFIRMED title; disabled at 5 or more |
| New Folder | | always | BH-094 | CONFIRMED; the selection is pinned into a new folder |
| Duplicate | | always | KB-042 ("Duplicate selected tabs") | CONFIRMED action |
| Pin Tabs | Cmd-D | always | KB-012 ("current (or selected) tab") | title PARITY (OQ1) |
| Move To > | | always | BH-042 | moves every selected tab; multi move [I] PARITY |
| Copy Links | Cmd-Shift-C | always | KB-013 (all selected tabs) | title PARITY (plural form unverified) |
| Archive | Cmd-W | always | BH-072 | all selected tabs close at once; the "Archived N tabs" undo toast follows (alerts design, decision 3) |

### 3.8 Empty sidebar area

| Item (Arc title) | Key | Enabled | Covers | Evidence |
|---|---|---|---|---|
| New Tab | Cmd-T | always | KB-001; same result as the double-click (BH-021) | menu presence PARITY (OQ11) |
| New Folder | | always | KB-040 | no key equivalent: the menu bar owns Cmd-Shift-N for New Incognito Window (CF-02); menu presence PARITY (OQ11) |
| Paste URL as New Tab | Cmd-Opt-V | clipboard holds a URL | KB-016 | menu presence PARITY (OQ11) |
| Clear Today Tabs | Cmd-Shift-K | the Space has Today tabs | BH-033 [S], KB-019, BH-075 | [S] title |

## 4. Double-click behaviors

### 4.1 Rename (BH-026, GS-004)

Double-click any tab row (or choose Rename) and the row's title becomes an inline text field, in place: the row
keeps its fill and favicon, the field takes the title's exact bounds, 13 pt, the current title fully selected,
white field (graphite in dark) with a 2 pt `focusRing` outline and radius 5. Return commits; Escape cancels and
restores the title; clicking outside commits (as folder rename does, BH-096; the tab behavior is [I]). The
custom title persists (BH-026). Two negative rules stay: pinning a tab never opens the field (BH-064), and
moving a tab between Spaces never opens it (BH-026). The field is single-line; pasting a newline commits. No
animation: the field is simply there (menus and text editing do not spring).

### 4.2 New tab on empty space (BH-021, GS-003)

Double-click anywhere in the sidebar that is not a row, the URL pill, the Favorites grid, the Space title, the
bottom bar or the Pinned/Today divider, and the command bar opens for a new tab, exactly like Cmd-T (KB-001).

### 4.3 Window drag from empty space (BH-023, GS-016)

The same empty area is a window-drag region: pressing and moving drags the window. Both behaviors share the
area because they are distinguished by the gesture, not the target: a double-click without motion opens the
command bar, any motion before mouse-up starts the drag and the double-click never fires. Rows, controls and
the resize edge never drag the window.

## 5. Non-key window dimming (BH-025)

When the window is not key, only the sidebar dims; the content card is untouched (BH-025 scopes the rule to the
sidebar). Proposal (exact values are OQ8): every sidebar child (URL pill, Favorites, Space title, rows, bottom
bar) renders at 60 % opacity, and the theme gradient washes 12 % toward the desktop color, so the dim reads as
the sidebar receding, not as a gray veil over it. The change is instant when the window loses or gains key
status (no animation; Arc's timing is unknown). Toast timers already pause while the window is not key (alerts
design, 4.1). The traffic lights are the system's and keep their look.

## 6. Multi-selection (BH-028, GS-031, BH-072)

- Cmd-click toggles one row in the selection; Shift-click extends a contiguous range from the anchor row
  (BH-028, GS-031). Clicking a row plainly selects it alone.
- Selected rows get the `tabContentVisible` fill (light: white 0.70; dark: P3 #FAFBFF 0.15); the current tab
  keeps `tabCurrent`, and a row that is both current and selected keeps `tabCurrent` (current wins). This
  visual is a proposal (OQ9): the spec confirms the gestures, not the look.
- Cmd-W with 2 or more rows selected archives all of them at once (BH-072) and shows the "Archived N tabs"
  undo toast (alerts design, decision 3); a single selection closes with no toast, as today.
- The selection survives scrolling and collapses only on a plain click, a Space switch, or when a selected row
  leaves the sidebar (archived, moved, pinned out).

## 7. Menu look and layout

The menus are native `NSMenu`s (`menuNeedsUpdate` from `clickedRow`, as today), so AppKit owns the material,
corner radius, shadow, item height and key-equivalent column, and light/dark, Increase Contrast and Reduce
Transparency come free. What this design fixes is structure: item titles and order (section 3), `autoenablesItems
= false` with explicit enabled rules, key equivalents mirroring the menu bar, and hidden Option-alternates
where Arc has them. For illustration the prototype draws the menus with these native metrics (pt): item height
22, font 14, leading inset 12, key column trailing inset 12, separator 1 pt inset 12 with 5 pt above and
below, min width 220, radius 8, surface white at 0.97 (dark #2D2D30 at 0.97), highlight the system accent,
disabled text at 0.35.

The sidebar in the prototype reuses the alerts prototype's window chrome: 190 pt sidebar, 34 pt rows with 9 pt
radius, 16 pt letter tiles, `tabCurrent` on the current row, the Space theme gradient behind everything. Folder
children and split panes indent 18 pt under their parent; a folder row leads with a disclosure chevron, a split
row with a two-pane tile.

## 8. Motion

Nothing here animates on purpose. AppKit plays its own menu open/close; the rename field appears without
animation; selection and dimming change instantly. Reduce Motion therefore changes nothing on this surface, and
Reduce Transparency reaches the menus through AppKit, not through us.

## 9. Keyboard and VoiceOver

- Menus: native `NSMenu` gives arrow-key navigation, type-ahead, Escape, and VoiceOver item reading for free.
  The context-menu key (VO+Shift+M, or the keyboard's menu key) opens the focused row's menu.
- Disabled items are skipped by arrows and read as "dimmed"; the enabled rules in section 3 are the contract.
- Rename field: an `AXTextField` labelled "Tab name" with the current title as its selected value; committing
  returns focus to the row. VoiceOver announces "Rename, text field" when it opens.
- Multi-selection: Cmd/Shift-click is pointer-only, so the sidebar's keyboard focus (Ctrl-Space, KB-036) gets
  no multi-select gestures for now (the arrow-key behavior with sidebar focus is itself BH-020,
  NEEDS-RUNTIME-CHECK); open question OQ14. VoiceOver users multi-select with VO+Cmd+Return per row once the
  rows expose it.
- The dimmed non-key sidebar is purely visual; VoiceOver output does not change with key status.

## 10. Parity notes

- CONFIRMED titles taken verbatim from the spec: Archive Below (BH-077), Open in Split View (BH-117),
  New Folder (BH-094), the folder menu's Rename / Change Icon / Duplicate / Share / Copy All Links /
  Paste URL as New Tab / Delete / Move (BH-095), Copy All as Markdown Links (GS-034), Separate All Tabs and
  Remove Tab from Split View (BH-121), Convert to Vertical / Horizontal Split View (BH-120), Back to Pinned URL
  (BH-057), Clear Today Tabs (BH-033), Share Split View (BH-126), Close and Keep Pinned as a string (BH-067).
- PARITY(NEEDS-RUNTIME-CHECK): exact titles for Pin Tab / Unpin Tab, Archive vs Archive Tab on a row,
  Close and Keep Pinned as a menu item, Remove from Favorites, Pin Tabs, Copy Links (plural), Mute,
  Close and Keep Favorite; the Move To submenu contents; key equivalents printed in context menus; Copy Link's
  Option-alternates on tab rows; the empty-area menu's contents.
- CF-02 stands: New Folder shows no key equivalent because the default menu's Cmd-Shift-N is claimed by New
  Incognito Window (KB-007).
- The pin/unpin toasts (BH-055) and the multi-archive undo toast (BH-072) are already designed in
  `docs/design/alerts-sheets-toasts.md`; this design adds nothing to them.
- Duplicate keeps the tab's full back/forward history (BH-027); Opt-drag and Cmd-click on Reload are the same
  action by other gestures (GS-014, GS-026) and need no menu presence.

## 11. Open questions

1. Exact titles the spec does not pin down: Pin Tab vs Pin; Unpin Tab; Archive vs Archive Tab on a row;
   Close and Keep Pinned as a menu title; Remove from Favorites; Pin Tabs and Copy Links on a multi-selection;
   Mute vs Mute Site on a pane.
2. Does a Split Tab row's menu offer Archive, and if so does it archive every pane or the focused one
   (BH-123 covers only Cmd-W on the focused pane)?
3. Move To submenu: Favorites plus every Space in order, current Space disabled - correct contents and
   order? Is there a New Space item at the bottom?
4. Do Arc's context menus print key equivalents? Arkt's native menus will show the menu-bar ones.
5. Copy Link's Option-alternates on tab rows: Copy Link as Markdown only, or also Copy Link as Quote (KB-015)?
6. Settings precedent shows unbuilt rows disabled: keep Share (folder, split) and Change Icon visible but
   disabled until built, or omit them?
7. Destructive items (folder Delete): plain title, or red text?
8. Non-key dimming: accept 60 % content opacity + 12 % theme wash, and the instant transition?
9. Multi-selection fill: accept `tabContentVisible`, current tab keeps `tabCurrent`?
10. Right-clicking an unselected row: replace the selection (standard macOS) or keep it?
11. Empty-area menu contents (New Tab, New Folder, Paste URL as New Tab, Clear Today Tabs) are partly [I]:
    which items does Arc really show there, and is this the right separator grouping everywhere?
12. Favorite menu close item: present, and titled Close and Keep Favorite?
13. File the implementation issue with acceptance criteria from sections 3-6.
14. Keyboard multi-select with sidebar focus (VO+Cmd+Return or Shift-arrows): design now or with BH-020?

## 12. Screenshots

Rendered at 2x with the project's Chromium in headless mode from the prototype (`--window-size=1080,760`,
`--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`), into
`design/tab-context-menus/screens/<state>-<light|dark>.png`: today-menu, pinned-menu, favorite-menu,
folder-menu, folder-menu-opt, split-menu, pane-menu, multi-menu, empty-menu, rename, dimmed (22 files). The
empty-menu state shows a short Today section so the menu sits fully inside the empty area it belongs to. All
titles, URLs and domains are synthetic (example.com family).
