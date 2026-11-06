# Private pages design

Switching, closing and muting the private pages of a Blank or Incognito window, and the per-window cap (#668, design
issue #709). A private page is an engine tab with no row in the shared sidebar (`privateTabs` in
`ShellWindowController`). The picked direction is B: the window's own sidebar, empty today, lists that window's
pages. Prototype: [`prototype.html`](prototype.html), states by hash `#s=<list|audio|cap>[&theme=dark][&shot=1]`.
Screens: `screens/b-<state>-<light|dark>.png` (2x, 960 x 600 window). The `b-` prefix is kept from the comparison
with direction A.

Everyday chrome: the system font, the shell's tokens, tab-row shapes. The list never shows the shared sidebar, other
windows' pages or anything from a normal window.

Not picked: A (the Ctrl-Tab switcher lists the pages; keyboard only).

## Decisions (maintainer, 2026-11-06)

1. Direction **B**: the private window's sidebar lists its own pages, with mute and close on hover.
2. Cap: **20 pages** per window.
3. Past the cap the new page **does not open**. A toast says so and offers **Close Oldest**. This covers a
   `target=_blank` link, `window.open` and Paste URL as New Tab alike: the page's new tab never opens.
4. **Cmd-W on the last private page closes the window**, as Cmd-W does in these windows today.
5. The mute key question was for direction A and does not apply.

## The list

- **Title**: "Pages", 11 pt semibold, `secondaryText`, 8 pt leading inset, 6 pt above the first row. It sits under the
  address pill (34 pt, 14 pt below it), in the space the shared sidebar would use.
- **Rows**: one per private page of this window, in the order they opened (newest last). 34 pt tall, radius 9, padding
  9 pt, gap 9: a 16 pt favicon (radius 4), the title on one line (13 pt, `primaryText`, truncating tail), then the
  trailing buttons.
- **Shown page**: its row is the current row (`tabCurrent`, shadow 0 / 1 / 2 black 0.08 in light, as a current tab row).
- **Hover**: `sidebarItemHovered` fill and a close button (16 pt box, radius 4, 10 pt xmark, `secondaryText`).
- **Sound**: a page playing sound has a mute button (16 pt box, 14 pt speaker glyph, `secondaryText`) on its row at all
  times, not only on hover. A muted page shows the muted glyph; the pressed button takes `sidebarItemHovered`.
- **Click a row**: shows that page. The list does not reorder.
- **Close** (the row's button, or Cmd-W on the shown page): the page closes; if it was shown, the page shown before it
  comes back. Cmd-W on the last page closes the window.
- **Footer**: the window's kind ("Incognito" or "Blank"), 11 pt semibold `sidebarForeground`, centered, as today.

## Past the cap

With 20 pages open, a 21st does not open. The window shows a toast: "This window has 20 pages open, the most it
keeps." with one action, **Close Oldest**, which closes the oldest page of the window that is not the shown one. The
refused page is not opened afterwards; the user repeats the click. The toast is the shared toast
(`docs/design/alerts-sheets-toasts.md`, section 4): "notice with action", 4 s, centered over the card. The mock draws
Close Oldest as a mustard pill; the shared toast draws its action as a small neutral pill, and the build uses the
shared toast as it is.

## States

| State | What it shows |
|---|---|
| `list` | three pages, the first shown (current row), the second hovered (close button) |
| `audio` | five pages, a hidden page playing sound with its mute button pressed (muted glyph) |
| `cap` | five rows drawn, the cap toast over the card |

Worst-case synthetic titles: an 80-character title and a one-letter title. No real browsing data.

## Tokens

| Use | Token | Light | Dark |
|---|---|---|---|
| Title, row text | `primaryText` | #0E0F10 at 0.90 | white 0.84 |
| "Pages", buttons | `secondaryText` | black 0.66 | white 0.76 |
| Address pill | `sidebarItemBackground` | #0E0F10 at 0.05 | #FAFBFF at 0.10 |
| Hovered row, pressed button | `sidebarItemHovered` | #0E0F10 at 0.10 | #FAFBFF at 0.15 |
| Current row | `tabCurrent` | white 0.85 | #FAFBFF at 0.20 |
| Footer label | `sidebarForeground` | black 0.49 | white 0.57 |
| Card edge | `cardBorder` | black 0.10 | white 0.20 |
| Toast | `toastSurface`, `toastText`, `toastShadow`, `toastEdge` | as the toast spec | as the toast spec |

No new tokens.

## Motion

A row added or closed: the rows below move 0.20 s on `firm` (`cubic-bezier(0.25, 1, 0.5, 1)`); a new row fades in. The
close and mute buttons fade in on hover, 0.12 s. The toast uses the shared toast motion. Reduce Motion: opacity only,
rows jump. Transform and opacity only.

## VoiceOver

The list is a list "Pages". Each row is a button with the page title; the shown page reads as selected. The mute
button is "Mute <title>" or "Unmute <title>"; the close button is "Close <title>". The cap toast is announced once.

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype of direction B, no network, synthetic titles |
| `screens/b-<list\|audio\|cap>-<light\|dark>.png` | 6 screenshots at 2x (3 light, 3 dark) |
