---
name: arkt-issue-loop
description: Use when picking up the next Arkt issue and taking it from claim to an open pull request - choosing work by status and order labels, claiming it, one worktree and branch per issue, test-first implementation, opening the pull request, and cleaning up after the merge.
---

# Arkt issue loop

One issue at a time, from claim to pull request. The rules behind each step are in `CONTRIBUTING.md`
(sections 2 to 6); this is the order to apply them in, with gates. Do not skip a gate.

Contributors open pull requests; maintainers merge. Never push to `main`. Never merge your own pull request.

## 1. Pick

1. List ready, unassigned issues, lowest `order:N` first, then lowest number:

   ```zsh
   gh issue list --label status:ready --state open --limit 200 --json number,labels,assignees --jq '
     [.[] | select((.assignees|length)==0)
      | {number, order: ([.labels[].name | select(startswith("order:")) | ltrimstr("order:") | tonumber] | min // 99)}]
     | sort_by(.order, .number) | .[:5]'
   ```

2. Re-check blocked issues. Each has a comment naming its blockers; if every blocker is closed, it is ready again:

   ```zsh
   gh issue list --label status:blocked --state open
   gh issue view <N> --comments          # read the blocker comment
   gh issue view <blocker> --json state  # CLOSED for every blocker means ready
   ```

3. Skip `status:blocked`, `status:needs-user`, and anything assigned to someone else.
4. Read the whole issue and its plan link. Check it against the definition of ready (`CONTRIBUTING.md`, section 2).

**STOP** if the issue has an open product question (behavior, naming, what ships), unclear acceptance criteria, or
an open dependency. Comment on the issue with the exact question; do not guess and do not start.

## 2. Claim

With write access:

```zsh
gh issue edit <N> --add-assignee @me --add-label status:in-progress --remove-label status:ready
gh issue comment <N> --body "Taking this. Branch <type>/<N>-<slug>. Starting with <first step>."
```

Without write access (fork contributors): post the same comment and ask a maintainer to assign you and set the label.

- One assignee, exactly one `status:*` label. Check with `gh issue view <N> --json assignees,labels`.
- Check open pull requests for the files you need (`gh pr list --state open`, `gh pr diff <PR> --name-only`).
  **STOP** if another open pull request touches them; comment on both and agree on an order first.
- Announce any repo hot file you will touch (section 3) in the issue.

## 3. Worktree and branch

```zsh
git fetch origin
git worktree add ../arkt-wt/<N>-<slug> -b <type>/<N>-<slug> origin/main
```

- Base: the latest upstream `main` (`origin/main` in a clone, `upstream/main` in a fork).
- Type: `feat`, `fix`, `docs`, `engine`, `chore` or `spike` (section 4).
- Never open, edit or delete another person's or another issue's worktree or branch.

## 4. Gate: write it down before editing

Write these in your notes (or the draft pull request) before the first edit:

1. What the issue asks, in one sentence, and each acceptance criterion.
2. The files you will touch, and which of them are repo hot files.
3. The layer rule that applies (`CONTRIBUTING.md`, section 6, Pass 2: who may import `Persistence`, core modules,
   WebKit).
4. The test you will write first and why it fails today.
5. How you will prove it works: the exact commands and the counts you expect.

**STOP** if you cannot fill in item 1 or 4. Ask in the issue.

## 5. Tests first, then code

1. Write the test. Run it. Confirm it fails for the right reason (a compile error counts).
2. Implement the smallest change that makes it pass.
3. Make tests deterministic: inject clocks and sleepers, step springs by hand, bounded turn waits. No `sleep`, no
   wall-clock deadlines (see `arkt-flaky-tests`). Follow `arkt-swift-ui-quality` for Swift and UI work.
4. Run the commands in `CONTRIBUTING.md`, section 7, "Before opening a pull request".

**Verify before you claim.** Every "passes" in the pull request carries the command and its count, copied from
the actual output. If a command was not run, write "not run" and why.

## 6. Pull request

1. Stage by pathspec only (never `git add -A` or `git add .`). Check `git diff --cached --stat` lists only your files.
2. Check the diff for banned content: no emojis, personal paths, usernames, emails, secrets, signing identities or
   real browsing data; no mention of tools or assistants in files, commits or pull requests.
3. Commit with a plain message and no trailers (section 5).
4. Push to the branch's own name: `git push -u origin <type>/<N>-<slug>` (your fork when you work from one).
5. Open a ready pull request with the template filled in and `Closes #N` (`Refs #N` when a maintainer step remains):
   `gh pr create --title "<plain title>" --body-file <filled template>`.
6. Move the issue to review (with write access; otherwise ask in the issue):
   `gh issue edit <N> --add-label status:in-review --remove-label status:in-progress`.
7. Address review on the same branch. Update it by merging `origin/main`; never force-push (see `arkt-pr-review`).

Never bypass a failing hook, a denied permission or a protected branch (`--no-verify`, force-push, admin merge). If
one blocks you, **STOP** and say so in the issue.

## 7. After the merge

A maintainer squash-merges after the separate review step. Then clean up your own things only:

```zsh
git -C <repo> worktree remove ../arkt-wt/<N>-<slug>
git -C <repo> worktree prune
git -C <repo> branch -D <type>/<N>-<slug>
git -C <repo> pull --ff-only
```

Before removing: the pull request is merged and the worktree has no uncommitted changes (`git status`). Stop any
process you started, by its PID, and clear test attachments (see `arkt-local-app-safety`). Then go back to step 1.

## Common mistakes we made

- Picking an issue whose blocker had closed but whose label still said blocked, or leaving a blocked label after the
  blocker closed. Re-check blockers every loop.
- Reporting "tests pass" without counts, or with counts from before the last change.
- Fixing a flaky test by raising its timeout (the 60 s deadline before #396). It only moved the race.
- Two status labels on one issue, or `status:in-progress` with no assignee.
- Staging build leftovers or local tool folders with `git add .`.
