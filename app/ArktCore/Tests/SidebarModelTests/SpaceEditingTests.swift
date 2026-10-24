import Foundation
import Testing
import SidebarModel

/// Space rename and reorder (#106, BH-038, BH-039).
struct SpaceEditingTests {
  func makeSpaces(_ titles: [String]) -> (Sidebar, [SpaceID]) {
    var sidebar = Sidebar()
    let ids = titles.map { sidebar.addSpace(title: $0) }
    return (sidebar, ids)
  }

  // MARK: - Rename

  @Test func renameChangesOnlyTheTitle() {
    var sidebar = Sidebar()
    let theme = SpaceTheme(baseColors: [RGBA(red: 1, green: 0, blue: 0)], isDark: true)
    let id = sidebar.addSpace(title: "Space 1", profile: "work", theme: theme)

    sidebar.renameSpace(id, to: "Research")

    #expect(sidebar.spaces[id] == Space(id: id, title: "Research", profile: "work", theme: theme))
    #expect(sidebar.spaceOrder == [id])
  }

  @Test func renameOfUnknownSpaceIsANoOp() {
    var (sidebar, _) = makeSpaces(["A"])
    let before = sidebar
    sidebar.renameSpace(SpaceID(), to: "B")
    #expect(sidebar == before)
  }

  // MARK: - Move

  /// The index is measured before the Space is removed, like `move(_:to:at:)`.
  @Test(arguments: [
    (from: 0, to: 2, expected: [1, 0, 2]),
    (from: 0, to: 3, expected: [1, 2, 0]),
    (from: 2, to: 0, expected: [2, 0, 1]),
    (from: 1, to: 1, expected: [0, 1, 2]),
    (from: 1, to: 2, expected: [0, 1, 2]),
    (from: 1, to: 99, expected: [0, 2, 1]),
    (from: 1, to: -5, expected: [1, 0, 2]),
  ])
  func moveUsesTheIndexBeforeRemovalAndClamps(from: Int, to: Int, expected: [Int]) {
    var (sidebar, ids) = makeSpaces(["A", "B", "C"])
    sidebar.moveSpace(ids[from], to: to)
    #expect(sidebar.spaceOrder == expected.map { ids[$0] })
  }

  @Test func moveKeepsTheSpaceAndItsSections() throws {
    var (sidebar, ids) = makeSpaces(["A", "B"])
    let tab = try sidebar.addTab(url: URL(string: "https://example.com")!, title: "T", in: .pinned(ids[0]))
    sidebar.moveSpace(ids[0], to: 2)
    #expect(sidebar.spaceOrder == [ids[1], ids[0]])
    #expect(sidebar.children(of: .pinned(ids[0])) == [tab])
    #expect(sidebar.spaces[ids[0]]?.title == "A")
  }

  @Test func moveOfUnknownSpaceIsANoOp() {
    var (sidebar, _) = makeSpaces(["A", "B"])
    let before = sidebar
    sidebar.moveSpace(SpaceID(), to: 0)
    #expect(sidebar == before)
  }

  // MARK: - Storage

  /// Renames and reorders are part of the stored value, so the autosave persists them.
  @Test func renameAndMoveSurviveAStorageRoundTrip() throws {
    var (sidebar, ids) = makeSpaces(["A", "B", "C"])
    sidebar.renameSpace(ids[1], to: "Renamed")
    sidebar.moveSpace(ids[2], to: 0)

    let decoded = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))

    #expect(decoded.spaceOrder == [ids[2], ids[0], ids[1]])
    #expect(decoded.spaces[ids[1]]?.title == "Renamed")
    #expect(decoded == sidebar)
  }

  // MARK: - Icon and theme

  @Test func setIconAndThemeChangeOnlyThoseFields() {
    var sidebar = Sidebar()
    let theme = SpaceTheme(baseColors: [RGBA(red: 0.1, green: 0.2, blue: 0.3)], isDark: true)
    let id = sidebar.addSpace(title: "Space 1", profile: "work", theme: theme)
    let icon = SpaceIcon(symbol: "star")
    let next = SpaceTheme(baseColors: [RGBA(red: 0, green: 0, blue: 0)], texture: "grain", isDark: true)

    sidebar.setIcon(id, to: icon)
    sidebar.setTheme(id, to: next)

    #expect(sidebar.spaces[id] == Space(id: id, title: "Space 1", profile: "work", theme: next, icon: icon))
    #expect(sidebar.spaceOrder == [id])
  }

  @Test func clearingTheIconAndThemeLeavesTheSpace() {
    var sidebar = Sidebar()
    let id = sidebar.addSpace(title: "A", theme: SpaceTheme(baseColors: [RGBA(red: 1, green: 0, blue: 0)]))
    sidebar.setIcon(id, to: SpaceIcon(symbol: "star"))
    sidebar.setIcon(id, to: nil)
    sidebar.setTheme(id, to: nil)
    #expect(sidebar.spaces[id] == Space(id: id, title: "A"))
  }

  @Test func settingTheSameIconOrThemeIsANoOp() {
    var sidebar = Sidebar()
    let theme = SpaceTheme(baseColors: [RGBA(red: 1, green: 1, blue: 1)])
    let icon = SpaceIcon(symbol: "book")
    let id = sidebar.addSpace(title: "A", theme: theme)
    sidebar.setIcon(id, to: icon)
    let before = sidebar
    sidebar.setIcon(id, to: icon)
    sidebar.setTheme(id, to: theme)
    sidebar.setIcon(SpaceID(), to: icon)
    sidebar.setTheme(SpaceID(), to: theme)
    #expect(sidebar == before)
  }

  /// Icon, theme and order are one stored value, so the autosave persists them together.
  @Test func iconThemeAndOrderSurviveAStorageRoundTrip() throws {
    var (sidebar, ids) = makeSpaces(["A", "B", "C"])
    let theme = SpaceTheme(baseColors: [RGBA(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)], isDark: true)
    sidebar.setIcon(ids[0], to: SpaceIcon(symbol: "star"))
    sidebar.setTheme(ids[2], to: theme)
    sidebar.moveSpace(ids[2], to: 0)

    let decoded = try SidebarStorageFormat.decode(SidebarStorageFormat.encode(sidebar))

    #expect(decoded == sidebar)
    #expect(decoded.spaceOrder == [ids[2], ids[0], ids[1]])
    #expect(decoded.spaces[ids[0]]?.icon == SpaceIcon(symbol: "star"))
    #expect(decoded.spaces[ids[2]]?.theme == theme)
    let object = try #require(try JSONSerialization.jsonObject(with: SidebarStorageFormat.encode(decoded)) as? [String: Any])
    #expect(object["version"] as? Int == SidebarStorageFormat.currentVersion)
  }
}
