import AppKit
import Motion

/// The drop preview of one Space page's outline (#104): the rows below the drop point make room on a spring, a line
/// marks the insertion point, and a highlight marks a folder or tab the drop acts on.
///
/// Frame cost: nothing here lays out or moves a view. Rows move through their layer's `sublayerTransform`, the line
/// and the highlight are layers of one view that covers the outline, and every frame sets them inside one
/// transaction with actions disabled. Springs retarget only when the target changes; a frame only samples them.
@MainActor
public final class SidebarDropPreview {
  /// The line between rows where an insert lands.
  public var indicatorLayer: CALayer { canvas.line }
  /// The fill over a folder row, or over the half of a tab row, that a drop acts on.
  public var highlightLayer: CALayer { canvas.highlight }
  /// Whether the line is shown (it fades, so its layer stays in the tree).
  public var isIndicatorShown: Bool { canvas.line.opacity == 1 }
  /// Whether the highlight is shown.
  public var isHighlightShown: Bool { canvas.highlight.opacity == 1 }
  /// The line's current y in outline coordinates (the middle of the opened gap, or the row boundary).
  public private(set) var indicatorY: CGFloat = 0
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  private weak var outline: SidebarOutlineView?
  private let canvas = SidebarDropCanvas(frame: .zero)
  private var rows = DropGapSprings<Int>()
  private var line = DropGapSprings<Int>()
  private var target: SidebarDropTarget?
  private var lineShown = false
  private var link: CADisplayLink?
  /// Rows that carry a shift, so a reset touches exactly those.
  private var shifted: Set<Int> = []

  init(outline: SidebarOutlineView) {
    self.outline = outline
  }

  isolated deinit { link?.invalidate() }

  // MARK: Targets

  /// Previews `target` from time `t`: the gap moves (rows spring from where they are), the line follows it, and a
  /// row target gets the highlight. Nil hides the preview and closes the gap, as `clear(dropped: false)` does.
  func show(_ target: SidebarDropTarget?, at t: Double) {
    guard let outline else { return }
    attachCanvas(to: outline)
    guard target != self.target else { return }
    self.target = target
    let reduce = reduceMotion()
    let gap = Double(SidebarMetrics.rowPitch)
    switch target {
    case .insert(_, _, let gapRow, let level)?:
      rows.retarget(SidebarDropMotion.gapOffsets(rowCount: outline.numberOfRows, gapBeforeRow: gapRow,
                                                 gap: CGFloat(gap), reduceMotion: reduce),
                    at: t, parameters: SidebarDropMotion.makeRoom)
      let boundary = Double(boundaryY(beforeRow: gapRow, in: outline))
      let y = reduce ? boundary : boundary + gap / 2
      if lineShown && !reduce {
        line.retarget([0: y], at: t, parameters: SidebarDropMotion.makeRoom)
      } else {
        line.place(0, at: y, time: t)                 // appears in place; under Reduce Motion it never travels
      }
      canvas.setLine(shown: true, x: indentX(level: level), width: outline.bounds.width)
      lineShown = true
      canvas.setHighlight(nil)
    case .folder(_, let row)?:
      closeGap(at: t)
      canvas.setHighlight(rowRect(row, in: outline))
    case .split(_, let before, let row)?:
      closeGap(at: t)
      let rect = rowRect(row, in: outline)
      let half = rect.width / 2
      canvas.setHighlight(CGRect(x: before ? rect.minX : rect.minX + half, y: rect.minY, width: half,
                                 height: rect.height))
    case nil:
      closeGap(at: t)
      canvas.setHighlight(nil)
    }
    tick(at: t)
    startLinkIfNeeded(at: t)
  }

  /// Ends the preview. A drop clears every shift at once (the source change already put the rows where the gap
  /// was); a cancel or an exit lets the rows spring back from where they are.
  func clear(dropped: Bool, at t: Double) {
    target = nil
    if dropped {
      rows.jumpToRest()
      line.jumpToRest()
      lineShown = false
      canvas.setLine(shown: false, x: 0, width: 0)
      canvas.setHighlight(nil)
      tick(at: t)
      stopLink()
      return
    }
    closeGap(at: t)
    canvas.setHighlight(nil)
    tick(at: t)
    startLinkIfNeeded(at: t)
  }

  private func closeGap(at t: Double) {
    rows.retarget([:], at: t, parameters: SidebarDropMotion.snapBack)
    if lineShown {
      lineShown = false
      canvas.setLine(shown: false, x: 0, width: 0)
    }
  }

  // MARK: Sampling

  /// The downward shift of display row `row` at time `t`, in points.
  public func offset(ofRow row: Int, at t: Double) -> Double { rows.offset(of: row, at: t) }

  public func isSettled(at t: Double) -> Bool { rows.isSettled(at: t) && line.isSettled(at: t) }

  /// Presents time `t`: every realized row's shift and the line's place, in one transaction without actions.
  public func tick(at t: Double) {
    guard let outline else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var next: Set<Int> = []
    outline.enumerateAvailableRowViews { rowView, row in
      let offset = self.rows.offset(of: row, at: t)
      guard offset != 0 || self.shifted.contains(row), let layer = rowView.layer else { return }
      let down = CGFloat(offset) * (layer.isFlippedInWindow ? 1 : -1)
      layer.sublayerTransform = offset == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, down, 0)
      if offset != 0 { next.insert(row) }
    }
    shifted = next
    if lineShown {
      indicatorY = CGFloat(line.offset(of: 0, at: t))
      canvas.placeLine(atY: indicatorY)
    }
    CATransaction.commit()
    if rows.isSettled(at: t) { rows.prune(at: t) }
  }

  // MARK: Geometry

  /// The y between `row - 1` and `row` (outline coordinates); the end of the rows for `row` past the last one.
  private func boundaryY(beforeRow row: Int, in outline: NSOutlineView) -> CGFloat {
    if row < outline.numberOfRows { return outline.rect(ofRow: max(row, 0)).minY }
    return outline.numberOfRows > 0 ? outline.rect(ofRow: outline.numberOfRows - 1).maxY : 0
  }

  private func indentX(level: Int) -> CGFloat {
    CGFloat(max(level, 0)) * SidebarMetrics.indentationPerLevel + SidebarDropCanvas.lineInset
  }

  private func rowRect(_ row: Int, in outline: NSOutlineView) -> CGRect {
    guard row >= 0, row < outline.numberOfRows else { return .zero }
    let indent = CGFloat(max(outline.level(forRow: row), 0)) * SidebarMetrics.indentationPerLevel
    let rect = outline.rect(ofRow: row).insetBy(dx: 0, dy: SidebarMetrics.rowBackgroundInsetY)
    return CGRect(x: rect.minX + indent, y: rect.minY, width: max(rect.width - indent, 0), height: rect.height)
  }

  private func attachCanvas(to outline: NSView) {
    if canvas.superview !== outline { outline.addSubview(canvas, positioned: .above, relativeTo: nil) }
    if canvas.frame != outline.bounds { canvas.frame = outline.bounds }
  }

  // MARK: Display link

  private func startLinkIfNeeded(at t: Double) {
    guard link == nil, !isSettled(at: t), let outline, outline.window != nil else { return }
    let proxy = DropPreviewLinkTarget(preview: self)
    let link = outline.displayLink(target: proxy, selector: #selector(DropPreviewLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func stopLink() {
    link?.invalidate()
    link = nil
  }

  fileprivate func linkFired(_ link: CADisplayLink) {
    guard link === self.link else { return link.invalidate() }
    tick(at: link.targetTimestamp)
    if isSettled(at: link.targetTimestamp) { stopLink() }
  }
}

/// Display-link target that does not retain the preview (CADisplayLink retains its target).
@MainActor
private final class DropPreviewLinkTarget: NSObject {
  weak var preview: SidebarDropPreview?
  init(preview: SidebarDropPreview) { self.preview = preview }

  @objc func tick(_ link: CADisplayLink) {
    guard let preview else { return link.invalidate() }
    preview.linkFired(link)
  }
}

extension CALayer {
  /// Whether this layer's sublayers run top-down on screen: the geometry flips of it and its ancestors, combined.
  var isFlippedInWindow: Bool {
    var flipped = false
    var current: CALayer? = self
    while let layer = current {
      if layer.isGeometryFlipped { flipped.toggle() }
      current = layer.superlayer
    }
    return flipped
  }
}

/// The view that draws the drop line and the row highlight above an outline. Never hit-tested and never an
/// accessibility element; it only shows where the drop goes.
@MainActor
final class SidebarDropCanvas: NSView {
  static let lineInset: CGFloat = 8
  static let lineHeight: CGFloat = 2

  let line = CALayer()
  let highlight = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityElement(false)
    line.cornerRadius = Self.lineHeight / 2
    line.opacity = 0
    highlight.cornerRadius = SidebarMetrics.rowCornerRadius
    highlight.cornerCurve = .continuous
    highlight.borderWidth = 2
    highlight.opacity = 0
    layer?.addSublayer(highlight)
    layer?.addSublayer(line)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private var lineX: CGFloat = 0
  private var lineWidth: CGFloat = 0

  /// Shows or hides the line (a short fade: feedback, not travel; kept under Reduce Motion) at `x`, spanning to
  /// `width` less the inset.
  func setLine(shown: Bool, x: CGFloat, width: CGFloat) {
    if shown {
      lineX = x
      lineWidth = max(width - x - Self.lineInset, 0)
      if line.opacity == 0 { applyColors() }
    }
    fade(line, shown: shown)
  }

  /// Puts the line's middle at `y` (view coordinates).
  func placeLine(atY y: CGFloat) {
    let rect = CGRect(x: lineX, y: y - Self.lineHeight / 2, width: lineWidth, height: Self.lineHeight)
    line.frame = layerRect(rect)
  }

  /// Highlights `rect` (view coordinates), or hides the highlight for nil.
  func setHighlight(_ rect: CGRect?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let rect {
      if highlight.opacity == 0 { applyColors() }
      highlight.frame = layerRect(rect)
    }
    CATransaction.commit()
    fade(highlight, shown: rect != nil)
  }

  /// A short fade (feedback, not travel; kept under Reduce Motion) from wherever the layer's opacity is now.
  private func fade(_ layer: CALayer, shown: Bool) {
    let to: Float = shown ? 1 : 0
    guard layer.opacity != to else { return }
    let from = layer.presentation()?.opacity ?? layer.opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = to
    CATransaction.commit()
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = SidebarDropMotion.indicatorFade
    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)   // strong ease-out
    layer.add(animation, forKey: "fade")
  }

  /// `rect` in this view's flipped coordinates, as a frame in its layer's own geometry.
  private func layerRect(_ rect: CGRect) -> CGRect {
    guard let layer, !layer.isFlippedInWindow else { return rect }
    return CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
  }

  private func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      line.backgroundColor = NSColor.controlAccentColor.cgColor
      highlight.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
      highlight.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }
  }
}
