#!/bin/zsh
# Classify every KB / BH / GS row in the Arc parity spec against one xcresult.
# Exits non-zero only on malformed input: the xcresult, the spec or the deferred file, or a test name that cites a
# row id the spec does not have (a test-naming bug; the report is still printed, with those ids listed).
# Failing rows are reported and do not fail the script (the test step already does).
emulate -L zsh
setopt err_exit pipefail nounset extended_glob

die() {
  print -u2 -- "parity-report: $*"
  exit 1
}

if (( $# != 3 )); then
  die "usage: parity-report.sh <xcresult> <spec> <deferred>"
fi

xcresult=$1
spec=$2
deferred=$3

jq=${commands[jq]:-}
[[ -n $jq ]] || die "jq is not on PATH; install jq (macOS 15 and later ship /usr/bin/jq) or add it to PATH"
[[ -d $xcresult ]] || die "malformed xcresult: not a directory: $xcresult"
[[ -f $spec ]] || die "malformed spec: not a file: $spec"
[[ -f $deferred ]] || die "malformed deferred file: not a file: $deferred"

workdir=$(mktemp -d "${TMPDIR:-/tmp}/parity-report.XXXXXX")
trap 'rm -rf "$workdir"' EXIT

# Row set is exactly the plan's grep. Section comes from the ### 1.x / ### 2.x / ## 3 heading above the row.
grep -oE '^\| (KB|BH|GS)-[0-9]{3} ' -- "$spec" | sed 's/^| //;s/ $//' > "$workdir/grep-ids.txt" || true
if [[ ! -s $workdir/grep-ids.txt ]]; then
  die "malformed spec: no KB/BH/GS rows"
fi
dups=$(sort -- "$workdir/grep-ids.txt" | uniq -d)
if [[ -n $dups ]]; then
  die "malformed spec: duplicate row id"
fi

typeset -A spec_seen
section=""
section_title=""
: > "$workdir/rows.tsv"
while IFS= read -r line || [[ -n ${line:-} ]]; do
  if [[ $line == '## '* ]]; then
    if [[ $line =~ '^## 3\. ' ]]; then
      section="3"
      section_title=${line#\#\# }
    else
      section=""
      section_title=""
    fi
    continue
  fi
  if [[ $line =~ '^### ((1|2)\.[0-9]+) ' ]]; then
    section=$match[1]
    section_title=${line#\#\#\# }
    continue
  fi
  if [[ ! $line =~ '^\| ((KB|BH|GS)-[0-9]{3}) ' ]]; then
    continue
  fi
  id=$match[1]
  if [[ -z $section || -z $section_title ]]; then
    die "malformed spec: $id is outside sections 1.x, 2.x and 3"
  fi
  inner=${${line%%[[:space:]]#}#|}
  inner=${inner%|}
  parts=("${(@s:|:)inner}")
  row_status=${parts[-1]}
  row_status=${${row_status##[[:space:]]##}%%[[:space:]]##}
  case $row_status in
    CONFIRMED|SINGLE-SOURCE|NEEDS-RUNTIME-CHECK) ;;
    *) die "malformed spec: $id has status '$row_status'" ;;
  esac
  title=${section_title##[[:space:]]##}
  title=${title%%[[:space:]]##}
  title=${title//$'\t'/ }
  if [[ $title == *'|'* ]]; then
    die "malformed spec: section title for $id contains a pipe"
  fi
  print -r -- "${id}"$'\t'"${section}"$'\t'"${title}"$'\t'"${row_status}" >> "$workdir/rows.tsv"
  spec_seen[$id]=1
done < "$spec"

cut -f1 -- "$workdir/rows.tsv" > "$workdir/parsed-ids.txt"
if ! cmp -s -- "$workdir/grep-ids.txt" "$workdir/parsed-ids.txt"; then
  die "malformed spec: parsed rows do not match the row grep"
fi

# One line per row: `ID<TAB>reason<TAB>#issue` defers the whole row; `ID (part)<TAB>reason<TAB>#issue` defers only
# that part of it (plan U9: "BH-087 (search)"). A row with a deferred part is still classified by its tests, and the
# part stays in the deferred list whatever the result, so a passing test for the rest of the row cannot hide it.
typeset -A deferred_seen
: > "$workdir/deferred.tsv"
while IFS=$'\t' read -r field reason issue rest || [[ -n ${field:-} ]]; do
  [[ -z ${field:-} && -z ${reason:-} && -z ${issue:-} && -z ${rest:-} ]] && continue
  if [[ -n ${rest:-} || -z ${reason:-} || -z ${issue:-} ]]; then
    die "malformed deferred file: expected ID, reason and #issue on one line"
  fi
  if [[ ! $field =~ '^((KB|BH|GS)-[0-9]{3})( \(([a-z0-9][a-z0-9 -]*[a-z0-9]|[a-z0-9])\))?$' ]]; then
    die "malformed deferred file: bad id '$field'"
  fi
  id=$match[1]
  part=${match[4]:-}
  if [[ ! $issue =~ '^#[0-9]+$' ]]; then
    die "malformed deferred file: $id has issue '$issue'"
  fi
  if [[ $reason == *'|'* ]]; then
    die "malformed deferred file: $id reason contains a pipe"
  fi
  if [[ -n ${deferred_seen[$id]:-} ]]; then
    die "malformed deferred file: duplicate id $id"
  fi
  if [[ -z ${spec_seen[$id]:-} ]]; then
    die "malformed deferred file: $id is not a spec row"
  fi
  deferred_seen[$id]=1
  print -r -- "${id}"$'\t'"${part}"$'\t'"${reason}"$'\t'"${issue}" >> "$workdir/deferred.tsv"
done < "$deferred"

if ! xcrun xcresulttool get test-results tests --path "$xcresult" --compact > "$workdir/tests.json" 2>"$workdir/xcresulttool.err"; then
  print -u2 -- "parity-report: xcresulttool stderr:"
  cat -- "$workdir/xcresulttool.err" >&2
  die "malformed xcresult: xcresulttool could not read test results"
fi

# Precedence, first match: any Failed -> failing; every naming test Passed -> passing
# (a stale whole-row deferred line does not hide a real pass or a real failure);
# whole row listed in the deferred file -> deferred; only skipped and/or expected-failure
# tests -> deferred; a mix of passes and skips or expected failures -> deferred
# (not passing, because not every test passed); otherwise not covered.
# A deferred part does not change the row's class; the part is listed under Deferred in every case.
#
# Observations: xcresulttool nests the runs of one Test Case as "Test Case Run" nodes (one per destination or test
# plan configuration) and "Repetition" nodes (-test-iterations, -run-tests-until-failure, -retry-tests-on-failure),
# possibly one inside the other. Every leaf run (a run node with no run node below it) is one observation with its own
# result, so one failed repetition fails the row. A case without run nodes is one observation.
cat > "$workdir/extract.jq" <<'JQ'
def walk_objects:
  .. | objects;
def number_or_null:
  if type == "number" then . else null end;
def string_or_empty:
  if type == "string" then . else "" end;
def is_run:
  .nodeType == "Test Case Run" or .nodeType == "Repetition";
def has_run_below:
  [ .children[]? | walk_objects | select(is_run) ] | length > 0;
# Skip and expected-failure reasons only. xcresulttool (Xcode 26.6, CI) gives an "Expected Failure" test one
# "Failure Message" node per matched XCTExpectFailure, named by its reason ("... (#269)"); a skip reason is taken the
# same way. The failure text of a failed test is never a reason.
def reasons_in($result):
  [ walk_objects
    | select(($result == "Skipped" or $result == "Expected Failure") and .nodeType == "Failure Message")
    | (.name // empty), (.details // empty)
  ];
if type != "object" or (.testNodes | type? != "array") then
  error("missing testNodes")
else
  .
end
| [
    walk_objects
    | select(.nodeType == "Test Case")
    | . as $case
    | [ $case | .children[]? | walk_objects | select(is_run and (has_run_below | not)) ] as $runs
    # One duration per test case: the longest single leaf run, so repetitions are never added up.
    # Without timed runs, the case value. A missing number is omitted later.
    | (
        [ $runs[]
          | select(.durationInSeconds | type == "number")
          | {seconds: .durationInSeconds, label: (.duration | string_or_empty)}
        ]
        | sort_by(.seconds)
        | last
      ) as $run_best
    | ($case.durationInSeconds | number_or_null) as $case_seconds
    | (
        if $run_best != null then
          $run_best
        elif $case_seconds != null then
          {seconds: $case_seconds, label: ($case.duration | string_or_empty)}
        else
          {seconds: null, label: ""}
        end
      ) as $timing
    | (if ($runs | length) > 0 then $runs[] else $case end) as $obs
    | ($obs.result // $case.result) as $result
    | if $result == null then
        error("test case missing result: \($case.name)")
      else
        {
          name: $case.name,
          result: $result,
          seconds: $timing.seconds,
          duration: $timing.label,
          reasons: (
            ( ($obs | reasons_in($result))
              + (if ($runs | length) > 0 then [ $case | .children[]? | select(is_run | not) | reasons_in($result)[] ] else [] end)
            )
            | map(select(type == "string" and length > 0)) | unique
          ),
          # Every node below the observation, for the stderr note on a skip or expected failure with no issue.
          nodes: [ $obs | .children[]? | walk_objects | select(.nodeType | type == "string")
                   | "\(.nodeType): \((.name // "") | tostring | .[0:200])" ]
        }
      end
  ]
| if length == 0 then error("no test cases") else . end
JQ

if ! "$jq" -e -f "$workdir/extract.jq" "$workdir/tests.json" > "$workdir/obs.json"; then
  die "malformed xcresult: test results JSON has no usable test cases"
fi

"$jq" -R -s -c '
  split("\n") | map(select(length > 0) | split("\t") | {id:.[0], section:.[1], sectionTitle:.[2], status:.[3]})
' "$workdir/rows.tsv" > "$workdir/rows.json"

"$jq" -R -s -c '
  split("\n") | map(select(length > 0) | split("\t") | {id:.[0], part:.[1], reason:.[2], issue:.[3]})
  | map({key:.id, value:.}) | from_entries
' "$workdir/deferred.tsv" > "$workdir/deferred.json"

cat > "$workdir/report.jq" <<'JQ'
def rowids:
  [ scan("(KB|BH|GS)([0-9]{3})") | "\(.[0])-\(.[1])" ] | unique;

def classify($tests; $whole_deferred):
  if ($tests | any(.result == "Failed")) then "failing"
  elif ($tests | length) > 0 and ($tests | all(.result == "Passed")) then "passing"
  elif $whole_deferred then "deferred"
  elif ($tests | length) > 0 then "deferred"
  else "not covered"
  end;

def generated_reason($tests):
  if ($tests | all(.result == "Skipped")) then "only skipped tests"
  elif ($tests | all(.result == "Expected Failure")) then "expected failure"
  elif ($tests | all(.result == "Skipped" or .result == "Expected Failure")) then "skipped or expected failure"
  else "not every naming test passed"
  end;

def issue_link($issue):
  if $issue == null or $issue == "" then ""
  else
    ($issue | ltrimstr("#")) as $n
    | "[\($issue)](https://github.com/krystianslowik/arkt/issues/\($n))"
  end;

# The issue of one skip or expected-failure reason: its leading "#N:" (`XCTSkip("#111: ...")`,
# `XCTExpectFailure("#106: ...")`) or its final "#N" / "(#N)" (`XCTSkip("flaky: #42")`, "... manual check in #26",
# the harness's "... (#269)"). An issue in the middle of the text is not one. If the text carries XCTest's console
# framing ("<file>.swift:<line>: ", "Test skipped - ", or assertion text before "Reason: "), only the reason is read.
def issue_of_reason:
  split("Reason: ") | last
  | split("Test skipped - ") | last
  | sub("^[^ :]+\\.swift:[0-9]+: "; "")
  | sub("^\\s+"; "") | sub("\\s+$"; "")
  | (if startswith("(") and endswith(")") then .[1:-1] else . end)
  | ((capture("^#(?<n>[0-9]+):") // capture("#(?<n>[0-9]+)\\)?$")) // null)
  | if . == null then empty else "#\(.n)" end;

def issue_from($tests):
  ([ $tests[] | .reasons[] | issue_of_reason ] | .[0]) // "";

def testlist($tests):
  [ $tests | sort_by(.name)[] | "`\(.name)` \(.result)" ] | join(", ");

def slow_line:
  if (.duration | type) == "string" and .duration != "" then
    "`\(.name)` \(.duration) (\(.seconds)s)"
  else
    "`\(.name)` \(.seconds)s"
  end;

def count($rows; $status):
  [$rows[] | select(.classification == $status)] | length;

$rowfile[0] as $rows
| $deferredfile[0] as $deferred
| $obsfile[0] as $obs
| ($rows | length) as $nrow
| ($obs | map(.result) | unique) as $results
| ($results - ["Passed", "Failed", "Skipped", "Expected Failure"]) as $bad
| if ($bad | length) > 0 then error("unexpected test result") else . end
| ($rows | map({key: .id, value: true}) | from_entries) as $spec_ids
| (reduce ($obs[] | . as $o | ($o.name | rowids)[] | {id:., test:$o}) as $item
    ({}; .[$item.id] = (.[$item.id] // []) + [$item.test])) as $by_id
| [ $by_id | to_entries[] | select($spec_ids[.key] | not)
    | {id: .key, tests: ([.value[].name] | unique)}
  ] as $unknown
| [
    $rows[]
    | . as $row
    | ($by_id[$row.id] // []) as $tests
    | ($deferred[$row.id] // null) as $d
    | ($d != null and $d.part == "") as $whole
    | ($d != null and $d.part != "") as $partial
    | .classification = classify($tests; $whole)
    | .tests = $tests
    | .part = (if $partial then $d.part else "" end)
    | .reason = (
        if $d != null then $d.reason
        elif .classification == "deferred" then generated_reason($tests)
        else ""
        end
      )
    | .failingIssue = (if $whole then $d.issue else issue_from($tests) end)
    | .deferredIssue = (if $d != null then $d.issue else issue_from($tests) end)
  ] as $classified
| if ($classified | length) != $nrow then error("row count mismatch") else . end
| ["passing", "failing", "deferred", "not covered"] as $statuses
| if ([ $statuses[] | count($classified; .) ] | add) != $nrow then error("status count mismatch") else . end
| [$classified[] | select(.part != "") | .id] as $partial_ids
| {
  unknown: $unknown,
  unlinked: [ $obs[] | select(.result == "Skipped" or .result == "Expected Failure")
              | select([.reasons[] | issue_of_reason] | length == 0)
              | {name, result, nodes} ],
  report: ([
    "# Parity report",
    "",
    "| Section | Passing | Failing | Deferred | Not covered | Total |",
    "|---|---:|---:|---:|---:|---:|"
  ]
  + (
    (
      reduce $classified[] as $row
        ([]; if index($row.section) then . else . + [$row.section] end)
    ) as $order
    | [
        $order[] as $sec
        | [$classified[] | select(.section == $sec)] as $srows
        | ($srows[0].sectionTitle) as $title
        | "| \($title) | \(count($srows; "passing")) | \(count($srows; "failing")) | \(count($srows; "deferred")) | \(count($srows; "not covered")) | \($srows | length) |"
      ]
  )
  + [
      "| Total | \(count($classified; "passing")) | \(count($classified; "failing")) | \(count($classified; "deferred")) | \(count($classified; "not covered")) | \($nrow) |",
      "",
      "Rows with a deferred part, counted above by their own result: \($partial_ids | length)"
        + (if ($partial_ids | length) > 0 then " (\($partial_ids | join(", ")))" else "" end) + ".",
      ""
    ]
  + (
      if ($unknown | length) == 0 then
        []
      else
        [
          "## Unknown row ids",
          "",
          "Test names cite these ids, which are not rows of the spec. Fix the test names.",
          "",
          "| Id | Tests |",
          "|---|---|"
        ]
        + [ $unknown[] | "| \(.id) | \([.tests[] | "`\(.)`"] | join(", ")) |" ]
        + [""]
      end
    )
  + [
      "## Slowest five",
      ""
    ]
  + (
      (
        [ $obs
          | group_by(.name)[]
          | (map(select(.seconds | type == "number")) | max_by(.seconds)) as $best
          | select($best != null)
          | $best
        ]
        | sort_by(-.seconds)
        | .[0:5]
      ) as $slow
      | if ($slow | length) == 0 then
          ["None.", ""]
        else
          [ $slow[] | slow_line ] + [""]
        end
    )
  + [
      "## Failing",
      ""
    ]
  + (
      [$classified[] | select(.classification == "failing")] as $failing
      | if ($failing | length) == 0 then
          ["None.", ""]
        else
          [
            "| Row | Tests | Issue |",
            "|---|---|---|"
          ]
          + [ $failing[] | "| \(.id) | \(testlist(.tests)) | \(issue_link(.failingIssue)) |" ]
          + [""]
        end
    )
  + [
      "## Deferred",
      ""
    ]
  + (
      [$classified[] | select(.classification == "deferred" or .part != "")] as $held
      | if ($held | length) == 0 then
          ["None.", ""]
        else
          [
            "| Row | Part | Row result | Reason | Issue |",
            "|---|---|---|---|---|"
          ]
          + [ $held[]
              | "| \(.id) | \(if .part == "" then "whole" else .part end) | \(.classification) | \(.reason) | \(issue_link(.deferredIssue)) |"
            ]
          + [""]
        end
    )
  + [
      "## Passing [I]",
      "",
      "NEEDS-RUNTIME-CHECK rows whose tests passed:",
      ""
    ]
  + (
      [$classified[] | select(.classification == "passing" and .status == "NEEDS-RUNTIME-CHECK")] as $inferred
      | if ($inferred | length) == 0 then
          ["None."]
        else
          [
            "| Row | Section | Tests |",
            "|---|---|---|"
          ]
          + [ $inferred[] | "| \(.id) | \(.sectionTitle) | \(testlist(.tests)) |" ]
        end
    )
  | join("\n"))
}
JQ

if ! "$jq" -e -n \
  --slurpfile rowfile "$workdir/rows.json" \
  --slurpfile deferredfile "$workdir/deferred.json" \
  --slurpfile obsfile "$workdir/obs.json" \
  -f "$workdir/report.jq" > "$workdir/result.json"; then
  die "malformed input: could not classify rows"
fi

"$jq" -r '.report' "$workdir/result.json"
# Not an error: a skip or expected failure whose reason names no issue gets no link. The note shows its nodes.
"$jq" -r '.unlinked[] | "parity-report: note: \(.name) (\(.result)) names no #issue in a skip or expected-failure reason; nodes: \(.nodes | join(" | "))"' \
  "$workdir/result.json" >&2
"$jq" -r '.unknown[] | "\(.id)\t\(.tests | join(", "))"' "$workdir/result.json" > "$workdir/unknown.tsv"
if [[ -s $workdir/unknown.tsv ]]; then
  while IFS=$'\t' read -r id tests; do
    print -u2 -- "parity-report: $id is not a spec row, named by: $tests"
  done < "$workdir/unknown.tsv"
  die "malformed test names: row ids above are not in the spec (listed under Unknown row ids in the report)"
fi
