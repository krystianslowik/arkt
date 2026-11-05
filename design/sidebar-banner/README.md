# Sidebar banner design

One notice at a time above the sidebar's bottom bar: "update ready" with Restart, or a short announcement (#648). The
picked direction is B: one row, 34 pt. Prototype: [`prototype.html`](prototype.html), states by hash
`#<update|announce|small>[&dark][&rm][&shot]`. Screens: `screens/sidebar-banner-<state>-<light|dark>.png` (2x,
1080 x 720 window).

Everyday chrome. The banner never covers rows: the row list shrinks and fades over its last 28 pt instead. It never
takes focus. Update notices carry the one mustard pill (Restart); announcements never use mustard.

Not picked: A (a card) and C (the bottom bar carries the notice).

## The row

- **Shape**: 34 pt tall, radius 9, `fill` background, the width of a tab row, 6 pt above the bottom bar. Padding 9 pt
  leading, 5 pt trailing; gap 8.
- **Update**: 16 pt update glyph, "Update" (13 semibold), and a small **Restart** pill (22 pt, 12 pt text, primary).
- **Announcement**: 16 pt spark glyph, the title on one line (truncates), a trailing chevron. Clicking the row opens a
  280 pt popover beside it: the full title (14 semibold), the body (12.5 pt secondary), one neutral action and a quiet
  Dismiss.
- **Dismiss**: on hover, an 18 pt close button appears at the row's top leading corner (surface, overlay shadow).
- **Smallest window** (640 x 420, 150 pt sidebar): the label hides; the glyph and a full-width Restart pill remain.

## States

| State | What it shows |
|---|---|
| `update` | update ready, pointer over the row (close button shown) |
| `announce` | worst-case 90-character announcement title truncated in the row, its popover open with a long body |
| `small` | smallest window, glyph and full-width Restart |

## Motion

Appear: the row rises 8 pt and fades in, 0.24 s on `firm`; rows above make room with the same curve. Dismiss: fade
0.15 s, rows settle. The popover uses the panel motion (opacity plus scale 0.97 to 1, 0.22 s on `firmFast`). Reduce
Motion: opacity only, rows jump. No looping or attention animation.

## VoiceOver

The row is a status region and announces a new notice once ("Update ready. Restart"). Restart is a button "Restart to
update". Dismiss is a button "Dismiss notice". The popover is a dialog "What's new". A dismissed notice id is stored,
so the same version never comes back.

## Answered questions (2026-11-05)

- Direction: B, one row, 34 pt.

## Still open

1. Should Restart wait for downloads in progress? (drawn: no prompt; the button could become "Restart after downloads")
2. Do announcements ship in the first release, or only update notices?
3. Is "Later" needed, or is hover-to-dismiss enough? (drawn: dismiss only)
