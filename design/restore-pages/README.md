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

## Swift engine contract (#580)

`EnginePageRecovery` refines the crash-only `EngineSessionRecovery` protocol and supplies only an ordered list of
`recoveryPages`. Pages contain a title, URL and kind (`littleArkt` or `peek`). The backend must never persist or return
private or sidebar data. The shell opens Little Arkt pages with `ShellWindowSet.openLittleArkt` and Peek pages via
`PeekController`, using the host window's current tab as the Peek source. Recovery refuses to replace or close any
existing live or hidden Peek in that host. It attempts the Peek first, closes a newly created tab if its page cannot
be presented, and opens Little Arkt windows only after that succeeds. A missing source, existing Peek, failed Peek
presentation or multiple recovered Peeks leaves the offer and crash unanswered for retry or dismissal. Little Arkt's
opening API reports no presentation result, so acknowledgement confirms its opening was requested, not that its page
loaded or appeared. The shell acknowledges once after the requests, dismissal, or an empty offer. Multi-Peek routing
remains a product decision; crash-only legacy providers have no page capability.
The crashed-session state seam shipped in #577. Recoverable-page list and source grouping integration, and
feature-level killed-process validation, remain unverified; no full engine session is restored.

The decision is hosted only by an ordinary regular window, never a Blank, Incognito, Little Arkt or Peek window.
Its unanswered model stays with the window set if no eligible host exists and moves to a regular window when one
becomes available. Closing or changing the host to a private mode does not acknowledge the crash. Private window
creation establishes its final mode before the window set considers recovery presentation.
