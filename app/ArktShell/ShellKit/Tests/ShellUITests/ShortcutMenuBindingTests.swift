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

  @Test func readOnlyMenuOwnersCannotBeStolen() throws {
    let menu = NSMenu()
    let tab = NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
    let window = NSMenuItem(title: "New Window", action: NSSelectorFromString("newWindow:"), keyEquivalent: "n")
    let hidden = NSMenuItem(title: "Hidden Alias", action: NSSelectorFromString("dynamic:"), keyEquivalent: "y")
    hidden.isHidden = true
    [tab, window, hidden].forEach { menu.addItem($0) }
    let suite = "dev.arkt.tests.protected.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    ShortcutCatalog.bind(model: model, to: menu)
    let id = ShortcutActionID("newTab")
    for (key, title) in [("n", "New Window"), ("y", "Hidden Alias")] {
      model.beginRecording(id)
      let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
        isARepeat: false, keyCode: 0))
      model.record(event: event)
      #expect(model.protectedConflicts.first?.title == title)
      #expect(model.pendingShortcut == ShortcutBinding(key: key, modifiers: .command))
      model.useRecordedShortcut()
      #expect(model.binding(for: id) == ShortcutBinding(key: "t", modifiers: .command))
      #expect(window.keyEquivalent == "n")
      model.keepExisting()
    }
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

@MainActor
struct CopyLinkCatalogTests {
  @Test func taggedAndDynamicRowsStayReadOnlyButListed() {
    let root = NSMenu()
    let holder = NSMenuItem(title: "Commands", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Commands")
    holder.submenu = menu
    root.addItem(holder)
    for (title, action, key, tag) in [("Find", "commandDispatch:", "f", 1),
                                      ("Reload", "commandDispatch:", "r", 2),
                                      ("Space 1", "goToSpace:", "1", 0),
                                      ("Sidebar 1", "goToSidebarItem:", "1", 1),
                                      ("Pane 1", "focusSplitPane:", "1", 0)] {
      let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
      item.tag = tag
      menu.addItem(item)
    }
    #expect(ShortcutCatalog.definitions(from: root).isEmpty)
    #expect(ShortcutCatalog.sections(from: root).flatMap(\.entries).map(\.title) ==
            ["Find", "Reload", "Space 1", "Sidebar 1", "Pane 1"])
  }

  @Test func copyAndPasteCommandsKeepDistinctIdentitiesAndPristineDefaults() throws {
    let menu = NSMenu()
    let selectors = ["copyCurrentURL:", "copyCurrentURLAsMarkdown:", "copyCurrentURLAsQuote:", "pasteURLAsNewTab:"]
    let ids = selectors.map { ShortcutActionID(String($0.dropLast())) }
    let keys = ["c", "c", "c", "v"]
    let flags: [NSEvent.ModifierFlags] = [[.command, .shift], [.command, .shift, .option],
                                          [.command, .shift, .control], [.command, .option]]
    let items = selectors.indices.map { index in
      let item = NSMenuItem(title: "Command \(index)", action: NSSelectorFromString(selectors[index]),
                            keyEquivalent: keys[index])
      item.keyEquivalentModifierMask = flags[index]
      return item
    }
    items.forEach { menu.addItem($0) }
    let definitions = ShortcutCatalog.definitions(from: menu)
    #expect(definitions.map(\.id) == ids)
    #expect(Set(definitions.map(\.id)).count == 4)
    #expect(definitions.map(\.defaultBinding) == selectors.indices.map { ShortcutBinding(key: keys[$0], modifiers: flags[$0]) })
    guard definitions.count == 4 else { return }
    let suite = "dev.arkt.tests.copyLinkCatalog.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    ShortcutCatalog.bind(model: model, to: menu)
    model.setBinding(ShortcutBinding(key: "e", modifiers: .command), for: ids[0])
    model.setBinding(nil, for: ids[1])
    items[0].title = "Validated title"
    let rebuilt = ShortcutCatalog.definitions(from: menu)
    #expect(rebuilt.map(\.defaultBinding) == definitions.map(\.defaultBinding))
    #expect(rebuilt[0].title == "Validated title")
    let reloaded = ShortcutEditorModel(catalog: rebuilt, defaults: defaults)
    ShortcutCatalog.bind(model: reloaded, to: menu)
    #expect(items[0].keyEquivalent == "e")
    #expect(items[1].keyEquivalent.isEmpty)
    for id in ids { reloaded.reset(id) }
    for index in items.indices {
      #expect(items[index].keyEquivalent == keys[index])
      #expect(items[index].keyEquivalentModifierMask == flags[index])
      #expect(items[index].action == NSSelectorFromString(selectors[index]))
      #expect(items[index].target == nil)
    }
  }
}
