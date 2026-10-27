import AppKit
import EngineAPI

/// The popover's content (design/downloads, direction B): the six most recent downloads as rows, and a footer with Show
/// Library and Clear. Frames are set in `layout()`. Rows come and go with the 0.24 s rise and the 0.16 s fade; a row that
/// is already there only updates, so a progress stream never rebuilds anything.
@MainActor
final class DownloadsPopoverView: NSView {
  private let listView = FlippedView(frame: .zero)
  private let emptyLabel = NSTextField(labelWithString: "No downloads yet")
  private let divider = CALayer()
  private let showLibraryButton = ArchiveLinkButton(style: .secondary, title: "Show Library", fontSize: 12)
  private let keycaps = NSTextField(labelWithString: "\u{2318}\u{21E7}J")
  let clearButton = ArchiveLinkButton(style: .secondary, title: "Clear", fontSize: 12)
  private(set) var rows: [DownloadID: DownloadRowView] = [:]
  /// The ids listed, newest first.
  private(set) var order: [DownloadID] = []
  var onAction: (@MainActor (DownloadRowAction, DownloadID) -> Void)?
  var onShowLibrary: (@MainActor () -> Void)?
  var onClear: (@MainActor () -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { for row in rows.values { row.reduceMotion = reduceMotion } }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(listView)
    emptyLabel.font = .systemFont(ofSize: 13)
    emptyLabel.alignment = .center
    emptyLabel.setAccessibilityElement(true)
    listView.addSubview(emptyLabel)
    layer?.addSublayer(divider)
    keycaps.font = .systemFont(ofSize: 11, weight: .medium)
    keycaps.setAccessibilityElement(false)
    for view in [showLibraryButton, keycaps, clearButton] as [NSView] { addSubview(view) }
    showLibraryButton.target = self
    showLibraryButton.action = #selector(showLibraryPressed(_:))
    showLibraryButton.setAccessibilityIdentifierWithCell(AXID.Downloads.popoverShowLibrary)
    showLibraryButton.setArchiveAccessibilityLabel("Show Library")
    clearButton.target = self
    clearButton.action = #selector(clearPressed(_:))
    clearButton.setAccessibilityIdentifierWithCell(AXID.Downloads.popoverClear)
    clearButton.setArchiveAccessibilityLabel("Clear finished downloads")
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Downloads.popover)
    setAccessibilityLabel("Downloads")
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  @objc private func showLibraryPressed(_ sender: Any?) { onShowLibrary?() }
  @objc private func clearPressed(_ sender: Any?) { onClear?() }

  // MARK: Content

  /// The height the content needs: padding, the rows (or the empty line) and the footer.
  var preferredHeight: CGFloat {
    let rowsHeight = order.isEmpty ? DownloadsMetrics.popoverRowMin : CGFloat(order.count) * DownloadsMetrics.popoverRowMin
    return DownloadsMetrics.popoverPadding * 2 + rowsHeight + DownloadsMetrics.popoverFooter
  }

  /// Lists `items` (newest first). New ids rise in, gone ones fade out, the rest update in place. `canClear`: there is a
  /// finished row to clear. Returns whether the row set changed (the panel then resizes).
  @discardableResult
  func reload(_ items: [DownloadItem], canClear: Bool) -> Bool {
    let ids = items.map(\.id)
    let changed = ids != order
    var leaving: [DownloadRowView] = []
    for (id, row) in rows where !ids.contains(id) {
      leaving.append(row)
      rows[id] = nil
    }
    for item in items {
      if let row = rows[item.id] {
        row.update(item)
      } else {
        let row = DownloadRowView(style: .popover, item: item)
        row.reduceMotion = reduceMotion
        row.onAction = { [weak self] action, id in self?.onAction?(action, id) }
        rows[item.id] = row
        listView.addSubview(row)
        row.frame = NSRect(x: 0, y: -DownloadsMetrics.popoverRowMin, width: listView.bounds.width, height: DownloadsMetrics.popoverRowMin)
        if changed { row.playAppearance() }
      }
    }
    order = ids
    emptyLabel.isHidden = !items.isEmpty
    clearButton.isEnabled = canClear
    for row in leaving {
      row.playRemoval { row.removeFromSuperview() }
    }
    if changed { needsLayout = true }
    return changed
  }

  // MARK: Layout

  override func layout() {
    super.layout()
    let pad = DownloadsMetrics.popoverPadding
    let footer = DownloadsMetrics.popoverFooter
    listView.frame = NSRect(x: pad, y: footer + pad, width: bounds.width - 2 * pad, height: max(0, bounds.height - footer - 2 * pad))
    var y: CGFloat = 0
    for id in order {
      rows[id]?.frame = NSRect(x: 0, y: y, width: listView.bounds.width, height: DownloadsMetrics.popoverRowMin)
      y += DownloadsMetrics.popoverRowMin
    }
    emptyLabel.frame = NSRect(x: 0, y: (DownloadsMetrics.popoverRowMin - 18) / 2, width: listView.bounds.width, height: 18)
    divider.frame = CGRect(x: pad + 2, y: footer, width: bounds.width - 2 * (pad + 2), height: 1)
    showLibraryButton.sizeToFit()
    let baseline = ((footer - showLibraryButton.frame.height) / 2).rounded()
    showLibraryButton.frame.origin = NSPoint(x: pad + 8, y: baseline - 2)
    keycaps.sizeToFit()
    keycaps.frame.origin = NSPoint(x: showLibraryButton.frame.maxX + 6, y: ((footer - keycaps.frame.height) / 2).rounded() - 2)
    clearButton.sizeToFit()
    clearButton.frame.origin = NSPoint(x: bounds.width - pad - 8 - clearButton.frame.width, y: baseline - 2)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    emptyLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    keycaps.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    ArchiveMotion.set { divider.backgroundColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor }
  }
}
