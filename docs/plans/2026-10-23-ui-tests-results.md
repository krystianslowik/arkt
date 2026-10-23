# UI test track results (XCUITest, track U)

Plan: `docs/plans/2026-10-23-ui-tests.md`. Tracking issue: #161. One section per task; each task appends its own
section and never rewrites another task's numbers.

## U0: Worktree, baselines, results file (#163)

### Environment

| | |
|---|---|
| Date | 2026-10-23 |
| Base | `origin/main` at `772f94c253781182e870b18fac59ce3bc25088eb` (worktree on branch `chore/163-ui-tests-u0`) |
| Machine | Apple silicon MacBook Pro (`Mac14,9`, Apple M2 Pro, 10 cores) |
| macOS | 27.0 (26A428) |
| Toolchain | Xcode 27.1 (27A9275), Swift 6.4, XcodeGen 2.46.0 |
| Main display | built-in Liquid Retina XDR, 1800 x 1169 points (3024 x 1964 pixels), 120.00 Hz |
| Chromium build | not running (no `ninja`, `autoninja` or `siso` process) |
| Other load | Swift work in other worktrees was running; load average 10 to 13 |
| Capacity | `nice -n 10`, `-j 4` / `-jobs 4` (no Chromium build, so the `nice -n 20`, two-job rule did not apply) |

### Baselines

Each Swift package was built first with `swift build --build-tests -j 4`, so the test durations below are the test
run only. Swift Testing prints one total per test product; the counts are the sum. Wall time is the `time` total of
the command.

| Suite | Command | Result | Count | Wall time |
|---|---|---|---|---|
| ArktCore | `cd $CORE && nice -n 10 swift test -j 4` | pass | 336 Swift Testing tests (84 + 97 + 59 + 96) | 5.7 s |
| ShellKit pure | `cd $KIT && nice -n 10 swift test -j 4 --skip ShellKitGUITests` | pass | 392 Swift Testing tests (164 + 33 + 15 + 4 + 22 + 154) | 6.8 s |
| ShellKit GUI | `cd $KIT && nice -n 10 swift test -j 4 --filter ShellKitGUITests` | pass | 240 XCTest tests, 0 failures | 42.9 s (XCTest reports 39.3 s) |
| App build (Debug) | `cd $APP && xcodegen generate && nice -n 10 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Debug -derivedDataPath build -jobs 4 build` | `** BUILD SUCCEEDED **` | 0 compiler warnings | 35.4 s (clean derived data) |
| Import layering | the `Check import layering` step of `.github/workflows/swift-tests.yml`, run locally | pass | `Import layering OK` | under 1 s |

Prebuild times (not part of the baseline): ArktCore `swift build --build-tests` 23.5 s, ShellKit 30.6 s, both from
a fresh worktree.

The only `warning:` line in the app build log is the `appintentsmetadataprocessor` note "Metadata extraction skipped,
no AppIntents.framework dependency found", which is a build tool message, not a compiler warning.

After the runs, `git status` is clean: `ArktShell.xcodeproj`, `build/` and `.build/` are ignored.

### One-time permission steps (plan section "One-time setup on a developer Mac")

Checked read-only; nothing was enabled or changed in U0.

| Step | State on this Mac | How checked |
|---|---|---|
| 1. Developer mode for the tools | **Not in place.** The account is in the `_developer` group, but `DevToolsSecurity -status` prints "Developer mode is currently disabled." | `DevToolsSecurity -status`, `id -Gn` |
| 2. Automation mode without authentication | **Not in place.** `automationmodetool` prints "Automation Mode is disabled." and "This device requires user authentication to enable Automation Mode." | `automationmodetool` (status only) |
| 3. Accessibility / Automation grant for the test runner | Unknown. No XCUITest has run yet; U2's first `xcodebuild test` shows whether macOS asks. | - |
| 4. Ad hoc signing | In place: the Debug app builds with the `project.yml` identity `-`; no Apple Development identity used. | app build above |

Steps 1 and 2 need an admin password and are maintainer steps before U2 can run the UI tests on this Mac:

```zsh
DevToolsSecurity -enable
automationmodetool enable-automationmode-without-authentication
```

### What remains

- U1 to U16 compare against the counts above ("baseline + N").
- The one-time permission steps 1 and 2 above, before the first local UI test run (U2).
