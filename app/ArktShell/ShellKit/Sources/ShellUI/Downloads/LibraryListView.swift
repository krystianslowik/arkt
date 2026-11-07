import AppKit
import EngineAPI

/// The Library's list of downloads, grouped by day (design/downloads, direction A): 56 pt rows with a 36 pt tile, group
/// headers, and keyboard selection. Frames are set in `layout()`; rows are reused by id, so a progress stream only
/// updates the row it belongs to. Return opens the selected file, Command-Return reveals it, Delete removes it from
/// the list (never from disk).
@MainActor
final class LibraryListView: NSView {
  private(set) var rows: [DownloadID: DownloadRowView] = [:]
  private var headers: [String: NSTextField] = [:]
  private(set) var sections: [DownloadsSection] = []
  /// The ids in display order.
  private(set) var order: [DownloadID] = []
  private(set) var selectedID: DownloadID?
  var onAction: (@MainActor (DownloadRowAction, DownloadID) -> Void)?
  var onDelete: (@MainActor (DownloadID) -> Void)?
  var onEscape: (@MainActor () -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { for row in rows.values { row.reduceMotion = reduceMotion } }
  }
  /// The time the day groups are measured from; tests set it.
  var now: @MainActor () -> Date = { Date() }
  static let rowPitch: CGFloat = DownloadsMetrics.libraryRow + 2

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.list)
    setAccessibilityLabel("Downloads")
    setAccessibilityIdentifier(AXID.Downloads.libraryList)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  // MARK: Content

  /// Lists `items`, grouped by day. Rows that are already there update; new ones rise in; gone ones fade out.
  func reload(_ items: [DownloadItem], animated: Bool = true) {
    let next = DownloadsFormat.sections(items, now: now())
    let ids = next.flatMap(\.items).map(\.id)
    let isNewSet = Set(ids).subtracting(rows.keys)
    for (id, row) in rows where !ids.contains(id) {
      rows[id] = nil
      if animated { row.playRemoval { row.removeFromSuperview() } } else { row.removeFromSuperview() }
    }
    for item in next.flatMap(\.items) {
      if let row = rows[item.id] {
        row.update(item)
      } else {
        let row = DownloadRowView(style: .library, item: item)
        row.reduceMotion = reduceMotion
        row.onAction = { [weak self] action, id in self?.onAction?(action, id) }
        row.onSelect = { [weak self] id in self?.select(id) }
        rows[item.id] = row
        addSubview(row)
        if animated, isNewSet.contains(item.id) { row.playAppearance() }
      }
    }
    for (title, header) in headers where !next.contains(where: { $0.title == title }) {
      header.removeFromSuperview()
      headers[title] = nil
    }
    for section in next where headers[section.title] == nil {
      let header = NSTextField(labelWithString: section.title)
      header.font = .systemFont(ofSize: 12, weight: .semibold)
      header.setAccessibilityElement(false)
      addSubview(header)
      headers[section.title] = header
    }
    sections = next
    order = ids
    if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
    restyle()
    needsLayout = true
    syncSelection()
  }

  /// The height the content needs; the scroll view's document view takes it.
  var contentHeight: CGFloat {
    let headerHeight = DownloadsMetrics.groupHeader
    return sections.reduce(CGFloat(8)) { $0 + headerHeight + CGFloat($1.items.count) * Self.rowPitch } + 8
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 4
    let inset: CGFloat = 6
    for section in sections {
      headers[section.title]?.frame = NSRect(x: inset + 10, y: y + 10, width: bounds.width - 2 * inset - 20, height: 16)
      y += DownloadsMetrics.groupHeader
      for item in section.items {
        rows[item.id]?.frame = NSRect(x: inset, y: y, width: bounds.width - 2 * inset, height: DownloadsMetrics.libraryRow)
        y += Self.rowPitch
      }
    }
  }

  private func restyle() {
    let color = ShellTokens.secondaryText.resolve(archiveFlavor).nsColor()
    for header in headers.values { header.textColor = color }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  // MARK: Selection

  func select(_ id: DownloadID?) {
    guard id != selectedID else { return }
    selectedID = id
    syncSelection()
  }

  private func syncSelection() {
    for (id, row) in rows { row.isSelected = id == selectedID }
    if let selectedID, let row = rows[selectedID] { scrollToVisible(row.frame.insetBy(dx: 0, dy: -4)) }
  }

  /// Moves the selection by `step` rows, stopping at either end; from nothing the first row.
  func moveSelection(by step: Int) {
    guard !order.isEmpty else { return }
    guard let current = selectedID, let index = order.firstIndex(of: current) else {
      select(step > 0 ? order.first : order.last)
      return
    }
    select(order[min(max(index + step, 0), order.count - 1)])
  }

  // MARK: Keys

  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    switch event.keyCode {
    case 125: moveSelection(by: 1)                       // Down
    case 126: moveSelection(by: -1)                      // Up
    case 36, 76:                                         // Return, Enter
      guard let selectedID else { return }
      onAction?(flags == .command ? .showInFinder : .open, selectedID)
    case 51, 117:                                        // Delete, Forward Delete
      if let selectedID { onDelete?(selectedID) }
    case 53: onEscape?()                                 // Escape
    default: super.keyDown(with: event)
    }
  }
}
