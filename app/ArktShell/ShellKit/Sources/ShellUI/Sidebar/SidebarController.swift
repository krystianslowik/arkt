import AppKit

/// Owns the sidebar column for one window: Space pages, favorites, and the current / previous tab states.
/// Engine-agnostic: the window controller listens to `onActivate` to create engine tabs and fill the card,
/// and feeds titles back through the source and favicons through `setFavicon(_:for:)`.
@MainActor
public final class SidebarController {
  public let source: any SidebarSource
  public let profile: String
  public let view: SidebarContainerView
  public private(set) var current: NodeID?
  /// The previously current tab (drawn at the 32% level).
  public private(set) var previous: NodeID?
  public private(set) var currentSpace: SpaceID?

  /// A tab became current (fires on every activation, including re-activating the current tab).
  public var onActivate: (@MainActor (NodeID) -> Void)?
  /// The "+" button in the bottom bar.
  public var onNewTab: (@MainActor () -> Void)?
  /// Continuous pager position on every strip move (drives the window theme crossfade).
  public var onSpacePosition: (@MainActor (CGFloat) -> Void)?
  /// The profile's Space list changed (themes need refreshing).
  public var onSpacesChanged: (@MainActor ([SpaceID]) -> Void)?

  private var pages: [SpaceID: SpacePageView] = [:]
  private var pagedSpaces: [SpaceID] = []
  /// Flavor per paged Space, cached so a swipe frame does no source lookups.
  private var pagedFlavors: [ThemeFlavor] = []
  /// Last active tab per Space, restored when the Space becomes current again (BH-036).
  private var lastActive: [SpaceID: NodeID] = [:]
  /// Decoded favicons by node; kept while the node exists in the source (its engine tab may close and reopen),
  /// dropped when the node leaves it (`.structure` and `.spaces` changes, `deactivate(node:)`).
  private(set) var favicons: [NodeID: NSImage] = [:]
  private var observation: SidebarObservation?
  private let buttonTarget = ButtonTarget()

  public init(source: any SidebarSource, profile: String = "default",
              topBarHeight: CGFloat = ShellMetrics.standard.sidebarTopBarHeight) {
    self.source = source
    self.profile = profile
    self.view = SidebarContainerView(source: source, profile: profile, topBarHeight: topBarHeight)
    view.favorites.onActivate = { [weak self] id in self?.activate(node: id) }
    view.favorites.faviconProvider = { [weak self] id in self?.favicons[id] }
    view.spaceDots.onSelect = { [weak self] index in self?.goToSpace(at: index) }
    view.pager.onPosition = { [weak self] position in self?.pagerMoved(to: position) }
    view.pager.onSettle = { [weak self] index in self?.pagerSettled(on: index) }
    buttonTarget.onNewTab = { [weak self] in self?.onNewTab?() }
    view.newTabButton.target = buttonTarget
    view.newTabButton.action = #selector(ButtonTarget.newTab(_:))
    observation = source.observe { [weak self] change in self?.apply(change) }
    if let first = spaces.first { showSpace(first) }
  }

  /// Spaces of this window's profile, in sidebar order.
  public var spaces: [SpaceID] { source.spaceOrder.filter { source.space($0)?.profile == profile } }

  public var currentPage: SpacePageView? { currentSpace.flatMap { pages[$0] } }

  public var resolver: TabRowState.Resolver {
    TabRowState.Resolver(current: current, visible: current.map { [$0] } ?? [], previous: previous)
  }

  public func rowState(for id: NodeID) -> TabRowState { resolver.state(for: id) }

  // MARK: Spaces

  /// Makes `id` the current Space now and shows its page without animating (activation, launch).
  public func showSpace(_ id: SpaceID) {
    guard let info = source.space(id), info.profile == profile else { return }
    syncPages()
    guard let index = pagedSpaces.firstIndex(of: id) else { return }
    commit(space: id, info: info, index: index)
    view.pager.jump(to: index)
  }

  /// Animates to the Space at `index` (dots, Ctrl-1..9); it becomes current when the pager settles.
  public func goToSpace(at index: Int) {
    syncPages()
    guard pagedSpaces.indices.contains(index) else { return }
    view.pager.go(to: index)
  }

  /// KB-033: Cmd-Opt-Right. Counts from the Space a running switch heads to; stops at the last Space.
  public func nextSpace() { goToSpace(at: min(view.pager.targetIndex + 1, pagedSpaces.count - 1)) }
  /// KB-034: Cmd-Opt-Left. Stops at the first Space.
  public func previousSpace() { goToSpace(at: max(view.pager.targetIndex - 1, 0)) }

  /// The tab to show when `space` becomes current: its last active tab (BH-036), else its first tab,
  /// Pinned before Today. PARITY(NEEDS-RUNTIME-CHECK): what Arc shows in a never-visited Space.
  public func tabToRestore(in space: SpaceID) -> NodeID? {
    if let last = lastActive[space], source.spaceID(containing: last) == space { return last }
    return (source.children(of: .pinned(space)) + source.children(of: .today(space)))
      .lazy.compactMap { self.source.firstTab(at: $0) }.first
  }

  private func commit(space id: SpaceID, info: SidebarSpaceInfo, index: Int) {
    guard let page = pages[id] else { return }
    currentSpace = id
    page.outlineController.setRowStates(resolver)
    view.setCurrent(page: page)
    view.setFlavor(info.theme.flavor)
    view.spaceDots.selectedIndex = index
  }

  private func pagerMoved(to position: CGFloat) {
    view.spaceDots.position = position
    // The chrome around the pages takes the flavor of the Space nearest the fingers.
    let nearest = min(max(Int(position.rounded()), 0), max(pagedFlavors.count - 1, 0))
    if pagedFlavors.indices.contains(nearest), pagedFlavors[nearest] != view.flavor {
      view.setFlavor(pagedFlavors[nearest])
    }
    onSpacePosition?(position)
  }

  private func pagerSettled(on index: Int) {
    guard pagedSpaces.indices.contains(index) else { return }
    let id = pagedSpaces[index]
    guard let info = source.space(id) else { return }
    if id != currentSpace {
      commit(space: id, info: info, index: index)
      if let tab = tabToRestore(in: id) { activate(node: tab) }
    } else {
      view.spaceDots.selectedIndex = index
      view.setFlavor(info.theme.flavor)
    }
  }

  /// Creates pages for new Spaces and hands the ordered list to the pager when it changed, then refreshes Space
  /// details (which fires `onSpacesChanged` unless `notify` is false).
  private func syncPages(notify: Bool = true) {
    let order = spaces
    guard order != pagedSpaces else { return }
    for id in order where pages[id] == nil { makePage(id) }
    for id in pages.keys where !order.contains(id) { pages[id] = nil }
    pagedSpaces = order
    let index = currentSpace.flatMap { order.firstIndex(of: $0) } ?? 0
    view.setPages(order.compactMap { pages[$0] }, index: index)
    refreshSpaceDetails(notify: notify)
  }

  /// Re-reads every paged Space: live pages (title, flavor), dot titles, cached flavors and the current chrome,
  /// then tells the window once (themes) unless `notify` is false. Called after any Space list or Space field change.
  private func refreshSpaceDetails(notify: Bool = true) {
    for id in pagedSpaces { pages[id]?.refresh(from: source.space(id)) }
    pagedFlavors = pagedSpaces.map { source.space($0)?.theme.flavor ?? .light }
    view.spaceDots.titles = pagedSpaces.map { source.space($0)?.title ?? "" }
    if let id = currentSpace, let info = source.space(id) { view.setFlavor(info.theme.flavor) }
    if notify { onSpacesChanged?(pagedSpaces) }
  }

  @discardableResult
  private func makePage(_ id: SpaceID) -> SpacePageView {
    let page = SpacePageView(source: source, spaceID: id)
    page.outlineController.onActivate = { [weak self] node in self?.activate(node: node) }
    page.outlineController.faviconProvider = { [weak self] node in self?.favicons[node] }
    page.outlineController.setRowStates(resolver)
    pages[id] = page
    return page
  }

  // MARK: Activation

  /// Makes `node` current. A split activates its first pane; folders and unknown nodes are ignored.
  /// Activating a tab in another Space of this profile switches to that Space.
  public func activate(node: NodeID) {
    if case .folder? = source.node(node) { return }       // folders expand in place, they never activate
    guard let tab = source.firstTab(at: node) else { return }
    let space = source.spaceID(containing: tab)
    if let space, space != currentSpace { showSpace(space) }
    if let space { lastActive[space] = tab }
    if tab != current {
      previous = current
      current = tab
      let states = resolver
      for page in pages.values { page.outlineController.setRowStates(states) }
      view.favorites.setRowStates(states)
    }
    onActivate?(tab)
  }

  /// Forgets a node that no longer has a tab (engine tab closed): any current/previous role, and its favicon only
  /// when the node itself is gone from the source.
  public func deactivate(node: NodeID) {
    if source.node(node) == nil { favicons[node] = nil }
    guard node == current || node == previous else { return }
    if node == current { current = nil }
    if node == previous { previous = nil }
    let states = resolver
    for page in pages.values { page.outlineController.setRowStates(states) }
    view.favorites.setRowStates(states)
  }

  // MARK: Updates

  /// Caches a favicon (nil = back to the letter placeholder) and refreshes only that row or tile.
  public func setFavicon(_ data: Data?, for node: NodeID) {
    favicons[node] = data.flatMap(NSImage.init(data:))
    for page in pages.values { page.outlineController.reload(node: node) }
    view.favorites.reload(node: node)
  }

  /// Caches a batch of favicons (for example the ones loaded after launch), then refreshes each affected row or tile
  /// once. Ids the source does not know are ignored.
  public func setFavicons(_ batch: [NodeID: Data]) {
    var changed: [NodeID] = []
    for (node, data) in batch where source.node(node) != nil {
      favicons[node] = NSImage(data: data)
      changed.append(node)
    }
    for node in changed {
      for page in pages.values { page.outlineController.reload(node: node) }
      view.favorites.reload(node: node)
    }
  }

  /// Drops cached favicons of nodes that left the source. O(cached favicons), on structure and Space changes only.
  private func pruneFavicons() {
    for node in favicons.keys where source.node(node) == nil { favicons[node] = nil }
  }

  private func apply(_ change: SidebarChange) {
    switch change {
    case .structure(let location):
      pruneFavicons()
      if case .favorites = location {
        if view.favorites.apply(structure: location) { view.needsLayout = true }
      } else {
        for page in pages.values { page.outlineController.apply(structure: location) }
      }
    case .node(let id):
      for page in pages.values { page.outlineController.reload(node: id) }
      view.favorites.reload(node: id)
    case .spaces:
      pruneFavicons()                               // a removed Space's nodes emit no structure change
      // Settle pages and the current Space first, then tell the window once, so `onSpacesChanged` never sees a
      // nil current Space after an add or a removed one after a removal.
      if spaces == pagedSpaces {
        refreshSpaceDetails(notify: false)          // same list: a title, theme or other Space field changed
      } else {
        syncPages(notify: false)                    // creates/drops pages, then the same refresh
      }
      let currentIsShown = currentSpace.map { spaces.contains($0) } ?? false
      if !currentIsShown {
        if let first = spaces.first {
          let replacesRemoved = currentSpace != nil
          showSpace(first)
          if replacesRemoved { activateRestoredTabLater(in: first) }
        } else if currentSpace != nil {             // the last Space went away
          currentSpace = nil
          view.setCurrent(page: nil)
        }
      }
      onSpacesChanged?(pagedSpaces)
    }
  }
}

extension SidebarController {
  /// After the current Space was removed and `space` took its place, shows its tab the way a settled swipe does.
  /// Deferred one main-queue turn: activating fills the card, which writes titles back to the source, and a
  /// source must not be mutated while it is still delivering the change that removed the Space.
  private func activateRestoredTabLater(in space: SpaceID) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.currentSpace == space else { return }
      if let current = self.current, self.source.spaceID(containing: current) == space { return }
      if let tab = self.tabToRestore(in: space) { self.activate(node: tab) }
    }
  }
}

/// `NSButton` target (the controller itself is not an NSObject).
@MainActor
private final class ButtonTarget: NSObject {
  var onNewTab: (@MainActor () -> Void)?
  @objc func newTab(_ sender: Any?) { onNewTab?() }
}
