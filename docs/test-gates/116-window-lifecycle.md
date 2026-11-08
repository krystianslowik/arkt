# Window session lifecycle gate (#116)

The maintainer chose UserDefaults for the collection in [PR #829](https://github.com/krystianslowik/arkt/pull/829#issuecomment-6721408956). `MultiWindowLifecycleGateTests` uses the actual `WindowSessionStore`, isolated defaults, `ShellWindowSet`, `InMemoryEngine` and `ModelSidebarSource` backed by a real sidebar model. Tests run on the main actor; they add no production hot-path work or animation.

The gate specifies ordered, independent regular-window state, including collapsed folders, capture before engine teardown, a frozen collection during quit and immediate refresh plus continued writes on resume. It checks private windows while the originals are open and after reopening, deleted Space/tab/folder fallback, and per-window disconnected-display placement through the existing screen seam. Quit capture starts with a deliberately stale empty collection; cancellation checks the collection before resume as well as immediately afterward. The launch tests use an explicit component boundary: an absent collection falls back to the legacy value, while an explicit empty collection restores no windows. Creating a fresh window after an empty restore is an app-level decision and is not asserted here.

The proposed smallest new boundary is `ShellWindowSet.restoreWindowsAtLaunch(settings: AppSettings) -> [ShellWindowController]` (with a default settings argument where appropriate), called once at launch, returning the restored regular windows in stored order. It does not create a default window for an empty collection. The existing termination and resume methods need collection capture, freezing and immediate refresh; normal changes and closes must also update the collection, and private creation/reopen paths must remain excluded. Folder restoration must validate IDs against the live sidebar. The implementation now provides this boundary.

The General row is currently disabled and `AppSettings` has no restore preference. The gate proposes `restoreWindowsOnLaunch` on the shared settings store and checks the documented restore default, persistence of explicit changes, and disabled launch without erasing the saved collection. It does not prescribe reset behavior.

At `ac7231d`, CI run 42484606253, ShellKit job 128743709058, failed compilation on the absent launch and settings APIs and dependent inference diagnostics; zero tests ran. This is compile-time red, not runtime evidence. AppSession/AppDelegate/Chromium cancellation ordering, full relaunch and window order remain an integration boundary. No app test seed or completion hook is included. Navigation history remains #612; composition with the unanswered crash recovery offer in #690 remains separate and unverified.

## Implementation scope recorded before changes

Implement the WindowSet collection lifecycle and shared restore preference against this gate. Validate with available focused actual-source checks and Swift parsing; local full ShellKit, app builds and GUI execution are unavailable. App launch and termination composition, General UI, recovery composition and full relaunch require their own executable integration gate.

## Implementation validation

The implementation adds collection capture and freeze/resume, ordered restoration, folder validation, and the shared preference. Unreadable collections are protected from automatic writes for the lifetime of the set. Swift frontend parsing and whitespace checks passed; no lifecycle tests were executed locally. Frame changes are captured at resize end, key resignation and termination; live window movement alone is not persisted until a subsequent capture. App lifecycle composition, the General row, recovery and relaunch remain unverified.

## Empty-Space review regression

Review of `de8df5b` found that switching to an empty Space leaves the collection at the previous Space until another
capture. The focused test uses two real regular windows and two empty Spaces: switch one window to each empty
Space and read the real UserDefaults collection immediately, without quit capture, focus changes or waits. It
checks the empty current selection, retained per-Space history, collection order and the untouched second window.
The second switch also protects the nil-to-nil tab transition. This is a synchronous main-actor GUI test, with no
new clocks or animation. Only the test, this note and Track C results change; the production correction is pending
the observed runtime red. Existing lifecycle assertions remain intact. Source parsing cannot establish that red.

The runtime red is now observed at `c6ba758` in GUI job 128752869704: four assertions retain the previous Space/tab
through both empty switches. The Space-change callback now saves the session, including nil-to-nil tab transitions.
The same run exposed two test errors in the remembered-tab check: `showSpace` intentionally positions the page
without activating its remembered tab. That check now asserts both complete restored selection dictionaries and
uses the real dot/keyboard switch path with Reduce Motion enabled for synchronous settling. It still requires each
window's distinct tab on every switch; no persistence or history assertion is removed. Current-head CI must verify
the unchanged empty-Space regression and corrected interaction path.

## App composition gate plan

Issue #116 requires the General opening preference and actual app launch/quit composition for ordered regular
windows; each window retains its Space, tab and available folder state, while live private windows are excluded.
The existing component and legacy tests remain unchanged. The gate uses the supplied shared `AppSettings` and real
General popup, then an isolated real-app Cmd-Q/relaunch with distinct window identities. Disabled restore needs a
reliable launch-completion boundary; cancellation needs observation of the frozen and immediately resumed store.
Neither may be inferred from a first-window wait or a later incidental event.

Tests and UI state run on the main actor. The only edits are test files and this gate note; no production hot file,
animation, per-frame or sidebar hot-path change is planned. Production integration hot files are `AppSession`,
`AppDelegate`, the Chromium termination composition, and Settings pane/controller. Only App may import Persistence;
ShellUI exchanges plain values and actions. Two distinct Spaces and tabs, plus a live private window, exercise the
relevant state. The intended first runtime red is the disabled General popup and/or failure to restore both windows,
not a missing test API. A red is not claimed until executed.

Supported local validation: the Swift 6.2.4 frontend `-parse` on edited Swift files, `git diff --check`, and
repository static import/UI-source/parity checks where available. Parsing is neither typechecking nor execution.
Full package and App builds and GUI execution are unavailable here; CI must typecheck and execute the focused gates.

## App composition gate and remaining boundaries

The earlier statement that the preference does not exist describes the `ac7231d` gate, not the current code.
The in-process General test now exercises the real popup's selection path against one supplied `AppSettings`,
including both persisted values, shared-instance notifications and reset removing the preference key. The old
assertion that this row stays disabled is retired; other planned-row assertions remain.

The real-app test creates two regular windows with different selected Space/tab pairs, keeps a private window open,
reads the ordered collection before Cmd-Q, compares its selections after process exit, and identifies both restored
selections in actual windows. Loopback request baselines are taken after shutdown. It uses existing UI and defaults
facilities; it does not seed a session or call the WindowSet termination methods. Folder state is not asserted here.

The review correction checks that the raw saved collection has exactly two entries before projecting selection
identities, and uses a throwing map so an entry with a missing Space or tab cannot disappear. It repeats the raw
count after quit. The third live window must carry the Incognito label within its own accessibility subtree.
Setup identifies the new regular window by its absent selected beta tab rather than enumeration order. These checks
close the private-entry false pass at the capture boundary; exact final restored count and order still require the
launch-completion observation described below. The correction has not run and does not establish cross-process
defaults visibility or native accessibility behavior.

The test is a positive restoration gate, not proof that no extra window can appear. Neither new test has been
executed or typechecked locally; its intended failure has not been observed. In particular, CI must establish that
the sandboxed runner can observe the app's defaults suite and that the window-scoped accessibility queries work.

A complete disabled-restore assertion still needs a supported completion signal: scoped to a specific launch,
emitted after the app has finished deciding and opening all session windows (including the disabled and empty
cases), without changing window creation, focus or persisted state. Only then may a test assert one default window
and saved-collection preservation. No such hook is currently implemented or assumed by these tests.

The native cancellation gate is also outstanding. `ChromiumShell` forwards begin/cancel callbacks to the composition,
and `AppDelegate` uses its own termination path, but neither forwarding nor its ordering is proven by the component
tests. The current UI harness has no supported armed beforeunload fixture and no controlled observation point for a
stale collection at quit start, frozen state before dismissal, and the immediate post-cancel refresh before another
window event. A representative gate needs a loopback page armed by a user gesture, the actual Leave site dialog,
read-only observations at those boundaries, dismissal and a responsive survivor. A later tab action or a FakeEngine
close alone cannot demonstrate the immediate refresh or Chromium wiring. No cancellation test is claimed here.
Recovery composition (#690) and navigation history (#612) remain separate and unverified.

The smallest production path is to connect the existing popup to the shared setting and its observer, then have
`AppSession.finishLaunch` invoke the existing collection restoration with that same setting and supply a normal
window only when needed, while preserving queued Chromium-window and recovery behavior. Termination callbacks must
be verified through both actual composition paths before any further change is inferred.

Local source validation for this gate: Swift 6.2.4 frontend parsing of both edited Swift files, the workflow's
import-layering and UI-test-source checks, `scripts/ui-tests/parity-report-test.sh`, `actionlint`, and
`git diff --check` passed. No full build, typecheck, test execution, app launch or GUI run was performed here.


## Component green before app-gate publication

Run 42490834029 at `fc87d5123b406ad7e5c66a65c465d60f3f39e2a9` passed all twelve lifecycle methods,
with GUI 2083 reported/60 skipped/zero failures and pure ShellKit 2535 tests/285 suites. The app build, lint and
required gate passed; XCUITest and Core were skipped. The new General and app gates have not run and do not inherit
that green result. The optional focused UI workflow selector is copied unchanged from the maintainer-approved
#823 input so this branch can dispatch its actual app gate once; empty selection preserves full-suite behavior.


## First published app-gate result

At `899a4f7`, run 42494525891 reached the General GUI scenario and failed its eight popup/persistence/observer
assertions. The popup is now connected to the existing shared AppSettings instance and its observer. The app job
never ran a test: its source closure omitted the shared Incognito AXID declaration and failed compilation.
project.yml now includes that existing file alongside AXID, Peek and LittleArkt. A focused Swift 6.4.1 typecheck
passes for all four declarations (libSwiftScan fallback warning), but native relaunch and XCUITest compilation remain
for CI. No AppSession launch/restoration wiring is changed by this repair.

## Native observation boundary at b2d2efc

Run 42498813013, UI job 128786898768, compiled and ran the focused method. It stopped at the pre-quit wait for
two raw entries, not at restoration. Attachment 13624967395's accessibility tree shows the identified Incognito
window and the two regular windows with their distinct selected Space and loaded fixture tab. The test does not
report whether its defaults object saw no object, a non-Data value, invalid JSON, a missing `windows` array, or an
array of another count. It therefore proves neither successful app capture nor a capture defect.

The measurement crosses processes: the main-actor `ShellWindowSet` captures non-private controllers into the
injected `WindowSessionStore`, which encodes a version 1 JSON envelope as Data in the app's defaults; the
main-actor UI test reads a separately constructed `UserDefaults(suiteName:)`. AppSession supplies
`AppEnvironment.userDefaults`, which selects the test suite in Debug. The project disables App Sandbox globally for
the app, while the UI-test target describes an Xcode-sandboxed runner with a network-server entitlement and no
declared App Groups entitlement. The actual signed runner entitlements have not been inspected in this run.
Apple's [UserDefaults documentation](https://developer.apple.com/documentation/foundation/userdefaults?changes=l__4_5&language=objc)
states that a sandboxed app cannot access another process's settings except in the documented cases and that suite
access requires the App Groups entitlement. The SDK header also describes interprocess availability and asynchronous
persistence, but these do not establish access across this sandbox boundary. Same suite spelling is not evidence
that the runner observes the app's domain. The precise value seen in this run and the app's actual snapshot remain
unknown. Increasing the wait or adding synchronize would not establish the missing access contract.

Before changing the test, a native probe needs a supported, read-only observation from the app's own injected
defaults, gated to strict Debug UI-test mode. It must distinguish absent, wrong type, malformed envelope and raw
entry count, exposing the actual stored bytes or an equivalent lossless representation without capturing live
controllers or writing defaults. Observe that value while the private window is open. For the post-quit comparison,
the next process must expose a snapshot read from the same store before any launch-time write can replace it;
that snapshot needs a launch-specific identity and must remain available until observed. This is a proposed contract,
not an implemented seam. Its placement and accessibility transport still need review and native verification.

The probe must retain exact two-entry checks, private exclusion, throwing selection projection, ordered pre/post-quit
comparison and fresh fixture requests after relaunch. A stale pre-quit value reused as the post-quit result, a
snapshot taken after startup overwrites the store, or a value synthesized from live windows could falsely pass;
the probe must rule each out. Deliberately breaking collection writes and quit capture should fail their respective
checks. A native run must first establish that the observation itself is available; only a representative runtime
failure after that boundary can justify app launch/restoration changes. This is not a complete acceptance gate:
launch completion, disabled restore, cancellation, exact final window count/order, and folder state remain separate.

## Local observation repair (native verification pending)

The Debug strict UI-test session now exposes a read-only accessibility report from the same `WindowSessionStore`
instance supplied to `ShellWindowSet`. Its initial raw collection value is frozen before that set is created; current
reads query the injected defaults and preserve absent, non-Data and Data bytes. A per-session UUID distinguishes
launches, and the completion latch follows the actual `finishLaunch` window decision. The adapter appends a
noninteractive child to each root without replacing its accessibility children. It does not request a capture or
change restoration policy. AX discovery and value refresh are not established without a native run.

The revised UI test checks the current collection with the identified private window still open, then compares its
ordered selection pairs with the next launch's initial collection after requiring a different launch ID and the
completion latch. It checks the exact restored window count and fresh fixture requests; AX enumeration does not
establish creation order. A focused Foundation executable passed the raw-value, immutability, read-only, identity,
latch and codec checks. The AppKit adapter type-checked separately.

The repeatable [actual-source probe](../../integration/WindowSession/README.md) then passed **34 tests in four
suites: 32 existing store/compatibility tests plus two observation tests**. It links the production store, observer,
shared sidebar identity declarations, and the canonical tests. The identity aliases moved unchanged to their own
production file so this bounded target needs no substitute declarations. Its EngineAPI subset omits the unrelated
Arc import source and dependency. Swift 6.4.1 emitted missing developer-framework/library search-path warnings.

For the mutation check, an unconditional return was temporarily inserted at the start of the actual
`WindowSessionStore.saveWindows` method. The observation filter executed two tests and failed exactly the collection
save test with `missing saved data`. The mutation was removed before the 34-test green run. This establishes that the
store fixture detects disabled saves; it does not establish that App capture reaches the store. Deliberately broken
window capture, AX discovery and refresh, full App compilation and native UI execution remain unverified. The probe
is not currently run by CI. A representative native observation must precede any restoration change.


### Review boundary before native publication

Source review of `7351f9f` supports publication for one focused disposable native observation, with no claim that
AX transport or restoration passes. It identified a quit-capture coverage gap: comparing an already-correct
pre-quit collection with the next launch can pass even if termination capture is omitted. The native scenario is
therefore explicitly a restore round trip; it does not establish capture timing. A future quit-capture gate must
create distinguishable pending state and demonstrate failure when termination capture is disabled. The existing
window-set capture tests are a separate component boundary, not native App coverage. The store-save mutation above
is not that termination mutation.

The current raw count also does not map each stored ID to a live AX row. The later restored Space/tab labels and
fresh page requests are the behavior checks; a failure before that point must be interpreted at the observation
boundary first. No production restoration call is added by this publication.


## Native observation established; App restoration red

[Run 42504717042](https://github.com/krystianslowik/arkt/actions/runs/42504717042) at `ce5ba72` compiled and executed
the repaired native case. Its first assertion failure was line 95, waiting for both distinct window selections
to restore. The preceding store observation, raw two-entry count, private-window setup, distinct per-launch ID,
completion latch and ordered initial snapshot comparison succeeded. The failure AX attachment shows one regular
window selected in Space 2 on Fixture session-beta, with the observation element present. Thus the previous
runner-side observation barrier is passed and the missing App collection restoration now has a runtime red.
This does not establish quit-capture timing, disabled restore or every native lifecycle criterion.

The same focused workflow's GUI job passed: 2058 reported tests, 54 skipped and zero failures. Core, pure ShellKit,
App build, lint and the aggregate also passed; the native test remained red. Normal PR GUI was still running at
the status read. Those are `ce5ba72` results, not validation of the following implementation.

The bounded App change calls the existing once-at-launch collection restore with the shared `AppSettings` when
launch requests a window, then creates a default window only if no regular window exists. When Chromium reports
that its queued startup requests already opened a window, the existing `opensWindow: false` path continues to
use the primary window. Onboarding, crash prompts, recovery notice, auto-archive and the observation latch retain
their order after that launch decision. This has been parsed and source-inspected only; independent review and
a fresh native run must establish behavior before claiming green. #690 recovery composition remains separate.


## Enabled native green and disabled-launch regression gate

At `88d7d56`, [focused run 42507901483](https://github.com/krystianslowik/arkt/actions/runs/42507901483) passed the
real-app two-window round trip in 49.345 seconds. The normal PR [run 42507899180](https://github.com/krystianslowik/arkt/actions/runs/42507899180)
passed all executed checks; GUI reported 2118 tests, 63 skipped and zero failures. This is enabled FakeEngine App
composition evidence, including private exclusion at capture and matching ordered pre/post-quit selections; it
still does not prove that a quit-time capture was necessary or cover native Chromium cancellation.

The source review identified a separate P2: disabling restoration returns no collection windows, then the App's
fresh fallback immediately captures over the previous collection. The helper-only preservation test never created
that fallback. A second native case now uses the real General popup to disable restoration before quit, requires
the two-entry frozen initial collection after relaunch, then requires exactly one regular window and byte-for-byte
unchanged current collection at the launch-completion report before further interaction. The already-green enabled
case shares only setup and retains its restore, private, identity and fresh-page assertions. The new case covers
preservation at this launch boundary, not a promise to retain that snapshot after later user actions or another quit.

The new case has only parsed and passed source/whitespace checks; its intended preservation failure is unobserved.
No production behavior changed for this gate. CI must establish that failure before the preservation fix.


## Disabled-launch overwrite runtime red and bounded fix

[Run 42510853793](https://github.com/krystianslowik/arkt/actions/runs/42510853793) at `7a377dd` passed the enabled
case in 56.126 seconds. The disabled case completed its General preference, capture, quit, fresh launch ID/latch,
initial collection and one-window checks, then failed exactly the current-versus-initial comparison: 327 current
bytes versus 707 initial bytes at line 121. This establishes the fallback overwrite at the actual App boundary.
Normal required, Core, pure ShellKit, App and lint checks passed at this head; GUI remained in progress at the read.

The bounded fix adds `ShellWindowSet.openWindowsAtLaunch` for the complete restore-or-fallback decision and uses
it from AppSession. It reuses the once-only restore helper and an existing primary window, if present. Disabled
restoration suppresses collection capture only while constructing the fresh fallback, restoring the prior
suppression state on return. Later ordinary window changes still save. Enabled, absent, empty and unreadable
collection handling otherwise follows the existing helper and fallback behavior.

A component test calls this same complete entry point, not only the restore helper. It seeds both collection and
legacy state in another Space, requires one fresh window and preserved collection, checks repeated forwarding
creates no duplicate, then changes the selected tab and requires the collection to update. Native tests retain
their assertions. The new production/component sources parsed and passed whitespace checks only; the component
test, complete App build and native fix have not run locally. Source review and new-head CI remain required.


## Fixed native launch cases green; main integration pending

At `6c5946b`, [run 42513197636](https://github.com/krystianslowik/arkt/actions/runs/42513197636) passed both native
cases: enabled restore in 52.943 seconds and disabled-launch preservation in 54.519 seconds (two tests, zero
failures). The normal PR run passed all executed checks, including GUI 2136 reported, 63 skipped, zero failures;
the complete-boundary component test passed. This validates the bounded fallback fix on that head, not a future
merge or necessary quit-capture timing.

Main `a9457aa` now includes #690 recovery and #833 retained-window fixes. The local integration resolves four
files: AppSession retains the exact injected store observation plus RecoveryPages, invokes collection restoration
before beginning engine recovery, and keeps the recovery notice sequence; WindowSet retains both unreadable-store
protection and unanswered-recovery protection. The factory accepts both explicit window-session state and early
regular/private kind classification. Close and private-transition events invoke both recovery and collection
callbacks, after their closed/private flags change. Main's weak Little Arkt anchors and other landed changes remain.

The four resolved Swift files parsed; the import/UI-source workflow checks, actionlint, engine-header comparison
and resolution-specific whitespace checks passed. No merged-head build or tests ran. The full staged whitespace
check includes four inherited findings in main's extensions directions README and Chromium patch context; both
files are byte-identical to main and were not rewritten. Recovery-with-multiple-window/crash interaction and native
cancellation remain verification boundaries for the merged head. Independent review precedes publication.
