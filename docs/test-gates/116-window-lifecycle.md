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
