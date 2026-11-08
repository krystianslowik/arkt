# Dialog label colors (#711)

`shots/` holds before and after renders of three dialogs, in light and dark:

- the sidebar banner's announcement popover;
- the launch-failure alert;
- a sheet with a subtitle, a list and a checkbox.

Before is `main` before #711; after is the fix. Labels drawn by AppKit came out heavier than `primaryText` and
`secondaryText`; after the fix they land on the tokens.

**These are `cacheDisplay` renders from the test harness, not screen captures.** Each dialog's root view is drawn
offscreen at 2x into a bitmap. The levels match what Core Animation composites for these views, but window-server
color matching and the display profile are not in them. Check the screen itself with Digital Color Meter.

## Rendering

From the repository root:

```zsh
cd app/ArktShell/ShellKit
ARKT_LABEL_SHOTS_DIR=/tmp/label-shots nice -n 20 swift test -j 2 --filter DialogLabelColorTests/testShots
```

This writes `popover-<light|dark>.png`, `launch-failure-<light|dark>.png` and `checkbox-list-<light|dark>.png`. Without
`ARKT_LABEL_SHOTS_DIR` the test is skipped. Rename each file with a `-before` or `-after` suffix as you copy it into
`shots/`. To get the before set, run the same command on `main`. That needs a `testShots` that uses only `main`'s
API, so take the shots test and its helpers from `DialogLabelColorTests` without the assertions.

Then quantize to 256 colors so the files stay small:

```zsh
pngquant --force --ext .png 256 design/dialog-label-color/shots/*.png
```
