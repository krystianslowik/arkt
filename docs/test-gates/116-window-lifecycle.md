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
