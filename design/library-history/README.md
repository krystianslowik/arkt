# Library History design

The History section of the Library window (#631). Picked direction: **A, one list by day** (maintainer, 2026-11-05).
The Library window is the one drawn in `design/downloads` (A). Prototype: [`prototype.html`](prototype.html), states by
hash `#<default|filter|search|delete-day|empty>[&dark][&shot]`. Screens:
`screens/library-history-<state>-<light|dark>.png` (2x). Synthetic data only.

Everyday chrome: system font, shell tokens, one primary pill (Open on the selected row).

## Layout

- **Window**: the Library window, 800 x 540 pt default; rail 164 pt (Downloads, History, Spaces); 52 pt header with the
  title and a 240 pt search field ("Search history").
- **Filter row** (32 pt): a "Show" pop-up: All history, This Mac, Imported (with its count).
- **Day headers**: 12 pt semibold `textSecondary` ("Today", "Yesterday", then the weekday or date), followed by the full
  date in `textTertiary`. Padding 12 top, 4 bottom.
- **Rows**: 44 pt, radius 9: 22 pt site tile, title (one line, truncates at the end), host under it (11.5 pt
  `textSecondary`), time trailing (12 pt `textSecondary`, tabular figures). The selected row takes `fillHover` and shows
  **Open** (small mustard pill, Return).
- **Footer** (44 pt): "Clear browsing data..." (quiet link, opens the Clear browsing data sheet, `design/clear-browsing-data`)
  and the total visit count trailing.

## Imported history

Merged into the same list by date, with no per-row mark. The Show pop-up filters it (This Mac or Imported), and search
covers it.

## Search

Matches titles and addresses across every day, imported included; results keep their day headers. The matched text is
tinted with a mustard fill at 35 % (`accent` 0.35, radius 3). It is a fill, never a stroke or text color.

## Delete

- Delete (the key) removes the selected rows.
- **Delete Day...**: pointing at a day header shows "Delete Day..." at its trailing end (12 pt, `destructive`); the
  header takes `fill`. It is also in the header's context menu. It opens a window sheet: "Delete Today's history?" /
  "<n> pages visited on <date> are removed from History. Your Spaces, sidebar tabs and Archive stay as they are."
  Cancel (neutral, Return default) and **Delete Day** (neutral pill, red title, never mustard, never the Return
  default).

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Show pop-up opens | the system menu | the system menu |
| Delete Day sheet | the system sheet | the system sheet |
| Rows removed | height and opacity to 0, 0.24 s on `firm`; rows below slide up | opacity only, 0.15 s, then the gap closes without motion |
| Search results replace the list | crossfade, 0.15 s | none |

## Accessibility

- The list is a table; each day header is a group heading.
- Row label: "<title>, <host>, <time>"; imported rows read the same.
- Day header button: "Delete <day>", hint "Deletes every page visited on <date>".
- Show pop-up: "Show: <source>".

## States

| State | What it shows |
|---|---|
| `default` | two days, long titles; the selected row with Open |
| `filter` | the Show pop-up open: All history, This Mac, Imported |
| `search` | "lichen": results across days, one imported |
| `delete-day` | pointer on Today's header and the Delete Day sheet |
| `empty` | no history yet |

## Answered questions

- Direction: A (one list by day).
- Imported history: merged into the same list by date; the Show pop-up filters All history, This Mac, Imported.
- Delete Day: yes, from the day header (hover and context menu), with a confirmation sheet.
- Search tint: mustard fill at 35 %, allowed because it is a fill.

Rejected directions: B (days folded into sites) and C (days and a timeline).
