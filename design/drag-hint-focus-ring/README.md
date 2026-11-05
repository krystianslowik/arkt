# Drag hint and focus ring

Two token decisions on one sheet: the drag-hint color (#641) and the chrome focus ring (#642). Prototype:
[`prototype.html`](prototype.html), `#hint` and `#focus`, with `[&dark][&shot]`. Screens:
`screens/drag-hint-focus-ring-<hint|focus>-<light|dark>.png` (2x). Each value is drawn on three sample Space themes:
Blue and Sand (dark text) and Plum (light text), because the acceptance asks for 3:1 on every shipped theme.

Both follow the tone `ThemeContrast` already picks for sidebar text, so they read on every theme in both appearances.
Contrast stays automatic and is never shown to users.

## Drag hint (#641): ink edge and fill

Drawn on the sidebar drop slot, the Favorites drop target and the Split View drop zone. Picked over 1 (system accent)
and 3 (ink fill only).

| Token | Value |
|---|---|
| `ShellTokens.dragHint` (fill) | the Space's text tone at 12 % |
| `ShellTokens.dragHintEdge` | the Space's text tone at 45 %, 1 pt, inside the target's own corner radius |

- Sidebar drop slot: 30 pt high, radius 9, the row width.
- Favorites drop target: the tile's own shape (radius 10), fill and edge drawn over it.
- Split View drop zone: the zone sits on the page card, so it uses the card tone instead of the Space tone: graphite
  (`#202321`) in light, porcelain (`#FAF9F5`) in dark, at the same 12 % and 45 %.
- The alphas are ours. `controlAccentColor` is no longer used for drag hints.

## Focus ring (#642): ink ring

Drawn on a sidebar row, a Favorite tile, the split close button and Settings controls. Picked over 1 (system focus
color) and 2 (`BrandTokens.focusRing` as it is today).

| Where | Value |
|---|---|
| Ring shape | 3 pt, outside the control, following its corner radius |
| Over a Space theme (sidebar chrome) | the Space's text tone at 85 %, so the ring has the same contrast as the sidebar's text |
| On brand surfaces (Settings: porcelain or graphite) | `BrandTokens.focusRing`: graphite in light, porcelain in dark, at 85 % |
- `BrandTokens.focusRing`'s dark value changes from mustard to porcelain. No focus ring is ever mustard: mustard is a
  fill, never a stroke.

## States

| State | What it shows |
|---|---|
| `hint` | drop slot, Favorites target and Split View zone on the Blue, Sand and Plum Spaces |
| `focus` | focus ring on a row, a tile and the split close button on each Space, and on a Settings switch and button |

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Drag hint appears or moves to another target | opacity 0 to 1, 0.12 s ease-out | same |
| Focus ring | appears at once with keyboard focus, as the system ring does | same |

## VoiceOver

No new elements. Drop targets keep their existing drag-and-drop announcements; the focus ring follows keyboard focus
and does not change labels.

## Answered questions

1. Drag hint: option 2, ink edge and fill (Space text tone, 12 % fill, 45 % edge); the Split View drop zone uses the
   card tone.
2. Focus ring: option 3, ink ring at 85 %, 3 pt.
3. Retire the mustard dark value of `BrandTokens.focusRing`: yes, dark becomes porcelain.
