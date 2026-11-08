# External-link app integration gate (#113)

The gate is designed to exercise the Debug app, its real Settings editor and SQLite-backed session, the sandboxed
UI-test runner, Launch Services targeting that exact test bundle, and the loopback fixture server. A route to Space 1
and a route to Little Arkt override a Space 2 default; an unmatched URL uses that default. Warm delivery and a URL used to relaunch after Cmd-Q exercise
both application-open forwarding and persisted routing, with unique fixture pages as positive delivery barriers.
The tests check the visible destination and unique page identity after delivery. It must not change the
system default browser or register a handler. The cold launch uses the sandbox environment and normal test launch
arguments in the OS open configuration.

Before App composition wiring, the intended red was the destination assertion: the window set had no routing
resolver and AppDelegate dropped events before session creation. A cold failure alone does not deterministically
identify either defect. The checks are app-composition coverage, not proof of every
startup ordering. NSWorkspace completion confirms Launch Services accepted the request, while fixture page identity
and accessibility state confirm delivery; neither is a general queue-drained signal. There is no observable application-open completion
barrier that proves all resulting work has drained. The tests
therefore do not assert absence of wrong-Space duplicates; add that assertion once such a barrier exists.

No current app seam holds or fails the routing read while observing real composition, so no deterministic load/retry
test is claimed. A future seam should inject the routing store into AppSession and expose controlled read completion,
while keeping the actual AppDelegate, session and window wiring in the test. Native Chromium startup requests use a
separate engine queue; the FakeEngine app run does not prove that path or cancellation. A supported Chromium UI run
and an observable request completion seam are needed. No local app launch or full build is part of this gate's
validation; parser and focused API checks alone are not test execution.

The six independent cases are intended for the existing FakeEngine XCUITest job; a warm failure does not prevent a
cold case from running. The Space route demonstrates that a matching route overrides the default, and the unmatched
case requires the non-fresh default to survive quit and relaunch. Actual OS delivery timing is not controlled, so
these tests cannot force an event before session creation or during a routing read.

## Local coordinator test-first contract

The canonical `CoreBridgeTests/ExternalOpenCoordinatorTests.swift` specifies a main-actor, plain-value receiver,
source-linked into the focused `integration/LinkRouting` probe. `ExternalOpenCoordinator<Outcome>` was absent at the test-first gate. Its surface is `init()`, `receive([URL])`, `state` (`waiting`, `loading`,
`ready`, `failed`), `pendingCount`, and `start(read:deliver:onResult:) async -> Bool`. The first start attaches the
session's read, synchronous per-URL delivery, and result callbacks; concurrent starts join that attempt. A start after
failure is an explicit retry; a start while ready does not reload or replace callbacks. The Boolean and state expose
read failure; the callback transfers every delivery outcome, in order, to the caller. Requests are removed only as
reported, and arrivals during a callback join the tail. The caller owns reported unresolved or missing-Space results;
this contract neither silently loses them nor invents a retry/fallback policy. No URL is deduplicated. Load failure
leaves the entire undelivered queue intact. A loaded editor must not be reloaded merely because another caller starts.

The receiver exists in AppComposition before AppDelegate can receive URLs. After the session and its existing single
`linkRoutingSettings` editor are available and the window system is ready, composition attaches closures that load
that editor, check `isLoaded` after `load()` (which reports errors via state rather than throwing), and invoke
`windows.openFromOtherApp([url])`. The window resolver reads `linkRoutingSettings.destination(for:)` on each delivery,
not a captured snapshot. The App owns and handles the returned `ExternalLinkOpenResult` values, including unresolved
and missing-Space outcomes; their user-facing handling remains an integration boundary. The coordinator and editor are
one per composition/session, not one per event or Settings window. An explicit retry must reuse the retained queue.
App composition now follows this wiring path; no automatic retry or user-facing blocked-outcome policy is implemented.

The component gate is designed to exercise held and failed reads, coalescing, reentrant arrivals, duplicate inputs, ordered outcome
reporting and a later edit to the real shared editor. It does not construct AppSession or establish that AppDelegate
actually uses the receiver. Existing real-app positive cases cover the latter only after native execution; their run's
result must be observed before implementing App composition. The app still needs a genuine queue-drained observation
before asserting duplicate absence. Chromium's already-created engine windows use the separate `embedderReady` queue;
these tests do not authorize replaying those tabs as new URL opens, and representative engine adoption needs its own
integration coverage.

### Pure implementation boundary and validation plan

The receiver and its callbacks are main-actor isolated in a new CoreBridge source file. The injected async read owns
its existing store I/O; CoreBridge does not import Persistence or GRDB. The focused package will source-link that
same file beside the existing editor link. No App, session, delegate, window, or Chromium hot files need changes for
this component. The queue uses an index and a guarded synchronous drain so callback arrivals join its tail.

Validation is the supported Swift 6.4.1 actual-source probe with the macOS 15.5 SDK and two jobs, plus a Swift 6.2.4
parser check. The canonical held-read helpers have unbounded waits and one continuation; an overwritten continuation
could hang a broken coalescing implementation, so a hang is not a passing result. Native app execution and wiring
remain separate gates.

### Pure implementation result

The actual-source probe passed 59 tests in 13 suites before the additional result-callback regression. The final
rerun and parser result are recorded below. The build emitted linker warnings for missing Swift and Command Line
Tools framework search directories and a missing Command Line Tools library search path; no coordinator source
warning was reported. This result does not establish app forwarding or native app runtime behavior.

The final supported probe run passed 60 tests in 13 suites, including the five original coordinator contracts and an
additional result-callback reentrancy/ready-callback retention regression. Swift 6.2.4 frontend parsing of the new
source and canonical test file also passed; this parser check is distinct from test execution. The held-read and
signal helpers still have unbounded waits, and HeldRead holds only one continuation; bounded cleanup remains work for
the gate owner before publication. The native app run remains unobserved here.


### Bounded canonical harness

The canonical contracts now use finite main-actor turn waits (10,000 yields), including completion of each start.
There is no wall-clock deadline or sleep. HeldRead retains all pending continuations rather than overwriting one;
each throwing test registers cleanup before its first observation, releases all held reads, and cancels its start
attempts. The original behavior expectations and the result-callback regression remain intact.

With the production coalescing guard deliberately disabled, the focused six-test suite failed with three issues:
the retry read count became three instead of two, and the concurrent-start completion hit the finite turn bound.
The broken run exited with failure rather than hanging. The production guard was restored before validation and
commit. An initial parser error in the helper rewrite was corrected before these executable runs.

After restoration, the supported actual-source probe passed 60 tests in 13 suites. The six coordinator tests also
passed 20 consecutive filtered runs while two CPU-load workers ran. Load averages were 1.62/1.74/1.65 at the start
and 1.89/1.79/1.67 at the end. Commands were:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk /opt/homebrew/opt/swift/bin/swift test --package-path integration/LinkRouting -j 2
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk /opt/homebrew/opt/swift/bin/swift test --package-path integration/LinkRouting -j 2 --skip-build --filter ExternalOpenCoordinatorTests
```

Swift 6.2.4 parsing and whitespace checks passed. The focused build still emits the previously recorded missing
framework/library search-path linker warnings, with no coordinator source warning. The standalone probe is not
currently a CI job and does not establish AppSession, AppDelegate, Chromium, GUI or app behavior. At that inspection focused native run 42491702781 had not yet been observed; its later result is recorded below.


### Independent component review

Independent review of `8bcb01e3c2d387867fdc7464e6c00d3eab2397ea` found no P1/P2 issue within the pure
component boundary and independently executed the six-test coordinator filter successfully. A fresh build exposed
a Swift Testing optional-Bool ambiguity warning in the harness. Explicitly unwrapping `value as Bool?` removes that
warning while preserving false as a valid completed result.

The ready-start regression now also checks each delivered String value, so replacing only the delivery callback
cannot escape its callback-retention assertion. Deliberately assigning a replacement delivery callback in the ready
branch made this assertion fail; the production ready branch was restored before the final full probe. The final
probe again passed 60 tests in 13 suites with no ambiguity warning; the recorded linker search-path warnings remain.

Integration constraints remain: cancelling one start waiter does not cancel the shared read, and a suspended read's
unstructured task retains the coordinator until completion. The queue has no size cap and retains its peak array
capacity after a drain. During callbacks, pendingCount includes the current input until reporting returns. Direct
cancellation/lifetime and in-callback pendingCount tests are not present. These constraints require deliberate App
ownership and recovery handling; the pure component's tests do not establish those future composition behaviors.


### Native red and bounded App composition

Focused manual run 42491702781 (UI job 128765333816), tested head `0f2f48081d93e8e2222596e6642fa59df4777d1e`, completed all six cases. The three warm cases loaded their unique fixture pages but failed their first expected-destination assertions: the unmatched default stayed in Space 1 instead of configured Space 2, the Little Arkt route stayed in Space 2, and the Space 1 route stayed in Space 2. Accessibility attachments establish real OS delivery and the wrong destination. The three cold cases showed Welcome instead of the configured profile; their profile/environment identity is unestablished and they are setup failures, not routing-specific red evidence.

AppComposition now owns the receiver before session creation. After normal FakeEngine launch or deferred Chromium finishLaunch, it uses the shared session editor, checks load success, installs a current-state resolver, and drains each input through the window set. A failed initial read retains the queue for an explicit composition retry. Reported unresolved and missing-Space outcomes remain in composition-owned memory until termination; user-facing handling and fallback are undecided. Dispatch means the open was handed to the window path, not that a page loaded. No automatic retry or queue cap is provided. Suspended coordinator reads retain their task and coordinator until completion; cancelling a waiter does not cancel the shared read.

This stage does not establish held/failed-read behavior in the actual App, early OS event timing, queue-drained duplicate absence, cold persisted-profile relaunch, or Chromium startup-window adoption. Chromium's existing queued engine requests are not replayed as external URLs. The six app tests remain unchanged and require a new native run before any app-green claim.

The post-wiring actual-source focused probe passed 60 tests in 13 suites, including six coordinator tests; linker search-path warnings remained. Swift 6.2.4 frontend parsing of the changed App sources and whitespace checks passed. The probe does not compile App or prove the wiring; no full local ShellKit/App build, GUI run or app launch was performed.


## Retry and termination review repair

Review of `1a8f13e63771553124cedb290892002290de73b5` identified two App composition gaps: no reachable
retry after the initial routing read failed, and delivery after quit had frozen session saves. The receiver now
pauses before session capture and resumes only after session cancellation restores writes. A successful read while
paused leaves its inputs queued. Pausing reentrantly during reporting retains the undelivered tail and current
index; it does not clear or shift queued inputs one at a time.

Composition retries a waiting or failed receiver after window readiness, on a new external-open event, after a
successful shared-editor read (including Settings recovery), and after quit cancellation. It starts no new read
while terminating. The model's main-actor onDidLoad notification runs only after a successful read has completed;
failed reads do not trigger it. Ready starts still preserve callbacks and dirty editor state.

Three new canonical tests first failed compilation on the missing pause/resume and load-notification APIs; zero
tests ran at red. The supported actual-source probe then passed 63 tests in 13 suites. Removing pause deliberately
failed six assertions across the held-read and reentrant-tail cases; removing the successful-load notification
failed the retained-queue retry case. Both mutations were restored before the final 63-test green. The nine-test
coordinator filter passed 20 consecutive runs with two CPU-load workers (load averages 0.96/1.29/1.31 at start,
1.51/1.39/1.34 at end). Commands are the same supported probe and coordinator filter recorded above.

App-source parsing, layering and whitespace checks are separate from execution. The focused package proves the
actual coordinator/model behavior and notification-driven retry, not that App forwards each lifecycle callback.
No local full App build, app launch, GUI or native termination/cancellation ran. Existing linker search-path
warnings remain; current-head App and native validation are pending.

The three cold OS-open cases remain unrepresentative: their captured processes showed onboarding despite the
requested skip flag. SDK environment semantics and the discarded returned process identity do not establish which
bundle/process or effective sandbox was used. They must not be rerun as routing evidence until a pre-disk Debug
identity/isolation observation, returned bundle/PID correlation, and the persisted two-Space routing profile are
established on a disposable runner. No cold-harness repair or native green is claimed by this source change.


## Pre-migration UI-test requirement: first stage

The Debug entry point now evaluates a pure `EnvironmentOverrides` startup policy before legacy-defaults migration,
`NSApplication`, delegate, or session construction. A separate `ArktRequireUITestOverrides` Info value defaults to
NO in the XcodeGen settings; only the UI workflow's xcodebuild passes YES. When required, the policy requires
`ARKT_UITEST=1` and delegates the remaining checks to the existing strict validator. Explicit UI-test mode also
validates with the flag off; ordinary launches with the flag off and no UI-test environment retain their behavior.
Failure exits with status 64. This checks nonempty directory strings and a usable suite name, not directory
confinement or effective profile identity. No reporter or acknowledgement path is introduced.

The test-first focused actual-source probe linked the app's validator and canonical ShellUITests file, without an
App or session substitute. Before the policy existed, the command below failed compilation with eight missing
`uiTestStartupViolations` member errors; zero tests ran. After implementation it passed 22 tests in one suite,
including five new policy tests. It emitted three linker warnings for missing toolchain/Command Line Tools library
and framework search paths. A preliminary direct `swiftc -typecheck` attempt failed to find the Testing module and
ran zero tests; the SwiftPM probe supplies it.

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk /opt/homebrew/opt/swift/bin/swift test --package-path integration/StartupPolicy -j 2
```

Swift 6.2.4 frontend parsing, workflow actionlint, source layering, UI-test source lint and whitespace checks passed.
The six app test methods, routing expectations and cold helper are unchanged. Pure tests do not prove the entry
point's call order; that order was reviewed in source. Static build-setting plumbing does not establish the generated
Info value or compiled App behavior: neither XcodeGen output, App build nor native execution was observed. The cold
gate remains held until actual PID, effective profile identity and persisted routing profile are observed and the
remaining identity barrier is reviewed. No cold run or routing-green claim follows from this stage.
