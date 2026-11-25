# Command bar

Design for the command bar (#988, replacing the hybrid from #112): the overlay that Cmd-T and Cmd-L open to type an
address, search, switch to an open tab, show a folder, open a page from history or run an extension. Everyday chrome, so it uses the system font.

The maintainer's brief: "simple, fast and reliable". One field, one list, no modes, nothing to learn. The grouped
direction was picked from four mocks (Spotlight, Inline, Grouped, Answer first). The previous hybrid is kept in
[`directions/hybrid/`](directions/hybrid/) with the reason; the other three mocks live only in the history of the
#988 pull request.

- Prototype: [`prototype/index.html`](prototype/index.html), 1280 x 800 pt. States by URL hash:
  `#s=empty|search|url|worst|none|small&theme=light|dark`. `small` is the 640 x 420 pt minimum window.
- Screens: [`screens/`](screens/), `<state>-<light|dark>.png`, 2x, each under 400 KB. Titles and URLs are synthetic.
- Render (zsh, from the repo root; headless Chromium from Playwright):

      CH=$(print -l ~/Library/Caches/ms-playwright/chromium_headless_shell-*/**/chrome-headless-shell(N) | tail -1)
      $CH --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,800 \
        --screenshot=design/command-bar/screens/search-dark.png \
        "file://$PWD/design/command-bar/prototype/index.html#s=search&theme=dark"

## What it is, and what it is not

One text field and one list. The list has up to five groups, in a fixed order: **Tabs**, **Folders**, **History**,
**Extensions**, **Search**. Each group shows at most 3 rows and only appears when it has rows. Return runs the selected
row. That is the whole surface.

Removed from the hybrid, and not coming back in this design: filter pills and Cmd-1 to Cmd-4, the preview column and
Split View in the bar, the hint strip, the Esc key cap, the mustard selection tick and the sliding selection, per-row
kind labels ("Switch to Tab" on every row), the actions group, Space rows, site search with its Tab key, archived results and the
bar widening. Kept: open tabs, history, search suggestions, typed addresses, and Paste and Go as one row. Added
back by the maintainer's decision (#562, BH-104): folders and extensions as result groups.

## Look

A centred glass panel over a lightly dimmed window. The panel is a blurred, saturated surface with a 1 pt inner edge,
a 0.5 pt outer edge and a soft shadow, 14 pt continuous corners. Light and dark are both required; the screens show both.

Typeface: the system font (SF Pro; `-apple-system` in the prototype). Brand rules (`design/brand/README.md`):

- Mustard is a fill only. Here it is used once: the 2 pt caret. It is never text, never a stroke, never the selection.
- The selection is a neutral fill, `commandBarSelectedRow` (see the token table below). No tick, no ring.
- No user-facing "Arc". Say "browser data" if the data source ever has to be named.
- No contrast ratios or warnings in the UI.

No new tokens and no changed token values. Every value below already exists in `ShellTokens`
(`app/ArktShell/ShellKit/Sources/ShellUI/Theme/ShellTokens.swift`); the prototype uses the same numbers.

| Token | Value (light / dark) | Use here |
|---|---|---|
| `commandBarSurface` | `#FDFCF9` 86 % / `#292C2A` 84 %, over the blur | panel fill |
| `commandBarSurfaceOpaque` | `#FAF9F5` / `#262927` | panel fill under Reduce Transparency, and the surface contrast is measured on |
| `commandBarText` | graphite / porcelain | field text, row titles, the bold query match |
| `commandBarSecondaryText` | graphite 72 % / porcelain 72 % | icons, the verb, key cap label |
| `commandBarTertiaryText` | graphite 68 % / porcelain 62 % | row URL, trailing time, group headers, placeholder |
| `commandBarDivider` | graphite 9 % / white 7 % | hairline under the field |
| `commandBarInnerEdge`, `commandBarBorder` | white 70 % / white 9 %; graphite 18 % / black 60 % | 1 pt inner edge, 0.5 pt outer edge |
| `commandBarSelectedRow` | graphite 7 % / white 10 % | selected and hovered row fill |
| `commandBarKeyCap` | graphite 5.5 % / white 7 % | Return key cap |
| `commandBarScrim` | graphite 10 % / `#0A0B0A` 28 % | dim over the window |
| `increasedContrastEdge` | black 20 % / white 20 %, 1 pt | Increase Contrast: the panel's edge |

Token usage changes (values unchanged): row titles now use `commandBarText` at rest (the hybrid used
`commandBarSecondaryText`), so the bold match and the selected fill carry the hierarchy.

Removed with the code that used them: `commandBarPillWell`, `commandBarPillOn`, `commandBarPillOnText`,
`commandBarTick`, `commandBarThumbnailWell`, `commandBarOpenDot`.

## Layout

All values in points. Window sizes from 640 x 420 (the shell minimum) up.

| Element | Value |
|---|---|
| Panel width | `min(600, window width - 48)`; 600 in any window 648 or wider |
| Panel position | horizontally centred; top edge `clamp(48, 14 % of window height, 110)`, rounded to a whole point (59 in the 420 pt window), and fixed, so results grow downward only |
| Panel height | field plus list; at most `window height - top - 24`, then the list scrolls |
| Panel corners | 14, continuous |
| Field | 54 high; 20 regular; 20 side inset; magnifier 18, 12 gap to the text; placeholder "Search or enter address" |
| Caret | 2 wide, mustard fill |
| Divider | 1 hairline under the field |
| List padding | 6 on the sides, 6 on top, 8 on the bottom |
| Group header | 11 semibold, tertiary text, +0.02 em tracking; 26 high including 10 above (20 high, 4 above, for a group that starts the list) |
| Row | 36 high, 8 corner radius, 10 horizontal padding, 12 gap |
| Row slot | 18 wide: favicon 16 (4 radius) or a 16 symbol (clock for history, magnifier for search, globe for Go, clipboard for Paste and Go, folder for a folder, the extension's own icon or a puzzle piece for an extension) |
| Row title | 14 regular, text; the part that matches the query 600 weight |
| Row secondary text | 13 regular, tertiary text: host and path without the scheme (tabs, history), "<n> tabs" (folders), the extension's short description (extensions) |
| Trailing | 12; history rows show the relative time ("Yesterday") when not selected; the selected row shows its verb and the Return key cap |
| Return key cap | 20 high, 5 radius, 11 medium |
| Scrollbar | system overlay scroller, right edge |

### Row order and what each group searches

Selection always starts on the first row of the list. Rows keep their position while typing: a late result never
inserts above the selection.

1. **Literal row, no header, only when it applies** (the Go and Paste and Go rows only; the Search for row belongs to the Search group). It sits above the groups and is the selected row.
   - Empty field and the clipboard holds an address: **Paste and Go**, with the address in the URL slot. Only on the
     Cmd-T bar, like Cmd-Shift-V: Cmd-L and the split pane bar do not offer it.
   - The field parses as an address (scheme, or `host.tld`, with optional path): **Go**, showing the text as typed.
2. **Tabs.** Open tabs in this window, all Spaces, excluding the current tab. Matches word starts in the title and in
   host and path. Ranked by match quality, then by recency of viewing. Empty field: the 3 most recently viewed. A tab
   inside a closed folder is found here; switching to it shows it peeking out under the folder (BH-105, built).
3. **Folders.** Folders in the Pinned section of this window, nested ones included, matched on the folder name by word
   starts. Ranked by match quality, then by when a tab in the folder was last viewed. Secondary text: "<n> tabs".
   Return shows the folder: it opens in the sidebar and scrolls into view, and the bar closes. Not shown for an empty
   field.
4. **History.** Browser history, matched like tabs, ranked by frecency. A page that is already an open tab is not
   shown again. Empty field: the 3 most recent visits. Row shows the relative time.
5. **Extensions.** Installed, enabled extensions that have a toolbar action, matched on name and short description by
   word starts. Ranked by match quality, then by name. Return opens the extension's popup from the toolbar button, as
   a click would. Not shown for an empty field.
6. **Search.** Only with text in the field. First row, always present: **Search for "<text>"** with the exact text
   (sent as typed, with the user's search engine from Settings). Then up to 2 suggestions from the search engine when
   "Include search engine suggestions" is on (#562). Suggestions arrive asynchronously and fill rows below the
   Search for row; nothing above them moves.

Why this order. Tabs and Folders come first because they are the user's own sidebar: live, nearest, and the usual
target of Cmd-L/Cmd-T typing. History is the past. Extensions are a rare target, so they sit just above Search, where
a miss costs one row of scrolling. Search is last on purpose: its suggestions arrive late, and a group at the bottom can
grow without moving anything above it. Because selection starts on the first row, that is the best match among the
user's own things, and Cmd-Return is the one key for "no, search the web".

Consequences worth stating: there is no "no results" dead end, because the Search row is always there; an address
that is also a tab shows both the Go row and the tab; the cap is 3 rows per group, so the panel has at most 16 rows and 5
headers: a Go row, 3 tabs, 3 folders, 3 history rows, 3 extensions, and the Search for row with 2 suggestions.

Height arithmetic, for that worst case: field 54 + divider 1 + list padding 14 + 16 rows x 36 (576) + headers
5 x 26 (130, the Go row starts the list, so no header is 20) = 775 pt. (`worst-*.png` shows 15 rows, because "layout" is not an address, so there is no Go row;
that is 733 pt.) The panel may be at most `window height - top - 24` tall, so the worst case
fits without scrolling only in a window at least 909 pt high (top 110 + 775 + 24). In the 800 pt prototype window the
worst case scrolls (`worst-*.png` shows the overlay scroller). The `url` screens show no suggestions; the search engine often returns none for an address. Typical queries match two or three groups (about
300 to 520 pt) and fit in any window of 700 pt or more. When it scrolls, moving the selection scrolls the row into view
with the least movement, and group headers scroll with their rows. The cap of 3 is what keeps the worst case bounded.

### Truncation

- Titles are one line, tail ellipsis, never wrap. The title is protected: the URL truncates first.
- The URL is dropped entirely when less than 48 wide would remain, rather than showing a stub.
- A suggestion that is too long truncates with an ellipsis like a title.
- **Folder** and **Extension** rows: the name is the title and is protected; the secondary text ("<n> tabs", the
  description) truncates first and is dropped under the same 48 pt rule.
- **Go** row: the typed text is the title, tail ellipsis, no URL slot.
- **Paste and Go** row: the title "Paste and Go" is protected; the clipboard address sits in the URL slot, tail ellipsis, dropped under the same 48 pt rule.
- The field scrolls horizontally with the caret; it never wraps and never grows.
- Right-to-left and CJK text align and truncate by their own direction; the layout mirrors.

### States (see `screens/`)

| State | File | Notes |
|---|---|---|
| Empty | `empty-{light,dark}.png` | Paste and Go (only when the clipboard holds an address), Tabs (3 recent), History (3 recent). No Folders, Extensions or Search group. |
| Typing a search | `search-{light,dark}.png` | query "git": Tabs, Folders, History, Extensions, Search with the Search for row and 2 suggestions. |
| Typing an address | `url-{light,dark}.png` | the Go row on top, the matching tab and history row below, one Search for row. |
| Worst case | `worst-{light,dark}.png` | very long titles and URLs, CJK, all five groups full: capped at 3 rows each, 15 rows, 733 pt tall, so it scrolls in the 800 pt window. |
| No results | `no-results-{light,dark}.png` | only the Search header and the Search for row, selected. The panel shrinks to field, header and one row. |
| Smallest window | `small-window-{light,dark}.png` | 640 x 420: panel 592 wide, top 59, list scrolls. |

## Keyboard

Focus never leaves the field. Typing always edits the text; the list is driven by key events.

| Key | Action |
|---|---|
| Cmd-T | Open on a new tab. Empty field. Return opens the result in that new tab. |
| Cmd-L | Open on the current tab. The field holds the current address, fully selected, and the list shows the empty state; typing replaces it. Return opens the result in the current tab. |
| Up / Down | Move the selection one row, across groups. Wraps from the last row to the first and back on a fresh press; held-key repeat stops at the ends. Ctrl-P and Ctrl-N do the same. |
| Tab / Shift-Tab | Jump to the first row of the next or previous group; the literal row counts as a group of its own. Stops at the last and first group (no wrap). Tab does nothing else (site search is gone). |
| Return | Run the selected row: Switch to Tab, Show Folder, Open (history), Open Extension, Go, Search, or Paste and Go. With the Cmd-L address untouched, Return reloads the page (KB-004, unchanged). |
| Opt-Return | Run the selected row in a new tab (KB-085, unchanged). |
| Cmd-Return | Search the web for exactly the typed text, whatever is selected, where Return would open it (the new tab, the current tab, the new split pane). The escape hatch when a tab or history row outranks what you meant. |
| Cmd-Shift-V | Paste and Go from any state (unchanged from #322). |
| Cmd-Opt-Delete | Remove the selected history row from history (unchanged from #322). Other rows are not removable, and rows have no hover remove button. |
| Esc | Clear the text if there is any, otherwise close. With the Cmd-L address untouched, Esc closes. |
| Click a row | Runs it. Click outside the panel closes. |
| Hover | Shows the hover fill. The keyboard selection does not move until the pointer actually moves. |

Text editing keys (arrows in the field, Option-arrows, Cmd-A, undo) belong to the field, as everywhere else.

## Selected row

A neutral fill over the whole row (no tick, no stroke). The trailing area shows the verb in 12 secondary text and the
Return key cap: "Switch to Tab" (tab), "Show Folder" (folder), "Open" (history), "Open Extension" (extension), "Go" (Go and
Paste and Go), "Search" (a suggestion). The Search for row shows the key cap only, because its title already says it.
Unselected history rows show their time instead. Only the selected row carries a verb, so there is no per-row label
column to read.

## Motion

Opening the bar is a keyboard action used many times a day, so it does not animate. This follows the project's motion
rule (motion with a purpose; none here has one) and Raycast/Spotlight practice.

| Transition | Motion |
|---|---|
| Open | Fully laid out on the first frame, scrim included. No fade, no scale. The target is the first frame after the key press. |
| Close | Immediate, on the same frame as the action. |
| Typing | The list updates in place on every keystroke, no cross-fade. The top edge stays; height changes instantly. |
| Selection move | Instant fill change, no slide. |
| Hover | Instant fill change. |
| Press on a row | Fill goes to 100 % of its token while the button is down (feedback on pointer-down, action on release). No scale. |

Reduce Motion: identical, there is nothing to reduce. **Reduce Transparency**: the panel fills with
`commandBarSurfaceOpaque`, blur off, shadow stays. **Increase Contrast**: the panel gets a 1 pt `increasedContrastEdge`
(black 20 % / white 20 %, drawn as a layer border so nothing changes size), and tertiary text (URL, time, group
headers, placeholder) uses `commandBarSecondaryText`.

## What keeps it fast and reliable

- The list is filled synchronously from in-memory indexes (open tabs, folders, history, extensions) on every keystroke: top 3 per group,
  no thumbnails, no preview snapshots, no network on the key path.
- Favicons come from the existing cache and fall back to a letter tile; a missing one never delays a row.
- Search suggestions are the only async part. They fill rows below the Search for row, never above, and are dropped if
  the text changed (generation check, see #884).
- Return always has something to do: the Search row exists whenever there is text, and Paste and Go or Go cover the
  rest.
- No state to remember between opens: no filter, no preview target, no scope. Each open starts the same way.
- Bounded work: at most 16 rows laid out, so layout cost is constant.

## Accessibility

- The panel is a dialog group labelled "Command bar". The field is the first element, an `AXTextField` labelled
  "Search or enter address", and keeps focus.
- The list is the results table, `AXTable` `commandBar.results` with `AXRow` rows, as the shell's other lists (the UI test harness
  reads it as a table). Each row that starts a group holds its header as an `AXGroup` label ("Tabs", "Folders", "History", "Extensions", "Search"). Each row reads
  "<title>, <secondary text, if any>, <kind>, <k> of <n>" with kind one of "open tab", "folder", "history", "extension", "search suggestion", "search for
  what you typed", "go to address", "paste and go". The selected row is announced on every move.
- After typing settles (150 ms), announce the count once: "<n> results". With only the Search row:
  "No matches. Return searches the web."
- Every action is reachable by keyboard; mouse is optional.
- Selected state is a fill plus the Return key cap and the verb, never color alone.
- Text on the glass meets 4.5:1 against both appearance fills; check against the opaque Reduce Transparency fill too.
- Dynamic type is not a macOS concept here; the sizes above are fixed, as for the rest of the chrome.

## Build notes (#993)

Settled while building, where this document was silent:

- **Matching.** Word starts, ignoring case and diacritics, in the title and in the address as stored (an
  internationalized host in its `xn--` form). The host as the rows show it is matched ignoring case only, so a
  look-alike host is never found by folding its accents away (#732).
- **"<n> tabs".** Every tab inside the folder, nested folders included; a Split View counts as one tab, as its row does.
- **History and suggestions.** There is no history store and no suggestion fetcher yet. Both groups take a provider
  (history in frecency order; suggestions asynchronous, dropped when the text changed or the bar hid, #884); the app
  passes none today, so History and the suggestion rows stay empty until those land.
- **Removed with the hybrid.** The search-suggestion privacy notice (BH-113) and its dismissed setting: the layout above
  has no place for it and nothing is sent to an engine yet. It comes back with the suggestion fetcher if it is needed.

## Decisions

The maintainer answered the open questions on 2026-11-25:

1. The Search for "<text>" row is always present while there is text, so a query never ends in an empty list.
2. A typed address gets a Go row above the groups, selected.
3. Cmd-Return searches the web for exactly the typed text, whatever is selected.
4. Tab and Shift-Tab jump to the first row of the next or previous group.
5. Up and Down wrap on a fresh press and stop at the ends on a held key repeat.
6. The current tab is excluded from Tabs.
7. Space rows are dropped; tabs in other Spaces are still found under Tabs.
8. Extensions and folders return as result groups (#562, BH-104): Folders after Tabs, Extensions after History, 3 rows
   each, neither shown for an empty field.
