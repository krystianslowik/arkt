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
      git -C $CR checkout -B arkt ${PIN:?}
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

- Trigger and deadline: the "Policy" list in `engine/REBASE.md` section 1 (security releases within 7 days). A
  security release whose patches apply cleanly and whose overlay builds unchanged takes the fast path (fewer checks).
- Procedure: save branch `arkt` as `arkt-<old tag>`, fetch the new tag (shallow), create a new `arkt` on it and
  apply `.patches` with `git am -3`, resolving conflicts inside each patch's own commit; `gclient sync` with
  `--revision src@refs/tags/<new tag>` (never without it); set `PIN` above to the new tag and run Export. A rebase
  re-exports every patch, so announce it like any `.patches` change (`CONTRIBUTING.md`, section 8).
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
  `Sec-CH-UA` and `navigator.userAgentData.brands` carry `Chromium` plus a GREASE brand and no product brand
  (for 156: `"Not:A-Brand";v="8", "Chromium";v="156"`). No "Google Chrome" brand: it would take a patch
  (`ChromeContentBrowserClient::GetUserAgentMetadata`), and it does not remove the Web Store "Switch to Chrome"
  banner, which shows even with that brand sent (#9; week-3 results, "#9: Web identity"). The banner is expected and
  is not a regression.
- Never set `is_chrome_branded`: it turns on Google-only code paths, and with our branding file it would add
  `PRODUCT_FULLNAME` ("Arkt") to the brand list. The branding file alone never changes the brands.
- Never pass `--user-agent`, in any launch or test: it replaces the UA string but not the client hints, so the two
  disagree, and it hides what the build really sends.

After a rebase, on the rebuilt and installed bundle (launched with `--remote-debugging-port=9333`; the CDP helper
`engine/tools/cdp.mjs` comes with week-2 Task W0):

    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgent'
    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.brands.map(b=>b.brand)'
    node $REPO/engine/tools/cdp.mjs example.com 'navigator.userAgentData.getHighEntropyValues(["fullVersionList"]).then(v=>v.fullVersionList.map(b=>b.brand))'

Then the request headers, on a loopback echo page (no external echo service; it asks for the high-entropy hints with
`Accept-CH`, so load it twice):

    node -e 'require("http").createServer((q,r)=>{r.setHeader("Accept-CH","Sec-CH-UA-Full-Version-List");r.end(JSON.stringify(q.headers,null,1))}).listen(9480,"127.0.0.1")' & ECHO=$!
    node $REPO/engine/tools/cdp.mjs --navigate type:page http://127.0.0.1:9480/
    node $REPO/engine/tools/cdp.mjs --navigate 127.0.0.1:9480 http://127.0.0.1:9480/
    node $REPO/engine/tools/cdp.mjs 127.0.0.1:9480 'document.body.innerText'
    kill $ECHO

Expected: the UA is exactly the stock reduced string above with `Chrome/<new major>.0.0.0 Safari/537.36` for the new
milestone; `brands`, `fullVersionList`, `sec-ch-ua` and `sec-ch-ua-full-version-list` each list exactly `Chromium`
(new major, and the full version in the full lists) and one GREASE brand; no `Arkt` and no other product brand
anywhere; `user-agent` in the echoed headers equals `navigator.userAgent`.

The dev engine (`FakeEngine`, WKWebView) is not Chrome and does not pretend to be: it keeps WebKit's own UA and
appends `Version/<installed Safari version> Safari/605.1.15` through `applicationNameForUserAgent`, read from the
installed Safari at launch, so test pages get the same markup Safari gets. Setting `customUserAgent` instead would
replace WebKit's platform and engine tokens with a hand-written copy that drifts.

## Release build (out/Arkt)

A self-contained, Arkt-branded, non-component build in its own output directory (`$REL=$CR/out/Arkt`). It shares no
objects with the component build in `out/Spike`. Branding comes from the GN arg `branding_file_path`, which points at
`arkt/branding/BRANDING` (no patch): it renames the app (`Arkt.app`), the framework (`Arkt Framework`), the helpers
(`Arkt Helper*.app`) and the bundle id (`dev.arkt.Arkt`, #73 and #128; helpers and the framework derive theirs from it). Icons and UI strings stay Chromium's.

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

Measured on this Mac (10 cores, 32 GB, 2026-10-24): 4 h 11 min, about 66k steps, 0 failed; `Arkt.app` 541 MB,
`out/Arkt` 7.6 GB; the framework link took under a minute. Swap, not CPU, is the limit: at `-j 6` swap use grew by
1.6 GB in 20 minutes, at `-j 4` it stayed flat. Swap use does not shrink afterwards, so pass `-j 4` to `autoninja`
when swap is already above about 6 GB. To pause or stop the build, signal the `siso ninja` process
(`ps -axo pid,command | grep '[s]iso ninja'`), not the shell PID from `$!`; `siso ps -C out/Arkt -n 1` (in
`third_party/siso/cipd/`) shows progress when the log is quiet. The result is ad-hoc (linker) signed and launches
as is; it must be re-signed after every rebuild before it goes into `/Applications` (W2).

## Sign and install (out/Arkt)

`out/Arkt` must be re-signed after every rebuild, incremental ones included (plan W2): a rebuild replaces the signed
binaries. Sign a copy, never `$REL` itself, so the build output stays as the linker left it. The identity is any
Apple Development (or Developer ID) certificate in the login keychain; pass its hash from
`security find-identity -v -p codesigning`. Never write the identity, team id or certificate hash into this repo.
Sign inside-out, with the entitlements files Chromium ships in `chrome/app/` and the hardened runtime on every
executable (as in `chrome/installer/mac/signing/parts.py`: JIT only for the Renderer and GPU helpers, the device and
personal-information entitlements only on the app):

    ID=<certificate hash>; ENT=$CR/chrome/app; STAGE=$CHROMIUM_ROOT/stage-w2
    mkdir -p $STAGE && ditto $REL/Arkt.app $STAGE/Arkt.app && cd $STAGE
    S=(codesign --force --timestamp=none --sign $ID)
    F="Arkt.app/Contents/Frameworks/Arkt Framework.framework/Versions/Current"
    for l in "$F"/Libraries/*.dylib; do $S "$l"; done
    for b in "$F"/Helpers/chrome_crashpad_handler "$F"/Helpers/app_mode_loader "$F"/Helpers/web_app_shortcut_copier; do
      [[ -e "$b" ]] && $S --options runtime "$b"; done
    for h in "$F"/Helpers/*.app; do case "$h" in
      *Renderer*) e="--entitlements $ENT/helper-renderer-entitlements.plist";;
      *GPU*) e="--entitlements $ENT/helper-gpu-entitlements.plist";; *) e="";; esac
      $S --options runtime ${=e} "$h"; done
    $S "Arkt.app/Contents/Frameworks/Arkt Framework.framework"
    $S --options runtime --entitlements $ENT/app-entitlements.plist Arkt.app
    codesign --verify --deep --strict --verbose=2 Arkt.app      # valid on disk, satisfies its Designated Requirement
    codesign -dv Arkt.app 2>&1 | grep -E '^(Identifier|CodeDirectory)'   # dev.arkt.Arkt, flags=0x10000(runtime)

List `"$F"/Helpers` first: every executable there must be covered (11 entries on 156: eight `Arkt Helper*.app`,
including the four `Aperitif` ones, plus the three tools above). `--timestamp=none` keeps signing offline; a
notarized build (#125) needs a secure timestamp and a Developer ID certificate instead.

Install (the internal disk holds swap; keep at least 4 GB free after the copy):

    df -h / | tail -1; sysctl vm.swapusage
    ls -d /Applications/Arkt.app 2>/dev/null && echo EXISTS   # replace only a bundle this project installed
    ditto $STAGE/Arkt.app /Applications/Arkt.app
    codesign --verify --deep --strict --verbose=2 /Applications/Arkt.app
    spctl --assess --type execute -vv /Applications/Arkt.app   # "rejected" until the build is notarized (#125)

To replace an older install, move it aside first (keep it for rollback until the new one passes the smoke), then
`ditto` the new one in. Smoke from `/Applications` with a fresh profile and the launch flags above: plan W2 Step 3.

## Embedding in the app (Engine configuration on out/Arkt)

The shell app (`app/ArktShell`, configuration `Engine`) loads the engine framework from its own
`Contents/Frameworks` and calls `ChromeMain` (week-3 plan, Decision 1). On `out/Arkt` the framework is
self-contained: no component dylibs next to the bundle, so the app can be copied anywhere. Layout:

    ArktShell.app/Contents/
      MacOS/ArktShell                       Swift app (arm64); dlopens the framework, never links it
      Frameworks/Arkt Framework.framework/  copied unchanged from $REL/Arkt.app by the Engine build phase
        Versions/<version>/Libraries/       libaperitif, libvk_swiftshader, libvulkan (+ data files)
        Versions/<version>/Helpers/         8 Arkt Helper*.app, chrome_crashpad_handler, app_mode_loader,
                                            web_app_shortcut_copier (11 entries on 156)
      Resources/GRDB_GRDB.bundle            resources only, no code
      Info.plist                            ArktEngineFrameworkName, ArktEngineFrameworkVersion, CrProductDirName

Build the app against the release framework without editing `Local.xcconfig` (it may point at `out/Spike` for
development), into a folder on the Chromium disk:

    cd $REPO/app/ArktShell && xcodebuild -scheme ArktShell -configuration Engine \
      ARKT_ENGINE_APP=$REL/Arkt.app CONFIGURATION_BUILD_DIR=$CHROMIUM_ROOT/embed-rel \
      -derivedDataPath $CHROMIUM_ROOT/arkt-shell-dd/embed-rel build

Expect `Engine framework copied: Arkt Framework.framework <version>` in the log and `ArktEngineFrameworkName = Arkt
Framework` in the app's Info.plist. Xcode signs only the app (ad hoc); the framework keeps the linker's signature
until the steps below.

**Sign** a copy, inside-out, with one identity, taking each part's options and entitlements from
`chrome/installer/mac/signing/parts.py`. The helpers' sandbox profiles are not touched.

| Part | `--options` | `--entitlements` (`$CR/chrome/app/`) |
|---|---|---|
| `Libraries/*.dylib` | none | none |
| `chrome_crashpad_handler`, `app_mode_loader`, `web_app_shortcut_copier` | `restrict,library,kill,runtime` | none |
| `Arkt Helper.app`, `(Alerts)`, `(Aperitif)`, `(Aperitif Alerts)` | `restrict,library,kill,runtime` | none |
| `(Renderer)`, `(Aperitif Renderer)` | `restrict,kill,runtime` | `helper-renderer-entitlements.plist` (JIT) |
| `(GPU)`, `(Aperitif GPU)` | `restrict,kill,runtime` | `helper-gpu-entitlements.plist` (JIT) |
| `Arkt Framework.framework` | none | none |
| `ArktShell.app` (last) | `restrict,library,kill,runtime` | `app-entitlements.plist` |

    ID=<certificate hash>; ENT=$CR/chrome/app; STAGE=$CHROMIUM_ROOT/stage-embed
    rm -rf $STAGE && mkdir -p $STAGE && ditto $CHROMIUM_ROOT/embed-rel/ArktShell.app $STAGE/ArktShell.app && cd $STAGE
    S=(codesign --force --timestamp=none --sign $ID)
    FULL=restrict,library,kill,runtime; JIT=restrict,kill,runtime
    FW="ArktShell.app/Contents/Frameworks/Arkt Framework.framework"; F="$FW/Versions/Current"
    for l in "$F"/Libraries/*.dylib; do $S "$l"; done
    for t in chrome_crashpad_handler app_mode_loader web_app_shortcut_copier; do $S --options $FULL "$F/Helpers/$t"; done
    for h in "$F"/Helpers/*.app; do case "$h" in
      *Renderer*) $S --options $JIT --entitlements $ENT/helper-renderer-entitlements.plist "$h";;
      *GPU*) $S --options $JIT --entitlements $ENT/helper-gpu-entitlements.plist "$h";;
      *) $S --options $FULL "$h";; esac; done
    $S "$FW"
    $S --options $FULL --entitlements $ENT/app-entitlements.plist ArktShell.app
    codesign --verify --deep --strict --verbose=2 ArktShell.app
    codesign -dv ArktShell.app 2>&1 | grep -E '^(Identifier|CodeDirectory)'  # flags=0x12a00(kill,restrict,library-validation,runtime)

Library validation on the app is why everything inside must carry the same team id: the app `dlopen`s the
framework, and an ad-hoc or foreign-signed part fails to load. Signing the app drops Xcode's `get-task-allow`, so
`sample` and debuggers no longer attach to the browser process.

**Install for testing on the internal disk**, never into `/Applications` over a bundle someone else installed, and
not on the Chromium disk (a launch from a removable volume shows the removable-volume prompt):

    mkdir -p ~/Applications/ArktTest && ditto $STAGE/ArktShell.app ~/Applications/ArktTest/ArktShell.app
    codesign --verify --deep --strict --verbose=2 ~/Applications/ArktTest/ArktShell.app

**Launch** the executable directly, with the launch flags above, a profile under
`~/Library/Application Support/ArktTest`, and the `ARKT_*` overrides so the shell's own data, Arc folder and
defaults stay away from the real ones (the bundle id is the product's, `dev.arkt.Arkt`, unless the build overrides it):

    T=~/Library/Application\ Support/ArktTest/<run>
    ARKT_DATA_DIR=$T/shell ARKT_ARC_DIR=$T/arc ARKT_DEFAULTS_SUITE=arkt-test-<run> \
      ~/Applications/ArktTest/ArktShell.app/Contents/MacOS/ArktShell --user-data-dir=$T/profile \
      --use-mock-keychain --no-first-run --no-default-browser-check --enable-logging=stderr &

Add `--enable-sandbox-logging` to see seatbelt denials in the unified log (Chromium's profiles do not log them
otherwise), and use `/usr/bin/log`, not zsh's `log` builtin:
`/usr/bin/log show --start '<launch time>' --style compact --predicate 'sender == "Sandbox"' | grep -i arkt`.

Ids in this bundle: see "Product identity" below.

## Preview release

How a maintainer cuts a preview build (v0.1.0-preview.1, tracking issue #481). The preview is an unsigned,
ad-hoc signed zip on a GitHub pre-release. There is no DMG, no Developer ID signing, no notarization and no update
feed; those follow in #125. Nothing here is scripted: run the steps in order, in zsh, with the variables from the top
of this file (`$REPO`, `$CHROMIUM_ROOT`, `$CR`, `$PIN`). The release is the maintainer's to publish; do not run steps
5 and 6 without that go-ahead.

    export REL=$CR/out/Arkt
    export VERSION=0.1.0-preview.1
    export OUT=$CHROMIUM_ROOT/preview-$VERSION     # build and staging folder, outside the repo

### 1. Freeze the overlay and build the engine

Check out the commit to release in `$REPO` and leave it there until the build ends: the build compiles whatever
overlay and patches are in `$CR`. Do not edit `engine/` or run Apply, Export or a rebase meanwhile. `$REPO` must be
the worktree that the overlay link points at: `readlink $CR/arkt` prints `$REPO/engine/arkt`, otherwise the build
compiles another checkout's overlay. Run the disk and swap checks of "Release build (out/Arkt)" first (swap was
12.8 of 14.3 GiB used on the dry run before the build started; record it), then the release build, with its PID
recorded so it can be stopped:

    cd $CR && gn gen out/Arkt
    cd $CR && nice -n 15 autoninja -C out/Arkt chrome > $CHROMIUM_ROOT/build-arkt.log 2>&1 &
    echo $! > $CHROMIUM_ROOT/build-arkt.pid

The build is incremental: with an up-to-date `out/Arkt` and one new patch it took 94 s (a clean build takes the hours
listed in "Release build (out/Arkt)"). Wait for it to end before running the checks below.

Check the result:

    tail -3 $CHROMIUM_ROOT/build-arkt.log                       # The build has finished successfully.
    grep -c FAILED: $CHROMIUM_ROOT/build-arkt.log               # 0
    wc -l < $REPO/engine/patches/chromium/.patches              # N
    git -C $CR rev-list --count $PIN..arkt                      # N again: every exported patch is in the build

The two counts must match, and the build must report 0 `FAILED:` lines. If they differ, the checkout is not the
overlay in the repo: run Export (or Apply) and rebuild.

### 2. Build the Distribution app

Generate the Xcode project (it is not committed), then build the `Distribution` configuration against the engine
app, into a folder outside the repo (see "Embedding in the app" for what the configuration contains):

    mkdir -p $OUT
    cd $REPO/app/ArktShell && xcodegen generate
    cd $REPO && xcodebuild -project app/ArktShell/ArktShell.xcodeproj -scheme ArktShell -configuration Distribution \
      ARKT_ENGINE_APP=$REL/Arkt.app CONFIGURATION_BUILD_DIR=$OUT/build build

Expect `BUILD SUCCEEDED` and `Engine framework copied: Arkt Framework.framework <version>` in the log (a
"CoreSimulator is out of date" line from `xcodebuild` is harmless). The product is `$OUT/build/Arkt.app` (executable
`Arkt`, bundle id `dev.arkt.Arkt`). Xcode signs only the app, ad hoc.

On a machine that has a development build, this build registers `$OUT/build/Arkt.app` and its helpers with
LaunchServices under the product bundle id. When you delete `$OUT/build` and `$OUT/stage` (after step 4), unregister
them first, so a stale `dev.arkt.Arkt` entry cannot take over link opens: run
`lsregister -u $OUT/build/Arkt.app` (`lsregister` is
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`) and check
`lsregister -dump | grep -c "path:.*$OUT"` prints `0`, unregistering any remaining helper path the same way.

### 3. Ad-hoc sign a copy

Sign a copy, inside-out, in the order of "Embedding in the app": libraries, tools, helpers, framework, app. The
identity is `-` (ad hoc). Pass no `--options runtime` and no entitlements: an ad-hoc bundle has no team id, so the
hardened runtime's library validation would refuse to load the framework, and the entitlements only mean something
under a real identity.

    rm -rf $OUT/stage && mkdir -p $OUT/stage && ditto $OUT/build/Arkt.app $OUT/stage/Arkt.app && cd $OUT/stage
    S=(codesign --force --timestamp=none --sign -)
    FW="Arkt.app/Contents/Frameworks/Arkt Framework.framework"; F="$FW/Versions/Current"
    for l in "$F"/Libraries/*.dylib; do $S "$l"; done
    for t in chrome_crashpad_handler app_mode_loader web_app_shortcut_copier; do $S "$F/Helpers/$t"; done
    for h in "$F"/Helpers/*.app; do $S "$h"; done
    $S "$FW"
    $S Arkt.app
    codesign --verify --deep --strict --verbose=2 Arkt.app      # valid on disk, satisfies its Designated Requirement
    codesign -dv Arkt.app 2>&1 | grep -E '^(Identifier|Signature|CodeDirectory)'   # dev.arkt.Arkt, Signature=adhoc

List `"$F"/Helpers` first: every executable there must be covered (11 entries on 156). Expect `Signature=adhoc` and
no `runtime` in the flags. `spctl --assess` reports `rejected`; that is expected for this build.

### 4. Package

Zip with `ditto`, which keeps the bundle's symlinks and metadata (`zip` does not), then record the checksum:

    cd $OUT/stage && ditto -c -k --keepParent Arkt.app $OUT/Arkt-$VERSION-arm64.zip
    cd $OUT && shasum -a 256 Arkt-$VERSION-arm64.zip | tee Arkt-$VERSION-arm64.zip.sha256
    ls -l Arkt-$VERSION-arm64.zip                                  # about 196 MB (569 MB unpacked) on 156

### 5. Draft the release and smoke test the asset

Write the notes from `docs/release/0.1.0-preview.1.md` (copy it to a file outside the repo, and put the checksum in
it). Create a draft pre-release; a draft is not visible to the public:

    gh release create v$VERSION --draft --prerelease --target main \
      --title "Arkt $VERSION" --notes-file <notes file> \
      $OUT/Arkt-$VERSION-arm64.zip $OUT/Arkt-$VERSION-arm64.zip.sha256

Smoke test the downloaded asset, not the local build, on a fresh macOS user account (System Settings > Users &
Groups, a standard user with no Arkt data). Download the zip from the draft release in Safari, so the file carries the
quarantine flag a user's download carries. Then, as that user:

    cd ~/Downloads && shasum -a 256 Arkt-$VERSION-arm64.zip        # equals the .sha256 file
    ditto -x -k Arkt-$VERSION-arm64.zip /Applications              # or drag Arkt.app to /Applications

Open it as described in the README ("Download the preview"). What to expect on 156 (dry run, quarantine flag set with
`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;"`): `spctl -a -vv Arkt.app` prints `rejected`,
and launching the executable directly shows the "Arkt Not Opened" dialog ("Apple could not verify ...") with the
buttons Move to Trash and Done. Choose Done, never Move to Trash. The process sits at `_dyld_start` with no window
until the dialog is answered, and the dialog stays on screen after you kill that process, so do not start a second
launch before dismissing it. Do not dry-run this on the maintainer's own login: use the fresh user above. Run the
checklist below. If any item fails, delete the
draft (`gh release delete v$VERSION --yes --cleanup-tag`), fix the cause and start again from step 1 or 2.

### 6. Publish

Only after the whole checklist passes and the maintainer agrees:

    gh release edit v$VERSION --draft=false

Then check the Releases page shows the asset, the checksum and the pre-release label, and download the published
asset once more to confirm the checksum.

### Smoke checklist

Run it on the fresh user, from `/Applications/Arkt.app`, on Apple silicon with macOS 15 or later.

- [ ] Onboarding completes and lands in a window with a sidebar.
- [ ] Browsing works; a YouTube video plays with sound.
- [ ] Google sign-in completes.
- [ ] A Chrome Web Store extension installs and runs.
- [ ] Cmd-T, Cmd-L, Cmd-N and Cmd-F each do their job.
- [ ] Three Spaces exist and a trackpad swipe moves between them.
- [ ] Quit and relaunch restores the Spaces and tabs.
- [ ] Cmd-W closes a tab and reopening it brings it back.
- [ ] Camera, microphone and location each show their permission prompt (try a page that requests them).
- [ ] After Make Default, a link opened from another app opens in Arkt.
- [ ] Peek opens and dismisses.
- [ ] Little Arkt opens and dismisses.
- [ ] Full screen enters and leaves cleanly.
- [ ] The window moves between a 1x and a 2x display without a blurry or blank frame.
- [ ] `chrome://credits` loads.
- [ ] No seatbelt denials for Arkt in the log. Launch once from Terminal with `--enable-sandbox-logging` (see
      "Embedding in the app"):
      `/Applications/Arkt.app/Contents/MacOS/Arkt --enable-sandbox-logging`, run the items above, then
      `/usr/bin/log show --last 30m --style compact --predicate 'sender == "Sandbox"' | grep -i arkt` prints nothing.

## Product identity (#128)

One prefix, `dev.arkt.*` (#73), for everything a user's machine binds to: app `dev.arkt.Arkt` (`PRODUCT_BUNDLE_IDENTIFIER`,
shown as "Arkt"), framework `dev.arkt.Arkt.framework`, helpers `dev.arkt.Arkt.helper` (Helper, GPU, Aperitif, Aperitif
GPU), `dev.arkt.Arkt.helper.renderer` (Renderer, Aperitif Renderer) and
`dev.arkt.Arkt.framework.AlertNotificationService` (Alerts, Aperitif Alerts). The framework and helper ids come from
`MAC_BUNDLE_ID` in `arkt/branding/BRANDING`, which must equal the app id (`ProductIdentityTests` pins it). The Mach
rendezvous service follows the outer app: `<app id>.MachPortRendezvousServer.<browser pid>`.

Data folders, all under `~/Library/Application Support`:

| Folder | Holds | Set by |
|---|---|---|
| `Arkt` | the shell's database, backups, favicons | `DatabaseLocation.productFolderName` |
| `Arkt/Engine` | the product engine's default user-data-dir | `CrProductDirName` in the app's Info.plist |
| `Arkt Dev Engine` | the development engine's default user-data-dir | the same key, from `Engine.xcconfig` |

`CrProductDirName` is written by the embed build phase from the build setting `ARKT_PRODUCT_DIR_NAME`
(`app/ArktShell/Engine.xcconfig`, default `Arkt Dev Engine`, so a development build never shares a profile with the
product). The Distribution configuration (#334) sets the product value, `ARKT_PRODUCT_DIR_NAME=Arkt/Engine`, in
`app/ArktShell/Distribution.xcconfig`.

Distribution is the shipped app: the Engine configuration's engine-backed shell, optimized (`-O`, whole module), named
`Arkt.app`, without the test-only code. It does not link `EngineAPITestSupport` (so the contract runner and its
loopback server are not in the binary), compiles the `ARKT_*` overrides and the `--arkt-engine-contract` switch out
(`ArktEnvironmentOverrides` is `NO`; the stand-in shell and its probes go with them), and writes `CrProductDirName` = `Arkt/Engine`. Build it like the Engine
configuration, against the self-contained engine app:

    cd $REPO/app/ArktShell && xcodebuild -scheme ArktShell -configuration Distribution \
      ARKT_ENGINE_APP=$REL/Arkt.app CONFIGURATION_BUILD_DIR=<output dir> build

The result is `Arkt.app` with the engine framework embedded. Signing and the hardened-runtime check (#125) follow the
steps above and are not part of the configuration yet.

The key is a seam (Chromium's `chrome_paths_mac.mm` reads it from the outer bundle; its fallback is `Chromium`), so there
is no patch. The keychain item stays "Arkt Safe Storage" (patch 0003); the existing "Chromium Safe Storage" item is
the maintainer's and is never touched (#20).
