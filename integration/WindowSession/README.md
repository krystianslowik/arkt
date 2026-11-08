# Window session observation probe

Runs the canonical store, compatibility and observation tests against the actual injected defaults store and observation source:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk /opt/homebrew/opt/swift/bin/swift test --package-path integration/WindowSession -j 2
```

All source and test links point to production or canonical test files. The EngineAPI subset omits only the unrelated Arc import protocol/helpers and their ArcImport dependency. Sidebar identity aliases are shared production declarations. There are no replacement store, engine, or observation types.

This bounded probe does not compile the App, window set, AppKit observation adapter, or XCUITest target. It does not verify capture, AX discovery, restoration, or app lifecycle composition. It is not run by CI.

Local validation: 34 tests in four suites passed (32 existing plus two observation tests). Temporarily making the actual `saveWindows` return without writing caused `actualCollectionSaveIsObservable` to fail with `missing saved data`; restoring it returned the full probe to green. This mutation checks the store fixture, not window capture.
