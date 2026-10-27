import AppKit
import QuartzCore

/// The link status pill (design/status-pill/README.md, direction A): a 26 pt floating capsule at a bottom corner of the
/// card that shows where the link under the pointer goes. The host is semibold and the rest of the address sits in
/// quiet type, shortened in the middle on one line. It lives in a `ContentCardView`, which sets its frame
/// (`preferredWidth(maxWidth:)` and `StatusPillGeometry`); this view lays out its two labels.
///
/// It never takes a click, a hover or the keyboard (`hitTest` is nil), and it is out of the accessibility tree:
/// VoiceOver already says "link, <address>" for the link, and a pill that spoke on every hover would talk over it.
/// Direction A is the plain brand surface in light and dark, not tinted by the Space theme.
///
/// Motion (transform and opacity only, never layout): it fades in over 0.14 s and rises 4 pt, fades out over 0.09 s;
/// moving to another link changes the text at once; crossing to the other corner is a `firmFast` spring from where it
/// was (`StatusPillSlide`), retargeted from its current place. Reduce Motion drops the movement: a fade, and a
/// crossing becomes out, move, in.
@MainActor
final class StatusPillView: NSView {
  static let horizontalPadding: CGFloat = 12
  static let fontSize: CGFloat = 12
  /// The label gap between the host and the rest.
  private static let minimumRestWidth: CGFloat = 24
  static let fadeInDuration: CFTimeInterval = 0.14
  static let fadeOutDuration: CFTimeInterval = 0.09
  static let rise: CGFloat = 4
  static let crossFadeDuration: CFTimeInterval = 0.18
  /// Layer animation keys.
  static let fadeKey = "statusPillFade"
  static let riseKey = "statusPillRise"
  static let crossKey = "statusPillCross"

  let hostLabel = NSTextField(labelWithString: "")
  let restLabel = NSTextField(labelWithString: "")
  private(set) var text = StatusPillText(prefix: "", host: "", rest: "")
  private(set) var corner: StatusPillCorner = .leading
  /// True from `show` until `hide`; a fade-out may still be running after it turns false.
  private(set) var isShown = false

  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  /// Tests turn this off and step the crossing with `stepSlide(at:)`: what they read does not depend on how long the
  /// machine took to get there.
  var drivesDisplayLink = true

  private var slide = StatusPillSlide()
  private var link: CADisplayLink?
  /// The horizontal offset the crossing presents now, from the resting place.
  private(set) var slideOffset: CGFloat = 0
  private var layoutWidth: CGFloat = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    if let layer {
      layer.cornerRadius = StatusPillGeometry.height / 2
      layer.cornerCurve = .continuous
      layer.masksToBounds = false
      layer.opacity = 0
    }
    for label in [hostLabel, restLabel] {
      label.isSelectable = false
      label.isEditable = false
      label.usesSingleLineMode = true
      label.maximumNumberOfLines = 1
      label.lineBreakMode = .byTruncatingMiddle
      label.setAccessibilityElement(false)
      label.cell?.setAccessibilityElement(false)       // AppKit exposes the cell, not the field
      addSubview(label)
    }
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  isolated deinit {
    link?.invalidate()
  }

  // MARK: Never in the way

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var acceptsFirstResponder: Bool { false }
  override var mouseDownCanMoveWindow: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func isAccessibilityHidden() -> Bool { true }
  override func accessibilityChildren() -> [Any]? { [] }

  // MARK: Content and size

  private var hostFont: NSFont { .systemFont(ofSize: Self.fontSize, weight: .semibold) }
  private var restFont: NSFont { .systemFont(ofSize: Self.fontSize, weight: .regular) }
  private var flavor: ThemeFlavor { ThemeFlavor(appearance: effectiveAppearance) }

  private func hostText() -> NSAttributedString {
    let result = NSMutableAttributedString()
    let secondary = ShellTokens.secondaryText.resolve(flavor).nsColor()
    let primary = ShellTokens.primaryText.resolve(flavor).nsColor()
    if !text.prefix.isEmpty {
      result.append(NSAttributedString(string: text.prefix, attributes: [.font: restFont, .foregroundColor: secondary]))
    }
    result.append(NSAttributedString(string: text.host, attributes: [.font: hostFont, .foregroundColor: primary]))
    return result
  }

  private func restText() -> NSAttributedString {
    NSAttributedString(string: text.rest, attributes: [
      .font: restFont, .foregroundColor: ShellTokens.secondaryText.resolve(flavor).nsColor(),
    ])
  }

  private func hostWidth() -> CGFloat { ceil(hostText().size().width) + 4 }          // the cell's 2 pt inset per side
  private func restWidth() -> CGFloat { text.rest.isEmpty ? 0 : ceil(restText().size().width) + 4 }

  /// The width the pill wants for its text, at most `maxWidth`.
  func preferredWidth(maxWidth: CGFloat) -> CGFloat {
    min(maxWidth, Self.horizontalPadding * 2 + hostWidth() + restWidth())
  }

  /// Sets the text (no animation); the owner lays the pill out again.
  func setText(_ newText: StatusPillText) {
    guard newText != text else { return }
    text = newText
    hostLabel.attributedStringValue = hostText()
    restLabel.attributedStringValue = restText()
    needsLayout = true
    superview?.needsLayout = true
  }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let available = max(0, bounds.width - Self.horizontalPadding * 2)
    let host = min(hostWidth(), available)
    let remaining = available - host
    let showsRest = !text.rest.isEmpty && remaining >= Self.minimumRestWidth
    let rest = showsRest ? min(restWidth(), remaining) : 0
    let height = ceil(hostFont.boundingRectForFont.height)
    let y = ((bounds.height - height) / 2).rounded()
    hostLabel.frame = CGRect(x: Self.horizontalPadding - 2, y: y, width: host + 4, height: height)
    restLabel.isHidden = !showsRest
    restLabel.frame = CGRect(x: Self.horizontalPadding - 2 + host, y: y, width: rest, height: height)
    layoutWidth = bounds.width
  }

  // MARK: Colors

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  private func applyColors() {
    guard let layer else { return }
    let flavor = flavor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    let contrast = increaseContrast()
    layer.borderWidth = contrast ? 1 : 0.5
    layer.borderColor = (contrast ? BrandTokens.brandHairlineContrast : ShellTokens.toastEdge).resolve(flavor).cgColor
    let shadow = ShellTokens.toastShadow
    layer.shadowColor = shadow.color.resolve(flavor).cgColor
    layer.shadowOpacity = 1
    layer.shadowRadius = shadow.radius
    layer.shadowOffset = CGSize(width: 0, height: -shadow.offsetY)       // the card is not flipped: down is negative
    CATransaction.commit()
    hostLabel.attributedStringValue = hostText()
    restLabel.attributedStringValue = restText()
  }

  // MARK: Showing and hiding

  /// Shows `text` in `corner`: fades in and rises 4 pt (Reduce Motion: fades only). A pill that is already up swaps
  /// the text at once and stays where it is.
  func show(_ newText: StatusPillText, corner newCorner: StatusPillCorner, animated: Bool) {
    guard !isShown else {
      setText(newText)
      return
    }
    isShown = true
    corner = newCorner
    slide.cancel()
    stopLink()
    setSlideOffset(0)
    setText(newText)
    isHidden = false
    superview?.needsLayout = true
    guard let layer else { return }
    let wasLeaving = layer.animation(forKey: Self.fadeKey) != nil
    let presented = layer.presentation()?.opacity ?? 0
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 1
    CATransaction.commit()
    guard animated else {
      layer.removeAnimation(forKey: Self.fadeKey)
      layer.removeAnimation(forKey: Self.riseKey)
      return
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = wasLeaving ? presented : 0
    fade.toValue = 1
    fade.duration = Self.fadeInDuration
    fade.timingFunction = ToastMotion.easeOut
    layer.add(fade, forKey: Self.fadeKey)
    if reduceMotion() {
      layer.removeAnimation(forKey: Self.riseKey)
    } else {
      layer.add(riseAnimation(from: wasLeaving ? presentedRise() : Self.rise, to: 0, duration: Self.fadeInDuration),
                forKey: Self.riseKey)
    }
  }

  /// Fades out over 0.09 s and sinks back 4 pt (Reduce Motion: fades only). Leaves the card's layout alone.
  func hide(animated: Bool) {
    guard isShown else { return }
    isShown = false
    slide.cancel()
    stopLink()
    guard animated, let layer else {
      layer?.removeAnimation(forKey: Self.fadeKey)
      layer?.removeAnimation(forKey: Self.riseKey)
      layer?.removeAnimation(forKey: Self.crossKey)
      layer?.opacity = 0
      setSlideOffset(0)
      isHidden = true
      return
    }
    let presented = layer.presentation()?.opacity ?? layer.opacity
    let rise = presentedRise()
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = presented
    fade.toValue = 0
    fade.duration = Self.fadeOutDuration
    fade.timingFunction = ToastMotion.easeOut
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    CATransaction.commit()
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShown else { return }
        self.isHidden = true
        self.setSlideOffset(0)
      }
    }
    layer.add(fade, forKey: Self.fadeKey)
    if reduceMotion() {
      layer.removeAnimation(forKey: Self.riseKey)
    } else {
      layer.add(riseAnimation(from: rise, to: Self.rise, duration: Self.fadeOutDuration), forKey: Self.riseKey)
    }
    CATransaction.commit()
  }

  private func riseAnimation(from: CGFloat, to: CGFloat, duration: CFTimeInterval) -> CABasicAnimation {
    // The card is not flipped, so "down" is negative; this view is flipped but its layer is not.
    let move = CABasicAnimation(keyPath: "transform.translation.y")
    move.fromValue = -from
    move.toValue = -to
    move.duration = duration
    move.timingFunction = ToastMotion.easeOut
    move.fillMode = .both
    return move
  }

  private func presentedRise() -> CGFloat {
    guard let y = layer?.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat else { return 0 }
    return -y
  }

  // MARK: Crossing to the other corner

  /// Moves to `newCorner`, whose resting place starts at `newMinX` (the pill is at `oldMinX` now; the owner lays it
  /// out there next). It starts from where it is, wherever the last crossing had reached.
  func setCorner(_ newCorner: StatusPillCorner, from oldMinX: CGFloat, to newMinX: CGFloat, animated: Bool) {
    guard newCorner != corner else { return }
    corner = newCorner
    guard isShown, animated, let layer else {
      slide.cancel()
      stopLink()
      setSlideOffset(0)
      return
    }
    if reduceMotion() {
      slide.cancel()
      stopLink()
      setSlideOffset(0)
      layer.add(crossFade(from: oldMinX, to: newMinX), forKey: Self.crossKey)
      return
    }
    let time = now()
    let presentedOffset = CGFloat(slide.offset(at: time))
    slide.begin(from: Double(oldMinX + presentedOffset - newMinX), at: time)
    setSlideOffset(CGFloat(slide.offset(at: time)))
    startLinkIfNeeded()
  }

  /// Out, move, in: the position holds the old place for the first half and jumps to the new one while the pill is
  /// clear. The card's layout moves the layer's position by exactly `newMinX - oldMinX` right after this.
  private func crossFade(from oldMinX: CGFloat, to newMinX: CGFloat) -> CAAnimationGroup {
    let position = CAKeyframeAnimation(keyPath: "position.x")
    let current = layer?.position.x ?? 0
    position.values = [current, current + (newMinX - oldMinX)]
    position.keyTimes = [0, 0.5]
    position.calculationMode = .discrete
    let opacity = CAKeyframeAnimation(keyPath: "opacity")
    opacity.values = [1, 0, 1]
    opacity.keyTimes = [0, 0.5, 1]
    opacity.timingFunctions = [ToastMotion.easeOut, ToastMotion.easeOut]
    let group = CAAnimationGroup()
    group.animations = [position, opacity]
    group.duration = Self.crossFadeDuration
    return group
  }

  /// Presents the crossing at `time` (a display-link timestamp; tests pass their own).
  func stepSlide(at time: CFTimeInterval) {
    setSlideOffset(CGFloat(slide.offset(at: time)))
    if !slide.isActive { stopLink() }
  }

  var isSliding: Bool { slide.isActive }

  private func setSlideOffset(_ offset: CGFloat) {
    guard offset != slideOffset else { return }
    slideOffset = offset
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.setAffineTransform(CGAffineTransform(translationX: offset, y: 0))
    CATransaction.commit()
  }

  private func startLinkIfNeeded() {
    guard drivesDisplayLink, link == nil, window != nil else { return }
    let proxy = LinkTarget(owner: self)
    let link = displayLink(target: proxy, selector: #selector(LinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func stopLink() {
    link?.invalidate()
    link = nil
  }

  @MainActor
  private final class LinkTarget: NSObject {
    weak var owner: StatusPillView?
    init(owner: StatusPillView) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
      guard let owner, owner.link === link else { link.invalidate(); return }
      owner.stepSlide(at: link.targetTimestamp)
    }
  }
}
