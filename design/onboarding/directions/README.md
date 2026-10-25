# Onboarding: three directions

The first-run design restarts from arkt.dev. These are three directions for Welcome and Import only, in light and
dark, at 2x of a 1120 x 720 pt window. The maintainer picks one, then the full flow gets built in it. The rejected
card wizard (`../screens/`, `../prototype.html`) stays until then.

The product decisions don't change: import from Arc with a live count first, a theme step (also after import), no
named password manager, five tour tips, Dune as the default theme, Skip setup confirms and reverts the preview, a
window of at least 1000 x 680, and full Reduce Motion, Reduce Transparency and Increase Contrast variants.

| Direction | Pitch | Welcome | Import |
|---|---|---|---|
| [Chapter](chapter/) | Every step is a chapter of the site: a big left column, the formation on the right | [light](chapter/welcome-light.png), [dark](chapter/welcome-dark.png) | [light](chapter/import-light.png), [dark](chapter/import-dark.png) |
| [Hero](hero/) | Every step is the site's hero: one centred message, and the live count is a particle sculpture | [light](hero/welcome-light.png), [dark](hero/welcome-dark.png) | [light](hero/import-light.png), [dark](hero/import-dark.png) |
| [Acts](acts/) | The whole flow is one pinned chapter like "The feel": the steps are large words, and that list is the wayfinding | [light](acts/welcome-light.png), [dark](acts/welcome-dark.png) | [light](acts/import-light.png), [dark](acts/import-dark.png) |

Open any `index.html` from a local web server at the repository root (the field samples the logo PNGs, which a
`file://` page can't read). Query parameters: `?step=welcome|import`, `?theme=light|dark`, and `?still=1` to settle
the field for a capture. "Get started" plays the Welcome to Import change live.

All three share one base: `_shared/base.css` holds the site's tokens, type and buttons, `_shared/field.js` holds the
particle field, and `_shared/flow.js` holds the step plumbing and the live count. They differ in structure, not in
palette.

## Language extraction

What makes arkt.dev feel premium:

- **One typeface, set large and tight.** Avenir Next, Demi Bold (600) for every headline and Regular (400) for copy.
  Headlines run 72 to 132 px at a line height of 0.92 to 0.98 and track in hard (-0.045 to -0.055 em). The scale
  jumps: a huge headline, then 18 to 20 px copy, with nothing in between.
- **The field is the stage.** One full-screen particle field carries the page. Every chapter is a shape built from a
  real thing (the countdown digits, Arc's sidebar data, the Space rooms, the logo sampled pixel by pixel), and the
  motes keep moving inside it. Ink motes sit at low alpha and mustard appears as sparse sparks. Text over the field
  gets a soft halo in the background colour instead of a card behind it.
- **Few, confident controls.** Buttons are 50 px pills, 600 weight at 15 px, mustard fill with graphite labels, and
  scale to 0.97 when pressed. The secondary is a glass ghost pill with a hairline. There is no other button style.
- **Colour is three things.** Porcelain #FAF9F5, graphite #202321, and mustard #E9B520 only as a fill or a spark.
  Accent text is #8A5A0E on porcelain. Hairlines are the ink at 12 %.
- **Structure is quiet.** Lists are hairline rows with a bold name and a muted detail. There are no boxes, no shadows
  on content and no step dots. The navbar is a floating glass capsule that only appears once you move.
- **Copy is short and plain.** One idea per screen, short declarative sentences, no instructions such as "Click",
  and no em-dashes. Brand lines stay verbatim ("A native macOS browser.").
- **Motion is choreographed.** Words resolve one by one from blur (45 ms apart), springs drive everything that
  moves, and the one big moment per section is the field changing shape.

What made the rejected onboarding feel generic:

- **System UI type at system UI sizes.** SF at 28 px over 15 px body copy is a settings sheet, not the brand. The
  site never sets a headline under 38 px.
- **A card inside a window.** A centred 440 px column in a bordered card, with a ghost sidebar around it. The
  particles were decoration behind the card, not the stage.
- **Small macOS buttons.** 32 px rounded rectangles with an outlined secondary read as a dialog. The site uses
  50 px pills.
- **Wizard chrome.** Progress dots, Back in a corner and a boxed four-row count table are the template every
  onboarding uses.
- **Too many words.** Two-sentence bodies on every step, centred, at 400 px wide.

## Typeface and licence

The directions use Avenir Next, the website's face. It ships with macOS in `/System/Library/Fonts` (a core system
font, not an on-demand download), so the app can use it by name (`AvenirNext-Regular`, `AvenirNext-DemiBold`)
without bundling anything. It must not be bundled or redistributed: it is a Monotype face licensed to Apple for use
on the Mac, and the app gets it from the system the same way it gets SF. On the off chance it is missing, fall back
to the system font.

This settles a question `design/brand.md` leaves open ("use `website` on the website and `sans` everywhere else
until one family is chosen for both"): picking any of these directions picks Avenir Next for the first run, so
`brand.md` should be updated to match.

## Motion, shared by all three

- Every mote is a spring toward its target (damping about 0.86 to 0.9, response 0.35 to 0.9 s, in line with
  `firmSlow` and `firmExtraSlow`). A new formation retargets from where each mote is, with its velocity, so a step
  change can be interrupted at any moment. The simulation sub-steps at 240 Hz so it holds on a 120 Hz display.
- The outgoing step's text leaves fast (220 ms fade and blur). The incoming one resolves word by word (700 ms
  strong ease-out, 45 ms apart), as on the site.
- Reduce Motion: nothing travels. Motes fade out, move and fade back in, and text cross-fades without blur or
  movement. Reduce Transparency makes the ghost button and capsule solid. Increase Contrast raises the muted text
  and hairlines and, in Acts, lifts the faded step words.
