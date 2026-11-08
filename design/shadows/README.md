# Shadows on flipped views

The lifts #767 turned to cast down: the theme creator's slider knob, first run's appearance thumb and Space preview,
and the floating sidebar, each on a plain surface.

Shots: `shots/flipped-shadows-after-<light|dark>.png` (2x, 900 x 340 window). `FlippedShadowScreenshotTests`
(ShellKitGUITests) writes them when `ARKT_SHADOW_SHOTS_DIR` names a folder, and skips otherwise:

```zsh
cd app/ArktShell/ShellKit
ARKT_SHADOW_SHOTS_DIR=/tmp/shadow-shots swift test --filter FlippedShadowScreenshotTests
pngquant --force --nofs --ext .png 256 /tmp/shadow-shots/*.png
```

That filter matches the whole class, so it also writes the settings and row shots of the next section.

The test draws the window's layer tree directly (`cacheDisplay` leaves out the floating sidebar's own shadow).

## Settings controls and row lifts (#773)

The Settings switch knob, the selected segment's plate and the selected pane item's plate, the current sidebar row
and the selected Archive row now cast down too. Favorite tiles, the content card and the Little Arkt flight already
did: their layers are not flipped.

Shots: `shots/flipped-shadows-settings-rows-<light|dark>.png` (2x, 560 x 200 window, a flipped container as the
Settings content views and the tables host them). In dark only the off knob draws a lift; the plate and row lifts are
light only.

```zsh
cd app/ArktShell/ShellKit
ARKT_SHADOW_SHOTS_DIR=/tmp/shadow-shots swift test --filter FlippedShadowScreenshotTests/testSettingsAndRowShots
pngquant --force --nofs --ext .png 256 /tmp/shadow-shots/*.png
```

## Archive table selection (#796)

The Archive table drew AppKit's own selection over its selected row, so the row's `tabCurrent` fill and lift never
showed. The table now sets `selectionHighlightStyle = .none` and `ArchiveRowView` draws the selection.

Shots: `shots/archive-selected-row-<light|dark>.png` (2x, the Archive window with its second row selected, focused).
The lift is light only.

```zsh
cd app/ArktShell/ShellKit
ARKT_SHADOW_SHOTS_DIR=/tmp/shadow-shots swift test --filter FlippedShadowScreenshotTests/testArchiveTableShots
pngquant --force --nofs --ext .png 256 /tmp/shadow-shots/*.png
```
