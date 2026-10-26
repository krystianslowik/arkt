import AppKit
import Motion

/// One step's content, centred over the stage (section 4): eyebrow, stage slot, title, lede, the step's controls and
/// the buttons. Frames are set directly from measured text; nothing changes frame while it animates.
@MainActor
final class OnboardingStepView: NSView {
  struct Button {
    var title: String
    var identifier: String
    var isEnabled = true
  }

  enum Extra {
    case none
    case counts
    case theme
    case option(isOn: Bool)
  }

  struct Content {
    var step: OnboardingStep
    var eyebrow: String?
    var title: String
    var titleRole: BrandType.Role
    var lede: String?
    var ledeRole: BrandType.Role = .lede
    var ledeEmphasis: [String] = []
    var ledeIdentifier = AXID.Onboarding.lede
    var extra: Extra = .none
    var secondary: Button?
    var primary: Button?
    /// The stage's accessibility label (Welcome, Done, tips 1 and 2); nil hides it.
    var stageLabel: String?
  }

  let content: Content
  private(set) var appearanceModel: OnboardingAppearance
  let compact: Bool

  let eyebrowLabel: BrandLabel
  let title: WordRevealTitle
  let ledeLabel: BrandLabel
  let stageElement = StageAccessibilityView()
  let secondaryButton: PillButton?
  let primaryButton: PillButton?
  // Import
  private(set) var countsView: CountsView?
  // Make it yours
  private(set) var preview: SpacePreviewView?
  private(set) var nameField: SpaceNameField?
  private(set) var swatches: SwatchRowView?
  private(set) var segment: AppearanceSegmentView?
  private(set) var themeName: BrandLabel?
  // Extensions
  private(set) var option: OptionPillView?

  /// The stage slot in this view's coordinates, as laid out.
  private(set) var stageRect: CGRect = .zero

  init(content: Content, appearance: OnboardingAppearance, compact: Bool) {
    self.content = content
    self.appearanceModel = appearance
    self.compact = compact
    eyebrowLabel = BrandLabel(text: content.eyebrow ?? "", role: .eyebrow, color: appearance.accentText)
    title = WordRevealTitle(text: content.title, role: content.titleRole, color: appearance.textPrimary)
    let welcome = content.step == .welcome
    ledeLabel = BrandLabel(text: content.lede ?? "", role: content.ledeRole,
                           color: welcome ? appearance.textPrimary : appearance.textSecondary)
    secondaryButton = content.secondary.map { PillButton(style: .glass, title: $0.title, appearance: appearance) }
    primaryButton = content.primary.map { PillButton(style: .primary, title: $0.title, appearance: appearance) }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Onboarding.step(content.step.identifier))
    let halo = appearance.halo
    eyebrowLabel.setAccessibilityIdentifier(AXID.Onboarding.eyebrow)
    title.halo = halo
    title.compact = compact
    ledeLabel.halo = halo
    ledeLabel.emphasis = content.ledeEmphasis
    ledeLabel.emphasisColor = appearance.textPrimary
    ledeLabel.setAccessibilityIdentifier(content.ledeIdentifier)
    stageElement.setAccessibilityLabel(content.stageLabel)
    stageElement.setAccessibilityIdentifier(AXID.Onboarding.stage)
    if let button = content.secondary, let view = secondaryButton {
      view.setAccessibilityIdentifierWithCell(button.identifier)
      view.isEnabled = button.isEnabled
    }
    if let button = content.primary, let view = primaryButton {
      view.setAccessibilityIdentifierWithCell(button.identifier)
      view.isEnabled = button.isEnabled
      view.keyEquivalent = "\r"
    }
    addSubview(stageElement)
    if content.eyebrow != nil { addSubview(eyebrowLabel) }
    switch content.extra {
    case .none: break
    case .counts:
      let counts = CountsView(appearance: appearance, compact: compact)
      countsView = counts
      addSubview(counts)
    case .theme:
      let preview = SpacePreviewView(frame: .zero)
      let name = SpaceNameField(appearance: appearance)
      name.compact = compact
      let swatches = SwatchRowView(appearance: appearance)
      let segment = AppearanceSegmentView(appearance: appearance)
      let themeName = BrandLabel(role: .themeName, color: appearance.textSecondary)
      themeName.halo = halo
      self.preview = preview
      self.nameField = name
      self.swatches = swatches
      self.segment = segment
      self.themeName = themeName
      for view in [preview, name, swatches, segment, themeName] as [NSView] { addSubview(view) }
    case .option(let isOn):
      let option = OptionPillView(title: OnboardingCopy.webStoreOption, appearance: appearance)
      option.setOn(isOn)
      self.option = option
      addSubview(option)
    }
    addSubview(title)
    if content.lede != nil { addSubview(ledeLabel) }
    for button in [secondaryButton, primaryButton].compactMap({ $0 }) { addSubview(button) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  /// Elements in reading order (section 11): eyebrow, stage (when labelled), title, lede, controls, secondary,
  /// primary.
  var readingOrder: [NSView] {
    var order: [NSView] = []
    if content.eyebrow != nil { order.append(eyebrowLabel) }
    if content.stageLabel != nil { order.append(stageElement) }
    if let countsView { order += countsView.accessibilityOrder }
    if let nameField { order.append(nameField.field) }
    if !title.isHidden { order.append(title) }
    if content.lede != nil { order.append(ledeLabel) }
    if let swatches { order.append(swatches) }
    if let segment { order.append(segment) }
    if let themeName { order.append(themeName) }
    if let option { order.append(option) }
    order += [secondaryButton, primaryButton].compactMap { $0 }
    return order
  }

  /// Controls in Tab order.
  var keyViews: [NSView] {
    var views: [NSView] = []
    if let nameField { views.append(nameField.field) }
    if let swatches { views.append(swatches) }
    if let segment { views.append(segment) }
    if let option { views.append(option) }
    return views + [secondaryButton, primaryButton].compactMap { $0 }.filter(\.isEnabled)
  }

  override func accessibilityChildren() -> [Any]? { readingOrder }

  // MARK: - Layout (section 4)

  private var isWelcome: Bool { content.step == .welcome }
  private var isDone: Bool { content.step == .done }
  private var topPadding: CGFloat { compact ? (isWelcome ? 70 : 46) : (isWelcome ? 84 : 58) }
  private var columnWidth: CGFloat { min(bounds.width - 64, 900) }

  /// The stage slot's size for this step.
  var stageSize: CGSize {
    if isWelcome { return CGSize(width: 220, height: compact ? 176 : 200) }
    return CGSize(width: 560, height: compact ? 196 : 236)
  }

  /// Width of 40 characters of the lede (section 3: at most 40 characters a line).
  private var ledeWidth: CGFloat {
    let style = content.ledeRole.style(compact: compact)
    let zero = NSAttributedString(string: "0", attributes: [.font: BrandType.font(for: style)]).size().width
    return ceil(zero * 40 + 24)
  }

  override func layout() {
    super.layout()
    let midX = bounds.midX
    func place(_ view: NSView, y: CGFloat, size: NSSize) -> CGFloat {
      view.frame = NSRect(x: (midX - size.width / 2).rounded(), y: y.rounded(), width: ceil(size.width),
                          height: ceil(size.height))
      return y + size.height
    }
    var y = topPadding
    if content.eyebrow != nil {
      y = place(eyebrowLabel, y: y, size: eyebrowLabel.textSize)
      y += 14
    }
    title.maxWidth = columnWidth
    ledeLabel.maxWidth = ledeWidth
    ledeLabel.compact = compact
    switch content.extra {
    case .counts:
      guard let countsView else { break }
      y += 2
      stageRect = CGRect(x: midX - stageSize.width / 2, y: y, width: stageSize.width, height: countsView.blockHeight)
      y = place(countsView, y: y, size: NSSize(width: 640, height: countsView.blockHeight))
      y += compact ? 22 : 30
      y = place(title, y: y, size: title.textSize)
      y += 12
      y = place(ledeLabel, y: y, size: ledeLabel.textSize)
      y += 24
    case .theme:
      stageRect = CGRect(x: midX - stageSize.width / 2, y: y, width: stageSize.width, height: stageSize.height)
      let previewSize = compact ? CGSize(width: 300, height: 168) : CGSize(width: 340, height: 196)
      preview?.frame = NSRect(x: (midX - previewSize.width / 2).rounded(), y: (y + 20).rounded(),
                              width: previewSize.width, height: previewSize.height)
      y += stageSize.height
      if let nameField {
        y += compact ? 6 : 18
        y = place(nameField, y: y, size: NSSize(width: 640, height: nameField.lineHeight + 14))
      }
      y += 12
      y = place(ledeLabel, y: y, size: ledeLabel.textSize)
      y += 20
      if let swatches, let segment {
        let swatchSize = swatches.intrinsicContentSize, segmentSize = segment.intrinsicContentSize
        let rowWidth = swatchSize.width + 28 + segmentSize.width
        let left = (midX - rowWidth / 2).rounded()
        let rowHeight = max(swatchSize.height, segmentSize.height)
        swatches.frame = NSRect(x: left, y: y + (rowHeight - swatchSize.height) / 2, width: swatchSize.width,
                                height: swatchSize.height)
        segment.frame = NSRect(x: left + swatchSize.width + 28, y: y + (rowHeight - segmentSize.height) / 2,
                               width: segmentSize.width, height: segmentSize.height)
        y += rowHeight + 10
      }
      if let themeName { y = place(themeName, y: y, size: NSSize(width: 200, height: themeName.textSize.height)) }
      y += compact ? 22 : 30
    default:
      stageRect = CGRect(x: midX - stageSize.width / 2, y: y, width: stageSize.width, height: stageSize.height)
      y += stageSize.height
      y += isWelcome ? (compact ? 36 : 44) : 16
      y = place(title, y: y, size: title.textSize)
      if content.lede != nil {
        y += isWelcome ? 22 : 16
        y = place(ledeLabel, y: y, size: ledeLabel.textSize)
      }
      if let option {
        y += 22
        y = place(option, y: y, size: option.intrinsicContentSize)
      }
      y += isWelcome ? 34 : (compact ? 24 : 30)
    }
    stageElement.frame = stageRect
    let buttons = [secondaryButton, primaryButton].compactMap { $0 }
    let sizes = buttons.map(\.intrinsicContentSize)
    let width = sizes.map(\.width).reduce(0, +) + CGFloat(max(buttons.count - 1, 0)) * 10
    var x = (midX - width / 2).rounded()
    for (button, size) in zip(buttons, sizes) {
      button.frame = NSRect(x: x, y: y.rounded(), width: size.width, height: size.height)
      x += size.width + 10
    }
  }

  // MARK: - Motion

  /// Incoming (M1, M2): eyebrow, then the title word by word, then lede, controls and buttons (+300, +360, +420 ms).
  func reveal(reduceMotion: Bool, firstReveal: Bool) {
    layoutSubtreeIfNeeded()
    let base: CFTimeInterval = firstReveal ? 0.12 : 0.06
    let rise: CGFloat = 10
    if let layer = eyebrowLabel.layer {
      OnboardingMotion.reveal(layer, rise: rise, delay: 0, reduceMotion: reduceMotion)
    }
    title.reveal(delay: base, reduceMotion: reduceMotion)
    if let layer = ledeLabel.layer { OnboardingMotion.reveal(layer, rise: rise, delay: 0.3, reduceMotion: reduceMotion) }
    let controls: [NSView?] = [countsView, preview, nameField, swatches, segment, themeName, option]
    for view in controls.compactMap({ $0 }) {
      if let layer = view.layer { OnboardingMotion.reveal(layer, rise: rise, delay: 0.36, reduceMotion: reduceMotion) }
    }
    for button in [secondaryButton, primaryButton].compactMap({ $0 }) {
      if let layer = button.layer { OnboardingMotion.reveal(layer, rise: rise, delay: 0.42, reduceMotion: reduceMotion) }
    }
  }

  /// Outgoing (M2): opacity to 0 in 200 ms, from where it is.
  func conceal(duration: CFTimeInterval = 0.2) {
    if let layer { OnboardingMotion.conceal(layer, duration: duration) }
  }

  /// Everything at rest (resume, screenshots).
  func showAtRest() {
    layoutSubtreeIfNeeded()
    title.showAtRest()
  }
}

/// The stage's stand-in for VoiceOver: an image labelled "Arkt" (Welcome, Done) or with the keys of tips 1 and 2;
/// absent from the tree elsewhere.
@MainActor
final class StageAccessibilityView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func isAccessibilityElement() -> Bool { accessibilityLabel() != nil }
  override func accessibilityRole() -> NSAccessibility.Role? { .image }
}

// MARK: - Counts

/// The Import step's numbers as text (section 6.2): pinned tabs large, then Spaces, Favorites and folders in a row,
/// each with its uppercase label. Drawn in Avenir Next DemiBold when the stage has no particles, else clear (the
/// particles draw them) and kept for VoiceOver. Each finished category's label gets a tick (M4).
@MainActor
final class CountsView: NSView {
  private let appearanceModel: OnboardingAppearance
  private let compact: Bool
  private var numbers: [OnboardingCounts.Kind: BrandLabel] = [:]
  private var labels: [OnboardingCounts.Kind: BrandLabel] = [:]
  private var ticks: [OnboardingCounts.Kind: CALayer] = [:]
  private var elements: [OnboardingCounts.Kind: CountElement] = [:]
  private var landed: Set<OnboardingCounts.Kind> = []
  /// Draw the digits (no particle layer).
  var drawsDigits = true { didSet { refreshColors() } }
  private var values = OnboardingCounts()
  private var state: OnboardingCopy.CountState = .counting
  private var failed = false

  static let rowGap: CGFloat = 64

  init(appearance: OnboardingAppearance, compact: Bool) {
    self.appearanceModel = appearance
    self.compact = compact
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    for kind in OnboardingCounts.Kind.allCases {
      let large = kind == .pinnedTabs
      let number = BrandLabel(text: "0", role: large ? .countLarge : .countRow, color: appearance.textPrimary)
      number.compact = compact
      number.setAccessibilityElement(false)
      let label = BrandLabel(text: OnboardingCopy.countLabel(kind, 2), role: large ? .countLabelLarge : .countLabel,
                             color: appearance.textSecondary)
      label.setAccessibilityElement(false)
      let tick = Self.tickLayer(appearance: appearance)
      tick.opacity = 0
      let element = CountElement()
      element.setAccessibilityIdentifier(Self.identifier(kind))
      numbers[kind] = number
      labels[kind] = label
      ticks[kind] = tick
      elements[kind] = element
      for view in [number, label, element] { addSubview(view) }
      label.layer?.addSublayer(tick)
    }
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  static func identifier(_ kind: OnboardingCounts.Kind) -> String {
    switch kind {
    case .pinnedTabs: AXID.Onboarding.countPinnedTabs
    case .spaces: AXID.Onboarding.countSpaces
    case .favorites: AXID.Onboarding.countFavorites
    case .folders: AXID.Onboarding.countFolders
    }
  }

  var accessibilityOrder: [NSView] { OnboardingCounts.Kind.allCases.compactMap { elements[$0] } }

  private static func tickLayer(appearance: OnboardingAppearance) -> CALayer {
    let tick = CALayer()
    tick.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
    tick.cornerRadius = 6
    tick.backgroundColor = appearance.accent.cgColor
    let mark = CAShapeLayer()
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 3.4, y: 6.2))
    path.addLine(to: CGPoint(x: 5.2, y: 8))
    path.addLine(to: CGPoint(x: 8.8, y: 4))
    mark.path = path
    mark.strokeColor = BrandTokens.Palette.graphite.cgColor
    mark.fillColor = nil
    mark.lineWidth = 1.6
    mark.lineCap = .round
    mark.lineJoin = .round
    mark.frame = tick.bounds
    tick.addSublayer(mark)
    return tick
  }

  private var largeStyle: BrandType.Style { BrandType.Role.countLarge.style(compact: compact) }
  private var rowStyle: BrandType.Style { BrandType.Role.countRow.style(compact: compact) }

  /// Height of the whole block: the large number, its label, the row of numbers and their labels.
  var blockHeight: CGFloat {
    (largeStyle.lineHeight ?? 0) + 12 + 18 + 12 + (rowStyle.lineHeight ?? 0) + 10 + 15
  }

  /// The numbers' glyph boxes in this view's coordinates, for the particle stage.
  func numberFrames() -> [(kind: OnboardingCounts.Kind, text: String, frame: CGRect, size: CGFloat)] {
    layoutSubtreeIfNeeded()
    return OnboardingCounts.Kind.allCases.compactMap { kind in
      guard let number = numbers[kind] else { return nil }
      let size = kind == .pinnedTabs ? largeStyle.size : rowStyle.size
      return (kind, number.text, number.frame, size)
    }
  }

  func update(_ counts: OnboardingCounts, state: OnboardingCopy.CountState, failed: Bool) {
    values = counts
    self.state = state
    self.failed = failed
    for kind in OnboardingCounts.Kind.allCases {
      numbers[kind]?.text = String(counts[kind])
      labels[kind]?.text = OnboardingCopy.countLabel(kind, counts[kind])
      let element = elements[kind]
      element?.setAccessibilityLabel(OnboardingCopy.countAccessibility(kind, value: counts[kind], state: state))
      element?.isHiddenForFailure = failed
    }
    isHidden = failed
    needsLayout = true
  }

  /// M4: a finished category's label gets a tick that pops in from 0.8 on `springyFast`.
  func land(_ kinds: Set<OnboardingCounts.Kind>, reduceMotion: Bool) {
    for kind in kinds.subtracting(landed) {
      guard let tick = ticks[kind] else { continue }
      OnboardingMotion.set { tick.opacity = 1 }
      if !reduceMotion {
        let pop = SpringAnimationFactoryBridge.scale(from: 0.8, to: 1)
        tick.add(pop, forKey: "pop")
      }
    }
    landed.formUnion(kinds)
    needsLayout = true
  }

  /// Every label ticked at rest (resume after an import).
  func landAll() {
    landed = Set(OnboardingCounts.Kind.allCases)
    OnboardingMotion.set { ticks.values.forEach { $0.opacity = 1 } }
    needsLayout = true
  }

  private func refreshColors() {
    let color = drawsDigits ? appearanceModel.textPrimary : .clear
    numbers.values.forEach { $0.color = color }
  }

  override func layout() {
    super.layout()
    let midX = bounds.midX
    var y: CGFloat = 0
    func center(_ view: BrandLabel, x: CGFloat, y: CGFloat, height: CGFloat? = nil) {
      let size = view.textSize
      view.frame = NSRect(x: (x - size.width / 2).rounded(), y: y.rounded(), width: ceil(size.width),
                          height: ceil(height ?? size.height))
    }
    guard let pinned = numbers[.pinnedTabs], let pinnedLabel = labels[.pinnedTabs] else { return }
    let largeLine = largeStyle.lineHeight ?? largeStyle.size
    center(pinned, x: midX, y: y, height: largeLine)
    y += largeLine + 12
    center(pinnedLabel, x: midX, y: y)
    elements[.pinnedTabs]?.frame = pinned.frame.union(pinnedLabel.frame)
    y += 18 + 12
    let row: [OnboardingCounts.Kind] = [.spaces, .favorites, .folders]
    let rowLine = rowStyle.lineHeight ?? rowStyle.size
    let widths = row.map { kind in max(numbers[kind]?.textSize.width ?? 0, labelWidth(kind)) }
    let total = widths.reduce(0, +) + Self.rowGap * CGFloat(row.count - 1)
    var x = midX - total / 2
    for (kind, width) in zip(row, widths) {
      guard let number = numbers[kind], let label = labels[kind] else { continue }
      center(number, x: x + width / 2, y: y, height: rowLine)
      center(label, x: x + width / 2, y: y + rowLine + 10)
      elements[kind]?.frame = number.frame.union(label.frame)
      x += width + Self.rowGap
    }
    // Ticks sit left of their label, 6 pt apart.
    for (kind, tick) in ticks {
      guard let label = labels[kind] else { continue }
      OnboardingMotion.set { tick.position = CGPoint(x: -12, y: label.bounds.height / 2) }
    }
  }

  private func labelWidth(_ kind: OnboardingCounts.Kind) -> CGFloat { (labels[kind]?.textSize.width ?? 0) + 18 }
}

/// One count for VoiceOver: "37 pinned tabs", "Pinned tabs, counting", "37 pinned tabs, imported".
@MainActor
final class CountElement: NSView {
  var isHiddenForFailure = false
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func isAccessibilityElement() -> Bool { !isHiddenForFailure }
  override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
}

/// `SpringAnimationFactory` for a layer's scale.
@MainActor
enum SpringAnimationFactoryBridge {
  static func scale(from: Double, to: Double) -> CASpringAnimation {
    SpringAnimationFactory.make(keyPath: "transform.scale", from: from, to: to,
                                parameters: SpringPreset.springyFast.parameters)
  }
}
