# Link routing SQLite integration probe

From the repository root on macOS, with Swift 6.4.1 and the macOS 15 SDK:

```sh
swift test --package-path integration/LinkRouting
```

This standalone package runs two termination cases and a Settings adapter value round-trip using the production CoreBridge model, the real typed Persistence/SQLite store, and production ShellUI support sources linked into this focused build. The symlinks deliberately point to the current checkout's sources. It exercises blocking persistence, reopening the database, failure after closing it, and ordered duplicate route conversion through the actual Settings adapter. It does not build AppSession, the Settings window, or the complete ShellKit product. It is an explicit probe, not currently a CI job; the pure CoreBridge tests and ArktCore Persistence tests remain in their existing CI targets.

The probe also includes the canonical CoreBridge Settings-readiness tests by source link. Those two tests run in normal ShellKit CI as well; the combined SQLite/model cases remain specific to this standalone probe.

The Space-removal cases also run the canonical pure editor tests through a source link. The SQLite probe checks pruning across close and reopen. It does not compile or exercise AppSession, the source observer composition, or the Settings sheet; those remain separate CI coverage.

The termination cases also hold or fail the initial read and reopen the typed database after normal and blocking cleanup. They exercise the production editor and store, but do not exercise the AppSession observer/termination composition or a live Settings window.

The probe also source-links the canonical Core matching, typed routing persistence, atomic store, and CoreBridge
editor tests. Together they verify case-insensitive contains, exact-string matches, and first-match precedence
through stored list order without replacing the normal Core and ShellKit CI targets.

The canonical external-open coordinator contract tests are also linked here. They deliberately fail to compile until
`CoreBridge` supplies the coordinator; this probe exercises the actual editor and dependencies, not App composition.
