import AppKit
import Motion

/// The colour pad (README, "Colour pad"): the field `ThemePad.color` draws, one or two dots and the line joining
/// them. All pointer handling is here; the dots are accessibility elements and keyboard targets.
///
/// A dot follows the pointer with no lag and no easing. Its pick-up and release spring (`springyExtraFast`) on its
/// transform; a dot dragged more than 24 pt off the pad fades to 35 % and is removed when let go.
@MainActor
final class ThemePadView: NSView {
  /// Pointer events, in pad coordinates (top-left origin).
  var onDragBegan: ((Int) -> Void)?
  var onDragMoved: ((Int, CGPoint) -> Void)?
  var onDragEnded: ((Int, CGPoint) -> Void)?
  var onDoubleClick: ((CGPoint) -> Void)?
  /// Read when a dot is added or removed and on pick-up.
  var reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  private(set) var dots: [ThemeDotView] = []
  private let field = CALayer()
  private let innerShadow = CAShapeLayer()
  private let innerShadowMask = CAShapeLayer()
  private let edge = CALayer()
  private let link = CAShapeLayer()
  private var fieldScale: CGFloat = 0
  private var dragging: Int?
  private static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(),
                                                      "contents": NSNull(), "hidden": NSNull(), "opacity": NSNull()]

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    field.cornerRadius = ThemeCreatorMetrics.padRadius
    field.masksToBounds = true
    field.contentsGravity = .resize
    innerShadow.fillRule = .evenOdd
    innerShadow.fillColor = CGColor.black
    innerShadow.shadowColor = CGColor.black
    innerShadow.shadowOpacity = 0.12
    innerShadow.shadowRadius = 7
    innerShadow.shadowOffset = CGSize(width: 0, height: 3)
    innerShadow.mask = innerShadowMask
    edge.cornerRadius = ThemeCreatorMetrics.padRadius
    edge.borderWidth = 0.5
    edge.borderColor = CGColor(gray: 0, alpha: 0.16)
    link.strokeColor = CGColor(gray: 1, alpha: 0.85)
    link.lineWidth = ThemeCreatorMetrics.linkWidth
    link.fillColor = nil
    link.lineCap = .round
    for sublayer in [field, innerShadow, edge, link] {
      sublayer.actions = Self.noActions
      layer?.addSublayer(sublayer)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Colour")
    setAccessibilityIdentifier(AXID.ThemeCreator.pad)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    field.frame = bounds
    edge.frame = bounds
    innerShadow.frame = bounds
    innerShadowMask.frame = bounds
    let rounded = CGPath(roundedRect: bounds, cornerWidth: ThemeCreatorMetrics.padRadius,
                         cornerHeight: ThemeCreatorMetrics.padRadius, transform: nil)
    let outer = CGMutablePath()
    outer.addRect(bounds.insetBy(dx: -40, dy: -40))
    outer.addPath(rounded)
    innerShadow.path = outer
    innerShadowMask.path = rounded
    link.frame = bounds
    CATransaction.commit()
    for dot in dots { dot.place(at: ThemePad.location(of: dot.point, in: bounds.size)) }
    updateLink()
    drawFieldIfNeeded()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    drawFieldIfNeeded()
  }

  /// The field at the backing scale, drawn once per scale from `ThemePad.color`.
  private func drawFieldIfNeeded() {
    let scale = window?.backingScaleFactor ?? 2
    guard scale != fieldScale, bounds.width > 0 else { return }
    fieldScale = scale
    field.contents = ThemePadField.image(size: bounds.size, scale: scale)
    field.contentsScale = scale
  }

  // MARK: - Dots

  /// Removes the dot at `index` where it stands (shrink and fade); the others take its place in the order.
  func removeDot(at index: Int, animated: Bool) {
    guard dots.indices.contains(index) else { return }
    let gone = dots.remove(at: index)
    gone.remove(animated: animated, reduceMotion: reducesMotion())
    for (offset, dot) in dots.enumerated() { dot.index = offset }
    updateLink()
  }

  /// Shows `points` with `colors` (the stored colours). Dots added or removed animate unless `animated` is false.
  func update(points: [ThemePadPoint], colors: [RGBA], animated: Bool) {
    let reduce = reducesMotion()
    while dots.count > points.count {
      let gone = dots.removeLast()
      gone.remove(animated: animated, reduceMotion: reduce)
    }
    while dots.count < points.count {
      let dot = ThemeDotView(index: dots.count)
      addSubview(dot)
      let origin = dots.first?.center
      dots.append(dot)
      dot.place(at: ThemePad.location(of: points[dots.count - 1], in: bounds.size))
      if animated { dot.appear(from: origin, reduceMotion: reduce) }
    }
    for (index, dot) in dots.enumerated() {
      dot.color = colors.indices.contains(index) ? colors[index] : ThemePad.color(points[index])
      dot.point = points[index]
      dot.place(at: ThemePad.location(of: points[index], in: bounds.size))
    }
    updateLink()
  }

  private func updateLink() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if dots.count > 1 {
      let path = CGMutablePath()
      path.move(to: dots[0].center)
      path.addLine(to: dots[1].center)
      link.path = path
      link.isHidden = false
    } else {
      link.isHidden = true
    }
    CATransaction.commit()
  }

  /// The dot under `location`, nearest first, within its dragged radius.
  private func dot(at location: CGPoint) -> Int? {
    let hits = dots.enumerated().filter { hypot($1.center.x - location.x, $1.center.y - location.y)
      <= ThemeCreatorMetrics.dotDragged / 2 }
    return hits.min { hypot($0.1.center.x - location.x, $0.1.center.y - location.y)
      < hypot($1.1.center.x - location.x, $1.1.center.y - location.y) }?.0
  }

  /// Marks a dragged dot as leaving the pad (35 %) or back on it.
  func setLeaving(_ leaving: Bool, dot index: Int) {
    guard dots.indices.contains(index) else { return }
    dots[index].setLeaving(leaving)
  }

  // MARK: - Pointer

  override func mouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    if event.clickCount == 2, dot(at: location) == nil {
      onDoubleClick?(location)
      return
    }
    guard let index = dot(at: location) else { return }
    dragging = index
    dots[index].setPickedUp(true, reduceMotion: reducesMotion())
    onDragBegan?(index)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let index = dragging else { return }
    onDragMoved?(index, convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    guard let index = dragging else { return }
    dragging = nil
    if dots.indices.contains(index) { dots[index].setPickedUp(false, reduceMotion: reducesMotion()) }
    onDragEnded?(index, convert(event.locationInWindow, from: nil))
  }

  var isDragging: Bool { dragging != nil }
}

// MARK: - Dot

/// One colour dot: 26 pt with a 3 pt white ring and a soft shadow; 34 pt and a deeper shadow while dragged. The
/// view is 34 pt so the picked-up dot fits; only its layers scale.
@MainActor
final class ThemeDotView: ThemeFocusableView {
  var index: Int { didSet { setAccessibilityLabel("Colour \(index + 1)") } }
  var point = ThemePadPoint(hue: 0, tone: 0.5) { didSet { refreshAccessibility() } }
  var color: RGBA = .white(1) {
    didSet {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      disc.backgroundColor = color.cgColor
      CATransaction.commit()
    }
  }
  /// Keyboard: arrows, Shift-arrows, Delete. The popover applies them.
  var onArrow: ((Int, ThemePad.Arrow, Bool) -> Void)?
  var onDelete: ((Int) -> Void)?

  private let disc = CALayer()
  private let restShadow = CALayer()
  private let liftShadow = CALayer()
  private(set) var isPickedUp = false

  init(index: Int) {
    self.index = index
    let side = ThemeCreatorMetrics.dotDragged
    super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
    wantsLayer = true
    layer?.masksToBounds = false
    let size = ThemeCreatorMetrics.dot
    let frame = CGRect(x: (side - size) / 2, y: (side - size) / 2, width: size, height: size)
    for (shadow, offset, radius, opacity) in [(restShadow, 2.0, 4.0, Float(0.35)), (liftShadow, 8.0, 11.0, 0.38)] {
      shadow.frame = frame
      shadow.cornerRadius = size / 2
      shadow.shadowColor = CGColor.black
      shadow.shadowOpacity = opacity
      shadow.shadowRadius = radius
      shadow.shadowOffset = CGSize(width: 0, height: offset)
      shadow.shadowPath = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
      layer?.addSublayer(shadow)
    }
    liftShadow.opacity = 0
    disc.frame = frame
    disc.cornerRadius = size / 2
    disc.borderWidth = ThemeCreatorMetrics.dotRing
    disc.borderColor = CGColor.white
    layer?.addSublayer(disc)
    setAccessibilityElement(true)
    setAccessibilityRole(.slider)
    setAccessibilityLabel("Colour \(index + 1)")
    setAccessibilityIdentifier(AXID.ThemeCreator.dot)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The dot's centre in the pad.
  var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

  func place(at location: CGPoint) {
    let side = ThemeCreatorMetrics.dotDragged
    setFrameOrigin(NSPoint(x: location.x - side / 2, y: location.y - side / 2))
  }

  override var focusRingRect: NSRect { disc.frame }

  // Pointer events belong to the pad.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private func refreshAccessibility() {
    setAccessibilityValue(ThemePad.accessibilityValue(point))
  }

  // MARK: Motion

  /// Pick-up: the disc and its shadows grow to 34 pt and the deeper shadow fades in; release springs back.
  func setPickedUp(_ pickedUp: Bool, reduceMotion: Bool) {
    guard pickedUp != isPickedUp else { return }
    isPickedUp = pickedUp
    let scale = pickedUp ? ThemeCreatorMetrics.dotDragged / ThemeCreatorMetrics.dot : 1
    let target = CATransform3DMakeScale(scale, scale, 1)
    for sublayer in [disc, restShadow, liftShadow] {
      let from = sublayer.presentation()?.transform ?? sublayer.transform
      sublayer.transform = target
      if !reduceMotion {
        let spring = SpringAnimationFactory.make(keyPath: "transform.scale", from: Double(from.m11),
                                                 to: Double(scale), parameters: ThemeCreatorMotion.pickUp)
        sublayer.add(spring, forKey: "pickUp")
      }
    }
    let lift: Float = pickedUp ? 1 : 0
    let fromLift = liftShadow.presentation()?.opacity ?? liftShadow.opacity
    liftShadow.opacity = lift
    restShadow.opacity = 1 - lift
    if !reduceMotion {
      for (sublayer, from, to) in [(liftShadow, fromLift, lift), (restShadow, 1 - fromLift, 1 - lift)] {
        sublayer.add(SpringAnimationFactory.make(keyPath: "opacity", from: Double(from), to: Double(to),
                                                 parameters: ThemeCreatorMotion.pickUp), forKey: "lift")
      }
    }
  }

  func setLeaving(_ leaving: Bool) {
    let target: CGFloat = leaving ? 0.35 : 1
    guard alphaValue != target else { return }
    let from = Float(layer?.presentation()?.opacity ?? Float(alphaValue))
    alphaValue = target
    layer?.add(Self.fade(from: from, to: Float(target), duration: 0.1), forKey: "leaving")
  }

  /// A new second dot springs out of the first (`springy`), or fades in in place with Reduce Motion.
  func appear(from origin: CGPoint?, reduceMotion: Bool) {
    guard let layer else { return }
    if reduceMotion || origin == nil {
      layer.add(Self.fade(from: 0, to: 1, duration: ThemeCreatorMotion.stateDuration), forKey: "appear")
      return
    }
    guard let origin else { return }
    let offset = CGSize(width: origin.x - center.x, height: origin.y - center.y)
    for sublayer in [disc, restShadow, liftShadow] {
      for (key, value) in [("transform.translation.x", offset.width), ("transform.translation.y", offset.height)] {
        sublayer.add(SpringAnimationFactory.make(keyPath: key, from: Double(value), to: 0,
                                                 parameters: ThemeCreatorMotion.secondDot), forKey: "appear-\(key)")
      }
    }
  }

  /// A removed dot shrinks and fades (0.15 s), or only fades with Reduce Motion, then leaves the pad.
  func remove(animated: Bool, reduceMotion: Bool) {
    guard animated, let layer else {
      removeFromSuperview()
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.removeFromSuperview() }
    }
    let from = Float(alphaValue)
    alphaValue = 0
    layer.add(Self.fade(from: from, to: 0, duration: ThemeCreatorMotion.removeDuration), forKey: "remove")
    if !reduceMotion {
      for sublayer in [disc, restShadow, liftShadow] {
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = sublayer.presentation()?.transform.m11 ?? 1
        shrink.toValue = 0.01
        shrink.duration = ThemeCreatorMotion.removeDuration
        shrink.timingFunction = ThemeCreatorMotion.easeOut
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        sublayer.add(shrink, forKey: "remove")
      }
    }
    CATransaction.commit()
  }

  static func fade(from: Float, to: Float, duration: TimeInterval) -> CABasicAnimation {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = to
    fade.duration = duration
    fade.timingFunction = ThemeCreatorMotion.easeOut
    return fade
  }

  // MARK: Keyboard and accessibility

  override func handleKey(_ event: NSEvent) -> Bool {
    if let arrow = event.themePadArrow {
      onArrow?(index, arrow, event.isShiftDown)
      return true
    }
    if event.keyCode == 51 || event.keyCode == 117 {           // Delete, Forward Delete
      onDelete?(index)
      return true
    }
    return false
  }

  /// Increment and decrement change tone: increment is lighter.
  override func accessibilityPerformIncrement() -> Bool {
    onArrow?(index, .up, false)
    return true
  }

  override func accessibilityPerformDecrement() -> Bool {
    onArrow?(index, .down, false)
    return true
  }
}

// MARK: - Field image

/// The pad's colour field as an image, drawn pixel by pixel from `ThemePad.color` so the pad shows exactly the
/// colours it stores. Cached per size and scale.
@MainActor
enum ThemePadField {
  private static var cache: [String: CGImage] = [:]

  static func image(size: CGSize, scale: CGFloat) -> CGImage? {
    let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
    guard width > 0, height > 0 else { return nil }
    let key = "\(width)x\(height)"
    if let cached = cache[key] { return cached }
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    // The middle band per column, then each row blends it toward an end (the same arithmetic as `ThemePad.color`).
    let middles = (0..<width).map { x in
      ThemePad.color(ThemePadPoint(hue: 360 * (Double(x) + 0.5) / Double(width), tone: 0.5))
    }
    for y in 0..<height {
      let tone = (Double(y) + 0.5) / Double(height)
      let end = tone <= 0.5 ? ThemeContrast.porcelain : ThemeContrast.nearBlack
      let t = tone <= 0.5 ? 1 - tone / 0.5 : (tone - 0.5) / 0.5
      for x in 0..<width {
        let middle = middles[x]
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8(clamping: Int(((middle.red + (end.red - middle.red) * t) * 255).rounded()))
        pixels[offset + 1] = UInt8(clamping: Int(((middle.green + (end.green - middle.green) * t) * 255).rounded()))
        pixels[offset + 2] = UInt8(clamping: Int(((middle.blue + (end.blue - middle.blue) * t) * 255).rounded()))
      }
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: space,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return nil }
    cache[key] = image
    return image
  }
}
