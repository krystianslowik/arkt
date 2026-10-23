# Arkt engine

`$CHROMIUM_ROOT` is the directory that holds the Chromium build environment: `depot_tools/` and the checkout in
`chromium/src` (pinned to tag 156.0.8078.48). It needs well over 100 GB free; any local or external disk works.
Every doc in this repo uses these variables:

    export REPO=/path/to/arkt                      # root of this repository
    export CHROMIUM_ROOT=/path/to/arkt-chromium    # depot_tools/ and chromium/src live here
    export CR=$CHROMIUM_ROOT/chromium/src
    export PATH=$CHROMIUM_ROOT/depot_tools:$PATH

- `arkt/` is symlinked into the Chromium checkout as `src/arkt`. Our own sources only.
- `patches/chromium/*.patch` are the only upstream edits, applied in the order listed in `.patches`.
- //arkt is wired into the build by patch 0001: `//chrome/browser:core` (Mac) depends on `//arkt/browser`.

## Link the overlay

Once per checkout (both commands are safe to re-run):

    ln -sfn $REPO/engine/arkt $CR/arkt
    grep -qx /arkt $CR/.git/info/exclude || echo /arkt >> $CR/.git/info/exclude

## Apply

Fresh checkout at the pinned tag; stops at the first patch that fails to apply. It refuses to run if branch `arkt` already exists and its commit count differs from `.patches`, because `checkout -B` would discard commits that were never exported. It compares counts only, so an amended commit that was not exported is not detected; always run Export after editing upstream files.

    n_commits=$(git -C $CR rev-list --count 156.0.8078.48..arkt 2>/dev/null || echo 0)
    n_patches=$(wc -l < $REPO/engine/patches/chromium/.patches | tr -d ' ')
    if git -C $CR rev-parse -q --verify arkt >/dev/null && [ "$n_commits" != "$n_patches" ]; then
      echo "arkt has unexported commits; run Export first"
    else
      git -C $CR checkout -B arkt 156.0.8078.48
      for p in $(cat $REPO/engine/patches/chromium/.patches); do
        git -C $CR am -3 "$REPO/engine/patches/chromium/$p" || { echo "stopped at $p"; break; }
      done
    fi

## Export

After editing upstream files (one commit per patch on branch `arkt`). Patches are written to a temp dir first and replace the old ones only if `format-patch` succeeds and produced at least one patch; otherwise the existing patches are kept:

    tmp=$(mktemp -d)
    if git -C $CR format-patch --no-numbered --zero-commit --no-signature -o $tmp 156.0.8078.48..arkt; then
      if [ -z "$(find $tmp -name '*.patch')" ]; then
        echo "no commits to export"
      else
        find $REPO/engine/patches/chromium -name '*.patch' -delete &&
          find $tmp -name '*.patch' -exec mv {} $REPO/engine/patches/chromium/ \; &&
          (cd $REPO/engine/patches/chromium && find . -name '*.patch' | sed 's|^\./||' | sort > .patches)
      fi
    fi
    rm -rf $tmp
