import Foundation
import Testing
import SidebarModel

struct SidebarStorageFormatTests {
  static func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "sidebar-v1", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// The fixture as a mutable JSON tree, changed by `change`, re-serialized.
  static func mutatedFixture(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    try change(&json)
    return try JSONSerialization.data(withJSONObject: json)
  }

  static func roundTrip(_ sidebar: Sidebar) throws -> Sidebar {
    try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))
  }

  /// A rich sidebar built through the public API, including a move, two favorites profiles and a theme.
  static func richSidebar() throws -> Sidebar {
    var sidebar = Sidebar()
    let theme = SpaceTheme(baseColors: [RGBA(red: 0.1, green: 0.2, blue: 0.3)], texture: "grain", isDark: true)
    let work = sidebar.addSpace(title: "Work", theme: theme)
    let home = sidebar.addSpace(title: "Home", profile: "personal")
    let folder = try sidebar.addFolder(title: "Docs", in: .pinned(work))
    let inner = try sidebar.addFolder(title: "Inner", in: .folder(folder))
    try sidebar.addTab(url: URL(string: "https://example.com/1")!, title: "One", customTitle: "Uno", in: .folder(inner))
    let split = try sidebar.addSplit(orientation: .vertical, widthFactors: [0.3, 0.7], in: .today(work))
    try sidebar.addTab(url: URL(string: "https://example.com/2")!, title: "Two", in: .split(split))
    try sidebar.addTab(url: URL(string: "https://example.com/3")!, title: "Three", in: .split(split))
    let moved = try sidebar.addTab(
      url: URL(string: "https://example.com/4")!, title: "Four", lastActiveAt: Date(timeIntervalSinceReferenceDate: 783_000_050.75), in: .today(home))
    try sidebar.move(moved, to: .pinned(home), at: 0)
    try sidebar.addTab(url: URL(string: "https://example.com/m")!, title: "Mail", in: .favorites(profile: "default"))
    try sidebar.addTab(url: URL(string: "https://example.com/p")!, title: "Pay", in: .favorites(profile: "personal"))
    return sidebar
  }

  @Test func roundTripPreservesEverything() throws {
    let sidebar = try Self.richSidebar()
    #expect(try Self.roundTrip(sidebar) == sidebar)
  }

  @Test func roundTripKeepsFractionalDatesExactly() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let created = Date(timeIntervalSinceReferenceDate: 783_000_000.123_456_7)
    let active = Date(timeIntervalSinceReferenceDate: 1.0 / 3.0)
    try sidebar.addTab(
      url: URL(string: "https://example.com")!, title: "T", lastActiveAt: active, in: .today(space), createdAt: created)
    #expect(try Self.roundTrip(sidebar) == sidebar)
  }

  @Test func splitBuiltByOperationsRoundTrips() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "S")
    let tabs = try (0..<3).map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: "T\($0)", in: .today(space))
    }
    let split = try sidebar.createSplit(of: [tabs[1], tabs[0]], orientation: .vertical)
    try sidebar.addPane(tabs[2], to: split)
    try sidebar.setSplitWidthFactors(split, [1, 2, 1])
    #expect(sidebar.children(of: .split(split)) == [tabs[1], tabs[0], tabs[2]])
    #expect(try Self.roundTrip(sidebar) == sidebar)
  }

  @Test func emptySidebarRoundTrips() throws {
    #expect(try Self.roundTrip(Sidebar()) == Sidebar())
  }

  @Test func encodingIsDeterministic() throws {
    let sidebar = try Self.richSidebar()
    let first = try SidebarStorageFormat.encode(sidebar)
    #expect(try SidebarStorageFormat.encode(sidebar) == first)
    #expect(try SidebarStorageFormat.encode(SidebarStorageFormat.decode(first)) == first)
  }

  static func fixtureData(version name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// Version 1 has no Space icon. Reading it is the migration: every icon stays nil, and writing it back stores
  /// version 2. Compared as JSON values, not bytes.
  @Test func reencodingVersion1FixtureMigratesToVersion2WithoutIcons() throws {
    let fixture = try Self.fixtureData()
    let sidebar = try SidebarStorageFormat.decode(fixture)
    #expect(sidebar.spaces.values.allSatisfy { $0.icon == nil })
    let reencoded = try SidebarStorageFormat.encode(sidebar)
    var expected = try #require(try JSONSerialization.jsonObject(with: fixture) as? [String: Any])
    expected["version"] = SidebarStorageFormat.currentVersion
    let actual = try #require(try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary)
    #expect(SidebarStorageFormat.currentVersion == 2)
    #expect(actual == (expected as NSDictionary))
  }

  /// Golden test: decoding and re-encoding the frozen v2 fixture reproduces it (compared as JSON values, not bytes).
  @Test func reencodingVersion2FixtureReproducesIt() throws {
    let fixture = try Self.fixtureData(version: "sidebar-v2")
    let sidebar = try SidebarStorageFormat.decode(fixture)
    let alpha = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
    #expect(sidebar.spaces[alpha]?.icon == .symbol("star"))
    let beta = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000B1"))
    #expect(sidebar.spaces[beta]?.icon == .emoji("\u{1F680}"))
    let reencoded = try SidebarStorageFormat.encode(sidebar)
    let expected = try #require(try JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    let actual = try #require(try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary)
    #expect(actual == expected)
  }

  /// The stored icon shape is explicit and tagged, like `NodeKind`: one key names the case, one holds its value.
  @Test func spaceIconEncodesAsATaggedObject() throws {
    func object(_ icon: SpaceIcon) throws -> NSDictionary {
      try #require(try JSONSerialization.jsonObject(with: SidebarStorageFormat.makeEncoder().encode(icon)) as? NSDictionary)
    }
    #expect(try object(.symbol("star")) == (["type": "symbol", "symbol": "star"] as NSDictionary))
    #expect(try object(.emoji("\u{1F680}")) == (["type": "emoji", "emoji": "\u{1F680}"] as NSDictionary))
    for icon in [SpaceIcon.symbol("star"), .emoji("\u{1F468}\u{200D}\u{1F4BB}")] {
      let data = try SidebarStorageFormat.makeEncoder().encode(icon)
      #expect(try SidebarStorageFormat.makeDecoder().decode(SpaceIcon.self, from: data) == icon)
    }
    let unknown = Data(#"{"type":"sticker","sticker":"x"}"#.utf8)
    #expect(throws: DecodingError.self) { try SidebarStorageFormat.makeDecoder().decode(SpaceIcon.self, from: unknown) }
  }

  /// A version 1 document has no icon field. An `icon` key in one is not read, whether it holds a version 2 icon
  /// or anything else.
  @Test(arguments: [0, 1])
  func version1DocumentIgnoresAnIconKey(variant: Int) throws {
    let icon: Any = if variant == 0 { ["type": "symbol", "symbol": "star"] as [String: String] } else { 42 }
    let data = try Self.mutatedFixture { json in
      var spaces = try #require(json["spaces"] as? [[String: Any]])
      var space = try #require(spaces[0]["space"] as? [String: Any])
      space["icon"] = icon
      spaces[0]["space"] = space
      json["spaces"] = spaces
    }
    let sidebar = try SidebarStorageFormat.decode(data)
    let withoutKey = try SidebarStorageFormat.decode(Self.fixtureData())
    #expect(sidebar == withoutKey)
    #expect(sidebar.spaces.values.allSatisfy { $0.icon == nil })
  }

  @Test func decodesVersion1Fixture() throws {
    let sidebar = try SidebarStorageFormat.decode(Self.fixtureData())
    let alpha = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
    let folder = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000101"))
    let split = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000103"))
    let beta = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000B1"))
    #expect(sidebar.spaceOrder == [alpha, beta])
    #expect(sidebar.spaces[alpha]?.theme?.texture == "grain")
    #expect(sidebar.children(of: .pinned(alpha)) == [folder, split])
    #expect(sidebar.children(of: .split(split)).count == 2)
    #expect(sidebar.nodes[split]?.kind == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])))
    let todayTab = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000106"))
    #expect(sidebar.nodes[todayTab]?.kind == .tab(TabItem(
      url: URL(string: "https://example.com/d")!, title: "D",
      lastActiveAt: Date(timeIntervalSinceReferenceDate: 783_000_100.25))))
    #expect(sidebar.children(of: .favorites(profile: "default")).count == 1)
    let renamed = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000102"))
    #expect(sidebar.nodes[renamed]?.parent == .folder(folder))
    #expect(sidebar.nodes[renamed]?.kind == .tab(TabItem(
      url: URL(string: "https://example.com/a")!, title: "A", customTitle: "Renamed A")))
    #expect(sidebar.nodes[renamed]?.createdAt == Date(timeIntervalSinceReferenceDate: 783_000_001.5))
  }

  @Test func rejectsDuplicateNodeIDAcrossSections() throws {
    let duplicate = "D1000000-0000-4000-8000-000000000107"
    let data = try Self.mutatedFixture { json in
      var spaces = try #require(json["spaces"] as? [[String: Any]])
      var today = try #require(spaces[0]["today"] as? [[String: Any]])
      today[0]["id"] = duplicate
      spaces[0]["today"] = today
      json["spaces"] = spaces
    }
    let id = try #require(UUID(uuidString: duplicate))
    #expect(throws: SidebarDocumentError.invalidTree(.duplicateID(id))) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsDuplicateSpaceID() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = try #require(json["spaces"] as? [[String: Any]])
      var beta = try #require(spaces[1]["space"] as? [String: Any])
      beta["id"] = "D1000000-0000-4000-8000-0000000000A1"
      spaces[1]["space"] = beta
      json["spaces"] = spaces
    }
    let id = try #require(UUID(uuidString: "D1000000-0000-4000-8000-0000000000A1"))
    #expect(throws: SidebarDocumentError.invalidTree(.duplicateID(id))) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsFolderInsideSplit() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = try #require(json["spaces"] as? [[String: Any]])
      var pinned = try #require(spaces[0]["pinned"] as? [[String: Any]])
      var children = try #require(pinned[1]["children"] as? [[String: Any]])
      children[0]["kind"] = ["type": "folder", "folder": ["title": "Nope"]]
      pinned[1]["children"] = children
      spaces[0]["pinned"] = pinned
      json["spaces"] = spaces
    }
    let split = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000103"))
    #expect(throws: SidebarDocumentError.invalidTree(.invalidDestination(.split(split)))) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsChildrenUnderATab() throws {
    let data = try Self.mutatedFixture { json in
      var spaces = try #require(json["spaces"] as? [[String: Any]])
      var today = try #require(spaces[0]["today"] as? [[String: Any]])
      today[0]["children"] = [[
        "id": "D1000000-0000-4000-8000-000000000199", "createdAt": 0, "children": [],
        "kind": ["type": "tab", "tab": ["url": "https://example.com/x", "title": "X"]],
      ]]
      spaces[0]["today"] = today
      json["spaces"] = spaces
    }
    let tab = try #require(UUID(uuidString: "D1000000-0000-4000-8000-000000000106"))
    #expect(throws: SidebarDocumentError.invalidTree(.invalidDestination(.folder(tab)))) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsDuplicateFavoritesProfile() throws {
    let data = try Self.mutatedFixture { json in
      json["favorites"] = [["profile": "default", "items": []], ["profile": "default", "items": []]]
    }
    #expect(throws: SidebarDocumentError.duplicateFavoritesProfile("default")) {
      try SidebarStorageFormat.decode(data)
    }
  }

  @Test func rejectsUnknownNodeType() throws {
    let data = try Self.mutatedFixture { json in
      var favorites = try #require(json["favorites"] as? [[String: Any]])
      var items = try #require(favorites[0]["items"] as? [[String: Any]])
      items[0]["kind"] = ["type": "easel", "easel": [:]]
      favorites[0]["items"] = items
      json["favorites"] = favorites
    }
    #expect(throws: DecodingError.self) { try SidebarStorageFormat.decode(data) }
  }

  @Test func rejectsUnsupportedVersion() throws {
    for version in [SidebarStorageFormat.currentVersion + 1, 0, -1] {
      let data = try Self.mutatedFixture { $0["version"] = version }
      #expect(throws: SidebarDocumentError.unsupportedVersion(version)) { try SidebarStorageFormat.decode(data) }
    }
  }

  /// A favorites tree of `depth` nested folders (the root counts as 1), as fixture JSON.
  static func nestedFolders(depth: Int) throws -> (Data, ids: [String]) {
    let ids = (0..<depth).map { String(format: "D1000000-0000-4000-8000-%012d", 500 + $0) }
    var node: [String: Any]? = nil
    for id in ids.reversed() {
      node = [
        "id": id, "createdAt": 0, "children": node.map { [$0] } ?? [],
        "kind": ["type": "folder", "folder": ["title": "F"]],
      ]
    }
    let root = try #require(node)
    let data = try mutatedFixture { $0["favorites"] = [["profile": "deep", "items": [root]]] }
    return (data, ids)
  }

  @Test func acceptsFoldersAtMaximumDepth() throws {
    let withoutFavorites = try SidebarStorageFormat.decode(Self.mutatedFixture { $0["favorites"] = [] as [Any] })
    let (data, _) = try Self.nestedFolders(depth: SidebarStorageFormat.maximumNestingDepth)
    let sidebar = try SidebarStorageFormat.decode(data)
    #expect(sidebar.nodes.count == withoutFavorites.nodes.count + SidebarStorageFormat.maximumNestingDepth)
  }

  @Test func rejectsFoldersDeeperThanMaximum() throws {
    let (data, ids) = try Self.nestedFolders(depth: SidebarStorageFormat.maximumNestingDepth + 1)
    let tooDeep = try #require(UUID(uuidString: ids[SidebarStorageFormat.maximumNestingDepth]))
    #expect(throws: SidebarDocumentError.invalidTree(.nestingTooDeep(tooDeep))) { try SidebarStorageFormat.decode(data) }
  }

  @Test func pathologicallyDeepFileThrowsInsteadOfCrashing() throws {
    let depth = 5_000
    let open = #"{"id":"D1000000-0000-4000-8000-000000000999","createdAt":0,"kind":{"type":"folder","folder":{"title":"F"}},"children":["#
    let json = #"{"version":1,"spaces":[],"favorites":[{"profile":"p","items":["#
      + String(repeating: open, count: depth) + String(repeating: "]}", count: depth) + "]}]}"
    #expect(throws: (any Error).self) { try SidebarStorageFormat.decode(Data(json.utf8)) }
  }

  /// Property: any sidebar the model accepted encodes and decodes back equal, including one grown to the depth cap.
  @Test(arguments: [1, 2, 3, 42, 2026] as [UInt64])
  func everyAcceptedSidebarRoundTrips(seed: UInt64) throws {
    let sidebar = Self.randomSidebar(seed: seed)
    #expect(sidebar.nodes.count > 50)
    #expect(try Self.roundTrip(sidebar) == sidebar)
    let bytes = try SidebarStorageFormat.encode(sidebar)
    #expect(try SidebarStorageFormat.encode(SidebarStorageFormat.decode(bytes)) == bytes)
  }

  /// SplitMix64, so every seed builds the same sidebar on every run.
  struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Random inserts, moves and removes (each may be refused by the model), then a folder chain grown in one
  /// Space until the model refuses it. Ids are minted from a counter so the result depends only on `seed`.
  static func randomSidebar(seed: UInt64) -> Sidebar {
    var rng = SeededGenerator(state: seed)
    var sidebar = Sidebar()
    var counter = 0
    func nextID() -> UUID {
      counter += 1
      return UUID(uuidString: String(format: "E0000000-0000-4000-8000-%012d", counter))!
    }
    for (index, profile) in ["default", "default", "work"].enumerated() {
      try? sidebar.addSpace(Space(id: nextID(), title: "S\(index)", profile: profile))
    }
    let base = 783_000_000.0
    for step in 0..<400 {
      let nodeIDs = sidebar.nodes.keys.sorted { $0.uuidString < $1.uuidString }
      var locations: [Location] = sidebar.spaceOrder.flatMap { [Location.pinned($0), .today($0)] }
      locations += [.favorites(profile: "default"), .favorites(profile: "work")]
      for id in nodeIDs {
        switch sidebar.nodes[id]?.kind {
        case .folder?: locations.append(.folder(id))
        case .split?: locations.append(.split(id))
        default: break
        }
      }
      let location = locations[Int.random(in: 0..<locations.count, using: &rng)]
      let index = Int.random(in: -1...6, using: &rng)
      let createdAt = Date(timeIntervalSinceReferenceDate: base + Double(step) * 0.37)
      let kind: NodeKind
      switch Int.random(in: 0..<10, using: &rng) {
      case 0..<4:
        let active: Date? = Bool.random(using: &rng) ? Date(timeIntervalSinceReferenceDate: base + Double(step) / 3) : nil
        kind = .tab(TabItem(
          url: URL(string: "https://example.com/\(step)")!, title: "T\(step)",
          customTitle: Bool.random(using: &rng) ? "C\(step)" : nil, lastActiveAt: active))
      case 4..<6:
        kind = .folder(FolderItem(title: "F\(step)"))
      case 6:
        kind = .split(SplitItem(orientation: Bool.random(using: &rng) ? .horizontal : .vertical, widthFactors: [0.4, 0.6]))
      case 7..<9:
        if let id = nodeIDs.randomElement(using: &rng) { try? sidebar.move(id, to: location, at: index) }
        continue
      default:
        if step % 3 == 0, let id = nodeIDs.randomElement(using: &rng) { sidebar.remove(id) }
        continue
      }
      try? sidebar.insert(NodeSnapshot(id: nextID(), kind: kind, createdAt: createdAt), in: location, at: index)
    }
    var location = Location.today(sidebar.spaceOrder[0])
    var chain = 0
    for _ in 0..<100 {
      let folder = NodeSnapshot(
        id: nextID(), kind: .folder(FolderItem(title: "Deep")), createdAt: Date(timeIntervalSinceReferenceDate: base))
      guard (try? sidebar.insert(folder, in: location)) != nil else { break }
      location = .folder(folder.id)
      chain += 1
    }
    precondition(chain == Sidebar.maximumNestingDepth, "the model must stop the chain exactly at the cap")
    return sidebar
  }
}
