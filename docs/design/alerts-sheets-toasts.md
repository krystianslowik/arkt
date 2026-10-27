# Alerts, sheets and toasts design

Design issue: #306 (part of #304). Implementation issue: #308.
Prototype: [`design/alerts-sheets-toasts/prototype.html`](../../design/alerts-sheets-toasts/prototype.html).
Screenshots: [`design/alerts-sheets-toasts/screens/`](../../design/alerts-sheets-toasts/screens/). Restyled to the
brand direction (#304); the before and after list is in
[`design/alerts-sheets-toasts/README.md`](../../design/alerts-sheets-toasts/README.md).

## 1. The system in one paragraph

Two families, one look, and it is the Archive window's look (`design/archive-search/archive-search.md`, section 2).
**Dialogs** ask a question and wait: one content model (title, optional 32 pt icon, body paragraphs, optional list,
optional checkbox, footer link, up to three buttons) drawn on a porcelain (graphite in dark) surface, hosted three
ways: a window sheet, a panel anchored to the page, or an app-modal alert when no window exists. **Toasts** report
and offer one action, never wait: a floating pill over the bottom of the content card, tinted by the Space's theme,
with a leading glyph, a sentence and one small neutral pill. The rules:

- **One primary per surface, and only when the user started something.** It is a mustard pill with graphite text:
  Try Again, Add Extension, the shortcut conflict's Use. A dialog that only confirms has no mustard.
- **Everything else is quiet.** Cancel and other answers are neutral pills (`sidebarItemHovered`, no edge, no
  bezel); the footer's extra action (Show Data Folder, Open in Web Store) is a text link at the leading edge.
- **Destructive answers are red, never grey-bordered.** A neutral pill with a `destructiveText` title (Delete Space,
  Remove, Clear Archive), never the Return key.
- **Lists are recessed fields**, as in the Archive, not hairline-ruled blocks.
- **Space color carries meaning.** Delete Space shows the Space's own theme swatch; toasts take their surface from the
  Space's theme.
- **Focus is the system's** focus ring. Mustard is a fill only: never text, never a stroke.

Everything an engine draws (extension sheets, permission panel, infobars) uses the same values, copied into the
engine as the existing comments already do.

## 2. Inventory

| Surface | Today | Family / host | Designed state |
|---|---|---|---|
| Delete Space | `NSAlert` sheet, Delete Space first and destructive, no key equivalent, Cancel on Escape | dialog / window sheet | `delete-space`, `delete-space-empty` |
| Launch failure | app-modal `NSAlert`, critical style, Try Again + Quit | dialog / app-modal alert | `launch-failure` |
| Newer data schema | same alert, Quit only | dialog / app-modal alert | `launch-newer` |
| Restore failure | transient toast "Couldn't restore from the Archive." | toast / error | `toast-error` |
| Import Browser Data failure | transient toast "Couldn't import browser data." | toast / error | as `toast-error` |
| Sidebar mutation errors | transient toasts ("Couldn't add the tab.", "Cannot Add New Pane", ...) | toast / error | as `toast-error` |
| Restore done | toast "Tab restored to Work. Click to view." + View | toast / notice with action | `toast-restored` |
| Auto-archive | toast "Auto archived 3 tabs" | toast / undo | as `toast-undo` |
| Archive of several tabs (Clear, Archive Below, multi-selection) | no toast today | toast / undo (new) | `toast-undo` |
| Recovery | persistent toast with Show Files, one line, truncates at 480 pt | toast / persistent, multi-line | `toast-recovery` |
| Extension install, post-install, uninstall | engine `ArktDialogSheet` as a window sheet | dialog / window sheet (engine-drawn) | `ext-install`, `ext-remove` |
| Permission prompts | shell `DialogPanel` as an anchored panel (#400); the engine's `ArktDialogSheet` stays the fallback while no embedder presents it | dialog / anchored panel | `permission` |
| Infobars | engine `ArktInfobarView` rows, 40 pt, fade-in 0.14 s | infobar (engine-drawn) | `infobar` |

Found while inventorying: the recovery texts are about 100 characters and `ToastView` is one truncating line at most
480 pt wide, so the most important notice Arkt shows is cut off. The multi-line toast below fixes it.

## 3. Dialogs

### 3.1 Content model

The engine's `ArktDialogSheetContent` already is the model; the shell gets a Swift twin (`DialogContent`) with the
same fields, so Delete Space, launch failure and future confirmations (Clear Archive BH-087, Reset settings, Clear
browsing data) and the engine's prompts are one design:

title, icon (32 pt; nil: none), subtitle, paragraphs (primary or secondary color, one link each), list heading and
items, checkbox, footer link, primary / secondary / cancel titles, default button (none, primary, cancel), primary
enable delay, width (default 420), stacked buttons, neutral primary, Escape dismisses, **destructive primary** (new).

### 3.2 Layout (pt)

| Element | Value | Token / source |
|---|---|---|
| Width | 420 (permission panel 320) | engine kDefaultWidth |
| Padding | 20 (panel 16; app-modal alert 24 top) | engine kInset |
| Surface | `surfaceBrand` | BrandTokens.surfaceBrand |
| Icon | 32 x 32, radius 8, gap 12 to the title | engine kIconSize, kIconGap |
| Title | 15 semibold, `primaryText`, 5 top offset beside an icon | engine title font |
| Subtitle | 12 regular, `secondaryText`, 3 below the title | engine subtitle |
| Body | 13 regular, line height 1.45, `primaryText`; secondary paragraphs `secondaryText`; 12 between paragraphs; indented 44 under an icon | engine paragraphs |
| List | recessed field: radius 10, padding 10 / 12, `ArchiveTokens.listField`, no edge; heading 12 semibold `secondaryText`; items 13 `primaryText` with a 5 pt `sidebarForeground` dot; max height 260 then scroll | engine kListMaxHeight, ArchiveTokens.listField |
| Footer | 20 above; footer link leading (13 regular `secondaryText`, no underline, hover `primaryText`); buttons trailing, 8 apart | |
| Buttons | pills: 28 high, radius 14, min 76, padding 16, 13 semibold; no edge | the Archive window's pills; engine kButton* |
| Primary | `accent` fill, `onAccent` text, hover `accentHighlight`, pressed `accentPressed` | BrandTokens |
| Neutral | `sidebarItemHovered` fill, no edge; hover `sidebarItemBackground` | ShellTokens |
| Destructive | neutral pill with a `destructiveText` title; pressed keeps the hover fill (no pressed fill), scale 0.97. Light #B3261E: 5.59:1 on the fill, 5.02:1 hovered; dark #FFAAA2: 6.44:1, 5.45:1 hovered | AlertTokens.destructiveText |
| Stacked buttons | full-width neutral pills, 8 apart, 16 above (permission prompts; deliberately no primary) | engine stackedButtons |
| Sheet corners | bottom corners 14, as the Archive's Clear Archive sheet | |
| Panel corners | 12 (was 10) | change, see section 6 |
| Alert corners | 14 | |
| Focus ring | the system focus ring (`NSColor.keyboardFocusIndicatorColor`), never mustard | AppKit |
| Shadow | `overlayShadow`: 0.5 pt edge black 0.12 (dark white 0.20), 18 / 48 blur black 0.22 (dark 0.55), 3 / 10 black 0.10 | new AlertTokens.overlayShadow |

Button order: trailing edge holds the answer that continues; the cancel answer is to its left; a third answer (Allow
This Time) goes between. Destructive confirmations keep today's behavior: no Return key on the destructive button,
Escape is Cancel, so a stray Return never deletes anything.

### 3.3 The three hosts

1. **Window sheet** (`NSWindow.beginSheet`): Delete Space, extension install / post-install / uninstall, Settings'
   Clear browsing data and Reset. AppKit owns the slide; Arkt draws the content view. Centered on the browser window
   (the Arkt window has no title bar, so the sheet hangs from the window's top edge).
2. **Anchored panel** (child `NSPanel`, non-activating): permission prompts. Top-leading corner 12 pt inside the
   content card (or the focused split pane), so the prompt points at the page that asked. Never steals focus from a
   text field on the page unless the user clicks it; Escape dismisses it without choosing (the
   engine's own panel does the same), and only while the panel is key.
3. **App-modal alert** (`NSApp.runModal(for:)` on a centered panel): launch failure before any window exists. Icon is
   the plain app icon at 56 pt, no badge, with the brand clear space kept (decision 5); the title stacks under the
   icon, as in system alerts. Runs from the same run-loop callout `askAfterLaunchFailure` uses
   today (never from inside a main-actor job, week-3 Decision 3).

Delete Space moves from `NSAlert` to the shared sheet. What is lost: `NSAlert`'s free accessibility and the system
look. What replaces it: the role, order and keys in section 7, and a look that matches the engine sheets next to it.
The gain is the Space's own theme swatch and icon as the sheet's icon, so the user sees which Space goes.

### 3.4 Copy

| Surface | Title | Body | Buttons |
|---|---|---|---|
| Delete Space, with items | Delete the Space "Work"? | Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them. / 3 pinned tabs, 3 Today tabs (secondary; counts only, omitted parts at zero) | Cancel, **Delete Space** (destructive) |
| Delete Space, empty | Delete the Space "Work"? | This cannot be undone. | Cancel, **Delete Space** |
| Delete Space, untitled | Delete this Space? | as above | as above |
| Launch failure | Arkt couldn't open its data | Nothing was changed. Try again, or show the data folder. / Error: <type> <code> (secondary) | Show Data Folder (text link, leading), Quit, **Try Again** (primary, Return) |
| Newer schema | This data was saved by a newer version of Arkt | Update Arkt to open it. Nothing was changed. | **Quit** (primary, Return) |
| Crash report (next launch after a crash, switch off, asked once) | Arkt quit unexpectedly. Send a report? | The report has no web addresses, page titles, file paths or names. Nothing is sent until you review it in your browser. / You can change this in Settings, under Privacy. (secondary) | Don't Send (Escape), Always Send, **Send** (primary, Return); a window sheet on the browser window (#129) |
| Extension install | Add "<name>"? (Chromium string) | subtitle: rating and users; list "It can:" + permissions in a recessed field | Open in Web Store (text link), Cancel, **Add Extension** |
| Extension uninstall | Remove "<name>"? (Chromium string) | checkbox Report abuse (Chromium string) | Cancel, **Remove** (destructive) |
| Permission | <origin> wants to | glyph + permission ("Know your location") | Allow While Visiting the Site, Allow This Time, Never Allow (stacked, neutral: no nudge) |

The Delete Space strings and `SpaceRemovalPrompt` tests stay as they are; the counts line is new. Launch failure
titles drop the trailing period (titles are not sentences in the rest of the system); the error code moves to its own
secondary line. Engine strings stay Chromium's (`IDS_*`), so translations keep working.

## 4. Toasts

### 4.1 Kinds

| Kind | Glyph (SF Symbol) | Lifetime | Action |
|---|---|---|---|
| Undo | archivebox | 6 s | Undo (Cmd-Z also undoes; the pill carries no key hint) |
| Notice with action | arrow.counterclockwise (restore), pin (BH-055), link (BH-191) | 4 s | View / none |
| Error | exclamationmark.circle | 4 s | none, or Try Again when a retry exists |
| Persistent (recovery) | exclamationmark.shield | until dismissed or replaced | Show Files + dismiss (xmark) |

Timers pause while the pointer is over the toast and while the window is not key; they restart at full length when it
becomes key again (a toast that expired unseen taught nothing). One toast at a time per window, as `ToastPresenter`
does today; a transient toast over a persistent one hides it only while it is up.

### 4.2 Layout (pt)

| Element | Value | Token / source |
|---|---|---|
| Position | centered over the content card (over the pane it concerns in a split, BH-190), 16 above the bottom edge | ToastView.bottomInset |
| Single line | 36 high, radius 18 (continuous), max width 480 | ToastView.height, maxWidth |
| Padding | 12 leading; 6 trailing with an action, 14 without | changes from 14 / 14 |
| Glyph | 16 x 16 box, 14 pt symbol, `toastText` at 72 % (light 64 %), 8 to the text | new |
| Text | 13 medium `toastText`, one line, truncating tail | ToastView label |
| Action | a small neutral pill: 24 high, radius 12, padding 12, 12 semibold `toastText`, fill `sidebarItemHovered`, hover `sidebarItemBackground`; 8 after the text; no hairline before it | ToastView actionButton |
| Multi-line (persistent) | radius 12, padding 10 / 8 / 10 / 12, text column 300 wide, up to 3 lines, line height 1.38; actions top-aligned | new |
| Dismiss | 24 x 24 capsule, xmark 10 pt, `toastText` at 72 % | new |
| Surface | follows the Space theme: `toastSurface` (light white 0.96 / dark #1C1C20 0.96) with the theme's first color stop mixed in, 22 % in light and 30 % in dark, as a plain layer fill, no blur. On the default theme it is plain `toastSurface`. Text contrast on the prototype's blue Work theme: 14.39:1 light, 11.43:1 dark | new AlertTokens.toastSurface(theme) |
| Shadow | `toastShadow`: 0.5 pt edge black 0.10 (dark white 0.14), 8 / 24 black 0.16 (dark 0.45), 1 / 3 black 0.08 | new AlertTokens.toastShadow |
| Flavor | follows the Space theme's flavor, as today (BH-190) | ToastView.flavor |

### 4.3 Copy

| Toast | Text |
|---|---|
| Archive of several tabs (Clear, Archive Below, multi-selection Cmd-W) | Archived 3 tabs (never shown for one tab, decision 3) |
| Auto-archive (2 or more tabs only) | Auto archived 3 tabs (BH-085, unchanged; the singular form is no longer shown) |
| Restore | Tab restored to Work / Folder restored to Work / Split View restored to Favorites; action View |
| Restore failed | Couldn't restore from the Archive. |
| Import failed | Couldn't import browser data. |
| Recovery | the four `RecoveryNotice` texts, unchanged; action Show Files |

Counts and Space titles only, never a tab title or URL (the `ToastText` rule). The restore toast drops "Click to
view." when the View button is shown: the button says it. PARITY(NEEDS-RUNTIME-CHECK BH-086): Arc's toast is
clickable as a whole and says "Click to view."; Arkt keeps a real button for keyboard and VoiceOver users.

## 5. Infobars

Kept as the engine draws them, values aligned: 40 pt rows stacked at the top of the tab's container, `surfaceBrand`
fill with no hairline below (the surface against the page is the edge), 12 inset, 20 pt icon in `secondaryText`, 13
regular message in `primaryText`, links in `secondaryText` without underline, buttons the small neutral pill (24 high,
radius 12), close 22 x 22 round. The page moves
down once by the row height (no height animation, which would resize the page every frame), and the row fades in
over 0.14 s; no exit animation. Both rules stay: they are right.

## 6. Engine restyle (values to copy)

The engine cannot link ShellKit; `arkt_dialog_sheet.mm` and `arkt_infobar_view.mm` mirror the tokens by value with a
comment naming each token. Changes for this pass:

| Engine constant / function | Today | Design | Note |
|---|---|---|---|
| `kDefaultWidth`, `kInset`, `kIconSize`, `kIconGap` | 420, 20, 32, 12 | unchanged | already on the grid |
| `kButtonHeight`, `kButtonRadius`, padding, min width | 28 / 7 / 14 / 80 | 28 / 14 / 16 / 76, 13 semibold | pills, as the shell |
| button edge | 0.5 pt `sidebarDivider` | none; neutral fill `sidebarItemHovered` | |
| footer link | underlined `secondaryText` | no underline; hover `primaryText` | |
| list | hairline above | recessed field (`listField`, radius 10, padding 10 / 12) | |
| `kPanelRadius` | 10 | 12 | matches the alert and toast multi-line radius |
| `kPanelInset` | 12 | unchanged | |
| panel content padding | 20 | 16 | 320 pt panel reads less heavy |
| panel shadow | window default | `overlayShadow` values (section 3.2) plus a 0.5 pt edge | panel has `hasShadow` and a layer border |
| panel entrance | alpha 0 to 1, 0.14 s | opacity 0 to 1 over 0.16 s ease-out and scale 0.97 to 1 from the top-leading corner on firmFast (0.95 / 0.15 s); Reduce Motion: opacity only | layer transform on the content view, not the window frame |
| panel exit | immediate | opacity to 0 over 0.10 s; immediate when keyboard-initiated | |
| button press | none | scale 0.97 while pressed, 0.12 s ease-out back | `ArktDialogSheetButton` layer transform |
| destructive primary | n/a | `destructivePrimary` flag: neutral fill, `destructiveText` title, no Return | uninstall, Clear data |
| `DestructiveTextColor()` | n/a | Dynamic(#B3261E, #FFAAA2) | new function, comment "AlertTokens.destructiveText" |
| infobar | 40 / 12 / 20 / fade 0.14, hairline below | unchanged sizes; no hairline; button the small pill (24 high, radius 12) | |

## 7. Motion spec

| Moment | Frequency | Purpose | Motion | Reduce Motion |
|---|---|---|---|---|
| Window sheet in / out | occasional | system | AppKit's sheet animation, untouched | AppKit's own |
| Anchored panel in | occasional | spatial: it comes from the page | scale 0.97 to 1 + translateY -4 to 0 from top-leading on `firmFast`, opacity 0.16 s ease-out | opacity 0.15 s |
| Anchored panel out | occasional | none | opacity 0.10 s; instant if keyboard-initiated | instant |
| App-modal alert in | rare | prevent a jarring pop | scale 0.96 to 1 on `firmFast`, opacity 0.18 s ease-out, centered origin | opacity 0.15 s |
| Toast in | occasional | spatial: it rises from the edge it lives on | translateY 12 to 0 and scale 0.96 to 1 on `springyFast` (0.80 / 0.18 s, slight overshoot), opacity 0.16 s ease-out | opacity 0.15 s (today's fade) |
| Toast out | occasional | exits the way it came | translateY 0 to 6, scale to 0.98, opacity to 0, 0.15 s ease-out (exit faster than entry) | opacity 0.15 s |
| Toast replaced | occasional | continuity | old one out as above while the new one enters; no width animation (the new pill has its own width) | cross-fade |
| Toast action press | occasional | feedback | scale 0.96, 0.12 s | same |
| Dialog button press | occasional | feedback | scale 0.97, 0.12 s | same |
| Infobar | occasional | none | page moves once, row fades 0.14 s (unchanged) | instant |
| Single Cmd-W archive | frequent | none | no toast (decision 3); Cmd-Z undoes it | none |

Transform and opacity only, driven on the layer (`SpringDriver` for springs, `CABasicAnimation` for the short fades),
never `alphaValue` mixed with `layer.opacity` (the rule in `ToastView`). Layout never animates. Every spring is
interruptible: a toast dismissed mid-entry reverses from its presentation value.

Reduce Transparency: the toast uses `toastSurface` at alpha 1 (instead of 0.96); sheets, panels and infobars are already
opaque.

## 8. Light and dark

Dialogs: porcelain / graphite surface, `primaryText` and `secondaryText`, mustard primary in both, only where a
surface has one. Toasts follow the Space theme (decision 2): its flavor picks the light or dark toast, and its first
color stop tints the surface, so a toast over the blue Work Space is faintly blue. Increase Contrast: dialog edges and the list field use
`SettingsTokens.separatorIncreasedContrast` (light black 0.20, dark white 0.20); the toast action pill gains the same 1 pt edge.

## 9. Keyboard and VoiceOver

- Dialogs: focus starts on the default button when there is one (Try Again, Add Extension), otherwise on Cancel.
  Return presses the default button only; the destructive button never has a key. Escape is Cancel (or dismiss when
  `escapeDismisses`). Tab cycles footer link, checkbox, buttons. The primary enable delay (engine) keeps the button
  visibly disabled, and VoiceOver reads "dimmed" until it enables.
- Dialog VoiceOver: role `AXSheet` (window sheet) or `AXDialog`, label = title, description = the body paragraphs in
  order, then the list, then the buttons; the destructive button's help is "Deletes the Space". Posted
  `.announcementRequested` with the title when a panel appears without focus.
- Toasts never take focus (unchanged). VoiceOver: a group labelled with the text, value timed / persistent (the `AXID`
  values today), action button and dismiss button as children; the text is announced with high priority. Undo is also
  Cmd-Z (KB-011), so keyboard users never need to reach the toast. Ctrl-F6 style "focus the notification" is not
  added.
- Infobars: role `AXGroup` with the message as label; buttons in order.

## 10. Parity notes

- BH-190: toasts use the Space theme's flavor and sit over the pane they concern in a split. Kept.
- BH-085, BH-086 copy kept; "Click to view." dropped next to a View button (PARITY(NEEDS-RUNTIME-CHECK)).
- Archive undo toast: Arc's undo is Cmd-Z / Cmd-Shift-T (KB-010, KB-011, BH-074); whether Arc shows a toast for a
  manual archive is PARITY(NEEDS-RUNTIME-CHECK). Arkt shows one only when several tabs go at once (decision 3).
- Toast duration: Arc's is unknown (BH-192); Arkt uses 4 s, 6 s for undo.
- Delete Space confirmation: Arc's dialog copy and buttons were not inspected; PARITY(NEEDS-RUNTIME-CHECK).
- Permission prompts and extension dialogs keep Chromium's strings and answers.

## 11. Decisions (maintainer, 2026-10-25)

1. Delete Space uses the **shared Arkt sheet** (not `NSAlert`).
2. Toasts **follow the Space theme's flavor** (BH-190), not the system appearance.
3. The undo toast shows **only when several tabs are archived at once** (Clear, Archive Below, a multi-selection
   Cmd-W, an auto-archive pass that archived 2 or more tabs). A single Cmd-W archive and a 1-tab auto-archive pass
   show no toast; Cmd-Z still undoes a manual archive.
4. The launch-failure alert **gets "Show Data Folder"**.
5. The caution badge on the app icon is **not accepted**: the launch alerts show the plain app icon with its clear
   space intact; the critical style is carried by the title and the copy.

## 12. Screenshots

Rendered at 2x with the project's Chromium in headless mode from the prototype (`--window-size=1080,720`,
`--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`), into
`design/alerts-sheets-toasts/screens/<state>-<light|dark>.png`: delete-space, delete-space-empty, launch-failure,
launch-newer, toast-undo, toast-restored, toast-error, toast-recovery, ext-install, ext-remove, permission, infobar
(24 files).
