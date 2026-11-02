import AppKit

/// Row background: the selected row gets a lighter rounded fill, inset from the panel edges.
@MainActor
final class LittleArktLookupRowView: NSTableRowView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.row")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier(AXID.CommandBar.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isSelected: Bool {
    didSet {
      if isSelected != oldValue { needsDisplay = true }
      setAccessibilitySelected(isSelected)
    }
  }

  override func isAccessibilitySelected() -> Bool { isSelected }

  override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
  }

  override func accessibilityChildren() -> [Any]? {
    NSAccessibility.unignoredChildren(from: subviews)
  }

  private var resultCell: LittleArktLookupCellView? {
    numberOfColumns > 0 ? view(atColumn: 0) as? LittleArktLookupCellView : nil
  }

  override func accessibilityLabel() -> String? {
    resultCell?.title.stringValue ?? super.accessibilityLabel()
  }

  override func accessibilityValue() -> Any? {
    resultCell?.accessibilityValue() ?? super.accessibilityValue()
  }

  override func drawBackground(in dirtyRect: NSRect) {
    guard isSelected else { return }
    let r = LittleArktGeometry.selectedRowRadius
    let rect = bounds.insetBy(dx: LittleArktGeometry.listPadding, dy: 0)
    ShellTokens.lookupSelectedRow.nsColor().setFill()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
  }

  override func drawSelection(in dirtyRect: NSRect) {}
}

/// One result: 16 pt icon, title, subtitle on the same baseline, trailing hint ("Switch to Tab ->").
@MainActor
final class LittleArktLookupCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.cell")
  static let iconSize: CGFloat = 16

  let icon = NSImageView()
  let title = LittleArktLookupCellView.label(size: 14, color: ShellTokens.lookupText)
  let subtitle = LittleArktLookupCellView.label(size: 12, color: ShellTokens.lookupSecondaryText)
  let hint = LittleArktLookupCellView.label(size: 12, color: ShellTokens.lookupSecondaryText)
  /// The hovered row's remove button (BH-109); hidden unless the row is removable and hovered.
  let closeButton = NSButton()

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    [icon, title, subtitle, hint].forEach(addSubview)
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.toolTip = "Remove Suggestion"
    closeButton.setAccessibilityLabel("Remove Suggestion")
    closeButton.setAccessibilityIdentifier(AXID.CommandBar.rowRemove)
    closeButton.isHidden = true
    closeButton.target = self
    closeButton.action = #selector(closeClicked(_:))
    addSubview(closeButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private static func label(size: CGFloat, color: RGBA) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: size)
    label.textColor = color.nsColor()
    label.lineBreakMode = .byTruncatingTail
    label.cell?.usesSingleLineMode = true
    return label
  }

  /// Removal (BH-109): nil for a row that is not removable; the X shows only while the row is hovered.
  var onRemove: (() -> Void)?

  @objc private func closeClicked(_ sender: Any?) { onRemove?() }

  func setCloseHovered(_ hovered: Bool) {
    closeButton.isHidden = !(hovered && onRemove != nil)
    needsLayout = true
  }

  /// `scale`: pixels per point for the icon bitmap (the bar's backing scale, which the cell's own window may
  /// not report yet while the panel is still on the previous display).
  func configure(_ result: CommandBarResults.Result, scale: CGFloat) {
    let symbol = switch result.kind {
    case .open, .pasteAndGo: "globe"
    case .switchTo: "square.on.square"
    case .search, .siteSearch: "magnifyingglass"
    case .restore: "archivebox"
    case .action: "bolt"
    case .switchSpace: "square.grid.2x2"
    case .history: "clock"
    case .noMatch: "magnifyingglass"
    }
    icon.image = SymbolImageCache.shared.symbol(symbol, box: Self.iconSize, color: ShellTokens.lookupText,
                                                scale: scale)
    closeButton.image = SymbolImageCache.shared.symbol("xmark", box: 10,
                                                       color: ShellTokens.lookupSecondaryText, scale: scale)
    closeButton.isHidden = true
    title.stringValue = result.title
    subtitle.stringValue = result.subtitle
    hint.stringValue = result.trailingHint.map { $0 + " \u{2192}" } ?? ""
    hint.isHidden = result.trailingHint == nil
    setAccessibilityLabel(result.title)
    setAccessibilityValue(result.accessibilityCaption)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let leading = LittleArktGeometry.listPadding + 16       // matches the 8 pt inset of the selected fill
    var trailing = bounds.width - leading
    let iconSize = Self.iconSize
    icon.frame = NSRect(x: leading, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
    if !closeButton.isHidden {
      let closeSize: CGFloat = 20
      closeButton.frame = NSRect(x: trailing - closeSize, y: (bounds.height - closeSize) / 2,
                                 width: closeSize, height: closeSize)
      trailing = closeButton.frame.minX - 8
    }
    let hintWidth = hint.isHidden ? 0 : ceil(hint.fittingSize.width)
    hint.frame = centered(x: trailing - hintWidth, width: hintWidth, field: hint)
    let textX = icon.frame.maxX + 12
    let textLimit = (hint.isHidden ? trailing : hint.frame.minX - 12)
    let titleWidth = min(ceil(title.fittingSize.width), max(0, textLimit - textX))
    title.frame = centered(x: textX, width: titleWidth, field: title)
    let subtitleX = title.frame.maxX + 8
    subtitle.frame = centered(x: subtitleX, width: max(0, textLimit - subtitleX), field: subtitle)
  }

  private func centered(x: CGFloat, width: CGFloat, field: NSTextField) -> NSRect {
    let h = ceil(field.intrinsicContentSize.height)
    return NSRect(x: x, y: (bounds.height - h) / 2, width: width, height: h)
  }
}
