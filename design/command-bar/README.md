# Command bar

Design for the command bar (#112): the Cmd-T / Cmd-L overlay that opens URLs, searches, switches tabs and runs
actions. This is the approved direction, the "hybrid": the compact glass bar of the first mock with the filter pills
and preview column of the fourth. The build is tracked in the issues that reference this design.

- Prototype: [`design/command-bar/prototype/`](prototype/). Open any `hybrid-*.html` in a browser. Each file is one
  state at 1280 x 800 pt; `base.css` draws the window behind the bar, `hybrid.css` is the bar itself.
- Screenshots: [`design/command-bar/screens/`](screens/). Index at the end of this document.
- Rejected directions, kept for history: [`design/command-bar/directions/`](directions/).
- Scope: the look, layout and behavior of the bar. Search and ranking logic, site search, Paste and Go and the
  archived results already exist (#322, #365) and keep their behavior; this design only restyles and extends them.

## Look

One compact, centred glass bar over a lightly dimmed window. The window behind it keeps its colors; the dim is a
black 28 % scrim, enough to separate the bar without hiding the page. The bar is a blurred, saturated surface with a
1 pt inner edge, a 0.5 pt outer edge and a soft drop shadow, 16 pt continuous corners. It works in light and dark.

Typeface: the system font, as in every AppKit view in the shell. The prototype uses `-apple-system`, which is the
same face.

Brand rules:

- Mustard is a fill only: the selected-row tick, the caret, the Switch to Tab button and chips. Never a text color
  and never a stroke. Text on a mustard fill is graphite.
- No user-facing "Arc" anywhere: row captions, empty states, accessibility labels. Say "browser data" where the data
  source would be named.
- Light and dark are both required; the light screenshot is the pill, button and scrim reference for light mode.

## Layout

All values in points.

| Element | Value |
|---|---|
| Bar width | 680 by default; 968 when the preview column is shown |
| Bar position | horizontally centred in the window; top edge fixed so results grow downward (the prototype uses 176 from the top of an 800 high window) |
| Bar corners | 16, continuous |
| Query field | 58 high, 22 regular, 18 leading inset, magnifier 18 |
| Filter pills | right of the query field, in one 26 high capsule; 22 high pills, 12 medium, count in 10.5 tabular figures |
| Esc key cap | at the right end of the field row |
| List padding | 6 on every side |
| Row | 40 high, 9 corner radius, 12 horizontal padding, 12 gap between slot and title |
| Group header | 11 semibold, secondary text, 8 above and 4 below |
| Hint strip | 34 high, 11.5, hairline above, key caps 18 high |
| Preview column | 300 wide, 12 padding, hairline on its leading edge |
| Preview height | no taller than the five rows it sits beside (5 x 40 plus the list padding); the bar does not grow for it |
| Preview thumbnail | 116 high, 10 corner radius |
| Preview buttons | 30 high, 8 corner radius, 12.5 semibold |

Rows shown: at most five without scrolling in the search states. The empty state shows more (see
[Empty state](#empty-state)).

## Row anatomy

Left to right: a 20 wide slot with the favicon (16) or a symbol, the title in 14, an optional secondary URL in 13
that truncates first, then a trailing group that is right-aligned.

| Row kind | Slot | Title | Secondary | Trailing |
|---|---|---|---|---|
| Open tab | favicon | page title, query match in semibold | host and path | Return key cap on the selected row, otherwise "Switch to Tab" for the selected row when no preview |
| Search suggestion | magnifier | suggestion, query match in semibold | none | "Search" |
| History | clock | page title | host and path | relative time ("Yesterday") |
| Site search | the site's favicon | "Search <site> for <query>" | none | Tab key cap, then Return on the selected row |
| Action | symbol | verb ("Copy URL", "New Space") | detail where useful | shortcut key caps |
| Paste and Go | clipboard glyph | "Paste and Go" | the clipboard URL | Return key cap on the selected row |
| Archived result | favicon | page title | host, Space, when archived | "Restore from Archive" |

Selected row: a `commandBarSelectedRow`-style fill with a 0.5 pt inner edge, and a thin mustard tick on the leading
edge, 3 wide, inset 10 from the top and bottom of the row, with a rounded trailing edge. The tick is a fill; there is
no mustard stroke around the row. Hover uses the same fill without the tick.

## Filters

Pills: **All**, **Tabs**, **History**, **Actions**. They sit to the right of the query field and filter the result
list without changing the query.

- Each pill shows the match count for the current query in a smaller tabular figure. With an empty query the counts
  are hidden.
- The selected pill is a filled capsule (light fill with dark text in dark mode, dark fill with light text in light
  mode). Only one pill is selected at a time; All is the default on every open.
- Archived results belong to All and Tabs. Suggestions and site-search rows belong to All only.
- Cmd-1 to Cmd-4 select the pills in order. The hint strip shows "Cmd 1-4 Filter".
- A filter that matches nothing shows one empty row: "No <filter> match <query>".

## Preview column

The bar widens from 680 to 968 and adds a 300 wide column on the right when the selected row is a **tab** or a
**history** row. For every other selected row (search suggestion, site search, action, Paste and Go, archived
result) the bar stays at 680 with no preview.

The column holds, top to bottom:

1. The thumbnail: a snapshot of the live tab; for a history row, a cached snapshot if one exists, otherwise the
   favicon on a neutral well. The thumbnail never blocks the bar: until it loads, the well shows.
2. The title, 14 semibold, one line, tail truncation.
3. A meta line, "<host> · open in <Space>, <time>", for example "github.com · open in Work, 12 min ago", led by the
   open-dot. The dot is the open-dot, 6 pt green, shown only when the page is open in a tab. A history row shows "<host>, visited
   <time>" with no dot.
4. Two buttons, side by side:
   - **Split View** (Cmd-Return), the secondary button.
   - **Switch to Tab** (Return), the primary button and the only mustard one. For a history row that is not open, the
     primary reads "Open" and Split View opens the page in a new split pane.

Moving the selection between two rows that both show a preview keeps the column in place and swaps its content.

## Empty state

With an empty query the bar is 680 wide, the placeholder reads "Search or enter address", and the list is grouped
with small headers, in this order:

1. **Clipboard**: "Paste and Go" with the URL, only when the clipboard holds a URL. Selected first when present.
2. **Recent tabs**: up to four recently viewed tabs with host and relative time ("12 min", "1 h", "Yesterday").
3. **Actions**: a short list of common verbs ("New Space" with its shortcut).

With nothing on the clipboard the Clipboard group is absent and the first Recent tab is selected. The hint strip
shows "Open", "Cmd 1-4 Filter" and the right-aligned line "Type a URL, a search, or a command".

## Archived results

Already built (#365) and kept as is: matching archived items show as rows captioned "Restore from Archive", at most
3, listed after the open tabs; Return restores the item instead of opening a duplicate. The restyle gives them the
standard row anatomy above and no preview column.

## Keyboard

| Key | Action |
|---|---|
| Up / Down | Move the selection; wraps from the last row to the first. |
| Tab | Cycle the filter pills forward (All, Tabs, History, Actions, All). Shift-Tab cycles backward. On a site-search row that shows a Tab key cap, and on an empty field, Tab keeps its existing meaning from #322 (scope to that site, or enter action search). See open question 1. |
| Cmd-1 to Cmd-4 | Select a filter pill directly. |
| Return | Run the selected row: Switch to Tab, open, search, run the action, Paste and Go or Restore from Archive. |
| Cmd-Return | Split View with the selected tab or history page. Only on rows that show the preview. |
| Esc | Clear the query if there is one; close the bar if the query is already empty. The Esc key cap in the field row closes the bar. |
| Cmd-Shift-V | Paste and Go, from any state. |
| Cmd-Opt-Delete | Remove the selected suggestion (from #322). |

Keyboard focus never leaves the query field: the list and the pills are driven by key events, so typing always edits
the query.

## Motion

| Transition | Motion |
|---|---|
| Bar appears | Fully laid out on the first frame, fade in only; no scale. |
| Selection moves | The selected-row fill and tick slide to the new row; retargeted if the key repeats mid-flight. |
| Widening to 968 | An interruptible spring on the bar's width. The leading edge of the list does not move. Pressing Up or Down in the middle retargets the spring; it never restarts from zero. |
| Narrowing to 680 | The same spring in reverse. |
| Preview content | Cross-fades when the selection changes between two rows that both show it. |
| Dismiss | Fade out, 0.1 s. |

Springs come from `Motion/SpringPreset`; animate transform, opacity and mask bounds, not layout, and resize the live
view once at rest.

**Reduce Motion** (`NSWorkspace.accessibilityDisplayShouldReduceMotion`): the width changes instantly, with no
spring. The preview content still fades in. The selection fill moves instantly. Dismiss keeps its fade.

**Reduce Transparency**: the bar takes an opaque surface fill; the blur is dropped and the shadow stays.

## Accessibility

- The bar is a dialog group labelled "Command bar". The query field is the first element and keeps focus.
- The list is an `AXList`; each row reads "<title>, <host>, <kind>, <k> of <n>", where kind is "open tab",
  "history", "action", "search suggestion", "clipboard" or "archived". The selected row is announced on every
  move.
- The filter pills are a tab group with one selected item each: "<name>, <count> results, selected". Changing the
  filter announces "<name>, <count> results".
- The preview column is a group labelled "Preview" with its title, the open-in line and two labelled buttons. It
  is announced when it appears ("Preview, <title>"); the buttons are reachable with VoiceOver navigation but are not
  in the Tab order of the query field.
- Contrast: text on the mustard fill is graphite (the brand pair, above 7:1). Secondary text on the glass surface
  must meet 4.5:1 in both appearances; check it against the lightest and darkest wallpaper-independent surface
  fills, not the blurred backdrop.
- The mustard tick and open-dot are never the only carrier of a state: the selected row also has a fill, and the
  open state is also spelled out in the "open in" line.
- Every action is reachable by keyboard.

## Tokens to reuse

- Brand colors and the mustard values: [`design/brand/tokens/brand-tokens.json`](../brand/tokens/brand-tokens.json). Use
  `mustard` for fills and graphite for text on it.
- Shell tokens: find them with `grep -rn ShellTokens app/ArktShell/ShellKit/Sources`. The existing command bar
  tokens (`commandBarSurface`, `commandBarText`, `commandBarSecondaryText`, `commandBarDivider`,
  `commandBarSelectedRow`, `commandBarBorder`) are the starting point; the light appearance needs token pairs.
  Reuse `toastSurface`, `toolbarSurface`, `primaryText`, `secondaryText`, `sidebarItemHovered` and `sidebarDivider`
  where they fit rather than adding colors.
- New tokens this design needs: a mustard fill for the tick and the primary button, a scrim, the pill capsule fills,
  and the open-dot green. Add them as pairs and extend `ShellTokensContrastTests`.
- Metrics: `CommandBarGeometry` holds today's values (766 wide, 50 high rows). This design replaces them with the
  values in [Layout](#layout); the old numbers were measured, these are Arkt's own.

## Open questions

1. **Tab key.** Tab cycles the filters, but #322 gives Tab a second job: scope the bar to a site search, or enter
   action search from the empty field. The rule above resolves it by context (Tab scopes when the selected row shows
   a Tab key cap, cycles otherwise). Confirm, or move one of the two to another key.
2. **History without a snapshot.** Is the favicon on a neutral well acceptable for history rows that have no cached
   thumbnail, or should the preview column be hidden for them?
3. **Primary action on a history row.** "Open" in the primary slot, with Split View opening a new pane: confirm the
   wording and the behavior.
4. **Filter counts.** Do the counts update live while results stream in, or settle once per query?
5. **Window width.** Below roughly 1000 pt of window width the 968 bar leaves little margin. Assumed: the bar keeps
   24 pt of side margin and the preview column narrows to a minimum of 240; below that, no preview. Confirm.
6. **Archived results and the Archived filter.** Archived rows appear under All and Tabs; should they also get a
   fifth pill?

## Screenshot index

All in [`screens/`](screens/), 2000 x 1250 px (the 1280 x 800 pt prototype), 8-bit palette PNG, each under 400 KB.
Titles and URLs are synthetic. The rejected directions in [`directions/`](directions/) are history only and are not
to be built.

| File | State |
|---|---|
| `hybrid-tab-dark.png` | A tab row selected: 968 wide with the preview column, dark |
| `hybrid-search-dark.png` | A site-search row selected: 680 wide, no preview, dark |
| `hybrid-tab-light.png` | A tab row selected with the preview column, light |
| `hybrid-empty-dark.png` | Empty query: Clipboard, Recent tabs, Actions, dark |
