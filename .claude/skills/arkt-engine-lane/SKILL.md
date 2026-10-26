---
name: arkt-engine-lane
description: Use when working on the Arkt Chromium engine (engine/ overlay, patches, facade header, engine builds and smoke runs) - one engine task at a time in a dedicated engine worktree, facade seams before patches, .patches kept in sync, results recorded, and a fresh test profile per run.
---

# Arkt engine lane

The engine workflow is `engine/README.md` plus `CONTRIBUTING.md`, section 8. Variables follow `engine/README.md`:
`$REPO`, `$CHROMIUM_ROOT`, `$CR` (the Chromium `src` checkout) and `$PIN`. Every contributor has their own
checkout, outputs and overlay link; none are shared between people.

## 0. Gate: write it down before touching the engine

1. The task, and whether a seam in the facade or overlay can do it without a Chromium patch. If a patch is needed,
   why no seam works.
2. Whether the facade header changes. If yes: the additive change, and the issue where both lanes agree to it.
3. Whether `.patches` changes, and the patch number you claim in the pull request.
4. The build and smoke commands you will run, and the free disk they need.

**STOP** if item 2 is a non-additive change, or item 3 collides with an open engine pull request. Comment on the
issue and wait.

## 1. Checklist

1. **One engine task at a time**, in one engine worktree of your own (for example `../arkt-wt/engine`). Switch it to
   the task's branch; do not create a second engine worktree for a parallel task.
2. **Check the overlay link** before every build:
   `readlink $CR/arkt` must print `<engine worktree>/engine/arkt`. A wrong link means a stale build.
3. **Never delete a branch checked out in the engine worktree.** Check `git worktree list` first.
4. **Check disk** before building: `df -h $CHROMIUM_ROOT`. **STOP** if it is below what `engine/README.md` lists;
   record it in the results file, never free space by deleting files you did not create.
5. **Seams before patches.** Prefer `engine/arkt/api/`, `EngineAPI` or the overlay. A patch is the last resort.
6. **Facade header frozen.** Additive only; both copies byte-identical:
   `cmp engine/arkt/api/arkt_engine.h app/ArktShell/ShellKit/Sources/ArktEngineABI/include/arkt_engine.h`.
7. **Upstream edits only through Apply and Export** (`engine/README.md`). Announce the export in the issue. Commit the
   patch files and `.patches` together with the overlay change. If Export changes only the `From:` line of a patch
   you did not touch, restore that file.
8. **Keep `.patches` in sync:**

   ```zsh
   [ "$(git -C $CR rev-list --count $PIN..arkt)" = "$(wc -l < $REPO/engine/patches/chromium/.patches | tr -d ' ')" ] \
     && echo in sync || echo "run Export"
   ```

9. **Test launches** use a fresh, separately named throwaway profile and the mock keychain:

   ```zsh
   "$CR/out/Spike/Chromium.app/Contents/MacOS/Chromium" \
     --user-data-dir=$CHROMIUM_ROOT/profiles/<task>-<date> --use-mock-keychain \
     --no-first-run --no-default-browser-check --enable-logging=stderr <url> & PID=$!
   kill $PID   # when done; exact PID only
   ```

   Never point `--user-data-dir` at a real profile; never pass `--user-agent`. See `arkt-local-app-safety`.
10. **Capacity.** While a Chromium build runs, Swift builds and tests run at low priority with two jobs
    (`CONTRIBUTING.md`, section 7).

## 2. Record results, verify before you claim

Append your own section to the engine results file in `docs/plans/`: what was done, the commands, build and smoke
numbers, the patch budget table, and what remains. Never rewrite another task's numbers. The pull request quotes
the sync check output, the `cmp` result and the smoke result.

## Common mistakes we made

- A non-additive facade change (`.tabClosed` gaining a reason) that every call site and test double had to follow
  (engine week 3 results, "Non-additive changes").
- Export rewriting the `From:` line of untouched patches.
