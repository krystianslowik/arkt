# Archive routing actual-source probe

```zsh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk /opt/homebrew/opt/swift/bin/swift test --package-path integration/ArchiveRouting -j 2
```

The production sources and canonical focused tests are symlinked from their original locations. The package compiles the real ArchiveCoordinator, ModelSidebarSource, mappings/diff and LinkRoutingSettingsModel with real Core Archive/SidebarModel and value-only ShellUI/Motion dependencies. The archive/routing store actors are test inputs; placement and mutation implementations are not substituted.

The six tests in two suites cover routing, one-mutation placement, retained-entry retry, explicit destination failures, held/failed reads and unsaved settings. The probe does not compile AppSession or ArchiveListModel, run the Archive window, access SQLite, or exercise OS/Chromium integration. It is not currently run by CI; the normal CoreBridge suite remains authoritative for full target compilation.
