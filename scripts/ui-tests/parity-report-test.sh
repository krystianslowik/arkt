#!/bin/zsh
# Tests for parity-report.sh against the synthetic fixtures in parity-report-fixtures/.
# xcrun is replaced by a stub on PATH that prints <bundle>/tests.json, or prints <bundle>/xcresulttool.err to stderr
# and fails, so the tests run without Xcode. Usage: scripts/ui-tests/parity-report-test.sh
emulate -L zsh
setopt err_exit pipefail nounset

here=${0:A:h}
script=$here/parity-report.sh
fixtures=$here/parity-report-fixtures
spec=$fixtures/spec.md
deferred=$fixtures/deferred.txt

work=$(mktemp -d "${TMPDIR:-/tmp}/parity-report-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/xcrun" <<'STUB'
#!/bin/zsh
bundle=""
while (( $# )); do
  if [[ $1 == --path ]]; then
    bundle=$2
    shift
  fi
  shift
done
if [[ -f $bundle/xcresulttool.err ]]; then
  cat -- "$bundle/xcresulttool.err" >&2
  exit 1
fi
cat -- "$bundle/tests.json"
STUB
chmod +x "$work/bin/xcrun"

failures=0
fail() {
  print -u2 -- "FAIL: $*"
  failures=$(( failures + 1 ))
}

# run <name> <PATH> <xcresult> [deferred]: sets $out, $err and $code.
run() {
  local name=$1 path=$2 bundle=$3 deferred_file=${4:-$deferred}
  code=0
  PATH=$path "$script" "$bundle" "$spec" "$deferred_file" > "$work/$name.out" 2> "$work/$name.err" || code=$?
  out=$(<"$work/$name.out")
  err=$(<"$work/$name.err")
}

has_line() {
  local text=$1 line=$2 what=$3
  if ! grep -qxF -- "$line" <<< "$text"; then
    fail "$what: missing line: $line"
  fi
}

lacks() {
  local text=$1 needle=$2 what=$3
  if grep -qF -- "$needle" <<< "$text"; then
    fail "$what: unexpected text: $needle"
  fi
}

# Section of the report between "## <title>" and the next "## " heading.
section() {
  print -r -- "$1" | awk -v want="## $2" '$0 == want { on = 1; next } /^## / { on = 0 } on'
}

std_path=$work/bin:$PATH

# 1. Main fixture: classification, partial deferral, issue source, repetitions.
run main "$std_path" "$fixtures/main.xcresult"
(( code == 0 )) || fail "main: exit $code, stderr: $err"
has_line "$out" '| 1.1 Tabs | 1 | 1 | 2 | 0 | 4 |' "main counts 1.1"
has_line "$out" '| 2.1 Archive | 2 | 1 | 2 | 0 | 5 |' "main counts 2.1"
has_line "$out" '| 3. Gestures | 1 | 0 | 1 | 0 | 2 |' "main counts 3"
has_line "$out" '| Total | 4 | 2 | 5 | 0 | 11 |' "main total"
has_line "$out" 'Rows with a deferred part, counted above by their own result: 2 (BH-001, BH-002).' "main partial line"

failing=$(section "$out" Failing)
# A failure message's #N is not a known issue: KB-002 links nothing, BH-004 links nothing.
has_line "$failing" '| KB-002 | `test_KB002_fails()` Failed |  |' "failing KB-002 issue"
has_line "$failing" '| BH-004 | `test_BH004_repeated()` Passed, `test_BH004_repeated()` Failed |  |' "failing BH-004 repetitions"
lacks "$failing" '#99' "failing issue from failure text"
lacks "$failing" '#1234' "failing issue from repetition failure text"

held=$(section "$out" Deferred)
link() { print -r -- "[#$1](https://github.com/krystianslowik/arkt/issues/$1)"; }
has_line "$held" "| KB-003 | whole | deferred | expected failure | $(link 269) |" "deferred KB-003 expected-failure reason"
lacks "$held" '#777' "deferred issue from assertion text"
has_line "$held" "| KB-004 | whole | deferred | only skipped tests | $(link 42) |" "deferred KB-004 flaky skip"
# Partial deferral: BH-001 passes and its search part stays listed with its issue.
has_line "$held" "| BH-001 | search | passing | Search UI is not implemented | $(link 111) |" "deferred BH-001 part"
has_line "$held" "| BH-002 | search | deferred | Search UI is not implemented | $(link 112) |" "deferred BH-002 part"
has_line "$held" "| BH-003 | whole | deferred | Clearing is not implemented | $(link 85) |" "deferred BH-003 whole"
has_line "$held" "| GS-002 | whole | deferred | only skipped tests | $(link 26) |" "deferred GS-002 skip reason"

slow=$(section "$out" 'Slowest five')
# One repetition's time, not the case's sum of repetitions.
has_line "$slow" '`test_BH005_repeatedOnDevice()` 13s (13.5s)' "slowest BH-005 longest repetition"
has_line "$slow" '`test_BH004_repeated()` 20s (20.5s)' "slowest BH-004 longest repetition"
lacks "$slow" '(30' "slowest uses the BH-004 case sum"
lacks "$slow" '(24' "slowest uses the BH-005 case sum"

lacks "$out" '## Unknown row ids' "main unknown ids section"
[[ -z $err ]] || fail "main: unexpected stderr: $err"

# 2. Test names that cite ids missing from the spec: report printed, ids listed there and on stderr, exit non-zero.
run unknown "$std_path" "$fixtures/unknown-id.xcresult"
(( code != 0 )) || fail "unknown: exit 0"
has_line "$out" '| Total | 2 | 0 | 1 | 8 | 11 |' "unknown total (KB-001 and BH-001 pass)"
unknown=$(section "$out" 'Unknown row ids')
has_line "$unknown" '| GS-777 | `test_GS777_typo()` |' "unknown GS-777 listed"
has_line "$unknown" '| KB-850 | `test_KB850_BH001_typo()` |' "unknown KB-850 listed"
grep -qF -- 'KB-850' <<< "$err" || fail "unknown: KB-850 not on stderr: $err"
grep -qF -- 'GS-777' <<< "$err" || fail "unknown: GS-777 not on stderr: $err"

# 3. xcresulttool's own error reaches stderr.
run xcerr "$std_path" "$fixtures/xcresulttool-error.xcresult"
(( code != 0 )) || fail "xcresulttool error: exit 0"
grep -qF -- 'synthetic xcresulttool failure: unsupported bundle version' <<< "$err" \
  || fail "xcresulttool error: message not printed: $err"

# 4. jq comes from PATH; without it the script names the missing tool.
mkdir -p "$work/nojq"
for tool in cat cmp cut grep mktemp rm sed sort uniq; do
  ln -s -- "${commands[$tool]}" "$work/nojq/$tool"
done
run nojq "$work/bin:$work/nojq" "$fixtures/main.xcresult"
(( code != 0 )) || fail "no jq: exit 0"
grep -qF -- 'jq is not on PATH' <<< "$err" || fail "no jq: unexpected stderr: $err"

# 5. Deferred file: one line per row, whole or one part, and a part needs a name.
print -r -- $'BH-001 (search)\tSearch UI is not implemented\t#111\nBH-001\tWhole row\t#85' > "$work/dup.txt"
run dup "$std_path" "$fixtures/main.xcresult" "$work/dup.txt"
(( code != 0 )) || fail "deferred whole and part of one row: exit 0"
grep -qF -- 'duplicate id BH-001' <<< "$err" || fail "deferred duplicate: unexpected stderr: $err"
print -r -- $'BH-001 ()\tNo part name\t#111' > "$work/nopart.txt"
run nopart "$std_path" "$fixtures/main.xcresult" "$work/nopart.txt"
(( code != 0 )) || fail "deferred empty part: exit 0"
grep -qF -- "bad id 'BH-001 ()'" <<< "$err" || fail "deferred empty part: unexpected stderr: $err"

if (( failures > 0 )); then
  print -u2 -- "parity-report-test: $failures failure(s)"
  exit 1
fi
print -- "parity-report-test: all checks passed"
