# Extensions design

The spec picks **direction C** for pinned actions: one Extensions button opens a panel. It picks **direction B**
for the install sheet (#590). The existing engine-drawn install sheet (#244, #548) is close enough; no restyle is
needed. New extensions are unpinned and the install toast offers Pin. Extension shortcuts work in Arkt by default,
with a per-command opt-in to All Apps. On conflict, Return keeps the existing shortcut and leaves the extension
command unassigned.

The [prototype](prototype.html) contains the chosen states and historical alternatives; use `#c-pinned`,
`#c-reorder`, `#b-install`, and `#b-install-long` for the chosen directions. The other states are `#menu`,
`#menu-unpinned`, `#shortcuts`, `#shortcuts-conflict`, `#shortcuts-record`, `#toast-pin`,
`#c-<empty|none-pinned|small>` and `#surf-<crashed|dialog|restore|pageinfo|zoom|sharing>`. Append `&dark`,
`&rm`, or `&shot` for dark, Reduce Motion, or screenshot mode. The [direction comparison](directions/README.md)
is historical, not a specification.

Everyday chrome: the system font, the shell's tokens, neutral pills. Mustard is a fill and the one primary pill of a
surface (Add Extension, Reload, OK, Restore, Keep Existing). Extension icons and names are synthetic. Pinned actions
carry no mustard: a badge is a graphite capsule with porcelain text, "needs attention" is a graphite dot.

## Extensions panel

The 28 pt Extensions button at the trailing end of the bottom bar opens a 316 pt panel. Pinned extensions appear as
rows with a status line; drag a row by its grip to reorder it, with a 2 pt insertion line. All actions remain in the
panel, including when the window is small. The [approved states](#approved-states-590) specify the empty, unpinned,
and smallest-window cases.

## The install sheet

Direction B is a 460 pt window sheet with a 52 pt icon, rating, user count, size, and permission rows with plain
explanations. Its proposed sidebar switch is omitted under C. The existing Chromium sheet is accepted as close enough.

- **Content**: icon, "Add "<name>"?", publisher, "4.6 stars, 1,000,000+ users", the permission list (the strings
  Chromium reports, one per line, plain), Open in Web Store (a quiet link), Cancel, **Add Extension** (the one primary,
  Return). Esc cancels. The sheet attaches to the window; it never blocks other windows.
- **Worst case**: an 85-character name wraps to two lines and ends with an ellipsis; a 50-character publisher
  truncates; six permissions scroll inside the field (150 pt max, faded edge); the buttons never move.
- **After Add**: a toast on the window, "<name> added", with one quiet action, "Pin": new extensions are not pinned
  (#590). This replaces Chromium's "has been added to Chromium. Manage your extensions by clicking
  Extensions in the Window menu." (#121 comment, W3-9): the name and the Window-menu wording are gone from the product.
- **Remove**: the existing sheet in `design/alerts-sheets-toasts` ("Remove "<name>"?", Report abuse, Remove).
- **Policy and errors**: a blocked or unsupported extension shows the alert style from the same system, one answer.

## Pinned actions

- **What pins**: extensions with an action. A new extension is not pinned (#590); pin it from the install toast or its row in the Extensions panel (B's "Show in
  sidebar" switch is not used under C). A
  profile syncs the order with the Space's profile.
- **Order**: the panel rows follow pin order. Drag the grip to reorder. The menu has Move Left and
  Move Right for the keyboard (disabled at the ends). Cmd-E cycles the pinned extensions in this order (KB-047: hold
  Command, tap E; each tap opens the next one's popup; release Command to leave it open).
- **Click**: opens the extension's popup anchored under the panel row. A badge updates live.
  Right-click or Ctrl-click opens the context menu.
- **Smallest window**: the sidebar's width never changes; the panel caps its height to the window and its list scrolls.

## The context menu

A native `NSMenu`, drawn by AppKit like the tab menus (`design/tab-context-menus`); the design fixes the items.

| Item | Enabled | Notes |
|---|---|---|
| (extension name) | disabled header | |
| Options... | extension has an options page | opens it in a tab |
| Unpin from Sidebar / Pin to Sidebar | always | the title follows the state |
| Move Left, Move Right | pinned only; each disabled at its end | |
| This Can Read and Change Site Data > | extension has host permissions | submenu: When You Click the Extension, On <host>, On All Sites (one checked) |
| Manage Extension... | always | opens its entry in Settings, Extensions |
| Remove from Arkt... | always | opens the remove sheet |

## Keyboard commands (`chrome.commands`)

Settings, Shortcuts, in the existing "Extension Shortcuts" section (BH-202); the search accepts a name or a shortcut. The
section's first row is "Cycle through pinned extensions", Cmd-E. Each extension is a group: its name with a small
icon, then one row per command: title, its description, the shortcut as keycaps, and a scope pop-up ("In Arkt" or "All
Apps" for global commands). An unset command shows a Set Shortcut pill. Clicking the keycaps records (the field takes
the system focus ring and reads "Press new shortcut"). A conflict uses the Settings pane's row-shaped notice: a neutral
exclamation, "Cmd-Shift-E is already used by "Reopen Closed Tab"", **Keep Existing** (the one primary, the default:
Return keeps the existing shortcut, #590) and a quiet **Use Cmd-Shift-E**. Kept, the extension's command stays
unassigned until the user sets it in Settings, Shortcuts. Esc cancels recording; Delete clears. A shortcut set here
survives updates to the extension.

## The other Views surfaces (#122)

| Surface (#122) | Decision | Designed here |
|---|---|---|
| Crashed tab (sad tab) with Reload | native view in the card | `surf-crashed`: 52 pt tile, "This page quit unexpectedly", Reload (primary), Close Tab quiet. A GPU process crash keeps the window up and reloads the tab |
| JavaScript alert, confirm, prompt, beforeunload | tab-modal panel attached to the card's top edge (not the window), the page dims | `surf-dialog`: "<host> says", message, a field for prompt, "Prevent this page from creating more dialogs", Cancel, OK. beforeunload: Stay is primary, Leave neutral |
| Session-crashed "Restore pages?" bubble | small panel, top trailing | `surf-restore`: Restore (primary), Dismiss. Not an infobar |
| Page info | panel anchored below the address pill | `surf-pageinfo`: host, "Connection is secure", Cookies and site data, a pop-up per permission, Reset Permissions, Site Settings... |
| Zoom bubble | pill at the card's top trailing corner, like the find pill | `surf-zoom`: minus, 125 %, plus, Reset; closes after 2 s without the pointer |
| Tab sharing infobar (own Views) | an infobar row, same style as the confirm infobars | `surf-sharing`: "<host> is sharing the contents of this tab", Stop Sharing |
| Dialog and panel anchoring over infobars | rule: panels sit below the infobar rows, never over them | rule only |
| Infobars in HTML fullscreen | hidden, as Chrome's `ShouldHideInFullscreen` | rule only |
| File chooser | the system open panel as a sheet on the window; no design needed | no |
| Page context menu | native `NSMenu` (items from the engine; #121 comment) | no |
| Sign-in QR code infobar | known gap, recorded with a no-crash check | no |
| Docked DevTools | known gap this release (undocked works) | no |
| Autofill and payments bubbles | known gap with a no-crash check on `GetAutofillBubbleHandler()` callers | no |
| Translate | none on desktop (bubble, no Arkt case) | no |

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Install sheet | AppKit's sheet slide (the prototype imitates it, 0.30 s) | opacity only, 0.20 s |
| Panels, popups, page info, dialog | opacity 0 to 1 and scale 0.97 to 1 with translateY -4 to 0, 0.22 s on `firmFast` `cubic-bezier(0.2, 1, 0.4, 1)` | opacity only, 0.15 s |
| Reorder | the lifted icon scales to 1.12 and rises 4 pt; neighbours move 0.20 s on `firm`; drop settles 0.18 s | the neighbours jump, no scale |
| Badge change | none (a count is information, not an event) | same |
| Press | scale 0.94 (icon), 0.97 (pill), 0.12 s | none |

Transform and opacity only.

## VoiceOver and accessibility

- Move Left and Move Right in the menu are the keyboard route for ordering; dragging is never the only way.
- The panel is a dialog "Extensions": a list; each row's pin button is a toggle ("Pin <name>", pressed when pinned).
- The install sheet and the page dialogs are alert dialogs: title, then description, then the default button. Permission
  rows read as a list. Focus starts on the default button (a prompt's field takes focus first).
- The sad-tab view is an alert; Reload takes focus.
- The shortcut recorder announces "Recording, press the new shortcut"; a conflict announces its text.
- No contrast values are shown; the dot and badge are never the only signal (the label says it).

## Light and dark

Light: porcelain panels, white page. Dark: graphite `#202321`. Extension icon tiles keep their own colors with white
letters in both. The menu uses the system's menu material. Increase Contrast adds a 1 pt edge to the panel rows.

## Open questions for the maintainer

1. ~~Which direction for pinned actions and for the install sheet?~~ Answered: C for pinned actions, B for install.
2. ~~Are new extensions pinned by default?~~ Answered 2026-11-05: no; the toast offers Pin.
3. Does Cmd-E ship (KB-047) or stay deferred? The design is ready either way.
4. ~~Should "Keep Existing" be the default on a shortcut conflict?~~ Answered 2026-11-06 (#590): yes. Return keeps the
   existing shortcut; Use is the secondary (`shortcuts-conflict`).
5. Docked DevTools: confirm it is a known gap for the first release.
6. ~~Global (All Apps) extension shortcuts?~~ Answered (#590): the Chrome model, In Arkt by default, each shortcut can
   opt in to All Apps (`shortcuts-record`).

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network, synthetic data |
| `screens/extensions-<state>-<light\|dark>.png` | 54 screenshots at 2x (27 light, 27 dark; 1080 x 720 window): `a-`, `b-`, `c-` pinned, reorder, install, install-long; `c-empty`, `c-none-pinned`, `c-small`; menu, menu-unpinned, shortcuts, shortcuts-conflict, shortcuts-record, toast-pin; surf-crashed, surf-dialog, surf-restore, surf-pageinfo, surf-zoom, surf-sharing |

## Approved states (#590)

The approved additional states are in the prototype and screens:
`screens/extensions-<state>-<light|dark>.png`, 10 files at 2x.

| State | What it shows |
|---|---|
| `c-empty` | zero extensions: puzzle tile, "No extensions yet", one line, **Browse the Web Store** (the panel's one primary), Manage Extensions... |
| `c-none-pinned` | extensions installed, none pinned: the Pinned group shows a hint row (pin the ones you use most; Cmd-E opens each in turn); all six under Not pinned |
| `c-small` | smallest window (640 x 420, 150 pt sidebar): the panel caps its height to the window, the list scrolls with a faded edge, the footer stays ("Manage..." plus Cmd-E) |
| `toast-pin` | after Add Extension in the B sheet: "“Quiet Reader” added" with **Pin** (a quiet action). New extensions are not pinned |
| `shortcuts-record` | the shortcut recorder (the field shows the keys pressed so far) and the row's scope pop-up open: In Arkt (checked) and All Apps, each with a one-line explanation. Scope is per shortcut |

Notes:
- The conflict notice from `shortcuts-conflict` applies unchanged to All Apps shortcuts; shortcuts macOS reserves are
  rejected in the recorder ("Some shortcuts are taken by macOS").
- Under C there are no sidebar icons, so B's "Show in sidebar" switch is not used; Pin from the toast or the panel row
  pins an extension in the Extensions panel.

### Answered questions (2026-11-05)

1. Pin new extensions on install by default? **No.** The toast offers Pin (`toast-pin`). This replaces "The default
   for a new extension is pinned" under Pinned actions and question 2 above.
2. Is the shipped engine-drawn install sheet (#244, #548) close enough to B? **Yes**, no restyle issue.

### Answered questions (2026-11-06)

1. Default button on a shortcut conflict? **Keep Existing** (Return); Use is the secondary. The extension's command
   stays unassigned until the user sets it in Settings, Shortcuts. `shortcuts-conflict` is redrawn that way.
