import Foundation
import Testing
import ArcImport
import SidebarModel

struct ArcSidebarImporterTests {
  static let alphaID = "A0000000-0000-4000-8000-0000000000A1"
  static let betaID = "A0000000-0000-4000-8000-0000000000B1"
  static let alphaPinnedID = "A0000000-0000-4000-8000-000000000101"
  static let alphaUnpinnedID = "A0000000-0000-4000-8000-000000000102"
  static let folderID = "A0000000-0000-4000-8000-000000000111"
  static let folderTabIDs = ["A0000000-0000-4000-8000-000000000112", "A0000000-0000-4000-8000-000000000113"]
  static let splitID = "A0000000-0000-4000-8000-000000000121"
  static let easelID = "A0000000-0000-4000-8000-000000000212"
  static let betaTodayTabID = "A0000000-0000-4000-8000-000000000221"
  static let favoriteMailID = "A0000000-0000-4000-8000-000000000311"

  // MARK: Fixture helpers

  static func fixtureJSON() throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: ArcSidebarFileTests.fixture()) as? [String: Any])
  }

  /// Applies `change` to the global container object of the fixture and imports the result.
  static func importMutated(
    fallbackCreatedAt: Date = ArcSidebarImporter.defaultFallbackCreatedAt,
    _ change: (inout [String: Any]) throws -> Void
  ) throws -> (Sidebar, ImportReport) {
    let result = try importMutatedResult(fallbackCreatedAt: fallbackCreatedAt, change)
    return (result.sidebar, result.report)
  }

  static func mutatedFile(_ change: (inout [String: Any]) throws -> Void) throws -> ArcSidebarFile {
    var root = try fixtureJSON()
    var sidebar = try #require(root["sidebar"] as? [String: Any])
    var containers = try #require(sidebar["containers"] as? [Any])
    var global = try #require(containers[1] as? [String: Any])
    try change(&global)
    containers[1] = global
    sidebar["containers"] = containers
    root["sidebar"] = sidebar
    return try ArcSidebarFile.decode(JSONSerialization.data(withJSONObject: root))
  }

  static func importMutatedResult(
    fallbackCreatedAt: Date = ArcSidebarImporter.defaultFallbackCreatedAt,
    _ change: (inout [String: Any]) throws -> Void
  ) throws -> ArcImportResult {
    try ArcSidebarImporter.makeSidebar(from: mutatedFile(change), fallbackCreatedAt: fallbackCreatedAt)
  }

  /// Rewrites the value stored under `id` in a flat `[k0, v0, k1, v1, ...]` array.
  static func mutateEntry(
    _ id: String, in field: String, of global: inout [String: Any], _ change: (inout [String: Any]) -> Void
  ) throws {
    var flat = try #require(global[field] as? [Any])
    let keyIndex = try #require(stride(from: 0, to: flat.count, by: 2).first { flat[$0] as? String == id })
    var value = try #require(flat[keyIndex + 1] as? [String: Any])
    change(&value)
    flat[keyIndex + 1] = value
    global[field] = flat
  }

  static func importFixture() throws -> (Sidebar, ImportReport) {
    let result = try importFixtureResult()
    return (result.sidebar, result.report)
  }

  static func importFixtureResult() throws -> ArcImportResult {
    try ArcSidebarImporter.makeSidebar(from: ArcSidebarFile.decode(ArcSidebarFileTests.fixture()))
  }

  static func asTab(_ kind: NodeKind?) -> TabItem? {
    if case .tab(let tab)? = kind { return tab }
    return nil
  }

  static func tab(_ sidebar: Sidebar, _ id: NodeID) throws -> TabItem {
    try #require(asTab(sidebar.nodes[id]?.kind), "node \(id) is not a tab")
  }

  static func spaceID(_ sidebar: Sidebar, titled title: String) throws -> SpaceID {
    try #require(sidebar.spaceOrder.first { sidebar.spaces[$0]?.title == title })
  }

  // MARK: Spaces and themes

  @Test func importsSpacesInFileOrder() throws {
    let (sidebar, _) = try Self.importFixture()
    #expect(sidebar.spaceOrder.compactMap { sidebar.spaces[$0]?.title } == ["Alpha", "Beta"])
    #expect(sidebar.spaceOrder.allSatisfy { sidebar.spaces[$0]?.profile == "default" })
  }

  @Test func mapsBlendedGradientTheme() throws {
    let (sidebar, _) = try Self.importFixture()
    let alpha = try #require(sidebar.spaces[try Self.spaceID(sidebar, titled: "Alpha")])
    let theme = try #require(alpha.theme)
    #expect(theme.baseColors == [
      RGBA(red: 0.2, green: 0.4, blue: 0.9, alpha: 1),
      RGBA(red: 0.9, green: 0.3, blue: 0.5, alpha: 1),
    ])
    #expect(theme.overlayColors == [RGBA(red: 1, green: 1, blue: 1, alpha: 0.3)])
    #expect(theme.texture == "grain")
    #expect(theme.isDark == false)
  }

  @Test func mapsBlendedSingleColorTheme() throws {
    let (sidebar, _) = try Self.importFixture()
    let beta = try #require(sidebar.spaces[try Self.spaceID(sidebar, titled: "Beta")])
    let theme = try #require(beta.theme)
    #expect(theme.baseColors == [RGBA(red: 0.1, green: 0.7, blue: 0.4, alpha: 1)])
    #expect(theme.overlayColors.isEmpty)
    #expect(theme.texture == "sand")
  }

  @Test func darkAppearanceMarksThemeDark() throws {
    let (sidebar, _) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaID, in: "spaces", of: &global) { space in
        var info = space["customInfo"] as? [String: Any] ?? [:]
        var windowTheme = info["windowTheme"] as? [String: Any] ?? [:]
        var background = windowTheme["background"] as? [String: Any] ?? [:]
        var single = background["single"] as? [String: Any] ?? [:]
        var body = single["_0"] as? [String: Any] ?? [:]
        body["contentOverBackgroundAppearance"] = "dark"
        single["_0"] = body
        background["single"] = single
        windowTheme["background"] = background
        info["windowTheme"] = windowTheme
        space["customInfo"] = info
      }
    }
    let beta = try #require(sidebar.spaces[try Self.spaceID(sidebar, titled: "Beta")])
    #expect(beta.theme?.isDark == true)
  }

  @Test func unknownThemeShapeIsNilAndReported() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaID, in: "spaces", of: &global) { space in
        space["customInfo"] = ["windowTheme": ["background": ["perAppearance": ["_0": [:] as [String: Any]]]]]
      }
    }
    let beta = try #require(sidebar.spaces[try Self.spaceID(sidebar, titled: "Beta")])
    #expect(beta.theme == nil)
    #expect(report.warnings == [.unsupportedTheme(spaceID: Self.betaID)])
  }

  @Test func nonDefaultProfileIsNamedAndReportedOnce() throws {
    let profile: [String: Any] = ["custom": ["_0": ["directoryBasename": "Profile 1"]]]
    let (sidebar, report) = try Self.importMutated { global in
      for id in [Self.alphaID, Self.betaID] {
        try Self.mutateEntry(id, in: "spaces", of: &global) { $0["profile"] = profile }
      }
    }
    #expect(sidebar.spaceOrder.allSatisfy { sidebar.spaces[$0]?.profile == "profile-custom" })
    #expect(report.warnings == [.unrecognizedProfile("profile-custom")])
  }

  // MARK: Sections

  @Test func alphaPinnedHasFolderThenSplit() throws {
    let (sidebar, _) = try Self.importFixture()
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    let pinned = sidebar.children(of: .pinned(alpha))
    #expect(pinned.count == 2)
    let folderNode = try #require(sidebar.nodes[pinned[0]])
    #expect(folderNode.kind == .folder(FolderItem(title: "Reading")))
    #expect(folderNode.createdAt == Date(timeIntervalSinceReferenceDate: 780_000_302.5))
    let folderTabs = try sidebar.children(of: .folder(pinned[0])).map { try Self.tab(sidebar, $0) }
    #expect(folderTabs.map(\.title) == ["Article One", "Article Two"])
    #expect(folderTabs.map(\.url.absoluteString) == ["https://example.com/articles/one", "https://example.com/articles/two"])
    #expect(folderTabs[0].lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_000_000.25))

    let splitNode = try #require(sidebar.nodes[pinned[1]])
    #expect(splitNode.kind == .split(SplitItem(orientation: .vertical, widthFactors: [0.5, 0.5])))
    let splitTabs = try sidebar.children(of: .split(pinned[1])).map { try Self.tab(sidebar, $0) }
    #expect(splitTabs.map(\.title) == ["Left Pane", "Right Pane"])
  }

  @Test func alphaTodayKeepsRenamedTitleSeparate() throws {
    let (sidebar, _) = try Self.importFixture()
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    let today = sidebar.children(of: .today(alpha))
    #expect(today.count == 1)
    let tab = try Self.tab(sidebar, today[0])
    #expect(tab.customTitle == "My Renamed Tab")
    #expect(tab.title == "Example News")
    #expect(tab.url == URL(string: "https://example.com/news"))
  }

  @Test func betaPinnedSkipsEasel() throws {
    let (sidebar, report) = try Self.importFixture()
    let beta = try Self.spaceID(sidebar, titled: "Beta")
    let pinned = try sidebar.children(of: .pinned(beta)).map { try Self.tab(sidebar, $0) }
    #expect(pinned.map(\.title) == ["Example Wiki"])
    let today = try sidebar.children(of: .today(beta)).map { try Self.tab(sidebar, $0) }
    #expect(today.map(\.url.absoluteString) == ["https://example.com/search?q=arkt"])
    #expect(report.skipped == [SkippedItem(itemID: Self.easelID, reason: .unsupportedKind("easel"))])
  }

  @Test func favoritesForDefaultProfile() throws {
    let (sidebar, _) = try Self.importFixture()
    let favorites = try sidebar.children(of: .favorites(profile: "default")).map { try Self.tab(sidebar, $0) }
    #expect(favorites.map(\.title) == ["Example Mail", "Example Calendar"])
    #expect(favorites.map(\.customTitle) == [nil, nil])
    #expect(favorites[1].lastActiveAt == nil)
  }

  @Test func reportCountsMatchFixture() throws {
    let (sidebar, report) = try Self.importFixture()
    #expect(report.spaces == 2)
    #expect(report.tabs == 9)
    #expect(report.folders == 1)
    #expect(report.splits == 1)
    #expect(report.warnings.isEmpty)
    #expect(sidebar.nodes.count == 11)
  }

  // MARK: Pinned versus Today

  @Test func containerFileOrderDoesNotDecideSection() throws {
    let (sidebar, _) = try Self.importMutated { global in
      var flat = try #require(global["items"] as? [Any])
      let pinnedIndex = try #require(flat.firstIndex { $0 as? String == Self.alphaPinnedID })
      let unpinnedIndex = try #require(flat.firstIndex { $0 as? String == Self.alphaUnpinnedID })
      let pinnedPair = Array(flat[pinnedIndex...pinnedIndex + 1])
      let unpinnedPair = Array(flat[unpinnedIndex...unpinnedIndex + 1])
      flat.replaceSubrange(unpinnedIndex...unpinnedIndex + 1, with: pinnedPair)
      flat.replaceSubrange(pinnedIndex...pinnedIndex + 1, with: unpinnedPair)
      global["items"] = flat
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    #expect(sidebar.children(of: .pinned(alpha)).count == 2)
    #expect(try Self.tab(sidebar, try #require(sidebar.children(of: .today(alpha)).first)).customTitle
      == "My Renamed Tab")
  }

  @Test func newContainerIDsWinOverLegacyMap() throws {
    let (sidebar, _) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        // Unpinned listed first and pointing at the old pinned root; legacy map left untouched.
        space["newContainerIDs"] = [
          ["unpinned": ["_0": ["shared": [:] as [String: Any]]]], Self.alphaPinnedID,
          ["pinned": [:] as [String: Any]], Self.alphaUnpinnedID,
        ] as [Any]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    let pinned = sidebar.children(of: .pinned(alpha))
    #expect(pinned.count == 1)
    #expect(try Self.tab(sidebar, pinned[0]).customTitle == "My Renamed Tab")
    #expect(sidebar.children(of: .today(alpha)).count == 2)
  }

  @Test func fallsBackToLegacyContainerIDs() throws {
    let (sidebar, _) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        space["newContainerIDs"] = nil
        space["containerIDs"] = ["pinned", Self.alphaUnpinnedID, "unpinned", Self.alphaPinnedID]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    #expect(sidebar.children(of: .pinned(alpha)).count == 1)
    #expect(sidebar.children(of: .today(alpha)).count == 2)
  }

  // MARK: Skips

  @Test func childrenOfSkippedContainerAreReported() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.folderID, in: "items", of: &global) { $0["data"] = ["arcDocument": [:] as [String: Any]] }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    #expect(sidebar.children(of: .pinned(alpha)).count == 1)
    #expect(report.skipped.prefix(3) == [
      SkippedItem(itemID: Self.folderID, reason: .unsupportedKind("arcDocument")),
      SkippedItem(itemID: Self.folderTabIDs[0], reason: .parentSkipped(parentID: Self.folderID)),
      SkippedItem(itemID: Self.folderTabIDs[1], reason: .parentSkipped(parentID: Self.folderID)),
    ])
    #expect(report.folders == 0)
    #expect(report.tabs == 7)
  }

  @Test func undecodableItemIsReportedAndRestImports() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaTodayTabID, in: "items", of: &global) { $0["data"] = 5 }
    }
    let beta = try Self.spaceID(sidebar, titled: "Beta")
    #expect(sidebar.children(of: .today(beta)).isEmpty)
    let failure = try #require(report.skipped.first { $0.itemID == Self.betaTodayTabID })
    guard case .decodeFailed(let reason) = failure.reason else {
      Issue.record("expected decodeFailed, got \(failure.reason)")
      return
    }
    #expect(!reason.isEmpty)
    #expect(report.skipped.filter { $0.itemID == Self.betaTodayTabID }.count == 1)
    #expect(report.tabs == 8)
  }

  @Test func malformedTabPayloadIsReported() throws {
    let (_, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaTodayTabID, in: "items", of: &global) {
        $0["data"] = ["tab": ["savedTitle": "No URL"]]
      }
    }
    let failure = try #require(report.skipped.first { $0.itemID == Self.betaTodayTabID })
    if case .decodeFailed = failure.reason {} else { Issue.record("expected decodeFailed, got \(failure.reason)") }
  }

  @Test func invalidURLIsSkipped() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.favoriteMailID, in: "items", of: &global) { item in
        var data = item["data"] as? [String: Any] ?? [:]
        var tab = data["tab"] as? [String: Any] ?? [:]
        tab["savedURL"] = ""
        data["tab"] = tab
        item["data"] = data
      }
    }
    #expect(sidebar.children(of: .favorites(profile: "default")).count == 1)
    #expect(report.skipped.contains(SkippedItem(itemID: Self.favoriteMailID, reason: .invalidURL)))
  }

  @Test func nonTabInsideSplitIsReported() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.splitID, in: "items", of: &global) { split in
        split["childrenIds"] = [Self.folderID]
      }
      try Self.mutateEntry(Self.alphaPinnedID, in: "items", of: &global) { root in
        root["childrenIds"] = [Self.splitID]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    let split = try #require(sidebar.children(of: .pinned(alpha)).first)
    #expect(sidebar.children(of: .split(split)).isEmpty)
    #expect(report.skipped.contains(SkippedItem(itemID: Self.folderID, reason: .notAllowedHere)))
    #expect(report.skipped.contains(SkippedItem(itemID: Self.folderTabIDs[0], reason: .parentSkipped(parentID: Self.folderID))))
  }

  @Test func folderChainDeeperThanModelCapIsReported() throws {
    let depth = Sidebar.maximumNestingDepth + 1
    let chain = (0..<depth).map { String(format: "A0000000-0000-4000-8000-%012d", 900 + $0) }
    let result = try Self.importMutatedResult { global in
      var items = try #require(global["items"] as? [Any])
      let folderIndex = try #require(stride(from: 0, to: items.count, by: 2).first { items[$0] as? String == Self.folderID })
      let template = try #require(items[folderIndex + 1] as? [String: Any])
      for (index, id) in chain.enumerated() {
        var item = template
        item["id"] = id
        item["parentID"] = index == 0 ? Self.alphaPinnedID : chain[index - 1]
        item["childrenIds"] = index + 1 < chain.count ? [chain[index + 1]] : [String]()
        items += [id, item] as [Any]
      }
      global["items"] = items
      try Self.mutateEntry(Self.alphaPinnedID, in: "items", of: &global) { root in
        root["childrenIds"] = ((root["childrenIds"] as? [String]) ?? []) + [chain[0]]
      }
    }
    #expect(result.report.skipped.contains(SkippedItem(itemID: chain[depth - 1], reason: .notAllowedHere)))
    #expect(result.nodeIDsByArcID[chain[depth - 1]] == nil)
    let deepest = try #require(result.nodeIDsByArcID[chain[depth - 2]])
    #expect(result.sidebar.nodes[deepest]?.kind == .folder(FolderItem(title: "Reading")))
    #expect(result.sidebar.children(of: .folder(deepest)).isEmpty)
  }

  @Test func missingChildIsReported() throws {
    let missing = "A0000000-0000-4000-8000-00000000FFFF"
    let (_, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaUnpinnedID, in: "items", of: &global) { root in
        root["childrenIds"] = [missing]
      }
    }
    #expect(report.skipped.contains(SkippedItem(itemID: missing, reason: .missingItem)))
  }

  @Test func undecodableSpaceIsReported() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaID, in: "spaces", of: &global) { $0["title"] = nil }
    }
    #expect(sidebar.spaceOrder.count == 1)
    let failure = try #require(report.skipped.first { $0.itemID == Self.betaID })
    if case .decodeFailed = failure.reason {} else { Issue.record("expected decodeFailed, got \(failure.reason)") }
  }

  @Test func throwsWithoutGlobalContainer() throws {
    let data = Data(#"{"version": 1, "sidebar": {"containers": []}}"#.utf8)
    #expect(throws: ArcImportError.noGlobalContainer) {
      try ArcSidebarImporter.makeSidebar(from: ArcSidebarFile.decode(data))
    }
  }

  @Test func missingCreatedAtUsesFallbackDate() throws {
    let fallback = Date(timeIntervalSinceReferenceDate: 1234)
    let (sidebar, _) = try Self.importMutated(fallbackCreatedAt: fallback) { global in
      try Self.mutateEntry(Self.favoriteMailID, in: "items", of: &global) { $0["createdAt"] = nil }
    }
    let first = try #require(sidebar.children(of: .favorites(profile: "default")).first)
    #expect(sidebar.nodes[first]?.createdAt == fallback)
  }

  // MARK: Accounting

  /// Every items key is exactly one of: a walked root container, an imported node, or a skipped entry.
  static func expectEveryItemAccounted(_ file: ArcSidebarFile, _ result: ArcImportResult) throws {
    let container = try #require(file.globalContainer)
    let keys = Set(container.items.pairs.map(\.key))
    var roots: Set<String> = Set(container.topAppsContainerIDs.values)
    for space in container.decodedSpaces {
      roots.formUnion(space.newContainerIDs?.values ?? [])
      roots.formUnion(space.containerIDs?.values ?? [])
    }
    roots.formIntersection(keys)
    roots.subtract(result.report.skipped.map(\.itemID))
    let imported = Set(result.nodeIDsByArcID.keys)
    let skippedKeys = result.report.skipped.map(\.itemID).filter(keys.contains)
    #expect(Set(skippedKeys).count == skippedKeys.count, "an item was reported twice")
    let skipped = Set(skippedKeys)
    #expect(roots.isDisjoint(with: imported))
    #expect(roots.isDisjoint(with: skipped))
    #expect(imported.isDisjoint(with: skipped))
    #expect(roots.union(imported).union(skipped) == keys)
    #expect(result.nodeIDsByArcID.count == result.sidebar.nodes.count)
    #expect(Set(result.nodeIDsByArcID.values) == Set(result.sidebar.nodes.keys))
  }

  @Test func fixtureAccountsForEveryItem() throws {
    let file = try ArcSidebarFile.decode(ArcSidebarFileTests.fixture())
    try Self.expectEveryItemAccounted(file, ArcSidebarImporter.makeSidebar(from: file))
  }

  @Test func undecodableSpaceStillAccountsForEveryItem() throws {
    let file = try Self.mutatedFile { global in
      try Self.mutateEntry(Self.betaID, in: "spaces", of: &global) { $0["title"] = nil }
    }
    let result = try ArcSidebarImporter.makeSidebar(from: file)
    try Self.expectEveryItemAccounted(file, result)
    let unreachable = Set(result.report.skipped.filter { $0.reason == .unreachable }.map(\.itemID))
    #expect(unreachable == [
      "A0000000-0000-4000-8000-000000000201", "A0000000-0000-4000-8000-000000000211", Self.easelID,
      "A0000000-0000-4000-8000-000000000202", Self.betaTodayTabID,
    ])
  }

  @Test func mapsArcIDsToNodes() throws {
    let result = try Self.importFixtureResult()
    let node = try #require(result.nodeIDsByArcID[Self.folderID])
    #expect(result.sidebar.nodes[node]?.kind == .folder(FolderItem(title: "Reading")))
    #expect(result.nodeIDsByArcID[Self.alphaPinnedID] == nil)
    #expect(result.nodeIDsByArcID[Self.easelID] == nil)
  }

  // MARK: Roots

  @Test func nonContainerRootIsReported() throws {
    let tabID = "A0000000-0000-4000-8000-000000000131"
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        space["newContainerIDs"] = [
          ["pinned": [:] as [String: Any]], Self.alphaPinnedID,
          ["unpinned": ["_0": ["shared": [:] as [String: Any]]]], tabID,
        ] as [Any]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    #expect(sidebar.children(of: .today(alpha)).isEmpty)
    #expect(report.skipped.contains(SkippedItem(itemID: tabID, reason: .notAllowedHere)))
    #expect(report.skipped.contains(SkippedItem(itemID: Self.alphaUnpinnedID, reason: .unreachable)))
  }

  @Test func rootReachedTwiceIsReported() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.betaID, in: "spaces", of: &global) { space in
        space["newContainerIDs"] = [
          ["pinned": [:] as [String: Any]], Self.alphaPinnedID,
          ["unpinned": ["_0": ["shared": [:] as [String: Any]]]], "A0000000-0000-4000-8000-000000000202",
        ] as [Any]
      }
    }
    let beta = try Self.spaceID(sidebar, titled: "Beta")
    #expect(sidebar.children(of: .pinned(beta)).isEmpty)
    #expect(report.skipped.contains(SkippedItem(itemID: Self.alphaPinnedID, reason: .duplicateReference)))
  }

  @Test func missingNewKeyFallsBackToLegacyPerKey() throws {
    let (sidebar, _) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        space["newContainerIDs"] = [["pinned": [:] as [String: Any]], Self.alphaPinnedID] as [Any]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    #expect(sidebar.children(of: .pinned(alpha)).count == 2)
    #expect(sidebar.children(of: .today(alpha)).count == 1)
  }

  @Test func prefersSharedUnpinnedContainer() throws {
    let (sidebar, _) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        space["newContainerIDs"] = [
          ["pinned": [:] as [String: Any]], Self.alphaPinnedID,
          ["unpinned": ["_0": ["window": ["_0": "W1"]]]], "A0000000-0000-4000-8000-000000000202",
          ["unpinned": ["_0": ["shared": [:] as [String: Any]]]], Self.alphaUnpinnedID,
        ] as [Any]
      }
    }
    let alpha = try Self.spaceID(sidebar, titled: "Alpha")
    let today = sidebar.children(of: .today(alpha))
    #expect(try today.map { try Self.tab(sidebar, $0).customTitle } == ["My Renamed Tab"])
  }

  // MARK: Values

  @Test func horizontalSplitOrientation() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.splitID, in: "items", of: &global) { Self.setOrientation("horizontal", &$0) }
    }
    let split = try #require(sidebar.nodes.values.first { if case .split = $0.kind { true } else { false } })
    #expect(split.kind == .split(SplitItem(orientation: .horizontal, widthFactors: [0.5, 0.5])))
    #expect(report.warnings.isEmpty)
  }

  @Test func unknownSplitOrientationWarns() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.splitID, in: "items", of: &global) { Self.setOrientation("diagonal", &$0) }
    }
    let split = try #require(sidebar.nodes.values.first { if case .split = $0.kind { true } else { false } })
    #expect(split.kind == .split(SplitItem(orientation: .vertical, widthFactors: [0.5, 0.5])))
    #expect(report.warnings == [.unsupportedValue(itemID: Self.splitID, field: "layoutOrientation")])
  }

  static func setOrientation(_ value: String, _ item: inout [String: Any]) {
    var data = item["data"] as? [String: Any] ?? [:]
    var split = data["splitView"] as? [String: Any] ?? [:]
    split["layoutOrientation"] = value
    data["splitView"] = split
    item["data"] = data
  }

  @Test func malformedOverlayColorDropsTheme() throws {
    let (sidebar, report) = try Self.importMutated { global in
      try Self.mutateEntry(Self.alphaID, in: "spaces", of: &global) { space in
        var json = space["customInfo"] as? [String: Any] ?? [:]
        var windowTheme = json["windowTheme"] as? [String: Any] ?? [:]
        var background = windowTheme["background"] as? [String: Any] ?? [:]
        var single = background["single"] as? [String: Any] ?? [:]
        var body = single["_0"] as? [String: Any] ?? [:]
        var style = body["style"] as? [String: Any] ?? [:]
        var color = style["color"] as? [String: Any] ?? [:]
        var color0 = color["_0"] as? [String: Any] ?? [:]
        var gradient = color0["blendedGradient"] as? [String: Any] ?? [:]
        var gradient0 = gradient["_0"] as? [String: Any] ?? [:]
        gradient0["overlayColors"] = [["red": "not a number"]]
        gradient["_0"] = gradient0
        color0["blendedGradient"] = gradient
        color["_0"] = color0
        style["color"] = color
        body["style"] = style
        single["_0"] = body
        background["single"] = single
        windowTheme["background"] = background
        json["windowTheme"] = windowTheme
        space["customInfo"] = json
      }
    }
    let alpha = try #require(sidebar.spaces[try Self.spaceID(sidebar, titled: "Alpha")])
    #expect(alpha.theme == nil)
    #expect(report.warnings == [.unsupportedTheme(spaceID: Self.alphaID)])
  }
}
