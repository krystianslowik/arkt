# Capture design

Region capture (KB-061, Cmd-Shift-2), hold Cmd-Shift and drag (with a setting), full page, and capture in Little Arkt
(#646). The picked direction is A: frame, adjust, capture. Prototype: [`prototype.html`](prototype.html), states by hash
`#<select|result|fullpage|little>[&dark][&rm][&shot]`. Screens: `screens/capture-<state>-<light|dark>.png` (2x,
1080 x 720 window). The page is synthetic.

Everyday chrome: system font, shell tokens. The selection frame is white on a scrim, never mustard. **Capture** is the
one mustard pill while capturing.

Not picked: B (capture bar first, result card) and C (drag and it is done, sidebar card).

## Flow

1. **Start**: Cmd-Shift-2 dims the page with the scrim (light `rgba(20,22,24,0.34)`, dark `rgba(0,0,0,0.50)`); drag a
   frame. Holding Cmd-Shift and dragging on the page (when the setting is on) skips the dock and captures on release.
2. **Adjust**: the frame is a clear window in the scrim with a 1 pt white edge and 8 handles (10 pt white circles). A
   size readout (22 pt, radius 6, dark capsule, tabular figures, "400 x 190") sits 28 pt above the frame's top edge.
3. **Dock**: 12 pt under the frame, 40 pt tall, radius 12, `surface` and `overlayShadow`: Full Page (quiet), a divider,
   Cancel (quiet), **Capture** with the Return glyph (primary). Return captures, Esc cancels.
4. **After**: the image is copied and saved to Captures; a toast with a 28 x 20 pt thumbnail, "Copied, and saved to
   Captures", and Show (quiet action). No shutter animation on the page.

## Full page (`fullpage`)

The page dims; a 320 pt panel in the card's center shows a thumbnail strip being assembled, "Capturing the full page",
"Part 3 of 7. Scroll stays where it is; the page is copied as it loads.", a graphite progress bar and **Stop** (neutral
pill). The result is the same toast.

## Little Arkt (`little`)

The same frame and dock inside the Little Arkt window. Its "Open in <Space>" pill turns neutral while capturing, so the
window keeps one primary (Capture).

## States

| State | What it shows |
|---|---|
| `select` | frame drawn over the figure, handles, size readout, the dock |
| `result` | the page back, the toast |
| `fullpage` | full-page capture in progress |
| `little` | capturing in Little Arkt, its Open in pill neutral |

## Motion

Scrim fades in 0.15 s; the dock and the toast use the existing panel and toast motion (opacity plus scale 0.97 to 1,
0.22 s on `firmFast`). Handles and the frame follow the pointer with no animation. Reduce Motion: opacity only.

## VoiceOver

Capture mode announces "Capture. Drag to select, or press Return for the visible page". The frame is an adjustable
element "Selected area, 400 by 190 points"; arrow keys move it, Shift-arrow by 10 pt, and it announces its size. The
dock is a toolbar "Capture". The toast is a status announced once.

## Answered questions (2026-11-05)

- Direction: A, frame, adjust, capture.
- Little Arkt: its "Open in" pill stays neutral while capturing (accepted).

## Still open

1. Where saved captures go: a Captures section in the Library only, or also a folder in Finder (drawn: both)?
2. Default for the hold-Cmd-Shift-and-drag setting: on or off?
