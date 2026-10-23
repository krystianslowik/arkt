# Contributing to Arkt

Arkt is built by a small team. This guide is the working agreement: how work is chosen, claimed, built, reviewed and
merged, so that two or more people can work in parallel without stepping on each other. The technical rules in the
plans (`docs/plans/*`, "Rules" sections) still apply; this file collects the ones every change needs and adds the
team workflow around them.

Contents:

1. Roles and ownership
2. Issues and statuses
3. Claiming work and avoiding collisions
4. Branches and worktrees
5. Commits
6. Pull requests and review
7. Code rules
8. Engine work with more than one developer
9. Plans, results and decisions
10. Communication
11. Main, releases and tags
12. Repository settings to enable (maintainer)

## 1. Roles and ownership

- **Maintainer** (@krystianslowik): owns the roadmap (#30), decides product and scope questions, sets issue order,
  holds the release signing identity and does the steps the plans list under "Needs the user". Has the final word
  when two contributors disagree on a technical question that review did not settle.
- **Contributors**: pick up `status:ready` issues, write the code, tests and results, review each other's pull
  requests, and raise product questions instead of deciding them.

Product questions (behavior, Arc parity choices, naming, bundle ids, what ships) are decided by the maintainer and
recorded in the issue and the plan they affect (section 9). Technical choices inside an accepted plan are made by the
person doing the work and explained in the pull request.

### Areas and owners

Each area has one owner. The owner reviews pull requests that touch the area (see `.github/CODEOWNERS`) and keeps
the area's plan and results files current. Anyone may work in any area.

| Area | Labels | Paths | Owner |
|---|---|---|---|
| Shell | `area:shell` | `app/ArktShell/App`, `app/ArktShell/ShellKit` (ShellUI, Motion, CoreBridge, EngineAPI, FakeEngineKit), `app/ArktShell/project.yml` | @krystianslowik |
| Core | `area:core` | `app/ArktCore` (SidebarModel, Persistence) | @krystianslowik |
| Engine | `area:engine`, `area:compat` | `engine/` (overlay, patches, tools, branding) | @krystianslowik |
| Import and archive | `area:import`, `area:archive` | `app/ArktCore/Sources/ArcImport`, `app/ArktCore/Sources/Archive` and their tests | @krystianslowik |
| Design and brand | `area:design` | `design/` (brand kit, tokens, logos, social images) | @krystianslowik |
| Docs and plans | `type:chore` | `docs/`, `README.md`, `CONTRIBUTING.md`, `.github/` | @krystianslowik |

When the second developer joins, they add their GitHub handle as owner of the areas they take over, in this table
and in `.github/CODEOWNERS` (the commented placeholder lines there show where), in one small pull request.

## 2. Issues and statuses

Every piece of work is a GitHub issue. Backlog items found outside a plan become an issue right away
(`status:triage`); the Roadmap issue (#30) lists them by order. Use the issue templates: feature, bug or task. Small
docs or housekeeping changes (typos, templates, this file) may go straight to a pull request without an issue.

### Labels

| Kind | Labels | Meaning |
|---|---|---|
| Status | `status:*` (below) | Where the issue is. Exactly one per open issue. |
| Area | `area:shell`, `area:core`, `area:engine`, `area:import`, `area:archive`, `area:compat`, `area:design` | Which code it touches. One or more. |
| Type | `type:feature`, `type:bug`, `type:chore` | What kind of work. Exactly one. |
| Order | `order:1` ... `order:7` | Priority. Lower runs first (below). |

### Statuses

| Label | Meaning | Who sets it |
|---|---|---|
| `status:triage` | New, not yet checked against the definition of ready. | Whoever opens the issue (the templates add it). |
| `status:ready` | Meets the definition of ready, no open dependencies, nobody assigned. Free to claim. | Maintainer, or anyone when the last dependency closes. |
| `status:in-progress` | Assigned and being worked on, or a draft pull request is open. | The assignee, when they start. |
| `status:in-review` | A pull request for it is open and ready for review. | The pull request author. |
| `status:blocked` | Cannot move. A comment names the blocker: open issues (`#N`) or the exact external reason. | Whoever finds the blocker. |
| `status:needs-user` | The next step is the maintainer's: a decision, a manual check, or a "Needs the user" step from a plan. | Whoever reaches that step. |
| Done | Closed by its merged pull request. No status label needed. | The merge. |

Rules:

- **One status label at a time.** Swap labels in one edit:
  `gh issue edit <N> --add-label status:in-progress --remove-label status:ready`.
- **Precedence** when more than one seems to fit: `in-review` > `in-progress` > `blocked` > `needs-user` > `ready`.
  An issue that waits on open issues and also has a maintainer step after them is `status:blocked`; its blocker
  comment says that a maintainer step follows.
- **One assignee per issue.** The assignee is the one person responsible for moving it. Pairing is fine; one name
  still owns it. Every `status:in-progress` and `status:in-review` issue has an assignee.
- **Blocked needs a comment.** `status:blocked` without a comment naming the blocker is not allowed. Examples:
  "Blocked by #12 and #21." or "Blocked: the `out/Arkt` link needs a quiet machine." When the blocker clears,
  whoever notices moves the issue to `status:ready` (or back to `status:in-progress` if it is assigned).
- **Needs-user maps to the plans.** Steps under a plan's "Needs the user" heading are the only steps that need the
  maintainer. When an issue reaches one, set `status:needs-user` and list the exact steps in a comment.
  `status:needs-user` replaces the old `needs-user` label.
- The Roadmap issue (#30) carries no status label; it is the index.

### Order labels

`order:N` is the priority. Pick work from the lowest order that has `status:ready` issues. Within one order, follow
the "Depends on" lists in the issues and the lane tables in the plans. Only the maintainer changes an issue's order;
ask in the issue if you think it should move.

### Definition of ready

An issue is ready (`status:ready`) when it has:

- a Context section that says why,
- acceptance criteria as a checklist that someone else can verify,
- a Plan link (a file and task in `docs/plans/`, or a section of `docs/spec/`), or a short plan in the issue for small
  work,
- a "Depends on" list in which every issue is closed (or no dependencies),
- one `type:*`, at least one `area:*` and one `order:*` label,
- no open product question. If there is one, it goes to the maintainer first (`status:needs-user`).

### Definition of done

An issue is done when:

- every acceptance criterion is checked, or explicitly deferred in a comment that links a follow-up issue,
- tests were written first and pass, with counts reported in the pull request,
- the pull request was reviewed and approved (section 6),
- the results file and every doc the change affects are updated (section 9),
- the merged pull request said `Closes #N`, so the issue closed with the merge. If a maintainer step remains, the
  pull request says `Refs #N` instead, and the issue moves to `status:needs-user` with the steps listed.

## 3. Claiming work and avoiding collisions

To claim an issue:

1. Check that it is `status:ready` and has no assignee.
2. Assign yourself, swap the label and leave a one-line comment with your branch and first step:

   ```zsh
   gh issue edit <N> --add-assignee @me --add-label status:in-progress --remove-label status:ready
   gh issue comment <N> --body "Taking this. Branch feat/<N>-<slug>. Starting with <first step>."
   ```

3. Before writing code, check open pull requests for the files you need:

   ```zsh
   gh pr list --state open
   gh pr diff <PR> --name-only
   ```

   If another open pull request touches them, comment on your issue and on that pull request and agree on an order
   before starting.

Do not start on an issue someone else is assigned to. If an assignee has been silent for a few days, ask in the
issue; the maintainer can reassign.

### Repo hot files

These files are touched by most features and conflict often. Before changing one, leave a comment in your issue
("Touching `AppSession.swift`: adding the Archive window hook") so the other developer can rebase early or wait:

- `app/ArktShell/App/AppSession.swift`
- `app/ArktShell/ShellKit/Sources/ShellUI/Window/ShellWindowController.swift`
- `app/ArktShell/App/MainMenu.swift`
- `app/ArktCore/Package.swift`, `app/ArktShell/ShellKit/Package.swift`, `app/ArktShell/project.yml`
- `docs/plans/*-results.md`
- `engine/patches/chromium/.patches` (section 8)

Keep edits to these files small and in their own commits. Rebase on `main` often, at least daily and before asking
for review: `git fetch origin && git rebase origin/main`.

The engine plans also name "hot files" on the Chromium side (`browser_window_features.cc`, `tab_features.cc`). Those
are upstream files our patches avoid; their hunk count is tracked in the patch budget of the engine results file.

## 4. Branches and worktrees

- **One branch per issue**, named `<type>/<issue#>-<slug>`:
  - `feat/` new capability, `fix/` bug, `docs/` docs only, `engine/` Chromium overlay or patches, `chore/` build or
    housekeeping, `spike/` time-boxed experiment whose result is a written decision.
  - Examples: `feat/27-split-view`, `fix/25-command-bar-latency`, `engine/16-seam-fixes`.
- Branch from the latest `origin/main`. Do not branch from another open feature branch unless both pull requests say
  they land in that order.
- **Worktrees.** Keep the main checkout on `main` and work on each issue in its own worktree in a sibling folder:

  ```zsh
  git -C <repo> fetch origin
  git -C <repo> worktree add ../arkt-wt/<N>-<slug> -b feat/<N>-<slug> origin/main
  ```

  Never touch another person's or another issue's worktree. Remove yours after the merge (section 6).
- **Public history only.** This repository is public. Never push a branch that holds private notes, local paths,
  personal data or commits from a private repository. If a branch picked up something like that, rebuild it from
  `origin/main` with only the clean commits before pushing.

## 5. Commits

- Plain, imperative, descriptive messages: "Add the Archive window", "Fix the late command bar show". Add a body when
  the why is not obvious. No trailers and no emojis.
- **Pathspec staging only.** Name the files: `git add <path> <path>`. Never `git add -A` or `git add .`; worktrees
  hold build leftovers and local tool directories. For engine work, name each file, not a directory. Check
  `git diff --cached --stat` before committing.
- **Author identity.** Commit with your GitHub noreply address so no personal email lands in public history:

  ```zsh
  git config user.name "<Your Name>"
  git config user.email "<id>+<handle>@users.noreply.github.com"
  ```

  The address is listed in GitHub settings under Emails; turn on "Keep my email addresses private" there too.
- Exported Chromium patches and `.patches` are committed together with the overlay change that needs them.

## 6. Pull requests and review

- **Small and single-purpose**: one issue per pull request, one pull request per issue. Split large work into issues
  first.
- **Draft pull requests for work in progress.** Open a draft early for visibility; the issue stays
  `status:in-progress`. Mark it ready for review when the template checklist is complete, then move the issue to
  `status:in-review`.
- **Body.** Fill in the template (`.github/pull_request_template.md`): summary, `Closes #N` (or `Refs #N` when a
  maintainer step remains), plan and results links, changes, tests run with counts, deviations from the plan, manual
  checks needed, and screenshots or a screen recording for UI changes.
- **Review.** Once two developers are active (the second developer has write access), every pull request needs an
  approving review from someone other than the author; no self-merge. Until then the maintainer may merge their own
  pull requests after re-reading the diff.
- **Merge.** Squash merge only. The author merges after approval, with the pull request title as the squash subject,
  then deletes the branch and cleans up:

  ```zsh
  gh pr merge <PR> --squash --delete-branch
  git -C <repo> worktree remove ../arkt-wt/<N>-<slug>
  git -C <repo> worktree prune
  git -C <repo> branch -D feat/<N>-<slug>
  git -C <repo> pull --ff-only
  ```

### Reviewer checklist

Review in two passes.

**Pass 1, spec.** Does the change do what the issue and the plan say?

- Every acceptance criterion is met, or deferred with a follow-up issue.
- Deviations from the plan are listed and justified; no product question was decided silently.
- Tests cover the new behavior; the reported counts match "baseline + N".
- Results file, README or plan updated where the change affects them.

**Pass 2, quality.**

- Layering: only the app target (`app/ArktShell/App/*.swift`) imports `Persistence`; nothing in
  `ShellKit/Sources` imports `Persistence` or `GRDB`; nothing in `ShellKit/Sources/ShellUI` imports `SidebarModel`,
  `Archive`, `ArcImport`, `Persistence` or `GRDB`. `IsolationTests/CoreIsolationTests` is the gate.
- Only `FakeEngineKit` imports WebKit; `IsolationTests/WebKitIsolationTests` is the gate.
- Concurrency: Swift 6 mode, no new warnings, no `@unchecked Sendable` and no `nonisolated(unsafe)` in production
  code; diagnostics fixed at the root.
- The main thread never waits on disk: database, file and Arc reads run in `@concurrent` functions or GRDB's queue;
  main-actor code only `await`s.
- Hot paths (sidebar, command bar, window chrome, toasts, Archive table) are AppKit + Core Animation with frames set
  directly; no SwiftUI lists and no Auto Layout there.
- Engine: upstream changes only as exported patches; no widely included upstream header edited; patch budget table
  updated.
- Banned content: no emojis; no real browsing data, Arc data, titles, URLs, credentials, signing identities, team
  ids, personal paths or email addresses in code, fixtures, logs, docs or commit messages.

Use "Request changes" for anything that must change and plain comments for suggestions. The author answers every
comment (a fix, or a reason not to) before merging.

### Two pull requests on the same hot file

1. The one approved first merges first. If neither is approved yet, the smaller one goes first.
2. The other author rebases on the new `main`, resolves the conflict keeping both changes, reruns the full test set
   and posts the new counts in the pull request.
3. If the resolution changes behavior (not just text), the reviewer looks again before the merge.
4. In `docs/plans/*-results.md`, keep both sections; each change appends its own section and never rewrites another
   change's numbers.
5. For `.patches` and patch files, follow section 8.

## 7. Code rules

- **Shell: zsh.** Commands in docs and scripts are written for zsh.
- **No emojis** anywhere: sources, comments, logs, fixtures, commit messages, issues and pull requests.
- **Swift 6** language mode with complete concurrency checking, macOS 15 deployment target. No `@unchecked Sendable`
  or `nonisolated(unsafe)` in production code.
- **TDD.** Write the test first, run it and watch it fail (a compile error counts), implement, run it again. Pure
  logic goes into Swift Testing tests; anything that opens windows goes into `ShellKitGUITests`.
- **Hot paths** (sidebar, command bar, window chrome) are AppKit + Core Animation, not SwiftUI lists or Auto Layout.
- **Upstream Chromium changes** live only as patch files in `engine/patches/chromium`; follow the workflow in
  `engine/README.md`.
- **Capacity.** While a Chromium build runs on the machine, Swift builds and tests run with `nice -n 20` and two
  jobs (`swift test -j 2`, `xcodebuild ... -jobs 2`), and at most two Swift builds run at once.
- **Processes.** Stop processes you started by their PID; never `pkill` or `killall`.

### Before opening a pull request

```zsh
cd app/ArktCore && swift test
cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests
```

Run the GUI tests (`swift test --filter ShellKitGUITests`, logged-in GUI session) when you touch the shell UI, and
build the app (`xcodegen generate`, then `xcodebuild`, see `README.md`) when you touch `app/ArktShell/App` or
`project.yml`.

### Privacy

Test fixtures are synthetic. Never commit real browsing data, Arc data, titles, URLs, credentials or signing
identities. Never open, copy or grep real Arc data; tests use the synthetic fixtures under
`app/ArktCore/Tests/ArcImportTests/Fixtures/`. Logs print counts and enum case names, never titles, URLs or paths of
user data.

## 8. Engine work with more than one developer

The workflow in `engine/README.md` and the Rules section of the current engine plan apply in full. On top of that:

- **Own checkout, own outputs.** Each developer has their own `$CHROMIUM_ROOT` (depot_tools, `chromium/src` at the
  pinned tag) and their own `out/Spike` and `out/Arkt` directories. Checkouts and output directories are never
  shared between people.
- **Own overlay link.** `$CR/arkt` points at the `engine/arkt` of your own engine worktree. Before every build,
  `readlink $CR/arkt` must print that path; a wrong link means a stale build.
- **Patch author identity.** Commits on the Chromium branch `arkt` use one shared identity, so Export writes the
  same `From:` line for everyone. Set it once per checkout:

  ```zsh
  git -C $CR config user.name "Arkt contributors"
  git -C $CR config user.email "noreply@arkt.invalid"
  ```

  If an Export changes only the `From:` line of a patch you did not touch, restore that file before committing.
- **Patch numbers are claimed in the pull request.** A pull request that adds a patch states its number in the
  description ("adds patch 0004"). The number is reserved while that pull request is open; check open engine pull
  requests before choosing one.
- **Renumbering on conflict.** If another patch lands first with your number: rebase your branch on `main`, run
  Apply onto a fresh `arkt` branch (it now includes the merged patch), cherry-pick your commit on top, run Export
  (`format-patch` numbers by commit order), commit the renamed patch files and `.patches` together, update the patch
  budget table in the results file and the number in the pull request description.
- **One `.patches` change at a time.** Only one person changes the set or order of patches in `.patches` at a time.
  Announce it in the issue ("Exporting patches now"), export, commit, push, and say when you are done; then the other
  developer may export. Two pull requests that both add patches land one after the other, with a rebase and
  re-export in between.
- **Launch flags.** Every test launch passes `--user-data-dir` (a throwaway profile) and `--use-mock-keychain`, as
  `engine/README.md` requires. Only the maintainer launches without the mock keychain, for the release check.
- **Signing identities are personal.** Each developer signs local test bundles with their own Apple Development
  identity. Identity names, team ids, provisioning profiles and certificate hashes are never committed;
  `engine/arkt/branding/BRANDING` keeps `MAC_TEAM_ID` empty. The release signing identity belongs to the maintainer.
- **Disk and memory.** Each machine follows the disk, swap and quiet-machine rules in `engine/README.md` ("Release
  build (out/Arkt)"). A build stopped for space is recorded in the results file, never fixed by deleting files.

## 9. Plans, results and decisions

- **Plans** live in `docs/plans/<date>-<name>.md`: Rules, tasks with steps and checks, time-boxes, and an "Open
  questions (product decisions)" section. A plan is written before a multi-issue track starts and is reviewed like
  code.
- **Results** live in `docs/plans/<date>-<name>-results.md`, one section per task: what was done, the commands and
  numbers (test counts, timings, sizes), and what remains. Append your own section; do not rewrite another task's
  numbers.
- **Deviations.** When you do something different from the plan, record it in the results section (what changed and
  why), in the "Deviations from the plan" part of the pull request, and in the plan itself when later tasks depend
  on it. Never silently follow a different plan.
- **Decisions.** Product decisions are made by the maintainer in the issue (or a decision issue, section 10) and
  then copied into the plan's "Decisions" or "Open questions (product decisions)" section with the issue link, so the
  plan stays the one place to read them.
- **What stays out.** Notes that cannot be public (machine-specific details, private research, third-party material
  that cannot be redistributed, anything with user data) stay out of this repository. Put the public conclusion in
  the plan or results file instead.

## 10. Communication

- **Issues are the source of truth.** Decisions, blockers, hand-offs and status changes go into issue comments. If
  something was agreed elsewhere, summarize it in the issue.
- **Weekly roadmap update.** Once a week the maintainer updates the Roadmap issue (#30): what closed, what is in
  progress and by whom, what is blocked and on what, and what comes next by order.
- **Product questions.** For a question inside one issue, ask in a comment and set `status:needs-user`. For a
  question that affects several issues, open a task issue titled "Decision: <question>" with the options and their
  costs, label it `status:needs-user`, and link it from the affected issues. The maintainer answers there, and the
  answer is copied into the plan (section 9).
- **Heads-up comments** before touching a repo hot file or exporting patches (sections 3 and 8).

## 11. Main, releases and tags

- `main` is always green and buildable: both Swift packages' tests pass and the app builds against the FakeEngine. A
  change that breaks `main` is reverted first and fixed in a new pull request.
- Everything reaches `main` through a squash-merged pull request; no direct pushes.
- No release branches and no tags yet. Versioned tags start with the first build meant for users; this section will
  describe them then.

## 12. Repository settings to enable (maintainer)

Recommendations only; repository settings are changed by the maintainer.

- **Branch protection on `main`:** require a pull request before merging, 1 approving review, dismiss stale approvals
  on new commits, require review from code owners (this is what enforces `.github/CODEOWNERS`), require linear
  history, block force pushes and deletions, and require status checks once CI exists.
- **Merge options:** allow squash merging only; turn on "Automatically delete head branches".
- **Projects board:** a GitHub Projects board for the repository with a Status field whose values mirror the labels
  (Triage, Ready, In progress, In review, Blocked, Needs user, Done), plus Order and Area fields. The labels stay the
  source of truth until the board is automated.
- **CI:** a GitHub Actions workflow on macOS runners that runs `swift test` in `app/ArktCore` and
  `swift test --skip ShellKitGUITests` in `app/ArktShell/ShellKit` on every pull request and on `main`. Chromium is
  not built in CI (hours of build time and over 100 GB of disk); engine changes are verified locally and reported in
  the pull request.
