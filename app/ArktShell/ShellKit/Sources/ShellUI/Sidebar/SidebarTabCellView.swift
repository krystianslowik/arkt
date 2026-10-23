import AppKit

/// Favicon (16 pt at x 10) and title (14 pt medium at x 34). Frames set in `layout()`; no constraints.
@MainActor
public final class SidebarTabCellView: NSTableCellView {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarTabCellView")

  public let faviconView = NSImageView()
  public let titleField = NSTextField(labelWithString: "")

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
    imageView = faviconView
    textField = titleField
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public func configure(title: String, image: NSImage, flavor: ThemeFlavor) {
    titleField.stringValue = title
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    faviconView.image = image
    needsLayout = true
  }

  public override func layout() {
    super.layout()
    let size = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: SidebarMetrics.faviconLeading, y: ((bounds.height - size) / 2).rounded(),
                               width: size, height: size)
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let titleX = SidebarMetrics.titleLeading
    titleField.frame = NSRect(x: titleX, y: ((bounds.height - titleHeight) / 2).rounded(),
                              width: max(0, bounds.width - titleX - SidebarMetrics.titleTrailing),
                              height: titleHeight)
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
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }

  public override func updateLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    line.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
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
  static func letter(for title: String, url: URL?, flavor: ThemeFlavor, size: CGFloat, scale: CGFloat,
                     cache: SymbolImageCache = .shared) -> NSImage {
    let source = url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? title
    let letter = source.first.map { String($0).uppercased() } ?? "?"
    let fill = ShellTokens.sidebarItemHovered.resolve(flavor)
    let ink = ShellTokens.primaryText.resolve(flavor)
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

  /// Row symbol in the row's text color for `flavor`.
  static func symbol(_ name: String, flavor: ThemeFlavor, scale: CGFloat,
                     cache: SymbolImageCache = .shared) -> NSImage {
    cache.symbol(name, box: SidebarMetrics.faviconSize, color: ShellTokens.primaryText.resolve(flavor), scale: scale)
  }
}
