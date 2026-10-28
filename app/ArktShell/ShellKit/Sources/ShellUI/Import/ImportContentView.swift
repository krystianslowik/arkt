import AppKit

// The browser data import's content (#514, direction B "Tiers"): one view for the everyday sheet and the first run's
// Hero entry. It draws a `BrowserDataImportState` and calls the source; it knows nothing of the coordinator.

/// The Keychain line and the denied message: a symbol and a wrapped sentence with a heavier lead.
@MainActor
final class ImportNoticeView: NSView {
  let icon = NSImageView()
  let text: ImportText
  private(set) var notice: BrowserDataImportNotice
  private var style: ImportViewStyle

  init(notice: BrowserDataImportNotice, style: ImportViewStyle) {
    self.notice = notice
    self.style = style
    text = ImportText(role: .note, style: style, accessible: true)
    super.init(frame: .zero)
    addSubview(icon)
    addSubview(text)
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.setAccessibilityElement(false)
    apply(notice, style: style)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func apply(_ notice: BrowserDataImportNotice, style: ImportViewStyle) {
    self.notice = notice
    self.style = style
    text.apply(style: style)
    text.text = notice.text
    text.emphasis = notice.emphasis
    text.tone = .secondary
    let name = notice.symbol == .lock ? "lock" : "exclamationmark.circle"
    let size = style.isHero ? 17.0 : 13.0
    icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    icon.contentTintColor = style.isHero && notice.symbol == .lock ? style.palette.accent : style.palette.secondary
    needsLayout = true
  }

  private var iconSize: CGFloat { style.isHero ? 20 : 16 }

  func fittingHeight(width: CGFloat) -> CGFloat {
    max(iconSize, text.fitting(width: max(1, width - iconSize - 10)).height)
  }

  override func layout() {
    super.layout()
    text.place(x: iconSize + 10, y: 0, width: max(1, bounds.width - iconSize - 10))
    icon.frame = NSRect(x: 0, y: style.isHero ? 1 : 0, width: iconSize, height: iconSize)
  }
}

/// A heading and its rows: in the sheet a recessed field with 0.5 pt hairlines, in the Hero entry bare rows with 1 pt
/// rules. The notice sits under the last row, inside the field.
@MainActor
final class ImportGroupView: NSView {
  let heading: ImportText
  private(set) var rows: [ImportRowView] = []
  private(set) var noticeView: ImportNoticeView?
  private(set) var group: BrowserDataImportGroup?
  private let field = CALayer()
  private let noticeRule = CALayer()
  private var style: ImportViewStyle

  init(style: ImportViewStyle) {
    self.style = style
    heading = ImportText(role: .heading, style: style, accessible: true)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(field)
    layer?.addSublayer(noticeRule)
    addSubview(heading)
    heading.tone = .secondary
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  /// The heading, the rows (a checkbox, or the row as one status) and the notice, in reading order.
  override func accessibilityChildren() -> [Any]? {
    var children: [Any] = [heading]
    for row in rows { children.append(row.checkbox.isHidden ? row : row.checkbox) }
    if let noticeView { children.append(noticeView.text) }
    return children
  }

  func configure(_ group: BrowserDataImportGroup, rows rowViews: [ImportRowView], style: ImportViewStyle) {
    self.style = style
    self.group = group
    heading.apply(style: style)
    heading.text = group.heading
    heading.tone = .secondary
    setAccessibilityLabel(group.heading)
    for row in rows where !rowViews.contains(where: { $0 === row }) { row.removeFromSuperview() }
    rows = rowViews
    for (index, row) in rowViews.enumerated() {
      row.showsHairline = index < rowViews.count - 1
      if row.superview !== self { addSubview(row) }
    }
    if let notice = group.notice {
      if let noticeView { noticeView.apply(notice, style: style) } else {
        let view = ImportNoticeView(notice: notice, style: style)
        addSubview(view)
        noticeView = view
      }
    } else {
      noticeView?.removeFromSuperview()
      noticeView = nil
    }
    needsLayout = true
  }

  private var fieldInset: CGFloat { style.isHero ? 0 : 12 }
  private var headingInset: CGFloat { style.isHero ? 8 : 4 }
  private var noticeInset: CGFloat { style.isHero ? 8 : 12 }

  func fittingHeight(width: CGFloat) -> CGFloat {
    var y = heading.fitting(width: max(1, width - 2 * headingInset)).height + style.headingGap
    if !style.isHero { y += 2 }
    y += rows.reduce(CGFloat(0)) { $0 + $1.preferredHeight }
    if let noticeView {
      y += (style.isHero ? 16 : 12) + noticeView.fittingHeight(width: max(1, width - 2 * noticeInset))
      y += style.isHero ? 0 : 12
    }
    return y + (style.isHero ? 0 : 2)
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 0
    heading.place(x: headingInset, y: y, width: max(1, bounds.width - 2 * headingInset))
    y += heading.frame.height + style.headingGap
    let fieldTop = y
    if !style.isHero { y += 2 }
    for row in rows {
      row.frame = NSRect(x: 0, y: y, width: bounds.width, height: row.preferredHeight)
      y += row.preferredHeight
    }
    var ruleY: CGFloat?
    if let noticeView {
      ruleY = y
      y += style.isHero ? 16 : 12
      let width = max(1, bounds.width - 2 * noticeInset)
      let height = noticeView.fittingHeight(width: width)
      noticeView.frame = NSRect(x: noticeInset, y: y, width: width, height: height)
      y += height + (style.isHero ? 0 : 12)
    }
    if !style.isHero { y += 2 }
    ArchiveMotion.set {
      field.backgroundColor = style.palette.field.cgColor
      field.cornerRadius = 10
      field.cornerCurve = .continuous
      field.frame = CGRect(x: 0, y: fieldTop, width: bounds.width, height: max(0, y - fieldTop))
      field.isHidden = style.isHero
      noticeRule.backgroundColor = style.palette.hairline.cgColor
      noticeRule.isHidden = ruleY == nil || style.isHero
      if let ruleY {
        noticeRule.frame = CGRect(x: fieldInset, y: ruleY, width: max(0, bounds.width - 2 * fieldInset),
                                  height: style.hairlineWidth)
      }
    }
  }
}

/// Title, subtitle, the overall progress, the groups, the footnote and the buttons, top down.
@MainActor
final class ImportContentView: NSView {
  private(set) var style: ImportViewStyle
  private let source: any BrowserDataImportSource
  private(set) var state: BrowserDataImportState
  let eyebrow: ImportText
  let title: ImportText
  let subtitle: ImportText
  let overallLead: ImportText
  let overallTrail: ImportText
  let overallBar: ImportBarView
  let footnote: ImportText
  let primaryButton: NSButton
  let secondaryButton: NSButton
  private(set) var groupViews: [ImportGroupView] = []
  private(set) var rowViews: [BrowserDataKind: ImportRowView] = [:]
  private var showsOverall = false
  /// Called with what VoiceOver should announce (a phase, a type finishing, the Keychain wait; never per count).
  var onAnnouncement: (@MainActor (String) -> Void)?
  /// The phase or the number of groups changed, so the height did: the host resizes (the sheet) or scrolls (the Hero).
  var onHeightChange: (@MainActor () -> Void)?

  init(source: any BrowserDataImportSource, style: ImportViewStyle, primary: NSButton, secondary: NSButton) {
    self.source = source
    self.style = style
    state = source.state
    eyebrow = ImportText(role: .eyebrow, style: style, alignment: .center, accessible: true)
    title = ImportText(role: .title, style: style, alignment: style.isHero ? .center : .left, accessible: true)
    subtitle = ImportText(role: .subtitle, style: style, alignment: style.isHero ? .center : .left, accessible: true)
    overallLead = ImportText(role: .progressLead, style: style)
    overallTrail = ImportText(role: .progressTrail, style: style, alignment: .right)
    overallBar = ImportBarView(style: style)
    footnote = ImportText(role: .note, style: style, alignment: style.isHero ? .center : .left, accessible: true)
    primaryButton = primary
    secondaryButton = secondary
    super.init(frame: .zero)
    wantsLayer = true
    for kind in BrowserDataKind.allCases {
      let row = ImportRowView(kind: kind, style: style)
      row.onToggle = { [weak self] kind, isOn in self?.source.setSelected(kind, isOn) }
      rowViews[kind] = row
    }
    for view in [eyebrow, title, subtitle, overallLead, overallTrail, overallBar, footnote, secondaryButton, primaryButton]
      as [NSView] { addSubview(view) }
    eyebrow.tone = .accent
    footnote.tone = .secondary
    overallTrail.tone = .secondary
    subtitle.tone = .secondary
    eyebrow.isHidden = !style.isHero
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    apply(state)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  // MARK: State

  /// Draws `state`. Rows keep their views, so a focused checkbox stays focused while the state changes under it.
  func apply(_ new: BrowserDataImportState) {
    let old = state
    let animated = old.phase == new.phase && window != nil
    state = new
    eyebrow.text = style.isHero ? new.heroEyebrow : ""
    title.text = style.isHero ? new.heroTitle : new.title
    subtitle.text = style.isHero ? new.heroLede : new.subtitle
    setAccessibilityLabel(new.title)
    showsOverall = new.phase == .progress
    let overall = new.overall
    overallLead.text = showsOverall ? overall.label : ""
    overallTrail.text = showsOverall ? overall.trailing : ""
    overallBar.isHidden = !showsOverall
    overallBar.set(fraction: overall.fraction, animated: animated, sweeping: showsOverall && !new.isStopping)
    footnote.text = new.footnote ?? ""

    let groups = new.groups
    while groupViews.count > groups.count { groupViews.removeLast().removeFromSuperview() }
    while groupViews.count < groups.count {
      let view = ImportGroupView(style: style)
      addSubview(view)
      groupViews.append(view)
    }
    var used = Set<BrowserDataKind>()
    for (view, group) in zip(groupViews, groups) {
      let views = group.rows.compactMap { row -> ImportRowView? in
        guard let rowView = rowViews[row.kind] else { return nil }
        rowView.apply(row, animated: animated)
        used.insert(row.kind)
        return rowView
      }
      view.configure(group, rows: views, style: style)
    }
    for (kind, rowView) in rowViews where !used.contains(kind) { rowView.removeFromSuperview() }

    configure(primaryButton, with: style.isHero ? new.heroPrimaryButton() : new.primaryButton)
    configure(secondaryButton, with: new.secondaryButton(hero: style.isHero))
    // Return presses the primary while it is there and enabled. Set after the button's state, because a disabled
    // default button gives its key up.
    primaryButton.keyEquivalent = !primaryButton.isHidden && primaryButton.isEnabled ? "\r" : ""
    secondaryButton.keyEquivalent = ""
    needsLayout = true
    wireKeyLoop()
    if let spoken = new.announcement(after: old) { onAnnouncement?(spoken) }
    if old.phase != new.phase || old.groups.count != groups.count { onHeightChange?() }
  }

  private func configure(_ button: NSButton, with spec: BrowserDataImportButton?) {
    guard let spec else {
      button.isHidden = true
      button.isEnabled = false
      button.setAccessibilityElement(false)
      button.cell?.setAccessibilityElement(false)
      return
    }
    button.isHidden = false
    if button.title != spec.title { button.title = spec.title }
    if button.isEnabled != spec.isEnabled { button.isEnabled = spec.isEnabled }
    button.setAccessibilityElement(true)
    button.cell?.setAccessibilityElement(true)
    button.tag = Self.tag(spec.action)
  }

  static func tag(_ action: BrowserDataImportButton.Action) -> Int {
    switch action {
    case .importData: 1
    case .cancel: 2
    case .done: 3
    case .retry: 4
    }
  }

  /// A button's action: Import, Cancel, Done or Retry.
  @objc func buttonPressed(_ sender: NSButton) {
    switch sender.tag {
    case 1: source.beginImport()
    case 2: source.cancel()
    case 3: source.finish()
    case 4: source.retry()
    default: break
    }
  }

  /// The system's appearance or accessibility settings changed.
  func restyle(_ new: ImportViewStyle) {
    style = new
    for text in [eyebrow, title, subtitle, overallLead, overallTrail, footnote] { text.apply(style: new) }
    overallBar.apply(style: new)
    for row in rowViews.values { row.apply(style: new) }
    for view in groupViews {
      if let group = view.group { view.configure(group, rows: view.rows, style: new) }
    }
    apply(state)
  }

  // MARK: Layout

  private var side: CGFloat { style.isHero ? 0 : 20 }
  private var topInset: CGFloat { style.isHero ? 0 : 20 }
  private var bottomInset: CGFloat { style.isHero ? 0 : 20 }

  /// Lays the content out for `width` and returns the height it takes.
  @discardableResult
  func layoutContent(width: CGFloat) -> CGFloat {
    let inner = max(1, width - 2 * side)
    var y = topInset
    if style.isHero {
      if !eyebrow.text.isEmpty {
        eyebrow.place(x: 0, y: y, width: width)
        y += eyebrow.frame.height + 14
      }
      title.place(x: 0, y: y, width: width)
      y += title.frame.height + 10
      subtitle.place(x: 0, y: y, width: width)
      y += subtitle.frame.height + (style.compact ? 18 : 28)
    } else {
      title.place(x: side, y: y, width: inner)
      y += title.frame.height
      subtitle.place(x: side, y: y + 2, width: inner)
      y += 2 + subtitle.frame.height + 18
    }
    if showsOverall {
      let trailWidth = overallTrail.fitting(width: inner * 0.4).width
      overallTrail.place(x: side + inner - trailWidth, y: y, width: max(1, trailWidth))
      overallLead.place(x: side, y: y, width: max(1, inner - trailWidth - 12))
      let lineHeight = max(overallLead.frame.height, overallTrail.frame.height)
      overallTrail.frame.origin.y = (y + (lineHeight - overallTrail.frame.height) / 2).rounded()
      y += lineHeight + 8
      overallBar.frame = NSRect(x: side, y: y, width: inner, height: style.overallBarHeight)
      y += style.overallBarHeight + 16
    } else {
      overallLead.frame = .zero
      overallTrail.frame = .zero
    }
    for group in groupViews {
      let height = group.fittingHeight(width: inner)
      group.frame = NSRect(x: side, y: y, width: inner, height: height)
      group.layoutSubtreeIfNeeded()
      y += height + style.groupGap
    }
    if !groupViews.isEmpty { y -= style.groupGap }
    y += style.isHero ? 22 : 20
    layoutFooter(width: width, y: &y)
    return y + bottomInset
  }

  private func layoutFooter(width: CGFloat, y: inout CGFloat) {
    let buttons = [secondaryButton, primaryButton].filter { !$0.isHidden }
    let sizes = buttons.map(\.intrinsicContentSize)
    let height = sizes.map(\.height).max() ?? 0
    let gap: CGFloat = style.isHero ? 12 : 8
    if style.isHero {
      footnote.place(x: 0, y: y, width: min(width, 520).rounded())
      footnote.frame.origin.x = ((width - footnote.frame.width) / 2).rounded()
      if footnote.frame.height > 0 { y += footnote.frame.height + 18 }
      let total = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, buttons.count - 1))
      var x = ((width - total) / 2).rounded()
      for (button, size) in zip(buttons, sizes) {
        button.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        x += size.width + gap
      }
    } else {
      var x = width - side
      for (button, size) in zip(buttons.reversed(), sizes.reversed()) {
        x -= size.width
        button.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        x -= gap
      }
      footnote.place(x: side, y: y, width: max(1, x - side))
      footnote.frame.origin.y = (y + (height - footnote.frame.height) / 2).rounded()
    }
    y += height
  }

  override func layout() {
    super.layout()
    _ = layoutContent(width: bounds.width)
  }

  // MARK: Keyboard and VoiceOver

  /// The controls in Tab order: the enabled checkboxes, then Cancel, then the primary.
  var keyViews: [NSView] {
    var views: [NSView] = []
    for group in groupViews {
      for row in group.rows where !row.checkbox.isHidden && row.checkbox.isEnabled { views.append(row.checkbox) }
    }
    for button in [secondaryButton, primaryButton] where !button.isHidden && button.isEnabled { views.append(button) }
    return views
  }

  func wireKeyLoop() {
    let views = keyViews
    guard let first = views.first else { return }
    for (view, next) in zip(views, views.dropFirst() + [first]) { view.nextKeyView = next }
  }

  override func accessibilityChildren() -> [Any]? {
    var children: [Any] = []
    if style.isHero, !eyebrow.text.isEmpty { children.append(eyebrow) }
    children += [title, subtitle]
    if showsOverall { children.append(overallLead) }
    for group in groupViews {
      children.append(group)
    }
    if !footnote.text.isEmpty { children.append(footnote) }
    for button in [secondaryButton, primaryButton] where !button.isHidden { children.append(button) }
    return children
  }
}
