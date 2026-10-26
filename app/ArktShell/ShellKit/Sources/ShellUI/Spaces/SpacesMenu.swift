import AppKit

/// The Spaces menu (#387). The app's `MainMenu` hands it the fixed items; between them it lists the main window's
/// Spaces, in sidebar order, one item each: the Space's title, Ctrl-1 ... Ctrl-9 on the first nine (KB-035, BH-041),
/// the zero-based index as tag (`ShellWindowController.goToSpace(_:)`), nil target.
///
/// The list follows adds, renames, moves and removals as they happen: a `ShellWindowController` posts
/// `listDidChangeNotification` when its Spaces change, and a window becoming main may bring other Spaces, so the keys
/// match the current Spaces without the menu being opened (AppKit does not ask the delegate before it matches a key
/// equivalent). `menuNeedsUpdate(_:)` checks once more before the menu shows. A rebuild only happens when the list
/// changed.
@MainActor
public final class SpacesMenu: NSMenu, NSMenuDelegate {
  public static let menuTitle = "Spaces"
  /// Spaces with a key equivalent: Ctrl-1 ... Ctrl-9.
  public static let keyedCount = 9
  /// Posted by a `ShellWindowController` whose Spaces changed (added, removed, renamed, moved).
  public static let listDidChangeNotification = Notification.Name("ArktSpacesMenuListDidChange")

  /// One listed Space.
  public struct Entry: Equatable, Sendable {
    public var id: SpaceID
    public var title: String

    public init(id: SpaceID, title: String) {
      self.id = id
      self.title = title
    }
  }

  /// The Spaces to list. Default: those of the main window's `ShellWindowController`, the window the items' nil
  /// target reaches; none while another window (the Archive, Little Arkt) is main.
  public var entries: @MainActor () -> [Entry] = {
    (NSApp.mainWindow?.windowController as? ShellWindowController)?.spaceMenuEntries ?? []
  }

  private let leadingCount: Int
  private var listed: [Entry]?
  private var listItems: [NSMenuItem] = []

  /// `leading` items come first, `trailing` last; the Space list goes between them behind a separator.
  public init(leading: [NSMenuItem], trailing: [NSMenuItem]) {
    leadingCount = leading.count
    super.init(title: Self.menuTitle)
    (leading + trailing).forEach { addItem($0) }
    delegate = self
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(listMayHaveChanged(_:)), name: Self.listDidChangeNotification,
                       object: nil)
    center.addObserver(self, selector: #selector(listMayHaveChanged(_:)), name: NSWindow.didBecomeMainNotification,
                       object: nil)
    refreshList()                        // a window may be main already (the Engine build installs the menu late)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public func menuNeedsUpdate(_ menu: NSMenu) { refreshList() }

  @objc private func listMayHaveChanged(_ notification: Notification) { refreshList() }

  /// Rebuilds the Space items when the listed Spaces changed.
  public func refreshList() {
    let next = entries()
    guard next != listed else { return }
    listed = next
    listItems.forEach { removeItem($0) }
    listItems = next.isEmpty ? [] : [.separator()] + next.enumerated().map(Self.item)
    for (offset, item) in listItems.enumerated() { insertItem(item, at: leadingCount + offset) }
  }

  private static func item(index: Int, entry: Entry) -> NSMenuItem {
    let title = entry.title.isEmpty ? "Space \(index + 1)" : entry.title
    let keyed = index < keyedCount
    let item = NSMenuItem(title: title, action: #selector(ShellWindowController.goToSpace(_:)),
                          keyEquivalent: keyed ? "\(index + 1)" : "")
    item.keyEquivalentModifierMask = keyed ? [.control] : []
    item.tag = index                     // not top level, and far below Chromium's `IDC_` values
    return item
  }
}
