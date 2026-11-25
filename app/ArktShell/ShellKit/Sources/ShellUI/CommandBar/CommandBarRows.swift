import AppKit

/// A table row that draws its own selection: a neutral `commandBarSelectedRow` fill with 8 pt corners over the row's
/// content (not its group header). No tick, no stroke, no slide. It tells its cell whether it is selected (the trailing
/// group changes) and speaks for the row to accessibility.
@MainActor
final class CommandBarRowView: NSTableRowView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.row")

  /// The height of the group header at the top of the row, 0 for a row without one.
  var headerHeight: CGFloat = 0 {
    didSet { if headerHeight != oldValue { needsDisplay = true } }
  }
  var flavor: ThemeFlavor = .dark {
    didSet { if flavor != oldValue { needsDisplay = true } }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier(AXID.CommandBar.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override var isSelected: Bool {
    didSet {
      guard isSelected != oldValue else { return }
      resultCell?.isRowSelected = isSelected
      needsDisplay = true
      setAccessibilitySelected(isSelected)
    }
  }

  override func didAddSubview(_ subview: NSView) {
    super.didAddSubview(subview)
    (subview as? CommandBarCellView)?.isRowSelected = isSelected
  }

  /// The selected fill's rectangle: the row below its header.
  var fillRect: NSRect {
    NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
  }

  override func drawBackground(in dirtyRect: NSRect) {
    guard isSelected else { return }
    ShellTokens.commandBarSelectedRow.resolve(flavor).nsColor().setFill()
    let radius = CommandBarGeometry.rowRadius
    NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
  }

  override func drawSelection(in dirtyRect: NSRect) {}

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
}

/// One result, by the README's row anatomy: an 18 pt slot (a 16 pt favicon, letter tile, extension icon or symbol),
/// the title (14) with the query match in semibold, the secondary text (13) that truncates first and is dropped under
/// 48 pt, and the trailing group: the selected row's verb and Return key cap, or an unselected history row's time.
/// A row that starts a group carries the group header above its content.
@MainActor
final class CommandBarCellView: NSTableCellView {
  static let titleFontSize: CGFloat = 14
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.cell")
  static let iconSize: CGFloat = CommandBarGeometry.iconSize

  let icon = NSImageView()
  let title = NSTextField(labelWithString: "")
  let subtitle = CommandBarCellView.label(size: 13)
  /// The verb (selected) or the time (an unselected history row).
  let trailingText = CommandBarCellView.label(size: 12)
  let returnKey = CommandBarKeyCapView(frame: .zero)
  /// A history row's remove button, shown while the pointer is over the row (BH-109): removes it from history.
  let removeButton = NSButton()
  static let removeButtonSize: CGFloat = 20
  static let removeGlyphSize: CGFloat = 10
  static let removeLabel = "Remove from History"
  /// Removes the row; nil for a row that is not removable.
  var onRemove: (() -> Void)?
  private var isHovered = false
  /// The group header over the first row of a group: 11 pt semibold, tertiary text.
  let header = CommandBarGroupHeaderLabel(labelWithString: "")
  private(set) var headerHeight: CGFloat = 0
  private var isFirstRow = false

  private(set) var result: CommandBarResults.Result?
  private var query = ""
  private var flavor: ThemeFlavor = .dark
  private var scale: CGFloat = 2
  private var increasedContrast = false
  private var favicon: NSImage?
  /// Whether this row is the selected one: the trailing group shows the verb and the Return key cap.
  var isRowSelected = false {
    didSet { if isRowSelected != oldValue { applyTrailing() } }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.wantsLayer = true
    icon.layer?.cornerRadius = CommandBarGeometry.faviconRadius
    icon.layer?.masksToBounds = true
    title.lineBreakMode = .byTruncatingTail
    title.cell?.usesSingleLineMode = true
    title.setAccessibilityElement(false)
    subtitle.setAccessibilityElement(false)
    trailingText.setAccessibilityElement(false)
    header.lineBreakMode = .byTruncatingTail
    header.cell?.usesSingleLineMode = true
    header.isHidden = true
    header.setAccessibilityElement(false)                // the controller publishes headers from its model
    [icon, title, subtitle, trailingText, returnKey, header].forEach(addSubview)
    removeButton.isBordered = false
    removeButton.imagePosition = .imageOnly
    removeButton.toolTip = Self.removeLabel
    removeButton.setAccessibilityLabel(Self.removeLabel)
    removeButton.setAccessibilityIdentifier(AXID.CommandBar.rowRemove)
    removeButton.isHidden = true
    removeButton.target = self
    removeButton.action = #selector(removeClicked(_:))
    addSubview(removeButton)
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

  @objc private func removeClicked(_ sender: Any?) { onRemove?() }

  /// The pointer came onto the row or left it: a removable row shows its remove button meanwhile.
  func setHovered(_ hovered: Bool) {
    isHovered = hovered
    let shows = hovered && onRemove != nil
    guard shows == removeButton.isHidden else { return }
    removeButton.isHidden = !shows
    needsLayout = true
  }

  /// `scale`: pixels per point for symbol bitmaps (the bar's backing scale). `favicon`: the tab's cached favicon or the extension's icon.
  /// `increasedContrast`: tertiary text (URL, time, header) takes the secondary color.
  func configure(_ result: CommandBarResults.Result, query: String, position: Int, count: Int, flavor: ThemeFlavor,
                 scale: CGFloat, groupHeader: String?, isFirstRow: Bool, favicon: NSImage?,
                 increasedContrast: Bool) {
    self.result = result
    self.query = query
    self.flavor = flavor
    self.scale = scale
    self.favicon = favicon
    self.increasedContrast = increasedContrast
    self.isFirstRow = isFirstRow
    header.isHidden = groupHeader == nil
    headerHeight = groupHeader == nil ? 0 : (isFirstRow ? CommandBarGeometry.firstGroupHeaderHeight
                                                       : CommandBarGeometry.groupHeaderHeight)
    header.attributedStringValue = NSAttributedString(string: groupHeader ?? "", attributes: [
      .font: ShellType.sectionHeader.font, .kern: ShellType.sectionHeader.font.pointSize * 0.02,
      .foregroundColor: tertiaryColor,
    ])
    subtitle.stringValue = result.secondaryText
    subtitle.textColor = tertiaryColor
    setAccessibilityLabel(result.commandBarLabel(position: position, of: count))
    setAccessibilityValue(result.accessibilityCaption)
    removeButton.image = SymbolImageCache.shared.symbol("xmark", box: Self.removeGlyphSize,
                                                        color: tertiaryToken.resolve(flavor), scale: scale)
    applyIcon()
    applyTitle()
    applyTrailing()
  }

  private var tertiaryToken: TokenPair {
    increasedContrast ? ShellTokens.commandBarSecondaryText : ShellTokens.commandBarTertiaryText
  }

  private var tertiaryColor: NSColor { tertiaryToken.resolve(flavor).nsColor() }

  private func applyIcon() {
    guard let result else { return }
    if let favicon {
      icon.image = favicon                            // a tab's favicon, or an extension's icon
    } else if case .switchTo = result.kind {
      icon.image = SidebarGlyphs.letter(for: result.title, url: URL(string: "https://" + result.subtitle),
                                        flavor: flavor, size: Self.iconSize, scale: scale)
    } else {
      icon.image = SymbolImageCache.shared.symbol(result.symbolName, box: Self.iconSize,
                                                  color: ShellTokens.commandBarSecondaryText.resolve(flavor),
                                                  scale: scale)
    }
  }

  /// The title in `commandBarText`; the part that matches the query in semibold. The Search for row bolds what it
  /// searches for; Go and Paste and Go rows are the user's own text and bold nothing.
  private func applyTitle() {
    guard let result else { return }
    let color = ShellTokens.commandBarText.resolve(flavor).nsColor()
    let regular = NSFont.systemFont(ofSize: Self.titleFontSize)
    let bold = NSFont.systemFont(ofSize: Self.titleFontSize, weight: .semibold)
    let text = result.displayTitle
    let attributed = NSMutableAttributedString(string: text, attributes: [.font: regular, .foregroundColor: color])
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
    switch result.kind {
    case .search:
      if let range = text.range(of: "\u{201C}" + result.title + "\u{201D}") {
        attributed.addAttribute(.font, value: bold, range: NSRange(range, in: text))
      }
    case .open, .pasteAndGo:
      break
    default:
      for range in CommandBarTitleMatch.wordStartRanges(of: query, in: text) {
        attributed.addAttribute(.font, value: bold, range: NSRange(range, in: text))
      }
    }
    title.attributedStringValue = attributed
    needsLayout = true
  }

  private func applyTrailing() {
    guard let result else { return }
    if isRowSelected {
      trailingText.stringValue = result.verb ?? ""
      trailingText.textColor = ShellTokens.commandBarSecondaryText.resolve(flavor).nsColor()
      returnKey.configure(CommandBarKeyCaps.return, flavor: flavor)
      returnKey.isHidden = false
    } else {
      trailingText.stringValue = result.group == .history ? (result.timeText ?? "") : ""
      trailingText.textColor = tertiaryColor
      returnKey.isHidden = true
    }
    trailingText.isHidden = trailingText.stringValue.isEmpty
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let g = CommandBarGeometry.self
    let content = NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
    if !header.isHidden {
      let h = ceil(header.intrinsicContentSize.height)
      // The header's text starts `above` from the top of the row (10, or 4 for the group that starts the list); the
      // label's line box carries about 2 pt of leading above the glyphs.
      let above: CGFloat = isFirstRow ? 4 : 10
      header.frame = NSRect(x: g.rowHorizontalPadding - g.labelInset, y: above - 2,
                            width: max(0, bounds.width - 2 * g.rowHorizontalPadding), height: h)
    }
    var trailing = bounds.width - g.rowHorizontalPadding
    if !removeButton.isHidden {
      let size = Self.removeButtonSize
      removeButton.frame = NSRect(x: trailing - size, y: content.minY + (content.height - size) / 2,
                                  width: size, height: size)
      trailing = removeButton.frame.minX - 8
    }
    if !returnKey.isHidden {
      let size = returnKey.size
      returnKey.frame = NSRect(x: trailing - size.width, y: content.minY + (content.height - size.height) / 2,
                               width: size.width, height: size.height)
      trailing = returnKey.frame.minX - 8
    }
    if !trailingText.isHidden {
      let width = ceil(trailingText.fittingSize.width)
      trailingText.frame = centered(x: trailing - width, width: width, field: trailingText, in: content)
      trailing = trailingText.frame.minX
    }
    let hasTrailing = !returnKey.isHidden || !trailingText.isHidden
    let textLimit = trailing - (hasTrailing ? g.slotGap : 0)
    icon.frame = NSRect(x: g.rowHorizontalPadding + (g.slotWidth - g.iconSize) / 2,
                        y: content.minY + (content.height - g.iconSize) / 2, width: g.iconSize, height: g.iconSize)
    let textX = g.rowHorizontalPadding + g.slotWidth + g.slotGap - g.labelInset
    // The title is protected: it takes what it needs; the secondary text gets the rest, or nothing under 48 pt.
    let titleWidth = min(ceil(title.fittingSize.width), max(0, textLimit - textX))
    title.frame = centered(x: textX, width: titleWidth, field: title, in: content)
    let subtitleX = title.frame.maxX + g.slotGap
    let subtitleWidth = textLimit - subtitleX
    subtitle.isHidden = subtitle.stringValue.isEmpty || subtitleWidth < g.minimumURLWidth
    subtitle.frame = centered(x: subtitleX, width: max(0, subtitleWidth), field: subtitle, in: content)
  }

  private func centered(x: CGFloat, width: CGFloat, field: NSTextField, in content: NSRect) -> NSRect {
    let h = ceil(field.intrinsicContentSize.height)
    return NSRect(x: x, y: (content.minY + (content.height - h) / 2).rounded(), width: width, height: h)
  }
}

/// A group header ("Tabs", "History"): an accessibility group with the header's text as its label.
@MainActor
final class CommandBarGroupHeaderLabel: NSTextField {
  override func accessibilityRole() -> NSAccessibility.Role? { .group }
  override func isAccessibilityElement() -> Bool { accessibilityLabel() != nil && super.isAccessibilityElement() }
}
