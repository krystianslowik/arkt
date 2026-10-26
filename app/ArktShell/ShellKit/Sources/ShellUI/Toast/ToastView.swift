import AppKit

/// Draws a `Toast` (docs/design/alerts-sheets-toasts.md, section 4.2): a floating pill over the bottom of the content
/// card with a leading glyph, one sentence and one small neutral action pill. A persistent toast (recovery) wraps to
/// three lines in a 300 pt column, with its action and a dismiss button top-aligned. The surface is
/// `AlertTokens.toastSurface` for the Space theme (decision 2), a plain layer fill with `toastShadow` and `toastEdge`,
/// never a blur. `ContentCardView.layout()` sets its frame from `preferredSize(maxWidth:)`; the subviews are laid out
/// here. It comes, goes and is replaced with `ToastMotion`.
@MainActor
final class ToastView: NSView {
  static let maxWidth: CGFloat = 480
  static let bottomInset: CGFloat = 16
  static let height: CGFloat = 36
  /// Persistent toasts: the text column, its lines and their height (13 pt at 1.38).
  static let textColumnWidth: CGFloat = 300
  static let maximumLines = 3
  static let lineHeight: CGFloat = 18
  static let multiLineRadius: CGFloat = 12
  private static let leadingPadding: CGFloat = 12
  private static let trailingPadding: CGFloat = 14
  private static let trailingPaddingWithAction: CGFloat = 6
  private static let glyphBox: CGFloat = 16
  private static let glyphGap: CGFloat = 8
  private static let actionGap: CGFloat = 8
  private static let dismissSize: CGFloat = 24
  private static let dismissGap: CGFloat = 4
  /// Persistent: padding 10 / 8 / 10 / 12.
  private static let multiLineInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 8)
  /// The text field cell's inset on each side of its text.
  private static let labelInset: CGFloat = 2
  /// Layer animation keys of the entrance and exit.
  static let transformKey = "toastTransform"
  static let fadeKey = "fade"

  let glyphView = NSImageView()
  let label = NSTextField(wrappingLabelWithString: "")
  let actionButton = ArchivePillButton(style: .neutral, title: "", metrics: .toastAction)
  let dismissButton = ToastDismissButton()
  /// The presenter whose action the button runs.
  weak var presenter: ToastPresenter?
  /// The Space theme the toast takes its flavor and tint from (BH-190, decision 2); nil: the plain light toast.
  var theme: SpaceThemeInfo? {
    didSet { if theme != oldValue { applyColors() } }
  }
  /// Dark text on a light fill for light themes, light on dark for dark ones (BH-190).
  var flavor: ThemeFlavor { theme?.flavor ?? .light }

  /// An untinted theme of `flavor`, for windows without a Space (the Archive window follows the system).
  static func plainTheme(_ flavor: ThemeFlavor) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: [flavor == .dark ? .black(1) : .white(1)], isDark: flavor == .dark)
  }
  /// True while a toast is displayed (a fade-out may still be running after it turns false).
  private(set) var isShowingToast = false
  /// Reduce Motion, read when the toast comes or goes. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Reduce Transparency: the surface goes opaque. Tests set it.
  var reduceTransparency: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
  /// Increase Contrast: the action pill gains a 1 pt edge. Tests set it.
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  /// The toast on screen, for layout.
  private var shown: Toast?
  private var tracking: NSTrackingArea?
  private var keyObservers: [NSObjectProtocol] = []
  /// The replaced toast, leaving as a snapshot while the new one enters.
  private(set) var leavingSnapshot: CALayer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    if let layer {
      layer.cornerRadius = Self.height / 2
      layer.cornerCurve = .continuous
      layer.masksToBounds = false
      layer.borderWidth = 0.5
    }
    glyphView.imageScaling = .scaleProportionallyDown
    glyphView.setAccessibilityElement(false)
    glyphView.cell?.setAccessibilityElement(false)        // decorative: the text says it
    addSubview(glyphView)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.isSelectable = false
    label.setAccessibilityElement(false)
    label.cell?.setAccessibilityElement(false)      // AppKit exposes the cell, not the field
    addSubview(label)
    actionButton.refusesFirstResponder = true
    actionButton.target = self
    actionButton.action = #selector(performAction(_:))
    actionButton.isHidden = true
    addSubview(actionButton)
    dismissButton.target = self
    dismissButton.action = #selector(dismissPressed(_:))
    dismissButton.isHidden = true
    addSubview(dismissButton)
    // A group labelled with the toast text: the label is folded into the group's label, and the action and dismiss
    // buttons stay reachable children for VoiceOver.
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Toast.root)
    actionButton.setAccessibilityIdentifierWithCell(AXID.Toast.action)
    dismissButton.setAccessibilityIdentifierWithCell(AXID.Toast.dismiss)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { false }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Shows `toast`, or fades out when nil. A toast shown over another one replaces it: the old one leaves as a
  /// snapshot while the new one enters. Never touches the first responder.
  func display(_ toast: Toast?, animated: Bool) {
    guard let toast else {
      shown = nil
      presenter?.setPaused(false, for: .hover)
      hide(animated: animated)
      return
    }
    let wasShowing = isShowingToast
    let replacing = wasShowing && shown != toast && animated && window != nil
    if replacing { leaveAsSnapshot() }
    shown = toast
    configure(for: toast)
    isShowingToast = true
    isHidden = false
    superview?.needsLayout = true
    needsLayout = true
    if !wasShowing || replacing {
      superview?.layoutSubtreeIfNeeded()            // the entrance scales about the pill's center at its new size
      enter(animated: animated)
    }
    let priority: NSAccessibilityPriorityLevel = toast.isPolite ? .medium : .high
    NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
      .announcement: toast.spokenText,
      .priority: priority.rawValue,
    ])
  }

  private func configure(for toast: Toast) {
    let multiLine = toast.isPersistent
    label.maximumNumberOfLines = multiLine ? Self.maximumLines : 1
    label.lineBreakMode = multiLine ? .byWordWrapping : .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    label.cell?.wraps = multiLine
    label.cell?.isScrollable = false
    label.attributedStringValue = attributedText(toast.text, multiLine: multiLine)
    glyphView.image = toast.glyph.flatMap {
      NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    }
    glyphView.isHidden = glyphView.image == nil
    actionButton.title = toast.actionTitle ?? ""
    actionButton.shortcut = toast.shortcut
    actionButton.isHidden = toast.actionTitle == nil
    actionButton.setAccessibilityLabel(toast.actionTitle)
    actionButton.cell?.setAccessibilityLabel(toast.actionTitle)
    dismissButton.isHidden = !multiLine
    layer?.cornerRadius = multiLine ? Self.multiLineRadius : Self.height / 2
    applyColors()
    setAccessibilityLabel(toast.text)
    setAccessibilityValue(toast.isPersistent ? AXID.Toast.persistent : AXID.Toast.timed)
  }

  private func attributedText(_ text: String, multiLine: Bool) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = multiLine ? .byWordWrapping : .byTruncatingTail
    if multiLine {
      paragraph.minimumLineHeight = Self.lineHeight
      paragraph.maximumLineHeight = Self.lineHeight
    }
    return NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: ShellTokens.toastText.resolve(flavor).nsColor(),
      .paragraphStyle: paragraph,
    ])
  }

  // MARK: - Size and layout

  private var isMultiLine: Bool { shown?.isPersistent ?? false }

  /// The text's own one-line width, plus the field's insets.
  private var naturalTextWidth: CGFloat {
    ceil(NSAttributedString(string: label.stringValue, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    ]).size().width) + 2 * Self.labelInset
  }

  /// The text column of a persistent toast: its one-line width up to `textColumnWidth`.
  private var textColumnWidth: CGFloat { min(naturalTextWidth, Self.textColumnWidth) }

  private var glyphWidth: CGFloat { glyphView.isHidden ? 0 : Self.glyphBox + Self.glyphGap }
  private var actionWidth: CGFloat { actionButton.isHidden ? 0 : ceil(actionButton.intrinsicContentSize.width) }

  /// The height of the wrapped text at `width`, up to `maximumLines` lines.
  private func textHeight(width: CGFloat) -> CGFloat {
    let fitting = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 0
    return min(max(ceil(fitting), Self.lineHeight), Self.lineHeight * CGFloat(Self.maximumLines))
  }

  /// Size for the current text, capped at `maxWidth` (and `maxWidth` of the toast).
  func preferredSize(maxWidth: CGFloat) -> NSSize {
    let limit = min(maxWidth, Self.maxWidth)
    if isMultiLine {
      let insets = Self.multiLineInsets
      let trailing = (actionButton.isHidden ? 0 : Self.actionGap + actionWidth)
        + Self.dismissGap + Self.dismissSize
      let fixed = insets.left + glyphWidth + trailing + insets.right
      let column = max(0, min(textColumnWidth, limit - fixed))
      let height = insets.top + textHeight(width: column) + insets.bottom
      return NSSize(width: min(fixed + column, limit), height: max(Self.height, height))
    }
    let action = actionButton.isHidden ? 0 : Self.actionGap + actionWidth
    let trailing = actionButton.isHidden ? Self.trailingPadding : Self.trailingPaddingWithAction
    let width = Self.leadingPadding + glyphWidth + naturalTextWidth + action + trailing
    return NSSize(width: min(width, limit), height: Self.height)
  }

  /// The frame in a host's (unflipped) `bounds`: centered, `bottomInset` above the bottom edge, at most `maxWidth`
  /// wide. The single content card and the split container both place the toast this way.
  func frame(centeredIn bounds: CGRect) -> NSRect {
    let size = preferredSize(maxWidth: max(0, bounds.width - 2 * Self.bottomInset))
    return NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: Self.bottomInset,
                  width: size.width, height: size.height)
  }

  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: layer?.cornerRadius ?? 0,
                               cornerHeight: layer?.cornerRadius ?? 0, transform: nil)
    if isMultiLine { layoutMultiLine() } else { layoutSingleLine() }
    updateTrackingAreas()
  }

  private func layoutSingleLine() {
    var x = Self.leadingPadding
    if !glyphView.isHidden {
      glyphView.frame = NSRect(x: x, y: ((bounds.height - Self.glyphBox) / 2).rounded(), width: Self.glyphBox,
                               height: Self.glyphBox)
      x += Self.glyphBox + Self.glyphGap
    }
    var labelRight = bounds.width - Self.trailingPadding
    if !actionButton.isHidden {
      let height = actionButton.metrics.height
      actionButton.frame = NSRect(x: bounds.width - Self.trailingPaddingWithAction - actionWidth,
                                  y: ((bounds.height - height) / 2).rounded(), width: actionWidth, height: height)
      labelRight = actionButton.frame.minX - Self.actionGap
    }
    let labelHeight = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(x: x - Self.labelInset, y: ((bounds.height - labelHeight) / 2).rounded(),
                         width: max(0, labelRight - x + Self.labelInset), height: labelHeight)
  }

  private func layoutMultiLine() {
    let insets = Self.multiLineInsets
    let firstLineMid = insets.top + Self.lineHeight / 2
    var x = insets.left
    if !glyphView.isHidden {
      glyphView.frame = NSRect(x: x, y: (firstLineMid - Self.glyphBox / 2).rounded(), width: Self.glyphBox,
                               height: Self.glyphBox)
      x += Self.glyphBox + Self.glyphGap
    }
    var right = bounds.width - insets.right
    dismissButton.frame = NSRect(x: right - Self.dismissSize, y: (firstLineMid - Self.dismissSize / 2).rounded(),
                                 width: Self.dismissSize, height: Self.dismissSize)
    right = dismissButton.frame.minX - Self.dismissGap
    if !actionButton.isHidden {
      let height = actionButton.metrics.height
      actionButton.frame = NSRect(x: right - actionWidth, y: (firstLineMid - height / 2).rounded(),
                                  width: actionWidth, height: height)
      right = actionButton.frame.minX - Self.actionGap
    }
    let width = max(0, right - x)
    label.frame = NSRect(x: x - Self.labelInset, y: insets.top, width: width + Self.labelInset,
                         height: textHeight(width: width + Self.labelInset))
  }

  /// True when the label shows its whole text (no line cut off and no truncation).
  var showsWholeText: Bool {
    let needed = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.frame.width, height: 10_000))
      .height ?? .infinity
    return ceil(needed) <= label.frame.height + 0.5
  }

  // MARK: - Hover and key (timers pause, alerts design 4.1)

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard isShowingToast else { return }
    presenter?.setPaused(true, for: .hover)
  }

  override func mouseExited(with event: NSEvent) {
    presenter?.setPaused(false, for: .hover)
  }

  /// Follows its window's key state: a toast's timer waits while the window is not key. The first state is left
  /// alone (a window shown without becoming key, as in tests, keeps its timers).
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
    keyObservers = []
    guard let window else { return }
    let center = NotificationCenter.default
    for (name, paused) in [(NSWindow.didBecomeKeyNotification, false), (NSWindow.didResignKeyNotification, true)] {
      keyObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.presenter?.setPaused(paused, for: .windowInactive) }
      })
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  @objc private func performAction(_ sender: Any?) { presenter?.performAction() }
  @objc private func dismissPressed(_ sender: Any?) { presenter?.dismissFromButton() }

  private func hide(animated: Bool) {
    guard isShowingToast else { return }
    isShowingToast = false
    guard animated, let layer else {
      layer?.removeAnimation(forKey: Self.transformKey)
      layer?.removeAnimation(forKey: Self.fadeKey)
      layer?.opacity = 0
      layer?.transform = CATransform3DIdentity
      isHidden = true
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShowingToast else { return }
        self.isHidden = true
        self.layer?.transform = CATransform3DIdentity
      }
    }
    exit(layer, bounds: bounds)
    CATransaction.commit()
  }

  // MARK: - Motion (alerts design, section 7)

  /// Rises into place and fades in. Starts from where a running exit left the pill, so a toast shown again while it
  /// leaves turns around instead of jumping.
  private func enter(animated: Bool) {
    guard let layer else { return }
    let step = ToastMotion.enter(reduceMotion: reduceMotion())
    let leaving = layer.animation(forKey: Self.fadeKey) != nil && leavingSnapshot == nil
    let presentation = layer.presentation()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 1
    layer.transform = CATransform3DIdentity
    CATransaction.commit()
    guard animated else {
      layer.removeAnimation(forKey: Self.transformKey)
      layer.removeAnimation(forKey: Self.fadeKey)
      return
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = leaving ? (presentation?.opacity ?? 0) : 0
    fade.toValue = 1
    fade.duration = step.fadeDuration
    fade.timingFunction = ToastMotion.easeOut
    layer.add(fade, forKey: Self.fadeKey)
    guard let spring = step.spring else {
      layer.removeAnimation(forKey: Self.transformKey)
      return
    }
    let start = leaving ? (presentation?.transform ?? restingStart(step)) : restingStart(step)
    let motion = CASpringAnimation(keyPath: "transform")
    motion.mass = CGFloat(spring.mass)
    motion.stiffness = CGFloat(spring.stiffness)
    motion.damping = CGFloat(spring.damping)
    motion.fromValue = NSValue(caTransform3D: start)
    motion.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    motion.duration = max(spring.settlingDuration(), motion.settlingDuration)
    layer.add(motion, forKey: Self.transformKey)
  }

  private func restingStart(_ step: ToastMotion.Step) -> CATransform3D {
    ToastMotion.transform(offset: step.offset, scale: step.scale, bounds: bounds, anchor: layer?.anchorPoint ?? .zero)
  }

  /// Sinks a little and fades out, from wherever the entrance is (an interrupted entrance reverses from there).
  private func exit(_ layer: CALayer, bounds: CGRect) {
    let step = ToastMotion.exit(reduceMotion: reduceMotion())
    let presentation = layer.presentation()
    let end = ToastMotion.transform(offset: step.offset, scale: step.scale, bounds: bounds, anchor: layer.anchorPoint)
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = presentation?.opacity ?? layer.opacity
    fade.toValue = 0
    fade.duration = step.fadeDuration
    fade.timingFunction = ToastMotion.easeOut
    let move = CABasicAnimation(keyPath: "transform")
    move.fromValue = NSValue(caTransform3D: presentation?.transform ?? layer.transform)
    move.toValue = NSValue(caTransform3D: end)
    move.duration = step.fadeDuration
    move.timingFunction = ToastMotion.easeOut
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    layer.transform = end
    CATransaction.commit()
    layer.add(fade, forKey: Self.fadeKey)
    layer.add(move, forKey: Self.transformKey)
  }

  /// The toast being replaced leaves as a snapshot layer under this one, the way any toast exits, while this view
  /// enters with the new toast at its own width (no width animation, section 7).
  private func leaveAsSnapshot() {
    leavingSnapshot?.removeFromSuperlayer()
    leavingSnapshot = nil
    guard let layer, let host = superview?.layer, bounds.width > 0, bounds.height > 0,
          let image = snapshotImage() else { return }
    let ghost = CALayer()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ghost.contents = image
    ghost.contentsScale = window?.backingScaleFactor ?? 2
    ghost.anchorPoint = layer.anchorPoint
    ghost.bounds = CGRect(origin: .zero, size: bounds.size)
    ghost.position = layer.position
    ghost.transform = layer.presentation()?.transform ?? layer.transform
    ghost.opacity = layer.presentation()?.opacity ?? layer.opacity
    ghost.contentsGravity = .resize
    host.insertSublayer(ghost, below: layer)
    CATransaction.commit()
    leavingSnapshot = ghost
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self, weak ghost] in
      MainActor.assumeIsolated {
        ghost?.removeFromSuperlayer()
        if self?.leavingSnapshot === ghost { self?.leavingSnapshot = nil }
      }
    }
    exit(ghost, bounds: ghost.bounds)
    CATransaction.commit()
  }

  /// The pill as drawn now, for the replaced toast's exit.
  private func snapshotImage() -> CGImage? {
    guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    cacheDisplay(in: bounds, to: rep)
    return rep.cgImage
  }

  // MARK: - Colors

  private func applyColors() {
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    guard let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.backgroundColor = AlertTokens.toastSurface(theme: theme, opaque: reduceTransparency()).cgColor
    layer.borderColor = AlertTokens.toastEdge.resolve(flavor).cgColor
    let shadow = AlertTokens.toastShadow
    layer.shadowColor = shadow.color.resolve(flavor).cgColor
    layer.shadowOpacity = 1
    layer.shadowRadius = shadow.radius
    layer.shadowOffset = CGSize(width: 0, height: -shadow.offsetY)       // the card is not flipped: down is negative
    CATransaction.commit()
    let text = ShellTokens.toastText.resolve(flavor)
    var glyph = text
    glyph.alpha *= AlertTokens.toastGlyphAlpha.resolve(flavor).alpha
    glyphView.contentTintColor = glyph.nsColor()
    dismissButton.contentTintColor = glyph.nsColor()
    dismissButton.flavor = flavor
    if let shown { label.attributedStringValue = attributedText(shown.text, multiLine: shown.isPersistent) }
    actionButton.edge = increaseContrast() ? AlertTokens.increasedContrastEdge.resolve(flavor) : nil
  }
}

/// The persistent toast's dismiss button: a 24 x 24 capsule with a 10 pt xmark, a hover fill and no focus (toasts
/// never take focus). VoiceOver reads it as "Dismiss".
@MainActor
final class ToastDismissButton: NSButton {
  var flavor: ThemeFlavor = .light { didSet { updateFill() } }
  private var hovering = false
  private var tracking: NSTrackingArea?

  init() {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    refusesFirstResponder = true
    image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    setAccessibilityLabel("Dismiss")
    cell?.setAccessibilityLabel("Dismiss")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    updateFill()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    updateFill()
  }

  private func updateFill() {
    layer?.backgroundColor = hovering ? ShellTokens.sidebarItemHovered.resolve(flavor).cgColor : nil
  }
}
