# Alerts, sheets and toasts design

Design issue: #306 (part of #304). Implementation issue: #308.
Prototype: [`design/alerts-sheets-toasts/prototype.html`](../../design/alerts-sheets-toasts/prototype.html).
Screenshots: [`design/alerts-sheets-toasts/screens/`](../../design/alerts-sheets-toasts/screens/).

## 1. The system in one paragraph

Two families, one look. **Dialogs** ask a question and wait: one content model (title, optional 32 pt icon, body
paragraphs, optional list, optional checkbox, footer link, up to three buttons) drawn on a porcelain (graphite in dark)
surface, hosted three ways: a window sheet, a panel anchored to the page, or an app-modal alert when no window exists.
**Toasts** report and offer one action, never wait: a floating pill over the bottom of the content card with a leading
glyph, a sentence, and an action after a hairline. Mustard appears only on the button that answers yes to something
the user started (Try Again, Add Extension, the shortcut conflict's Use). Destructive answers are neutral buttons with
red text and never the Return key. Everything an engine draws (extension sheets, permission panel, infobars) uses the
same values, copied into the engine as the existing comments already do.

## 2. Inventory

| Surface | Today | Family / host | Designed state |
|---|---|---|---|
| Delete Space | `NSAlert` sheet, Delete Space first and destructive, no key equivalent, Cancel on Escape | dialog / window sheet | `delete-space`, `delete-space-empty` |
| Launch failure | app-modal `NSAlert`, critical style, Try Again + Quit | dialog / app-modal alert | `launch-failure` |
| Newer data schema | same alert, Quit only | dialog / app-modal alert | `launch-newer` |
| Restore failure | transient toast "Couldn't restore from the Archive." | toast / error | `toast-error` |
| Import from Arc failure | transient toast "Couldn't import from Arc." | toast / error | as `toast-error` |
| Sidebar mutation errors | transient toasts ("Couldn't add the tab.", "Cannot Add New Pane", ...) | toast / error | as `toast-error` |
| Restore done | toast "Tab restored to Work. Click to view." + View | toast / notice with action | `toast-restored` |
| Auto-archive | toast "Auto archived 3 tabs" | toast / undo | as `toast-undo` |
| Archive (Cmd-W, Clear) | no toast today | toast / undo (new) | `toast-undo` |
| Recovery | persistent toast with Show Files, one line, truncates at 480 pt | toast / persistent, multi-line | `toast-recovery` |
| Extension install, post-install, uninstall | engine `ArktDialogSheet` as a window sheet | dialog / window sheet (engine-drawn) | `ext-install`, `ext-remove` |
| Permission prompts | engine `ArktDialogSheet` as an anchored panel, fade-in 0.14 s | dialog / anchored panel (engine-drawn) | `permission` |
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
| List | 1 pt `sidebarDivider` above, 10 padding, heading 13 semibold, bullets 13, max height 260 then scroll | engine kListMaxHeight |
| Footer | 20 above; footer link leading (13, `secondaryText`, underline `sidebarDivider`); buttons trailing, 8 apart | |
| Buttons | 28 high, radius 7, min 80, padding 14, 13 medium | engine kButton* |
| Primary | `accent` fill, `onAccent` text, hover `accentHighlight`, pressed `accentPressed` | BrandTokens |
| Neutral | `sidebarItemBackground` fill + 0.5 pt `sidebarDivider` edge; hover `sidebarItemHovered` | ShellTokens |
| Destructive | neutral fill, `destructiveText` title | new AlertTokens.destructiveText |
| Stacked buttons | full width, 8 apart, 16 above (permission prompts) | engine stackedButtons |
| Sheet corners | bottom corners 12 (AppKit draws the sheet frame) | system |
| Panel / alert corners | 12 (was 10 for the panel) | change, see section 6 |
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
   text field on the page unless the user clicks it; Escape answers Never Allow only when the panel is key.
3. **App-modal alert** (`NSApp.runModal(for:)` on a centered panel): launch failure before any window exists. Icon is
   the app icon at 56 pt with a mustard caution badge (24 pt plate, 18 pt glyph) on its trailing-bottom corner; the
   title stacks under the icon, as in system alerts. Runs from the same run-loop callout `askAfterLaunchFailure` uses
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
| Launch failure | Arkt couldn't open its data | Nothing was changed. Try again, or quit and look at the data folder. / Error: <type> <code> (secondary) | Show Data Folder (leading), Quit, **Try Again** (primary, Return) |
| Newer schema | This data was saved by a newer version of Arkt | Update Arkt to open it. Nothing was changed. | **Quit** (primary, Return) |
| Extension install | Add "<name>"? (Chromium string) | subtitle: rating and users; list "It can:" + permissions | Open in Web Store (link), Cancel, **Add Extension** |
| Extension uninstall | Remove "<name>"? (Chromium string) | checkbox Report abuse (Chromium string) | Cancel, **Remove** (destructive) |
| Permission | <origin> wants to | glyph + permission ("Know your location") | Allow While Visiting the Site, Allow This Time, Never Allow (stacked, neutral: no nudge) |

The Delete Space strings and `SpaceRemovalPrompt` tests stay as they are; the counts line is new. Launch failure
titles drop the trailing period (titles are not sentences in the rest of the system); the error code moves to its own
secondary line. Engine strings stay Chromium's (`IDS_*`), so translations keep working.

## 4. Toasts

### 4.1 Kinds

| Kind | Glyph (SF Symbol) | Lifetime | Action |
|---|---|---|---|
| Undo | archivebox | 6 s | Undo (Cmd-Z hint at 50 %) |
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
| Hairline | 1 x 16, `toastText` at 10 % (dark 14 %), between text and action | new |
| Action | 13 semibold `toastText`, 28 high capsule, padding 10, hover `sidebarItemBackground` | ToastView actionButton |
| Multi-line (persistent) | radius 12, padding 10 / 8 / 10 / 12, text column 300 wide, up to 3 lines, line height 1.38; actions top-aligned | new |
| Dismiss | 24 x 24 capsule, xmark 10 pt, `toastText` at 72 % | new |
| Surface | `toastSurface` (light white 0.96 / dark #1C1C20 0.96), backdrop blur 20 with saturation 1.5 | ShellTokens.toastSurface |
| Shadow | `toastShadow`: 0.5 pt edge black 0.10 (dark white 0.14), 8 / 24 black 0.16 (dark 0.45), 1 / 3 black 0.08 | new AlertTokens.toastShadow |
| Flavor | follows the Space theme's flavor, as today (BH-190) | ToastView.flavor |

### 4.3 Copy

| Toast | Text |
|---|---|
| Archive (Cmd-W on a Today tab, Clear, Archive Below) | Archived 1 tab / Archived 3 tabs |
| Auto-archive | Auto archived 3 tabs (BH-085, unchanged) |
| Restore | Tab restored to Work / Folder restored to Work / Split View restored to Favorites; action View |
| Restore failed | Couldn't restore from the Archive. |
| Import failed | Couldn't import from Arc. |
| Recovery | the four `RecoveryNotice` texts, unchanged; action Show Files |

Counts and Space titles only, never a tab title or URL (the `ToastText` rule). The restore toast drops "Click to
view." when the View button is shown: the button says it. PARITY(NEEDS-RUNTIME-CHECK BH-086): Arc's toast is
clickable as a whole and says "Click to view."; Arkt keeps a real button for keyboard and VoiceOver users.

## 5. Infobars

Kept as the engine draws them, values aligned: 40 pt rows stacked at the top of the tab's container, `surfaceBrand`
fill, 1 pt `sidebarDivider` below, 12 inset, 20 pt icon in `secondaryText`, 13 regular message in `primaryText`,
links in `secondaryText` underlined, buttons the small push button (24 high, radius 6), close 22 x 22. The page moves
down once by the row height (no height animation, which would resize the page every frame), and the row fades in
over 0.14 s; no exit animation. Both rules stay: they are right.

## 6. Engine restyle (values to copy)

The engine cannot link ShellKit; `arkt_dialog_sheet.mm` and `arkt_infobar_view.mm` mirror the tokens by value with a
comment naming each token. Changes for this pass:

| Engine constant / function | Today | Design | Note |
|---|---|---|---|
| `kDefaultWidth`, `kInset`, `kIconSize`, `kIconGap`, button sizes | 420, 20, 32, 12, 28 / 7 / 14 / 80 | unchanged | already on the grid |
| `kPanelRadius` | 10 | 12 | matches the alert and toast multi-line radius |
| `kPanelInset` | 12 | unchanged | |
| panel content padding | 20 | 16 | 320 pt panel reads less heavy |
| panel shadow | window default | `overlayShadow` values (section 3.2) plus a 0.5 pt edge | panel has `hasShadow` and a layer border |
| panel entrance | alpha 0 to 1, 0.14 s | opacity 0 to 1 over 0.16 s ease-out and scale 0.97 to 1 from the top-leading corner on firmFast (0.95 / 0.15 s); Reduce Motion: opacity only | layer transform on the content view, not the window frame |
| panel exit | immediate | opacity to 0 over 0.10 s; immediate when keyboard-initiated | |
| button press | none | scale 0.97 while pressed, 0.12 s ease-out back | `ArktDialogSheetButton` layer transform |
| destructive primary | n/a | `destructivePrimary` flag: neutral fill, `destructiveText` title, no Return | uninstall, Clear data |
| `DestructiveTextColor()` | n/a | Dynamic(#B3261E, #FF7A6E) | new function, comment "AlertTokens.destructiveText" |
| infobar | 40 / 12 / 20 / fade 0.14 | unchanged; button radius 6, height 24 | small push button |

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
| Toast from a keyboard action (Cmd-W archive) | frequent | confirmation | the toast still enters (it reports, it is not the action), but repeated archives within its lifetime update the text in place ("Archived 2 tabs") without re-entering | text swap |

Transform and opacity only, driven on the layer (`SpringDriver` for springs, `CABasicAnimation` for the short fades),
never `alphaValue` mixed with `layer.opacity` (the rule in `ToastView`). Layout never animates. Every spring is
interruptible: a toast dismissed mid-entry reverses from its presentation value.

Reduce Transparency: the toast drops its backdrop blur and uses `toastSurface` at alpha 1; sheets, panels and infobars
are already opaque.

## 8. Light and dark

Dialogs: porcelain / graphite surface, `primaryText` and `secondaryText`, mustard primary in both. Toasts follow the
Space theme's flavor (a light toast over a light theme, dark over dark), not the system appearance, as today. The
caution badge is mustard with a graphite glyph in both appearances. Increase Contrast: dialog edges use `cardBorder`;
the toast hairline goes to 20 %.

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
  manual archive is PARITY(NEEDS-RUNTIME-CHECK). Arkt shows one, because archiving is silent otherwise.
- Toast duration: Arc's is unknown (BH-192); Arkt uses 4 s, 6 s for undo.
- Delete Space confirmation: Arc's dialog copy and buttons were not inspected; PARITY(NEEDS-RUNTIME-CHECK).
- Permission prompts and extension dialogs keep Chromium's strings and answers.

## 11. Open questions for the maintainer

1. Delete Space: move from `NSAlert` to the shared Arkt sheet (designed), or keep the system alert?
2. Toasts: keep following the Space theme's flavor (designed, BH-190), or follow the system appearance?
3. Should a manual archive (Cmd-W on a Today tab) show the undo toast every time, or only for Clear and Archive Below
   (several tabs at once)?
4. Launch failure: is "Show Data Folder" in the alert wanted, or should the data folder stay out of sight?

## 12. Screenshots

Rendered at 2x with the project's Chromium in headless mode from the prototype (`--window-size=1080,720`,
`--force-device-scale-factor=2`, hash `#<state>[&dark]&shot`), into
`design/alerts-sheets-toasts/screens/<state>-<light|dark>.png`: delete-space, delete-space-empty, launch-failure,
launch-newer, toast-undo, toast-restored, toast-error, toast-recovery, ext-install, ext-remove, permission, infobar
(24 files).
