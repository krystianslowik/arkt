import AppKit

// MARK: - Chips

/// One active filter (design section 5): a 24 pt capsule with a leading mark (a Space's 7 pt dot, Little Arkt's
/// window glyph, or a close-type glyph), the filter's name and a 16 pt round remove button. A Space chip is tinted
/// with the Space's color at 16 % over the window surface; the others sit on `sidebarItemHovered`.
@MainActor
final class ArchiveChipView: NSView {
  enum Mark: Equatable {
    case dot(RGBA?)
    case symbol(String)
  }

  let filterName: String
  let mark: Mark
  let removeButton = NSButton(title: "", target: nil, action: nil)
  var onRemove: (@MainActor () -> Void)?
  private let label = NSTextField(labelWithString: "")
  private let markView = NSImageView()
  private let tinted: Bool

  init(name: String, mark: Mark, identifier: String) {
    filterName = name
    self.mark = mark
    if case .dot = mark { tinted = true } else { tinted = false }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = ArchiveMetrics.chipHeight / 2
    layer?.cornerCurve = .continuous
    label.stringValue = name
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.lineBreakMode = .byTruncatingTail
    label.setAccessibilityElement(false)
    label.cell?.setAccessibilityElement(false)
    markView.imageScaling = .scaleNone
    markView.setAccessibilityElement(false)
    removeButton.isBordered = false
    removeButton.bezelStyle = .regularSquare
    removeButton.imagePosition = .imageOnly
    removeButton.wantsLayer = true
    removeButton.layer?.cornerRadius = 8
    removeButton.target = self
    removeButton.action = #selector(removePressed(_:))
    removeButton.setArchiveAccessibilityLabel("Remove filter")
    [markView, label, removeButton].forEach(addSubview)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(name), filter")
    setAccessibilityIdentifier(identifier)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  override func accessibilityChildren() -> [Any]? { [removeButton] }

  /// The chip's opaque fill: a Space chip tints the surface with its color, a close-type chip uses the neutral fill.
  var displayedFill: RGBA {
    let flavor = archiveFlavor
    if case .dot(let color?) = mark {
      return ArchiveTokens.chipFill(color, over: BrandTokens.surfaceBrand.resolve(flavor))
    }
    return BrandTokens.composite(ShellTokens.sidebarItemHovered.resolve(flavor),
                                 over: BrandTokens.surfaceBrand.resolve(flavor))
  }

  var preferredWidth: CGFloat {
    let font = label.font ?? .systemFont(ofSize: 12, weight: .medium)
    let text = ceil((filterName as NSString).size(withAttributes: [.font: font]).width) + 4
    return 10 + markWidth + 6 + text + 6 + 16 + 5
  }

  private var markWidth: CGFloat {
    if case .dot = mark { return ArchiveMetrics.dotSize }
    return 12
  }

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    ArchiveMotion.set { layer?.backgroundColor = displayedFill.cgColor }
    label.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    switch mark {
    case .dot(let color):
      let fill = color ?? ShellTokens.sidebarForeground.resolve(flavor)
      markView.image = ArchiveGlyphs.dot(fill, size: ArchiveMetrics.dotSize, scale: scale)
    case .symbol(let name):
      markView.image = SymbolImageCache.shared.symbol(name, box: 12, color: ShellTokens.sidebarForeground.resolve(flavor),
                                                      scale: scale)
    }
    removeButton.image = SymbolImageCache.shared.symbol("xmark", box: 8, weight: .semibold,
                                                        color: ShellTokens.sidebarForeground.resolve(flavor),
                                                        scale: scale)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func layout() {
    super.layout()
    let h = bounds.height
    markView.frame = NSRect(x: 10, y: ((h - 12) / 2).rounded(), width: markWidth, height: 12)
    let labelHeight = ceil(label.intrinsicContentSize.height)
    let labelX = markView.frame.maxX + 6
    let removeX = bounds.width - 5 - 16
    label.frame = NSRect(x: labelX, y: ((h - labelHeight) / 2).rounded(), width: max(0, removeX - 6 - labelX),
                         height: labelHeight)
    removeButton.frame = NSRect(x: removeX, y: ((h - 16) / 2).rounded(), width: 16, height: 16)
  }

  @objc private func removePressed(_ sender: Any?) { onRemove?() }
}

/// The strip under the title bar while a filter is on: the chips, then a "Clear Filters" link 12 pt after the last.
@MainActor
final class ArchiveChipStrip: NSView {
  private(set) var chips: [ArchiveChipView] = []
  let clearFilters = ArchiveLinkButton(style: .secondary, title: "Clear Filters")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(clearFilters)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  func setChips(_ new: [ArchiveChipView]) {
    chips.forEach { $0.removeFromSuperview() }
    chips = new
    chips.forEach { addSubview($0) }
    needsLayout = true
  }

  /// Fades the strip in or out (150 ms); Reduce Motion shows and hides it at once.
  func setShown(_ shown: Bool, animated: Bool) {
    guard shown == isHidden || layer?.opacity != (shown ? 1 : 0) else { return }
    if shown { isHidden = false }
    let target: Float = shown ? 1 : 0
    guard animated, !ArchiveMotion.reduceMotion(), let layer else {
      layer?.opacity = target
      isHidden = !shown
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.layer?.opacity == 0 else { return }
        self.isHidden = true
      }
    }
    ArchiveMotion.animate(layer, "opacity", to: target, duration: ArchiveMotion.fadeDuration)
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    var x: CGFloat = 0
    for chip in chips {
      let width = min(chip.preferredWidth, max(0, bounds.width - x))
      chip.frame = NSRect(x: x, y: 0, width: width, height: ArchiveMetrics.chipHeight)
      x = chip.frame.maxX + ArchiveMetrics.chipSpacing
    }
    clearFilters.sizeToFit()
    let linkX = chips.isEmpty ? 0 : chips[chips.count - 1].frame.maxX + 12
    clearFilters.frame = NSRect(x: linkX, y: ((ArchiveMetrics.chipHeight - clearFilters.frame.height) / 2).rounded(),
                                width: clearFilters.frame.width, height: clearFilters.frame.height)
  }
}

// MARK: - Banner

/// The one-time auto-archive education banner (BH-089, design section 8): a rounded `sidebarItemBackground` card with
/// an `archivebox` tile, two lines, then Got It (a neutral pill) and an Open Settings link.
@MainActor
final class ArchiveBannerView: NSView {
  static let padding: CGFloat = 12
  static let tile: CGFloat = 32
  static let tileToText: CGFloat = 12
  static let textToActions: CGFloat = 10

  let headline = NSTextField(wrappingLabelWithString: "")
  let detail = NSTextField(wrappingLabelWithString: "")
  let gotIt = ArchivePillButton(style: .neutral, title: "Got It", height: ArchiveMetrics.smallPillHeight)
  let openSettings = ArchiveLinkButton(style: .secondary, title: "Open Settings")
  private let tileLayer = CALayer()
  private let glyph = NSImageView()

  init(banner: ArchiveBanner, showsSettings: Bool) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    tileLayer.cornerRadius = ArchiveMetrics.fieldRadius
    tileLayer.cornerCurve = .continuous
    layer?.addSublayer(tileLayer)
    headline.stringValue = banner.headline
    headline.font = .systemFont(ofSize: 12, weight: .semibold)
    detail.stringValue = banner.detail
    detail.font = .systemFont(ofSize: 12)
    for field in [headline, detail] {
      field.isSelectable = false
      field.setAccessibilityElement(false)
      field.cell?.setAccessibilityElement(false)
    }
    glyph.imageScaling = .scaleNone
    glyph.setAccessibilityElement(false)
    openSettings.isHidden = !showsSettings
    [glyph, headline, detail, gotIt, openSettings].forEach(addSubview)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(banner.headline) \(banner.detail)")
    setAccessibilityIdentifier(AXID.Archive.banner)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  override func accessibilityChildren() -> [Any]? {
    [gotIt, openSettings].filter { !$0.isHidden }
  }

  private func restyle() {
    let flavor = archiveFlavor
    ArchiveMotion.set {
      layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
      tileLayer.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    }
    headline.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    detail.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    glyph.image = SymbolImageCache.shared.symbol("archivebox", box: 16, color: ShellTokens.primaryText.resolve(flavor),
                                                 scale: window?.backingScaleFactor ?? 2)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private var textX: CGFloat { Self.padding + Self.tile + Self.tileToText }

  /// The card's height at `width`: padding, the two lines, the actions row, padding.
  func height(forWidth width: CGFloat) -> CGFloat {
    let textWidth = max(0, width - textX - Self.padding)
    let lines = textHeight(headline, textWidth) + 2 + textHeight(detail, textWidth)
    return Self.padding + lines + Self.textToActions + ArchiveMetrics.smallPillHeight + Self.padding
  }

  private func textHeight(_ field: NSTextField, _ width: CGFloat) -> CGFloat {
    ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 16)
  }

  override func layout() {
    super.layout()
    ArchiveMotion.set {
      tileLayer.frame = CGRect(x: Self.padding, y: Self.padding, width: Self.tile, height: Self.tile)
    }
    glyph.frame = NSRect(x: Self.padding, y: Self.padding, width: Self.tile, height: Self.tile)
    let width = max(0, bounds.width - textX - Self.padding)
    let headlineHeight = textHeight(headline, width)
    headline.frame = NSRect(x: textX, y: Self.padding, width: width, height: headlineHeight)
    let detailHeight = textHeight(detail, width)
    detail.frame = NSRect(x: textX, y: headline.frame.maxY + 2, width: width, height: detailHeight)
    let actionsY = detail.frame.maxY + Self.textToActions
    let gotItWidth = gotIt.intrinsicContentSize.width
    gotIt.frame = NSRect(x: textX, y: actionsY, width: gotItWidth, height: ArchiveMetrics.smallPillHeight)
    openSettings.sizeToFit()
    openSettings.frame = NSRect(
      x: gotIt.frame.maxX + 14, y: actionsY + ((ArchiveMetrics.smallPillHeight - openSettings.frame.height) / 2).rounded(),
      width: openSettings.frame.width, height: openSettings.frame.height)
  }
}

// MARK: - Glyph bitmaps

/// Small bitmaps the Archive window draws: the Space color dots.
@MainActor
enum ArchiveGlyphs {
  static func dot(_ color: RGBA, size: CGFloat, scale: CGFloat) -> NSImage {
    let key = "archive-dot-\(color.red)-\(color.green)-\(color.blue)-\(color.alpha)-\(color.space)"
    return SymbolImageCache.shared.bitmap(key: key, size: size, scale: scale) { rect in
      color.nsColor().setFill()
      NSBezierPath(ovalIn: rect).fill()
    }
  }
}
