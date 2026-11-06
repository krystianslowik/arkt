import AppKit
import Motion

/// The drop preview of one Space page's outline (#104): the rows below the drop point make room on a spring, a slot
/// marks the insertion point, and a highlight marks a folder or tab the drop acts on.
///
/// The insertion point (#686, design/drag-hint-focus-ring): a 30 pt slot in the open gap, in the drag hint fill and
/// edge. A fresh slot opens with its gap (its middle and height follow the gap row's shift, so it never covers a
/// row); moving to another gap, it travels on the gap's spring from where it is. Reduce Motion variant, the boundary
/// line: no gap opens, so nothing is drawn over the rows; a 2 pt `dragHintEdge` line marks the row boundary.
/// Both fade in over `SidebarDropMotion.indicatorFade`.
///
/// Frame cost: nothing here lays out or moves a view. Rows move through their layer's `sublayerTransform`, the
/// slot, the line and the highlight are layers of one view that covers the outline, and every frame sets them inside
/// one transaction with actions disabled. A frame sets the indicator's position, and its height only while a fresh
/// slot opens with its gap; the width and colors are set once per target.
/// Springs retarget only when the target changes; a frame only samples them.
@MainActor
public final class SidebarDropPreview {
  /// How the insertion point is drawn.
  public enum IndicatorStyle: Sendable, Equatable {
    /// A 30 pt slot in the open gap, the row width at the target's indent.
    case slot
    /// Reduce Motion: no gap opens, so a 2 pt line on the row boundary.
    case boundaryLine
  }

  /// The line on the row boundary where an insert lands (Reduce Motion).
  public var indicatorLayer: CALayer { canvas.line }
  /// The slot in the open gap where an insert lands.
  public var slotLayer: CALayer { canvas.slot }
  /// The style of the current insertion point; set when a target is shown.
  public private(set) var indicatorStyle: IndicatorStyle = .slot
  /// The fill over a folder row, or over the half of a tab row, that a drop acts on.
  public var highlightLayer: CALayer { canvas.highlight }
  /// Whether the insertion point is shown (it fades, so its layers stay in the tree).
  public var isIndicatorShown: Bool { lineShown && canvasLayer(indicatorStyle).opacity == 1 }
  /// Whether the highlight is shown.
  public var isHighlightShown: Bool { canvas.highlight.opacity == 1 }
  /// The insertion point's current y (its middle) in outline coordinates: the middle of the opened gap, or the row
  /// boundary.
  public private(set) var indicatorY: CGFloat = 0
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The motion clock; the display link samples it too, so tests that set it see no frame from another clock.
  var now: @MainActor () -> Double = { CACurrentMediaTime() }

  private weak var outline: SidebarOutlineView?
  private let canvas = SidebarDropCanvas(frame: .zero)
  var canvasView: SidebarDropCanvas { canvas }
  private var rows = DropGapSprings<Int>()
  private var line = DropGapSprings<Int>()
  private var target: SidebarDropTarget?
  private var lineShown = false
  /// A fresh slot opens with its gap: its middle and height come from the gap row's shift until the target moves.
  private var slotFollowsGap = false
  private var gapRow = 0
  private var gapBoundary: Double = 0
  private var link: CADisplayLink?

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
    guard target != self.target else {
      tick(at: t)                                     // rows scrolled into view under a steady gap get their shift
      return
    }
    self.target = target
    let reduce = reduceMotion()
    let gap = Double(SidebarMetrics.rowPitch)
    switch target {
    case .insert(_, _, let gapRow, let level)?:
      rows.retarget(SidebarDropMotion.gapOffsets(rowCount: outline.numberOfRows, gapBeforeRow: gapRow,
                                                 gap: CGFloat(gap), reduceMotion: reduce),
                    at: t, parameters: SidebarDropMotion.makeRoom)
      let boundary = Double(boundaryY(beforeRow: gapRow, in: outline))
      let style: IndicatorStyle = reduce ? .boundaryLine : .slot
      let y = reduce ? boundary : boundary + gap / 2
      if lineShown && style == .slot && indicatorStyle == .slot {
        // Moving from one gap to another: the slot travels from where it is shown now.
        if slotFollowsGap { line.place(0, at: Double(indicatorY), time: t) }
        line.retarget([0: y], at: t, parameters: SidebarDropMotion.makeRoom)
        slotFollowsGap = false
      } else {
        line.place(0, at: y, time: t)                 // under Reduce Motion it never travels
        slotFollowsGap = style == .slot               // a fresh slot opens with the gap instead of over the rows
      }
      self.gapRow = gapRow
      gapBoundary = boundary
      indicatorStyle = style
      switch style {
      case .slot:
        let x = outline.bounds.minX + indent(level: level)
        canvas.setIndicator(.slot, shown: true, x: x, width: outline.bounds.maxX - x)
      case .boundaryLine:
        let x = indentX(level: level)
        canvas.setIndicator(.boundaryLine, shown: true, x: x,
                            width: outline.bounds.width - x - SidebarDropCanvas.lineInset)
      }
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
      canvas.setIndicator(indicatorStyle, shown: false)
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
      canvas.setIndicator(indicatorStyle, shown: false)
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
    outline.enumerateAvailableRowViews { rowView, row in
      guard let layer = rowView.layer else { return }
      let offset = self.rows.offset(of: row, at: t)
      let down = CGFloat(offset) * (layer.isFlippedInWindow ? 1 : -1)
      let transform = offset == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, down, 0)
      if !CATransform3DEqualToTransform(layer.sublayerTransform, transform) { layer.sublayerTransform = transform }
    }
    if lineShown {
      var openness: CGFloat = 1
      if slotFollowsGap {
        let pitch = Double(SidebarMetrics.rowPitch)
        let open = gapRow < outline.numberOfRows ? rows.offset(of: gapRow, at: t) : pitch   // past the last row: room
        indicatorY = CGFloat(gapBoundary + open / 2)
        openness = CGFloat(min(max(open / pitch, 0), 1))
      } else {
        indicatorY = CGFloat(line.offset(of: 0, at: t))
      }
      canvas.placeIndicator(atY: indicatorY, openness: openness)
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

  private func indent(level: Int) -> CGFloat { CGFloat(max(level, 0)) * SidebarMetrics.indentationPerLevel }

  private func indentX(level: Int) -> CGFloat { indent(level: level) + SidebarDropCanvas.lineInset }

  private func canvasLayer(_ style: IndicatorStyle) -> CALayer { style == .slot ? canvas.slot : canvas.line }

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
    let t = now()
    tick(at: t)
    if isSettled(at: t) { stopLink() }
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

/// The view that draws the drop slot, the boundary line and the row highlight above an outline. Never hit-tested and
/// never an accessibility element; it only shows where the drop goes.
@MainActor
final class SidebarDropCanvas: NSView {
  static let lineInset: CGFloat = 8
  static let lineHeight: CGFloat = 2
  /// design/drag-hint-focus-ring: the slot in the open gap is 30 pt high with a radius of 9, the row width.
  static let slotHeight: CGFloat = 30
  static let slotCornerRadius: CGFloat = 9

  let slot = CALayer()
  let line = CALayer()
  let highlight = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityElement(false)
    slot.cornerRadius = Self.slotCornerRadius
    slot.cornerCurve = .continuous
    slot.borderWidth = 1
    slot.opacity = 0
    line.cornerRadius = Self.lineHeight / 2
    line.opacity = 0
    highlight.cornerRadius = SidebarMetrics.rowCornerRadius
    highlight.cornerCurve = .continuous
    highlight.borderWidth = 1
    highlight.opacity = 0
    layer?.addSublayer(highlight)
    layer?.addSublayer(slot)
    layer?.addSublayer(line)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private var style: SidebarDropPreview.IndicatorStyle = .slot
  private var indicatorMidX: CGFloat = 0
  private var indicatorSize: CGSize = .zero

  private func layer(for style: SidebarDropPreview.IndicatorStyle) -> CALayer {
    style == .slot ? slot : line
  }

  /// Shows the indicator in `style` from `x` across `width` (view coordinates), or hides it. The size is set here,
  /// once per target; a frame only moves it (`placeIndicator`). A short fade: feedback, not travel; kept under
  /// Reduce Motion.
  func setIndicator(_ style: SidebarDropPreview.IndicatorStyle, shown: Bool, x: CGFloat = 0, width: CGFloat = 0) {
    guard shown else {
      fade(slot, shown: false)
      fade(line, shown: false)
      return
    }
    let layer = layer(for: style)
    let other = style == .slot ? line : slot
    let size = CGSize(width: max(width, 0), height: style == .slot ? Self.slotHeight : Self.lineHeight)
    self.style = style
    indicatorMidX = x + size.width / 2
    indicatorSize = size
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if layer.opacity == 0 { applyColors() }           // no implicit color animation under the fade
    setSize(of: layer, height: size.height)
    CATransaction.commit()
    fade(other, shown: false)
    fade(layer, shown: true)
  }

  /// Puts the indicator's middle at `y` (view coordinates). Called every frame inside the caller's transaction: it
  /// sets a position, and while a fresh slot's gap opens (`openness` under 1) the slot's height, a layer property;
  /// no view lays out.
  func placeIndicator(atY y: CGFloat, openness: CGFloat = 1) {
    let layer = layer(for: style)
    if style == .slot { setSize(of: layer, height: indicatorSize.height * min(max(openness, 0), 1)) }
    layer.position = layerPoint(CGPoint(x: indicatorMidX, y: y))
  }

  /// `layer` at the indicator's width and `height`, with the corner radius never over half the height.
  private func setSize(of layer: CALayer, height: CGFloat) {
    let size = CGSize(width: indicatorSize.width, height: height)
    guard layer.bounds.size != size else { return }
    layer.bounds = CGRect(origin: .zero, size: size)
    if layer === slot { slot.cornerRadius = min(Self.slotCornerRadius, height / 2) }
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
    animation.timingFunction = MotionCurve.strongEaseOut.timingFunction
    layer.add(animation, forKey: "fade")
  }

  /// `rect` in this view's flipped coordinates, as a frame in its layer's own geometry.
  private func layerRect(_ rect: CGRect) -> CGRect {
    guard let layer, !layer.isFlippedInWindow else { return rect }
    return CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
  }

  private func layerPoint(_ point: CGPoint) -> CGPoint {
    guard let layer, !layer.isFlippedInWindow else { return point }
    return CGPoint(x: point.x, y: bounds.height - point.y)
  }

  /// `sublayer`'s frame in this view's flipped coordinates (the inverse of `layerRect`).
  func viewRect(of sublayer: CALayer) -> CGRect { layerRect(sublayer.frame) }

  /// The drag hint in the Space's text tone (#641): the sidebar's appearance follows it.
  func applyColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    let fill = ShellTokens.dragHint.resolve(flavor).cgColor
    let edge = ShellTokens.dragHintEdge.resolve(flavor).cgColor
    slot.backgroundColor = fill
    slot.borderColor = edge
    line.backgroundColor = edge
    highlight.backgroundColor = fill
    highlight.borderColor = edge
  }
}
