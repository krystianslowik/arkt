# Clear browsing data design

The Clear browsing data sheet, from Settings, Privacy and Security, "Clear..." (#637). Picked direction: **A, the
compact sheet, with B's summary line** (maintainer, 2026-11-05). Prototype: [`prototype.html`](prototype.html), states
by hash `#<default|alltime|clearing|nothing>[&dark][&shot]`. Screens:
`screens/clear-browsing-data-<state>-<light|dark>.png` (2x). Synthetic data only.

Everyday chrome: system font, shell tokens. No mustard: the only action that does something is destructive.

## The sheet

- A window sheet on Settings, 440 pt wide, padding 20, `surfaceBrand`, square top corners.
- **Title**: "Clear browsing data", 15 pt semibold.
- **Range row** (14 pt below): "Time range" and a pop-up (Last hour, Today, 7 days, 4 weeks, All time); "Profile:
  <name>" trailing in 12 pt `textSecondary`.
- **Kinds** (14 pt below, gap 10): four checkboxes, each with its cost under the title (12 pt `textSecondary`):
  - History: "<n> pages", counts include imported history.
  - Cookies and site data: "From <n> sites. Keeps you signed in elsewhere"; for All time "Signs you out of most sites"
    in `destructive`.
  - Cached images and files: the size.
  - Downloads list: "The files stay in your folder".
- **Defaults**: History and Cached images on; Cookies off below All time and on for All time; Downloads list off.
- **Summary line** (12 pt below the kinds, 12 pt `textPrimary`): names the total of what is checked, updated with every
  change: "Removes 86 pages and 412 MB of cached files." / "Removes 12,486 pages, cookies from 318 sites and 1.9 GB of
  cached files." With nothing checked: "Nothing selected."
- **Keep note**: a recessed line (`listField`, radius 9, Spaces glyph, 12 pt `textSecondary`): "Your Spaces, sidebar tabs
  and Archive stay as they are."
- **Actions**: Cancel (neutral pill, Esc) and **Clear Data**: a neutral pill with a `destructive` title, never mustard
  and never the Return default (as Clear Archive). Disabled with nothing checked. No second alert: the costs and the
  summary are the warning.

## Clearing

Controls dim to 50 %, a 14 pt spinner and "Clearing..." lead the action row. The sheet closes when done and the
Settings row shows "Cleared just now".

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Sheet | the system sheet | the system sheet |
| Summary changes | text crossfade, 0.12 s | none |
| Clearing | spinner rotation | the spinner is replaced by "Clearing..." alone |

## Accessibility

- Sheet: "Clear browsing data". Each checkbox reads its title and its cost line.
- The summary line is a live region; changes are announced politely.
- Clear Data: "Clear Data", hint "Removes the checked data. This cannot be undone."

## States

| State | What it shows |
|---|---|
| `default` | Last hour; History and Cached on; the summary line |
| `alltime` | All time with cookies; the sign-out warning; the full summary |
| `clearing` | clearing in progress |
| `nothing` | nothing checked; Clear Data disabled |

## Answered questions

- Direction: A (compact sheet) plus B's summary line under the list.

Rejected directions: B (segmented range and switch rows; only its summary line is kept) and C (history first).
