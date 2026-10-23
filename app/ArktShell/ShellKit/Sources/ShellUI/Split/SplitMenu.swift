import AppKit

/// The View menu's Split View items (S5). The app's `MainMenu` appends them; they live here so the shell's tests can
/// build and drive them. Targets are nil: AppKit walks the main window's chain to `ShellWindowController`, which
/// enables the pane items only while the current tab is a split pane (`validateSplitMenuItem`).
///
/// Placement and titles: Arc's View menu holds Add Split View (Ctrl-Shift-=), Close this Split Pane (Ctrl-Shift--),
/// Separate Page from Split View and Expand Current Split directly, with no submenu (RT-38, passive read in #78, taken
/// with no split showing). Everything else Arc shows no menu item for, so it sits in a "Split View" submenu with
/// inferred titles [I] PARITY(NEEDS-RUNTIME-CHECK RT-38).
///
/// Key equivalents: the unshifted US character with `[.control, .shift]` ("=", not "+"). AppKit matches it against
/// a layout-translated Ctrl-Shift-= (charactersIgnoringModifiers "+"), checked with Quartz-built key events in
/// `SplitShortcutTests` and `MainMenuKeyEquivalentTests`; no key-down monitor is needed on the US layout. Layouts that
/// put these characters elsewhere (German, French) are a recorded risk, not a gate.
@MainActor
public enum SplitMenu {
  /// The most panes the focus items cover (Ctrl-Shift-1 ... Ctrl-Shift-4, KB-072).
  public static let focusItemCount = SplitLayoutInfo.maximumPanes

  /// The convert item's title for a split that is `orientation` now (BH-120): it offers the other one.
  public static func convertTitle(for orientation: SplitOrientation) -> String {
    switch orientation {
    case .horizontal: "Convert to Vertical Split View"
    case .vertical: "Convert to Horizontal Split View"
    }
  }

  /// The items, in View menu order.
  public static func items() -> [NSMenuItem] {
    [
      item("Add Split View", #selector(ShellWindowController.addSplitPane(_:)), "="),                // KB-070
      item("Close this Split Pane", #selector(ShellWindowController.closeSplitPane(_:)), "-"),       // KB-071
      item("Separate Page from Split View", #selector(ShellWindowController.separatePageFromSplit(_:))),  // KB-075
      item("Expand Current Split", #selector(ShellWindowController.expandCurrentSplit(_:))),         // KB-075, BH-124
      submenu("Split View", inferredItems()),
    ]
  }

  /// [I] Items Arc's menu bar does not show (RT-38).
  private static func inferredItems() -> [NSMenuItem] {
    var items = [
      // BH-120; `validateSplitMenuItem` retitles it for the shown split.
      item(convertTitle(for: .horizontal), #selector(ShellWindowController.convertSplitOrientation(_:))),
      .separator(),
      // BH-117, unbound.
      item("Add Right Split", #selector(ShellWindowController.addSplitRight(_:))),
      item("Add Left Split", #selector(ShellWindowController.addSplitLeft(_:))),
      item("Add Top Split", #selector(ShellWindowController.addSplitTop(_:))),
      item("Add Bottom Split", #selector(ShellWindowController.addSplitBottom(_:))),
      .separator(),
      // KB-073: Ctrl-Shift-] next, Ctrl-Shift-[ previous, as listed; CF-16 is unresolved.
      // PARITY(NEEDS-RUNTIME-CHECK RT-06)
      item("Next Split View Pane", #selector(ShellWindowController.nextSplitPane(_:)), "]"),
      item("Previous Split View Pane", #selector(ShellWindowController.previousSplitPane(_:)), "["),
      .separator(),
    ]
    // KB-072, BH-128 ([S] "Switch to Split View N"): the tag is the zero-based pane index.
    for number in 1...focusItemCount {
      let focus = item("Switch to Split View \(number)", #selector(ShellWindowController.focusSplitPane(_:)),
                       "\(number)")
      focus.tag = number - 1
      items.append(focus)
    }
    return items
  }

  /// A key equivalent here is always Ctrl-Shift and the unshifted character.
  private static func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = key.isEmpty ? [] : [.control, .shift]
    return item
  }

  private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    holder.submenu = menu
    return holder
  }
}
