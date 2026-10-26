---
name: arkt-issue-loop
description: Use when picking up the next Arkt issue and taking it from claim to an open pull request - choosing work by status and order labels, claiming it, one worktree and branch per issue, test-first implementation, opening the pull request, and cleaning up after the merge.
---

# Arkt issue loop

One issue at a time, from claim to pull request. The rules behind each step are in `CONTRIBUTING.md`
(sections 2 to 6); this is the order to apply them in.

Contributors open pull requests; maintainers merge. Never push to `main`. Never merge your own pull request.

## 1. Pick

Pick an open `status:ready` issue that is unassigned (or already yours). Lowest `order:N` first, then lowest number.
Skip `status:blocked` and `status:needs-user`.

```zsh
gh issue list --label status:ready --state open --limit 200 --json number,labels,assignees --jq '
  [.[] | select((.assignees|length)==0)
   | {number, order: ([.labels[].name | select(startswith("order:")) | ltrimstr("order:") | tonumber] | min // 99)}]
  | sort_by(.order, .number) | .[:5]'
```

Before picking, re-check blocked issues: each one has a comment naming its blockers. If every blocker is closed,
the issue is ready again (`CONTRIBUTING.md`, section 2, "Blocked needs a comment").

```zsh
gh issue list --label status:blocked --state open
gh issue view <N> --comments          # read the blocker comment
gh issue view <blocker> --json state  # CLOSED for every blocker means ready
```

Check that the issue meets the definition of ready (section 2). If a product question is open, ask in the issue
instead of deciding it.

## 2. Claim

One assignee per issue, one status label at a time. With write access:

```zsh
gh issue edit <N> --add-assignee @me --add-label status:in-progress --remove-label status:ready
gh issue comment <N> --body "Taking this. Branch <type>/<N>-<slug>. Starting with <first step>."
```

Without write access (fork contributors), post the same comment and ask a maintainer to assign you and set the
label. Then check open pull requests for the files you need (section 3) and announce any repo hot file you touch.

## 3. Worktree and branch

One worktree per issue, from the latest upstream `main` (`origin/main` in a clone, `upstream/main` in a fork).
Branch names are `<type>/<N>-<slug>` with type `feat`, `fix`, `docs`, `engine`, `chore` or `spike` (section 4).

```zsh
git fetch origin
git worktree add ../arkt-wt/<N>-<slug> -b <type>/<N>-<slug> origin/main
```

Never work in another person's or another issue's worktree.

## 4. Tests first

- Write the test, run it, watch it fail, then implement (section 7, TDD).
- Make tests deterministic: inject clocks and sleepers, step springs and display-link motion by hand, wait on
  conditions with a bounded turn count. No `sleep`, no wall-clock deadlines. See the `arkt-flaky-tests` skill.
- Run the test commands in section 7 "Before opening a pull request" and note the counts.

## 5. Pull request

- Stage by pathspec only, check `git diff --cached --stat`, commit with a plain message and no trailers (section 5).
- Push the branch to its own name: `git push -u origin <type>/<N>-<slug>` (to your fork when you work from one).
- Open a ready pull request with the template filled in and `Closes #N` (or `Refs #N` when a maintainer step
  remains):

  ```zsh
  gh pr create --title "<plain title>" --body-file <filled template>
  ```

- Move the issue to review (with write access; otherwise ask in the issue):

  ```zsh
  gh issue edit <N> --add-label status:in-review --remove-label status:in-progress
  ```

- Address review on the same branch. Update it by merging `origin/main`; never force-push (see `arkt-pr-review`).

## 6. After the merge

A maintainer squash-merges after the separate review step. Then clean up your own things only:

```zsh
git worktree remove ../arkt-wt/<N>-<slug>
git worktree prune
git branch -D <type>/<N>-<slug>
git -C <repo> pull --ff-only
```

Stop any process you started, by its PID (see `arkt-local-app-safety`). Then go back to step 1.
