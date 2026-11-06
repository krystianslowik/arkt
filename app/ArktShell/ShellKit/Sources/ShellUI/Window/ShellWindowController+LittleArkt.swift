import AppKit
import EngineAPI

// MARK: - Little Arkt (#314, #352)

/// The main window's side of Little Arkt's Open in: a tab from a Little Arkt window becomes a Today tab here, with
/// its page, history and state (no reload, BH-136). Without the flight it happens at once (`receiveMovedTab`); with
/// it, the row comes first and the page at rest (`LittleArktFlightDestination`).
extension ShellWindowController: LittleArktFlightDestination {
  /// `tab`, now in a Little Arkt window, becomes the first Today tab of `space` (the current Space when nil, a new
  /// first Space on a first run), selected, and the window comes forward with the page focused. The row and its
  /// mapping exist before the engine moves the tab, so the tab's first event here already has its row. False when
  /// the sidebar refuses the row; the tab then stays where it is.
  func receiveMovedTab(_ tab: TabID, in space: SpaceID?, dialog: JavaScriptDialog? = nil) -> Bool {
    guard let node = beginReceiving(tab, in: space) else { return false }
    return finishReceiving(tab, node: node, dialog: dialog)
  }

  /// The row at the top of Today in `space`, mapped to `tab` (the page itself is still in the Little Arkt window),
  /// and that Space shown. Nil when the sidebar refuses the row.
  func beginReceiving(_ tab: TabID, in space: SpaceID?) -> NodeID? {
    guard let snapshot = engine.snapshot(of: tab) else { return nil }
    let url = snapshot.url ?? Self.blankPage
    let title = snapshot.title.isEmpty ? HostDisplay.savedTitle(for: url) : snapshot.title
    guard let target = space ?? currentSpace ?? createSpace() else { return nil }
    let node: NodeID
    do {
      node = try sidebar.addTab(url: url, title: title, in: .today(target), at: 0)    // BH-079: the top of Today
    } catch {
      onError?(.addTab, error)
      return nil
    }
    _ = ensureEngineWindow()
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    replay(snapshot, into: node)
    if target != currentSpace { sidebarController.showSpace(target) }
    return node
  }

  /// The page moves into this window's engine window and its row is selected, mounting the page in the content card
  /// at its final size; the window becomes key with the page focused. `clearingPrevious` is the flight's landing
  /// (#455): the old selection already faded out, so it must not draw the previous fill now. A landing before the
  /// first arrival frame cleared nothing, so the previous fill stays as the no-flight path draws it. A pending
  /// JavaScript dialog of the page (`dialog`) is adopted before the move, as in Tab Handoff (#471): its panel shows
  /// once the page is shown, and the answer reaches the page from this window only.
  func finishReceiving(_ tab: TabID, node: NodeID, clearingPrevious: Bool = false,
                       dialog: JavaScriptDialog? = nil) -> Bool {
    guard tabsByNode[node] == tab else { return false }
    if let dialog { javaScriptDialogs.adopt(dialog) }
    let endedArrival = sidebarController.outline(containing: node)?.endArrival() ?? false
    sidebarController.endFavoriteSelectionFade()
    engine.moveTab(tab, to: ensureEngineWindow())
    activate(node: node)
    if clearingPrevious, endedArrival { sidebarController.clearPrevious() }
    window?.makeKeyAndOrderFront(nil)
    engine.focusPage(of: tab)
    return true
  }

  /// The flight ended and the page is not coming (the page closed itself, or this window is going away): the
  /// arrival stops and the row made for the page goes. The page is still in the Little Arkt window, so the row lets
  /// go of it first; a row the page's own close already archived is left alone.
  func cancelReceiving(_ tab: TabID, node: NodeID) {
    sidebarController.outline(containing: node)?.endArrival()
    sidebarController.endFavoriteSelectionFade()
    guard tabsByNode[node] == tab else { return }
    _ = releaseLiveTab(of: node)
    archive(node, heldCurrent: false)
  }

  func presentArrival(of node: NodeID, room: Double, appear: Double) {
    sidebarController.outline(containing: node)?.presentArrival(of: node, room: room, appear: appear)
    sidebarController.fadeCurrentFavoriteSelection(room: room)
  }

  var flightWindow: NSWindow? { window }

  var flightCardFrame: CGRect? {
    rootView.layoutSubtreeIfNeeded()
    let card = rootView.card
    guard let window = card.window, !card.isHiddenOrHasHiddenAncestor else { return nil }
    return window.convertToScreen(card.convert(card.bounds, to: nil))
  }

  /// The Space "Open in" names: this window's current Space.
  var littleArktTargetSpace: SidebarSpaceInfo? {
    currentSpace.flatMap { sidebar.space($0) }
  }
}

// MARK: - Opt-Cmd-click into Little Arkt (#356, BH-132, GS-028)

extension ShellWindowController {
  /// A link activated with Option and Command held, while the setting is on: the engine drops it and a new Little
  /// Arkt window opens on its URL after the call returns (the engine is never called from inside its own decision).
  /// From a blank or incognito window, a private window of the same kind opens instead (#710).
  func opensLinkInLittleArkt(_ activation: EngineLinkActivation) -> Bool {
    guard let open = onOpenLinkInLittleArkt,
          LittleArktRouting.opensInLittleArkt(activation, enabled: opensLittleArktOnOptionCommandClick()) else {
      return false
    }
    let url = activation.url
    let kind = privateKind                       // #710: read now, so the hop cannot lose it with the window
    DispatchQueue.main.async { open(url, kind) }
    return true
  }

  /// This window's kind when it is a blank or incognito window; nil for a normal one.
  private var privateKind: SidebarPresentation? { isPrivateWindow ? sidebarController.presentation : nil }

  /// Opt-Cmd-click on a tab's row or tile (BH-132; docs/design/little-arkt.md, When a Little Arkt window opens):
  /// - a Today tab's page moves into a new Little Arkt window (no reload when it is loaded) and the row leaves the
  ///   sidebar without an Archive entry (the window set does both);
  /// - a pinned tab or a Favorite opens its page in a new Little Arkt window and keeps its place, as a Peek does.
  /// False when nothing happened (the setting is off); the click is then a plain click.
  func moveToLittleArkt(_ node: NodeID) -> Bool {
    guard opensLittleArktOnOptionCommandClick(), case .tab(_, let url, _)? = sidebar.node(node) else { return false }
    let pageURL = tabsByNode[node].flatMap { engine.snapshot(of: $0)?.url } ?? url
    switch sidebar.section(containing: node) {
    case .today?:
      return onMoveToLittleArkt?(node, pageURL) ?? false
    case .pinned?, .favorites?:
      guard let open = onOpenLinkInLittleArkt else { return false }
      open(pageURL, privateKind)
      return true
    default:
      return false
    }
  }

  /// `node` is about to leave the sidebar while this window shows its handoff placeholder (its page went to another
  /// window): what to do once it is gone. The next tab is picked now, while the row is still in place, as a closed
  /// current tab's is (`archive(_:heldCurrent:)`); it is shown unless another window shows it by then. Nil when this
  /// window does not show that placeholder.
  func afterRowLeaves(_ node: NodeID) -> (@MainActor () -> Void)? {
    guard currentTab == nil, let placeholder = handoffPlaceholder, placeholder.node == node,
          rootView.card.contentView === placeholder else { return nil }
    let next = sidebar.spaceID(containing: node) == currentSpace ? successor(of: node) : nil
    return { [weak self] in
      // The removal itself already dropped the placeholder (`dropPlaceholderOfRemovedRow`); a tab picked meanwhile
      // stays.
      guard let self, self.currentTab == nil else { return }
      if let next, self.sidebar.node(next) != nil, !(self.otherWindowsVisibleNodes?() ?? []).contains(next) {
        self.activate(node: next)
      } else {
        self.dropHandoffPlaceholder()
      }
    }
  }

  /// The card stops showing the handoff placeholder, whose row is gone; it shows nothing until a tab is picked.
  func dropHandoffPlaceholder() {
    guard let placeholder = handoffPlaceholder, rootView.card.contentView === placeholder else { return }
    rootView.card.setContent(nil)
    refreshAddress()
  }
}
