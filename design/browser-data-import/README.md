# Browser data import sheet design

The consent, progress and result sheet for importing data from another browser's profile (#514, part of #131; the
plan is the comment on #131). Two directions were mocked; the maintainer picked **B (Tiers)** and it is built in #514. A is kept as the record of the other option.

- Prototype: [`prototype.html`](prototype.html). Open it from disk. States by hash:
  `#<dir>-<entry>-<state>[&dark][&rm][&shot]`, for example `#a-menu-consent`, `#b-hero-denied&dark`.
  `dir` is `a` or `b`; `entry` is `menu` or `hero`; `state` is `consent`, `consent-worst`, `consent-zero`,
  `progress`, `progress-worst`, `result` or `denied`. `rm` is Reduce Motion, `shot` hides the review bar.
- Screens: [`screens/`](screens/), 2x, light and dark, named `import-<dir>-<state>-<light|dark>.png` for the menu
  entry and `import-<dir>-hero-<state>-<light|dark>.png` for the onboarding entry. `progress-rm` is the Reduce Motion
  variant. All data is synthetic.
- Copy never names the other browser. It says "your browser data" and "your other browser", like the
  "Import Browser Data..." menu item and the onboarding spec (section 6.2).

## The flow

1. **Consent.** One sheet. A checkbox per data type with its count from the probe. Cookies and passwords say
   "Needs your Mac password". When either is checked, a short line explains the macOS Keychain prompt that follows.
2. **Progress.** A row per type: its count, then done or skipped, with Cancel.
3. **Result.** Counts only. When macOS denies the Keychain, the sheet says "Passwords and cookies weren't imported"
   and offers Retry.

One primary mustard pill per state: Import, then (none while importing, Cancel is quiet), then Done, or Retry when
the Keychain was denied (Done stays quiet).

## Two entry points

| | Menu: File > Import Browser Data... | Onboarding: the import step hands off |
|---|---|---|
| Surface | an everyday sheet on the browser window | the Hero step itself, no sheet: the content replaces the step in place |
| Type | system font, 13 pt rows, 15 pt title | Avenir Next at the website's scale (56 pt headline, 18 pt rows, 26 pt DemiBold counts) |
| Buttons | 28 pt pills, mustard primary | 50 pt pills, mustard primary, glass secondary |
| Chrome around it | the window, sidebar visible behind | the particle field and fold; "1 of 6" and Skip setup stay |
| Secondary | Cancel | Not now (returns to the step) |

The existing onboarding Import step (`design/onboarding/screens/03-import-light.png`, the live "37") keeps its
Start fresh and Import buttons. **Import now opens this consent view** instead of importing at once. The counts the
step already shows (pinned tabs, Spaces, favorites, folders) are the Spaces and tabs row. Counting runs once; the
consent view reuses the probe result. Finishing the flow returns to the step's own Imported state (Continue), so
the first-run result replaces the menu result alert, as the onboarding spec already says.

## Directions

### A. Ledger

One recessed list, five rows, the same geometry in all three states. A row's leading slot is a checkbox in consent,
a status glyph in progress and result, so the list never moves and the eye stays on the counts. The Keychain line
sits under the list. The denied result keeps the full list and adds one notice under it.

### B. Tiers

Types are grouped by what they need: "Ready to import" and "Needs your Mac password". The Keychain line lives inside
the second group, next to the types it concerns, and the password note is stated once as the group's heading
instead of on each row. Progress adds one overall bar and a line naming the current type. The result splits by
outcome, "Imported" and "Not imported", so the denied state is a natural second group with the explanation in it.

| | A Ledger | B Tiers |
|---|---|---|
| Height | shortest (five equal rows) | taller by one heading per group and the overall bar |
| Keychain explanation | one line under the list | inside the group it applies to |
| Progress | per-row only | per-row plus one overall bar |
| Denied | list plus a notice | the group "Not imported" carries the reason |
| Best at | calm, no movement between states | telling the user why two rows ask for a password |

## Spec (values in points)

### Sheet (menu entry)

- Window sheet, 460 wide (A) or 500 wide (B), 20 padding, bottom corners 14, `surfaceBrand`. Title 15 semibold,
  subtitle 12 secondary. Same host and slide as the other sheets (`design/alerts-sheets-toasts`).
- List field: `listField` fill, radius 10, 12 horizontal padding, rows 40 tall (36 in B groups), 0.5 hairline between
  rows. Row: 16 slot, 12 gap, name 13 medium, optional detail 12 secondary, count 13 tabular figures, trailing.
- Checkbox: 16, radius 4.5, graphite fill (ivory in dark) with an inverted check when on. Mustard is never a
  checkbox or progress fill: it stays on the one primary pill.
- Status glyphs, 16: done (check in a ring), working (arc), waiting (dashed ring), skipped (dash in a ring), not
  imported (exclamation in a ring, secondary color, not red: nothing is destructive).
- Buttons: the shared 28 pt pills. Cancel is neutral; the primary is mustard with graphite text.
- Row progress bar: 3 tall, graphite, under the name. B's overall bar is 6 tall.

### Hero (onboarding entry)

- Content column 640 wide, centered on the field. Eyebrow 12 DemiBold uppercase +0.16 em, headline 56 DemiBold at
  0.92 line height and -0.055 em, lede 18. Rows 52 tall, name 18 medium, count 26 DemiBold, 1 pt rule between rows
  (no card, no field). Group labels (B) use the eyebrow style in the muted color.
- Buttons 50 tall, the website's pills. The particle field and fold stay as on the other steps; the field is static
  here only in the prototype.

### States

| State | Content |
|---|---|
| Consent | all rows checked with a nonzero count; counts from the probe. The Keychain line shows only while Cookies or Passwords is checked. Import is disabled when nothing is checked |
| A type with a count of 0 | its row is dimmed, the checkbox disabled and unchecked, the count shows 0 |
| Every type at 0 | title "Nothing to import", all rows dimmed, Cancel only usable, Import disabled. The Hero entry says the same and Not now returns to the step |
| Progress | rows move in a fixed order: Spaces and tabs, History, Extensions, Cookies, Passwords. Working row shows "x of y"; waiting rows "Waiting"; unchecked rows "Skipped". While macOS holds the Keychain prompt the row says "Waiting for macOS" |
| Cancel | stops after the current record batch. What already came over stays; the result lists the rest as Skipped |
| Result | counts only: no Space names, titles, URLs or paths |
| Denied | rows for Cookies and Passwords read "Not imported". Message: "Passwords and cookies weren't imported", reason: "macOS didn't let Arkt read your other browser's saved logins. Retry asks again." Retry runs only the two denied types and shows the pre-prompt line again. If one of the two types was unchecked, only the other is named |
| Retry that is denied again | the same state, no escalation, no counter |

### Counts and worst case

- Counts use grouped digits up to 9,999,999 ("48,210"), then compact ("12.5M", "2.1B"). They are tabular, never
  wrap, and the name truncates before the count does.
- "x of y" progress uses the same format for both numbers ("1.4B of 2.1B"), so it stays under 14 characters.
- Plural: "1 Space", "4 Spaces". A count of 1 is shown as "1", never "1 items".
- The screens cover huge counts (consent-worst, progress-worst) and every type at zero (consent-zero) in both
  directions and both entries where it applies.

### Copy

| Where | Text |
|---|---|
| Consent title and subtitle | "Import browser data" / "Choose what to bring into Arkt. Your other browser stays as it is." |
| Keychain line | "Next, macOS will ask to let Arkt read your other browser's saved logins. **Choose Allow, not Always Allow**, so this is a one-time permission." |
| Row note | "Needs your Mac password" |
| Progress | "Importing your browser data" / "Your other browser stays as it is." Footer: "Cancel keeps what has already come over." |
| Result | "Import finished" / "Everything you chose came over." |
| Denied | "Import finished" / "Most of it came over." plus the denied message above |
| Hero headlines | "Choose what comes over." / "Bringing it over." / "Your setup is here." / "Most of it came over." |

macOS's own prompt cannot be changed, so the line only has to prepare the choice. It names the outcome ("a
one-time permission") so the reason for "not Always Allow" is clear without a security lecture.

### Motion and Reduce Motion

Motion appears at three moments and answers what the user did; nothing loops without a reason.

| Moment | Motion | Reduce Motion |
|---|---|---|
| Sheet appears (menu) | the system sheet slide, 300 ms | opacity only, 200 ms |
| Working row | arc spins at 900 ms per turn, a soft highlight sweeps the row's bar every 1.4 s | the arc and the sweep stop; the bar fills in steps and the count text is the indicator |
| A type finishes | the check pops from scale 0.8 with `springyFast`, 240 ms | no scale; the glyph cross-fades |
| Consent to progress to result | rows stay in place; the slot and the count cross-fade, 150 ms | the same cross-fade |
| Press | `scale(0.97)` on pills | no scale, only the pressed fill |

Nothing animates on a keyboard action (Space on a checkbox, Return on Import). The Hero entry keeps the
onboarding's own choreography for the step change; the rows here appear without a stagger because the screen is
read, not watched.

### Accessibility

- The sheet is a dialog labelled by its title. Rows are a checkbox group; each checkbox is labelled
  "Spaces and tabs, 213" and its note is read as its description ("Needs your Mac password").
- During progress each row is a status: "History, 30,854 of 48,210", "Cookies, waiting". Progress is announced when
  a type finishes, not per record.
- Space toggles, Return activates the primary, Escape is Cancel (during progress it asks nothing and cancels). Tab
  order: rows, then Cancel and the primary. Focus ring is the system's.
- Color is never the only signal: every state has a glyph and a word. The denied state is not red.
- Both appearances, Reduce Motion, Reduce Transparency (nothing here is translucent in the sheet) and Increase
  Contrast (hairlines move to the `Increase Contrast` values already used by the other sheets).

## Decisions (maintainer, built in #514)

1. **Direction**: B, Tiers.
2. **Defaults**: Cookies and Passwords start checked, like every other type that has something in it.
3. **Retry scope**: only the failed types.
4. **Onboarding**: the consent replaces the Import step's content in place.
5. **Cancel**: keeps what came over.

### Where the build differs from the mock

- **Bookmarks** is a sixth row in Ready to import. The profile coordinator imports bookmarks as a type of its own; the five-row mock had no place for it. It dims to 0 when the other browser has none.
- **Spaces and tabs** is the existing sidebar import, run first as one row; the other rows run through the profile coordinator.
- When the other browser's profile folder cannot be read but its sidebar file can, the consent offers Spaces and tabs alone.
- The Keychain line shows again during a Retry's progress, inside the password group, as the spec says for the pre-prompt line.
- "Waiting for macOS" is inferred: from the user's answer until the coordinator's first progress event, because the coordinator reports no event for the Keychain prompt.

## Open questions (answered above)

1. **Direction**: A or B (the one open choice).
2. **Defaults**: should Cookies and Passwords start checked? The prototype checks everything; starting them
   unchecked would make the Keychain line appear only on request.
3. **Retry scope**: Retry only the denied types (as drawn), or rerun the whole import?
4. **Onboarding**: show the consent in the step itself (as drawn) or open it as a sheet over the step?
5. **Cancel**: keep what came over (as drawn) or roll back?

## Build issue

After a direction is picked, the build issue (#514's build half) takes its acceptance criteria from the Spec above.
The prototype's synthetic sets are the fixtures for the sheet's tests: normal, huge counts and every type at zero.
