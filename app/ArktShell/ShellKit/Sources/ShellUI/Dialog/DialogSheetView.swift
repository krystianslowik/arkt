import AppKit

/// Draws a `DialogContent` (docs/design/alerts-sheets-toasts.md, section 3.2) on the porcelain (graphite in dark)
/// surface, following the system appearance: icon, title, subtitle, body paragraphs, a recessed list, then the footer
/// link at the leading edge and the pills at the trailing edge (cancel, secondary, primary). Frames are set directly;
/// `fittingHeight` lays it out top down. The hosts (`DialogSheet`, `DialogPanel`, `DialogAlert`) size their window
/// from it and wire the answers.
@MainActor
final class DialogSheetView: NSView {
  /// Insets: 20 (16 in a panel, 24 at the top of an app-modal alert).
  struct Insets: Equatable {
    var top: CGFloat
    var side: CGFloat

    static let sheet = Insets(top: 20, side: 20)
    static let panel = Insets(top: 16, side: 16)
    static let alert = Insets(top: 24, side: 20)
  }

  static let besideIconSize: CGFloat = 32
  static let stackedIconSize: CGFloat = 56
  static let iconGap: CGFloat = 12
  static let paragraphGap: CGFloat = 12
  static let footerGap: CGFloat = 20
  static let stackedGap: CGFloat = 16
  static let buttonGap: CGFloat = 8
  static let bodyLineHeight: CGFloat = 19      // 13 pt at 1.45
  static let listMaxHeight: CGFloat = 260

  let content: DialogContent
  let insets: Insets
  let iconView: DialogIconView?
  let titleField = NSTextField(wrappingLabelWithString: "")
  let subtitleField: NSTextField?
  let paragraphFields: [NSTextField]
  /// The paragraphs inside a scroll view, when the content caps the body's height.
  let bodyScroll: NSScrollView?
  private let bodyContainer = FlippedView()
  /// The prompt's field, when the content has one.
  let inputView: DialogInputView?
  let listField: DialogListView?
  let footerLinkButton: ArchiveLinkButton?
  let primaryButton: ArchivePillButton
  let secondaryButton: ArchivePillButton?
  let cancelButton: ArchivePillButton?
  /// Called with the answer a button gave.
  var onAnswer: (@MainActor (DialogContent.Answer) -> Void)?
  /// Called when the footer link is pressed (the dialog stays).
  var onFooterLink: (@MainActor () -> Void)?
  /// Called when Escape closes a dialog whose content `escapeDismisses`.
  var onDismiss: (@MainActor () -> Void)?
  /// The time the input protection reads (seconds); tests inject it.
  var clock: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  private var protectedUntil: TimeInterval?

  init(content: DialogContent, insets: Insets = .sheet) {
    self.content = content
    self.insets = insets
    iconView = content.icon == .none ? nil : DialogIconView(icon: content.icon, size: content.iconPlacement == .stacked
      ? Self.stackedIconSize : Self.besideIconSize)
    subtitleField = content.subtitle.map { NSTextField(wrappingLabelWithString: $0) }
    paragraphFields = content.paragraphs.map { NSTextField(wrappingLabelWithString: $0.text) }
    bodyScroll = content.bodyMaxHeight == nil ? nil : NSScrollView()
    inputView = content.input.map { DialogInputView(input: $0) }
    listField = content.listItems.isEmpty ? nil : DialogListView(heading: content.listHeading, items: content.listItems)
    footerLinkButton = content.footerLink.map { ArchiveLinkButton(style: .secondary, title: $0, fontSize: 13) }
    primaryButton = ArchivePillButton(style: content.isDestructive ? .destructive
                                        : content.neutralPrimary ? .neutral : .primary,
                                      title: content.primaryTitle, metrics: .dialog)
    secondaryButton = content.secondaryTitle.map { ArchivePillButton(style: .neutral, title: $0, metrics: .dialog) }
    cancelButton = content.cancelTitle.map { ArchivePillButton(style: .neutral, title: $0, metrics: .dialog) }
    super.init(frame: NSRect(x: 0, y: 0, width: content.width, height: 160))
    wantsLayer = true
    build()
    _ = layoutContent(width: content.width)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.dialogSurface.resolve(archiveFlavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
    restyle()
  }

  private func build() {
    if let iconView { addSubview(iconView) }
    titleField.stringValue = content.title
    titleField.font = .systemFont(ofSize: 15, weight: .semibold)
    subtitleField?.font = .systemFont(ofSize: 12)
    for (field, paragraph) in zip(paragraphFields, content.paragraphs) {
      field.attributedStringValue = Self.body(paragraph.text)
    }
    for field in [titleField] + [subtitleField].compactMap({ $0 }) + paragraphFields {
      field.isSelectable = false
      if bodyScroll == nil || field === titleField || field === subtitleField { addSubview(field) }
    }
    if let bodyScroll {
      for field in paragraphFields { bodyContainer.addSubview(field) }
      bodyScroll.documentView = bodyContainer
      bodyScroll.drawsBackground = false
      bodyScroll.hasVerticalScroller = true
      bodyScroll.autohidesScrollers = true
      bodyScroll.scrollerStyle = .overlay
      bodyScroll.borderType = .noBorder
      addSubview(bodyScroll)
    }
    if let inputView { addSubview(inputView) }
    if let listField { addSubview(listField) }
    if let footerLinkButton {
      footerLinkButton.target = self
      footerLinkButton.action = #selector(footerLinkPressed(_:))
      addSubview(footerLinkButton)
    }
    for (button, action) in [(cancelButton, #selector(cancelPressed(_:))),
                             (secondaryButton, #selector(secondaryPressed(_:))),
                             (primaryButton, #selector(primaryPressed(_:)))] {
      guard let button else { continue }
      button.target = self
      button.action = action
      addSubview(button)
    }
    // Return presses the default button only; the destructive primary never has a key (section 3.2).
    switch content.defaultButton {
    case .primary: primaryButton.keyEquivalent = "\r"
    case .cancel: cancelButton?.keyEquivalent = "\r"
    case .none: break
    }
    primaryButton.hasDestructiveAction = content.isDestructive
    if let help = content.primaryHelp {
      primaryButton.setAccessibilityHelp(help)
      primaryButton.cell?.setAccessibilityHelp(help)
    }
    primaryButton.setArchiveAccessibilityLabel(content.primaryTitle)
    cancelButton?.setArchiveAccessibilityLabel(content.cancelTitle)
    secondaryButton?.setArchiveAccessibilityLabel(content.secondaryTitle)
    primaryButton.setAccessibilityIdentifierWithCell(AXID.Dialog.primary)
    cancelButton?.setAccessibilityIdentifierWithCell(AXID.Dialog.cancel)
    secondaryButton?.setAccessibilityIdentifierWithCell(AXID.Dialog.secondary)
    footerLinkButton?.setAccessibilityIdentifierWithCell(AXID.Dialog.footerLink)
    // Tab cycles footer link, then the buttons in order.
    let loop: [NSView] = [inputView?.field, footerLinkButton, cancelButton, secondaryButton, primaryButton]
      .compactMap { $0 }
    for (index, view) in loop.enumerated() { view.nextKeyView = loop[(index + 1) % loop.count] }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(content.title)
    setAccessibilityHelp(content.accessibilityDescription)
    setAccessibilityIdentifier(AXID.Dialog.root)
    restyle()
  }

  /// Where focus starts: the prompt's field when there is one, else the default button, otherwise Cancel (section 9).
  var initialFocus: NSView {
    if let field = inputView?.field { return field }
    return switch content.defaultButton {
    case .primary: primaryButton
    case .cancel, .none: cancelButton ?? primaryButton
    }
  }

  private static func body(_ text: String) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = bodyLineHeight
    paragraph.maximumLineHeight = bodyLineHeight
    return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                          .paragraphStyle: paragraph])
  }

  private func restyle() {
    let flavor = archiveFlavor
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    subtitleField?.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    for (field, paragraph) in zip(paragraphFields, content.paragraphs) {
      let color = (paragraph.isSecondary ? ShellTokens.secondaryText : ShellTokens.primaryText).resolve(flavor)
      let text = NSMutableAttributedString(attributedString: Self.body(paragraph.text))
      text.addAttribute(.foregroundColor, value: color.nsColor(), range: NSRange(location: 0, length: text.length))
      field.attributedStringValue = text
    }
  }

  // MARK: - Layout

  /// Lays the content out for `width` and returns the height it needs.
  func layoutContent(width: CGFloat) -> CGFloat {
    let side = insets.side
    var y = insets.top
    var textX = side
    if let iconView {
      switch content.iconPlacement {
      case .stacked:
        iconView.frame = NSRect(x: side, y: y, width: Self.stackedIconSize, height: Self.stackedIconSize)
        y += Self.stackedIconSize + 14
      case .beside:
        iconView.frame = NSRect(x: side, y: y, width: Self.besideIconSize, height: Self.besideIconSize)
        textX = side + Self.besideIconSize + Self.iconGap
      }
    }
    let textWidth = max(0, width - textX - side)
    let besideIcon = iconView != nil && content.iconPlacement == .beside
    y += besideIcon ? 5 : 0
    y = place(titleField, x: textX, y: y, width: textWidth)
    if let subtitleField { y = place(subtitleField, x: textX, y: y + 3, width: textWidth) }
    if let bodyScroll, let maxHeight = content.bodyMaxHeight {
      // Fields stack inside the scroll view's document; the view shows at most `maxHeight` of them.
      var inner: CGFloat = 0
      for (index, field) in paragraphFields.enumerated() {
        inner = place(field, x: 0, y: inner + (index == 0 ? 0 : Self.paragraphGap), width: textWidth)
      }
      bodyContainer.frame = NSRect(x: 0, y: 0, width: textWidth, height: inner)
      bodyScroll.frame = NSRect(x: textX, y: y + 10, width: textWidth, height: min(inner, maxHeight))
      y = bodyScroll.frame.maxY
    } else {
      for (index, field) in paragraphFields.enumerated() {
        y = place(field, x: textX, y: y + (index == 0 ? 10 : Self.paragraphGap), width: textWidth)
      }
    }
    if let inputView {
      inputView.frame = NSRect(x: textX, y: y + Self.paragraphGap, width: textWidth, height: DialogInputView.height)
      y = inputView.frame.maxY
    }
    if let listField {
      let height = min(listField.fittingHeight(width: textWidth), Self.listMaxHeight)
      listField.frame = NSRect(x: textX, y: y + Self.paragraphGap, width: textWidth, height: height)
      y = listField.frame.maxY
    }
    if besideIcon, let iconView { y = max(y, iconView.frame.maxY) }
    let height = DialogMetrics.buttonHeight
    if content.stackedButtons {
      // Full-width pills, primary first, 8 apart and 16 above (section 3.2).
      y += Self.stackedGap
      for button in [primaryButton, secondaryButton, cancelButton].compactMap({ $0 }) {
        button.frame = NSRect(x: side, y: y, width: max(0, width - 2 * side), height: height)
        y += height + Self.buttonGap
      }
      y -= Self.buttonGap + height
    } else {
      y += Self.footerGap
      var right = width - side
      for button in [primaryButton, secondaryButton, cancelButton].compactMap({ $0 }) {
        let buttonWidth = ceil(button.intrinsicContentSize.width)
        button.frame = NSRect(x: right - buttonWidth, y: y, width: buttonWidth, height: height)
        right = button.frame.minX - Self.buttonGap
      }
    }
    if let footerLinkButton {
      footerLinkButton.sizeToFit()
      let size = footerLinkButton.frame.size
      footerLinkButton.frame = NSRect(x: side, y: y + ((height - size.height) / 2).rounded(), width: size.width,
                                      height: size.height)
    }
    return y + height + side
  }

  private func place(_ field: NSTextField, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
    let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 18)
    field.frame = NSRect(x: x, y: y, width: width, height: height)
    return y + height
  }

  override func layout() {
    super.layout()
    _ = layoutContent(width: bounds.width)
  }

  /// What the prompt's field holds now; nil without a field.
  var inputText: String? { inputView?.field.stringValue }

  // MARK: - Answers

  /// Starts the input protection (`content.inputProtection`): until it has run out, button presses and Return answer
  /// nothing. Called when the dialog appears.
  func beginInputProtection() {
    protectedUntil = content.inputProtection > 0 ? clock() + content.inputProtection : nil
  }

  /// Whether presses are ignored now.
  var isInputProtected: Bool {
    guard let protectedUntil else { return false }
    return clock() < protectedUntil
  }

  @objc func primaryPressed(_ sender: Any?) { if !isInputProtected { onAnswer?(.primary) } }
  @objc func secondaryPressed(_ sender: Any?) { if !isInputProtected { onAnswer?(.secondary) } }
  @objc func cancelPressed(_ sender: Any?) { if !isInputProtected { onAnswer?(.cancel) } }
  @objc func footerLinkPressed(_ sender: Any?) { onFooterLink?() }

  /// Escape: closes a dialog that `escapeDismisses` without an answer; else Cancel when the dialog has one and Escape
  /// answers it. True when handled.
  func escape() -> Bool {
    if content.escapeDismisses {
      onDismiss?()
      return true
    }
    guard content.escapeAnswersCancel else { return false }
    onAnswer?(.cancel)
    return true
  }
}

/// A flipped container, so stacked fields keep a top-down origin.
final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// The prompt's field: a recessed rounded field (the Archive's `listField`, radius 8) holding a plain text field.
@MainActor
final class DialogInputView: NSView {
  static let height: CGFloat = 28
  let field = NSTextField(string: "")

  init(input: DialogContent.Input) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    field.stringValue = input.text
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.lineBreakMode = .byTruncatingTail
    field.cell?.usesSingleLineMode = true
    field.setAccessibilityLabel(input.accessibilityLabel)
    field.setAccessibilityIdentifier(AXID.Dialog.input)
    addSubview(field)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = ArchiveTokens.listField.resolve(archiveFlavor).cgColor
    field.textColor = ShellTokens.primaryText.resolve(archiveFlavor).nsColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    let height = ceil(field.intrinsicContentSize.height)
    field.frame = NSRect(x: 10, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 20),
                         height: height)
  }
}

enum DialogMetrics {
  static let buttonHeight: CGFloat = 28
  static let sheetCornerRadius: CGFloat = 14
  static let panelCornerRadius: CGFloat = 12
  static let alertCornerRadius: CGFloat = 14
}

// MARK: - Icon

/// The dialog's icon: the plain app icon, or a Space's theme swatch (32 pt, radius 8) with its mark centered.
@MainActor
final class DialogIconView: NSView {
  let icon: DialogContent.Icon

  init(icon: DialogContent.Icon, size: CGFloat) {
    self.icon = icon
    super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
    wantsLayer = true
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    switch icon {
    case .none:
      return
    case .appIcon:
      NSApp.applicationIconImage?.draw(in: bounds)
    case .spaceSwatch(let colors, let isDark, let mark):
      let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
      let stops = colors.isEmpty ? [ShellTokens.sidebarItemHovered.resolve(isDark ? .dark : .light)] : colors
      let gradient = NSGradient(colors: (stops.count == 1 ? stops + stops : stops).map { $0.nsColor() })
      gradient?.draw(in: path, angle: -45)
      NSColor.black.withAlphaComponent(0.08).setStroke()
      path.lineWidth = 1
      path.stroke()
      drawMark(mark, isDark: isDark)
    }
  }

  private func drawMark(_ mark: SpaceIconInfo?, isDark: Bool) {
    let color = (isDark ? ShellTokens.primaryText.dark : ShellTokens.primaryText.light).nsColor()
    switch mark {
    case .symbol(let name)?:
      guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)
          .applying(.init(paletteColors: [color]))) else { return }
      let size = image.size
      image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                            width: size.width, height: size.height))
    case .emoji(let text)?:
      let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 17)])
      let size = string.size()
      string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    case nil:
      color.setFill()
      NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
    }
  }
}

// MARK: - List

/// A recessed field (the Archive's `listField`, radius 10, padding 10 / 12, no edge) with an optional heading and
/// dotted items.
@MainActor
final class DialogListView: NSView {
  let headingField: NSTextField?
  let itemFields: [NSTextField]

  init(heading: String?, items: [String]) {
    headingField = heading.map { NSTextField(labelWithString: $0) }
    itemFields = items.map { NSTextField(wrappingLabelWithString: $0) }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.cornerCurve = .continuous
    headingField?.font = .systemFont(ofSize: 12, weight: .semibold)
    for field in itemFields { field.font = .systemFont(ofSize: 13) }
    for field in [headingField].compactMap({ $0 }) + itemFields { addSubview(field) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  func fittingHeight(width: CGFloat) -> CGFloat { layoutFields(width: width) }

  override func layout() {
    super.layout()
    _ = layoutFields(width: bounds.width)
  }

  @discardableResult
  private func layoutFields(width: CGFloat) -> CGFloat {
    var y: CGFloat = 10
    let inner = max(0, width - 24 - 13)
    if let headingField {
      headingField.sizeToFit()
      headingField.frame = NSRect(x: 12, y: y, width: width - 24, height: headingField.frame.height)
      y = headingField.frame.maxY + 6
    }
    for field in itemFields {
      let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 1000)).height ?? 18)
      field.frame = NSRect(x: 12 + 13, y: y, width: inner, height: height)
      y += height + 4
    }
    return y - (itemFields.isEmpty ? 0 : 4) + 10
  }

  override func draw(_ dirtyRect: NSRect) {
    let flavor = archiveFlavor
    layer?.backgroundColor = ArchiveTokens.listField.resolve(flavor).cgColor
    let edged = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    layer?.borderWidth = edged ? 1 : 0
    layer?.borderColor = AlertTokens.increasedContrastEdge.resolve(flavor).cgColor
    headingField?.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    for field in itemFields { field.textColor = ShellTokens.primaryText.resolve(flavor).nsColor() }
    ShellTokens.sidebarForeground.resolve(flavor).nsColor().setFill()
    for field in itemFields {
      NSBezierPath(ovalIn: NSRect(x: 12, y: field.frame.minY + 6.5, width: 5, height: 5)).fill()
    }
  }
}
