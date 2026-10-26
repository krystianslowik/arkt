import AppKit
import Testing
@testable import ShellUI

/// Settings > Shortcuts lists the main menu's key equivalents (read-only until the shortcut editor, #119) and
/// searches them by name or by keys.
@MainActor
struct ShortcutCatalogTests {
  private static func item(_ title: String, _ key: String, _ modifiers: NSEvent.ModifierFlags = [.command],
                           hidden: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.isHidden = hidden
    return item
  }

  private static func menu() -> NSMenu {
    let main = NSMenu()
    func top(_ title: String, _ items: [NSMenuItem]) {
      let menu = NSMenu(title: title)
      items.forEach { menu.addItem($0) }
      let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      holder.submenu = menu
      main.addItem(holder)
    }
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let find = NSMenu(title: "Find")
    find.addItem(item("Find...", "f"))
    let findHolder = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
    findHolder.submenu = find
    let closeAll = item("Close All", "w", [.command, .option])
    closeAll.isAlternate = true
    top("File", [item("New Tab", "t"), item("Reopen Closed Tab", "t", [.command, .shift]), .separator(), closeAll,
                 item("Import Browser Data...", ""),
                 item("Archive Tab", "w")])
    top("Edit", [findHolder, item("Next Tab", "}", hidden: true)])
    top("View", [item("Show Toolbar", "D"), item("Next Space", right, [.command, .option]),
                 item("Reveal Current Tab", " ", [.control])])
    top("Empty", [item("No Key", "")])
    return main
  }

  @Test func listsKeyedItemsByTopLevelMenu() {
    let sections = ShortcutCatalog.sections(from: Self.menu())
    #expect(sections.map(\.title) == ["File", "Edit", "View"], "a menu without keys is left out")
    #expect(sections[0].entries.map(\.title) == ["New Tab", "Reopen Closed Tab", "Archive Tab"])
    #expect(sections[1].entries.map(\.title) == ["Find..."], "submenus are included, hidden aliases are not")
    #expect(!sections[0].entries.contains { $0.title == "Close All" }, "Option alternates are not listed")
  }

  /// An upper-case key equivalent implies Shift, as AppKit draws it; arrows and Space get their names.
  @Test func keycapsAndSpokenForms() throws {
    let view = try #require(ShortcutCatalog.sections(from: Self.menu()).first { $0.title == "View" })
    #expect(view.entries[0].keys == ["\u{21E7}", "\u{2318}", "D"])
    #expect(view.entries[0].spoken == "Shift Command D")
    #expect(view.entries[1].keys == ["\u{2325}", "\u{2318}", "\u{2192}"])
    #expect(view.entries[1].spoken == "Option Command Right Arrow")
    #expect(view.entries[2].keys == ["\u{2303}", "Space"])
    #expect(view.entries[2].spoken == "Control Space")
  }

  @Test func titlesDropTheEllipsis() throws {
    let edit = try #require(ShortcutCatalog.sections(from: Self.menu()).first { $0.title == "Edit" })
    #expect(edit.entries[0].displayTitle == "Find")
  }

  @Test(arguments: [
    ("tab", ["New Tab", "Reopen Closed Tab", "Archive Tab", "Reveal Current Tab"]),
    ("Command-T", ["New Tab"]),
    ("cmd shift t", ["Reopen Closed Tab"]),
    ("Option Command Right Arrow", ["Next Space"]),
    ("TOOLBAR", ["Show Toolbar"]),
    ("Command-W", ["Archive Tab"]),
    ("shift command d", ["Show Toolbar"]),
    ("\u{2318}T", ["New Tab"]),
    ("  ", ["New Tab", "Reopen Closed Tab", "Archive Tab", "Find...", "Show Toolbar", "Next Space",
            "Reveal Current Tab"]),
    ("zzz", []),
  ])
  func search(query: String, expected: [String]) {
    let all = ShortcutCatalog.sections(from: Self.menu())
    let found = ShortcutCatalog.filter(all, query: query).flatMap(\.entries).map(\.title)
    #expect(found == expected)
  }

  /// Sections with no match disappear.
  @Test func filteredSectionsDropEmptyOnes() {
    let found = ShortcutCatalog.filter(ShortcutCatalog.sections(from: Self.menu()), query: "space")
    #expect(found.map(\.title) == ["View"])
    #expect(found.first?.entries.map(\.title) == ["Next Space"], "names match titles; keys match whole shortcuts")
  }
}

/// Settings > Spaces and Profiles reads the Spaces from the sidebar: name, theme gradient and counts.
@MainActor
struct SettingsSpaceSummaryTests {
  @Test func summarizesEachSpaceInOrder() throws {
    let sidebar = StubSidebar()
    let theme = SpaceThemeInfo(baseColors: [.srgb(hex: 0xB9D5F5), .srgb(hex: 0x8FB3E8)], isDark: false)
    let work = sidebar.addSpace(title: "Work", profile: "work", theme: theme)
    let home = sidebar.addSpace(title: "Home")
    for n in 0..<2 {
      try sidebar.addTab(url: URL(string: "https://p\(n).example")!, title: "P", in: .pinned(work), at: nil)
    }
    try sidebar.addTab(url: URL(string: "https://t.example")!, title: "T", in: .today(work), at: nil)

    let list = SettingsSpaceSummary.list(from: sidebar)
    #expect(list.map(\.title) == ["Work", "Home"])
    #expect(list[0].id == work)
    #expect(list[0].gradient == theme.baseColors)
    #expect(list[0].detail == "2 pinned, 1 in Today")
    #expect(list[0].profile == "work")
    #expect(list[1].id == home)
    #expect(list[1].detail == "0 pinned, 0 in Today")
  }

  @Test func profilesListWhichSpacesUseThem() {
    let sidebar = StubSidebar()
    let theme = SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    sidebar.addSpace(title: "Personal", theme: theme)
    sidebar.addSpace(title: "Work", profile: "work", theme: theme)
    sidebar.addSpace(title: "Reading", theme: theme)
    let profiles = SettingsSpaceSummary.profiles(in: SettingsSpaceSummary.list(from: sidebar))
    #expect(profiles.map(\.name) == ["Default", "Work"])
    #expect(profiles.map(\.detail) == ["Used by Personal and Reading", "Used by Work"])
  }
}
