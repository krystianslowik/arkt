---
name: arkt-design-first
description: Use before building any new or restyled user-facing Arkt surface (window, sheet, menu, overlay, toast, onboarding step) - mock several directions, get the maintainer's pick, commit the design under design/<surface>/, then open the build issue. Includes the brand rules.
---

# Arkt design first

Every user-facing surface is designed before it is built. The design is reviewed like code and committed to
`design/<surface>/`; the build issue links it. Existing examples: `design/command-bar/`, `design/settings/`,
`design/onboarding/`, `design/theme-creator/`.

## Steps

1. **Open a design issue** (`area:design`, `type:chore`), or use the one you were given.
2. **Mock several directions.** Static HTML and CSS, no network, one state per file or per URL hash. Render each to
   PNG in light and dark, at 2x. Show the states that matter (default, empty, error, long content).
3. **The maintainer picks one.** Post the screenshots in the issue and set `status:needs-user`. Do not build until
   a direction is chosen. Product questions (naming, behavior, what ships) are the maintainer's.
4. **Commit the design** to `design/<surface>/`:
   - `README.md`: the spec, or a short README that links the spec in `docs/design/<surface>.md`. Values in points,
     states, behavior, Reduce Motion variants, and accessibility labels.
   - `prototype.html` or `prototype/`: the chosen direction.
   - `screens/`: `<state>-<light|dark>.png`, each under 400 KB. Check with
     `find design/<surface>/screens -name '*.png' -size +400k` (prints nothing when all pass).
   - Rejected directions only when they explain the choice (`directions/`); otherwise leave them in history.
5. **Open the build issue** that links the design and lists acceptance criteria from the spec.

## Brand rules

From `design/brand/README.md` and the approved designs:

- **System font for everyday chrome**: sidebar, tab rows, toolbar, command bar, menus, settings, alerts.
- **Hero style only for moment surfaces**: first run and onboarding, About, Welcome, social graphics. Avenir Next,
  used from the system, never bundled.
- **One primary mustard pill per surface.** Secondaries stay quiet.
- **Mustard is a fill**, never text or a stroke. Text on mustard is graphite.
- **Contrast is automatic and never shown to users.** No contrast ratios or warnings in the UI; the app picks
  readable text colors itself (`design/theme-creator/README.md`, "Automatic contrast").
- **No "Arc" in user-facing copy.** Say "browser data".
- **Light and dark are both required.**
- **Keep it simple.** One focal point, few controls, short plain copy.
