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
