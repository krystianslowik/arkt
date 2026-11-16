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

  @Test func savedProtectedCollisionIsUnavailableWithoutDiscardingOtherOverrides() throws {
    let menu = NSMenu()
    let tab = NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
    let sidebar = NSMenuItem(title: "Sidebar", action: NSSelectorFromString("toggleSidebarVisibility:"), keyEquivalent: "s")
    let window = NSMenuItem(title: "New Window", action: NSSelectorFromString("newWindow:"), keyEquivalent: "n")
    [tab, sidebar, window].forEach { menu.addItem($0) }
    let definitions = ShortcutCatalog.definitions(from: menu)
    let suite = "dev.arkt.tests.savedProtected.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = ShortcutActionID("newTab"), other = ShortcutActionID("toggleSidebarVisibility")
    let conflict = ShortcutBinding(key: "n", modifiers: .command)
    let valid = ShortcutBinding(key: "k", modifiers: [.control, .option])
    let writer = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    writer.setBinding(conflict, for: id)
    writer.setBinding(valid, for: other)
    let stored = defaults.data(forKey: "shortcutOverrides")
    let reader = ShortcutEditorModel(catalog: definitions, defaults: defaults)
    ShortcutCatalog.bind(model: reader, to: menu)
    #expect(reader.binding(for: id) == nil)
    #expect(tab.keyEquivalent.isEmpty && window.keyEquivalent == "n")
    #expect(reader.blockedOverrides[id]?.first?.title == "New Window")
    #expect(reader.overrides[id] == .binding(conflict))
    #expect(reader.binding(for: other) == valid && sidebar.keyEquivalent == "k")
    #expect(defaults.data(forKey: "shortcutOverrides") == stored)
    reader.reset(id)
    #expect(reader.blockedOverrides.isEmpty)
    #expect(tab.keyEquivalent == "t" && window.keyEquivalent == "n")
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

/// #828 review: protected owners that are not menu items, and how edited bindings are reserved before the page.
@MainActor
struct ShortcutOwnersAndReservedKeysTests {
  /// A menu holding New Tab only, bound to a model on a throwaway defaults suite.
  private func boundNewTab() throws -> (ShortcutEditorModel, NSMenu, UserDefaults, String) {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t"))
    let suite = "dev.arkt.tests.nonMenu.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let model = ShortcutEditorModel(catalog: ShortcutCatalog.definitions(from: menu), defaults: defaults)
    ShortcutCatalog.bind(model: model, to: menu)
    return (model, menu, defaults, suite)
  }

  /// #828 review: keys owned outside the menu are protected too (Peek's and Little Arkt's Cmd-O, Little Arkt's
  /// Opt-Cmd-O, the tab switcher's Ctrl-` and Ctrl-W, the command bar's Opt-Cmd-Delete), and so are Ctrl-1 ... 9
  /// whatever the Spaces menu lists at that moment: while Settings is the main window it lists none.
  @Test func keysOwnedOutsideTheMenuAndSpaceKeysAreProtected() throws {
    let (model, menu, defaults, suite) = try boundNewTab()
    defer { ShortcutCatalog.unbind(from: menu); defaults.removePersistentDomain(forName: suite) }
    let id = ShortcutActionID("newTab")
    let owned: [(String, NSEvent.ModifierFlags, String)] = [
      ("o", .command, "Open in Space (Peek, Little Arkt)"), ("o", [.command, .option], "Open In (Little Arkt)"),
      ("`", .control, "Tab Switcher"), ("w", .control, "Close Tab in the Tab Switcher"),
      ("\u{7f}", [.command, .option], "Remove Suggestion (command bar)"), ("1", .control, "Space 1"),
      ("9", .control, "Space 9"),
    ]
    for (key, flags, title) in owned {
      let binding = ShortcutBinding(key: key, modifiers: flags)
      #expect(model.protectedOwners?(binding).map(\.title) == [title], "\(title)")
      model.setBinding(binding, for: id)
      #expect(model.blockedOverrides[id]?.first?.title == title, "a saved \(title) key is Unavailable")
    }
    #expect(model.protectedOwners?(ShortcutBinding(key: "0", modifiers: .control)) == [])
  }

  /// A Space item in the menu names the Space; the fixed owner is not listed twice.
  @Test func aListedSpaceItemNamesTheSpaceOnce() throws {
    let (model, menu, defaults, suite) = try boundNewTab()
    defer { ShortcutCatalog.unbind(from: menu); defaults.removePersistentDomain(forName: suite) }
    let space = NSMenuItem(title: "Work", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "1")
    space.keyEquivalentModifierMask = .control
    space.tag = 1
    menu.addItem(space)
    #expect(model.protectedOwners?(ShortcutBinding(key: "1", modifiers: .control)).map(\.title) == ["Work"])
  }

  /// #828 review, the #497 class: an edited binding is reserved before the focused page by the key the layout types
  /// without modifiers, or by its US key code when that is not ASCII, as `ReservedKeys` matches, and Caps Lock
  /// changes nothing.
  @Test func editedBindingsAreReservedOnNonLatinLayoutsAndWithCapsLock() throws {
    let (model, menu, defaults, suite) = try boundNewTab()
    defer { ShortcutCatalog.unbind(from: menu); defaults.removePersistentDomain(forName: suite) }
    model.setBinding(ShortcutBinding(key: "k", modifiers: [.command, .option]), for: ShortcutActionID("newTab"))
    func key(_ characters: String, _ flags: NSEvent.ModifierFlags, code: UInt16 = 40) throws -> NSEvent {
      try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                    windowNumber: 0, context: nil, characters: characters,
                                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
    #expect(ShortcutCatalog.reserves(try key("k", [.command, .option]), in: menu))
    #expect(ShortcutCatalog.reserves(try key("\u{43B}", [.command, .option]), in: menu), "Cyrillic el on the K key")
    #expect(ShortcutCatalog.reserves(try key("K", [.command, .option, .capsLock]), in: menu), "Caps Lock")
    #expect(!ShortcutCatalog.reserves(try key("k", [.command, .option, .shift]), in: menu), "Shift is another key")
    #expect(!ShortcutCatalog.reserves(try key("\u{43B}", [.command], code: 40), in: menu))
    #expect(!ShortcutCatalog.reserves(try key("j", [.command, .option], code: 38), in: menu))
  }

  /// The matching rule alone, with what a Cyrillic layout types: the K key's US code stands in for "k", while a
  /// Latin character on another key never matches by code.
  @Test func aNonLatinKeyMatchesByItsUSKeyCode() {
    let binding = ShortcutBinding(key: "k", modifiers: [.command, .option])
    #expect(ShortcutCatalog.matches(binding, typed: ["\u{43B}"], keyCode: 40, modifiers: [.command, .option]))
    #expect(ShortcutCatalog.matches(binding, typed: ["K"], keyCode: 40, modifiers: [.command, .option, .capsLock]))
    #expect(!ShortcutCatalog.matches(binding, typed: ["\u{43B}"], keyCode: 38, modifiers: [.command, .option]))
    #expect(!ShortcutCatalog.matches(binding, typed: ["j"], keyCode: 40, modifiers: [.command, .option]),
            "a layout typing ASCII matches by character only (AZERTY, Dvorak)")
    #expect(!ShortcutCatalog.matches(binding, typed: ["\u{43B}"], keyCode: 40, modifiers: .command))
  }
}
