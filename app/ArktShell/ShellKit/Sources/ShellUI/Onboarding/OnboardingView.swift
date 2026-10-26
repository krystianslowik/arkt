import AppKit

/// The first run over the whole window (section 4 and 7.1): `surfaceBrand` from edge to edge, the theme wash, the
/// stage, the current step's content and the footer. One accessibility group, "Welcome to Arkt", whose value is
/// "Step {n} of {total}". The view is the window's first responder between controls, so Escape and the arrows reach
/// it; controls that own the arrows (the name field, swatches, segmented control and option) keep them.
@MainActor
final class OnboardingView: NSView {
  /// Keys the controller answers.
  enum Key { case escape, left, right }

  var appearanceModel: OnboardingAppearance { didSet { if appearanceModel != oldValue { restyle() } } }
  var onKey: (@MainActor (Key) -> Void)?
  var onBack: (@MainActor () -> Void)?
  var onSkipSetup: (@MainActor () -> Void)?
  /// The window's light or dark appearance changed.
  var onAppearanceChange: (@MainActor () -> Void)?
  /// The window was resized: shapes are built again from the new layout.
  var onResize: (@MainActor () -> Void)?
  private var laidOutSize = NSSize.zero

  let surface = CALayer()
  let wash = CAGradientLayer()
  let stage: any OnboardingStage
  private(set) var stepView: OnboardingStepView?
  let backButton: PillButton
  let skipButton: PillButton
  let progressLabel: BrandLabel

  init(stage: any OnboardingStage, appearance: OnboardingAppearance) {
    self.stage = stage
    self.appearanceModel = appearance
    backButton = PillButton(style: .quiet, title: OnboardingCopy.back, appearance: appearance)
    skipButton = PillButton(style: .quiet, title: OnboardingCopy.skipSetup, appearance: appearance)
    progressLabel = BrandLabel(role: .progress, color: appearance.textSecondary)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    layer?.addSublayer(surface)
    wash.startPoint = .zero
    wash.endPoint = CGPoint(x: 1, y: 1)
    wash.opacity = 0
    layer?.addSublayer(wash)
    addSubview(stage.view)
    backButton.setAccessibilityIdentifierWithCell(AXID.Onboarding.back)
    skipButton.setAccessibilityIdentifierWithCell(AXID.Onboarding.skipSetup)
    progressLabel.setAccessibilityIdentifier(AXID.Onboarding.progress)
    backButton.onPress = { [weak self] in self?.onBack?() }
    skipButton.onPress = { [weak self] in self?.onSkipSetup?() }
    for view in [backButton, progressLabel, skipButton] as [NSView] { addSubview(view) }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(OnboardingCopy.groupLabel)
    setAccessibilityIdentifier(AXID.Onboarding.root)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { !passesEventsThrough }
  /// Set for the finish (M8): the browser underneath takes the pointer while the field fades.
  var passesEventsThrough = false

  override func hitTest(_ point: NSPoint) -> NSView? {
    passesEventsThrough ? nil : super.hitTest(point)
  }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Windows shorter than 700 pt use the compact values of section 4.
  var isCompact: Bool { bounds.height < 700 }

  private func restyle() {
    OnboardingMotion.set { surface.backgroundColor = appearanceModel.surface.cgColor }
    backButton.appearanceModel = appearanceModel
    skipButton.appearanceModel = appearanceModel
    progressLabel.color = appearanceModel.textSecondary
    progressLabel.halo = appearanceModel.halo
  }

  // MARK: Steps

  /// Replaces the step content: the old one leaves in 200 ms (or at once), the new one is laid out at rest first.
  func setStep(_ view: OnboardingStepView, animated: Bool) {
    let old = stepView
    stepView = view
    view.frame = bounds
    view.autoresizingMask = [.width, .height]
    addSubview(view, positioned: .below, relativeTo: backButton)
    view.layoutSubtreeIfNeeded()
    if let old {
      if animated {
        old.conceal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak old] in old?.removeFromSuperview() }
      } else {
        old.removeFromSuperview()
      }
    }
    rebuildKeyLoop()
  }

  /// Footer pieces keep their place when hidden, so nothing shifts.
  func setFooter(showsBack: Bool, progress: String?, showsSkip: Bool, animated: Bool) {
    func show(_ view: NSView, _ shown: Bool) {
      if let button = view as? PillButton {
        button.isEnabled = shown
        button.cell?.setAccessibilityElement(shown)     // a button reaches VoiceOver through its cell
      } else {
        view.setAccessibilityElement(shown)
      }
      guard let layer = view.layer else { return }
      OnboardingMotion.animate(layer, "opacity", to: Float(shown ? 1 : 0), duration: animated ? 0.25 : 0)
      view.isHidden = false
    }
    show(backButton, showsBack)
    show(skipButton, showsSkip)
    progressLabel.text = progress ?? ""
    show(progressLabel, progress != nil)
    setAccessibilityValue(progress.map { _ in stepValue } ?? "")
    needsLayout = true
    rebuildKeyLoop()
  }

  /// "Step {n} of {total}", set by the controller with the footer.
  var stepValue = ""

  func setWash(_ theme: SpaceThemeInfo?, animated: Bool) {
    if let theme {
      let colors = theme.baseColors.map(\.cgColor)
      OnboardingMotion.animate(wash, "colors", to: colors.count > 1 ? colors : colors + colors,
                               duration: animated ? 0.28 : 0)
    }
    OnboardingMotion.animate(wash, "opacity", to: theme == nil ? Float(0) : appearanceModel.washOpacity,
                             duration: animated ? 0.6 : 0, timing: CAMediaTimingFunction(name: .default))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }

  // MARK: Layout

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      surface.frame = bounds
      wash.frame = bounds
    }
    stage.view.frame = bounds
    stepView?.frame = bounds
    if laidOutSize != bounds.size {
      let first = laidOutSize == .zero
      laidOutSize = bounds.size
      if !first { onResize?() }
    }
    let y = bounds.height - 16 - PillButton.quietHeight
    let back = backButton.intrinsicContentSize, skip = skipButton.intrinsicContentSize
    backButton.frame = NSRect(x: 26 - 14, y: y, width: back.width, height: back.height)
    skipButton.frame = NSRect(x: bounds.width - 26 + 14 - skip.width, y: y, width: skip.width, height: skip.height)
    let progress = progressLabel.textSize
    progressLabel.frame = NSRect(x: (bounds.midX - progress.width / 2).rounded(),
                                 y: (y + (PillButton.quietHeight - progress.height) / 2).rounded(),
                                 width: ceil(progress.width), height: ceil(progress.height))
  }

  // MARK: Keyboard

  /// Tab and Shift-Tab: the step's controls in reading order, then Back and Skip setup (section 10).
  func rebuildKeyLoop() {
    var views: [NSView] = stepView?.keyViews ?? []
    if backButton.isEnabled { views.append(backButton) }
    if skipButton.isEnabled { views.append(skipButton) }
    guard let first = views.first else {
      nextKeyView = nil
      return
    }
    nextKeyView = first
    for (view, next) in zip(views, views.dropFirst() + [first]) { view.nextKeyView = next }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onKey?(.escape)
      return
    }
    switch event.specialKey {
    case .leftArrow?: onKey?(.left)
    case .rightArrow?: onKey?(.right)
    default: super.keyDown(with: event)
    }
  }

  override func cancelOperation(_ sender: Any?) { onKey?(.escape) }

  // MARK: Accessibility

  override func accessibilityChildren() -> [Any]? {
    var children: [Any] = stepView.map { [$0] } ?? []
    if backButton.cell?.isAccessibilityElement() == true { children.append(backButton) }
    if progressLabel.isAccessibilityElement() { children.append(progressLabel) }
    if skipButton.cell?.isAccessibilityElement() == true { children.append(skipButton) }
    return children
  }
}
