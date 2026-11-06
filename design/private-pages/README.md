# Private pages design

Switching, closing and muting the private pages of a Blank or Incognito window, and the per-window cap (#668, design
issue #709). A private page is an engine tab with no row in the shared sidebar (`privateTabs` in
`ShellWindowController`). The picked direction is B: the window's own sidebar, empty today, lists that window's
pages. Prototype: [`prototype.html`](prototype.html), states by hash `#s=<list|audio|cap|cap-none|small>[&theme=dark][&shot=1]`.
Screens: `screens/<state>-<light|dark>.png` (2x; 960 x 600 window, `small` at 640 x 420).

Everyday chrome: the system font, the shell's tokens, tab-row shapes. The list never shows the shared sidebar, other
windows' pages or anything from a normal window.

Not picked: A (the Ctrl-Tab switcher lists the pages; keyboard only).

## Decisions (maintainer, 2026-11-06)

1. Direction **B**. The private window's empty sidebar lists that window's own pages: the shown page is the current
   row, a page playing sound has a mute button, and a hovered row has a close button.
2. Cap: **20 pages** per window.
3. Past the cap the new page **does not open**. A toast says so and offers **Close Oldest**. This covers a
   `target=_blank` link, `window.open` and Paste URL as New Tab alike: the page's new tab never opens.
4. **Cmd-W on the last private page closes the window**, as Cmd-W does in these windows today.
5. The mute key question was for direction A and does not apply.

## Close Oldest (maintainer, 2026-11-06)

1. Close Oldest **spares the shown page**.
2. "Oldest" is the **earliest-opened page that is not shown**: the top row that is not the current row.
3. The refused page **does not open afterwards**. After Close Oldest the user repeats the click.
4. A page **playing sound is spared too**. Close Oldest closes the earliest-opened page that is neither shown nor
   playing sound. If every page is shown or playing sound, the toast has no Close Oldest (see "Past the cap").

## The list

- **Title**: "Pages", 11 pt semibold, `secondaryText`, 8 pt leading inset, 6 pt above the first row. It sits under the
  address pill (34 pt, 14 pt below it), in the space the shared sidebar would use.
- **Rows**: one per private page of this window, in open order (below). 34 pt tall, radius 9, padding 9 pt, gap 9
  between the row's parts: a 16 pt favicon (radius 4), the title on one line (13 pt, `primaryText`, truncating tail),
  then the trailing buttons.
- **Spacing between rows**: 0 pt. Rows are stacked on a 34 pt pitch; the fills and the current row's shadow separate
  them.
- **Shown page**: its row is the current row (`tabCurrent`, shadow 0 / 1 / 2 black 0.08 in light, none in dark, as a
  current tab row).
- **Hover**: `sidebarItemHovered` fill and a close button (16 pt box, radius 4, 10 pt xmark, `secondaryText`).
- **Sound**: a page playing sound has a mute button (16 pt box, 14 pt speaker glyph, `secondaryText`) on its row at all
  times, not only on hover. A muted page shows the muted glyph; the pressed button takes `sidebarItemHovered`.
- **Click a row**: shows that page. The list does not reorder.
- **Close** (the row's button, or Cmd-W on the shown page): the page closes; if it was shown, the page shown before it
  comes back. Cmd-W on the last page closes the window.
- **Footer**: the window's kind ("Incognito" or "Blank"), 11 pt semibold `sidebarForeground`, centered in a 40 pt band
  at the bottom of the sidebar.

## Order

The rows follow **open order**: the order the pages were opened in this window, oldest at the top, newest at the
bottom. Showing a page never moves its row.

`privateTabs` does not keep that order. `showPrivatePage` moves the shown page to the end of `privateTabs`, and
`adoptPrivatePage` inserts a background page just behind the shown page, so that `privateTabs` is the order pages come
back in when the shown one closes. The build keeps `privateTabs` for that job and keeps a **separate open-order list**
for the rows. A page enters the open-order list once, when it becomes a private page, and leaves it when it closes.

| How the page opened | Open-order list | `privateTabs` (unchanged) |
|---|---|---|
| Command bar or Paste and Go, first page | appended (bottom row) | appended, shown |
| Paste URL as New Tab | appended (bottom row) | appended, shown |
| Engine tab the engine makes active (`window.open`, `chrome.tabs.create`) | appended (bottom row) | appended, shown |
| Background engine tab: one adopted from a `target=_blank` link (or `window.open`) that the engine did not make active | **appended (bottom row)**, not next to its opener | inserted just behind the shown page |
| A row clicked, or the engine activates a page | no change | moved to the end, shown |

The 21st page of any kind is refused before it enters either list.

Close Oldest walks the open-order list from the top and closes the first page that is neither the shown page nor
playing sound. A muted page that is still playing counts as playing sound. `privateTabs` does not decide it.

## Scrolling and the smallest window

- The list scrolls when its rows do not fit between "Pages" and the footer: at the default 960 x 600 window about 13
  rows fit; at the smallest window (640 x 420, 150 pt sidebar) about 7.
- Only the rows scroll. The address pill and "Pages" stay at the top; the footer ("Incognito" or "Blank") stays in its
  40 pt band at the bottom and never scrolls with the list. The list ends above the footer.
- While rows are hidden below, the list's last 28 pt fade out, as the sidebar banner fades the row list. The scroller
  is the system overlay scroller.
- When a page is shown (a click, an activation, a new page), its row scrolls into view. A background page added at the
  bottom does not scroll the list.
- Titles truncate at the tail at any width; at 150 pt a row keeps its favicon, about 9 characters of title and its
  buttons.
- At the smallest window the toast keeps 16 pt from the card's edges and truncates its text; Close Oldest never
  truncates.

## Past the cap

With 20 pages open, a 21st does not open. The window shows the shared toast (section 4 of
`docs/design/alerts-sheets-toasts.md`, kind "notice with action", 4 s; added there in this change):

- 36 pt high, radius 18, centered over the card, 16 pt above the card's bottom edge, at most 480 pt wide.
- Padding 12 pt leading, 6 pt trailing. A 16 pt glyph box with the 14 pt `rectangle.stack` symbol at `toastText` 64 %
  (light) or 72 % (dark), 8 pt to the text.
- Text, 13 pt medium `toastText`: "This window has 20 pages open, the most it keeps."
- Action, 8 pt after the text: **Close Oldest**, the shared 24 pt neutral pill, not mustard (radius 12, padding 12, 12 pt semibold
  `toastText`, fill `sidebarItemHovered`, hover `sidebarItemBackground`).
- Surface `toastSurface` (these windows have no Space theme), shadow `toastShadow` and `toastEdge`.

Close Oldest closes the page the rules above pick ("Close Oldest") and the toast goes. The refused page does not open.

**No page can be closed for the user.** When every page is shown or playing sound, there is no Close Oldest. The toast
has no action (padding 14 pt trailing) and reads: "This window has 20 pages open. Close one to open another." The user
closes a page from its row.

## States

| State | What it shows |
|---|---|
| `list` | three pages, the first shown (current row), the second hovered (close button) |
| `audio` | five pages, a hidden page playing sound with its mute button pressed (muted glyph) |
| `cap` | 20 pages, the list scrolled to the top with its bottom edge faded, the cap toast over the card. Close Oldest would close the second row: the first is shown, and the second is neither shown nor playing sound |
| `cap-none` | 20 pages, the first shown and every other one playing sound: the toast has no action and reads "This window has 20 pages open. Close one to open another." |
| `small` | the smallest window (640 x 420, 150 pt sidebar), 20 pages, the list scrolling, the footer in its band, the cap toast truncating |

Worst-case synthetic titles: an 80-character title, a one-letter title and 20 pages. No real browsing data.

## Tokens

| Use | Token | Light | Dark |
|---|---|---|---|
| Title, row text | `primaryText` | #0E0F10 at 0.90 | white 0.84 |
| "Pages", buttons | `secondaryText` | black 0.66 | white 0.76 |
| Address pill | `sidebarItemBackground` | #0E0F10 at 0.05 | #FAFBFF at 0.10 |
| Hovered row, pressed button, toast action | `sidebarItemHovered` | #0E0F10 at 0.10 | #FAFBFF at 0.15 |
| Current row | `tabCurrent` | white 0.85 | #FAFBFF at 0.20 |
| Footer label | `sidebarForeground` | black 0.49 | white 0.57 |
| Card edge | `cardBorder` | black 0.10 | white 0.20 |
| Toast | `toastSurface`, `toastText`, `toastShadow`, `toastEdge` | as the toast spec | as the toast spec |

No new tokens.

## Motion

A row added or closed: the rows below move 0.20 s on `firm` (`cubic-bezier(0.25, 1, 0.5, 1)`); a new row fades in. The
close and mute buttons fade in on hover, 0.12 s. Scrolling a shown row into view uses the system scroll animation. The
toast uses the shared toast motion. Reduce Motion: opacity only, rows jump, the scroll jumps. Transform and opacity
only.

## VoiceOver

The list is a list "Pages". Each row is a button with the page title; the shown page reads as selected. The mute
button is "Mute <title>" or "Unmute <title>"; the close button is "Close <title>". The cap toast is announced once,
and Close Oldest, when shown, is a button.

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype of direction B, no network, synthetic titles |
| `screens/<list\|audio\|cap\|cap-none\|small>-<light\|dark>.png` | 10 screenshots at 2x (5 light, 5 dark) |
