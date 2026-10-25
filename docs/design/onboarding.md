# Onboarding: first-run experience

Design for issue #303. This document is the spec for the native implementation; the clickable prototype at
[`design/onboarding/prototype.html`](../../design/onboarding/prototype.html) shows the same layout, copy and motion
for review. Where the two disagree, this document wins.

Status: design. Nothing here is implemented yet.

## Contents

1. [Idea](#1-idea)
2. [Flow](#2-flow)
3. [Shared layout](#3-shared-layout)
4. [Tokens](#4-tokens)
5. [Steps](#5-steps)
6. [Motion](#6-motion)
7. [Keyboard](#7-keyboard)
8. [VoiceOver](#8-voiceover)
9. [Help > Welcome to Arkt](#9-help--welcome-to-arkt)
10. [State and persistence](#10-state-and-persistence)
11. [Parity with Arc](#11-parity-with-arc)
12. [Implementation dependencies](#12-implementation-dependencies)
13. [Open questions](#13-open-questions)
14. [Screenshots](#14-screenshots)
15. [Prototype](#15-prototype)

## 1. Idea

Onboarding happens inside the real browser window, not in a separate wizard window. The window is already there,
with the Space theme behind it and the sidebar in its normal place, and the setup runs in the content card where the
first page will later appear.

- **Welcome is a brand field.** The first launch fills the whole window with the brand surface (porcelain in light,
  graphite in dark), the mark, the wordmark and the descriptor.
- **The field folds into the window.** On "Get started" the field contracts to the content card's exact frame and
  corner radius while the sidebar fades in around it. The brand surface becomes the card, and the card hosts the
  setup steps. This is the one bold moment: it shows where everything lives before the user has read a word.
- **The window fills in as you answer.** The sidebar is quiet (ghost rows) during setup. Importing from Arc fills it
  with the imported rows; choosing a theme repaints the window behind the card live; naming the Space and picking an
  icon update the sidebar title and the dock as you type.
- **Done is the browser.** The last step does not close a window. The card turns into the first tab's page and the
  command bar opens, ready for an address.

Everything else stays quiet: one centered column, system type, the brand's porcelain and graphite, mustard only on the
primary button. Motion is reserved for moments that explain something (the fold, the step direction, the import
filling the sidebar, the tour demos).

## 2. Flow

```mermaid
flowchart TD
  L[First launch: profile has no Space and onboarding not finished] --> W[Welcome]
  W -->|Get started| A{Arc found?}
  W -->|Skip setup / Escape| F[Finish: fresh Space 1, default theme]
  A -->|yes| I[Bring your Arc setup]
  A -->|no| T[Make it yours]
  A -->|still checking| I
  I -->|Import from Arc| P[Importing]
  P -->|done| D1[Your Arc setup is here]
  P -->|failed| E[Couldn't import from Arc]
  E -->|Try again| P
  E -->|Start fresh| T
  I -->|Start fresh / Escape| T
  D1 -->|Continue| B
  T -->|Continue / Skip / Escape| B{Arkt already default browser?}
  B -->|no| DB[Default browser]
  B -->|yes| X[Extensions and passwords]
  DB -->|Make default / Not now / Escape| X
  X -->|Continue / Skip / Escape| TR[The sidebar tour, 6 tips]
  TR -->|Done / Skip tour / Escape| DN[You're all set]
  DN -->|Start browsing| BR[Browser: first Space, new tab, command bar open]
  F --> BR
```

Branch rules:

| Condition | Effect |
|---|---|
| Arc found (Arc's sidebar file exists, `AppSession.refreshArcImportAvailability`) | Import step is shown |
| Arc not found | Import step is left out; Make it yours is the first step; one fewer progress dot |
| Arc check still running when Welcome is left | Import step is shown in its counting state; if the check then says "no Arc", the step is replaced by Make it yours with a normal forward transition |
| Import path chosen | Make it yours is left out: imported Spaces keep their Arc themes. The theme can still be changed later from the Space header |
| Start fresh, or import failed and then Start fresh | Make it yours is shown |
| Arkt is already the default browser | Default browser step is left out |
| "Skip setup" (any step) or Escape on Welcome | Finish immediately: a fresh "Space 1" with the default theme unless an import already finished, then the browser state |

Every step can be skipped: each has a secondary action (Skip, Not now, Start fresh, Skip tour), Escape runs that
secondary action, and "Skip setup" in the card's top-right corner ends the whole flow from any step. An import in
progress is the only thing Escape does not interrupt; Skip setup during an import lets the import finish in the
background and then shows the File > Import from Arc summary alert instead of the step.

Progress dots count the steps after Welcome for the current branch: Arc found and fresh is 6 (import, theme, default,
extensions, tour, done); Arc found and imported is 5; no Arc is 5; Arkt already default removes one more.

## 3. Shared layout

All sizes in points on the existing grid (`ShellMetrics`, `SidebarMetrics`, brand spacing 8, 16, 24, 32, 48, 64, 96).
Reference window for every screenshot: 1120 x 720 pt.

```
+--------------------------------------------------------------------------------------+
| o o o                                                                                |
| [ URL bar (ghost)   ]  +----------------------------------------------------------+  |
| [fav][fav][fav]        | < Back                                     Skip setup     |  |
| Space 1                |                                                          |  |
| [== ghost row ==  ]    |                   [ illustration 440x152 ]  (tour only)  |  |
| [== ghost row     ]    |                        Title 28/34                       |  |
| ----------------       |              Body 15/22, max 400 wide, centered          |  |
| + New Tab              |               [ step controls, 440 wide ]                |  |
|                        |               [ Secondary ]  [ Primary ]                 |  |
|                        |                                                          |  |
| [arch]   .   [+]       |                        o o * o o o                       |  |
|  sidebar 190           +----------------------------------------------------------+  |
+--------------------------------------------------------------------------------------+
```

| Element | Spec |
|---|---|
| Window | First run opens at least 1000 x 680 pt so the tallest step (Make it yours) fits without scrolling |
| Background | The Space theme (`ThemeBackgroundView`: gradient plus grain), the default theme until the user picks one |
| Sidebar | Normal position and width (190, `ShellMetrics.sidebarDefaultWidth`), Toolbar-off layout (URL bar at y 40, height 30). Non-interactive and hidden from accessibility during setup |
| Ghost sidebar | Real geometry with placeholder content: URL bar, three empty Favorite tiles, the Space title, two skeleton rows (16 pt icon block, text block 70-92 pt wide, `sidebarItemHovered` fill, radius 4), divider, "New Tab" row, dock with one dot. Content at opacity 0.55 |
| Content card | Normal card frame (insets 10, radius 10, `cardBorder`, `cardShadow`), filled with `BrandTokens.surfaceBrand` instead of the page |
| Column | 440 wide, centered horizontally and vertically in the card; padding 64 top, 32 sides, 72 bottom (keeps clear of the dots) |
| Title | SF Pro Display Semibold 28/34, tracking -0.3 pt, `brandTextPrimary`, balanced wrapping, centered |
| Body | SF Pro Text Regular 15/22, `brandTextSecondary`, max 400 wide, 8 below the title |
| Controls block | 32 below the body |
| Button row | 32 below the controls (or the body), centered, 12 between buttons (same gap as `EmptyStateView`) |
| Primary button | Height 32, min width 120, padding 16, radius 8, SF Pro Text Semibold 13. Fill `accent`, hover `accentHighlight`, pressed `accentPressed`, label `onAccent`. It is the default button (Return) |
| Secondary button | Same size, no fill, 1 pt inside border `brandControlBorder`, label `brandTextPrimary`, hover fill `brandControlFill` |
| Back | Top-left of the card at (16, 16), height 28, chevron 12 plus "Back", 13 pt, `brandTextSecondary`; hidden on the first step after Welcome and on Done |
| Skip setup | Top-right of the card at 16, height 28, 13 pt, `brandTextSecondary`; hover fill `brandControlFill`, text `brandTextPrimary` |
| Progress dots | 6 pt dots, 14 pt pitch, centered, 24 above the card bottom; idle `brandControlBorder` at 60 %, current is a separate 6 pt dot in `brandTextPrimary` that moves |
| Focus ring | 2 pt `BrandTokens.focusRing`, 2 pt outside the control (graphite in light, mustard in dark) |

Typography is San Francisco throughout. This is a deliberate choice: Arkt is a native macOS app, the brand guide
uses the system stack, and the onboarding should read as part of the system, with the wordmark artwork carrying the
brand voice. No other typeface is introduced.

Light and dark follow the system appearance for everything in the card and the Welcome field. The sidebar chrome
follows the Space theme's `isDark`, exactly as it does in the browser (it uses `ShellTokens`, not `BrandTokens`).

## 4. Tokens

### Existing tokens used

| Token | Light | Dark | Used for |
|---|---|---|---|
| `BrandTokens.surfaceBrand` | porcelain #FAF9F5 | graphite #202321 | Welcome field, card during setup |
| `BrandTokens.accent` | mustard #E9B520 | mustard | Primary button fill, tour highlight (as a 20-28 % fill) |
| `BrandTokens.accentHighlight` | #F3CA3D | #F3CA3D | Primary button hover |
| `BrandTokens.accentPressed` | #DCA319 | #DCA319 | Primary button pressed |
| `BrandTokens.onAccent` | graphite | graphite | Primary button label (8.38:1 on mustard, 7.02:1 on pressed) |
| `BrandTokens.focusRing` | graphite | mustard | Focus rings, selected swatch ring, selected icon ring |
| `BrandTokens.accentText` | #8A5A0E | mustard | Not needed in the current copy; reserved for an accent-colored link |
| `ShellTokens.*` | | | Sidebar, card border and shadow, command bar, page surface (`toolbarSurface`) |

Mustard is never text on porcelain and never a ring on porcelain, as the brand rules require.

### Proposed `BrandTokens` additions

The brand kit has no secondary text or border colors yet. These come from values already used in
`design/brand/brand-guide.html`; contrast is WCAG 2.x against `surfaceBrand`.

| Proposed token | Light | Dark | Contrast | Use |
|---|---|---|---|---|
| `brandTextPrimary` | #202321 | #FAF9F5 | 15.06:1 | Titles, button labels, counts |
| `brandTextSecondary` | #62655F | #B6BAB3 | 5.62:1 / 8.06:1 | Body, labels, notes, Back, Skip setup |
| `brandHairline` | #DEDED5 | white 10 % | decorative | Count list border and dividers, option rows |
| `brandControlBorder` | #8C8F88 | #6E726B | 3.11:1 / 3.23:1 | Secondary button border, idle dots (WCAG 1.4.11 non-text 3:1) |
| `brandControlFill` | graphite 5 % | porcelain 6 % | n/a | Hover fill, text field fill, segmented control track, key caps |

`BrandTokensTests` should cover the four contrast pairs above, like the existing pairs.

### Proposed first-Space themes

`SpaceThemeCatalog` has only Paper and Dusk, both marked `TODO(design)`. The theme step needs a small set with a light
and a dark variant per family. Two-stop gradients, top-left to bottom-right, no texture (so they round-trip through
the bridge, as the catalog comment requires). Mist reuses the stub "Work" light stops and Dusk; Blossom reuses the
stub "Personal" stops; Indigo dark reuses the stub "Dev" stops; Paper light is the existing Paper.

| Family | Light stops | Dark stops |
|---|---|---|
| Mist (default selection) | #E0F2FB to #C5C6E2 | #3A4158 to #1C2030 |
| Paper | #F4F1EA to #E4DDD2 | #3A3631 to #211F1C |
| Sage | #E6EDE3 to #C4D3C0 | #2F3B33 to #171E1A |
| Dune | #F7EED2 to #EBD592 | #3D3420 to #1E1A10 |
| Blossom | #F2EAE4 to #F29BBB | #4A2A3A to #1F1520 |
| Indigo | #E4E2F4 to #C9C3E8 | #2D4468 to #120F2E |

Each new stop pair has to pass the existing `ShellTokensContrastTests` (sidebar text and icons over every shipped
theme) before it ships; adjust a stop rather than the chrome tokens if one fails.

## 5. Steps

Copy below is final unless an open question says otherwise. Sentence case everywhere; "Arkt" capitalized in
sentences, the lowercase name only as the wordmark artwork.

### 5.1 Welcome

![Welcome, light](../../design/onboarding/screens/01-welcome-light.png)

| | |
|---|---|
| Surface | Full-window `surfaceBrand` field above the sidebar and card, with grain at about half the theme grain opacity. Traffic lights stay visible above it |
| Mark | `01-mustard-on-white.png` in light, `02-mustard-on-graphite.png` in dark, 112 x 112 pt, centered (clear space well above a quarter of the icon). Raster, scaled proportionally, no shadow or effect |
| Wordmark | `wordmark-graphite.png` in light, `wordmark-ivory.png` in dark, 90 x 38 pt (the 180 x 76 px source at 2x), 32 below the mark |
| Descriptor | "A native macOS browser." SF Pro Display Regular 17/22, `brandTextSecondary`, 16 below the wordmark |
| Primary | "Get started", 48 below the descriptor |
| Corner | "Skip setup" at the field's top-right (16, 16) |
| Accessibility title | "Welcome to Arkt" (not drawn; the wordmark is decorative) |

The group's block is vertically centered; the mark sits slightly above the window's center.

### 5.2 Bring your Arc setup

![Import, light](../../design/onboarding/screens/02-import-light.png)

States: counting, ready, importing, imported, failed.

| State | Title | Body | Controls | Buttons |
|---|---|---|---|---|
| Counting | Bring your Arc setup | Arkt found Arc on this Mac. Your Spaces, pinned tabs, Favorites and folders can come over. Arc stays as it is. | Count list, numbers show "-" | Start fresh, Import from Arc (disabled) |
| Ready | same | same | Count list with numbers | Start fresh, **Import from Arc** |
| Importing | same | same | Each row gets a 14 pt spinner, replaced by a check as its category finishes | Start fresh (disabled), Importing... (disabled) |
| Imported | Your Arc setup is here | {n} Spaces, {n} pinned tabs, {n} Favorites and {n} folders came over. | Count list, all checked; note "{n} items couldn't be imported." only when `skipped` > 0 | **Continue** |
| Failed | Couldn't import from Arc | Arkt couldn't read Arc's data. Try again, or import later from File > Import from Arc. | none | Start fresh, **Try again** |

Count list: 440 wide, radius 12, 1 pt `brandHairline` border, four rows of 44 (Spaces, Pinned tabs, Favorites,
Folders), 16 side padding, name 14 regular `brandTextPrimary`, count 14 semibold with tabular figures, a 16 pt state
slot 12 to the right of the count. Counts only: no Space names, titles, URLs or paths, matching the import summary's
counts-only rule. Plural rules apply to every count ("1 Space", "1 pinned tab", "1 folder"); a category with 0 is
still listed.

"Arc stays as it is" is true: the importer only reads Arc's folder.

While the import runs and when it finishes, the ghost sidebar fills with the imported content of the first Space
(Favorites, its title, pinned rows) and the dock shows one dot per imported Space.

The first-run path does not show the `NSAlert` summary that File > Import from Arc shows; the Imported state replaces
it. File > Import from Arc keeps the alert.

### 5.3 Make it yours

![Make it yours, light](../../design/onboarding/screens/06-theme-light.png)

| | |
|---|---|
| Title | Make it yours |
| Body | Pick a look for your first Space. You can change it later. |
| Theme | Label "Theme" (12 semibold, `brandTextSecondary`, 8 above). Six swatches in a row, 440 wide, 12 apart (about 63 pt square), radius 12, a 1 pt inner hairline. Selected: a 2 pt `focusRing` ring 4 pt outside the swatch. Radio group |
| Appearance | Label "Appearance". Segmented control "Light" / "Dark", track `brandControlFill` radius 8 with 2 pt padding, segments 72 x 28, the thumb is a `surfaceBrand` pill with a hairline. Starts at the system appearance |
| Name | Label "Name", text field 32 high, radius 8, `brandControlFill`, 1 pt `brandHairline`, 14 pt text, placeholder "Space 1" (the name New Space would give, `SpaceNaming`), 40 characters max. Fills the rest of the row, 16 from the segmented control |
| Icon | Label "Icon". Nine choices from `SpaceIconCatalog` (None, Star, Bookmark, Folder, Heart, Bolt, Book, Globe, Person) as SF Symbols at 18 pt in 36 x 32 buttons spread over 440. Selected: `brandControlFill` plus a 1.5 pt inner `focusRing` ring |
| Group spacing | 24 between Theme, the Appearance/Name row and Icon |
| Buttons | Skip, **Continue** |

Live preview: choosing a swatch or the appearance repaints the window background behind the card at once
(`ThemeBackgroundView.replaceThemes(_:crossfade:)`), and the sidebar chrome flips between its light and dark token
sets with it. Typing a name updates the sidebar's Space title; picking an icon replaces the dock dot with the symbol.
Skip keeps the default theme, "Space 1" and no icon; Continue keeps the choices. The Space itself is created when
this step is left (Continue or Skip), so Back from the next step returns to the same choices.

### 5.4 Default browser

![Default browser, light](../../design/onboarding/screens/07-default-light.png)

| | |
|---|---|
| Title | Make Arkt your default browser? |
| Body | Links you open in other apps will open in Arkt. macOS asks you to confirm, and you can change it later in System Settings. |
| Buttons | Not now, **Make default** |

Not pushy: one question, no illustration, "Not now" is a full button next to the primary, no follow-up nag. After
"Make default" the system confirmation appears; whatever the answer, the flow moves on when the system prompt closes.
The body line while the prompt is up: "macOS is asking you to confirm. Arkt continues either way." The step is left
out when Arkt is already the default browser.

### 5.5 Extensions and passwords

![Extensions, light](../../design/onboarding/screens/08-extensions-light.png)

| | |
|---|---|
| Title | Extensions and passwords |
| Body | Arkt installs extensions from the Chrome Web Store. Your password manager's extension is there too. |
| Option | Checkbox row, 440 wide, radius 12, hairline border, 12 x 16 padding: **Open the Chrome Web Store** / "It opens in a tab when setup ends." Off by default |
| Buttons | Skip, **Continue** |

Nothing opens mid-setup. When the option is on, the Web Store opens as the first Space's tab at the end instead of the
empty new tab. 1Password is not named: desktop-app integration depends on signing (#23), and the copy only claims
what the engine build already does (Web Store install works on the native window, engine week 3 results, W7). This
step is shown only in builds that run the Chromium engine; the WKWebView development shell leaves it out.

### 5.6 The sidebar tour

![Tour tip 1, light](../../design/onboarding/screens/09-tour-1-light.png)

Six tips, one at a time. Each has an illustration area (440 x 152), a title, a body, "{n} of 6" (12 pt
`brandTextSecondary`, tabular, 16 below the body), and Skip tour, **Next** ("Done" on the last tip). Back steps
through tips before leaving the tour. A matching area of the ghost sidebar is highlighted with a mustard fill
(`accent` at 28 % over light themes, 20 % over dark, radius 10) so the tip points at the real place.

| # | Title | Body | Illustration | Sidebar highlight | Parity rows |
|---|---|---|---|---|---|
| 1 | Open a tab | Press Command-T, then search or type an address. | Key caps "Command" "T" | New Tab row | KB-001 |
| 2 | Go to the address | Press Command-L to edit the address of the current tab. | Key caps "Command" "L" | URL bar | KB-002 |
| 3 | Close by archiving | Command-W closes a tab and keeps it in the Archive, so you can find it again. | Key caps "Command" "W" | Archive button in the dock | KB-008 |
| 4 | Switch Spaces | Swipe left or right with two fingers on the sidebar to move between Spaces. | Mini window: two finger dots swipe, the sidebar pages over, the page dot moves | Dock dots | GS-001, BH-035 |
| 5 | Split the view | Drag a tab from the sidebar onto the page to see two tabs side by side. | Mini window: a tab chip travels from the sidebar to the page, a drop zone shows, the page splits | Pinned rows | GS-011, BH-117 |
| 6 | Keep Favorites close | Drag a tab to the top of the sidebar to make it a Favorite. | Mini window: a tab chip travels up into the Favorites row | Favorites | GS-008, BH-047 |

Key caps: 64 high, min 64 wide, radius 14, SF Pro Display Medium 28, `brandControlFill` with a hairline border and a
3 pt hairline bottom edge. Key glyphs are the Command symbol and the letter, drawn as text, not images. Mini window:
280 x 152, radius 12, a 72 wide sidebar strip and a page inset 4; the moving chip is an `accent` fill.

Tip 3 copy assumes Today tabs archive on close, which is the shipped behavior (KB-008); a pinned tab closes and stays
pinned, which the tip does not need to explain.

### 5.7 You're all set

![Done, light](../../design/onboarding/screens/15-done-light.png)

| | |
|---|---|
| Mark | The app icon at 64 pt, 32 above the title |
| Title | You're all set |
| Body | Your Space is ready. To see this again, choose Help > Welcome to Arkt. |
| Buttons | **Start browsing** |

### 5.8 Landing in the browser

![Browser, light](../../design/onboarding/screens/16-browser-light.png)

"Start browsing" (or Skip setup) ends the flow: the sidebar becomes live (no ghost, clicks and accessibility on), the
card shows the first tab's page surface, a "New Tab" Today row is current, and the command bar opens in its normal
place with the field focused. With the Web Store option on, the first tab is the Chrome Web Store instead and the
command bar stays closed. After an import, the current Space is the first imported Space and its own last state
applies; a new tab is still opened and focused so typing works at once.

## 6. Motion

All values come from `Motion/SpringPreset` (response and damping ratio, solved as in `SpringParameters`). Native
implementation: `CASpringAnimation` from `SpringAnimationFactory`, or `SpringDriver` where a gesture or retarget needs
velocity carried over. Settle times are the 0.1 % envelope from `settlingDuration()`.

| Preset | Damping, response | Settles | Overshoot | Used for |
|---|---|---|---|---|
| `firmFast` | 0.95, 0.15 s | 203 ms | 0.01 % | Outgoing content, press release |
| `firm` | 0.90, 0.25 s | 342 ms | 0.15 % | Incoming step content, sidebar rows filling in |
| `firmSlow` | 0.90, 0.35 s | 479 ms | 0.15 % | The fold, the descriptor, the active highlight |
| `springyFast` | 0.80, 0.18 s | 266 ms | 1.5 % | Progress dot, segmented thumb, import checks, key cap release |
| `springy` | 0.63, 0.28 s | 507 ms | 7.8 % | The mark's entrance, the tour's Space page swipe |

Durations without a spring use the strong ease-out `cubic-bezier(0.23, 1, 0.32, 1)` (`EASE_OUT` below) or, for
movement between two on-screen places in demos, `cubic-bezier(0.77, 0, 0.175, 1)` (`EASE_IN_OUT`). Nothing uses
ease-in.

### 6.1 Transitions

| ID | Trigger | What moves | Spec | Interruptible |
|---|---|---|---|---|
| M1 Welcome reveal | Window first shown | Mark: opacity 0 to 1, translateY 8 to 0, scale 0.92 to 1. Wordmark: mask wipe left to right plus opacity. Descriptor: opacity, translateY 6 to 0. Button and Skip setup: opacity | Mark `springy` at +120 ms; wordmark 420 ms `EASE_OUT` at +300 ms; descriptor `firmSlow` at +440 ms; button and corner link 240 ms `EASE_OUT` at +560 ms. All settled by about 900 ms | Yes: Return or a click at any moment jumps every element to its end value and starts M2 |
| M2 Fold | Get started | The field's mask from the window bounds (radius 0) to the card frame (radius 10). Welcome content: opacity 1 to 0, scale 1 to 0.97. The field itself: opacity 1 to 0 in the last part. Ghost sidebar items: opacity 0 to 0.55, 30 ms apart. First step: enters as M3 | Mask `firmSlow` at +60 ms; content `firmFast`; field opacity 200 ms `EASE_OUT` at +200 ms; sidebar items 240 ms `EASE_OUT` from +120 ms; first step starts at +140 ms. About 520 ms total | Yes: a second press of Return lands the first step at once (mask and opacities snap to end) |
| M3 Step forward | Continue, Skip, Next, Right arrow | Outgoing column: opacity 1 to 0, translateX 0 to -24. Incoming column: opacity 0 to 1, translateX +24 to 0. Progress dot: translateX to the new slot | Outgoing `firmFast`; incoming `firm` at +70 ms; dot `springyFast` | Yes: a new navigation retargets from the presented values (the in-flight incoming column becomes the outgoing one from where it is) |
| M4 Step back | Back, Left arrow | Mirror of M3 (outgoing to +24, incoming from -24) | Same as M3 | Same as M3 |
| M5 Tip change | Next or Back inside the tour | Illustration, title and body: as M3 at 16 pt, 30 ms stagger on the way in. Highlight: the old one opacity to 0 and scale to 0.97, the new one opacity to 1, scale 0.97 to 1 | Out `firmFast`, in `firm`; highlight in `firmSlow`, out `firmFast`. Each highlight is its own layer at its target's frame, so nothing resizes | Yes |
| M6 Theme preview | Swatch or appearance change | Window theme: crossfade old to new. Sidebar chrome tokens: switch with the crossfade. Swatch ring: opacity and scale 0.92 to 1. Segmented thumb: translateX | `ThemeBackgroundView` crossfade (0.28 s); ring 160 ms opacity, 220 ms scale `EASE_OUT`; thumb `springyFast` | Yes: `replaceThemes` already cancels an in-flight crossfade |
| M7 Counts arrive | Arc count finishes | Each count: opacity from the "-" placeholder to the number | 160 ms `EASE_OUT`, 40 ms apart. No rolling digits: numbers do not move | n/a |
| M8 Import progress | Each category finishes | Spinner replaced by a check: opacity 0 to 1, scale 0.8 to 1 | `springyFast`, in the real completion order (no fake timing) | n/a |
| M9 Sidebar fills | Import finished | Imported Favorites and rows: opacity 0 to 1, translateY 6 to 0 | `firm`, 30 ms apart, the first 12 items only; the rest appear without motion | n/a |
| M10 Key cap press | Tips 1 to 3 appear | Each key: translateY 0 to 2 and scale 0.96 over 90 ms `EASE_OUT`, then back with `springyFast`; second key 70 ms after the first | Plays once per tip, 260 ms after the tip appears | n/a |
| M11 Tour demos | Tips 4 to 6 appear | Swipe: finger dots fade in and slide 24 (360 ms `EASE_IN_OUT`), the sidebar pages over (`springy`). Split: chip travels 800 ms `EASE_IN_OUT`, drop zone fades in, then the page splits (200 ms fades). Favorite: chip travels 700 ms `EASE_IN_OUT` up into the Favorites row, the tile pops in with `springyFast` from scale 0.9 | Each demo plays twice, then rests on its end frame. They never loop forever | Leaving the tip stops the demo at once |
| M12 Finish | Start browsing, Skip setup | Card content: opacity to 0. Page surface: opacity 0 to 1. Ghost content: opacity 0.55 to 1. Command bar: its own normal presentation | Content 160 ms `EASE_OUT`; page 240 ms `EASE_OUT` at +80 ms; command bar after the page settles (+320 ms). Skip setup uses the same path, no extra flourish | n/a |
| M13 Press | Any button or swatch | Scale to 0.97 (swatches 0.95, icons 0.94) on press, back on release | 160 ms `EASE_OUT` (the existing press feel); no hover motion, only fill color | Yes |

Keyboard navigation (Return, Escape, arrows) runs the same transitions as clicks. This is deliberate: onboarding is a
once-per-install flow, not a 100-times-a-day shortcut, and the motion is what shows the direction of travel.

### 6.2 Reduce Motion

`NSWorkspace.accessibilityDisplayShouldReduceMotion`, read when each transition starts.

| ID | Reduce Motion variant |
|---|---|
| M1 | Every element fades in together, 250 ms `EASE_OUT`; no scale, no translation, no wipe |
| M2 | The field crossfades out (240 ms `EASE_OUT`) over the card and sidebar, which are already in place; no mask animation |
| M3, M4, M5 | Crossfade only: outgoing 200 ms, incoming 200 ms `EASE_OUT`; no translation. The progress dot jumps |
| M6 | The theme snaps (what `ThemeBackgroundView` already does under Reduce Motion); the swatch ring fades without scaling; the thumb jumps |
| M7, M8 | Fades only (200 ms); checks do not scale |
| M9 | Fades only, no translateY |
| M10 | No key press |
| M11 | No demo motion; each demo shows its end frame (the split page, the new Favorite, the second Space page) |
| M12 | Unchanged (it is already fades only) |
| M13 | No press scale; the pressed fill color still changes |

The settled frames are identical with and without Reduce Motion, so the end-state screenshots in section 14 cover
both.

### 6.3 Reduce Transparency and Increase Contrast

Onboarding uses opaque surfaces already (the brand field, the card, the command bar). With Reduce Transparency:

- the grain layer on the Welcome field and the window theme is hidden;
- the tour highlight becomes an opaque blend (#F1DE9F over light themes, #6A5A26 over dark themes) instead of
  mustard at 20-28 %;
- the command bar surface is fully opaque (`commandBarSurface` without alpha);
- ghost sidebar content keeps its 0.55 opacity (it is a state, not a material), but its fills use the opaque blend of
  `sidebarItemHovered` over the theme's first stop.

With Increase Contrast: secondary button borders and the count list border use `brandTextSecondary`; the focus ring
grows to 3 pt.

### 6.4 120 Hz rules

- Only layer `opacity` and `transform` change per frame, plus the fold's mask layer `bounds`, `position` and
  `cornerRadius`, which Core Animation renders on the render server. No `NSView` frame, constraint or text change
  happens during any animation.
- Each step's view is laid out once when it is created; transitions move its layer. Text is never re-laid-out or
  re-rendered mid-animation (no font size or weight animation).
- Every animation is a `CASpringAnimation` or `CABasicAnimation` on a layer, or a `SpringDriver` run where velocity
  must carry over. No timers drive frames. `ShellSignposts` intervals wrap M2, M3 and M12 so the existing frame
  pacing checks can cover them.
- Retarget, never restart: a new transition reads the presentation layer's current value as its `fromValue`.
- No blur, no shadow-path animation, no `CIFilter` during transitions.

## 7. Keyboard

| Key | Action |
|---|---|
| Return | The step's primary button (the default button). In the Name field, Return moves on like Continue |
| Escape | The step's secondary action: Skip, Not now, Start fresh, Skip tour. On Welcome: Skip setup. During an import: nothing |
| Right arrow | Next step, or next tip in the tour. Not in the import step before the import finished. Ignored while a text field has focus |
| Left arrow | Back, or previous tip. Ignored while a text field has focus |
| Tab, Shift-Tab | Moves focus through the card in reading order (section 8); Skip setup and Back are in the loop |
| Arrow keys in a radio group | Move the selection in the theme swatches, the appearance control and the icon row (roving focus, one Tab stop per group) |
| Space | Presses the focused button, toggles the focused checkbox |
| Command-W, Command-Q | Normal window and app behavior. Closing the window mid-setup keeps the flow's progress (section 10) |

The primary button gets initial focus on every step, so Return always does the expected thing without Tab. Full
Keyboard Access is not required to reach any control.

## 8. VoiceOver

The onboarding is one `NSAccessibility` group labeled "Welcome to Arkt", containing the current step only. The ghost
sidebar is hidden from accessibility until the flow ends. On each step change: post `layoutChanged` with the step's
title as the focused element, then the primary button takes keyboard focus.

Reading order per step: Back (when shown), title (heading), body, controls, secondary button, primary button, Skip
setup. The progress dots are not separate elements; the group's value reads "Step {n} of {total}".

| Element | Role | Label / value |
|---|---|---|
| Mark on Welcome | image | "Arkt" |
| Wordmark | hidden | (decorative; the title is "Welcome to Arkt") |
| Descriptor | static text | "A native macOS browser." |
| Count row | static text | "Spaces, 4"; while counting "Spaces, counting"; after import "Spaces, 4, imported" |
| Spinner, check | hidden | (state is in the row label) |
| Theme swatch | radio button | "Mist", "Paper"... selected state from the radio group |
| Appearance | radio group of two | "Light", "Dark" |
| Name | text field | label "Name", placeholder read as "Space 1" |
| Icon | radio button | "None", "Star", "Bookmark", "Folder", "Heart", "Bolt", "Book", "Globe", "Person" |
| Web Store option | checkbox | "Open the Chrome Web Store", help "It opens in a tab when setup ends." |
| Key caps | image | "Command T", "Command L", "Command W" |
| Tour demos | hidden | (the body text says it) |
| Tip count | static text | "1 of 6" |
| Back | button | "Back" |
| Skip setup | button | "Skip setup" |

Announcements (`announcementRequested`, medium priority): when counts arrive ("Found 4 Spaces, 37 pinned tabs, 12
Favorites and 9 folders."), when the import starts ("Importing from Arc."), when it ends ("Imported from Arc." or the
failure title), and at the end ("Setup finished. The command bar is open.").

Accessibility identifiers go in `AXID.Onboarding` (root, each step, each button) so UI tests can drive the flow the
way `AXID.EmptyState` is used today.

## 9. Help > Welcome to Arkt

The Help menu exists and is empty (`MainMenu.make`). Add "Welcome to Arkt" as its first item; no shortcut.

Re-entry runs the same flow over the frontmost window, with these differences:

- The Welcome field covers the window with M1 and folds with M2, but over the current page: the card shows the brand
  surface on a layer above the page; the page is not unloaded or navigated.
- Import step: shown when Arc is found. The body changes to "Arkt adds what's new in Arc. Spaces already in Arkt stay
  as they are." (true per the summary's `existingSpaces` and `previouslyImportedSpaces` rules). After it, the
  File > Import from Arc counts-only summary appears in the Imported state as on first run.
- Make it yours applies to the current Space and starts from its current theme, name and icon. Skip or Escape
  restores what it had.
- Default browser is left out when Arkt is already the default.
- Done: title "You're all set", body "Nothing else changed.", button "Back to browsing". It returns to the tab that was
  open; no new tab, no command bar.
- Skip setup and Escape on Welcome return to the tab with M12's fades.

## 10. State and persistence

- Shown automatically when the window's profile has no Space (the condition that shows `EmptyStateView` today) and
  the app default `onboardingCompletedVersion` is lower than the current flow version (1). The existing empty state
  remains the fallback for later windows with no Space.
- Existing users with Spaces never see it automatically.
- The current step id is saved as the user moves on. Quitting mid-flow resumes at that step on the next launch,
  without the Welcome reveal; an import that finished stays imported and the Import step shows its Imported state.
- `onboardingCompletedVersion` is written on Start browsing and on Skip setup.
- Opened windows other than the first during setup show the normal empty state; only one window runs the flow.

## 11. Parity with Arc

Arc's onboarding was not inspected for this design. Known rows:

| Topic | Arc (source) | Arkt | Note |
|---|---|---|---|
| Tour content | BH-211: Arc101 onboarding strings "Open your first tab", "Pin tabs to save for later", "Spaces for work and life", "Multitask with Split View", "Favorites keep your most used sites and apps close" / "Drag to add Favorites". SINGLE-SOURCE, order and gating unknown | Six tips: open a tab, the address, archiving, Spaces, Split View, Favorites | PARITY(NEEDS-RUNTIME-CHECK): order, whether Arc's tips are interactive, and whether pinning is a separate tip. Arkt drops "pin tabs" for "close by archiving", the habit that surprises new users most; easy to add as a seventh tip |
| Gestures and keys taught | KB-001, KB-002, KB-008, GS-001, GS-008, GS-011 (CONFIRMED) | Taught as in Arc | The behaviors exist; only the teaching is new |
| Default browser | BH-129 [S] NUX "Links Open in Little Arc" suggests Arc's onboarding touches default-browser handling | One optional step, system prompt | PARITY(NEEDS-RUNTIME-CHECK): where and how Arc asks. Little Arc routing is not part of this flow |
| Account | Arc's first run is reported to require an account | No account step | Deliberate difference: Arkt has no account. PARITY(NEEDS-RUNTIME-CHECK) |
| Import source | Arc's first run reportedly offers import from other browsers | Import from Arc only (Chromium profile data is #131) | Deliberate for now. PARITY(NEEDS-RUNTIME-CHECK) |
| Theme picking | Arc reportedly lets the user pick a Space color during first run | Make it yours step | PARITY(NEEDS-RUNTIME-CHECK) on Arc's exact picker; Arkt's theme set is its own |
| Visual style | Unknown | Brand field and in-window setup | Arkt's own design; not a parity target |

## 12. Implementation dependencies

1. **Count-only preview pass.** `ArcImportSummary` exists only after `ArcImportCoordinator.run`. The "live count"
   needs a read-only pass that returns Spaces, pinned tabs, Favorites and folders without writing anything (counts
   only, same privacy rule). Alternative if that is too costly: import first, then show what came over (see open
   question 1).
2. **Per-category progress.** M8 needs the importer to report category completion (or at least start and finish).
   If it cannot, all four checks appear together at the end, with the same stagger as M7.
3. **Default browser registration.** Nothing in the code sets the default browser today. Needs the URL scheme and
   document type registration in the app's Info.plist and `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)`
   (macOS shows its own confirmation), plus a check of the current default to leave the step out.
4. **Theme catalog.** Add the six families (light and dark) to `SpaceThemeCatalog` and pass `ShellTokensContrastTests`.
5. **Brand tokens.** Add the five proposed `BrandTokens` and their contrast tests.
6. **Help menu item** and an `AppCommands` action that starts the flow on the key window.
7. **Engine-only step.** The extensions step needs a build-configuration check (Chromium engine vs WKWebView shell).

## 13. Open questions

1. Live count before import (needs a preview pass in the importer) or "import, then show what came over"? The design
   assumes the preview; the fallback keeps every screen and drops the Ready state's numbers.
2. Should the import path also offer Make it yours, for the first imported Space? The design leaves it out because
   imported Spaces keep their Arc themes.
3. Extensions step copy: is naming no password manager right while #23 is open, or should it say "1Password, once
   signing is in place"? The design names none.
4. Tour length: six tips, or five with Command-L folded into tip 1? "The sidebar in 20 seconds" fits six at about 3
   seconds each only if users click through quickly.
5. The default first-Space theme: Mist (neutral, cool) is selected by default. Dune is the closest to the brand
   mustard; is a brand-colored default wanted?
6. Should Skip setup ask for confirmation? The design does not: everything is reachable later (File > Import from
   Arc, the Space header, Help > Welcome to Arkt).
7. Window size on first launch: the design asks for at least 1000 x 680 pt. Is that compatible with the current
   default window frame?

## 14. Screenshots

Rendered from the prototype with the project's Chromium build in headless mode, window 1120 x 720 pt at device scale 2
(2240 x 1440 px), settled end states (`?still=1&shot=1`), quantized to 256 colors. Files are in
[`design/onboarding/screens/`](../../design/onboarding/screens/).

| # | Step | Light | Dark |
|---|---|---|---|
| 01 | Welcome | [01-welcome-light.png](../../design/onboarding/screens/01-welcome-light.png) | [01-welcome-dark.png](../../design/onboarding/screens/01-welcome-dark.png) |
| 02 | Import, ready | [02-import-light.png](../../design/onboarding/screens/02-import-light.png) | [02-import-dark.png](../../design/onboarding/screens/02-import-dark.png) |
| 03 | Importing | [03-importing-light.png](../../design/onboarding/screens/03-importing-light.png) | [03-importing-dark.png](../../design/onboarding/screens/03-importing-dark.png) |
| 04 | Imported | [04-imported-light.png](../../design/onboarding/screens/04-imported-light.png) | [04-imported-dark.png](../../design/onboarding/screens/04-imported-dark.png) |
| 05 | Import failed | [05-import-failed-light.png](../../design/onboarding/screens/05-import-failed-light.png) | [05-import-failed-dark.png](../../design/onboarding/screens/05-import-failed-dark.png) |
| 06 | Make it yours | [06-theme-light.png](../../design/onboarding/screens/06-theme-light.png) | [06-theme-dark.png](../../design/onboarding/screens/06-theme-dark.png) |
| 07 | Default browser | [07-default-light.png](../../design/onboarding/screens/07-default-light.png) | [07-default-dark.png](../../design/onboarding/screens/07-default-dark.png) |
| 08 | Extensions and passwords | [08-extensions-light.png](../../design/onboarding/screens/08-extensions-light.png) | [08-extensions-dark.png](../../design/onboarding/screens/08-extensions-dark.png) |
| 09 | Tour 1, Open a tab | [09-tour-1-light.png](../../design/onboarding/screens/09-tour-1-light.png) | [09-tour-1-dark.png](../../design/onboarding/screens/09-tour-1-dark.png) |
| 10 | Tour 2, Go to the address | [10-tour-2-light.png](../../design/onboarding/screens/10-tour-2-light.png) | [10-tour-2-dark.png](../../design/onboarding/screens/10-tour-2-dark.png) |
| 11 | Tour 3, Close by archiving | [11-tour-3-light.png](../../design/onboarding/screens/11-tour-3-light.png) | [11-tour-3-dark.png](../../design/onboarding/screens/11-tour-3-dark.png) |
| 12 | Tour 4, Switch Spaces (end frame) | [12-tour-4-light.png](../../design/onboarding/screens/12-tour-4-light.png) | [12-tour-4-dark.png](../../design/onboarding/screens/12-tour-4-dark.png) |
| 13 | Tour 5, Split the view (end frame) | [13-tour-5-light.png](../../design/onboarding/screens/13-tour-5-light.png) | [13-tour-5-dark.png](../../design/onboarding/screens/13-tour-5-dark.png) |
| 14 | Tour 6, Keep Favorites close (end frame) | [14-tour-6-light.png](../../design/onboarding/screens/14-tour-6-light.png) | [14-tour-6-dark.png](../../design/onboarding/screens/14-tour-6-dark.png) |
| 15 | You're all set | [15-done-light.png](../../design/onboarding/screens/15-done-light.png) | [15-done-dark.png](../../design/onboarding/screens/15-done-dark.png) |
| 16 | Landing in the browser | [16-browser-light.png](../../design/onboarding/screens/16-browser-light.png) | [16-browser-dark.png](../../design/onboarding/screens/16-browser-dark.png) |
| 17 | Make it yours, no Arc (first step, no Back, 5 dots) | [17-theme-no-arc-light.png](../../design/onboarding/screens/17-theme-no-arc-light.png) | [17-theme-no-arc-dark.png](../../design/onboarding/screens/17-theme-no-arc-dark.png) |
| 18 | Tour 1 with Reduce Transparency (opaque highlight, no grain) | [18-tour-1-reduce-transparency-light.png](../../design/onboarding/screens/18-tour-1-reduce-transparency-light.png) | [18-tour-1-reduce-transparency-dark.png](../../design/onboarding/screens/18-tour-1-reduce-transparency-dark.png) |
| 19a | Fold (M2) paused at about 160 ms | [19-motion-a-fold-160ms-light.png](../../design/onboarding/screens/19-motion-a-fold-160ms-light.png) | [19-motion-a-fold-160ms-dark.png](../../design/onboarding/screens/19-motion-a-fold-160ms-dark.png) |
| 19b | Fold (M2) paused at about 320 ms | [19-motion-b-fold-320ms-light.png](../../design/onboarding/screens/19-motion-b-fold-320ms-light.png) | [19-motion-b-fold-320ms-dark.png](../../design/onboarding/screens/19-motion-b-fold-320ms-dark.png) |
| 19c | Step forward (M3) paused at about 100 ms | [19-motion-c-step-100ms-light.png](../../design/onboarding/screens/19-motion-c-step-100ms-light.png) | [19-motion-c-step-100ms-dark.png](../../design/onboarding/screens/19-motion-c-step-100ms-dark.png) |

Reduce Motion end states are identical to the ones above (section 6.2), so they are not duplicated.

## 15. Prototype

Open `design/onboarding/prototype.html` in a browser from a checkout (it loads the logos from `design/brand/logos`).
It has no network access and no dependencies.

- The bar above the window switches light and dark, Reduce Motion, Reduce Transparency and "Arc on this Mac", jumps
  to any step, and replays from the start.
- URL parameters: `appearance=light|dark`, `motion=reduce`, `transparency=reduce`, `arc=0`, `still=1` (no entrance
  motion), `shot=1` (window fills the viewport). Hash: `#welcome`, `#import`, `#importing`, `#imported`,
  `#import-failed`, `#theme`, `#default`, `#extensions`, `#tour-1` to `#tour-6`, `#done`, `#browser`.
- Springs are the `SpringPreset` values solved with the `SpringParameters` formulas and sampled into CSS `linear()`
  easings, so the curves are the spec, not an approximation. Transitions retarget from the current presented value;
  unlike `SpringDriver`, they do not carry velocity.
- Stand-ins: icons are simple SVG drawings in place of SF Symbols; the grain is a generated noise tile; Arc data is
  sample counts; the system default-browser prompt is not shown.
