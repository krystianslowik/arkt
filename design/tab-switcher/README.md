# Tab switcher

Design for the tab switcher and keyboard tab navigation (#103), part of the design-first pass in #304. The switcher
is the Ctrl-Tab overlay: hold Ctrl, tap Tab, and the five most recently viewed tabs appear in a floating list; keep
tapping to walk the list, release Ctrl to land. Around it sit the quiet keyboard paths with no overlay at all:
Cmd-1..9 jumps straight to a sidebar item, Cmd-Opt-Down/Up steps through the sidebar in order, and Ctrl-Space hands
keyboard focus to the sidebar with the current tab revealed.

- Prototype: [`design/tab-switcher/prototype.html`](prototype.html). Open it in a browser. The bar at the top
  switches states and toggles dark mode; the states are hash-addressable (`#s=first`, `#s=mid`, `#s=single`,
  `#s=sidebar`, with `&theme=dark&shot=1`).
- Screenshots: [`design/tab-switcher/screens/`](screens/), light and dark, 2x, rendered headless. The index is at
  the end of this document.
- Implementation issue: #103 (this design precedes the build; the acceptance bar "switcher overlay shows within one
  frame of the key press" is specified under [Motion](#motion)).

Note on location: the other #304 surfaces keep their doc at `docs/design/<surface>.md`. This branch is restricted to
`design/tab-switcher/`, so the doc lives here; the maintainer may move it to `docs/design/tab-switcher.md` on merge.

## Look

The switcher is one floating panel, centered over the window, above the sidebar and the content card. It borrows the
toast family: the `toastSurface` fill, 12 pt continuous corners, the `overlayShadow` from the alerts design, no
scrim — the page behind is not dimmed (BH-011). There is no header, no hint bar, no footer: five rows and nothing
else. The only color besides the text tokens is the Space dot on each row, so a list that spans Spaces reads at a
glance (BH-011, BH-012).

Each row is one tab: favicon, title, then a trailing group with a recording indicator (when the tab is using the
camera or microphone), a split marker (when the tab is one pane of a Split View), and the Space chip. The current
tab is not listed; the first row is the tab you will land on if you release Ctrl right now, and it starts
highlighted — that is what makes the quick flick feel instant (BH-007).

Typeface: the system font (SF Pro) throughout, as in every AppKit view in the shell. The prototype uses
`-apple-system`, which is the same face, so the screenshots match the app.

## Keys and what they do

| Key | Action | Overlay? | Rule |
|---|---|---|---|
| Ctrl-Tab, tap and release | Switch to the previously viewed tab, no UI if the release beats the first frame | no | BH-007, KB-022 |
| Ctrl-Tab, Ctrl held | Show the switcher; first row (most recent previous tab) highlighted | yes | BH-008, KB-022 |
| Tab, while Ctrl held | Move the highlight down one row; wraps from the last row to the first | yes | BH-008 |
| Ctrl-Shift-Tab | Same, backwards; wraps from the first row to the last | yes | BH-009, KB-023 |
| Ctrl-` (backtick), while the switcher is open | Same as Ctrl-Shift-Tab (alternate) | yes | BH-009, KB-024 (SINGLE-SOURCE) |
| W, while Ctrl held | Close the highlighted tab; the switcher stays open | yes | BH-010, KB-025 (SINGLE-SOURCE) |
| Release Ctrl | Activate the highlighted tab | dismisses | BH-007, BH-008 |
| Esc, while the switcher is open | Cancel: stay on the current tab | dismisses | proposed; PARITY(NEEDS-RUNTIME-CHECK) |
| Ctrl-Cmd-Right / Ctrl-Cmd-Left | Cycle forward / backward through previously viewed tabs | assumed no | BH-013, KB-026, KB-027; open question RT-01 |
| Cmd-1 ... Cmd-8 | Go to sidebar item 1..8 (Favorites counted first while Settings > Appearance "Count Favorites in Command-1 to Command-8" is on) | no | BH-014, KB-020 |
| Cmd-9 | Go to the last sidebar item (the 9th item while "Command-9 opens the ninth tab" is on) | no | BH-015, KB-021 |
| Cmd-Opt-Down / Cmd-Opt-Up | Next / previous tab in sidebar order; a collapsed Pinned section is skipped | no | BH-016, BH-017, KB-028, KB-029 |
| Cmd-} / Cmd-{ | Assumed aliases of next / previous tab in sidebar order | no | KB-030; open question RT-02 |
| Ctrl-Space | Reveal the current tab in the sidebar and move keyboard focus to it | no | BH-019, KB-036 |

## Layout

All values in points. The panel reuses the alerts overlay tokens; the only new tokens are the two listed at the end
of the table.

| Element | Value | Token or source |
|---|---|---|
| Panel width | 480 | Arkt's value; Arc's is unpublished, PARITY(NEEDS-RUNTIME-CHECK) |
| Panel padding | 6 on every side | proposed |
| Rows visible | at most 5 (the five most recently viewed tabs) | BH-008; see open question 5 |
| Row height | 40 | proposed |
| Row corner radius | 8 | matches sidebar rows |
| Favicon slot | 20 wide, favicon 16, 10 leading inset, 10 gap to the title | sidebar favicon size |
| Title | 13 medium, `primaryText`, single line, tail truncation | ShellTokens |
| Recording indicator | 7 pt green dot plus a 12 pt camera glyph, shown when the tab holds camera or microphone; 8 before the Space chip | BH-011; system green |
| Split marker | 12 pt split glyph (two panes), shown when the tab is one pane of a Split View; 8 before the Space chip | proposed; see open question 6 |
| Space chip | 7 pt dot in the Space's theme color, 5 gap, Space name 11 regular `secondaryText`, truncated at 120 | BH-011, BH-012 |
| Trailing group gap | 12 from the title | proposed |
| Highlighted row | `sidebarItemHovered` fill with a 1 pt `sidebarDivider` inner edge | ShellTokens |
| Panel position | horizontally centered in the window (sidebar included); top edge at 38 % of the window height | proposed; PARITY(NEEDS-RUNTIME-CHECK) |
| Panel surface | `toastSurface` | ShellTokens |
| Panel corners | 12, continuous | as the alerts overlay |
| Panel shadow | `overlayShadow` (0.5 pt edge, 18/48 and 3/10 drop) | AlertTokens |
| Sidebar keyboard focus ring | The system focus ring on the row (`NSView.focusRingType = .default`, drawn in `NSColor.keyboardFocusIndicatorColor`, following the user's accent color). Mustard is never a stroke | AppKit |
| Sidebar overflow pill | 24 high, `toastSurface`, `toastShadow`, chevron plus count ("3 more above"), centered on the sidebar's top or bottom edge for 3 s | proposed `ShellTokens.switcherOverflowPill`; PARITY(NEEDS-RUNTIME-CHECK) |

New tokens this design adds: `switcherOverflowPill` reuses `toastSurface` and `toastShadow`, so no new colors at
all; the name is for the component, not a color. `ShellTokensContrastTests` needs no new cases: every color used is
an existing token.

## States

| State | Prototype hash | Screenshot |
|---|---|---|
| Just opened (Ctrl held, first row highlighted) | `#s=first` | `switcher-first-open-{light,dark}.png` |
| Mid-cycle (Tab pressed once; second row highlighted) | `#s=mid` | `switcher-mid-cycle-{light,dark}.png` |
| One row left after closing tabs with W | `#s=single` | `switcher-single-row-{light,dark}.png` |
| Sidebar keyboard focus after Ctrl-Space, with the overflow pill | `#s=sidebar` | `sidebar-focus-{light,dark}.png` |
| Favorites grid keyboard focus after Ctrl-Space | `#s=sidebar` | `favorites-focus-{light,dark}.png` |

The list in the prototype is deliberately a multi-Space MRU: five synthetic tabs across the Work, Personal and Dev
Spaces, one with a camera indicator, one inside a Split View (BH-011, BH-012).

## Flows

### The flick (BH-007)

Press Ctrl-Tab and let go. If the Ctrl key-up arrives before the next frame is presented, nothing is ever drawn and
the previously viewed tab becomes active at once. This is how "no switcher UI" and the build bar "the overlay shows
within one frame of the key press" coexist: the overlay never waits, but a fast release commits before it exists.
Whether Arc works the same way is open question 9.

### Holding Ctrl (BH-008, BH-009)

While Ctrl stays held, the panel is on screen from the first presented frame. The highlight starts on the first row.
Each Tab moves it down, each Shift-Tab or Ctrl-` moves it up, and both directions wrap around the ends. Releasing
Ctrl activates the highlighted tab and dismisses the panel.

### Closing tabs from the switcher (BH-010, KB-025)

With Ctrl held, W closes the highlighted tab. Its row collapses, the rows below slide up, and the highlight moves to
the row that took its place (the next most recent). The switcher stays open, so W can be repeated. When the last row
is closed this way the panel dismisses and the tab that was current when the switcher opened stays active. A tab
closed from the switcher follows the normal close path: unpinned tabs go to the Archive, Cmd-Shift-T / Cmd-Z bring
them back (KB-010, KB-011).

### Dismiss rules

The panel leaves three ways: commit (release Ctrl), cancel (Esc, or a click anywhere outside the panel), and
replacement (any key that is not Tab, Shift-Tab, backtick, W or Esc dismisses the panel as a cancel and is then
handled normally — so Cmd-W while cycling closes the current tab, it does not get eaten). Cancel and replacement
never change the active tab. Esc here is the shell's own context (KB-039), not the page's: the page behind is not
focused while the switcher is open, so there is no "page first" ordering question as there is for Peek.

### Splits

A Split View's panes are separate tabs with separate last-viewed times, so each pane gets its own row, marked with
the split glyph. Landing on a pane row activates that pane inside its split. The other pane of the split is not
pulled along. Proposed; how Arc orders split panes in the MRU list is open question 6.

### Other Spaces and other windows (BH-012)

The list spans Spaces: a tab viewed in another Space appears with that Space's chip, and landing on it switches
Space (the existing Space-switch presentation runs; the switcher does not add its own). The assumed scope is the
current window only — tabs last viewed in a second window do not appear. That scope is open question 1 (RT-12).

Tabs inside closed folders appear normally: the MRU list is about what was viewed, not what is visible.

### Cmd-1..9 and next / previous (no overlay)

Cmd-1..8 and Cmd-9 activate the sidebar item directly (BH-014, BH-015), with the two Appearance settings from the
Settings design deciding the counting ("Count Favorites in Command-1 to Command-8", on; "Command-9 opens the ninth
tab", off). Cmd-Opt-Down / Cmd-Opt-Up step through the sidebar in order — Favorites, then Pinned, then Today — and
skip the Pinned section when it is collapsed (BH-016, BH-017). Whether next/previous wraps at the ends is open
question 7. None of these keys show the switcher; the only visible change is the sidebar selection moving and the
reveal behavior below.

### Reveal and the overflow pill (BH-018)

Whenever a keyboard command lands on a sidebar row that is scrolled out of view, the sidebar scrolls it into view
(`springyFast`), and a small pill appears on the edge where rows remain hidden: "3 more above" or "2 more below".
The pill fades after 3 seconds or on the next scroll. The pill's exact form in Arc is not documented; the count pill
is proposed, PARITY(NEEDS-RUNTIME-CHECK).

### Ctrl-Space and the sidebar keyboard focus hand-off (BH-019, BH-020, KB-036)

Ctrl-Space reveals the current tab — scrolling the sidebar and opening a closed folder if the tab sits inside one —
and moves keyboard focus to that row, shown with the system focus ring. This is a real focus hand-off: the page loses
focus, the sidebar becomes the key view. From there, the assumed behavior (open question 4, RT-13):

- Up / Down move the focus row through the list; Left / Right move across the Favorites grid.
- Return opens the focused item and returns focus to the page.
- Esc returns focus to the page without opening anything.
- The focus ring is shown only while the sidebar holds keyboard focus; the next pointer click or page key removes it.

### Edge cases

- One tab viewed: Ctrl-Tab does nothing. No overlay, no beep; the previously-viewed list is empty.
- Two tabs: the flick toggles between them; holding Ctrl shows a one-row panel with the other tab.
- Closing tabs with W down to one row: the panel shows that single row; one more W closes it and dismisses the
  panel (the state in `switcher-single-row-*.png`).
- The current tab is closed from another path while the switcher is open: the switcher cancels and the tab that
  takes focus takes it without the overlay.
- A tab is archived or a Space is deleted while the switcher is open: its row collapses exactly as if closed with W.
- Sidebar hidden (Cmd-S): the switcher is unaffected; it floats over the window either way.
- Full screen: the switcher shows in the full screen space, centered on the window as usual.

## Motion

The build bar: **the switcher overlay shows within one frame of the key press** — 8.3 ms at 120 Hz. The design meets
it by giving the panel no entrance animation at all: it is presented fully laid out, at full opacity, on the first
frame after key-down. The rows are filled from data already in memory (favicons from the favicon cache, titles and
Space chips from the sidebar model); nothing is snapshotted, measured or fetched before the panel is on screen.

Motion exists only after that first frame, and all of it is transform/opacity springs from `Motion/SpringPreset`:

| Transition | Motion | Preset |
|---|---|---|
| Highlight move (Tab / Shift-Tab / Ctrl-`) | the highlight fill slides between rows, transform Y only; retargeted if the key repeats mid-flight | `springyFast` (0.80, 0.18 s) |
| Close row with W | the row's opacity to 0 and its height to 0, rows below slide up with the same spring | `firmFast` (0.95, 0.15 s) |
| Dismiss (commit, cancel, replace) | panel opacity to 0; no transform | 0.10 s ease-out |
| Sidebar scroll to reveal | the sidebar scrolls the row into view | `springyFast` |
| Overflow pill | fades in and slides 4 pt from its edge; out after 3 s | `springyFast` in, 0.15 s fade out |

Reduce Motion (`NSWorkspace.accessibilityDisplayShouldReduceMotion`): the open path is already instant and stays
identical (nothing to reduce — the one-frame bar holds in Reduce Motion too). The highlight moves instantly. The W
collapse becomes opacity-only. The dismiss fade stays. The sidebar scroll to reveal becomes an instant jump cut.

Reduce Transparency: the panel keeps `toastSurface` (it is already near-opaque) and takes a fully opaque fill
(`toolbarSurface`); the shadow is unchanged.

## Keyboard

Everything is in the [keys table](#keys-and-what-they-do) above. Implementation-facing notes:

- The switcher is a key-down-driven, modifier-held overlay: it opens on the Ctrl-Tab key-down and lives exactly as
  long as Ctrl stays held. Ctrl release is the commit signal, tracked from `flagsChanged`.
- While the switcher is open, Tab, Shift-Tab, backtick, W and Esc are swallowed; every other key dismisses the
  switcher as a cancel and is processed normally.
- The switcher never moves keyboard focus into itself in the AppKit sense — it is a transient overlay driven by raw
  key events, so focus (and the page's caret) is undisturbed unless the user commits. The deliberate focus hand-off
  is Ctrl-Space, which moves focus to the sidebar.

## VoiceOver

- Opening the switcher posts "Recent tabs, <n> tabs" and moves VoiceOver focus to the highlighted row. The panel is
  a modal group (`AXGroup`, dialog subrole, label "Recent tabs"); the page behind is hidden from accessibility while
  it is open.
- Each row is "〈title〉, 〈Space〉, <k> of <n>", with ", camera in use" or ", microphone in use" appended for
  recording tabs and ", split" for split panes. Moving the highlight announces the new row.
- W announces "Closed 〈title〉" and then the newly highlighted row.
- Committing announces the tab change as any tab switch does ("〈title〉, selected"). Esc announces "Cancelled".
- Ctrl-Space moves VoiceOver focus to the sidebar and announces "Sidebar, 〈current tab title〉". Arrow-key movement
  reads each row; Return announces the opened tab.

## Copy

The switcher itself has no visible copy — no heading, no hints — matching Arc's minimal overlay. The only new
strings:

| Where | Text |
|---|---|
| Overflow pill | "〈n〉 more above" / "〈n〉 more below" |
| VoiceOver, open | Recent tabs, 〈n〉 tabs |
| VoiceOver, row | 〈title〉, 〈Space〉, 〈k〉 of 〈n〉 |
| VoiceOver, close from switcher | Closed 〈title〉 |
| VoiceOver, cancel | Cancelled |
| VoiceOver, Ctrl-Space | Sidebar, 〈current tab title〉 |

Settings strings are not invented here: "Count Favorites in Command-1 to Command-8" and "Command-9 opens the ninth
tab" are already in the Settings design (#305).

## Light and dark

The switcher follows the window's appearance like the rest of the chrome, and the Space chips carry each tab's Space
theme color in both appearances (BH-011). Light screenshots use the Personal sample theme, dark ones the Dev sample
theme. The panel keeps the `overlayShadow` in dark mode, which is what separates it from a dark page; the 0.5 pt
edge brightens to white 20 %, as on every overlay.

## Parity notes and open questions

BH-007, BH-008, BH-009, BH-011, BH-014, BH-015, BH-016, BH-018, BH-019 and KB-020 to KB-029, KB-036 are CONFIRMED
in the spec and are designed as written. KB-024, KB-025 and BH-010 are SINGLE-SOURCE (one release note each); they
are designed in but should be confirmed at runtime. Everything else undecided is an open question for the
maintainer — the prototype and the flows above assume the answer on the left, but nothing is settled:

1. **RT-12 (BH-012) — window scope.** Assumed: the MRU list spans the Spaces of the current window only. Open: does
   Arc list tabs last viewed in another window, and in what order?
2. **RT-01 (BH-013, KB-026, KB-027) — Ctrl-Cmd-Right/Left vs Ctrl-Tab.** Assumed: same MRU order as the switcher,
   but instant, with no overlay, and it wraps. Open: does Arc show an overlay for these, does the order match, does
   it wrap?
3. **RT-02 (KB-030) — Cmd-} / Cmd-{.** Assumed: aliases of next / previous tab in sidebar order (HK and APC say so;
   ATH says back/forward; not in the default menu). Open until measured.
4. **RT-13 (BH-020) — sidebar keyboard navigation.** Assumed: arrows move the focus row, Return opens and returns
   focus to the page, Esc returns focus without opening. Open: Arc's exact keys, including whether Left/Right do
   anything outside the Favorites grid (folders? collapse?) and whether typing selects.
5. **List length.** Assumed: exactly the five most recently viewed tabs (BH-008), wrap-around within them, no
   scrolling. Open: does Arc ever show more than five or scroll?
6. **Splits in the MRU list.** Assumed: one row per pane, ordered by each pane's own last-viewed time, landing
   focuses that pane. Open: Arc's treatment of split panes in the switcher.
7. **Next/previous wrap.** Assumed: Cmd-Opt-Down/Up clamps at the first and last sidebar item (no wrap), unlike the
   MRU switcher, which wraps. Open: Arc's behavior at the ends.
8. **Row content vs "previews".** BH-008 says the overlay shows titles and previews. Assumed: favicon, title and
   Space chip are enough; live page thumbnails are deliberately left out (cost, and a one-frame budget). Open:
   whether previews are required for parity, and if so whether snapshots or live.
9. **Tap vs hold timing.** Assumed: the overlay is presented on the first frame after key-down, and a Ctrl release
   before that frame commits with no UI. Open: whether Arc instead shows the overlay only after a short hold delay —
   a runtime check against real Arc settles it.
10. **Panel size and position.** The 480 pt width, 40 pt rows and 38 % vertical position are Arkt's values; Arc's
    are unpublished. PARITY(NEEDS-RUNTIME-CHECK).

## Implementation notes

- The panel is a layer-backed overlay view in the existing `ShellWindowController`, above the sidebar and the
  content card, non-activating. To hit the one-frame bar it is kept pre-built and hidden per window; key-down fills
  the five rows synchronously from the sidebar model and the favicon cache and orders the layer in the same run-loop
  turn. No web content, snapshot or layout work may sit between key-down and presentation.
- The MRU list lives next to the sidebar model: an ordered list of tab IDs per window, moved to front on every tab
  activation, pruned on close. The switcher, Ctrl-Cmd-Right/Left (if confirmed) and any future "recent" surface all
  read the same list.
- Key handling: Ctrl-Tab and friends are matched on key-down with modifier flags; the overlay's open state is driven
  by `flagsChanged` for Ctrl. The swallow list while open is exactly Tab, Shift-Tab, backtick, W, Esc.
- Cmd-1..9 resolves the sidebar item index against the two Appearance settings, activates the tab, and runs the
  reveal (BH-018). Next/previous walks the same flattened sidebar order the sidebar model already exposes.
- Highlight and row motion run on Core Animation through `SpringAnimationFactory`; the highlight is a single
  transform-animated fill layer behind the row content.

## Screenshot index

All in `design/tab-switcher/screens/`, 2560 x 1600 (1280 x 800 pt at 2x), saved as full-color PNG (no palette
quantization, so shadows stay smooth), each under 400 KB. Titles and URLs are synthetic.

States, light and dark: `switcher-first-open`, `switcher-mid-cycle`, `switcher-single-row`, `sidebar-focus`,
`favorites-focus`.
