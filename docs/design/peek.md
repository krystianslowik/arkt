# Peek

Design for Peek (#29), part of the design-first pass in #304. Peek shows a link from a pinned tab or a Favorite in
a card floating over the page, so you can read it and drop it without losing your place. It can be closed, opened as
a Today tab, or added to a Split View with the page it came from.

- Prototype: [`design/peek/prototype.html`](../../design/peek/prototype.html). Open it in a browser. The bar at the
  top switches states, plays each transition, and toggles dark mode, Reduce Motion and 4x slow motion. In the live
  prototype the link in the mail opens a Peek, the card can be dragged down to dismiss, and Esc, Cmd-W, Cmd-O and
  Cmd-Z work.
- Screenshots: [`design/peek/screens/`](../../design/peek/screens/), light and dark, 2x, rendered headless with the
  project's Chromium build. The index is at the end of this document.
- Implementation issue: #313.

## Look

Peek is a second content card, not a new kind of window. It uses the content card's own shape: 10 pt continuous
corners, the `cardBorder` hairline, and the page drawn edge to edge. Two things set it apart from the card under it:
a deeper shadow, so it reads as lifted, and a scrim over the source card, so the source reads as set aside rather than
gone. The source card also recedes a little (scale 0.985). Its controls sit outside the card, in the gutter to the right
of its top corner, as three small circles. Nothing in Peek uses the brand accent; the page is the subject.

The one memorable moment is the open: the card grows out of the link you clicked and settles with a firm spring,
while the page behind it steps back. Every other transition is a continuation of that same physical object: it
shrinks back towards the link when closed, it is thrown down when dragged, it widens into the tab when expanded, and
it slides into the right-hand pane when split.

Typeface: the system font (SF Pro) throughout, as in every AppKit view in the shell. The prototype uses
`-apple-system`, which is the same face, so the screenshots match the app.

## When a Peek opens

| Trigger | Result | Rule |
|---|---|---|
| Click a link to another site in a pinned tab or a Favorite | Peek over that tab | BH-144, BH-048, BH-056 |
| Click a same-site link in a pinned tab or a Favorite | Navigates in place, no Peek | BH-056 |
| Shift-click any link in any tab | Peek over that tab | BH-145, GS-027 |
| Click a meeting link (Meet, Zoom, Teams) in a pinned tab | New Today tab, no Peek | BH-146 |
| An Air Traffic Control route matches the link | The route's destination wins | BH-147, BH-157 (#113) |
| Cmd-Shift-E with Gmail as a Favorite | Latest mail from the site in Peek | BH-153 (out of scope for the first build) |
| Today tabs, links without modifiers | Unaffected | BH-144 |

Settings (Settings > Links, final copy): "Open a Peek window when clicking on links to other sites" with the note
"Only affects Favorites and pinned tabs" (on by default), and "Open a Peek window when clicking on links with Shift
held" (on by default).

Popups (#123), decided by the maintainer on 2026-10-25:

- `window.open` with window features (sign-in, payment, share dialogs) opens a Little Arkt popup window, not a Peek.
  These pages need a real, separate window: they are sized by the opener, the opener keeps running behind them, and
  they usually close themselves. See [Little Arkt](little-arkt.md#popups).
- `window.open` without features and `target="_blank"` follow the normal tab rules, and therefore the Peek rules
  above when the opener is a pinned tab or a Favorite.
- A `window.open` popup from inside a Peek opens the same Little Arkt popup; the Peek stays open behind it.

## Layout

All values in points, on the shell's existing grid (`ShellMetrics.standard`: content card inset 10, corner radius 10).

| Element | Value | Token or source |
|---|---|---|
| Peek card | content card inset by 56 left and right, 34 top, 26 bottom | Arkt's value; PARITY(NEEDS-RUNTIME-CHECK RT-24, BH-154) |
| Peek card in a 1080 x 780 content card | 968 x 720 | |
| Minimum margin | 24 on every side; below a 600 pt wide content card the side insets shrink to 24 and the controls move inside the card's top-right corner | proposed |
| Corner radius | 10, continuous | `ShellMetrics.cardCornerRadius` |
| Hairline | 1 physical pixel | `ShellTokens.cardBorder` |
| Shadow | light: black 22 %, radius 24, y 18, plus black 10 %, radius 5, y 3; dark: black 55 % and 30 % | proposed `ShellTokens.peekShadow` |
| Scrim over the source card | light black 18 %, dark black 42 %, clipped to the source card | proposed `ShellTokens.peekScrim` |
| Source card scale while a Peek is open | 0.985 about its center | decided 2026-10-25 |
| Controls | three 28 pt circles, 8 apart, 12 right of the card's top-right corner, top-aligned with the card (outside the card) | decided 2026-10-25 |
| Control fill | light white 96 %, dark `#1C1C20` 96 %, hairline `cardBorder` | reuses `ShellTokens.toastSurface` |
| Control glyph | 14 pt, `secondaryText`; `primaryText` on hover | |
| Control order, top to bottom | Close, Open as Tab, Add to Split View | proposed; Arc lists expand, split, close (BH-148), PARITY(NEEDS-RUNTIME-CHECK) |
| Grabber | 36 x 5, radius 3, 12 above the card's top edge, centered, full opacity at rest; light black 50 % (3.6:1 over a white page under the light scrim, 4.0:1 over plain white), dark white 55 % (6.3:1 over a near-black page under the dark scrim); WCAG 1.4.11 asks 3:1 | proposed `ShellTokens.peekGrabber` |
| Keyboard focus ring | 2 pt, 2 pt outset | `BrandTokens.focusRing` |
| Toolbar inside Peek (when "Show Toolbar" is on) | the Toolbar strip (32 pt plus 1 pt hairline) at the top of the Peek card | `ContentToolbarView`, BH-151 |
| "Peek closed" toast | `ToastView`: 36 high, radius 18, 16 above the card bottom | `ShellTokens.toastSurface`, `toastText` |

New tokens this design adds (`ShellTokens`, `TokenPair`, light and dark): `peekScrim`, `peekShadow` (color plus
radius and offset), `peekGrabber`. The controls reuse `toastSurface`. No other new colors. `ShellTokensContrastTests`
gains a case for `peekGrabber`: at least 3:1 against white and against the dark page fill, each under `peekScrim`.

## States

| State | Prototype hash | Screenshot |
|---|---|---|
| Pinned tab, link hovered | `#s=idle` | `peek-idle-{light,dark}.png` |
| Peek open | `#s=open` | `peek-open-{light,dark}.png` |
| Control hovered, with tooltip | `#s=hover` | `peek-hover-{light,dark}.png` |
| Control focused from the keyboard | `#s=focus` | `peek-focus-{light,dark}.png` |
| Peek with the Toolbar | `#s=toolbar` | `peek-toolbar-{light,dark}.png` |
| Dragging down to dismiss | `#s=drag` | `peek-drag-{light,dark}.png` |
| Closed, with the reopen toast | `#s=closed` | `peek-closed-{light,dark}.png` |
| Opened as a Today tab | `#s=expanded` | `peek-expanded-{light,dark}.png` |
| Added to a Split View | `#s=split` | `peek-split-{light,dark}.png` |
| Peek inside a Split View, source pane 655 pt (1520 pt window) | `#s=insplitPeek` | `peek-insplitPeek-{light,dark}.png` |
| Peek inside a Split View, source pane 535 pt (under 600 pt) | `#s=insplitNarrow` | `peek-insplitNarrow-{light,dark}.png` |
| Split View already full | `#s=splitFull` | `peek-splitFull-{light,dark}.png` |

## Flows

### Open

1. The engine reports a link activation in a pinned tab or a Favorite (URL, source tab, modifiers, and the link's
   bounds in the tab's coordinates when Blink knows them). The shell decides: navigate in place, Peek, or new tab.
2. The shell creates a tab that is not in the sidebar (BH-152), mounts its `contentView(for:)` in a Peek overlay in
   the same window, above the content card, and starts loading.
3. The Peek card grows from the link and the source card recedes (motion below). The Peek's page gets keyboard focus.
4. The sidebar URL bar shows the Peek's URL while it is open; Copy URL (Cmd-Shift-C) and Copy URL as Markdown act on
   the Peek (KB-013, KB-014, BH-151).
5. Links inside the Peek navigate inside the Peek. Shift-click inside a Peek opens a new Today tab rather than a
   Peek on a Peek; there is only ever one Peek per source tab.

### Close

Five ways to close, all keeping the source tab as it was (BH-149): the Close control, a click on the scrim, Esc,
Cmd-W, and dragging the card down. After a close, a "Peek closed" toast with "Reopen" (Cmd-Z) shows for 4 seconds.
Cmd-Shift-T and Cmd-Z reopen it (BH-150, KB-079), with its history; a reopened Peek opens at the same place, without
the travel from the link.

How the history survives the close (decided on #346): just before the Peek's tab closes, the shell parks an engine
duplicate of it (`EngineClient.duplicateTab`, back and forward entries included) that is never shown. Chromium loads
a cloned tab only when it is first shown, so the parked copy plays no audio and runs no page; keeping the Peek's own
tab alive instead would keep its audio playing. Reopen shows the copy. Closed tabs and Peeks share one reopen stack
per window (20 entries [I]); Cmd-Z reopens only when no text is being edited, and only after the page passed on the
key. A reopen while the close still runs turns the card around where it is.

Esc goes to the page first (maintainer decision, 2026-10-25). If the page uses it (closes its own dialog, leaves full
screen, cancels a field), the Peek stays and the next Esc closes the Peek. An Esc the page does not use closes the
Peek at once. PARITY(NEEDS-RUNTIME-CHECK): Arc's order is not documented.

### Open as Tab (Cmd-O)

The Peek becomes a Today tab at the top of Today in the source tab's Space and is selected (BH-148, KB-076). The card
widens to the content card's frame; the Today rows below make room and the new row fades in, with the selection
moving to it. Its history comes with it. The source tab stays where it was in the sidebar.

### Add to Split View

The source tab and the Peek become a Split View: the source on the left, the Peek on the right, focus in the Peek
(BH-117, BH-148). Both cards slide into their panes together. The sidebar row becomes a split row. If the source tab
is already in a split with room, the Peek joins that split to the right of the source pane. If the split is full
(four panes, BH-116), the control is disabled and its tooltip reads "Split View is full".

### Drag to dismiss (GS-022)

The card follows the pointer vertically from anywhere on the grabber or the 12 pt band above the card, and from the
card's top 32 pt when the page there is not draggable content. While dragging down, the card scales towards 0.94 at
300 pt and the scrim fades towards 25 %; the controls and the grabber fade out within the first 60 pt. Dragging up
moves with resistance (offset to the power of 0.7). On release, a drag past 120 pt or a release velocity above
800 pt/s dismisses: the card continues with the release velocity and fades. Anything less springs back with a little
bounce, keeping the release velocity.

### Peek inside Split View

A Peek belongs to its source pane, not to the whole split. It covers the source pane only: the scrim and the recede
apply to that pane, the other panes stay live and clickable, and clicking another pane closes the Peek like a click
on the scrim. The card insets in a pane are 24 on the left, 34 top, 26 bottom and 52 on the right, which is the
control gutter. Below a 600 pt wide pane the Peek covers the whole content area instead, with the normal insets:
the scrim and the recede then apply to every pane, and a click on any pane closes the Peek. Decided 2026-10-25;
Arc's behavior is PARITY(NEEDS-RUNTIME-CHECK).

The prototype shows both sides of the threshold: `#s=insplitPeek` uses a 1520 pt window (content card 1320 pt,
panes 655 pt) with the Peek over the source pane only, and `#s=insplitNarrow` keeps the 1280 pt window (panes 535 pt)
with the Peek over the whole content area.

### Edge cases

- Switching tab or Space while a Peek is open: the Peek stays attached to its source tab, hidden with its live
  page (scroll, history and state kept), and comes back with the Open motion (Reduce Motion: the fade) when the tab
  is shown again. One hidden Peek per source tab; it has no row and is not in the tab switcher, the Archive or the
  saved session, and it does not survive quit (BH-152). A hidden Peek is not a closed one: nothing goes on the
  reopen stack until the user closes it. Decided on #348 (memory cost accepted). PARITY(NEEDS-RUNTIME-CHECK).
- The source tab closing or archived while its Peek is hidden closes the Peek too; Cmd-Shift-T brings both back
  together.
- Tab Handoff (#300) moving the source's page to another window closes its Peek, shown or hidden, in the window it
  was in, onto that window's reopen stack; the Peek does not move with the page.
- Window resize while a Peek is open: the Peek frame follows the layout directly, without animation.
- Sidebar hidden (Cmd-S): the content card is wider and Peek follows it; nothing else changes.
- Full screen video inside a Peek goes full screen from the Peek; leaving full screen returns to the Peek.
- A download started in a Peek goes to the normal Downloads; the Peek stays open.
- Closing the source tab closes its Peek with it, and both reopen together with Cmd-Shift-T.
- The source page navigating on its own (a redirect, a timer) does not close the Peek.
- Very small windows: below a 600 pt wide content card, the controls move inside the card's top-right corner, on the
  page, so the card can use the full width less 24 pt each side.
- Several quick link clicks: a second Peek request while one is opening replaces the URL in the same Peek; the open
  animation is not restarted.

## Motion

Every transition is a spring from `Motion/SpringPreset` on layer transform and opacity only. Sizes change through
the card's mask bounds (Core Animation, on the render server), never through the live view's frame: the page's view
keeps its old size during the motion, anchored at the top center, and is resized once, at rest. Where the card grows,
the plate behind the page (the page's background color) fills the new space. Springs are retargeted, never restarted:
an Esc during the open picks up the card's current position and velocity (prototype: Play > Interrupt).

| Transition | Card | Around it | Preset |
|---|---|---|---|
| Open | from 30 % of the way to the clicked link, scale 0.90, opacity 0, to its frame, scale 1, opacity 1 | scrim 0 to 1; source card scale 1 to 0.985; controls fade in and slide 10 pt from the card after 70 ms (`springyFast`); grabber after 110 ms | card and recede `firmSlow` (0.90, 0.35 s); opacity critically damped, 0.16 s |
| Close (control, scrim) | back towards the link, scale 0.92, opacity 0 | scrim out, source scale back to 1, controls out first; toast in after 140 ms (`springyFast`, from 8 pt below, scale 0.96) | `firm` (0.90, 0.25 s); opacity 0.12 s |
| Close (Esc, Cmd-W) | in place, scale 0.97, opacity 0 | as above | `firmFast` (0.95, 0.15 s): keyboard closes stay almost instant |
| Open as Tab | mask grows to the content card frame | scrim and controls out; Today rows move down 34 pt after 60 ms (`springyFast`); old selection fades; the new row and its selection fade in after 150 ms, row scale 0.96 to 1 (`springyFast`) | `firmSlow` |
| Add to Split View | Peek to the right pane, source card to the left pane, both through their masks | scrim and controls out; sidebar row crossfades to the split row after 40 ms | `firmSlow` |
| Drag | follows the pointer 1:1 | scrim, controls and grabber follow the drag distance | none while dragging |
| Fling (release past the threshold) | continues with the release velocity to 520 pt below, scale 0.90, opacity 0 | as Close | `firm`, initial velocity from the pointer |
| Snap back | back to its frame with the release velocity | scrim and controls back | `springy` (0.63, 0.28 s), the one place with a visible bounce |
| Reopen | from scale 0.96 and opacity 0 in place | as Open, no travel | `firm` |

Reduce Motion (`NSWorkspace.accessibilityDisplayShouldReduceMotion`): no scale, no travel, no recede.

| Transition | Reduce Motion |
|---|---|
| Open, Reopen | the card fades in at its frame (0.20 s); scrim fades in |
| Close, Esc, Fling | the card fades out (0.12 s) |
| Open as Tab, Add to Split View | the card fades out (0.12 s), takes its new frame while hidden, and fades in (0.20 s); sidebar changes fade |
| Drag | still follows the pointer (direct manipulation); release snaps back with `firm` and no bounce, or fades out |

Reduce Transparency: the scrim stays (it is not a blur); the controls take an opaque fill (`toolbarSurface`).

Keyframe screenshots (`peek-kf-<transition>-<ms>ms-<theme>.png`, `peek-rm-...` for Reduce Motion) freeze the same
spring simulation at the given time: open at 40, 90 and 160 ms; close at 50 and 110; Esc at 40 and 90; expand and
split at 60, 140 and 240; fling at 60 and 140; snap back at 80 and 200; reopen at 60; and Interrupt (open, then Esc
at 120 ms) at 150.

## Keyboard

| Key | Action | Rule |
|---|---|---|
| Esc | Goes to the page first; when the page uses it, the next Esc closes the Peek; otherwise it closes the Peek | KB-039, KB-078 |
| Cmd-W | Close the Peek | KB-078 |
| Cmd-O | Open as Tab | KB-076 |
| Cmd-Shift-T, Cmd-Z | Reopen the last closed Peek | KB-010, KB-011, KB-079 |
| Cmd-Shift-C, Cmd-Shift-Opt-C | Copy the Peek's URL, as Markdown | KB-013, KB-014 |
| Cmd-L | Edit the Peek's URL in the sidebar URL bar (or the Toolbar); Return navigates the Peek | proposed |
| Tab, Shift-Tab | Move through the page, then the three controls, then back to the page; focus never leaves the Peek while it is open | proposed |

Keyboard-initiated closes use the fastest preset and travel nowhere. The controls show the focus ring
(`BrandTokens.focusRing`) only for keyboard focus.

## VoiceOver

- The Peek is a modal group: role `AXGroup` with subrole dialog, label "Peek, <page title>". Opening it posts an
  announcement "Peek opened, <page title>" and moves VoiceOver focus to the web area.
- The source card is hidden from accessibility while the Peek is open; the sidebar stays reachable.
- Controls: "Close Peek" (help "Esc"), "Open as Tab" (help "Command-O"), "Add to Split View" (help "Adds this page
  next to <source title>"). When the split is full: "Add to Split View, dimmed", help "Split View is full".
- The drag gesture has an accessible equivalent: the Close control and the `AXCancel` action on the Peek group.
- Closing announces "Peek closed. Press Command-Z to reopen." and returns focus to the source page.
- The toast is a polite live region.

## Copy

| Where | Text |
|---|---|
| Close control | Close, tooltip "Close" with "Esc" |
| Expand control | Open as Tab, tooltip with "⌘O" |
| Split control | Add to Split View |
| Split control, split full | Split View is full |
| Toast after closing | Peek closed, action "Reopen" with "⌘Z" |
| Settings > Links | Open a Peek window when clicking on links to other sites |
| Settings > Links, note | Only affects Favorites and pinned tabs |
| Settings > Links | Open a Peek window when clicking on links with Shift held |
| VoiceOver | Peek, <title>; Peek opened, <title>; Peek closed. Press Command-Z to reopen. |

## Light and dark

Peek follows the Space theme's appearance like the rest of the chrome. Light screenshots use the Personal sample
theme, dark ones the Dev sample theme (both from `StubSidebar`). Dark mode drops the card shadow token
(`cardShadow` is clear) but keeps the Peek shadow, which is what separates the two cards over a dark page; the
`cardBorder` hairline is brighter in dark (white 20 %) and carries the edge.

## Parity notes

- Size, position and insets of the Peek are unpublished (BH-154): the values above are Arkt's.
  PARITY(NEEDS-RUNTIME-CHECK RT-24).
- The order and placement of the controls: Arc documents expand, Split and close at the top right (BH-148); whether
  they sit inside or outside the card is not documented. PARITY(NEEDS-RUNTIME-CHECK).
- Esc ordering against the page, Peek behavior across tab and Space switches, and Peek inside a Split View are not
  documented. PARITY(NEEDS-RUNTIME-CHECK).
- The scrim, the recede, the travel from the link and the drag thresholds are Arkt design choices, not measured
  from Arc.
- Easels (links in Easels open in Peek, OS-03) are out of scope.

## Implementation notes

- The Peek is a tab container in the existing `ShellWindowController`, not an engine window: `createTab(url:in:)`
  plus `contentView(for:)` mounted in a `PeekOverlayView` above `ContentCardView` (or above the source pane's card in
  a split). A sidebar-less tab needs the sidebar model to accept a tab that is not in any section until it is opened
  as a tab.
- Missing engine piece: a link activation hook. The engine reports a user link activation (URL, source tab,
  modifiers, disposition, link bounds) before navigating, and the shell answers navigate, Peek or new tab. Without
  it, only Shift-click through a context-menu style path is possible.
- Motion runs on Core Animation: `CASpringAnimation` through `SpringAnimationFactory` for transform and opacity, and
  the mask layer's bounds for size changes. `SpringDriver` drives the drag release so the release velocity carries
  into the spring.
- Opening as a tab moves no web contents: the same tab joins the sidebar. Split moves it into a `SplitContainerView`
  pane.

## Decisions (maintainer, 2026-10-25)

1. Popups (#123): `window.open` with window features and extension popup windows open in a Little Arkt popup window;
   Peek is only for link clicks. Accepted.
2. Peek inside a Split View covers only the source pane, and the whole content area below a 600 pt wide pane.
   Accepted.
3. Peek's controls sit outside the card, in the right gutter. Accepted.
4. The source card recedes to 0.985 under a Peek. Accepted.
5. Esc goes to the page first; when the page uses it, the second Esc closes the Peek. Accepted.

No open questions remain for Peek. Parity checks still open: RT-24 (size and insets), control placement in Arc, Esc
order in Arc, Peek across tab and Space switches.

## Screenshot index

All in `design/peek/screens/`, 2640 x 1680 (1320 x 840 pt at 2x; `peek-insplitPeek` is 3120 x 1680 for the wider
window), quantized to 256 colors to stay under 400 KB.

States, light and dark: `peek-idle`, `peek-open`, `peek-hover`, `peek-focus`, `peek-toolbar`, `peek-drag`,
`peek-closed`, `peek-expanded`, `peek-split`, `peek-insplitPeek`, `peek-insplitNarrow`, `peek-splitFull`.

Motion keyframes, light and dark: `peek-kf-open-{40,90,160}ms`, `peek-kf-close-{50,110}ms`, `peek-kf-esc-{40,90}ms`,
`peek-kf-expand-{60,140,240}ms`, `peek-kf-split-{60,140,240}ms`, `peek-kf-fling-{60,140}ms`,
`peek-kf-snapback-{80,200}ms`, `peek-kf-reopen-60ms`, `peek-kf-interrupt-150ms`.

Reduce Motion keyframes, light and dark: `peek-rm-open-100ms`, `peek-rm-expand-{90,220}ms`, `peek-rm-close-80ms`.
