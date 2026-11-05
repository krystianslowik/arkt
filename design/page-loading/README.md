# Page loading design

The loading indicator on the content card (#649): a 2 pt edge line inside the card's top edge. Prototype:
[`prototype.html`](prototype.html), states by hash `#<loading|split|small|theme2|idle>[&dark][&rm][&shot]`. Screens:
`screens/page-loading-<state>-<light|dark>.png` (2x, frozen on one frame of the loop; `loading-rm` is the Reduce
Motion variant).

Everyday chrome. No mustard: the indicator sits on the card's edge, and mustard is never a stroke. Picked over
B (Space glow) and C (orbit on the hairline).

## Shape

| | Value |
|---|---|
| Line | 2 pt high, radius 1 pt, 34 % of the card (or pane) width |
| Position | inside the card's top edge, clipped by the card's 10 pt corner radius |
| Color | `ShellTokens.loadingEdge` (new): `#202321` at 62 % light, `#FAF9F5` at 72 % dark |
| Increase Contrast | the same token at 85 % |
| Loop | translateX from -100 % to +300 % of the line's own width, 1.4 s, ease in-out (`cubic-bezier(0.45, 0, 0.55, 1)`), repeating |

The color is a fixed token pair; it does not follow the Space theme.

## States

| State | What it shows |
|---|---|
| `loading` | the selected tab of the card is loading; the line sweeps along the top edge |
| `split` | Split View: the left pane loads (its own line, 34 % of that pane), the right pane has focus and no line |
| `small` | smallest window (720 x 520): same sizes |
| `theme2` | a green Space theme: the line keeps the neutral ink color |
| `loading&rm` | Reduce Motion: a still full-width line that breathes in opacity |
| `idle` | page loaded: nothing on the card |

## Behavior

- Shown for the selected tab of each card while `isLoading` is true. Each Split View pane has its own line.
- No flash: show only after 150 ms of loading; once shown, stay at least 400 ms; fade out over 200 ms when the load
  finishes.
- A navigation that starts while the line is fading restarts the loop without a jump (opacity animates from its
  current value).
- Background tabs show nothing on the card, and the sidebar row is unchanged (no spinner).

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Appear | opacity 0 to 1, 0.2 s ease-out | same |
| Loop | translateX sweep, 1.4 s, ease in-out | full-width line, opacity 0.35 to 1 and back over 1.6 s, ease in-out |
| Finish | opacity to 0, 0.2 s | same |

Core Animation only: one transformed layer under the card's corner mask. Never per-frame layout or a redraw of the
card.

## VoiceOver

- The card announces "Loading" once when the line appears, not on every loop. "Loaded" is not announced.
- The line itself is not an element; the card's value reads "Loading" while it shows.

## Answered questions

1. Direction: A, edge line.
2. Thresholds: accepted as drawn, 150 ms delay before showing and 400 ms minimum once shown.
3. Background tab loading in the sidebar row: nothing is shown. This is the sheet's default; the maintainer did not
   ask for a row indicator.
