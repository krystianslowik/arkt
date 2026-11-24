# Command bar redesign, four mocks (#988)

The maintainer found the hybrid (`../README.md`) overengineered: filter pills with counts, a 300 pt preview column that
widens the bar, a hint strip, a mustard selection tick, Paste and Go, site search, archived results and actions in one
surface. These four mocks each take a different route to "one input, one list, keyboard-first, instant".

Common to all four: system font, no pills, no preview column, no hint strip, no Esc key cap, no counts. Selection is a
neutral fill, never mustard. Mustard appears only as the caret fill (and, in mock 4, the one primary pill). Return
opens the selected row, Up/Down move, Esc clears then closes. Focus never leaves the field. Synthetic data only.

How to view: open `<n>/index.html#s=empty|search|worst&theme=light|dark` (1280 x 800 pt). PNGs are in `<n>/screens/`,
2x, headless Chromium, each under 400 KB (the few largest worst-case ones are palette-quantized at 256 colors).

Render command (zsh, from the repo root):

    CH=$(print -l ~/Library/Caches/ms-playwright/chromium_headless_shell-*/**/chrome-headless-shell(N) | tail -1)
    $CH --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,800 \
      --screenshot=design/command-bar/redesign/1/screens/search-dark.png \
      "file://$PWD/design/command-bar/redesign/1/index.html#s=search&theme=dark"

| # | Idea | Drops from the hybrid | Result cap |
|---|---|---|---|
| 1 | Spotlight: one centred field, one flat list, a quiet kind label on the right | pills, preview, hint strip, group headers, Esc cap | scrolls, 9 rows visible |
| 2 | Inline: the sidebar address pill itself grows into the panel, no scrim | pills, preview, hint strip, scrim, the centred overlay | scrolls, 8 rows visible |
| 3 | Grouped: centred field, three quiet labels (Tabs / History / Search) | pills, preview, hint strip, per-row kind labels | 3 per group, never scrolls |
| 4 | Answer first: row one always names what Return does, with the verb | pills, preview, hint strip, scrolling | 6 rows total, never scrolls |

## Motion and speed, per mock (emil: no animation on keyboard actions used 100+ times a day)

1. **Spotlight.** Opens and closes with no animation: fully laid out on the first frame, scrim included. Reduce Motion
   variant: identical. Fast because: the list is filled synchronously from an in-memory index on every keystroke (top 9
   by rank, no network, no thumbnails), favicons come from cache and fall back to a tile.
2. **Inline.** Purpose: spatial continuity, the pill and the panel are the same object. Open: panel scales from
   `scale(.97)` to 1 and fades in, `transform-origin: 0 0` (the pill corner), 140 ms `cubic-bezier(.23,1,.32,1)`,
   transform and opacity only; close is 90 ms opacity only. Reduce Motion: 80 ms cross-fade, no scale. Fast because:
   the field is already on screen, so focus lands before the first frame; the list is filled as in 1.
3. **Grouped.** No animation, as in 1. Reduce Motion: identical. Fast because: each group is ranked and cut to 3
   independently, so the worst case is 9 rows and the layout is bounded and cheap; groups appear only when non-empty.
4. **Answer first.** No animation, as in 1. The first row changes in place per keystroke, no slide. Reduce Motion:
   identical. Fast because: the answer is computed first and painted first; the 5 rows under it may arrive a frame later
   without moving the answer. Never scrolls, so no scroll-position state.

## Features, per mock (open questions for the maintainer)

All four keep: open tabs, history, search suggestions, typed URLs, and Paste and Go as one row when the clipboard holds
a URL (empty state). All four drop: filter pills and Cmd-1..4, the preview column and Split View from the bar, site
search with its Tab key, archived results, the actions group. Each can be re-added later as an ordinary row type.
