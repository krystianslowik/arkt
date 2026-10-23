import AppKit

/// The minimal Archive window (E5c; Window > Show Archive, unbound by default, KB-043): archived items newest first
/// in a one-column AppKit table, a footer for unreadable items, "Load More" while more may exist, and Restore
/// (button or double-click). Not a hot path, but still AppKit, never a SwiftUI list.
@MainActor
public final class ArchiveWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
  static let contentSize = NSSize(width: 600, height: 480)
  static let rowHeight: CGFloat = 44
  private static let barHeight: CGFloat = 44
  private static let margin: CGFloat = 12

  public let tableView = NSTableView()
  public let restoreButton = NSButton(title: "Restore", target: nil, action: nil)
  public let loadMoreButton = NSButton(title: "Load More", target: nil, action: nil)
  /// "N items could not be read", or the load failure; hidden when there is nothing to say.
  public let footerLabel = NSTextField(labelWithString: "")
  /// The rows on screen, newest first.
  public private(set) var rows: [ArchiveRow] = []
  /// The load started by `show()` or "Load More"; tests await it.
  public private(set) var pendingLoad: Task<Void, Never>?

  private let dataSource: any ArchiveListDataSource

  public init(dataSource: any ArchiveListDataSource) {
    self.dataSource = dataSource
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
    window.title = "Archive"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 360, height: 240)
    super.init(window: window)
    buildContent(in: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Showing and loading

  /// Shows (or fronts) the window and loads the first page again.
  public func show() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    pendingLoad = Task { [weak self] in await self?.reload() }
  }

  /// Loads the first page, starting over. Overlapping loads are ordered by the data source (see
  /// `ArchiveListDataSource`), so every page that comes back is applied.
  public func reload() async {
    apply(await dataSource.loadPage())
  }

  /// Loads the next page.
  public func loadMore() async {
    apply(await dataSource.loadMore())
  }

  /// Escape closes the window, like its close button.
  public override func cancelOperation(_ sender: Any?) {
    window?.performClose(sender)
  }

  @objc func loadMoreClicked(_ sender: Any?) {
    pendingLoad = Task { [weak self] in await self?.loadMore() }
  }

  private func apply(_ page: ArchiveListPage) {
    rows = page.rows
    tableView.reloadData()
    loadMoreButton.isHidden = !page.mayHaveMore
    if page.failed {
      footerLabel.stringValue = "The Archive could not be read."
    } else if page.unreadable > 0 {
      footerLabel.stringValue = "\(page.unreadable) \(page.unreadable == 1 ? "item" : "items") could not be read"
    }
    footerLabel.isHidden = !page.failed && page.unreadable == 0
    updateRestoreButton()
  }

  // MARK: Restore

  /// The Restore button: restores the selected row.
  @objc public func restoreSelected(_ sender: Any?) {
    restore(row: tableView.selectedRow)
  }

  /// Double-click: the clicked row; without a mouse event (keyboard, tests), the selected row.
  @objc func rowDoubleClicked(_ sender: Any?) {
    let isMouse = NSApp.currentEvent.map { [.leftMouseDown, .leftMouseUp].contains($0.type) } ?? false
    restore(row: tableView.clickedRow >= 0 ? tableView.clickedRow : (isMouse ? -1 : tableView.selectedRow))
  }

  private func restore(row: Int) {
    guard dataSource.canRestore, rows.indices.contains(row) else { return }
    guard dataSource.restore(rows[row].id) else { return }
    rows.remove(at: row)
    tableView.removeRows(at: [row], withAnimation: [])
    updateRestoreButton()
  }

  private func updateRestoreButton() {
    restoreButton.isEnabled = dataSource.canRestore && rows.indices.contains(tableView.selectedRow)
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: ArchiveRowCellView.identifier, owner: self) as? ArchiveRowCellView
      ?? ArchiveRowCellView()
    let item = rows[row]
    cell.titleField.stringValue = item.title
    cell.detailField.stringValue = "\(item.detail) - \(item.reason)"
    return cell
  }

  public func tableViewSelectionDidChange(_ notification: Notification) { updateRestoreButton() }

  // MARK: Layout

  private func buildContent(in window: NSWindow) {
    let content = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
    content.autoresizingMask = [.width, .height]

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = Self.rowHeight
    tableView.usesAutomaticRowHeights = false
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.allowsMultipleSelection = false
    tableView.style = .inset
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(rowDoubleClicked(_:))

    let scroll = NSScrollView(frame: NSRect(
      x: 0, y: Self.barHeight, width: Self.contentSize.width, height: Self.contentSize.height - Self.barHeight))
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.documentView = tableView
    content.addSubview(scroll)

    restoreButton.bezelStyle = .push
    restoreButton.target = self
    restoreButton.action = #selector(restoreSelected(_:))
    restoreButton.isEnabled = false
    restoreButton.sizeToFit()
    restoreButton.frame.origin = NSPoint(
      x: Self.contentSize.width - Self.margin - restoreButton.frame.width,
      y: (Self.barHeight - restoreButton.frame.height) / 2)
    restoreButton.autoresizingMask = [.minXMargin, .maxYMargin]
    content.addSubview(restoreButton)

    loadMoreButton.bezelStyle = .push
    loadMoreButton.target = self
    loadMoreButton.action = #selector(loadMoreClicked(_:))
    loadMoreButton.isHidden = true
    loadMoreButton.sizeToFit()
    loadMoreButton.frame.origin = NSPoint(
      x: restoreButton.frame.minX - 8 - loadMoreButton.frame.width,
      y: (Self.barHeight - loadMoreButton.frame.height) / 2)
    loadMoreButton.autoresizingMask = [.minXMargin, .maxYMargin]
    content.addSubview(loadMoreButton)

    footerLabel.font = .systemFont(ofSize: 12)
    footerLabel.textColor = .secondaryLabelColor
    footerLabel.lineBreakMode = .byTruncatingTail
    footerLabel.isHidden = true
    let labelHeight: CGFloat = 16
    footerLabel.frame = NSRect(
      x: Self.margin, y: (Self.barHeight - labelHeight) / 2,
      width: loadMoreButton.frame.minX - 2 * Self.margin, height: labelHeight)
    footerLabel.autoresizingMask = [.width, .maxYMargin]
    content.addSubview(footerLabel)

    window.contentView = content
    window.setContentSize(Self.contentSize)
    window.center()
  }
}

/// Two lines: the title, then detail and reason.
@MainActor
final class ArchiveRowCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("ArchiveRowCell")

  let titleField = NSTextField(labelWithString: "")
  let detailField = NSTextField(labelWithString: "")

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 400, height: ArchiveWindowController.rowHeight))
    identifier = Self.identifier
    titleField.font = .systemFont(ofSize: 13)
    titleField.lineBreakMode = .byTruncatingTail
    detailField.font = .systemFont(ofSize: 11)
    detailField.textColor = .secondaryLabelColor
    detailField.lineBreakMode = .byTruncatingTail
    addSubview(titleField)
    addSubview(detailField)
    textField = titleField
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layout() {
    super.layout()
    let width = max(bounds.width - 8, 0)
    titleField.frame = NSRect(x: 4, y: bounds.midY, width: width, height: 18)
    detailField.frame = NSRect(x: 4, y: bounds.midY - 16, width: width, height: 15)
  }
}
