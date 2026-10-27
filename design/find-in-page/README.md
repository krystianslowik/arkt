# Find in page design

The find bar (#134): Cmd-F, Cmd-G, Shift-Cmd-G, a match count and a "no matches" state. Three directions are drawn
for the maintainer to pick from; none is built yet. The prototype is [`prototype.html`](prototype.html) (open it in a
browser; the page is live, so type in the field and step through the matches). States by hash,
`#<a|b|c>-<default|nomatch|long|empty>[&dark][&rm][&shot]`; Replay plays the entrance again.

Everyday chrome: the system font, the shell's tokens, neutral pills. Mustard appears only as a fill: the current match
in the page (graphite text on `#E9B520`), the other matches in a 34 % tint of it, and, in direction B only, the one
primary pill (Done).

## Directions

| | A. Floating pill | B. Docked bar | C. Panel with key hints |
|---|---|---|---|
| Idea | the smallest thing that does the job | a row of the card, like an infobar | a quiet panel that teaches the keys |
| Placement | top trailing, 12 in from the card's top and trailing edges | full card width, flush with the top edge | centered, 12 below the card's top edge |
| Size (pt) | 372 x 36, radius 18 | card width x 48; field 300 x 28 | 460 x 78 (row 32 + hint strip), radius 14 |
| Field | 13 regular, bare, glyph 14 | 13 regular in a `sidebarItemBackground` pill (radius 14) | 15 regular, glyph 16 |
| Count | 12 tabular, secondary, right aligned (min 56) | 12 tabular, secondary (min 70) | 12 tabular in a 24 high neutral capsule |
| Previous, next | 24 round chevron buttons, hairline before them | neutral 28 pills "Previous" and "Next" | 28 round neutral chevron buttons |
| Close | 24 round x button | **Done**, the one mustard pill | 28 round x button |
| Surface | `surfaceBrand`, `overlayShadow` | `surfaceBrand`, soft drop shadow below, no hairline | `surfaceBrand`, `overlayShadow` |
| Covers | a corner of the page's top margin | the page's top 48 | the page's top 88 |
| Best for | frequent use, least obstruction | clearest controls, no guessing | learning the shortcuts |
| Cost | icon-only buttons | covers the most; the one mustard pill | tallest; hint strip is permanent |

## Behavior

- **Open**: Cmd-F (Edit > Find > Find...). Focus goes to the field and its text is selected, so a second Cmd-F
  followed by typing replaces the query. The query is remembered per window; a new window starts empty.
- **Search**: live as you type, case and diacritic insensitive, whole page. The first match at or after the viewport top
  becomes current (not always the first in the page). Typing never moves focus out of the field.
- **Count**: "3 of 12" (current of total). Empty field: no count. No match: "No matches" in `primaryText` (never red: it is
  not an error), Previous and Next dim to 35 %, the field nudges once (see Motion). Counts above 999 read "999+".
- **Highlights**: current match in mustard with graphite text; all others in mustard at 34 %. The current match
  scrolls to the vertical center only when it is outside the middle 70 % of the viewport.
- **Step**: Return or Cmd-G next; Shift-Return or Shift-Cmd-G previous; both wrap past the ends with no message.
  Cmd-G and Shift-Cmd-G also work with the bar closed (reopens it on the last query).
- **Close**: Esc or the close control. The current match becomes the page's text selection, so Cmd-C copies it and
  the next Cmd-F starts there. Highlights clear. Focus returns to the page.
- **Split panes**: the bar belongs to the focused pane; it sits over that pane's card, not the window. Clicking another
  pane closes nothing; Cmd-F there opens that pane's own bar.
- **Smallest window**: the card can be as narrow as 480. A and C shrink to the card width minus 24; B hides the words
  "Previous" and "Next" and shows chevron pills of the same height. The count never hides.
- **Longest content**: a long query scrolls inside the field (it never wraps or grows the bar); the count keeps its place.

## Keyboard

| Key | Action |
|---|---|
| Cmd-F | open and focus; with the bar open, focus and select the field |
| Return, Cmd-G | next match |
| Shift-Return, Shift-Cmd-G | previous match |
| Esc | close |
| Tab, Shift-Tab | field, Previous, Next, close (Done); the system focus ring, never mustard |
| Cmd-E | use the selection as the query (system Find convention, if the maintainer wants it; not drawn) |

## Motion

The bar is opened from the keyboard, often, so motion is minimal.

| Moment | Motion | Reduce Motion |
|---|---|---|
| Open | opacity 0 to 1 and translateY -6 to 0, 0.12 s, ease-out `cubic-bezier(0.23, 1, 0.32, 1)`; skipped if it is already open | opacity only, 0.12 s |
| Close | none (instant) | none |
| Step to next or previous | none; the page scrolls without animation | same |
| No matches | the field nudges 3 pt left and right, 0.24 s, once per change into the empty result | none; the text alone says it |
| Button press | scale 0.94 (round) or 0.97 (pill), 0.12 s | none |

Transform and opacity only; layout never animates.

## VoiceOver and accessibility

- The bar is a group, role search, label "Find in page". The field is a search field labelled "Find in page".
- The count is a live region (polite): it reads "3 of 12" or "No matches" after the field settles (250 ms debounce).
  Stepping announces the new count only, not the page text; the page's own selection is read by VoiceOver as it moves.
- Buttons: "Previous match", "Next match", "Close find bar" (B: "Previous", "Next", "Done"). Dimmed buttons read
  "dimmed".
- The hint strip in C is decoration for sighted users; it is hidden from VoiceOver (the keys are in the menu).
- Mustard highlights carry no meaning alone: the count and the page selection do. No contrast ratio or warning is ever
  shown; the highlight text stays graphite in light and dark.

## Light and dark

Light: porcelain surface, black text at 90 %. Dark: graphite `#202321`, white text at 84 %. The mustard highlights are the
same in both (the tint drops to 30 % in dark). Increase Contrast adds a 1 pt `separatorIncreasedContrast` edge to the
field in B and to the count capsule in C. Reduce Transparency changes nothing: every surface is already opaque.

## Open questions for the maintainer

1. Which direction (A, B or C).
2. Does Esc keep the match selected (drawn here) or leave the page untouched?
3. Should the query be shared across tabs of one window, as it is across pages here?
4. Is Cmd-E "use selection for find" in scope for the first release?

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network, live search over a synthetic page |
| `screens/find-<a\|b\|c>-<default\|nomatch\|long>-<light\|dark>.png` | 18 screenshots at 2x (1080 x 720 window), synthetic text only |
