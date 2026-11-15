# Restore pages design

The "Restore pages?" prompt after a crashed session (#580). Picked direction: **A, the top trailing panel with a
list** (maintainer, 2026-11-05). Builds on `design/extensions` `surf-restore`. Prototype:
[`prototype.html`](prototype.html), states by hash `#<items|long|nothing|small>[&dark][&shot]`. Screens:
`screens/restore-pages-<state>-<light|dark>.png` (2x). Synthetic data only.

## What Restore means (accepted)

- Arkt's own restore always runs and brings back Spaces, sidebar tabs and the Archive without asking.
- The prompt offers only what that restore cannot bring back: **Little Arkt windows and Peek pages** that were open.
- Private windows (Incognito and Blank) are never offered; they write nothing (#557, #559).
- With nothing to offer there is no prompt, only a notice toast: "Arkt quit unexpectedly. Your Spaces and tabs are
  back." The toast also counts as acknowledging the crash.
- The engine's full session is never merged into the sidebar: it would duplicate rows.

## The panel

- **Where**: the existing top trailing panel of the crashed window, 22 pt from the card's top and trailing edges.
- **Size**: 340 pt wide, padding 18, radius 14, `surfaceBrand`, `overlayShadow`.
- **Title**: "Restore pages?", 15 pt semibold.
- **Body**: "Arkt quit unexpectedly. Your Spaces and tabs are back. These were open outside the sidebar:", 13 pt
  `textSecondary`, line height 1.45.
- **List**: a recessed field (`listField`, radius 10, padding 4). Up to 3 rows: 18 pt site tile, title (one line,
  truncates at the end), and the kind under it, 11 pt `textSecondary` ("Little Arkt window" or "Peek"). Beyond 3,
  a line "and <n> more" (12 pt `textSecondary`).
- **Actions** (14 pt below the list): Dismiss (neutral pill), **Restore <n>** (mustard, the one primary, Return).
  Esc is Dismiss. Restore reopens every listed page, not only the visible three.
- The panel stays until answered; it does not time out.

## The notice toast

The shared toast (`design/alerts-sheets-toasts`), shield glyph, no action, closes after 6 s or on its x.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Panel appears | opacity 0 to 1, translateY -8 to 0, 0.24 s on `firm` | opacity only, 0.15 s |
| Panel closes | opacity to 0, 0.15 s | same |
| Toast | the shared toast motion | the shared toast's Reduce Motion variant |

## Accessibility

- Panel: dialog, label "Restore pages?"; VoiceOver reads the body and the list.
- List rows: "<title>, <kind>"; the "and <n> more" line reads "and <n> more pages".
- Restore button: "Restore <n> pages".
- The notice toast is a status announcement.

## States

| State | What it shows |
|---|---|
| `items` | three pages outside the sidebar: two Little Arkt windows and a Peek page |
| `long` | twelve pages: three rows and "and 9 more"; Restore 12 |
| `small` | smallest window, 640 x 420 pt, 150 pt sidebar: the panel keeps its 340 pt width; long titles truncate |
| `nothing` | nothing outside the sidebar was open: the notice toast, no prompt |

## Answered questions

- Direction: A (top trailing panel listing what comes back).
- Meaning of Restore: accepted as above. Arkt restores Spaces, tabs and the Archive silently; the prompt offers only
  Little Arkt windows and Peek pages; never private windows; nothing to offer means a toast, not a prompt.

Rejected directions: B (one toast with Reopen) and C (a card in the sidebar).

## Recovery contract and implementation (#580)

The engine's `EngineSessionRecovery` supplies only crash state and dismissal. The shell owns URL, title, kind and
Peek source `NodeID` records through an injected `RecoveryPageSource`; only the App imports Persistence. The App
adapter writes ordered snapshots off the main actor. Engine tab and window identities are not persisted.

The window set captures the prior snapshot at initialization, before live writes. While the crash marker is set and
an offer is unanswered, live Little Arkt and Peek events must not overwrite the crashed snapshot, and even a confirmed
clean quit must not clear it. [#803](https://github.com/krystianslowik/arkt/pull/803) retains the engine marker across
launches until the decision is answered. After Restore, Dismiss, or the empty-offer notice acknowledges it, the shell
refreshes records from current live pages and resumes tracking opens, navigation, titles and actual closes, including
hidden Peeks. Blank, Incognito and sidebar pages are excluded. Unchanged snapshots do not write. A confirmed clean
quit then clears records and stops lifecycle writes; a cancelled quit resumes tracking. The App suspends writes during
a potentially cancelled teardown to preserve the pre-quit snapshot.

At offer time, Peeks without an existing, non-archived sidebar source are excluded. Duplicate Peeks per source keep
the last record. An empty offer shows the notice and acknowledges the crash. Restore prefers a regular window showing
the source, otherwise activates it in the host; it never replaces a live or hidden Peek. Distinct sources can coexist.
An unsuccessful restore retains the offer and does not acknowledge. Little Arkt's opening API reports requests, not
successful page loads. The decision is hosted only by a regular window and remains pending across host closure or a
change to private mode.

On normal confirmed quit the App requests a clear and flushes it, except while an offer is unanswered; a failed flush is logged and the existing quit flow
allows failure. SIGTERM has no final confirmed-termination hook, so its flush retains the snapshot. Persistence tests
and ShellKit tests cover their respective boundaries, not the App adapter or a killed process; feature-level validation
and CI on the combined head remain necessary. See the maintainer's [contract](https://github.com/krystianslowik/arkt/pull/690#issuecomment-6707149941)
and [source eligibility decision](https://github.com/krystianslowik/arkt/pull/690#issuecomment-6707374449).
