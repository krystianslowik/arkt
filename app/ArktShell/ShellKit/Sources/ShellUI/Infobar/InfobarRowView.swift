import AppKit
import EngineAPI

/// Sizes of the infobar row (docs/design/alerts-sheets-toasts.md section 5). The row height is the engine's too:
/// `kArktInfobarRowHeight` reserves it at the top of the tab's container while the shell draws the row.
enum InfobarMetrics {
  static let rowHeight: CGFloat = 40
  static let inset: CGFloat = 12
  static let iconSize: CGFloat = 20
  static let gap: CGFloat = 8
  static let closeSize: CGFloat = 22
  static let messageFontSize: CGFloat = 13
  /// A row that appears fades in over 0.14 s; none fades out. Reduce Motion: instant.
  static let fadeDuration: CFTimeInterval = 0.14
}

/// The message of an infobar: one line, the end cut off with an ellipsis, inline links in the quiet link color. A link
/// click reports the substitution index the engine expects back.
@MainActor
final class InfobarMessageView: NSTextView, NSTextViewDelegate {
  var onLink: ((Int) -> Void)?
  private(set) var plainText = ""
  private var current: Infobar?

  /// The text system is kept here: the text view does not own its storage.
  private let storage = NSTextStorage()

  init() {
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    isEditable = false
    isSelectable = true
    drawsBackground = false
    isRichText = true                    // the colors and links are attributes of the text
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.maximumNumberOfLines = 1
    textContainer?.lineBreakMode = .byTruncatingTail
    textContainer?.widthTracksTextView = true
    textContainer?.heightTracksTextView = false
    isVerticallyResizable = false
    isHorizontallyResizable = false
    delegate = self
    setAccessibilityElement(false)       // the row speaks the message; its link and buttons are its children
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }
  /// A click on the message (a link, or a text selection) must not make the strip key: the page keeps its focus.
  override var needsPanelToBecomeKey: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  func show(_ infobar: Infobar) {
    current = infobar
    plainText = infobar.message
    toolTip = infobar.message
    let flavor = archiveFlavor
    linkTextAttributes = [
      .foregroundColor: ShellTokens.secondaryText.resolve(flavor).nsColor(),
      .cursor: NSCursor.pointingHand,
    ]
    let text = NSMutableAttributedString(string: infobar.message, attributes: [
      .font: NSFont.systemFont(ofSize: InfobarMetrics.messageFontSize),
      .foregroundColor: ShellTokens.primaryText.resolve(flavor).nsColor(),
    ])
    let length = (infobar.message as NSString).length
    for link in infobar.messageLinks where link.range.lowerBound >= 0 && link.range.upperBound <= length {
      text.addAttribute(.link, value: NSNumber(value: link.index),
                        range: NSRange(location: link.range.lowerBound, length: link.range.count))
    }
    textStorage?.setAttributedString(text)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    if let current { show(current) }
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let index = (link as? NSNumber)?.intValue else { return false }
    onLink?(index)
    return true
  }
}

/// The close button: a 22 pt round hover fill under a small cross, as the toast's dismiss button.
@MainActor
final class InfobarCloseButton: NSButton {
  private var hovering = false
  private var tracking: NSTrackingArea?

  init(label: String) {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    image = NSImage(systemSymbolName: "xmark", accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
    wantsLayer = true
    layer?.cornerRadius = InfobarMetrics.closeSize / 2
    layer?.cornerCurve = .continuous
    setArchiveAccessibilityLabel(label)
    toolTip = label
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
  override func mouseExited(with event: NSEvent) { hovering = false; restyle() }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }

  private func restyle() {
    let flavor = archiveFlavor
    contentTintColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    layer?.backgroundColor = hovering ? ShellTokens.sidebarItemHovered.resolve(flavor).cgColor : nil
  }
}

/// One infobar as a 40 pt row on the brand surface: icon, one line of message, a quiet link, the engine's buttons as
/// small neutral pills, and a close button. Clicks report an `InfobarAction`; the owner sends it to the engine and the
/// row goes when the engine's next list says so (a delegate may keep its infobar).
@MainActor
final class InfobarRowView: NSView {
  private(set) var infobar: Infobar
  var onAction: ((InfobarAction) -> Void)?

  let iconView = NSImageView()
  let message = InfobarMessageView()
  private(set) var linkButton: ArchiveLinkButton?
  private(set) var okButton: ArchivePillButton?
  private(set) var cancelButton: ArchivePillButton?
  private(set) var closeButton: InfobarCloseButton?
  private var hasIcon = false

  init(infobar: Infobar) {
    self.infobar = infobar
    super.init(frame: NSRect(x: 0, y: 0, width: 400, height: InfobarMetrics.rowHeight))
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Infobar.root)
    iconView.imageScaling = .scaleProportionallyDown
    iconView.setAccessibilityElement(false)
    addSubview(iconView)
    message.onLink = { [weak self] index in self?.onAction?(.messageLink(index)) }
    addSubview(message)
    build()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Shows `infobar`'s values: the same row stays when only a title or an enabled state changed.
  func update(_ infobar: Infobar) {
    guard infobar != self.infobar else { return }
    self.infobar = infobar
    for view in [linkButton, okButton, cancelButton, closeButton] as [NSView?] { view?.removeFromSuperview() }
    linkButton = nil; okButton = nil; cancelButton = nil; closeButton = nil
    build()
    needsLayout = true
  }

  private func build() {
    message.show(infobar)
    setAccessibilityLabel(infobar.message)
    if let data = infobar.iconPNG, let image = NSImage(data: data) {
      image.size = NSSize(width: InfobarMetrics.iconSize, height: InfobarMetrics.iconSize)
      iconView.image = image
      iconView.contentTintColor = nil
      hasIcon = true
    } else if let symbol = Self.symbol(for: infobar.kind),
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) {
      iconView.image = image
      iconView.contentTintColor = ShellTokens.secondaryText.resolve(archiveFlavor).nsColor()
      hasIcon = true
    } else {
      iconView.image = nil
      hasIcon = false
    }
    iconView.isHidden = !hasIcon
    if let title = infobar.linkTitle {
      let link = ArchiveLinkButton(style: .secondary, title: title, fontSize: InfobarMetrics.messageFontSize)
      link.target = self
      link.action = #selector(linkPressed(_:))
      link.setAccessibilityIdentifierWithCell(AXID.Infobar.link)
      if let label = infobar.linkAccessibilityLabel { link.setArchiveAccessibilityLabel(label) }
      addSubview(link)
      linkButton = link
    }
    okButton = makeButton(infobar.ok, id: AXID.Infobar.ok, action: #selector(okPressed(_:)))
    cancelButton = makeButton(infobar.cancel, id: AXID.Infobar.cancel, action: #selector(cancelPressed(_:)))
    if let label = infobar.closeLabel {
      let close = InfobarCloseButton(label: label)
      close.target = self
      close.action = #selector(closePressed(_:))
      close.setAccessibilityIdentifierWithCell(AXID.Infobar.close)
      addSubview(close)
      closeButton = close
    }
    // VoiceOver reads the message (the row's label), then the link, the buttons and the close button, in that order;
    // the icon is decoration.
    setAccessibilityChildren([linkButton, okButton, cancelButton, closeButton].compactMap { $0 })
  }

  private func makeButton(_ button: InfobarButton?, id: String, action: Selector) -> ArchivePillButton? {
    guard let button else { return nil }
    let pill = ArchivePillButton(style: .neutral, title: button.title, metrics: .infobar)
    pill.isEnabled = button.isEnabled
    pill.toolTip = button.tooltip
    pill.target = self
    pill.action = action
    pill.setArchiveAccessibilityLabel(button.title)
    if let tooltip = button.tooltip { pill.setAccessibilityHelp(tooltip); pill.cell?.setAccessibilityHelp(tooltip) }
    pill.setAccessibilityIdentifierWithCell(id)
    addSubview(pill)
    return pill
  }

  /// The glyph for an infobar whose engine sent no icon.
  static func symbol(for kind: InfobarKind) -> String? {
    switch kind {
    case .debugger: "ladybug"
    case .automation: "gearshape"
    case .reload: "arrow.clockwise"
    case .other: nil
    }
  }

  @objc private func okPressed(_ sender: Any?) { onAction?(.ok) }
  @objc private func cancelPressed(_ sender: Any?) { onAction?(.cancel) }
  @objc private func linkPressed(_ sender: Any?) { onAction?(.link) }
  @objc private func closePressed(_ sender: Any?) { onAction?(.close) }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    if infobar.iconPNG == nil, hasIcon { iconView.contentTintColor = ShellTokens.secondaryText.resolve(archiveFlavor).nsColor() }
  }

  // Frames are set directly (the row sits on the page card's hot path). Laid out left to right and mirrored for a
  // right-to-left interface: icon, message, then [link] OK, Cancel [link] and the close button at the far end.
  override func layout() {
    super.layout()
    let width = bounds.width
    let inset = InfobarMetrics.inset
    let gap = InfobarMetrics.gap
    let mirrored = userInterfaceLayoutDirection == .rightToLeft
    func place(_ view: NSView, x: CGFloat, size: NSSize) {
      let originX = mirrored ? width - x - size.width : x
      view.frame = NSRect(x: originX, y: ((InfobarMetrics.rowHeight - size.height) / 2).rounded(),
                          width: size.width, height: size.height)
    }
    var leading = inset
    if hasIcon {
      place(iconView, x: leading, size: NSSize(width: InfobarMetrics.iconSize, height: InfobarMetrics.iconSize))
      leading += InfobarMetrics.iconSize + gap
    }
    // The trailing group from the far end inward.
    var trailing = inset
    var trailingViews: [(NSView, NSSize)] = []
    if let closeButton { trailingViews.append((closeButton, NSSize(width: InfobarMetrics.closeSize, height: InfobarMetrics.closeSize))) }
    if let linkButton, !infobar.linkBeforeButtons { trailingViews.append((linkButton, linkButton.fittingSize)) }
    if let cancelButton { trailingViews.append((cancelButton, cancelButton.intrinsicContentSize)) }
    if let okButton { trailingViews.append((okButton, okButton.intrinsicContentSize)) }
    if let linkButton, infobar.linkBeforeButtons { trailingViews.append((linkButton, linkButton.fittingSize)) }
    for (view, size) in trailingViews {
      place(view, x: width - trailing - size.width, size: size)
      trailing += size.width + gap
    }
    let messageWidth = max(0, width - trailing - leading)
    let lineHeight = ceil(NSFont.systemFont(ofSize: InfobarMetrics.messageFontSize).boundingRectForFont.height)
    place(message, x: leading, size: NSSize(width: messageWidth, height: lineHeight))
  }

  // MARK: Entrance

  /// A row added to a list that is already up fades in (opacity only, so the page, which moved once, does not wait for
  /// it); Reduce Motion shows it at once.
  func fadeIn(reduceMotion: Bool) {
    guard !reduceMotion, let layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = InfobarMetrics.fadeDuration
    fade.timingFunction = ArchiveMotion.easeOut
    layer.add(fade, forKey: "infobarFade")
  }
}
