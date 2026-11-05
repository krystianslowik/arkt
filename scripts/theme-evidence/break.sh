#!/bin/zsh
set -eu
setopt pipefail
out=$1
mkdir -p "$out"
cd app/ArktShell/ShellKit
source=Sources/ShellUI/Theme/ThemeBackgroundView.swift
backup=$(mktemp)
cp "$source" "$backup"
restore() { cp "$backup" "$source"; rm -f "$backup"; }
trap restore EXIT INT TERM
python3 - "$source" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = 'guard let self, self.crossfadeToken == token, self.crossfadeActive else { return }'
assert text.count(old) == 1
path.write_text(text.replace(old, 'guard let self else { return }'))
PY
set +e
swift test --filter 'ThemeCrossfadeTests/staleCompletionsCannotSettleNewerOrInterruptedCrossfades' > "$out/broken.log" 2>&1
test_status=$?
set -e
cat "$out/broken.log"
[[ $test_status -ne 0 ]] || { print 'Broken test unexpectedly passed'; exit 1; }
grep -q 'Expectation failed.*crossfadeAnimationForTesting' "$out/broken.log" || {
  print 'Expected stale animation assertion not found'; exit 1
}
restore
trap - EXIT INT TERM
swift test --filter 'ThemeCrossfadeTests/staleCompletionsCannotSettleNewerOrInterruptedCrossfades' 2>&1 | tee "$out/restored.log"
grep -q 'staleCompletionsCannotSettleNewerOrInterruptedCrossfades.*passed' "$out/restored.log" || {
  print 'Restored test did not report a pass'; exit 1
}
