# Downloads design

The native Downloads UI (#132): progress at the bottom of the sidebar (BH-180), the Library window or panel with its
last section remembered (BH-181, KB-065), the download location (BH-182) and the dangerous-file warning. Three
directions are drawn for the maintainer to pick from; none is built yet. The prototype is
[`prototype.html`](prototype.html) (open it in a browser; Prev and Next step through every state). States by hash,
`#<a|b|c>-<progress|multi|finished|danger|library|library-empty>[&dark][&rm][&shot]`, plus `#b-closed`, `#location`
and `#location-ask`. Chromium's download shelf and bubble stay hidden in Arkt windows.

Everyday chrome: the system font, the shell's tokens, neutral pills. Mustard appears only as a fill: the one primary
pill of a surface (Delete Download, Open Downloads Folder, Open on the selected Library row) and, in A and C, the
progress bar fill. Direction B draws progress in graphite. All data is synthetic.

## Directions

| | A. Progress row | B. Library button ring | C. Stacked cards |
|---|---|---|---|
| Idea | one quiet row where the eye already is | no new row; the Library button is the progress | each download is a small card |
| Sidebar, active | row 58 pt: tile 28, name 13 medium (middle-truncated), "42 MB of 310 MB / 2 min left" 11.5, 3 pt bar, cancel x 24 | the 28 pt Library button gets a 2.2 pt graphite ring that fills; click or hover opens a 316 pt popover | card radius 12, tile 36, name, "42 of 310 MB", 4 pt bar, "2 min left" and speed, cancel x |
| Several at once | a header row "3 downloads" with one aggregate bar; expands to compact rows (22 pt tile, 3 pt bar) | the ring shows the total; the popover lists every file | the newest card, then a "2 more" stack with one aggregate bar |
| Finished | row turns into name, "Done, 212 MB", a neutral Open pill (24 pt) and a Show in Finder icon button; x dismisses | ring completes into a check with a dot; the popover shows Show in Finder per file | card with Open and Show in Finder neutral pills side by side |
| Failed | "Failed, Connection lost" and a Retry pill | popover row with a Retry pill | card with a Retry pill |
| Footprint | 58 pt per download at the bottom; stack grows upward over the tab list with a fade | zero when idle; one button | 100 pt per card; most visible |
| Library | window 800 x 540: section rail (Downloads, History) and a list of 56 pt rows | panel 600 x 456 over the page, like the command bar: search, section control, grouped list | window 800 x 540 with a grid of file tiles (3 columns, 52 pt type tile) |
| Best for | the common case, calm and familiar | people who download rarely and want chrome to stay empty | people who download a lot and want big targets |
| Cost | rows push tabs up | progress is easy to miss at 28 pt | tallest; most competition with tabs |

Recommendation: A for the sidebar and the Library window, because it matches the sidebar's rows and the Archive's list
and costs the least new vocabulary. B is the quietest; C reads best for large files.

## States (every direction)

`progress`, `multi`, `finished` (a done file and a failed one), `danger`, `library` (two active, done, selected, failed,
yesterday), `library-empty`. Worst cases drawn: a 71-character file name, a 2.4 GB file, a failed download, three
active at once, a blocked file. The smallest window shrinks the tab list behind the download rows (they fade under the
rows); the rows never shrink below the sidebar's width.

## Behavior

- **Start**: a download goes to the Library, never to a tab (BH-180). The row, ring or card appears at once; the
  window does not take focus. Several downloads at once aggregate (A header, B ring total, C stack).
- **Active row**: name (middle-truncated, the extension stays visible), "amount of total, time left", cancel. Speed shows
  in C and the Library only. Time left reads "20 s", "2 min", "1 h 05 min"; under 3 s it reads "Almost done".
- **Cancel**: the x cancels at once and removes the row; the partial file is deleted. No confirmation.
- **Finished**: Open (opens with the default app), Show in Finder (reveals it), x dismisses the row. The row stays
  until dismissed or until 60 s pass without the pointer over the sidebar, then collapses to the Library button's dot
  (B always shows the dot). Opening the Library clears the dot.
- **Failed or cancelled by the network**: "Failed, <reason>", Retry (restarts from the same URL, resuming if the server
  allows), x removes it. The Library keeps failed items until cleared.
- **Library**: Cmd-Shift-L opens it, Cmd-Shift-J on Downloads, Cmd-Y on History (KB-065). It reopens on the section used
  last (BH-181). Hovering the Library button for 0.4 s lists the 6 most recent files in the popover (A and C reuse the B
  popover for this; BH-180). Rows: Open, Show in Finder on hover or selection, Retry on failed, cancel on active.
  Return opens the selected file, Cmd-Return shows it in Finder, Delete removes it from the list (not from disk).
  Clear List removes every finished row from the list and leaves the files.
- **Location (BH-182)**: Settings, General, Downloads: "Ask Where to Save" (the system save panel opens for each
  download) or "Save to Folder" with a pop-up (Downloads, Desktop, Other...) and Choose.... If the folder is missing or not
  writable, the download falls back to Downloads and a toast says so ("Saved to Downloads. The chosen folder is
  unavailable."). The Library footer shows the current place and a Change... link that opens the same pane.
- **Dangerous file**: the file is held, never opened, and the row reads "Unsafe file" with a Review pill. Review opens a
  window sheet: title "Arkt blocked "<name>"", the kind, size and host, a plain sentence, and three answers. The one
  primary is **Delete Download** (the safe answer, Return). Show in Finder is neutral. **Keep Anyway** is a quiet red
  text link at the leading edge, never the default, and needs a second Return or click. Uncommon but not dangerous files
  show a plain row note ("Not commonly downloaded") and Keep or Delete in the Library, with no sheet.
- **Empty Library**: 44 pt tile, "No downloads yet", one primary pill, Open Downloads Folder.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Row, card or popover appears | opacity 0 to 1 and translateY 8 to 0, 0.24 s on `firm` `cubic-bezier(0.25, 1, 0.5, 1)`; popover scale 0.97 to 1, 0.22 s | opacity only, 0.15 s |
| Progress | bar scaleX or ring dashoffset eases to the new value in 0.5 s, linear, every update | jumps to the value |
| Finished | the bar is replaced by the actions with a 0.12 s cross-fade; no celebration | same |
| Remove | opacity to 0 and the rows below move up, 0.16 s, ease-out | opacity only |
| Library opens | window: AppKit's own; panel: opacity and scale 0.97, 0.22 s | opacity only |
| Button press | scale 0.97 (pill) or 0.94 (icon), 0.12 s | none |

Transform and opacity only. Every motion is interruptible: a new update retargets the bar from where it is.

## VoiceOver and accessibility

- A row or card is a group labelled "Downloading <name>, 13 percent" (finished: "<name>, finished"; failed: "<name>,
  failed"; blocked: "<name>, blocked"). The bar is a progress indicator with min, max and value.
- Progress announces at 25, 50, 75 percent and on finish or failure (polite), never on every tick.
- Buttons: "Cancel download", "Open", "Show in Finder", "Retry", "Remove from list", "Review". The Library button reads
  "Library, downloading 13 percent" or "Library, downloads finished".
- The popover and the Library panel are dialogs; Esc closes them and focus returns to the button. The Library list is a
  list with arrow-key selection. Focus rings are the system's, never mustard.
- Color never carries state alone: the glyph and the words say failed or blocked. No contrast values appear anywhere.

## Light and dark

Light: porcelain surfaces, rows in `sidebarItemBackground`. Dark: graphite `#202321`, white text at 84 %. The file tiles
use fixed mid-tone fills with white text in both. The Library window and popover use `surfaceBrand`; Increase Contrast
adds a 1 pt `separatorIncreasedContrast` edge to rows and cards.

## Open questions for the maintainer

1. Which direction (A, B or C) for the sidebar and for the Library; they can be mixed (for example A with the B popover).
2. Progress fill in mustard (A and C, drawn) or graphite (B, drawn)? Mustard is a fill here, but it is not a pill.
3. Do finished rows auto-collapse after 60 s (drawn) or stay until dismissed?
4. Is "Keep Anyway" offered at all, or is a blocked file only deletable?
5. Is the Library window one window per app (drawn) or one per Space?
6. Tidy Downloads (OS-02, renaming) is out of scope here.

## Files

| Path | What it is |
|---|---|
| `prototype.html` | Single-file prototype, no network, synthetic data |
| `screens/downloads-<state>-<light\|dark>.png` | 42 screenshots at 2x (1080 x 720 window): `a-`, `b-`, `c-` progress, multi, finished, danger, library, library-empty; `b-closed`; `location`, `location-ask` |
