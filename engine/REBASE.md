# Chromium rebase runbook

How Arkt moves its Chromium pin to a new upstream tag: fetch, reapply the patch series, rebuild both output
directories, verify, re-sign and ship. `engine/README.md` holds the variables, Apply, Export and the build rules this
runbook uses; read it first. Every rebase is tracked in its own issue, opened from the "Chromium rebase" issue
template (`.github/ISSUE_TEMPLATE/rebase.md`), whose body is the checklist at the end of this file.

Shell is zsh. Set once per shell, in addition to the variables in `engine/README.md`:

    export OLD=$PIN                 # the current pin (engine/README.md)
    export NEW=<new tag>            # for example 156.0.8078.60 (security) or 157.0.xxxx.yy (milestone)

## 1. Trigger and deadline

| Kind | Trigger | Deadline |
|---|---|---|
| Security | Chrome ships a new build of the pinned milestone with security fixes (which channel: Policy a): the Chrome Releases blog post "Stable Channel Update for Desktop", Mac row on the Chromium Dash releases page. | Merged and installed within 7 days of the Chrome release. |
| Milestone | A new Chrome milestone reaches Stable. | As planned on the roadmap (#30), except Policy b. |

### Policy

The rebase rules every other document points to (maintainer decision on #138):

- Every Chrome security release of the pinned milestone is rebased, merged and installed within 7 days of the
  Chrome release; milestone rebases follow the roadmap (#30).
- a. While the pin is on an Extended Stable milestone, the security path follows the Extended Stable releases of
  that milestone.
- b. When the pinned milestone stops receiving fixes, the next security release is on a newer milestone, and that
  milestone rebase takes the 7-day deadline.

Whoever sees the release opens the rebase issue the same day (template above), with the Chrome release date and
the deadline in the title line of the body. The issue is claimed like any other (`CONTRIBUTING.md`, section 3).

### Fast path or full path

The **fast path** (security release) applies only when all of these hold:

- `$NEW` has the same `MAJOR.MINOR.BUILD` as `$OLD`; only `PATCH` differs,
- every patch applies with `git am -3` without a conflict (section 4),
- `out/Spike` builds without changing the overlay (section 5).

If any fails, switch to the **full path** and note it in the issue. The verification list (section 7) marks which
checks the fast path may skip. Everything else is the same for both paths.

## 2. Names

| Thing | Name |
|---|---|
| Rebase issue | `Rebase: Chromium <NEW>` |
| Repo branch | `engine/<issue#>-rebase-<NEW>`, for example `engine/250-rebase-156.0.8078.60` |
| Repo worktree | `../arkt-wt/<issue#>-rebase-<NEW>` |
| Chromium working branch | `arkt` (always the branch Apply and Export use) |
| Chromium backup branch | `arkt-<OLD>`: the previous `arkt`, kept until the next rebase merges (rollback) |
| Pull request title | `Rebase Chromium onto <NEW>` |

No repository tags: `CONTRIBUTING.md` section 11 has none yet. The pin is the `PIN` line in `engine/README.md`, set
by the merged rebase pull request.

## 3. Before you start

1. Announce it. A rebase re-exports every patch file, so it is a `.patches` change for the whole run
   (`CONTRIBUTING.md`, section 8). Comment in the rebase issue "Exporting patches now" and in every open engine pull
   request (`gh pr list --state open`, branches `engine/*`). Those pull requests rebase and re-export after this one
   merges; no other `.patches` change lands while it is open.
2. Clean state. `git -C $CR status --short --untracked-files=no` prints nothing, the Apply guard in `engine/README.md` passes (branch
   `arkt` commit count equals the `.patches` line count), and no build or engine process is running
   (`ps -axo pid,command | grep -E "out/Spike|out/Arkt" | grep -v grep`).
3. Worktree. Create the repo worktree from `origin/main` (`CONTRIBUTING.md`, section 4) and point the overlay at it:

       ln -sfn $REPO/engine/arkt $CR/arkt && readlink $CR/arkt     # must print $REPO/engine/arkt

4. Disk. `df -h $CHROMIUM_ROOT | tail -1` at least 60 GB free (the new tag, a full rebuild of both output
   directories); `df -h / | tail -1` at least 8 GiB free; record `sysctl vm.swapusage`. The rules in
   `engine/README.md` ("Release build (out/Arkt)") apply for the whole run.
5. Milestone rebases only: update depot_tools. Chromium's sync hooks turn its self-update off, so pull it by hand:
   `git -C $CHROMIUM_ROOT/depot_tools pull --ff-only`.

## 4. Fetch and reapply the patches

The checkout is shallow (`gclient sync --no-history`), holding only the pinned tag. Keep the old tag and the backup
branch until the rebase merges: `git am -3` needs the old blobs to fall back to a three-way merge.

    git -C $CR rev-parse arkt > $CHROMIUM_ROOT/arkt-before-rebase-$OLD.sha
    git -C $CR branch -m arkt arkt-$OLD
    GIT_LFS_SKIP_SMUDGE=1 git -C $CR fetch --depth 1 origin tag $NEW
    git -C $CR checkout -b arkt $NEW
    GIT_LFS_SKIP_SMUDGE=1 git -C $CR am -3 $(sed "s|^|$REPO/engine/patches/chromium/|" $REPO/engine/patches/chromium/.patches)

Renaming `arkt` first is required: Apply's guard (and `checkout -B`) would otherwise see the old commits on top of
the new tag. `GIT_LFS_SKIP_SMUDGE=1` is the week-1 LiteRT workaround (`docs/plans/2026-10-22-week1-results.md`,
Task 1).

### Conflicts

`git am` stops at the first patch that does not apply and names it.

1. `git -C $CR status --short` lists the conflicted files. See what upstream changed with
   `git -C $CR diff $OLD $NEW -- <file>` (the shallow checkout has no history in between, only the two trees).
2. Resolve with the same intent as the patch, keeping the hunk as small as before. If upstream now does what the
   patch did, drop the patch with `git -C $CR am --skip` and record it as dropped.
3. `git -C $CR add <file> ...` (name each file), then `git -C $CR am --continue`. The patch keeps its commit subject
   and the shared author identity (`CONTRIBUTING.md`, section 8).
4. A conflict never becomes a new patch. One commit per existing patch, nothing else on `arkt`.

When the series is done: `git -C $CR rev-list --count $NEW..arkt` equals the `.patches` line count (minus any
dropped patch).

### Sync the dependencies

From the gclient root, with `arkt` checked out. Always pin `src` to the tag: `.gclient` names no revision and `arkt`
tracks no upstream, so a plain `gclient sync` would rebase `arkt` onto `origin/main`. With the tag, the rebase of
`arkt` onto `$NEW` is a no-op and only the dependencies move to the new `DEPS`:

    cd $CHROMIUM_ROOT/chromium && gclient sync -D --no-history --with_tags -j 4 --revision src@refs/tags/$NEW \
      > $CHROMIUM_ROOT/sync-$NEW.log 2>&1
    tail -5 $CHROMIUM_ROOT/sync-$NEW.log
    cat $CR/chrome/VERSION        # MAJOR.MINOR.BUILD.PATCH must equal $NEW

Never pass `--reset` or `--force`: they discard local changes. If a dependency fails to fetch, rerun the same
command; if a hook fails, check it against the toolchain fixes in the week-1 results (Task 1: LiteRT LFS skip,
`enable_nacl`, Xcode Metal toolchain) before changing anything.

### Export

Set `PIN=$NEW` in `engine/README.md` (and `export PIN=$NEW` in the shell), then run Export from `engine/README.md`.
Every patch file is rewritten (new index lines; renumbered if one was dropped). Commit all patch files and
`.patches` together. If a patch differs only in its `From:` line, restore it (`CONTRIBUTING.md`, section 8).

## 5. Build and triage overlay breakage

Build `out/Spike` first (component, used for every check below), then `out/Arkt` (release) in the background,
following the disk, swap and quiet-machine rules in `engine/README.md`. After a tag change both are close to full
rebuilds.

    cd $CR && gn gen out/Spike && autoninja -C out/Spike chrome > $CHROMIUM_ROOT/build-rebase-spike.log 2>&1
    tail -3 $CHROMIUM_ROOT/build-rebase-spike.log; grep -c FAILED: $CHROMIUM_ROOT/build-rebase-spike.log

    cd $CR && gn gen out/Arkt && gn args out/Arkt --list=branding_file_path --short
    nice -n 15 autoninja -C out/Arkt chrome > $CHROMIUM_ROOT/build-rebase-arkt.log 2>&1 &
    echo $! > $CHROMIUM_ROOT/build-arkt.pid

Record start and end times and `du -sh out/Spike out/Arkt` for the rebase log (section 10).

Triage each `FAILED:` line by where it is:

| Failure | Meaning | Fix |
|---|---|---|
| `git am` stopped | Patch conflict | Section 4, in the patch's own commit. |
| `gn gen` error naming `//arkt/...` | A GN target the overlay depends on moved or was renamed | Fix the deps in `engine/arkt/**/BUILD.gn`. No patch. |
| Compile error in `arkt/...` | Upstream API changed under the overlay | Find the new symbol with `git -C $CR grep -n '<symbol>'` and `git -C $CR diff $OLD $NEW -- <header>`; fix in the overlay. No patch. |
| Compile error in a patched upstream file | The resolved patch no longer fits | Fix it in that patch's commit: `git -C $CR commit --fixup=<commit> <file>`, then `GIT_SEQUENCE_EDITOR=: git -C $CR rebase -i --autosquash $NEW`; re-Export. |
| Link error, missing `_ChromeMain`, missing helpers | Build config or branding drift | Compare `args.gn` and `engine/arkt/branding/BRANDING` with `chrome/app/theme/chromium/BRANDING` at `$NEW`. |

Overlay fixes are committed on the rebase branch, one commit per fix, with the reason in the message. A fix that
needs an upstream change is a new patch only after the patch budget gate (section 6) allows it; say so in the
issue first.

## 6. Patch budget gate

Run after Export and before the verification:

    git -C $CR rev-list --count $NEW..arkt; wc -l < $REPO/engine/patches/chromium/.patches
    git -C $CR diff --stat $NEW..arkt | tail -1
    git -C $CR diff $NEW..arkt -- chrome/browser/ui/browser_window/internal/browser_window_features.cc \
      chrome/browser/ui/tabs/tab_features.cc | grep -c '^@@'

The rebase passes the gate when:

- the two counts on the first line are equal,
- the patch files stay under 30 (design target), and the rebase added none,
- the hot-file hunk count did not grow, and the seam limits from the week-2 plan still hold (at most 8 seam patch
  files, 25 upstream files, 6 hot-file hunks, no widely included header),
- the patch budget table in the current engine results file is updated with the new numbers.

If the gate fails, stop and set the issue to `status:needs-user` with the numbers; the maintainer decides.

## 7. Verification

Run every check on the rebuilt builds with the launch flags from `engine/README.md` (`--user-data-dir` throwaway
profile, `--use-mock-keychain`, never `--user-agent`). The task names point at the week-2 plan
(`docs/plans/2026-10-23-engine-week2.md`), which has the exact commands. `F` = full path only; everything else runs
on both paths.

1. Version: `chrome://version` in `out/Spike` shows `$NEW`.
2. Smoke matrix, W5b Step 1: all 17 scenarios pass (the native window is the default since W9; no switch). Fast
   path: scenarios 1-8.
3. Tab list and visibility, W5c Step 3. (F)
4. Web Store install on the native window, W7: uBlock Origin Lite installs, census `views=0`.
5. Extension popup: the uBO Lite popup opens from the Extensions menu path (W4 Step 7).
6. Web identity on the signed `Arkt.app` (W2 Step 3, `engine/README.md` "Web identity", #9), with the commands in
   that section: `navigator.userAgent` is the stock reduced string ending in `Chrome/<new major>.0.0.0
   Safari/537.36`; `navigator.userAgentData.brands` and the `fullVersionList` brands are exactly `Chromium` (new
   major or full version) plus one GREASE brand, no `Arkt`, no other product brand; the loopback echo page shows the
   same `user-agent`, `sec-ch-ua` and `sec-ch-ua-full-version-list`; `_ChromeMain` count is `1`. A changed brand
   list (a product brand appearing, `Chromium` missing) or any `Arkt` token fails the check. The Web Store "Switch to
   Chrome" banner is expected and is not part of this check.
7. Keychain item, W8 Step 3 on `Arkt Framework`: `Arkt Safe Storage` present, `Chromium Safe Storage` absent. If
   patch 0003 changed in this rebase, the maintainer repeats W8 "Needs the user" step 2 on the installed app.
8. Embedding: the Swift app loads the new framework and renders a page (week-2 Task WE, or the shipping embedding
   once it lands). (F)
9. 120 Hz: the week-1 Task 5 frame-interval check in the AppKit window. (F)
10. 1Password: popup connects to the desktop app (W2 "Needs the user"); maintainer step; required once #23 can be
    re-tested with a Developer ID signature (#125, planned at beta).
11. Housekeeping: no engine process left (`ps -axo pid,command | grep -E "out/Spike|out/Arkt|/Applications/Arkt.app" | grep -v grep`), patch counts match.

A failed check blocks the merge. Fix it on the rebase branch, or roll back (section 9).

## 8. Re-sign, install, ship

1. Re-sign `out/Arkt` inside-out with week-2 Task W2 Step 1 (every rebuild replaces the signed binaries). Once #125
   lands, its Developer ID signing and notarization steps replace this step; the rebase then also notarizes and
   staples before install.
2. Keep the previous installed bundle for rollback, then replace it (W10 Step 1):

       codesign -dv /Applications/Arkt.app 2>&1 | grep Identifier=dev.arkt.Arkt
       mkdir -p $CHROMIUM_ROOT/releases && ditto /Applications/Arkt.app $CHROMIUM_ROOT/releases/Arkt-$OLD.app
       rm -rf /Applications/Arkt.app && ditto $CR/out/Arkt/Arkt.app /Applications/Arkt.app

   Disk on `/` must stay at least 4 GiB free after the copy. Run checks 6, 7 and 10 on the installed copy.
3. Open the pull request (`Closes #<rebase issue>`): patch files, `.patches`, `PIN` in `engine/README.md`, the pin
   row in `docs/plans/2026-10-22-arkt-design.md` (milestone rebases), overlay fixes, the patch budget table and the
   rebase log row. Report the checklist results in the body.
4. After the merge: tell the open engine pull requests to rebase and re-export (section 3), point `$CR/arkt` back at
   the engine worktree you use day to day, and delete the backup branch of the rebase before last
   (`git -C $CR branch -D arkt-<pin before OLD>`) and its saved bundle. Publishing builds to users comes with #125
   and the release process; until then shipping means the merged pin and the installed `/Applications/Arkt.app`.

## 9. Rollback

Before the merge (a check fails and cannot be fixed by the deadline):

    git -C $CR branch -m arkt arkt-$NEW-failed
    git -C $CR branch -m arkt-$OLD arkt
    git -C $CR checkout arkt
    cd $CHROMIUM_ROOT/chromium && gclient sync -D --no-history --with_tags -j 4 --revision src@refs/tags/$OLD

Then rebuild `out/Spike` and `out/Arkt` (incremental), re-sign, and if the new bundle was already installed, restore
the saved one (`ditto $CHROMIUM_ROOT/releases/Arkt-$OLD.app /Applications/Arkt.app` after removing the new one).
Leave the pull request open as a draft with the failing check, set the issue to `status:blocked` naming it, and tell
the maintainer: a rollback leaves the security fixes unshipped, so the 7-day deadline still runs.

After the merge: revert the squash commit in a new pull request (`CONTRIBUTING.md`, section 11), then the steps
above. `arkt-$OLD` and the saved bundle are what make this possible; do not delete them before the next rebase.

## 10. Rebase log

One row per rebase, appended by its pull request. Times are wall clock on the build machine; note how loaded it was.

| Date | From -> to | Path | Patches (conflicts, dropped) | Overlay fixes | Fetch + sync | `out/Spike` build | `out/Arkt` build | Disk (`out/Spike`, `out/Arkt`, free after) | Issue |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-22 | initial pin 156.0.8078.48 | - | 2 at start (6 at week 2) | - | not recorded | ~75k objects, full | not finished (W1 stopped on swap; plan budget 5-7 h quiet, up to 14 h loaded) | 6.1 GB, 1.3 GB partial (10-15 GB expected), - | - |

The first real rebase is the dry run for the time and disk budget: its row replaces the estimates above.

## Rebase issue checklist

The body of `.github/ISSUE_TEMPLATE/rebase.md`, repeated here for reference:

- Chrome release date, kind (security or milestone), deadline (release date + 7 days for security)
- Announced "Exporting patches now" in this issue and on open engine pull requests
- Clean `$CR`, Apply guard passes, disk and swap recorded, overlay link checked
- `arkt` saved as `arkt-<OLD>`; `$NEW` fetched; patches applied (conflicts and dropped patches listed)
- `gclient sync --revision src@refs/tags/$NEW` done; `chrome/VERSION` equals `$NEW`
- Export done with `PIN=$NEW`; patch files and `.patches` committed
- `out/Spike` and `out/Arkt` built, no `FAILED:`; overlay fixes listed
- Patch budget gate passes; budget table updated
- Verification 1-11 (section 7) with results
- Re-signed (notarized once #125 lands); previous bundle saved; installed bundle checked
- Rebase log row with times and disk
- Pull request open; backup branch and saved bundle kept until the next rebase
