import AppKit

// The Extensions pane's own views (#600): the 20 pt icon, the button that covers a row, and the details block.

/// An extension's 20 pt icon (section 4, leading glyph): its image clipped to radius 5, or the puzzle piece on a
/// neutral tile when it has none. Decorative: the row's name says what it is.
@MainActor
final class SettingsExtensionIcon: NSView {
  private let image: NSImage?

  init(png: Data?) {
    image = png.flatMap(NSImage.init(data:))
    super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func draw(_ dirtyRect: NSRect) {
    let clip = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
    if let image {
      NSGraphicsContext.saveGraphicsState()
      clip.addClip()
      image.draw(in: bounds)
      NSGraphicsContext.restoreGraphicsState()
      return
    }
    let flavor = archiveFlavor
    ShellTokens.sidebarItemHovered.resolve(flavor).nsColor().setFill()
    clip.fill()
    let glyph = SymbolImageCache.shared.symbol("puzzlepiece.extension", box: 12, weight: .medium,
                                               color: ShellTokens.sidebarForeground.resolve(flavor),
                                               scale: window?.backingScaleFactor ?? 2)
    glyph.draw(in: NSRect(x: 4, y: 4, width: 12, height: 12))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

/// A clear button over a whole settings row (`SettingsRowView.setRowButton`): a click on the row presses it, the key
/// view loop and VoiceOver reach it, and it draws `ShellTokens.focusRing` around the row while focused (#642). The row
/// draws its own hover.
@MainActor
final class SettingsRowButton: NSButton {
  private(set) lazy var keyboardFocusRing = KeyboardFocusRingView.attach(outside: self,
                                                                         radius: SettingsMetrics.rowRadius)

  init(label: String) {
    super.init(frame: .zero)
    cell = SettingsBlankCell()
    title = ""
    isBordered = false
    setButtonType(.momentaryChange)
    focusRingType = .none
    setAccessibilityLabel(label)
    cell?.setAccessibilityLabel(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      performClick(nil)
      return
    }
    super.keyDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { keyboardFocusRing.setFocused(true) }
    return became
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { keyboardFocusRing.setFocused(false) }
    return resigned
  }
}

/// An extension's details, right under its row in the group (#600): the row-shaped block of the shortcut conflict
/// notice (radius 9, `sidebarItemBackground`), its text aligned with the row's name. The description, a line with the
/// version and where it came from, then its actions in one line: Options... (a small neutral pill), Keyboard
/// Shortcuts... (a quiet link) and Remove... (a quiet red link), each only when it applies.
@MainActor
final class SettingsExtensionDetailsView: SettingsBlockView {
  private let summary: NSTextField?
  private let meta: NSTextField
  private let actions: [NSView]

  private static let top: CGFloat = 8
  private static let bottom: CGFloat = 12
  /// The row's name: leading padding, the 20 pt icon, 12 to the text.
  private static let textX: CGFloat = SettingsMetrics.rowPaddingLeading + 20 + 12

  init(description: String, meta metaText: String, actions: [NSView]) {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    summary = text.isEmpty ? nil : settingsLabel(text, size: 13)
    meta = settingsLabel(metaText, size: 12)
    self.actions = actions
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.rowRadius
    layer?.cornerCurve = .continuous
    if let summary { addSubview(summary) }
    addSubview(meta)
    actions.forEach(addSubview)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func textWidth(_ width: CGFloat) -> CGFloat {
    max(40, width - Self.textX - SettingsMetrics.rowPaddingTrailing)
  }

  private var actionsHeight: CGFloat { actions.map { $0.intrinsicContentSize.height }.max() ?? 0 }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    let text = textWidth(width)
    var height = Self.top
    if let summary { height += settingsTextHeight(summary, width: text) + 2 }
    height += settingsTextHeight(meta, width: text)
    if !actions.isEmpty { height += 10 + actionsHeight }
    return height + Self.bottom
  }

  override func layout() {
    super.layout()
    let width = textWidth(bounds.width)
    var y = Self.top
    if let summary {
      let height = settingsTextHeight(summary, width: width)
      summary.frame = NSRect(x: Self.textX, y: y, width: width, height: height)
      y += height + 2
    }
    let metaHeight = settingsTextHeight(meta, width: width)
    meta.frame = NSRect(x: Self.textX, y: y, width: width, height: metaHeight)
    y += metaHeight + 10
    var x = Self.textX
    let line = actionsHeight
    for view in actions {
      let size = view.intrinsicContentSize
      view.frame = NSRect(x: x, y: y + ((line - size.height) / 2).rounded(), width: size.width, height: size.height)
      x += size.width + 14
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
    summary?.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    meta.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }
}
