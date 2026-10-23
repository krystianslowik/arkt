# Track B: Sidebar Model and Arc Import Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** A pure-Swift package with Arkt's sidebar data model and a read-only importer that turns Arc's
`StorableSidebar.json` into that model, fully tested, built in parallel with the Chromium engine spike.

**Architecture:** SwiftPM package `app/ArktCore` with two library targets: `SidebarModel` (our own types: spaces,
favorites, pinned and Today trees of tabs, folders and split views) and `ArcImport` (Codable mirror of Arc's on-disk
format plus a mapper into `SidebarModel`). No third-party dependencies yet (TCA arrives with the app shell, after the
Chromium build frees the CPU). Arc's format is documented in the private data-model notes
(sections 0, 1.2-1.6 and 7).

**Tech Stack:** Swift 6 (Xcode 27.1 toolchain), SwiftPM, Swift Testing (`import Testing`), Foundation, CryptoKit.

**Rules**
- `$REPO` = root of this git repo, branch `spike/week1`. Package root: `$REPO/app/ArktCore`.
- A Chromium build is running and saturating the CPU: run `swift build`/`swift test` with `-j 2`.
- Test fixtures are synthetic. Never copy anything from the user's real Arc data into the repo.
- The importer only ever reads Arc files. It never writes to `~/Library/Application Support/Arc`.
- No emojis in code. Plain commit messages. zsh.

---

### Task B1: Package scaffold

**Files:**
- Create: `app/ArktCore/Package.swift`
- Create: `app/ArktCore/Sources/SidebarModel/SidebarModel.swift`
- Create: `app/ArktCore/Sources/ArcImport/ArcImport.swift`
- Create: `app/ArktCore/Tests/SidebarModelTests/SmokeTests.swift`
- Create: `app/ArktCore/Tests/ArcImportTests/SmokeTests.swift`
- Modify: `.gitignore` (add `.build/` and `.swiftpm/`)

**Step 1: Package.swift**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ArktCore",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SidebarModel", targets: ["SidebarModel"]),
    .library(name: "ArcImport", targets: ["ArcImport"]),
  ],
  targets: [
    .target(name: "SidebarModel"),
    .target(name: "ArcImport", dependencies: ["SidebarModel"]),
    .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"]),
    .testTarget(
      name: "ArcImportTests",
      dependencies: ["ArcImport"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
```
Create an empty `Tests/ArcImportTests/Fixtures/.gitkeep` so the resource path exists.

**Step 2: Placeholder sources and smoke tests**

`Sources/SidebarModel/SidebarModel.swift`: `public enum SidebarModelVersion { public static let current = 1 }`
`Sources/ArcImport/ArcImport.swift`: `import SidebarModel` plus `public enum ArcImportVersion { public static let current = 1 }`
Each smoke test: `@Test func versionIsOne() { #expect(SidebarModelVersion.current == 1) }` (same for `ArcImportVersion`).

**Step 3: Run**

Run: `cd $REPO/app/ArktCore && swift test -j 2`
Expected: 2 tests pass.

**Step 4: Commit**
```zsh
cd $REPO && git add .gitignore app && git commit -m "Add ArktCore Swift package"
```

---

### Task B2: Decoding helpers for Arc's Codable quirks

Arc's files use two non-obvious encodings (data-model doc section 0): dictionaries with non-String keys are flat
alternating arrays `[k0, v0, k1, v1]`, and enums with payloads are `{caseName: {_0: payload}}`.

**Files:**
- Create: `app/ArktCore/Sources/ArcImport/FlatDictionary.swift`
- Create: `app/ArktCore/Sources/ArcImport/TaggedEnum.swift`
- Test: `app/ArktCore/Tests/ArcImportTests/DecodingHelpersTests.swift`

**Step 1: Write the failing tests**
```swift
import Foundation
import Testing
@testable import ArcImport

struct DecodingHelpersTests {
  @Test func flatDictionaryKeepsPairsInOrder() throws {
    let json = #"["b", 2, "a", 1, "c", 3]"#.data(using: .utf8)!
    let dict = try JSONDecoder().decode(FlatDictionary<String, Int>.self, from: json)
    #expect(dict.pairs.map(\.key) == ["b", "a", "c"])
    #expect(dict["a"] == 1)
    #expect(dict["missing"] == nil)
  }

  @Test func flatDictionaryRejectsOddLength() {
    let json = #"["a", 1, "b"]"#.data(using: .utf8)!
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(FlatDictionary<String, Int>.self, from: json)
    }
  }

  @Test func flatDictionaryAcceptsObjectKeys() throws {
    let json = #"[{"global": {}}, 7]"#.data(using: .utf8)!
    let dict = try JSONDecoder().decode(FlatDictionary<TaggedEnum, Int>.self, from: json)
    #expect(dict.pairs.first?.key.caseName == "global")
    #expect(dict.pairs.first?.value == 7)
  }

  @Test func taggedEnumExposesCaseAndPayload() throws {
    let json = #"{"spaceItems": {"_0": "SPACE-1"}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(tag.caseName == "spaceItems")
    #expect(try tag.payload(String.self) == "SPACE-1")
  }

  @Test func taggedEnumWithoutPayload() throws {
    let json = #"{"pinned": {}}"#.data(using: .utf8)!
    let tag = try JSONDecoder().decode(TaggedEnum.self, from: json)
    #expect(tag.caseName == "pinned")
    #expect(tag.hasPayload == false)
  }
}
```

**Step 2: Run to verify failure**

Run: `swift test -j 2 --filter DecodingHelpersTests`
Expected: FAIL, `FlatDictionary` / `TaggedEnum` not found.

**Step 3: Implement**

`FlatDictionary.swift`:
```swift
/// A dictionary that Swift's JSONEncoder wrote as a flat `[k0, v0, k1, v1, ...]`
/// array because its key type is not String. Preserves the on-disk order,
/// which Arc uses for space order.
public struct FlatDictionary<Key: Decodable & Hashable, Value: Decodable>: Decodable {
  public struct Pair {
    public let key: Key
    public let value: Value
  }

  public let pairs: [Pair]
  private let index: [Key: Int]

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var pairs: [Pair] = []
    while !container.isAtEnd {
      let key = try container.decode(Key.self)
      guard !container.isAtEnd else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Flat dictionary has a key without a value")
      }
      pairs.append(Pair(key: key, value: try container.decode(Value.self)))
    }
    self.pairs = pairs
    self.index = Dictionary(pairs.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
  }

  public subscript(key: Key) -> Value? {
    index[key].map { pairs[$0].value }
  }

  public var values: [Value] { pairs.map(\.value) }
}
```

`TaggedEnum.swift`:
```swift
import Foundation

/// An enum case as Swift's synthesized Codable writes it: a single-key object
/// `{caseName: {...}}`, where associated values sit under `_0`, `_1`, ...
public struct TaggedEnum: Decodable, Hashable {
  public let caseName: String
  private let body: [String: JSONValue]

  public var hasPayload: Bool { !body.isEmpty }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    guard container.allKeys.count == 1, let key = container.allKeys.first else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: decoder.codingPath, debugDescription: "Expected a single-key enum object"))
    }
    caseName = key.stringValue
    body = (try? container.decode([String: JSONValue].self, forKey: key)) ?? [:]
  }

  /// Decodes associated value `_<position>` as `T`.
  public func payload<T: Decodable>(_ type: T.Type, at position: Int = 0) throws -> T {
    guard let value = body["_\(position)"] else {
      throw DecodingError.valueNotFound(T.self, .init(
        codingPath: [], debugDescription: "\(caseName) has no _\(position)"))
    }
    return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
  }
}

struct AnyKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}
```
Also create `JSONValue.swift`: a `Codable, Hashable` enum (`string, number(Double), bool, null, array([JSONValue]),
object([String: JSONValue])`) with single-value decoding in that order and matching encoding.

**Step 4: Run tests**

Run: `swift test -j 2 --filter DecodingHelpersTests`
Expected: 5 tests pass.

**Step 5: Commit**
```zsh
cd $REPO && git add app && git commit -m "Decode Arc flat dictionaries and tagged enums"
```

---

### Task B3: Arkt sidebar model

Our own model (design section 2 and 4). Independent of Arc's format.

**Files:**
- Modify: `app/ArktCore/Sources/SidebarModel/SidebarModel.swift`
- Test: `app/ArktCore/Tests/SidebarModelTests/SidebarTests.swift`

**Step 1: Failing tests**
```swift
import Foundation
import Testing
@testable import SidebarModel

struct SidebarTests {
  func makeSidebar() -> Sidebar {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = sidebar.addFolder(title: "Docs", in: .pinned(space))
    sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .folder(folder))
    sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    return sidebar
  }

  @Test func spacesKeepInsertionOrder() {
    var sidebar = Sidebar()
    let a = sidebar.addSpace(title: "A")
    let b = sidebar.addSpace(title: "B")
    #expect(sidebar.spaceOrder == [a, b])
  }

  @Test func childrenAreOrdered() {
    let sidebar = makeSidebar()
    let space = sidebar.spaceOrder[0]
    let pinned = sidebar.children(of: .pinned(space))
    #expect(pinned.count == 1)
    guard case .folder(let folder) = sidebar.nodes[pinned[0]]?.kind else {
      Issue.record("expected folder"); return
    }
    #expect(folder.title == "Docs")
    #expect(sidebar.children(of: .folder(pinned[0])).count == 1)
    #expect(sidebar.children(of: .today(space)).count == 1)
  }

  @Test func moveReordersAndReparents() {
    var sidebar = makeSidebar()
    let space = sidebar.spaceOrder[0]
    let todayTab = sidebar.children(of: .today(space))[0]
    sidebar.move(todayTab, to: .pinned(space), at: 0)
    #expect(sidebar.children(of: .today(space)).isEmpty)
    #expect(sidebar.children(of: .pinned(space)).first == todayTab)
  }

  @Test func removeDropsDescendants() {
    var sidebar = makeSidebar()
    let space = sidebar.spaceOrder[0]
    let folder = sidebar.children(of: .pinned(space))[0]
    sidebar.remove(folder)
    #expect(sidebar.children(of: .pinned(space)).isEmpty)
    #expect(sidebar.nodes.count == 1)
  }
}
```

**Step 2: Run to verify failure** (`swift test -j 2 --filter SidebarTests`; expected: compile failure).

**Step 3: Implement** in `SidebarModel.swift`:
- `public typealias NodeID = UUID`, `public typealias SpaceID = UUID`.
- `public struct Space: Hashable { id, title, profile: String, theme: SpaceTheme? }` with
  `SpaceTheme { baseColors: [RGBA], overlayColors: [RGBA], texture: String?, isDark: Bool }`,
  `RGBA { red, green, blue, alpha: Double }`.
- `public enum NodeKind: Hashable { case tab(Tab), folder(Folder), split(Split) }`, with `Tab { url: URL, title:
  String, customTitle: String?, lastActiveAt: Date? }`, `Folder { title: String }`,
  `Split { orientation: Orientation, widthFactors: [Double] }`, `Orientation { horizontal, vertical }`.
- `public struct Node: Hashable { id: NodeID, kind: NodeKind, parent: Location, createdAt: Date }`.
- `public enum Location: Hashable { case favorites(profile: String), pinned(SpaceID), today(SpaceID), folder(NodeID), split(NodeID) }`.
- `public struct Sidebar`: `spaces: [SpaceID: Space]`, `spaceOrder: [SpaceID]`, `nodes: [NodeID: Node]`,
  `childOrder: [Location: [NodeID]]`; methods `addSpace`, `addFolder`, `addTab`, `addSplit`, `children(of:)`,
  `move(_:to:at:)`, `remove(_:)` (recursive). Keep it a value type; no persistence yet (YAGNI).

**Step 4: Run tests** (expected: 4 pass). **Step 5: Commit** `"Add Arkt sidebar model"`.

---

### Task B4: Codable mirror of StorableSidebar.json

**Files:**
- Create: `app/ArktCore/Sources/ArcImport/ArcSidebarFile.swift`
- Create: `app/ArktCore/Tests/ArcImportTests/Fixtures/StorableSidebar-synthetic.json`
- Test: `app/ArktCore/Tests/ArcImportTests/ArcSidebarFileTests.swift`

**Step 1: Write the synthetic fixture** following data-model doc sections 1.2-1.6 exactly (alternating arrays,
tagged enums, 2001-epoch dates, uppercase UUIDs). Content (all invented): 2 spaces ("Alpha" with an `icon` iconType
and a `blendedGradient` theme with overlay `grain`; "Beta" with no icon and a `blendedSingleColor` theme); each with
pinned and unpinned `itemContainer` roots wired through both `containerIDs` and `newContainerIDs`; one `topApps`
container for profile `{"default": true}` with 2 tabs; Alpha pinned: a `list` folder holding 2 tabs, plus a
`splitView` (vertical, `itemWidthFactors` [0.5, 0.5]) holding 2 tabs; Alpha unpinned: 1 tab with `title` (rename)
set; Beta pinned: 1 tab; Beta unpinned: 1 tab; plus one `easel` item in Beta pinned (unsupported kind).
Include `firebaseSyncState: {}` and `sidebarSyncState: {}` stubs. URLs use `https://example.com/...`.

**Step 2: Failing test**
```swift
import Foundation
import Testing
@testable import ArcImport

struct ArcSidebarFileTests {
  static func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(
      forResource: "StorableSidebar-synthetic", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  @Test func decodesSpacesItemsAndFavorites() throws {
    let file = try ArcSidebarFile.decode(Self.fixture())
    let container = try #require(file.globalContainer)
    #expect(container.spaces.pairs.map(\.value.title) == ["Alpha", "Beta"])
    #expect(container.items.pairs.count == 19)
    #expect(container.topAppsContainerIDs.pairs.count == 1)
  }

  @Test func classifiesItemData() throws {
    let container = try #require(try ArcSidebarFile.decode(Self.fixture()).globalContainer)
    let kinds = Set(container.items.values.map(\.data.caseName))
    #expect(kinds == ["tab", "list", "itemContainer", "splitView", "easel"])
  }
}
```
(Adjust the item count `19` to exactly match the fixture you wrote: 5 containers + items listed in step 1.)

**Step 3: Implement** `ArcSidebarFile` with `static func decode(_ data: Data) throws -> ArcSidebarFile` using a
`JSONDecoder` with default `.deferredToDate` (seconds since 2001, which is what Arc writes). Types:
`ArcSidebarFile { version: Int, sidebar: { containers: FlatDictionary<TaggedEnum, ArcContainer> } }`,
`globalContainer` = the value whose key `caseName == "global"`; `ArcContainer { spaces: FlatDictionary<String,
ArcSpace>, items: FlatDictionary<String, ArcItem>, topAppsContainerIDs: FlatDictionary<JSONValue, String> }`;
`ArcSpace { id, title, profile: JSONValue, newContainerIDs: FlatDictionary<TaggedEnum, String>?, containerIDs:
FlatDictionary<String, String>?, customInfo: JSONValue? }`; `ArcItem { id, parentID: String?, childrenIds:
[String], title: String?, createdAt: Date, data: TaggedEnum }`. Unknown fields are ignored.

**Step 4: Run tests** (expected: pass). **Step 5: Commit** `"Decode Arc StorableSidebar.json"`.

---

### Task B5: Map Arc sidebar into the Arkt model

**Files:**
- Create: `app/ArktCore/Sources/ArcImport/ArcSidebarImporter.swift`
- Test: `app/ArktCore/Tests/ArcImportTests/ArcSidebarImporterTests.swift`

**Step 1: Failing tests** (using the B4 fixture):
- Spaces imported in file order with titles; Alpha's theme has 2+ base colors and texture `grain`; Beta's theme
  has the single color as its only base color.
- Alpha pinned children: [folder "<fixture folder title>", split]; folder has 2 tabs in fixture order; split has
  vertical orientation, width factors [0.5, 0.5], 2 tabs.
- Alpha today: 1 tab whose `customTitle` is the renamed title and `title` is the saved page title.
- Favorites for profile `"default"`: 2 tabs in order.
- The easel is not imported and appears in `report.skipped` with reason `unsupportedKind("easel")`.
- Pinned vs today is decided by the space's `newContainerIDs` (fall back to `containerIDs`), never by the container.

**Step 2: Run to verify failure.**

**Step 3: Implement** `public struct ArcSidebarImporter { public static func makeSidebar(from: ArcSidebarFile)
throws -> (Sidebar, ImportReport) }`. Walk each root container's `childrenIds` recursively (data-model doc 7.2).
`ImportReport { imported counts per kind, skipped: [(itemID: String, reason: SkipReason)] }`. A malformed item is
skipped and reported; the rest still imports (design section 5). Profile `{"default": true}` maps to `"default"`;
other profile shapes map to `"profile-<caseName>"` and are reported.

**Step 4: Run tests** (expected: pass). **Step 5: Commit** `"Import Arc sidebar into Arkt model"`.

---

### Task B6: Favicon lookup

**Files:**
- Create: `app/ArktCore/Sources/ArcImport/ArcFaviconCache.swift`
- Test: `app/ArktCore/Tests/ArcImportTests/ArcFaviconCacheTests.swift`

**Step 1: Failing test:** for item id `"0B3F1C2A-1111-2222-3333-444455556666"`, `ArcFaviconCache.fileName(forItemID:)`
returns the lowercase hex MD5 of exactly that uppercase string (compute the expected value once with
`printf %s "0B3F1C2A-1111-2222-3333-444455556666" | md5` and hardcode it). A second test builds a temp directory with
that file and checks `ArcFaviconCache(directory:).pngData(forItemID:)` returns its bytes, and `nil` for an unknown id.

**Step 2-4:** implement with `CryptoKit.Insecure.MD5`; run tests. **Step 5: Commit** `"Locate Arc favicons by item id"`.

---

### Task B7: Read-only import check against the real Arc file

Verifies the importer on real data without exposing any of it.

**Files:**
- Modify: `app/ArktCore/Package.swift` (add `.executableTarget(name: "arkt-import-check", dependencies: ["ArcImport"])`)
- Create: `app/ArktCore/Sources/arkt-import-check/main.swift`

**Step 1: Implement** a CLI that reads `~/Library/Application Support/Arc/StorableSidebar.json` (path overridable by
the first argument), runs the importer, and prints ONLY counts: spaces, favorites, pinned tabs/folders/splits, today
tabs, skipped items grouped by reason, favicons found vs missing. It must never print titles, URLs or ids. Open the
file read-only (`Data(contentsOf:)`); write nothing.

**Step 2: Run**
```zsh
cd $REPO/app/ArktCore && swift run -j 2 arkt-import-check
```
Expected: counts consistent with data-model doc section 1.2 (N spaces, N items: N tabs, N folders, N containers);
no crash; every skipped item has a reason. Record the printed counts (counts only) in
`docs/plans/2026-10-22-week1-results.md` under "Track B".

**Step 3: Commit** `"Add read-only Arc import check"`.
