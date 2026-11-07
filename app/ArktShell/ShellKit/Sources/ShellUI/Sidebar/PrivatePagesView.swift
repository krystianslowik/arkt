import AppKit
import EngineAPI

/// One row of a private window's Pages list (#668): what the row draws of its page.
struct PrivatePageRowContent: Equatable {
  var tab: TabID
  var title: String
  var url: URL?
  var favicon: Data?
  var isShown: Bool

  /// The row's text: the page title, else its checked host or address (`HostDisplay`), else "Untitled".
  var displayTitle: String {
    if !title.isEmpty { return title }
    if let url { return HostDisplay.hostOrAddress(url) }
    return "Untitled"
  }
}

/// The Pages list of a blank or incognito window's sidebar (#668, design/private-pages, direction B): "Pages", then
/// one row per page of this window in open order, the shown page as the current row. Only the rows scroll; while
/// rows are hidden below, the list's last 28 pt fade out. A shown page's row scrolls into view; a page added in the
/// background does not move the list. Rows are AppKit views with frames set directly (a hot path, no Auto Layout).
@MainActor
final class PrivatePagesView: NSView {
  /// "Pages": 14 pt below the address bar, 6 pt above the first row, 8 pt in from the rows' leading edge.
  static let titleTopGap: CGFloat = 14
  static let titleBottomGap: CGFloat = 6
  static let titleInset: CGFloat = 8
  static let rowHeight: CGFloat = 34
  /// The list's fade while rows are hidden below it, as the sidebar banner fades the row list.
  static let fadeHeight: CGFloat = 28

  let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "Pages")
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.setAccessibilityElement(false)            // the list carries the name
    return label
  }()
  let scrollView = NSScrollView()
  let listView = PrivatePagesListView()
  private(set) var rows: [PrivatePageRowView] = []
  private(set) var contents: [PrivatePageRowContent] = []
  /// A click (or VoiceOver press) on a row: show its page.
  var onSelect: (@MainActor (TabID) -> Void)?
  /// Reduce Motion, read when a shown row scrolls into view: the scroll jumps. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The last row scrolled into view and whether it animated; for tests.
  private(set) var lastReveal: (tab: TabID, animated: Bool)?
  let fade = CAGradientLayer()
  private let favicons = FaviconImageLoader<TabID>()
  private var faviconImages: [TabID: NSImage] = [:]

  var flavor: ThemeFlavor = .light {
    didSet {
      guard flavor != oldValue else { return }
      applyColors()
      for row in rows { row.flavor = flavor }
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(titleLabel)
    scrollView.drawsBackground = false
    scrollView.contentView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.automaticallyAdjustsContentInsets = false   // no titlebar inset or scroll edge effect on the rows
    scrollView.contentInsets = NSEdgeInsetsZero
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.scrollerStyle = .overlay
    scrollView.autohidesScrollers = true
    scrollView.horizontalScrollElasticity = .none
    scrollView.documentView = listView
    scrollView.wantsLayer = true
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(clipMoved(_:)),
                                           name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    addSubview(scrollView)
    fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    setAccessibilityElement(false)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  /// The scroll view's layer settles its orientation when the window first draws, after the rows were set: the fade
  /// is oriented again on every display while it is on (`refreshFade` asks for one).
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() { orientFade() }

  /// Replaces the rows with `contents`, in that order. Rows are reused by page. When the shown page changed (a click,
  /// an activation, a new page) its row scrolls into view; a page added without being shown does not scroll.
  func setPages(_ contents: [PrivatePageRowContent]) {
    let previousShown = self.contents.first(where: \.isShown)?.tab
    let byTab = Dictionary(rows.map { ($0.tab, $0) }, uniquingKeysWith: { first, _ in first })
    var next: [PrivatePageRowView] = []
    for content in contents {
      let row = byTab[content.tab] ?? makeRow(for: content.tab)
      row.flavor = flavor
      row.apply(content, favicon: faviconImages[content.tab])
      next.append(row)
    }
    let kept = Set(contents.map(\.tab))
    for row in rows where !kept.contains(row.tab) { row.removeFromSuperview() }
    for tab in faviconImages.keys where !kept.contains(tab) { faviconImages[tab] = nil }
    rows = next
    self.contents = contents
    listView.setAccessibilityChildren(rows)
    loadFavicons()
    layoutRows()
    if let shown = contents.first(where: \.isShown)?.tab, shown != previousShown { reveal(shown) }
    refreshFade()
  }

  private func makeRow(for tab: TabID) -> PrivatePageRowView {
    let row = PrivatePageRowView(tab: tab)
    row.onPress = { [weak self] tab in self?.onSelect?(tab) }
    listView.addSubview(row)
    return row
  }

  private func loadFavicons() {
    var batch: [TabID: Data] = [:]
    for content in contents { if let data = content.favicon { batch[content.tab] = data } }
    guard !batch.isEmpty else { return }
    favicons.load(batch) { [weak self] images in
      guard let self else { return }
      for (tab, image) in images {
        self.faviconImages[tab] = image
        self.rows.first { $0.tab == tab }?.setFavicon(image)
      }
    }
  }

  // MARK: Layout

  override func layout() {
    super.layout()
    let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
    titleLabel.frame = NSRect(x: Self.titleInset, y: Self.titleTopGap, width: max(0, bounds.width - Self.titleInset),
                              height: titleHeight)
    let listTop = titleLabel.frame.maxY + Self.titleBottomGap
    let frame = NSRect(x: 0, y: listTop, width: bounds.width, height: max(0, bounds.height - listTop))
    if scrollView.frame != frame { scrollView.frame = frame }
    layoutRows()
    refreshFade()
  }

  private func layoutRows() {
    let width = scrollView.contentSize.width
    let height = CGFloat(rows.count) * Self.rowHeight
    let size = NSSize(width: width, height: height)
    if listView.frame.size != size { listView.setFrameSize(size) }
    for (index, row) in rows.enumerated() {
      let frame = NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: width, height: Self.rowHeight)
      if row.frame != frame { row.frame = frame }
    }
  }

  /// Rows hidden below the visible part of the list.
  var hasRowsBelow: Bool {
    let clip = scrollView.contentView.bounds
    return listView.frame.height - clip.maxY > 0.5
  }

  @objc private func clipMoved(_ note: Notification) { refreshFade() }

  /// The mask costs an offscreen pass per frame the list draws, so it is on only while rows are hidden below.
  private func refreshFade() {
    guard let layer = scrollView.layer else { return }
    guard hasRowsBelow else {
      if layer.mask != nil { layer.mask = nil }
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let height = scrollView.bounds.height
    fade.frame = scrollView.bounds
    let start = height > 0 ? max(0, (height - Self.fadeHeight) / height) : 0
    fade.locations = [0, NSNumber(value: Double(start)), 1]
    orientFade()
    if layer.mask !== fade { layer.mask = fade }
    CATransaction.commit()
    needsDisplay = true
  }

  /// From the top of the list to its bottom, in the masked layer's own y direction (as the sidebar banner's fade).
  private func orientFade() {
    guard let layer = scrollView.layer else { return }
    let flipped = layer.contentsAreFlipped()
    let start = CGPoint(x: 0.5, y: flipped ? 0 : 1)
    guard fade.startPoint != start else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fade.startPoint = start
    fade.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
    CATransaction.commit()
  }

  /// Scrolls `tab`'s row into view: the system scroll animation, or a jump under Reduce Motion.
  private func reveal(_ tab: TabID) {
    guard let row = rows.first(where: { $0.tab == tab }) else { return }
    let clip = scrollView.contentView
    let visible = clip.bounds
    var origin = visible.origin
    if row.frame.minY < visible.minY {
      origin.y = row.frame.minY
    } else if row.frame.maxY > visible.maxY {
      origin.y = row.frame.maxY - visible.height
    } else {
      lastReveal = (tab, false)
      return
    }
    origin.y = max(0, min(origin.y, listView.frame.height - visible.height))
    let animated = !reduceMotion() && window != nil
    lastReveal = (tab, animated)
    if animated {
      NSAnimationContext.runAnimationGroup { _ in clip.animator().setBoundsOrigin(origin) }
    } else {
      clip.setBoundsOrigin(origin)
    }
    scrollView.reflectScrolledClipView(clip)
    refreshFade()
  }

  private func applyColors() {
    titleLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }
}

/// The rows' container: the accessibility list "Pages".
@MainActor
final class PrivatePagesListView: NSView {
  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.list)
    setAccessibilityLabel("Pages")
    setAccessibilityIdentifier(AXID.PrivatePages.list)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A row of the Pages list: a 16 pt favicon, the title on one line truncating at the tail. The shown page's row is
/// the current row (`tabCurrent`, the current tab row's shadow in light). VoiceOver reads it as a button named by the
/// title; the shown page's row reads as selected.
@MainActor
final class PrivatePageRowView: NSView {
  static let padding: CGFloat = 9
  static let gap: CGFloat = 9
  static let faviconRadius: CGFloat = 4

  let tab: TabID
  let faviconView = NSImageView()
  let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.usesSingleLineMode = true
    label.cell?.truncatesLastVisibleLine = true
    label.cell?.isScrollable = false
    label.setAccessibilityElement(false)
    return label
  }()
  private let background = CALayer()
  var onPress: (@MainActor (TabID) -> Void)?
  private(set) var content: PrivatePageRowContent?
  private var favicon: NSImage?

  var flavor: ThemeFlavor = .light {
    didSet { if flavor != oldValue { applyStyle() } }
  }

  init(tab: TabID) {
    self.tab = tab
    super.init(frame: .zero)
    wantsLayer = true
    background.cornerRadius = SidebarMetrics.rowCornerRadius
    background.cornerCurve = .continuous
    background.shadowRadius = 2
    background.shadowOffset = CGSize(width: 0, height: -1)
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.wantsLayer = true
    faviconView.layer?.cornerRadius = Self.faviconRadius
    faviconView.layer?.masksToBounds = true
    faviconView.setAccessibilityElement(false)
    addSubview(faviconView)
    addSubview(titleLabel)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier(AXID.PrivatePages.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  var isShown: Bool { content?.isShown ?? false }

  func apply(_ content: PrivatePageRowContent, favicon: NSImage?) {
    let changed = content != self.content
    self.content = content
    if favicon != nil || content.favicon == nil { self.favicon = favicon }
    guard changed else { return }
    titleLabel.stringValue = content.displayTitle
    setAccessibilityLabel(content.displayTitle)
    setAccessibilitySelected(content.isShown)
    applyStyle()
  }

  func setFavicon(_ image: NSImage?) {
    favicon = image
    applyFavicon()
  }

  private func applyFavicon() {
    guard let content else { return }
    faviconView.image = favicon ?? SidebarGlyphs.letter(for: content.title, url: content.url, flavor: flavor,
                                                         size: SidebarMetrics.faviconSize, scale: shellBackingScale)
  }

  private func applyStyle() {
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    applyFavicon()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let shown = isShown
    background.backgroundColor = shown ? ShellTokens.tabCurrent.resolve(flavor).cgColor : nil
    let shadow = ShellTokens.tabCurrentShadow.resolve(flavor)
    background.shadowColor = shadow.cgColor
    background.shadowOpacity = shown && shadow.alpha > 0 ? 1 : 0
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // Below the subviews' layers, which AppKit adds after this one: the fill never covers the favicon or the title.
    if let layer, layer.sublayers?.first !== background { layer.insertSublayer(background, at: 0) }
    background.frame = bounds
    background.shadowPath = CGPath(roundedRect: bounds, cornerWidth: SidebarMetrics.rowCornerRadius,
                                   cornerHeight: SidebarMetrics.rowCornerRadius, transform: nil)
    CATransaction.commit()
    let icon = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: Self.padding, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
    let titleX = faviconView.frame.maxX + Self.gap
    let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
    titleLabel.frame = NSRect(x: titleX, y: ((bounds.height - titleHeight) / 2).rounded(),
                              width: max(0, bounds.width - Self.padding - titleX), height: titleHeight)
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onPress?(tab)
  }

  override func accessibilityPerformPress() -> Bool {
    onPress?(tab)
    return true
  }
}
