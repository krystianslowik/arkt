# Historical direction comparison

This comparison records the original alternatives and recommendation. The maintainer chose C for pinned actions and B for install; the [spec](../README.md) supersedes the recommendation below. The original [prototype](../prototype.html) and [screens](../screens/) retain the alternatives so existing links continue to work.

## Alternatives

| | A. Strip under the address | B. Tiles in the Favorites grid | C. One button and a panel |
|---|---|---|---|
| Idea | small icons where the page's address already is | extensions are tiles like Favorites | no persistent icons; one calm place |
| Pinned actions | 28 pt hit targets (24 pt icon, radius 7), gap 4, up to 4 visible, a puzzle button at the trailing end opens the panel | 38 pt tiles in the Favorites grid's second row (4 columns), 20 pt icon, the 4th slot is the puzzle button | none in the sidebar; the Extensions button (28 pt, bottom bar, trailing) opens a 316 pt panel |
| Badge and attention | 15 pt capsule at the icon's top trailing corner, dot for "needs access" | same, on the tile | in the panel row: the status line ("12 clips on this page", "Needs access to this site") |
| Order | drag an icon; a 2 pt insertion mark shows the target; the lifted icon scales to 1.12 | drag a tile; the old slot shows a recessed outline | drag a row by its grip; a 2 pt insertion line |
| Overflow | beyond 4 pinned, the rest go to the panel (the puzzle button) | beyond 3, the rest go to the panel | always in the panel |
| Install | compact window sheet 420 pt: name, publisher and rating, a recessed "It can" list, Open in Web Store, Cancel, Add Extension | window sheet 460 pt: 52 pt icon, rating, users and size, permission rows with a plain explanation, a "Show in sidebar" switch (on), Cancel, Add Extension | panel anchored to the Extensions button, 320 pt: centered icon, permissions field, full-width Add Extension (primary) over a full-width Cancel |
| Best for | the common case: a few extensions, one click | people who live in a few extensions | people with many extensions, a minimal sidebar |
| Cost | competes with the address pill | uses the Favorites area's height | one more click to reach an extension |

Recommendation: A for pinned actions with the C panel as its overflow, and the A sheet for install (shortest; the
permission list is the same content as B's rows, and B's "Show in sidebar" can be a quiet toggle later). The A sheet
replaces the Views prompt one for one (`ExtensionInstallPrompt` ShowDialogCallback), so it is also the cheapest to build.

