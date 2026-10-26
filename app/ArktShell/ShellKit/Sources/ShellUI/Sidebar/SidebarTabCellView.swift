import AppKit

/// Favicon (16 pt at x 10), title (14 pt medium at x 34), the audio button of a page that plays or is muted (#364)
/// and the hover close (X) button at the trailing edge (GS-043). Frames set in `layout()`; no constraints.
@MainActor
public final class SidebarTabCellView: NSTableCellView, NSTextFieldDelegate {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarTabCellView")

  public let faviconView = NSImageView()
  public let titleField = NSTextField(labelWithString: "")
  /// Shown while the row is hovered and the row has a close action. Its target and action are set by the
  /// outline controller; it is hidden (so neither hit-tested nor in the accessibility tree) otherwise.
  public let closeButton = HoverCloseButton()
  /// The page's sound (#364): shown while it plays or is muted, left of the X's slot so the hover X never moves it.
  /// A click mutes or unmutes; the outline sets its target and action.
  public let audioButton = HoverCloseButton()
  public private(set) var audio: TabAudio = .silent

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
    addSubview(audioButton)
    addSubview(closeButton)
    closeButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.rowClose)
    audioButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.rowAudio)
    audioButton.fadeDuration = SidebarMetrics.audioButtonFadeDuration
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
                        isClosing: Bool = false, audio: TabAudio = .silent) {
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
    let restyled = flavor != self.flavor || closeButton.image == nil
    if restyled {
      self.flavor = flavor
      closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
    }
    setAudio(audio, restyled: restyled)
    self.closeAction = closeAction
    closeButton.toolTip = closeAction?.tooltip
    closeButton.setAccessibilityLabel(closeAction?.tooltip)
    if closeAction == nil { setCloseButtonShown(false, animated: false) }
    needsLayout = true
  }

  /// Shows or hides the X (only when there is a close action), fading with the row's hover state. Only the button's
  /// opacity and hidden flag and the title's width change: two frames set directly, nothing else is laid out.
  public func setCloseButtonShown(_ shown: Bool, animated: Bool) {
    let shown = shown && closeAction != nil && renameField == nil
    guard shown != isCloseButtonShown || !animated else { return }   // unanimated calls always settle the state
    isCloseButtonShown = shown
    layoutTitle()
    closeButton.setShown(shown, animated: animated)
  }

  /// Shows the audio button for a page that plays or is muted, fading in or out when the sound starts or stops (it
  /// changes a few times an hour, not on every hover); the glyph swaps at once on a click, which is the feedback.
  private func setAudio(_ audio: TabAudio, restyled: Bool) {
    let changed = audio != self.audio
    guard changed || restyled else { return }
    let wasShown = self.audio != .silent
    self.audio = audio
    if let symbol = audio.symbolName {
      audioButton.image = SidebarGlyphs.audio(symbol, flavor: flavor, scale: shellBackingScale)
    }
    audioButton.toolTip = audio.tooltip
    audioButton.setAccessibilityLabel(audio.toggleTitle)
    let shown = audio != .silent
    if shown != wasShown || restyled {
      audioButton.setShown(shown, animated: changed && window != nil)
      layoutTitle()
    }
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    setCloseButtonShown(false, animated: false)
    if isRenaming { endRename(commit: true) }
  }

  // MARK: Rename (BH-026, design 4.1)

  /// The inline rename field: a native rounded text field over the title's bounds, 13 pt, the whole title selected,
  /// the system focus ring (`NSColor.keyboardFocusIndicatorColor`, so the accent color) and the system selection
  /// color. No brand color and no animation: the field is simply there.
  public private(set) var renameField: NSTextField?
  /// Called once when the field closes: the typed name on Return or focus loss, nil on Escape.
  private var onRenameEnd: (@MainActor (String?) -> Void)?
  private var renameCancelled = false
  public var isRenaming: Bool { renameField != nil }

  /// The rename field's font size (design 4.1) and height (the native rounded field at that size).
  static let renameFontSize: CGFloat = 13
  static let renameFieldHeight: CGFloat = 22

  /// Opens the field over the title with the title selected. False when the cell has no window or the field could
  /// not take focus (nothing changes then).
  @discardableResult
  public func beginRename(flavor: ThemeFlavor, onEnd: @escaping @MainActor (String?) -> Void) -> Bool {
    guard !isRenaming, let window else { return false }
    let field = NSTextField(string: titleField.stringValue)
    field.font = .systemFont(ofSize: Self.renameFontSize)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.focusRingType = .default
    field.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.lineBreakMode = .byClipping
    field.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    field.delegate = self
    field.setAccessibilityLabel("Tab name")
    renameField = field
    onRenameEnd = onEnd
    renameCancelled = false
    titleField.isHidden = true
    setCloseButtonShown(false, animated: false)
    addSubview(field)
    layoutRenameField()
    guard window.makeFirstResponder(field) else {
      endRename(commit: false)
      return false
    }
    field.currentEditor()?.selectAll(nil)
    NSAccessibility.post(element: field, notification: .focusedUIElementChanged)
    return true
  }

  /// Return commits, Escape cancels; both resign the field, so `controlTextDidEndEditing` is the single exit.
  /// A pasted newline arrives as `insertNewline` too in a single-line field, so it commits as well.
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === renameField else { return false }
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      renameCancelled = true
    case #selector(NSResponder.insertNewline(_:)):
      break
    default:
      return false
    }
    if window?.makeFirstResponder(nil) != true { endRename(commit: !renameCancelled) }
    return true
  }

  /// Return, Escape, a click elsewhere, the cell leaving its window: every way out ends here.
  public func controlTextDidEndEditing(_ notification: Notification) {
    guard (notification.object as? NSTextField) === renameField else { return }
    endRename(commit: !renameCancelled)
  }

  /// Closes the field (commit: hands the typed text on; else nil) and shows the title again.
  public func endRename(commit: Bool) {
    guard let field = renameField else { return }
    let typed = field.stringValue
    renameField = nil
    field.delegate = nil
    field.abortEditing()
    field.removeFromSuperview()
    titleField.isHidden = false
    let end = onRenameEnd
    onRenameEnd = nil
    end?(commit ? typed : nil)
  }

  /// The field takes the title's horizontal bounds and the native field height, centered on the row.
  private func layoutRenameField() {
    guard let field = renameField else { return }
    let height = Self.renameFieldHeight
    let x = SidebarMetrics.titleLeading - 4
    let end = bounds.width - SidebarMetrics.titleTrailing
    field.frame = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, end - x), height: height)
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
    if let symbol = audio.symbolName {
      audioButton.image = SidebarGlyphs.audio(symbol, flavor: flavor, scale: shellBackingScale)
    }
  }

  public override func layout() {
    super.layout()
    let size = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: SidebarMetrics.faviconLeading, y: ((bounds.height - size) / 2).rounded(),
                               width: size, height: size)
    let box = SidebarMetrics.closeButtonSize
    closeButton.frame = NSRect(x: bounds.width - SidebarMetrics.closeButtonTrailing - box,
                               y: ((bounds.height - box) / 2).rounded(), width: box, height: box)
    let audioBox = SidebarMetrics.audioButtonSize
    audioButton.frame = NSRect(x: closeButton.frame.minX - SidebarMetrics.audioButtonGap - audioBox,
                               y: ((bounds.height - audioBox) / 2).rounded(), width: audioBox, height: audioBox)
    layoutTitle()
    layoutRenameField()
  }

  /// The title ends before the audio button while there is one, else before the X while it is shown, else at the
  /// usual trailing inset.
  private func layoutTitle() {
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let titleX = SidebarMetrics.titleLeading
    let closeStart = bounds.width - SidebarMetrics.closeButtonTrailing - SidebarMetrics.closeButtonSize
    let end = if audio != .silent {
      closeStart - SidebarMetrics.audioButtonGap - SidebarMetrics.audioButtonSize - SidebarMetrics.closeButtonTitleGap
    } else if isCloseButtonShown {
      closeStart - SidebarMetrics.closeButtonTitleGap
    } else {
      bounds.width - SidebarMetrics.titleTrailing
    }
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

  /// The audio button's glyph (#364): `symbol` in the X's color, a little larger than the X.
  static func audio(_ symbol: String, flavor: ThemeFlavor, scale: CGFloat,
                    cache: SymbolImageCache = .shared) -> NSImage {
    cache.symbol(symbol, box: SidebarMetrics.audioButtonGlyphSize, weight: .semibold,
                 color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
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
