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

<!-- Exact commands and counts, as "baseline + N", copied from the output of the last run. -->

- `cd app/ArktCore && swift test`: 
- `cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests`: 
- Lints after merging `main`: `cd app/ArktShell/ShellKit && swift test --filter 'LintTests|IsolationTests'`: 
- GUI tests (`--filter ShellKitGUITests`), app build, engine build or smoke, if relevant: 
- 20 runs under load for each GUI or timing test added or changed (passes and `uptime`), or "no such test": 

### Deliberate break

<!-- The line you broke, and the failing output. Then restore it. "Docs only" if no code or test changed. -->

## Overlap with open pull requests

<!-- Open pull requests that touch the same files, with `git merge-tree --write-tree origin/main <head>` results,
     or "No overlap". -->

## Deviations from the plan

<!-- What differs from the plan and why. "None" if nothing. Also recorded in the results file. -->

## Manual checks needed

<!-- Checks the reviewer or maintainer must do by hand (trackpad, displays, signing). "None" if nothing. -->

## Needs the maintainer

<!-- Every product decision you made without the maintainer, and every "Needs the user" step that remains.
     "None" only if you made no such decision and no step remains. -->

## Screenshots

<!-- Required for UI changes: window-only screenshots or a short recording. No real browsing data. -->

## Checklist

First pass ready (`.claude/skills/arkt-issue-loop/SKILL.md`, step 6):

- [ ] Deliberate break shown: the line named and the failing output pasted
- [ ] Baseline + N counts with the exact commands
- [ ] 20 runs under load for each GUI or timing test added or changed
- [ ] `main` merged in right before opening; lints run
- [ ] Every product decision made without the maintainer listed under "Needs the maintainer"
- [ ] Overlap with open pull requests listed, with merge-tree results
- [ ] Hot files touched were announced on the issue

Rules:

- [ ] Branch is `<type>/<issue#>-<slug>` (or `docs/<slug>` for a docs change without an issue)
- [ ] Tests written first; all tests pass
- [ ] Layering and WebKit isolation tests pass
- [ ] No `@unchecked Sendable` or `nonisolated(unsafe)` in production code; main thread never waits on disk
- [ ] Engine: patches exported and committed with `.patches`; patch number claimed above; patch budget updated
- [ ] Results file and docs updated
- [ ] No emojis, real user data, credentials, signing identities, personal paths or email addresses
- [ ] Issue moved to `status:in-review` when this pull request left draft
