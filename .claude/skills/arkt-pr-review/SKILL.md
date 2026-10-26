---
name: arkt-pr-review
description: Use when reviewing an Arkt pull request, or preparing your own for review - two passes (spec, then quality), the checklist of bug classes the project has actually hit, keeping a branch current without force-pushing, flaky CI retries, and the merge conditions.
---

# Arkt pull request review

Review in two passes. The base checklist is `CONTRIBUTING.md`, section 6, "Reviewer checklist"; this skill adds the
bug classes found in past pull requests. Do not approve from the description alone.

## 0. Gate: read before judging

```zsh
gh pr view <PR>
gh pr diff <PR>
gh pr checks <PR>
gh issue view <N>
```

Write down before commenting:

1. What the issue and plan task ask, and each acceptance criterion.
2. Which layers and files the diff touches (shell UI, core, persistence, engine, design).
3. Which items of Pass 2 apply to those files.

## 1. Pass 1: spec

- [ ] Every acceptance criterion is met, or deferred with a linked follow-up issue.
- [ ] Deviations from the plan are listed and justified.
- [ ] No product question was decided silently. **STOP** if one was: request changes and ask the maintainer in the
      issue.
- [ ] Test counts are reported as "baseline + N" with the commands; results file or docs updated where affected.

## 2. Pass 2: quality, bug classes we have hit

Check each item that the diff can touch. For each, point to the line or test that shows it holds.

- [ ] **Split View survives sidebar moves.** Moving, pinning, reordering or dragging a tab in a Split View keeps or
      dissolves the split on purpose, never leaves it broken (#374). Reopening a closed pane restores its split (#407).
- [ ] **Automatic policies spare what the user sees.** Auto-archive and Clear Today never archive the current tab or
      a tab shown in another window (#429, #435).
- [ ] **No stale state after moves.** After a tab moves between Spaces, windows or panes, its URL and `lastActiveAt`
      are the live values, not the ones from before the move.
- [ ] **No main-thread waits.** Main-actor code only `await`s; no semaphores, `DispatchQueue.main.sync`, blocking
      reads or waits that can deadlock against work queued on the main actor.
- [ ] **Frozen engine facade.** `EngineAPI` and the facade header change additively only. The two header copies
      stay byte-identical:
      `cmp engine/arkt/api/arkt_engine.h app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h`.
- [ ] **Chromium patch budget.** Patches and `.patches` committed together; `git -C $CR rev-list --count $PIN..arkt`
      equals `wc -l < engine/patches/chromium/.patches`; budget table updated (see `arkt-engine-lane`).
- [ ] **Layering.** `ShellUI` imports no core module (`SidebarModel`, `Archive`, `ArcImport`, `Persistence`, `GRDB`);
      `CoreBridge` and the rest of `ShellKit/Sources` do not import `Persistence` or `GRDB`; only `App/*` imports
      `Persistence`; only `FakeEngineKit` imports WebKit. The isolation tests are the gate.
- [ ] **No user-facing "Arc".** Menus, toasts, alerts, empty states and accessibility labels say "browser data".
- [ ] **Mustard is a fill.** Never a stroke; text on mustard is graphite; mustard text only on graphite.
- [ ] **Reduce Motion.** Every new animation has a Reduce Motion variant, and a test covers it.
- [ ] **Tests fail without the fix.** The author names the line they broke and shows the test failing. If not, ask.
- [ ] **Key routing.** Shortcuts reach the controller, not a focused text field or the window (#373, #397).
- [ ] **Banned content.** No emojis, personal paths, usernames, emails, secrets, signing identities, real browsing
      data, or mentions of tools or assistants.

Use "Request changes" for anything that must change, plain comments for suggestions.

## 3. Verify before you claim

An approval or a "looks good" states what you checked: the commands you ran and their output, or the items above
with the line that shows each. "Not checked" is allowed; silence is not.

## Keeping a branch current

Merge the latest upstream `main` into a pushed branch; never force-push a branch under review.

```zsh
git fetch origin
git merge origin/main   # upstream/main in a fork
git push
```

Rerun the tests after the merge and post the new counts. Never push to someone else's branch; comment instead.

## CI

- The required check is **Swift tests** (`CONTRIBUTING.md`, section 12). GUI and UI test jobs are informative.
- Team convention: a test with a known flaky issue may be rerun once: `gh run rerun <run-id> --failed`. A second failure is real.
  A flake without an issue gets one (see `arkt-flaky-tests`).

## Merge

Maintainers merge; contributors open pull requests. Merge only when all hold:

1. The review approved it, from someone other than the author once two developers are active (section 6).
2. **Swift tests** is green on the latest commit.
3. The maintainer's current merge policy allows it.

Squash only, title as subject: `gh pr merge <PR> --squash --delete-branch`. Never use admin override to skip a
failing check or a missing review.

## Common mistakes we made

- Approving a flaky-test fix without proof it fails when the code is broken.
- Clear Today sweeping the tab on screen until it learned to keep shown tabs (#429, #435).
- A shortcut swallowed by a focused text field (#373) or handled by the window instead of the controller (#397).
- A selection loading a page a second time instead of moving the live one (#300).
- Non-additive facade changes made without both lanes agreeing (engine week 3 results, "Non-additive changes").
