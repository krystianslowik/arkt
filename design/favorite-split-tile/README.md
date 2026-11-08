# A Split View as a Favorites tile

Design for #788. A split made on a Favorite stays in the Favorites (maintainer decision, #801) and is drawn as one
tile. #802 made that tile work (X, drag out, menu, labels); this design gives it its look and settles its menu.

**Picked direction: B, the stack** (maintainer, 2026-11-08). The menu below was accepted as proposed; Rename... joins
it after #847.

- Prototype: [`prototype.html`](prototype.html). No hash: an overview of every state. One state per hash:
  `#<resting|hover|selected|loading|menu|menu-rename|rename-popover>[&dark][&shot]`.
- Screens: [`screens/`](screens/), `<state>-<light|dark>.png`, at 2x. Each shows the sidebar at its real size on the
  left and the split tile at 2x on the right for a split of 2 panes side by side, 2 stacked, 3 and 4.
- The directions compared: [Considered](#considered), with their prototype and screens in
  [`directions/`](directions/).

## Gate

1. **Surface:** a Favorites tile. Everyday chrome: system font, no Hero style, no mustard.
2. **States:** resting, hover (with the X), selected (the split is shown), a pane loading or without a favicon,
   context menu. Longest content: 4 panes, the most a split holds (BH-116). Smallest window: the 52 x 46 pt tile of
   a 3-column grid at the default 190 pt sidebar; no tile is narrower.
3. **Primary action:** click the tile to show the split. Nothing else on the tile competes with it.

## Tile

The tile is a Favorite tile like any other; only its content differs. These values are main's and do not change:

| Value | Source |
|---|---|
| Tile 52 x 46 pt at its narrowest, 9 pt gap, 1 to 4 columns | `FavoritesLayout.minimumTileWidth`, `tileHeight`, `gap` |
| Corner radius 10, continuous | `FavoritesLayout.tileCornerRadius` |
| Resting fill `sidebarItemBackground`, hovered `sidebarItemHovered`, selected `tabCurrent` with `rowLiftShadow` | `FavoriteTileView.displayedFill` |
| X: 16 pt hit box, inset 3 from the top trailing corner, 10 pt glyph, fades with the hover (120 ms) | `SidebarMetrics.favoriteCloseButtonSize`, `favoriteCloseButtonInset`, `closeButtonGlyphSize`, `closeButtonFadeDuration` |
| No favicon: the letter tile (25 % radius, `letterTileFill`, semibold at 0.62 of its size, `primaryText`) | `SidebarGlyphs.letter` |
| Increase Contrast: the 1 pt `increasedContrastEdge` on the tile | `IncreasedContrast.setEdge` |

Increase Contrast and Space themes add nothing new for this tile, so they have no screens here: the tile's fill and
1 pt edge are `design/increase-contrast` ("Favorites tiles" row), and themed fills are `design/theme-creator`. The
one themed detail is the cut-out ring, which the build checks on a theme (acceptance criteria).

`ShellRadius` (#810) and the type roles (#812) are open pull requests, not on main yet. The Favorites tile keeps its
own `tileCornerRadius`; #810 does not change it.

### The stack

Up to three pane favicons, layered. Offsets are from the top leading corner of a 52 x 46 pt box; on a wider tile that
box is centered in the tile, as a plain Favorite's favicon is.

| Layer | Pane | Size | Offset (x, y) |
|---|---|---|---|
| Front | the focused pane while the split is shown, else the first pane | 20 pt | 9, 7 |
| Second | the next pane in order after the front one | 16 pt | 25, 21 |
| Third | the one after that; 3 and 4 panes only | 14 pt | 32, 28 |

- A 4th pane is not drawn. The tooltip and VoiceOver label name every pane.
- **Cut-out ring:** the front favicon, and the second when a third is behind it, carry a 2 pt ring so the layers read
  as separate. Draw it as a cut-out (clear the ring's shape from the layers below), not as a painted color, so it
  matches the tile's fill exactly in every state and on every theme. The prototype paints an approximate solid color.
- **Letter tiles in the stack:** the letter tile is translucent, so in the stack the pane behind it is cleared under
  its shape too; nothing shows through.
- **Orientation** is not shown. Convert to Vertical / Horizontal Split View does not change the tile.

### States

| State | What changes |
|---|---|
| Resting | `sidebarItemBackground`; the first pane in front |
| Hover | `sidebarItemHovered`; the X fades in on a round 16 pt plate in the hovered fill, which covers any favicon under it |
| Selected (the split is shown) | `tabCurrent` with `rowLiftShadow`; the focused pane's favicon is in front |
| Focus moves to another pane | its favicon comes to the front, the others follow in pane order: a cross-fade of the layers (`FavoritesLayout.focusCrossFadeDuration`, below) |
| A pane loading, or with no favicon | that layer is the letter tile (the host's first letter) until a favicon arrives. No spinner: the sidebar shows nothing while a page loads (`design/page-loading`, decision 3) |
| No pane loaded in this window | as resting; no X (#802) |

### Motion

The hover fill, the X fade and the selection fill are the tile's existing motion. The only new motion is the front
layer changing when focus moves between panes: a cross-fade, ease-out, with Reduce Motion the layers switch at once.

The shell has no shared motion token; durations are named per surface (`SidebarMetrics.closeButtonFadeDuration`
0.12, `SettingsMotion.crossFade` 0.15, `StatusPillView.crossFadeDuration` 0.18). The build adds
`FavoritesLayout.focusCrossFadeDuration = 0.15`, the same value as `SettingsMotion.crossFade`.

## Context menu

Accepted by the maintainer. In order:

| Item | Key | Enabled | Behavior |
|---|---|---|---|
| Rename... | | always; **after #847** | Opens the Edit Pin popover (`design/edit-pin`), titled "Edit Favorite", with only its Name field (a split has no pinned URL), anchored to the tile, Name focused with the text selected. Save stores the split's name (#847); an empty name goes back to the pane titles. The name becomes the tile's tooltip and VoiceOver label |
| (separator, after #847) | | | |
| Separate All Tabs | | always | Each pane becomes its own Favorite, in pane order, at the split's place. Their pages stay open. BH-121, shipped title |
| Convert to Vertical Split View | | always | Retitled Convert to Horizontal Split View for a vertical split. BH-120, shipped title |
| (separator) | | | |
| Copy Links | | always | Every pane's URL. Option: Copy Links as Markdown. Shipped in #802 |
| (separator) | | | |
| Remove from Favorites | | always | The split moves to the top of Today, whole. Shipped in #802 |
| Close and Keep Favorite | Cmd-W | always | Closes every pane's page; the tile stays. Shipped in #802 |

Until #847 lands, the menu starts at Separate All Tabs (screens `menu-*`); Rename... is not shown, not even disabled.
With #847: screens `menu-rename-*`.

### Rename popover (after #847)

`design/edit-pin`'s popover, unchanged in size, type, colors and behavior (320 pt, padding 16, radius 12, the arrow on
its top edge centered on the tile, Esc and a click outside cancel), with three differences, shown in
`screens/rename-popover-<light|dark>.png`:

- Title "Edit Favorite" (as for a Favorite tab).
- Only the Name field: no Pinned URL field and no Use Current Page link.
- Name is prefilled with what the tile's tooltip shows (the split's name, else the pane titles joined with " | "),
  focused, with the text selected. Cancel and **Save** (the one mustard pill, Return). An empty name on Save clears
  the split's name, so the tooltip and label go back to the pane titles.

Left out, and why:

- **Remove Tab from Split View** (one pane). A tile has no pane rows to aim it at, so it would need a submenu of pane
  titles: more menu for a case already covered. For 2 panes, the most common split, Separate All Tabs does the same
  thing. For 3 and 4, show the split, focus the pane and press Ctrl-Shift-- (Close this Split Pane, BH-122) or use
  Separate Page from Split View; the pane lands as a Favorite right after the split, with its page.
- **Duplicate Split View.** A Favorite's tab menu has no Duplicate; a duplicate would add a second Favorite.
- **Change Icon, Edit Pinned URL..., Back to Pinned URL.** They act on one tab's pin; a split has no pinned URL.
- **Pin Tab, Move To.** Not on a Favorite's tab menu either; dragging the tile below the Space title moves it out
  (#802).
- **Share Split View.** Not built (#362).

## Accessibility

- The tile stays one button. Label: the split's name after #847, else the pane titles joined with " | ", as today
  (#802). Value: "current" while a pane is shown, and loaded or unloaded, as other tiles.
- The X's label stays Close and Keep Favorite. The tile's custom actions add Separate All Tabs, so VoiceOver reaches
  it without the menu.
- The favicons are not elements; the focused pane is announced by the content.

## Build acceptance criteria

- [ ] A split tile draws the stack: front 20 pt, second 16 pt, third 14 pt at the offsets above; 4 panes draw 3 layers
- [ ] The tile is selected (`tabCurrent`), and its accessibility value is "current", while any of its panes is
      current. Main resolves a split tile's state through its panes since #802 (`FavoritesGridView.state(for:)`);
      a test pins it for a split tile in the Favorites
- [ ] The front layer is the focused pane while the split is shown, else the first pane; a focus change cross-fades in
      `FavoritesLayout.focusCrossFadeDuration` (0.15 s), and switches at once with Reduce Motion
- [ ] The cut-out ring matches the tile's fill resting, hovered and selected, light and dark, on a theme
- [ ] A pane without a favicon draws the letter tile in its layer; nothing behind shows through
- [ ] The X sits on its plate while hovered; a tile with no loaded pane has no X
- [ ] The menu is the table above; Rename... only once #847 has landed
- [ ] Separate All Tabs on a Favorite split turns each pane into its own Favorite, in pane order, at the split's place;
      the pages stay open
- [ ] Convert to Vertical / Horizontal Split View works on a Favorite split and does not change the tile
- [ ] After #847, Rename... opens the Edit Pin popover titled "Edit Favorite" with only the Name field; an empty name
      goes back to the pane titles; the name becomes the tile's tooltip and accessibility label
- [ ] The tile's VoiceOver custom action is Separate All Tabs (next to the X's Close and Keep Favorite)
- [ ] Increase Contrast draws the tile's edge
- [ ] Screenshot tests for each state in this README, light and dark

## Considered

Kept in [`directions/`](directions/) because they explain the pick: prototype `directions/prototype.html` (hash
`#<a|b|c>-<state>`), screens `directions/screens/<a|c>-<state>-<light|dark>.png`.

- **A. Side by side.** The pane favicons next to each other in the slot, following the orientation (16 pt for 2 panes,
  2 x 2 at 14 pt for 3 and 4). Every pane visible, but small favicons at 3 and 4 panes, and the X covers a pane.
- **C. Divided tile.** The tile's fill split into one cell per pane, laid out like the split, the focused pane's cell
  brighter. The only one that showed focus, but the most new drawing and visual weight in a row of plain Favorites,
  and 12 pt favicons at 3 panes.

B keeps the front favicon at the size of every other Favorite, and the tile calm among them.

## Verify

```zsh
find design/favorite-split-tile -name '*.png' -size +400k    # prints nothing
ls design/favorite-split-tile/screens | grep -c light        # 7
ls design/favorite-split-tile/screens | grep -c dark         # 7
```
