# Explicit archive restore routing (#113)

The Archive window's existing list-model action now obtains routing through `ArchiveCoordinator.linkRoutingProvider: (@MainActor () -> LinkRouting?)?`. AppSession supplies its one shared editor's `loadedSettings`, which includes unsaved edits and returns nil before loading, during a read, or after a failed read. An absent provider retains historical behavior; a configured unavailable snapshot reports restore failure and preserves the archive row for retry.

For a tab URL, the first explicit matching rule can restore into an existing same-profile Space. The coordinator projects only the entry's placement metadata before the existing single source restore mutation. Its snapshot and ID remain intact, and archive withdrawal still uses the original outbox path after insertion succeeds. The recorded Pinned/Today section is preserved. An observer test checks that the node first appears at the destination, with no intermediate restore-and-move. No explicit match retains ordinary original/fallback placement; the configured external-link default is not substituted. Unavailable or unsupported explicit destinations, foreign profiles and routed Favorites retain the archived entry and report failure. Little Arkt/Most Recent placement, Favorite/folder/split policy, optional import, Peek routing and Chromium startup integration remain incomplete.

## Test evidence

At `6bff3b4`, [run 42526445558 / ShellKit job 128871049653](https://github.com/krystianslowik/arkt/actions/runs/42526445558/job/128871049653) failed compilation on the absent provider at all three expected call sites; zero runtime tests ran. The aggregate failed because that required job failed. The separate loaded-snapshot contract also failed compilation on its missing API before implementation.

The source-linked `integration/ArchiveRouting` probe compiles the actual coordinator, sidebar adapter, mappings/diff and routing editor against real Core Archive/SidebarModel and value-only ShellUI/Motion dependencies. Its six tests in two suites passed on Swift 6.4.1 with the macOS 15.5 SDK, including distinct contains/exact routes, later competing matches, unavailable-state retry, missing/unsupported destinations, single-mutation placement, held/failed reads and unsaved edits. Bypassing the routing projection caused both parameter cases to fail with eight behavioral issues; restoring the production implementation returned all six tests to green. The linker reported missing developer framework/library search paths.

The canonical ArchiveListModel tests additionally exercise row retention, retry, store removal, neighbors and destination membership without adding a routed insertion-order rule. They have not run locally. The probe does not compile AppSession or run the Archive window, SQLite, OS delivery or Chromium. Full target compilation, App forwarding and UI/native behavior remain CI/runtime boundaries. See `integration/ArchiveRouting/README.md` for the exact command.

BH-086/BH-157 cover archive restores obeying explicit routes. The [maintainer decision](https://github.com/krystianslowik/arkt/pull/825#issuecomment-6721408579) specifies case-insensitive contains, exact unnormalized matches and first match. BH-156's default describes external links; this change preserves the existing unmatched archive behavior. It does not complete #113.


## Full-suite fixture correction

At `5006b7e`, run 42528538251 / ShellKit job 128877432002 executed 2,612 tests in 300 suites and reported 14 issues, all at the newly added tests' `flush()` assertions. The production one-second termination race was being used as an ordinary fake-store barrier. App build, Core and lint passed; this is not a green full ShellKit result. Routing assertions did not report failures.

The new fixtures now wait for actual add/remove acknowledgments and a drained writer using finite state-based yield bounds, matching the established archive-test pattern. The list-model cases retain their explicit row/store/snapshot assertions. Production deadlines, termination tests and placement/retention assertions are unchanged. The source-linked probe must be rerun; fresh full-suite CI remains required to establish the fixture correction.
