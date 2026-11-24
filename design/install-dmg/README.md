# Install DMG window (draft, directions only)

Issue #983. The Finder window that opens when a user mounts `Arkt-0.1.0-preview.1-arm64.dmg`. Three directions are
here for the maintainer to pick from; nothing is built yet.

## Gate

- **Surface:** a moment surface (hero style, Avenir Next, brand art). The DMG's Finder window: a fixed background
  image, the Arkt app icon, an alias to `/Applications`, and the volume icon.
- **States:** Finder light and Finder dark (Finder draws the icon labels, so the art must hold both label colors);
  Retina and non-Retina (the shipped background is a multi-resolution TIFF from `background.png` 660 x 420 and
  `background@2x.png` 1320 x 840); one fixed window size, no scrolling, no toolbar, no sidebar.
- **Primary action:** drag Arkt onto Applications. The arrow is the only instruction; no text says "drag".
- **Open questions (maintainer):**
  1. Include the first-open hint (Privacy & Security > Open Anyway, #125) in the art, or keep it in the release
     notes? B and C show it, A leaves it out. It is baked into the image, so it must be removed when builds are
     notarized.
  2. Direction (A, B or C) and window size (660 x 420 pt content proposed).
  3. Volume name: `Arkt` or `Arkt 0.1.0 preview`.
  4. Label readability approach (below): accept a mid-tone label zone in every direction?

## Window

Content size **660 x 420 pt** (title bar excluded, no toolbar or status bar). Icon size **128 pt** in all three
(Finder draws the macOS icon canvas at that size, so the tile itself is about 103 pt). Text size 12 pt. Coordinates
below are icon centers, in points from the content top-left, which is what the Finder layout `position` takes.

| | Arkt.app | Applications | Arrow (drawn in art) | Label zone (art) | Hint |
|---|---|---|---|---|---|
| A porcelain | (190, 214) | (470, 214) | x 306 to 352, y 214, centered at x 330 | full-width band, y 272 to 312 | none |
| B mustard | (190, 196) | (470, 196) | x 306 to 360, y 196 | full-width band, y 248 to 300 | centered, y 350 to 368 |
| C graphite | (190, 200) | (470, 200) | x 304 to 360, y 200 | wells 150 x 28 at x 115 to 265 and 395 to 545, y 262 to 290 | centered, y 352 to 370 |

Labels sit about 76 pt below each icon center (Finder: icon bottom plus about 12).

## Label readability (the uncertain part)

Finder draws labels in the system appearance and ignores the background: black text in light mode, white in dark
mode (this is the usual behavior with a picture background; it has not been verified on a mounted DMG here, because
no DMG is built yet). A light band fails in dark mode and a dark band fails in light mode. A tone with relative
luminance near 0.18 (about `#767676`) gives black and white text the same contrast, about 4.6:1. Every direction
therefore puts the label zone on one mid-tone:

- A: stone `#767571` shelf under the icons (black 4.6:1, white 4.6:1).
- B: the brand fold shadow `#A96E12` band (black 4.9:1, white 4.3:1).
- C: `#767A77` wells under each label (black 4.8:1, white 4.4:1).

Finder's own selection pill and 2-line wrapping for long names still draw over the zone; the zones are taller than one line.

## Directions

- **A, porcelain minimal.** `#FAF9F5`, graphite wordmark, a hairline arrow, a stone shelf the icons stand on, lots of
  air. No hint.
- **B, mustard hero.** `#E9B520` field with folded bands in `#F3CA3D` and `#DCA319`; the label zone is the `#A96E12`
  fold band. Bold graphite arrow. Hint in graphite on mustard (about 10:1).
- **C, graphite.** `#202321`, ivory wordmark, a mustard arrow (a fill), plates under the labels. Hint in `#B9BDB8`.

Type: the hint is Avenir Next 400 to 500 at 12.5 to 13 pt, rasterized into the background (no font is bundled).
The wordmarks are the outlined vectors from `design/brand/vector/wordmarks/`.

## Volume icon

`.VolumeIcon.icns` is the app icon: build it from `design/brand/vector/macOS/mustard-on-white.svg` (the same source
as the `AppIcon` asset), with the volume's custom-icon flag set. The mock draws the real app icon; the Applications
icon in the mocks is a stand-in, Finder draws the real one.

## Files

| Path | What it is |
|---|---|
| `directions/<a\|b\|c>/background.html` | The bare background (what ships), 660 x 420 pt |
| `directions/<a\|b\|c>/background.png`, `background@2x.png` | The bare background at 1x and 2x |
| `directions/<a\|b\|c>/mock.html` | Finder window mock with icons, labels and a title bar; `#light` (default) or `#dark` |
| `directions/<a\|b\|c>/finder-light.png`, `finder-dark.png` | 2x renders of the mock (732 x 520 pt canvas) |
| `directions/shared/` | Mock-only CSS and the Applications folder stand-in |

Renders: headless Chromium (Playwright's `chrome-headless-shell`), `--force-device-scale-factor=2`, offline, with
`--window-size=732,520` for the mock (`660,420` for the background) and `--screenshot`.
