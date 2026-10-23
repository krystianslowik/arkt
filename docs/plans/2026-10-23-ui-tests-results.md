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
