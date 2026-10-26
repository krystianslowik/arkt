import AppKit
import EngineAPI

/// A pinned tab's relation to its pinned URL (BH-057): the tab is loaded and shows another page
/// (`.navigated`, with the page's current URL), or it shows its pinned URL (also when unloaded).
enum PinnedTabState: Equatable, Sendable {
  case notPinned
  case atPinnedURL
  case navigated(current: URL)
}

/// Pinned tabs (BH-055 to BH-061): pin / unpin (Cmd-D, KB-012), reset to the pinned URL (KB-041, the favicon click
/// of GS-005 and its Cmd-click of BH-058), Reset Space (BH-059), Replace Pin with Current Page (BH-060) and
/// Separate From Pinned Tab (BH-061).
///
/// The pinned URL is the sidebar node's `url`: engine navigations of a pinned or Favorite tab never reach it
/// (`writesLiveURL(toSection:)`), as in the browser's own data model (`savedURL`); the node's title still follows
/// the page (BH-062). A reset navigates the live engine tab back to the node URL; Replace Pin writes the page's
/// URL into the node. Dragging above the divider is #104 (GS-007), command bar actions are #112, BH-056's Peek is
/// #349's link-activation routing, and the hover affordance of BH-061 waits on the design pass (#304); the action
/// is on the row's context menu meanwhile.
extension ShellWindowController {
  /// Wires the sidebar's pinned-tab entry points: the context menu items and the favicon click.
  func wirePinned() {
    sidebarController.onPinToggle = { [weak self] node in self?.togglePin(of: node) }
    sidebarController.onResetPinned = { [weak self] node in self?.resetPinned(node: node) }
    sidebarController.onReplacePin = { [weak self] node in self?.replacePin(node: node) }
    sidebarController.onSeparateFromPinned = { [weak self] node in self?.separateFromPinned(node: node) }
    sidebarController.onPinnedFaviconClick = { [weak self] node, modifiers in
      self?.pinnedFaviconClicked(node: node, modifiers: modifiers)
    }
    sidebarController.pinnedNavigatedProvider = { [weak self] node in
      guard let self, case .navigated = self.pinnedState(of: node) else { return false }
      return true
    }
  }

  // MARK: Pure rules

  /// The node the pin command acts on (KB-012): a tab directly in Pinned or Today pins and unpins itself; a focused
  /// pane pins its whole split (BH-115), so panes are never torn out of their Split View. Favorites, folders and
  /// foldered tabs (pinned through their folder) have no pin toggle.
  static func pinnableNode(_ node: NodeID, in sidebar: any SidebarSource) -> NodeID? {
    switch sidebar.parent(of: node) {
    case .pinned?, .today?:
      return node
    case .split(let split)?:
      switch sidebar.parent(of: split) {
      case .pinned?, .today?: return split
      default: return nil
      }
    default:
      return nil
    }
  }

  /// The File menu item's title (KB-012).
  static func pinMenuTitle(isPinned: Bool) -> String { isPinned ? "Unpin Tab" : "Pin Tab" }

  /// The pin / unpin toast (BH-055, [S] strings).
  static func pinToastText(pinned: Bool, spaceTitle: String) -> String {
    pinned ? "Pinned Tab to \(spaceTitle)" : "Un-Pinned Tab from \(spaceTitle)"
  }

  /// Only Today nodes track the page's URL: pinned and Favorite nodes keep the pinned URL (BH-057, BH-048), so
  /// Reset, Replace Pin and reopening a closed pin (BH-068's direction) can return to it.
  static func writesLiveURL(toSection section: SidebarLocation?) -> Bool {
    if case .today? = section { true } else { false }
  }

  // MARK: Pin and unpin (BH-055)

  /// Cmd-D (KB-012, File > Pin / Unpin Tab): pins the current Today tab or split, unpins a pinned one. The page
  /// never closes and the row never archives: the tab (or split) only changes sections.
  @objc public func pinTab(_ sender: Any?) {
    guard let node = currentNode, let target = Self.pinnableNode(node, in: sidebar) else { return }
    togglePin(of: target)
  }

  /// The row context menu's Pin / Unpin Tab, on a node directly in Pinned or Today.
  func togglePin(of node: NodeID) {
    switch sidebar.parent(of: node) {
    case .today(let space)?:
      guard move(node, to: .pinned(space)) else { return }       // appended to Pinned [I]
      showPinToast(pinned: true, space: space)
    case .pinned(let space)?:
      guard move(node, to: .today(space), at: 0) else { return } // on top of Today [I]
      showPinToast(pinned: false, space: space)
    default:
      break
    }
  }

  private func showPinToast(pinned: Bool, space: SpaceID) {
    toasts.show(Toast(text: Self.pinToastText(pinned: pinned, spaceTitle: sidebar.space(space)?.title ?? "")))
  }

  // MARK: Reset (BH-057, KB-041)

  /// Where `node` stands relative to its pinned URL. `.notPinned` covers Today tabs, Favorites and unknown nodes.
  func pinnedState(of node: NodeID) -> PinnedTabState {
    guard case .tab(_, let pinnedURL, _)? = sidebar.node(node),
          case .pinned? = sidebar.section(containing: node) else { return .notPinned }
    guard let tab = tabsByNode[node], let current = engine.snapshot(of: tab)?.url, current != pinnedURL else {
      return .atPinnedURL
    }
    return .navigated(current: current)
  }

  /// File > Back to Pinned URL (KB-041, unbound as in Arc): the current tab, when it is a navigated pinned tab,
  /// returns to its pinned URL.
  @objc public func resetTab(_ sender: Any?) {
    guard let node = currentNode else { return }
    resetPinned(node: node)
  }

  /// Navigates `node`'s live engine tab back to the pinned URL (BH-057); a no-op for anything else.
  func resetPinned(node: NodeID) {
    guard case .navigated = pinnedState(of: node),
          case .tab(_, let pinnedURL, _)? = sidebar.node(node),
          let tab = tabsByNode[node] else { return }
    engine.navigate(tab, to: pinnedURL)
  }

  /// GS-005: a favicon click on a navigated pinned tab resets it (BH-057); Cmd-click also opens the page it was on
  /// in a new Today tab (BH-058; in the background [I], as Cmd-opens are). Any other favicon click is a plain click.
  func pinnedFaviconClicked(node: NodeID, modifiers: NSEvent.ModifierFlags) {
    guard case .navigated(let current) = pinnedState(of: node),
          let space = sidebar.spaceID(containing: node) else {
      activate(node: node)
      return
    }
    guard modifiers.intersection([.command, .option, .control, .shift]) == .command else {
      resetPinned(node: node)
      return
    }
    let title = pageTitle(of: node, fallback: current)
    resetPinned(node: node)
    do {
      _ = try sidebar.addTab(url: current, title: title, in: .today(space), at: 0)
      announceCreation(.tab)                                        // BH-006
    } catch {
      onError?(.addTab, error)
    }
  }

  // MARK: Reset Space (BH-059)

  /// Spaces > Reset Space: every loaded pinned tab of the current Space that navigated away (foldered and split
  /// tabs included) returns to its pinned URL. Unloaded pins already show it.
  @objc public func resetSpace(_ sender: Any?) {
    guard let space = currentSpace else { return }
    for node in resettablePinnedTabs(in: space) { resetPinned(node: node) }
  }

  /// The current Space's loaded, navigated pinned tabs, at every depth.
  func resettablePinnedTabs(in space: SpaceID) -> [NodeID] {
    var found: [NodeID] = []
    collectNavigatedPinned(at: .pinned(space), into: &found)
    return found
  }

  private func collectNavigatedPinned(at location: SidebarLocation, into found: inout [NodeID]) {
    for child in sidebar.children(of: location) {
      if case .navigated = pinnedState(of: child) { found.append(child) }
      if let inner = sidebar.node(child)?.childLocation { collectNavigatedPinned(at: inner, into: &found) }
    }
  }

  // MARK: Replace Pin and Separate (BH-060, BH-061)

  /// Replace Pin with Current Page (BH-060): the stored pinned URL becomes the page's current URL.
  func replacePin(node: NodeID) {
    guard case .navigated(let current) = pinnedState(of: node) else { return }
    sidebar.updateTab(node, url: current, title: nil)
  }

  /// Separate From Pinned Tab (BH-061): the page detaches into its own Today tab (on top, and focused [I]) and the
  /// pin resets to its URL. The page loads again in the new tab [I]; moving the live page over is the same
  /// cross-tab handoff BH-066 needs (#300).
  func separateFromPinned(node: NodeID) {
    guard case .navigated(let current) = pinnedState(of: node),
          let space = sidebar.spaceID(containing: node) else { return }
    let title = pageTitle(of: node, fallback: current)
    resetPinned(node: node)
    do {
      let detached = try sidebar.addTab(url: current, title: title, in: .today(space), at: 0)
      activate(node: detached)
      announceCreation(.tab)                                        // BH-006
    } catch {
      onError?(.addTab, error)
    }
  }

  /// The live page's title for a detached copy, before a reset changes it; the URL's host as the fallback.
  private func pageTitle(of node: NodeID, fallback url: URL) -> String {
    let live = tabsByNode[node].flatMap { engine.snapshot(of: $0)?.title }
    return live.flatMap { $0.isEmpty ? nil : $0 } ?? (url.host() ?? url.absoluteString)
  }

  // MARK: Menu validation

  /// Titles File > Pin / Unpin Tab for the current tab and gates the three pinned commands; nil for other items.
  /// Pin needs a pinnable current node, Reset a navigated current pinned tab, Reset Space a navigated pinned tab
  /// in the current Space.
  func validatePinnedMenuItem(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(pinTab(_:)):
      guard let node = currentNode, let target = Self.pinnableNode(node, in: sidebar) else { return false }
      item.title = Self.pinMenuTitle(isPinned: sidebar.parent(of: target).map {
        if case .pinned = $0 { true } else { false }
      } ?? false)
      return true
    case #selector(resetTab(_:)):
      guard let node = currentNode, case .navigated = pinnedState(of: node) else { return false }
      return true
    case #selector(resetSpace(_:)):
      guard let space = currentSpace, !resettablePinnedTabs(in: space).isEmpty else { return false }
      return true
    default:
      return nil
    }
  }
}
