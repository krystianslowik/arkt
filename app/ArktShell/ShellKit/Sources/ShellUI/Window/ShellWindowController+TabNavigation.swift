import AppKit

/// Keyboard tab navigation (#103, design/tab-switcher): the Ctrl-Tab switcher, Cmd-1 ... Cmd-9, next / previous tab
/// in sidebar order, Ctrl-Cmd-Right / Left through recent tabs, and Ctrl-Space (reveal and focus the current tab).
/// None of these shows the sidebar's own motion except the reveal scroll (BH-018).
extension ShellWindowController {
  /// Called once from `init`: the switcher panel joins the root view on top, the window hands it raw events first,
  /// and the outlines hand keyboard focus back to the page.
  func wireTabNavigation() {
    let switcher = tabSwitcher
    rootView.addSubview(switcher.view)
    switcher.currentNode = { [weak self] in self?.currentNode }
    switcher.row = { [weak self] node in self?.switcherRow(for: node) }
    switcher.isAlive = { [weak self] node in self?.isSwitchable(node) ?? false }
    switcher.flavor = { [weak self] in self?.currentFlavor ?? .light }
    switcher.onCommit = { [weak self] node in self?.activateByKeyboard(node) }
    switcher.onClose = { [weak self] node in self?.close(node: node) }
    (window as? ShellWindow)?.eventInterceptor = { [weak self] event in
      guard let self, !self.isShowingOnboarding else { return false }   // the first run covers the browser
      return self.tabSwitcher.handle(event)
    }
    if let current = currentNode { switcher.noteViewed(current) }
  }

  /// The flavor of the Space the window shows (the switcher and the pill follow it, as toasts do).
  private var currentFlavor: ThemeFlavor {
    currentSpace.flatMap { sidebar.space($0)?.theme.flavor } ?? .light
  }

  /// A tab of this window's profile that is still in the sidebar (cheap: no row is built).
  func isSwitchable(_ node: NodeID) -> Bool {
    guard case .tab? = sidebar.node(node) else { return false }
    if let space = sidebar.spaceID(containing: node) {
      return sidebar.space(space)?.profile == sidebarController.profile
    }
    return sidebar.section(containing: node) == .favorites(profile: sidebarController.profile)
  }

  /// A switcher row for a tab of this window's profile; nil for anything else (gone, a folder, another profile).
  func switcherRow(for node: NodeID) -> TabSwitcherRow? {
    guard isSwitchable(node), case .tab(_, let url, let title)? = sidebar.node(node) else { return nil }
    let spaceInfo = sidebar.spaceID(containing: node).flatMap { sidebar.space($0) }
    let favicon = sidebarController.favicons[node]
      ?? SidebarGlyphs.letter(for: title, url: url, flavor: currentFlavor, size: SidebarMetrics.faviconSize,
                              scale: window?.backingScaleFactor ?? 2)
    var isPane = false
    if case .split? = sidebar.parent(of: node) { isPane = true }
    return TabSwitcherRow(node: node, title: title, favicon: favicon, spaceTitle: spaceInfo?.title,
                          spaceColor: spaceInfo?.theme.chipColor, isSplitPane: isPane)
  }

  /// A tab chosen by a keyboard command becomes current and is revealed in the sidebar (BH-018).
  func activateByKeyboard(_ node: NodeID) {
    activate(node: node)
    revealInSidebar(currentNode ?? node)
  }

  /// Scrolls the current Space's outline to `node`'s row (opening folders that hold it) and returns that row. The
  /// whole window is laid out first, not only the page: a pending window resize or a Space switch the command caused
  /// changes the visible height the scroll target is measured against.
  @discardableResult
  func revealInSidebar(_ node: NodeID) -> Int? {
    rootView.layoutSubtreeIfNeeded()
    guard let page = sidebarController.currentPage,
          let row = page.outlineController.expandAncestors(of: node) else { return nil }
    page.layoutSubtreeIfNeeded()
    sidebarReveal.reveal(row: row, in: page, flavor: currentFlavor)
    return row
  }

  /// The sidebar items the keyboard steps through, for this window's profile and current Space.
  func sidebarTabOrder(countingFavorites: Bool) -> SidebarTabOrder {
    SidebarTabOrder(source: sidebar, profile: sidebarController.profile, space: currentSpace,
                    includeFavorites: countingFavorites,
                    collapsedFolders: sidebarController.currentPage?.outlineController.collapsedFolderIDs ?? [])
  }

  // MARK: Menu actions

  /// Cmd-1 ... Cmd-9 (BH-014, BH-015, KB-020, KB-021): the item's tag is the number.
  @objc public func goToSidebarItem(_ sender: Any?) {
    guard let number = (sender as? NSMenuItem)?.tag else { return }
    let order = sidebarTabOrder(countingFavorites: tabNavigationSettings.countsFavorites)
    guard let item = order.item(number: number, settings: tabNavigationSettings) else { return }
    activateByKeyboard(item)
  }

  /// Cmd-Opt-Down (BH-016, KB-028) and its alias Cmd-} (KB-030, PARITY(NEEDS-RUNTIME-CHECK RT-02)).
  @objc public func nextSidebarTab(_ sender: Any?) { stepSidebarTab(forward: true) }
  /// Cmd-Opt-Up (BH-016, KB-029) and its alias Cmd-{ (KB-030, PARITY(NEEDS-RUNTIME-CHECK RT-02)).
  @objc public func previousSidebarTab(_ sender: Any?) { stepSidebarTab(forward: false) }

  private func stepSidebarTab(forward: Bool) {
    let order = sidebarTabOrder(countingFavorites: true)
    guard let item = order.neighbour(of: currentNode, forward: forward) else { return }
    activateByKeyboard(item)
  }

  /// Ctrl-Cmd-Right (BH-013, KB-026): back through previously viewed tabs, no overlay, wrapping.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-01).
  @objc public func cycleRecentTabForward(_ sender: Any?) { cycleRecentTab(forward: true) }
  /// Ctrl-Cmd-Left (BH-013, KB-027). PARITY(NEEDS-RUNTIME-CHECK RT-01).
  @objc public func cycleRecentTabBackward(_ sender: Any?) { cycleRecentTab(forward: false) }

  private func cycleRecentTab(forward: Bool) {
    tabSwitcher.sourceDidChange()
    guard let target = tabSwitcher.cycleTarget(forward: forward) else { return }
    activateByKeyboard(target)
  }

  /// Ctrl-Space (BH-019, KB-036): reveals the current tab in the sidebar (opening a closed folder) and moves keyboard
  /// focus to its row, drawn with the system focus ring. A hidden sidebar is shown first [I]. Up / Down, Return and
  /// Esc then work as `SidebarOutlineView` describes (BH-020, PARITY(NEEDS-RUNTIME-CHECK RT-13)). A Favorite current
  /// tab puts the focus on the first row: the Favorites grid has no keyboard focus yet.
  @objc public func revealCurrentTab(_ sender: Any?) {
    guard let page = sidebarController.currentPage else { return }
    if !rootView.sidebarVisible { rootView.sidebarVisible = true }
    rootView.layoutSubtreeIfNeeded()
    let controller = page.outlineController
    let row = currentNode.flatMap { revealInSidebar($0) }
      ?? (0..<page.outlineView.numberOfRows).first { controller.isKeyboardFocusable(row: $0) }
    guard let row else { return }
    controller.onKeyboardFocusExit = { [weak self] in self?.returnFocusToPage() }
    page.outlineView.onKeyboardFocusMoved = { [weak self, weak page] row in
      guard let self, let page else { return }
      self.sidebarReveal.reveal(row: row, in: page, flavor: self.currentFlavor)
    }
    controller.focusKeyboard(on: row)
    guard window?.makeFirstResponder(page.outlineView) == true, window?.firstResponder === page.outlineView else {
      page.outlineView.keyboardFocusRow = nil
      return
    }
    let title = currentNode.flatMap { node -> String? in
      if case .tab(_, _, let title)? = sidebar.node(node) { return title }
      return nil
    }
    NSAccessibility.post(element: page.outlineView, notification: .announcementRequested, userInfo: [
      .announcement: ["Sidebar", title].compactMap { $0 }.joined(separator: ", "),
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }

  /// Return or Esc in the sidebar: the current page takes keyboard focus again.
  func returnFocusToPage() {
    guard let window else { return }
    if let tab = currentTab, let page = engine.contentView(for: tab) {
      window.makeFirstResponder(page)
    } else {
      window.makeFirstResponder(nil)
    }
  }
}

extension SpaceThemeInfo {
  /// The Space's color for a chip (the switcher's dot): its most saturated gradient stop, opaque. Nil without stops.
  var chipColor: RGBA? {
    baseColors.max { saturation($0) < saturation($1) }.map {
      RGBA(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1, space: $0.space)
    }
  }

  private func saturation(_ color: RGBA) -> Double {
    let high = max(color.red, color.green, color.blue)
    let low = min(color.red, color.green, color.blue)
    return high == 0 ? 0 : (high - low) / high
  }
}
