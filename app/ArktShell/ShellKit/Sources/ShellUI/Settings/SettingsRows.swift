import AppKit

// MARK: - Blocks

/// A piece of a pane laid out by frames: it reports its height for a width, then lays its children out in
/// `layout()`. Flipped. Settings is not a hot path, but frames keep the window's height exact for the pane it shows.
@MainActor
class SettingsBlockView: NSView {
  override var isFlipped: Bool { true }

  func fittingHeight(width: CGFloat) -> CGFloat { 0 }
}

/// Height of a wrapping label at `width`.
@MainActor
func settingsTextHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
  guard let cell = field.cell, width > 0 else { return 0 }
  return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height)
}

@MainActor
func settingsLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, wraps: Bool = true) -> NSTextField {
  let field = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
  field.font = .systemFont(ofSize: size, weight: weight)
  field.isSelectable = false
  field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
  field.maximumNumberOfLines = wraps ? 0 : 1
  return field
}

// MARK: - Row

/// A settings row (section 4): a sidebar row in a group. Min height 36, radius 9, padding 6 / 8 / 6 / 10, a 13
/// medium label over a 12 `secondaryText` caption, trailing controls 12 after the text, hover `sidebarItemBackground`.
///
/// A planned row (decision 4) shows its label in `secondaryText`, its controls at 42 % and not enabled, and a caption
/// that ends "Not available yet."; VoiceOver reads its controls as dimmed. Every control carries the row label as its
/// accessibility label and the caption as its help.
@MainActor
final class SettingsRowView: SettingsBlockView {
  static let notAvailable = "Not available yet."

  private let leading: NSView?
  private let leadingSize: NSSize
  private let label: NSTextField
  private let caption: NSTextField?
  /// Inline keycaps after the caption text ("Also with" Shift Command D).
  private let captionAccessory: NSView?
  private(set) var trailing: [NSView]
  let isPlanned: Bool
  /// Dimmed like a planned row without the caption (Show the full URL while the Toolbar is off).
  private(set) var isDimmed = false
  private var hovering = false
  private var tracking: NSTrackingArea?
  private let hoverable: Bool

  init(label text: String, caption captionText: String? = nil, captionAccessory: NSView? = nil,
       leading: NSView? = nil, leadingSize: NSSize = NSSize(width: 20, height: 20), trailing: [NSView] = [],
       planned: Bool = false, hoverable: Bool = true) {
    isPlanned = planned
    self.leading = leading
    self.leadingSize = leadingSize
    self.captionAccessory = captionAccessory
    self.trailing = trailing
    self.hoverable = hoverable && !planned
    label = settingsLabel(text, size: 13, weight: .medium)
    var full = captionText ?? ""
    if planned { full = full.isEmpty ? Self.notAvailable : "\(full) \(Self.notAvailable)" }
    caption = full.isEmpty ? nil : settingsLabel(full, size: 12)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.rowRadius
    layer?.cornerCurve = .continuous
    if let leading { addSubview(leading) }
    addSubview(label)
    if let caption { addSubview(caption) }
    if let captionAccessory { addSubview(captionAccessory) }
    trailing.forEach(addSubview)
    describeControls()
    applyDimming()
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  var labelText: String { label.stringValue }
  var captionText: String { caption?.stringValue ?? "" }
  var labelColor: RGBA {
    (isPlanned || isDimmed ? ShellTokens.secondaryText : ShellTokens.primaryText).resolve(archiveFlavor)
  }

  /// Replaces the trailing controls (the default-browser row's button and capsule).
  func setTrailing(_ views: [NSView]) {
    trailing.forEach { $0.removeFromSuperview() }
    trailing = views
    views.forEach(addSubview)
    describeControls()
    applyDimming()
    needsLayout = true
  }

  func setDimmed(_ dimmed: Bool) {
    guard dimmed != isDimmed else { return }
    isDimmed = dimmed
    applyDimming()
    restyle()
  }

  private func describeControls() {
    let help = caption?.stringValue
    for view in trailing {
      guard let control = view as? NSControl else { continue }
      if control.accessibilityLabel()?.isEmpty ?? true {
        control.setAccessibilityLabel(label.stringValue)
        control.cell?.setAccessibilityLabel(label.stringValue)
      }
      control.setAccessibilityHelp(help)
      control.cell?.setAccessibilityHelp(help)
    }
  }

  private func applyDimming() {
    let off = isPlanned || isDimmed
    for view in trailing {
      if let control = view as? NSControl { control.isEnabled = !off }
      switch view {
      case let pill as ArchivePillButton: pill.disabledOpacity = Float(SettingsTokens.disabledControlAlpha)
      case let link as ArchiveLinkButton: link.disabledOpacity = Float(SettingsTokens.disabledControlAlpha)
      default: view.alphaValue = off ? SettingsTokens.disabledControlAlpha : 1
      }
    }
  }

  private func restyle() {
    let flavor = archiveFlavor
    label.textColor = labelColor.nsColor()
    caption?.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    layer?.backgroundColor = hovering && hoverable && !isDimmed
      ? ShellTokens.sidebarItemBackground.resolve(flavor).cgColor : nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  // MARK: Layout

  private var controlsWidth: CGFloat {
    let widths = trailing.map { $0.intrinsicContentSize.width }
    return widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 8
  }

  private var textX: CGFloat {
    SettingsMetrics.rowPaddingLeading + (leading == nil ? 0 : leadingSize.width + 12)
  }

  private func textWidth(_ width: CGFloat) -> CGFloat {
    let controls = trailing.isEmpty ? 0 : controlsWidth + SettingsMetrics.rowGapToControl
    return max(40, width - textX - SettingsMetrics.rowPaddingTrailing - controls)
  }

  private func captionHeight(width: CGFloat) -> CGFloat {
    guard let caption else { return 0 }
    let accessory = captionAccessory?.intrinsicContentSize.height ?? 0
    return max(settingsTextHeight(caption, width: captionWidth(width)), accessory)
  }

  private func captionWidth(_ width: CGFloat) -> CGFloat {
    let text = textWidth(width)
    guard let captionAccessory, let caption else { return text }
    let accessory = captionAccessory.intrinsicContentSize.width + 4
    let natural = ceil((caption.stringValue as NSString).size(withAttributes: [.font: caption.font as Any]).width) + 4
    return min(natural, max(20, text - accessory))
  }

  private func textBlockHeight(width: CGFloat) -> CGFloat {
    let labelHeight = settingsTextHeight(label, width: textWidth(width))
    guard caption != nil else { return labelHeight }
    return labelHeight + SettingsMetrics.captionBelowLabel + captionHeight(width: width)
  }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    let padding = SettingsMetrics.rowPaddingTop + SettingsMetrics.rowPaddingBottom
    let control = trailing.map { $0.intrinsicContentSize.height }.max() ?? 0
    let glyph = leading == nil ? 0 : leadingSize.height
    return max(SettingsMetrics.rowMinHeight, textBlockHeight(width: width) + padding, control + padding,
               glyph + padding)
  }

  override func layout() {
    super.layout()
    let width = bounds.width
    let height = bounds.height
    if let leading {
      leading.frame = NSRect(x: SettingsMetrics.rowPaddingLeading, y: ((height - leadingSize.height) / 2).rounded(),
                             width: leadingSize.width, height: leadingSize.height)
    }
    let block = textBlockHeight(width: width)
    var y = ((height - block) / 2).rounded()
    let labelHeight = settingsTextHeight(label, width: textWidth(width))
    label.frame = NSRect(x: textX, y: y, width: textWidth(width), height: labelHeight)
    y += labelHeight + SettingsMetrics.captionBelowLabel
    if let caption {
      let captionHeight = captionHeight(width: width)
      let textHeight = settingsTextHeight(caption, width: captionWidth(width))
      caption.frame = NSRect(x: textX, y: y + ((captionHeight - textHeight) / 2).rounded(),
                             width: captionWidth(width), height: textHeight)
      if let captionAccessory {
        let size = captionAccessory.intrinsicContentSize
        captionAccessory.frame = NSRect(x: caption.frame.maxX + 4, y: y + ((captionHeight - size.height) / 2).rounded(),
                                        width: size.width, height: size.height)
      }
    }
    var x = width - SettingsMetrics.rowPaddingTrailing
    for view in trailing.reversed() {
      let size = view.intrinsicContentSize
      x -= size.width
      view.frame = NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
      x -= 8
    }
  }

  // MARK: Hover

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    guard hoverable else { return }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    restyle()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    restyle()
  }
}

extension NSView {
  /// The settings row this view sits in.
  var enclosingSettingsRow: SettingsRowView? {
    var view = superview
    while let current = view {
      if let row = current as? SettingsRowView { return row }
      view = current.superview
    }
    return nil
  }
}

// MARK: - Add row

/// The sidebar's New Tab row as an add action (New Profile..., Add Route...): 34 high, 14 leading, a 12 pt plus and
/// the label in `sidebarForeground`, `primaryText` on hover. A button, so the key view loop and VoiceOver reach it.
@MainActor
final class SettingsAddRowButton: NSButton {
  private let titleText: String
  private var hovering = false
  private var tracking: NSTrackingArea?

  init(title: String) {
    titleText = title
    super.init(frame: .zero)
    let cell = SettingsBlankCell()
    cell.focusRadius = SettingsMetrics.rowRadius
    self.cell = cell
    self.title = ""
    isBordered = false
    setButtonType(.momentaryChange)
    focusRingType = .default
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.rowRadius
    layer?.cornerCurve = .continuous
    setAccessibilityLabel(title.replacingOccurrences(of: "...", with: ""))
    cell.setAccessibilityLabel(accessibilityLabel())
    needsDisplay = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var isEnabled: Bool { didSet { needsDisplay = true } }

  override func draw(_ dirtyRect: NSRect) {
    let flavor = archiveFlavor
    let color = (hovering && isEnabled ? ShellTokens.primaryText : ShellTokens.sidebarForeground).resolve(flavor)
    let scale = window?.backingScaleFactor ?? 2
    let plus = SymbolImageCache.shared.symbol("plus", box: 12, weight: .medium, color: color, scale: scale)
    plus.draw(in: NSRect(x: SettingsMetrics.addRowLeading, y: ((bounds.height - 12) / 2).rounded(), width: 12,
                         height: 12))
    let font = NSFont.systemFont(ofSize: 13)
    let text = NSAttributedString(string: titleText, attributes: [.font: font, .foregroundColor: color.nsColor()])
    let line = ceil(font.ascender - font.descender + font.leading)
    text.draw(at: NSPoint(x: SettingsMetrics.addRowLeading + 12 + 8, y: ((bounds.height - line) / 2).rounded()))
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

/// An add row inside a group (block wrapper so it stacks with the rows).
@MainActor
final class SettingsAddRowView: SettingsBlockView {
  let button: SettingsAddRowButton

  init(title: String, planned: Bool) {
    button = SettingsAddRowButton(title: title)
    super.init(frame: .zero)
    addSubview(button)
    button.isEnabled = !planned
    button.alphaValue = planned ? SettingsTokens.disabledControlAlpha : 1
    if planned {
      button.setAccessibilityHelp(SettingsRowView.notAvailable)
      button.cell?.setAccessibilityHelp(SettingsRowView.notAvailable)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func fittingHeight(width: CGFloat) -> CGFloat { SettingsMetrics.addRowHeight }

  override func layout() {
    super.layout()
    button.frame = bounds
  }
}

// MARK: - Group, section, pane

/// A group (section 4): the Archive's recessed field, radius 10, 4 pt padding, rows 2 apart, no separators; a 1 pt
/// `separatorIncreasedContrast` edge under Increase Contrast.
@MainActor
final class SettingsGroupView: SettingsBlockView {
  let blocks: [SettingsBlockView]

  init(_ blocks: [SettingsBlockView]) {
    self.blocks = blocks
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.groupRadius
    layer?.cornerCurve = .continuous
    blocks.forEach(addSubview)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    let inner = width - SettingsMetrics.groupPadding * 2
    let rows = blocks.map { $0.fittingHeight(width: inner) }
    return rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * SettingsMetrics.rowGap
      + SettingsMetrics.groupPadding * 2
  }

  override func layout() {
    super.layout()
    let inner = bounds.width - SettingsMetrics.groupPadding * 2
    var y = SettingsMetrics.groupPadding
    for block in blocks {
      let height = block.fittingHeight(width: inner)
      block.frame = NSRect(x: SettingsMetrics.groupPadding, y: y, width: inner, height: height)
      y += height + SettingsMetrics.rowGap
    }
  }

  private func restyle() {
    let flavor = archiveFlavor
    layer?.backgroundColor = SettingsTokens.groupField.resolve(flavor).cgColor
    let increase = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    layer?.borderWidth = increase ? 1 : 0
    layer?.borderColor = SettingsTokens.separatorIncreasedContrast.resolve(flavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

/// A section: the sidebar's section title (12 semibold `secondaryText`, 10 leading, 6 below), one group or other
/// block, and an optional note (12 `secondaryText`, 8 below, max 560 wide).
@MainActor
final class SettingsSectionView: SettingsBlockView {
  private let title: NSTextField?
  let body: SettingsBlockView
  private let note: NSTextField?

  init(title: String?, body: SettingsBlockView, note: String? = nil) {
    self.title = title.map { settingsLabel($0, size: 12, weight: .semibold, wraps: false) }
    self.body = body
    self.note = note.map { settingsLabel($0, size: 12) }
    super.init(frame: .zero)
    if let titleField = self.title {
      titleField.setAccessibilityRole(.staticText)
      addSubview(titleField)
    }
    addSubview(body)
    if let note = self.note { addSubview(note) }
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private var titleHeight: CGFloat { title.map { ceil($0.intrinsicContentSize.height) } ?? 0 }

  private func noteWidth(_ width: CGFloat) -> CGFloat {
    min(SettingsMetrics.noteMaxWidth, width - SettingsMetrics.sectionTitleLeading * 2)
  }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    var height = body.fittingHeight(width: width)
    if title != nil { height += titleHeight + SettingsMetrics.sectionTitleBelow }
    if let note { height += SettingsMetrics.noteBelow + settingsTextHeight(note, width: noteWidth(width)) }
    return height
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 0
    if let title {
      title.frame = NSRect(x: SettingsMetrics.sectionTitleLeading, y: 0,
                           width: bounds.width - SettingsMetrics.sectionTitleLeading * 2, height: titleHeight)
      y = titleHeight + SettingsMetrics.sectionTitleBelow
    }
    let bodyHeight = body.fittingHeight(width: bounds.width)
    body.frame = NSRect(x: 0, y: y, width: bounds.width, height: bodyHeight)
    y += bodyHeight
    if let note {
      let width = noteWidth(bounds.width)
      note.frame = NSRect(x: SettingsMetrics.sectionTitleLeading, y: y + SettingsMetrics.noteBelow, width: width,
                          height: settingsTextHeight(note, width: width))
    }
  }

  private func restyle() {
    let color = ShellTokens.secondaryText.resolve(archiveFlavor).nsColor()
    title?.textColor = color
    note?.textColor = color
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

/// A pane: its sections top to bottom, 18 apart, inset 8 top, 16 sides, 20 bottom.
@MainActor
final class SettingsPaneView: SettingsBlockView {
  let pane: SettingsPane
  private(set) var blocks: [SettingsBlockView]

  init(pane: SettingsPane, blocks: [SettingsBlockView]) {
    self.pane = pane
    self.blocks = blocks
    super.init(frame: .zero)
    blocks.forEach(addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Replaces the blocks (the Shortcuts search).
  /// Blocks kept in the new list stay in place, so a search field keeps its focus while the results change.
  func setBlocks(_ newBlocks: [SettingsBlockView]) {
    for block in blocks where !newBlocks.contains(where: { $0 === block }) { block.removeFromSuperview() }
    for block in newBlocks where block.superview !== self { addSubview(block) }
    blocks = newBlocks
    needsLayout = true
  }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    let inner = width - SettingsMetrics.contentSide * 2
    let heights = blocks.map { $0.fittingHeight(width: inner) }
    return SettingsMetrics.contentTop + heights.reduce(0, +)
      + CGFloat(max(0, heights.count - 1)) * SettingsMetrics.sectionGap + SettingsMetrics.contentBottom
  }

  override func layout() {
    super.layout()
    let inner = bounds.width - SettingsMetrics.contentSide * 2
    var y = SettingsMetrics.contentTop
    for block in blocks {
      let height = block.fittingHeight(width: inner)
      block.frame = NSRect(x: SettingsMetrics.contentSide, y: y, width: inner, height: height)
      y += height + SettingsMetrics.sectionGap
    }
  }
}

/// A block holding one view at a fixed height (the search field, the footer line).
@MainActor
final class SettingsFixedBlock: SettingsBlockView {
  let content: NSView
  private let height: CGFloat
  private let place: @MainActor (NSView, NSRect) -> Void

  init(_ content: NSView, height: CGFloat, place: @escaping @MainActor (NSView, NSRect) -> Void = { $0.frame = $1 }) {
    self.content = content
    self.height = height
    self.place = place
    super.init(frame: .zero)
    addSubview(content)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func fittingHeight(width: CGFloat) -> CGFloat { height }

  override func layout() {
    super.layout()
    place(content, bounds)
  }
}
