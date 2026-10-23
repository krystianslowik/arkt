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
  runs and removes the sandbox.
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
  (`xcodebuild test` turns Automation Mode on for the session by itself).
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
