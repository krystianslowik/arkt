import AppKit
import ObjectiveC

/// Settings > Shortcuts: the main menu's key equivalents by top-level menu (read-only until the shortcut editor,
/// #119), and the search over them.
@MainActor
public enum ShortcutCatalog {
  // Only selectors audited as unique commands are editable. Dynamic and tagged commands remain read-only.
  private static func actionID(_ item: NSMenuItem) -> ShortcutActionID? {
    guard item.tag == 0, let action = item.action else { return nil }
    switch NSStringFromSelector(action) {
    case "newTab:": return ShortcutActionID("newTab")
    case "toggleSidebarVisibility:": return ShortcutActionID("toggleSidebarVisibility")
    case "copyCurrentURL:": return ShortcutActionID("copyCurrentURL")
    case "copyCurrentURLAsMarkdown:": return ShortcutActionID("copyCurrentURLAsMarkdown")
    case "copyCurrentURLAsQuote:": return ShortcutActionID("copyCurrentURLAsQuote")
    case "pasteURLAsNewTab:": return ShortcutActionID("pasteURLAsNewTab")
    default: return nil
    }
  }

  private static func items(in menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map { items(in: $0) } ?? []) }
  }

  /// The first visible, non-alternate occurrence supplies the original default for each supported action.
  /// Binding changes key equivalents, so capture the original before either reading or applying an override.
  public static func definitions(from menu: NSMenu) -> [ShortcutDefinition] {
    var seen: Set<ShortcutActionID> = []
    return items(in: menu).compactMap { item in
      guard !item.isHidden, !item.isAlternate, item.submenu == nil,
            let id = actionID(item), seen.insert(id).inserted else { return nil }
      return ShortcutDefinition(id: id, title: item.title, defaultBinding: originalBinding(for: item))
    }
  }

  /// Replacing a binding disconnects the previous model before applying the new one.
  public static func bind(model: ShortcutEditorModel, to menu: NSMenu) {
    unbind(from: menu)
    let binding = MenuBinding(model: model, menu: menu)
    objc_setAssociatedObject(menu, &bindingKey, binding, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    binding.start()
  }

  /// Disconnect a menu being replaced, even if another owner still retains it.
  public static func unbind(from menu: NSMenu) {
    if let previous = objc_getAssociatedObject(menu, &bindingKey) as? MenuBinding {
      previous.model.removeObserver(previous.observer)
      previous.model.protectedOwners = nil
      objc_setAssociatedObject(menu, &bindingKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// The bound model is the source of the equivalents routed before a focused page.
  static func reserves(_ event: NSEvent, in menu: NSMenu?) -> Bool {
    guard let menu, let binding = objc_getAssociatedObject(menu, &bindingKey) as? MenuBinding,
          event.type == .keyDown, let key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }
    let candidate = ShortcutBinding(key: key, modifiers: event.modifierFlags)
    return binding.model.catalog.contains { binding.model.binding(for: $0.id) == candidate }
  }

  private static var bindingKey: UInt8 = 0
  private static var originalBindingKey: UInt8 = 0

  @MainActor private final class OriginalBinding {
    let value: ShortcutBinding?
    init(_ value: ShortcutBinding?) { self.value = value }
  }

  private static func originalBinding(for item: NSMenuItem) -> ShortcutBinding? {
    if let original = objc_getAssociatedObject(item, &originalBindingKey) as? OriginalBinding {
      return original.value
    }
    let binding = item.keyEquivalent.isEmpty ? nil : ShortcutBinding(key: item.keyEquivalent,
                                                                    modifiers: item.keyEquivalentModifierMask)
    objc_setAssociatedObject(item, &originalBindingKey, OriginalBinding(binding), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return binding
  }

  @MainActor private final class MenuBinding {
    let model: ShortcutEditorModel
    weak var menu: NSMenu?
    var observer = UUID()
    init(model: ShortcutEditorModel, menu: NSMenu) { self.model = model; self.menu = menu }
    func start() {
      model.protectedOwners = { [weak self, weak menu] candidate in
        guard let self, let menu else { return [] }
        let editable = Set(self.model.catalog.map(\.id))
        return ShortcutCatalog.items(in: menu).compactMap { item in
          guard item.submenu == nil, !item.isSeparatorItem,
                !item.keyEquivalent.isEmpty else { return nil }
          if let id = ShortcutCatalog.actionID(item), editable.contains(id) { return nil }
          let binding = ShortcutBinding(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
          guard binding == candidate else { return nil }
          return ShortcutEditorModel.ProtectedConflict(title: item.title, binding: binding)
        }
      }
      observer = model.observe { [weak self] in self?.apply() }
      apply()
    }
    func apply() {
      guard let menu else { return }
      let supported = Set(model.catalog.map(\.id))
      for item in ShortcutCatalog.items(in: menu) {
        guard let id = ShortcutCatalog.actionID(item), supported.contains(id) else { continue }
        _ = ShortcutCatalog.originalBinding(for: item)
        let binding = model.binding(for: id)
        item.keyEquivalent = binding?.key ?? ""
        item.keyEquivalentModifierMask = binding?.modifiers ?? []
      }
    }
  }

  public struct Entry: Equatable, Sendable {
    public var title: String
    public var actionID: ShortcutActionID? = nil
    /// Keycaps in AppKit's order: Control, Option, Shift, Command, then the key.
    public var keys: [String]
    /// The keys as VoiceOver reads them: "Shift Command D".
    public var spoken: String

    /// The title without a trailing ellipsis.
    public var displayTitle: String {
      for suffix in ["...", "\u{2026}"] where title.hasSuffix(suffix) { return String(title.dropLast(suffix.count)) }
      return title
    }
  }

  public struct Section: Equatable, Sendable {
    public var title: String
    public var entries: [Entry]
  }

  /// Every visible item with a key equivalent, submenus included, grouped by top-level menu; menus without one are
  /// left out.
  public static func sections(from menu: NSMenu, includeEditableWithoutBindings: Bool = false) -> [Section] {
    menu.items.compactMap { top in
      guard let submenu = top.submenu, !top.isHidden else { return nil }
      var entries: [Entry] = []
      collect(submenu, into: &entries, includeEditableWithoutBindings: includeEditableWithoutBindings)
      return entries.isEmpty ? nil : Section(title: top.title, entries: entries)
    }
  }

  private static func collect(_ menu: NSMenu, into entries: inout [Entry], includeEditableWithoutBindings: Bool) {
    for item in menu.items where !item.isHidden && !item.isSeparatorItem && !item.isAlternate {
      if let submenu = item.submenu {
        collect(submenu, into: &entries, includeEditableWithoutBindings: includeEditableWithoutBindings)
      } else if let entry = entry(for: item) {
        entries.append(entry)
      } else if includeEditableWithoutBindings, let id = actionID(item) {
        entries.append(Entry(title: item.title, actionID: id, keys: [], spoken: "None"))
      }
    }
  }

  static func entry(for item: NSMenuItem) -> Entry? {
    let key = item.keyEquivalent
    guard !key.isEmpty else { return nil }
    var modifiers = item.keyEquivalentModifierMask
    if key.count == 1, key.lowercased() != key { modifiers.insert(.shift) }   // "D" is Shift-Command-D
    var keys: [String] = []
    var words: [String] = []
    let order: [(NSEvent.ModifierFlags, String, String)] = [
      (.control, "\u{2303}", "Control"), (.option, "\u{2325}", "Option"), (.shift, "\u{21E7}", "Shift"),
      (.command, "\u{2318}", "Command"),
    ]
    for (flag, glyph, word) in order where modifiers.contains(flag) {
      keys.append(glyph)
      words.append(word)
    }
    let (glyph, word) = name(of: key)
    keys.append(glyph)
    words.append(word)
    return Entry(title: item.title, actionID: actionID(item), keys: keys, spoken: words.joined(separator: " "))
  }

  private static func name(of key: String) -> (glyph: String, word: String) {
    switch key.unicodeScalars.first.map({ Int($0.value) }) {
    case NSRightArrowFunctionKey: ("\u{2192}", "Right Arrow")
    case NSLeftArrowFunctionKey: ("\u{2190}", "Left Arrow")
    case NSUpArrowFunctionKey: ("\u{2191}", "Up Arrow")
    case NSDownArrowFunctionKey: ("\u{2193}", "Down Arrow")
    case 0x20: ("Space", "Space")
    case 0x0D, 0x03: ("\u{21A9}", "Return")
    case 0x09: ("\u{21E5}", "Tab")
    case 0x1B: ("\u{238B}", "Escape")
    case 0x08, 0x7F: ("\u{232B}", "Delete")
    default: (key.uppercased(), key.uppercased())
    }
  }

  /// Entries whose title, spoken keys ("Command-E" and "command e" match "Command E") or keycaps ("⌘E") contain
  /// `query`, case-insensitively; sections without a match are dropped. A blank query keeps everything.
  ///
  /// A query that spells a whole shortcut ("Command-E", "shift command d", "\u{2318}E") matches exactly that
  /// combination, so Command-T does not also find Shift-Command-T.
  public static func filter(_ sections: [Section], query: String) -> [Section] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return sections }
    let combination = Combination(query: trimmed)
    return sections.compactMap { section in
      let entries = section.entries.filter { entry in
        if let combination, combination == Combination(entry: entry) { return true }
        return entry.title.lowercased().contains(trimmed)          // "command bar" still finds Open Command Bar
      }
      return entries.isEmpty ? nil : Section(title: section.title, entries: entries)
    }
  }

  /// Modifiers and key, order-free.
  private struct Combination: Equatable {
    var modifiers: Set<String>
    var key: String

    private static let words: [String: String] = [
      "command": "command", "cmd": "command", "shift": "shift", "option": "option", "opt": "option",
      "alt": "option", "control": "control", "ctrl": "control",
    ]
    private static let glyphs: [Character: String] = [
      "\u{2318}": "command", "\u{21E7}": "shift", "\u{2325}": "option", "\u{2303}": "control",
    ]

    init(entry: Entry) {
      let words = entry.spoken.lowercased().split(separator: " ").map(String.init)
      let modifiers = words.prefix { Self.words[$0] != nil }
      self.modifiers = Set(modifiers.compactMap { Self.words[$0] })
      key = words.dropFirst(modifiers.count).joined(separator: " ")
    }

    /// nil unless `query` is one or more modifiers followed by a key, as words or as glyphs.
    init?(query: String) {
      let words = query.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "+" }).map(String.init)
      let modifiers = words.prefix { Self.words[$0] != nil }
      if !modifiers.isEmpty, modifiers.count < words.count {
        self.modifiers = Set(modifiers.compactMap { Self.words[$0] })
        key = words.dropFirst(modifiers.count).joined(separator: " ")
        return
      }
      let glyphs = query.prefix { Self.glyphs[$0] != nil }
      guard !glyphs.isEmpty, glyphs.count < query.count else { return nil }
      self.modifiers = Set(glyphs.compactMap { Self.glyphs[$0] })
      key = String(query.dropFirst(glyphs.count)).trimmingCharacters(in: .whitespaces)
    }
  }
}
