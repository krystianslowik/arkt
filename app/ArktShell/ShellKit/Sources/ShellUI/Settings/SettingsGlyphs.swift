import AppKit
import Motion

// MARK: - Leading glyphs

/// A Space's theme swatch: 20 x 20, radius 6, the theme's own gradient, the Space's icon on it. Decorative: the row
/// reads the Space.
@MainActor
final class SettingsSpaceSwatch: NSView {
  private let gradient = CAGradientLayer()
  private let icon = CATextLayer()

  init(colors: [RGBA], icon spaceIcon: SpaceIconInfo?) {
    super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    wantsLayer = true
    gradient.cornerRadius = 6
    gradient.cornerCurve = .continuous
    gradient.borderWidth = 0.5
    let stops = colors.isEmpty ? [RGBA.white(1)] : colors
    gradient.colors = (stops.count == 1 ? [stops[0], stops[0]] : stops).map(\.cgColor)
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    layer?.addSublayer(gradient)
    if case .emoji(let text)? = spaceIcon {
      icon.string = text
      icon.fontSize = 11
      icon.alignmentMode = .center
      gradient.addSublayer(icon)
    }
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layout() {
    super.layout()
    ArchiveMotion.set {
      gradient.frame = bounds
      gradient.borderColor = RGBA.black(0.12).cgColor
      icon.frame = CGRect(x: 0, y: 3, width: bounds.width, height: 14)
      icon.contentsScale = window?.backingScaleFactor ?? 2
    }
  }
}

/// A profile's monogram: 20 x 20, radius 5, its first letter in white on a color picked from its name.
@MainActor
final class SettingsMonogram: NSView {
  private static let fills: [RGBA] = [.srgb(hex: 0x7C8A6E), .srgb(hex: 0x5B7AA6), .srgb(hex: 0x8A6E7C),
                                      .srgb(hex: 0x6E7C8A), .srgb(hex: 0xA6845B)]
  private let letter: String
  private let fill: RGBA

  init(name: String) {
    letter = String(name.prefix(1)).uppercased()
    let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    fill = Self.fills[sum % Self.fills.count]
    super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    fill.nsColor().setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    let font = NSFont.systemFont(ofSize: 11, weight: .bold)
    let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = text.size()
    text.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()))
  }
}

/// A trailing disclosure chevron (a profile's or a permission's site list).
@MainActor
final class SettingsChevron: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: NSRect(x: 0, y: 0, width: 7, height: 12))
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: NSSize { NSSize(width: 7, height: 12) }

  override func draw(_ dirtyRect: NSRect) {
    let image = SymbolImageCache.shared.symbol("chevron.right", box: 12, weight: .semibold,
                                               color: ShellTokens.sidebarForeground.resolve(archiveFlavor),
                                               scale: window?.backingScaleFactor ?? 2)
    image.draw(in: NSRect(x: -2.5, y: 0, width: 12, height: 12))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

// MARK: - Empty state

/// The Archive's empty-state pattern inside a group: a 44 pt tile (radius 12, `sidebarItemBackground`) with a 22 pt
/// glyph, a 15 semibold title, a 12 `secondaryText` detail at most 320 wide, then the action 16 below.
@MainActor
final class SettingsEmptyStateBlock: SettingsBlockView {
  private let tile = CALayer()
  private let glyph = CALayer()
  private let symbol: String
  private let title: NSTextField
  private let detail: NSTextField
  let action: NSView

  init(symbol: String, title titleText: String, detail detailText: String, action: NSView) {
    self.symbol = symbol
    title = settingsLabel(titleText, size: 15, weight: .semibold, wraps: false)
    detail = settingsLabel(detailText, size: 12)
    detail.alignment = .center
    title.alignment = .center
    self.action = action
    super.init(frame: .zero)
    wantsLayer = true
    tile.cornerRadius = 12
    tile.cornerCurve = .continuous
    tile.addSublayer(glyph)
    layer?.addSublayer(tile)
    addSubview(title)
    addSubview(detail)
    addSubview(action)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func detailWidth(_ width: CGFloat) -> CGFloat { min(320, width - 48) }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    30 + 44 + 10 + ceil(title.intrinsicContentSize.height) + 4 + settingsTextHeight(detail, width: detailWidth(width))
      + 16 + action.intrinsicContentSize.height + 26
  }

  override func layout() {
    super.layout()
    let width = bounds.width
    var y: CGFloat = 30
    ArchiveMotion.set {
      tile.frame = CGRect(x: ((width - 44) / 2).rounded(), y: y, width: 44, height: 44)
      glyph.frame = CGRect(x: 11, y: 11, width: 22, height: 22)
    }
    y += 44 + 10
    let titleHeight = ceil(title.intrinsicContentSize.height)
    title.frame = NSRect(x: 0, y: y, width: width, height: titleHeight)
    y += titleHeight + 4
    let detailWidth = detailWidth(width)
    let detailHeight = settingsTextHeight(detail, width: detailWidth)
    detail.frame = NSRect(x: ((width - detailWidth) / 2).rounded(), y: y, width: detailWidth, height: detailHeight)
    y += detailHeight + 16
    let size = action.intrinsicContentSize
    action.frame = NSRect(x: ((width - size.width) / 2).rounded(), y: y, width: size.width, height: size.height)
  }

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    ArchiveMotion.set {
      tile.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
      let image = SymbolImageCache.shared.symbol(symbol, box: 22, color: ShellTokens.sidebarForeground.resolve(flavor),
                                                 scale: scale)
      glyph.contents = image.layerContents(forContentsScale: scale)
      glyph.contentsScale = scale
    }
    title.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    detail.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

// MARK: - Appearance preview

/// The Appearance pane's live preview (section 5): a small Arkt window in a Space's theme. Turning the Toolbar on
/// slides the strip down from above the page and moves the page by its height, both on `firm`, and fades the
/// sidebar's URL pill out over 0.15 s; Reduce Motion jumps.
@MainActor
final class SettingsAppearancePreview: NSView {
  static let size = NSSize(width: 236, height: 140)
  private let background = CAGradientLayer()
  private let sidebarURL = CALayer()
  private var sidebarRows: [CALayer] = []
  private var dots: [CALayer] = []
  private let card = CALayer()
  private let page = CALayer()
  private var pageLines: [CALayer] = []
  private let strip = CALayer()
  private let stripURL = CALayer()
  private(set) var showsToolbar = false
  private let gradient: [RGBA]

  init(gradient: [RGBA]) {
    self.gradient = gradient
    super.init(frame: NSRect(origin: .zero, size: Self.size))
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    background.startPoint = CGPoint(x: 0.2, y: 0)
    background.endPoint = CGPoint(x: 0.8, y: 1)
    layer?.addSublayer(background)
    for _ in 0..<3 {
      let dot = CALayer()
      dot.cornerRadius = 2
      dots.append(dot)
      layer?.addSublayer(dot)
    }
    sidebarURL.cornerRadius = 4
    layer?.addSublayer(sidebarURL)
    for _ in 0..<4 {
      let row = CALayer()
      row.cornerRadius = 3
      sidebarRows.append(row)
      layer?.addSublayer(row)
    }
    card.cornerRadius = 4
    card.masksToBounds = true
    layer?.addSublayer(card)
    card.addSublayer(page)
    for _ in 0..<6 {
      let line = CALayer()
      line.cornerRadius = 2
      pageLines.append(line)
      page.addSublayer(line)
    }
    card.addSublayer(strip)
    stripURL.cornerRadius = 2
    strip.addSublayer(stripURL)
    setAccessibilityElement(false)
    layoutLayers()
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { Self.size }

  private static let stripHeight: CGFloat = 14

  /// Shows or hides the Toolbar strip; `animated` springs it (a change made in Settings or a browser window).
  func setShowsToolbar(_ shows: Bool, animated: Bool) {
    showsToolbar = shows
    let reduce = SettingsMotion.reduceMotion() || !animated || window == nil
    SettingsMotion.spring(strip, "transform.translation.y", to: shows ? 0 : -Self.stripHeight, preset: .firm,
                          reduceMotion: reduce)
    SettingsMotion.spring(page, "transform.translation.y", to: shows ? Self.stripHeight : 0, preset: .firm,
                          reduceMotion: reduce)
    let opacity: Float = shows ? 0 : 1
    if reduce && !animated {
      ArchiveMotion.set { sidebarURL.opacity = opacity }
    } else {
      SettingsMotion.fade(sidebarURL, to: opacity, duration: SettingsMotion.crossFade)
    }
  }

  private func layoutLayers() {
    ArchiveMotion.set {
      background.frame = bounds
      for (index, dot) in dots.enumerated() {
        dot.frame = CGRect(x: 6 + CGFloat(index) * 7, y: 6, width: 4, height: 4)
      }
      sidebarURL.frame = CGRect(x: 6, y: 18, width: 44, height: 10)
      let widths: [CGFloat] = [44, 44, 44, 31]
      for (index, row) in sidebarRows.enumerated() {
        row.frame = CGRect(x: 6, y: 36 + CGFloat(index) * 11, width: widths[index], height: 7)
      }
      card.frame = CGRect(x: 58, y: 4, width: Self.size.width - 62, height: Self.size.height - 8)
      page.frame = card.bounds
      let lineWidths: [CGFloat] = [0.6, 1, 1, 0.8, 1, 0.55]
      var y: CGFloat = 10
      for (index, line) in pageLines.enumerated() {
        let height: CGFloat = index == 0 ? 9 : 5
        line.frame = CGRect(x: 10, y: y, width: (card.bounds.width - 20) * lineWidths[index], height: height)
        y += height + (index == 0 ? 8 : 5)
      }
      strip.frame = CGRect(x: 0, y: 0, width: card.bounds.width, height: Self.stripHeight)
      strip.setValue(-Self.stripHeight, forKeyPath: "transform.translation.y")
      stripURL.frame = CGRect(x: 8, y: 4.5, width: 70, height: 5)
    }
  }

  private func restyle() {
    let flavor = archiveFlavor
    let dark = flavor == .dark
    ArchiveMotion.set {
      let stops = gradient.isEmpty
        ? (dark ? [RGBA.srgb(hex: 0x2E3A4C), .srgb(hex: 0x1F2734)] : [RGBA.srgb(hex: 0xDCE8F7), .srgb(hex: 0xBFD3EE)])
        : gradient
      background.colors = (stops.count == 1 ? [stops[0], stops[0]] : stops).map(\.cgColor)
      dots.forEach { $0.backgroundColor = RGBA.black(0.18).cgColor }
      sidebarURL.backgroundColor = (dark ? RGBA.white(0.10) : .black(0.06)).cgColor
      for (index, row) in sidebarRows.enumerated() {
        let alpha = index == 0 ? (dark ? 0.22 : 0.9) : (dark ? 0.10 : 0.45)
        row.backgroundColor = RGBA.white(alpha).cgColor
      }
      let paper = dark ? RGBA.srgb(hex: 0x1E1F22) : .white(1)
      card.backgroundColor = paper.cgColor
      card.borderWidth = 0.5
      card.borderColor = (dark ? RGBA.white(0.08) : .black(0.10)).cgColor
      strip.backgroundColor = paper.cgColor
      stripURL.backgroundColor = (dark ? RGBA.white(0.12) : .black(0.12)).cgColor
      for (index, line) in pageLines.enumerated() {
        line.backgroundColor = (dark ? RGBA.white(index == 0 ? 0.24 : 0.12) : .black(index == 0 ? 0.18 : 0.10)).cgColor
      }
      layer?.borderWidth = 0.5
      layer?.borderColor = (dark ? RGBA.white(0.16) : .black(0.14)).cgColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

/// The preview row: the mini window and its explanation.
@MainActor
final class SettingsPreviewBlock: SettingsBlockView {
  let preview: SettingsAppearancePreview
  private let heading = settingsLabel("Preview", size: 13, weight: .semibold, wraps: false)
  private let text = settingsLabel(
    "Changes here apply to every window right away. The page follows the website setting below.", size: 12)

  init(gradient: [RGBA]) {
    preview = SettingsAppearancePreview(gradient: gradient)
    super.init(frame: .zero)
    addSubview(preview)
    addSubview(heading)
    addSubview(text)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func textWidth(_ width: CGFloat) -> CGFloat { max(40, width - 12 - SettingsAppearancePreview.size.width - 16 - 12) }

  override func fittingHeight(width: CGFloat) -> CGFloat { SettingsAppearancePreview.size.height + 24 }

  override func layout() {
    super.layout()
    preview.frame = NSRect(origin: NSPoint(x: 12, y: 12), size: SettingsAppearancePreview.size)
    let x = preview.frame.maxX + 16
    let width = textWidth(bounds.width)
    let headingHeight = ceil(heading.intrinsicContentSize.height)
    let textHeight = settingsTextHeight(text, width: width)
    var y = ((bounds.height - headingHeight - 4 - textHeight) / 2).rounded()
    heading.frame = NSRect(x: x, y: y, width: width, height: headingHeight)
    y += headingHeight + 4
    text.frame = NSRect(x: x, y: y, width: width, height: textHeight)
  }

  private func restyle() {
    let flavor = archiveFlavor
    heading.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    text.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

/// The app icon on the default-browser row: 32 pt, never redrawn.
@MainActor
final class SettingsAppIcon: NSImageView {
  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
    image = NSApp.applicationIconImage
    imageScaling = .scaleProportionallyUpOrDown
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
