# Archive search, filters, Clear Archive and the education banner design

Design issue: #111 (part of the design-first rule in #304). Implementation issue: to be filed after this design merges.
Prototype: [`design/archive-search/prototype.html`](prototype.html). Screenshots:
[`design/archive-search/screens/`](screens/).

## 1. The window in one paragraph

The Archive window keeps its quiet job — list what was closed, restore it — and gains the three things a growing
archive needs to stay useful: a search field in a new header row, a filter button next to it, and Clear Archive in
the footer, far from Restore. Searching filters the list live, matches without case or diacritics, and finds tabs
inside archived folders; the filters narrow by Space or Little Arkt and by close type, and show themselves as
removable chips so an invisible filter never hides an item. Clear Archive asks once, with the count in the question
and no Return key on the destructive button, then confirms with a toast. The first time auto-archive has something
to explain, a one-time banner at the top of the list says what happened and where to turn it off. The command bar
gains archived matches with a "Restore from Archive" caption, so a closed tab is one Cmd-T away.

## 2. What changes, mapped to the spec

| Element | Behavior | Spec |
|---|---|---|
| Search field in the Archive window header | Live store-side filtering of the list | BH-087 (Archive search half) |
| Unicode case- and diacritic-insensitive matching, incl. folder children | "ü" matches "u", a folder matches when any child's title or URL matches | BH-087; week-1 Track D follow-up |
| Archived results in the command bar | Archived items match queries; Enter restores | BH-087 (command bar half), BH-104 |
| Clear Archive | Menu item (unbound, KB-043) and footer button; confirmation, then a confirmation toast | BH-087, KB-043 |
| Filters by Space, by Little Arkt, by close type | One source filter + one close-type filter, combinable with search | BH-088 |
| Auto-archive education banner | Shown once after the first auto-archived item exists; never again after dismissal | BH-089 |

The store already models all of it: `ArchiveFilter(source:reason:text:)` in `ArchiveQuery.swift`, `ArchiveReason`
(manual/auto) and `ArchiveSource` (space/littleArc/unknown) in `ArchivedItem.swift`, and `ArchiveStore.removeAll`
("Clear Archive (BH-087). The confirmation dialog is the caller's."). What is missing store-side is exactly the
Track D follow-up: the text match is an ASCII-only LIKE; it must become Unicode case/diacritic-insensitive
(`search_text` column or FTS5) and cover folder children.

## 3. The search field

**Placement.** A new 52 pt header row under the title bar, above the list: the search field fills the row (12 pt
margins), the filter button sits at its trailing edge. This is the Finder window's arrangement shrunk to one
control, and it keeps the title bar untouched. The field is the Settings design's search field (28 high, radius 7,
`sidebarItemBackground`, magnifier glyph in `secondaryText`), identifier `archive.search` (already reserved in
`AXID.Archive`).

**Focus behavior.** When the window opens, focus is on the table, not the field: the Archive is a restore surface
first, and arrow keys must work at once. Cmd-F focuses the field (standard Find key; Find has no other meaning in
this window). Typing does not jump from the table to the field (no type-to-search; see open question 7). Down
arrow from the field selects the first row and moves focus to the table.

**Escape.** With a non-empty query, Escape clears the query (standard `NSSearchField`) and the list reloads
unfiltered. With an empty query, Escape closes the window — today's behavior, and the same rule Settings uses
(decision 2 there).

**Matching.** Every keystroke (debounced 150 ms) queries the store, not the loaded pages: search covers the whole
archive, so "Load More" is never needed to find something. The match is Unicode case- and diacritic-insensitive
(`localizedStandardContains` semantics) over the item's title and URL. A folder or Split View matches when its own
title matches or when any tab inside it matches; restoring a folder matched through a child restores the whole
folder (there is no partial restore). When a folder matched only through a child, the detail line says so:
"Folder, 4 tabs - Work, Yesterday - contains "Q3 report outline" - Closed" (proposal, open question 6).

**Result presentation.** Rows stay in newest-first order; the matched substring is highlighted in the title and
detail at 35 % accent fill. While a query or filter is active, the footer label shows the count: "3 results", or
"3 of 7 items" when only filters narrow the list. No matches: a centered "No Results" with 'The Archive has no
items matching "zebra".' under it; Restore and Load More are disabled.

## 4. The filters (BH-088)

**The button.** A 28 x 28 icon button (`line.3.horizontal.decrease.circle`) at the trailing edge of the header.
With any filter active it switches to the filled glyph and carries a small ink dot at its top-trailing corner — the
mustard accent stays reserved, so "a filter is on" reads in ink, not brand color.

**The menu.** The button opens a native `NSMenu` (224 pt) with two sections:

- **Space**: Everywhere (default) — then one item per Space with its theme dot — then Little Arkt. These are the
  `ArchiveSource` cases; "unknown" sources (old Arc imports) match Everywhere and are not listed as a filter.
- **Close Type**: Closed and Auto Archived (default) — Closed — Auto Archived. These are the `ArchiveReason` cases.

One selection per section, checkmarked; the two sections and the search text combine (AND), which is exactly what
`ArchiveFilter` expresses. Choosing the default in a section clears that section.

**The chips.** While any filter is active, a 22 pt chip strip appears between the header and the list: one capsule
per active filter ("Work" with the theme dot, "Little Arkt", "Closed"), each with an xmark that removes it, plus a
trailing "Clear Filters" link. The strip exists so state that hides rows is always visible and one click from
being undone — an archive that looks short because a filter is on must not read as lost tabs. Search text is not a
chip; it is already visible in the field.

**Interaction with search and paging.** Filters apply at the store, so they cover pages not yet loaded; "Load
More" keeps paging the filtered result set. Changing a filter or the query restarts at the first page. The window
remembers nothing between openings: every open starts unfiltered with an empty search.

## 5. Clear Archive (BH-087)

**Entry points.** Two, one flow:

1. Window > Clear Archive… (the unbound menu item, KB-043; rebindable as `clearArchive`). Enabled whenever the
   archive is not empty. If the Archive window is not open, it opens and comes forward first — one consistent
   place for the confirmation and the result (see open question 3 for the alternative).
2. The "Clear Archive…" button at the leading edge of the Archive window's footer, as far from Restore (trailing
   edge) as the window allows, in `destructiveText`. Disabled when the archive is empty.

**The confirmation.** The shared dialog sheet from `docs/design/alerts-sheets-toasts.md` (its content model
already names Clear Archive BH-087 as a consumer), hosted as a window sheet on the Archive window:

- Title: **Clear the Archive?**
- Body: **All 7 archived items are permanently deleted. This cannot be undone.**
- With a search or filter active, a second (secondary) paragraph: **This includes items hidden by the current
  filters.** — Clear Archive always empties the whole archive (`removeAll`), never just what is on screen.
- Buttons: Cancel — **Clear Archive** (destructive style: neutral fill, red title, never the Return key; Escape is
  Cancel).

**After.** The store is emptied, the list shows the empty state ("No Archived Tabs" — final copy for the empty
Archive belongs to the empty-states surface in #304; this is a placeholder), and a toast in the Archive window,
16 pt above the footer's top edge, confirms: **The Archive has been cleared.** (wording: open question 4). No undo:
the dialog said so, and Cmd-Z does not bring a cleared archive back.

## 6. Archived results in the command bar (BH-087, BH-104)

BH-104 already lists archived tabs among command bar results; this design adds them to today's provider chain.
Proposal (ranking and sectioning are open questions 1-2; the spec does not say):

- An archived match is a result row like any other: favicon tile, title, subtitle "host - Space, archived
  <relative date>", and the caption **Restore from Archive** in the accent text color where "Switch to Tab" would
  sit on an open tab.
- Ordering: after open-tab matches, before the search-what-you-typed row. Switching to a tab that is open beats
  restoring one that is closed beats searching the web. Cap: 3 archived matches, ranked by archived date, newest
  first.
- Enter restores the item per BH-086 (back to its original Space, obeying routes) and the restore toast
  ("Tab restored to Work") appears in the browser window. It does not open a duplicate tab.
- The same Unicode-insensitive matching as the Archive window, folder children included; a folder match restores
  the folder ("Folder restored to Work").

The command bar's own polish pass is a separate surface in #304; this is the archive slice only.

## 7. The education banner (BH-089)

**Timing.** The banner appears at the top of the Archive list the first time the Archive window is opened while at
least one auto-archived item exists — the "first auto-archive context". Before auto-archive has ever archived
anything there is nothing to explain; after the user has seen it once there is nothing to repeat. ([O] dismissal
counters back the once-only rule.)

**Content.** A rounded card (10 pt radius, `sidebarItemBackground` fill, hairline edge) between the header and the
list, 12 pt margins: an `archivebox` glyph on a 28 pt tile, then two lines, then the actions:

- Line 1: **Arkt archives Today tabs you haven't used in the past 12 hours.** (The [S] banner string, adapted:
  "Arc archives tabs that you haven't used in the past 12 hours"; the number follows the profile's "Archive tabs
  after" value when it differs from 12 hours.)
- Line 2 (secondary): **Restored tabs return to their Space. Change this in Settings > Spaces.**
- Actions: **Open Settings** (small neutral; opens Settings > Spaces, dismisses the banner) and **Got It** (small
  primary; dismisses). Mustard on Got It: it is the button that answers the banner, the same rule as Try Again in
  the dialogs.

**Dismissal.** Both actions dismiss and persist the dismissal; the banner is never shown again (BH-089). There is
no third state (no "remind me later"), and it does not time out on its own — it waits for a decision. It sits
above the list when the window opens; it does not animate in or push rows down mid-session.

Whether Arc also shows this banner in the sidebar (above Today) is unknown; the Archive-window placement is the
one this issue designs. See open question 5.

## 8. Layout spec (pt)

| Element | Value | Token / source |
|---|---|---|
| Window | 600 x 480, min 360 x 240 (unchanged) | `ArchiveWindowController.contentSize` |
| Title bar | system, title "Archive" (unchanged) | |
| Header row | 52 high, 1 pt `sidebarDivider` below, 12 side margins, 8 between field and filter button | new |
| Search field | 28 high, radius 7, `sidebarItemBackground` fill, 0.5 pt `sidebarDivider` edge; magnifier 13 pt at 9 leading; clear button 14 x 14 | Settings design's search field |
| Focus ring | 2 pt `focusRing`, outset 2 | BrandTokens.focusRing |
| Filter button | 28 x 28, radius 7, glyph 15 pt `secondaryText`; active: filled glyph `primaryText` + 7 pt ink dot, offset -2/-2, `surfaceBrand` halo | new |
| Filter menu | 224 wide, 24 pt items, section headers 11 semibold `secondaryText`, 10 pt theme dots, 13 pt checkmark column | NSMenu metrics |
| Chip strip | 8 above, 12 sides; chips 22 high, radius 11, `sidebarItemHovered` fill, 12 regular, 8 pt theme dot, 14 x 14 remove button; "Clear Filters" 12 `secondaryText` underlined | new |
| Banner | margins 12 top / 12 sides, radius 10, `sidebarItemBackground` fill, 0.5 pt `sidebarDivider` edge, padding 10/12; icon tile 28 x 28 radius 7 `sidebarItemHovered`, glyph 16 pt `secondaryText`; text 12 regular `primaryText`, sub-line `secondaryText`; buttons 24 high (small push) | new |
| Rows | 44 high, title 13 + detail 11 `secondaryText` (unchanged); folder glyph 14 pt `secondaryText` before folder titles | `ArchiveWindowController.rowHeight` |
| Match highlight | `accent` at 35 % fill, 2 pt radius, 1 pt padding | new ArchiveTokens.matchHighlight |
| Empty states | centered: 34 pt glyph `secondaryText` at 55 %, title 15 semibold, detail 12 `secondaryText`, max 320 wide | new |
| Footer bar | 44 high, 1 pt `sidebarDivider` above, 12 side margins (unchanged) | `ArchiveWindowController.barHeight` |
| Clear Archive button | 24 high small push button, `destructiveText` title, leading edge | AlertTokens.destructiveText |
| Footer message | 12 regular `secondaryText` (unchanged; gains "N results" / "N of M items") | `ArchiveWindowController.footerLabel` |
| Confirmation dialog | 420 wide sheet, 20 padding — the shared dialog values, unchanged | alerts-sheets-toasts 3.2 |
| Cleared toast | 36 high pill, 16 above the footer's top edge, centered | alerts-sheets-toasts 4.2, adapted host |

New tokens: `ArchiveTokens.matchHighlight` (accent 35 % / 35 %) only. Everything else reuses ShellTokens,
BrandTokens and AlertTokens. Contrast: the destructive footer button and dialog button use the measured
`AlertTokens.destructiveText` pairs (5.59:1 light, 6.44:1 dark on the neutral fill); chip and banner text on
`sidebarItemBackground`/`sidebarItemHovered` over porcelain/graphite stays above 4.5:1 (the Settings group's
measured pairing).

## 9. Motion spec

| Moment | Frequency | Purpose | Motion | Reduce Motion |
|---|---|---|---|---|
| Search/filter result swap | frequent (per keystroke) | none — the list is data | instant reload (keyboard-driven, like Settings' Cmd-1..7 pane switch) | same |
| Chip strip appears / a chip is removed | occasional | none | fades 0.15 s; no height animation (layout never animates) | instant |
| Filter menu | occasional | system | NSMenu's own | system's own |
| Banner present | once ever | none | rendered with the window; no entrance | none |
| Confirmation sheet | rare | system | AppKit's sheet animation | AppKit's own |
| Cleared toast in / out | rare | spatial continuity with other toasts | the shared toast motion: translateY 12 to 0, scale 0.96 to 1 on `springyFast`, opacity 0.16 s; out 0.15 s | opacity 0.15 s |
| Row removed on restore | occasional | none | none (today's `removeRows(withAnimation: [])`) | none |

Transform and opacity only; the one animated layer pair is the toast, shared with the alerts design. Reduce
Transparency: the toast fill goes to `toastSurface` at alpha 1; everything else is already opaque.

## 10. Keyboard and VoiceOver

- Keys in the Archive window: Cmd-F focuses the search field; Down from the field selects the first row; Return on
  a selected row restores it (same as double-click; today only double-click and the button work — proposal); Escape
  clears a non-empty query, then closes the window; Cmd-W closes the window (retitled "Close Window" while the
  Archive is key, the Settings Cmd-W pattern); Tab cycles search field, filter button, table, Clear Archive, Load
  More, Restore.
- In the confirmation sheet: focus starts on Cancel; the destructive button has no key; Escape cancels (the shared
  dialog rule).
- VoiceOver: the search field is "Search Archive, search text"; the filter button is "Filter, button", value "N
  filters active" when on; each chip is a group "Work, filter" with a "Remove filter" button; the banner is a
  group announced once when the window opens ("Arkt archives Today tabs…", with two buttons); the result count is
  the footer label's value and is announced on change (`.announcementRequested`); rows keep their current
  title/place/date/reason label, plus "contains <child title>" when present. Cleared toast: announced high
  priority, as every toast. Identifiers: `archive.search` (reserved), `archive.filter`, `archive.chip.<name>`,
  `archive.banner`, `archive.clear`, `archive.clearConfirm`, next to the existing `archive.*` set.
- The command bar's archive rows read like its other rows: title, subtitle, then the caption ("Restore from
  Archive") as the value.

## 11. Light and dark

Every color is a `TokenPair`; the window follows the system appearance (it belongs to no Space, like Little
Arkt's frame). Porcelain/graphite surface; the mustard accent appears only in the banner's Got It, the match
highlight at 35 %, and the command bar's caption (accent text). Increase Contrast: header/footer hairlines, the
search field edge and the banner edge use `SettingsTokens.separatorIncreasedContrast`; the filter-active dot keeps
its `surfaceBrand` halo.

## 12. Parity notes

- BH-087 names the "Library Archive": Arc's Archive lives in its Library (Cmd-Shift-L). Arkt has no Library; the
  Archive window is the surface. The search is designed for it.
- The cleared-confirmation string ([S] "Confirmation the Archive has been cleared.") backs the toast's existence,
  not its exact wording: PARITY(NEEDS-RUNTIME-CHECK) (open question 4).
- Whether Arc's Archive search has a keyboard shortcut, and whether Arc's command bar groups archived results
  under a header, is not in the catalogs: PARITY(NEEDS-RUNTIME-CHECK) (open questions 1 and 7).
- Filter strings exist in Arc's strings catalog (BH-088); the two-section menu and the chips are Arkt's layout.
- The banner's placement (Archive window vs sidebar) and its exact Arc wording beyond the [S] line:
  PARITY(NEEDS-RUNTIME-CHECK) (open question 5).
- "contains <child title>" on folder rows is an Arkt addition; the spec requires only that folder children match
  (open question 6).

## 13. Open questions for the maintainer

1. **Command bar grouping.** Does Arc show archived results under their own section header, or mixed into the
   flat list? The spec does not say, and Arkt's bar has no sections today. Proposal: flat, after open tabs, at
   most 3, newest first.
2. **Command bar caption and action.** Proposal: caption "Restore from Archive"; Enter restores per BH-086 (with
   the restore toast) instead of opening a duplicate. PARITY(NEEDS-RUNTIME-CHECK) for Arc's caption.
3. **Clear Archive from the menu with the window closed.** Proposal: the menu item opens/fronts the Archive
   window and runs the sheet there, so the confirmation and the empty result are seen in one place. Alternative:
   an app-modal alert without opening the window (the launch-failure host).
4. **Cleared-toast wording.** Proposal: "The Archive has been cleared." The [S] string is a description
   ("Confirmation the Archive has been cleared."), not proven display text.
5. **Banner surface.** Proposal: Archive window only. If Arc also shows the banner in the sidebar above Today,
   that instance would be a follow-up on the sidebar surface, sharing the dismissal flag.
6. **Folder child callout.** Proposal: when a folder matches only through a child tab, the detail line appends
   'contains "<child title>"'. Not required by the spec; drop if it reads noisy.
7. **Type-to-search.** Proposal: no — Cmd-F only, typing in the table does not start a search. Finder does the
   opposite; flag if parity or preference says otherwise.
8. **Return restores the selected row.** Proposal: yes (double-click's keyboard twin). Today there is no keyboard
   restore at all.

## 14. Screenshots

Rendered at 2x with headless Chromium (`--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`; window states
at `--window-size=672,580`, the command bar state at `1080,720`), into
`design/archive-search/screens/<state>-<light|dark>.png` (16 files):

| State | Shows |
|---|---|
| `search` | empty search field, full list, a selected row, Clear Archive in the footer |
| `filtered` | live query "report": title matches highlighted, a folder matched through a child with the "contains" callout, "3 results" |
| `no-results` | 'No Results' empty state for a query with no matches |
| `filters` | the filter menu open (Work + Closed chosen) over the chips strip, "3 of 7 items" |
| `clear` | the Clear Archive confirmation sheet |
| `cleared` | after clearing: the empty archive and the confirmation toast |
| `banner` | the one-time auto-archive education banner above the list |
| `command-bar` | an archived match in the command bar with the "Restore from Archive" caption |

Synthetic titles and example.com hosts only; no real browsing data.
