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

## U1: Debug-only test hooks in the app target (#164)

Base: `origin/main` at `b4b6dc9`, rebased before review onto `4ec4189` (#185), branch `chore/164-ui-tests-u1`. Same machine and capacity as U0 (`nice -n 10`,
`-j 4` / `-jobs 4`, no Chromium build running).

### What was done

- `App/EnvironmentOverrides.swift` (new, Foundation only, whole file under `#if DEBUG || ARKT_SMOKE_BUILD`): parses
  `ARKT_DEFAULTS_SUITE`, `ARKT_AUTOSAVE_DELAY_MS` (integer, 0 to 600000, anything else keeps the default) and, under
  `#if DEBUG`, `ARKT_UITEST=1` and the list of missing strict-mode overrides (`ARKT_DATA_DIR`, `ARKT_ARC_DIR`,
  `ARKT_DEFAULTS_SUITE`, in that order). An empty value counts as missing; a suite named after the app's own domain
  or `NSGlobalDomain` counts as missing, since it would write the real defaults.
- `AppEnvironment.userDefaults` (the suite in Debug and Profile when set, else `.standard`; Release is always
  `.standard`), `AppEnvironment.autosaveDelay` (else `SidebarAutosaver.defaultDelay`), and, Debug only,
  `isUITest` and `missingUITestOverrides()`. A suite name that is set but unusable stops the app
  (`preconditionFailure`) instead of falling back to the real defaults; strict mode reports it earlier as missing.
- `AppSession`: `ToolbarSetting(defaults: AppEnvironment.userDefaults)` and
  `SidebarAutosaver(store:delay: AppEnvironment.autosaveDelay)`.
- `AppDelegate.applicationDidFinishLaunching`: the strict-mode check is the first statement (before the main menu,
  activation, the scripted smoke and `launch()`). It logs `uitest missing overrides <key names>` and exits with 64.
- `project.yml` (own commit): build setting `ARKT_ENV_OVERRIDES` (`NO` in the base settings, `YES` in Debug and
  Profile) and the Info.plist key `ArktEnvironmentOverrides: $(ARKT_ENV_OVERRIDES)`.
- Tests: `ShellKit/Tests/ShellUITests/EnvironmentOverridesTests.swift` (10 Swift Testing tests) compiles the app file
  through the symlink `ShellUITests/EnvironmentOverrides.swift -> ../../../App/EnvironmentOverrides.swift` (the
  pattern `ShellKitGUITests/MainMenu.swift` already uses). Written first; the first build failed with "cannot find type
  'EnvironmentOverrides' in scope", then passed.

### Verification

| Check | Command | Result |
|---|---|---|
| ArktCore | `cd $CORE && nice -n 10 swift test -j 4` | pass, 336 tests (baseline + 0) |
| ShellKit pure | `cd $KIT && nice -n 10 swift test -j 4 --skip ShellKitGUITests` | pass, 402 tests (baseline 392 + 10); after the rebase onto #185, 414 (392 + 12 from #185 + 10) |
| App build (Debug) | App command, `-jobs 4` | `** BUILD SUCCEEDED **`, 0 compiler warnings, 33 s; again after the rebase |
| App build (Release) | same with `-configuration Release` | `** BUILD SUCCEEDED **`, 0 compiler warnings, 61 s |
| App build (Profile) | same with `-configuration Profile` (outer `#if` true, inner `#if DEBUG` false) | `** BUILD SUCCEEDED **`, 0 compiler warnings, 49 s |
| Import layering | the workflow's `Check import layering` step, run locally | `Import layering OK` |
| `ArktEnvironmentOverrides` | `plutil -extract ArktEnvironmentOverrides raw .../Contents/Info.plist` | Debug `YES`, Profile `YES`, Release `NO` |
| Build setting, all configs | `xcodebuild -showBuildSettings -configuration <C> \| grep ARKT_ENV_OVERRIDES` | Debug `YES`, Profile `YES`, Release `NO`, Spike `NO` |
| Release has no hooks | `strings -a` on the Release executable, grep for `ARKT_DEFAULTS_SUITE`, `ARKT_UITEST`, `ARKT_AUTOSAVE_DELAY_MS`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR`, `ARKT_SMOKE`, `uitest missing overrides`, `EnvironmentOverrides` | 0 hits each (no `ARKT` string at all). The Debug `ArktShell.debug.dylib` has each once (`ARKT_SMOKE` 5 times). The Profile executable has `ARKT_DEFAULTS_SUITE` and `ARKT_AUTOSAVE_DELAY_MS` but not `ARKT_UITEST` or the strict-mode line (Debug only) |
| Source gating | `grep -n '"ARKT_' $APP/App/*.swift` | every hit is inside `#if DEBUG` or `#if DEBUG \|\| ARKT_SMOKE_BUILD` |

Strict mode, on the Debug build with a throwaway `$SMOKE`:

| Run | Exit code | Log line (`log show`, subsystem `dev.arkt.shell`) |
|---|---|---|
| `ARKT_UITEST=1 ARKT_DATA_DIR=$SMOKE/d $BIN` (plan step) | 64; `$SMOKE` still empty, no `$SMOKE/d` | `uitest missing overrides ARKT_ARC_DIR ARKT_DEFAULTS_SUITE` |
| data and Arc dirs set, no suite | 64 | `uitest missing overrides ARKT_DEFAULTS_SUITE` |
| data and Arc dirs set, suite = `dev.arkt.ArktShell` | 64 | `uitest missing overrides ARKT_DEFAULTS_SUITE` |

Toolbar setting goes to the suite. All four keys set (`ARKT_UITEST=1`, data and Arc dirs in `$SMOKE`, the Arc dir
empty, suite `dev.arkt.uitest.u1-<random>`), launch arguments `-ApplePersistenceIgnoreState YES
-NSQuitAlwaysKeepsWindows NO -AppleLanguages (en) -AppleLocale en_US`. The app started and created
`$SMOKE/data/Arkt.sqlite`. View > Show Toolbar (the menu item Cmd-Shift-D fires) was clicked through System Events
on the app's process, then Arkt Shell > Quit Arkt Shell; exit code 0.

| Value | Before | After |
|---|---|---|
| `defaults read dev.arkt.ArktShell topBarURLEnabled` | key not found | key not found |
| `defaults export dev.arkt.ArktShell - \| shasum -a 256` | `a75631db...2abb3` | `a75631db...2abb3` (unchanged) |
| `defaults read <suite> topBarURLEnabled` | domain not found | `1` |
| `~/Library/Preferences/<suite>.plist` | absent | present; removed with `defaults delete <suite>` and then the empty file |
| `~/Library/Application Support/Arkt` | absent | absent |

E6 regression (track E plan, Task E6, step 3, steps 1 to 3) on the new Debug build, synthetic fixture copies in a
temp folder, plus `ARKT_DEFAULTS_SUITE` set to a throwaway suite so no run reads or writes the real defaults:

```
1  ARKT_SMOKE phase=verify outcome=created spaces=0 tabs=0 folders=0 splits=0 favorites=0 archive=0 added=- existing=- archiveAdded=- toast=none
   backups: 0
2  ARKT_SMOKE phase=import outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=2 existing=0 archiveAdded=7 toast=none
3  ARKT_SMOKE phase=verify outcome=opened spaces=2 tabs=9 folders=1 splits=1 favorites=2 archive=7 added=- existing=- archiveAdded=- toast=none
   backups: 1, archived_item rows: 7
```

Each line is identical to the E6 results (`docs/plans/2026-10-23-track-e-results.md`, steps 1 to 3). The Arc copy's
checksums were unchanged. Temp folders and suites were removed afterwards.

### Deviations from the plan

- The parsing lives in a new file, `App/EnvironmentOverrides.swift`, instead of directly in `AppEnvironment.swift`.
  `AppEnvironment` imports `Persistence`, so it cannot be compiled into a package test target; the pure file can,
  through a symlink, which is how the hooks got their in-process tests first (Rules: TDD for app hooks).
- A suite name equal to the app's bundle identifier or `NSGlobalDomain` is treated as missing in strict mode, and
  stops a non-strict Debug run, because `UserDefaults(suiteName:)` would otherwise write the real defaults.
- The Toolbar was toggled by clicking its View menu item through System Events on the app's process, not by typing
  Cmd-Shift-D: a synthetic keystroke goes to whatever app is frontmost, the menu click goes only to the Arkt process.
  The menu item is the one the shortcut fires.
- `ARKT_ENV_OVERRIDES` is `NO` in the base settings and `YES` only in Debug and Profile, so Release, Spike and any
  future configuration default to `NO`.

### What remains

- Nothing for U1. The XCUITest run itself starts in U2 and still needs the one-time permission steps 1 and 2 from U0
  (developer mode, automation mode).

## U4a: Accessibility identifiers: window, empty state, Toolbar and toasts (#167)

Base: `origin/main` at `5db2b4e`, rebased before review onto `ba0c281` (#191), branch `chore/167-ui-tests-u4a`.
Same machine as U0 (`nice -n 10`, `-j 4` / `-jobs 4`, no Chromium build running).

### What was done

- `ShellKit/Sources/ShellUI/Accessibility/AXID.swift` (new, no imports): `public enum AXID` with one nested enum per
  area: `Shell`, `Content`, `EmptyState`, `Toolbar`, `Toast`. The toast values `persistent` and `timed` live next to
  their identifier. U4b and U4c add their own nested enums. `xcrun swiftc -typecheck` on the file alone succeeds, so
  the UI test target can compile it by path.
- Identifiers set (setter calls only):

  | Identifier | Where | Role, label, value, state |
  |---|---|---|
  | `shell.window` | `ShellWindow.init` | window |
  | `content.card` | `ContentCardView.init` | group (the card becomes an accessibility element) |
  | `emptyState` | `EmptyStateView.init` | group (the panel becomes an accessibility element) |
  | `emptyState.import`, `emptyState.newSpace` | `EmptyStateView.init` | buttons keep their titles; `emptyState.import` absent while hidden |
  | `toolbar` | `ContentToolbarView.init` | toolbar, label "Toolbar"; absent while the Toolbar is hidden |
  | `toolbar.back`, `toolbar.forward`, `toolbar.reload` | `ContentToolbarView.init` | buttons, labels Back / Forward / Reload, enabled from `setHistory` |
  | `toolbar.urlBar` | `ContentToolbarView.init` on its `urlBar` | button, value = full address |
  | `toast` | `ToastView.init` | group, label = toast text, value `persistent` or `timed` (set in `display`) |
  | `toast.action` | `ToastView.init` on `actionButton` | button; absent without an action title |

- AppKit lists a control's cell, not the control, as the accessibility child, and the cell does not report an
  identifier set only on the control (checked in process: `NSButtonCell.accessibilityIdentifier()` stays empty).
  `NSControl.setAccessibilityIdentifierWithCell(_:)` (internal, `Accessibility/NSControl+AXID.swift`) sets the
  identifier on both; every button above uses it.
- `ShellWindowController.swift` is not touched: every identifier is set in the view that owns it.
- Tests: `ShellKitGUITests/AccessibilityIdentifierTests.swift`, 8 XCTest tests over a real `ShellWindowController`
  (`StubSidebar.sample()` or an empty `StubSidebar()`, `InMemoryEngine`). They walk the window's tree through
  `NSAccessibility.unignoredChildren` (what a client sees), find each identifier exactly once, check role, label,
  value or enabled state, and check that hidden views (import button, hidden Toolbar, idle toast, action button
  without a title) are absent. Written first: the first build failed with "cannot find 'AXID' in scope"; with
  `AXID.swift` only, 8 tests ran with 11 failures; with the identifiers set on the controls only, the 3 toolbar
  button checks still failed on the cell; then all passed.

### Verification

| Check | Command | Result |
|---|---|---|
| ShellKit GUI | `cd $KIT && nice -n 10 swift test -j 4 --filter ShellKitGUITests` | pass, 288 XCTest tests (baseline 280 at `5db2b4e` + 8), 0 failures, 46.8 s; after the rebase onto #191, 293 (280 + 5 from #191 + 8), 0 failures |
| ShellKit pure | `cd $KIT && nice -n 10 swift test -j 4 --skip ShellKitGUITests` | pass, 416 tests (baseline 416 at `5db2b4e` + 0); after the rebase onto #191, 423 (416 + 7 from #191) |
| ArktCore | `cd $CORE && nice -n 10 swift test -j 4` | pass, 336 tests (+ 0) |
| App build (Debug) | App command, `-jobs 4` | `** BUILD SUCCEEDED **`, 0 compiler warnings, 32.8 s; again after the rebase |
| Import layering | the workflow's `Check import layering` step, run locally | `Import layering OK` |
| `AXID.swift` stands alone | `xcrun swiftc -typecheck $KIT/Sources/ShellUI/Accessibility/AXID.swift` | no output, exit 0 |

The GUI baseline is 280, not U0's 240: #183, #185 and #187 added GUI tests after U0's base. Both baselines were run
on the untouched worktree at `5db2b4e` before any change.

### Deviations from the plan

- `project.yml` does not add `AXID.swift` to `ArktShellUITests` yet: that target does not exist until U2 (#165). U2
  adds the path (`ShellKit/Sources/ShellUI/Accessibility/AXID.swift`) to the target's sources. The plan's U2 step 1 and the
  U4 "Files" list now say so.
- Buttons get their identifier on the cell as well as on the control (`setAccessibilityIdentifierWithCell`), see
  above. The labels Back / Forward / Reload stay on the control as before; the first XCUITest run (U2) shows whether
  the real tree reports them, and U8 asserts on identifiers, not those labels.
- Split View pane cards are `ContentCardView`s too, so they carry `content.card` until U4c gives them `split.pane`.

### What remains

- U2 (#165): add `AXID.swift` to the `ArktShellUITests` sources by path and confirm the identifiers in the real
  accessibility tree. That run needs the one-time permission steps 1 and 2 from U0 (developer mode, automation mode).

## U2: UI test target, scheme and the first launch test (#165)

Base: `origin/main` at `5db2b4e`, branch `chore/165-ui-tests-u2`. Same machine as U0; no Chromium build running, so
`nice -n 10`, `-jobs 4`. Developer mode and Automation Mode (without authentication) were enabled by the maintainer
before this task.

### What was done

- `project.yml` (own commit): target `ArktShellUITests` (`bundle.ui-testing`, sources `UITests`, depends on
  `ArktShell`, `TEST_TARGET_NAME: ArktShell`, `dev.arkt.ArktShellUITests`, generated Info.plist) and scheme
  `ArktShellUITests` (builds `ArktShell` and the UI test target, tests in Debug, coverage off). The `ArktShell` scheme
  is unchanged.
- `UITests/Harness/Sandbox.swift`: `<NSTemporaryDirectory()>/arkt-uitest-<UUID>/{data,arc}` and the suite
  `dev.arkt.uitest.<UUID>`; `environment` gives `ARKT_UITEST=1`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR`,
  `ARKT_DEFAULTS_SUITE` and, when set, `ARKT_AUTOSAVE_DELAY_MS`. Every path must sit under the temp folder and contain
  neither `/Library/Application Support/` nor `Arc` (case sensitive), or the sandbox throws. `remove()` deletes the
  folder and the suite's persistent domain (only for `dev.arkt.uitest.` names). `listing()` gives names and sizes only.
- `UITests/Harness/Waits.swift`: `waitFor(_:)`, `waitFor(_:value:)`, `waitFor(_:label:)`, `waitForEnabled`,
  `waitForSelected`, `waitUntilGone`, `waitFor(app, state)`, all one `XCTNSPredicateExpectation` with `XCTWaiter`;
  10 s default times `ARKT_UITEST_TIMEOUT_SCALE`.
- `UITests/Harness/ArktUITestCase.swift`: `continueAfterFailure = false`. `makeApp()` resolves the bundle
  (`ARKT_UITEST_APP`, else `ArktShell.app` next to the runner) and launches it with `XCUIApplication(url:)` in both
  cases, so the bundle whose Info.plist was checked is the one that runs. It throws before creating the proxy when
  `ArktEnvironmentOverrides` is not `YES`, and when an app with the same bundle identifier is already running
  (`launch()` would terminate it). `launch` sets the sandbox environment and the Rules launch arguments, then waits for
  the window (`app.windows.firstMatch` until `shell.window` lands with U4a, #167). `quit` activates the app, waits for
  `.runningForeground`, then types Cmd-Q and waits for `.notRunning`. A tear-down block attaches, on failure only, the
  window screenshot, the accessibility tree and the sandbox listing (`.keepAlways`), terminates the app if it still
  runs and removes the sandbox. A test launches into one sandbox; a relaunch reuses it, a second sandbox throws.
- `UITests/LaunchTests.swift`: `test_E_launchOnEmptyDataFolderShowsWindowAndQuitsCleanly`.

### Verification

| Check | Result |
|---|---|
| `xcodebuild ... -scheme ArktShellUITests ... test` (incremental) | `** TEST SUCCEEDED **`, `Executed 1 test, with 0 failures`; test 4.6 s, command 9.1 s wall |
| Same from a clean derived data folder | `** TEST SUCCEEDED **`, 1 test; test 5.1 s, command 38.8 s wall (build included) |
| No sleeps, no URLs in `UITests` | `grep -rnE '\b(sleep\|usleep\|Thread\.sleep\|Task\.sleep)\b'` and `grep -rn http` on `UITests`: 0 hits |
| Import layering | the workflow's `Check import layering` step, run locally: `Import layering OK` |
| Refusal probe | `TEST_RUNNER_ARKT_UITEST_APP` pointed at a scratch bundle that holds only a copy of the Debug Info.plist with `ArktEnvironmentOverrides = NO`: the test fails with "Fake.app does not declare ArktEnvironmentOverrides = YES; refusing to launch", nothing is launched |
| Failure artifacts probe | a temporary `XCTFail` after launch (reverted, not committed): attachments `window`, `accessibility tree`, `sandbox listing`; then the app was terminated and the sandbox removed. A passing run adds no attachment |
| `ArktShell` scheme unchanged | generated `ArktShell.xcscheme` from this branch and from `origin/main`'s `project.yml`: `diff` prints nothing |
| ArktCore | `nice -n 10 swift test -j 4`: pass, 336 tests (84 + 97 + 59 + 96), no package change |
| ShellKit pure | `nice -n 10 swift test -j 4 --skip ShellKitGUITests`: pass, 416 tests (176 + 33 + 15 + 4 + 22 + 166) on current `main`, no package change |
| `git status` | only `project.yml` and `UITests/`; `ArktShell.xcodeproj` and `build/` stay ignored |

Real data, read-only checks from the shell before and after all runs:

| Value | Before | After |
|---|---|---|
| `defaults export dev.arkt.ArktShell - \| shasum -a 256` | `a75631db...2abb3` | `a75631db...2abb3` (unchanged, same as U1) |
| `~/Library/Application Support/Arkt` | absent | absent |
| `~/Library/Preferences/dev.arkt.uitest.*` | none | none |
| `$TMPDIR/arkt-uitest-*` | none | none |

### First-run permission prompts

- State before the run: `DevToolsSecurity -status` "Developer mode is currently enabled."; `automationmodetool`
  "Automation Mode is disabled." and "This device DOES NOT REQUIRE user authentication to enable Automation Mode."
  After the runs `automationmodetool` still prints "Automation Mode is disabled.", so it is not left on between runs.
- The first `xcodebuild test` passed without any prompt blocking it and without any manual step during the run. No
  Accessibility or Automation grant had to be added by hand for the run from the terminal.

### Signing probe (plan step 7)

`build-for-testing` with the base identity (`CODE_SIGN_IDENTITY: "-"`, no command-line signing settings):
`codesign -dv` shows `Signature=adhoc`, `TeamIdentifier=not set` for both `ArktShellUITests-Runner.app`
(`dev.arkt.ArktShellUITests.xctrunner`) and `ArktShell.app`. The runner launched and drove the app; no signing
override was needed.

### Deviations from the plan

- `ArktUITestCase` is `@MainActor` because `XCUIApplication` is main-actor isolated in this SDK. Clean-up runs as a
  main-actor tear-down block registered by `launch` instead of an overridden `tearDown`: a nonisolated `tearDown`
  cannot hand the test case to the main actor under Swift 6 checking.
- The default `ArktShell` target is launched through `XCUIApplication(url:)` too (the plan has `XCUIApplication()`
  for that case), so the Info.plist check and the launch always use the same bundle.
- `makeApp()` also refuses to launch while an app with the bundle's identifier is running, because `launch()`
  terminates a running instance, which could be a developer's own Debug build.

### Notes for U3

- Runner environment variables reach the test runner only through `xcodebuild`'s process environment:
  `TEST_RUNNER_ARKT_UITEST_APP=... xcodebuild ... test` worked, while the same value passed as a build-setting
  argument (`xcodebuild ... TEST_RUNNER_ARKT_UITEST_APP=... test`) did not reach the runner (the refusal probe
  passed instead of failing). The CI step should therefore set `TEST_RUNNER_ARKT_UITEST_TIMEOUT_SCALE: 3` in the
  step's `env:` rather than on the command line.

### What remains

- Nothing for U2. The CI job is U3; `shell.window` replaces `windows.firstMatch` once U4a (#167) lands.
- `Sandbox.remove()` clears the suite with `removePersistentDomain`, but the launch test never writes a defaults key,
  so a populated suite was not exercised. U1 saw `defaults delete` leave an empty plist; U8 (Toolbar toggle) is the
  first test that shows whether an empty `dev.arkt.uitest.*.plist` stays behind.

## U3: CI job (informative) and the local how-to (#166)

Base: `origin/main` at `a79d75f`, branch `chore/166-ui-tests-u3`. No local build or UI test run: the change is CI
YAML and docs, verified on the pull request's own runs.

### What was done

- `.github/workflows/swift-tests.yml` (own commit): job `ui-tests`, name `UI tests (informative)`, `macos-26`,
  `timeout-minutes: 40`, `continue-on-error: true`, not in the gate's `needs`. Steps: checkout, setup-xcode, XcodeGen
  with the `app` job's pinned version and SHA-256, restore-only cache of `app/ArktShell/build/SourcePackages`,
  `xcodegen generate`, then `xcodebuild -scheme ArktShellUITests ... -resultBundlePath $RUNNER_TEMP/ui.xcresult
  -parallel-testing-enabled NO test` with `TEST_RUNNER_ARKT_UITEST_TIMEOUT_SCALE: "3"` in the step's `env:`. No
  `CODE_SIGNING_ALLOWED=NO`. On failure, `actions/upload-artifact` (v7.0.2, pinned by SHA) uploads the result bundle
  as `ui-tests-xcresult`, kept 7 days.
- `CONTRIBUTING.md` (own commit): section 7 gains the local UI test run, the hands-off rule, the timeout-scale note
  and the one-time setup list; section 12 describes the job, its artifact and the promotion criteria (decision 8).
- `actionlint` on the workflow: no findings.

### CI run on the pull request

| | |
|---|---|
| Run | `39988982373`, head `32a1372`, workflow conclusion `success` |
| `UI tests (informative)` | `success`, job 2 min 30 s (16:49:40 to 16:52:09 UTC) |
| `xcodebuild test` step | 2 min 12 s, build included (no derived data cache); `** TEST SUCCEEDED **` |
| Tests | `Executed 1 test, with 0 failures` (`LaunchTests/test_E_launchOnEmptyDataFolderShowsWindowAndQuitsCleanly`, 10.07 s; "Setting up automation session" at 3.9 s) |
| SPM cache | restored from the `app` job's `app-spm-macOS-ARM64-...` key |
| Signing | `ArktShell.app` and `ArktShellUITests-Runner.app` signed "Sign to Run Locally" (`codesign --sign -`), accepted by the runner |
| Permission steps | none: no Accessibility, Automation or developer mode step was needed on the hosted runner |
| `Swift tests` gate | `success`; its `needs` are still `isolation, arktcore, shellkit, app` |
| Result bundle upload | skipped (the tests passed); the failure path was not exercised in this pull request |

The CI build (Xcode 26.6) prints 11 Swift 6 concurrency warnings in `UITests/Harness/Waits.swift` ("main
actor-isolated property 'exists' / 'value' / 'label' / 'isEnabled' / 'isSelected' / 'state' can not be referenced
from a nonisolated context") that the local Xcode 27.1 build of U2 did not show. They do not fail the build; they
are left for a follow-up because U3 does not change the harness.

### Deviations from the plan

- The result bundle is uploaded only when the job fails (`if: ${{ failure() }}`), not on every non-cancelled run: a
  passing run has no attachments (decision 7), so its bundle carries nothing a reviewer needs.
- `TEST_RUNNER_ARKT_UITEST_TIMEOUT_SCALE=3` is set in the step's `env:` instead of on the `xcodebuild` command line
  (U2 notes for U3: only the process environment reaches the test runner).
- `-parallel-testing-enabled NO` added to the command, from the plan's flakiness strategy.
- The issue was moved from `status:blocked` (not `status:ready`) to `status:in-progress`, since U2 (#165) had merged.

### What remains

- Promotion to a required check (U16): 10 consecutive green runs on `main` and a local 20-iteration run.
- The `Waits.swift` concurrency warnings under Xcode 26.6.

## U5: Loopback fixture server and source checks (#170)

Base: `origin/main` at `77d4a94`, rebased onto `fdda316` (#203, U3), branch `chore/170-ui-tests-u5`. No Chromium
build running; `nice -n 10`, `-jobs 4`.

### What was done

- `UITests/Harness/FixtureServer.swift`: HTTP/1.1 on `127.0.0.1` only (`requiredInterfaceType = .loopback` and a
  required local endpoint `127.0.0.1:0`), ephemeral port, one request per connection. `/p/<name>` serves
  `<title>Fixture <name></title>` with a link to `/p/<name>-next`; `/favicon.ico` answers 404; any other path serves a
  generic page titled `Fixture <path>`. The request log (paths only) sits behind a `Mutex`. `base` is
  `http://127.0.0.1:<port>`. The start waits on `stateUpdateHandler` through one `CheckedThrowingContinuation`
  (resumed once: the handler is cleared on the first final state); a deadline on the server's queue cancels a
  listener that is not ready after 5 s, and `.waiting` counts as a failure. No sleep.
- `ArktUITestCase.fixtureServer()`: starts the test's server on first use, caches it on the test case instance and
  stops it in a tear-down block.
- `UITests/LoopbackPageTests.swift`: `test_E_loopbackPageLoadsInTheEngine`. Cmd-T on an empty profile (the shell
  creates the first Space), type `<base>/p/alpha` into `commandBar.field`, Return, then wait for the sidebar row's
  title `Fixture alpha` and check the server log has `/p/alpha`.
- `Check UI test sources`, an inline zsh step of the `ui-tests` job in `.github/workflows/swift-tests.yml` (no
  script): fails on `sleep(`, `usleep(`, `Thread.sleep`, `Task.sleep`, and on any
  `http(s)://` under `app/ArktShell/UITests` other than `http://127.0.0.1` (followed by `:`, `/` or the end) and
  `https://example.com` in `Harness/ArcFixture.swift` only.
- `project.yml` (own commit): the `ArktShellUITests` target gets an entitlements file,
  `ArktShellUITests.entitlements`, with `com.apple.security.network.server`. It sits next to `project.yml`, not in
  `UITests/`, so it is not a target source and its plist DOCTYPE URL stays out of the source check.
- `.github/workflows/swift-tests.yml` (own commit): `Check UI test sources` runs right after checkout in the
  `ui-tests` job, before Xcode is set up.

### Verification

| Check | Result |
|---|---|
| `Check UI test sources` step on the branch | `UI test sources OK`, exit 0 |
| Temporary `sleep(1)` in `LoopbackPageTests.swift` (reverted) | lists `./LoopbackPageTests.swift:25:    sleep(1)`, exit 1 |
| Temporary `Task.sleep`, `Thread.sleep`, `usleep` line (reverted) | listed, exit 1 |
| Temporary `https://www.example.org/x`, `http://127.0.0.1.evil.test/`, `https://example.com/a` outside `ArcFixture.swift` (reverted) | all three listed, exit 1 |
| Server alone (scratch build of `FixtureServer.swift` with a `main.swift`, not committed) | `lsof` shows one `TCP 127.0.0.1:<port> (LISTEN)`, IPv4 only; `/p/alpha` 200 with the title and link, `/favicon.ico` 404, `/some/x?y=1` 200 titled after the path; 50 concurrent requests all logged |
| Same, inside an ad-hoc signed sandboxed app bundle | with `network.client` only: `POSIXErrorCode(rawValue: 1): Operation not permitted`; with `network.server` added: serves as above |
| `build-for-testing` (Xcode 27.1) | `** TEST BUILD SUCCEEDED **`; runner entitlements now include `network.server`; no new warnings (the `Waits.swift` warnings from U3 remain) |
| Local UI run (once, Xcode 27.1, before the entitlement) | `LaunchTests` passed; `test_E_loopbackPageLoadsInTheEngine` failed at the server start: `bind(127.0.0.1:0)` EPERM, the runner is sandboxed with `network.client` only |
| CI `UI tests (informative)`, head `2ffcf33` (Xcode 26.6) | `Check UI test sources`: `UI test sources OK`; `** TEST SUCCEEDED **`, `Executed 2 tests, with 0 failures` (LaunchTests 9.3 s, LoopbackPageTests 10.0 s) |
| `Swift tests` gate on the same run | `success` |

The local UI run was not repeated after the entitlement fix (one GUI run per change on a shared machine); CI ran
both tests green with the fix.

### App Transport Security

No exception needed. The Debug `Info.plist` has no `NSAppTransportSecurity` key, and the page at
`http://127.0.0.1:<port>/p/alpha` loaded in the FakeEngine (WKWebView) on CI: IP literals are exempt from ATS, as the
plan expected.

### Deviations from the plan

- The server starts on first use (`fixtureServer()`) instead of in `setUp`: tests that open no page start no
  listener, and an `async` start does not fit the nonisolated `setUpWithError` of the main-actor test case. One
  server per test case instance, stopped in tear-down, as planned.
- The probe test finds the row as the title text inside the sidebar outline (`app.outlines` static text with value
  or label `Fixture alpha`), because `sidebar.row.today` lands with U4b (#168). U4b switches it to the identifier.
- New `project.yml` entitlements for the UI test runner (`network.server`); the plan did not foresee that the
  runner is sandboxed.
- The fallback page is titled `Fixture <path>` (the plan says "titled after the path").

### What remains

- U4b (#168): replace the outline text query in `LoopbackPageTests` with `sidebar.row.today`.
- The local failed run attached Xcode's automatic screen recording (`lifetime deleteOnSuccess`, so kept on failure)
  of the whole screen, which decision 7 rules out; the scheme should turn it off. Left for the harness follow-up
  (#199). The same run also spent about 150 s between the recorded failure and tear-down, likely that recording.
- #93 removes the duplication between `FixtureServer` and `ShellKitGUITests/LoopbackServer.swift`.

## U4b: Accessibility identifiers: sidebar rows, Space dots and Favorites (#168)

Base: `origin/main` at `8b1a570`, branch `chore/168-ui-tests-u4b`.

### What was done

- `ShellKit/Sources/ShellUI/Accessibility/AXID.swift`: added `AXID.Sidebar` (`urlBar`, `newTab`, `spaceDots`,
  `spaceDot`, `page`, `spaceTitle`, `rowPinned`, `rowToday`, `rowFolder`, `rowSplit`, `divider`, `rowClose`) and
  `AXID.Favorites` (`grid`, `tile`, `tileClose`, `loaded`, `unloaded`).
- Identifiers, labels, values and selected state set:
  - `SidebarContainerView`: `urlBar` (`sidebar.urlBar`), `newTabButton` (`sidebar.newTab`), `SpaceDotsView`
    (`sidebar.spaceDots`) and each `SpaceDotElement` (`sidebar.spaceDot`), plus `setAccessibilitySelected` on
    `SpacePageView` from `setPages(_:index:)` and `setCurrent(page:)`.
  - `SpacePageView`: `sidebar.page` (role `.group`, label = Space title, selected = current Space) and `titleLabel`
    (`sidebar.spaceTitle`).
  - `SidebarOutlineView`, `SidebarOutlineController`, `SidebarRowView`, `SidebarTabCellView`, `SidebarDividerView`:
    `SidebarOutlineView.accessibilityChildren()` exposes the unignored row views; node rows carry `sidebar.row.pinned`,
    `sidebar.row.today`, `sidebar.row.folder` or `sidebar.row.split` with role `.row`, label = row title and
    `isAccessibilitySelected() == (state == .current)` without enabling outline selection; the divider row is ignored
    so its child `SidebarDividerView` (`sidebar.divider`, role `.splitter`) sits directly in the outline's unignored
    children; `SidebarTabCellView.closeButton` carries `sidebar.row.close` while shown.
  - `FavoritesGridView` and `FavoriteTileView`: `FavoritesGridView` carries `favorites.grid` (role `.group`),
    `FavoritesCollectionView.accessibilityChildren()` exposes the realized `FavoriteTileView`s (`favorites.tile`,
    role `.button`, label = title, value `loaded` or `unloaded`), and `FavoriteTileView.closeButton` carries
    `favorites.tile.close` while shown.
- Tests: `AccessibilityIdentifierTests` gains 4 tests (`testSidebarURLBarNewTabAndSpaceDotsHaveIdentifiersLabelsAndSelection`,
  `testSpacePagesAndTitlesHaveIdentifiersLabelsAndSelection`, `testSidebarOutlineRowsDividerAndHoverCloseButton`,
  `testFavoritesGridTilesAndCloseButton`), written first (failed before the view changes, then 12/12 pass).

### Verification

| Check | Command | Result |
|---|---|---|
| `AccessibilityIdentifierTests` | `swift test --filter AccessibilityIdentifierTests` | 12/12 pass (8 U4a + 4 U4b) |
| ShellKit pure + isolation | `swift test --skip ShellKitGUITests` | 456 tests in 61 suites pass |
| `AXID.swift` standalone | `xcrun swiftc -typecheck app/ArktShell/ShellKit/Sources/ShellUI/Accessibility/AXID.swift` | exit 0 |

## U4c: Accessibility identifiers: command bar, Archive window and Split View (#169)

Base: `origin/main` at `d318d0c`, branch `chore/169-ui-tests-u4c`.

### What was done

- `ShellKit/Sources/ShellUI/Accessibility/AXID.swift`: added `AXID.CommandBar` (`root`, `field`, `results`, `row`,
  `open`, `closed`), `AXID.Archive` (`window`, `table`, `row`, `restore`, `loadMore`, `footer`, plus the documented
  `search = "archive.search"` constant reserved for #111), and `AXID.Split` (`container`, `pane`, `divider`, `reopen`).
- Identifiers, labels, values and selected state set:
  - `CommandBarView`, `CommandBarPanel`, `CommandBarController`, `CommandBarResults`: `CommandBarView` carries
    `commandBar` with value `open` while shown and `closed` while hidden and inert; `field` carries
    `commandBar.field` (on the control and cell); `table` (`CommandBarTableView`) carries `commandBar.results` and
    exposes its unignored `CommandBarRowView`s (`commandBar.row`, role `.row`, label = result title, value =
    `accessibilityCaption` ("Switch to Tab", "Switch to Split View", "Open", "Search"), selected = `isSelected`).
  - `ArchiveWindowController`: `window` carries `archive.window`; `tableView` (`ArchiveTableView`) carries
    `archive.table` and exposes its `ArchiveRowView`s (`archive.row`, role `.row`, label = row title, selected =
    `isSelected`); `restoreButton` (`archive.restore`), `loadMoreButton` (`archive.loadMore`) and `footerLabel`
    (`archive.footer`, value = footer text) set their identifiers on both control and cell.
  - `SplitContainerView` and `SplitDividerView`: `SplitContainerView` carries `split.container` and orders its
    `accessibilityChildren()` in pane order (`paneCards` then `dividers` then `toastView`); each pane card carries
    `split.pane` with `isAccessibilitySelected() == (index == focusedIndex)`; each `SplitDividerView` carries
    `split.divider` with value = share factor (`NSNumber`); `SplitPanePlaceholderView` carries `split.reopen`.
- Tests: `AccessibilityIdentifierTests` gains 3 tests
  (`testCommandBarAndResultRowsHaveIdentifiersLabelsValuesAndSelection`,
  `testArchiveWindowTableRowsButtonsAndFooterHaveIdentifiers`,
  `testSplitViewContainerPanesDividerAndReopenButtonHaveIdentifiers`), written first (failed before the view changes,
  then 15/15 pass).

### Verification

| Check | Command | Result |
|---|---|---|
| `AccessibilityIdentifierTests` | `swift test --filter AccessibilityIdentifierTests` | 15/15 pass (8 U4a + 4 U4b + 3 U4c) |
| `ArchiveWindowTests` | `swift test --filter ArchiveWindowTests` | 19/19 pass |
| ShellKit pure + isolation | `swift test --skip ShellKitGUITests` | 456 tests in 61 suites pass |
| `AXID.swift` standalone | `xcrun swiftc -typecheck app/ArktShell/ShellKit/Sources/ShellUI/Accessibility/AXID.swift` | exit 0 |

## U2 follow-ups: harden the UI test harness (#199)

Base: `origin/main` at `c5f9db8`, branch `chore/199-harden-u2-harness`.

### What was done

- `ArktUITestCase.shellWindow(of:)` now returns `app.windows[AXID.Shell.window]` (plan U2 step 3).
- `ArktUITestCase.mergedEnvironment(sandbox:extraEnv:)` (called by `launch(_:extraEnv:)` before creating or launching
  the app proxy) rejects any `extraEnv` key owned by `Sandbox` (`ARKT_UITEST`, `ARKT_DATA_DIR`, `ARKT_ARC_DIR`,
  `ARKT_DEFAULTS_SUITE`, and `ARKT_AUTOSAVE_DELAY_MS` when set on the sandbox), so a test cannot point the app at a
  path outside the sandbox.
- `Sandbox.checkSafe(_:root:under:)` checks both that `root` sits under `temp` (with a trailing `/`) and that every
  handed-out path sits under `root` (with a trailing `/`), in addition to rejecting `/Library/Application Support/`
  and `Arc`.
- `LoopbackPageTests` switched from the temporary pre-U4b outline static-text query to `AXID.CommandBar.field` and
  `app.outlineRows[AXID.Sidebar.rowToday]`, and `SidebarOutlineView` / `CommandBarTableView` / `ArchiveTableView` and
  their row views implement `accessibilityRows()`, `accessibilityVisibleRows()` and `accessibilityParent()` for
  out-of-process `AXUIElement` traversal.
- `LaunchTests.test_E_sandboxGuardAndExtraEnvRestrictions` covers the `Sandbox.checkSafe` prefix rules and
  `mergedEnvironment` / `launch(_:extraEnv:)` rejections.
- `Waits.swift` (`Waits` and the `XCTestCase` wait helpers) is `@MainActor`-isolated so `XCUIElement` property reads
  compile with zero Swift 6 concurrency warnings on Xcode 26.6+, and `.github/workflows/swift-tests.yml` and
  `CONTRIBUTING.md` pass `-collect-test-diagnostics never` on `xcodebuild ... test` so Xcode never records whole-screen
  videos (plan decision 7).

### Verification

| Check | Command | Result |
|---|---|---|
| `Check UI test sources` | workflow grep step on `app/ArktShell/UITests` | `UI test sources OK`, exit 0 |
| `LaunchTests` guard test | `xctest -XCTest ArktShellUITests.LaunchTests/test_E_sandboxGuardAndExtraEnvRestrictions` | pass (0.006 s) |
| `AccessibilityIdentifierTests` | `swift test --filter AccessibilityIdentifierTests` | 15/15 pass |
| ShellKit pure + isolation | `swift test --skip ShellKitGUITests` | 457 tests in 61 suites pass |

## U6: Arc fixtures and seeding (#171)

Base: `origin/main` at `ab08905`, branch `chore/171-ui-tests-u6`.

### What was done

- `project.yml` (own commit): `ArktShellUITests` bundles
  `../ArktCore/Tests/ArcImportTests/Fixtures/StorableSidebar-synthetic.json` and
  `../ArktCore/Tests/ArcImportTests/Fixtures/StorableArchiveItems-synthetic.json` by path reference with
  `buildPhase: resources` (no copy in the repo).
- `UITests/Harness/ArcFixture.swift`: `ArcFixture.render(into:base:)` reads both bundled fixtures, replaces every
  `https://example.com` with `base`, writes `StorableSidebar.json` and `StorableArchiveItems.json` into `arcDir`, and
  returns their SHA-256 digests (`Checksums`, with `unchanged(in:)`). `ArcFixture.expected` holds the E6 counts
  (`spaces = 2`, `tabs = 9`, `folders = 1`, `splits = 1`, `favorites = 2`, `archive = 7`), each commented with
  `docs/plans/2026-10-23-track-e-results.md`.
- `UITests/Harness/Sandbox.swift`: `Sandbox.seedFromArcFixture(server:)` renders the fixture into `arcDirectory`,
  launches the app with `ARKT_SMOKE=import`, waits for `.notRunning` (timeout 30 s times `Waits.scale`), asserts
  `data/Arkt.sqlite` exists, and returns the rendered checksums. It is the only place `ARKT_SMOKE` appears in
  `UITests/`.
- `UITests/LaunchTests.swift`: added `test_E_arcFixtureRenderRewritesURLsAndMatchesExpectedCounts` and
  `test_E_seededLaunchShowsImportedSpaces`.

### Verification

| Check | Command | Result |
|---|---|---|
| `Check UI test sources` | workflow grep step on `app/ArktShell/UITests` | `UI test sources OK`, exit 0 |
| Single `ARKT_SMOKE` site | `grep -rn ARKT_SMOKE app/ArktShell/UITests` | 1 hit (`Sandbox.seedFromArcFixture`) |
| `ArcFixture` render & checksums | `xctest -XCTest ArktShellUITests.LaunchTests/test_E_arcFixtureRenderRewritesURLsAndMatchesExpectedCounts` | pass (0.009 s) |
| `build-for-testing` | `xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests -derivedDataPath build build-for-testing` | `** TEST BUILD SUCCEEDED **` |

## U7: First run, New Space, Cmd-T, Today, Cmd-L (#172)

Base: `origin/main` at `01e68c3`, branch `chore/172-ui-tests-u7`.

### What was done

- `UITests/FirstRunAndOpenTests.swift`: 9 tests (the plan's 8, with the `Space 1` naming rule as its own test).
- `UITests/Harness/Shell.swift` (new): command bar and sidebar row helpers (`openCommandBar`, `openInNewTab`, `submit`,
  `waitForCommandBar`, `todayRow`, `todayRows`, `spaceDots`). The plan's `Shell.openInNewTab(_:)` for U8 is
  `Shell.openInNewTab(_:in:)`.
- #269 known issue narrowed (review follow-up from #270): `expectOutlineRowsKnownIssue()` marked the whole test. It is
  replaced by `ArktUITestCase.waitForOutlineRows(_:_:)`, which wraps only the row wait in a non-strict
  `XCTExpectFailure` and returns whether the rows were there. Any other failure in the test still fails it, and the
  checks after the wait run (`continueAfterFailure` is on for the duration of the wait). `LaunchTests` and
  `LoopbackPageTests` use it.
- Deviation: the first-run test renders the Arc fixture into the same sandbox after a quit and relaunches, because a
  test launches into one sandbox only.
- Deviation: the closed command bar is "root absent or value `closed`", since a hidden panel can leave the
  accessibility tree.
- Not covered: `Space 2` (New Space from the Spaces menu, #106) is not asserted yet.

### Tests

| Test | Parity | Run time (CI) |
|---|---|---|
| `test_E_firstRunShowsEmptyStateWithoutImport` | none | 12.2 s |
| `test_E_newSpaceCreatesFirstSpace` | none | 6.6 s |
| `test_E_newSpaceTitleFollowsDecision106` (asserts normally since #106 landed) | none | 5.0 s |
| `test_KB001_BH100_cmdTOpensURLInNewTodayTab` | KB-001, BH-100 | 77.5 s (two #269 waits) |
| `test_KB002_BH101_cmdLEditedEnterNavigatesCurrentTab` | KB-002, BH-101 | 79.9 s (two #269 waits) |
| `test_KB004_BH102_cmdLUneditedEnterReloads` | KB-004, BH-102 | 48.6 s (one #269 wait) |
| `test_KB003_BH103_cmdTOrCmdLWhileOpenCloses` | KB-003, BH-103 | 13.8 s |
| `test_KB084_escClosesCommandBar` | KB-084, NEEDS-RUNTIME-CHECK RT-08 | 10.1 s |
| `test_E_cmdTWithNoSpaceCreatesSpaceThenTab` | none | 44.8 s (one #269 wait) |

### Verification

Run on CI ("UI tests (informative)", macos-26, `ARKT_UITEST_TIMEOUT_SCALE=3`), not locally: the machine was under load
and other GUI work was running. 14 tests, 0 unexpected failures, 380 s. On macOS 26 the sidebar rows are missing
(#269), so each row wait times out at 30 s as an expected failure; the remaining checks of each test ran and passed.
The `Space 1` test reported its expected failure (`"Space"` is not `"Space 1"`). Run times with rows exposed
(macOS 27) are not measured yet.

Known issues used: #269 (outline rows), #106 (Space naming).

## U8: Toolbar and Back / Forward (#173)

Base: `origin/main` at `12202c5`, branch `chore/173-ui-tests-u8`.

### What was done

- `UITests/ToolbarTests.swift`: 4 tests, as in the plan.
- `UITests/Harness/Shell.swift`: `createFirstSpace(in:)` moved here from `FirstRunAndOpenTests` (now an
  `ArktUITestCase` extension) so both suites share it.
- Back / Forward state is also checked through `toolbar.urlBar`, which is not an outline row, so only the row-label
  checks go through `waitForOutlineRows` (#269).
- A test launches into one sandbox only, so "a fresh sandbox starts with the Toolbar off" is asserted at the start of
  the toggle and relaunch tests (each runs in its own new suite) rather than by a second launch. A Toolbar left on in
  the real `dev.arkt.ArktShell` domain would make those assertions fail.
- Deferred: KB-031 / KB-032 (Cmd-[ / Cmd-]) to #119; `parity-deferred.txt` entries are added in U16.

### Tests

| Test | Parity |
|---|---|
| `test_KB018_BH032_cmdShiftDTogglesToolbar` | KB-018, BH-032 |
| `test_BH031_GS042_sidebarURLBarContextMenuShowsToolbar` | BH-031, GS-042 |
| `test_BH032_toolbarSettingSurvivesRelaunchInSameSuite` | BH-032 |
| `test_BH032_backForwardEnabledFollowsHistory` | BH-032 |

### Verification

Source typecheck with `swiftc -typecheck` against XCTest (the machine was under load, load average above 20, so no
local UI run). CI "UI tests (informative)" on `d9a9145` (macos-26, scale 3, 10 m 55 s): pass, all 4 `ToolbarTests` passed
beside the existing 14 tests. The context menu item "Show Toolbar" shares its title with the View menu item, so the
test clicks the hittable match.

Known issues used: #269 (outline rows).

## U11: Command bar keys (#176)

Base: `origin/main` at `46f3729`, branch `chore/176-command-bar-keys`.

### What was done

- `UITests/CommandBarKeyTests.swift`: four of the plan's five tests (see Deviations).
- `UITests/Harness/Shell.swift`: `commitSelectedRow` presses Return (or Cmd-Return / Opt-Return) on the selected
  `commandBar.row` and returns false without pressing when that row's value is `Search`. `selectCommandBarRow` moves
  with Down and does not press Enter. Row queries stay on the results table (`commandBar.results`); a whole-app
  `descendants` query also walks the web view and stalls inside a wait.
- `ShellUI/Accessibility/AXProxyRows.swift` (new, shared): `AXProxyRows` publishes the table as one
  `AXProxyTable` element (role table, identifier `commandBar.results`) with one `AXProxyRow` child per row.
  `NSTableRowView` never shows up as a child of `commandBar.results` for XCUITest, so
  `app.tables["commandBar.results"].tableRows.matching(identifier: "commandBar.row")` was empty while the Open row
  was on screen; `NSTableView` answers out of process from its own internals (#269). `CommandBarView` lists the
  proxy table in place of the scroll view that holds the real table. Each
  proxy computes its label, value and identifier from the model for its row index, its selection from the table
  and its frame in screen coordinates when asked; nothing creates a row view or forces layout. Proxies keep their
  identity between queries and are rebuilt on `reloadData` and when the row count changes. The proxies subclass
  `NSAccessibilityElement`, whose getters the SDK leaves nonisolated: they read main-actor state only on the main
  thread, through `MainActor.assumeIsolated` with `Sendable` results, and fall back to an empty answer off it. No
  legacy `accessibilityAttributeValue` override, no `nonisolated(unsafe)`, no `@unchecked Sendable`. Each proxy's
  `accessibilityChildren()` is empty so a snapshot does not walk from the row back into the table. The Archive table
  (#292) and the sidebar outline (#283, #269) reuse this helper and land after this pull request.
- `CommandBarView.swift`: `CommandBarTableView` owns the `AXProxyRows` and reports reloads and selection changes;
  `CommandBarView` lists its element. `CommandBarController` supplies the row content from its results.
- The three KB-085 tests are marked `PARITY(NEEDS-RUNTIME-CHECK RT-08)`. They assert Arkt's current [I] default.
- Sidebar checks go through `waitForOutlineRows` (#269). Command bar rows are selected directly.

### Tests

| Test | Parity | Run time |
|---|---|---|
| `test_KB085_downWrapsFromLastToFirst` | KB-085, NEEDS-RUNTIME-CHECK RT-08 | 76.570 s, passed |
| `test_BH104_BH110_switchToTabRow` | BH-104, BH-110 | 78.482 s, passed |
| `test_KB085_cmdEnterOpensURLInNewTab` | KB-085, NEEDS-RUNTIME-CHECK RT-08 | 83.557 s, passed |
| `test_KB085_optEnterOpensURLInNewTab` | KB-085, NEEDS-RUNTIME-CHECK RT-08 | 83.857 s, passed |

### Verification

The first local class run (bundle `ui-1792869775`) executed 5 and failed 5. Each case timed out after 10.0 s at
`CommandBarKeyTests.swift:110` with summary `no command bar rows`. After the exposure above, from `app/ArktShell`:

```zsh
nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests -derivedDataPath build \
  -resultBundlePath build/ui-1792875051.xcresult -collect-test-diagnostics never \
  -parallel-testing-enabled NO -only-testing:ArktShellUITests/CommandBarKeyTests -jobs 2 test-without-building
```

5 tests executed, 0 failed. `** TEST EXECUTE SUCCEEDED **`, exit 0.

`Executed 5 tests, with 0 failures (0 unexpected) in 404.914 (404.916) seconds`

`test_E_noSearchCommitted` selected the Search row and `commitSelectedRow` returned false without pressing Return:
the bar stayed open and no search was committed. Each case still records the #269 expected failure on
`sidebar.row.today`. That expected failure is not a product failure of these five tests.

TDD: the first `build-for-testing` failed (`Shell` had no `commitSelectedRow` / `selectCommandBarRow` /
`selectedCommandBarRow` / `commandBarRowSummary`). The helper landed before either UI run. The passing run is the
exposure above.

Source check (the CI grep, from `app/ArktShell/UITests`): `UI test sources OK`, exit 0. No sleeps. No http(s) literal
other than `http://127.0.0.1` and `https://example.com` in `Harness/ArcFixture.swift`.

Pure tests, recorded before the `CommandBarView.swift` exposure and not re-run after it, `nice -n 20 swift test -j 2`:
`app/ArktCore` exit 0, Swift Testing 355 tests in four runs (94 + 100 + 63 + 98), 0 failures.
`app/ArktShell/ShellKit` with `--skip ShellKitGUITests` exit 0, 545 tests
(212 + 33 + 28 + 4 + 48 + 185 + 23 + 12), 0 failures. The 28-test run is the four isolation suites, including
`CoreIsolationTests` and `WebKitIsolationTests`. `ShellKitGUITests` (including `AccessibilityIdentifierTests`) was
not re-run; the in-process walk of `accessibilityChildren()` now sees the proxy rows.

### Deviations

- The plan names `Shell.commitSelectedRow()`. The harness also adds the row query and `selectCommandBarRow`, so a
  test can move onto a row without pressing Enter, and every Enter in the class goes through the guard.
- The passing run uses `app.tables["commandBar.results"].tableRows.matching(identifier: "commandBar.row")`.
- Row exposure is in `CommandBarView.swift`. A Swift extension cannot override `NSTableView`'s accessibility methods.
  #283's diff was not copied. Sidebar and archive outline rows were not changed.
- The plan's fifth test, `test_E_noSearchCommitted`, is removed: it only exercised the UITests-target guard in
  `commitSelectedRow` (a real search would leave loopback), not app behavior. What Enter does on a Search row is
  asserted in process by `CommandBarTests.testArrowKeysMoveSelectionAndEnterSearches`, and the wrap test asserts
  that landing on the Search row commits nothing.
- BH-110 in the plan's steps is the Switch to Tab commit (bar closes, `Fixture alpha` stays selected, row count
  unchanged), not a separate sidebar-click check. The test follows those steps.

Known issues: #269 (sidebar outline rows are still missing out of process; the command bar rows in this class are
not), #283 (open; its `CommandBarView.swift` bridge was not copied).

### Review follow-up

- Bridge redesign above (`AXProxyRows`): the `MainThreadAX` helper and its `nonisolated(unsafe)` local are gone.
  Labels no longer depend on a row view existing, and frames are no longer captured at publish time.
- The removed `@objc accessibilityChildrenInNavigationOrder()` claimed the method is not overridable; it is a
  requirement of the `NSAccessibility` protocol since macOS 10.13. With the proxy table in place of the real table,
  no table override is needed for it.
- A first version kept the proxies under the real `NSTableView` behind nonisolated legacy
  `accessibilityAttributeValue` overrides. It did not compile: `MainActor.assumeIsolated` requires a `Sendable`
  result (`T: Sendable` in the Swift 6.2 and 6.3 standard library), and the proxy array is not `Sendable`
  (`NSAccessibilityElement` is neither `Sendable` nor main-actor isolated). The cached elements cannot leave
  main-actor state for a nonisolated caller without an unsafe annotation, so the bridge moved out of the table.
- Accessibility hit tests at a row's point still return the real table's views, not the proxy row.
  `accessibilityHitTest(_:)` comes from the nonisolated `NSAccessibility` protocol, and returning a cached proxy
  from it would need the same non-Sendable crossing. XCUITest's queries and key presses do not use it; VoiceOver's
  mouse tracking does. Follow-up if needed.
- In-process tests, `ShellKitGUITests/AXProxyRowsTests.swift`: rows beyond the visible range report the model's
  labels and build no row view; frames are the row's screen rectangle and follow a moved window and the moved
  command bar panel; `reloadData` publishes fresh proxies; children are flat leaves parented to the proxy table and
  follow selection; the command bar lists the proxy table instead of the scroll view.
- UI tests assert the named behavior without sidebar rows (#269): Switch to Tab shows alpha's address in the
  Toolbar's URL bar (the sidebar URL bar shows the host only, the same for every fixture page) with no second
  `/p/alpha` request; Cmd-Return and Opt-Return open delta in a new tab whose Back button is disabled, while the
  previous tab (navigated in place gamma -> epsilon) keeps Back enabled and is not loaded again. The Cmd-L prefill check runs in every case. Sidebar row checks are one combined
  `waitForOutlineRows` per test (none in the wrap test), so a test waits out the #269 timeout at most once; the run
  before this change spent 829 s on the class because every row wait timed out.
- Run times in the table above predate this follow-up. On CI at `ad7e157` (macos-26 runner, wait scale 3): wrap
  52 s, Cmd-Return 108 s, Opt-Return 106 s (each including the one 30 s #269 row wait), Switch to Tab 215 s (it
  failed there on the sidebar URL bar, fixed since). Most of the remaining time is launch plus typing three loopback
  addresses into the command bar; #269 removes the 30 s row wait.

## U12: Space switching (#177)

Base: `origin/main` at `46f3729`, branch `chore/177-space-switching`. Same machine as U0 (macOS 27.0, 26A428). Capacity
`nice -n 20`, `-jobs 2`. No Chromium build. Another UI test run held the GUI lock for part of the session.

### What was done

- `UITests/SpaceSwitchTests.swift`: the four key and dot tests, seeded from the Arc fixture (Alpha, then Beta), plus
  the swipe probe.
- The probe called `sidebar.page.scroll(byDeltaX: -400, deltaY: 0)` and waited 2 s for dot 2. It failed: the page was
  still Alpha and the Alpha dot was still selected. The synthesized scroll's `gesturePhase` was 0 and its horizontal
  delta was -400. `SpacePagerView.scrollWheel` ignores an event whose phase is empty, so the Space did not move.
  The test is now `XCTSkip("GS-001: XCUITest scroll has no gesture phases; manual check in #26")`.
- `UITests/parity-deferred.txt` (new): GS-001 and BH-040, both manual in #26. No Debug-only scripted swipe path.
  `SpacePagerView.swift` was not edited.
- Deviation: `test_BH036_switchingBackRestoresLastActiveTab` skips with `#269` while no outline row is in the
  accessibility tree, instead of `waitForOutlineRows`. The skip happened on this macOS 27 machine too: the Today row
  was not exposed (#269), and `waitForOutlineRows`'s expected-failure path returned and then left the app's event loop
  unmonitorable (the test still "passed" after 193 s, and after 435 s on a repeat). The skip finishes in the row
  timeout. If outline rows are exposed but the chosen row is missing, the test fails instead of skipping. The restore
  assertion itself did not run here; it runs unchanged once #269 exposes the rows.
- Cmd-Opt arrows also check that a further arrow at either end stays put. Wrap is #98 and is not asserted.
- Keys that must change nothing (Ctrl-9 with two Spaces, a further arrow at either end) are each followed by a key
  that does switch (Cmd-Opt-Right after Ctrl-9; the opposite arrow after an end arrow), and the test waits for that
  switch before asserting. Menu key equivalents run in order, every switch goes through `SpacePagerView.go(to:)`
  (which stops a running settle), and the arrows count from the target of a running switch, so a late switch from the
  no-op key cannot land after the check. No fixed waits. The other Space's page is checked by waiting until it is
  gone: at rest the pager hides every page but the current one, and hidden pages leave the accessibility tree.
- Precondition, not handled by the harness: Ctrl-1 and Ctrl-2 must not be bound to Mission Control's "Switch to
  Desktop 1" / "Switch to Desktop 2" (System Settings > Keyboard > Keyboard Shortcuts > Mission Control) on the Mac
  running the tests; where they are, the system takes the key and the Ctrl-N waits time out. The tests do not change
  OS settings.

### Tests

| Test | Parity | Result |
|---|---|---|
| `test_KB035_BH041_ctrlNumberGoesToSpace` | KB-035, BH-041 | passed (76.5 s; the seed launch waited about 60 s to become idle, then the keys took about 8 s) |
| `test_KB033_KB034_cmdOptArrowsMoveBetweenSpaces` | KB-033, KB-034 | passed (16.2 s) |
| `test_BH035_spaceDotClickSelectsSpace` | BH-035 | passed (11.1 s) |
| `test_BH036_switchingBackRestoresLastActiveTab` | BH-036 | skipped, #269 (17.1 s) |
| `test_GS001_twoFingerSwipeMovesSpace` | GS-001, BH-040 | skipped, #26 (0.2 s) |

These results are from the run before the sync points and the narrower BH-036 skip were added; that revision has not
been rerun on a Mac yet.

### Verification

```zsh
cd app/ArktShell && xcodegen generate
nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests \
  -derivedDataPath build -jobs 2 \
  -resultBundlePath build/ui-1792870504.xcresult \
  -collect-test-diagnostics never -parallel-testing-enabled NO \
  -only-testing:ArktShellUITests/SpaceSwitchTests test
```

`** TEST SUCCEEDED **`. Executed 5 tests, with 2 tests skipped and 0 failures (0 unexpected) in 121.1 s.
`Check UI test sources` on `app/ArktShell/UITests`: `UI test sources OK`.

Known issues used: #269 (outline rows), #26 (swipe phase).

## U16: Parity report (#181)

Base: `origin/main` at `46f3729`, branch `chore/181-parity-report`. Step 6 (promotion to a required check) is not in
this change.

### What was done

- `scripts/ui-tests/parity-report.sh` reads the spec with `grep -oE '^\| (KB|BH|GS)-[0-9]{3} '` (346 rows), the test
  results from `xcrun xcresulttool get test-results tests`, and `app/ArktShell/UITests/parity-deferred.txt`. It
  prints counts per section (1.x, 2.x, 3) and status, the rows with a deferred part, the five slowest tests (name, the
  `duration` string and `durationInSeconds`), then the failing rows, the deferred rows with issue links, and
  NEEDS-RUNTIME-CHECK rows that pass ("passing [I]"). `jq` is taken from `PATH`; without it the script says so.
- Deferred file format: `ID<TAB>reason<TAB>#issue` defers the whole row; `ID (part)<TAB>reason<TAB>#issue` defers one
  part of it. The spec has no sub-ids and the plan names parts in the U9 mapping ("BH-087 (part)", "BH-087 (search)"),
  so the part lives in the deferred file rather than in a split spec row (which would change the spec's 346 rows). A
  row with a deferred part is classified by its tests as usual and its part is always listed under Deferred with the
  row's own result, so a passing U9 test for the restore half of BH-087 cannot hide #111.
- Precedence: any `Failed` observation fails the row; every naming test `Passed` passes the row, including a row whose
  whole line is still in the deferred file; a whole deferred-file row that is not fully passing is deferred; skipped
  tests and expected failures are deferred; a mix of passes and skips or expected failures is deferred, because
  passing requires every naming test to pass. Anything else with no test is not covered.
- Observations: every leaf `Test Case Run` or `Repetition` node under a Test Case (a run node with no run node below
  it) is one observation with its own result, so one failed iteration fails the row; a case with no run nodes is one
  observation. The slowest list keeps one duration per test: the longest single leaf run, else the case value, so
  repetitions are never added up.
- Issue links come only from skip and expected-failure reasons: in the CI bundle (Xcode 26.6) an "Expected Failure"
  test carries one `Failure Message` node per matched `XCTExpectFailure`, named by its reason, and no "Expected
  Failure" node. The issue is the reason's leading `#N:` or its final `#N` / `(#N)` (the plan's `XCTSkip("#111: ...")`,
  `XCTSkip("flaky: #NNN")`, "manual check in #26", and the harness's "... (#269)"). Failure text of a failed test and
  the test name are never read, so a `#N` quoted in an assertion is not linked as the row's issue.
- Exit status: non-zero only on malformed input. That includes test names that cite a row id the spec does not have
  (for example `KB850`): the report is still printed, those ids are listed under "Unknown row ids" and on stderr, and
  the script exits 1. The informative job then shows red while `continue-on-error` keeps it out of the run's result,
  as the plan defines for this job; the upload step still runs (`!cancelled()`). Failing rows never fail the script.
  A failed `xcresulttool` call prints its stderr. A skipped or expected-failure test whose reason names no issue gets
  a note on stderr with its nodes.
- Deferred file, 25 rows: KB-031 and KB-032 (#119); GS-001 and BH-040 (#26: U12's swipe probe failed because
  XCUITest's scroll has gesture phase 0, recorded in U12, #177, not merged yet); BH-087 search part only (#111);
  BH-069 (#85); the U15 split rows KB-070 to KB-075, BH-115, BH-116, BH-117, BH-120, BH-121, BH-122, BH-123, BH-125,
  BH-128, GS-010, GS-011, GS-032, GS-033 (#54 to #58, matching the U15 test table; GS-010 is #57). BH-118, BH-119,
  BH-124, BH-126 and BH-127 stay not covered.
- `.github/workflows/swift-tests.yml`, `ui-tests` job: a first step runs `scripts/ui-tests/parity-report-test.sh`;
  after the UI test step, if the job was not cancelled, the report goes to the job summary, the job log and
  `parity-report.md`, which is uploaded with the `.xcresult`. On failure, attachments are exported and uploaded.
  `continue-on-error` stays, and `ui-tests` stays out of the gate.

### Script tests

`scripts/ui-tests/parity-report-test.sh` runs the script on synthetic fixtures in
`scripts/ui-tests/parity-report-fixtures/` (an 11-row spec, a deferred file with two partial rows and one whole row, and
three bundles) with a stub `xcrun` on `PATH`. It checks: the counts; a passing row with a deferred part listed under
Deferred with result `passing` and its issue; issues from a leading `#N:`, `flaky: #N`, "manual check in #N" and the
harness's `(#269)`, and none from a failed test's message or from mid-text `#N`; a failed repetition failing its row and
the slowest list using one repetition, not the case sum; unknown ids in the report and on stderr with a non-zero exit;
`xcresulttool` stderr on failure; the missing-`jq` message; and deferred-file errors for a row deferred both whole and
in part, or an empty part. Run locally (zsh 5.9, jq 1.7): all checks passed; against the pre-change script: 25 failures.
CI step "Parity report script tests" passed on macOS 26.

### CI run

Run 40191934579, job `UI tests (informative)` at `59e9cc8` on the `macos-26` runner, Xcode 26.6: `** TEST SUCCEEDED **`,
18 tests, 0 failures, `Executed 18 tests ... in 521.438 (521.466) seconds`; xcodebuild reports 527.640 s for testing.
The `xcodebuild test` step (build and test) took 10 min 28 s (12:16:35 to 12:27:03 UTC), the job 10 min 56 s.

Report from that run (job log, step "Parity report", exit 0), counts:

| Status | Rows |
|---|---:|
| Passing | 6 (KB-003, KB-018, KB-084, BH-031, BH-103, GS-042) |
| Failing | 0 |
| Deferred | 31: the 24 whole rows of the file, and KB-001, KB-002, KB-004, BH-032, BH-100 to BH-102 (#269) |
| Not covered | 309 (BH-087 among them; its search part is listed as deferred, #111) |
| Total | 346 |

Passing [I]: KB-084. No unknown row ids.

Slowest five, as printed:

```
`test_BH032_backForwardEnabledFollowsHistory()` 1m 29s (89.2746160030365s)
`test_KB002_BH101_cmdLEditedEnterNavigatesCurrentTab()` 1m 19s (79.13402307033539s)
`test_KB001_BH100_cmdTOpensURLInNewTodayTab()` 1m 18s (78.18275904655457s)
`test_KB004_BH102_cmdLUneditedEnterReloads()` 48s (48.44455802440643s)
`test_E_cmdTWithNoSpaceCreatesSpaceThenTab()` 47s (47.1280460357666s)
```

The four slowest each include one or two 30 s outline-row waits that end as the #269 expected failure. The earlier
run at `d2e7c47` (run 40125570080) had the same 18 tests in 530.369 s and the same five slowest tests (KB-001 and
KB-002 in the other order).

The bundle had no `Test Case Run` or `Repetition` nodes (one iteration). How xcresulttool nests runs from
`-test-iterations` or `-run-tests-until-failure` was not seen in a real bundle; the leaf-run handling follows the node
types `Test Case Run` and `Repetition` and is covered by the fixture only. Skip reasons were not seen either (the suite
has no skipped test yet); they are read from `Failure Message` nodes the same way. Local suite wall time was not
measured.

Promotion still waits on 10 green `UI tests (informative)` runs on `main`, one local
`-test-iterations 20 -run-tests-until-failure` run with no failure, and a maintainer decision in #161.

### Deviations from the plan

- Step 6 is not done: `continue-on-error` is unchanged, the job is not in the gate, and CONTRIBUTING.md is not edited.
- Wall time and the slowest five come from CI only; no local full-suite run.
- A mix of passed and skipped or expected-failure tests is deferred. The plan states passing as every test passed, and
  deferred as only skipped tests or a deferred-file row; the mix is neither passing nor failing.
- The deferred file supports one part of a row (`BH-087 (search)`), which the plan's `ID<TAB>reason<TAB>#issue` format
  does not spell out; the plan's U9 mapping and step 1 ("BH-087 search") name the part.
- Test names citing a row id outside the spec count as malformed input and exit 1 after the report is printed.
- GS-001 and BH-040 are in the deferred file before U12 merges; U12's probe failed as the plan describes.

### Parity rows and a local run on current main (2026-10-26)

Base: `origin/main` at `98a8445`, branch `chore/181-parity-report`. The counts above were taken when the suite had 18
tests and #54 to #58 and #111 were open. It now has 45 tests, those issues are closed, and U16's deferred rows were
checked one by one against `main`.

Deferred rows: 25, none added and none dropped. None of the 25 ids has a passing naming test in
`app/ArktShell/UITests` (`grep -rn "func test_"`): 24 have no naming test at all, and GS-001's only one,
`test_GS001_twoFingerSwipeMovesSpace`, skips itself (#26). So every line still records a real gap.

| Rows | Was | Now | Why |
|---|---|---|---|
| KB-031, KB-032 | #119, "not bound" | #119, reason corrected | `MainMenu.historyItems` now binds Cmd-[ and Cmd-] (#294); Cmd-Left / Cmd-Right stay out of the menu on purpose (the comment there), and no UI test names either row |
| 19 split rows: KB-070 to KB-075, BH-115 to BH-117, BH-120 to BH-123, BH-125, BH-128, GS-010, GS-011, GS-032, GS-033 | #54 to #58 (closed) | #180 | S4 to S8 shipped, but `UITests/` has no `SplitViewTests.swift`; #180 (U15) is the open task that owns those tests |
| BH-087 (search) | #111 (closed), "not implemented" | #174 | Archive search shipped in #111; the U9 archive UI tests (#174) are not written |
| BH-069, GS-001, BH-040 | #85, #26 | unchanged | Issues open, gap unchanged |

Skip reasons: Xcode 27.1 (local) reports `XCTSkip` as a `Skip Message` node, Xcode 26.6 (CI) as a `Failure Message`
node. The script read only `Failure Message`, so a local run printed the "names no #issue" note for
`test_GS001_twoFingerSwipeMovesSpace()` even though its reason ends in `#26`. `reasons_in` now reads `Skip Message`
for a skipped test as well (expected failures stay `Failure Message`), and the fixture's `GS-002` uses a `Skip
Message` node so `parity-report-test.sh` fails without the fix.

### Local run

Apple M2 Pro, macOS 27.0 (26A428), Xcode 27.1, built-in 3024 x 1964 display. `xcodegen generate`, then:

```zsh
TEST_RUNNER_ARKT_UITEST_TIMEOUT_SCALE=3 xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests \
  -derivedDataPath build -resultBundlePath build/ui-1793028533.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

`** TEST SUCCEEDED **`, 45 tests, 1 skipped (`test_GS001_twoFingerSwipeMovesSpace`, #26), 0 failures:
`Executed 45 tests, with 1 test skipped and 0 failures (0 unexpected) in 960.918 (960.964) seconds`; xcodebuild
reports 962.287 s of testing and 16 min 42 s wall time including the build.

`scripts/ui-tests/parity-report.sh` on that bundle exited 0, with the refreshed deferred file:

| Status | Rows |
|---|---:|
| Passing | 27 |
| Failing | 0 |
| Deferred | 24 |
| Not covered | 295 |
| Total | 346 |

One row has a deferred part (BH-087, search). Passing [I]: KB-084 and KB-085, all three of KB-085's tests. No unknown
row ids, and no "names no #issue" note after the `Skip Message` fix.

Slowest five:

```
`test_KB085_optEnterOpensURLInNewTab()` 1m 14s (74.15589594841003s)
`test_KB085_cmdEnterOpensURLInNewTab()` 1m 11s (71.94246995449066s)
`test_onboarding_arcBranchImportsAndLandsInTheBrowser()` 1m (60.7766010761261s)
`test_BH104_BH110_switchToTabRow()` 55s (55.702857971191406s)
`test_E_issue301_newEmptySpaceClearsContentAndRestoresLiveTab()` 51s (51.48850703239441s)
```

### CI run and promotion status

Run 40329967087 at `main` (`Persist the sidebar width and hidden state per window`), `macos-26` runner, Xcode 26.6:
`** TEST SUCCEEDED **`, 45 tests, 1 skipped, 0 failures, `Executed 45 tests ... in 999.241 (999.291) seconds`. The
`xcodebuild test` step took 18 min 38 s (14:10:32 to 14:29:10 UTC) and the job 19 min 11 s, inside the 40 min job
timeout and the plan's 20 min suite budget. Its report has the same counts as the local run (27 / 0 / 24 / 295 / 346)
and the same passing [I] rows; the slowest five there were `test_KB085_cmdEnterOpensURLInNewTab` 84.1 s,
`test_KB085_optEnterOpensURLInNewTab` 82.9 s, `test_BH104_BH110_switchToTabRow` 66.7 s, `test_KB085_downWrapsFromLastToFirst` 57.2 s
and `test_onboarding_arcBranchImportsAndLandsInTheBrowser` 57.1 s.

Promotion, as of this run: the `UI tests (informative)` job has been green on 26 consecutive completed runs on
`main`, from 40280792149 (06:36 UTC) to 40334727687 (13:54 UTC). It is not green by construction: 40277908550 at
06:06 UTC reported a failed job, so `continue-on-error` does not hide a failed suite. The local 20-iteration run
(`-test-iterations 20 -run-tests-until-failure`) and the maintainer decision in #161 remain; this change does not
remove `continue-on-error`, does not add `ui-tests` to the gate and does not edit `CONTRIBUTING.md`.

## U13: Import from Arc (#178)

Base: `origin/main` at `46f3729`, branch `chore/178-arc-import-ui`. Lands after #289: it merges
`chore/176-command-bar-keys` for the shared `AXProxyRows` bridge.

### What was done

- `UITests/ArcImportTests.swift`: the plan's 5 tests. Every test checks the Arc copy it launched against (the rendered
  copy's SHA-256, or an empty directory when Import must stay disabled). Each import checks the summary sheet's
  counts of what it wrote (`ArcImportSummary.lines`, read from the sheet's static text) before pressing OK.
- Archive counts are the number of `archive.row` rows under `archive.table` (`tableRows`, scoped to the Archive
  window). Favorite tiles are `favorites.tile` buttons under the `favorites.grid` group, not a whole-app
  `descendants` query (that walks the web view and can stall a wait, #289).
- Menus are opened once and acted on: one click on File (or Window), a wait until the item is hittable in the open
  menu, then a click or Escape. Nothing is clicked or typed inside a wait predicate. No fixed waits.

### Tests

| Test | Parity | What it asserts |
|---|---|---|
| `test_E_importFromEmptyState` | none (E4c / E6) | sheet: 2 Spaces, 2 favorites added, 7 new archived items; 2 dots, 2 tiles, 7 Archive rows |
| `test_E_importFromFileMenu` | none | menu enabled once the empty state offered the import; same sheet counts; 3 dots |
| `test_E_reimportIsIdempotent` | none | second sheet: 0 new Spaces, 0 favorites added, 0 new archived items; 2 dots, 2 tiles; the Archive, first opened after the re-import, lists 7 rows |
| `test_E_importMenuDisabledWithoutArcData` | none | menu item disabled, no empty-state import button, Arc directory still empty |
| `test_BH045_BH034_importedSpacesShareFavorites` | BH-045, BH-034 | the same tile labels after Ctrl-2 selects Space 2 |

The re-import test opens the Archive window for the first time after the re-import. The window keeps its rows while
hidden and `show()` reloads asynchronously, so a window opened before the re-import would show the old count until
the reload lands and a count wait could pass on stale rows. A window created after the re-import applies one page
with the count after both imports: a duplicated archive shows 14 rows, never 7.

The disabled-menu test has no positive sync for the availability check. Availability starts false and the check can
only set it true when `StorableSidebar.json` exists, and the test asserts the Arc directory is empty, so the menu
state it reads is the same before and after the check. The previous inverted 2 s wait is removed (the plan allows a
fixed wait only in U14 test 5).

### Verification

The first version of this pull request passed locally (5 tests, 0 failures, 79.504 s, macOS 27.0 arm64, bundle
`app/ArktShell/build/ui-u13-1792879044.xcresult`). That run predates the changes below; CI on the new head commit
(`UI tests (informative)`, `ShellKit GUI tests (informative)`) has the current results. The pure suites were run by
CI on every push: on `215fa3e`, `ArktCore tests`, `ShellKit tests`, `Isolation greps` and `App build (Debug)`
passed. `ShellKit GUI tests (informative)` failed there only in
`SplitSidebarTests.testOptClickMouseDownOnASplitRowSeparatesIt` (#277), which this change does not touch.

### Deviations

Production changes the plan did not list:

- `ShellUI/Archive/ArchiveWindowController.swift`: `ArchiveTableView` publishes its rows through the shared
  `AXProxyRows` (#289) with content from the loaded page: label = title, value = "place and date, reason" (what the
  cell reads, #91). A new `ArchiveContentView` (a group) lists the proxy `archive.table` in place of the scroll view
  that holds the real table, as `CommandBarView` does. No row view is built for accessibility, and the table has no
  accessibility value (an earlier revision set a test-only `rows N`, created every row view on every reload and
  bridged legacy attributes through a `nonisolated(unsafe)` local; all three are gone).
- `ShellUI/Sidebar/FavoritesGridView.swift`: product fix. A Favorites batch insert while the collection view had no
  size (an empty grid is 0 pt tall, so an Arc import into an empty profile hits it) left no tiles after the grid was
  sized. CI evidence (diagnostic run on `5468834`): after the resize the collection view had the grid's frame, its
  data source's 4 items and a prepared rect covering its bounds, but its layout's content size was still
  `(174, 0)`, 0 visible items and `item(at:)` nil, also after a run-loop turn and a second layout pass; a
  `reloadData` from outside the layout pass fixed it (content `(174, 101)`, 4 visible items). A reload issued from
  the grid's `layout()` did not (run `c400aa7`). So `apply(structure:)` now reloads the collection view, in the model
  change, when it has no size, instead of batch-updating it. In-process test:
  `SidebarViewTests.testFavoritesAddedWhileTheGridHasNoSizeGetTiles` (layout content height, visible items, tiles
  with titles, grid accessibility children).
- Same file, accessibility: `NSCollectionView`, like `NSTableView`, answers children out of process from its own
  internals, so the collection view is no longer an accessibility element and the `favorites.grid` group (a plain
  view) lists the existing tile views itself; the tiles report the grid as their parent. This is #289's pattern
  (the container lists the elements); the tiles are real views (close button, Close action), so no proxy and no
  change to `AXProxyRows.swift` is needed. Nothing creates an item, reloads or lays out from an accessibility call.
- In-process test for the Archive rows: `ArchiveWindowTests.testAccessibilityRowsComeFromThePageWithoutRowViews`.

In-process accessibility tests assert through the protocol getters (`accessibilityChildren()`,
`accessibilityRows()`, ...); the legacy `accessibilityAttributeValue` returns nil in process for these elements, so
out-of-process proof is the UI tests job.

Known issues used: #277 (unrelated GUI-test flake).

## #269: Sidebar outline rows out of process

### What was done

- Root cause: `NSOutlineView` (like `NSTableView`) answers `AXChildren` / `AXRows` out of process from its own
  internals. The overrides that returned the realized row views answered in-process callers only, so on the
  macos-26 runner XCUITest saw an `Outline` with no children. A diagnostic run on the runner showed the command bar
  table (same override pattern) with no rows either.
- The Space page lists a proxy outline (`sidebar.outline`, `AXProxyRows`, shared with U11) in place of the scroll
  view: one proxy row per displayed row, read from the model on every query (identifier, label, `Closing` value,
  disclosure level, expanded state, selection from the row state, VoiceOver actions, the realized cell as child).
- `waitForOutlineRows` is a plain `Waits.until`; the #269 `XCTExpectFailure` wrapper is removed.

### Verification

- CI run 40206251471 (`0da8044`, macos-26, Xcode 26.6): UI tests 22 passed, 0 failed, among them
  `LaunchTests.test_E_seededLaunchShowsImportedSpaces` and `LoopbackPageTests.test_E_loopbackPageLoadsInTheEngine`,
  with every row wait plain.
- One expected failure, scoped to one assertion: the order check of `test_KB001_BH100_cmdTOpensURLInNewTodayTab`.
  Cmd-T appends to Today; the plan above expects the top and the spec leaves it open (BH-079, CF-27). Tracked in
  #293.

## U14: Quit, relaunch, recovery (#179)

Base: `origin/main` at `46f3729`, branch `chore/179-quit-relaunch`. Local run on 2026-10-24
(macOS 27.0, Xcode 27.1, Apple M2 Pro). `ARKT_UITEST_TIMEOUT_SCALE` was unset.

### What was done

- `UITests/PersistenceTests.swift`: the plan's 5 tests. No production files changed. Quit flush, the
  debounce override, the default debounce, both recovery toasts, and a persistent toast surviving Cmd-T then Esc
  were already in the app.
- The debounce test sets `ARKT_AUTOSAVE_DELAY_MS=600000` (the largest value `EnvironmentOverrides` accepts) on
  the first launch and clears it before the relaunch. Between the model change and Cmd-Q there is no row probe:
  once the sidebar URL bar shows the loopback host, the test captures the size and modification date of
  `data/Arkt.sqlite`, asserts the file does not contain the alpha address, and asserts the size and date are
  unchanged immediately before Cmd-Q. The database uses a rollback journal, so a debounced write would change that
  file. Only the termination flush can save the change.
- `ArktUITestCase.quit` takes an optional `timeout` (seconds before scaling); test 1 passes 5.
- The one fixed wait is the inverted expectation in `test_E_toastStaysUntilDismissed` (2 s, unscaled), commented
  there as the absence assertion.

### Tests

| Test | Run time |
|---|---|
| `test_E_quitInsideAutosaveDebounceKeepsChange` | 37.781 s |
| `test_E_quitAtDefaultDebounceKeepsChange` | 25.544 s |
| `test_E_corruptDatabaseWithoutBackupShowsRecreatedToast` | 30.568 s |
| `test_E_corruptDatabaseWithBackupShowsRestoredToast` | 48.624 s |
| `test_E_toastStaysUntilDismissed` | 33.972 s |

### Verification

`Check UI test sources` on `app/ArktShell/UITests`: `UI test sources OK`, exit 0.

```
cd app/ArktShell
nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests \
  -derivedDataPath build -resultBundlePath build/ui-1792873897.xcresult \
  -collect-test-diagnostics never -parallel-testing-enabled NO -jobs 2 \
  -only-testing:ArktShellUITests/PersistenceTests test
```

Exit 0. `** TEST SUCCEEDED **`. Executed 5 tests, with 0 failures (0 unexpected) in 176.488 (176.492) seconds.
Only `PersistenceTests` ran. CoreSimulator "out of date" (1171.7.0 vs 1174.9.2) was logged and did not fail the run.

On this run the Today row predicate completed for every `Fixture alpha` check. These timings and this run are
for commit `986f251`, before the review fixes below; the fixes were not run on a Mac by their author.

CI on `986f251` (run 40130722270, job "UI tests (informative)", macos-26, scale 3): 23 UI tests, 0 failures
(0 unexpected), `** TEST SUCCEEDED **`, all 5 `PersistenceTests` passed. Rows were missing (#269) and the URL bar
held the loopback host after every relaunch. The notification dialog query found no dialog in any of the 5 tests.

### Review fixes

- Row checks go through `waitForOutlineRows` (expected failure while #269 hides the rows, the `Fixture alpha`
  title assertion where they are exposed). The sidebar URL bar containing `127.0.0.1` is asserted every time in
  addition. On `986f251` they bypassed it because recording the expected failure hung in-process symbolication
  on the local Mac; that does not happen on CI, where the other suites record that expected failure, and where
  the rows are exposed (macOS 27) nothing is recorded.
- `dismissNotificationPermission` is gone. Nothing in the app requests notification authorization: no
  `UserNotifications` import, no `UNUserNotificationCenter`, `NSUserNotification`, `requestAuthorization`, no
  `WKUIDelegate` on the FakeEngine web view, and the fixture pages have no script. The CI run above found no
  dialog. The origin of the dialog seen on the local macOS 27 Mac is not known; clicking Don't Allow wrote a
  decision outside the sandbox for whichever app owned the prompt, so the tests no longer touch it. If it appears again, the test fails
  and the dialog's owner process and text belong in an issue.
- The `launchEnvironment` assertions (which only read the harness's own input) are removed.

### Deviations from the plan

- The backup wait requires a finished `Arkt-*.sqlite`, not the `.tmp` written first.
- Test 1 waits for `.notRunning` within 5 s times the scale (`quit(app, timeout: 5)`). The other tests use the
  default (10 s). Test 2 calls `quit` immediately after Enter. `quit` still activates and waits for foreground
  before the key, so the key stays on this app.
- `toast.action` is matched by identifier on any element, and "Show Files" is accepted as `label` or `title`.
  Out of process the button exposes those words as its title. It is never clicked.

Known issues used: #269 (outline rows).

## U9: Archive scenarios (#174)

Added UI coverage for hover X, Cmd-W, the last Today tab, the Archive menu and restoring a tab with its View toast.
The search scenario remains an explicit skip as specified by U9, although #111 is now closed. The in-process menu
inventory checks the empty key equivalent because XCUITest exposes the menu title but not its key equivalent.

Checks after updating to main at `7940026`:

- `cd app/ArktCore && nice -n 20 swift test -j 2 --scratch-path /private/tmp/arkt-174-core`: 428 tests in 29 suites passed.
- `cd app/ArktShell/ShellKit && nice -n 20 swift test -j 2 --scratch-path /private/tmp/arkt-174-shell --skip ShellKitGUITests`: 1,287 tests in 162 suites passed.
- `cd app/ArktShell/ShellKit && nice -n 20 swift test -j 2 --scratch-path /private/tmp/arkt-174-shell --filter MainMenuInventoryTests/testShellItemsAndTheirKeys`: 1 test, 0 failures.
- `cd app/ArktShell && nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests -derivedDataPath /private/tmp/arkt-174-derived -resultBundlePath /private/tmp/arkt-174-ui-latest.xcresult -collect-test-diagnostics never -jobs 2 -only-testing:ArktShellUITests/ArchiveTests test`: 6 tests, 1 skipped, 0 failures.

The initial UI run failed the restore case because clicking the accessibility proxy row did not select it, and the
menu case queried the label instead of the title. The test now confirms selection and enabled state, using Down if
needed, and reads the menu title. A targeted rerun of the two corrected tests passed, 2 tests, 0 failures. The first
build under Desktop could not be signed because of Finder metadata; using temporary derived data resolved that.
No product code changed. The full ShellKit GUI suite and full XCUITest suite were not run; the changed menu test and
all U9 scenarios were run directly. No screenshot is needed for test-only changes.

The menu assertion was checked against a deliberate regression: temporarily assigning `x` to Show Archive in
`MainMenu.swift` made the targeted menu test fail (1 test, 1 failure); restoring the original empty key made it pass
again (1 test, 0 failures). The temporary change was not committed.

## U10: Favorites close and pinned rows (#175)

Added `app/ArktShell/UITests/FavoritesAndPinnedTests.swift` for the four plan cases. Seed is `seedFromArcFixture`.
BH-070 carries `PARITY(NEEDS-RUNTIME-CHECK RT-17)`. No product code changed. Archive rows, the archive footer and
sidebar outline rows are read once; a missing `favorites.tile` or `sidebar.row.pinned` would skip for #269 rather
than poll. That path was not reached.

The first `xcodebuild` of `ArktShellUITests/FavoritesAndPinnedTests` failed to compile: `wikiPath` inside the server-log
closure needed a local copy. A later run started all four tests and failed before launch because another Debug
`ArktShell` (`dev.arkt.Arkt`, pid 56398) was already running. That process was not quit. After it had exited, the
class-only run passed. Favorites tiles and pinned rows were present, so the #269 skip was not used.

`xcodebuild -project ArktShell.xcodeproj -scheme ArktShellUITests -derivedDataPath build -jobs 2 -collect-test-diagnostics never test -only-testing:ArktShellUITests/FavoritesAndPinnedTests`:

Executed 4 tests, with 0 failures (0 unexpected) in 111.307 (111.313) seconds. TEST SUCCEEDED.

- `test_BH048_cmdWOnFavoriteDoesNotArchive` passed (25.884 seconds)
- `test_BH048_GS043_favoriteXClosesPageKeepsTile` passed (26.183 seconds)
- `test_BH067_cmdWOnPinnedTabKeepsPin` passed (28.485 seconds)
- `test_BH070_pinnedHoverXCloseAndKeepPinned` passed (30.755 seconds)

`cd app/ArktShell/ShellKit && swift test -j 2 --skip ShellKitGUITests` was not run. ShellKit production and ShellKit
tests were not changed. ArktCore was not run for the same reason.
