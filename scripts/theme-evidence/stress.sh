#!/bin/zsh
set -eu
setopt pipefail
out=$1
mkdir -p "$out"
cd app/ArktShell/ShellKit
pids=()
cleanup() {
  for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  for pid in $pids; do wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM
# Compile first; the recorded runs execute while these tracked workers are active.
swift test --filter ThemeCrossfadeTests 2>&1 | tee "$out/warmup.log"
uptime | tee "$out/load.log"
for i in {1..3}; do yes > /dev/null & pids+=($!); done
print "Load worker PIDs: $pids" | tee -a "$out/load.log"
for i in {1..20}; do
  for pid in $pids; do kill -0 "$pid"; done
  print "Run $i" | tee -a "$out/load.log"
  uptime | tee -a "$out/load.log"
  swift test --skip-build --filter ThemeCrossfadeTests 2>&1 | tee "$out/stress-$i.log"
  grep -q "Suite ThemeCrossfadeTests passed" "$out/stress-$i.log" || {
    print "Crossfade suite did not report a pass in run $i"; exit 1
  }
done
uptime | tee -a "$out/load.log"
print '20 of 20 runs passed under load' | tee -a "$out/load.log"
cleanup
pids=()
uptime | tee -a "$out/load.log"
