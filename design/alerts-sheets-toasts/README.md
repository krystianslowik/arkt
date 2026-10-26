# Alerts, sheets and toasts design

The shared dialog and toast system (#306, built in #308), restyled to the brand direction set in #304. The spec is
[`docs/design/alerts-sheets-toasts.md`](../../docs/design/alerts-sheets-toasts.md); the prototype is
[`prototype.html`](prototype.html) (open it in a browser; states by hash, `#<state>[&dark][&rm][&rt]`, Replay plays
the entrance again).

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network. Every state in the spec is a hash |
| `screens/<state>-<light\|dark>.png` | 24 screenshots at 2x: delete-space, delete-space-empty, launch-failure, launch-newer, toast-undo, toast-restored, toast-error, toast-recovery, ext-install, ext-remove, permission, infobar |

## Before and after

The first pass (#309) drew the dialogs as stock system sheets. This pass applies the rules the Archive window set
(`design/archive-search/archive-search.md`, section 2) and its Clear Archive sheet. The before screenshots are the
ones in `design/alerts-sheets-toasts/screens/` at commit 41f59f6. Product decisions are unchanged: Delete Space uses
the Arkt sheet, toasts follow the Space theme, the undo toast appears only when several tabs are archived, the launch
alert has Show Data Folder, and the app icon carries no caution badge.

| Element | Before | After | Why |
|---|---|---|---|
| Dialog buttons | 28 pt rounded rectangles, radius 7, 0.5 pt edge | pills: 28 pt radius 14, 13 semibold, no edge | the brand's pill, as the Archive's sheet |
| Cancel and other answers | grey bordered buttons | neutral pills (`sidebarItemHovered`) | quiet secondaries, no stock bezel |
| Destructive answers (Delete Space, Remove) | grey bordered button with red text | neutral pill with a red title, no Return key | red, never a grey bordered button; same as Clear Archive |
| Launch failure, Show Data Folder | a third grey bordered button at the leading edge | a quiet text link at the leading edge; Quit neutral, Try Again the one mustard pill | one primary, the rest quiet |
| Extension install, Open in Web Store | underlined link | quiet text link, no underline | links in chrome are quiet, not web links |
| Extension install, permission list | hairline-ruled block with indented bullets | the Archive's recessed field, dot bullets | lists are fields, not ruled blocks |
| Permission prompt | three bordered buttons | three full-width neutral pills, still no primary | no nudge, now in the brand's shape |
| Sheet and alert corners | 12 | 14, as the Clear Archive sheet | one sheet shape |
| Toast surface | plain white or near-black | `toastSurface` tinted with the Space theme's first stop (the Work Space shows faintly blue) | toasts follow the Space theme |
| Toast action | bare text after a 1 pt hairline; Undo carried a Cmd-Z hint | a small neutral pill, no hairline, no key hint | one quiet action per toast |
| Infobar | 1 pt hairline below, small bordered button, underlined link | no hairline (the surface is the edge), small neutral pill, quiet link | no stock chrome |
| Focus ring | 2 pt graphite (mustard in dark) | the system focus ring | system focus everywhere; mustard is never a stroke |
| Import failure toast | "Couldn't import from Arc." | "Couldn't import browser data." | no user-facing "Arc" |
| Browser context in the screenshots | neutral grey theme | the Work Space's blue theme | shows that toasts and Delete Space take the Space's own color |

The engine values to copy (button radius and edge, list field, panel radius) are in the spec, section 6.
