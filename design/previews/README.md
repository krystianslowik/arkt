# Previews design

Hover previews for pinned and Favorite sites, and link hover cards (#650): a side card with a native list of the
site's items, read from the open signed-in tab, and a snapshot of the tab when that fails. Prototype:
[`prototype.html`](prototype.html), states `#<mail|calendar|link|empty|long|fallback|settings>[&dark][&rm][&shot]`.
Screens: `screens/previews-<state>-<light|dark>.png` (2x). Site names, people and mail are synthetic.

Everyday chrome: system font, `surfaceBrand` card, `overlayShadow`. No mustard anywhere: a preview has no primary
action (a click opens the tab). The unread count is a graphite capsule with porcelain text (porcelain with graphite
text in dark), as in the extensions design. Picked over B (snapshot card for every site) and C (compact callout);
B's snapshot is kept only as the fallback.

## The card

| | Value |
|---|---|
| Placement | 8 pt to the right of the sidebar, top aligned with the hovered row or tile |
| Width | 340 pt; corner radius 12 |
| Header | site glyph 16 pt, title 13 semibold, unread capsule (11 semibold, radius 8), account or summary in 12 secondary, trailing; padding 10 / 12 / 8 |
| Rows | up to 4 items, padding 7 / 12; the first row is highlighted with `sidebarItemBackground` |
| Mail row | 6 pt unread dot, sender (semibold), subject (primary), first line (secondary 12), time (11.5 secondary, tabular) |
| Calendar row | 3 pt bar in `sidebarForeground`, start and end times (66 pt column), title (semibold), place (12 secondary); next 3 events |
| Footer | 1 pt `sidebarDivider` above, "Click a row to open it in the tab", 12 secondary |
| Link card | 300 pt wide: snapshot 150 pt high (radius 8, 1 pt `cardBorder`), title (semibold), description (12 secondary), site glyph and host |
| Snapshot fallback | same card and header ("Updated just now" instead of the count), a 200 pt high picture of the pinned tab, footer "Click to open the tab" |

## First supported sites

One mail site and one calendar site, each with its own reader. Documents and design files come later and have no
switch until they ship. For a supported site whose reader fails (the page changed, or the tab has not loaded the data
yet), the card shows the snapshot fallback instead of an error.

## States

| State | What it shows |
|---|---|
| `mail` | pointer on the mail Favorite: 12 unread, four messages |
| `calendar` | pointer on the calendar Favorite: the next three events |
| `link` | pointer on a link in the page: the link card |
| `empty` | no unread mail: "Inbox zero" and "No unread mail" |
| `long` | 9,999+ unread, a 60-character sender and a 100-character subject, both truncated on one line |
| `fallback` | the mail reader failed: the card shows a snapshot of the pinned tab |
| `settings` | the Previews group in Settings |

## Behavior

- Sidebar previews open after 500 ms of hover on a row or tile. Moving to the next row within 300 ms moves the card
  without a new delay.
- Dismiss when the pointer leaves both the row and the card for 150 ms; Esc closes it.
- Click a row in the card: the pinned tab opens on that item. Click the header: the tab opens.
- Link cards open after 800 ms of hover over a link. Holding Shift shows the card at once, with no delay.
- The Settings pop-up "Show link previews" has two choices: "After a short pause" (default: 800 ms, or at once with
  Shift) and "Only with Shift".
- The link snapshot comes from a background render of the link target with no cookies beyond what the page already
  sends; nothing leaves the Mac.
- Longest: names and subjects truncate with an ellipsis on one line; counts above 9,999 read "9,999+".
- Smallest window: the card flips to the left edge of the content card if it would cross the window's trailing edge.

## Settings

A "Previews" group: Mail, Calendar and Links, each a switch (graphite when on, as in `design/settings`), and the
"Show link previews" pop-up. Copy: "Built from tabs you already have open. Nothing is fetched for a preview."

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Open | opacity 0 to 1, translateX -4 to 0, scale 0.98 to 1, 0.18 s `firmFast` | opacity only, 0.15 s |
| Move to another row | the card moves with the row, 0.15 s ease-out, no new entrance | jump |
| Close | opacity to 0, 0.1 s | same |

## VoiceOver and keyboard

- The hovered row or tile gets a custom action "Show preview".
- The card is a popover labeled "Mail preview" (or "Calendar preview", "Link preview") with a list of items. Each item
  is a button, for example "Hut warden, Second hut water is back on, 9:41, unread".
- The snapshot fallback reads as "Mail preview, picture of the tab, updated just now"; the card's header button opens
  the tab.
- Cmd-Option-P opens the preview for the focused row from the keyboard.

## Answered questions

1. Direction: A, side card, with B's snapshot as the fallback when a site's reader fails.
2. First supported sites: one mail site and one calendar site. Documents and design files later.
3. Link previews: both. After an 800 ms hover by default, and at once while Shift is held; "Only with Shift" is the
   other choice in Settings.
