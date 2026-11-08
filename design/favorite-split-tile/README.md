# A Split View as a Favorites tile

Design for #788. A split made on a Favorite stays in the Favorites (maintainer decision, #801) and is drawn as one
tile. #802 made that tile work (X, drag out, menu, labels); this design gives it a look and settles its menu.

- Prototype: [`prototype.html`](prototype.html). No hash: an overview of every direction and state. One state per
  hash: `#<a|b|c>-<resting|hover|selected|loading|menu>[&dark][&shot]`.
- Screens: [`screens/`](screens/), `<direction>-<state>-<light|dark>.png`, at 2x. Each shows the sidebar at its real
  size on the left and the split tile at 2x on the right for a split of 2 panes side by side, 2 stacked, 3 and 4.

**Status: three directions for the maintainer to pick.** Once one is picked, the others move to `directions/` (or
are dropped) and this README becomes the spec of the chosen one.

## Gate

1. **Surface:** a Favorites tile. Everyday chrome: system font, no Hero style, no mustard.
2. **States:** resting, hover (with the X), selected (the split is shown), a pane loading or without a favicon,
   context menu. Longest content: 4 panes, the most a split holds (BH-116). Smallest window: the 52 x 46 pt tile of
   a 3-column grid at the default 190 pt sidebar; no tile is narrower.
3. **Primary action:** click the tile to show the split. Nothing else on the tile competes with it.
4. **Open questions:** which direction; the menu below.

## Fixed by the existing tile

These are main's values and stay as they are in every direction.

| Value | Source |
|---|---|
| Tile 52 x 46 pt at its narrowest, 9 pt gap, 1 to 4 columns | `FavoritesLayout.minimumTileWidth`, `tileHeight`, `gap` |
| Corner radius 10, continuous | `FavoritesLayout.tileCornerRadius` |
| Favicon slot 20 pt, centered | `SidebarMetrics.favoriteFaviconSize` |
| X: 16 pt hit box, inset 3 from the top trailing corner, 10 pt glyph, fades with the hover | `SidebarMetrics.favoriteCloseButtonSize`, `favoriteCloseButtonInset`, `closeButtonGlyphSize` |
| Resting fill `sidebarItemBackground`, hovered `sidebarItemHovered`, selected `tabCurrent` with `rowLiftShadow` | `FavoriteTileView.displayedFill` |
| No favicon: the letter tile (25 % radius, `letterTileFill`, semibold at 0.62 of its size, `primaryText`) | `SidebarGlyphs.letter` |
| Increase Contrast: the 1 pt `increasedContrastEdge` on every filled shape | `IncreasedContrast.setEdge` |

`ShellRadius` (#810) and the type roles (#812) are open pull requests, not on main yet. The Favorites tile keeps its
own `tileCornerRadius`; #810 does not change it.

Loading: the sidebar shows nothing while a page loads (`design/page-loading`, decision 3), and that holds here. A
pane whose favicon has not arrived yet draws the letter tile, as any Favorite without a favicon does, and the favicon
replaces it when it arrives. No spinner on the tile.

## Directions

### A. Side by side

The pane favicons sit next to each other in the favicon slot, in pane order, following the split's orientation.

| Panes | Layout | Favicon |
|---|---|---|
| 2, side by side | one row, 4 pt apart (36 x 16) | 16 pt |
| 2, stacked | one column, 4 pt apart (16 x 36) | 16 pt |
| 3 | 2 over 1, 3 pt apart | 14 pt |
| 4 | 2 x 2, 3 pt apart (31 x 31) | 14 pt |

- Selected: the tile's fill, as any Favorite. Which pane has focus is not shown on the tile; the content shows it.
- Hover: the X covers part of the top trailing favicon at 3 and 4 panes, so a split tile's X gets a round plate in
  the hovered tile's color.
- For: reads as "these sites together" at a glance; every pane is visible; orientation shown for 2 panes; the
  closest to the tile people know.
- Against: 14 pt favicons at 3 and 4 panes; the X covers a pane while hovered.

### B. Stack

The focused pane's favicon at the full 20 pt, the next panes peeking out behind it, bottom trailing.

| Layer | Size | Offset from the tile's top leading corner |
|---|---|---|
| Front: the focused pane while the split is shown, else the first pane | 20 pt | 9, 7 |
| Second | 16 pt | 25, 21 |
| Third (3 and 4 panes) | 14 pt | 32, 28 |

- The front favicon and the second (when a third is behind it) carry a 2 pt cut-out ring in the tile's fill color, so
  they read as separate. A letter tile in the stack sits on that color too; it is translucent on its own.
- Selected: the tile's fill, and the front favicon follows focus: focusing another pane brings its favicon to the
  front (cross-fade 150 ms; Reduce Motion: switch at once).
- For: the main favicon stays at the size of every other Favorite; the tile looks calm in a row of plain Favorites.
- Against: a 4th pane is not drawn (3 and 4 panes look the same); orientation is not shown; the second favicon is
  only partly visible, so the second site is harder to recognize; the stack can read as "a group" or "a folder"
  rather than a split.

### C. Divided tile

The tile's fill itself is split into one cell per pane, 2 pt apart, laid out like the split. Each cell holds its pane's
favicon. Outer corners keep the tile's radius 10; inner corners are 4.

| Panes | Cells | Cell size | Favicon |
|---|---|---|---|
| 2, side by side | 2 columns | 25 x 46 | 16 pt |
| 2, stacked | 2 rows | 52 x 22 | 14 pt |
| 3 | 3 columns | 16 x 46 | 12 pt |
| 4 | 2 x 2 (orientation not shown) | 25 x 22 | 14 pt |

- Resting and hover: every cell takes the tile's fill (`sidebarItemBackground`, `sidebarItemHovered`).
- Selected: the focused pane's cell takes `tabCurrent` with the lift shadow, the other cells `tabContentVisible` (the
  existing token for a page that is visible but not focused). Focus moving between panes moves the bright cell (fill
  cross-fade 150 ms; Reduce Motion: at once).
- Hover: the X sits on a round plate over the top trailing cell.
- For: the only direction that says "split" and shows which pane has focus; matches the content's layout.
- Against: the most new drawing (cells, per-cell fills and Increase Contrast edges); 12 pt favicons at 3 panes; 4
  panes drop the orientation; the most visual weight in a row of plain Favorites.

## Context menu

Decided for every direction (the menu does not depend on the look). Proposed labels, in order:

| Item | Key | Enabled | Behavior |
|---|---|---|---|
| Separate All Tabs | | always | Each pane becomes its own Favorite, in pane order, at the split's place. Their pages stay open. BH-121, shipped title |
| Convert to Vertical Split View | | always | Retitled Convert to Horizontal Split View for a vertical split. BH-120, shipped title |
| (separator) | | | |
| Copy Links | | always | Every pane's URL. Option: Copy Links as Markdown. Shipped in #802 |
| (separator) | | | |
| Remove from Favorites | | always | The split moves to the top of Today, whole. Shipped in #802 |
| Close and Keep Favorite | Cmd-W | always | Closes every pane's page; the tile stays. Shipped in #802 |

Left out, and why:

- **Remove Tab from Split View** (one pane). A tile has no pane rows to aim it at, so it would need a submenu of pane
  titles: more menu for a case already covered. For 2 panes, the most common split, Separate All Tabs does the same
  thing. For 3 and 4, show the split, focus the pane and press Ctrl-Shift-- (Close this Split Pane, BH-122) or use
  Separate Page from Split View; the pane lands as a Favorite right after the split, with its page.
- **Duplicate Split View.** A Favorite's tab menu has no Duplicate; a duplicate would add a second Favorite.
- **Rename..., Change Icon, Edit Pinned URL..., Back to Pinned URL.** They edit one tab (the Edit Pin popover); a
  split has no stored title (BH-115 rename is deferred).
- **Pin Tab, Move To.** Not on a Favorite's tab menu either; dragging the tile below the Space title moves it out
  (#802).
- **Share Split View.** Not built (#362).

## Accessibility

- The tile stays one button. Label: the pane titles joined with " | ", as today (#802). Value: "current" while a
  pane is shown, and loaded or unloaded, as other tiles.
- The X's label stays Close and Keep Favorite. Proposed: the tile's custom actions add Separate All Tabs, so
  VoiceOver reaches it without the menu.
- Favicons are not elements. In C, the cells are not elements either; focus is announced by the content.

## Motion

The tile adds no motion of its own beyond what any Favorite has (hover fill and X fade, selection fill). B and C
cross-fade the focused pane's favicon or cell in 150 ms, ease-out; with Reduce Motion they switch at once.

## Verify

```zsh
find design/favorite-split-tile/screens -name '*.png' -size +400k   # prints nothing
ls design/favorite-split-tile/screens | grep -c light               # 15
ls design/favorite-split-tile/screens | grep -c dark                # 15
```
