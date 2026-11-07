# Link status pill design

The pill that shows the address of the link under the pointer (#114, BH-167, GS-021). It sits at a bottom corner of
the page card, moves away from the pointer, shows the host in emphasis and truncates the middle of long addresses.
Three directions are drawn for the maintainer to pick from; none is built yet. The prototype is
[`prototype.html`](prototype.html) (open it in a browser; the links are live, so hover them and move the pointer toward
the pill). States by hash, `#<a|b|c>-<long|short|host|avoid>[&dark][&rm][&shot]`.

Everyday chrome: the system font, the shell's tokens, no mustard anywhere (a status is not an action).

## Directions

| | A. Floating capsule | B. Corner tab | C. Two-line card |
|---|---|---|---|
| Idea | the quiet default | part of the card's edge, not an overlay | the whole address, on two lines |
| Placement | 12 in from the card's bottom and leading edge | flush with the card's bottom and leading edge | 12 in from the bottom and leading edge |
| Size (pt) | 26 high, radius 13, padding 12, max 480 wide | 24 high, only the inner top corner rounded (radius 10), padding 10 / 11, max 560 | auto height (host 17 + path 15 + padding 9), radius 12, padding 13, max 372 wide |
| Type | 12; host 600 `primaryText`, rest 400 `secondaryText` | 11.5, same weights | host 13 / 600, path 11.5 / 400 on its own line |
| Surface | `surfaceBrand`, `toastShadow` | `surfaceBrand`, 0.5 pt edge, no shadow (the card edge clips it) | `toastSurface` in the Space theme (as toasts), `toastShadow` |
| Long address | host, then the path middle-truncated on one line | same, wider | host on line 1 (never truncated unless alone too long), path middle-truncated on line 2 |
| Best for | familiarity, small footprint | calm, nothing floats over the page | long, tracking-heavy addresses |
| Cost | covers a little page | squarer, less friendly | tallest, themed surface changes with the Space |

## Behavior

- **What it shows**: the link's destination. The scheme is hidden for https and shown for others ("http://"), the host is
  emphasized (600, `primaryText`), the rest (path, query, fragment) is secondary. No title, no icon, no lock.
- **Delay**: 0.4 s of the pointer resting on a link before it appears. Leaving a link cancels the timer. Nothing shows
  while a mouse button is down, a drag is in progress, or the page is scrolling.
- **Link to link**: while it is visible, moving onto another link swaps the text at once, with no delay and no
  animation. Leaving every link hides it after 0.1 s (so a gap between two close links does not blink it).
- **Keyboard focus**: Tabbing to a link shows it with no delay and keeps it until focus leaves.
- **Avoiding the pointer**: when the pointer comes within 28 pt of the pill, the pill crosses to the other bottom
  corner (leading to trailing, and back). It stays there until the pointer comes near it again. It never covers the
  pointer and never intercepts it (clicks and hover pass through).
- **Truncation (middle)**: the host is never cut while it fits. The path, query and fragment are shortened in the middle
  ("/notices/2026/winter-t...=quay-office#section-4") so the start of the path and the end of the address both stay.
  If the host alone is wider than the pill's maximum, its middle is shortened and the rest is dropped.
- **Full address**: not shown here. Cmd-Option-click Copy Link and the context menu already give it; the pill is a
  glance, not a reader.
- **Split panes and the smallest window**: the pill belongs to the card (or pane) under the pointer. Its maximum width is
  the smaller of its own limit and 62 % of the card, so it never reaches the other corner's area.
- **Worst case drawn**: a 170-character address with tracking parameters, a 90-character host (`host` state), an
  http address, a three-character path.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Appear | opacity 0 to 1 and translateY 4 to 0, 0.14 s, ease-out `cubic-bezier(0.23, 1, 0.32, 1)` | opacity only |
| Disappear | opacity to 0 and translateY back to 4, 0.09 s (exit faster than entry) | opacity only |
| Link to link | none | none |
| Cross to the other corner | translateX over the distance, 0.20 s on `firmFast` `cubic-bezier(0.2, 1, 0.4, 1)` | cross-fade: out 0.09 s, move, in 0.09 s |

Frequent, so it is small and short; transform and opacity only, laid out once. Every motion can be interrupted: a new
link or a new corner retargets from the current position.

## VoiceOver and accessibility

- The pill is hidden from VoiceOver (it duplicates what VoiceOver reads for the link: "link, <address>").
- It never takes focus and never intercepts pointer events.
- Text is `primaryText` and `secondaryText` on an opaque surface in light and dark; no contrast numbers are shown to users.
- Increase Contrast adds a 1 pt `separatorIncreasedContrast` edge to A and C.

## Light and dark

Light: porcelain pill (C: the Space's blue-tinted toast surface). Dark: graphite `#202321` (C: the dark toast surface).
The page, pointer and Space are synthetic.

## Open questions for the maintainer

1. Which direction (A, B or C).
2. Delay: 0.4 s here; is that the product value?
3. Should non-https addresses carry the scheme (drawn) or a visible "Not secure" word as well?
4. Does the pill also show for links in the Archive or the sidebar, or only for page links?

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network, live hover logic over a synthetic page |
| `screens/status-<a\|b\|c>-<long\|avoid>-<light\|dark>.png` | 12 screenshots at 2x (1080 x 720 window), synthetic addresses only |
