import AppKit

/// A transparent table row: the fill and tick of the selected row are `CommandBarSelectionIndicator`'s, drawn behind
/// the rows. The row tells its cell whether it is selected (the trailing key caps change) and speaks for the row to
/// accessibility.
@MainActor
final class CommandBarRowView: NSTableRowView {
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
      if isSelected != oldValue { resultCell?.isRowSelected = isSelected }
      setAccessibilitySelected(isSelected)
    }
  }

  override func didAddSubview(_ subview: NSView) {
    super.didAddSubview(subview)
    (subview as? CommandBarCellView)?.isRowSelected = isSelected
  }

  override func isAccessibilitySelected() -> Bool { isSelected }

  override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
  }

  override func accessibilityChildren() -> [Any]? {
    NSAccessibility.unignoredChildren(from: subviews)
  }

  private var resultCell: CommandBarCellView? {
    numberOfColumns > 0 ? view(atColumn: 0) as? CommandBarCellView : nil
  }

  override func accessibilityLabel() -> String? {
    resultCell?.accessibilityLabel() ?? super.accessibilityLabel()
  }

  override func accessibilityValue() -> Any? {
    resultCell?.accessibilityValue() ?? super.accessibilityValue()
  }

  override func drawBackground(in dirtyRect: NSRect) {}
  override func drawSelection(in dirtyRect: NSRect) {}
}

/// One result, by the README's row anatomy: a 20 pt slot with a 16 pt symbol, the title (14) with the query match in
/// semibold, a secondary URL (13) that truncates first, and a right-aligned trailing group of captions and key caps.
@MainActor
final class CommandBarCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.cell")
  static let iconSize: CGFloat = CommandBarGeometry.iconSize
  private static let keyCapGap: CGFloat = 5
  private static let maxKeyCaps = 3

  let icon = NSImageView()
  let title = NSTextField(labelWithString: "")
  let subtitle = CommandBarCellView.label(size: 13)
  let hint = CommandBarCellView.label(size: 12)
  private var keyCaps: [CommandBarKeyCapView] = (0..<CommandBarCellView.maxKeyCaps).map { _ in
    CommandBarKeyCapView(frame: .zero)
  }
  /// The hovered row's remove button (BH-109); hidden unless the row is removable and hovered.
  let closeButton = NSButton()
  /// The group header over the first row of a group (empty state): 11 pt semibold in the top 26 pt of the cell.
  let header = NSTextField(labelWithString: "")
  private var groupHeader: String?

  private(set) var result: CommandBarResults.Result?
  private var query = ""
  private var flavor: ThemeFlavor = .dark
  private var scale: CGFloat = 2
  /// Whether this row is the selected one: the trailing group gains a Return key cap and the title the strong color.
  var isRowSelected = false {
    didSet { if isRowSelected != oldValue { applyState() } }
  }
  /// Position and count for the accessibility sentence.
  private var position = 1
  private var count = 1

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    title.lineBreakMode = .byTruncatingTail
    title.cell?.usesSingleLineMode = true
    header.font = .systemFont(ofSize: 11, weight: .semibold)
    header.lineBreakMode = .byTruncatingTail
    header.cell?.usesSingleLineMode = true
    header.isHidden = true
    header.setAccessibilityElement(false)
    [icon, title, subtitle, hint, header].forEach(addSubview)
    keyCaps.forEach(addSubview)
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

  /// Top-down, so a group header sits at the top of the cell.
  override var isFlipped: Bool { true }

  private static func label(size: CGFloat) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: size)
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
  func configure(_ result: CommandBarResults.Result, query: String, position: Int, count: Int, flavor: ThemeFlavor,
                 scale: CGFloat, groupHeader: String? = nil) {
    self.groupHeader = groupHeader
    header.stringValue = groupHeader ?? ""
    header.isHidden = groupHeader == nil
    self.result = result
    self.query = query
    self.position = position
    self.count = count
    self.flavor = flavor
    self.scale = scale
    closeButton.isHidden = true
    subtitle.stringValue = result.secondaryText
    subtitle.isHidden = result.secondaryText.isEmpty
    setAccessibilityLabel(result.accessibilityLabel(position: position, of: count))
    setAccessibilityValue(result.accessibilityCaption)
    applyState()
  }

  /// Colors, symbol, title emphasis and trailing group for the current selection state.
  private func applyState() {
    guard let result else { return }
    icon.image = SymbolImageCache.shared.symbol(result.symbolName, box: Self.iconSize,
                                                color: ShellTokens.commandBarSecondaryText.resolve(flavor), scale: scale)
    closeButton.image = SymbolImageCache.shared.symbol("xmark", box: 10,
                                                       color: ShellTokens.commandBarTertiaryText.resolve(flavor),
                                                       scale: scale)
    let strong = ShellTokens.commandBarText.resolve(flavor).nsColor()
    let rest = (isRowSelected ? strong : ShellTokens.commandBarSecondaryText.resolve(flavor).nsColor())
    let attributed = NSMutableAttributedString(string: result.title, attributes: [
      .font: NSFont.systemFont(ofSize: 14), .foregroundColor: rest,
    ])
    if let range = CommandBarTitleMatch.range(of: query, in: result.title) {
      attributed.addAttributes([.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: strong],
                               range: NSRange(range, in: result.title))
    }
    title.attributedStringValue = attributed
    subtitle.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    header.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()

    let trailing = result.trailing(isSelected: isRowSelected)
    var caption = ""
    var caps: [String] = []
    for item in trailing {
      switch item {
      case .text(let text): caption = text
      case .keyCap(let cap): caps.append(cap)
      }
    }
    hint.stringValue = caption
    hint.isHidden = caption.isEmpty
    hint.textColor = (isRowSelected ? ShellTokens.commandBarSecondaryText : ShellTokens.commandBarTertiaryText)
      .resolve(flavor).nsColor()
    for (index, view) in keyCaps.enumerated() {
      if index < caps.count {
        view.configure(caps[index], flavor: flavor)
        view.isHidden = false
      } else {
        view.isHidden = true
      }
    }
    needsLayout = true
  }

  /// The trailing key caps' text, in order (tests).
  var visibleKeyCaps: [String] { keyCaps.filter { !$0.isHidden }.map(\.text) }

  override func layout() {
    super.layout()
    let g = CommandBarGeometry.self
    // A row that starts a group is taller by its header; the row's own content sits in the bottom `rowHeight`.
    let headerHeight = groupHeader == nil ? 0 : g.groupHeaderHeight
    let content = NSRect(x: 0, y: headerHeight, width: bounds.width, height: bounds.height - headerHeight)
    if headerHeight > 0 {
      let h = ceil(header.fittingSize.height)
      header.frame = NSRect(x: g.rowHorizontalPadding, y: g.groupHeaderHeight - 4 - h, width: max(0, bounds.width - 2 * g.rowHorizontalPadding), height: h)
    }
    var trailing = bounds.width - g.rowHorizontalPadding
    if !closeButton.isHidden {
      let closeSize: CGFloat = 20
      closeButton.frame = NSRect(x: trailing - closeSize, y: content.minY + (content.height - closeSize) / 2,
                                 width: closeSize, height: closeSize)
      trailing = closeButton.frame.minX - 8
    }
    // The trailing group, right to left: key caps, then the caption.
    for view in keyCaps.reversed() where !view.isHidden {
      let size = view.size
      view.frame = NSRect(x: trailing - size.width, y: content.minY + (content.height - size.height) / 2, width: size.width,
                          height: size.height)
      trailing = view.frame.minX - 4
    }
    if !hint.isHidden {
      let width = ceil(hint.fittingSize.width)
      if keyCaps.contains(where: { !$0.isHidden }) { trailing -= 2 }
      hint.frame = centered(x: trailing - width, width: width, field: hint, in: content)
      trailing = hint.frame.minX
    }
    let slotX = g.rowHorizontalPadding
    icon.frame = NSRect(x: slotX + (g.slotWidth - g.iconSize) / 2, y: content.minY + (content.height - g.iconSize) / 2,
                        width: g.iconSize, height: g.iconSize)
    let textX = slotX + g.slotWidth + g.slotGap
    let textLimit = trailing - (hint.isHidden && !keyCaps.contains(where: { !$0.isHidden }) ? 0 : 12)
    let titleWidth = min(ceil(title.fittingSize.width), max(0, textLimit - textX))
    title.frame = centered(x: textX, width: titleWidth, field: title, in: content)
    let subtitleX = title.frame.maxX + 10
    subtitle.frame = centered(x: subtitleX, width: max(0, textLimit - subtitleX), field: subtitle, in: content)
  }

  private func centered(x: CGFloat, width: CGFloat, field: NSTextField, in content: NSRect) -> NSRect {
    let h = ceil(field.intrinsicContentSize.height)
    return NSRect(x: x, y: (content.minY + (content.height - h) / 2).rounded(), width: width, height: h)
  }
}
