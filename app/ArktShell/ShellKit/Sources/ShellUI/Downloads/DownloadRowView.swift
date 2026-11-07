import AppKit
import QuartzCore
import EngineAPI

/// What a row's buttons do.
enum DownloadRowAction: Equatable {
  case cancel, open, showInFinder, retry, remove, review, keep, discard
}

/// One download as a row (design/downloads): a file tile, the name (middle-truncated, the extension stays visible), a
/// line of progress or outcome, and the buttons its state needs. The popover and the Library window use it with
/// different sizes; frames are set in `layout()`, never Auto Layout.
///
/// - Active: the 3 pt graphite bar under the line, and a Cancel x.
/// - Finished: Show in Finder and Open (Library: on hover or selection; the popover: always).
/// - Failed or cancelled: Retry and a Remove x.
/// - Held for a decision: Review (the one thing to do), and Remove stays out of the way.
@MainActor
final class DownloadRowView: NSView {
  enum Style { case popover, library }

  let style: Style
  private(set) var item: DownloadItem
  var onAction: (@MainActor (DownloadRowAction, DownloadID) -> Void)?
  /// Library: the row was clicked (selects it). A double click opens a finished file.
  var onSelect: (@MainActor (DownloadID) -> Void)?

  let tile = DownloadTileView(frame: .zero)
  let nameField = NSTextField(labelWithString: "")
  let statusField = NSTextField(labelWithString: "")
  let bar = ProgressBarView(frame: .zero)
  let cancelButton = DownloadIconButton(symbol: "xmark", label: "Cancel download")
  let showButton = DownloadIconButton(symbol: "folder", label: "Show in Finder")
  let removeButton = DownloadIconButton(symbol: "xmark", label: "Remove from list")
  let openPill = ArchivePillButton(style: .neutral, title: "Open", height: DownloadsMetrics.pill)
  let primaryOpenPill = ArchivePillButton(style: .primary, title: "Open", height: DownloadsMetrics.pill)
  let retryPill = ArchivePillButton(style: .neutral, title: "Retry", height: DownloadsMetrics.pill)
  let reviewPill = ArchivePillButton(style: .neutral, title: "Review", height: DownloadsMetrics.pill)
  let keepPill = ArchivePillButton(style: .neutral, title: "Keep", height: DownloadsMetrics.pill)
  let deletePill = ArchivePillButton(style: .destructive, title: "Delete", height: DownloadsMetrics.pill)

  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { bar.reduceMotion = reduceMotion }
  }

  /// Library: the row the keyboard or a click selected. Its Open pill is the mustard primary.
  var isSelected = false { didSet { if isSelected != oldValue { restyle(); needsLayout = true } } }
  private(set) var isHovered = false
  private var tracking: NSTrackingArea?

  init(style: Style, item: DownloadItem) {
    self.style = style
    self.item = item
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerCurve = .continuous
    layer?.cornerRadius = DownloadsMetrics.rowCorner
    for field in [nameField, statusField] {
      field.lineBreakMode = .byTruncatingMiddle
      field.isSelectable = false
      field.setAccessibilityElement(false)
      addSubview(field)
    }
    statusField.lineBreakMode = .byTruncatingTail
    for view in [tile, bar, cancelButton, showButton, removeButton, openPill, primaryOpenPill, retryPill, reviewPill, keepPill, deletePill] as [NSView] {
      addSubview(view)
    }
    wire(cancelButton, .cancel, AXID.Downloads.cancel)
    wire(showButton, .showInFinder, AXID.Downloads.showInFinder)
    wire(removeButton, .remove, AXID.Downloads.remove)
    wire(openPill, .open, AXID.Downloads.open)
    wire(primaryOpenPill, .open, AXID.Downloads.open)
    wire(retryPill, .retry, AXID.Downloads.retry)
    wire(reviewPill, .review, AXID.Downloads.review)
    wire(keepPill, .keep, AXID.Downloads.keep)
    wire(deletePill, .discard, AXID.Downloads.discard)
    bar.setAccessibilityIdentifier(AXID.Downloads.progress)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Downloads.row)
    update(item)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private static let actions: [DownloadRowAction] = [.cancel, .open, .showInFinder, .retry, .remove, .review, .keep, .discard]

  private func wire(_ button: NSButton, _ action: DownloadRowAction, _ identifier: String) {
    button.target = self
    button.action = #selector(buttonPressed(_:))
    button.tag = Self.actions.firstIndex(of: action) ?? 0
    button.setAccessibilityIdentifierWithCell(identifier)
  }

  @objc private func buttonPressed(_ sender: NSButton) {
    guard Self.actions.indices.contains(sender.tag) else { return }
    onAction?(Self.actions[sender.tag], item.id)
  }

  // MARK: Metrics

  private var tileSize: CGFloat { style == .popover ? DownloadsMetrics.tilePopover : DownloadsMetrics.tileLibrary }
  var rowHeight: CGFloat { style == .popover ? DownloadsMetrics.popoverRowMin : DownloadsMetrics.libraryRow }
  private var nameFont: NSFont { .systemFont(ofSize: 13, weight: .medium) }
  private var statusFont: NSFont { .systemFont(ofSize: 11.5) }

  // MARK: State

  /// The buttons this state shows, leading to trailing: what a test or the layout reads.
  enum Control: Equatable { case cancel, show, open, retry, review, remove, keep, delete }

  var visibleControls: [Control] {
    let held = item.dangerType.needsSheet
    // Uncommon but not dangerous: no sheet, Keep or Delete right on the row.
    if !held, item.dangerType.isUncommon, item.state == .complete { return [.keep, .delete] }
    switch item.state {
    case _ where held: return [.review, .remove]
    case .inProgress, .paused: return [.cancel]
    case .complete:
      if style == .popover { return [.show] }            // a click on the row opens the file
      return isHovered || isSelected ? [.show, .open] : []
    case .cancelled, .interrupted: return [.retry, .remove]
    }
  }

  var showsBar: Bool { item.state.isActive && !item.dangerType.needsSheet }

  func update(_ next: DownloadItem) {
    let previous = item
    item = next
    tile.configure(filename: next.filename, blocked: next.dangerType.needsSheet)
    nameField.stringValue = next.filename
    statusField.stringValue = style == .popover ? DownloadsFormat.popoverLine(next) : DownloadsFormat.libraryLine(next)
    if showsBar { bar.setFraction(next.fraction) }
    setAccessibilityLabel(DownloadsFormat.accessibilityLabel(next))
    setAccessibilityValue(next.id.rawValue)
    if previous.state != next.state || previous.dangerType != next.dangerType { crossFadeControls() }
    restyle()
    needsLayout = true
  }

  private func crossFadeControls() {
    guard window != nil, !reduceMotionNow else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = DownloadsMotion.swapDuration
    fade.timingFunction = DownloadsMotion.easeOut.timingFunction
    for view in controlViews() { view.layer?.add(fade, forKey: "swap") }
  }

  private var reduceMotionNow: Bool { reduceMotion() }

  private func controlViews() -> [NSView] { [bar, cancelButton, showButton, removeButton, openPill, primaryOpenPill, retryPill, reviewPill, keepPill, deletePill] }

  private func restyle() {
    let flavor = archiveFlavor
    nameField.font = nameFont
    statusField.font = statusFont
    nameField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    statusField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    let fill: RGBA? = isSelected ? DownloadsTokens.rowFill.resolve(flavor) : isHovered && style == .library
      ? DownloadsTokens.rowFill.resolve(flavor) : nil
    ArchiveMotion.set { layer?.backgroundColor = fill?.cgColor }
    let controls = visibleControls
    cancelButton.isHidden = !controls.contains(.cancel)
    showButton.isHidden = !controls.contains(.show)
    removeButton.isHidden = !controls.contains(.remove)
    retryPill.isHidden = !controls.contains(.retry)
    reviewPill.isHidden = !controls.contains(.review)
    keepPill.isHidden = !controls.contains(.keep)
    deletePill.isHidden = !controls.contains(.delete)
    openPill.isHidden = !controls.contains(.open) || isSelected && style == .library
    primaryOpenPill.isHidden = !controls.contains(.open) || !(isSelected && style == .library)
    bar.isHidden = !showsBar
    setAccessibilityChildren(controlViews().filter { !$0.isHidden })
  }

  // MARK: Layout

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let inset = DownloadsMetrics.rowInset
    let size = tileSize
    tile.frame = NSRect(x: inset + (style == .library ? 2 : 0), y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
    // Trailing buttons, right to left.
    var trailing = bounds.width - inset - (style == .library ? 2 : 0)
    func place(_ view: NSView, width: CGFloat? = nil) {
      guard !view.isHidden else { return }
      let width = width ?? (view as? NSControl)?.intrinsicContentSize.width ?? DownloadsMetrics.iconButton
      let height = view is ArchivePillButton ? DownloadsMetrics.pill : DownloadsMetrics.iconButton
      view.frame = NSRect(x: trailing - width, y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
      trailing = view.frame.minX - 6
    }
    place(removeButton); place(cancelButton)
    place(deletePill, width: deletePill.intrinsicContentSize.width)
    place(keepPill, width: keepPill.intrinsicContentSize.width)
    place(reviewPill, width: reviewPill.intrinsicContentSize.width)
    place(retryPill, width: retryPill.intrinsicContentSize.width)
    place(openPill, width: openPill.intrinsicContentSize.width)
    place(primaryOpenPill, width: primaryOpenPill.intrinsicContentSize.width)
    place(showButton)
    let textX = tile.frame.maxX + 10
    // `trailing + 6` is the left edge of the leftmost button (or the row's right edge): 8 pt of air before it.
    let textWidth = max(0, trailing + 6 - 8 - textX)
    let nameHeight: CGFloat = 16, statusHeight: CGFloat = 14, gap: CGFloat = 1
    let barBlock: CGFloat = showsBar ? DownloadsMetrics.barHeight + 5 : 0
    let block = nameHeight + gap + statusHeight + barBlock
    var y = ((bounds.height - block) / 2).rounded()
    nameField.frame = NSRect(x: textX, y: y, width: textWidth, height: nameHeight)
    y += nameHeight + gap
    statusField.frame = NSRect(x: textX, y: y, width: textWidth, height: statusHeight)
    y += statusHeight + 5
    bar.frame = NSRect(x: textX, y: y, width: textWidth, height: DownloadsMetrics.barHeight)
  }

  // MARK: Hover

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  /// The pointer is over the row (tests set it directly).
  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    restyle()
    needsLayout = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  // MARK: Motion

  /// The row appears: opacity 0 to 1 and 8 pt up over 0.24 s (Reduce Motion: the fade, 0.15 s).
  func playAppearance() {
    guard let layer, window != nil else { return }
    let step = DownloadsMotion.rowAppears(reduceMotion: reduceMotion())
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.duration
    fade.timingFunction = step.curve.timingFunction
    layer.add(fade, forKey: "appear.opacity")
    guard step.offset != 0 else { return }
    let rise = CABasicAnimation(keyPath: "transform.translation.y")
    rise.fromValue = step.offset
    rise.toValue = 0
    rise.duration = step.duration
    rise.timingFunction = step.curve.timingFunction
    layer.add(rise, forKey: "appear.transform")
  }

  /// The row leaves: opacity to 0 over 0.16 s, then `completion`.
  func playRemoval(completion: @escaping @MainActor () -> Void) {
    guard let layer, window != nil else { completion(); return }
    CATransaction.begin()
    CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = DownloadsMotion.removeDuration
    fade.timingFunction = DownloadsMotion.easeOut.timingFunction
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    layer.add(fade, forKey: "remove")
    CATransaction.commit()
  }

  // MARK: Clicks

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    guard style == .library else { return }
    onSelect?(item.id)
    if event.clickCount == 2, item.state == .complete, !item.dangerType.needsSheet { onAction?(.open, item.id) }
  }

  /// In the popover a click on a finished row opens the file.
  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    guard style == .popover, item.state == .complete, !item.dangerType.needsSheet else { return }
    onAction?(.open, item.id)
  }

  // MARK: Accessibility

  override func accessibilityPerformPress() -> Bool {
    guard item.state == .complete, !item.dangerType.needsSheet else { return false }
    onAction?(.open, item.id)
    return true
  }
}
