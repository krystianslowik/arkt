# Arc measurements for the TODO(measure) tokens (#77)

Passive measurement pass over a running Arc 1.168.0. Arc was only observed: no clicks, keys, scrolls, menu presses,
window moves or focus changes, and none of Arc's data files were read. The values here are inputs for the follow-up
that changes the code and the tests that pin them; this file changes no code.

## Setup and method

- Arc 1.168.0 (version from the app bundle), one browser window of 1800 x 1072 pt on a 2x display. The capture is in
  Display P3; colors below are converted to sRGB (8 bit) and also given as raw P3 where they differ.
- System appearance Dark. Only one Space was on screen, so every color is for one Space theme only. Light appearance
  and a second theme were not available without switching, and nothing was switched.
- The Arc window was **not key** (traffic lights drawn gray). Surface colors are reliable for that state; text, glyph
  and hairline levels may be dimmed compared with a key window.
- The Toolbar was **on** (View menu showed "Hide Toolbar", Shift-Cmd-D). No tab row was selected or hovered, the
  command bar, toasts and Split View were not showing.
- Methods:
  - **AX**: read-only accessibility frames (role, position, size) of Arc's window tree; window-relative points.
    No titles, values or descriptions were recorded.
  - **Pixels**: a window-only capture (`screencapture -l <id> -x -o`), 2 device px per pt. Edges were found by luminance
    scans and bounding boxes; colors are averages over chrome-only areas (Arc's grain adds about +-3 per channel per
    pixel). The capture was deleted after the pass and is not in the repository.
  - **Menu**: read-only reads of menu item titles and key equivalents from the menu bar's accessibility tree, without
    opening a menu. Only generic action items were read (not the Spaces, Archive or Window menus).
- Confidence: **exact (AX)** = a frame read from the accessibility tree; **measured (px)** = from the capture, +-0.5 pt;
  **inferred** = derived from other values or a related element, with the assumption stated.

## Tokens

`ShellUI` = `app/ArktShell/ShellKit/Sources/ShellUI`. Line numbers are on `main` at df073b9. The issue lists 36
tokens; `main` now has 39 (adds `TabRowState.swift:32` and `:33` from #156 and `SplitContainerView.swift:40` from
#154).

| Token | File:line | Arkt now | Arc value | Method | Confidence |
|---|---|---|---|---|---|
| `maxVisibleRows` | `ShellUI/CommandBar/CommandBarGeometry.swift:12` | 8 | not measured (command bar closed) | - | checklist |
| bottom bar `buttonSize` | `ShellUI/Sidebar/SidebarContainerView.swift:254` | 28 | **32 x 32**; 8 pt from the sidebar's leading and trailing edges; glyphs about 14.5 x 16.5 (archive) and 14 x 14 (plus) | AX frames; glyph bboxes from px | exact (AX) |
| `rowCornerRadius` | `ShellUI/Sidebar/TabRowState.swift:9` | 9 | not measured (no selected or hovered row on screen) | - | checklist |
| `titleTrailing` | `ShellUI/Sidebar/TabRowState.swift:14` | 10 | **9** from the row's visual trailing edge. AX title frame ends 17 pt before the sidebar edge (x 175 of 192); with Arkt's 8 pt row inset that is 9 | AX text frame | inferred (assumes the row fill is inset 8 pt, as for Favorites and the bottom buttons) |
| `closeButtonSize` | `ShellUI/Sidebar/TabRowState.swift:16` | 20 | not measured (hover only) | - | checklist |
| `closeButtonGlyphSize` | `ShellUI/Sidebar/TabRowState.swift:17` | 10 | not measured (hover only) | - | checklist |
| `closeButtonTrailing` | `ShellUI/Sidebar/TabRowState.swift:18` | 7 | not measured (hover only) | - | checklist |
| `closeButtonTitleGap` | `ShellUI/Sidebar/TabRowState.swift:19` | 4 | not measured (hover only) | - | checklist |
| `closeButtonFadeDuration` | `ShellUI/Sidebar/TabRowState.swift:20` | 0.12 s | not measured (needs a screen recording of a hover) | - | checklist |
| `spaceTitleHeight` | `ShellUI/Sidebar/TabRowState.swift:24` | 28 | **36**: Space header top to tab list top. Icon 26 x 26 at 5 pt from the header top, name text frame 18 pt tall, both centered in the 36 pt band. The tab list then starts with a 3 pt spacer row | AX frames | exact (AX) |
| `dividerHeight` | `ShellUI/Sidebar/TabRowState.swift:25` | 13 | **25** row height (other rows 41). Hairline inset 18 pt on both sides (x 18 to 174 at width 192), AX height 0.5 pt, drawn 2 device px tall, about 11.5 pt from the row top. Color sRGB #848484 over the #7A7A7A sidebar, about white 7.5 % | AX frames; px for color and thickness | exact (AX) height; measured (px) line |
| `indentationPerLevel` | `ShellUI/Sidebar/TabRowState.swift:26` | 14 | **16** (child row starts at x 16, child favicon at x 33 vs 17 at level 0) | AX frames | exact (AX) |
| `favoritesTopGap` | `ShellUI/Sidebar/TabRowState.swift:27` | 4 | URL bar to Favorites not measurable: Arc hides the sidebar URL bar while the Toolbar is on. With the Toolbar on, the Favorites section starts 36 pt below the window top and the tiles 8 pt below that | AX frames | checklist (Toolbar off); exact (AX) for the Toolbar-on layout |
| `favoritesBottomGap` | `ShellUI/Sidebar/TabRowState.swift:28` | 10 | **8** from the tile bottom to the Space header top (13 to the header icon) | AX frames | exact (AX) |
| `bottomBarHeight` | `ShellUI/Sidebar/TabRowState.swift:29` | 36 | **50**: the Space dock strip at the bottom of the sidebar; 32 pt buttons with 9 pt above and below | AX frames | exact (AX) frames; strip edges inferred from the dock's scroll area |
| `favoriteCloseButtonSize` | `ShellUI/Sidebar/TabRowState.swift:32` | 16 | not measured (hover only) | - | checklist |
| `favoriteCloseButtonInset` | `ShellUI/Sidebar/TabRowState.swift:33` | 3 | not measured (hover only) | - | checklist |
| `spaceDotSize` | `ShellUI/Sidebar/TabRowState.swift:35` | 6 | **4** (8 x 8 device px). Color sRGB #858686 over #7A7A7A, about white 8 % (window not key) | px | measured (px) |
| `spaceDotSpacing` | `ShellUI/Sidebar/TabRowState.swift:36` | 8 | **17.5** (center pitch 21.5 minus the 4 pt dot). Dock items are 23.5 to 24 pt wide hit frames at a 21.5 pt pitch; a Space with an icon uses the same slot | AX frames for the pitch; px for the dot | exact (AX) pitch |
| `urlBarTopGap` | `ShellUI/Sidebar/TabRowState.swift:39` | 4 | not measurable (sidebar URL bar hidden while the Toolbar is on) | - | checklist |
| `urlBarHeight` | `ShellUI/Sidebar/TabRowState.swift:40` | 30 | not measurable (as above) | - | checklist |
| `urlBarCornerRadius` | `ShellUI/Sidebar/TabRowState.swift:41` | 9 | not measurable (as above) | - | checklist |
| `urlBarTextInset` | `ShellUI/Sidebar/TabRowState.swift:42` | 10 | not measurable (as above) | - | checklist |
| `urlBarFontSize` | `ShellUI/Sidebar/TabRowState.swift:43` | 13 | not measurable (as above). The Toolbar's URL text has a cap height of 7.5 to 8 pt (about 11 to 12 pt type), in a 16 pt text frame | px for the Toolbar text | checklist; Toolbar value inferred |
| split gap | `ShellUI/Split/SplitContainerView.swift:40` | 10 | not measured (no split on screen, RT-37) | - | checklist |
| `commandBarSurface` | `ShellUI/Theme/ShellTokens.swift:46` | P3 #1C1C20 a 0.98 | not measured (command bar closed) | - | checklist |
| `commandBarSelectedRow` | `ShellUI/Theme/ShellTokens.swift:50` | white 0.10 | not measured (command bar closed) | - | checklist |
| `toastSurface` | `ShellUI/Theme/ShellTokens.swift:53` | white 0.96 / P3 #1C1C20 a 0.96 | not measured (no toast) | - | checklist |
| `toolbarSurface` | `ShellUI/Theme/ShellTokens.swift:56` | white 1 / P3 #1C1C20 a 1 | **dark, this theme: the same surface as the content card**, sRGB #878787 (P3 #878787), separated from the page by a 1 pt hairline sRGB #8D8D8D (about white 5 % over the card). The sidebar and window background around the card is #7A7A7A. Light: not measured | px averages | measured (px), one theme, window not key; whether the strip stays this color over a page with its own background is checklist |
| `defaultDuration` | `ShellUI/Toast/ToastPresenter.swift:24` | 4 s | not measured (needs a toast and a recording, RT-28) | - | checklist |
| `height` (Toolbar) | `ShellUI/Toolbar/ContentToolbarView.swift:9` | 40 | **32**, inside the content card (card top to hairline), then the 1 pt hairline | AX frame of the toolbar panel; px for the hairline | exact (AX) |
| `buttonSize` (Toolbar) | `ShellUI/Toolbar/ContentToolbarView.swift:10` | 28 | **32 wide x 24 tall** for Back, Forward, Reload and the trailing buttons (one trailing button is 32 x 28); 5 pt between buttons (37 pt pitch); 4 pt from the card top | AX frames | exact (AX) |
| `iconSize` (Toolbar) | `ShellUI/Toolbar/ContentToolbarView.swift:11` | 14 | glyph boxes: Back and Forward 13 x 10.5, Reload 12 x 14.5, trailing icons 16 x 16 and 14 x 14; consistent with about 14 pt symbols | px bounding boxes | inferred (symbol point size from glyph boxes) |
| `horizontalPadding` (Toolbar) | `ShellUI/Toolbar/ContentToolbarView.swift:12` | 8 | **5** from the card's leading edge to Back and from the last trailing button to the card's trailing edge | AX frames | exact (AX) |
| `urlBarHeight` (Toolbar) | `ShellUI/Toolbar/ContentToolbarView.swift:13` | 28 | **no pill**: the URL is plain text centered in the 32 pt strip (16 pt text frame, no fill, border or radius around it); a 24 x 24 button sits right of the text | AX frames; px scan across the strip (uniform card color) | measured (px) |
| `sidebarMinWidth` | `ShellUI/Window/ShellMetrics.swift:23` | 150 | not measured (needs a drag) | - | checklist |
| `sidebarMaxWidth` | `ShellUI/Window/ShellMetrics.swift:24` | 400 | not measured (needs a drag) | - | checklist |
| `trafficLightOrigin` | `ShellUI/Window/ShellMetrics.swift:30` | (16, 16) | **(12, 16)**: close button frame 16 x 16 at window x 12, y 16. The drawn circle is 14 pt at (13, 17) | AX frame; px for the circle | exact (AX) |
| `sidebarTopBarHeight` | `ShellUI/Window/ShellMetrics.swift:32` | 44 | **36** with the Toolbar on (window top to the Favorites section). Traffic-light centers sit at y 24. Toolbar off (sidebar URL bar shown): not measured | AX frames | exact (AX) Toolbar on; checklist Toolbar off |

Summary: 18 of 39 tokens have an Arc value (13 exact from AX, 3 measured from pixels, 2 inferred), and 21 need
interaction or a different Arc state (checklist below). Two of the 18 (`favoritesTopGap`, `sidebarTopBarHeight`)
are only known for the Toolbar-on layout.

## Related values (not tokens)

Noted while measuring; listed so the follow-up can decide whether they change.

- Sidebar width in this window: 192 (Arkt default 190).
- Traffic-light pitch: 23 pt (close x 12, minimize x 35, zoom x 58). Arkt `trafficLightSpacing` is 20.
- Sidebar toggle button next to the traffic lights: 28 x 28 at x 77, y 9.5; glyph about 16 x 12.5.
- Content card: inset 10 from the top, 10 from the right, leading edge at the sidebar edge (x 192). Arkt has
  `cardInsetTop` 9.
- Favorites: 3 tiles at sidebar width 192 are 53.3 x 47 with an 8 pt outer inset and about 8.2 pt between tiles; the
  Favorites section is 63 tall (8 + 47 + 8). Arkt has `tileHeight` 46 and `gap` 9. Tile fill about sRGB #878787 over
  #7A7A7A (about white 10 %).
- Tab rows: 41 pt pitch, 40 pt cell (matches `rowPitch`). Favicon frame 18 x 18 at x 17 (Arkt `faviconSize` 16 at
  leading 10, so the centers coincide); title text frame at x 43, 19 pt tall.

## Open questions from #77 answered here

- **Sidebar URL bar while the Toolbar is on:** Arc **hides** it. With the Toolbar on, the Favorites section starts
  right under the traffic-light strip (36 pt from the window top) and no URL field exists in the sidebar's
  accessibility tree. Arkt keeps it visible (`[I]`), so `ShellWindowController` should hide it.
- **Toolbar URL bar contrast on the Toolbar surface:** in Arc there is no URL pill; the Toolbar is the top 32 pt of
  the content card, on the card's own surface. The placeholder text measured about sRGB #E1E1E1 on #878787, 2.75:1 in
  this theme with the window not key. Light appearance and a key window were not measured.

## Interaction checklist (maintainer)

Each item needs input to Arc, so it was not done here.

1. Hover a Today tab: close X hit box, glyph size, trailing inset, gap to the title; record the fade with a screen
   recording (tokens `TabRowState.swift:16` to `:20`).
2. Hover a loaded Favorite tile: close X hit box and inset (`:32`, `:33`).
3. Select a tab (and hover another): row fill corner radius and the selected and hovered fill colors (`:9`).
4. Hide the Toolbar (Shift-Cmd-D): sidebar URL bar top gap, height, radius, text inset and font size, the gap from
   the URL bar to Favorites, and the traffic-light strip height (`:27`, `:39` to `:43`, `ShellMetrics.swift:32`).
5. Drag the sidebar edge to its minimum and maximum (`ShellMetrics.swift:23`, `:24`).
6. Open the command bar (Cmd-T) with more results than fit: visible row count, surface and selected row colors
   (`CommandBarGeometry.swift:12`, `ShellTokens.swift:46`, `:50`).
7. Trigger a toast (Cmd-Shift-C): surface color in light and dark, and its on-screen duration from a recording
   (`ShellTokens.swift:53`, `ToastPresenter.swift:24`, RT-28).
8. Make a 2-pane split: gap between panes (`SplitContainerView.swift:40`, RT-37).
9. Repeat the color reads with the window key, in light appearance and on a second Space theme (`toolbarSurface`,
   dots, divider), and over a page with its own background to see whether the Toolbar strip stays the card color.
