import AppKit
import Testing
@testable import ShellUI

@MainActor
struct ShortcutMenuBindingTests {
  @Test func definitionsUseSelectorsAndIgnoreDynamicCommands() {
    let menu = NSMenu()
    let tab = NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
    let sidebar = NSMenuItem(title: "Hide Sidebar", action: NSSelectorFromString("toggleSidebarVisibility:"), keyEquivalent: "s")
    let dynamic = NSMenuItem(title: "Space 1", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "1")
    [tab, sidebar, dynamic].forEach { menu.addItem($0) }
    let definitions = ShortcutCatalog.definitions(from: menu)
    #expect(definitions.map(\.id) == [ShortcutActionID("newTab"), ShortcutActionID("toggleSidebarVisibility")])
    #expect(definitions.map(\.defaultBinding) == [ShortcutBinding(key: "t", modifiers: .command),
                                                  ShortcutBinding(key: "s", modifiers: .command)])
    sidebar.title = "Show Sidebar"
    #expect(ShortcutCatalog.definitions(from: menu).map(\.id) == definitions.map(\.id))
  }

  @Test func replacingModelDetachesPreviousModelAndUpdatesAliases() throws {
    let menu = NSMenu()
    let visible = NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
    let alias = NSMenuItem(title: "Alias", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
    alias.isHidden = true
    menu.addItem(visible)
    menu.addItem(alias)
    let definitions = ShortcutCatalog.definitions(from: menu)
    let id = ShortcutActionID("newTab")
    #expect(definitions.count == 1)
    let suite = "dev.arkt.tests.shortcutBinding.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    let second = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    ShortcutCatalog.bind(model: first, to: menu)
    ShortcutCatalog.bind(model: second, to: menu)
    second.setBinding(ShortcutBinding(key: "k", modifiers: .command), for: id)
    first.setBinding(nil, for: id)
    #expect(visible.keyEquivalent == "k")
    #expect(alias.keyEquivalent == "k")
    second.setBinding(nil, for: id)
    #expect(visible.keyEquivalent.isEmpty)
    #expect(alias.keyEquivalent.isEmpty)
    let reloaded = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    ShortcutCatalog.bind(model: reloaded, to: menu)
    #expect(visible.keyEquivalent.isEmpty)
    reloaded.reset(id)
    #expect(visible.keyEquivalent == "t")
    #expect(alias.keyEquivalent == "t")
    let restored = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    ShortcutCatalog.bind(model: restored, to: menu)
    #expect(visible.keyEquivalent == "t")
    #expect(visible.action == NSSelectorFromString("newTab:"))
    #expect(visible.target == nil)
  }

  @Test(arguments: [false, true])
  func rebuildingDefinitionsAfterBindingPreservesOriginalDefaults(cleared: Bool) throws {
    func menu() -> NSMenu {
      let value = NSMenu()
      value.addItem(NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t"))
      return value
    }
    let original = ShortcutCatalog.definitions(from: menu())
    let bound = menu() // This menu has not had definitions read before its first binding.
    let item = try #require(bound.items.first)
    let id = ShortcutActionID("newTab")
    let suite = "dev.arkt.tests.shortcutDefaults.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = ShortcutEditorModel(catalog: original, defaults: defaults)
    ShortcutCatalog.bind(model: first, to: bound)
    first.setBinding(cleared ? nil : ShortcutBinding(key: "k", modifiers: .command), for: id)
    item.title = "Open New Tab"

    let rebuilt = ShortcutCatalog.definitions(from: bound)
    #expect(rebuilt.first?.defaultBinding == ShortcutBinding(key: "t", modifiers: .command))
    #expect(rebuilt.first?.title == "Open New Tab", "capture defaults without freezing validated titles")
    let reloaded = ShortcutEditorModel(catalog: rebuilt, defaults: defaults)
    ShortcutCatalog.bind(model: reloaded, to: bound)
    reloaded.reset(id)
    #expect(item.keyEquivalent == "t")
    #expect(item.keyEquivalentModifierMask == .command)
  }

}
