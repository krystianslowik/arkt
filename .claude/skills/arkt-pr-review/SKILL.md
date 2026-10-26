---
name: arkt-pr-review
description: Use when reviewing an Arkt pull request, or preparing your own for review - two passes (spec, then quality), the checklist of bug classes the project has actually hit, keeping a branch current without force-pushing, flaky CI retries, and the merge conditions.
---

# Arkt pull request review

Review in two passes. The base checklist is `CONTRIBUTING.md`, section 6, "Reviewer checklist"; this skill adds the
bug classes found in past pull requests. Read the diff, the issue and the plan task before commenting.

```zsh
gh pr view <PR>
gh pr diff <PR>
gh pr checks <PR>
```

## Pass 1: spec

- Every acceptance criterion in the issue is met, or deferred with a follow-up issue.
- Deviations from the plan are listed and justified. No product question was decided silently.
- Test counts are reported as "baseline + N", and the results file or docs are updated where affected.

## Pass 2: quality

Check each item that the diff can touch:

- **Split View survives sidebar moves.** Moving, pinning, reordering or dragging a tab that is part of a Split View
  keeps or dissolves the split on purpose, never leaves a broken split (see #374, #407).
- **Automatic policies spare what the user sees.** Auto-archive, Clear Today and similar sweeps never archive the
  current tab or a tab shown in another window (see #429, #435).
- **No stale state after moves.** After a tab moves between Spaces, windows or panes, its URL and `lastActiveAt`
  are the live values, not the ones from before the move.
- **No main-thread waits.** Main-actor code only `await`s; no semaphores, `DispatchQueue.main.sync` or blocking
  reads on the main thread, and no waits that can deadlock against work queued on the main actor (section 6, Pass 2).
- **Frozen engine facade.** `EngineAPI` and the facade header change additively only: new cases, members or
  methods, never a renamed, removed or reordered one. The two header copies,
  `engine/arkt/api/arkt_engine.h` and `app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h`, stay
  byte-identical (`cmp` them).
- **Chromium patch budget.** Upstream changes only as exported patches committed with `.patches`. The patch count
  matches the branch: `git -C $CR rev-list --count $PIN..arkt` equals `wc -l < engine/patches/chromium/.patches`.
  The budget table in the engine results file is updated (see `arkt-engine-lane`).
- **Layering.** `ShellUI` imports no core module (`SidebarModel`, `Archive`, `ArcImport`, `Persistence`, `GRDB`);
  `CoreBridge` and the rest of `ShellKit/Sources` do not import `Persistence` or `GRDB`; only `App/*` imports
  `Persistence`. Only `FakeEngineKit` imports WebKit. The isolation tests are the gate.
- **No user-facing "Arc".** Menus, toasts, alerts, empty states and accessibility labels say "browser data".
- **Mustard is a fill only.** Never a text color or a stroke; text on mustard is graphite (`design/brand/README.md`).
- **Reduce Motion.** Every new animation has a Reduce Motion variant, and a test covers it.
- **Tests fail without the fix.** For a bug fix, revert or break the fixed line locally and confirm the new test
  fails. Ask the author for this in the pull request if it is not stated.
- Banned content: no emojis, real browsing data, credentials, signing identities, personal paths or email addresses.

Use "Request changes" for anything that must change and plain comments for suggestions.

## Keeping the branch current

Update a pushed branch by merging the latest upstream `main` into it; never force-push a branch under review.

```zsh
git fetch origin
git merge origin/main
git push
```

Rerun the test commands after the merge and post the new counts if they changed.

## CI

- The required check is **Swift tests** (`CONTRIBUTING.md`, section 12). The GUI and UI test jobs are informative.
- If a test with a known flaky issue fails, rerun the failed job once (`gh run rerun <run-id> --failed`). A second
  failure is a real failure. A flake without an issue gets one, see `arkt-flaky-tests`.

## Merge

Maintainers merge; contributors open pull requests. A pull request is merged only when:

- the review above approved it, and the reviewer is not the author once two developers are active (section 6),
- **Swift tests** is green,
- the maintainer's current merge policy allows it.

Merge is squash only, with the pull request title as the subject:

```zsh
gh pr merge <PR> --squash --delete-branch
```
