# Link routing SQLite integration probe

From the repository root on macOS, with Swift 6.4.1 and the macOS 15 SDK:

```sh
swift test --package-path integration/LinkRouting
```

This standalone package runs two termination cases using the production CoreBridge model, the real typed Persistence/SQLite store, and production ShellUI support sources linked into this focused build. The symlinks deliberately point to the current checkout's sources. It exercises blocking persistence, reopening the database, and failure after closing it. It does not build AppSession, the Settings window, or the complete ShellKit product. It is an explicit probe, not currently a CI job; the pure CoreBridge tests and ArktCore Persistence tests remain in their existing CI targets.
