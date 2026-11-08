# Folder and extension result activation (#562)

The next bounded contract uses the requested selection behavior: reveal and expand a folder in its Space, and invoke an extension's existing action. Search engines remain Google and DuckDuckGo with Google as default; no Bing is added.

The pure result test now requires enabled provider rows to be actionable. `CommandBarFolderExtensionActivationTests` uses the actual ShellWindowController command bar and real ModelSidebarSource, without substituting provider or activation callbacks. It covers nested closed folders in Pinned and Today across Spaces, unchanged node snapshots, updated and deleted source data on subsequent queries, two windows with distinct extension action IDs, disabled-action exclusion, host-window invocation/anchor identity, no extra tabs, and action changes while the query remains open. Teardown closes and releases all retained window controllers.

The intended first red was observed at `d88ed06` in run `42528726868`: pure ShellKit executed 2,567 tests in 294 suites with eight issues, all in the enabled-provider actionability/presentation test. GUI executed 2,181 reported tests, 64 skipped, with four intended activation failures across the three new methods and one separate AddressBarNavigationTests window-lifetime guard failure. Core, app build and lint passed. This follows the import-only correction described below; it is a behavioral failure, not a compilation failure. This gate does not establish real extension installation, Chromium popup behavior, native keyboard or VoiceOver behavior, hot-path performance, or whole-issue completion. It does not prescribe new ordering or filter classification for the provider kinds. Existing mixed-result ordering tests remain unchanged.

Previous stage at `3cc5ebf`: run 42522998624 passed Core 579 tests / 47 suites, pure ShellKit 2,556 / 293, GUI 2,172 reported / 64 skipped / zero failures, app build, lint and required aggregate; XCUITest was skipped. Both real Settings search control methods passed. Those counts precede this test-only stage.


At `f74b3d7`, run 42526889444 / ShellKit job 128872412872 failed compilation because the GUI fixture omitted the Smoke SPI import required by `setQueryForTesting`. No behavioral test ran, so that failure is not the intended actionability red. The follow-up adds the same SPI import used by neighboring command-bar GUI tests; assertions and production sources remain unchanged. Observe the next run before implementing activation.

## Production forwarding and activation

The window now supplies folders from its profile's Spaces and enabled actions from its own engine window. Folder
collection is cached until sidebar changes (or the Space list changes); the existing traversal keeps its depth and
visited-ID guards. Sidebar notifications invalidate that cache and coalesce visible command-bar refreshes on the
main queue. Engine action-change events refresh the per-window action cache and an already open query. Empty and
scoped queries do not request the new providers. These are main-actor UI paths; no disk or network work is added.
No measured performance improvement is claimed, and worst-case result volume and hot-path timing remain unmeasured.

Rows have distinct folder/extension symbols, action captions, Return hints and positional accessibility labels.
Folders include their Space title as context. Existing result order and All-only filter classification are retained.
Refresh retains the selected identity across a rename, then refreshes preview and hints through the common selection
path. The new kinds have no preview.

Selecting a folder rechecks that it still exists in this window's profile, switches to its Space, expands its ancestors
and the selected folder, reveals it and focuses its sidebar row. Unrelated folders stay collapsed. Private windows do
not supply shared folder rows. Selecting an extension action rechecks the current per-window engine list and enabled
state, then invokes the same engine action as the existing Extensions panel with a window-owned anchor. Removed,
disabled and closing-window targets do nothing. Extension availability follows the engine's existing per-window policy.

The GUI cases retain the original actual-window provider/activation assertions and add stale-target checks, profile
and private-folder exclusion, unrelated-folder state, and selection retention on action rename. Pure cases add Space
context and unchanged filter counts. These new cases have only been parsed locally; no implementation-head compilation
or test pass is established yet. Full ShellKit/App/GUI builds are left to CI because local free disk is approximately
1 GiB. Native keyboard selection, real installed extension popup behavior, VoiceOver and light/dark visual inspection
remain unverified.

Main `cfc4e69` is integrated, preserving both the landed reorder-haptics reset key and the search-engine reset key,
the real haptics row and its AppSession bind. The AddressBarNavigationTests teardown now calls the existing
`closeAllForTesting()` helper before releasing its sets; its window guard and behavior assertions remain intact.
Google and DuckDuckGo remain the only engine choices, with Google the default. The broader issue remains draft and
requires current-head CI and independent review before any readiness claim.


## Activation run and fixture Space correction

At `8c549f9`, run `42532419492` passed Core, App build, lint and required aggregate; pure ShellKit passed
2,573 tests / 295 suites, including the provider actionability, Space-context/filter and preview cases. GUI executed
2,184 reported tests, 64 skipped, with four failures, all the unrelated-folder collapsed-state assertions in the two
folder locations. Extension invocation, live action updates and profile/private-folder exclusion passed. The prior
address-bar fixture window guard passed.

The new fixture used internal `show(node:)`, which creates/displays content but does not change SidebarController's
current Space. With Personal created first and the setup tab in Work, it closed IDs on Personal's outline; the reveal
correctly switched to Work's separate outline, where the unrelated folder had never been closed. The helper now uses
public `activate(node:)`, the real Space-selection path. Added assertions establish Work before collapsing, the
unrelated folder's closed state before and after switching away, and the same outline on return. All post-reveal
and stale-target assertions are retained. This is a test-only setup repair; production activation is unchanged.
Parsing and whitespace checks passed; the corrected GUI behavior still needs a fresh run. No local GUI or App build
ran. The prior component successes do not establish native keyboard/VoiceOver or installed-extension popup behavior.
