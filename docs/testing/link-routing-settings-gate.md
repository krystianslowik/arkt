# Link routing Settings test gate

This is a test-first contract for #113, not an implementation or a routing policy. The Settings design puts Link
routing in Spaces and Profiles: the default popup, ordered route rows with Edit, and Add Route. The prototype does
not specify the editing controls, removal gesture, cancel behavior, or their labels. Do not infer those details from
these tests. The design's keyboard walk, control labels and focus ring apply once controls exist; a UI test for editing,
cancellation, focus restoration and choosing available Spaces needs the approved editor interaction first. Profiles
are out of this slice. The default popup must also offer a chosen Space and most recent Space per BH-156.

The proposed `LinkRoutingSettingsStoring` pure Core protocol has `loadLinkRouting()` and transactional
`updateLinkRouting(at:_:)`. `SettingsStore` should conform using the existing `linkRouting.settings` typed group.
The proposed main-actor `LinkRoutingSettingsModel` loads it, edits the ordered value, and flushes writes. Method names
in the tests are a proposed seam, not a requirement to expose engine identifiers in the UI. ShellUI should consume
plain values and actions through `SettingsServices`, with a CoreBridge adapter like `ArchiveSettingsModel`; the app
composition root owns the real `SettingsStore` and injects the adapter. Disk work remains off the main actor. Test
Space choices using the existing `SettingsSpaceSummary` source, including duplicate names and stable IDs, when the
editor controls are specified. No new normalization or empty-pattern validation is assumed.

The CoreBridge tests cover editing and reopening against an isolated value store. The Persistence test separately
requires the same protocol to use the actual typed SQLite store and reopen it. Neither proves AppSession forwards
edits: ShellKit cannot import Persistence, and the existing app UI test only checks the fresh entry points and Settings
keyboard navigation. Extend that real sandboxed app UI test to edit, cancel, select destinations, quit and relaunch
once the editor interaction is settled; do not substitute a fake AppSession. The tests do not choose a winner or a
fallback for competing routes. Dispatch, Meet, Peek, Archive, import, deleted-Space cleanup and profile destinations
remain later work. General Settings reset and shortcut recording are unrelated.

The intended first red is a compile failure for the proposed store protocol and editor model, followed by the app UI
entry points remaining disabled until composition is wired. No red or passing suite is claimed without running it.

The default-destination slice now exposes a plain Settings adapter over one session-owned editor. The popup uses Space
IDs, including when names repeat, and retains an unavailable stored Space as an unavailable choice. Loading and read
failure leave the control disabled; changing the default retains the route array. Add Route remains planned until its
interaction is approved. The adapter tests exercise two consumers of the same editor, but do not verify AppSession's
forwarding, the SQLite-backed app composition, or the popup in a window. The existing XCUITest expectation that Add
Route is enabled remains a whole-feature gate and may fail until the editor form exists.
