import AppKit
import EngineAPI

/// The bottom bar's Clear menu (BH-033) and the two Clear actions behind it (#110): Clear Today Tabs archives every
/// Today row of the current Space (BH-075, KB-019), Clear unselected Today tabs only the rows with nothing selected
/// (BH-078). A row whose page plays media stays in both (BH-076), and so does a folder or split holding one: its
/// page is the one that must not be closed.
extension ShellWindowController {
  /// The identifier that marks the bottom bar's menu in `menuNeedsUpdate(_:)`; the menu is otherwise an ordinary
  /// context menu on the archive button.
  static let todayBarMenuIdentifier = NSUserInterfaceItemIdentifier("dev.arkt.todayBarMenu")

  /// Puts the Clear items on the bottom bar's archive button [I]: the spec gives the strings (BH-033) but not the
  /// control, and the archive button is the bottom bar's only item without an action. The second item needs a
  /// selection of Today rows, so the menu disables it until there is one.
  func wireTodayBarMenu() {
    let menu = NSMenu(title: "")
    menu.identifier = Self.todayBarMenuIdentifier
    menu.autoenablesItems = false
    menu.delegate = self
    let clear = NSMenuItem(title: "Clear Today Tabs", action: #selector(clearTodayTabs(_:)), keyEquivalent: "k")
    clear.keyEquivalentModifierMask = [.command, .shift]
    clear.target = self
    let unselected = NSMenuItem(title: "Clear unselected Today tabs",
                                action: #selector(clearUnselectedTodayTabs(_:)), keyEquivalent: "")
    unselected.target = self
    menu.addItem(clear)
    menu.addItem(unselected)
    sidebarController.view.archiveButton.menu = menu
    updateTodayBarMenu(menu)
  }

  /// File > Clear Today Tabs (Shift-Cmd-K, KB-019, BH-075): the Today rows of the current Space go to the Archive,
  /// except the ones a window shows (#429).
  @objc public func clearTodayTabs(_ sender: Any?) {
    guard let space = currentSpace else { return }
    clearToday(space)
  }

  /// The bottom bar's Clear unselected Today tabs (BH-078): the Today rows with nothing selected go, the selected
  /// ones stay; with no selected Today row the action does nothing.
  @objc public func clearUnselectedTodayTabs(_ sender: Any?) {
    guard let space = currentSpace else { return }
    clearUnselectedToday(space)
  }

  /// Clears the unselected Today rows of `space` (BH-078), as one undo unit like Clear Today Tabs.
  func clearUnselectedToday(_ space: SpaceID) {
    let selected = Set(sidebarController.selectedNodes)
    guard Self.holdsSelection(sidebar.children(of: .today(space)), selected, tabs: { self.tabs(in: $0) }) else {
      return
    }
    let rows = todayRows(of: space, scope: .unselected)
    guard !rows.isEmpty else { return }
    archiveToday(rows)
  }

  /// True when a Clear would take a row: the menu bar item's enabled rule.
  var canClearToday: Bool {
    guard let space = currentSpace else { return false }
    return !todayRows(of: space, scope: .all).isEmpty
  }

  /// True when the menu's second item would clear something: a Today row is selected, and at least one row would go
  /// (unselected and not playing media).
  var canClearUnselectedToday: Bool {
    guard let space = currentSpace else { return false }
    return !todayRows(of: space, scope: .unselected).isEmpty
      && Self.holdsSelection(sidebar.children(of: .today(space)), Set(sidebarController.selectedNodes),
                             tabs: { self.tabs(in: $0) })
  }

  /// The rows a Clear takes, in Today order (BH-075, BH-076, BH-078, #429). A row showing in this window (the current
  /// tab, both panes of a shown Split View) or in another window stays, whatever the scope. A row counts as selected when it or any tab
  /// inside it is (a selected tab in a folder keeps the folder), and as playing when any of its pages plays media.
  /// The row holding the current tab always reads as selected (as `SidebarSelection` seeds it), so Clear unselected
  /// never archives the shown page, nor tears its Split View apart, even after a Cmd-click deselected it.
  func todayRows(of space: SpaceID, scope: TodayClearPolicy.Scope) -> [NodeID] {
    let selected = Set(sidebarController.selectedNodes)
    let current = currentNode
    let shown = visibleNodes.union(current.map { [$0] } ?? []).union(otherWindowsVisibleNodes?() ?? [])
    return TodayClearPolicy.rows(
      sidebar.children(of: .today(space)), scope: scope,
      isSelected: { row in
        Self.holdsSelection([row], selected, tabs: { self.tabs(in: $0) })
          || current.map(self.tabs(in: row).contains) == true
      },
      playsMedia: { row in self.tabs(in: row).contains { self.pagePlaysMedia($0) } },
      isShown: { row in self.tabs(in: row).contains(where: shown.contains) })
  }

  /// Whether a page plays media now (BH-076): the engine's audible state, which Chromium also reports for a muted
  /// page that plays. A page that is not loaded cannot play, so a row without one is never exempt.
  func pagePlaysMedia(_ node: NodeID) -> Bool {
    guard let tab = tabsByNode[node], let snapshot = engine.snapshot(of: tab) else { return false }
    return snapshot.isAudible
  }

  /// Whether `rows` hold any of `selected`: a row itself, or a tab inside it (`tabs` answers for a row).
  static func holdsSelection(_ rows: [NodeID], _ selected: Set<NodeID>,
                             tabs: (NodeID) -> [NodeID]) -> Bool {
    guard !selected.isEmpty else { return false }
    return rows.contains { row in selected.contains(row) || tabs(row).contains(where: selected.contains) }
  }

  /// Enables the two items for the current Space and its selection.
  func updateTodayBarMenu(_ menu: NSMenu) {
    menu.item(at: 0)?.isEnabled = canClearToday
    menu.item(at: 1)?.isEnabled = canClearUnselectedToday
  }
}

extension ShellWindowController: NSMenuDelegate {
  public func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu.identifier == Self.todayBarMenuIdentifier else { return }
    updateTodayBarMenu(menu)
  }
}
