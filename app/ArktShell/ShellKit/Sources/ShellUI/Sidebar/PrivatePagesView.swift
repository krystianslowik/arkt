import AppKit
import EngineAPI

/// One row of a private window's Pages list (#668): what the row draws of its page.
struct PrivatePageRowContent: Equatable {
  var tab: TabID
  var title: String
  var url: URL?
  var favicon: Data?
  var isShown: Bool
  /// The row's sound: a mute button while the page plays or is muted.
  var audio: TabAudio = .silent

  /// The row's text: the page title, else its address, else "Untitled".
  var displayTitle: String {
    if !title.isEmpty { return title }
    if let url { return url.host() ?? url.absoluteString }
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
  /// A row's close button: close its page.
  var onClose: (@MainActor (TabID) -> Void)?
  /// A row's mute button: mute or unmute its page.
  var onToggleMute: (@MainActor (TabID) -> Void)?
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

  /// Replaces the rows with `contents`, in that order. Rows are reused by page. A new row fades in and the rows that
  /// moved (below an added or closed row) slide to their place on `firm`, or jump under Reduce Motion. When the shown
  /// page changed (a click, an activation, a new page) its row scrolls into view; a page added without being shown
  /// does not scroll.
  func setPages(_ contents: [PrivatePageRowContent]) {
    let previousShown = self.contents.first(where: \.isShown)?.tab
    let byTab = Dictionary(rows.map { ($0.tab, $0) }, uniquingKeysWith: { first, _ in first })
    let before = Dictionary(rows.map { ($0.tab, $0.layer?.position) }, uniquingKeysWith: { first, _ in first })
    var next: [PrivatePageRowView] = []
    var added: [PrivatePageRowView] = []
    for content in contents {
      let existing = byTab[content.tab]
      let row = existing ?? makeRow(for: content.tab)
      if existing == nil { added.append(row) }
      row.flavor = flavor
      row.apply(content, favicon: faviconImages[content.tab])
      next.append(row)
    }
    let kept = Set(contents.map(\.tab))
    for row in rows where !kept.contains(row.tab) { row.removeFromSuperview() }
    for tab in faviconImages.keys where !kept.contains(tab) { faviconImages[tab] = nil }
    let changedOrder = rows.map(\.tab) != next.map(\.tab)
    rows = next
    self.contents = contents
    listView.setAccessibilityChildren(rows)
    loadFavicons()
    layoutRows()
    if changedOrder { animateRows(added: added, from: before) }
    if let shown = contents.first(where: \.isShown)?.tab, shown != previousShown { reveal(shown) }
    refreshFade()
  }

  private func makeRow(for tab: TabID) -> PrivatePageRowView {
    let row = PrivatePageRowView(tab: tab)
    row.onPress = { [weak self] tab in self?.onSelect?(tab) }
    row.onClose = { [weak self] tab in self?.onClose?(tab) }
    row.onToggleMute = { [weak self] tab in self?.onToggleMute?(tab) }
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

  /// The rows' motion after a row was added or closed: the layers of rows that moved start from where they were and
  /// slide to their new place; a new row fades in. Frames are already final.
  private func animateRows(added: [PrivatePageRowView], from before: [TabID: CGPoint?]) {
    let step = PrivatePagesMotion.rows(reduceMotion: reduceMotion())
    for row in added { PrivatePagesMotion.fadeIn(row.layer, duration: step.fadeDuration) }
    guard step.movesRows else { return }
    for row in rows {
      guard let layer = row.layer, let old = before[row.tab] ?? nil, old != layer.position else { continue }
      let move = CABasicAnimation(keyPath: "position")
      move.fromValue = NSValue(point: old)
      move.toValue = NSValue(point: layer.position)
      move.duration = step.duration
      move.timingFunction = step.curve.timingFunction
      layer.add(move, forKey: PrivatePagesMotion.moveKey)
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
