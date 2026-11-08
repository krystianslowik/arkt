# Folder and extension result activation (#562)

The next bounded contract uses the requested selection behavior: reveal and expand a folder in its Space, and invoke an extension's existing action. Search engines remain Google and DuckDuckGo with Google as default; no Bing is added.

The pure result test now requires enabled provider rows to be actionable. `CommandBarFolderExtensionActivationTests` uses the actual ShellWindowController command bar and real ModelSidebarSource, without substituting provider or activation callbacks. It covers nested closed folders in Pinned and Today across Spaces, unchanged node snapshots, updated and deleted source data on subsequent queries, two windows with distinct extension action IDs, disabled-action exclusion, host-window invocation/anchor identity, no extra tabs, and action changes while the query remains open. Teardown closes and releases all retained window controllers.

Expected first red: the pure actionable assertions fail and the GUI tests cannot find forwarded provider rows. No new production API is required by the tests. Swift parsing and whitespace checks passed locally; compilation and runtime failure remain unobserved until CI. Production wiring must follow that observed red. This gate does not establish real extension installation, Chromium popup behavior, native keyboard or VoiceOver behavior, hot-path performance, or whole-issue completion. It does not prescribe new ordering or filter classification for the provider kinds. Existing mixed-result ordering tests remain unchanged.

Previous stage at `3cc5ebf`: run 42522998624 passed Core 579 tests / 47 suites, pure ShellKit 2,556 / 293, GUI 2,172 reported / 64 skipped / zero failures, app build, lint and required aggregate; XCUITest was skipped. Both real Settings search control methods passed. Those counts precede this test-only stage.


At `f74b3d7`, run 42526889444 / ShellKit job 128872412872 failed compilation because the GUI fixture omitted the Smoke SPI import required by `setQueryForTesting`. No behavioral test ran, so that failure is not the intended actionability red. The follow-up adds the same SPI import used by neighboring command-bar GUI tests; assertions and production sources remain unchanged. Observe the next run before implementing activation.
