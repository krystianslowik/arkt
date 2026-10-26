import AppKit

/// Draws a `Toast`: a rounded, layer-backed pill with one label and an optional borderless action button (with its
/// key after the title, #346). `ContentCardView.layout()` sets its frame from `preferredSize(maxWidth:)`; the subviews
/// are laid out here. It comes and goes with `ToastMotion`.
@MainActor
final class ToastView: NSView {
  static let maxWidth: CGFloat = 480
  static let bottomInset: CGFloat = 16
  static let height: CGFloat = 36
  private static let horizontalPadding: CGFloat = 14
  private static let buttonSpacing: CGFloat = 12
  /// Layer animation keys of the entrance and exit.
  static let transformKey = "toastTransform"
  static let fadeKey = "fade"

  let label = NSTextField(labelWithString: "")
  let actionButton = NSButton(title: "", target: nil, action: nil)
  /// The presenter whose action the button runs.
  weak var presenter: ToastPresenter?
  /// The Space theme's flavor: dark text on a light fill for light themes, light on dark for dark ones (BH-190).
  var flavor: ThemeFlavor = .light {
    didSet { if flavor != oldValue { applyColors() } }
  }
  /// True while a toast is displayed (a fade-out may still be running after it turns false).
  private(set) var isShowingToast = false
  /// Reduce Motion, read when the toast comes or goes. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The action's key ("\u{2318}Z"), drawn after its title.
  private var shortcut: String?
  private var actionTitle: String?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    if let layer {
      layer.cornerRadius = Self.height / 2
      layer.cornerCurve = .continuous
    }
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.setAccessibilityElement(false)
    label.cell?.setAccessibilityElement(false)      // AppKit exposes the cell, not the field
    addSubview(label)
    actionButton.isBordered = false
    actionButton.refusesFirstResponder = true
    actionButton.font = .systemFont(ofSize: 13, weight: .semibold)
    actionButton.target = self
    actionButton.action = #selector(performAction(_:))
    actionButton.isHidden = true
    addSubview(actionButton)
    // A group labelled with the toast text: the label is folded into the group's label, and the action button stays
    // a reachable child for VoiceOver.
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Toast.root)
    actionButton.setAccessibilityIdentifierWithCell(AXID.Toast.action)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { false }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Shows `toast`, or fades out when nil. Never touches the first responder.
  func display(_ toast: Toast?, animated: Bool) {
    guard let toast else {
      hide(animated: animated)
      return
    }
    label.stringValue = toast.text
    actionButton.title = toast.actionTitle ?? ""
    actionButton.isHidden = toast.actionTitle == nil
    actionButton.setAccessibilityLabel(toast.actionTitle)
    shortcut = toast.shortcut
    actionTitle = toast.actionTitle
    applyColors()
    setAccessibilityLabel(toast.text)
    setAccessibilityValue(toast.isPersistent ? AXID.Toast.persistent : AXID.Toast.timed)
    let wasShowing = isShowingToast
    isShowingToast = true
    isHidden = false
    superview?.needsLayout = true
    needsLayout = true
    if !wasShowing {
      superview?.layoutSubtreeIfNeeded()            // the entrance scales about the pill's center at its new size
      enter(animated: animated)
    }
    let priority: NSAccessibilityPriorityLevel = toast.isPolite ? .medium : .high
    NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
      .announcement: toast.spokenText,
      .priority: priority.rawValue,
    ])
  }

  /// Size for the current text, capped at `maxWidth`.
  func preferredSize(maxWidth: CGFloat) -> NSSize {
    let labelWidth = ceil(label.intrinsicContentSize.width)
    let buttonWidth = actionButton.isHidden ? 0 : ceil(actionButton.intrinsicContentSize.width) + Self.buttonSpacing
    let width = labelWidth + buttonWidth + 2 * Self.horizontalPadding
    return NSSize(width: min(width, min(maxWidth, Self.maxWidth)), height: Self.height)
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
    let padding = Self.horizontalPadding
    var labelRight = bounds.width - padding
    if !actionButton.isHidden {
      let size = actionButton.intrinsicContentSize
      let width = ceil(size.width)
      actionButton.frame = NSRect(x: bounds.width - padding - width, y: ((bounds.height - size.height) / 2).rounded(),
                                  width: width, height: size.height)
      labelRight = actionButton.frame.minX - Self.buttonSpacing
    }
    let labelHeight = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(x: padding, y: ((bounds.height - labelHeight) / 2).rounded(),
                         width: max(0, labelRight - padding), height: labelHeight)
  }

  @objc private func performAction(_ sender: Any?) { presenter?.performAction() }

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
    exit(layer)
    CATransaction.commit()
  }

  // MARK: - Motion (alerts design, section 7)

  /// Rises into place and fades in. Starts from where a running exit left the pill, so a toast shown again while it
  /// leaves turns around instead of jumping.
  private func enter(animated: Bool) {
    guard let layer else { return }
    let step = ToastMotion.enter(reduceMotion: reduceMotion())
    let leaving = layer.animation(forKey: Self.fadeKey) != nil
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
    let start = leaving ? (presentation?.transform ?? restingStart(step))
      : restingStart(step)
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
  private func exit(_ layer: CALayer) {
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

  private func applyColors() {
    layer?.backgroundColor = ShellTokens.toastSurface.resolve(flavor).cgColor
    let text = ShellTokens.toastText.resolve(flavor).nsColor()
    label.textColor = text
    actionButton.contentTintColor = text
    applyActionTitle(color: text)
  }

  /// "Reopen" in the action's weight, then its key at half strength (the Peek's toast, #346).
  private func applyActionTitle(color: NSColor) {
    guard let shortcut, let actionTitle else { return }
    let title = NSMutableAttributedString(string: actionTitle, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color,
    ])
    title.append(NSAttributedString(string: " " + shortcut, attributes: [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color.withAlphaComponent(0.5),
    ]))
    actionButton.attributedTitle = title
  }
}
