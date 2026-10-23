# Arkt engine

`$CHROMIUM_ROOT` is the directory that holds the Chromium build environment: `depot_tools/` and the checkout in
`chromium/src` (pinned to the tag in `$PIN`). It needs well over 100 GB free; any local or external disk works.
Every doc in this repo uses these variables:

    export REPO=/path/to/arkt                      # root of this repository
    export CHROMIUM_ROOT=/path/to/arkt-chromium    # depot_tools/ and chromium/src live here
    export CR=$CHROMIUM_ROOT/chromium/src
    export PATH=$CHROMIUM_ROOT/depot_tools:$PATH
    export PIN=156.0.8078.48                       # pinned Chromium tag; changed only by a rebase (REBASE.md)

- `arkt/` is symlinked into the Chromium checkout as `src/arkt`. Our own sources only.
- `patches/chromium/*.patch` are the only upstream edits, applied in the order listed in `.patches`.
- //arkt is wired into the build by patch 0001: `//chrome/browser:core` (Mac) depends on `//arkt/browser`.

## Link the overlay

Once per checkout (both commands are safe to re-run):

    ln -sfn $REPO/engine/arkt $CR/arkt
    grep -qx /arkt $CR/.git/info/exclude || echo /arkt >> $CR/.git/info/exclude

## Apply

Fresh checkout at the pinned tag; stops at the first patch that fails to apply. It refuses to run if branch `arkt` already exists and its commit count differs from `.patches`, because `checkout -B` would discard commits that were never exported. It compares counts only, so an amended commit that was not exported is not detected; always run Export after editing upstream files.

    n_commits=$(git -C $CR rev-list --count $PIN..arkt 2>/dev/null || echo 0)
    n_patches=$(wc -l < $REPO/engine/patches/chromium/.patches | tr -d ' ')
    if git -C $CR rev-parse -q --verify arkt >/dev/null && [ "$n_commits" != "$n_patches" ]; then
      echo "arkt has unexported commits; run Export first"
    else
      git -C $CR checkout -B arkt $PIN
      for p in $(cat $REPO/engine/patches/chromium/.patches); do
        git -C $CR am -3 "$REPO/engine/patches/chromium/$p" || { echo "stopped at $p"; break; }
      done
    fi

## Export

After editing upstream files (one commit per patch on branch `arkt`). Patches are written to a temp dir first and replace the old ones only if `format-patch` succeeds and produced at least one patch; otherwise the existing patches are kept:

    tmp=$(mktemp -d)
    if git -C $CR format-patch --no-numbered --zero-commit --no-signature -o $tmp $PIN..arkt; then
      if [ -z "$(find $tmp -name '*.patch')" ]; then
        echo "no commits to export"
      else
        find $REPO/engine/patches/chromium -name '*.patch' -delete &&
          find $tmp -name '*.patch' -exec mv {} $REPO/engine/patches/chromium/ \; &&
          (cd $REPO/engine/patches/chromium && find . -name '*.patch' | sed 's|^\./||' | sort > .patches)
      fi
    fi
    rm -rf $tmp

## Rebase onto a new Chromium tag

The pin moves by rebase only, following `engine/REBASE.md` step by step, tracked in an issue opened from the
"Chromium rebase" template. In short:

- Trigger: every Chrome Stable security release of the pinned milestone is rebased, merged and installed within
  7 days of the Chrome release (maintainer decision, #138); milestone rebases follow the roadmap (#30). A security
  release whose patches apply cleanly and whose overlay builds unchanged takes the fast path (fewer checks).
- Procedure: save branch `arkt` as `arkt-<old tag>`, fetch the new tag (shallow), create a new `arkt` on it and
  apply `.patches` with `git am -3`, resolving conflicts inside each patch's own commit; `gclient sync`; set `PIN`
  above to the new tag and run Export. A rebase re-exports every patch, so announce it like any `.patches` change
  (`CONTRIBUTING.md`, section 8).
- Gate: `git -C $CR rev-list --count $PIN..arkt` equals the `.patches` line count, the patch budget holds (under 30
  patch files, no new patch, hot-file hunks not grown) and the budget table is updated.
- Checks: rebuild `out/Spike` and `out/Arkt`, then the engine smoke (design section 5, testing item 5), the W5b
  smoke matrix, Web Store install and extension popup, web identity (below), the keychain item string, and
  1Password once #23 records a GO. Re-sign (notarize once #125 lands), keep the previous bundle for rollback,
  install, record time and disk in the rebase log.

## Launch flags (every test launch)

Every test launch of a built engine (`out/Spike`, `out/Arkt`, or an installed test bundle) passes both of these:

- `--use-mock-keychain`: an in-memory fake keychain, so a test run never reads, creates or changes an item in the
  login keychain and never shows a keychain prompt. Encrypted profile data (cookies, saved passwords) therefore does
  not survive a relaunch of a test profile; extension installs and extension state do.
- `--user-data-dir=<test profile>`: a throwaway profile under `$CHROMIUM_ROOT/profiles` (or
  `~/Library/Application Support/ArktTest` for an installed bundle), never a real browser profile.

Usual companions: `--no-first-run --no-default-browser-check --enable-logging=stderr`. For example:

    "$CR/out/Spike/Chromium.app/Contents/MacOS/Chromium" --user-data-dir=$CHROMIUM_ROOT/profiles/<name> \
      --use-mock-keychain --no-first-run --no-default-browser-check --enable-logging=stderr <url>

Without the mock flag the product stores its encryption key in the login keychain as the generic password
"Arkt Safe Storage" (account "Arkt"); patch 0003 renames Chromium's "Chromium Safe Storage" item. Only a maintainer
runs a build without `--use-mock-keychain`, and only for the one release check that needs the real item.

## Web identity (check on every rebase)

Sites must see Arkt as Chrome. Issue #9 owns the product side; the checks run in the week-2 plan
(`docs/plans/2026-10-23-engine-week2.md`, Task W2 Step 3 and Task W10 Step 2).

- The engine sends Chromium's stock reduced user agent for the pinned milestone, unchanged:
  `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/<major>.0.0.0 Safari/537.36`.
  No patch touches it, and no `Arkt` token is added anywhere sites can read it.
- The client hints follow from the branding: with our branding file the build is `CHROMIUM_BRANDING`, so
  `Sec-CH-UA` and `navigator.userAgentData.brands` carry `Chromium` plus a GREASE brand and no product brand.
  Whether to also send a "Google Chrome" brand for parity is an open question (week-2 plan, "Open questions" 6).
- Never pass `--user-agent`, in any launch or test: it replaces the UA string but not the client hints, so the two
  disagree, and it hides what the build really sends.

After a rebase, on the rebuilt and installed bundle (launched with `--remote-debugging-port=9333`; the CDP helper
`engine/tools/cdp.mjs` comes with week-2 Task W0):

    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgent'
    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.brands.map(b=>b.brand)'
    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.getHighEntropyValues(["fullVersionList"]).then(v=>v.fullVersionList.map(b=>b.brand))'

Expected: the UA contains `Chrome/<new major>.0.0.0 Safari/537.36` for the new milestone and no `Arkt`; neither brand
list contains `Arkt`.

The dev engine (`FakeEngine`, WKWebView) is not Chrome and does not pretend to be: it keeps WebKit's own UA and
appends `Version/<installed Safari version> Safari/605.1.15` through `applicationNameForUserAgent`, read from the
installed Safari at launch, so test pages get the same markup Safari gets. Setting `customUserAgent` instead would
replace WebKit's platform and engine tokens with a hand-written copy that drifts.

## Release build (out/Arkt)

A self-contained, Arkt-branded, non-component build in its own output directory (`$REL=$CR/out/Arkt`). It shares no
objects with the component build in `out/Spike`. Branding comes from the GN arg `branding_file_path`, which points at
`arkt/branding/BRANDING` (no patch): it renames the app (`Arkt.app`), the framework (`Arkt Framework`), the helpers
(`Arkt Helper*.app`) and the bundle id (`com.arkt.Arkt`, a placeholder). Icons and UI strings stay Chromium's.

`$REL/args.gn`:

    is_debug = false
    is_component_build = false
    is_official_build = false     # official turns on PGO/ThinLTO and adds hours
    chrome_pgo_phase = 0
    symbol_level = 0
    blink_symbol_level = 0
    v8_symbol_level = 0
    dcheck_always_on = false
    target_cpu = "arm64"
    use_siso = true
    branding_file_path = "//arkt/branding/BRANDING"

Generate and confirm the branding took (expect `branding_file_path = "//arkt/branding/BRANDING"`):

    cd $CR && gn gen out/Arkt && gn args out/Arkt --list=branding_file_path --short

Before the build, and every hour while it runs: the Chromium disk needs at least 40 GB free; the internal disk (it
holds swap) needs at least 8 GiB free. Record the swap use each time. Below about 4 GiB free on `/`, stop the build by
its recorded PID and do not delete files to make room. A full build compiles about 75k objects and ends in one large,
memory-heavy link of `Arkt Framework`; while that link runs, keep the machine quiet (no other Chromium or Swift
builds). Budget 5-7 h on a quiet machine, up to 14 h under load; the output directory is 10-15 GB.

    df -h $CHROMIUM_ROOT | tail -1
    df -h / | tail -1
    sysctl vm.swapusage
    cd $CR && nice -n 15 autoninja -C out/Arkt chrome > $CHROMIUM_ROOT/build-arkt.log 2>&1 &
    echo $! > $CHROMIUM_ROOT/build-arkt.pid

Check the result with `tail -3 $CHROMIUM_ROOT/build-arkt.log` (expect `The build has finished successfully.`) and
`grep -c FAILED: $CHROMIUM_ROOT/build-arkt.log` (expect `0`). The build compiles whatever overlay and patches are in
`$CR` at the time, so the branch providing `arkt/branding/BRANDING` must stay checked out until it finishes.

`out/Arkt` must be re-signed after every rebuild, incremental ones included (plan W2): a rebuild replaces the signed
binaries.
