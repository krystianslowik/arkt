# Archive search, filters, Clear Archive and the education banner design

Design issue: #111 (part of the design-first rule in #304). Implementation issue: to be filed after this design merges.
Prototype: [`design/archive-search/prototype.html`](prototype.html). Screenshots:
[`design/archive-search/screens/`](screens/).

## 1. The window in one paragraph

The Archive window keeps its quiet job — list what was closed, restore it — and gains the three things a growing
archive needs to stay useful: a search field and a filter button in a unified title bar, and Clear Archive as a
quiet link in the footer, far from Restore. Searching filters the list live, matches without case or diacritics, and
finds tabs inside archived folders; the filters narrow by Space or Little Arkt and by close type, and show
themselves as removable chips so an invisible filter never hides an item. Clear Archive asks once, with the count in
the question and no Return key on the destructive button, then confirms with a toast. The first time auto-archive
has something to explain, a one-time banner at the top of the list says what happened and where to turn it off. The
command bar gains archived matches with a "Restore from Archive" caption, so a closed tab is one Cmd-T away.

## 2. The look

The Archive is a utility window, so it keeps the everyday chrome rules: the system font, Arc's sidebar density, no
Avenir and no hero treatment. What lifts it above a stock sheet is that it borrows the sidebar instead of the table
view:

- **One bar on top.** The title bar is unified (`titlebarAppearsTransparent`, `.fullSizeContentView`, 52 pt): traffic
  lights, the title "Archive", then the search field and the filter button on the same line. There is no separate
  header strip and no hairline under it.
- **Rows are sidebar rows.** Favicon, title, and trailing metadata (the Space's color dot and a relative time) on a
  single 34 pt line with the sidebar's radius, fills and selection. No dot-joined meta string. A folder is a folder
  row with its tab count; when a search matches inside it, it opens and shows the matching child, indented as in the
  sidebar.
- **The list sits in a recessed field** (`ArchiveTokens.listField`), so the selected row lifts off it in
  `tabCurrent` exactly as the current tab does in the sidebar.
- **One primary.** Restore is the only filled button on the window: a mustard pill with graphite text. Everything
  else is quiet: Clear Archive is a destructive text link, Clear Filters and Open Settings are text links, Got It is
  a neutral pill, and further pages load on their own as the list scrolls (no Load More button).
- **Space color carries meaning.** Filter chips tint with the Space's own theme color and carry its dot; the filter
  menu shows the same dots. Close-type chips stay neutral.
- **Focus is the system's.** Every focus ring on this surface is the system focus ring
  (`NSColor.keyboardFocusIndicatorColor`, following the user's accent color). Mustard is a fill only: never text,
  never a stroke.

## 3. What changes, mapped to the spec

| Element | Behavior | Spec |
|---|---|---|
| Search field in the Archive window header | Live store-side filtering of the list | BH-087 (Archive search half) |
| Unicode case- and diacritic-insensitive matching, incl. folder children | "ü" matches "u", a folder matches when any child's title or URL matches | BH-087; week-1 Track D follow-up |
| Archived results in the command bar | Archived items match queries; Enter restores | BH-087 (command bar half), BH-104 |
| Clear Archive | Menu item (unbound, KB-043) and a quiet footer link; confirmation, then a confirmation toast | BH-087, KB-043 |
| Filters by Space, by Little Arkt, by close type | One source filter + one close-type filter, combinable with search | BH-088 |
| Auto-archive education banner | Shown once after the first auto-archived item exists; never again after dismissal | BH-089 |

The store already models all of it: `ArchiveFilter(source:reason:text:)` in `ArchiveQuery.swift`, `ArchiveReason`
(manual/auto) and `ArchiveSource` (space/littleArc/unknown) in `ArchivedItem.swift`, and `ArchiveStore.removeAll`
("Clear Archive (BH-087). The confirmation dialog is the caller's."). What is missing store-side is exactly the
Track D follow-up: the text match is an ASCII-only LIKE; it must become Unicode case/diacritic-insensitive
(`search_text` column or FTS5) and cover folder children.

## 4. The search field

**Placement.** In the unified 52 pt title bar, after the traffic lights and the title: the search field fills the
bar, the filter button sits at its trailing edge (10 pt from the window edge, 8 pt from the field). The field is
drawn like the sidebar's URL pill, not like a stock `NSSearchField` bezel: 32 high, radius 9, `sidebarItemBackground`
fill with no edge, a 14 pt magnifier in `sidebarForeground`, 13 pt text. Identifier `archive.search` (already
reserved in `AXID.Archive`).

**Focus behavior.** When the window opens, focus is on the table, not the field: the Archive is a restore surface
first, and arrow keys must work at once. Cmd-F focuses the field (standard Find key; Find has no other meaning in
this window). Typing does not jump from the table to the field (no type-to-search; see open question 7). Down
arrow from the field selects the first row and moves focus to the table.

**Escape.** With a non-empty query, Escape clears the query (standard `NSSearchField`) and the list reloads
unfiltered. With an empty query, Escape closes the window — today's behavior, and the same rule Settings uses
(decision 2 there).

**Matching.** Every keystroke (debounced 150 ms) queries the store, not the loaded pages: search covers the whole
archive, not just the pages loaded so far. The match is Unicode case- and diacritic-insensitive
(`localizedStandardContains` semantics) over the item's title and URL. A folder or Split View matches when its own
title matches or when any tab inside it matches; restoring a folder matched through a child restores the whole
folder (there is no partial restore). When a folder matched only through a child, the folder row shows open (the
sidebar's disclosure chevron) with the matching child rows indented under it, their match highlighted; the child
rows are not selectable on their own (proposal, open question 6).

**Result presentation.** Rows stay in newest-first order; the matched substring is highlighted in the title at 35 %
accent fill (a fill, never colored text). While a query or filter is active, the footer count reads "3 results", or
"3 of 42 items" when only filters narrow the list. No matches: a centered "No Results" with 'Nothing in the Archive
matches "zebra".' under it, and Restore is disabled.

## 5. The filters (BH-088)

**The button.** A 32 x 32 borderless icon button (`line.3.horizontal.decrease`, 16 pt, `sidebarForeground`) at the
trailing edge of the title bar, hover fill `sidebarItemBackground`. With any filter active it keeps the
`sidebarItemHovered` fill and the glyph turns `primaryText`; the chips below say which filters are on, so the button
needs no badge.

**The menu.** The button opens a native `NSMenu` with two sections, built from `NSMenuItem.sectionHeader(title:)`
and plain items. Nothing in it is custom-drawn: the Space dots are 10 pt circle `NSMenuItem.image`s in the Space's
color, Little Arkt gets its small window glyph as a template image, the checkmarks and the highlight are the system's.

- **Space**: Everywhere (default) — then one item per Space with its theme dot — then Little Arkt. These are the
  `ArchiveSource` cases; "unknown" sources (old Arc imports) match Everywhere and are not listed as a filter.
- **Close Type**: Closed and Auto Archived (default) — Closed — Auto Archived. These are the `ArchiveReason` cases.

One selection per section, checkmarked; the two sections and the search text combine (AND), which is exactly what
`ArchiveFilter` expresses. Choosing the default in a section clears that section.

**The chips.** While any filter is active, a chip strip appears between the title bar and the list: one capsule per
active filter, each with an xmark that removes it, plus a trailing "Clear Filters" text link. A Space chip ("Work")
is tinted with that Space's color at 16 % over the window surface and leads with its 7 pt dot, so the filter reads
as the Space at a glance; "Little Arkt" leads with its window glyph; a close-type chip ("Closed", "Auto Archived")
stays neutral on `sidebarItemHovered` with a small glyph. The strip exists so state that hides rows is always
visible and one click from being undone — an archive that looks short because a filter is on must not read as lost
tabs. Search text is not a chip; it is already visible in the field.

**Interaction with search and paging.** Filters apply at the store, so they cover pages not yet loaded. Auto-loading
keeps paging the filtered result set. Changing a filter or the query restarts at the first page. The window
remembers nothing between openings: every open starts unfiltered with an empty search.

## 6. Clear Archive (BH-087)

**Entry points.** Two, one flow:

1. Window > Clear Archive… (the unbound menu item, KB-043; rebindable as `clearArchive`). Enabled whenever the
   archive is not empty. If the Archive window is not open, it opens and comes forward first — one consistent
   place for the confirmation and the result (see open question 3 for the alternative).
2. A quiet "Clear Archive…" text link at the leading edge of the Archive window's footer, as far from Restore
   (trailing edge) as the window allows: 12 pt `destructiveText`, no fill and no bezel, underlined on hover.
   Disabled (40 %) when the archive is empty. It is deliberately not a button: a destructive action that empties
   the whole archive should never look like a peer of Restore.

**The confirmation.** The shared dialog sheet from `docs/design/alerts-sheets-toasts.md` (its content model
already names Clear Archive BH-087 as a consumer), hosted as a window sheet on the Archive window:

- Title: **Clear the Archive?**
- Body: **All 42 archived items are permanently deleted. This cannot be undone.**
- With a search or filter active, a second (secondary) paragraph: **This includes items hidden by the current
  filters.** — Clear Archive always empties the whole archive (`removeAll`), never just what is on screen.
- Buttons: Cancel and **Clear Archive**, both neutral pills (28 high, fully round, `sidebarItemHovered`), Clear
  Archive with a `destructiveText` title. Neither is mustard and neither has the Return key; Escape is Cancel.

**After.** The store is emptied, the list shows the empty state ("No Archived Tabs" — final copy for the empty
Archive belongs to the empty-states surface in #304; this is a placeholder), and a toast in the Archive window,
16 pt above the footer's top edge, confirms: **The Archive has been cleared.** (wording: open question 4). No undo:
the dialog said so, and Cmd-Z does not bring a cleared archive back.

## 7. Archived results in the command bar (BH-087, BH-104)

BH-104 already lists archived tabs among command bar results; this design adds them to today's provider chain.
Proposal (ranking and sectioning are open questions 1-2; the spec does not say):

- An archived match is a result row like any other: favicon tile, title, subtitle "host", the Space's dot, "Space,
  archived <relative date>", and the caption **Restore from Archive** with a small archive-box glyph in
  `commandBarText` where "Switch to Tab" would sit on an open tab. Mustard is not used for the caption: it is
  never text.
- Ordering: after open-tab matches, before the search-what-you-typed row. Switching to a tab that is open beats
  restoring one that is closed beats searching the web. Cap: 3 archived matches, ranked by archived date, newest
  first.
- Enter restores the item per BH-086 (back to its original Space, obeying routes) and the restore toast
  ("Tab restored to Work") appears in the browser window. It does not open a duplicate tab.
- The same Unicode-insensitive matching as the Archive window, folder children included; a folder match restores
  the folder ("Folder restored to Work").

The command bar's own polish pass is a separate surface in #304; this is the archive slice only.

## 8. The education banner (BH-089)

**Timing.** The banner appears at the top of the Archive list the first time the Archive window is opened while at
least one auto-archived item exists — the "first auto-archive context". Before auto-archive has ever archived
anything there is nothing to explain; after the user has seen it once there is nothing to repeat. ([O] dismissal
counters back the once-only rule.)

**Content.** A rounded card (12 pt radius, `sidebarItemBackground` fill, no edge) between the title bar and the
list, 12 pt margins: an `archivebox` glyph on a 32 pt `sidebarItemHovered` tile, then two lines, then the actions:

- Line 1: **Arkt archives Today tabs you haven't used in the past 12 hours.** (The [S] banner string, adapted:
  "Arc archives tabs that you haven't used in the past 12 hours"; the number follows the profile's "Archive tabs
  after" value when it differs from 12 hours.)
- Line 2 (secondary): **Restored tabs return to their Space. Change this in Settings > Spaces.**
- Actions: **Open Settings** (quiet text link; opens Settings > Spaces, dismisses the banner) and **Got It** (small
  neutral pill; dismisses). Got It is not mustard: Restore is the window's one primary, and the banner must not
  compete with it.

**Dismissal.** Both actions dismiss and persist the dismissal; the banner is never shown again (BH-089). There is
no third state (no "remind me later"), and it does not time out on its own — it waits for a decision. It sits
above the list when the window opens; it does not animate in or push rows down mid-session.

Whether Arc also shows this banner in the sidebar (above Today) is unknown; the Archive-window placement is the
one this issue designs. See open question 5.

## 9. Layout spec (pt)

| Element | Value | Token / source |
|---|---|---|
| Window | 600 x 480 content, min 360 x 240 (unchanged); `surfaceBrand` background | `ArchiveWindowController.contentSize`, BrandTokens |
| Title bar | unified, 52 high, transparent, full-size content view; traffic lights at their standard inset; title "Archive" 13 semibold `primaryText`, 12 after the lights, 8 before the field; no hairline below | new |
| Search field | 32 high, radius 9, `sidebarItemBackground` fill, no edge; magnifier 14 pt `sidebarForeground` at 10 leading; text and placeholder 13 (`primaryText` / `secondaryText`); clear button 14 x 14 `sidebarForeground` | the sidebar URL pill's shape |
| Filter button | 32 x 32, radius 9, glyph 16 pt `sidebarForeground`, hover `sidebarItemBackground`; active: `sidebarItemHovered` fill, glyph `primaryText`; 10 from the window's trailing edge | new |
| Focus ring | the system focus ring (`focusRingType = .default`), `NSColor.keyboardFocusIndicatorColor`; never mustard | AppKit |
| Filter menu | native `NSMenu`: section headers via `NSMenuItem.sectionHeader`, 10 pt circle images in the Space color, system checkmarks and highlight | AppKit |
| Chip strip | 0 above (it follows the title bar), 10 below, 12 sides, 6 between chips | new |
| Chip | 24 high capsule (radius 12), padding 10 leading / 5 trailing, 12 medium `primaryText`, 6 between parts; Space chip fill = Space color at 16 % over the surface with a 7 pt dot in the Space color; close-type chip `sidebarItemHovered` with a 12 pt glyph in `sidebarForeground`; remove button 16 x 16 round, xmark 8 pt `sidebarForeground`, hover `sidebarItemHovered` | new `ArchiveTokens.chipTintAlpha` (0.16) |
| Clear Filters | text link, 12 regular `secondaryText`, hover `primaryText`, 12 after the last chip | new |
| Banner | margins 0 top (after the title bar or chips) / 12 sides / 10 below, radius 12, `sidebarItemBackground`, no edge, padding 12; icon tile 32 x 32 radius 9 `sidebarItemHovered`, glyph 16 pt `primaryText`; line 1 12 semibold `primaryText`, line 2 12 regular `secondaryText`; actions on their own row 10 below the text, aligned with it: Got It (24 high neutral pill), then the Open Settings text link 14 after it | new |
| List field | inset 8 from the window sides, radius 10, `ArchiveTokens.listField` (light graphite 3.5 %, dark black 14 %), 4 pt vertical padding | new |
| Rows | `SidebarMetrics`: 34 high fill in a 37 pt pitch (3 between rows), radius 9 (`rowCornerRadius`), 4 inset from the field's sides; favicon 16 at 10 leading, title 8 after the favicon, 13 medium `primaryText`, tail truncation | SidebarMetrics |
| Row states | selected `tabCurrent` + `tabCurrentShadow`; hover `sidebarItemBackground`; no hairlines between rows | ShellTokens |
| Folder row | `folder` glyph 16 pt `sidebarForeground` in the favicon slot, then the title and its tab count (13 regular `secondaryText`, 6 after the title); when opened by a search match, the sidebar's 10 pt disclosure chevron leads and matching children follow indented 22 (`indentationPerLevel` plus the chevron) without trailing metadata | SidebarMetrics |
| Trailing metadata | 16 after the title: the Space's 7 pt color dot (Little Arkt: its 10 pt window glyph in `sidebarForeground`), 8 gap, then the relative time in a 58 pt left-aligned column, 12 regular `secondaryText`, tabular figures; 9 from the fill's trailing edge (`titleTrailing`) | new |
| Relative time | under an hour "12m"; under a day "3h"; the day before "Yesterday"; within a week the weekday ("Mon"); otherwise day and month ("22 Sep"), plus the year when not the current one | new; `Date.FormatStyle` per locale |
| Match highlight | `accent` at 35 % fill, 3 pt radius, 1 pt padding, title only | new `ArchiveTokens.matchHighlight` |
| Auto-load row | 30 high, centered 12 pt spinner (`NSProgressIndicator`, small) and "Loading more" 12 `secondaryText`; shown while the next page loads | new |
| Empty states | centered in the list field: 44 pt tile radius 12 `sidebarItemBackground` with a 22 pt glyph `sidebarForeground`, 8 below it the title 15 semibold, detail 12 `secondaryText`, max 300 wide | new |
| Footer | 52 high, no hairline above, 16 leading / 12 trailing | `ArchiveWindowController.barHeight` (44 to 52) |
| Clear Archive | text link at the leading edge, 12 regular `destructiveText`, underline on hover, 40 % when disabled | AlertTokens.destructiveText |
| Footer count | 12 regular `secondaryText`, tabular figures, 14 before Restore: "42 items", "3 results", "3 of 42 items"; empty when there are no results | `ArchiveWindowController.footerLabel` |
| Restore | the window's one primary: 28 high pill (radius 14), padding 16, 13 semibold; fill `accent`, hover `accentHighlight`, pressed `accentPressed`, title `onAccent`; disabled: `sidebarItemBackground` fill, title and fill at 40 % (a disabled primary is not mustard) | BrandTokens |
| Confirmation dialog | 400 wide window sheet, 20 padding, radius 14 at the bottom corners; title 15 semibold, body 13 `secondaryText`; Cancel and Clear Archive as 28 high neutral pills, trailing | alerts-sheets-toasts 3.2, pill buttons |
| Cleared toast | 36 high pill, 16 above the footer's top edge, centered | alerts-sheets-toasts 4.2, adapted host |

New tokens: `ArchiveTokens.matchHighlight` (accent 35 %), `ArchiveTokens.listField` (light `#0E0F10` at 3.5 %,
dark black at 14 %) and `ArchiveTokens.chipTintAlpha` (0.16). Everything else reuses ShellTokens, SidebarMetrics,
BrandTokens and AlertTokens. Contrast: `destructiveText` reaches 5.59:1 (light) and 6.44:1 (dark) on the neutral
fill, and stays above 4.5:1 on the bare surface; `primaryText` on a Space-tinted chip stays above 4.5:1 for every
shipped Space color at 16 %; `onAccent` on `accent` is 8.4:1. `ShellTokensContrastTests` gains the chip and
list-field pairs.

## 10. Motion spec

| Moment | Frequency | Purpose | Motion | Reduce Motion |
|---|---|---|---|---|
| Search/filter result swap | frequent (per keystroke) | none, the list is data | instant reload (keyboard-driven, like Settings' Cmd-1..7 pane switch) | same |
| Chip strip appears / a chip is removed | occasional | none | fades 0.15 s; no height animation (layout never animates) | instant |
| Restore press | occasional | feedback | scale 0.97 with `accentPressed`, 160 ms ease-out | fill change only |
| Next page auto-loads | occasional | none | rows append below; the spinner row is replaced, nothing slides | same |
| Folder opens for a child match | per query | none | instant, as part of the result swap | same |
| Filter menu | occasional | system | NSMenu's own | system's own |
| Banner present | once ever | none | rendered with the window; no entrance | none |
| Confirmation sheet | rare | system | AppKit's sheet animation | AppKit's own |
| Cleared toast in / out | rare | spatial continuity with other toasts | the shared toast motion: translateY 12 to 0, scale 0.96 to 1 on `springyFast`, opacity 0.16 s; out 0.15 s | opacity 0.15 s |
| Row removed on restore | occasional | none | none (today's `removeRows(withAnimation: [])`) | none |

Transform and opacity only; the one animated layer pair is the toast, shared with the alerts design. Reduce
Transparency: the toast fill goes to `toastSurface` at alpha 1; everything else is already opaque.

## 11. Keyboard and VoiceOver

- Keys in the Archive window: Cmd-F focuses the search field; Down from the field selects the first row; Return on
  a selected row restores it (same as double-click; today only double-click and the button work, proposal);
  Escape clears a non-empty query, then closes the window; Cmd-W closes the window (retitled "Close Window" while
  the Archive is key, the Settings Cmd-W pattern); Tab cycles search field, filter button, chips (when shown),
  table, Clear Archive, Restore. Restore is the default button only while the table has focus.
- Auto-load: arrowing or scrolling to within 10 rows of the end loads the next page; keyboard selection never
  stalls on an unloaded row.
- In the confirmation sheet: focus starts on Cancel; the destructive button has no key; Escape cancels (the shared
  dialog rule).
- VoiceOver: the search field is "Search Archive, search text"; the filter button is "Filter, button", value "N
  filters active" when on; each chip is a group "Work, filter" with a "Remove filter" button; Clear Archive is a
  button ("Clear Archive", not a link, for the rotor); the banner is a group announced once when the window opens
  ("Arkt archives Today tabs...", with two buttons); the result count is the footer label's value and is announced
  on change (`.announcementRequested`). A row reads its title, then the details the row no longer prints: "Work,
  closed today at 09:41" or "Little Arkt, auto archived yesterday", plus "4 tabs" for a folder; a child shown
  under an opened folder reads "in Research". The time column's compact text is never what VoiceOver says. The
  spinner row is announced once as "Loading more". Cleared toast: announced high priority, as every toast.
  Identifiers: `archive.search` (reserved), `archive.filter`, `archive.chip.<name>`, `archive.banner`,
  `archive.clear`, `archive.clearConfirm`, `archive.restore`, next to the existing `archive.*` set.
- Hover on a row shows a tooltip with the same details (host, Space, close type and the exact date), since the
  row itself no longer prints the host or the close type.
- The command bar's archive rows read like its other rows: title, subtitle, then the caption ("Restore from
  Archive") as the value.

## 12. Light and dark

Every color is a `TokenPair`; the window follows the system appearance (it belongs to no Space, like Little
Arkt's frame). Porcelain/graphite surface with the recessed list field. Mustard appears in exactly two places,
both fills: the Restore pill and the 35 % match highlight. It is never text and never a stroke; the focus rings are
the system's, and the command bar's caption uses `commandBarText`. Increase Contrast: the search field, the
chips and the list field gain a 1 pt `SettingsTokens.separatorIncreasedContrast` edge, and the selected row's
`tabCurrentShadow` becomes that edge in dark.

## 13. Parity notes

- BH-087 names the "Library Archive": Arc's Archive lives in its Library (Cmd-Shift-L). Arkt has no Library; the
  Archive window is the surface. The search is designed for it.
- The cleared-confirmation string ([S] "Confirmation the Archive has been cleared.") backs the toast's existence,
  not its exact wording: PARITY(NEEDS-RUNTIME-CHECK) (open question 4).
- Whether Arc's Archive search has a keyboard shortcut, and whether Arc's command bar groups archived results
  under a header, is not in the catalogs: PARITY(NEEDS-RUNTIME-CHECK) (open questions 1 and 7).
- Filter strings exist in Arc's strings catalog (BH-088); the two-section menu and the chips are Arkt's layout.
- The banner's placement (Archive window vs sidebar) and its exact Arc wording beyond the [S] line:
  PARITY(NEEDS-RUNTIME-CHECK) (open question 5).
- Showing a folder opened to its matching child is an Arkt addition; the spec requires only that folder children
  match (open question 6).
- Auto-loading pages replaces today's Load More button; the store's paging is unchanged (open question 9).

## 14. Open questions for the maintainer

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
6. **Folder child match.** Proposal: a folder that matches only through a child shows open, with the matching
   children indented under it, as the sidebar would show them. Not required by the spec; the alternative is a
   closed folder row with no hint of why it matched.
7. **Type-to-search.** Proposal: no, Cmd-F only; typing in the table does not start a search. Finder does the
   opposite; flag if parity or preference says otherwise.
8. **Return restores the selected row.** Proposal: yes (double-click's keyboard twin). Today there is no keyboard
   restore at all.
9. **Auto-load instead of Load More.** Proposal: auto-load the next page near the end of the list. If explicit
   paging is preferred, the fallback is a quiet "Show More" text link as the list's last row, never a footer
   button.

## 15. Screenshots

Rendered at 2x with the project's headless Chromium (device scale factor 2, hash `#<state>[&dark]&shot`; window
states at 672 x 580, the command bar state at 1080 x 720), into
`design/archive-search/screens/<state>-<light|dark>.png` (16 files):

| State | Shows |
|---|---|
| `search` | empty search field, the full list in sidebar rows, a selected row, the auto-load row, Restore as the one primary |
| `filtered` | live query "report" with the system focus ring: title matches highlighted, a folder opened to its matching child, "3 results" |
| `no-results` | 'No Results' empty state for a query with no matches; Restore disabled |
| `filters` | the native filter menu open (Work and Closed chosen) over the Space-tinted chips, "3 of 42 items" |
| `clear` | the Clear Archive confirmation sheet with pill buttons |
| `cleared` | after clearing: the empty archive and the confirmation toast |
| `banner` | the one-time auto-archive education banner above the list, Got It as a neutral pill |
| `command-bar` | an archived match in the command bar with the "Restore from Archive" caption |

Synthetic titles and example.com hosts only; no real browsing data.
