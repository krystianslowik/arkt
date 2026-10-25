import AppKit

/// Favicon (16 pt at x 10), title (14 pt medium at x 34) and the hover close (X) button at the trailing edge
/// (GS-043). Frames set in `layout()`; no constraints.
@MainActor
public final class SidebarTabCellView: NSTableCellView {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarTabCellView")

  public let faviconView = NSImageView()
  public let titleField = NSTextField(labelWithString: "")
  /// Shown while the row is hovered and the row has a close action. Its target and action are set by the
  /// outline controller; it is hidden (so neither hit-tested nor in the accessibility tree) otherwise.
  public let closeButton = HoverCloseButton()

  /// What the X does for this row; nil (folders) never shows it.
  public private(set) var closeAction: RowCloseAction?
  /// Whether the X is shown or fading in (the row is hovered and there is a close action).
  public private(set) var isCloseButtonShown = false
  private var flavor: ThemeFlavor = .light

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = Self.reuseIdentifier
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.autoresizingMask = []
    titleField.font = .systemFont(ofSize: SidebarMetrics.titleFontSize, weight: .medium)
    titleField.lineBreakMode = .byTruncatingTail
    titleField.maximumNumberOfLines = 1
    titleField.cell?.truncatesLastVisibleLine = true
    titleField.autoresizingMask = []
    addSubview(faviconView)
    addSubview(titleField)
    addSubview(closeButton)
    closeButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.rowClose)
    // The row's proxy lists this cell as its one child (#269); the title and the X sit under it.
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
    imageView = faviconView
    textField = titleField
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Opacity of a row's favicon and title while its close is held (week-3 Decision 11). [I]
  public static let closingAlpha: CGFloat = 0.45

  /// True while the row's page close waits on a leave-site prompt; the row is dimmed, without an animation (the
  /// state follows Cmd-W or a click, and the prompt itself is the feedback).
  public private(set) var isClosing = false

  public func configure(title: String, image: NSImage, flavor: ThemeFlavor, closeAction: RowCloseAction? = nil,
                        isClosing: Bool = false) {
    if isClosing != self.isClosing {
      self.isClosing = isClosing
      let alpha: CGFloat = isClosing ? Self.closingAlpha : 1
      titleField.alphaValue = alpha
      faviconView.alphaValue = alpha
      setAccessibilityValue(isClosing ? "Closing" : nil)
    }
    titleField.stringValue = title
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    faviconView.image = image
    if flavor != self.flavor || closeButton.image == nil {
      self.flavor = flavor
      closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
    }
    self.closeAction = closeAction
    closeButton.toolTip = closeAction?.tooltip
    closeButton.setAccessibilityLabel(closeAction?.tooltip)
    if closeAction == nil { setCloseButtonShown(false, animated: false) }
    needsLayout = true
  }

  /// Shows or hides the X (only when there is a close action), fading with the row's hover state. Only the button's
  /// opacity and hidden flag and the title's width change: two frames set directly, nothing else is laid out.
  public func setCloseButtonShown(_ shown: Bool, animated: Bool) {
    let shown = shown && closeAction != nil
    guard shown != isCloseButtonShown || !animated else { return }   // unanimated calls always settle the state
    isCloseButtonShown = shown
    layoutTitle()
    closeButton.setShown(shown, animated: animated)
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    setCloseButtonShown(false, animated: false)
  }

  /// The proxy of the row this cell is in (#269): the proxy lists the cell as its child. Outside a sidebar outline,
  /// the usual ancestor.
  public override func accessibilityParent() -> Any? {
    var ancestor = superview
    while let view = ancestor, !(view is SidebarOutlineView) { ancestor = view.superview }
    if let outline = ancestor as? SidebarOutlineView, let proxy = outline.axProxyRow(hosting: self) { return proxy }
    return super.accessibilityParent()
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
  }

  public override func layout() {
    super.layout()
    let size = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: SidebarMetrics.faviconLeading, y: ((bounds.height - size) / 2).rounded(),
                               width: size, height: size)
    let box = SidebarMetrics.closeButtonSize
    closeButton.frame = NSRect(x: bounds.width - SidebarMetrics.closeButtonTrailing - box,
                               y: ((bounds.height - box) / 2).rounded(), width: box, height: box)
    layoutTitle()
  }

  /// The title ends before the X while it is shown, else at the usual trailing inset.
  private func layoutTitle() {
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let titleX = SidebarMetrics.titleLeading
    let end = isCloseButtonShown
      ? bounds.width - SidebarMetrics.closeButtonTrailing - SidebarMetrics.closeButtonSize
        - SidebarMetrics.closeButtonTitleGap
      : bounds.width - SidebarMetrics.titleTrailing
    titleField.frame = NSRect(x: titleX, y: ((bounds.height - titleHeight) / 2).rounded(),
                              width: max(0, end - titleX), height: titleHeight)
  }
}

/// The hairline between pinned tabs and Today.
@MainActor
public final class SidebarDividerView: NSView {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarDividerView")
  private let line = CALayer()

  public var flavor: ThemeFlavor = .light {
    didSet { needsDisplay = true }
  }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = Self.reuseIdentifier
    wantsLayer = true
    layer?.addSublayer(line)
    setAccessibilityElement(true)
    setAccessibilityRole(.splitter)
    setAccessibilityIdentifier(AXID.Sidebar.divider)
  }

  public override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }

  public override func updateLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    line.backgroundColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor
    let scale = window?.backingScaleFactor ?? 2
    line.frame = CGRect(x: SidebarMetrics.faviconLeading, y: (bounds.height / 2).rounded(),
                        width: max(0, bounds.width - 2 * SidebarMetrics.faviconLeading), height: 1 / scale)
    CATransaction.commit()
  }

  public override func layout() {
    super.layout()
    needsDisplay = true
  }
}

/// Images for rows without a favicon yet: a letter tile, plus folder and split symbols. All are bitmaps
/// from `SymbolImageCache`, so displaying them during a Space swipe never re-rasterizes a glyph.
@MainActor
enum SidebarGlyphs {
  /// Fill and ink of the letter tile. Both depend on the flavor only, so the bitmap cache key needs no colors.
  static let letterFill = ShellTokens.letterTileFill
  static let letterInk = ShellTokens.primaryText

  static func letter(for title: String, url: URL?, flavor: ThemeFlavor, size: CGFloat, scale: CGFloat,
                     cache: SymbolImageCache = .shared) -> NSImage {
    let source = url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? title
    let letter = source.first.map { String($0).uppercased() } ?? "?"
    let fill = letterFill.resolve(flavor)
    let ink = letterInk.resolve(flavor)
    return cache.bitmap(key: "letter-\(letter)-\(flavor)", size: size, scale: scale) { rect in
      let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.25, yRadius: rect.height * 0.25)
      fill.nsColor().setFill()
      path.fill()
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: rect.height * 0.62, weight: .semibold),
        .foregroundColor: ink.nsColor(),
      ]
      let text = NSAttributedString(string: letter, attributes: attributes)
      let textSize = text.size()
      text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }
  }

  /// The hover close (X) glyph for `flavor` (GS-043).
  static func close(flavor: ThemeFlavor, scale: CGFloat, cache: SymbolImageCache = .shared) -> NSImage {
    cache.symbol("xmark", box: SidebarMetrics.closeButtonGlyphSize, weight: .semibold,
                 color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
  }

  /// Row symbol in the row's text color for `flavor`.
  static func symbol(_ name: String, flavor: ThemeFlavor, scale: CGFloat,
                     cache: SymbolImageCache = .shared) -> NSImage {
    cache.symbol(name, box: SidebarMetrics.faviconSize, color: ShellTokens.primaryText.resolve(flavor), scale: scale)
  }
}
