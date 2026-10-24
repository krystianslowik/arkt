#!/bin/zsh
# Classify every KB / BH / GS row in the Arc parity spec against one xcresult.
# Exits non-zero only when the xcresult, the spec or the deferred file is malformed.
# Failing rows are reported and do not fail the script (the test step already does).
emulate -L zsh
setopt err_exit pipefail nounset extended_glob

jq=/usr/bin/jq

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

[[ -x $jq ]] || die "malformed environment: /usr/bin/jq is missing"
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

typeset -A deferred_seen
: > "$workdir/deferred.tsv"
while IFS=$'\t' read -r id reason issue rest || [[ -n ${id:-} ]]; do
  [[ -z ${id:-} && -z ${reason:-} && -z ${issue:-} && -z ${rest:-} ]] && continue
  if [[ -n ${rest:-} || -z ${reason:-} || -z ${issue:-} ]]; then
    die "malformed deferred file: expected ID, reason and #issue on one line"
  fi
  if [[ ! $id =~ '^(KB|BH|GS)-[0-9]{3}$' ]]; then
    die "malformed deferred file: bad id '$id'"
  fi
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
  print -r -- "${id}"$'\t'"${reason}"$'\t'"${issue}" >> "$workdir/deferred.tsv"
done < "$deferred"

if ! xcrun xcresulttool get test-results tests --path "$xcresult" --compact > "$workdir/tests.json" 2>"$workdir/xcresulttool.err"; then
  die "malformed xcresult: xcresulttool could not read test results"
fi

# Precedence, first match: any Failed -> failing; every naming test Passed -> passing
# (a stale deferred-file row does not hide a real pass or a real failure);
# listed in the deferred file -> deferred; only skipped and/or expected-failure
# tests -> deferred; a mix of passes and skips or expected failures -> deferred
# (not passing, because not every test passed); otherwise not covered.
cat > "$workdir/extract.jq" <<'JQ'
def walk_objects:
  .. | objects;
def number_or_null:
  if type == "number" then . else null end;
def string_or_empty:
  if type == "string" then . else "" end;
if type != "object" or (.testNodes | type? != "array") then
  error("missing testNodes")
else
  .
end
| [
    walk_objects
    | select(.nodeType == "Test Case")
    | . as $case
    | ($case | [walk_objects | select(.nodeType == "Test Case Run")]) as $runs
    # One duration per test case. Prefer the case value so repeated runs are not added.
    # Otherwise keep the longest Test Case Run. A missing number is omitted later.
    | ($case.durationInSeconds | number_or_null) as $case_seconds
    | (
        [ $runs[]
          | select(.durationInSeconds | type == "number")
          | {seconds: .durationInSeconds, label: (.duration | string_or_empty)}
        ]
        | sort_by(.seconds)
        | last
      ) as $run_best
    | (
        if $case_seconds != null then
          {seconds: $case_seconds, label: ($case.duration | string_or_empty)}
        elif $run_best != null then
          $run_best
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
          notes: (
            [ $case | walk_objects
              | select(.nodeType == "Skip Message" or .nodeType == "Expected Failure" or .nodeType == "Failure Message")
              | (.details // empty), (.name // empty)
            ] | map(select(type == "string" and length > 0)) | unique | join(" ")
          )
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
  split("\n") | map(select(length > 0) | split("\t") | {id:.[0], reason:.[1], issue:.[2]})
  | map({key:.id, value:.}) | from_entries
' "$workdir/deferred.tsv" > "$workdir/deferred.json"

cat > "$workdir/report.jq" <<'JQ'
def rowids:
  [ scan("(KB|BH|GS)([0-9]{3})") | "\(.[0])-\(.[1])" ] | unique;

def classify($tests; $in_deferred):
  if ($tests | any(.result == "Failed")) then "failing"
  elif ($tests | length) > 0 and ($tests | all(.result == "Passed")) then "passing"
  elif $in_deferred then "deferred"
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

def issue_from($tests):
  ([ $tests[] | (.notes, .name) | scan("#[0-9]+") ] | .[0]) // "";

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
| (reduce ($obs[] | . as $o | ($o.name | rowids)[] | {id:., test:$o}) as $item
    ({}; .[$item.id] = (.[$item.id] // []) + [$item.test])) as $by_id
| [
    $rows[]
    | . as $row
    | ($by_id[$row.id] // []) as $tests
    | ($deferred[$row.id] != null) as $in_deferred
    | .classification = classify($tests; $in_deferred)
    | .tests = $tests
    | .reason = (
        if .classification != "deferred" then ""
        elif $in_deferred then $deferred[$row.id].reason
        else generated_reason($tests)
        end
      )
    | .issue = (
        if $in_deferred then $deferred[$row.id].issue
        elif .classification == "failing" or .classification == "deferred" then issue_from($tests)
        else ""
        end
      )
  ] as $classified
| if ($classified | length) != $nrow then error("row count mismatch") else . end
| ["passing", "failing", "deferred", "not covered"] as $statuses
| if ([ $statuses[] | count($classified; .) ] | add) != $nrow then error("status count mismatch") else . end
| [
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
          + [ $failing[] | "| \(.id) | \(testlist(.tests)) | \(issue_link(.issue)) |" ]
          + [""]
        end
    )
  + [
      "## Deferred",
      ""
    ]
  + (
      [$classified[] | select(.classification == "deferred")] as $held
      | if ($held | length) == 0 then
          ["None.", ""]
        else
          [
            "| Row | Reason | Issue |",
            "|---|---|---|"
          ]
          + [ $held[] | "| \(.id) | \(.reason) | \(issue_link(.issue)) |" ]
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
  | join("\n")
JQ

if ! "$jq" -r -e -n \
  --slurpfile rowfile "$workdir/rows.json" \
  --slurpfile deferredfile "$workdir/deferred.json" \
  --slurpfile obsfile "$workdir/obs.json" \
  -f "$workdir/report.jq" > "$workdir/report.md"; then
  die "malformed input: could not classify rows"
fi

cat -- "$workdir/report.md"
