# Library Spaces design

The Spaces section of the Library window: an overview of every Space and a way to move tabs between them, including
to an empty Space (#635, BH-044). Picked direction: **A, a board of Spaces** (maintainer, 2026-11-05). The Library
keeps a Spaces section, next to Downloads and History. Prototype: [`prototype.html`](prototype.html), states by hash
`#<default|drag|worst|done|small>[&dark][&shot]`. Screens: `screens/library-spaces-<state>-<light|dark>.png` (2x). Synthetic
data only.

Everyday chrome: system font, shell tokens, no mustard (the board has no primary action).

## Layout

- **Window**: the Library window, titled "Library" (800 x 540 pt default, smallest 640 x 420 pt with a 150 pt rail).
  The rail is the shared Library window rail (Downloads, History, Spaces, Boosts), documented once in
  [`design/library-history`](../library-history/README.md#library-window-rail). Search field "Search tabs" filters
  every column.
- **Board**: one column per Space, in sidebar order, 146 pt wide, gap 8, radius 10, `listField` background, padding
  8 x 6. More columns than fit scroll sideways; the trailing edge fades over the last 8 % of the board.
- **Column header**: 14 pt Space swatch (the Space's theme gradient, radius 4), the name (13 pt semibold, truncates at
  the end), the tab count trailing (12 pt `textSecondary`).
- **Groups**: "Pinned" then "Today" (11 pt semibold `textTertiary`). A group with no tabs is not drawn.
- **Tab rows**: 30 pt, radius 8: 14 pt favicon, title (one line, truncates). Selected rows take `fillHover`.
- **Empty Space**: a 76 pt well (`fill`, radius 9) reading "No tabs" (12 pt `textTertiary`).

## Moving tabs

- Drag a tab (or a multi-selection) onto another column. A pinned tab dropped in Pinned stays pinned; dropped in
  Today it becomes a Today tab, and the other way round.
- **Drop area on an empty Space**: while dragging, the target column takes `fillHover` and its well lifts
  (`rowCurrent` fill, small shadow) and reads "Drop to move here" (12 pt semibold).
- The lifted tab follows the pointer at scale 1.03 with `overlayShadow`; its source row stays at 30 % opacity.
- After the drop: a toast "Moved to <Space>" with **Undo**.
- Keyboard: Move to Space... in the row's context menu does the same.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Lift | scale 1 to 1.03, shadow in, 0.18 s on `firm` | shadow only, no scale |
| Target column highlights | fill crossfade, 0.12 s | same |
| Drop | the row settles into its new slot, 0.24 s on `firm`; rows below make room with the same spring | opacity only, 0.15 s |
| Toast | the shared toast motion | the shared toast's Reduce Motion variant |

## Accessibility

- Each column is a group: "<Space>, <n> tabs".
- Rows: "<title>, pinned" or "<title>"; the Move to Space actions are exposed as VoiceOver custom actions.
- While dragging, the target is announced: "Drop in <Space>".

## States

| State | What it shows |
|---|---|
| `default` | four Spaces; an empty Space shows its well |
| `drag` | a tab dragged onto the empty Space: column lifted, "Drop to move here" |
| `worst` | six Spaces scroll sideways, a long Space name truncates, 14 tabs in one column |
| `small` | smallest Library window, 640 x 420 pt, 150 pt rail: three columns show, the board scrolls sideways with a faded edge |
| `done` | after the drop: the tab in the formerly empty Space; toast with Undo |

## Answered questions

- Direction: A (Library board, one column per Space, a drop area on empty Spaces).
- Scope: the Library keeps a Spaces section.

Rejected directions: B (Spaces list and tabs) and C (no section, a Move to Space picker).
