---
name: arkt-engine-lane
description: Use when working on the Arkt Chromium engine (engine/ overlay, patches, facade header, engine builds and smoke runs) - one engine task at a time in a dedicated engine worktree, facade seams before patches, .patches kept in sync, results recorded, and a fresh test profile per run.
---

# Arkt engine lane

The engine workflow is `engine/README.md` plus `CONTRIBUTING.md`, section 8. Variables follow `engine/README.md`:
`$REPO`, `$CHROMIUM_ROOT`, `$CR` (the Chromium `src` checkout) and `$PIN`. Every contributor has their own
checkout, outputs and overlay link; none of them are shared between people.

## One task at a time

- Run one engine task at a time, in one engine worktree of your own (for example `../arkt-wt/engine`). `$CR/arkt`
  links to that worktree's `engine/arkt`. Before every build, check the link:

  ```zsh
  readlink $CR/arkt   # must print <engine worktree>/engine/arkt
  ```

- Switch the engine worktree to the task's branch; do not create a second engine worktree for a parallel task.
- Never delete a branch that is checked out in the engine worktree. Check first:

  ```zsh
  git worktree list   # the engine worktree's branch is in use
  ```

## Seams before patches

- Prefer a seam in the facade (`engine/arkt/api/`, `EngineAPI`) or the overlay over a Chromium patch. A patch is the
  last resort and needs a reason in the pull request.
- The facade header is frozen: additive changes only, and both copies stay byte-identical (`engine/arkt/api/arkt_engine.h`
  and `app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h`).
- Upstream edits go only through Apply and Export in `engine/README.md`. Commit the patch files and `.patches`
  together with the overlay change. Claim the patch number in the pull request and announce exports in the issue
  (section 8).
- Keep `.patches` in sync with branch `arkt`:

  ```zsh
  [ "$(git -C $CR rev-list --count $PIN..arkt)" = "$(wc -l < $REPO/engine/patches/chromium/.patches | tr -d ' ')" ] \
    && echo in sync || echo "run Export"
  ```

## Record results

Append your own section to the engine results file in `docs/plans/` (section 9): what was done, commands, build
and smoke numbers, the patch budget table, and what remains. Never rewrite another task's numbers. A build stopped
for disk space is recorded, not fixed by deleting files.

## Test launches

- Every launch uses a fresh, separately named throwaway profile and the mock keychain (`engine/README.md`,
  "Launch flags"):

  ```zsh
  "$CR/out/Spike/Chromium.app/Contents/MacOS/Chromium" \
    --user-data-dir=$CHROMIUM_ROOT/profiles/<task>-<date> --use-mock-keychain \
    --no-first-run --no-default-browser-check --enable-logging=stderr <url>
  ```

- Never point `--user-data-dir` at a real browser profile, never pass `--user-agent`, and stop what you launched by
  its PID (see `arkt-local-app-safety`).
- While a Chromium build runs, Swift builds and tests run at low priority with two jobs (`CONTRIBUTING.md`,
  section 7, "Capacity").
