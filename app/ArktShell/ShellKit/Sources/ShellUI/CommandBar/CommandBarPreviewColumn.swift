import AppKit
import EngineAPI
import ImageIO

/// Decodes a page thumbnail on the main actor after the well is already up. The image is at most 80 KB (#370),
/// so the decode does not hold the bar back; the request itself is the await.
enum CommandBarPreviewImage {
  static func cgImage(from image: PageImage) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(image.data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

/// The preview column beside the results (#372): hairline, thumbnail, title, meta, Split View and the one
/// mustard button. Frames are set in `layout()`. Keyboard only: the buttons refuse first responder and stay
/// out of the field's Tab order. VoiceOver reaches them as a group, "Preview, <title>".
@MainActor
final class CommandBarPreviewColumn: NSView {
  enum Transition: Equatable { case appear, crossfade, hide }

  private(set) var content: CommandBarPreview.Content?
  private(set) var lastTransition: Transition?
  /// Fades added for appear and crossfade. Reduce Motion still fades the content; only the width snaps.
  private(set) var contentFadeCount = 0
  /// The image on screen, if the matching request has arrived.
  private(set) var shownImage: CGImage?

  var onSplit: (() -> Void)?
  var onPrimary: (() -> Void)?

  private let hairline = NSView()
  private let well = NSView()
  private let imageLayer = CALayer()
  private let faviconView = NSImageView()
  private let symbolView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let dot = NSView()
  private let metaLabel = NSTextField(labelWithString: "")
  private let contentGroup = CommandBarPreviewContentGroup()
  let splitButton = CommandBarPreviewButton(frame: .zero)
  let primaryButton = CommandBarPreviewButton(frame: .zero)
  private var flavor: ThemeFlavor = .dark
  private var symbolName = "square.on.square"

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    isHidden = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.CommandBar.preview)

    hairline.wantsLayer = true
    well.wantsLayer = true
    well.layer?.cornerRadius = CommandBarGeometry.previewThumbnailRadius
    well.layer?.cornerCurve = .continuous
    well.layer?.masksToBounds = true
    imageLayer.contentsGravity = .resizeAspectFill
    imageLayer.isHidden = true
    well.layer?.addSublayer(imageLayer)
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    symbolView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.setAccessibilityElement(false)
    symbolView.setAccessibilityElement(false)
    well.addSubview(faviconView)
    well.addSubview(symbolView)

    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.usesSingleLineMode = true
    titleLabel.maximumNumberOfLines = 1
    metaLabel.font = .systemFont(ofSize: 11.5)
    metaLabel.lineBreakMode = .byTruncatingTail
    metaLabel.cell?.usesSingleLineMode = true
    metaLabel.maximumNumberOfLines = 1
    dot.wantsLayer = true
    dot.layer?.cornerRadius = CommandBarGeometry.previewOpenDot / 2
    titleLabel.setAccessibilityElement(false)
    metaLabel.setAccessibilityElement(false)
    dot.setAccessibilityElement(false)

    contentGroup.wantsLayer = true
    for view in [well, titleLabel, dot, metaLabel, splitButton, primaryButton] { contentGroup.addSubview(view) }
    addSubview(hairline)
    addSubview(contentGroup)

    splitButton.setAccessibilityIdentifier(AXID.CommandBar.previewSplit)
    primaryButton.setAccessibilityIdentifier(AXID.CommandBar.previewPrimary)
    splitButton.onPress = { [weak self] in self?.onSplit?() }
    primaryButton.onPress = { [weak self] in self?.onPrimary?() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Shows `next`, fading the content in. The same content does not restart the fade. Nil hides the column;
  /// the controller calls that only once the bar has narrowed.
  func setContent(_ next: CommandBarPreview.Content?, flavor: ThemeFlavor) {
    self.flavor = flavor
    guard next != content else {
      applyChrome()
      return
    }
    let previous = content
    content = next
    guard let next else {
      lastTransition = .hide
      shownImage = nil
      imageLayer.contents = nil
      isHidden = true
      return
    }
    symbolName = next.thumbnail.symbolName
    titleLabel.stringValue = next.title
    metaLabel.stringValue = next.meta
    dot.isHidden = !next.showsOpenDot
    splitButton.configure(title: next.splitTitle,
                          key: CommandBarKeyCaps.command + CommandBarKeyCaps.return,
                          primary: false, flavor: flavor)
    primaryButton.configure(title: next.primaryTitle, key: CommandBarKeyCaps.return, primary: true, flavor: flavor)
    setAccessibilityLabel("Preview, \(next.title)")
    applyChrome()
    isHidden = false
    needsLayout = true
    if previous == nil {
      lastTransition = .appear
    } else {
      lastTransition = .crossfade
    }
    fadeContent()
  }

  /// The neutral well, with a favicon when one is cached and the row's symbol otherwise. Clears a previous image
  /// so a stale frame cannot stay up while the next request is out.
  func showWell(favicon: NSImage?) {
    shownImage = nil
    imageLayer.contents = nil
    imageLayer.isHidden = true
    faviconView.image = favicon
    faviconView.isHidden = favicon == nil
    if favicon == nil { refreshSymbol() }
    symbolView.isHidden = favicon != nil
    needsLayout = true
  }

  /// Replaces the well. Nil keeps the well (the engine had no frame).
  func showImage(_ image: CGImage?) {
    guard let image else { return }
    shownImage = image
    imageLayer.contents = image
    imageLayer.isHidden = false
    faviconView.isHidden = true
    symbolView.isHidden = true
  }

  func apply(flavor: ThemeFlavor) {
    self.flavor = flavor
    applyChrome()
    guard let content else { return }
    splitButton.configure(title: content.splitTitle,
                          key: CommandBarKeyCaps.command + CommandBarKeyCaps.return,
                          primary: false, flavor: flavor)
    primaryButton.configure(title: content.primaryTitle, key: CommandBarKeyCaps.return, primary: true, flavor: flavor)
    refreshSymbol()
  }

  private func applyChrome() {
    hairline.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    well.layer?.backgroundColor = ShellTokens.commandBarThumbnailWell.resolve(flavor).cgColor
    titleLabel.textColor = ShellTokens.commandBarText.resolve(flavor).nsColor()
    metaLabel.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    dot.layer?.backgroundColor = ShellTokens.commandBarOpenDot.resolve(flavor).cgColor
  }

  private func refreshSymbol() {
    symbolView.image = SymbolImageCache.shared.symbol(symbolName, box: 22,
                                                      color: ShellTokens.commandBarTertiaryText.resolve(flavor),
                                                      scale: window?.backingScaleFactor ?? 2)
  }

  private func fadeContent() {
    contentFadeCount += 1
    guard let layer = contentGroup.layer else { return }
    layer.removeAnimation(forKey: "preview.fade")
    layer.opacity = 1
    layer.add(CommandBarMotion.animation(CommandBarMotion.appear), forKey: "preview.fade")
  }

  override func layout() {
    super.layout()
    let g = CommandBarGeometry.self
    let scale = window?.backingScaleFactor ?? 2
    let pad = g.previewColumnPadding
    hairline.frame = NSRect(x: 0, y: 0, width: 1 / scale, height: bounds.height)
    contentGroup.frame = bounds

    let buttonH = g.previewButtonHeight
    let buttonsY = bounds.height - pad - buttonH
    let textGap: CGFloat = 6
    let titleH: CGFloat = 18
    let metaH: CGFloat = 14
    // 12 + 116 + 6 + 18 + 2 + 14 + 30 + 12 = 210, which fits the five-row band (~212).
    let textBlock = textGap + titleH + 2 + metaH
    let room = buttonsY - pad - textBlock
    let thumbH = min(g.previewThumbnailHeight, max(0, room))
    let showThumb = thumbH >= 48
    well.isHidden = !showThumb
    let thumbW = bounds.width - 2 * pad
    if showThumb {
      well.frame = NSRect(x: pad, y: pad, width: max(0, thumbW), height: thumbH)
      imageLayer.frame = well.bounds
      let icon: CGFloat = faviconView.isHidden ? 22 : 32
      let iconFrame = NSRect(x: (well.bounds.width - icon) / 2, y: (well.bounds.height - icon) / 2,
                             width: icon, height: icon)
      faviconView.frame = iconFrame
      symbolView.frame = iconFrame
    }
    var y = showThumb ? well.frame.maxY + textGap : pad
    titleLabel.frame = NSRect(x: pad, y: y, width: max(0, thumbW), height: titleH)
    y = titleLabel.frame.maxY + 2
    let dotSize = g.previewOpenDot
    dot.frame = NSRect(x: pad, y: y + (metaH - dotSize) / 2, width: dotSize, height: dotSize)
    let metaX = dot.isHidden ? pad : dot.frame.maxX + 6
    metaLabel.frame = NSRect(x: metaX, y: y, width: max(0, bounds.width - pad - metaX), height: metaH)

    let gap: CGFloat = 6
    let inner = max(0, bounds.width - 2 * pad - gap)
    let splitW = inner / (1 + 1.25)
    splitButton.frame = NSRect(x: pad, y: buttonsY, width: splitW, height: buttonH)
    primaryButton.frame = NSRect(x: splitButton.frame.maxX + gap, y: buttonsY,
                                 width: max(0, bounds.width - pad - (splitButton.frame.maxX + gap)), height: buttonH)
  }

  override func isAccessibilityElement() -> Bool { !isHidden }

  override func accessibilityRole() -> NSAccessibility.Role? { .group }

  override func accessibilityLabel() -> String? {
    content.map { "Preview, \($0.title)" }
  }

  override func accessibilityChildren() -> [Any]? { isHidden ? [] : [splitButton, primaryButton] }
}

extension CommandBarPreview.Thumbnail {
  var symbolName: String {
    switch self {
    case .liveTab: "square.on.square"
    case .cachedPage: "clock"
    }
  }
}

/// Holds the column's text and controls. The column is flipped; this group has to be too, or the frames land
/// upside down inside it.
@MainActor
private final class CommandBarPreviewContentGroup: NSView {
  override var isFlipped: Bool { true }
}

/// One preview button. Mustard is the primary fill; its label is graphite. Not in the key loop.
@MainActor
final class CommandBarPreviewButton: NSView {
  var onPress: (() -> Void)?
  private let titleLabel = NSTextField(labelWithString: "")
  private let keyCap = CommandBarKeyCapView(frame: .zero)
  private(set) var isPrimary = false
  private var flavor: ThemeFlavor = .dark

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { false }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = CommandBarGeometry.previewButtonRadius
    layer?.cornerCurve = .continuous
    titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.usesSingleLineMode = true
    titleLabel.maximumNumberOfLines = 1
    titleLabel.setAccessibilityElement(false)
    keyCap.setAccessibilityElement(false)
    addSubview(titleLabel)
    addSubview(keyCap)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(title: String, key: String, primary: Bool, flavor: ThemeFlavor) {
    isPrimary = primary
    self.flavor = flavor
    titleLabel.stringValue = title
    keyCap.configure(key, flavor: flavor, metrics: .preview, tone: primary ? .onMustard : .neutral)
    setAccessibilityLabel(title)
    apply()
    needsLayout = true
  }

  private func apply() {
    if isPrimary {
      layer?.backgroundColor = BrandTokens.accent.resolve(flavor).cgColor
      titleLabel.textColor = BrandTokens.onAccent.resolve(flavor).nsColor()
    } else {
      layer?.backgroundColor = ShellTokens.commandBarKeyCap.resolve(flavor).cgColor
      titleLabel.textColor = ShellTokens.commandBarText.resolve(flavor).nsColor()
    }
  }

  override func layout() {
    super.layout()
    let cap = keyCap.size
    let labelH = ceil(titleLabel.fittingSize.height)
    let labelW = ceil(titleLabel.fittingSize.width)
    let gap: CGFloat = 7
    let group = labelW + gap + cap.width
    let yCap = (bounds.height - cap.height) / 2
    let yLabel = (bounds.height - labelH) / 2
    if group <= bounds.width - 8 {
      let x = (bounds.width - group) / 2
      titleLabel.frame = NSRect(x: x, y: yLabel, width: labelW, height: labelH)
      keyCap.frame = NSRect(x: titleLabel.frame.maxX + gap, y: yCap, width: cap.width, height: cap.height)
    } else {
      keyCap.frame = NSRect(x: bounds.width - 4 - cap.width, y: yCap, width: cap.width, height: cap.height)
      titleLabel.frame = NSRect(x: 4, y: yLabel, width: max(0, keyCap.frame.minX - 4 - gap), height: labelH)
    }
  }

  override func mouseDown(with event: NSEvent) { onPress?() }

  override func accessibilityPerformPress() -> Bool {
    onPress?()
    return true
  }

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityRole() -> NSAccessibility.Role? { .button }

  override func accessibilityLabel() -> String? { titleLabel.stringValue }
}
