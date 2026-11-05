# Clear Today Tabs design

The Clear control above Today and the motion of the rows it archives (#413). Picked direction: **A, divider text**
(maintainer, 2026-11-05). Prototype: [`prototype.html`](prototype.html), states by hash
`#<hover|exit|after|rm|worst>[&dark][&shot]`; Prev and Next step through them. Screens:
`screens/clear-today-tabs-<state>-<light|dark>.png` (2x). Motion is shown as posed mid-motion frames. Synthetic data only.

Everyday chrome: system font, shell tokens, no mustard.

## The control

- **Where**: the trailing end of the divider between the pinned tabs and Today. The divider line runs from the
  leading inset to the control.
- **Shape**: "Clear", 12 pt semibold, `textSecondary`, on a `sidebarItemBackground` chip (`fill`, radius 6, padding
  1 x 6). The divider row keeps the shell's measured 25 pt (the prototype draws 18 pt), with the chip centred on the
  hairline; the hairline is inset 10 pt and the chip's trailing edge sits 2 pt past it.
- **Visibility**: shown while the pointer is over the sidebar; hidden otherwise. It is always in the accessibility
  tree, whether or not it is drawn.
- **Hover and press**: chip fill goes to `fillHover`; pressed, the title goes to `textPrimary`.
- **What it does**: archives every Today tab in the current Space except a tab that is playing media (BH-076). Pinned
  tabs and Favorites are untouched. With no Today tabs, the control is not
  drawn and is disabled for VoiceOver.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Control appears on sidebar hover | opacity 0 to 1, 0.12 s ease-out | same |
| Rows leave | every archived row collapses upward at once: height to 0, opacity to 0, translateY 0 to -6, scaleY 1 to 0.38 (anchor top), on `firm` `cubic-bezier(0.25, 1, 0.5, 1)` 0.24 s. One spring, no stagger. Rows below (the kept media tab) slide up with the same spring | opacity only, 0.15 s, rows in place; then the gap closes without motion |
| Undo toast | the existing toast entrance | the existing toast's Reduce Motion variant |

A Clear during the exit is ignored. File > Clear Today Tabs, Shift-Cmd-K and the bottom bar's Clear items run the same exit
while the sidebar is on screen; otherwise the rows go at once. Undo brings the rows back in their old order with the reverse of the same spring.

## After

- The playing tab stays and keeps its position at the top of Today.
- When two or more tabs were archived, the existing undo toast shows: "Archived <n> tabs", **Undo**. One tab: no
  toast (the Archive is one click away).

## Accessibility

- The control: button, label "Clear Today tabs", hint "Moves the tabs under Today to the Archive". Not hidden when
  the pointer is elsewhere.
- After Clear, VoiceOver announces "Archived <n> tabs" (the toast text).
- Keyboard: Tab from a focused sidebar row (Ctrl-Space) reaches the control, drawn while it has the focus; Return
  or Space presses it, Tab goes back to the rows, Esc to the page.

## States

| State | What it shows |
|---|---|
| `hover` | pointer over the sidebar, "Clear" at the trailing end of the divider |
| `exit` | mid-motion frame: every row collapsing upward at once; the playing tab stays |
| `after` | only the playing tab left; undo toast |
| `rm` | Reduce Motion: rows fading in place |
| `worst` | 24 Today tabs, long titles, a playing tab in the middle (kept) |

## Answered questions

- Direction: A (trailing "Clear" on hover, rows collapse upward, one spring).
- Shown without hover when Today is long: no. The control shows on sidebar hover only; it is always available to
  VoiceOver.
- Undo toast: kept (the existing toast, for two or more tabs).

Rejected directions: B (capsule on the divider, rows drop toward the Archive) and C (named Today header, slide out).
