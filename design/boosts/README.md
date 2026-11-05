# Boosts design

Per-site tweaks: page color, font, hidden elements, custom CSS and JavaScript (#645). The picked direction is A, a
panel from the address pill; "Code..." opens a code pane inside the card. Prototype: [`prototype.html`](prototype.html),
states by hash `#<editor|picker|code|small|manage>[&dark][&rm][&shot]`. Screens: `screens/boosts-<state>-<light|dark>.png`
(2x, 1080 x 720 window). The page and hosts are synthetic.

Everyday chrome: system font, shell tokens (`surface`, `overlayShadow`, `divider`, `fill`). Done is the one mustard
pill on each surface. The UI says "Hide", never "zap".

Not picked: B (inspector beside the page, kept only as the Code pane) and C (tray along the bottom).

## The panel

- **Anchor**: under the sidebar's address pill (the site's own control), 300 pt wide, 12 pt from the sidebar edge.
- **Header**: 28 pt brush tile (radius 8), "Boost", the host in secondary text, and an on/off switch for this site.
- **Page color**: 8 swatches, 24 pt circles, gap 8: Site colors (none), paper, sage, sky, lilac, rose, sand, night. The
  chosen one has a 2 pt ring in the text color, 4 pt outside the swatch (never mustard).
- **Font**: 4 cells (Site, Sans, Serif, Mono), 48 pt tall, radius 9, each showing "Aa" in its face; the chosen cell
  uses the current-row fill with a 1.5 pt text-color edge (porcelain in dark).
- **Hidden**: one 30 pt row per hidden element (eye-off glyph, label, Show). Under it: **Hide an Element...** (neutral
  pill) and **Code...** (quiet).
- **Footer**: Delete Boost (quiet, red title) and **Done** (primary). Changes apply at once; Done only closes.

## Tokens

Boost page colors follow the appearance: each has a light and a dark value, and the page text follows the appearance
(graphite on the light values, porcelain on the dark values and on Night). The swatches in the panel show the value
for the current appearance.

| Token | Light | Dark | Use |
|---|---|---|---|
| `BoostTokens.pageColorPaper` | `#F4ECDA` | `#2B2620` | page background |
| `BoostTokens.pageColorSage` | `#DCE7DA` | `#232B25` | page background |
| `BoostTokens.pageColorSky` | `#DCE6F2` | `#222831` | page background |
| `BoostTokens.pageColorLilac` | `#E6DEF0` | `#2A2530` | page background |
| `BoostTokens.pageColorRose` | `#F2DEDE` | `#2F2526` | page background |
| `BoostTokens.pageColorSand` | `#E9E1D2` | `#2A2721` | page background |
| `BoostTokens.pageColorNight` | `#202321` | `#202321` | page background |
| `BoostTokens.pageText` | `#202321` (graphite); secondary 64 % | `#FAF9F5` (porcelain); secondary 68 % | text on Paper, Sage, Sky, Lilac, Rose, Sand |
| `BoostTokens.pageTextOnNight` | `#FAF9F5` (porcelain); secondary 68 % | `#FAF9F5` (porcelain); secondary 68 % | text on Night |

"Site colors" (the first swatch) removes the color and keeps the site's own. A swatch has a 0.5 pt inner edge (black
18 % in light, white 28 % in dark) so the dark values and Night stay visible on the dark panel. The selected font cell
has a 1.5 pt edge in the text color: graphite in light, porcelain `#FAF9F5` in dark.

## Hiding an element (`picker`)

The panel steps aside. A 40 pt bar at the card's top center: cursor glyph, "Click what you want to hide", the count
("1 hidden"), Undo, **Done**. The hovered element gets a 2 pt system-blue outline (2 pt offset) and a 10 % blue tint; a
label rides on it with the element's name, its selector in monospace and a Hide pill. Esc or Done leaves picking.

## Code pane (`code`)

"Code..." opens a 300 pt pane at the card's trailing edge; the page reflows to its left. Header: code glyph, "Code",
host. A CSS / JavaScript segmented control, "Applied" status, a recessed editor (`listField`, radius 10) with line
numbers in system monospace 12 pt, then one line: "Runs only on <host>. JavaScript runs apart from the page's own
scripts." Footer: **Done**.

## Smallest window (`small`)

At 640 x 420 (150 pt sidebar) the panel keeps its 300 pt width, 8 pt from the window's leading edge, and caps its
height to the window (8 pt from the bottom). The middle (colors, fonts, hidden list) scrolls with a 28 pt faded edge;
the header and the footer with Done stay.

## Managing Boosts (`manage`)

The Library window (title "Library") uses the shared rail documented in `design/library-history/README.md`, "Library
window rail": Downloads, History, Spaces, Boosts, in that order. Boosts uses the brush glyph, the same as the panel header. Captures is not in the rail while the capture
destination question on #646 is open. The search field reads "Search Boosts". The Boosts section: one 56 pt row per site (32 pt site tile, host, a one-line summary, an on/off
switch, a more menu). Long hosts truncate; rows that are off are dimmed. The footer reads "Boosts change how a site
looks on this Mac. Each one runs only on its own site."

## States

| State | What it shows |
|---|---|
| `editor` | the panel open, paper color and serif applied, two hidden elements listed |
| `picker` | picking mode: bar at the top, the newsletter banner outlined with its label |
| `code` | the Code pane with CSS, the page reflowed |
| `small` | smallest window (640 x 420): the panel capped to the window, its middle scrolling |
| `manage` | Library window, Boosts selected in the rail, worst-case long host and an off row |

## Motion

Panel and pane: opacity plus scale 0.97 to 1 (the pane: translateX 12 to 0), 0.22 s on `firmFast`. A color or font
change applies instantly (no crossfade on the page). The picker outline follows the pointer with no animation.
Reduce Motion: opacity only, 0.15 s.

## VoiceOver

The panel is a dialog "Boost for <host>". The switch is "Boost on". Colors and fonts are radio groups ("Page color",
"Font"). Picking mode announces "Picking. Click an element to hide it"; the outlined element reads its label
("Newsletter banner"). Every hidden element is listed with Show, so picking is never the only way to undo. The code
editor is a multi-line text field "CSS for <host>".

## Answered questions (2026-11-05)

- Direction: A, the panel from the address pill.
- Custom code: "Code..." opens B's Code pane inside the card (the only part of B kept).

## Still open

1. JavaScript Boosts in the first release, or CSS only?
2. One Boost per host, or per path as well?
3. Does turning a Boost off from the address menu need a confirmation? (drawn: no)
