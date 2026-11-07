# Edit Pin design

Edit Pinned URL for a pinned tab and Rename for a Favorite (#363). Picked direction: **B, one "Edit Pin" popover**
(maintainer, 2026-11-05). Prototype: [`prototype.html`](prototype.html), states by hash
`#<url|fav|invalid|small>[&dark][&shot]`. Screens: `screens/edit-pin-<state>-<light|dark>.png` (2x). Synthetic data only.

Everyday chrome: system font, shell tokens, one primary pill (Save).

## The popover

- **Opens from**: the pinned tab's menu (Edit Pinned URL...) and the Favorite tile's menu (Rename...). Anchored to the
  row (arrow on the leading edge, 16 pt from the top) or to the tile (arrow on the top edge, centered on the tile).
- **Size**: 320 pt wide, padding 16, radius 12, `surfaceBrand`, `overlayShadow`.
- **Title**: "Edit Pinned Tab" or "Edit Favorite", 13 pt semibold.
- **Fields**: labels 11 pt semibold `textSecondary`, 10 pt above each field; fields 28 pt.
  - Name: prefilled with the current title.
  - Pinned URL: prefilled with the pinned address; a long URL scrolls inside the field, never wraps.
- **Focus**: Edit Pinned URL focuses Pinned URL with the text selected; Rename focuses Name with the text selected.
- **Actions** (16 pt below the last field): "Use Current Page" (quiet text link, leading; fills Pinned URL with the
  tab's current address), Cancel (neutral pill), **Save** (mustard, the one primary, Return). Esc and a click outside
  cancel.
- A Favorite has no title on its tile: the name is the tile's hover tooltip and its VoiceOver label.

## Invalid address

Save stays enabled. On Save or Return with something that is not a web address, the Pinned URL field gets a 1 pt
`destructive` ring and a line under it: "Enter a web address, like example.com" (11 pt, `destructive`, warning glyph).
The popover stays open; the line clears on the next edit.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Popover opens | opacity 0 to 1, scale 0.97 to 1 from the arrow, 0.22 s on `firm` | opacity only, 0.15 s |
| Popover closes | opacity to 0, 0.15 s | same |
| Error line appears | opacity and height, 0.15 s | opacity only |

## Accessibility

- Popover: dialog, label "Edit Pinned Tab" or "Edit Favorite".
- Fields labelled "Name" and "Pinned URL"; the error line is announced when it appears and is the field's help text.
- "Use Current Page" is a button, hint "Sets the pinned URL to this tab's address".

## States

| State | What it shows |
|---|---|
| `url` | Edit Pinned URL on a pinned row; the longest URL scrolls in its field |
| `fav` | Rename on a Favorite; Name focused |
| `invalid` | not a web address; the reason under the field |
| `small` | smallest window, 640 x 420 pt, 150 pt sidebar: the popover keeps its 320 pt width, anchors to the row and overlaps the page, never the sidebar |

## Answered questions

- Direction: B (one Edit Pin popover for both menu items).
- Open: should Rename on a pinned tab also open this popover, or stay inline as today? Until answered, Rename on a
  pinned tab stays inline; the popover opens from Edit Pinned URL... and from a Favorite's Rename...

Rejected directions: A (edit in place in the sidebar) and C (command bar edit mode).
