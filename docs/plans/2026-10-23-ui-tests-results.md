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

## U16: Parity report (#181)

Base: `origin/main` at `46f3729`, branch `chore/181-parity-report`. Step 6 (promotion to a required check) is not in
this change.

### What was done

- `scripts/ui-tests/parity-report.sh` reads the spec with `grep -oE '^\| (KB|BH|GS)-[0-9]{3} '` (346 rows), the test
  results from `xcrun xcresulttool get test-results tests`, and `app/ArktShell/UITests/parity-deferred.txt`
  (`ID<TAB>reason<TAB>#issue`). It prints counts per section (1.x, 2.x, 3) and status, then the five slowest tests
  (name, the Test Case `duration` string, and `durationInSeconds`), then the failing rows, the deferred rows with
  issue links, and NEEDS-RUNTIME-CHECK rows that pass ("passing [I]"). Exit status is non-zero only for malformed
  input. A test with no numeric duration is left out of the slowest list. A Test Case duration wins over its runs;
  otherwise the longest Test Case Run is kept.
- Precedence: any `Failed` test fails the row; every naming test `Passed` passes the row, including a row still listed
  in the deferred file; a deferred-file row that is not fully passing is deferred; skipped tests and expected failures
  are deferred; a mix of passes and skips or expected failures is deferred, because passing requires every naming test
  to pass. Anything else with no test is not covered.
- Deferred file, 25 starter rows: KB-031 and KB-032 (#119); GS-001 and BH-040 (#26; U12 has not landed on this branch);
  BH-087 (#111); BH-069 (#85); the U15 split rows KB-070 to KB-075, BH-115, BH-116, BH-117, BH-120, BH-121, BH-122,
  BH-123, BH-125, BH-128, GS-010, GS-011, GS-032, GS-033 (#54 to #58, matching the U15 test table; GS-010 is #57).
  BH-118, BH-119, BH-124, BH-126 and BH-127 stay not covered.
- `.github/workflows/swift-tests.yml`: after the UI test step, if the job was not cancelled, the script appends the
  report to the job summary and `parity-report.md` is uploaded with the `.xcresult`. On failure, attachments are
  exported and uploaded. `continue-on-error` stays, and `ui-tests` stays out of the gate.

### Classifier run

No UI suite xcresult. Both swift slots and the GUI lock were already held, so this check did not build or launch the
app. The script was run against the real spec and the real deferred file. `xcrun xcresulttool get test-results tests`
was given a JSON document in schema 0.4.0 (`Test Case` nodes; one row also nested a `Test Case Run`) instead of a
bundle from `xcodebuild`.

Fixture cases: `test_KB001_BH100_passes` Passed; `test_KB084_passes` Passed; `test_KB018_fails` Failed;
`test_KB002_BH101_skipped` Skipped (`#172`); `test_KB070_BH116_skipped` Skipped; `test_KB030_expected` Expected Failure;
`test_KB004_passes` Passed and `test_KB004_skipped` Skipped; `test_BH032_passes` Passed and `test_BH032_fails` Failed;
`test_GS042_passes` Passed; `test_E_infra` Passed (no row).

Command: `scripts/ui-tests/parity-report.sh <fixture> docs/spec/arc-parity-spec.md app/ArktShell/UITests/parity-deferred.txt`

Exit code 0 (the two failing rows do not fail the script).

| Section | Passing | Failing | Deferred | Not covered | Total |
|---|---:|---:|---:|---:|---:|
| 1.1 Tabs, windows, sidebar, navigation (global) | 1 | 1 | 5 | 36 | 43 |
| 1.2 App, page, tools | 0 | 0 | 0 | 26 | 26 |
| 1.3 Split View | 0 | 0 | 6 | 0 | 6 |
| 1.4 Peek, Little Arc, command bar, PiP | 1 | 0 | 0 | 13 | 14 |
| 2.1 Sidebar | 0 | 1 | 0 | 32 | 33 |
| 2.2 Spaces | 0 | 0 | 1 | 10 | 11 |
| 2.3 Favorites | 0 | 0 | 0 | 9 | 9 |
| 2.4 Pinned tabs | 0 | 0 | 1 | 16 | 17 |
| 2.5 Today and Archive | 0 | 0 | 1 | 18 | 19 |
| 2.6 Folders | 0 | 0 | 0 | 10 | 10 |
| 2.7 Command bar | 1 | 0 | 1 | 13 | 15 |
| 2.8 Split View | 0 | 0 | 9 | 5 | 14 |
| 2.9 Little Arc | 0 | 0 | 0 | 15 | 15 |
| 2.10 Peek | 0 | 0 | 0 | 11 | 11 |
| 2.11 Air Traffic Control | 0 | 0 | 0 | 7 | 7 |
| 2.12 Links and clicks | 0 | 0 | 0 | 8 | 8 |
| 2.13 Windows, Incognito, Profiles | 0 | 0 | 0 | 10 | 10 |
| 2.14 Downloads and Library | 0 | 0 | 0 | 3 | 3 |
| 2.15 Media and Picture in Picture | 0 | 0 | 0 | 7 | 7 |
| 2.16 Toasts and notifications | 0 | 0 | 0 | 8 | 8 |
| 2.17 Settings and shortcut system | 0 | 0 | 0 | 16 | 16 |
| 3. Mouse, trackpad and modifier-click gestures | 1 | 0 | 5 | 38 | 44 |
| Total | 4 | 2 | 29 | 311 | 346 |

Passing is KB-001, BH-100, KB-084, GS-042. Failing is KB-018, and BH-032 (one pass and one fail). Deferred adds KB-002,
BH-101 (skip only), KB-030 (expected failure) and KB-004 (pass and skip) to the 25 file rows. Passing [I] is KB-084
only. A second run that also passed `test_KB031_passes` reported 5 passing, 2 failing, 28 deferred, 311 not covered:
KB-031 left the deferred list.

Malformed input exits non-zero: missing arguments, missing spec, a spec status other than CONFIRMED / SINGLE-SOURCE /
NEEDS-RUNTIME-CHECK, a deferred id that is not a spec row, a duplicate deferred id, a reason containing `|`, an issue
that is not `#N`, and a deferred line with the wrong number of fields. An empty deferred file is accepted and still
fails later when the xcresult cannot be read.

The full UI suite was not run. `/tmp/arkt-gui-lock` was held, so this check did not start a second `xcodebuild`. CI
wall time is still unmeasured.

Slowest five and the only measured elapsed time come from a completed partial bundle another issue already wrote:
`177-space-switching/app/ArktShell/build/ui-1792868138.xcresult` (`ArktShellUITests/SpaceSwitchTests`, five tests).
`xcrun xcresulttool` 25115, schema 0.4.0. Each Test Case node has `duration` (string) and `durationInSeconds` (number).
Observed Test Case keys: `children`, `duration`, `durationInSeconds`, `name`, `nodeIdentifier`, `nodeIdentifierURL`,
`nodeType`, `result`. That bundle has no Test Case Run nodes. `get test-results summary` reports `startTime`
1792868139.378 and `finishTime` 1792868456.992, an elapsed 317.614 seconds for this SpaceSwitchTests run.

Command: `scripts/ui-tests/parity-report.sh /Users/slovik/Desktop/Codewrabler/Projekty/arkt-wt/177-space-switching/app/ArktShell/build/ui-1792868138.xcresult docs/spec/arc-parity-spec.md app/ArktShell/UITests/parity-deferred.txt`

Exit code 0. The script printed these five lines after the status table:

```
`test_BH036_switchingBackRestoresLastActiveTab()` 3m 13s (193.8715180158615s)
`test_KB035_BH041_ctrlNumberGoesToSpace()` 1m 16s (76.50147294998169s)
`test_KB033_KB034_cmdOptArrowsMoveBetweenSpaces()` 16s (16.32246494293213s)
`test_BH035_spaceDotClickSelectsSpace()` 13s (13.301324009895325s)
`test_GS001_twoFingerSwipeMovesSpace()` 10s (10.702916026115417s)
```

Promotion still waits on 10 green `UI tests (informative)` runs on `main`, one local
`-test-iterations 20 -run-tests-until-failure` run with no failure, and a maintainer decision in #161.

### Deviations from the plan

- Step 6 is not done: `continue-on-error` is unchanged, the job is not in the gate, and CONTRIBUTING.md is not edited.
- The classifier counts above were checked with a schema fixture. The slowest five were printed by re-running the
  script on `177-space-switching`'s completed `ui-1792868138.xcresult`. The full UI suite was not run.
- A mix of passed and skipped or expected-failure tests is deferred. The plan states passing as every test passed, and
  deferred as only skipped tests or a deferred-file row; the mix is neither passing nor failing.
- GS-001 and BH-040 are in the starter file even though U12's probe is not on this branch.
