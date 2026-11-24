# Command bar

Design for the command bar (#988, replacing the hybrid from #112): the overlay that Cmd-T and Cmd-L open to type an
address, search, switch to an open tab or open a page from history. Everyday chrome, so it uses the system font.

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

One text field and one list. The list has up to three groups, in a fixed order: **Tabs**, **History**, **Search**.
Each group shows at most 3 rows. Return runs the selected row. That is the whole surface.

Removed from the hybrid, and not coming back in this design: filter pills and Cmd-1 to Cmd-4, the preview column and
Split View in the bar, the hint strip, the Esc key cap, the mustard selection tick and the sliding selection, per-row
kind labels ("Switch to Tab" on every row), the actions group, site search with its Tab key, archived results and the
bar widening. Kept: open tabs, history, search suggestions, typed addresses, and Paste and Go as one row.

## Look

A centred glass panel over a lightly dimmed window. The panel is a blurred, saturated surface with a 1 pt inner edge,
a 0.5 pt outer edge and a soft shadow, 14 pt continuous corners. Light and dark are both required; the screens show both.

Typeface: the system font (SF Pro; `-apple-system` in the prototype). Brand rules (`design/brand/README.md`):

- Mustard is a fill only. Here it is used once: the 2 pt caret. It is never text, never a stroke, never the selection.
- The selection is a neutral fill (white 11 % in dark, graphite 7.5 % in light). No tick, no ring.
- No user-facing "Arc". Say "browser data" if the data source ever has to be named.
- No contrast ratios or warnings in the UI.

| Token (existing in `ShellTokens`) | Use |
|---|---|
| `commandBarSurface` | panel fill, with the blur; dark `rgb(40 43 41 / 88%)`, light `rgb(252 251 248 / 90%)` |
| `commandBarText` | field text, row titles, bold query match |
| `commandBarSecondaryText` | row URL, verb, trailing time, icons |
| `commandBarTertiaryText` (new, if not present) | placeholder, group headers; dark white 38 %, light graphite 42 % |
| `commandBarDivider` | hairline under the field |
| `commandBarSelectedRow` | selected and hovered row fill; hover is the same fill at 60 % |
| `commandBarBorder` | 1 pt inner edge, 0.5 pt outer edge |
| `commandBarScrim` | dark 34 % black, light 12 % graphite |

The mustard tick token, pill fills and preview tokens go away with the code that used them.

## Layout

All values in points. Window sizes from 640 x 420 (the shell minimum) up.

| Element | Value |
|---|---|
| Panel width | `min(600, window width - 48)`; 600 in any window 648 or wider |
| Panel position | horizontally centred; top edge `clamp(48, 14 % of window height, 110)` and fixed, so results grow downward only |
| Panel height | field plus list; at most `window height - top - 24`, then the list scrolls |
| Panel corners | 14, continuous |
| Field | 54 high; 20 regular; 20 side inset; magnifier 18, 12 gap to the text; placeholder "Search or enter address" |
| Caret | 2 wide, mustard fill |
| Divider | 1 hairline under the field |
| List padding | 6 on the sides, 6 on top, 8 on the bottom |
| Group header | 11 semibold, tertiary text, +0.02 em tracking; 26 high including 10 above (20 high, 4 above, for the first group) |
| Row | 36 high, 8 corner radius, 10 horizontal padding, 12 gap |
| Row slot | 18 wide: favicon 16 (4 radius) or a 16 symbol (clock for history, magnifier for search, globe for Go, clipboard for Paste and Go) |
| Row title | 14 regular, text; the part that matches the query 600 weight |
| Row URL | 13 regular, tertiary text, host and path without the scheme |
| Trailing | 12; history rows show the relative time ("Yesterday") when not selected; the selected row shows its verb and the Return key cap |
| Return key cap | 20 high, 5 radius, 11 medium |
| Scrollbar | system overlay scroller, right edge |

### Row order and what each group searches

Selection always starts on the first row of the list. Rows keep their position while typing: a late result never
inserts above the selection.

1. **Literal row, no header, only when it applies.** It sits above the groups and is the selected row.
   - Empty field and the clipboard holds an address: **Paste and Go**, with the address in the URL slot.
   - The field parses as an address (scheme, or `host.tld`, with optional path): **Go**, showing the text as typed.
2. **Tabs.** Open tabs in this window, all Spaces, excluding the current tab. Matches word starts in the title and in
   host and path. Ranked by match quality, then by recency of viewing. Empty field: the 3 most recently viewed.
3. **History.** Browser history, matched like tabs, ranked by frecency. A page that is already an open tab is not
   shown again. Empty field: the 3 most recent visits. Row shows the relative time.
4. **Search.** Only with text in the field. First row, always present: **Search for "<text>"** with the exact text
   (sent as typed, with the user's search engine from Settings). Then up to 2 suggestions from the search engine when
   "Include search engine suggestions" is on (#562). Suggestions arrive asynchronously and fill rows below the
   literal row; nothing above them moves.

Consequences worth stating: there is no "no results" dead end, because the Search row is always there; an address
that is also a tab shows both the Go row and the tab; the cap of 3 means the panel is at most 3 groups x 3 rows plus a
literal row, 10 rows and 3 headers (about 500 high with the field), and in a normal window never scrolls. It scrolls
only when the window is too short (see small window).

### Truncation

- Titles are one line, tail ellipsis, never wrap. The title is protected: the URL truncates first.
- The URL is dropped entirely when less than 48 wide would remain, rather than showing a stub.
- A suggestion that is too long truncates with an ellipsis like a title.
- The field scrolls horizontally with the caret; it never wraps and never grows.
- Right-to-left and CJK text align and truncate by their own direction; the layout mirrors.

### States (see `screens/`)

| State | File | Notes |
|---|---|---|
| Empty | `empty-{light,dark}.png` | Paste and Go (only when the clipboard holds an address), Tabs (3 recent), History (3 recent). No Search group. |
| Typing a search | `search-{light,dark}.png` | query "git": Tabs, History, Search with the literal row and 2 suggestions. |
| Typing an address | `url-{light,dark}.png` | the Go row on top, the matching tab and history row below, one literal Search row. |
| Worst case | `worst-{light,dark}.png` | very long titles and URLs, CJK, all groups full: capped at 3 rows each. |
| No results | `no-results-{light,dark}.png` | only the Search group with the literal row, selected. The panel shrinks to field plus one row. |
| Smallest window | `small-window-{light,dark}.png` | 640 x 420: panel 592 wide, top 59, list scrolls. |

## Keyboard

Focus never leaves the field. Typing always edits the text; the list is driven by key events.

| Key | Action |
|---|---|
| Cmd-T | Open on a new tab. Empty field. Return opens the result in that new tab. |
| Cmd-L | Open on the current tab. The field holds the current address, fully selected, and the list shows the empty state; typing replaces it. Return opens the result in the current tab. |
| Up / Down | Move the selection one row, across groups. Wraps from the last row to the first and back on a fresh press; held-key repeat stops at the ends. Ctrl-P and Ctrl-N do the same. |
| Tab / Shift-Tab | Jump to the first row of the next or previous group. Tab does nothing else (site search is gone). |
| Return | Run the selected row: Switch to Tab, Open (history), Go, Search, or Paste and Go. |
| Cmd-Return | Search the web for exactly the typed text, whatever is selected. The escape hatch when a tab or history row outranks what you meant. |
| Cmd-Shift-V | Paste and Go from any state (unchanged from #322). |
| Cmd-Opt-Delete | Remove the selected history row from history (unchanged from #322). |
| Esc | Clear the text if there is any, otherwise close. With the Cmd-L address untouched, Esc closes. |
| Click a row | Runs it. Click outside the panel closes. |
| Hover | Shows the hover fill. The keyboard selection does not move until the pointer actually moves. |

Text editing keys (arrows in the field, Option-arrows, Cmd-A, undo) belong to the field, as everywhere else.

## Selected row

A neutral fill over the whole row (no tick, no stroke). The trailing area shows the verb in 12 secondary text and the
Return key cap: "Switch to Tab", "Open", "Go", "Search" (omitted on the Search for row, which already says it).
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

Reduce Motion: identical, there is nothing to reduce. **Reduce Transparency**: opaque `commandBarSurface`, blur off,
shadow stays. **Increased Contrast**: the 1 pt inner edge goes to a defined border at full contrast; secondary text
steps up one level.

## What keeps it fast and reliable

- The list is filled synchronously from in-memory indexes (open tabs, history) on every keystroke: top 3 per group,
  no thumbnails, no preview snapshots, no network on the key path.
- Favicons come from the existing cache and fall back to a letter tile; a missing one never delays a row.
- Search suggestions are the only async part. They fill rows below the literal row, never above, and are dropped if
  the text changed (generation check, see #884).
- Return always has something to do: the Search row exists whenever there is text, and Paste and Go or Go cover the
  rest.
- No state to remember between opens: no filter, no preview target, no scope. Each open starts the same way.
- Bounded work: at most 10 rows laid out, so layout cost is constant.

## Accessibility

- The panel is a dialog group labelled "Command bar". The field is the first element, an `AXTextField` labelled
  "Search or enter address", and keeps focus.
- The list is an `AXList`. Group headers are `AXGroup` labels ("Tabs", "History", "Search"). Each row reads
  "<title>, <host>, <kind>, <k> of <n>" with kind one of "open tab", "history", "search suggestion", "search for
  what you typed", "go to address", "paste and go". The selected row is announced on every move.
- After typing settles (150 ms), announce the count once: "<n> results". With only the Search row:
  "No matches. Return searches the web."
- Every action is reachable by keyboard; mouse is optional.
- Selected state is a fill plus the Return key cap and the verb, never color alone.
- Text on the glass meets 4.5:1 against both appearance fills; check against the opaque Reduce Transparency fill too.
- Dynamic type is not a macOS concept here; the sizes above are fixed, as for the rest of the chrome.

## Open questions

1. **Cmd-Return** is proposed as "search the web for exactly this text". Alternative: open the selected result in a
   new tab. Confirm.
2. **Tab key** now jumps between groups. If you prefer, make it do nothing and keep Up/Down only.
3. **Current tab** is excluded from Tabs. Confirm that Cmd-L on the page you are already on should never offer to
   "switch" to it.
4. **Extensions and folders as results** (#562) are not in this design. Say if they should return as a fourth group.
