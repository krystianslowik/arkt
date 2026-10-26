import AppKit

/// The Archive window (E5c, #111; Window > Show Archive, unbound by default, KB-043; design/archive-search): a utility
/// window with the title, the search field and the filter button in one unified title bar, filter chips, the
/// one-time education banner, archived items newest first in sidebar-style rows that load further pages as the list
/// scrolls, Clear Archive at the footer's leading edge and Restore (the one primary) at its trailing edge.
///
/// Searching and filtering run in the data source's store, off the main actor; the window only awaits pages and
/// reloads the table, and a row never decodes or measures more than its own title. While on screen it refreshes when
/// the data source reports a change (an entry archived or its archive write landed, #88). Every opening starts
/// unfiltered with an empty search. Not a hot path, but AppKit and Core Animation only, never a SwiftUI list.
@MainActor
public final class ArchiveWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
  NSSearchFieldDelegate {
  /// The size of the area below the title bar, as before the unified bar (the frame adds the 28 pt title bar).
  static let contentSize = NSSize(width: 600, height: 480)
  static let minimumContentSize = NSSize(width: 360, height: 240)

  private let archiveTable = ArchiveTableView(frame: .zero)
  public var tableView: NSTableView { archiveTable }
  let restorePill = ArchivePillButton(style: .primary, title: "Restore")
  public var restoreButton: NSButton { restorePill }
  /// "42 items", "3 results", "3 of 42 items", plus unreadable items or the load failure.
  public let footerLabel = NSTextField(labelWithString: "")
  let searchField = ArchiveSearchField(frame: .zero)
  let filterButton = ArchiveFilterButton(frame: .zero)
  let clearLink = ArchiveLinkButton(style: .destructive, title: "Clear Archive...")
  let chipStrip = ArchiveChipStrip(frame: .zero)
  let emptyState = ArchiveEmptyStateView(frame: .zero)
  let titleLabel = NSTextField(labelWithString: "Archive")
  private(set) var bannerView: ArchiveBannerView?
  private(set) var clearSheet: ArchiveClearSheet?
  /// The window's toasts (the cleared confirmation), 16 pt above the footer.
  public let toasts = ToastPresenter()
  let toastView = ToastView(frame: .zero)

  /// The rows on screen, newest first.
  public private(set) var rows: [ArchiveRow] = []
  /// The table's lines: rows, the tabs shown under opened folders, and the auto-load row.
  private(set) var entries: [ArchiveListEntry] = []
  /// The search and filters in effect.
  public private(set) var query = ArchiveQuery()
  /// The load started by `show()`, a search, a filter or auto-load; tests await it.
  public private(set) var pendingLoad: Task<Void, Never>?
  /// More pages may exist beyond `rows`.
  public private(set) var mayHaveMore = false
  /// The next page is loading (the auto-load row shows).
  public private(set) var isLoadingMore = false
  /// The debounce between a keystroke and the search it starts (design section 4).
  public var searchDebounce: Duration = .milliseconds(150)
  /// Open Settings in the education banner (Settings > Spaces); the link is hidden while nil.
  public var onOpenSettings: (@MainActor () -> Void)?

  private let dataSource: any ArchiveListDataSource
  private let listField = ArchiveListFieldView(frame: .zero)
  private let scrollView = NSScrollView(frame: .zero)
  private let dragView = ArchiveDragView(frame: .zero)
  private var total: Int?
  private var matching: Int?
  private var unreadable = 0
  private var failed = false
  private var favicons: [UUID: NSImage] = [:]
  private var requestedFavicons: Set<UUID> = []
  private var searchTask: Task<Void, Never>?
  /// Bumped by every load that replaces the list (search, filter, reload), so an older auto-load landing late is
  /// dropped instead of replacing newer rows.
  private var listGeneration = 0

  public init(dataSource: any ArchiveListDataSource) {
    self.dataSource = dataSource
    let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    let frame = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: style)
    let window = ArchiveWindow(contentRect: NSRect(origin: .zero, size: frame.size),
                               styleMask: style.union(.fullSizeContentView), backing: .buffered, defer: true)
    window.title = "Archive"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.minSize = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize),
                                        styleMask: style).size
    window.setAccessibilityIdentifier(AXID.Archive.window)
    super.init(window: window)
    window.onFind = { [weak self] in self?.focusSearch() }
    buildContent(in: window)
    // Accessibility rows read `rows`, not row views: one announcement per item (title, then place, date and reason,
    // #91), and nothing is built for a row that was never laid out.
    archiveTable.axProxyRows.content = { [weak self] row in self?.accessibilityContent(row: row) }
    dataSource.onChange = { [weak self] in self?.dataSourceDidChange() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Showing and loading

  /// Shows (or fronts) the window, starting unfiltered with an empty search, and loads the first page (and the
  /// education banner, when it is due) again. Focus starts on the list: the Archive is a restore surface first.
  public func show() {
    let wasVisible = window?.isVisible == true
    if !wasVisible { resetQuery() }
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    if !wasVisible { window?.makeFirstResponder(tableView) }
    pendingLoad = Task { [weak self] in
      guard let self else { return }
      if self.bannerView == nil, let banner = await self.dataSource.educationBanner() { self.installBanner(banner) }
      await self.reload()
    }
  }

  /// Loads the first page with the current query, starting over. Overlapping loads are ordered by the data source
  /// (see `ArchiveListDataSource`), so every page that comes back is applied.
  public func reload() async {
    listGeneration += 1
    isLoadingMore = false
    apply(await dataSource.loadPage())
  }

  /// Loads the next page (auto-load calls it as the list nears its end).
  public func loadMore() async {
    let generation = listGeneration
    let page = await dataSource.loadMore()
    guard generation == listGeneration else { return }
    isLoadingMore = false
    apply(page)
  }

  /// Escape: clears a non-empty search, else closes the window like its close button.
  public override func cancelOperation(_ sender: Any?) {
    if !searchField.stringValue.isEmpty {
      clearSearch()
    } else {
      window?.performClose(sender)
    }
  }

  /// The list changed elsewhere: on screen, read it again at the loaded depth; hidden, nothing (`show()` reloads).
  private func dataSourceDidChange() {
    guard window?.isVisible == true else { return }
    let generation = listGeneration
    pendingLoad = Task { [weak self] in
      guard let self else { return }
      let page = await self.dataSource.refresh()
      guard generation == self.listGeneration else { return }
      self.apply(page)
    }
  }

  // MARK: Search

  /// Cmd-F: focus the search field.
  func focusSearch() {
    window?.makeFirstResponder(searchField)
  }

  /// Sets the search text, as typing does, and searches after the debounce. Tests await `pendingLoad`.
  public func setSearchText(_ text: String) {
    if searchField.stringValue != text { searchField.stringValue = text }
    scheduleSearch()
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    let text = searchField.stringValue
    let debounce = searchDebounce
    let task = Task { [weak self] in
      if debounce > .zero {
        do { try await Task.sleep(for: debounce) } catch { return }
      }
      guard let self, !Task.isCancelled else { return }
      await self.run(ArchiveQuery(text: text, space: self.query.space, closeType: self.query.closeType))
    }
    searchTask = task
    pendingLoad = task
  }

  private func clearSearch() {
    searchTask?.cancel()
    searchField.stringValue = ""
    pendingLoad = Task { [weak self] in
      guard let self else { return }
      await self.run(ArchiveQuery(space: self.query.space, closeType: self.query.closeType))
    }
  }

  /// Applies `query` and loads its first page; the list starts at the top.
  private func run(_ newQuery: ArchiveQuery) async {
    query = newQuery
    dataSource.setQuery(newQuery)
    updateChips(animated: true)
    await reload()
    tableView.scrollRowToVisible(0)
  }

  private func resetQuery() {
    searchTask?.cancel()
    searchField.stringValue = ""
    query = ArchiveQuery()
    dataSource.setQuery(query)
    updateChips(animated: false)
  }

  public func controlTextDidChange(_ obj: Notification) {
    guard (obj.object as? NSSearchField) === searchField else { return }
    scheduleSearch()
  }

  /// In the search field: Escape clears a query (then closes, with an empty one); Down moves to the first row.
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === searchField else { return false }
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      cancelOperation(nil)
      return true
    case #selector(NSResponder.moveDown(_:)):
      window?.makeFirstResponder(tableView)
      if archiveTable.selectedRow < 0 { archiveTable.moveSelection(by: 1) }
      return true
    case #selector(NSResponder.insertNewline(_:)):
      return true
    default:
      return false
    }
  }

  // MARK: Filters

  /// Sets the Space filter (nil: Everywhere) and reloads.
  public func setSpaceFilter(_ space: ArchiveSpaceFilter?) {
    var next = query
    next.space = space
    startFilterLoad(next)
  }

  /// Sets the close-type filter (nil: Closed and Auto Archived) and reloads.
  public func setCloseTypeFilter(_ closeType: ArchiveCloseType?) {
    var next = query
    next.closeType = closeType
    startFilterLoad(next)
  }

  @objc func clearFiltersPressed(_ sender: Any?) {
    startFilterLoad(ArchiveQuery(text: query.text))
  }

  private func startFilterLoad(_ next: ArchiveQuery) {
    guard next != query else { return }
    pendingLoad = Task { [weak self] in await self?.run(next) }
  }

  /// The filter menu (design section 5): a Space section (Everywhere, each Space with its color dot, Little Arkt)
  /// and a Close Type section, one checkmark per section. Native items only.
  func makeFilterMenu() -> NSMenu {
    let menu = NSMenu(title: "Filter")
    menu.autoenablesItems = false
    let flavor = window?.contentView?.archiveFlavor ?? .light
    let scale = window?.backingScaleFactor ?? 2
    menu.addItem(.sectionHeader(title: "Space"))
    menu.addItem(filterItem("Everywhere", checked: query.space == nil) { $0.setSpaceFilter(nil) })
    for option in dataSource.spaceOptions {
      let item = filterItem(option.title, checked: query.space == .space(option.id)) {
        $0.setSpaceFilter(.space(option.id))
      }
      item.image = ArchiveGlyphs.dot(option.color ?? ShellTokens.sidebarForeground.resolve(flavor), size: 10,
                                     scale: scale)
      menu.addItem(item)
    }
    let little = filterItem("Little Arkt", checked: query.space == .littleArkt) { $0.setSpaceFilter(.littleArkt) }
    let glyph = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
    glyph?.isTemplate = true
    little.image = glyph
    menu.addItem(little)
    menu.addItem(.separator())
    menu.addItem(.sectionHeader(title: "Close Type"))
    menu.addItem(filterItem("Closed and Auto Archived", checked: query.closeType == nil) {
      $0.setCloseTypeFilter(nil)
    })
    for type in ArchiveCloseType.allCases {
      menu.addItem(filterItem(type.title, checked: query.closeType == type) { $0.setCloseTypeFilter(type) })
    }
    return menu
  }

  private func filterItem(_ title: String, checked: Bool,
                          _ choose: @escaping @MainActor (ArchiveWindowController) -> Void) -> NSMenuItem {
    let item = ArchiveFilterMenuItem(title: title, action: #selector(filterMenuItemChosen(_:)), keyEquivalent: "")
    item.target = self
    item.state = checked ? .on : .off
    item.choose = choose
    return item
  }

  @objc private func filterMenuItemChosen(_ sender: NSMenuItem) {
    (sender as? ArchiveFilterMenuItem)?.choose?(self)
  }

  @objc func filterButtonPressed(_ sender: Any?) {
    let menu = makeFilterMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: filterButton.bounds.height + 4), in: filterButton)
  }

  /// One chip per active filter, plus Clear Filters; the strip fades in and out (layout never animates).
  private func updateChips(animated: Bool) {
    var chips: [ArchiveChipView] = []
    switch query.space {
    case .space(let id)?:
      let option = dataSource.spaceOptions.first { $0.id == id }
      let title = option?.title ?? "Space"
      let chip = ArchiveChipView(name: title, mark: .dot(option?.color), identifier: AXID.Archive.chip(title))
      chip.onRemove = { [weak self] in self?.setSpaceFilter(nil) }
      chips.append(chip)
    case .littleArkt?:
      let chip = ArchiveChipView(name: "Little Arkt", mark: .symbol("macwindow"),
                                 identifier: AXID.Archive.chip("Little Arkt"))
      chip.onRemove = { [weak self] in self?.setSpaceFilter(nil) }
      chips.append(chip)
    case nil:
      break
    }
    if let type = query.closeType {
      let glyph = type == .closed ? "xmark.square" : "clock.arrow.circlepath"
      let chip = ArchiveChipView(name: type.title, mark: .symbol(glyph), identifier: AXID.Archive.chip(type.title))
      chip.onRemove = { [weak self] in self?.setCloseTypeFilter(nil) }
      chips.append(chip)
    }
    chipStrip.setChips(chips)
    chipStrip.setShown(!chips.isEmpty, animated: animated)
    filterButton.isActive = query.hasFilters
    let count = (query.space == nil ? 0 : 1) + (query.closeType == nil ? 0 : 1)
    filterButton.setArchiveAccessibilityValue(count == 0 ? nil : "\(count) \(count == 1 ? "filter" : "filters") active")
    window?.contentView?.needsLayout = true
    updateKeyViewLoop()
  }

  // MARK: Applying pages

  /// Applies a page; the selected row stays selected when it is still listed.
  private func apply(_ page: ArchiveListPage) {
    let selected = selectedItemIndex.map { rows[$0].id }
    rows = page.rows
    mayHaveMore = page.mayHaveMore
    total = page.total
    matching = page.matching
    unreadable = page.unreadable
    failed = page.failed
    rebuildEntries()
    tableView.reloadData()
    if let selected, let index = entries.firstIndex(where: { $0.itemIndex.map { rows[$0].id } == selected }) {
      tableView.selectRowIndexes([index], byExtendingSelection: false)
    }
    updateFooter()
    updateEmptyState()
    updateRestoreButton()
    loadFavicons()
    checkAutoLoad()
  }

  private func rebuildEntries() {
    var built: [ArchiveListEntry] = []
    for (index, row) in rows.enumerated() {
      built.append(.item(index))
      for child in row.matchedChildren.indices { built.append(.child(item: index, child: child)) }
    }
    if isLoadingMore { built.append(.loading) }
    entries = built
  }

  /// The footer's count, the unreadable note or the failure.
  private func updateFooter() {
    var text: String
    if failed {
      text = "The Archive could not be read."
    } else {
      text = Self.countText(query: query, shown: rows.count, total: total, matching: matching)
      if unreadable > 0 {
        let note = "\(unreadable) \(unreadable == 1 ? "item" : "items") could not be read"
        text = text.isEmpty ? note : "\(text), \(note)"
      }
    }
    if footerLabel.stringValue != text {
      footerLabel.stringValue = text
      footerLabel.setAccessibilityValue(text)
      if !text.isEmpty {
        NSAccessibility.post(element: footerLabel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
      }
    }
    footerLabel.isHidden = text.isEmpty
    clearLink.isEnabled = (total ?? rows.count) > 0
    window?.contentView?.needsLayout = true
  }

  /// "42 items" unfiltered, "3 results" while searching, "3 of 42 items" while only filters narrow the list; empty
  /// when nothing matches.
  static func countText(query: ArchiveQuery, shown: Int, total: Int?, matching: Int?) -> String {
    let matches = matching ?? shown
    let all = total ?? shown
    func items(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }
    if query.hasText { return matches == 0 ? "" : (matches == 1 ? "1 result" : "\(matches) results") }
    if query.hasFilters { return matches == 0 ? "" : "\(matches) of \(items(all))" }
    return all == 0 ? "" : items(all)
  }

  private func updateEmptyState() {
    let empty = rows.isEmpty && !failed
    emptyState.isHidden = !empty
    guard empty else { return }
    if query.hasText {
      emptyState.show(title: "No Results",
                      detail: "Nothing in the Archive matches \u{201C}\(query.text.trimmingCharacters(in: .whitespaces))\u{201D}.",
                      symbol: "magnifyingglass")
    } else if query.hasFilters {
      emptyState.show(title: "No Results", detail: "Nothing in the Archive matches these filters.",
                      symbol: "line.3.horizontal.decrease")
    } else {
      emptyState.show(title: "No Archived Tabs", detail: "Tabs you close appear here, ready to restore.",
                      symbol: "archivebox")
    }
  }

  // MARK: Auto-load

  /// Starts the next page when the list shows a row within 10 of its end (design section 11), unless one is loading.
  func checkAutoLoad() {
    guard mayHaveMore, !isLoadingMore, !rows.isEmpty, window?.isVisible == true else { return }
    let visible = tableView.rows(in: tableView.visibleRect)
    let lastVisible = visible.length > 0 ? visible.location + visible.length - 1 : -1
    let lastSelected = tableView.selectedRow
    guard max(lastVisible, lastSelected) >= entries.count - 1 - ArchiveMetrics.autoLoadDistance else { return }
    isLoadingMore = true
    entries.append(.loading)
    tableView.insertRows(at: [entries.count - 1], withAnimation: [])
    pendingLoad = Task { [weak self] in await self?.loadMore() }
  }

  @objc private func listDidScroll(_ notification: Notification) {
    checkAutoLoad()
  }

  // MARK: Favicons

  /// Asks the data source once per id for stored favicons of the rows (and the tabs under opened folders); rows
  /// show their letter tile until an image arrives, then only the visible rows reload.
  private func loadFavicons() {
    var wanted: Set<UUID> = []
    for row in rows {
      if case .tab = row.kind, !requestedFavicons.contains(row.id) { wanted.insert(row.id) }
      for child in row.matchedChildren where !requestedFavicons.contains(child.id) { wanted.insert(child.id) }
    }
    guard !wanted.isEmpty else { return }
    requestedFavicons.formUnion(wanted)
    Task { [weak self] in
      guard let self else { return }
      let loaded = await self.dataSource.favicons(for: wanted)
      guard !loaded.isEmpty else { return }
      for (id, data) in loaded { self.favicons[id] = NSImage(data: data) }
      let visible = self.tableView.rows(in: self.tableView.visibleRect)
      guard visible.length > 0 else { return }
      self.tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<visible.location + visible.length),
                                columnIndexes: [0])
    }
  }

  // MARK: Restore

  /// The Restore button and Return: restores the selected row.
  @objc public func restoreSelected(_ sender: Any?) {
    restore(row: tableView.selectedRow)
  }

  /// Double-click: the clicked row; without a mouse event (keyboard, tests), the selected row.
  @objc func rowDoubleClicked(_ sender: Any?) {
    let isMouse = NSApp.currentEvent.map { [.leftMouseDown, .leftMouseUp].contains($0.type) } ?? false
    restore(row: tableView.clickedRow >= 0 ? tableView.clickedRow : (isMouse ? -1 : tableView.selectedRow))
  }

  private var selectedItemIndex: Int? {
    let row = tableView.selectedRow
    return entries.indices.contains(row) ? entries[row].itemIndex : nil
  }

  private func restore(row: Int) {
    guard dataSource.canRestore, entries.indices.contains(row), let index = entries[row].itemIndex else { return }
    guard dataSource.restore(rows[index].id) else { return }
    let childCount = rows[index].matchedChildren.count
    rows.remove(at: index)
    total = total.map { max(0, $0 - 1) }
    matching = matching.map { max(0, $0 - 1) }
    rebuildEntries()
    tableView.removeRows(at: IndexSet(integersIn: row...(row + childCount)), withAnimation: [])
    updateFooter()
    updateEmptyState()
    updateRestoreButton()
  }

  private func updateRestoreButton() {
    restorePill.isEnabled = dataSource.canRestore && selectedItemIndex != nil
  }

  // MARK: Clear Archive

  /// Clear Archive (BH-087): asks first in a sheet; on Clear Archive, empties the archive and confirms with a toast.
  public func confirmClearArchive() {
    guard clearSheet == nil, let window else { return }
    let sheet = ArchiveClearSheet(count: total ?? rows.count, hiddenByFilters: query.hasText || query.hasFilters)
    sheet.onFinish = { [weak self] confirmed in
      guard let self else { return }
      self.clearSheet = nil
      guard confirmed else { return }
      self.pendingLoad = Task { [weak self] in await self?.clearArchive() }
    }
    clearSheet = sheet
    sheet.begin(on: window)
  }

  @objc func clearLinkPressed(_ sender: Any?) { confirmClearArchive() }

  private func clearArchive() async {
    let cleared = await dataSource.clearArchive()
    favicons = [:]
    requestedFavicons = []
    await reload()
    toasts.show(Toast(text: cleared ? "The Archive has been cleared." : "The Archive could not be cleared."))
  }

  // MARK: Banner

  private func installBanner(_ banner: ArchiveBanner) {
    let view = ArchiveBannerView(banner: banner, showsSettings: onOpenSettings != nil)
    view.gotIt.target = self
    view.gotIt.action = #selector(bannerGotIt(_:))
    view.openSettings.target = self
    view.openSettings.action = #selector(bannerOpenSettings(_:))
    window?.contentView?.addSubview(view)
    bannerView = view
    window?.contentView?.needsLayout = true
    updateKeyViewLoop()
    NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
      .announcement: "\(banner.headline) \(banner.detail)",
      .priority: NSAccessibilityPriorityLevel.medium.rawValue,
    ])
  }

  @objc func bannerGotIt(_ sender: Any?) { dismissBanner() }

  @objc func bannerOpenSettings(_ sender: Any?) {
    dismissBanner()
    onOpenSettings?()
  }

  private func dismissBanner() {
    dataSource.dismissEducationBanner()
    bannerView?.removeFromSuperview()
    bannerView = nil
    window?.contentView?.needsLayout = true
    updateKeyViewLoop()
    window?.makeFirstResponder(tableView)
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

  public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    entries.indices.contains(row) && entries[row] == .loading
      ? ArchiveMetrics.loadingRowHeight + (ArchiveMetrics.rowPitch - ArchiveMetrics.rowHeight)
      : ArchiveMetrics.rowPitch
  }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard entries.indices.contains(row) else { return nil }
    let scale = window?.backingScaleFactor ?? 2
    switch entries[row] {
    case .loading:
      let cell = tableView.makeView(withIdentifier: ArchiveLoadingCellView.identifier, owner: self)
        as? ArchiveLoadingCellView ?? ArchiveLoadingCellView()
      cell.start()
      return cell
    case .item(let index):
      let cell = rowCell(in: tableView)
      let item = rows[index]
      cell.show(item, query: query.text, favicon: favicons[item.id], scale: scale)
      return cell
    case .child(let index, let child):
      let cell = rowCell(in: tableView)
      let parent = rows[index]
      let tab = parent.matchedChildren[child]
      cell.showChild(tab, parentTitle: parent.title, query: query.text, favicon: favicons[tab.id], scale: scale)
      return cell
    }
  }

  private func rowCell(in tableView: NSTableView) -> ArchiveRowCellView {
    tableView.makeView(withIdentifier: ArchiveRowCellView.identifier, owner: self) as? ArchiveRowCellView
      ?? ArchiveRowCellView()
  }

  public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = tableView.makeView(withIdentifier: ArchiveRowView.identifier, owner: self) as? ArchiveRowView
      ?? ArchiveRowView(frame: .zero)
    rowView.isInteractive = entries.indices.contains(row) && entries[row].itemIndex != nil
    rowView.isHovered = archiveTable.hoveredRow == row
    if let content = accessibilityContent(row: row) { rowView.setAccessibilityLabel(content.label) }
    return rowView
  }

  public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    entries.indices.contains(row) && entries[row].itemIndex != nil
  }

  public func tableViewSelectionDidChange(_ notification: Notification) {
    updateRestoreButton()
    checkAutoLoad()
  }

  /// One proxy row per table row: an item reads its title, then its place, date and reason (and a folder's tab
  /// count); a tab under an opened folder reads "in <folder>"; the auto-load row reads "Loading more".
  private func accessibilityContent(row: Int) -> AXProxyRowContent? {
    guard entries.indices.contains(row) else { return nil }
    switch entries[row] {
    case .item(let index):
      let item = rows[index]
      var value = "\(item.detail), \(item.reason)"
      if case .folder(let count) = item.kind { value += ", \(count) \(count == 1 ? "tab" : "tabs")" }
      return AXProxyRowContent(identifier: AXID.Archive.row, label: item.title, value: value)
    case .child(let index, let child):
      let parent = rows[index]
      return AXProxyRowContent(identifier: AXID.Archive.row, label: parent.matchedChildren[child].title,
                               value: "in \(parent.title)")
    case .loading:
      return AXProxyRowContent(identifier: AXID.Archive.row, label: "Loading more")
    }
  }

  // MARK: Layout

  private func buildContent(in window: NSWindow) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = ArchiveMetrics.rowPitch
    tableView.intercellSpacing = .zero
    tableView.usesAutomaticRowHeights = false
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.style = .plain
    tableView.backgroundColor = .clear
    tableView.selectionHighlightStyle = .regular
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(rowDoubleClicked(_:))
    archiveTable.isSelectableRow = { [weak self] row in
      guard let self, self.entries.indices.contains(row) else { return false }
      return self.entries[row].itemIndex != nil
    }
    archiveTable.onReturn = { [weak self] in self?.restoreSelected(nil) }

    let frame = NSRect(origin: .zero, size: window.frame.size)
    let content = ArchiveContentView(frame: frame, table: archiveTable, scrollView: scrollView)
    content.autoresizingMask = [.width, .height]
    content.onLayout = { [weak self] in self?.layoutContent() }
    content.onAppearanceChange = { [weak self] in self?.appearanceDidChange() }

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = tableView
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(listDidScroll(_:)),
                                           name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.setAccessibilityElement(false)
    titleLabel.cell?.setAccessibilityElement(false)

    searchField.delegate = self
    searchField.setAccessibilityIdentifier(AXID.Archive.search)
    searchField.cell?.setAccessibilityIdentifier(AXID.Archive.search)
    searchField.setArchiveAccessibilityLabel("Search Archive")

    filterButton.target = self
    filterButton.action = #selector(filterButtonPressed(_:))
    filterButton.setAccessibilityIdentifierWithCell(AXID.Archive.filter)
    filterButton.setArchiveAccessibilityLabel("Filter")

    chipStrip.clearFilters.target = self
    chipStrip.clearFilters.action = #selector(clearFiltersPressed(_:))
    chipStrip.clearFilters.setAccessibilityIdentifierWithCell(AXID.Archive.clearFilters)
    chipStrip.setShown(false, animated: false)

    restorePill.target = self
    restorePill.action = #selector(restoreSelected(_:))
    restorePill.isEnabled = false
    restorePill.setAccessibilityIdentifierWithCell(AXID.Archive.restore)

    clearLink.target = self
    clearLink.action = #selector(clearLinkPressed(_:))
    clearLink.isEnabled = false
    clearLink.setAccessibilityIdentifierWithCell(AXID.Archive.clear)

    footerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    footerLabel.alignment = .right
    footerLabel.lineBreakMode = .byTruncatingHead
    footerLabel.isHidden = true
    footerLabel.setAccessibilityIdentifierWithCell(AXID.Archive.footer)

    emptyState.isHidden = true
    toastView.presenter = toasts
    toasts.view = toastView

    for view in [dragView, titleLabel, searchField, filterButton, chipStrip, listField, scrollView, emptyState,
                 clearLink, footerLabel, restorePill, toastView] as [NSView] {
      content.addSubview(view)
    }
    window.contentView = content
    window.autorecalculatesKeyViewLoop = false
    window.initialFirstResponder = tableView
    appearanceDidChange()
    updateKeyViewLoop()
    window.center()
  }

  private func appearanceDidChange() {
    guard let content = window?.contentView else { return }
    let flavor = content.archiveFlavor
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    footerLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    toastView.flavor = flavor
    searchField.restyle()
    tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<entries.count), columnIndexes: [0])
  }

  /// Tab cycles the search field, the filter button, the chips (when shown), the list, Clear Archive and Restore.
  private func updateKeyViewLoop() {
    var loop: [NSView] = [searchField, filterButton]
    if !chipStrip.isHidden {
      loop += chipStrip.chips.map(\.removeButton)
      loop.append(chipStrip.clearFilters)
    }
    if let bannerView {
      loop.append(bannerView.gotIt)
      if !bannerView.openSettings.isHidden { loop.append(bannerView.openSettings) }
    }
    loop += [tableView, clearLink, restorePill]
    for (index, view) in loop.enumerated() { view.nextKeyView = loop[(index + 1) % loop.count] }
  }

  private func layoutContent() {
    guard let content = window?.contentView else { return }
    let bounds = content.bounds
    let width = bounds.width
    let height = bounds.height
    let bar = ArchiveMetrics.barHeight
    dragView.frame = bounds
    (window as? ArchiveWindow)?.layoutTrafficLights()

    titleLabel.sizeToFit()
    titleLabel.frame.origin = NSPoint(x: ArchiveMetrics.titleLeading,
                                      y: ((bar - titleLabel.frame.height) / 2).rounded())
    let buttonSize = ArchiveMetrics.filterButtonSize
    filterButton.frame = NSRect(x: width - ArchiveMetrics.filterButtonTrailing - buttonSize,
                                y: ((bar - buttonSize) / 2).rounded(), width: buttonSize, height: buttonSize)
    let fieldX = titleLabel.frame.maxX + ArchiveMetrics.titleToField
    searchField.frame = NSRect(x: fieldX, y: ((bar - ArchiveMetrics.fieldHeight) / 2).rounded(),
                               width: max(0, filterButton.frame.minX - ArchiveMetrics.fieldToFilterButton - fieldX),
                               height: ArchiveMetrics.fieldHeight)

    var top = bar
    let side = ArchiveMetrics.sideMargin
    if !chipStrip.isHidden {
      chipStrip.frame = NSRect(x: side, y: top, width: width - 2 * side, height: ArchiveMetrics.chipHeight)
      top += ArchiveMetrics.chipHeight + ArchiveMetrics.chipBelow
    }
    if let bannerView {
      let bannerHeight = bannerView.height(forWidth: width - 2 * side)
      bannerView.frame = NSRect(x: side, y: top, width: width - 2 * side, height: bannerHeight)
      top += bannerHeight + ArchiveMetrics.bannerBelow
    }
    let footerTop = height - ArchiveMetrics.footerHeight
    listField.frame = NSRect(x: ArchiveMetrics.listInset, y: top, width: width - 2 * ArchiveMetrics.listInset,
                             height: max(0, footerTop - top))
    scrollView.frame = listField.frame.insetBy(dx: ArchiveMetrics.rowInset, dy: ArchiveMetrics.listPaddingY)
    emptyState.frame = listField.frame

    clearLink.sizeToFit()
    clearLink.frame.origin = NSPoint(x: ArchiveMetrics.footerLeading,
                                     y: footerTop + ((ArchiveMetrics.footerHeight - clearLink.frame.height) / 2).rounded())
    let restoreWidth = restorePill.intrinsicContentSize.width
    restorePill.frame = NSRect(x: width - ArchiveMetrics.footerTrailing - restoreWidth,
                               y: footerTop + ((ArchiveMetrics.footerHeight - ArchiveMetrics.pillHeight) / 2).rounded(),
                               width: restoreWidth, height: ArchiveMetrics.pillHeight)
    let labelHeight = ceil(footerLabel.intrinsicContentSize.height)
    let labelX = clearLink.frame.maxX + 12
    footerLabel.frame = NSRect(x: labelX, y: footerTop + ((ArchiveMetrics.footerHeight - labelHeight) / 2).rounded(),
                               width: max(0, restorePill.frame.minX - ArchiveMetrics.countToRestore - labelX),
                               height: labelHeight)

    let toastSize = toastView.preferredSize(maxWidth: max(0, width - 32))
    toastView.frame = NSRect(x: ((width - toastSize.width) / 2).rounded(),
                             y: footerTop - ArchiveMetrics.toastAboveFooter - toastSize.height,
                             width: toastSize.width, height: toastSize.height)
  }
}

/// A filter menu item and what choosing it does.
@MainActor
private final class ArchiveFilterMenuItem: NSMenuItem {
  var choose: (@MainActor (ArchiveWindowController) -> Void)?
}

/// The Archive window: a full-size content view under a transparent, hidden title, so the title, the search field and
/// the filter button share the traffic lights' 52 pt bar. Cmd-F focuses the search field and Cmd-W closes the window.
@MainActor
final class ArchiveWindow: NSWindow {
  var onFind: (@MainActor () -> Void)?

  /// Close, minimize and zoom at x 20, 40 and 60, centered in the 52 pt bar. The titlebar container is narrowed to
  /// the buttons, so it never takes clicks from the title, the search field or the filter button.
  func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton),
          let titlebar = close.superview, let container = titlebar.superview else { return }
    let height = ArchiveMetrics.barHeight
    let width = ArchiveMetrics.trafficLightX * 2 + ArchiveMetrics.trafficLightSpacing * 2 + close.frame.width
    let containerFrame = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != containerFrame { container.frame = containerFrame }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let origin = NSPoint(x: ArchiveMetrics.trafficLightX + CGFloat(index) * ArchiveMetrics.trafficLightSpacing,
                           y: ((titlebar.bounds.height - button.frame.height) / 2).rounded())
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if flags == .command, event.type == .keyDown {
      switch event.charactersIgnoringModifiers {
      case "f":
        onFind?()
        return true
      case "w":
        performClose(nil)
        return true
      default:
        break
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}
