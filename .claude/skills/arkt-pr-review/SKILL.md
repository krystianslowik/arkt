---
name: arkt-pr-review
description: Use when reviewing an Arkt pull request, or preparing your own for review - two passes (spec, then quality) for code and a light pass for docs-only or test-only changes, the checklist of bug classes the project has actually hit, when a branch needs updating from main, using scarce CI, and the merge conditions.
---

# Arkt pull request review

Code pull requests get two passes: spec, then quality. Docs-only and test-only pull requests get the light review
below instead. The base checklist is `CONTRIBUTING.md`, section 6, "Reviewer checklist"; this skill adds the bug
classes found in past pull requests and the merge rules. Do not approve from the description alone. Do not request
changes for merge order, overlap or soft dependencies; those are settled under "Decide or ask" in `arkt-issue-loop`.

A pull request should arrive ready for its first pass: the author fills in the checklist in `arkt-issue-loop`,
step 6, "First-pass-ready checklist". If an item is missing, ask for it in one comment instead of reviewing around it.

## Light review: docs-only and test-only

A pull request that changes only docs (`docs/`, `design/` text, `README.md`, `CONTRIBUTING.md`, `.claude/`,
`.github/` templates) or only test files gets one quick pass:

- [ ] **Accurate.** Commands, paths, section references and numbers match the repo as it is now.
- [ ] **Consistent.** It does not contradict `CONTRIBUTING.md`, another skill or a recorded maintainer decision.
- [ ] **Nothing weakened.** No rule, gate, assertion or test was dropped or loosened without a stated reason. For
      test-only changes, the deliberate break is still shown.

A pull request that also touches production code, the CI workflow or build settings gets the full review below.

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
- [ ] No product question was decided silently. Every product decision made without the maintainer is listed under
      "Needs the maintainer". **STOP** if one is missing: request changes and ask the maintainer in the issue.
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

Update a branch from `main` only when it needs it. Every push starts a CI run (see "CI" below).

**Do not update** a reviewed branch whose required **Swift tests** check is green on its own head when both hold:

1. It merges cleanly: `git merge-tree --write-tree origin/main $head` exits 0.
2. None of its files were changed by pull requests merged since its CI ran: the `comm` line prints nothing.

```zsh
git fetch origin
head=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
git fetch origin pull/<PR>/head
git merge-tree --write-tree origin/main $head > /dev/null && echo clean || echo conflict
base=$(git merge-base origin/main $head)
comm -12 <(git diff --name-only $base $head | sort) <(git diff --name-only $base origin/main | sort)
```

A clean merge-tree alone is not enough: two changes to one file can merge without a conflict and still break each
other. Comparing from the merge base also counts changes that landed before the last run; that errs on the safe
side.

**Update, then wait for a fresh green run,** when files overlap, or when a lint or guard that covers the branch's
area has landed on `main` since its CI ran. Examples: `SystemFontLintTests`, `CornerRadiusLintTests`, the window
leak guard (`arkt-flaky-tests`, "GUI test hygiene"). Read `git log --oneline $base..origin/main` to find them.

To update, merge the latest upstream `main`; never rebase or force-push a branch under review:

```zsh
git fetch origin
git merge origin/main   # upstream/main in a fork
(cd app/ArktShell/ShellKit && swift test --filter 'LintTests|IsolationTests')
git push
```

Rerun the tests the merge affects and post the new counts. Never push to someone else's branch; comment instead.

## CI

- The required check is **Swift tests** (`CONTRIBUTING.md`, section 12). GUI and UI test jobs are informative.
- **CI is scarce.** A few macOS runners serve the whole repo, and every push queues behind the others. Do not start
  runs that are not needed:
  - no update from `main` without one of the reasons above;
  - batch fixes into one push instead of pushing each commit;
  - no rerun of a real failure. A failing test is real until shown otherwise; fix it, or follow
    `arkt-flaky-tests`.
- **Infra failures may be rerun**: a download 504, a runner that died, a cancelled setup step. Rerun only the failed
  jobs: `gh run rerun <run-id> --failed`. Say in the pull request what the infra failure was.
- A failure in a test the change does not touch, with a known flaky issue: link the issue in the pull request. The
  maintainer decides whether to rerun once. A flake without an issue gets one (see `arkt-flaky-tests`).

## Merge

Maintainers merge; contributors open pull requests. Merge only when all hold:

1. The review passed. Once two developers are active, the approval comes from someone other than the author
   (`CONTRIBUTING.md`, section 6). The maintainer may authorize a merge after an independent review in place of a
   GitHub approval.
2. **Swift tests** is green on the pull request's own head commit.
3. The branch does not need an update (see "Keeping a branch current"), or it was updated and the new run is green.
4. `main` is green: the required **Swift tests** check passed on `main`'s latest run. The GUI and UI test jobs are
   informative and do not count. A red `main` is fixed first, before any more merges.

Squash only, title as subject, pinned to the head commit that was reviewed and tested:

```zsh
gh pr merge <PR> --squash --delete-branch --match-head-commit <full sha>
```

The sha is `gh pr view <PR> --json headRefOid --jq .headRefOid`. If the head moved, the merge fails; review the new
commits first.

- **Back to back** when the pull requests share no files. A newer push to `main` cancels the run it supersedes, so a
  batch of merges costs one `main` run.
- **One at a time** only when pull requests share files: merge one, then check the next with "Keeping a branch
  current".
- `main`'s own CI run catches what is left. If it goes red, stop merging until it is fixed (condition 4).

Never use an admin override to skip a failing check or a missing review.

## Common mistakes we made

- Approving a flaky-test fix without proof it fails when the code is broken.
- Updating every open branch from `main` after each merge, and merging strictly one at a time. On 2026-11-08,
  31 pull requests took about 13 hours, mostly waiting for CI.
- Clear Today sweeping the tab on screen until it learned to keep shown tabs (#429, #435).
- A shortcut swallowed by a focused text field (#373) or handled by the window instead of the controller (#397).
- A selection loading a page a second time instead of moving the live one (#300).
- Non-additive facade changes made without both lanes agreeing (engine week 3 results, "Non-additive changes").
