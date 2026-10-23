import Foundation
import Testing
import ArcImport

struct ArcSidebarFileTests {
  static func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(
      forResource: "StorableSidebar-synthetic", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  static func container() throws -> ArcContainer {
    try #require(try ArcSidebarFile.decode(fixture()).globalContainer)
  }

  static let alphaID = "A0000000-0000-4000-8000-0000000000A1"
  static let alphaPinnedID = "A0000000-0000-4000-8000-000000000101"
  static let alphaUnpinnedID = "A0000000-0000-4000-8000-000000000102"
  static let topAppsID = "A0000000-0000-4000-8000-000000000301"

  @Test func decodesSpacesItemsAndFavorites() throws {
    let file = try ArcSidebarFile.decode(Self.fixture())
    #expect(file.version == 1)
    let container = try #require(file.globalContainer)
    #expect(container.decodedSpaces.map(\.title) == ["Alpha", "Beta"])
    #expect(container.items.pairs.count == 17)
    #expect(container.topAppsContainerIDs.pairs.count == 1)
  }

  @Test func classifiesItemData() throws {
    let container = try Self.container()
    let kinds = Set(container.decodedItems.map(\.data.caseName))
    #expect(kinds == ["tab", "list", "itemContainer", "splitView", "easel"])
  }

  @Test func keysMatchIDs() throws {
    let container = try Self.container()
    #expect(container.items.pairs.allSatisfy { $0.key == $0.value.value?.id })
    #expect(container.spaces.pairs.allSatisfy { $0.key == $0.value.value?.id })
    #expect(container.itemFailures.isEmpty)
    #expect(container.spaceFailures.isEmpty)
  }

  @Test func topAppsKeyIsProfileObject() throws {
    let container = try Self.container()
    let pair = try #require(container.topAppsContainerIDs.pairs.first)
    #expect(pair.key == .object(["default": .bool(true)]))
    #expect(pair.value == Self.topAppsID)
    #expect(container.topAppsContainerIDs[.object(["default": .bool(true)])] == Self.topAppsID)
  }

  @Test func decodesSpaceContainerMaps() throws {
    let space = try #require(try Self.container().space(Self.alphaID))
    #expect(space.profile == .object(["default": .bool(true)]))
    let newIDs = try #require(space.newContainerIDs)
    #expect(newIDs.pairs.map(\.key.caseName) == ["pinned", "unpinned"])
    #expect(newIDs.pairs.map(\.value) == [Self.alphaPinnedID, Self.alphaUnpinnedID])
    let unpinnedKey = newIDs.pairs[1].key
    #expect(try unpinnedKey.payload(TaggedEnum.self).caseName == "shared")
    let legacy = try #require(space.containerIDs)
    #expect(legacy["pinned"] == Self.alphaPinnedID)
    #expect(legacy["unpinned"] == Self.alphaUnpinnedID)
    guard case .object(let info) = try #require(space.customInfo) else {
      Issue.record("customInfo is not an object")
      return
    }
    #expect(info["iconType"] == .object(["icon": .string("star")]))
  }

  @Test func decodesItemFields() throws {
    let container = try Self.container()
    let root = try #require(container.item(Self.alphaPinnedID))
    #expect(root.parentID == nil)
    #expect(root.title == nil)
    #expect(root.childrenIds.count == 2)
    let folder = try #require(container.item(root.childrenIds[0]))
    #expect(folder.parentID == Self.alphaPinnedID)
    #expect(folder.title == "Reading")
    #expect(folder.data.caseName == "list")
    #expect(try #require(folder.createdAt) > Date(timeIntervalSinceReferenceDate: 7.8e8))
  }

  @Test func exposesTabData() throws {
    let container = try Self.container()
    let unpinned = try #require(container.item(Self.alphaUnpinnedID))
    let tabItem = try #require(container.item(unpinned.childrenIds[0]))
    #expect(tabItem.title == "My Renamed Tab")
    let tab = try #require(try tabItem.tabData)
    #expect(tab.savedURL == "https://example.com/news")
    #expect(tab.savedTitle == "Example News")
    #expect(tab.timeLastActiveAt == Date(timeIntervalSinceReferenceDate: 790_000_000.25))
    #expect(try unpinned.tabData == nil)
  }

  @Test func tabWithoutLastActiveDate() throws {
    let container = try Self.container()
    let favorites = try #require(container.item(Self.topAppsID))
    let second = try #require(container.item(favorites.childrenIds[1]))
    let tab = try #require(try second.tabData)
    #expect(tab.savedURL == "https://example.com/calendar")
    #expect(tab.timeLastActiveAt == nil)
  }

  @Test func exposesSplitViewData() throws {
    let container = try Self.container()
    let root = try #require(container.item(Self.alphaPinnedID))
    let split = try #require(container.item(root.childrenIds[1]))
    let data = try #require(try split.splitViewData)
    #expect(data.layoutOrientation == "vertical")
    #expect(data.itemWidthFactors == [0.5, 0.5])
    #expect(split.childrenIds.count == 2)
    #expect(try root.splitViewData == nil)
  }

  @Test func exposesContainerType() throws {
    let container = try Self.container()
    let pinned = try #require(container.item(Self.alphaPinnedID))
    #expect(try pinned.containerType == .spaceItems(spaceID: Self.alphaID))
    let top = try #require(container.item(Self.topAppsID))
    #expect(try top.containerType == .topApps(profile: .object(["default": .bool(true)])))
    let tab = try #require(container.item(top.childrenIds[0]))
    #expect(try tab.containerType == nil)
  }

  @Test func malformedTabPayloadThrows() throws {
    let json = #"""
    {"id": "X", "parentID": null, "childrenIds": [], "title": null, "createdAt": 780000000,
     "data": {"tab": {"savedTitle": "no url"}}}
    """#.data(using: .utf8)!
    let item = try JSONDecoder().decode(ArcItem.self, from: json)
    #expect(throws: DecodingError.self) { try item.tabData }
  }

  @Test func missingGlobalContainerIsNil() throws {
    let json = #"{"version": 1, "sidebar": {"containers": []}}"#.data(using: .utf8)!
    #expect(try ArcSidebarFile.decode(json).globalContainer == nil)
  }

  @Test func oneBadItemDoesNotFailTheFile() throws {
    let json = #"""
    {"version": 1, "sidebar": {"containers": [{"global": {}}, {
      "spaces": [
        "S1", {"id": "S1", "title": "Good", "profile": {"default": true}},
        "S2", {"id": "S2", "profile": {"default": true}}
      ],
      "items": [
        "I1", {"id": "I1", "parentID": null, "title": null, "createdAt": 780000000,
               "data": {"tab": {"savedURL": "https://example.com/ok"}}},
        "I2", {"id": "I2", "parentID": null, "childrenIds": [], "title": null,
               "data": {"tab": {"savedURL": "https://example.com/no-date"}}},
        "I3", {"id": "I3", "parentID": null, "childrenIds": [], "createdAt": 780000000,
               "data": "garbage"},
        "I4", {"id": "I4", "childrenIds": ["I1"], "createdAt": 780000000,
               "data": {"list": {}}}
      ]
    }]}}
    """#.data(using: .utf8)!
    let container = try #require(try ArcSidebarFile.decode(json).globalContainer)
    #expect(container.decodedSpaces.map(\.id) == ["S1"])
    #expect(container.spaceFailures.map(\.id) == ["S2"])
    #expect(container.decodedItems.map(\.id) == ["I1", "I2", "I4"])
    #expect(container.itemFailures.map(\.id) == ["I3"])
    #expect(container.itemFailures.allSatisfy { !$0.reason.isEmpty })
    #expect(container.topAppsContainerIDs.pairs.isEmpty)
    let first = try #require(container.item("I1"))
    #expect(first.childrenIds == [])
    #expect(first.createdAt == Date(timeIntervalSinceReferenceDate: 780_000_000))
    #expect(try #require(container.item("I2")).createdAt == nil)
    #expect(container.item("I3") == nil)
  }

  /// Shape contract: the raw JSON paths the importer depends on, checked on the
  /// fixture without going through the decoder. Sidebar item case bodies have
  /// no `_0`; nested enums (containerType, newContainerIDs keys) do.
  @Test func fixtureFollowsShapeContract() throws {
    let root = try #require(try JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
    let sidebar = try #require(root["sidebar"] as? [String: Any])
    let containers = try #require(sidebar["containers"] as? [Any])
    let global = try #require(containers[1] as? [String: Any])
    let flat = try #require(global["items"] as? [Any])
    let items = flat.enumerated().filter { $0.offset % 2 == 1 }.compactMap { $0.element as? [String: Any] }
    #expect(items.count == 17)
    let datas = items.compactMap { $0["data"] as? [String: Any] }
    #expect(datas.count == 17)

    let tabs = datas.compactMap { $0["tab"] as? [String: Any] }
    #expect(!tabs.isEmpty)
    #expect(tabs.allSatisfy { $0["savedURL"] is String && $0["_0"] == nil })

    let containerTypes = datas.compactMap {
      ($0["itemContainer"] as? [String: Any])?["containerType"] as? [String: Any]
    }
    #expect(containerTypes.count == 5)
    let spaceIDs = containerTypes.compactMap { ($0["spaceItems"] as? [String: Any])?["_0"] as? String }
    #expect(spaceIDs.count == 4)
    let profiles = containerTypes.compactMap { ($0["topApps"] as? [String: Any])?["_0"] as? [String: Any] }
    #expect(profiles.count == 1)

    let splits = datas.compactMap { $0["splitView"] as? [String: Any] }
    #expect(splits.count == 1)
    #expect(splits.allSatisfy { $0["layoutOrientation"] is String && $0["itemWidthFactors"] is [Any] })
  }
}
