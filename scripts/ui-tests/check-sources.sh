#!/bin/zsh
# Source checks for the UI test suite (docs/plans/2026-10-23-ui-tests.md, Rules "No sleeps" and "No network").
# Fails when a file under app/ArktShell/UITests waits on time, or names an http(s) URL other than the loopback
# fixture server (http://127.0.0.1) and the Arc fixture placeholder (https://example.com, only in
# Harness/ArcFixture.swift, which rewrites it to the loopback server).
# Usage: scripts/ui-tests/check-sources.sh
emulate -L zsh

cd ${0:A:h:h:h}/app/ArktShell/UITests || exit 2
failed=0

sleeps=$(grep -rnE 'sleep\(|usleep\(|Thread\.sleep|Task\.sleep' .)
if [[ -n $sleeps ]]; then
  print -r -- "Sleeps in UI tests (wait on accessibility state instead):"
  print -r -- $sleeps
  failed=1
fi

urls=$(grep -rnoE 'https?://[^[:space:]"'\''<>()\\`]*' . \
  | grep -vE '^[^:]+:[0-9]+:http://127\.0\.0\.1([:/]|$)' \
  | grep -vE '^\./Harness/ArcFixture\.swift:[0-9]+:https://example\.com([:/]|$)')
if [[ -n $urls ]]; then
  print -r -- "URLs other than http://127.0.0.1 in UI tests (the network is never touched):"
  print -r -- $urls
  failed=1
fi

(( failed )) && exit 1
print "UI test sources OK"
