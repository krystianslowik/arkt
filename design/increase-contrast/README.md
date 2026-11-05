# Increase Contrast for the main window

Values for the main window's chrome when the system Increase Contrast setting is on (#640): edges only, plus a 2 pt
ink ring for the focused Split View pane. Prototype: [`prototype.html`](prototype.html), `#sheet` (setting off and on
side by side), `#off-window` and `#on-window`, with `[&dark][&shot]`. Screens:
`screens/increase-contrast-<sheet|off-window|on-window>-<light|dark>.png` (2x).

Contrast stays automatic and is never shown to users. Picked over B (stronger fills) and C (edges and fills).

## Token

One token: `ShellTokens.increasedContrastEdge`, black 20 % in light and white 20 % in dark. It is the value Settings,
the Archive and toasts already use under Increase Contrast; they point at this token instead of their own copies.

## Values

| Component | Setting off | Increase Contrast on |
|---|---|---|
| Sidebar row, current | `tabCurrent`, no edge | same fill + 1 pt `increasedContrastEdge` |
| Sidebar row, hover | `sidebarItemHovered` 10 % | same fill + 1 pt edge |
| Favorites tiles | `sidebarItemBackground` 5 % | same fill + 1 pt edge |
| URL bar | 5 % fill | same fill + 1 pt edge |
| Command bar selection | 7 % | same fill + 1 pt edge |
| Tab switcher selection | `tabCurrent` | same fill + 1 pt edge |
| Peek card, find bar | `overlayEdge` 12 % (dark 20 %) | 1 pt `increasedContrastEdge` (20 %) |
| Split pane focus | 2.5 pt `sidebarItemHovered` | 2 pt ink ring: `#202321` at 50 % light, `#FAF9F5` at 60 % dark |
| Secondary text, glyphs | unchanged | unchanged |

Fills never change; the theme's look stays intact. The pane focus ring is the one exception to "edges only", because
a 1 pt edge at 20 % is too weak to tell which pane has focus.

## States

| State | What it shows |
|---|---|
| `sheet` | every component, setting off next to setting on |
| `off-window` | the main window with Split View, a find bar and hovered and current rows, setting off |
| `on-window` | the same window with Increase Contrast on |

## Behavior

- Reacts to `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` without a relaunch.
- Edges are drawn as a layer border, never as layout: no row, tile or pill changes size when the setting changes.

## Motion

None. The edge appears and disappears with the setting, without animation, in both normal and Reduce Motion.

## VoiceOver

No change: the edges are visual only and add no elements or labels.

## Answered questions

1. Option: A, edges only, with B's 2 pt ink ring for Split View pane focus.
2. Token: one token, `ShellTokens.increasedContrastEdge`; Settings and the Archive point at it.
