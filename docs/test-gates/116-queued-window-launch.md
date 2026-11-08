# Queued regular windows at launch (#116)

`QueuedWindowLaunchGateTests` is a test-first proposal, not a report of a passing app launch. It drives
`InMemoryEngine.openEngineWindow` through the window set's real host provider and window-opened adoption before the
launch decision. The proposed `defersLaunchCapture: true` initializer argument starts collection capture suspended;
`openWindowsAtLaunch(settings:defaultWindowAllowed:)` ends that suspension after the shared restore decision and
suppresses the default-window fallback when the argument is false. Its return value contains only restored controllers, not an already-adopted queued controller. The decision must also inspect controller privacy (or receive equivalent explicit context): a private-only launch returns no restored regular windows and preserves both stored values. Names are illustrative, but the constructor
must establish the protection before any queued host is delivered, and the complete decision must be one actual
ShellKit API called unconditionally by `AppSession.finishLaunch`. The test intentionally does not replicate the
app's fanout. Existing callers must retain their established behavior when the new initializer argument is omitted.

For a queued regular startup window, App should construct the set in the deferred mode before `embedderReady`, then
call the complete decision after queued adoptions, with default-window creation disallowed when an engine window has
already been supplied. The decision restores saved regular windows if enabled; if disabled it leaves the old
collection untouched through the decision and permits later ordinary changes to save. Unreadable data remains
protected. Any legacy single-window write during the pending period also needs consideration: protecting only the
collection cannot make an absent-collection legacy case safe. The tests compare the raw legacy bytes before the decision even when an explicit collection masks that key. After enabled restoration they change a restored selection and require a complete three-window collection in controller order, including independent selections and folders; capture cannot remain frozen. The queued tab must still belong to its original engine window. Recovery offers and their independent domain protection
must remain independent of this ordering; this gate chooses no routing winner and does not wire #113 or #825.

The existing app treats *any* queued controller as a reason not to open its usual launch window. Blank and incognito
windows are private, and engine requests inherit a private opener or use off-the-record status; they do not save regular
sessions. The off-the-record fixture explicitly guards the existing private-only behavior: no regular history is restored and neither saved value changes. Mixed and unknown privacy or fallback policy remain outside this case;
the app must distinguish the regular startup case without assuming every queued controller is regular.

ShellKit cannot import App. Passing this fixture alone cannot prove that AppSession forwards the decision or that
Chromium delivers the expected requests. Review the real app call ordering and observe the intended red on the
published base before production changes; then run the focused GUI gate and appropriate app/engine checks in a safe
environment. No native app or GUI test was launched to prepare this gate.

Review repairs add the private-only regression, post-decision complete persistence, adopted-tab ownership, and raw legacy protection. Parsing is the only local Swift validation; no compile or runtime red is claimed.
