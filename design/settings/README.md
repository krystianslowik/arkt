# Settings window design

The Settings window (#305, built in #307), restyled to the brand direction set in #304. The spec is
[`docs/design/settings.md`](../../docs/design/settings.md); the prototype is [`prototype.html`](prototype.html)
(open it in a browser; states by hash, `#<state>[&dark][&today][&rm][&rt]`).

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network. Every state in the spec is a hash |
| `screens/<state>-<light\|dark>.png` | 26 screenshots at 2x: general, general-default, spaces, appearance, shortcuts, shortcuts-recording, shortcuts-conflict, extensions, extensions-empty, privacy, advanced, general-today, appearance-today |

## Before and after

The first pass (#309) drew Settings as a stock System Settings sheet. This pass applies the rules the Archive
window set (`design/archive-search/archive-search.md`, section 2): the system font at sidebar density, sidebar rows,
one mustard primary per surface, quiet secondaries, the system focus ring. The before screenshots are the ones in
`design/settings/screens/` at commit 41f59f6. Product decisions are unchanged: Cmd-1 to Cmd-7 switch panes, Escape
closes, no ad blocking row, unbuilt rows shown disabled, width 680.

| Element | Before | After | Why |
|---|---|---|---|
| Title bar and pane bar | separate toolbar strip, 86 pt, 1 pt hairline under it | unified 84 pt chrome on the window surface, no hairline | one bar on top, as the Archive |
| Selected pane | 28 pt tile filled with mustard, graphite glyph | the whole item lifts in `tabCurrent` with its shadow, like the current tab in the sidebar | mustard is for the one primary action, not for navigation |
| Idle panes | grey 28 pt tiles behind every glyph | bare glyph in `sidebarForeground`, hover `sidebarItemBackground` | seven grey tiles read as a stock toolbar |
| Groups | white cards with a 1 pt inner border | the Archive's recessed list field, no edge | a group is a field the rows sit in |
| Rows | 44 pt rows split by hairlines | sidebar rows: radius 9, 2 pt apart, hover fill, no separators | rows look like the sidebar's |
| Section titles | 13 semibold `primaryText` | 12 semibold `secondaryText`, the sidebar's section title | sidebar vocabulary |
| Add actions (New Profile, Add Route) | small grey buttons alone in an empty row | the sidebar's New Tab row: plus glyph and label | an add action is a row, not a button |
| Switches | mustard when on, 38 x 22 | graphite when on (porcelain in dark), 32 x 20 | twenty mustard switches drowned out the one primary |
| Buttons | 28 pt rounded rectangles with a 0.5 pt edge | pills: 28 pt radius 14 (24 / 12 small), 13 semibold, no edge | the brand's pill, as the Archive's Restore |
| Primary action | mustard button, one of several mustard things on the pane | the only mustard on the pane (Make Default, Open Chrome Web Store, Use Command-E) | one primary per surface |
| Destructive actions | grey bordered buttons with red text (Reset..., Reset All Shortcuts) | quiet red text links: Reset..., Clear..., Reset All Shortcuts... | destructive is red and quiet, never a grey bordered button |
| Default-browser state | mustard check seal | neutral "Default" capsule with a check | a status is not an action |
| Shortcut conflict | mustard warning triangle (mustard as a stroke), two buttons | neutral exclamation glyph in a row-shaped notice; Use Command-E primary pill, Keep Command-S text link | mustard is never a stroke; the second answer is quiet |
| Pop-ups, keycaps, search, segmented control | 0.5 pt edges, radius 6 or 7 | edgeless fills; the search field and pop-ups take the sidebar URL pill's shape; the segmented plate lifts in `tabCurrent` | no stock bezels |
| Focus ring | 2 pt graphite (mustard in dark) | the system focus ring | system focus everywhere; mustard is never a stroke |
| Space rows | 28 pt swatches | 20 pt swatches in the Space's theme gradient; the Appearance preview drawn in the Work theme | Space color carries meaning, at sidebar size |
| Import row | "Import from Arc" | "Import browser data" (the button runs File > Import Browser Data...) | no user-facing "Arc" |
| Empty extensions | bare glyph | 44 pt tile, 15 semibold title, primary pill, as the Archive's empty states | one empty-state pattern |

New and dropped tokens are listed in the spec, section 4.
