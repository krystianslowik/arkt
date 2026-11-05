import AppKit

/// Little Arkt's rows in the Dock menu and the Window menu (#356, BH-139, GS-041; docs/design/little-arkt.md, Several
/// windows). The Dock menu lists the windows by page title, then Hide All (Show All while every one is hidden) and
/// Close; the app adds New Window and New Little Arkt Window below. The Window menu lists them under their own heading,
/// above Bring All to Front; AppKit's own window list leaves them out (`isExcludedFromWindowsMenu`).
///
/// Owned by the window set; menu items hold their target weakly, so the items target this object, never a window.
@MainActor
public final class LittleArktMenus: NSObject {
  /// Tags the Window menu rows this object owns, so an update replaces them.
  static let sectionTag = 0x4C41_0356

  private let windows: @MainActor () -> [LittleArktWindowController]

  init(windows: @escaping @MainActor () -> [LittleArktWindowController]) {
    self.windows = windows
  }

  /// True while there are windows and none is on screen (Hide All ran, or each was hidden).
  public var allHidden: Bool {
    let open = windows()
    return !open.isEmpty && open.allSatisfy { !$0.window.isVisible }
  }

  // MARK: Dock menu

  /// The page titles, then Hide All or Show All and Close Little Arkt Windows; empty without windows.
  public func dockItems() -> [NSMenuItem] {
    let open = windows()
    guard !open.isEmpty else { return [] }
    var items = open.map { row(for: $0, marksKey: false) }
    items.append(.separator())
    items.append(allHidden ? item(LittleArktCopy.showAll, #selector(showAllWindows(_:)))
                           : item(LittleArktCopy.hideAll, #selector(hideAllWindows(_:))))
    items.append(item(LittleArktCopy.closeAll, #selector(closeAllWindows(_:))))
    return items
  }

  // MARK: Window menu

  /// Replaces the Little Arkt section of `menu`: the "Little Arkt" heading, one row per window (the key one checked)
  /// and a separator, just above Bring All to Front (else at the end). Nothing while no window is open.
  public func updateWindowMenu(_ menu: NSMenu) {
    for item in menu.items where item.tag == Self.sectionTag { menu.removeItem(item) }
    let open = windows()
    guard !open.isEmpty else { return }
    let heading = NSMenuItem.sectionHeader(title: LittleArktCopy.windowMenuHeading)
    let separator = NSMenuItem.separator()
    let section = [heading] + open.map { row(for: $0, marksKey: true) } + [separator]
    var index = menu.items.firstIndex { $0.action == #selector(NSApplication.arrangeInFront(_:)) } ?? menu.numberOfItems
    for item in section {
      item.tag = Self.sectionTag
      menu.insertItem(item, at: index)
      index += 1
    }
  }

  // MARK: Actions

  @objc func showWindow(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? ObjectIdentifier,
          let little = windows().first(where: { ObjectIdentifier($0) == id }) else { return }
    little.bringForward()
  }

  /// Every window leaves the screen and stays open; Show All, a row, or a new Little Arkt window brings them back.
  @objc func hideAllWindows(_ sender: Any?) {
    for little in windows() { little.window.orderOut(nil) }
  }

  /// Every window comes back where it was, the last one opened in front and key.
  @objc func showAllWindows(_ sender: Any?) {
    let open = windows()
    for little in open.dropLast() { little.window.orderFront(nil) }
    open.last?.bringForward()
  }

  @objc func closeAllWindows(_ sender: Any?) {
    for little in windows() { little.closeFromMenu() }
  }

  // MARK: Items

  private func row(for little: LittleArktWindowController, marksKey: Bool) -> NSMenuItem {
    let row = item(little.menuTitle, #selector(showWindow(_:)))
    row.representedObject = ObjectIdentifier(little)
    if marksKey, little.window.isKeyWindow { row.state = .on }
    return row
  }

  private func item(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }
}
