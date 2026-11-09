---
name: arkt-issue-loop
description: Use when picking up the next Arkt issue and taking it from claim to an open pull request - choosing work by status and order labels, claiming it, one worktree and branch per issue, test-first implementation, opening the pull request, and cleaning up after the merge.
---

# Arkt issue loop

One issue at a time, from claim to pull request. The rules behind each step are in `CONTRIBUTING.md`
(sections 2 to 6); this is the order to apply them in, with gates. Do not skip a gate.

Contributors open pull requests; maintainers merge. Never push to `main`. Never merge your own pull request.

## Decide or ask

Most open questions already have an answer in the repo. Decide them yourself, note the decision in one comment,
and keep working. Ask only for the few calls that no document settles.

Before you decide or ask, search in this order and follow what you find:

1. Design docs, specs and plan links (`design/`, the plan link in the issue).
2. Results docs.
3. Merged pull requests: `gh pr list --state merged --search "<keyword>"`.
4. Earlier maintainer comments: `gh issue view <N> --comments`.

### Decide yourself, comment, continue

- [ ] Merge order or overlap with another open pull request, including shared results and docs files. Merge
      `origin/main` into your branch later and keep both sections.
- [ ] A soft dependency. Note it in the pull request and proceed.
- [ ] Issue already shipped or duplicated. Close it with links to the pull requests that shipped it, or split the
      missing delta into a new issue.
- [ ] Stale issue text where the code and merged pull requests show the truth. Update the issue body.
- [ ] Wording mismatch with an obvious intent. Follow the intent and note the difference.
- [ ] Missing labels, plan link or `Depends-on` line. Add them.
- [ ] Test strategy details.
- [ ] Anything the design docs, spec, results docs or an earlier maintainer comment already answers.

### Ask (status:needs-user) only for

- [ ] New product behaviour with no default in the spec or design.
- [ ] Privacy, legal, money or external services.
- [ ] Irreversible or outward-facing actions.
- [ ] A real conflict between two maintainer decisions.

Unknown Arc runtime behaviour is not a reason to ask. Record the question on the runtime-check issue and continue
with the work that does not depend on it.

### How to ask

1. Post one comment with numbered questions. Give each question your recommended default.
2. Keep working on every part that does not depend on the answer.
3. Never block a whole issue for one sub-item. Split the sub-item into its own issue and mark only that one
   `status:needs-user`.

### Missing machine or tool

If the machine lacks something (for example a Chromium build), leave the issue `status:ready`, write "needs the
engine build" in the issue or pull request, and continue. Do not set `status:blocked`.

### When unsure

Do not assume what is not written down. If a guess would be hard to undo, ask. If it is easy to undo, decide, note
it, and continue.

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

**STOP** if the issue has a product question that no document settles (see "Decide or ask"), unclear acceptance
criteria, or an open hard dependency (work that must merge first). Ask with numbered questions and a default each;
for a hard dependency, name the blocker and set `status:blocked`. A soft dependency is not a stop.

## 2. Claim

With write access:

```zsh
gh issue edit <N> --add-assignee @me --add-label status:in-progress --remove-label status:ready
gh issue comment <N> --body "Taking this. Branch <type>/<N>-<slug>. Starting with <first step>."
```

Without write access (fork contributors): post the same comment and ask a maintainer to assign you and set the label.

- One assignee, exactly one `status:*` label. Check with `gh issue view <N> --json assignees,labels`.
- Check open pull requests for the files you need (`gh pr list --state open`, `gh pr diff <PR> --name-only`).
  If another open pull request touches them, decide the merge order yourself (see "Decide or ask") and note it on
  both pull requests.
- Announce any repo hot file you will touch (`CONTRIBUTING.md`, section 3) in the issue.

## 3. Worktree and branch

```zsh
git fetch origin
git worktree add ../arkt-wt/<N>-<slug> -b <type>/<N>-<slug> origin/main
```

- Base: the latest upstream `main` (`origin/main` in a clone, `upstream/main` in a fork).
- Type: `feat`, `fix`, `docs`, `engine`, `chore` or `spike` (`CONTRIBUTING.md`, section 4).
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

The first review pass should be the last. Open the pull request only when every item of the checklist below is in
it; each one missing costs a review round and a CI run.

### First-pass-ready checklist

Put each item in the pull request body (the template has a place for each):

- [ ] **Deliberate break.** You broke the behavior the new test guards, named the line, and pasted the failing
      output. Then you restored it.
- [ ] **Counts.** Baseline + N for each suite, with the exact commands, copied from the output of the last run.
- [ ] **20 runs under load** for every GUI or timing test you added or changed, with passes and `uptime`
      (`arkt-flaky-tests`, step 4).
- [ ] **Current with `main`.** You merged `origin/main` into the branch right before opening, and ran the lints:
      `cd app/ArktShell/ShellKit && swift test --filter 'LintTests|IsolationTests'`.
- [ ] **Needs the maintainer.** Every product decision you made without the maintainer is listed there. Write "None"
      only if you made none.
- [ ] **Overlap.** Open pull requests that touch your files, with the `git merge-tree --write-tree` result against
      each (`arkt-pr-review`, "Keeping a branch current"), or "no overlap".
- [ ] **Hot files** you touched were announced on the issue (`CONTRIBUTING.md`, section 3).

### Steps

1. Stage by pathspec only (never `git add -A` or `git add .`). Check `git diff --cached --stat` lists only your files.
2. Check the diff for banned content: no emojis, personal paths, usernames, emails, secrets, signing identities or
   real browsing data; no mention of tools or assistants in files, commits or pull requests.
3. Commit with a plain message and no trailers (`CONTRIBUTING.md`, section 5).
4. Push to the branch's own name: `git push -u origin <type>/<N>-<slug>` (your fork when you work from one).
5. Open a ready pull request with the template filled in and `Closes #N` (`Refs #N` when a maintainer step remains):
   `gh pr create --title "<plain title>" --body-file <filled template>`.
6. Move the issue to review (with write access; otherwise ask in the issue):
   `gh issue edit <N> --add-label status:in-review --remove-label status:in-progress`.
7. Address review on the same branch, all comments in one push. Update from `main` only for the reasons in
   `arkt-pr-review`, "Keeping a branch current", by merging `origin/main`; never force-push.

Never bypass a failing hook, a denied permission or a protected branch (`--no-verify`, force-push, admin merge). If
one blocks you, **STOP** and say so in the issue.

## 7. After the merge

A maintainer squash-merges after the review (`arkt-pr-review`, "Merge"). Then clean up your own things only:

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
- Opening a pull request without the deliberate break or the 20 runs, or with "None" under "Needs the maintainer"
  after deciding a product question. Each cost a review round and a CI run.
