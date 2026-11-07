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

## Recovery contract and implementation plan (#580)

The engine's `EngineSessionRecovery` supplies only `lastSessionCrashed` and `dismissLastSession` (#577).
The shell owns the list: URL, title, kind and, for a Peek, the sidebar `NodeID` of its source. Node IDs survive
sidebar persistence; engine tab and window IDs do not. No window identity is persisted. Only App imports
Persistence: expose a small `RecoveryPageSource` in ShellUI, inject it into `ShellWindowSet`, and implement the
adapter in App. Store durable records through Persistence; map the shell value to its storage representation in App.
Remove `EnginePageRecovery` and its page transport from EngineAPI when migrating the existing restore tests; keep
`EngineSessionRecovery` and unrelated engine protocols intact.

Record Little Arkt and Peek open, URL and title changes, and actual close, including hidden Peeks. Never record
Blank or Incognito pages. Clear live records on successful clean quit, not a cancelled quit. Capture the previous
records for the launch offer before live-session writes can replace them; keep that immutable offer until Restore,
Dismiss, or an empty-offer notice acknowledges the crash. An unsuccessful restore keeps the offer and does not
acknowledge. Persist updates off the main actor in order; a quit must wait for the clearing write.

Restore one Peek per source: deduplicate records by source, keeping the last. Prefer an open regular window showing
the node; otherwise activate it in the host. Use `PeekController.reopen(_:over:)` with a `ClosedPeek` whose parked
copy is nil. Do not replace a live or hidden Peek. Distinct sources can coexist, including as hidden Peeks. Preserve
the existing private-window and held-close safeguards. Little Arkt's opening API reports requests, not successful
page loads. These seams are test-first: ShellKit GUI tests exercise real window routing and the injected record
boundary; Persistence tests exercise storage across database reopen. `project.yml` has an XCUITest bundle but no
unit test target for App, and ShellKit does not link Persistence, so these tests do not claim to exercise AppSession
or its adapter. Feature-level killed-process validation remains necessary.

The test-first seam is a main-actor `RecoveryPageSource.pages` snapshot of `ShellRecoveryPage` values, injected into
`ShellWindowSet` as `recoveryPageSource`. `beginSessionRecovery` captures that snapshot before starting live writes;
`finishSessionRecovery(cleanQuit:)` expresses the quit outcome at the shell boundary, with the App adapter flushing
a successful clear before termination. Persistence's `RecoveryPageState` settings group contains `RecoveryPageRecord`
values and is mapped by the App adapter. The tests deliberately name these proposed APIs; they do not exist yet.
Keep failed writes and their retry/quit handling visible rather than claiming a durable clear before it completes.
During migration update existing `RestorePagesModelTests` and `RestorePagesWindowTests` to supply the shell source,
replace their old assertion that multiple Peeks must be rejected, and leave their private and held-close cases intact.
The old source-less cases do not decide the pending #776 edge.

Pending maintainer question (#776): whether a Peek with no source node, or a source that was archived or deleted,
is excluded from the offer. Do not choose a fallback until answered.

The decision is hosted only by an ordinary regular window, never a Blank, Incognito, Little Arkt or Peek window.
Its unanswered model stays with the window set if no eligible host exists and moves to a regular window when one
becomes available. Closing or changing the host to a private mode does not acknowledge the crash. Private window
creation establishes its final mode before the window set considers recovery presentation.
