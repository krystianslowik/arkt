import AppKit

/// The find bar, direction A (design/find-in-page): a 372 x 36 pill at the top trailing corner of the page card with
/// the field, the count ("3 of 12" or "No matches"), previous and next, and close. A sibling above the card's clip
/// view, like the toast: the field needs the keyboard, so it is not a panel. Hot path rules: frames set directly,
/// transform and opacity only. `FindBarPresenter` holds the state; this view draws `display` and reports the user.
@MainActor
public final class FindBarView: NSView, NSTextFieldDelegate {
  /// Layer animation keys of the entrance and the nudge.
  static let fadeKey = "findBarFade"
  static let riseKey = "findBarRise"
  static let nudgeKey = "findBarNudge"

  weak var presenter: FindBarPresenter?
  let field = FindBarField()
  let countLabel = NSTextField(labelWithString: "")
  let glyphView = NSImageView()
  let previousButton = FindBarButton(symbol: "chevron.up", pointSize: 11, label: "Previous match",
                                     identifier: AXID.Find.previous)
  let nextButton = FindBarButton(symbol: "chevron.down", pointSize: 11, label: "Next match",
                                 identifier: AXID.Find.next)
  let closeButton = FindBarButton(symbol: "xmark", pointSize: 10, label: "Close find bar",
                                  identifier: AXID.Find.close)
  /// The pill: the surface fill, the 0.5 pt edge and the radius. Two shadow layers sit under it.
  let surfaceLayer = CALayer()
  private let separator = CALayer()
  private var dropLayers: [CALayer] = []
  /// Reduce Motion, read when the bar comes or the field nudges. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { for button in [previousButton, nextButton, closeButton] { button.reduceMotion = reduceMotion } }
  }
  /// Speaks a count instead of VoiceOver. Tests set it.
  var postAnnouncement: (@MainActor (String) -> Void)?

  public init(presenter: FindBarPresenter) {
    self.presenter = presenter
    super.init(frame: .zero)
    wantsLayer = true
    isHidden = true
    layer?.masksToBounds = false
    for _ in 0..<2 {
      let drop = CALayer()
      drop.masksToBounds = false
      dropLayers.append(drop)
      layer?.addSublayer(drop)
    }
    surfaceLayer.cornerRadius = FindBarLayout.cornerRadius
    surfaceLayer.cornerCurve = .continuous
    surfaceLayer.borderWidth = 0.5
    layer?.addSublayer(surfaceLayer)
    layer?.addSublayer(separator)

    glyphView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    glyphView.imageScaling = .scaleProportionallyDown
    glyphView.setAccessibilityElement(false)
    glyphView.cell?.setAccessibilityElement(false)                 // decoration: the field says it
    addSubview(glyphView)

    field.delegate = self
    field.setAccessibilityLabel("Find in page")
    field.cell?.setAccessibilityLabel("Find in page")
    field.setAccessibilitySubrole(.searchField)
    field.cell?.setAccessibilitySubrole(.searchField)
    field.setAccessibilityIdentifierWithCell(AXID.Find.field)
    addSubview(field)

    countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    countLabel.alignment = .right
    countLabel.isSelectable = false
    countLabel.lineBreakMode = .byClipping
    countLabel.setAccessibilityElement(true)
    countLabel.setAccessibilityRole(.staticText)
    countLabel.setAccessibilityIdentifierWithCell(AXID.Find.count)
    addSubview(countLabel)

    previousButton.target = self
    previousButton.action = #selector(previousPressed(_:))
    nextButton.target = self
    nextButton.action = #selector(nextPressed(_:))
    closeButton.target = self
    closeButton.action = #selector(closePressed(_:))
    for button in [previousButton, nextButton, closeButton] { addSubview(button) }
    field.nextKeyView = previousButton
    previousButton.nextKeyView = nextButton
    nextButton.nextKeyView = closeButton
    closeButton.nextKeyView = field

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityRoleDescription("search")
    setAccessibilityLabel("Find in page")
    setAccessibilityIdentifier(AXID.Find.root)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  // MARK: Showing

  /// Draws the presenter's display: the bar for the shown tab, or hidden.
  func refresh() {
    guard let display = presenter?.display else {
      hide()
      return
    }
    let wasHidden = isHidden
    isHidden = false
    if field.stringValue != display.text { field.stringValue = display.text }
    countLabel.stringValue = display.countText
    countLabel.setAccessibilityValue(display.countText)
    let noMatches = display.hasNoMatches
    previousButton.isEnabled = !noMatches
    nextButton.isEnabled = !noMatches
    applyColors()
    (superview as? ContentCardView)?.layoutFindBar()
    needsLayout = true
    layoutSubtreeIfNeeded()
    if wasHidden, presenter?.isOpening == true { animateEntrance() }
  }

  /// Hiding is instant. A field that had the keyboard gives it up to the window.
  private func hide() {
    guard !isHidden else { return }
    if let window, let editor = field.currentEditor(), window.firstResponder === editor {
      window.makeFirstResponder(nil)
    }
    isHidden = true
  }

  /// Cmd-F: the field takes the keyboard and selects its text.
  func focusField() {
    guard let window, !isHidden else { return }
    if window.makeFirstResponder(field) { field.currentEditor()?.selectAll(nil) }
  }

  /// The count after a final reply, polite: it does not interrupt what VoiceOver is saying.
  func announce(_ text: String) {
    if let postAnnouncement {
      postAnnouncement(text)
      return
    }
    NSAccessibility.post(element: countLabel, notification: .announcementRequested, userInfo: [
      .announcement: text,
      .priority: NSAccessibilityPriorityLevel.medium.rawValue,
    ])
  }

  /// Lays the bar out again at once; for tests that set a field text directly.
  func refreshLayout() {
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  // MARK: Motion

  private func animateEntrance() {
    guard window != nil, let layer else { return }
    let entrance = FindBarMotion.entrance(reduceMotion: reduceMotion())
    layer.add(FindBarMotion.fadeAnimation(entrance), forKey: Self.fadeKey)
    if let rise = FindBarMotion.riseAnimation(entrance) { layer.add(rise, forKey: Self.riseKey) }
  }

  /// The field nudges once when a search ends with no match; Reduce Motion lets the text say it.
  func nudgeField() {
    guard window != nil, let nudge = FindBarMotion.nudge(reduceMotion: reduceMotion()) else { return }
    field.layer?.add(FindBarMotion.nudgeAnimation(nudge), forKey: Self.nudgeKey)
  }

  // MARK: Layout

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let textWidth = ceil(countLabel.attributedStringValue.size().width)
    let parts = FindBarLayout.parts(width: bounds.width, countWidth: FindBarLayout.countWidth(textWidth: textWidth))
    glyphView.frame = parts.glyph
    field.frame = parts.field
    countLabel.frame = parts.count.insetBy(dx: -2, dy: 0)          // a label cell insets its text by 2 on each side
    previousButton.frame = parts.previous
    nextButton.frame = parts.next
    closeButton.frame = parts.close
    separator.frame = parts.separator
    let shape = CGPath(roundedRect: bounds, cornerWidth: FindBarLayout.cornerRadius,
                       cornerHeight: FindBarLayout.cornerRadius, transform: nil)
    surfaceLayer.frame = bounds
    for drop in dropLayers {
      drop.frame = bounds
      drop.shadowPath = shape
    }
    CATransaction.commit()
  }

  // MARK: Colors

  private func applyColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    surfaceLayer.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    surfaceLayer.borderColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    for (drop, shadow) in zip(dropLayers, ShellTokens.overlayShadow.drops(flavor)) {
      drop.shadowColor = shadow.color
      drop.shadowOpacity = shadow.opacity
      drop.shadowRadius = shadow.radius
      drop.shadowOffset = CGSize(width: 0, height: -shadow.offsetY)         // y points up: the drop falls below
    }
    separator.backgroundColor = ShellTokens.sidebarDivider.resolve(flavor).cgColor
    field.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    field.placeholderAttributedString = NSAttributedString(string: "Find in page", attributes: [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: ShellTokens.secondaryText.resolve(flavor).nsColor().withAlphaComponent(0.8),
    ])
    let noMatches = presenter?.display?.hasNoMatches ?? false
    countLabel.textColor = (noMatches ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor).nsColor()
    glyphView.contentTintColor = ShellTokens.sidebarForeground.resolve(flavor).nsColor()
    for button in [previousButton, nextButton, closeButton] { button.refreshColors() }
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  // MARK: Keys

  /// Esc from a step button or anywhere else in the bar: the field handles its own in `control(_:textView:doCommandBy:)`.
  public override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
      presenter?.close()
      return
    }
    super.keyDown(with: event)
  }

  public func controlTextDidChange(_ notification: Notification) {
    presenter?.setText(field.stringValue)
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
         #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
      let flags = (textView as? FindBarEditor)?.lastModifiers ?? NSApp.currentEvent?.modifierFlags ?? []
      presenter?.step(forward: !flags.contains(.shift))
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      presenter?.close()
      return true
    default:
      return false
    }
  }

  @objc private func previousPressed(_ sender: Any?) { presenter?.step(forward: false) }
  @objc private func nextPressed(_ sender: Any?) { presenter?.step(forward: true) }
  @objc private func closePressed(_ sender: Any?) { presenter?.close() }
}
