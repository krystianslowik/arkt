# Little Arkt

Design for Little Arkt (#28), part of the design-first pass in #304. Little Arkt is a small window for links that come
from other apps and for the quick lookup hotkey. It has no sidebar and one job: show the page, then either close it or
move it into a Space with "Open in". Popup windows from pages and extensions use the same window (#123).

- Prototype: [`design/little-arkt/prototype.html`](../../design/little-arkt/prototype.html). The bar at the top
  switches states, plays each transition, and toggles dark mode, Reduce Motion and 4x slow motion. In the live
  prototype, the link preview in the chat window opens a Little Arkt window (or nudges the existing one), "Open in
  Personal" promotes it, the chevron opens the Space chooser, and Cmd-O, Cmd-Opt-O and Cmd-W work.
- Screenshots: [`design/little-arkt/screens/`](../../design/little-arkt/screens/), light and dark, 2x, rendered
  headless with the project's Chromium build. The index is at the end of this document.
- Implementation issue: #314.

## Look

A Little Arkt window is a small, quiet frame around a content card. It belongs to no Space yet, so it does not wear a
Space theme: its frame is the brand surface (`BrandTokens.surfaceBrand`: porcelain in light, graphite in dark), and
it follows the system appearance. Inside, the page sits in the same card as the main window (10 pt corners,
`cardBorder` hairline).

The top bar holds the traffic lights, the page's host, a Copy Link button and one primary action: "Open in
<Space>", a split button in the brand accent with graphite text (`BrandTokens.accent` and `onAccent`). It is the only
mustard fill on the surface and the only place the brand color carries an action, which is the point: the window's
one action is the one you can see from across the screen. Its small swatch shows the target Space's gradient, so the
button also says where the page is going.

The memorable moment is the promotion. "Open in Personal" lifts the page out of the small window and flies it, as one
object, into the main window's content card, where its Today row is waiting. The small frame fades away underneath
it; nothing is reloaded and nothing blinks.

Typeface: the system font (SF Pro), as everywhere in the shell.

## When a Little Arkt window opens

| Trigger | Result | Rule |
|---|---|---|
| A link opened from another app, with Little Arkt as the default destination and no matching route | New Little Arkt window | BH-129, BH-156 |
| A route matches the link | The route's destination wins | BH-140 (#113) |
| The same link again while its window is open | That window comes forward and nudges; no duplicate | BH-134 |
| Another link while one is open | A second window, cascaded | BH-133 |
| Cmd-Opt-N anywhere (global hotkey, off by default, turned on in Settings) | Quick lookup bar on the current desktop, above full-screen apps; Return opens the result in a new Little Arkt window | BH-130, KB-045 |
| Cmd-Opt-N with Arkt frontmost | Same, from the File menu ("New Little Arkt Window") | KB-044 |
| Opt-Cmd-click a link (when enabled) | Little Arkt window | BH-132, GS-028 |
| Opt-Cmd-click a sidebar tab (when enabled) | That tab moves into a Little Arkt window | BH-132 |
| `window.open` with features, extension popup windows | Little Arkt popup (below) | #123, decided 2026-10-25 |

Settings (Settings > Links, final copy): "Links from other apps open in Little Arkt" (on), "Open Little Arkt when I
press ⌥⌘N" (off by default, decided 2026-10-25; the user opts in, BH-131), "Open Little Arkt when clicking on links with ⌥⌘ held" (on in
Arkt: it only reacts to a deliberate two-modifier click and costs nothing when unused; Arc's default is unknown,
see Parity notes). Settings > Profiles: "Archive Little Arkts after:" with the same choices as "Archive tabs after", default
6 hours (BH-137).

## Layout

| Element | Value | Token or source |
|---|---|---|
| Window | 480 x 620 pt, borderless (full-size content view, hidden title bar), standard window shadow, radius 12 | decided 2026-10-25 until RT-23 is measured; PARITY(NEEDS-RUNTIME-CHECK RT-23, BH-143) |
| First position | top-right of the current screen's visible frame, 24 pt from the right edge and 20 below the menu bar | decided 2026-10-25 |
| Further windows | each 28 pt left and 28 pt down from the frontmost Little Arkt window; wraps back to the first position when it would leave the visible frame | decided 2026-10-25 |
| Size after a resize | the last size the user set is used for new windows | BH-142 |
| Minimum size | 360 x 400 | proposed |
| Frame | 6 pt around the card on the left, right and bottom | proposed |
| Frame color | light `#FAF9F5`, dark `#202321` | `BrandTokens.surfaceBrand` |
| Top bar | 40 pt, traffic lights at x 12, centered vertically | |
| Host label | from x 80, 13 pt: lock glyph, then the host in `primaryText` semibold; the full URL in the tooltip | |
| Copy Link | 26 pt icon button, `sidebarForeground`, hover fill `sidebarItemBackground` | |
| Open in split button | 26 pt high, radius 8, 8 pt from the right edge; label 12 pt semibold; 10 pt Space swatch; chevron segment after a 1 pt divider (graphite 18 %) | `BrandTokens.accent`, `accentHighlight` (hover), `accentPressed`, `onAccent`; focus ring `BrandTokens.focusRing` |
| Card | 10 pt continuous corners, hairline | `ShellMetrics.cardCornerRadius`, `ShellTokens.cardBorder`, `cardShadow` |
| Inactive window | traffic lights gray; nothing else dims | system behavior |
| Quick lookup bar | the command bar panel: 766 pt wide (narrower on small screens), 60 pt input, 50 pt rows, radius 12, at 34 % of the screen height; a "Little Arkt" tag before the input | `CommandBarGeometry`, `ShellTokens.commandBar*`; tag uses `accent` and `onAccent` |

New tokens: none. The window shadow is the system's. `surfaceBrand` gains a second use (it was for About and first
run).

## States

| State | Prototype hash | Screenshot |
|---|---|---|
| Window open over another app | `#s=idle` | `la-idle-{light,dark}.png` |
| Open in hovered and pressed, tooltip | `#s=hover` | `la-hover-{light,dark}.png` |
| Space chooser (Cmd-Opt-O) | `#s=chooser` | `la-chooser-{light,dark}.png` |
| Profile confirmation | `#s=profile` | `la-profile-{light,dark}.png` |
| Quick lookup bar (Cmd-Opt-N) | `#s=lookup` | `la-lookup-{light,dark}.png` |
| Three windows | `#s=multiple` | `la-multiple-{light,dark}.png` |
| Popup from a page | `#s=popup` | `la-popup-{light,dark}.png` |
| Dock menu | `#s=dock` | `la-dock-{light,dark}.png` |
| After Open in Personal | `#s=promoted` | `la-promoted-{light,dark}.png` |

## Flows

### Open from another app

1. macOS hands Arkt the URL (#135). Air Traffic Control checks the routes (#113); with no match and Little Arkt as the
   default destination, the shell opens a Little Arkt window.
2. If a Little Arkt window already shows this exact URL, it comes forward and nudges instead (BH-134).
3. The profile is the one last chosen for this domain in Little Arkt, else the default profile (BH-135).
4. The window appears without taking over the screen: it becomes key so the page can be read and scrolled at once,
   but the main window does not come forward.

### Open in (Cmd-O, Cmd-Opt-O)

- "Open in <Space>" (Cmd-O) moves the page into the most recently used Space of the frontmost main window, as a new
  Today tab at the top of Today, selected (BH-136, KB-076). The button's label always names that Space.
- The chevron (Cmd-Opt-O) opens the Space chooser, a native menu: "Open in" then every Space with its theme swatch
  (the default one with "⌘O"), then "Open in New Window", then "Copy Link". KB-077 is Cmd-Opt-O here;
  Cmd-Shift-O is the older documented key (CF-13), PARITY(NEEDS-RUNTIME-CHECK RT-07).
- If the target Space uses a different profile, a sheet asks first: "Open in Work?" (below). "Don't ask again"
  skips it from then on (`shouldBypassConfirmLittleBrowserProfileDialog`).
- The tab moves with its history, scroll position and page state: the web contents move between windows, nothing
  reloads, unless the profile changes, in which case the page reloads in the target profile.
- If no main window is open, one opens on the target Space first.
- If the main window is minimized, in another desktop or in full screen, the page moves without the flight; the
  Little Arkt window fades out and macOS brings the main window forward the usual way.

### Close and archive

- Cmd-W or the red light closes the window; the page goes to the Archive under the Little Arkt filter (BH-138,
  KB-080, BH-088).
- A Little Arkt window idle for the "Archive Little Arkts after:" time (6 hours by default) closes and is archived
  the same way (BH-137).
- Cmd-Shift-T in Arkt reopens the last closed Little Arkt window at its last frame.

### Several windows

Every link from another app gets its own window (BH-133). They cascade from the top-right, 28 pt at a time; the
frontmost is the only key one. The Dock menu lists them by page title, then "Hide All Little Arkt Windows" (or
"Show All Little Arkt Windows" when hidden) and "Close Little Arkt Windows" (BH-139, GS-041). The Window menu lists
them under their own heading.

### Quick lookup (Cmd-Opt-N)

The command bar opens on the current desktop, over full-screen apps, with the "Little Arkt" tag before the field.
It works like the main command bar (search, URLs, open tabs as suggestions). Return opens the result in a new Little
Arkt window and the bar closes; Esc closes it with nothing opened. The bar itself has no open or close animation:
it is a keyboard action used many times a day.

### Popups

Decided for #123 (maintainer, 2026-10-25). A page's `window.open` with window features, and an extension's
`chrome.windows.create({type: "popup"})`, open in a Little Arkt popup:

- the size and position the page asked for (clamped to the screen and the minimum size), else centered over the
  opener window;
- the same frame and top bar, with the host and lock; "Open as Tab" uses the quiet style (no accent fill), because
  the expected path is to finish the sign-in or payment and let the page close the window;
- the opener stays live and keeps its reference to the popup; when the page calls `window.close()`, the popup fades
  out (0.12 s);
- not archived when closed by the page; archived like any Little Arkt window when the user closes it.

### Edge cases

- Links from other apps while Arkt is not running: Arkt launches without restoring the main windows to the front;
  the Little Arkt window is the first thing on screen.
- The global hotkey taken by another app: Settings shows "⌥⌘N is used by another app." under the setting, and the
  in-app menu item still works.
- A Little Arkt window on a second display: it opens on the display with the pointer; the promotion flies to the main
  window's display only if it is visible there, else it uses the no-flight path above.
- Extensions, Capture and full-screen video work in Little Arkt (BH-141): the extensions menu is in the window's
  context menu; full-screen video leaves the small window and returns to it.
- Very long hosts truncate in the middle; the full URL is in the tooltip and in Cmd-L.
- Dragging the window: anywhere on the top bar and the frame.

## Motion

Springs from `Motion/SpringPreset`, on layer transform and opacity only. The window itself never animates its frame:
appear and close animate the root layer of the window's content (with the window's own shadow off and a layer shadow
in its place during the motion).

The promotion never moves the live page mid-flight. At the start, the shell takes a snapshot of the page (an image
of the tab's current frame from the engine) and puts it in a `CALayer` on a transparent, click-through overlay window
that spans both windows; that layer is what flies, with its position and mask bounds animated. Meanwhile the live
tab stays where it is, hidden. When the flight settles, the tab moves between engine windows once, its view is
mounted in the main window's content card at the final size, and after its first frame there the snapshot layer and
the overlay window are removed (a 0.1 s crossfade covers any difference). If the snapshot is not ready within one
frame, the flight starts with the card's plate (page background color) and the snapshot fades in on it.

| Transition | What moves | Preset |
|---|---|---|
| Appear | window content from 10 pt higher and scale 0.94 (anchored at the top center) to its place, opacity 0 to 1 | `firm` (0.90, 0.25 s); opacity critically damped 0.16 s |
| Same link again (nudge) | window scale kicked by +0.45/s and settling back at 1, a 1 to 2 % swell | `springy` (0.63, 0.28 s) |
| Open in Space | the card lifts out at its current frame, then its position and mask move to the main window's content card; the small window's frame fades out at once (0.12 s); the main window comes forward at the start; after 200 ms the Today rows make room (`springyFast`) and the old selection fades; 90 ms later the new row and its selection fade in (`springyFast`, scale 0.96 to 1) | card `firmSlow` (0.90, 0.35 s) |
| Close (Cmd-W, red light) | scale 0.97 in place, opacity 0 | `firmFast` (0.95, 0.15 s) |
| Quick lookup bar | none, it is keyboard-initiated | |
| Space chooser, profile sheet | native menu and sheet, system motion | |

The flight starts from wherever the window is: Open in during the appear picks up the card's current scale and
opacity (prototype: Play > Interrupt). In the prototype the lifted card stands in for the snapshot layer.

Reduce Motion:

| Transition | Reduce Motion |
|---|---|
| Appear | fade in at its place (0.20 s) |
| Nudge | the frame dips to 60 % and fades back (0.20 s), no scale |
| Open in Space | the card fades out in the small window (0.12 s), the small window closes, and the page fades in in the main window's card (0.20 s); the sidebar changes fade |
| Close | fade out (0.12 s) |

Keyframe screenshots (`la-kf-<transition>-<ms>ms-<theme>.png`, `la-rm-...` for Reduce Motion): appear at 40, 90 and
160 ms; Open in Space at 80, 160, 260 and 400; nudge at 60 and 140; close at 60; Interrupt at 220.

## Keyboard

| Key | Action | Rule |
|---|---|---|
| Cmd-O | Open in the most recent Space | KB-076 |
| Cmd-Opt-O | Choose a Space | KB-077, PARITY(NEEDS-RUNTIME-CHECK RT-07) |
| Cmd-W | Close and archive | KB-080 |
| Cmd-Opt-N | Quick lookup: in-app always; system-wide only after the user turns it on in Settings (off by default) | KB-044, KB-045 |
| Cmd-L | Edit the URL in the top bar; Return navigates | proposed |
| Cmd-Shift-C, Cmd-Shift-Opt-C | Copy the URL, as Markdown | KB-013, KB-014 |
| Cmd-[ and Cmd-], Cmd-R | Back, forward, reload | standard |
| Tab | Page, then Copy Link, Open in, the chooser, back to the page | proposed |

## VoiceOver

- Window title: the page title; the window's accessibility description "Little Arkt". VoiceOver reads "Three days in
  Lisbon, Little Arkt, window".
- Top bar: "atlas.example, secure" (static text, the full URL as help), "Copy Link" button, "Open in Personal" button
  (help "Command-O. Moves this page to the Personal Space."), "Choose a Space" menu button (help
  "Command-Option-O").
- After Open in: announce "Opened in Personal" and move focus to the page in the main window.
- Profile sheet: a standard alert, read by the system.
- Quick lookup bar: the command bar's existing accessibility, with the field labeled "Little Arkt: Search or Enter URL".

## Copy

| Where | Text |
|---|---|
| Primary button | Open in <Space name> |
| Primary button, popup | Open as Tab |
| Chooser button | Choose a Space (accessibility label; the button shows a chevron) |
| Chooser menu | Open in; <Space names>; Open in New Window; Copy Link |
| Profile sheet title | Open in <Space>? |
| Profile sheet message | <Space> uses the <Profile> profile. The page reloads there, with the <Profile> profile's sign-ins and cookies. |
| Profile sheet | Don't ask again; Cancel; Open in <Space> |
| Quick lookup tag and placeholder | Little Arkt; Search or Enter URL... |
| Dock menu | <page titles>; Hide All Little Arkt Windows / Show All Little Arkt Windows; Close Little Arkt Windows; New Window; New Little Arkt Window |
| File menu | New Little Arkt Window (⌥⌘N) |
| Settings > Links | Links from other apps open in Little Arkt; Open Little Arkt when I press ⌥⌘N; Open Little Arkt when clicking on links with ⌥⌘ held |
| Settings > Profiles | Archive Little Arkts after: |
| Archive filter | Little Arkt |
| Hotkey conflict | ⌥⌘N is used by another app. |

## Light and dark

The window follows the system appearance (it has no Space). Light: porcelain frame, white page card with `cardShadow`.
Dark: graphite frame, the brighter `cardBorder` hairline, no card shadow. The Open in button is the same mustard with
graphite text in both, at about 8.4:1 contrast for the label. In the promoted state, the main window wears its Space theme
as usual (Personal sample theme in light, Dev in dark).

## Parity notes

- Default size and position are unknown (BH-143). PARITY(NEEDS-RUNTIME-CHECK RT-23). Arkt uses 480 x 620 at the
  top-right until RT-23 is measured.
- Arc's hotkey default is unknown (BH-131), PARITY(NEEDS-RUNTIME-CHECK RT-23). Arkt ships it off; this is a product
  decision, not a parity claim.
- KB-077 key, Cmd-Opt-O or Cmd-Shift-O (CF-13). PARITY(NEEDS-RUNTIME-CHECK RT-07).
- Arc's default for Opt-Cmd-click into Little Arc (`optionCommandClickLittleArcEntryPointEnabled`) is unknown.
  PARITY(NEEDS-RUNTIME-CHECK, add to RT-23). Arkt ships it on until that is checked.
- The Space chooser's contents beyond the Space list, the profile sheet's wording and the popup behavior are Arkt's.
- The neutral brand frame, the accent Open in button and the flight into the main window are Arkt design choices.

## Implementation notes

- A Little Arkt window is a second `EngineWindowHosting` implementation (`LittleArktWindowController`), chosen in
  `ShellWindowSet.host(for:)` by request kind and destination: `.startupURL` when the link route resolves to Little
  Arkt, and `.page` / `.extension` popups once the engine reports them as such (today a page's new window arrives as
  `.reopen`, week-3 W3-4).
- Missing engine pieces: an image snapshot of a tab's current frame (for the Open in flight; Chromium can copy it
  from the compositor surface); moving a tab between engine windows once, at the end of the flight, without a
  reload; reporting `.page`
  window requests with the opener and the requested bounds; letting the shell close a popup when its page calls
  `window.close()` (already a window close event).
- Missing shell pieces: open-URL events and default-browser registration (#135); link routing (#113) for the
  destination; a global hotkey (`RegisterEventHotKey`, no Accessibility permission needed); the Archive's Little Arkt
  source and its threshold in auto-archive.

## Decisions (maintainer, 2026-10-25)

1. Frame: the neutral brand surface (`BrandTokens.surfaceBrand`), not a Space theme. Accepted.
2. The mustard "Open in <Space>" split button stays. Accepted.
3. Popups (#123): `window.open` with window features and extension popup windows open in a Little Arkt popup window;
   Peek is only for link clicks. Accepted.
4. Default window 480 x 620 at the top-right, cascading 28 pt, until RT-23 is measured. Accepted.
5. The global Cmd-Opt-N hotkey is off by default. The user turns it on in Settings > Links ("Open Little Arkt when I
   press ⌥⌘N"), laid out as in the Settings window design. The in-app File menu item works either way.

No open questions remain for Little Arkt. Parity checks still open: RT-23 (size, position, the hotkey default and the
Opt-Cmd-click default in Arc) and RT-07 (KB-077 key). Arkt's own Opt-Cmd-click default (on) is a design call, not a
maintainer decision; flag it if it should be off.

## Screenshot index

All in `design/little-arkt/screens/`, 2880 x 1800 (1440 x 900 pt, one screen, at 2x), quantized to 256 colors to stay
under 400 KB.

States, light and dark: `la-idle`, `la-hover`, `la-chooser`, `la-profile`, `la-lookup`, `la-multiple`, `la-popup`,
`la-dock`, `la-promoted`.

Motion keyframes, light and dark: `la-kf-appear-{40,90,160}ms`, `la-kf-promote-{80,160,260,400}ms`,
`la-kf-nudge-{60,140}ms`, `la-kf-close-60ms`, `la-kf-interrupt-220ms`.

Reduce Motion keyframes, light and dark: `la-rm-appear-100ms`, `la-rm-promote-{80,240}ms`.
