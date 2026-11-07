import AppKit

/// The browser data import in the first run's Import step (#514): the same consent, progress and result as the sheet,
/// drawn in the Hero style (Avenir Next at the website's scale, 50 pt pills, no card) in place of the step's content,
/// over the particle field. "Not now" returns to the step; finishing returns to its Imported state.
@MainActor
final class ImportHeroView: NSView {
  let source: any BrowserDataImportSource
  private(set) var content: ImportContentView!
  private let scroll = NSScrollView()
  private(set) var appearanceModel: OnboardingAppearance
  private(set) var isCompact: Bool
  let primaryButton: PillButton
  let secondaryButton: PillButton
  var onAnnouncement: (@MainActor (String) -> Void)?
  /// The flow moved to another phase (a confirmed Skip setup finishes the run when the result shows).
  var onPhaseChange: (@MainActor (BrowserDataImportPhase) -> Void)?
  private var lastPhase: BrowserDataImportPhase

  init(source: any BrowserDataImportSource, appearance: OnboardingAppearance, compact: Bool) {
    self.source = source
    appearanceModel = appearance
    isCompact = compact
    lastPhase = source.state.phase
    primaryButton = PillButton(style: .primary, title: "Import", appearance: appearance)
    secondaryButton = PillButton(style: .glass, title: "Not now", appearance: appearance)
    super.init(frame: .zero)
    let style = ImportViewStyle.hero(appearance, compact: compact)
    content = ImportContentView(source: source, style: style, primary: primaryButton, secondary: secondaryButton)
    for button in [primaryButton, secondaryButton] {
      button.onPress = { [weak self, weak button] in
        guard let self, let button else { return }
        content.buttonPressed(button)
      }
    }
    primaryButton.setAccessibilityIdentifierWithCell(AXID.BrowserDataImport.primary)
    secondaryButton.setAccessibilityIdentifierWithCell(AXID.BrowserDataImport.secondary)
    content.setAccessibilityIdentifier(AXID.BrowserDataImport.root)
    content.onAnnouncement = { [weak self] text in self?.onAnnouncement?(text) }
    content.onHeightChange = { [weak self] in self?.needsLayout = true }
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.borderType = .noBorder
    scroll.automaticallyAdjustsContentInsets = false
    scroll.documentView = content
    addSubview(scroll)
    addSubview(secondaryButton)
    addSubview(primaryButton)
    source.onChange = { [weak self] in self?.sourceChanged() }
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Controls in Tab order.
  var keyViews: [NSView] { content.keyViews }

  /// Escape is Cancel (Not now in consent), and Continue on the result.
  func handleEscape() {
    switch source.state.phase {
    case .result: source.finish()
    default: source.cancel()
    }
  }

  private func sourceChanged() {
    let state = source.state
    content.apply(state)
    needsLayout = true
    let changed = state.phase != lastPhase
    lastPhase = state.phase
    if changed, state.phase != .dismissed { focusFirstControl() }
    if changed { onPhaseChange?(state.phase) }
  }

  /// The first checkbox while asking, Cancel while importing, the primary on the result.
  func focusFirstControl() {
    guard let window else { return }
    let target: NSView? = switch source.state.phase {
    case .consent: content.keyViews.first
    case .result: content.primaryButton.isHidden ? content.secondaryButton : content.primaryButton
    default: content.secondaryButton.isHidden ? nil : content.secondaryButton
    }
    if let target { window.makeFirstResponder(target) }
  }

  func restyle(_ appearance: OnboardingAppearance) {
    appearanceModel = appearance
    primaryButton.appearanceModel = appearance
    secondaryButton.appearanceModel = appearance
    content.restyle(.hero(appearance, compact: isCompact))
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let compact = bounds.height < 700
    if compact != isCompact {
      isCompact = compact
      content.restyle(.hero(appearanceModel, compact: compact))
    }
    let column = max(320, min(640, bounds.width - 64)).rounded()
    let top: CGFloat = compact ? 46 : 58
    let footer = 16 + PillButton.quietHeight + 12
    let buttons = [secondaryButton, primaryButton].filter { !$0.isHidden }
    let sizes = buttons.map(\.intrinsicContentSize)
    let buttonHeight = sizes.map(\.height).max() ?? 0
    let buttonBand = buttonHeight > 0 ? buttonHeight + 22 : 0
    let available = max(160, bounds.height - top - footer - buttonBand)
    let height = content.layoutContent(width: column)
    let shown = min(height, available)
    scroll.frame = NSRect(x: ((bounds.width - column) / 2).rounded(), y: top, width: column, height: shown)
    content.frame = NSRect(x: 0, y: 0, width: column, height: height)
    // The buttons sit under the content, centered, and never scroll away.
    let gap: CGFloat = 12
    let total = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, buttons.count - 1))
    var x = ((bounds.width - total) / 2).rounded()
    for (button, size) in zip(buttons, sizes) {
      button.frame = NSRect(x: x, y: top + shown + 22, width: size.width, height: size.height)
      x += size.width + gap
    }
  }

  /// The content, then the buttons that sit under it.
  var accessibilityElementsInOrder: [Any] {
    [content as Any] + [secondaryButton, primaryButton].filter { !$0.isHidden }
  }

  override func accessibilityChildren() -> [Any]? { accessibilityElementsInOrder }
}
