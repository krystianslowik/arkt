import AppKit
import EngineAPI

/// The Extensions panel's content (design/extensions, direction C, with the empty, none-pinned and small-window states
/// from #590): a scrolling list with the Pinned and Not pinned groups over a footer with Manage Extensions.... Rows are
/// kept by action id and only move when the engine reorders, so the keyboard focus stays on a row that moved. Frames
/// are set directly; a reload lays the list out at once.
///
/// Ordering: drag a pinned row by its grip (the row lifts, follows the pointer by its transform alone and a 2 pt line
/// marks the drop place), Cmd-Option-arrow on a focused pinned row, or the row's Move Left and Move Right
/// accessibility actions and context menu items.
@MainActor
final class ExtensionsPanelView: NSView {
  let scrollView = NSScrollView(frame: .zero)
  let list = ExtensionsListView(frame: .zero)
  private let pinnedHeader = ExtensionsPanelView.header("Pinned")
  private let unpinnedHeader = ExtensionsPanelView.header("Not pinned")
  let hintView = FlippedView(frame: .zero)
  private let hintGlyph = NSImageView(frame: .zero)
  private let hintLabel = NSTextField(wrappingLabelWithString: ExtensionsPanelCopy.hint)
  let emptyView = FlippedView(frame: .zero)
  private let emptyTile = CALayer()
  private let emptyGlyph = CALayer()
  private let emptyTitle = NSTextField(labelWithString: ExtensionsPanelCopy.emptyTitle)
  private let emptyBody = NSTextField(wrappingLabelWithString: ExtensionsPanelCopy.emptyBody)
  let browseButton = ArchivePillButton(style: .primary, title: ExtensionsPanelCopy.browse, metrics: .dialog)
  let manageButton = ArchiveLinkButton(style: .secondary, title: ExtensionsPanelCopy.manage, fontSize: 13)
  let insertionLine = NSView(frame: .zero)
  private let footerDivider = CALayer()
  private let fade = CAGradientLayer()

  private(set) var model = ExtensionsPanelModel(actions: [])
  private var rows: [String: ExtensionsPanelRow] = [:]
  /// The ids shown, top to bottom.
  private(set) var displayedRowIDs: [String] = []
  /// The list's height at the current width.
  private(set) var listHeight: CGFloat = 0

  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Increase Contrast: rows get a 1 pt edge (design/extensions, Light and dark).
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  /// Runs an action after a delay (the settle timeout); the controller passes its clock.
  var scheduleSettleTimeout: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { _, _ in }
  var onRun: (@MainActor (ExtensionAction, NSView) -> Void)?
  var onSetPinned: (@MainActor (String, Bool) -> Void)?
  /// Moves a pinned extension to an index in the pin order.
  var onMove: (@MainActor (String, Int) -> Void)?
  var onManage: (@MainActor () -> Void)?
  var onBrowseWebStore: (@MainActor () -> Void)?
  /// The context menu of an action (#596); every row asks it for a fresh one.
  var menuProvider: (@MainActor (String) -> NSMenu?)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.horizontalScrollElasticity = .none
    scrollView.documentView = list
    scrollView.wantsLayer = true
    addSubview(scrollView)
    list.setAccessibilityElement(true)
    list.setAccessibilityRole(.list)
    list.setAccessibilityLabel("Extensions")
    list.setAccessibilityIdentifier(AXID.Extensions.list)
    for view in [pinnedHeader, unpinnedHeader, hintView] as [NSView] { list.addSubview(view) }
    hintView.wantsLayer = true
    hintView.layer?.cornerRadius = ExtensionsPanelMetrics.rowCorner
    hintView.layer?.cornerCurve = .continuous
    hintView.layer?.borderWidth = 1
    hintLabel.font = .systemFont(ofSize: 12)
    hintLabel.setAccessibilityElement(false)
    hintView.addSubview(hintGlyph)
    hintView.addSubview(hintLabel)
    hintView.setAccessibilityElement(true)
    hintView.setAccessibilityRole(.staticText)
    hintView.setAccessibilityLabel(ExtensionsPanelCopy.hint)
    hintView.setAccessibilityIdentifier(AXID.Extensions.hint)
    insertionLine.wantsLayer = true
    insertionLine.layer?.cornerRadius = ExtensionsPanelMetrics.insertionLineRadius
    insertionLine.isHidden = true
    insertionLine.setAccessibilityElement(false)
    list.addSubview(insertionLine)

    emptyView.wantsLayer = true
    emptyTile.cornerRadius = ShellRadius.tile
    emptyTile.cornerCurve = .continuous
    emptyTile.addSublayer(emptyGlyph)
    emptyView.layer?.addSublayer(emptyTile)
    emptyTitle.font = .systemFont(ofSize: 14, weight: .semibold)
    emptyTitle.alignment = .center
    emptyBody.font = .systemFont(ofSize: 12.5)
    emptyBody.alignment = .center
    for view in [emptyTitle, emptyBody, browseButton] as [NSView] { emptyView.addSubview(view) }
    emptyView.setAccessibilityElement(true)
    emptyView.setAccessibilityRole(.group)
    emptyView.setAccessibilityLabel(ExtensionsPanelCopy.emptyTitle)
    emptyView.setAccessibilityIdentifier(AXID.Extensions.empty)
    browseButton.target = self
    browseButton.action = #selector(browsePressed(_:))
    browseButton.setAccessibilityIdentifierWithCell(AXID.Extensions.browseWebStore)
    addSubview(emptyView)

    manageButton.target = self
    manageButton.action = #selector(managePressed(_:))
    manageButton.setAccessibilityIdentifierWithCell(AXID.Extensions.manage)
    addSubview(manageButton)
    layer?.addSublayer(footerDivider)
    fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Extensions")
    setAccessibilityIdentifier(AXID.Extensions.panel)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  private static func header(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.setAccessibilityRole(.staticText)
    return label
  }

  @objc private func browsePressed(_ sender: Any?) { onBrowseWebStore?() }
  @objc private func managePressed(_ sender: Any?) { onManage?() }

  // MARK: Content

  var state: ExtensionsPanelModel.State { model.state }
  var hintText: String { hintLabel.stringValue }
  /// The group titles shown, top to bottom.
  var headerTitles: [String] {
    [pinnedHeader, unpinnedHeader].filter { !$0.isHidden }.map(\.stringValue)
  }
  func row(for actionID: String) -> ExtensionsPanelRow? { rows[actionID] }
  /// Pinned rows, top to bottom.
  private var pinnedRows: [ExtensionsPanelRow] { model.pinned.compactMap { rows[$0.id] } }
  /// The list scrolls inside the panel (the window caps its height).
  var scrolls: Bool { listHeight > scrollView.frame.height + 0.5 }

  /// The height the panel needs for its content at `width`, before the window caps it.
  func preferredHeight(width: CGFloat) -> CGFloat {
    let m = ExtensionsPanelMetrics.self
    let body = model.state == .empty ? emptyContentHeight(width: width) : listHeight(width: width)
    return m.padding + body + m.footerHeight
  }

  /// Shows `model`: rows for new actions, updates in place for the others, gone ones removed.
  func reload(_ model: ExtensionsPanelModel) {
    let settle = pendingSettle
    pendingSettle = nil
    if drag != nil { cancelDrag() }
    let edged = increaseContrast()
    self.model = model
    let shown = model.pinned + model.unpinned
    let ids = shown.map(\.id)
    for (id, row) in rows where !ids.contains(id) {
      row.grip.releaseCursor()
      row.removeFromSuperview()
      rows[id] = nil
    }
    for (index, action) in shown.enumerated() {
      let place = action.isPinned ? (index: index, count: model.pinned.count) : nil
      if let row = rows[action.id] {
        row.apply(action, place: place)
      } else {
        let row = makeRow(action, place: place)
        rows[action.id] = row
        list.addSubview(row, positioned: .below, relativeTo: insertionLine)
      }
    }
    for row in rows.values { row.showsContrastEdge = edged }
    displayedRowIDs = ids
    let nonePinned = model.state == .nonePinned
    pinnedHeader.isHidden = model.state == .empty
    hintView.isHidden = !nonePinned
    unpinnedHeader.isHidden = model.unpinned.isEmpty
    emptyView.isHidden = model.state != .empty
    scrollView.isHidden = model.state == .empty
    layoutContent()
    if let settle, let row = rows[settle.id] {
      playSettle(row, fromTop: settle.top, reduceMotion: settle.reduceMotion)
    }
  }

  private func makeRow(_ action: ExtensionAction, place: (index: Int, count: Int)?) -> ExtensionsPanelRow {
    let row = ExtensionsPanelRow(action: action)
    row.apply(action, place: place)
    row.onRun = { [weak self] row in self?.onRun?(row.action, row) }
    row.onTogglePin = { [weak self] row in self?.onSetPinned?(row.action.extensionID, !row.action.isPinned) }
    row.onMove = { [weak self] row, step in self?.move(row, by: step) ?? false }
    let id = action.id
    row.menuProvider = { [weak self] in self?.menuProvider?(id) }
    row.grip.onBegin = { [weak self, weak row] point in if let self, let row { self.beginDrag(row, at: point) } }
    row.grip.onMove = { [weak self] point in self?.continueDrag(to: point) }
    row.grip.onEnd = { [weak self] in self?.endDrag() }
    return row
  }

  /// Move Left (-1) or Move Right (1) of a pinned row; false at the end it moves towards.
  @discardableResult
  func move(_ row: ExtensionsPanelRow, by step: Int) -> Bool {
    guard let target = model.moveTarget(of: row.action.extensionID, by: step) else { return false }
    onMove?(row.action.extensionID, target)
    return true
  }

  // MARK: Keyboard

  /// Cmd-Option-Up or Left: Move Left; Cmd-Option-Down or Right: Move Right, for the pinned row holding the focus.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    guard flags == [.command, .option], let step = Self.moveStep(keyCode: event.keyCode),
          let focused = window?.firstResponder as? NSView,
          let row = rows.values.first(where: { focused.isDescendant(of: $0) }) else {
      return super.performKeyEquivalent(with: event)
    }
    return move(row, by: step)
  }

  private static func moveStep(keyCode: UInt16) -> Int? {
    switch keyCode {
    case 0x7E, 0x7B: -1        // up, left
    case 0x7D, 0x7C: 1         // down, right
    default: nil
    }
  }

  // MARK: Drag by the grip

  private struct Drag {
    let row: ExtensionsPanelRow
    let from: Int
    let startY: CGFloat
    /// Reduce Motion as it was when the row was lifted; the whole gesture keeps it.
    let reduceMotion: Bool
    var offset: CGFloat = 0
    var gap: Int
  }

  /// A dropped row waiting for the engine's new order: where its top was when dropped. The engine reports the order
  /// with `.extensionActionsChanged`, at once (InMemoryEngine) or in a later batch (Chromium); until then the row
  /// stays where it was dropped. A drop the engine never answers settles back after `settleTimeout`.
  private struct PendingSettle {
    let id: String
    let top: CGFloat
    let reduceMotion: Bool
    let generation: Int
  }

  /// How long a dropped row waits for the engine's answer before it settles back into its old slot.
  static let settleTimeout: TimeInterval = 1.0

  private var drag: Drag?
  private var pendingSettle: PendingSettle?
  private var settleGeneration = 0
  /// The gap the dragged row would drop into (0 before the first pinned row); nil without a drag.
  var dragGap: Int? { drag?.gap }
  /// A dropped row waits for the engine's order.
  var isAwaitingDrop: Bool { pendingSettle != nil }

  /// Lifts a pinned row; `point` is in the list's coordinates.
  func beginDrag(_ row: ExtensionsPanelRow, at point: NSPoint) {
    guard drag == nil, pendingSettle == nil, let from = pinnedRows.firstIndex(where: { $0 === row }) else { return }
    let drag = Drag(row: row, from: from, startY: point.y, reduceMotion: reduceMotion(), gap: from)
    self.drag = drag
    row.setLifted(true)
    setTransform(of: row, offset: 0, scaled: !drag.reduceMotion)
  }

  /// Moves the lifted row with the pointer and the insertion line with the drop place. Layer properties only.
  func continueDrag(to point: NSPoint) {
    guard var drag else { return }
    let pinned = pinnedRows
    guard let first = pinned.first, let last = pinned.last else { return }
    let half = drag.row.frame.height / 2
    let low = first.frame.minY - half - drag.row.frame.midY
    let high = last.frame.maxY + half - drag.row.frame.midY
    drag.offset = min(max(point.y - drag.startY, low), high)
    let middles = pinned.map(\.frame.midY)
    let pointer = drag.row.frame.midY + (point.y - drag.startY)
    drag.gap = ExtensionsPanelModel.insertionGap(pointerY: pointer, rowMiddles: middles)
    self.drag = drag
    setTransform(of: drag.row, offset: drag.offset, scaled: !drag.reduceMotion)
    if ExtensionsPanelModel.dropIndex(from: drag.from, gap: drag.gap) == nil {
      insertionLine.isHidden = true
    } else {
      let y = drag.gap < pinned.count ? pinned[drag.gap].frame.minY : last.frame.maxY
      let height = ExtensionsPanelMetrics.insertionHeight
      ArchiveMotion.set {
        insertionLine.frame = NSRect(x: 8, y: y - height / 2, width: list.bounds.width - 16, height: height)
      }
      insertionLine.isHidden = false
    }
  }

  /// Drops the lifted row: a move goes to the engine and the row stays where it was dropped until the engine reports
  /// the new order; then it settles into its slot.
  func endDrag() {
    guard let drag else { return }
    self.drag = nil
    insertionLine.isHidden = true
    drag.row.setLifted(false)
    let top = drag.row.frame.minY + drag.offset
    guard let target = ExtensionsPanelModel.dropIndex(from: drag.from, gap: drag.gap) else {
      playSettle(drag.row, fromTop: top, reduceMotion: drag.reduceMotion)
      return
    }
    settleGeneration += 1
    let generation = settleGeneration
    pendingSettle = PendingSettle(id: drag.row.action.id, top: top, reduceMotion: drag.reduceMotion,
                                  generation: generation)
    setTransform(of: drag.row, offset: drag.offset, scaled: false)
    onMove?(drag.row.action.extensionID, target)
    guard pendingSettle?.generation == generation else { return }     // answered at once
    scheduleSettleTimeout(Self.settleTimeout) { [weak self] in self?.settleTimedOut(generation) }
  }

  /// The engine never answered the drop: the row settles back into its slot.
  func settleTimedOut(_ generation: Int) {
    guard let settle = pendingSettle, settle.generation == generation else { return }
    pendingSettle = nil
    if let row = rows[settle.id] { playSettle(row, fromTop: settle.top, reduceMotion: settle.reduceMotion) }
  }

  private func cancelDrag() {
    guard let drag else { return }
    self.drag = nil
    insertionLine.isHidden = true
    drag.row.setLifted(false)
    drag.row.grip.releaseCursor()
    setTransform(of: drag.row, offset: 0, scaled: false)
  }

  private func setTransform(of row: ExtensionsPanelRow, offset: CGFloat, scaled: Bool) {
    guard let layer = row.layer else { return }
    let scale = scaled && row.isLifted ? ExtensionsPanelMotion.liftScale : 1
    let pivot = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
    ArchiveMotion.set {
      layer.transform = DialogMotion.transform(scale: scale, offsetY: offset, about: pivot, bounds: layer.bounds,
                                               layerAnchor: layer.anchorPoint)
    }
  }

  /// The row eases from where it was dropped (`top` in the list) to its slot, 0.18 s on `firm`; Reduce Motion: it
  /// jumps. The layer's model transform is the slot either way.
  private func playSettle(_ row: ExtensionsPanelRow, fromTop top: CGFloat, reduceMotion: Bool) {
    guard let layer = row.layer else { return }
    layer.removeAnimation(forKey: "settle")
    setTransform(of: row, offset: 0, scaled: false)
    let delta = top - row.frame.minY
    guard abs(delta) > 0.5, !reduceMotion else { return }
    let animation = CABasicAnimation(keyPath: "transform")
    animation.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, delta, 0))
    animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    animation.duration = ExtensionsPanelMotion.settleDuration
    animation.timingFunction = ExtensionsPanelMotion.firm
    layer.add(animation, forKey: "settle")
  }

  // MARK: Layout

  private func listHeight(width: CGFloat) -> CGFloat {
    let m = ExtensionsPanelMetrics.self
    var height = m.headerHeight
    height += model.state == .nonePinned ? m.hintHeight + 4 : CGFloat(model.pinned.count) * m.rowHeight
    if !model.unpinned.isEmpty { height += m.headerHeight + CGFloat(model.unpinned.count) * m.rowHeight }
    return height
  }

  private func emptyBodyHeight(width: CGFloat) -> CGFloat {
    let textWidth = min(250, width - 44)
    return ceil(emptyBody.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 400)).height ?? 48)
  }

  private func emptyContentHeight(width: CGFloat) -> CGFloat {
    26 + 44 + 12 + 18 + 4 + emptyBodyHeight(width: width) + 16 + 28 + 18
  }

  override func layout() {
    super.layout()
    layoutContent()
  }

  private func layoutContent() {
    let m = ExtensionsPanelMetrics.self
    let width = bounds.width
    let inner = max(0, width - 2 * m.padding)
    let footerTop = bounds.height - m.footerHeight
    scrollView.frame = NSRect(x: m.padding, y: m.padding, width: inner, height: max(0, footerTop - m.padding))
    listHeight = listHeight(width: inner)
    list.frame = NSRect(x: 0, y: 0, width: inner, height: listHeight)
    var y: CGFloat = 0
    pinnedHeader.frame = NSRect(x: 8, y: y + 8, width: inner - 16, height: 16)
    y += m.headerHeight
    if model.state == .nonePinned {
      hintView.frame = NSRect(x: 2, y: y, width: inner - 4, height: m.hintHeight)
      hintGlyph.frame = NSRect(x: 12, y: (m.hintHeight - 16) / 2, width: 16, height: 16)
      hintLabel.frame = NSRect(x: 38, y: 8, width: hintView.frame.width - 50, height: m.hintHeight - 16)
      y += m.hintHeight + 4
    }
    for action in model.pinned {
      rows[action.id]?.frame = NSRect(x: 0, y: y, width: inner, height: m.rowHeight)
      y += m.rowHeight
    }
    if !model.unpinned.isEmpty {
      unpinnedHeader.frame = NSRect(x: 8, y: y + 8, width: inner - 16, height: 16)
      y += m.headerHeight
      for action in model.unpinned {
        rows[action.id]?.frame = NSRect(x: 0, y: y, width: inner, height: m.rowHeight)
        y += m.rowHeight
      }
    }
    for row in rows.values { row.layoutSubtreeIfNeeded() }

    // The empty state.
    emptyView.frame = NSRect(x: m.padding, y: m.padding, width: inner, height: max(0, footerTop - m.padding))
    let bodyHeight = emptyBodyHeight(width: inner)
    let textWidth = min(250, inner - 44)
    var top: CGFloat = 26
    ArchiveMotion.set {
      emptyTile.frame = CGRect(x: (inner - 44) / 2, y: top, width: 44, height: 44)
      emptyGlyph.frame = CGRect(x: 11, y: 11, width: 22, height: 22)
    }
    top += 44 + 12
    emptyTitle.frame = NSRect(x: 12, y: top, width: inner - 24, height: 18)
    top += 18 + 4
    emptyBody.frame = NSRect(x: (inner - textWidth) / 2, y: top, width: textWidth, height: bodyHeight)
    top += bodyHeight + 16
    let pill = browseButton.intrinsicContentSize
    browseButton.frame = NSRect(x: ((inner - pill.width) / 2).rounded(), y: top, width: pill.width, height: pill.height)

    // The footer: Manage Extensions... ("Manage..." when the window narrows the panel).
    manageButton.title = width < ExtensionsPanelMetrics.width ? ExtensionsPanelCopy.manageShort
      : ExtensionsPanelCopy.manage
    manageButton.sizeToFit()
    manageButton.frame.origin = NSPoint(x: m.padding + 8,
                                        y: (footerTop + (m.footerHeight - manageButton.frame.height) / 2).rounded())
    ArchiveMotion.set {
      footerDivider.frame = CGRect(x: m.padding + 2, y: footerTop, width: width - 2 * (m.padding + 2), height: 1)
      let visible = scrollView.frame.height
      if listHeight > visible + 0.5, visible > 0 {
        fade.frame = scrollView.bounds
        let edge = max(0, min(1, (visible - m.fadeHeight) / visible))
        fade.locations = [0, NSNumber(value: Double(edge)), 1]
        scrollView.layer?.mask = fade
      } else {
        scrollView.layer?.mask = nil
      }
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    let secondary = ShellTokens.secondaryText.resolve(flavor).nsColor()
    pinnedHeader.textColor = secondary
    unpinnedHeader.textColor = secondary
    hintLabel.textColor = secondary
    emptyTitle.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    emptyBody.textColor = secondary
    hintGlyph.image = SymbolImageCache.shared.symbol("pin", box: 14, color: ShellTokens.sidebarForeground.resolve(flavor),
                                                     scale: window?.backingScaleFactor ?? 2)
    ArchiveMotion.set {
      hintView.layer?.borderColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor
      footerDivider.backgroundColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor
      insertionLine.layer?.backgroundColor = ShellTokens.primaryText.resolve(flavor).cgColor
      insertionLine.layer?.opacity = 0.55
      emptyTile.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
      emptyGlyph.contents = SymbolImageCache.shared.symbol(
        "puzzlepiece.extension", box: 22, color: ShellTokens.sidebarForeground.resolve(flavor),
        scale: window?.backingScaleFactor ?? 2)
    }
  }
}

/// The list inside the scroll view: top-down, so rows stack from the top.
@MainActor
final class ExtensionsListView: NSView {
  override var isFlipped: Bool { true }
}

/// The panel's words. [I] product wording, from design/extensions.
enum ExtensionsPanelCopy {
  /// The none-pinned hint. The design's second sentence ("Cmd-E opens each in turn") joins it with #599.
  static let hint = "Pin the ones you use most. They stay at the top."
  static let emptyTitle = "No extensions yet"
  static let emptyBody = "Extensions from the Chrome Web Store work here. Add one and it shows up in this list."
  static let browse = "Browse the Web Store"
  static let manage = "Manage Extensions..."
  static let manageShort = "Manage..."
}
