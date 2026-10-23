<!-- Title: plain and descriptive, it becomes the squash commit subject. One issue per pull request. -->

Closes #

<!-- Use "Refs #N" instead when a maintainer step remains after the merge (list it under "Needs the maintainer"). -->

Plan: `docs/plans/...`, Task ...
Results: `docs/plans/...-results.md`, section ...

## Summary

<!-- What changed and why, in a few lines. -->

## Changes

- 

## Tests

<!-- Commands run and counts, as "baseline + N" where the plan records a baseline. -->

- `cd app/ArktCore && swift test`: 
- `cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests`: 
- GUI tests (`--filter ShellKitGUITests`), app build, engine build or smoke, if relevant: 

## Deviations from the plan

<!-- What differs from the plan and why. "None" if nothing. Also recorded in the results file. -->

## Manual checks needed

<!-- Checks the reviewer or maintainer must do by hand (trackpad, displays, signing). "None" if nothing. -->

## Needs the maintainer

<!-- Decisions or "Needs the user" steps that remain. "None" if nothing. -->

## Screenshots

<!-- Required for UI changes: window-only screenshots or a short recording. No real browsing data. -->

## Checklist

- [ ] Branch is `<type>/<issue#>-<slug>` and rebased on current `main`
- [ ] Tests written first; all tests pass; counts above
- [ ] Layering and WebKit isolation tests pass
- [ ] No `@unchecked Sendable` or `nonisolated(unsafe)` in production code; main thread never waits on disk
- [ ] Engine: patches exported and committed with `.patches`; patch number claimed above; patch budget updated
- [ ] Hot files touched were announced in the issue
- [ ] Results file and docs updated
- [ ] No emojis, real user data, credentials, signing identities, personal paths or email addresses
- [ ] Issue moved to `status:in-review` when this pull request left draft
