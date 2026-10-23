import AppKit

/// Draws a `Toast`: a rounded, layer-backed pill with one label and an optional borderless action button.
/// `ContentCardView.layout()` sets its frame from `preferredSize(maxWidth:)`; the subviews are laid out here.
@MainActor
final class ToastView: NSView {
  static let maxWidth: CGFloat = 480
  static let bottomInset: CGFloat = 16
  static let height: CGFloat = 36
  private static let horizontalPadding: CGFloat = 14
  private static let buttonSpacing: CGFloat = 12
  private static let fadeDuration: CFTimeInterval = 0.15

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
    applyColors()
    setAccessibilityLabel(toast.text)
    let wasShowing = isShowingToast
    isShowingToast = true
    isHidden = false
    superview?.needsLayout = true
    needsLayout = true
    if !wasShowing { fade(to: 1, animated: animated) }
    NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
      .announcement: toast.text,
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
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
    guard animated else {
      layer?.opacity = 0
      isHidden = true
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShowingToast else { return }
        self.isHidden = true
      }
    }
    fade(to: 0, animated: true)
    CATransaction.commit()
  }

  /// Opacity-only fade; layout never animates. Drives `layer.opacity` directly: never mix in `alphaValue`.
  private func fade(to opacity: Float, animated: Bool) {
    guard let layer else { return }
    if animated {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
      animation.toValue = opacity
      animation.duration = Self.fadeDuration
      layer.add(animation, forKey: "fade")
    }
    layer.opacity = opacity
  }

  private func applyColors() {
    layer?.backgroundColor = ShellTokens.toastSurface.resolve(flavor).cgColor
    let text = ShellTokens.toastText.resolve(flavor).nsColor()
    label.textColor = text
    actionButton.contentTintColor = text
  }
}
