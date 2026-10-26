import AppKit

/// What one Folder Preview row shows.
struct FolderPreviewRow {
  var node: NodeID
  var title: String
  var favicon: NSImage
}

/// Folder Preview (BH-093, GS-019): a small floating list beside the sidebar with a search field on top, in the
/// window's root view above the page. Its surface, edge, shadow and highlight are the tab switcher's tokens, so the
/// two overlays read as one family. Frames are set directly; no Auto Layout.
///
/// Motion: it is shown by a hover, tens of times a day, so it is quick and quiet: it fades in and scales from 0.97
/// at its leading edge (toward the folder row) in 0.15 s on the strong ease-out, and fades out in 0.10 s. Reduce
/// Motion keeps the fades and drops the scale.
@MainActor
final class FolderPreviewView: NSView {
  static let width: CGFloat = 264
  static let padding: CGFloat = 6
  static let searchHeight: CGFloat = 28
  static let rowHeight: CGFloat = 28
  static let maximumVisibleRows = 8
  static let cornerRadius: CGFloat = 10
  static let rowCornerRadius: CGFloat = 6
  static let enterDuration: CFTimeInterval = 0.15
  static let exitDuration: CFTimeInterval = 0.10
  static let enterOpacityKey = "folderPreview.enter.opacity"
  static let enterScaleKey = "folderPreview.enter.scale"
  static let exitKey = "folderPreview.exit"
  /// The strong ease-out of the motion guidelines, as the tab switcher uses it.
  static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

  static func height(rows: Int) -> CGFloat {
    let listed = CGFloat(min(max(rows, 1), maximumVisibleRows)) * rowHeight
    return padding + searchHeight + padding + listed + padding
  }

  let searchField = NSTextField(string: "")
  private let searchGlyph = NSImageView()
  private let separator = CALayer()
  private let scrollView = NSScrollView()
  private let list = FolderPreviewListView()
  private let emptyField = NSTextField(labelWithString: "No Matching Tabs")
  private let surface = CALayer()
  private var dropLayers: [CALayer] = []
  private let highlightLayer = CALayer()
  private(set) var rowViews: [FolderPreviewRowView] = []
  private(set) var rowCount = 0
  private(set) var highlightedRow: Int?
  private(set) var flavor: ThemeFlavor = .light
  var reduceTransparency: @MainActor () -> Bool = {
    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
  }
  /// A row was clicked, or the pointer moved onto one.
  var onRowClick: (@MainActor (Int) -> Void)?
  var onRowHover: (@MainActor (Int) -> Void)?
  /// The pointer entered or left the preview.
  var onPointerInside: (@MainActor (Bool) -> Void)?
  private var trackingArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    for _ in 0..<2 {
      let drop = CALayer()
      drop.masksToBounds = false
      dropLayers.append(drop)
      layer?.addSublayer(drop)
    }
    surface.cornerRadius = Self.cornerRadius
    surface.cornerCurve = .continuous
    surface.borderWidth = 0.5
    layer?.addSublayer(surface)
    layer?.addSublayer(separator)
    searchGlyph.imageScaling = .scaleProportionallyUpOrDown
    searchGlyph.setAccessibilityElement(false)
    searchField.isBezeled = false
    searchField.isBordered = false
    searchField.drawsBackground = false
    searchField.focusRingType = .none
    searchField.font = .systemFont(ofSize: 13)
    searchField.placeholderString = "Search"
    searchField.usesSingleLineMode = true
    searchField.cell?.isScrollable = true
    searchField.cell?.wraps = false
    searchField.setAccessibilityLabel("Search folder")
    searchField.setAccessibilityIdentifier(AXID.FolderPreview.search)
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.borderType = .noBorder
    scrollView.documentView = list
    list.wantsLayer = true
    highlightLayer.cornerRadius = Self.rowCornerRadius
    highlightLayer.cornerCurve = .continuous
    list.layer?.addSublayer(highlightLayer)
    emptyField.font = .systemFont(ofSize: 13)
    emptyField.isHidden = true
    for view in [searchGlyph, searchField, scrollView, emptyField] as [NSView] {
      view.autoresizingMask = []
      addSubview(view)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.FolderPreview.panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func accessibilityChildren() -> [Any]? {
    [searchField] + Array(rowViews.prefix(rowCount)) as [Any]
  }

  // MARK: Content

  /// Fills the list and sizes the surface; `frame` is its new frame in the host.
  func show(title: String, rows: [FolderPreviewRow], highlighted: Int?, flavor: ThemeFlavor, frame: NSRect) {
    self.flavor = flavor
    setAccessibilityLabel(title)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    self.frame = frame
    applyColors()
    fill(rows, highlighted: highlighted)
    layoutChrome()
    CATransaction.commit()
  }

  /// New matches for the same preview (typing); the frame keeps its height until the next show.
  func update(rows: [FolderPreviewRow], highlighted: Int?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fill(rows, highlighted: highlighted)
    layoutChrome()
    CATransaction.commit()
  }

  func setHighlight(_ index: Int?) {
    highlightedRow = index
    for (offset, row) in rowViews.prefix(rowCount).enumerated() { row.isHighlighted = offset == index }
    CATransaction.begin()
    CATransaction.setDisableActions(true)                // a hover or an arrow key: no motion (tens a day)
    if let index {
      highlightLayer.isHidden = false
      highlightLayer.frame = rowFrame(index)
      list.scrollToVisible(rowFrame(index))
    } else {
      highlightLayer.isHidden = true
    }
    CATransaction.commit()
  }

  private func fill(_ rows: [FolderPreviewRow], highlighted: Int?) {
    while rowViews.count < rows.count {
      let row = FolderPreviewRowView(frame: .zero)
      let index = rowViews.count
      row.onClick = { [weak self] in self?.onRowClick?(index) }
      row.onHover = { [weak self] in self?.onRowHover?(index) }
      rowViews.append(row)
      list.addSubview(row)
    }
    rowCount = rows.count
    for (index, row) in rowViews.enumerated() {
      row.isHidden = index >= rows.count
      guard index < rows.count else { continue }
      row.configure(rows[index], flavor: flavor)
      row.frame = rowFrame(index)
    }
    emptyField.isHidden = !rows.isEmpty
    setHighlight(highlighted)
  }

  private func rowFrame(_ index: Int) -> NSRect {
    NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: Self.width - 2 * Self.padding, height: Self.rowHeight)
  }

  private func layoutChrome() {
    let p = Self.padding
    surface.frame = bounds
    let shape = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                       transform: nil)
    for drop in dropLayers {
      drop.frame = bounds
      drop.shadowPath = shape
    }
    let glyphSize: CGFloat = 14
    searchGlyph.frame = NSRect(x: p + 6, y: p + (Self.searchHeight - glyphSize) / 2, width: glyphSize,
                               height: glyphSize)
    let fieldHeight: CGFloat = 18
    searchField.frame = NSRect(x: p + 6 + glyphSize + 6, y: p + (Self.searchHeight - fieldHeight) / 2,
                               width: bounds.width - (p + 6 + glyphSize + 6) - p - 6, height: fieldHeight)
    let listTop = p + Self.searchHeight + p
    separator.frame = NSRect(x: p, y: listTop - p / 2 - 0.25, width: bounds.width - 2 * p, height: 0.5)
    scrollView.frame = NSRect(x: p, y: listTop, width: bounds.width - 2 * p, height: bounds.height - listTop - p)
    list.frame = NSRect(x: 0, y: 0, width: scrollView.frame.width,
                        height: max(CGFloat(rowCount) * Self.rowHeight, scrollView.frame.height))
    emptyField.sizeToFit()
    emptyField.frame.origin = NSPoint(x: p + 10, y: listTop + (Self.rowHeight - emptyField.frame.height) / 2)
  }

  private func applyColors() {
    let surfaceColor = reduceTransparency() ? ShellTokens.toolbarSurface : ShellTokens.toastSurface
    surface.backgroundColor = surfaceColor.resolve(flavor).cgColor
    surface.borderColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    for (drop, shadow) in zip(dropLayers, ShellTokens.overlayShadow.drops(flavor)) {
      drop.shadowColor = shadow.color
      drop.shadowOpacity = shadow.opacity
      drop.shadowRadius = shadow.radius
      drop.shadowOffset = CGSize(width: 0, height: shadow.offsetY)        // the layer is flipped: y points down
    }
    highlightLayer.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    separator.backgroundColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor
    let primary = ShellTokens.primaryText.resolve(flavor)
    searchField.textColor = primary.nsColor()
    searchField.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    emptyField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    searchGlyph.image = SidebarGlyphs.symbol("magnifyingglass", flavor: flavor, scale: shellBackingScale)
  }

  // MARK: Motion

  /// Fades in and scales from 0.97 about the middle of the leading edge (the side of the folder row); Reduce
  /// Motion: the fade only.
  func animateIn(reduceMotion: Bool) {
    guard let layer else { return }
    layer.removeAnimation(forKey: Self.exitKey)
    layer.removeAnimation(forKey: Self.enterScaleKey)
    layer.opacity = 1
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = Float(0)
    fade.toValue = Float(1)
    fade.duration = Self.enterDuration
    fade.timingFunction = Self.easeOut
    layer.add(fade, forKey: Self.enterOpacityKey)
    guard !reduceMotion else { return }
    let pivot = CGPoint(x: 0, y: bounds.height / 2)
    var from = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
    from = CATransform3DScale(from, 0.97, 0.97, 1)
    from = CATransform3DTranslate(from, -pivot.x, -pivot.y, 0)
    let scale = CABasicAnimation(keyPath: "transform")
    scale.fromValue = NSValue(caTransform3D: from)
    scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    scale.duration = Self.enterDuration
    scale.timingFunction = Self.easeOut
    layer.add(scale, forKey: Self.enterScaleKey)
  }

  /// Fades out, then calls `completion`; without `animated` it is gone at once.
  func animateOut(animated: Bool, completion: @escaping @MainActor () -> Void) {
    guard let layer, animated else {
      completion()
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = Float(0)
    fade.duration = Self.exitDuration
    fade.timingFunction = Self.easeOut
    layer.opacity = 0
    layer.add(fade, forKey: Self.exitKey)
    CATransaction.commit()
  }

  // MARK: Pointer

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { onPointerInside?(true) }
  override func mouseExited(with event: NSEvent) { onPointerInside?(false) }
}

/// The preview's scrolling list: flipped, so row 0 is on top.
@MainActor
final class FolderPreviewListView: NSView {
  override var isFlipped: Bool { true }
}

/// One preview row: favicon and title. A click chooses it; the pointer over it highlights it.
@MainActor
final class FolderPreviewRowView: NSView {
  let faviconView = NSImageView()
  let titleField = NSTextField(labelWithString: "")
  var onClick: (@MainActor () -> Void)?
  var onHover: (@MainActor () -> Void)?
  var isHighlighted = false {
    didSet { setAccessibilitySelected(isHighlighted) }
  }
  private var trackingArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    titleField.font = .systemFont(ofSize: 13)
    titleField.lineBreakMode = .byTruncatingTail
    titleField.maximumNumberOfLines = 1
    titleField.cell?.truncatesLastVisibleLine = true
    for view in [faviconView, titleField] as [NSView] {
      view.autoresizingMask = []
      view.setAccessibilityElement(false)
      addSubview(view)
    }
    titleField.cell?.setAccessibilityElement(false)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier(AXID.FolderPreview.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  func configure(_ row: FolderPreviewRow, flavor: ThemeFlavor) {
    faviconView.image = row.favicon
    titleField.stringValue = row.title
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    setAccessibilityLabel(row.title)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let favicon = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: 8, y: (bounds.height - favicon) / 2, width: favicon, height: favicon)
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let x = 8 + favicon + 8
    titleField.frame = NSRect(x: x, y: (bounds.height - titleHeight) / 2, width: max(bounds.width - x - 8, 0),
                              height: titleHeight)
  }

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }

  override func mouseDown(with event: NSEvent) { onClick?() }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { onHover?() }
}
