import AppKit

/// What one window's sidebar draws. The shared source stays as it is: blank and incognito draw no items of it.
public enum SidebarPresentation: Equatable, Sendable {
  case standard
  case blank
  case incognito
}

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
  /// Blank and incognito windows draw no Spaces, tabs or Favorites. The source is shared with the other windows.
  public private(set) var presentation: SidebarPresentation = .standard

  /// A tab became current (fires on every activation, including re-activating the current tab).
  public var onActivate: (@MainActor (NodeID) -> Void)?
  /// A different Space has no tab to restore. The window detaches its pages without closing their engine tabs.
  public var onEmptySpace: (@MainActor () -> Void)?
  /// A row's hover close (X) button or VoiceOver close action (GS-043); the window closes the node as Cmd-W does.
  /// A pane row's X goes to `onRemovePane` instead (BH-121).
  public var onClose: (@MainActor (NodeID) -> Void)?
  /// Split row interactions of every Space page (S6), forwarded from `SidebarOutlineController`.
  public var onSeparateSplit: (@MainActor (NodeID) -> Void)?
  public var onRemovePane: (@MainActor (NodeID) -> Void)?
  public var onConvertSplit: (@MainActor (NodeID) -> Void)?
  public var onDuplicateSplit: (@MainActor (NodeID) -> Void)?
  public var onDuplicateIntoSplit: (@MainActor (NodeID) -> Void)?
  /// A tab row's drag of every Space page started and ended (S7), forwarded from `SidebarOutlineController`.
  public var onNodeDragBegan: (@MainActor (NodeID) -> Void)?
  public var onNodeDragEnded: (@MainActor () -> Void)?
  /// A sidebar drag settled on a location (BH-047): the Favorites band, or the Space page for a Favorite. The
  /// window moves the node; false means the move was refused.
  public var onSidebarDrop: (@MainActor (_ node: NodeID, _ location: SidebarLocation) -> Bool)?
  /// A drop on a Space page's outline (#104); the window performs it. False: refused.
  public var onSidebarDropRequest: (@MainActor (SidebarDropRequest) -> Bool)?
  /// Text or a link dropped on a Space page (GS-015): a new tab at `placement`. False: refused.
  public var onSidebarTextDrop: (@MainActor (_ url: URL, _ title: String, _ placement: SidebarDropPlacement)
    -> Bool)?
  /// A tab dragged out of the sidebar and released over no window (GS-013), at a screen point.
  public var onSidebarDragOut: (@MainActor (NodeID, NSPoint) -> Void)?
  /// The nodes of the sidebar drag in progress (the multi-selection, #105), empty between drags.
  public private(set) var dragNodes: [NodeID] = []
  /// A row's "Move To > Favorites" (BH-047); the window moves the node.
  public var onMoveToFavorites: (@MainActor (NodeID) -> Void)?
  /// Pin / Unpin Tab on a row's context menu (BH-055); the window moves the node.
  public var onPinToggle: (@MainActor (NodeID) -> Void)?
  /// Back to Pinned URL on a pinned row (BH-057).
  public var onResetPinned: (@MainActor (NodeID) -> Void)?
  /// Replace Pin with Current Page on a pinned row (BH-060).
  public var onReplacePin: (@MainActor (NodeID) -> Void)?
  /// Separate From Pinned Tab on a pinned row (BH-061).
  public var onSeparateFromPinned: (@MainActor (NodeID) -> Void)?
  /// A pinned row's favicon was clicked (GS-005), with the click's modifiers (BH-058).
  public var onPinnedFaviconClick: (@MainActor (NodeID, NSEvent.ModifierFlags) -> Void)?
  /// Whether a pinned tab sits away from its pinned URL (the window knows the live page's URL).
  public var pinnedNavigatedProvider: (@MainActor (NodeID) -> Bool)?
  /// A loaded Favorite past the recency limit should unload (BH-049); the window closes its page like the X does.
  public var onFavoriteUnload: (@MainActor (NodeID) -> Void)?
  /// A context menu action of any Space page that has no callback of its own (#105); the window runs it.
  public var onMenuAction: (@MainActor (SidebarMenuAction) -> Void)?
  /// A double-click on empty sidebar space of any Space page (BH-021).
  public var onEmptyAreaDoubleClick: (@MainActor () -> Void)?
  /// The "+" button in the bottom bar.
  public var onNewTab: (@MainActor () -> Void)?
  /// GS-035 (BH-108): the + button clicked in its "Paste and Go" state (hovered with Cmd held). The window
  /// opens the URL in a new tab.
  public var onPasteAndGo: (@MainActor (URL) -> Void)?
  /// The clipboard read behind GS-035; nil provider: the + button never offers Paste and Go.
  public var clipboardURLProvider: (@MainActor () -> URL?)?
  /// The current Space changed (swipe settle, `showSpace`, an activation crossing Spaces); the command bar
  /// refreshes its suggestions on it (BH-111).
  public var onCurrentSpaceChanged: (@MainActor (SpaceID) -> Void)?
  /// The pane to focus when a split row is activated (decision 7: the split's last focused pane). Nil, or a node
  /// that is not a pane of that split: its first pane.
  public var preferredPane: (@MainActor (NodeID) -> NodeID?)?
  /// Continuous pager position on every strip move (drives the window theme crossfade).
  public var onSpacePosition: (@MainActor (CGFloat) -> Void)?
  /// The profile's Space list changed (themes need refreshing).
  public var onSpacesChanged: (@MainActor ([SpaceID]) -> Void)?

  private var pages: [SpaceID: SpacePageView] = [:]
  private var pagedSpaces: [SpaceID] = []
  /// Theme last shown per Space. A change of the current Space's theme asks the window to crossfade; the first
  /// time a Space is seen does not.
  private var shownThemes: [SpaceID: SpaceThemeInfo] = [:]
  private var themeCrossfadePending = false
  /// Flavor per paged Space, cached so a swipe frame does no source lookups.
  private var pagedFlavors: [ThemeFlavor] = []
  /// Last active tab per Space, restored when the Space becomes current again (BH-036).
  private var lastActive: [SpaceID: NodeID] = [:]
  /// Decoded favicons by node; kept while the node exists in the source (its engine tab may close and reopen),
  /// dropped when the node leaves it (`.structure` and `.spaceRemoved` changes, `deactivate(node:)`).
  private(set) var favicons: [NodeID: NSImage] = [:]
  /// Tabs whose page is loaded in this window: every activation shows the tab, which creates its page; pages the
  /// window creates without an activation (the other panes of a split) are added through `markLoaded(node:)`, and
  /// the window calls `deactivate(node:)` when any page closes; nodes that leave the source are dropped like
  /// favicons. Decides whether a Favorite tile shows its X (#82).
  private(set) var loadedNodes: Set<NodeID> = []
  /// Loaded Favorites, least to most recently used (BH-049); activations append, closes and removals drop.
  private var favoriteLoadOrder: [NodeID] = []
  /// The current Favorite captured on the first arrival frame (#465). A Favorite that becomes current later does
  /// not start fading. `captured` stays set, with a nil node, when that frame had no current Favorite.
  private var favoriteFade: (captured: Bool, node: NodeID?) = (false, nil)
  /// The drop overlay over the Favorites band and the Space page, shown during a sidebar drag (BH-047).
  private(set) var dropOverlay: FavoritesDropOverlayView?
  /// Tabs the window shows besides the current one (the other panes of a shown split), drawn as `.contentVisible`.
  public var visible: Set<NodeID> = [] {
    didSet { if visible != oldValue { applyRowStates() } }
  }
  private var observation: SidebarObservation?
  private let buttonTarget = ButtonTarget()

  /// The appearance and Increase Contrast setting the Space themes are drawn for (#410). The window keeps it current;
  /// a change redraws every Space through `ThemeContrast`.
  public var themeContext = ThemeContext(appearance: .light) {
    didSet { if themeContext != oldValue { refreshSpaceDetails() } }
  }
  /// A theme drawn in place of a Space's stored one while the theme creator drags a control (#410). Not stored.
  private(set) var themePreview: (space: SpaceID, theme: SpaceThemeInfo)?
  /// The window draws a previewed theme at once, without a crossfade: the paged index and the drawn theme.
  public var onThemePreview: (@MainActor (Int, SpaceThemeInfo) -> Void)?
  /// The open theme creator, if any (#410).
  var themeCreator: ThemeCreatorController?
  /// The theme creator's haptics and Reduce Motion. Tests count haptics through an injected performer.
  var makeThemeHaptics: @MainActor () -> ThemeHaptics = { ThemeHaptics() }
  var themeCreatorReducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  public init(source: any SidebarSource, profile: String = "default",
              topBarHeight: CGFloat = ShellMetrics.standard.sidebarTopBarHeight) {
    self.source = source
    self.profile = profile
    self.view = SidebarContainerView(source: source, profile: profile, topBarHeight: topBarHeight)
    view.favorites.onActivate = { [weak self] id in self?.activate(node: id) }
    view.favorites.faviconProvider = { [weak self] id in self?.favicons[id] }
    view.favorites.onClose = { [weak self] id in self?.onClose?(id) }
    view.favorites.onMenuAction = { [weak self] action in self?.onMenuAction?(action) }
    view.favorites.pageLoadedProvider = { [weak self] id in self?.loadedNodes.contains(id) ?? false }
    view.favorites.onNodeDragBegan = { [weak self] id in self?.nodeDragBegan(id) }
    view.favorites.onNodeDragEnded = { [weak self] in self?.nodeDragEnded() }
    view.spaceDots.onSelect = { [weak self] index in self?.goToSpace(at: index) }
    view.pager.onPosition = { [weak self] position in self?.pagerMoved(to: position) }
    view.pager.onSettle = { [weak self] index in self?.pagerSettled(on: index) }
    buttonTarget.onNewTab = { [weak self] in self?.newTabClicked() }
    view.onNewTabHover = { [weak self] hovered in self?.newTabHoverChanged(hovered) }
    view.newTabButton.target = buttonTarget
    view.newTabButton.action = #selector(ButtonTarget.newTab(_:))
    observation = source.observe { [weak self] change in self?.apply(change) }
    if let first = spaces.first { showSpace(first) }
  }

  /// `id`'s Space as the window draws it: the source's info with its theme (or the creator's preview) passed through
  /// the automatic contrast rule (`ThemeContrast`). The source keeps the stored colors.
  public func drawnSpace(_ id: SpaceID) -> SidebarSpaceInfo? {
    guard var info = source.space(id) else { return nil }
    let stored = themePreview?.space == id ? themePreview?.theme ?? info.theme : info.theme
    info.theme = ThemeContrast.drawn(stored, in: themeContext)
    return info
  }

  /// Shows `theme` for `space` without storing it (nil ends the preview): the window background, the page and the
  /// sidebar chrome follow at once, with no animation. The creator stores the theme through the source when a drag
  /// ends; the window then sees the same drawn theme and does not crossfade.
  func previewTheme(_ theme: SpaceThemeInfo?, for space: SpaceID) {
    themePreview = theme.map { (space, $0) }
    guard theme != nil, let info = drawnSpace(space), let index = pagedSpaces.firstIndex(of: space) else { return }
    pages[space]?.refresh(from: info)
    if pagedFlavors.indices.contains(index) { pagedFlavors[index] = info.theme.flavor }
    if space == currentSpace, view.flavor != info.theme.flavor { view.setFlavor(info.theme.flavor) }
    onThemePreview?(index, info.theme)
  }

  /// The theme creator opened or closed (#410). The window switches its theme crossfade to `firm` while it is open.
  public var onThemeCreatorChange: (@MainActor (Bool) -> Void)?

  /// Theme > Edit Theme...: opens the theme creator for `id`, anchored to its Space name (#410). The Space becomes
  /// current first. A creator open for another Space closes.
  public func openThemeCreator(for id: SpaceID) {
    if let open = themeCreator {
      if open.spaceID == id { return }
      closeThemeCreator(animated: false)
    }
    guard source.space(id)?.profile == profile, let host = view.window?.contentView else { return }
    if id != currentSpace { showSpace(id) }
    guard let page = pages[id] else { return }
    host.layoutSubtreeIfNeeded()
    let title = page.titleLabel
    let anchor = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: host)
    let edge = view.convert(view.bounds, to: host).maxX
    let creator = ThemeCreatorController(spaceID: id, sidebar: self, haptics: makeThemeHaptics(),
                                         reducesMotion: themeCreatorReducesMotion)
    creator.onClose = { [weak self, weak creator] in
      guard let self, self.themeCreator === creator else { return }
      self.themeCreator = nil
      self.onThemeCreatorChange?(false)
    }
    creator.passThroughViews = [page.optionsButton]
    themeCreator = creator
    onThemeCreatorChange?(true)
    creator.show(in: host, anchor: anchor, edge: edge)
  }

  /// Closes the theme creator, keeping its changes.
  public func closeThemeCreator(animated: Bool = true) {
    themeCreator?.close(animated: animated)
  }

  public var isThemeCreatorOpen: Bool { themeCreator != nil }

  /// Spaces of this window's profile, in sidebar order. Empty for a blank or incognito window (BH-170, BH-174).
  public var spaces: [SpaceID] {
    guard presentation == .standard else { return [] }
    return source.spaceOrder.filter { source.space($0)?.profile == profile }
  }

  /// Draws this window's sidebar as a normal, blank or incognito window. Does not change the shared source.
  public func present(_ presentation: SidebarPresentation) {
    guard presentation != self.presentation else { return }
    self.presentation = presentation
    let hidesItems = presentation != .standard
    if hidesItems {
      current = nil
      previous = nil
      currentSpace = nil
      visible = []
      view.setCurrent(page: nil)
      onEmptySpace?()
    }
    syncPages()
    view.favorites.isHidden = hidesItems
    view.spaceDots.isHidden = hidesItems
    view.pager.isHidden = hidesItems
    view.setIncognitoLabelVisible(presentation == .incognito)
    if presentation == .standard, let first = spaces.first { showSpace(first) }
  }

  /// True once, after the current Space's theme changed. The window consumes it in `refreshThemes`.
  public func consumeThemeCrossfade() -> Bool {
    let pending = themeCrossfadePending
    themeCrossfadePending = false
    return pending
  }

  public var currentPage: SpacePageView? { currentSpace.flatMap { pages[$0] } }

  /// The outline of the Space that holds `node`, shown or not: Little Arkt's arrival belongs to the row's Space even
  /// when the window shows another one mid-flight (#455). Nil when no page has the node.
  func outline(containing node: NodeID) -> SidebarOutlineController? {
    guard let space = source.spaceID(containing: node) else { return nil }
    return pages[space]?.outlineController
  }

  public var resolver: TabRowState.Resolver {
    TabRowState.Resolver(current: current, visible: visible.union(current.map { [$0] } ?? []), previous: previous)
  }

  public func rowState(for id: NodeID) -> TabRowState { resolver.state(for: id) }

  // MARK: Spaces

  /// Makes `id` the current Space now and shows its page without animating (activation, launch).
  public func showSpace(_ id: SpaceID) {
    guard presentation == .standard else { return }
    guard let info = source.space(id), info.profile == profile else { return }
    syncPages()
    guard let index = pagedSpaces.firstIndex(of: id) else { return }
    commit(space: id, info: info, index: index)
    view.pager.jump(to: index)
  }

  /// Animates to the Space at `index` (dots, Ctrl-1..9); it becomes current when the pager settles.
  public func goToSpace(at index: Int) {
    guard presentation == .standard else { return }
    syncPages()
    guard pagedSpaces.indices.contains(index) else { return }
    view.pager.go(to: index)
  }

  /// KB-033, GS-002: Cmd-Opt-Right and mouse button 4. Counts from the Space a running switch heads to; stops at the
  /// last Space [I], PARITY(NEEDS-RUNTIME-CHECK #78: whether Arc wraps at the ends).
  public func nextSpace() { goToSpace(at: min(view.pager.targetIndex + 1, pagedSpaces.count - 1)) }
  /// KB-034, GS-002: Cmd-Opt-Left and mouse button 3. Stops at the first Space [I], PARITY(NEEDS-RUNTIME-CHECK #78).
  public func previousSpace() { goToSpace(at: max(view.pager.targetIndex - 1, 0)) }

  /// Each Space's selected tab (its last active tab), saved with the window's session (#116).
  public var selectedTabs: [SpaceID: NodeID] { lastActive }

  /// Seeds the last active tabs from a saved session, keeping the pairs whose Space exists and still holds a tab with
  /// that id (a deleted or moved tab falls back to the Space's first tab).
  public func restoreSelections(_ saved: [SpaceID: NodeID]) {
    for (space, tab) in saved where source.space(space) != nil && source.spaceID(containing: tab) == space {
      if case .tab? = source.node(tab) { lastActive[space] = tab }
    }
  }

  /// The tab to show when `space` becomes current: its last active tab (BH-036), else its first tab,
  /// Pinned before Today. PARITY(NEEDS-RUNTIME-CHECK): what Arc shows in a never-visited Space.
  public func tabToRestore(in space: SpaceID) -> NodeID? {
    if let last = lastActive[space], source.spaceID(containing: last) == space { return last }
    return (source.children(of: .pinned(space)) + source.children(of: .today(space)))
      .lazy.compactMap { self.source.firstTab(at: $0) }.first
  }

  private func commit(space id: SpaceID, info: SidebarSpaceInfo, index: Int) {
    guard let page = pages[id] else { return }
    let changed = currentSpace != id
    if changed, let creator = themeCreator, creator.spaceID != id { creator.close(animated: true) }   // #410
    if changed, let old = currentSpace { pages[old]?.outlineController.clearSelection() }   // design 6
    if changed { folderPreview.hide(animated: false) }                              // BH-093: the page left
    // The page leaving the screen ends its folder springs, so no closed folder's rows wait there for its return.
    if changed, let old = currentSpace { pages[old]?.outlineController.folderMotion.settleNow() }
    currentSpace = id
    if changed, tabToRestore(in: id) == nil {
      previous = current
      current = nil
      visible = []
      applyRowStates()
      onEmptySpace?()
    }
    page.outlineController.setRowStates(resolver)
    // BH-065: a collapsed Pinned section bolds the Space title while one of its tabs is shown [I].
    page.setCurrentTabInPinned(current.flatMap { source.section(containing: $0) } == .pinned(page.spaceID))
    view.setCurrent(page: page)
    view.setFlavor(drawnSpace(id)?.theme.flavor ?? info.theme.flavor)
    view.spaceDots.selectedIndex = index
    if changed { onCurrentSpaceChanged?(id) }        // BH-111
  }

  // MARK: New Tab button (GS-035)

  private var newTabHovered = false
  private var newTabFlagsMonitor: Any?

  /// The + button's click: in the GS-035 state (hovered with Cmd held, a URL on the clipboard) it pastes and
  /// goes; otherwise it is the plain New Tab.
  private func newTabClicked() {
    if view.newTabOffersPasteAndGo, let url = clipboardURLProvider?() { onPasteAndGo?(url) } else { onNewTab?() }
  }

  /// The Cmd monitor goes with the controller, not only with the pointer leaving the button.
  isolated deinit {
    if let monitor = newTabFlagsMonitor { NSEvent.removeMonitor(monitor) }
  }

  /// Cmd presses and releases while the pointer rests on the + button toggle its GS-035 state.
  private func newTabHoverChanged(_ hovered: Bool) {
    newTabHovered = hovered
    if hovered, newTabFlagsMonitor == nil {
      newTabFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
        MainActor.assumeIsolated { self?.refreshNewTabButton() }
        return event
      }
    } else if !hovered, let monitor = newTabFlagsMonitor {
      NSEvent.removeMonitor(monitor)
      newTabFlagsMonitor = nil
    }
    refreshNewTabButton()
  }

  private func refreshNewTabButton() {
    updateNewTabButton(hovered: newTabHovered,
                       commandHeld: NSEvent.modifierFlags.contains(.command))
  }

  /// GS-035: the + button offers "Paste and Go" while hovered with Cmd held and a URL on the clipboard.
  func updateNewTabButton(hovered: Bool, commandHeld: Bool) {
    view.newTabOffersPasteAndGo = hovered && commandHeld && clipboardURLProvider?() != nil
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
      view.setFlavor(drawnSpace(id)?.theme.flavor ?? info.theme.flavor)
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
    let currentIndex = currentSpace.flatMap { order.firstIndex(of: $0) }
    view.setPages(order.compactMap { pages[$0] }, index: currentIndex ?? 0)
    if let currentIndex { view.spaceDots.selectedIndex = currentIndex }   // the current Space moved or shifted
    refreshSpaceDetails(notify: notify)
  }

  /// Re-reads every paged Space: live pages (title, flavor), dot titles, cached flavors and the current chrome,
  /// then tells the window once (themes) unless `notify` is false. Called after any Space list or Space field change.
  private func refreshSpaceDetails(notify: Bool = true) {
    let drawn = pagedSpaces.map(drawnSpace)
    for (id, info) in zip(pagedSpaces, drawn) { pages[id]?.refresh(from: info) }
    pagedFlavors = drawn.map { $0?.theme.flavor ?? .light }
    view.spaceDots.titles = pagedSpaces.map { source.space($0)?.title ?? "" }
    view.spaceDots.icons = pagedSpaces.map { source.space($0)?.icon }
    if let id = currentSpace, let info = drawnSpace(id) { setChromeFlavor(info.theme.flavor) }
    noteCurrentTheme()
    themeCreator?.sourceDidChange()
    if notify { onSpacesChanged?(pagedSpaces) }
  }

  /// The sidebar chrome's flavor. While the theme creator is open, a tone flip that is not a live drag (a preset,
  /// adding or removing a colour) cross-fades the sidebar 0.2 s (#410); Reduce Motion flips at once.
  private func setChromeFlavor(_ flavor: ThemeFlavor) {
    if flavor != view.flavor, themeCreator != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
       let layer = view.layer {
      let fade = CATransition()
      fade.type = .fade
      fade.duration = ThemeCreatorMotion.toneFlipDuration
      layer.add(fade, forKey: kCATransition)
    }
    view.setFlavor(flavor)
  }

  /// Sets `themeCrossfadePending` only when the current Space's theme value changed, matched by id so a reorder
  /// (the pager jumps before this runs) does not look like a theme edit.
  private func noteCurrentTheme() {
    var next: [SpaceID: SpaceThemeInfo] = [:]
    next.reserveCapacity(pagedSpaces.count)
    for id in pagedSpaces {
      if let theme = source.space(id)?.theme { next[id] = theme }
    }
    if let current = currentSpace, let before = shownThemes[current], let after = next[current], before != after {
      themeCrossfadePending = true
    }
    shownThemes = next
  }

  @discardableResult
  private func makePage(_ id: SpaceID) -> SpacePageView {
    let page = SpacePageView(source: source, spaceID: id)
    page.outlineController.onActivate = { [weak self] node in self?.activate(node: node) }
    page.outlineController.onClose = { [weak self] node in self?.onClose?(node) }
    page.outlineController.onSeparateSplit = { [weak self] node in self?.onSeparateSplit?(node) }
    page.outlineController.onRemovePane = { [weak self] node in self?.onRemovePane?(node) }
    page.outlineController.onConvertSplit = { [weak self] node in self?.onConvertSplit?(node) }
    page.outlineController.onDuplicateSplit = { [weak self] node in self?.onDuplicateSplit?(node) }
    page.outlineController.onDuplicateIntoSplit = { [weak self] node in self?.onDuplicateIntoSplit?(node) }
    page.outlineController.onMoveToFavorites = { [weak self] node in self?.onMoveToFavorites?(node) }
    page.outlineController.onPinToggle = { [weak self] node in self?.onPinToggle?(node) }
    page.outlineController.onResetPinned = { [weak self] node in self?.onResetPinned?(node) }
    page.outlineController.onReplacePin = { [weak self] node in self?.onReplacePin?(node) }
    page.outlineController.onSeparateFromPinned = { [weak self] node in self?.onSeparateFromPinned?(node) }
    page.outlineController.onPinnedFaviconClick = { [weak self] node, modifiers in
      self?.onPinnedFaviconClick?(node, modifiers)
    }
    page.outlineController.pinnedNavigatedProvider = { [weak self] node in
      self?.pinnedNavigatedProvider?(node) ?? false
    }
    page.outlineController.onMenuAction = { [weak self] action in self?.onMenuAction?(action) }
    page.outlineController.onEmptyAreaDoubleClick = { [weak self] in self?.onEmptyAreaDoubleClick?() }
    page.outlineController.onNodeDragBegan = { [weak self] node in self?.nodeDragBegan(node) }
    page.outlineController.onNodeDragEnded = { [weak self] in self?.nodeDragEnded() }
    let drop = page.outlineController.drop
    drop.onDrop = { [weak self] request in self?.onSidebarDropRequest?(request) ?? false }
    drop.onTextDrop = { [weak self] url, title, placement in
      self?.onSidebarTextDrop?(url, title, placement) ?? false
    }
    drop.onEdgeDwell = { [weak self] step in step > 0 ? self?.nextSpace() : self?.previousSpace() }
    drop.onDragOut = { [weak self] node, point in self?.onSidebarDragOut?(node, point) }
    page.outlineController.faviconProvider = { [weak self] node in self?.favicons[node] }
    page.outlineController.closingProvider = { [weak self] node in self?.closingNodes.contains(node) ?? false }
    page.outlineController.audioProvider = { [weak self] node in self?.audio[node] ?? .silent }
    page.outlineController.loadedProvider = { [weak self] node in self?.loadedNodes.contains(node) ?? false }
    page.outlineController.onFolderHover = { [weak self, weak page] folder, hovered in
      guard let self, page === self.currentPage else { return }
      self.folderPreview.folderHoverChanged(folder, hovered: hovered)
    }
    page.outlineController.onFoldersChanged = { [weak self] in self?.folderPreview.folderStatesChanged() }
    page.onEditTheme = { [weak self] page in self?.openThemeCreator(for: page.spaceID) }
    page.outlineController.setRowStates(resolver)
    if let info = drawnSpace(id) { page.refresh(from: info) }
    pages[id] = page
    return page
  }

  // MARK: Selection and rename (#105)

  /// The current Space page's multi-selection, in display order (BH-028).
  public var selectedNodes: [NodeID] { currentPage?.outlineController.selectedNodes ?? [] }

  /// Opens the rename field on `node` in the current Space page (BH-026). False when that page does not show it.
  @discardableResult
  public func beginRename(node: NodeID) -> Bool {
    currentPage?.outlineController.beginRename(node) ?? false
  }

  // MARK: Folders (#109)

  /// Collapse All Folders / Expand All Folders (BH-097): every folder of every Space page in this window (each window
  /// keeps its own, BH-098). Only the page on screen moves; the others change at once.
  public func setAllFolders(open: Bool) {
    for page in pages.values {
      page.outlineController.setAllFolders(open: open, animated: page === currentPage)
    }
  }

  /// Whether the current Space has a folder (the Collapse / Expand All items' enabled state).
  public var currentSpaceHasFolders: Bool { currentPage?.outlineController.hasFolders ?? false }

  /// This window's Folder Preview (BH-093): a closed folder of the current page shows its tabs on hover.
  private(set) lazy var folderPreview: FolderPreviewController = makeFolderPreview()

  private func makeFolderPreview() -> FolderPreviewController {
    let preview = FolderPreviewController(source: source)
    preview.host = { [weak self] in self?.view.window?.contentView }
    preview.anchor = { [weak self] folder in self?.folderRowFrame(folder) }
    preview.isClosed = { [weak self] folder in
      guard let outline = self?.currentPage?.outlineController else { return false }
      return !outline.isFolderOpen(folder) && outline.row(for: folder) >= 0
    }
    preview.favicon = { [weak self] node, title, url in
      if let image = self?.favicons[node] { return image }
      let scale = self?.view.shellBackingScale ?? 2
      return SidebarGlyphs.letter(for: title, url: url, flavor: self?.currentFlavor ?? .light,
                                  size: SidebarMetrics.faviconSize, scale: scale)
    }
    preview.flavor = { [weak self] in self?.currentFlavor ?? .light }
    preview.onChoose = { [weak self] node in self?.activate(node: node) }
    return preview
  }

  /// The folder row's frame in the window's root view, stretched to the sidebar's right edge.
  private func folderRowFrame(_ folder: NodeID) -> NSRect? {
    guard let outline = currentPage?.outlineController, let host = view.window?.contentView else { return nil }
    let row = outline.row(for: folder)
    guard row >= 0 else { return nil }
    let rect = outline.outlineView.convert(outline.outlineView.rect(ofRow: row), to: host)
    let sidebar = view.convert(view.bounds, to: host)
    return NSRect(x: rect.minX, y: rect.minY, width: max(sidebar.maxX - rect.minX, 0), height: rect.height)
  }

  private var currentFlavor: ThemeFlavor {
    currentSpace.flatMap { drawnSpace($0)?.theme.flavor } ?? .light
  }

  // MARK: Activation

  /// Makes `node` current. A split activates its `preferredPane`, else its first pane; folders and unknown nodes
  /// are ignored. Activating a tab in another Space of this profile switches to that Space.
  public func activate(node: NodeID) {
    if case .folder? = source.node(node) { return }       // folders expand in place, they never activate
    guard let tab = paneToFocus(in: node) ?? source.firstTab(at: node) else { return }
    let space = source.spaceID(containing: tab)
    if let space, space != currentSpace { showSpace(space) }
    if let space { lastActive[space] = tab }
    let loadedNow = loadedNodes.insert(tab).inserted
    let isFavorite = source.section(containing: tab).map {
      if case .favorites = $0 { true } else { false }
    } ?? false
    if isFavorite {
      favoriteLoadOrder.removeAll { $0 == tab }
      favoriteLoadOrder.append(tab)
    }
    if tab != current {
      // Another tab coming forward (a Favorite click, Ctrl-Tab, the command bar) ends a multi-selection, so a later
      // Cmd-W closes the tab on screen rather than rows chosen earlier (design 6, BH-072).
      for page in pages.values { page.outlineController.clearSelection() }
      previous = current
      current = tab
      applyRowStates()                          // the favorites refresh their visible tiles, a newly loaded one too
    } else if loadedNow {
      view.favorites.reload(node: tab)
    }
    onActivate?(tab)
    if isFavorite { unloadOverflowFavorites() }
  }

  /// Clears the previous role without changing the current one: Little Arkt's arrival already faded the old
  /// selection out, so the old row must not pop back to the 32% previous fill when the page lands (#455).
  public func clearPrevious() {
    guard previous != nil else { return }
    previous = nil
    applyRowStates()
  }

  /// One frame of the arrival's room spring. When the current tab is a Favorite, its tile's selection fill fades
  /// with `room` (1 at the start, 0 when the room has opened). The flight's room value is the only clock.
  func fadeCurrentFavoriteSelection(room: Double) {
    if !favoriteFade.captured {
      let node = current.flatMap { source.section(containing: $0) == .favorites(profile: profile) ? $0 : nil }
      favoriteFade = (true, node)
    }
    guard let node = favoriteFade.node else { return }
    let alpha = 1 - CGFloat(min(max(room, 0), 1))
    view.favorites.setSelectionFade(alpha, for: node)
  }

  /// The arrival ended: the tile draws its fill at full opacity again (the selection itself changes with the row
  /// state, on the landing or when the page never arrives).
  func endFavoriteSelectionFade() {
    guard favoriteFade.captured else { return }
    favoriteFade = (false, nil)
    view.favorites.setSelectionFade(1, for: nil)
  }

  /// The window created `node`'s page without activating it (a background pane of a shown split, #156 review).
  public func markLoaded(node: NodeID) {
    if loadedNodes.insert(node).inserted { view.favorites.reload(node: node) }
  }

  /// Rows whose page close is held behind a leave-site prompt (week-3 Decision 11).
  public private(set) var closingNodes: Set<NodeID> = []

  /// Shows or clears a row's closing state: dimmed, without its X, until the close ends either way. Only that row
  /// is reconfigured.
  public func setClosing(_ node: NodeID, _ closing: Bool) {
    let changed = closing ? closingNodes.insert(node).inserted : closingNodes.remove(node) != nil
    guard changed else { return }
    for page in pages.values { page.outlineController.reload(node: node) }
  }

  /// The sound of tabs whose page plays or is muted (#364); a silent tab has no entry.
  public private(set) var audio: [NodeID: TabAudio] = [:]

  /// Shows a row's sound (#364): only that row's audio button changes, in place, and only when the state changed.
  public func setAudio(_ state: TabAudio, for node: NodeID) {
    guard (audio[node] ?? .silent) != state else { return }
    audio[node] = state == .silent ? nil : state
    for page in pages.values { page.outlineController.audioChanged(node: node) }
  }

  /// Forgets a node that no longer has a tab (engine tab closed): its loaded state, any current/previous role, its
  /// closing state and sound, and its favicon only when the node itself is gone from the source.
  public func deactivate(node: NodeID) {
    setClosing(node, false)
    setAudio(.silent, for: node)
    if source.node(node) == nil { favicons[node] = nil }
    favoriteLoadOrder.removeAll { $0 == node }
    let wasLoaded = loadedNodes.remove(node) != nil
    guard node == current || node == previous else {
      if wasLoaded { view.favorites.reload(node: node) }   // a background Favorite drops its X
      return
    }
    if node == current { current = nil }
    if node == previous { previous = nil }
    applyRowStates()
  }

  /// `preferredPane` for a split node, when it names one of that split's panes.
  private func paneToFocus(in node: NodeID) -> NodeID? {
    guard case .split? = source.node(node), let pane = preferredPane?(node),
          source.parent(of: pane) == .split(node) else { return nil }
    return pane
  }

  private func applyRowStates() {
    let states = resolver
    for page in pages.values {
      page.outlineController.setRowStates(states)
      // BH-065: a collapsed Pinned section bolds the Space title while one of its tabs is shown [I].
      page.setCurrentTabInPinned(current.flatMap { source.section(containing: $0) } == .pinned(page.spaceID))
    }
    view.favorites.setRowStates(states)       // refreshes the visible tiles, this one's X included
  }

  // MARK: Sidebar drag and drop (BH-047)

  private func nodeDragBegan(_ id: NodeID) {
    let payload = pages.values.lazy.compactMap { $0.outlineController.drop.sourcePayload }.first
    dragNodes = payload.map(\.nodes) ?? [id]
    folderPreview.hide(animated: false)                                             // BH-093: a drag ends it
    showDropOverlay(for: id)
    onNodeDragBegan?(id)
  }

  private func nodeDragEnded() {
    dragNodes = []
    dropOverlay?.end()
    dropOverlay?.removeFromSuperview()
    dropOverlay = nil
    onNodeDragEnded?()
  }

  /// Covers the Favorites band only, for the drag: the rows below are the page outline's drop target (#104), which
  /// takes a Favorite dropped on the page where its indicator stands. The band resolves through `FavoritesDrop` and
  /// the drop itself is the window's (`onSidebarDrop`).
  private func showDropOverlay(for id: NodeID) {
    let overlay = FavoritesDropOverlayView()
    overlay.onTarget = { [weak self] node, point, band, bounds in
      // Panes stay out: `moveNode` would leave their split with one pane; splits own that path (`addToSplit`).
      guard let self, case .tab? = self.source.node(node) else { return nil }
      if case .split? = self.source.parent(of: node) { return nil }
      return FavoritesDrop.target(at: point, band: band, bounds: bounds,
                                  section: self.source.section(containing: node),
                                  profile: self.profile, currentSpace: self.currentSpace)
    }
    overlay.onDrop = { [weak self] node, location in self?.onSidebarDrop?(node, location) ?? false }
    let band = FavoritesDrop.band(favoritesFrame: view.favorites.frame)
    overlay.frame = NSRect(x: 0, y: band.minY, width: view.bounds.width, height: band.height)
    overlay.autoresizingMask = []
    view.addSubview(overlay, positioned: .above, relativeTo: view.pager)
    overlay.begin(node: id, band: CGRect(x: band.minX, y: 0, width: band.width, height: band.height))
    dropOverlay = overlay
  }

  // MARK: Unloading (BH-049)

  /// After an activation loaded a Favorite past the recency limit, asks the window to unload the least recently
  /// used ones. The current tab, visible panes and held closes never unload. Entries that left Favorites since
  /// they loaded (dropped on the page, moved into a split) are dropped first, so only Favorites are ever closed;
  /// held closes are already on their way out and do not count toward the limit.
  private func unloadOverflowFavorites() {
    favoriteLoadOrder.removeAll { id in
      if case .favorites? = source.section(containing: id) { false } else { true }
    }
    let counted = favoriteLoadOrder.filter { !closingNodes.contains($0) }
    var exempt = visible
    if let current { exempt.insert(current) }
    for id in FavoritesUnloadPolicy.evictions(loadedOrder: counted, exempt: exempt) {
      onFavoriteUnload?(id)
    }
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

  /// Drops cached favicons and loaded state of nodes that left the source. O(cached favicons + loaded nodes), on
  /// structure and Space changes only.
  private func pruneRemovedNodes() {
    for node in favicons.keys where source.node(node) == nil { favicons[node] = nil }
    loadedNodes = loadedNodes.filter { source.node($0) != nil }
    audio = audio.filter { source.node($0.key) != nil }
    favoriteLoadOrder = favoriteLoadOrder.filter { source.node($0) != nil }
  }

  private func apply(_ change: SidebarChange) {
    switch change {
    case .structure(let location):
      pruneRemovedNodes()
      if case .favorites = location {
        if view.favorites.apply(structure: location) { view.needsLayout = true }
      } else {
        for page in pages.values {
          page.outlineController.apply(structure: location)
          if case .pinned = location { page.refreshCollapseAffordance() }
        }
      }
    case .node(let id):
      for page in pages.values { page.outlineController.reload(node: id) }
      view.favorites.reload(node: id)
    case .spaceRemoved:
      pruneRemovedNodes()                           // a removed Space's nodes emit no structure change
      applySpaceChange()
    case .spaceAdded, .spaceMoved, .spaceChanged:
      applySpaceChange()
    }
  }

  /// Settles pages and the current Space first, then tells the window once, so `onSpacesChanged` never sees a nil
  /// current Space after an add or a removed one after a removal. One mutation may report several Space events;
  /// the first brings the pages up to date and the rest only refresh details.
  private func applySpaceChange() {
    let before = pagedSpaces
    if spaces == pagedSpaces {
      refreshSpaceDetails(notify: false)            // same list: a title, theme or other Space field changed
    } else {
      syncPages(notify: false)                      // creates/drops/reorders pages, then the same refresh
    }
    let currentIsShown = currentSpace.map { spaces.contains($0) } ?? false
    if !currentIsShown {
      if let next = neighbour(of: currentSpace, in: before) ?? spaces.first {
        let replacesRemoved = currentSpace != nil
        showSpace(next)
        if replacesRemoved { activateRestoredTabLater(in: next) }
      } else if currentSpace != nil {               // the last Space went away
        currentSpace = nil
        view.setCurrent(page: nil)
      }
    }
    onSpacesChanged?(pagedSpaces)
  }

  /// The Space to show after `removed` left `order`: the first one after it that is still shown, which slides into
  /// its place, else the nearest one before it [I] (PARITY(NEEDS-RUNTIME-CHECK): which Space Arc shows).
  private func neighbour(of removed: SpaceID?, in order: [SpaceID]) -> SpaceID? {
    guard let removed, let index = order.firstIndex(of: removed) else { return nil }
    let shown = Set(spaces)
    return order[(index + 1)...].first { shown.contains($0) } ?? order[..<index].last { shown.contains($0) }
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
