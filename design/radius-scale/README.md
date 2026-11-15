# Corner radius scale (#620)

`ShellRadius` names the chrome's corner radii by role (row, control, field, tile, card, popover, sheet, pill). The
change routed every radius through it with the values unchanged, so nothing on screen moved.

Shots: `shots/settings-general-<before|after>-<light|dark>.png` (2x, the Settings window on its General pane).
"Before" is `main` at the branch point, "after" is the branch. Each pair is pixel-identical.

`RadiusScaleScreenshotTests` (ShellKitGUITests) renders the Settings window's General, Appearance and Shortcuts panes
and the Archive window, in light and dark. It writes `radius-<surface>-<light|dark>.png` when
`ARKT_RADIUS_SHOTS_DIR` names a folder, and skips otherwise:

```zsh
cd app/ArktShell/ShellKit
ARKT_RADIUS_SHOTS_DIR=/tmp/radius-shots swift test --filter RadiusScaleScreenshotTests
pngquant --force --nofs --ext .png 256 /tmp/radius-shots/*.png
```

To check that a radius change moves nothing, render the same tests on both sides of the change and compare the
images pixel by pixel. With `ShellRadius.row` set to 8, the General pane differs from the 9 pt render in 640 pixels,
so a row radius change shows in these shots.
