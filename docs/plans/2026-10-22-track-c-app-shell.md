# Track C: Native App Shell Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** A runnable native macOS app `app/ArktShell` (real `.app` with Info.plist) that proves Arkt's UI feel
(window chrome, sidebar, command bar, spring motion, Space paging at 120 Hz) before the Chromium framework is ready,
running against a `FakeEngine` behind the `EngineClient` protocol from design section 1.

**Architecture:** Two layers. (1) A local SwiftPM package `app/ArktShell/ShellKit` holds every line of logic and
UI in five library targets: `EngineAPI` (the `EngineClient` protocol and value types; no WebKit), `FakeEngineKit`
(the only code allowed to `import WebKit`: one file, `FakeEngine.swift`, a WKWebView stand-in for development),
`Motion` (spring math, `CASpringAnimation` builder, display-link spring driver), `ShellUI` (AppKit window chrome,
sidebar, command bar, Space pager, frame pacing) and the test-only `EngineAPITestSupport` (pure in-memory engine plus
a reusable engine contract suite). (2) A thin XcodeGen app target `ArktShell` (composition root: `main.swift`,
menu, app delegate, smoke runner) that links `ShellUI` + `FakeEngineKit`. When Chromium lands, a `ChromiumEngine`
conforming to `EngineClient` replaces `FakeEngine` in the composition root and nothing in `ShellUI` changes.
The sidebar renders against a small local `SidebarSource` protocol whose names mirror Track B's `SidebarModel`
(`spaceOrder`, `children(of:)`, `Location.favorites/pinned/today/folder`), backed by `StubSidebar` until Track B's
`app/ArktCore` package merges.

**Tech Stack:** Swift 6.4 (Swift 6 language mode), Xcode 27.1, XcodeGen (`/opt/homebrew/bin/xcodegen`, already
installed), SwiftPM, AppKit, Core Animation (`CASpringAnimation`, `CAGradientLayer`, `CADisplayLink` via
`NSView.displayLink(target:selector:)`), WebKit (FakeEngineKit only), `os` (`Logger`, `OSSignposter`),
Swift Testing for pure tests, XCTest for run-loop/GUI tests. No third-party dependencies.

---

## Why XcodeGen + a local package (and not SwiftPM alone)

- `swift build` of an executable target yields a bare Mach-O, not an `.app` bundle: no `Info.plist`, no bundle id,
  no `NSPrincipalClass`, and AppKit apps launched that way get no Dock icon / proper activation and cannot be
  `open`ed. Wrapping it by hand needs a bundling script, which the house rules forbid ("no redundant sh scripts").
- XcodeGen is already installed (`which xcodegen` -> `/opt/homebrew/bin/xcodegen`), needs no GUI, and turns a
  ~40-line `project.yml` into an `.xcodeproj` that `xcodebuild` builds into a signed (ad-hoc) `.app` with a
  generated `Info.plist`.
- Keeping all logic in a SwiftPM package means TDD loops run with `swift test -j 2` (seconds, no Xcode project),
  and the same targets are linked into the app. The app target has no test target, so package products are linked
  exactly once (no duplicate-class problems from hosted test bundles).
- The generated `ArktShell.xcodeproj` and `App/Info.plist` are build artifacts: they are gitignored and every build
  step starts with `xcodegen generate`. `project.yml` is the single source of truth.

## Rules (apply to every task)

| Name | Path |
|---|---|
| `$REPO` | `/path/to/arkt-wt/track-c` (git worktree, branch `track-c`) |
| `$APP` | `$REPO/app/ArktShell` |
| `$KIT` | `$APP/ShellKit` |
| `$DD` | `$APP/build` (xcodebuild `-derivedDataPath`) |

- Shell is zsh. Define the variables once per shell:
  `REPO=/path/to/arkt-wt/track-c; APP=$REPO/app/ArktShell; KIT=$APP/ShellKit; DD=$APP/build`
- A Chromium build is saturating the CPU. Always use low parallelism: `swift build -j 2`, `swift test -j 2`,
  `xcodebuild -jobs 2`. Optionally prefix with `nice -n 10`. Never run two builds at once.
- Target macOS 15.0+ (`platforms: [.macOS(.v15)]`, `MACOSX_DEPLOYMENT_TARGET = 15.0`). Swift 6 language mode,
  complete concurrency checking (default in Swift 6 mode).
- No third-party dependencies. No TCA yet: state lives in `@MainActor` controllers; reducers arrive with the real
  app after the Chromium build frees the CPU (design section 1 still holds for the product).
- Hot paths are AppKit + Core Animation. No SwiftUI lists, no SwiftUI drag and drop. Frames for hot-path views are
  set directly (`setFrameOrigin` / `frame =`), not via Auto Layout constraints.
- WebKit isolation is enforced, not asserted: only `ShellKit/Sources/FakeEngineKit/FakeEngine.swift` may
  `import WebKit`. `FakeEngine`'s public API exposes only `EngineAPI` types and `NSView`. The test
  `IsolationTests/WebKitIsolationTests` and this command must pass at the end of every task from C1 on:
  ```zsh
  grep -rlE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+([a-z]+[[:space:]]+)?WebKit' $APP --include='*.swift' | grep -v '/\.build/' | grep -v '/build/' | grep -v 'WebKitIsolationTests.swift' | grep -v 'ShellKit/Sources/FakeEngineKit/FakeEngine.swift'
  ```
  Expected: no output. Guard against a vacuous pass (a regex that matches nothing also prints nothing): run the same
  command without the last `| grep -v '...FakeEngine.swift'` stage; from C1 on it must print exactly one path,
  `.../ShellKit/Sources/FakeEngineKit/FakeEngine.swift`. The Swift test `WebKitIsolationTests` is the real gate.
- Prototype signing: ad-hoc (`CODE_SIGN_IDENTITY = "-"`), App Sandbox off, hardened runtime off (example.com needs
  network; no entitlements needed without the sandbox). Product signing is a later track.
- No emojis anywhere (code, comments, commit messages). Commit after every task. Plain commit messages.
- Values marked `TODO(measure)` come from approximate screenshots (+-2 pt); values marked `TODO(parity)` are
  placeholders until the spring constants are matched to Arc's behavior. Each such constant lives in exactly one
  place (`ShellMetrics`, `ShellTokens`, `SpringPreset`) so retuning is a one-line change.
- Tests that create windows, panels, WKWebViews or display links live in the XCTest target `ShellKitGUITests` and
  need a logged-in GUI session (they are skipped in headless CI with `--skip ShellKitGUITests`). All other tests are
  pure Swift Testing tests.

## Cross-track notes

- **Track B** (`app/ArktCore`, `SidebarModel`): not duplicated. ShellUI defines only the read/append surface it
  renders (`SidebarSource`) and a `StubSidebar`. Writing `TrackBSidebarSource` (a class wrapping Track B's value-type
  `Sidebar` and conforming to `SidebarSource`) is explicitly out of scope until Track B merges; the matching names
  make it a single small file.
- **`.gitignore`**: Track B appends `.build/` and `.swiftpm/`; this plan appends the same two lines plus
  ArktShell-specific ones. Expect a trivial merge conflict; keep the union.
- **Results**: Track B writes counts to `docs/plans/2026-10-22-week1-results.md`. To avoid conflicts, Track C writes
  its smoke numbers to its own file `docs/plans/2026-10-22-track-c-results.md`.

## Parity IDs this shell implements (from `docs/spec/arc-parity-spec.md`)

| ID | Behavior in the shell | Task |
|---|---|---|
| KB-001, BH-100 | Cmd-T opens the command bar (empty); Enter opens the result as a new Today tab | C5 |
| KB-002, BH-101 | Cmd-L opens the bar prefilled with the current URL; Enter navigates the current tab | C5 |
| KB-003, BH-103 | Cmd-T or Cmd-L while the bar is open closes it (SINGLE-SOURCE) | C5 |
| KB-004, BH-102 | Cmd-L then Enter without editing reloads the page | C5 |
| KB-084 | Esc closes the bar (NEEDS-RUNTIME-CHECK; implemented as the obvious behavior) | C5 |
| KB-033, KB-034 | Cmd-Opt-Right / Cmd-Opt-Left: next / previous Space | C6 |
| KB-035, BH-041 | Ctrl-1 ... Ctrl-9: go to Space N | C6 |
| BH-035 | Two-finger horizontal swipe in the sidebar switches Space | C6 |
| BH-040 | Space icon animates during the swipe (only the dot indicator here; icons later) | C6 |

## Target file tree (end state)

```
app/ArktShell/
  project.yml
  App/
    main.swift
    AppDelegate.swift
    MainMenu.swift
    SmokeRunner.swift                     (C7)
  ShellKit/
    Package.swift
    Sources/
      EngineAPI/
        EngineClient.swift                (protocol, TabID, TabSnapshot, EngineEvent)
        EngineEventHub.swift              (observer fan-out, terminal tabClosed)
      EngineAPITestSupport/
        InMemoryEngine.swift
        EngineContract.swift              (reusable contract checks)
        EventRecorder.swift
      FakeEngineKit/
        FakeEngine.swift                  (the ONLY WebKit import)
      Motion/
        SpringParameters.swift
        SpringPreset.swift
        SpringSolver.swift
        SpringAnimationFactory.swift
        SpringDriver.swift
      ShellUI/
        Theme/ShellTokens.swift, Theme/RGBA.swift, Theme/ThemeBackgroundView.swift
        Window/ShellMetrics.swift, Window/ShellLayout.swift, Window/ShellWindow.swift,
        Window/ShellRootView.swift, Window/ContentCardView.swift, Window/SidebarResizeHandle.swift,
        Window/ShellWindowController.swift
        Sidebar/SidebarSource.swift, Sidebar/StubSidebar.swift, Sidebar/TabRowState.swift,
        Sidebar/SidebarRowView.swift, Sidebar/SidebarTabCellView.swift, Sidebar/SidebarOutlineController.swift,
        Sidebar/FavoritesLayout.swift, Sidebar/FavoritesGridView.swift, Sidebar/SpacePageView.swift,
        Sidebar/SidebarContainerView.swift, Sidebar/SidebarScrollView.swift
        CommandBar/CommandBarGeometry.swift, CommandBar/URLInputParser.swift, CommandBar/CommandBarResults.swift,
        CommandBar/CommandBarPanel.swift, CommandBar/CommandBarView.swift, CommandBar/CommandBarController.swift
        Spaces/PagingMath.swift, Spaces/VelocityTracker.swift, Spaces/SpacePagerView.swift
        Perf/FrameStats.swift, Perf/FramePacer.swift, Perf/ShellSignposts.swift
    Tests/
      EngineAPITests/      MotionTests/      ShellUITests/      IsolationTests/
      ShellKitGUITests/    (XCTest: FakeEngine contract, window chrome, sidebar, command bar timing, pager)
```

---

### Task C0: Scaffold the package and the app project

**Files:**
- Create: `app/ArktShell/project.yml`
- Create: `app/ArktShell/App/main.swift`, `app/ArktShell/App/AppDelegate.swift`, `app/ArktShell/App/MainMenu.swift`
- Create: `app/ArktShell/ShellKit/Package.swift`
- Create: one placeholder source per target and one smoke test per test target (below)
- Modify: `.gitignore`

**Step 1: Confirm tools**

Run:
```zsh
which xcodegen && xcodegen --version && xcodebuild -version | head -1 && swift --version 2>&1 | head -1
```
Expected: `/opt/homebrew/bin/xcodegen`, a `Version: 2.x` line, `Xcode 27.1`, `Apple Swift version 6.4 ...`.
If `xcodegen` is missing: `brew install xcodegen` and rerun.

**Step 2: `.gitignore` additions** (append; keep existing lines)
```
.build/
.swiftpm/
app/ArktShell/ArktShell.xcodeproj/
app/ArktShell/App/Info.plist
app/ArktShell/build/
```

**Step 3: `ShellKit/Package.swift`**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ShellKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EngineAPI", targets: ["EngineAPI"]),
    .library(name: "FakeEngineKit", targets: ["FakeEngineKit"]),
    .library(name: "Motion", targets: ["Motion"]),
    .library(name: "ShellUI", targets: ["ShellUI"]),
  ],
  targets: [
    .target(name: "EngineAPI"),
    .target(name: "EngineAPITestSupport", dependencies: ["EngineAPI"]),
    .target(name: "FakeEngineKit", dependencies: ["EngineAPI"]),
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["EngineAPI", "Motion"]),
    .testTarget(name: "EngineAPITests", dependencies: ["EngineAPI", "EngineAPITestSupport"]),
    .testTarget(name: "MotionTests", dependencies: ["Motion"]),
    .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "EngineAPITestSupport"]),
    .testTarget(name: "IsolationTests"),
    .testTarget(
      name: "ShellKitGUITests",
      dependencies: ["ShellUI", "FakeEngineKit", "EngineAPITestSupport", "Motion"]
    ),
  ]
)
```
Module names deliberately differ from the main type names (`EngineAPI` vs. protocol `EngineClient`,
`FakeEngineKit` vs. class `FakeEngine`): a module and a type with the same name make `Module.Type` lookups ambiguous.

**Step 4: Placeholders**

- `Sources/EngineAPI/EngineClient.swift`: `public enum EngineAPIVersion { public static let current = 1 }`
- `Sources/EngineAPITestSupport/InMemoryEngine.swift`: `import EngineAPI` + `public enum EngineAPITestSupportVersion { public static let current = 1 }`
- `Sources/FakeEngineKit/FakeEngine.swift`: `import EngineAPI` + `public enum FakeEngineKitVersion { public static let current = 1 }`
- `Sources/Motion/SpringParameters.swift`: `public enum MotionVersion { public static let current = 1 }`
- `Sources/ShellUI/Window/ShellMetrics.swift`: `import AppKit` + `public enum ShellUIVersion { public static let current = 1 }`
- Each Swift Testing target gets `SmokeTests.swift`, e.g.
  ```swift
  import Testing
  @testable import Motion
  @Test func motionVersionIsOne() { #expect(MotionVersion.current == 1) }
  ```
  (`IsolationTests/SmokeTests.swift`: `@Test func runs() { #expect(true) }`.)
- `Tests/ShellKitGUITests/GUISmokeTests.swift`:
  ```swift
  import AppKit
  import XCTest
  @testable import ShellUI

  @MainActor
  final class GUISmokeTests: XCTestCase {
    func testCanCreateWindow() {
      _ = NSApplication.shared
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
      XCTAssertEqual(window.frame.width, 200)
    }
  }
  ```

**Step 5: App sources**

`App/main.swift` (top-level code in `main.swift` is main-actor isolated in Swift 6):
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

`App/AppDelegate.swift` (grows in later tasks):
```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    window.title = "Arkt Shell"
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

`App/MainMenu.swift` (no nib; the Edit menu is required for copy/paste in the command bar field):
```swift
import AppKit

@MainActor
enum MainMenu {
  static func make() -> NSMenu {
    let main = NSMenu()
    main.addItem(submenu(title: "Arkt Shell", items: [
      item("Quit Arkt Shell", #selector(NSApplication.terminate(_:)), "q"),
    ]))
    main.addItem(submenu(title: "Edit", items: [
      item("Undo", Selector(("undo:")), "z"),
      item("Redo", Selector(("redo:")), "Z"),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ]))
    return main
  }

  static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
    let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    holder.submenu = menu
    return holder
  }

  static func item(_ title: String, _ action: Selector, _ key: String,
                   _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }
}
```

**Step 6: `project.yml`**
```yaml
name: ArktShell
options:
  bundleIdPrefix: dev.arkt
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_APP_SANDBOX: NO
    DEAD_CODE_STRIPPING: YES
packages:
  ShellKit:
    path: ShellKit
targets:
  ArktShell:
    type: application
    platform: macOS
    sources:
      - path: App
        excludes: ["Info.plist"]
    info:
      path: App/Info.plist
      properties:
        CFBundleName: Arkt Shell
        CFBundleDisplayName: Arkt Shell
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "15.0"
        NSPrincipalClass: NSApplication
        NSHighResolutionCapable: true
        LSApplicationCategoryType: public.app-category.productivity
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.arkt.ArktShell
        PRODUCT_NAME: ArktShell
    dependencies:
      - package: ShellKit
        product: ShellUI
      - package: ShellKit
        product: FakeEngineKit
      - package: ShellKit
        product: EngineAPI
schemes:
  ArktShell:
    build:
      targets:
        ArktShell: all
    run:
      config: Debug
```

**Step 7: Run package tests**

Run: `cd $KIT && swift test -j 2`
Expected: Swift Testing reports `Test run with 4 tests passed`; XCTest reports `Executed 1 test, with 0 failures`.

**Step 8: Generate and build the app**

Run:
```zsh
cd $APP && xcodegen generate && xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Debug -derivedDataPath $DD -jobs 2 build 2>&1 | tail -3
plutil -p $DD/Build/Products/Debug/ArktShell.app/Contents/Info.plist | grep -E 'CFBundleIdentifier|NSPrincipalClass'
```
Expected: `Created project at .../ArktShell.xcodeproj`, `** BUILD SUCCEEDED **`, then
`"CFBundleIdentifier" => "dev.arkt.ArktShell"` and `"NSPrincipalClass" => "NSApplication"`.

**Step 9: Launch**

Run: `open $DD/Build/Products/Debug/ArktShell.app`
Expected: a titled 1200x800 window "Arkt Shell" appears with a Dock icon; Cmd-Q quits.

**Step 10: Commit**
```zsh
cd $REPO && git status --short   # must NOT list ArktShell.xcodeproj, App/Info.plist or build/
git add .gitignore app/ArktShell && git commit -m "Scaffold ArktShell app and ShellKit package"
```

---

### Task C1: EngineClient protocol, in-memory engine, contract suite, FakeEngine

Design section 1: `EngineClient` is the only thing the UI talks to. Contract decisions (each is a test):

1. `createTab(url:)` returns a fresh `TabID`, appends it to `tabIDs` (creation order), and emits `.tabCreated` before
   any other event for that tab.
2. `navigate` emits `.urlChanged(url)` and `.loadingChanged(true)` (in that order); completion emits
   `.titleChanged` (when it changed) and then `.loadingChanged(false)`. `snapshot(of:)` agrees with the last events.
3. `contentView(for:)` returns the same `NSView` instance for the life of the tab (the UI reparents it freely).
4. `closeTab` is terminal: emits `.tabClosed` exactly once; afterwards the tab is absent from `tabIDs`,
   `snapshot(of:)` and `contentView(for:)` return nil, and no further event for that id is ever delivered.
5. Cancelling an `EngineObservation` stops delivery to that handler only.

Why observer closures and not `AsyncStream`: the UI needs synchronous, ordered, main-thread delivery (design
section 4 batches engine events per display frame; batching is easy to add inside `EngineEventHub`, impossible to
undo after an async hop). Favicons travel as `Data` (PNG/ICO bytes), not `NSImage`, so every event is `Sendable`.

**Files:**
- Modify: `ShellKit/Sources/EngineAPI/EngineClient.swift`
- Create: `ShellKit/Sources/EngineAPI/EngineEventHub.swift`
- Modify: `ShellKit/Sources/EngineAPITestSupport/InMemoryEngine.swift`
- Create: `ShellKit/Sources/EngineAPITestSupport/EventRecorder.swift`, `.../EngineContract.swift`
- Modify: `ShellKit/Sources/FakeEngineKit/FakeEngine.swift`
- Test: `ShellKit/Tests/EngineAPITests/InMemoryEngineContractTests.swift`, `.../EngineEventHubTests.swift`
- Test: `ShellKit/Tests/ShellKitGUITests/FakeEngineContractTests.swift`
- Test: `ShellKit/Tests/IsolationTests/WebKitIsolationTests.swift`
- Delete: the C0 placeholder enums and smoke tests in `EngineAPITests`, `IsolationTests`

**Step 1: Write the failing isolation test** `Tests/IsolationTests/WebKitIsolationTests.swift`
```swift
import Foundation
import Testing

struct WebKitIsolationTests {
  /// app/ArktShell, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/IsolationTests/WebKitIsolationTests.swift
  static let appRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  static let allowed = "ShellKit/Sources/FakeEngineKit/FakeEngine.swift"
  static let importPattern = #"(?m)^\s*(@\w+\s+)*import\s+(\w+\s+)?WebKit\b"#

  @Test func onlyFakeEngineImportsWebKit() throws {
    let files = try #require(FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    var allowedFileImports = false
    for case let url as URL in files where url.pathExtension == "swift" {
      let path = url.path
      if path.contains("/.build/") || path.contains("/build/") || path.hasSuffix("WebKitIsolationTests.swift") {
        continue
      }
      let text = try String(contentsOf: url, encoding: .utf8)
      guard text.range(of: Self.importPattern, options: .regularExpression) != nil else { continue }
      if path.hasSuffix(Self.allowed) { allowedFileImports = true } else { offenders.append(path) }
    }
    #expect(offenders.isEmpty, "WebKit imported outside FakeEngine.swift: \(offenders)")
    #expect(allowedFileImports, "FakeEngine.swift should be the one WebKit importer")
  }
}
```

**Step 2: Write the failing contract tests**

`Tests/EngineAPITests/InMemoryEngineContractTests.swift`:
```swift
import Testing
import EngineAPI
@testable import EngineAPITestSupport

@MainActor
struct InMemoryEngineContractTests {
  let harness = EngineHarness.inMemory()

  @Test func createdTabIsListedAndAnnounced() async throws { try await EngineContract.createdTabIsListedAndAnnounced(harness) }
  @Test func navigateReportsURLLoadingAndTitle() async throws { try await EngineContract.navigateReportsURLLoadingAndTitle(harness) }
  @Test func contentViewIsStable() async throws { try await EngineContract.contentViewIsStable(harness) }
  @Test func closeIsTerminal() async throws { try await EngineContract.closeIsTerminal(harness) }
  @Test func cancelledObservationStopsDelivery() async throws { try await EngineContract.cancelledObservationStopsDelivery(harness) }
  @Test func tabIDsKeepCreationOrder() async throws { try await EngineContract.tabIDsKeepCreationOrder(harness) }
}
```

`Tests/EngineAPITests/EngineEventHubTests.swift`:
```swift
import Testing
@testable import EngineAPI

@MainActor
struct EngineEventHubTests {
  @Test func deliversInRegistrationOrder() {
    let hub = EngineEventHub()
    var log: [String] = []
    let a = hub.add { _ in log.append("a") }
    let b = hub.add { _ in log.append("b") }
    hub.emit(.tabCreated(TabID()))
    #expect(log == ["a", "b"])
    a.cancel(); b.cancel()
  }

  @Test func dropsEventsAfterTabClosed() {
    let hub = EngineEventHub()
    var events: [EngineEvent] = []
    let token = hub.add { events.append($0) }
    let id = TabID()
    hub.emit(.tabClosed(id))
    hub.emit(.titleChanged(id, "late"))
    hub.emit(.tabClosed(id))
    #expect(events == [.tabClosed(id)])
    token.cancel()
  }
}
```

`Tests/ShellKitGUITests/FakeEngineContractTests.swift` (XCTest so the main run loop spins for WKWebView):
```swift
import AppKit
import XCTest
import EngineAPI
import FakeEngineKit
@testable import EngineAPITestSupport

@MainActor
final class FakeEngineContractTests: XCTestCase {
  var harness: EngineHarness!

  override func setUp() async throws {
    _ = NSApplication.shared
    harness = EngineHarness.fake()
  }

  func testCreatedTabIsListedAndAnnounced() async throws { try await EngineContract.createdTabIsListedAndAnnounced(harness) }
  func testNavigateReportsURLLoadingAndTitle() async throws { try await EngineContract.navigateReportsURLLoadingAndTitle(harness) }
  func testContentViewIsStable() async throws { try await EngineContract.contentViewIsStable(harness) }
  func testCloseIsTerminal() async throws { try await EngineContract.closeIsTerminal(harness) }
  func testCancelledObservationStopsDelivery() async throws { try await EngineContract.cancelledObservationStopsDelivery(harness) }
  func testTabIDsKeepCreationOrder() async throws { try await EngineContract.tabIDsKeepCreationOrder(harness) }
}

extension EngineHarness {
  /// Pages are local files, so the contract never touches the network.
  @MainActor static func fake() -> EngineHarness {
    let dir = FileManager.default.temporaryDirectory.appending(path: "arkt-fake-engine-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return EngineHarness(
      makeEngine: { FakeEngine() },
      pageURL: { title in
        let url = dir.appending(path: "\(title).html")
        try "<!doctype html><title>\(title)</title><p>\(title)</p>".write(to: url, atomically: true, encoding: .utf8)
        return url
      },
      settle: { engine, id in
        try await EngineContract.waitUntil(timeout: .seconds(10)) {
          engine.snapshot(of: id).map { !$0.isLoading && !$0.title.isEmpty } ?? true
        }
      }
    )
  }
}
```

**Step 3: Run to verify failure**

Run: `cd $KIT && swift test -j 2 2>&1 | tail -15`
Expected: compile errors (`cannot find 'EngineHarness'`, `cannot find type 'EngineEventHub'`).

**Step 4: Implement `EngineAPI`**

`Sources/EngineAPI/EngineClient.swift`:
```swift
import AppKit

/// Opaque per-tab identity issued by the engine.
public struct TabID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// Latest known state of a tab. Value type; safe to hand to any layer.
public struct TabSnapshot: Equatable, Sendable {
  public var id: TabID
  public var url: URL?
  public var title: String
  /// Raw favicon bytes (PNG or ICO). Data, not NSImage, so snapshots stay Sendable.
  public var faviconData: Data?
  public var isLoading: Bool

  public init(id: TabID, url: URL? = nil, title: String = "", faviconData: Data? = nil, isLoading: Bool = false) {
    self.id = id; self.url = url; self.title = title; self.faviconData = faviconData; self.isLoading = isLoading
  }
}

public enum EngineEvent: Equatable, Sendable {
  case tabCreated(TabID)
  case tabClosed(TabID)
  case urlChanged(TabID, URL?)
  case titleChanged(TabID, String)
  case faviconChanged(TabID, Data?)
  case loadingChanged(TabID, isLoading: Bool)

  public var tabID: TabID {
    switch self {
    case .tabCreated(let id), .tabClosed(let id), .urlChanged(let id, _), .titleChanged(let id, _),
         .faviconChanged(let id, _), .loadingChanged(let id, _):
      return id
    }
  }
}

/// Handle returned by `observe`. Call `cancel()` to stop delivery; keep it alive otherwise.
@MainActor
public final class EngineObservation {
  private var onCancel: (@MainActor () -> Void)?
  init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }
  public func cancel() { onCancel?(); onCancel = nil }
}

/// The only surface the UI uses to talk to a browser engine (design section 1).
/// Implementations: FakeEngine (WKWebView stand-in), InMemoryEngine (tests), ChromiumEngine (later).
@MainActor
public protocol EngineClient: AnyObject {
  /// Open tabs in creation order.
  var tabIDs: [TabID] { get }
  @discardableResult func createTab(url: URL?) -> TabID
  func closeTab(_ id: TabID)
  func navigate(_ id: TabID, to url: URL)
  func reload(_ id: TabID)
  func snapshot(of id: TabID) -> TabSnapshot?
  /// The view that draws the tab's page. Same instance for the tab's whole life; nil once closed.
  func contentView(for id: TabID) -> NSView?
  /// Synchronous, ordered, main-thread delivery of every event.
  func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation
}
```

`Sources/EngineAPI/EngineEventHub.swift`:
```swift
import Foundation

/// Fan-out used by engine implementations. Guarantees contract rule 4: nothing after `.tabClosed`.
/// Per-frame batching (design section 4) will be added here, not in the UI.
@MainActor
public final class EngineEventHub {
  private var handlers: [(key: UUID, handler: @MainActor (EngineEvent) -> Void)] = []
  private var closed: Set<TabID> = []

  public init() {}

  public func add(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    let key = UUID()
    handlers.append((key, handler))
    return EngineObservation { [weak self] in self?.handlers.removeAll { $0.key == key } }
  }

  public func emit(_ event: EngineEvent) {
    guard !closed.contains(event.tabID) else { return }
    if case .tabClosed(let id) = event { closed.insert(id) }
    for entry in handlers { entry.handler(event) }
  }
}
```

**Step 5: Implement `EngineAPITestSupport`**

`InMemoryEngine.swift`:
```swift
import AppKit
import EngineAPI

/// Pure in-memory engine for tests and previews. Loads complete only when `finishLoad` is called,
/// which makes event order fully deterministic.
@MainActor
public final class InMemoryEngine: EngineClient {
  private var snapshots: [TabID: TabSnapshot] = [:]
  private var views: [TabID: NSView] = [:]
  private let hub = EngineEventHub()
  public private(set) var tabIDs: [TabID] = []

  public init() {}

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    let id = TabID()
    snapshots[id] = TabSnapshot(id: id)
    tabIDs.append(id)
    hub.emit(.tabCreated(id))
    if let url { navigate(id, to: url) }
    return id
  }

  public func closeTab(_ id: TabID) {
    guard snapshots.removeValue(forKey: id) != nil else { return }
    tabIDs.removeAll { $0 == id }
    views[id]?.removeFromSuperview()
    views[id] = nil
    hub.emit(.tabClosed(id))
  }

  public func navigate(_ id: TabID, to url: URL) {
    guard snapshots[id] != nil else { return }
    snapshots[id]?.url = url
    snapshots[id]?.isLoading = true
    hub.emit(.urlChanged(id, url))
    hub.emit(.loadingChanged(id, isLoading: true))
  }

  public func reload(_ id: TabID) {
    guard snapshots[id]?.url != nil else { return }
    snapshots[id]?.isLoading = true
    hub.emit(.loadingChanged(id, isLoading: true))
  }

  /// Test hook: completes the pending load the way a real engine would.
  public func finishLoad(_ id: TabID, title: String, favicon: Data? = nil) {
    guard let current = snapshots[id] else { return }
    if current.title != title {
      snapshots[id]?.title = title
      hub.emit(.titleChanged(id, title))
    }
    if let favicon {
      snapshots[id]?.faviconData = favicon
      hub.emit(.faviconChanged(id, favicon))
    }
    snapshots[id]?.isLoading = false
    hub.emit(.loadingChanged(id, isLoading: false))
  }

  public func snapshot(of id: TabID) -> TabSnapshot? { snapshots[id] }

  public func contentView(for id: TabID) -> NSView? {
    guard snapshots[id] != nil else { return nil }
    if let view = views[id] { return view }
    let view = NSView()
    view.identifier = NSUserInterfaceItemIdentifier("in-memory-tab-\(id)")
    views[id] = view
    return view
  }

  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation {
    hub.add(handler)
  }
}
```

`EventRecorder.swift`:
```swift
import EngineAPI

@MainActor
public final class EventRecorder {
  public private(set) var events: [EngineEvent] = []
  private var token: EngineObservation?

  public init(_ engine: any EngineClient) {
    token = engine.observe { [weak self] in self?.events.append($0) }
  }

  public func events(for id: TabID) -> [EngineEvent] { events.filter { $0.tabID == id } }
  public func stop() { token?.cancel(); token = nil }
}
```

`EngineContract.swift` (throws instead of using `#expect` so it works from Swift Testing and XCTest alike):
```swift
import AppKit
import EngineAPI

public struct ContractViolation: Error, CustomStringConvertible {
  public let description: String
}

/// Everything an engine-specific test needs to drive the shared contract.
@MainActor
public struct EngineHarness {
  public let makeEngine: @MainActor () -> any EngineClient
  /// A URL whose page has `<title>title</title>` and needs no network.
  public let pageURL: @MainActor (_ title: String) throws -> URL
  /// Drives (in-memory) or waits for (real engines) the end of the current load of `id`.
  public let settle: @MainActor (_ engine: any EngineClient, _ id: TabID) async throws -> Void

  public init(makeEngine: @escaping @MainActor () -> any EngineClient,
              pageURL: @escaping @MainActor (String) throws -> URL,
              settle: @escaping @MainActor (any EngineClient, TabID) async throws -> Void) {
    self.makeEngine = makeEngine; self.pageURL = pageURL; self.settle = settle
  }

  public static func inMemory() -> EngineHarness {
    EngineHarness(
      makeEngine: { InMemoryEngine() },
      pageURL: { title in URL(string: "arkt-test://page/\(title)")! },
      settle: { engine, id in
        guard let engine = engine as? InMemoryEngine, let url = engine.snapshot(of: id)?.url else { return }
        engine.finishLoad(id, title: url.lastPathComponent)
      }
    )
  }
}

@MainActor
public enum EngineContract {
  static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw ContractViolation(description: message()) }
  }

  /// Polls while yielding the main actor, so run-loop driven engines (WKWebView) make progress.
  public static func waitUntil(timeout: Duration, _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      if ContinuousClock.now > deadline { throw ContractViolation(description: "timed out after \(timeout)") }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  public static func createdTabIsListedAndAnnounced(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    try require(engine.tabIDs == [id], "tabIDs should be [id], got \(engine.tabIDs)")
    try require(recorder.events(for: id).first == .tabCreated(id), "first event must be tabCreated")
    try require(engine.snapshot(of: id) != nil, "snapshot of a live tab must exist")
  }

  public static func navigateReportsURLLoadingAndTitle(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    let url = try h.pageURL("ContractPage")
    engine.navigate(id, to: url)
    try await h.settle(engine, id)
    let events = recorder.events(for: id)
    let urlIndex = events.firstIndex { if case .urlChanged(_, let u) = $0 { return u == url }; return false }
    let startIndex = events.firstIndex(of: .loadingChanged(id, isLoading: true))
    let endIndex = events.lastIndex(of: .loadingChanged(id, isLoading: false))
    let titleIndex = events.firstIndex(of: .titleChanged(id, "ContractPage"))
    try require(urlIndex != nil && startIndex != nil && endIndex != nil && titleIndex != nil,
                "missing url/loading/title events: \(events)")
    try require(urlIndex! < endIndex! && startIndex! < endIndex!, "load must finish after it starts: \(events)")
    try require(titleIndex! < endIndex!, "title must be reported before loading ends: \(events)")
    let snap = try requireValue(engine.snapshot(of: id))
    try require(snap.url == url && snap.title == "ContractPage" && !snap.isLoading, "snapshot disagrees: \(snap)")
  }

  public static func contentViewIsStable(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let id = engine.createTab(url: nil)
    let first = try requireValue(engine.contentView(for: id))
    let host = NSView()
    host.addSubview(first)
    try require(engine.contentView(for: id) === first, "contentView must keep its identity")
  }

  public static func closeIsTerminal(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let recorder = EventRecorder(engine)
    let id = engine.createTab(url: nil)
    engine.closeTab(id)
    let late = try h.pageURL("AfterClose")
    engine.navigate(id, to: late)
    engine.closeTab(id)
    try await Task.sleep(for: .milliseconds(50))
    try require(!engine.tabIDs.contains(id), "closed tab still listed")
    try require(engine.snapshot(of: id) == nil && engine.contentView(for: id) == nil, "closed tab still resolvable")
    let closes = recorder.events(for: id).filter { $0 == .tabClosed(id) }.count
    try require(closes == 1 && recorder.events(for: id).last == .tabClosed(id), "tabClosed must be last and once")
  }

  public static func cancelledObservationStopsDelivery(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    var count = 0
    let token = engine.observe { _ in count += 1 }
    engine.createTab(url: nil)
    token.cancel()
    engine.createTab(url: nil)
    try require(count == 1, "expected 1 event before cancel, got \(count)")
  }

  public static func tabIDsKeepCreationOrder(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let a = engine.createTab(url: nil), b = engine.createTab(url: nil), c = engine.createTab(url: nil)
    engine.closeTab(b)
    try require(engine.tabIDs == [a, c], "order broken: \(engine.tabIDs)")
  }

  static func requireValue<T>(_ value: T?, _ what: String = "value") throws -> T {
    guard let value else { throw ContractViolation(description: "missing \(what)") }
    return value
  }
}
```
In Swift Testing, a thrown `ContractViolation` fails the test with its description; in XCTest an `async throws` test
method fails the same way.

Two FakeEngine risks to pre-empt, both fixed in the harness, never by weakening the contract:
- `FileManager.temporaryDirectory` lives under `/var/...`, a symlink to `/private/var/...`. If WKWebView reports the
  resolved path and `snap.url == url` fails, return `url.resolvingSymlinksInPath()` from the fake harness's `pageURL`.
- If WKWebView never finishes loading under `swift test` (the async XCTest method not spinning the main run loop),
  make the fake harness's `settle` spin it explicitly: loop `RunLoop.main.run(until: Date().addingTimeInterval(0.01))`
  until the condition holds or 10 s pass. Do not move these tests into an app-hosted test bundle: that links the
  static package products twice (app and bundle) and splits type identity.

**Step 6: Run in-memory contract and isolation tests (they pass; FakeEngine still fails to compile)**

Run: `cd $KIT && swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -5`
Expected: 11 Swift Testing tests (6 contract + 2 hub + 1 isolation + the Motion and ShellUI smoke tests from C0):
`10 passed, 1 failed`. The failure is the isolation test's "FakeEngine.swift should be the one WebKit importer"
check, which turns green in Step 7. Any other failure must be fixed first.

**Step 7: Implement `FakeEngine`** (`Sources/FakeEngineKit/FakeEngine.swift`, the only WebKit importer)
```swift
import AppKit
import WebKit
import EngineAPI

/// Development stand-in for the Chromium engine. Renders with WKWebView.
/// Nothing outside this file may import WebKit; the public surface uses EngineAPI types and NSView only.
@MainActor
public final class FakeEngine: EngineClient {
  private final class Entry {
    let webView: WKWebView
    var snapshot: TabSnapshot
    var observations: [NSKeyValueObservation] = []
    init(webView: WKWebView, snapshot: TabSnapshot) { self.webView = webView; self.snapshot = snapshot }
  }

  private var entries: [TabID: Entry] = [:]
  private let hub = EngineEventHub()
  private let configuration: WKWebViewConfiguration
  public private(set) var tabIDs: [TabID] = []

  public init() {
    configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
  }

  @discardableResult
  public func createTab(url: URL?) -> TabID {
    let id = TabID()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    let entry = Entry(webView: webView, snapshot: TabSnapshot(id: id))
    entries[id] = entry
    tabIDs.append(id)
    hub.emit(.tabCreated(id))
    // KVO handlers are not main-actor isolated in the SDK annotations, but WKWebView
    // always reports on the main thread, so assumeIsolated is a checked, correct hop.
    entry.observations = [
      webView.observe(\.url, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated { self?.update(id) { $0.url = web.url } event: { .urlChanged(id, web.url) } }
      },
      webView.observe(\.title, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated {
          let title = web.title ?? ""
          self?.update(id) { $0.title = title } event: { .titleChanged(id, title) }
        }
      },
      webView.observe(\.isLoading, options: [.new]) { [weak self] web, _ in
        MainActor.assumeIsolated {
          let loading = web.isLoading
          self?.update(id) { $0.isLoading = loading } event: { .loadingChanged(id, isLoading: loading) }
          if !loading { self?.fetchFavicon(id) }
        }
      },
    ]
    if let url { navigate(id, to: url) }
    return id
  }

  public func closeTab(_ id: TabID) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.observations.forEach { $0.invalidate() }
    entry.webView.stopLoading()
    entry.webView.removeFromSuperview()
    tabIDs.removeAll { $0 == id }
    hub.emit(.tabClosed(id))
  }

  public func navigate(_ id: TabID, to url: URL) {
    guard let web = entries[id]?.webView else { return }
    if url.isFileURL {
      web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
      web.load(URLRequest(url: url))
    }
  }

  public func reload(_ id: TabID) { entries[id]?.webView.reload() }
  public func snapshot(of id: TabID) -> TabSnapshot? { entries[id]?.snapshot }
  public func contentView(for id: TabID) -> NSView? { entries[id]?.webView }
  public func observe(_ handler: @escaping @MainActor (EngineEvent) -> Void) -> EngineObservation { hub.add(handler) }

  /// Applies a change and emits its event only if the snapshot actually changed.
  private func update(_ id: TabID, _ mutate: (inout TabSnapshot) -> Void, event: () -> EngineEvent) {
    guard let entry = entries[id] else { return }
    var next = entry.snapshot
    mutate(&next)
    guard next != entry.snapshot else { return }
    entry.snapshot = next
    hub.emit(event())
  }

  /// Prototype favicon: <link rel=icon> or /favicon.ico, fetched with URLSession. Real engines push it.
  private func fetchFavicon(_ id: TabID) {
    guard let web = entries[id]?.webView, let pageURL = web.url, !pageURL.isFileURL else { return }
    let script = "(document.querySelector('link[rel~=\"icon\"]') || {}).href || ''"
    web.evaluateJavaScript(script) { [weak self] result, _ in
      MainActor.assumeIsolated {
        let href = (result as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        guard let iconURL = href ?? URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL else { return }
        Task { @MainActor [weak self] in
          guard let (data, _) = try? await URLSession.shared.data(from: iconURL),
                self?.entries[id]?.snapshot.url == pageURL else { return }
          self?.update(id) { $0.faviconData = data } event: { .faviconChanged(id, data) }
        }
      }
    }
  }
}
```
If the compiler rejects a capture (Swift 6 region isolation), keep the shape and fix at the root: capture only
`Sendable` values (`id`, `URL`, `String`, `Data`) into the closures; do not add `@unchecked Sendable` or
`nonisolated(unsafe)`.

**Step 8: Run everything**

Run: `cd $KIT && swift test -j 2 2>&1 | tail -8`
Expected: `Test run with 11 tests passed` and `Executed 7 tests, with 0 failures` (6 FakeEngine contract +
1 GUI smoke). Then run the isolation grep from the Rules section: expected no output.

**Step 9: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add EngineClient protocol, in-memory contract and FakeEngine"
```

---

### Task C2: Window chrome (titleless window, traffic lights in the sidebar, inset content card)

"Borderless" in design section 2 means *visually* borderless. A real `.borderless` window loses the traffic lights,
key-window behavior and resizing, so the shell uses `[.titled, .closable, .miniaturizable, .resizable,
.fullSizeContentView]` + `titlebarAppearsTransparent` + `titleVisibility = .hidden`, then moves the standard window
buttons into the sidebar and re-applies their position after every layout pass, resize and full-screen exit.

Measured (arc-findings "Measured layout"): sidebar ~190 pt; card inset top ~9, right ~10, bottom ~10; card radius
~8-10 pt (use 10, continuous corners); hairline border plus shadow. Border color uses `FloatingScrimBorder`
(black 10% light / white 20% dark), shadow uses `Shadow` (black 20% light / none dark) from the design-system doc 1.1.

**Files:**
- Modify: `ShellKit/Sources/ShellUI/Window/ShellMetrics.swift`
- Create: `.../Window/ShellLayout.swift`, `ShellWindow.swift`, `ShellRootView.swift`, `ContentCardView.swift`,
  `SidebarResizeHandle.swift`, `ShellWindowController.swift`
- Create: `.../Theme/RGBA.swift`, `.../Theme/ShellTokens.swift`
- Modify: `app/ArktShell/App/AppDelegate.swift`
- Test: `ShellKit/Tests/ShellUITests/ShellLayoutTests.swift`, `ShellKit/Tests/ShellKitGUITests/WindowChromeTests.swift`

**Step 1: Failing pure layout tests** `Tests/ShellUITests/ShellLayoutTests.swift`
```swift
import CoreGraphics
import Testing
@testable import ShellUI

struct ShellLayoutTests {
  let metrics = ShellMetrics.standard
  let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)   // flipped: y grows downward

  @Test func sidebarAndInsetCard() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: true, metrics: metrics)
    #expect(layout.sidebarFrame == CGRect(x: 0, y: 0, width: 190, height: 800))
    #expect(layout.cardFrame == CGRect(x: 190, y: 9, width: 1000, height: 781))
    #expect(layout.resizeHandleFrame == CGRect(x: 186, y: 0, width: 8, height: 800))
  }

  @Test func clampsSidebarWidth() {
    let narrow = ShellLayout.compute(bounds: bounds, sidebarWidth: 20, sidebarVisible: true, metrics: metrics)
    let wide = ShellLayout.compute(bounds: bounds, sidebarWidth: 900, sidebarVisible: true, metrics: metrics)
    #expect(narrow.sidebarFrame.width == metrics.sidebarMinWidth)
    #expect(wide.sidebarFrame.width == metrics.sidebarMaxWidth)
  }

  @Test func hiddenSidebarGivesCardEvenInsets() {
    let layout = ShellLayout.compute(bounds: bounds, sidebarWidth: 190, sidebarVisible: false, metrics: metrics)
    #expect(layout.sidebarFrame.width == 0)
    #expect(layout.cardFrame == CGRect(x: 10, y: 9, width: 1180, height: 781))
  }
}
```

**Step 2: Run to verify failure** (`swift test -j 2 --skip ShellKitGUITests --filter ShellLayoutTests`; expected:
`cannot find 'ShellLayout'`).

**Step 3: Implement metrics and layout**

`Window/ShellMetrics.swift`:
```swift
import CoreGraphics

/// Every chrome dimension in one place. Values from arc-findings "Measured layout" (+-2 pt).
public struct ShellMetrics: Sendable, Equatable {
  public var sidebarDefaultWidth: CGFloat
  public var sidebarMinWidth: CGFloat
  public var sidebarMaxWidth: CGFloat
  public var cardInsetTop: CGFloat
  public var cardInsetRight: CGFloat
  public var cardInsetBottom: CGFloat
  public var cardCornerRadius: CGFloat
  public var resizeHandleWidth: CGFloat
  /// Close button origin measured from the window's top-left corner.
  public var trafficLightOrigin: CGPoint
  public var trafficLightSpacing: CGFloat
  /// Height of the sidebar strip that hosts the traffic lights (and later back/forward/reload).
  public var sidebarTopBarHeight: CGFloat

  public static let standard = ShellMetrics(
    sidebarDefaultWidth: 190,
    sidebarMinWidth: 150,          // TODO(measure): Arc's minimum
    sidebarMaxWidth: 400,          // TODO(measure): Arc's maximum
    cardInsetTop: 9,
    cardInsetRight: 10,
    cardInsetBottom: 10,
    cardCornerRadius: 10,
    resizeHandleWidth: 8,
    trafficLightOrigin: CGPoint(x: 16, y: 16),   // TODO(measure)
    trafficLightSpacing: 20,                     // AppKit default pitch
    sidebarTopBarHeight: 44                      // TODO(measure)
  )
}
```

`Window/ShellLayout.swift`:
```swift
import CoreGraphics

/// Pure frame math for the root view (flipped coordinates). No Auto Layout on this hot path.
public struct ShellLayout: Equatable, Sendable {
  public var sidebarFrame: CGRect
  public var cardFrame: CGRect
  public var resizeHandleFrame: CGRect

  public static func clampedWidth(_ width: CGFloat, metrics: ShellMetrics) -> CGFloat {
    min(max(width, metrics.sidebarMinWidth), metrics.sidebarMaxWidth)
  }

  public static func compute(bounds: CGRect, sidebarWidth: CGFloat, sidebarVisible: Bool,
                             metrics: ShellMetrics) -> ShellLayout {
    let width = sidebarVisible ? clampedWidth(sidebarWidth, metrics: metrics) : 0
    let cardX = sidebarVisible ? width : metrics.cardInsetRight
    let card = CGRect(
      x: bounds.minX + cardX,
      y: bounds.minY + metrics.cardInsetTop,
      width: max(0, bounds.width - cardX - metrics.cardInsetRight),
      height: max(0, bounds.height - metrics.cardInsetTop - metrics.cardInsetBottom))
    let handle = sidebarVisible
      ? CGRect(x: width - metrics.resizeHandleWidth / 2, y: bounds.minY, width: metrics.resizeHandleWidth, height: bounds.height)
      : .zero
    return ShellLayout(
      sidebarFrame: CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
      cardFrame: card, resizeHandleFrame: handle)
  }
}
```

**Step 4: Tokens** (`Theme/RGBA.swift`, `Theme/ShellTokens.swift`)

`RGBA` is a `Sendable, Equatable` struct (`red, green, blue, alpha: Double`) with `static func white(_ a:)`,
`black(_ a:)`, `p3(hex:alpha:)`, `var cgColor: CGColor` (sRGB, or Display P3 when built with `p3`; the design-system
doc 1.0 says P3 hex values must be recreated as P3) and `func nsColor() -> NSColor`. `ShellTokens` holds the subset of
design-system tokens the shell uses, each as `light/dark` pairs:
```swift
public enum ThemeFlavor: Sendable { case light, dark }

public struct TokenPair: Sendable, Equatable {
  public let light: RGBA
  public let dark: RGBA
  public func resolve(_ flavor: ThemeFlavor) -> RGBA { flavor == .light ? light : dark }
}

/// Arc's approach (design-system doc 1.1-1.3): chrome is black/white at low alpha over the Space theme.
/// Levels follow Arc's token levels; Arkt owns the values and may diverge.
public enum ShellTokens {
  public static let cardBorder = TokenPair(light: .black(0.10), dark: .white(0.20))       // FloatingScrimBorder
  public static let cardShadow = TokenPair(light: .black(0.20), dark: .black(0))           // Shadow
  public static let sidebarForeground = TokenPair(light: .black(0.30), dark: .white(0.45))
  public static let sidebarItemBackground = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.05), dark: .p3(hex: 0xFAFBFF, alpha: 0.10))
  public static let sidebarItemHovered = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.10), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  public static let primaryText = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.90), dark: .white(0.80))
  public static let secondaryText = TokenPair(light: .black(0.50), dark: .white(0.50))
  // Tab cell states (C3 tests these levels).
  public static let tabCurrent = TokenPair(light: .white(0.85), dark: .p3(hex: 0xFAFBFF, alpha: 0.20))
  public static let tabContentVisible = TokenPair(light: .white(0.70), dark: .p3(hex: 0xFAFBFF, alpha: 0.15))
  public static let tabPrevious = TokenPair(light: .white(0.32), dark: .p3(hex: 0xFAFBFF, alpha: 0.08))
  public static let tabPreviousHovered = TokenPair(light: .white(0.50), dark: .p3(hex: 0xFAFBFF, alpha: 0.12))
  public static let tabPressed = TokenPair(light: .p3(hex: 0x0E0F10, alpha: 0.065), dark: .p3(hex: 0xFAFBFF, alpha: 0.065))
  public static let tabCurrentShadow = TokenPair(light: .black(0.20), dark: .black(0))
  // Command bar (always dark surface, C5).
  public static let commandBarSurface = RGBA.p3(hex: 0x1C1C20, alpha: 0.98)                 // TODO(measure)
  public static let commandBarText = RGBA.white(0.80)
  public static let commandBarSecondaryText = RGBA.white(0.33)
  public static let commandBarDivider = RGBA.white(0.10)
  public static let commandBarSelectedRow = RGBA.white(0.10)                                // TODO(measure)
  public static let commandBarBorder = RGBA.white(0.10)
}
```

**Step 5: Window, root view, card, resize handle**

`Window/ShellWindow.swift`:
```swift
import AppKit

@MainActor
public final class ShellWindow: NSWindow {
  public var metrics = ShellMetrics.standard

  public init(contentRect: NSRect) {
    super.init(contentRect: contentRect,
               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
               backing: .buffered, defer: false)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false   // only the sidebar background drags the window (mouseDownCanMoveWindow)
    tabbingMode = .disallowed
    isReleasedWhenClosed = false
    minSize = NSSize(width: 640, height: 420)
    collectionBehavior.insert(.fullScreenPrimary)
  }

  /// Moves close/minimize/zoom so the close button's top-left sits at `metrics.trafficLightOrigin`
  /// (window coordinates, measured from the top-left). AppKit resets these frames on several events;
  /// ShellRootView.layout() and the window controller call this again each time.
  public func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen) else { return }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    guard let close = standardWindowButton(.closeButton),
          let titlebar = close.superview,                 // NSTitlebarView
          let container = titlebar.superview else { return } // NSTitlebarContainerView
    let origin = metrics.trafficLightOrigin
    // Grow the titlebar container so buttons below the default 28 pt titlebar stay hit-testable.
    let height = origin.y * 2 + close.frame.height
    container.frame = NSRect(x: 0, y: frame.height - height, width: frame.width, height: height)
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let x = origin.x + CGFloat(index) * metrics.trafficLightSpacing
      let y = titlebar.bounds.height - origin.y - button.frame.height   // titlebar view is not flipped
      button.setFrameOrigin(NSPoint(x: x, y: y))
    }
  }
}
```

`Window/ContentCardView.swift`: an `NSView` (layer-backed, `wantsUpdateLayer = true`) that owns a `clipView`
(`layer.cornerRadius = metrics.cardCornerRadius`, `cornerCurve = .continuous`, `masksToBounds = true`,
`borderWidth = 1 / backingScaleFactor` so the hairline is one physical pixel, `borderColor = cardBorder`). The outer
view carries the shadow (`shadowOpacity 1`, `shadowColor = cardShadow`, `shadowRadius 3`, `shadowOffset (0,-1)`,
`shadowPath` = rounded rect updated in `layout()`, which avoids offscreen shadow passes). A `CALayer` border is
drawn above sublayers, so page content never covers the hairline. API:
```swift
public func setContent(_ view: NSView?)   // removes the old subview, adds `view` filling clipView (autoresizing)
```
`updateLayer()` resolves colors with `effectiveAppearance` (`.darkAqua` -> `.dark`), and
`viewDidChangeBackingProperties()` refreshes `borderWidth`.

`Window/SidebarResizeHandle.swift`: 8 pt wide `NSView`, `resetCursorRects` adds `.resizeLeftRight`;
`mouseDown` records the start width, `mouseDragged` calls `onWidthChange(startWidth + deltaX)`; double-click
resets to `sidebarDefaultWidth`.

`Window/ShellRootView.swift`: flipped, layer-backed `NSView` that owns (back to front) `themeBackground` (a plain
layer-backed view filled with a fixed gradient in C2; replaced by `ThemeBackgroundView` in C6), `sidebarContainer`
(an empty `NSView` in C2, replaced in C3), `card`, `resizeHandle`. Stored `sidebarWidth`, `sidebarVisible`.
```swift
public override var isFlipped: Bool { true }
public override func layout() {
  super.layout()
  let l = ShellLayout.compute(bounds: bounds, sidebarWidth: sidebarWidth, sidebarVisible: sidebarVisible,
                              metrics: metrics)
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  themeBackground.frame = bounds
  sidebarContainer.frame = l.sidebarFrame
  card.frame = l.cardFrame
  resizeHandle.frame = l.resizeHandleFrame
  CATransaction.commit()
  (window as? ShellWindow)?.layoutTrafficLights()
}
```
`resizeHandle.onWidthChange = { [weak self] w in self?.sidebarWidth = ShellLayout.clampedWidth(w, metrics: ...);
self?.needsLayout = true }`.

`Window/ShellWindowController.swift` (grows through C3-C6): `NSWindowController`, `NSWindowDelegate`;
`init(engine: any EngineClient)` creates `ShellWindow(contentRect: 1200x800)`, sets `contentView = ShellRootView`,
and re-applies traffic lights in `windowDidResize`, `windowDidEndLiveResize`, `windowDidExitFullScreen`,
`windowDidBecomeKey`. For C2 it creates one tab with `engine.createTab(url: URL(string: "https://example.com"))`
and puts `engine.contentView(for:)` into the card so the chrome is visible around a real page.

**Step 6: GUI tests** `Tests/ShellKitGUITests/WindowChromeTests.swift`
```swift
import AppKit
import XCTest
import EngineAPITestSupport
@testable import ShellUI

@MainActor
final class WindowChromeTests: XCTestCase {
  override func setUp() async throws { _ = NSApplication.shared }

  func testTrafficLightsSitInSidebar() throws {
    let controller = ShellWindowController(engine: InMemoryEngine())
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    window.setContentSize(NSSize(width: 1200, height: 800))
    window.contentView?.layoutSubtreeIfNeeded()
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    let inWindow = close.convert(close.bounds, to: nil)            // window coords, origin bottom-left
    let topLeft = CGPoint(x: inWindow.minX, y: window.frame.height - inWindow.maxY)
    XCTAssertEqual(topLeft.x, 16, accuracy: 0.5)
    XCTAssertEqual(topLeft.y, 16, accuracy: 0.5)
    XCTAssertLessThan(inWindow.maxX, 190, "traffic lights must stay inside the sidebar")
  }

  func testWindowIsTitlelessFullSizeContent() throws {
    let window = try XCTUnwrap(ShellWindowController(engine: InMemoryEngine()).window)
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertEqual(window.titleVisibility, .hidden)
  }

  func testCardHasHairlineAndRadius() throws {
    let controller = ShellWindowController(engine: InMemoryEngine())
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    root.layoutSubtreeIfNeeded()
    let clip = try XCTUnwrap(root.card.clipView.layer)
    XCTAssertEqual(clip.cornerRadius, 10)
    XCTAssertEqual(clip.cornerCurve, .continuous)
    XCTAssertTrue(clip.masksToBounds)
    XCTAssertEqual(clip.borderWidth, 1 / (controller.window?.backingScaleFactor ?? 2), accuracy: 0.001)
    XCTAssertEqual(root.card.frame, CGRect(x: 190, y: 9, width: root.bounds.width - 200, height: root.bounds.height - 19))
  }
}
```

**Step 7: Run tests**

Run: `cd $KIT && swift test -j 2 2>&1 | tail -6`
Expected: all Swift Testing tests pass and `Executed 10 tests, with 0 failures`.

**Step 8: Wire the app** - `AppDelegate.applicationDidFinishLaunching`:
```swift
NSApp.mainMenu = MainMenu.make()
let engine = FakeEngine()                         // import FakeEngineKit; composition root only
let controller = ShellWindowController(engine: engine)
controller.window?.center()
controller.showWindow(nil)
self.controller = controller
NSApp.activate()
```

**Step 9: Build, launch and eyeball**

Run:
```zsh
cd $APP && xcodegen generate && xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Debug -derivedDataPath $DD -jobs 2 build 2>&1 | tail -1 && open $DD/Build/Products/Debug/ArktShell.app
```
Expected: `** BUILD SUCCEEDED **`; window has no title bar, traffic lights at the top-left inside the gradient
sidebar, example.com inside a rounded card with a 1 px border, 9/10/10 pt gaps; dragging the sidebar edge resizes
between 150 and 400 pt; after resizing the window and entering/exiting full screen the traffic lights stay put.
Run the isolation grep: no output.

**Step 10: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add shell window chrome with inset content card"
```

---

### Task C3: Sidebar (favorites grid, pinned + Today outline) on a stub model

**Files:**
- Create: `ShellKit/Sources/ShellUI/Sidebar/SidebarSource.swift`, `StubSidebar.swift`, `TabRowState.swift`,
  `SidebarRowView.swift`, `SidebarTabCellView.swift`, `SidebarOutlineController.swift`, `FavoritesLayout.swift`,
  `FavoritesGridView.swift`, `SpacePageView.swift`, `SidebarContainerView.swift`, `SidebarScrollView.swift`
- Modify: `ShellRootView.swift`, `ShellWindowController.swift`
- Test: `ShellKit/Tests/ShellUITests/SidebarModelStubTests.swift`, `TabRowStateTests.swift`, `FavoritesLayoutTests.swift`
- Test: `ShellKit/Tests/ShellKitGUITests/SidebarViewTests.swift`

**Step 1: Failing pure tests**

`TabRowStateTests.swift`:
```swift
import Foundation
import Testing
@testable import ShellUI

struct TabRowStateTests {
  let a = UUID(), b = UUID(), c = UUID(), d = UUID()

  @Test func resolvesStatePrecedence() {
    let r = TabRowState.Resolver(current: a, visible: [a, b], previous: c)
    #expect(r.state(for: a) == .current)
    #expect(r.state(for: b) == .contentVisible)
    #expect(r.state(for: c) == .previous)
    #expect(r.state(for: d) == .normal)
  }

  @Test func backgroundLevelsMatchArcTokenLevels() {
    #expect(TabRowState.current.background(.light)?.alpha == 0.85)
    #expect(TabRowState.contentVisible.background(.light)?.alpha == 0.70)
    #expect(TabRowState.previous.background(.light)?.alpha == 0.32)
    #expect(TabRowState.current.background(.light)?.red == 1)       // white over the theme in light
    #expect(TabRowState.current.background(.dark)?.alpha == 0.20)
    #expect(TabRowState.normal.background(.light) == nil)
  }

  @Test func rowMetrics() {
    #expect(SidebarMetrics.rowPitch == 41)
    #expect(SidebarMetrics.rowBackgroundHeight == 34)
    #expect(SidebarMetrics.rowBackgroundInsetY == 3.5)
  }
}
```

`FavoritesLayoutTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import ShellUI

struct FavoritesLayoutTests {
  @Test func threeTilesFitDefaultSidebar() {
    // 190 pt sidebar minus 8 pt padding each side = 174 = 3 * 52 + 2 * 9
    #expect(FavoritesLayout.contentWidth(sidebarWidth: 190) == 174)
    #expect(FavoritesLayout.itemSize(contentWidth: 174) == CGSize(width: 52, height: 46))
  }

  @Test func tilesStretchWithSidebar() {
    let size = FavoritesLayout.itemSize(contentWidth: 201)
    #expect(size.height == 46)
    #expect(abs(size.width - 61) < 0.001)
  }

  @Test func gridHeight() {
    #expect(FavoritesLayout.height(itemCount: 0) == 0)
    #expect(FavoritesLayout.height(itemCount: 3) == 46)
    #expect(FavoritesLayout.height(itemCount: 4) == 46 * 2 + 9)
  }
}
```

`SidebarModelStubTests.swift` (the stub honors the Track B-shaped surface):
```swift
import Foundation
import Testing
@testable import ShellUI

@MainActor
struct SidebarModelStubTests {
  @Test func sampleHasThreeSpacesAndFavorites() {
    let s = StubSidebar.sample()
    #expect(s.spaceOrder.count == 3)
    #expect(s.children(of: .favorites(profile: "default")).count == 6)
    let first = s.spaceOrder[0]
    #expect(!s.children(of: .pinned(first)).isEmpty)
    #expect(!s.children(of: .today(first)).isEmpty)
  }

  @Test func addTabAppendsToTodayAndNotifies() {
    let s = StubSidebar.sample()
    let space = s.spaceOrder[1]
    var changed: [SidebarLocation] = []
    s.onChange = { changed.append($0) }
    let id = s.addTab(url: URL(string: "https://example.com")!, title: "Example", in: .today(space))
    #expect(s.children(of: .today(space)).last == id)
    #expect(changed == [.today(space)])
    s.updateTab(id, url: nil, title: "Example Domain")
    #expect(s.node(id) == .tab(id: id, url: URL(string: "https://example.com")!, title: "Example Domain"))
  }
}
```

**Step 2: Run to verify failure** (`swift test -j 2 --skip ShellKitGUITests`; expected: compile errors).

**Step 3: Implement the model surface**

`Sidebar/SidebarSource.swift`:
```swift
import Foundation

public typealias SpaceID = UUID
public typealias NodeID = UUID

/// Mirrors Track B's `SidebarModel.Location` so the later adapter is mechanical.
public enum SidebarLocation: Hashable, Sendable {
  case favorites(profile: String)
  case pinned(SpaceID)
  case today(SpaceID)
  case folder(NodeID)
}

public struct SpaceThemeInfo: Equatable, Sendable {
  /// Gradient stops, top-left to bottom-right (Track B: `SpaceTheme.baseColors`).
  public var baseColors: [RGBA]
  public var isDark: Bool
  public var flavor: ThemeFlavor { isDark ? .dark : .light }
}

public struct SidebarSpaceInfo: Equatable, Sendable {
  public var id: SpaceID
  public var title: String
  public var profile: String
  public var theme: SpaceThemeInfo
}

public enum SidebarNodeInfo: Equatable, Sendable {
  case tab(id: NodeID, url: URL, title: String)
  case folder(id: NodeID, title: String)
}

/// What the shell needs from a sidebar store. Implemented by StubSidebar now and by an adapter over
/// Track B's `Sidebar` value type later (out of scope here).
@MainActor
public protocol SidebarSource: AnyObject {
  var spaceOrder: [SpaceID] { get }
  func space(_ id: SpaceID) -> SidebarSpaceInfo?
  func children(of location: SidebarLocation) -> [NodeID]
  func node(_ id: NodeID) -> SidebarNodeInfo?
  @discardableResult func addTab(url: URL, title: String, in location: SidebarLocation) -> NodeID
  func updateTab(_ id: NodeID, url: URL?, title: String?)
  /// Single observer (the window controller). Called with the location whose children changed.
  var onChange: (@MainActor (SidebarLocation) -> Void)? { get set }
}
```
`Sidebar/StubSidebar.swift`: `final class StubSidebar: SidebarSource` with dictionaries
`spaces`, `nodes`, `childOrder: [SidebarLocation: [NodeID]]`, and `static func sample() -> StubSidebar`:
3 Spaces ("Personal": light, warm stops `#F2EAE4 -> #F29BBB`; "Work": light, cool `#E0F2FB -> #C5C6E2`; "Dev": dark,
`#2D4468 -> #120F2E`; colors from the public palettes in design-system doc 1.7), 6 favorites
(`https://example.com`, `https://www.wikipedia.org`, `https://news.ycombinator.com`, `https://github.com`,
`https://developer.apple.com`, `https://www.swift.org`), per Space 2-3 pinned tabs plus one folder with 2 tabs, and
2-4 Today tabs. All titles invented. `updateTab` calls `onChange` with the node's parent location.

**Step 4: Implement row state, metrics, favorites math**

`Sidebar/TabRowState.swift`:
```swift
import CoreGraphics
import Foundation

public enum SidebarMetrics {
  public static let rowPitch: CGFloat = 41               // measured row pitch
  public static let rowBackgroundHeight: CGFloat = 34    // measured row
  public static var rowBackgroundInsetY: CGFloat { (rowPitch - rowBackgroundHeight) / 2 }
  public static let rowCornerRadius: CGFloat = 9         // TODO(measure)
  public static let horizontalPadding: CGFloat = 8
  public static let faviconSize: CGFloat = 16
  public static let faviconLeading: CGFloat = 10
  public static let titleLeading: CGFloat = 34
  public static let titleFontSize: CGFloat = 14          // measured, medium weight
  public static let spaceTitleFontSize: CGFloat = 12     // measured, secondary, left 16
  public static let indentationPerLevel: CGFloat = 14    // TODO(measure)
}

public enum TabRowState: Sendable, Equatable {
  case current, contentVisible, previous, previousHovered, pressed, normal

  /// Black-or-white at Arc's token levels over the theme; nil = no fill.
  public func background(_ flavor: ThemeFlavor) -> RGBA? {
    switch self {
    case .current: ShellTokens.tabCurrent.resolve(flavor)
    case .contentVisible: ShellTokens.tabContentVisible.resolve(flavor)
    case .previous: ShellTokens.tabPrevious.resolve(flavor)
    case .previousHovered: ShellTokens.tabPreviousHovered.resolve(flavor)
    case .pressed: ShellTokens.tabPressed.resolve(flavor)
    case .normal: nil
    }
  }

  public struct Resolver: Sendable {
    public var current: NodeID?
    public var visible: Set<NodeID>
    public var previous: NodeID?
    public init(current: NodeID?, visible: Set<NodeID>, previous: NodeID?) {
      self.current = current; self.visible = visible; self.previous = previous
    }
    public func state(for id: NodeID) -> TabRowState {
      if id == current { return .current }
      if visible.contains(id) { return .contentVisible }
      if id == previous { return .previous }
      return .normal
    }
  }
}
```

`Sidebar/FavoritesLayout.swift`:
```swift
import CoreGraphics

public enum FavoritesLayout {
  public static let columns = 3
  public static let gap: CGFloat = 9            // measured
  public static let tileHeight: CGFloat = 46    // measured
  public static let tileCornerRadius: CGFloat = 10

  public static func contentWidth(sidebarWidth: CGFloat) -> CGFloat {
    sidebarWidth - 2 * SidebarMetrics.horizontalPadding
  }

  public static func itemSize(contentWidth: CGFloat) -> CGSize {
    let width = (contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
    return CGSize(width: width, height: tileHeight)
  }

  public static func height(itemCount: Int) -> CGFloat {
    guard itemCount > 0 else { return 0 }
    let rows = (itemCount + columns - 1) / columns
    return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
  }
}
```

Run `swift test -j 2 --skip ShellKitGUITests`: expected all pure tests pass.

**Step 5: Implement the AppKit views**

- `SidebarRowView: NSTableRowView` - layer-backed, `wantsUpdateLayer = true`, owns one `backgroundLayer`
  (`frame = bounds.insetBy(dx: 0, dy: SidebarMetrics.rowBackgroundInsetY)`, `cornerRadius = rowCornerRadius`,
  `cornerCurve = .continuous`). Properties `state: TabRowState`, `flavor: ThemeFlavor`, `isHovered` (tracking
  area). `updateLayer()` sets `backgroundLayer.backgroundColor = (isHovered && state == .previous ?
  .previousHovered : state).background(flavor)?.cgColor` (hover on `.normal` uses `sidebarItemHovered`) and the
  `tabCurrentShadow` (radius 2, offset 0/-1) only for `.current`. Override `drawSelection(in:)` to do nothing;
  selection is our `current` state, not AppKit's highlight. Wrap changes in `CATransaction.setDisableActions(true)`.
- `SidebarTabCellView: NSTableCellView` - favicon `NSImageView` 16x16 at x 10 (letter placeholder until a favicon
  arrives), title `NSTextField(labelWithString:)` at x 34, `.systemFont(ofSize: 14, weight: .medium)`,
  `lineBreakMode = .byTruncatingTail`, color `primaryText`. Frames set in `layout()`; no constraints.
- `SidebarOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate` for one Space. NSOutlineView
  compares items by identity, so items are cached `final class OutlineItem { let kind: .node(NodeID) | .divider }`
  instances keyed by `NodeID`. Root children = pinned nodes + one divider item + Today nodes; folders expand.
  `rowHeight = SidebarMetrics.rowPitch`, `intercellSpacing = .zero`, `style = .plain`,
  `selectionHighlightStyle = .none`, `backgroundColor = .clear`, `indentationPerLevel = 14`,
  `floatsGroupRows = false`, header view nil. `outlineView(_:rowViewForItem:)` returns `SidebarRowView` with the
  resolver's state; `outlineView(_:heightOfRowByItem:)` returns 13 for the divider. A click (`action` on
  `clickedRow`) calls `onActivate(NodeID)`. `apply(change: SidebarLocation)` does a targeted
  `reloadItem(_:reloadChildren:)` (or root `insertItems` for appends) - never `reloadData()` after setup (design
  section 4: targeted diffs). `setRowStates(_ resolver:)` updates only visible row views
  (`enumerateAvailableRowViews`).
- `SidebarScrollView: NSScrollView` - vertical only, `drawsBackground = false`, `automaticallyAdjustsContentInsets
  = false`. (C6 adds horizontal-gesture forwarding.)
- `FavoritesGridView` - `NSCollectionView` with `NSCollectionViewFlowLayout` (`minimumInteritemSpacing = 9`,
  `minimumLineSpacing = 9`, `sectionInset = .zero`, `itemSize` from `FavoritesLayout` on every `layout()`),
  `isSelectable = true`, background clear, not inside a scrolling clip (height = `FavoritesLayout.height`). Item
  `FavoriteTileItem: NSCollectionViewItem` - layer radius 10, fill `sidebarItemBackground` (hover:
  `sidebarItemHovered`, current: `tabCurrent`), 20 pt favicon centered.
- `SpacePageView` - one Space page: Space title label (12 pt, `secondaryText`, x 16) then the outline scroll view.
- `SidebarContainerView` (flipped) - `topBar` (44 pt reserved for traffic lights, `mouseDownCanMoveWindow = true`),
  `favorites` (shared across Spaces of the same profile, BH-045), `pagesHost` (one `SpacePageView` for now; C6 turns
  it into `SpacePagerView`), `bottomBar` (36 pt: archive placeholder left, Space dots centre, "+" right; TODO(measure)).
  All frames set in `layout()`.

`ShellWindowController` now takes `init(engine: any EngineClient, sidebar: any SidebarSource)`, keeps
`tabsByNode: [NodeID: TabID]`, `current`, `previous` (the previous current, for the 32% state). Activating a node:
create the engine tab lazily (`engine.createTab(url:)`), put `engine.contentView(for:)` in the card, shift
`previous = current; current = node`, push a new `Resolver` to the outline. Engine events map back through
`nodeByTab` to `sidebar.updateTab` (title) and a favicon cache `[NodeID: Data]` that updates just that row's cell.

**Step 6: GUI test** `Tests/ShellKitGUITests/SidebarViewTests.swift`
```swift
import AppKit
import XCTest
import EngineAPITestSupport
@testable import ShellUI

@MainActor
final class SidebarViewTests: XCTestCase {
  override func setUp() async throws { _ = NSApplication.shared }

  func testRowPitchAndFavoriteTiles() throws {
    let sidebar = StubSidebar.sample()
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    let root = try XCTUnwrap(controller.window?.contentView as? ShellRootView)
    controller.window?.setContentSize(NSSize(width: 1200, height: 800))
    root.layoutSubtreeIfNeeded()
    let outline = try XCTUnwrap(root.sidebarContainer.currentOutline)
    XCTAssertEqual(outline.rect(ofRow: 0).height, 41)
    let grid = root.sidebarContainer.favorites.collectionView
    grid.layoutSubtreeIfNeeded()
    let frames = (0..<3).compactMap { grid.item(at: IndexPath(item: $0, section: 0))?.view.frame }
    XCTAssertEqual(frames.count, 3)
    XCTAssertEqual(frames[0].size, CGSize(width: 52, height: 46))
    XCTAssertEqual(Set(frames.map(\.minY)).count, 1, "first three favorites share a row")
  }

  func testActivatingRowSetsCurrentAndPreviousStates() throws {
    let sidebar = StubSidebar.sample()
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    let space = sidebar.spaceOrder[0]
    let first = sidebar.children(of: .today(space))[0]
    let second = sidebar.children(of: .today(space))[1]
    controller.activate(node: first)
    controller.activate(node: second)
    XCTAssertEqual(controller.rowState(for: second), .current)
    XCTAssertEqual(controller.rowState(for: first), .previous)
  }
}
```

**Step 7: Run tests** (`cd $KIT && swift test -j 2 2>&1 | tail -6`; expected: all pass, XCTest
`Executed 12 tests, with 0 failures`).

**Step 8: Build and eyeball** (same build/open command as C2). Expected: 3x2 favorite tiles under the traffic
lights, Space title, pinned rows, divider, Today rows at a 41 pt pitch; clicking a row loads it in the card, the
row turns white 85%, the previously current row 32%. Isolation grep: no output.

**Step 9: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add native sidebar with favorites grid and tab outline"
```

---

### Task C4: Motion module (spring presets, CASpringAnimation builder, spring driver)

Arc's presets are named `firmFast, firmSlow, firmExtraSlow, springy, springyFast, springyExtraFast` and parameterized
by `dampingRatio` + `frequencyResponse` (design-system doc 0 #4, section 6). The numbers are not yet
matched, so every value is a placeholder marked `TODO(parity)`.

Formulas (mass `m` fixed at 1): `stiffness = (2 pi / response)^2 * m`, `damping = 4 pi * dampingRatio * m / response`.
These are the standard response/damping-ratio parameterization (natural angular frequency `w0 = 2 pi / response`,
`damping = 2 * dampingRatio * sqrt(stiffness * m)`).

Why not `CASpringAnimation(perceptualDuration:bounce:)`: Arc's parameterization is (dampingRatio, response); keeping
the same two numbers means Arc-matched values drop in unchanged. `CASpringAnimation.initialVelocity` is
normalized (fraction of the total distance per second), so the factory converts from points/second.

Interactive gestures cannot use `CASpringAnimation` for the settle (it cannot be read back or retargeted mid-flight),
so `SpringDriver` evaluates the closed-form solution on each display-link tick. Reduce Motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) jumps to the target.

**Files:**
- Modify/Create: `ShellKit/Sources/Motion/SpringParameters.swift`, `SpringPreset.swift`, `SpringSolver.swift`,
  `SpringAnimationFactory.swift`, `SpringDriver.swift`
- Test: `ShellKit/Tests/MotionTests/SpringMathTests.swift`, `SpringSolverTests.swift`, `SpringAnimationFactoryTests.swift`

**Step 1: Failing tests**

`SpringMathTests.swift`:
```swift
import Foundation
import Testing
@testable import Motion

struct SpringMathTests {
  @Test func stiffnessFromResponse() {
    let p = SpringParameters(dampingRatio: 1, response: 0.5)
    #expect(abs(p.stiffness - pow(2 * .pi / 0.5, 2)) < 1e-9)       // 157.9137
    #expect(abs(p.stiffness - 157.913_670_417) < 1e-6)
  }

  @Test func dampingFromRatio() {
    let p = SpringParameters(dampingRatio: 1, response: 0.5)
    #expect(abs(p.damping - 4 * .pi * 1 * 1 / 0.5) < 1e-9)         // 8 pi = 25.1327
    #expect(abs(p.damping - 2 * (p.stiffness * p.mass).squareRoot()) < 1e-9, "ratio 1 is critical damping")
  }

  @Test func massScalesStiffnessAndDamping() {
    let p = SpringParameters(dampingRatio: 0.7, response: 0.3, mass: 2)
    #expect(abs(p.stiffness - pow(2 * .pi / 0.3, 2) * 2) < 1e-9)
    #expect(abs(p.damping - 4 * .pi * 0.7 * 2 / 0.3) < 1e-9)
  }

  @Test(arguments: SpringPreset.allCases)
  func presetsRoundTripDampingRatio(preset: SpringPreset) {
    let p = preset.parameters
    let ratio = p.damping / (2 * (p.stiffness * p.mass).squareRoot())
    #expect(abs(ratio - p.dampingRatio) < 1e-9)
    #expect(p.response > 0)
  }

  @Test func presetNamesMatchArc() {
    #expect(SpringPreset.allCases.map(\.rawValue) ==
            ["firmFast", "firmSlow", "firmExtraSlow", "springy", "springyFast", "springyExtraFast"])
  }

  @Test func firmPresetsAreCriticallyDampedAndOrderedBySpeed() {
    #expect(SpringPreset.firmFast.parameters.dampingRatio == 1)
    #expect(SpringPreset.firmFast.parameters.response < SpringPreset.firmSlow.parameters.response)
    #expect(SpringPreset.firmSlow.parameters.response < SpringPreset.firmExtraSlow.parameters.response)
    #expect(SpringPreset.springy.parameters.dampingRatio < 1)
  }
}
```

`SpringSolverTests.swift`:
```swift
import Testing
@testable import Motion

struct SpringSolverTests {
  static let regimes: [SpringParameters] = [
    SpringParameters(dampingRatio: 0.5, response: 0.4),   // under
    SpringParameters(dampingRatio: 1.0, response: 0.4),   // critical
    SpringParameters(dampingRatio: 1.6, response: 0.4),   // over
  ]

  @Test(arguments: regimes)
  func initialConditions(p: SpringParameters) {
    let s = SpringSolver(parameters: p, displacement: 100, velocity: -300)
    #expect(abs(s.displacement(at: 0) - 100) < 1e-9)
    #expect(abs(s.velocity(at: 0) + 300) < 1e-6)
  }

  @Test(arguments: regimes)
  func satisfiesTheSpringODE(p: SpringParameters) {
    // m x'' + c x' + k x = 0, checked with a central difference.
    let s = SpringSolver(parameters: p, displacement: 100, velocity: 50)
    let t = 0.07, h = 1e-5
    let accel = (s.velocity(at: t + h) - s.velocity(at: t - h)) / (2 * h)
    let residual = p.mass * accel + p.damping * s.velocity(at: t) + p.stiffness * s.displacement(at: t)
    #expect(abs(residual) < 1e-3 * p.stiffness)
  }

  @Test func underdampedOvershootsCriticalDoesNot() {
    let under = SpringSolver(parameters: .init(dampingRatio: 0.5, response: 0.4), displacement: 100, velocity: 0)
    let critical = SpringSolver(parameters: .init(dampingRatio: 1, response: 0.4), displacement: 100, velocity: 0)
    let samples = stride(from: 0.0, through: 1.0, by: 0.001)
    #expect(samples.map(under.displacement(at:)).min()! < -1)
    #expect(samples.map(critical.displacement(at:)).min()! >= -1e-9)
  }

  @Test(arguments: regimes)
  func settlesWithinSettlingDuration(p: SpringParameters) {
    let s = SpringSolver(parameters: p, displacement: 100, velocity: 0)
    let t = p.settlingDuration(epsilon: 0.001)
    #expect(t > 0 && t < 5)
    for time in stride(from: t, through: t + 1, by: 0.01) {
      #expect(abs(s.displacement(at: time)) <= 0.1 + 1e-6)   // 0.001 of 100 pt
    }
  }
}
```

`SpringAnimationFactoryTests.swift`:
```swift
import QuartzCore
import Testing
@testable import Motion

@MainActor
struct SpringAnimationFactoryTests {
  @Test func copiesPhysicsIntoCASpringAnimation() {
    let p = SpringPreset.springyFast.parameters
    let a = SpringAnimationFactory.make(keyPath: "position.x", from: 0, to: 200, parameters: p,
                                        initialVelocity: 600)
    #expect(abs(Double(a.mass) - p.mass) < 1e-9)
    #expect(abs(Double(a.stiffness) - p.stiffness) < 1e-6)
    #expect(abs(Double(a.damping) - p.damping) < 1e-6)
    #expect(abs(Double(a.initialVelocity) - 3) < 1e-9, "600 pt/s over 200 pt = 3 distances/s")
    #expect(abs(a.duration - p.settlingDuration()) < 1e-9)
  }

  @Test func zeroDistanceHasZeroNormalizedVelocity() {
    #expect(SpringAnimationFactory.normalizedVelocity(pointsPerSecond: 500, from: 10, to: 10) == 0)
  }
}
```

**Step 2: Run to verify failure** (`swift test -j 2 --filter MotionTests`; expected: compile errors).

**Step 3: Implement**

`SpringParameters.swift`:
```swift
import Foundation

/// Spring in Arc's parameterization: damping ratio + response (seconds per undamped oscillation).
public struct SpringParameters: Equatable, Sendable {
  public var dampingRatio: Double
  public var response: Double
  public var mass: Double

  public init(dampingRatio: Double, response: Double, mass: Double = 1) {
    precondition(response > 0 && mass > 0 && dampingRatio >= 0)
    self.dampingRatio = dampingRatio; self.response = response; self.mass = mass
  }

  /// k = (2 pi / response)^2 * m
  public var stiffness: Double { pow(2 * .pi / response, 2) * mass }
  /// c = 4 pi * dampingRatio * m / response  (= 2 * dampingRatio * sqrt(k m))
  public var damping: Double { 4 * .pi * dampingRatio * mass / response }
  /// Undamped angular frequency w0 = sqrt(k / m) = 2 pi / response.
  public var angularFrequency: Double { 2 * .pi / response }

  /// First time after which the solution's envelope stays below `epsilon` (as a fraction of a unit
  /// displacement released from rest). Used as CASpringAnimation.duration and as the driver's stop time.
  public func settlingDuration(epsilon: Double = 0.001) -> Double {
    let solver = SpringSolver(parameters: self, displacement: 1, velocity: 0)
    var t = 0.0
    while t < 10 {
      if solver.envelope(at: t) < epsilon { return t }
      t += 1.0 / 1000
    }
    return 10
  }

}
```
Production targets never import Testing. For readable parameterized test names, add in `SpringSolverTests.swift`:
`extension SpringParameters: @retroactive CustomTestStringConvertible { public var testDescription: String {
"ratio \(dampingRatio) response \(response)" } }`.

`SpringPreset.swift`:
```swift
/// Preset names.
/// TODO(parity): replace every (dampingRatio, response) pair with values matching
/// Arc 1.168.0's presets; keep the names and this single table.
public enum SpringPreset: String, CaseIterable, Sendable {
  case firmFast, firmSlow, firmExtraSlow, springy, springyFast, springyExtraFast

  public var parameters: SpringParameters {
    switch self {
    case .firmFast:         SpringParameters(dampingRatio: 1.0, response: 0.25)  // TODO(parity)
    case .firmSlow:         SpringParameters(dampingRatio: 1.0, response: 0.40)  // TODO(parity)
    case .firmExtraSlow:    SpringParameters(dampingRatio: 1.0, response: 0.55)  // TODO(parity)
    case .springy:          SpringParameters(dampingRatio: 0.75, response: 0.45) // TODO(parity)
    case .springyFast:      SpringParameters(dampingRatio: 0.75, response: 0.30) // TODO(parity)
    case .springyExtraFast: SpringParameters(dampingRatio: 0.80, response: 0.20) // TODO(parity)
    }
  }
}
```

`SpringSolver.swift`:
```swift
import Foundation

/// Closed-form solution of m x'' + c x' + k x = 0 for displacement x from the target.
public struct SpringSolver: Sendable {
  public let parameters: SpringParameters
  public let x0: Double
  public let v0: Double

  public init(parameters: SpringParameters, displacement: Double, velocity: Double) {
    self.parameters = parameters; x0 = displacement; v0 = velocity
  }

  private var w0: Double { parameters.angularFrequency }
  private var zeta: Double { parameters.dampingRatio }

  public func displacement(at t: Double) -> Double { evaluate(t).x }
  public func velocity(at t: Double) -> Double { evaluate(t).v }

  /// Upper bound of |x(t)| used for settling.
  public func envelope(at t: Double) -> Double {
    if zeta < 1 {
      let a = zeta * w0, wd = w0 * (1 - zeta * zeta).squareRoot()
      let b = (v0 + a * x0) / wd
      return exp(-a * t) * (x0 * x0 + b * b).squareRoot()
    } else if zeta == 1 {
      return exp(-w0 * t) * (abs(x0) + abs(v0 + w0 * x0) * t)
    } else {
      let (c1, c2, r1, r2) = overdamped()
      return abs(c1) * exp(r1 * t) + abs(c2) * exp(r2 * t)
    }
  }

  private func overdamped() -> (Double, Double, Double, Double) {
    let root = (zeta * zeta - 1).squareRoot()
    let r1 = -w0 * (zeta - root), r2 = -w0 * (zeta + root)
    let c1 = (v0 - r2 * x0) / (r1 - r2)
    return (c1, x0 - c1, r1, r2)
  }

  private func evaluate(_ t: Double) -> (x: Double, v: Double) {
    if zeta < 1 {
      let a = zeta * w0, wd = w0 * (1 - zeta * zeta).squareRoot()
      let A = x0, B = (v0 + a * x0) / wd
      let e = exp(-a * t), c = cos(wd * t), s = sin(wd * t)
      return (e * (A * c + B * s), e * ((B * wd - a * A) * c - (A * wd + a * B) * s))
    } else if zeta == 1 {
      let A = x0, B = v0 + w0 * x0, e = exp(-w0 * t)
      return (e * (A + B * t), e * (B - w0 * (A + B * t)))
    } else {
      let (c1, c2, r1, r2) = overdamped()
      let e1 = exp(r1 * t), e2 = exp(r2 * t)
      return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }
  }
}
```

`SpringAnimationFactory.swift`:
```swift
import QuartzCore

@MainActor
public enum SpringAnimationFactory {
  public static func make(keyPath: String, from: Double, to: Double, parameters p: SpringParameters,
                          initialVelocity pointsPerSecond: Double = 0) -> CASpringAnimation {
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.mass = CGFloat(p.mass)
    animation.stiffness = CGFloat(p.stiffness)
    animation.damping = CGFloat(p.damping)
    animation.initialVelocity = CGFloat(normalizedVelocity(pointsPerSecond: pointsPerSecond, from: from, to: to))
    animation.fromValue = from
    animation.toValue = to
    animation.duration = p.settlingDuration()
    return animation
  }

  /// CASpringAnimation.initialVelocity is in units of the total animated distance per second.
  public static func normalizedVelocity(pointsPerSecond v: Double, from: Double, to: Double) -> Double {
    let distance = to - from
    return distance == 0 ? 0 : v / distance
  }
}
```

`SpringDriver.swift` (display-link driven; `@objc` selector target must be an `NSObject`):
```swift
import AppKit
import QuartzCore

/// Drives a scalar along a spring on the view's display link. Interruptible: `stop()` returns the
/// current value and velocity so a new gesture can continue from exactly where the spring was.
@MainActor
public final class SpringDriver: NSObject {
  private var link: CADisplayLink?
  private var solver: SpringSolver?
  private var target = 0.0
  private var startTime: CFTimeInterval = 0
  private var stopAfter = 0.0
  private var onUpdate: ((Double) -> Void)?
  private var completion: ((Bool) -> Void)?
  public private(set) var isRunning = false

  public func animate(in view: NSView, from: Double, to: Double, initialVelocity: Double,
                      parameters: SpringParameters, onUpdate: @escaping (Double) -> Void,
                      completion: ((Bool) -> Void)? = nil) {
    _ = stop()
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      onUpdate(to); completion?(true); return
    }
    target = to
    solver = SpringSolver(parameters: parameters, displacement: from - to, velocity: initialVelocity)
    stopAfter = parameters.settlingDuration()
    self.onUpdate = onUpdate
    self.completion = completion
    startTime = CACurrentMediaTime()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
    isRunning = true
  }

  /// Stops without completing. Returns (value, velocity) at the current time, or nil if idle.
  @discardableResult
  public func stop() -> (value: Double, velocity: Double)? {
    guard isRunning, let solver else { return nil }
    let t = CACurrentMediaTime() - startTime
    let state = (target + solver.displacement(at: t), solver.velocity(at: t))
    finish(completed: false)
    return state
  }

  @objc private func tick(_ link: CADisplayLink) {
    guard let solver else { return }
    let t = link.targetTimestamp - startTime    // value for the frame about to be shown
    if t >= stopAfter {
      onUpdate?(target)
      finish(completed: true)
    } else {
      onUpdate?(target + solver.displacement(at: t))
    }
  }

  private func finish(completed: Bool) {
    link?.invalidate(); link = nil
    isRunning = false
    let done = completion
    solver = nil; onUpdate = nil; completion = nil
    done?(completed)
  }
}
```

**Step 4: Run tests**

Run: `cd $KIT && swift test -j 2 --skip ShellKitGUITests --filter MotionTests 2>&1 | tail -3`
Expected: all Motion tests pass (6 + 9 parameterized solver cases + 2 factory).

**Step 5: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add Motion module with Arc-named spring presets"
```

---

### Task C5: Command bar (pre-warmed panel, Cmd-T / Cmd-L, < 16 ms to appear)

Measured (arc-findings): ~766 pt wide, centered, top at ~34% of window height, radius ~12 pt, dark surface even on a
light theme, input row ~60 pt, result rows ~50 pt, selected row = lighter fill with ~8 pt radius, trailing
"Switch to Tab ->" hint. Behaviors: KB-001/BH-100, KB-002/BH-101, KB-003/BH-103, KB-004/BH-102, KB-084.

**Latency definition (what "< 16 ms" means here):**
- Start: entry of the menu action handler (`newTab(_:)` / `openLocation(_:)`), `CACurrentMediaTime()`. Key event
  delivery from the window server to AppKit is not included (not measurable in-process; it is the same for Arc).
- End: `targetTimestamp` of the first display-link tick of the panel's content view after `orderFront`, i.e. the
  presentation time of the first frame that contains the panel. "`orderFront` returned" is NOT the end.
- Reported both as an `OSSignposter` interval `CommandBarShow` (subsystem `dev.arkt.shell`, category
  `pointsOfInterest`; visible in Instruments) and as `CommandBarController.lastShowLatency` (seconds) for tests.

**Files:**
- Create: `ShellKit/Sources/ShellUI/CommandBar/CommandBarGeometry.swift`, `URLInputParser.swift`,
  `CommandBarResults.swift`, `CommandBarPanel.swift`, `CommandBarView.swift`, `CommandBarController.swift`
- Create: `ShellKit/Sources/ShellUI/Perf/ShellSignposts.swift`
- Modify: `ShellWindowController.swift`, `app/ArktShell/App/MainMenu.swift`
- Test: `ShellKit/Tests/ShellUITests/CommandBarGeometryTests.swift`, `URLInputParserTests.swift`, `CommandBarResultsTests.swift`
- Test: `ShellKit/Tests/ShellKitGUITests/CommandBarTests.swift`

**Step 1: Failing pure tests**

`CommandBarGeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import ShellUI

struct CommandBarGeometryTests {
  @Test func centeredAThirdDown() {
    // Arc measurement window: 1800 x 1072, screen coordinates (origin bottom-left).
    let parent = CGRect(x: 100, y: 50, width: 1800, height: 1072)
    let frame = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 300)
    #expect(frame.width == 766)
    #expect(frame.midX == parent.midX)
    #expect(abs(frame.maxY - (parent.maxY - 0.34 * 1072)) < 0.001)
    #expect(frame.height == 300)
  }

  @Test func shrinksInNarrowWindows() {
    let frame = CommandBarGeometry.frame(parentFrame: CGRect(x: 0, y: 0, width: 700, height: 600), contentHeight: 60)
    #expect(frame.width == 700 - 2 * 24)
  }

  @Test func heightForRows() {
    #expect(CommandBarGeometry.contentHeight(rowCount: 0) == 60)
    #expect(CommandBarGeometry.contentHeight(rowCount: 3) == 60 + 1 + 3 * 50 + 16)
    #expect(CommandBarGeometry.contentHeight(rowCount: 20) == CommandBarGeometry.contentHeight(rowCount: 8))
  }
}
```

`URLInputParserTests.swift`:
```swift
import Foundation
import Testing
@testable import ShellUI

struct URLInputParserTests {
  @Test(arguments: [
    ("example.com", "https://example.com"),
    ("https://example.com/a?b=1", "https://example.com/a?b=1"),
    ("http://localhost:3000", "http://localhost:3000"),
    ("localhost:3000", "http://localhost:3000"),
    ("sub.domain.co.uk/path", "https://sub.domain.co.uk/path"),
    ("  example.com  ", "https://example.com"),
  ])
  func parsesURLs(input: String, expected: String) {
    #expect(URLInputParser.url(from: input)?.absoluteString == expected)
  }

  @Test(arguments: ["hello world", "swift", "", "what is example.com"])
  func rejectsQueries(input: String) {
    #expect(URLInputParser.url(from: input) == nil)
  }

  @Test func searchURLEncodesQuery() {
    #expect(URLInputParser.searchURL(for: "a b&c").absoluteString == "https://www.google.com/search?q=a%20b%26c")
  }
}
```

`CommandBarResultsTests.swift`:
```swift
import Foundation
import Testing
@testable import ShellUI

struct CommandBarResultsTests {
  let tab = CommandBarResults.OpenTab(node: UUID(), title: "Example Domain", url: URL(string: "https://example.com")!)

  @Test func urlFirstThenMatchingTabsThenSearch() {
    let results = CommandBarResults.make(query: "example.com", openTabs: [tab])
    #expect(results.map(\.kind.name) == ["open", "switch", "search"])
    #expect(results[1].trailingHint == "Switch to Tab")
  }

  @Test func plainQueryHasSearchLastAndMatchesTitles() {
    let results = CommandBarResults.make(query: "domain", openTabs: [tab])
    #expect(results.map(\.kind.name) == ["switch", "search"])
  }

  @Test func emptyQueryListsOpenTabs() {
    #expect(CommandBarResults.make(query: "", openTabs: [tab]).map(\.kind.name) == ["switch"])
  }
}
```

**Step 2: Run to verify failure** (`swift test -j 2 --skip ShellKitGUITests`; expected: compile errors).

**Step 3: Implement pure parts**

`CommandBarGeometry.swift`:
```swift
import CoreGraphics

public enum CommandBarGeometry {
  public static let preferredWidth: CGFloat = 766      // measured
  public static let sideMargin: CGFloat = 24
  public static let topFraction: CGFloat = 0.34        // measured: top at ~34% of window height
  public static let inputHeight: CGFloat = 60          // measured
  public static let rowHeight: CGFloat = 50            // measured
  public static let cornerRadius: CGFloat = 12         // measured
  public static let selectedRowRadius: CGFloat = 8     // measured
  public static let maxVisibleRows = 8                 // TODO(measure)
  public static let listPadding: CGFloat = 8

  public static func contentHeight(rowCount: Int) -> CGFloat {
    let rows = min(rowCount, maxVisibleRows)
    return rows == 0 ? inputHeight : inputHeight + 1 + CGFloat(rows) * rowHeight + 2 * listPadding
  }

  /// Screen-space frame (origin bottom-left), top edge pinned so result changes grow downward.
  public static func frame(parentFrame p: CGRect, contentHeight: CGFloat) -> CGRect {
    let width = min(preferredWidth, p.width - 2 * sideMargin)
    let top = p.maxY - topFraction * p.height
    return CGRect(x: p.midX - width / 2, y: top - contentHeight, width: width, height: contentHeight)
  }
}
```

`URLInputParser.swift`: `url(from:)` trims whitespace; rejects input containing spaces; accepts `http(s)://`
URLs with a host; `localhost[:port][/...]` -> `http://`; otherwise requires a dot in the host part and a final label
of 2+ letters, then prefixes `https://`. `searchURL(for:)` builds `https://www.google.com/search?q=` with
`addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed minus "&+=?#")` (TODO: default engine is a product
decision; Arc defaulted to Google).

`CommandBarResults.swift`: `struct Result { kind: Kind; title: String; subtitle: String; trailingHint: String? }`,
`enum Kind { case open(URL), switchTo(NodeID), search(URL); var name: String }`, `struct OpenTab { node, title, url }`,
`static func make(query:openTabs:) -> [Result]`: URL result (if parseable) first; then up to 6 open tabs whose
title or host contains the query (case-insensitive, `localizedStandardContains`), hint "Switch to Tab"; then a search
result for non-empty queries. Real results (Chromium autocomplete, history, actions, Spaces) replace this provider
later behind the same `Result` type.

**Step 4: Implement the panel, view and controller**

`CommandBarPanel.swift`:
```swift
import AppKit

@MainActor
final class CommandBarPanel: NSPanel {
  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: CommandBarGeometry.preferredWidth, height: 60),
               styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
    isFloatingPanel = true
    hidesOnDeactivate = true
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none                     // no system fade: it would eat the 16 ms budget
    appearance = NSAppearance(named: .darkAqua)   // dark surface even on light Spaces
    collectionBehavior = [.fullScreenAuxiliary, .transient]
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
```

`CommandBarView.swift`: flipped root view, layer radius 12 continuous, fill `commandBarSurface`, 1 px border
`commandBarBorder`. Subviews: `field` (borderless `NSTextField`, `drawsBackground = false`, focus ring none,
`.systemFont(ofSize: 18)`, placeholder "Search or Enter URL...", 60 pt row with 20 pt leading), 1 px divider
(`commandBarDivider`), `table` in a borderless `NSScrollView`: `NSTableView`, `style = .plain`, `rowHeight = 50`,
`intercellSpacing = .zero`, `headerView = nil`, one column, `selectionHighlightStyle = .none`, custom
`CommandBarRowView` drawing `commandBarSelectedRow` with radius 8 inset 8 pt horizontally when selected, cells with
16 pt icon, title (14 pt, `commandBarText`), subtitle (12 pt, `commandBarSecondaryText`), trailing hint. Frames in
`layout()`.

`CommandBarController.swift` (the hot path; everything allocated in `prewarm`):
```swift
import AppKit
import os

@MainActor
public final class CommandBarController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
  public enum Mode: Equatable { case newTab, currentTab(URL?) }

  public var onOpen: ((URL, _ inNewTab: Bool) -> Void)?
  public var onSwitch: ((NodeID) -> Void)?
  public var onReload: (() -> Void)?
  public var openTabsProvider: () -> [CommandBarResults.OpenTab] = { [] }

  public private(set) var isVisible = false
  public private(set) var mode: Mode = .newTab
  /// Seconds from show() entry to the presentation time of the first frame with the panel.
  public private(set) var lastShowLatency: Double?
  public var onFirstFrame: ((Double) -> Void)?

  private let panel = CommandBarPanel()
  private let barView = CommandBarView()
  private var results: [CommandBarResults.Result] = []
  private var prefill: String?
  private var showStart: CFTimeInterval = 0
  private var firstFrameLink: CADisplayLink?
  private var signpostState: OSSignpostIntervalState?
  private weak var parent: NSWindow?

  public init(parent: NSWindow) {
    self.parent = parent
    super.init()
    panel.contentView = barView
    barView.field.delegate = self
    barView.table.dataSource = self
    barView.table.delegate = self
  }

  /// Creates the window-server backing store, lays out and draws once off-screen, so the first real
  /// show() does no allocation, nib loading or first-draw work.
  public func prewarm() {
    results = CommandBarResults.make(query: "warm", openTabs: [])
    barView.table.reloadData()
    panel.setFrame(NSRect(x: -10_000, y: -10_000, width: CommandBarGeometry.preferredWidth,
                          height: CommandBarGeometry.contentHeight(rowCount: 3)), display: true)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    panel.displayIfNeeded()
    panel.orderOut(nil)
    panel.alphaValue = 1
    results = []
  }

  /// Menu entry point. Cmd-T / Cmd-L while open closes the bar (KB-003, BH-103).
  public func toggle(_ newMode: Mode) {
    if isVisible { hide() } else { show(newMode) }
  }

  public func show(_ newMode: Mode) {
    showStart = CACurrentMediaTime()
    guard let parent else { return }
    signpostState = ShellSignposts.signposter.beginInterval("CommandBarShow")
    mode = newMode
    switch newMode {
    case .newTab: prefill = nil; barView.field.stringValue = ""
    case .currentTab(let url): prefill = url?.absoluteString; barView.field.stringValue = prefill ?? ""
    }
    reloadResults()
    let height = CommandBarGeometry.contentHeight(rowCount: results.count)
    panel.setFrame(CommandBarGeometry.frame(parentFrame: parent.frame, contentHeight: height), display: false)
    parent.addChildWindow(panel, ordered: .above)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(barView.field)
    barView.field.currentEditor()?.selectAll(nil)
    isVisible = true
    let link = barView.displayLink(target: self, selector: #selector(firstFrame(_:)))
    link.add(to: .main, forMode: .common)
    firstFrameLink = link
  }

  @objc private func firstFrame(_ link: CADisplayLink) {
    link.invalidate(); firstFrameLink = nil
    let latency = link.targetTimestamp - showStart
    lastShowLatency = latency
    if let state = signpostState { ShellSignposts.signposter.endInterval("CommandBarShow", state) }
    ShellSignposts.logger.info("commandbar.show ms=\(latency * 1000, format: .fixed(precision: 2))")
    onFirstFrame?(latency)
  }

  public func hide() {
    guard isVisible else { return }
    parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    isVisible = false
    parent?.makeKey()
  }

  // MARK: Field and keys

  public func controlTextDidChange(_ obj: Notification) {
    reloadResults()
    let height = CommandBarGeometry.contentHeight(rowCount: results.count)
    if let parent {
      panel.setFrame(CommandBarGeometry.frame(parentFrame: parent.frame, contentHeight: height), display: true)
    }
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)): hide(); return true          // Esc, KB-084
    case #selector(NSResponder.insertNewline(_:)): commit(); return true
    case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
    case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
    default: return false
    }
  }

  /// Enter. Cmd-L + Enter without editing reloads (KB-004, BH-102).
  public func commit() {
    let text = barView.field.stringValue
    if case .currentTab = mode, let prefill, text == prefill { hide(); onReload?(); return }
    let row = max(barView.table.selectedRow, 0)
    guard row < results.count else { hide(); return }
    let inNewTab = (mode == .newTab)
    hide()
    switch results[row].kind {
    case .open(let url), .search(let url): onOpen?(url, inNewTab)
    case .switchTo(let node): onSwitch?(node)
    }
  }

  private func reloadResults() {
    results = CommandBarResults.make(query: barView.field.stringValue, openTabs: openTabsProvider())
    barView.table.reloadData()
    if !results.isEmpty { barView.table.selectRowIndexes([0], byExtendingSelection: false) }
  }

  private func moveSelection(_ delta: Int) {
    guard !results.isEmpty else { return }
    let next = min(max(barView.table.selectedRow + delta, 0), results.count - 1)
    barView.table.selectRowIndexes([next], byExtendingSelection: false)
    barView.table.scrollRowToVisible(next)
  }

  // NSTableViewDataSource / Delegate: numberOfRows = results.count; viewFor returns a reused
  // CommandBarCellView (makeView(withIdentifier:owner:)); rowViewForRow returns CommandBarRowView.
}
```
`Perf/ShellSignposts.swift`:
```swift
import os

public enum ShellSignposts {
  public static let subsystem = "dev.arkt.shell"
  public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
  public static let logger = Logger(subsystem: subsystem, category: "perf")
}
```

`ShellWindowController` creates the `CommandBarController` in `init`, calls `prewarm()` from `windowDidBecomeKey`
the first time, and wires: `onOpen(url, true)` -> `sidebar.addTab(url:title:in: .today(currentSpace))` + activate
(BH-100: new Today tab); `onOpen(url, false)` -> `engine.navigate(currentTab, to: url)` (BH-101);
`onReload` -> `engine.reload(currentTab)`; `onSwitch` -> `activate(node:)`. Actions:
```swift
@objc public func newTab(_ sender: Any?) { commandBar.toggle(.newTab) }                                  // KB-001
@objc public func openLocation(_ sender: Any?) { commandBar.toggle(.currentTab(currentTabURL)) }          // KB-002
```
`MainMenu` adds a File menu: "New Tab" (`newTab:`, Cmd-T) and "Open Command Bar" (`openLocation:`, Cmd-L), both
with target nil. When the panel is key, AppKit still searches the main window's responder chain, which contains
`ShellWindowController`, so Cmd-T/Cmd-L reach `toggle` and close the bar (KB-003).

**Step 5: GUI tests** `Tests/ShellKitGUITests/CommandBarTests.swift`
```swift
import AppKit
import XCTest
import EngineAPITestSupport
@testable import ShellUI

@MainActor
final class CommandBarTests: XCTestCase {
  var controller: ShellWindowController!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    controller.commandBar.prewarm()
    try await Task.sleep(for: .milliseconds(300))   // let the window server settle
  }

  override func tearDown() async throws { controller.close() }

  /// Shows the bar and waits for its first presented frame.
  func showAndMeasure() async throws -> Double {
    let bar = controller.commandBar
    let frame = expectation(description: "first frame")
    var latency = 0.0
    bar.onFirstFrame = { latency = $0; frame.fulfill() }
    bar.toggle(.newTab)
    await fulfillment(of: [frame], timeout: 1)
    bar.toggle(.newTab)   // second Cmd-T closes (KB-003)
    XCTAssertFalse(bar.isVisible)
    try await Task.sleep(for: .milliseconds(30))
    return latency
  }

  func testAppearsUnder16ms() async throws {
    var samples: [Double] = []
    for _ in 0..<20 { samples.append(try await showAndMeasure()) }
    samples.sort()
    let median = samples[samples.count / 2], p95 = samples[Int(Double(samples.count) * 0.95) - 1]
    print("commandbar.latency.ms median=\(median * 1000) p95=\(p95 * 1000) max=\(samples.last! * 1000)")
    XCTAssertLessThan(p95, 0.016, "command bar must appear in under 16 ms (design section 5)")
  }

  func testGeometryAndDarkSurface() async throws {
    let window = try XCTUnwrap(controller.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1800, height: 1072), display: true)
    controller.commandBar.toggle(.newTab)
    let panel = try XCTUnwrap(window.childWindows?.first)
    XCTAssertEqual(panel.frame.width, 766)
    XCTAssertEqual(panel.frame.midX, window.frame.midX, accuracy: 0.5)
    XCTAssertEqual(panel.frame.maxY, window.frame.maxY - 0.34 * 1072, accuracy: 0.5)
    XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
  }

  func testCmdLPrefillAndUneditedEnterReloads() async throws {
    var reloaded = false
    controller.commandBar.onReload = { reloaded = true }
    controller.commandBar.toggle(.currentTab(URL(string: "https://example.com")))
    controller.commandBar.commit()
    XCTAssertTrue(reloaded)                       // KB-004
    XCTAssertFalse(controller.commandBar.isVisible)
  }

  func testEnterOnURLOpensNewTodayTab() async throws {
    let sidebar = controller.sidebar
    let space = controller.currentSpace
    let before = sidebar.children(of: .today(space)).count
    controller.commandBar.toggle(.newTab)
    controller.commandBar.setQueryForTesting("example.com")
    controller.commandBar.commit()
    XCTAssertEqual(sidebar.children(of: .today(space)).count, before + 1)   // KB-001, BH-100
  }
}
```
(`setQueryForTesting` sets the field text and calls the same `controlTextDidChange` path; mark it `internal`.)

**Step 6: Run tests**

Run: `cd $KIT && swift test -j 2 --filter CommandBar 2>&1 | grep -E 'commandbar.latency|Executed|passed|failed'`
Expected: a `commandbar.latency.ms median=... p95=... max=...` line with p95 below 16, all CommandBar tests pass.
Note: tests run a Debug build; if p95 >= 16 ms in Debug only, rerun with `swift test -c release -j 2 --filter
CommandBarTests` before optimizing. If Release also fails, profile with Instruments (`CommandBarShow` signpost)
and remove work from `show()`; do not raise the threshold.

**Step 7: Build, launch, eyeball**: Cmd-T opens an empty dark bar a third down; typing `example.com` + Enter adds a
Today row and loads the page; Cmd-L shows the URL selected; Enter without editing reloads; Cmd-T/Cmd-L/Esc close it.
Isolation grep: no output.

**Step 8: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add pre-warmed command bar with Cmd-T and Cmd-L"
```

---

### Task C6: Space paging (two-finger swipe, spring settle, theme crossfade, frame pacing)

BH-035 (two-finger horizontal swipe in the sidebar switches Space), KB-033/KB-034 (Cmd-Opt-Right/Left), KB-035
(Ctrl-1..9), BH-040 (indicator animates with the swipe). Design section 2: sidebars slide interactively and settle on
a spring; the theme crossfades on the GPU in sync. Core Animation gradients now; Metal later.

**Files:**
- Create: `ShellKit/Sources/ShellUI/Spaces/PagingMath.swift`, `VelocityTracker.swift`, `SpacePagerView.swift`
- Create: `ShellKit/Sources/ShellUI/Theme/ThemeBackgroundView.swift`
- Create: `ShellKit/Sources/ShellUI/Perf/FrameStats.swift`, `FramePacer.swift`
- Modify: `Sidebar/SidebarScrollView.swift`, `Sidebar/SidebarContainerView.swift`, `ShellRootView.swift`,
  `ShellWindowController.swift`, `app/ArktShell/App/MainMenu.swift`
- Test: `ShellKit/Tests/ShellUITests/PagingMathTests.swift`, `VelocityTrackerTests.swift`, `FrameStatsTests.swift`
- Test: `ShellKit/Tests/ShellKitGUITests/SpacePagerTests.swift`

**Step 1: Failing pure tests**

`PagingMathTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import ShellUI

struct PagingMathTests {
  let w: CGFloat = 190

  @Test func slowShortDragStays() {
    #expect(PagingMath.targetIndex(current: 1, translation: -40, velocity: -50, pageWidth: w, count: 3) == 1)
  }

  @Test func slowPastHalfwayAdvances() {
    #expect(PagingMath.targetIndex(current: 1, translation: -100, velocity: 0, pageWidth: w, count: 3) == 2)
    #expect(PagingMath.targetIndex(current: 1, translation: 100, velocity: 0, pageWidth: w, count: 3) == 0)
  }

  @Test func flickAdvancesEvenWhenShort() {
    #expect(PagingMath.targetIndex(current: 0, translation: -30, velocity: -900, pageWidth: w, count: 3) == 1)
  }

  @Test func neverMovesMoreThanOnePageOrPastEnds() {
    #expect(PagingMath.targetIndex(current: 0, translation: -30, velocity: -9000, pageWidth: w, count: 3) == 1)
    #expect(PagingMath.targetIndex(current: 2, translation: -150, velocity: -900, pageWidth: w, count: 3) == 2)
    #expect(PagingMath.targetIndex(current: 0, translation: 150, velocity: 900, pageWidth: w, count: 3) == 0)
  }

  @Test func rubberBandsBeyondEnds() {
    // Past the first page the offset resists: less than the raw translation, never more than the page width.
    let banded = PagingMath.offset(index: 0, translation: 120, pageWidth: w, count: 3)
    #expect(banded > 0 && banded < 120 && banded < w)
    #expect(PagingMath.offset(index: 1, translation: -50, pageWidth: w, count: 3) == -w - 50)
  }

  @Test func fractionalPositionForThemeBlend() {
    #expect(PagingMath.position(offset: -w * 1.25, pageWidth: w) == 1.25)
  }
}
```

`VelocityTrackerTests.swift`:
```swift
import Testing
@testable import ShellUI

struct VelocityTrackerTests {
  @Test func averagesRecentSamples() {
    var tracker = VelocityTracker(window: 0.1)
    for i in 0..<10 { tracker.add(delta: -10, at: Double(i) * 0.01) }   // -10 pt every 10 ms
    #expect(abs(tracker.velocity - (-1000)) < 1)
  }

  @Test func ignoresStaleSamples() {
    var tracker = VelocityTracker(window: 0.1)
    tracker.add(delta: 500, at: 0)
    tracker.add(delta: -5, at: 0.5)
    tracker.add(delta: -5, at: 0.51)
    #expect(tracker.velocity < 0)
  }
}
```

`FrameStatsTests.swift`:
```swift
import Testing
@testable import ShellUI

struct FrameStatsTests {
  @Test func countsHitchesAgainstBothThresholds() {
    var stats = FrameStats(hitchThreshold: 0.0086, designBudget: 0.00834)
    for _ in 0..<98 { stats.record(interval: 1.0 / 120) }   // 8.333 ms
    stats.record(interval: 0.0085)                           // over design budget only
    stats.record(interval: 0.0167)                           // dropped frame
    #expect(stats.frameCount == 100)
    #expect(stats.hitchCount == 1)
    #expect(stats.overBudgetCount == 2)
    #expect(abs(stats.overBudgetRatio - 0.02) < 1e-9)
    #expect(abs(stats.maxInterval - 0.0167) < 1e-9)
  }
}
```
Threshold note: design section 5 says "more than 1% of frames exceed 8.3 ms", but a perfect 120 Hz frame is
8.333 ms, so a literal 8.3 ms threshold counts every frame. `designBudget` therefore uses 8.34 ms (one 120 Hz frame
plus rounding). The C7 pass criterion is the stricter one from this track: zero intervals over 8.6 ms in the swipe
window; the design's <=1% over-budget ratio is recorded alongside. Raise "amend design section 5 to 8.6 ms or
'one refresh interval'" as an open question.

**Step 2: Run to verify failure** (expected: compile errors).

**Step 3: Implement pure parts**

`PagingMath.swift`:
```swift
import CoreGraphics

public enum PagingMath {
  public static let flickProjection: CGFloat = 0.2   // seconds of velocity added to the release translation
  public static let rubberBandCoefficient: CGFloat = 0.55

  /// Strip offset (negative = later pages) for page `index` plus finger translation, rubber-banded at the ends.
  public static func offset(index: Int, translation: CGFloat, pageWidth: CGFloat, count: Int) -> CGFloat {
    let base = -CGFloat(index) * pageWidth
    let raw = base + translation
    let minOffset = -CGFloat(max(count - 1, 0)) * pageWidth
    if raw > 0 { return rubberBand(raw, dimension: pageWidth) }
    if raw < minOffset { return minOffset - rubberBand(minOffset - raw, dimension: pageWidth) }
    return raw
  }

  /// UIScrollView-style resistance: (1 - 1 / (x * c / d + 1)) * d
  public static func rubberBand(_ x: CGFloat, dimension d: CGFloat) -> CGFloat {
    (1 - 1 / (x * rubberBandCoefficient / d + 1)) * d
  }

  public static func targetIndex(current: Int, translation: CGFloat, velocity: CGFloat,
                                 pageWidth: CGFloat, count: Int) -> Int {
    let projected = translation + velocity * flickProjection
    var target = current
    if projected <= -pageWidth / 2 { target = current + 1 }
    if projected >= pageWidth / 2 { target = current - 1 }
    return min(max(target, 0), count - 1)
  }

  /// Continuous page position (1.25 = a quarter of the way from page 1 to page 2).
  public static func position(offset: CGFloat, pageWidth: CGFloat) -> CGFloat {
    pageWidth > 0 ? -offset / pageWidth : 0
  }
}
```

`VelocityTracker.swift`: `struct VelocityTracker { var window: Double; mutating func add(delta: CGFloat, at time:
Double); var velocity: CGFloat; mutating func reset() }` - keeps samples within `window` seconds of the newest and
returns `sum(deltas) / (newest.time - oldest.time + frame)` where `frame` = the average sample spacing (so 10 samples
10 ms apart give 100 pt over 0.1 s).

`FrameStats.swift`:
```swift
public struct FrameStats: Sendable, Equatable {
  public let hitchThreshold: Double
  public let designBudget: Double
  public private(set) var frameCount = 0
  public private(set) var hitchCount = 0
  public private(set) var overBudgetCount = 0
  public private(set) var maxInterval = 0.0
  public private(set) var intervals: [Double] = []

  public init(hitchThreshold: Double = 0.0086, designBudget: Double = 0.00834) {
    self.hitchThreshold = hitchThreshold; self.designBudget = designBudget
  }

  public mutating func record(interval: Double) {
    frameCount += 1
    intervals.append(interval)
    if interval > hitchThreshold { hitchCount += 1 }
    if interval > designBudget { overBudgetCount += 1 }
    maxInterval = max(maxInterval, interval)
  }

  public var overBudgetRatio: Double { frameCount == 0 ? 0 : Double(overBudgetCount) / Double(frameCount) }
  public var p99: Double {
    guard !intervals.isEmpty else { return 0 }
    let sorted = intervals.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
  }
}
```

**Step 4: Frame pacer** (`Perf/FramePacer.swift`)
```swift
import AppKit
import QuartzCore

/// Logs display-link intervals while a hot-path interaction runs. A blocked main thread delays the
/// callback past a vsync, so the vsync-aligned `timestamp` jumps by two refresh intervals and shows up
/// as an interval over the threshold.
@MainActor
public final class FramePacer: NSObject {
  private var link: CADisplayLink?
  private var last: CFTimeInterval?
  private var label = ""
  public private(set) var stats = FrameStats()

  public func begin(_ label: String, in view: NSView) {
    _ = end()
    self.label = label
    stats = FrameStats()
    last = nil
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @discardableResult
  public func end() -> FrameStats? {
    guard let link else { return nil }
    link.invalidate()
    self.link = nil
    let fps = NSScreen.main?.maximumFramesPerSecond ?? 0
    ShellSignposts.logger.info("""
      pacing label=\(self.label, privacy: .public) screenMaxFPS=\(fps) frames=\(self.stats.frameCount) \
      over8.6=\(self.stats.hitchCount) overBudgetPct=\(self.stats.overBudgetRatio * 100, format: .fixed(precision: 2)) \
      maxMs=\(self.stats.maxInterval * 1000, format: .fixed(precision: 2)) p99Ms=\(self.stats.p99 * 1000, format: .fixed(precision: 2))
      """)
    return stats
  }

  @objc private func tick(_ link: CADisplayLink) {
    defer { last = link.timestamp }
    guard let last else { return }     // first tick after begin has no interval
    let interval = link.timestamp - last
    stats.record(interval: interval)
    if interval > stats.hitchThreshold {
      ShellSignposts.logger.info("hitch label=\(self.label, privacy: .public) ms=\(interval * 1000, format: .fixed(precision: 2))")
    }
  }
}
```

**Step 5: Pager, gesture forwarding, theme crossfade**

`SidebarScrollView` (modify): lock the axis per gesture and forward horizontal gestures to the pager.
```swift
@MainActor
final class SidebarScrollView: NSScrollView {
  weak var horizontalGestureTarget: NSView?
  private enum Axis { case undecided, horizontal, vertical }
  private var axis: Axis = .undecided
  private var pending: [NSEvent] = []

  override func scrollWheel(with event: NSEvent) {
    // Momentum after a horizontal gesture belongs to the pager (it ignores it; the spring owns the settle).
    if event.phase.contains(.began) || event.phase.contains(.mayBegin) { axis = .undecided; pending = [] }
    if axis == .undecided {
      let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
      if dx + dy < 2 && event.phase != [] { pending.append(event); return }
      axis = dx > dy ? .horizontal : .vertical
      let buffered = pending; pending = []
      for e in buffered { route(e) }
    }
    route(event)
  }

  private func route(_ event: NSEvent) {
    if axis == .horizontal, let target = horizontalGestureTarget { target.scrollWheel(with: event) }
    else { super.scrollWheel(with: event) }
  }
}
```

`SpacePagerView` (flipped; replaces `pagesHost`):
- Holds `pages: [SpacePageView]` inside `strip` (an `NSView` whose width = `count * pageWidth`); `index`,
  `translation`, `VelocityTracker`, `SpringDriver`, `FramePacer`, and `onPosition: (CGFloat) -> Void` (continuous
  page position for the theme and the dots) and `onSettle: (Int) -> Void`.
- `apply(offset:)` does `CATransaction.begin(); setDisableActions(true); strip.setFrameOrigin(NSPoint(x: offset,
  y: 0)); CATransaction.commit(); onPosition(PagingMath.position(offset:pageWidth:))`. No layout of page contents
  happens during a swipe (only the strip's origin moves).
- `scrollWheel(with:)`:
  ```swift
  override func scrollWheel(with event: NSEvent) {
    if event.momentumPhase != [] { return }                       // the spring owns deceleration
    // Follow the fingers in both scroll-direction settings.
    let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    if event.phase.contains(.began) {
      if let state = driver.stop() { translation = CGFloat(state.value) + CGFloat(index) * bounds.width }
      else { translation = 0 }
      tracker.reset()
      pacer.begin("space-swipe", in: self)
    } else if event.phase.contains(.changed) {
      translation += dx
      tracker.add(delta: dx, at: event.timestamp)
      apply(offset: PagingMath.offset(index: index, translation: translation, pageWidth: bounds.width, count: pages.count))
    } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      let target = PagingMath.targetIndex(current: index, translation: translation, velocity: tracker.velocity,
                                          pageWidth: bounds.width, count: pages.count)
      settle(to: target, velocity: tracker.velocity)
    }
  }
  ```
- `settle(to:velocity:)`: `from = current strip origin x`, `to = -target * width`, runs
  `driver.animate(in: self, from:, to:, initialVelocity: velocity, parameters: SpringPreset.firmSlow.parameters,
  onUpdate: apply(offset:), completion: { pacer.end(); index = target; onSettle(target) })`. The preset choice is a
  placeholder pending the matched values (TODO(parity): which preset Arc uses for Space paging).
- `go(to:)` (keyboard, Ctrl-N, dots): `pacer.begin("space-key")` then `settle(to:velocity: 0)`.
- Test hooks used by C7 and GUI tests (internal): `beginTracking()`, `track(delta:at:)`, `endTracking()` - the
  same functions `scrollWheel` calls, factored out so a scripted swipe exercises the identical path.

`ThemeBackgroundView` (full-window, behind sidebar and card):
```swift
@MainActor
public final class ThemeBackgroundView: NSView {
  private let base = CAGradientLayer()
  private let overlay = CAGradientLayer()
  private var lowerIndex = -1
  public var themes: [SpaceThemeInfo] = [] { didSet { lowerIndex = -1 } }

  public override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    for g in [base, overlay] {
      g.startPoint = CGPoint(x: 0, y: 1); g.endPoint = CGPoint(x: 1, y: 0)   // top-left to bottom-right
      g.actions = ["colors": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
      layer?.addSublayer(g)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  public override func layout() {
    super.layout()
    CATransaction.begin(); CATransaction.setDisableActions(true)
    base.frame = bounds; overlay.frame = bounds
    CATransaction.commit()
  }

  /// position 1.25 = theme 1 blended 25% toward theme 2. Per frame this only changes one opacity;
  /// gradient colors are reassigned only when the pair of neighbouring Spaces changes.
  public func setPosition(_ position: CGFloat) {
    guard !themes.isEmpty else { return }
    let clamped = min(max(position, 0), CGFloat(themes.count - 1))
    let lower = Int(clamped.rounded(.down))
    let upper = min(lower + 1, themes.count - 1)
    CATransaction.begin(); CATransaction.setDisableActions(true)
    if lower != lowerIndex {
      base.colors = themes[lower].baseColors.map(\.cgColor)
      overlay.colors = themes[upper].baseColors.map(\.cgColor)
      lowerIndex = lower
    }
    overlay.opacity = Float(clamped - CGFloat(lower))
    CATransaction.commit()
  }
}
```
`ShellWindowController` wires `pager.onPosition` to `themeBackground.setPosition`, to the bottom-bar dot indicator
(BH-040: the active dot interpolates its fill with the position), and, when `round(position)` crosses to a Space with
a different `isDark`, switches the sidebar container's `appearance` between `.aqua` and `.darkAqua` once (this
re-resolves token colors; it is a known hitch risk, so the pacer logs it; if it hitches, precompute both flavors on
the row layers instead). `onSettle` sets `currentSpace`, rebinds `currentOutline`, and restores that Space's last
active tab (BH-036).

Menu (`MainMenu`): "Spaces" menu with "Next Space" (`nextSpace:`, Cmd-Opt-Right arrow,
`String(UnicodeScalar(NSRightArrowFunctionKey)!)`), "Previous Space" (`previousSpace:`, Cmd-Opt-Left), and
"Space 1" ... "Space 9" (`goToSpace:` with `tag` 0-8, Ctrl-1 ... Ctrl-9). Actions live on `ShellWindowController`.

**Step 6: GUI tests** `Tests/ShellKitGUITests/SpacePagerTests.swift`
```swift
import AppKit
import XCTest
import EngineAPITestSupport
@testable import ShellUI

@MainActor
final class SpacePagerTests: XCTestCase {
  var controller: ShellWindowController!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws { controller.close() }

  func testScriptedSwipeSettlesOnNextSpace() async throws {
    let pager = controller.pager
    let settled = expectation(description: "settled")
    pager.onSettleForTesting = { _ in settled.fulfill() }
    pager.beginTracking()
    var t = 0.0
    for _ in 0..<12 { t += 1.0 / 120; pager.track(delta: -12, at: t) }    // 144 pt left, ~1440 pt/s
    pager.endTracking()
    await fulfillment(of: [settled], timeout: 3)
    XCTAssertEqual(pager.index, 1)
    XCTAssertEqual(controller.currentSpace, controller.sidebar.spaceOrder[1])
  }

  func testKeyboardNextAndPreviousSpace() async throws {
    let settled = expectation(description: "settled")
    controller.pager.onSettleForTesting = { _ in settled.fulfill() }
    controller.nextSpace(nil)                                                 // KB-033
    await fulfillment(of: [settled], timeout: 3)
    XCTAssertEqual(controller.pager.index, 1)
  }

  func testThemeBlendFollowsPosition() throws {
    controller.pager.setPositionForTesting(0.5)
    XCTAssertEqual(controller.themeBackground.overlayOpacityForTesting, 0.5, accuracy: 0.001)
  }
}
```

**Step 7: Run tests** (`cd $KIT && swift test -j 2 2>&1 | tail -6`; expected: all Swift Testing and XCTest tests pass).

**Step 8: Build, launch, manual check**: two-finger swipe left/right in the sidebar follows the fingers, rubber-bands
at the first and last Space, settles on a spring, the background gradient crossfades in sync and the dot indicator
moves; vertical scrolling in a long Today list still scrolls; Cmd-Opt-Left/Right and Ctrl-1/2/3 switch Spaces.
Read the pacing log:
```zsh
log show --last 2m --style compact --predicate 'subsystem == "dev.arkt.shell" AND category == "perf"' | grep -E 'pacing|hitch'
```
Expected: one `pacing label=space-swipe ...` line per swipe. Isolation grep: no output.

**Step 9: Commit**
```zsh
cd $REPO && git add app/ArktShell && git commit -m "Add interactive Space paging with spring settle and theme crossfade"
```

---

### Task C7: Smoke run with recorded numbers

Proves the whole loop in the real `.app` (Release build, the configuration whose numbers matter): launch, open
example.com through the command bar, switch Spaces, and record frame pacing. The scripted part drives the same code
paths as user input (the command bar's `toggle`/`commit`, the pager's `beginTracking/track/endTracking`); a manual
trackpad pass follows because synthetic scroll events cannot reproduce real trackpad timing.

**Preconditions:** run on the built-in ProMotion display (120 Hz), lid open, external displays disconnected or the
window on the built-in panel, Low Power Mode off. On a 60 Hz display every interval is ~16.7 ms and the 8.6 ms gate
is meaningless: the smoke runner records `screenMaxFPS` and reports `NOT-MEASURABLE` instead of PASS/FAIL when it
is below 120. The Chromium build should be paused (or at least noted) while measuring, since a saturated CPU
distorts frame pacing; record the load average with the numbers.

**Files:**
- Create: `app/ArktShell/App/SmokeRunner.swift`
- Modify: `app/ArktShell/App/AppDelegate.swift`
- Create: `docs/plans/2026-10-22-track-c-results.md`

**Step 1: Implement `SmokeRunner`** (runs only with the `-ArktSmoke YES` launch argument):
```swift
import AppKit
import EngineAPI
import ShellUI

@MainActor
final class SmokeRunner {
  struct Report: Encodable {
    var screenMaxFPS: Int
    var commandBarFirstShowMs: Double
    var commandBarWarmShowMs: [Double]
    var exampleLoaded: Bool
    var exampleTitle: String
    var swipes: [Swipe]
    var verdict: String
    struct Swipe: Encodable {
      var label: String; var frames: Int; var over8_6ms: Int; var overBudgetPct: Double; var maxMs: Double; var p99Ms: Double
    }
  }

  let controller: ShellWindowController
  let engine: any EngineClient

  init(controller: ShellWindowController, engine: any EngineClient) {
    self.controller = controller; self.engine = engine
  }

  func run() async -> Int32 {
    try? await Task.sleep(for: .seconds(1))                          // window on screen, prewarm done
    let fps = controller.window?.screen?.maximumFramesPerSecond ?? 0
    let bar = controller.commandBar

    // 1. Command bar latency: first show after launch, then 10 warm shows.
    let first = await measureShow(bar)
    var warm: [Double] = []
    for _ in 0..<10 { warm.append(await measureShow(bar)) }

    // 2. Open example.com through the command bar (KB-001 path).
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    bar.commit()
    let loaded = await waitFor(seconds: 20) { [controller] in
      controller.currentSnapshot.map { !$0.isLoading && $0.title == "Example Domain" } ?? false
    }

    // 3. Scripted swipes: to Space 2 and back, through the real tracking path.
    var swipes: [Report.Swipe] = []
    for direction in [-1.0, 1.0] {
      if let stats = await scriptedSwipe(direction: direction) {
        swipes.append(.init(label: direction < 0 ? "swipe-next" : "swipe-back", frames: stats.frameCount,
                            over8_6ms: stats.hitchCount, overBudgetPct: stats.overBudgetRatio * 100,
                            maxMs: stats.maxInterval * 1000, p99Ms: stats.p99 * 1000))
      }
    }

    let hitchFree = swipes.allSatisfy { $0.over8_6ms == 0 } && swipes.count == 2
    let barFast = warm.sorted()[warm.count * 95 / 100 - 1] < 16
    let verdict = fps < 120 ? "NOT-MEASURABLE (screen \(fps) Hz)"
      : (loaded && hitchFree && barFast ? "PASS" : "FAIL")
    let report = Report(screenMaxFPS: fps, commandBarFirstShowMs: first, commandBarWarmShowMs: warm,
                        exampleLoaded: loaded, exampleTitle: controller.currentSnapshot?.title ?? "",
                        swipes: swipes, verdict: verdict)
    let json = (try? JSONEncoder().encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    print("ARKT_SMOKE \(json)")
    return verdict == "PASS" ? 0 : 1
  }

  private func measureShow(_ bar: CommandBarController) async -> Double {
    await withCheckedContinuation { continuation in
      bar.onFirstFrame = { latency in
        bar.onFirstFrame = nil
        bar.toggle(.newTab)                                         // close again
        continuation.resume(returning: latency * 1000)
      }
      bar.toggle(.newTab)
    }
  }

  /// 0.3 s finger movement of ~150 pt at 120 events/s, then release (same as a medium trackpad swipe).
  private func scriptedSwipe(direction: Double) async -> FrameStats? {
    let pager = controller.pager
    pager.beginTracking()
    for step in 1...36 {
      try? await Task.sleep(for: .milliseconds(8))
      pager.track(delta: CGFloat(direction * 4.2), at: Double(step) / 120)
    }
    return await withCheckedContinuation { continuation in
      pager.onSettleStats = { stats in pager.onSettleStats = nil; continuation.resume(returning: stats) }
      pager.endTracking()
    }
  }

  private func waitFor(seconds: Double, _ condition: @escaping @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return false
  }
}
```
(`pager.onSettleStats` is invoked from the settle completion with `pacer.end()`'s stats; `controller.currentSnapshot`
is `engine.snapshot(of: currentTab)`. Add both as small internal accessors in ShellUI with `@_spi(Smoke) public`
if the app target needs them across the module boundary.)

`AppDelegate` after showing the window:
```swift
if UserDefaults.standard.bool(forKey: "ArktSmoke") {
  let runner = SmokeRunner(controller: controller, engine: engine)
  Task { @MainActor in
    let code = await runner.run()
    exit(code)
  }
}
```
(`-ArktSmoke YES` on the command line lands in `UserDefaults` via the argument domain.)

**Step 2: Release build**

Run:
```zsh
cd $APP && xcodegen generate && xcodebuild -project ArktShell.xcodeproj -scheme ArktShell -configuration Release -derivedDataPath $DD -jobs 2 build 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`.

**Step 3: Scripted smoke** (needs network for example.com)

Run:
```zsh
uptime
$DD/Build/Products/Release/ArktShell.app/Contents/MacOS/ArktShell -ArktSmoke YES | grep ARKT_SMOKE ; echo "exit=$?"
```
Expected: one `ARKT_SMOKE {...}` JSON line with `"screenMaxFPS":120`, `"exampleLoaded":true`,
`"exampleTitle":"Example Domain"`, warm command bar shows under 16 ms, two swipe entries with `"over8_6ms":0`,
`"verdict":"PASS"`, and `exit=0`. If the verdict is FAIL, do not loosen thresholds: open Instruments with
`xcrun xctrace record --template 'Animation Hitches' --launch -- $DD/Build/Products/Release/ArktShell.app/Contents/MacOS/ArktShell -ArktSmoke YES`
and debug the hitching frames systematically (reproduce, isolate, fix the root cause).

**Step 4: Manual trackpad pass** (real gesture timing)

Run `open $DD/Build/Products/Release/ArktShell.app`, press Cmd-T, type `example.com`, Enter, then do 10 two-finger
swipes between Spaces (5 each way, mixed slow drags and flicks). Then:
```zsh
log show --last 5m --style compact --predicate 'subsystem == "dev.arkt.shell" AND category == "perf"' | grep -E 'pacing label=space-swipe|commandbar.show'
```
Expected: 10 `pacing label=space-swipe` lines, each with `over8.6=0`; `commandbar.show ms=` values under 16.

**Step 5: Record results** in `docs/plans/2026-10-22-track-c-results.md`:
- Date, machine model, macOS build, `screenMaxFPS`, `uptime` load averages, whether the Chromium build was running.
- The full `ARKT_SMOKE` JSON line.
- A table of the 10 manual swipes (frames, over 8.6 ms, over design budget %, max ms, p99 ms) plus the command bar
  `ms` values.
- Verdict against both gates: this track's (zero intervals over 8.6 ms, command bar p95 < 16 ms) and design section 5's
  (<= 1% of frames over one 120 Hz interval).

**Step 6: Final verification**

Run:
```zsh
cd $KIT && swift test -j 2 2>&1 | tail -4
# then the isolation grep from the Rules section
cd $REPO && git status --short
```
Expected: all tests pass, isolation grep prints nothing, `git status` lists only the new/changed tracked files (no
`ArktShell.xcodeproj`, `App/Info.plist`, `build/`, `.build/`).

**Step 7: Commit**
```zsh
cd $REPO && git add app/ArktShell docs/plans/2026-10-22-track-c-results.md && git commit -m "Add shell smoke runner and record frame pacing results"
```

---

## Out of scope (next tracks)

- `TrackBSidebarSource` adapter over `app/ArktCore` `SidebarModel` (after Track B merges).
- `ChromiumEngine: EngineClient` over ArktCore.framework (after the week-1 engine spike's GO).
- TCA reducers, persistence, drag and drop with spring reordering, split view, Little Arkt, Peek, archive.
- Metal theme renderer with grain textures (`ThemeBackgroundView` keeps the same `setPosition` API so it can be
  swapped).
- Spring constants matching Arc (`SpringPreset` is the single place to update).

## Open questions

1. Spring preset values and which preset Arc uses for Space paging and the command bar (needs parity measurement of
   Arc's spring presets).
2. Unmeasured chrome constants: traffic-light origin, sidebar min/max width, row corner radius, bottom bar height,
   command bar max visible rows and surface color.
3. Bundle identifier and signing team (`dev.arkt.ArktShell` and ad-hoc signing are placeholders).
4. Design section 5's "8.3 ms" frame gate: a 120 Hz frame is 8.333 ms, so the literal value fails every frame.
   Proposal: amend to "more than one refresh interval + 0.25 ms" (8.6 ms at 120 Hz), which is what this track measures.
5. Default search engine for non-URL command bar input (Google placeholder).

## C3 review follow-ups (deferred)

- Removal and move handling in the sidebar outline that keeps folders' expanded or collapsed state, plus
  `StubSidebar` remove/move with tests. Needed before drag and drop (index-before-removal convention).
- Check that the pressed state is visible (the 6.5% fill under the pointer during `NSOutlineView`'s mouse tracking).
- Hover staleness: rows and tiles keep `isHovered` when content scrolls or reloads under a still pointer.
- Favorites grid first-responder and keyboard behavior.
- Space dots: accessibility labels and keyboard selection. Done in C6: each dot is an accessibility button named after its Space (press selects); keyboard selection is Ctrl-1..9 and Cmd-Opt-Left/Right, the dots take no key focus yet.
- Open-folder icon for expanded folders.

## C5 review follow-ups (deferred)

- Latency gate as adopted: `show()` main-thread CPU time p95 < 4 ms, plus wall-clock "earliest frame"
  (p95 total <= wall work p95 + 2 refresh intervals + 0.5 ms). The CPU gate is always asserted. The earliest-frame
  check is asserted only when the 1-minute load average (`getloadavg`) is below
  `ProcessInfo.activeProcessorCount`; otherwise its numbers are printed and attached
  (`commandbar.earliestframe ... asserted=no`) and only that assertion is skipped, because under saturation
  (measured at load ~300) the main run loop misses vsyncs after `show()` returns. The test also needs the display
  awake (a display link does not tick while the display is off).
- Enter on an empty query (RT-08): currently switches to the first listed open tab (the empty-query results are the open tabs); it closes the bar only when there are no tabs. Verify against Arc (RT-08).
- Reposition the open bar when the parent moves or changes screen; prewarm on `parent.screen`.
- Cmd-Enter / Opt-Enter (KB-085, RT-08), hover selection, PageUp/PageDown, arrow wrap (RT-08).
- Menu routing test through `NSApp.sendAction` (Cmd-T/Cmd-L reach `ShellWindowController` while the bar is key).
- URL parsing: trailing-dot hosts (`example.com.`), underscore hosts, user-info (`user@host`).
- Cmd-L on a URL shows the same text in the "open" and "Search Google" rows; dedupe or relabel.
- IPv4 octets with leading zeros (`010.0.0.1`) are accepted but Chromium reads them as octal; reject or canonicalise (C5 re-review minor).
- Run `testAppearsUnder16ms` once on an idle machine and record the `asserted=yes` line in the results doc before sign-off.

## C6 review follow-ups (deferred)

- Next / Previous Space at the ends: the shell stops at the first and last Space; Arc may wrap. Verify at runtime
  (RT item) before changing `SidebarController.nextSpace` / `previousSpace`.
- GS-002: mouse buttons 3 / 4 switch to the previous / next Space (BH-035). Not implemented.
- M1: horizontal swipes that start over the favorites grid or the bottom bar do not reach the pager yet (only the
  outline and the Space title do).
- I3: responsive scrolling (`NSScrollView` non-contiguous / responsive-scroll paths) for the outline, and I4: move
  the strip with a layer transform instead of `setFrameOrigin`. Decide both from idle-machine pacing in C7; the
  loaded runs so far record one 9-12 ms frame per scripted swipe (0 for keyboard switches).
- Pre-showing neighbouring pages on touch-down was tried and reverted (2026-10-23, load ~130-150 on 10 cores,
  scripted swipe, 3 runs each). Before: over8.6 = 0 / 1 / 1, max 8.39 / 10.04 / 10.97 ms. With pre-show:
  1 / 1 / 1, max 14.34 / 13.08 / 12.91 ms. The pacing test now prints the index of each slow frame: the
  single slow frame is always frame 0 (the first interval after the swipe begins), with or without
  pre-show, so un-hiding a page is not the cause. Next suspects: the first strip move after the pacer's and
  the script's display links start, or display-link start-up itself. Re-measure on an idle machine in C7.
- M3: catch a settle while it overshoots past the last page (the drag base rounds the overshot position).
- M4: a sidebar resize during an active swipe keeps the old page width until the gesture ends.
- M6: grain renderer: real Arc textures (grain, sand, denim, tweed), intensity from the metallib, Metal renderer
  with `overlayColors` (data-model doc 1.6).
- M9: the flavor flip (sidebar appearance aqua / darkAqua) at the halfway point is a known hitch risk; precompute
  both flavors on the row layers if C7 pacing shows it.
- M10: space-level change events in `SidebarSource` (add / remove / reorder / retheme a Space) so the pager and the
  themes refresh without polling `spaceOrder`.
