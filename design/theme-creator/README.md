# Space theme creator

Design for the Space theme creator (#382): a small popover where the user picks a Space's colours, texture and
opacity while the window behind it re-tints live. It extends the preset theme picker from #279 and uses the textures
from #120. The build is tracked in the issue that references this design.

- Prototype: [`prototype/index.html`](prototype/index.html). Open it in a browser. States by hash,
  `#<state>[&dark][&haptics]`, with state `two` (default), `single` or `none`. Everything is live: drag the dots,
  double-click the pad to add a second colour, drag a dot off the pad or use the header button to remove it, pick a
  texture, move the sliders. `&haptics` shows a small log of the haptic events the native popover plays.
- Screenshots: [`screens/`](screens/), at 2x. Index at the end of this document.
- Rejected directions, kept for history: [`directions/`](directions/).

## How it got here

The first round (`directions/v1-*`) tried three interaction models: a round dial close to the old picker, a
saturation and brightness pad with a hue strip, and editing in place on the window. All three showed contrast ratios,
warnings, hatched zones and "fix" suggestions, plus Light / Dark / Auto and preset lists. The maintainer rejected all
three as too complex: the user should not need to know about contrast; it should be automatic.

The second round kept three controls only (colour, texture, opacity) and varied the colour surface: a disc
(`directions/v2-a-*`), a soft pad (picked) and a hue ribbon with a Light slider (`directions/v2-c-*`).

## Look

One small popover, porcelain in light and graphite in dark, with a big tactile colour surface and two clean sliders.
No numbers, no warnings, no appearance switch, no preset list. The window behind it is the preview: the sidebar and
the window frame re-tint as the user drags.

Typeface: the system font, as in every AppKit view in the shell.

Brand rules:

- No mustard in this popover. It has no primary action: every change applies live, so there is nothing to confirm.
- No other browser's name anywhere the user can see: labels, accessibility text, menu items.
- Light and dark are both required. The stored theme is the same in both; what the window draws differs a little
  because of the automatic contrast rule.

## Layout

All sizes in points.

| Element | Size |
|---|---|
| Popover | 300 wide, height from content (about 286 with the pad), 18 corner radius, 14 padding, arrow 12 on the leading edge pointing at the Space name |
| Header | 24 high, 10 below it: the Space name (13 semibold, `primaryText`) and the colour-count button on the trailing edge |
| Colour-count button | 30 x 22, radius 7, `sidebarItemHovered` fill; two overlapping 12 pt swatches of the current colours, or one swatch and a "+" |
| Pad | 272 x 212, radius 16, 0.5 pt inner edge, soft inner shadow (3 pt down, 14 blur, 12 % black) |
| Colour dot | 26 diameter, 3 pt white ring, shadow 2 down / 8 blur; 34 while dragged, shadow 8 down / 22 blur |
| Link line | 1.5 pt white at 85 % between the two dots |
| Section label | 12 semibold, `secondaryText`, 18 high row, 8 below it; 16 between sections |
| Texture swatches | five 18 pt circles, 6 apart, on the label row's trailing edge; the selected one has a 1.5 pt accent ring 2 pt out |
| Slider track | full width, 10 high, radius 5, 0.5 pt inner edge |
| Slider knob | 24 diameter, white, 0.5 pt edge, shadow 2 down / 6 blur |

Order top to bottom: header, pad, Texture (label row with swatches, then the amount slider), Opacity.

## Where it opens

The Space header menu (`SpacePageView`, "Space Options") keeps its Theme submenu from #279 and gains one item at the
end, after a separator: **Edit Theme...**. Choosing it opens the popover anchored to the Space name in the sidebar.
The preset items stay: a preset is a quick start, the creator is for everything else. Picking a preset while the
popover is open moves the dots to that preset's colours.

The first-run theme step (onboarding) is unchanged.

## Colour pad

**Mapping.** Horizontal position is hue, 0 to 360 degrees left to right. Vertical position is tone: in the middle
band the hue sits at a fixed saturation (HSL 60 %, lightness 52 %); above the middle it blends toward porcelain
`#FAF9F5`, below toward near-black `#121214`. The pad draws exactly this field, so a dot shows the colour it stores.

**One or two colours.** A theme has one or two colours. With two, the window draws a gradient from the first colour at
the top leading corner to the second at the bottom trailing corner, as `SpaceThemeInfo.baseColors` does today, and a
thin line joins the dots.

- Add the second colour: click the colour-count button (one swatch and "+"), or double-click an empty spot on the pad.
  The new dot springs out of the first one to 40 degrees of hue away and a quarter of the pad's height toward the
  middle (from the button), or appears where the user double-clicked.
- Remove it: click the colour-count button (two swatches), drag a dot more than 24 pt outside the pad and let go (it
  fades to 35 % while outside to say it will go), or press Delete with a dot focused. The last dot cannot be
  removed.

**Dragging.** A dot follows the pointer with no lag and no easing. The top 6 % and bottom 6 % of the pad cannot be
reached: there the colour is too close to white or black to read as a theme. The dot rests on that limit with a
soft haptic stop (below). Hue wraps at the pad's edges only by keyboard; the pointer clamps at the edge.

**Themes from elsewhere.** A preset or imported theme may hold colours that are not on the pad. Opening the creator
places each dot at the nearest point of the pad (same hue, closest tone) and does not change the theme until the user
moves a dot. A theme with more than two colours shows its first and last; moving either writes a two-colour theme.

## Texture

Five swatches: None, Grain, Sand, Denim, Tweed (the textures from #120). The slider under them is the amount, 0 to
100 %, stored as `noiseFactor`. With None the slider is disabled at 40 % opacity and keeps its value, so switching
back restores it. The slider track previews the selected texture fading in from left to right.

## Opacity

How strongly the theme covers the window surface, 0 to 100 %: 0 is the plain window surface, 100 is the colours at
full strength. The track shows the current colours fading in over a checkerboard. Default 80 % for a new theme.

## Automatic contrast

The user never sees a ratio, a warning or a fix. The window keeps sidebar text readable on its own, at draw time,
for every Space theme (presets pass unchanged; `ShellTokensContrastTests` already measures them).

Rule, per colour of the theme, in the current appearance:

1. Composite the colour at the theme's opacity over the window surface (porcelain in light, graphite in dark).
2. Measure `primaryText` (composited at its own alpha) over that, with WCAG 2.x contrast, the same `Contrast.ratio`
   the contrast tests use. Target 4.5:1; 7:1 when Increase Contrast is on.
3. If it falls short, mix the colour toward near-black `#121214` (when the text is light) or porcelain `#FAF9F5`
   (when the text is dark) in 1 % steps until it passes, at most 50 %.
4. If any colour of the theme would need more than 50 % in the appearance's own text tone, flip the sidebar text
   tone for this Space (dark text on a pale theme in dark mode, light text on a deep theme in light mode) and run
   step 3 again with the flipped tone.

As built (#410), one check comes before step 3: when either text tone already reaches the target with no mix for
every colour (the appearance's own tone first), that tone is used and nothing is mixed. Without it a dark preset in
light mode would be mixed 35 to 49 % toward porcelain instead of keeping its light text, and the presets would not
pass unchanged. It also means a theme whose own tone would need a small mix but whose other tone passes as it is
takes the other tone, unmixed. The design's example below draws the same with or without it.

The stored colours never change: the adjustment is applied when drawing, so a theme looks right in both
appearances and nothing drifts each time the popover opens. Secondary sidebar text and glyphs follow the same tone.
The popover's own swatches show the stored colours.

Example from the screenshots: the stored colours are a deep blue and a copper. In dark mode the copper is drawn darker
so white tab titles stay readable; in light mode the blue is drawn lighter so dark titles stay readable.

## Haptics

Played with `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime: .now)`, only while the pointer drags
a control. They are felt on a Force Touch trackpad and do nothing elsewhere; keyboard changes play none. Nothing on
screen refers to them.

| Event | Pattern | When | Rate limit |
|---|---|---|---|
| Slider detent | `.generic` | Texture amount or Opacity reaches or crosses 0, 50 or 100 % | Once per crossing; re-armed after the value moves 3 % away from that stop |
| Preset hue | `.alignment` | The dragged dot's hue crosses the hue of a preset family (computed at launch from `SpaceThemeCatalog.families`: the HSL hue of each family's second light stop, today Paper 37, Dune 45, Sage 107, Mist 238, Indigo 250, Blossom 338) | Once per crossing; re-armed after 6 degrees; skipped when the hue jumps more than 30 degrees in one event (a fast fling) |
| Tone limit | `.levelChange` | A dot arrives at the pad's top or bottom limit | Once per arrival; re-armed after the dot moves 4 pt away from the limit |
| Texture step | `.alignment` | The selected texture swatch changes | Once per change |

Global limit: at most one haptic every 50 ms. An event inside that window is dropped, never queued. The prototype
plays the same events into its `&haptics` log.

## Motion

| Transition | Motion |
|---|---|
| Popover opens | Scale 0.96 to 1 and fade in from the arrow, `SpringPreset.springyFast` (0.80 / 0.18 s). Laid out on the first frame. |
| Popover closes | Fade out, 0.12 s. |
| Dot picked up | 26 to 34 pt and a deeper shadow, `springyExtraFast`; the same spring back on release. |
| Live re-tint | Window gradient, texture and sidebar text follow every drag event with no animation, coalesced to the display refresh (120 Hz on ProMotion); implicit layer actions off. |
| Programmatic change | Adding or removing a colour, picking a preset, a text tone flip: the window gradient animates 0.25 s with `firm`; a tone flip cross-fades the sidebar text 0.2 s. |
| Second dot appears | Springs out of the first dot to its spot, `springy`. |
| Dot removed | Shrinks to 0 and fades, 0.15 s. |

Animate transform and opacity only. **Reduce Motion**: the popover fades without scaling, dots appear and disappear in
place with a fade, a tone flip is instant. Live re-tint is direct manipulation and stays as it is. **Reduce
Transparency**: the popover is already opaque.

## Accessibility

- The popover is a dialog labelled "Space Theme", titled with the Space name. Focus starts on the first dot.
- Tab order: colour-count button, dots, texture swatches, Texture amount, Opacity. Escape closes the popover; every
  change is already applied. After closing, Edit > Undo reverts the whole session as one step.
- The pad is a group labelled "Colour". Each dot is an adjustable element, "Colour 1" or "Colour 2", whose value
  reads a plain colour name and tone, for example "blue, light 26 percent". Left and Right change hue by 2 degrees
  (wrapping), Up and Down change tone by 2 %, with Shift by 10 and 10 %; increment and decrement change tone. Delete
  removes the focused dot when there are two.
- The colour-count button reads "Add a second colour" or "Use one colour".
- Texture is a radio group ("None", "Grain", "Sand", "Denim", "Tweed"); arrows move the selection. "Texture amount"
  and "Opacity" are sliders that read percentages; Texture amount is disabled with None.
- The automatic contrast rule keeps sidebar text at 4.5:1 or more (7:1 with Increase Contrast) in both appearances.
- Haptics are never the only signal: every state they mark is visible.

## Tokens to reuse

- Shell tokens: find them with `grep -rn ShellTokens app/ArktShell/ShellKit/Sources`. Reuse `primaryText`,
  `secondaryText`, `sidebarItemHovered` (button and slider track fill), `overlayShadow` and `overlayEdge` (popover
  shadow and edge), `themeTextureMaxOpacity` and the texture kinds with their `alphaScale`.
- Popover surface: a new pair, porcelain `#FAF9F5` in light (`surfaceBrand`) and `#262927` in dark.
- Brand colors: [`design/brand/tokens/brand-tokens.json`](../brand/tokens/brand-tokens.json). The pad's top end is
  porcelain; its bottom end `#121214` is new and belongs with the theme code, not the brand.
- Focus and selection: the system focus ring and `controlAccentColor` for the selected texture swatch.
- Springs: `Motion/SpringPreset`.
- Contrast: `Contrast.ratio` and the probe in `ShellTokensContrastTests`.

## Data the build needs

`SpaceThemeInfo` already has `baseColors`, `texture` and `noiseFactor`. The stored model (`SidebarModel.SpaceTheme`)
does not keep `noiseFactor`: the bridge writes 0.5 for any texture. The build adds to `SpaceTheme`, with defaults that
decode old files unchanged:

- `noiseFactor: Double` (default 0.5 when a texture is set, as today)
- `opacity: Double` (default 1, so existing themes look the same)

The text tone flip of step 4 is derived when drawing; it is not stored.

## Screenshot index

| File | State |
|---|---|
| `screens/pad-light.png`, `screens/pad-dark.png` | Two colours (a deep blue and a copper), Sand at 40 %, opacity 80 % |
| `screens/single-colour-light.png`, `screens/single-colour-dark.png` | One colour; the colour-count button offers "+" |
| `screens/texture-none-light.png`, `screens/texture-none-dark.png` | Texture None: no texture on the window, the amount slider disabled |
| `directions/v1-1-orbit-*.png` | First round, rejected: round dial |
| `directions/v1-2-field-*.png` | First round, rejected: pad with hue strip and contrast meter |
| `directions/v1-3-in-place-*.png` | First round, rejected: editing in place on the window |
| `directions/v2-a-disc-*.png` | Second round, not picked: disc |
| `directions/v2-c-ribbon-*.png` | Second round, not picked: hue ribbon with a Light slider |
