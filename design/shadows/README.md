# Shadows on flipped views

The lifts #767 turned to cast down: the theme creator's slider knob, first run's appearance thumb and Space preview,
and the floating sidebar, each on a plain surface.

Shots: `shots/flipped-shadows-after-<light|dark>.png` (2x, 900 x 340 window). `FlippedShadowScreenshotTests`
(ShellKitGUITests) writes them when `ARKT_SHADOW_SHOTS_DIR` names a folder, and skips otherwise:

```zsh
cd app/ArktShell/ShellKit
ARKT_SHADOW_SHOTS_DIR=/tmp/shadow-shots swift test --filter FlippedShadowScreenshotTests
pngquant --force --nofs --ext .png 32 /tmp/shadow-shots/*.png
```

The test draws the window's layer tree directly (`cacheDisplay` leaves out the floating sidebar's own shadow).
Quantizing to 32 colors bands the soft blur of the Space preview's drop; the unquantized output is smooth.
