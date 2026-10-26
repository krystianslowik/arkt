---
name: arkt-design-first
description: Use before building any new or restyled user-facing Arkt surface (window, sheet, menu, overlay, toast, onboarding step) - mock several directions, get the maintainer's pick, commit the design under design/<surface>/, then open the build issue. Includes the brand rules.
---

# Arkt design first

Every user-facing surface is designed before it is built. The design is reviewed like code and committed to
`design/<surface>/`; the build issue links it. Examples: `design/command-bar/`, `design/settings/`,
`design/onboarding/`, `design/theme-creator/`.

## 0. Gate: write it down first

1. The surface, and whether it is everyday chrome or a moment surface (see brand rules).
2. Its states: default, empty, error, loading, longest content, smallest window.
3. The one primary action.
4. The open product questions (copy, behavior, what ships). These go to the maintainer.

**STOP** if no design issue exists for the surface. Open one (`area:design`, `type:chore`) or ask for one.

## 1. Steps

1. **Mock several directions.** Static HTML and CSS, no network, one state per file or per URL hash.
2. **Render to PNG**, light and dark, at 2x, for every state in gate item 2. Fill them with worst-case synthetic
   data: long titles, empty lists, huge counts. Never real browsing data.
3. **Ask the maintainer to pick.** Post the screenshots in the issue and set `status:needs-user` (or ask a maintainer
   to set it). **STOP** until a direction is chosen. Do not build.
4. **Commit the design** to `design/<surface>/`:
   - `README.md`: the spec, or a short README linking `docs/design/<surface>.md`. Values in points, states,
     behavior, motion and its Reduce Motion variant, accessibility labels.
   - `prototype.html` or `prototype/`: the chosen direction.
   - `screens/<state>-<light|dark>.png`, each under 400 KB.
   - Rejected directions only when they explain the choice (`directions/`).
5. **Open the build issue** linking the design, with acceptance criteria taken from the spec.

## 2. Verify before you claim

```zsh
find design/<surface>/screens -name '*.png' -size +400k   # must print nothing
ls design/<surface>/screens | grep -c dark                # dark screens exist
grep -rn "Arc\b" design/<surface>/prototype*               # no user-facing "Arc" in copy
```

Post the outputs in the pull request.

## Brand rules

From `design/brand/README.md` and the approved designs:

- **System font for everyday chrome**: sidebar, tab rows, toolbar, command bar, menus, settings, alerts.
- **Hero style only for moment surfaces**: first run and onboarding, About, Welcome, social graphics.
- **One primary mustard pill per surface.** Secondaries stay quiet.
- **Mustard is a fill**, never text, a stroke or navigation selection. Text on mustard is graphite.
- **Contrast is automatic and never shown to users.** No ratios or warnings in the UI
  (`design/theme-creator/README.md`, "Automatic contrast").
- **No "Arc" in user-facing copy.** Say "browser data".
- **Light and dark both required.**
- **Keep it simple.** One focal point, few controls, short plain copy.

## Common mistakes we made

- A generic card wizard for the first run, rejected twice before the Hero direction (`design/onboarding/README.md`).
- A stock System Settings look with mustard tiles for navigation; restyled in #304 (`design/settings/README.md`).
- Contrast ratios shown in the theme creator directions; the maintainer rejected them as too complex.
