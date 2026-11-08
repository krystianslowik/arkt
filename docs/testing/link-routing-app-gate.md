# External-link app integration gate (#113)

The gate is designed to exercise the Debug app, its real Settings editor and SQLite-backed session, the sandboxed
UI-test runner, Launch Services targeting that exact test bundle, and the loopback fixture server. A route to Space 1
and a route to Little Arkt override a Space 2 default; an unmatched URL uses that default. Warm delivery and a URL used to relaunch after Cmd-Q exercise
both application-open forwarding and persisted routing, with unique fixture pages as positive delivery barriers.
The tests check the visible destination and unique page identity after delivery. It must not change the
system default browser or register a handler. The cold launch uses the sandbox environment and normal test launch
arguments in the OS open configuration.

At this head the intended red is the destination assertion: AppSession forwards to the window set without wiring its
routing editor as the resolver, and AppDelegate drops events arriving before the session exists. A cold failure alone
does not deterministically identify which defect caused it. The checks are app-composition coverage, not proof of every
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
source-linked into the focused `integration/LinkRouting` probe. `ExternalOpenCoordinator<Outcome>` is intentionally
absent until implementation. Its intended surface is `init()`, `receive([URL])`, `state` (`waiting`, `loading`,
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
This is a proposed wiring path only; neither app integration nor an automatic retry policy is implemented here.

The component gate is designed to exercise held and failed reads, coalescing, reentrant arrivals, duplicate inputs, ordered outcome
reporting and a later edit to the real shared editor. It does not construct AppSession or establish that AppDelegate
actually uses the receiver. Existing real-app positive cases cover the latter only after native execution; their run's
result must be observed before implementing App composition. The app still needs a genuine queue-drained observation
before asserting duplicate absence. Chromium's already-created engine windows use the separate `embedderReady` queue;
these tests do not authorize replaying those tabs as new URL opens, and representative engine adoption needs its own
integration coverage.
