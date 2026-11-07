# Chrome type

The chrome's type roles are `ShellType` (`app/ArktShell/ShellKit/Sources/ShellUI/Theme/ShellType.swift`, #621). The
values are the ones the surfaces used before the roles existed, so the roles change nothing on screen.

## Toolbar URL (#623)

The Toolbar URL text has its own token, `ShellType.toolbarURL`, 13 pt medium. The sidebar URL bar keeps
`SidebarMetrics.urlBarFontSize`. The reference Toolbar text reads about 11 to 12 pt from its cap height
(`docs/plans/2026-10-23-arc-measurements.md`), so 12 is the candidate; the token stays at 13 until #77 checklist items
4 and 9 confirm it.

Shots: `shots/toolbar-url-<light|dark>.png` (2x, a 640 x 33 Toolbar strip with a long URL).
`ToolbarTypeScreenshotTests` (ShellKitGUITests) writes them when `ARKT_TYPE_SHOTS_DIR` names a folder, and skips
otherwise:

```zsh
cd app/ArktShell/ShellKit
ARKT_TYPE_SHOTS_DIR=/tmp/type-shots swift test --filter ToolbarTypeScreenshotTests
pngquant --force --nofs --ext .png 256 /tmp/type-shots/*.png
```
