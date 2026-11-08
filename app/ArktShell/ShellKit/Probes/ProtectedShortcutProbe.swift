import AppKit
import Foundation

/// A headless menu/model check against the actual sources; no app window or browser is created.
@main
struct ProtectedShortcutProbe {
  @MainActor static func main() {
    var checks = 0
    func expect(_ condition: Bool, _ message: String) {
      guard condition else { print("FAIL: \(message)"); exit(1) }
      checks += 1
    }
    for hidden in [false, true] {
      let suite = "dev.arkt.tests.saved-shortcut.\(UUID().uuidString)"
      guard let defaults = UserDefaults(suiteName: suite) else { exit(1) }
      defer { defaults.removePersistentDomain(forName: suite) }
      let menu = NSMenu()
      let tab = NSMenuItem(title: "New Tab", action: NSSelectorFromString("newTab:"), keyEquivalent: "t")
      let sidebar = NSMenuItem(title: "Sidebar", action: NSSelectorFromString("toggleSidebarVisibility:"), keyEquivalent: "s")
      let window = NSMenuItem(title: "New Window", action: NSSelectorFromString("newWindow:"), keyEquivalent: "n")
      window.isHidden = hidden
      [tab, sidebar, window].forEach { menu.addItem($0) }
      let definitions = ShortcutCatalog.definitions(from: menu)
      let id = ShortcutActionID("newTab"), other = ShortcutActionID("toggleSidebarVisibility")
      let conflict = ShortcutBinding(key: "n", modifiers: .command)
      let valid = ShortcutBinding(key: "k", modifiers: [.control, .option])
      let writer = ShortcutEditorModel(catalog: definitions, defaults: defaults)
      writer.setBinding(conflict, for: id)
      writer.setBinding(valid, for: other)
      let stored = defaults.data(forKey: "shortcutOverrides")
      let reader = ShortcutEditorModel(catalog: definitions, defaults: defaults)
      ShortcutCatalog.bind(model: reader, to: menu)
      expect(reader.binding(for: id) == nil, "a saved protected collision is unavailable")
      expect(reader.blockedOverrides[id]?.first?.title == "New Window", "the unavailable request identifies its owner")
      expect(tab.keyEquivalent.isEmpty, "the conflicting custom key is not applied")
      expect(window.keyEquivalent == "n", "the protected owner keeps its key")
      expect(reader.binding(for: other) == valid && sidebar.keyEquivalent == "k", "an unrelated saved override still works")
      expect(reader.overrides[id] == .binding(conflict), "the requested override remains available for repair")
      expect(defaults.data(forKey: "shortcutOverrides") == stored, "binding does not silently rewrite saved choices")
      reader.reset(id)
      expect(reader.blockedOverrides.isEmpty, "reset clears the unavailable state")
      expect(reader.binding(for: id) == ShortcutBinding(key: "t", modifiers: .command), "reset repairs the invalid override")
      expect(tab.keyEquivalent == "t" && window.keyEquivalent == "n", "reset preserves the protected command")
      ShortcutCatalog.unbind(from: menu)
    }
    print("PASS: \(checks) saved-shortcut checks")
  }
}
