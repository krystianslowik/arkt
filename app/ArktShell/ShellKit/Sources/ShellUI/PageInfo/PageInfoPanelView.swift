import AppKit
import EngineAPI

/// The page info panel's content (#582): the header (badge, host, connection line), then for a site the Cookies and
/// site data row, the Permissions section with a pop-up per permission, and the footer (Reset Permissions, Site
/// Settings...); for a local file the header and one note. Everyday chrome: no primary pill, changes apply at once.
///
/// The rows sit in a scroll view, so a long list scrolls under a fixed header and footer with a faded bottom edge.
/// Frames are set directly in `layout()`. #651 adds its rows (Auto Picture in Picture) to the site section.
@MainActor
final class PageInfoPanelView: NSView {
  private(set) var model: PageInfoModel?

  let badge = NSView()
  let badgeGlyph = NSImageView()
  let hostLabel = NSTextField(labelWithString: "")
  let connectionGlyph = NSImageView()
  let connectionLabel = NSTextField(wrappingLabelWithString: "")
  let noteLabel = NSTextField(wrappingLabelWithString: "")
  let scrollView = NSScrollView()
  private let list = FlippedView()
  let siteDataRow = PageInfoDataRow()
  private let permissionsTitle = NSTextField(labelWithString: "Permissions")
  let readOnlyLabel = NSTextField(labelWithString: "")
  private(set) var rows: [PageInfoPermissionRow] = []
  private var dividers: [NSView] = []
  private let footerDivider = NSView()
  let resetButton = NSButton(title: "Reset Permissions", target: nil, action: nil)
  let siteSettingsButton = NSButton(title: "Site Settings...", target: nil, action: nil)
  private let fadeMask = CAGradientLayer()

  /// A pop-up's choice; the site data row; the footer's buttons.
  var onSetPermission: (@MainActor (SitePermissionKind, PermissionSetting) -> Void)?
  var onShowSiteData: (@MainActor () -> Void)?
  var onResetPermissions: (@MainActor () -> Void)?
  var onSiteSettings: (@MainActor () -> Void)?
  /// Increase Contrast adds the 1 pt edge to the pop-ups (tests set it).
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    badge.wantsLayer = true
    badge.layer?.cornerRadius = PageInfoMetrics.badgeCorner
    badge.layer?.cornerCurve = .continuous
    badgeGlyph.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    badge.addSubview(badgeGlyph)
    hostLabel.font = ShellType.bodyEmphasis.font
    hostLabel.lineBreakMode = .byTruncatingMiddle
    hostLabel.maximumNumberOfLines = 1
    hostLabel.cell?.usesSingleLineMode = true
    connectionGlyph.symbolConfiguration = .init(pointSize: 10, weight: .medium)
    connectionLabel.font = ShellType.caption.font
    connectionLabel.maximumNumberOfLines = 2
    noteLabel.font = ShellType.caption.font
    for view in [badge, hostLabel, connectionGlyph, connectionLabel, noteLabel] as [NSView] { addSubview(view) }
    for view in [badgeGlyph, connectionGlyph] { view.setAccessibilityElement(false) }

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.documentView = list
    scrollView.wantsLayer = true
    addSubview(scrollView)
    siteDataRow.button.target = self
    siteDataRow.button.action = #selector(showSiteData(_:))
    list.addSubview(siteDataRow)
    permissionsTitle.font = ShellType.sectionHeader.font
    list.addSubview(permissionsTitle)
    readOnlyLabel.font = ShellType.footnote.font
    readOnlyLabel.lineBreakMode = .byTruncatingTail
    list.addSubview(readOnlyLabel)

    footerDivider.wantsLayer = true
    addSubview(footerDivider)
    for (button, action) in [(resetButton, #selector(resetPermissions(_:))),
                             (siteSettingsButton, #selector(openSiteSettings(_:)))] {
      button.isBordered = false
      button.bezelStyle = .regularSquare
      button.font = ShellType.body.font
      button.target = self
      button.action = action
      addSubview(button)
    }
    resetButton.setAccessibilityIdentifierWithCell(AXID.PageInfo.reset)
    siteSettingsButton.setAccessibilityIdentifierWithCell(AXID.PageInfo.siteSettings)
    siteDataRow.button.setAccessibilityIdentifierWithCell(AXID.PageInfo.siteData)
    fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Content

  /// Shows `model`, keeping the list's scroll position when the same page is shown again (a change read back).
  func reload(_ model: PageInfoModel) {
    let samePage = self.model?.tab == model.tab && self.model?.origin == model.origin
    let offset = scrollView.contentView.bounds.origin
    self.model = model
    hostLabel.stringValue = model.host
    hostLabel.toolTip = model.host
    connectionLabel.stringValue = model.connectionText
    connectionGlyph.image = NSImage(systemSymbolName: model.connectionSymbol, accessibilityDescription: nil)
    // The page's favicon when it has one; else the site glyph.
    let favicon = model.favicon.flatMap(NSImage.init(data:))
    badgeGlyph.image = favicon ?? NSImage(systemSymbolName: model.state == .localFile ? "doc" : "globe",
                                          accessibilityDescription: nil)
    showsFavicon = favicon != nil
    noteLabel.stringValue = model.note ?? ""
    let isSite = model.state == .site
    noteLabel.isHidden = isSite
    for view in [scrollView, footerDivider, resetButton, siteSettingsButton] as [NSView] { view.isHidden = !isSite }
    siteDataRow.summary.stringValue = model.siteDataText
    siteDataRow.button.setAccessibilityValue(model.siteDataText)
    resetButton.isEnabled = model.canResetPermissions
    permissionsTitle.isHidden = model.rows.isEmpty
    readOnlyLabel.stringValue = model.readOnlyNote ?? ""
    readOnlyLabel.isHidden = model.readOnlyNote == nil || model.rows.isEmpty
    rebuildRows(model.rows)
    for popUp in popUps { popUp.isEnabled = !model.isReadOnly }
    restyle()
    needsLayout = true
    layoutSubtreeIfNeeded()
    if samePage { scrollView.contentView.scroll(to: offset) }
  }

  private func rebuildRows(_ models: [PageInfoModel.Row]) {
    if rows.map(\.kind) == models.map(\.kind) {
      for (row, model) in zip(rows, models) { row.configure(model) }
      return
    }
    rows.forEach { $0.removeFromSuperview() }
    rows = models.map { model in
      let row = PageInfoPermissionRow(model)
      row.onChoose = { [weak self] kind, setting in self?.onSetPermission?(kind, setting) }
      list.addSubview(row)
      return row
    }
    dividers.forEach { $0.removeFromSuperview() }
    dividers = (0..<(models.isEmpty ? 1 : 2)).map { _ in
      let divider = NSView()
      divider.wantsLayer = true
      list.addSubview(divider)
      return divider
    }
  }

  /// The pop-ups in order; the first takes the focus when the panel opens.
  var popUps: [NSPopUpButton] { rows.map(\.popUp) }

  /// The first control, for the focus when the panel opens.
  var firstControl: NSView? {
    guard model?.state == .site else { return nil }
    return popUps.first { $0.isEnabled } ?? siteDataRow.button
  }

  /// The badge shows the page's favicon in its own colors rather than a tinted glyph.
  private(set) var showsFavicon = false

  // MARK: Layout

  /// The header's height at `width`: a not-secure line wraps to two.
  private func headerHeight(width: CGFloat) -> CGFloat {
    let m = PageInfoMetrics.self
    let textWidth = width - 2 * m.sideInset - m.badge - m.headerTextGap - 16
    let line = connectionLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(0, textWidth), height: 100))
      .height ?? 15
    return max(m.headerHeight, m.headerTop + 17 + ceil(line) + m.headerBottom)
  }

  private func noteHeight(width: CGFloat) -> CGFloat {
    ceil(noteLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(0, width - 2 * PageInfoMetrics.sideInset),
                                                    height: 400)).height ?? 32)
  }

  /// The list's content height (between the header and the footer).
  private var listHeight: CGFloat {
    let m = PageInfoMetrics.self
    let data = 1 + 2 * m.sectionPadding + m.rowHeight
    let list = rows.reduce(0) { $0 + $1.height }
    let readOnly = readOnlyLabel.isHidden ? 0 : m.readOnlyNoteHeight
    let permissions = rows.isEmpty ? 0 : 1 + m.sectionTitleHeight + readOnly + list + m.sectionPadding
    return data + permissions
  }

  /// The whole content's height at `width`, before any cap.
  func preferredHeight(width: CGFloat) -> CGFloat {
    let m = PageInfoMetrics.self
    let header = headerHeight(width: width)
    guard let model else { return header }
    switch model.state {
    case .localFile: return header + m.sectionPadding + noteHeight(width: width) + m.noteBottom
    case .site: return header + listHeight + 1 + m.footerHeight
    }
  }

  override func layout() {
    super.layout()
    let m = PageInfoMetrics.self
    let width = bounds.width
    let header = headerHeight(width: width)
    badge.frame = NSRect(x: m.sideInset, y: m.headerTop, width: m.badge, height: m.badge)
    badgeGlyph.frame = badge.bounds.insetBy(dx: showsFavicon ? 6 : 7, dy: showsFavicon ? 6 : 7)
    let textX = badge.frame.maxX + m.headerTextGap
    let textWidth = max(0, width - textX - m.sideInset)
    hostLabel.frame = NSRect(x: textX, y: m.headerTop - 1, width: textWidth, height: 17)
    connectionGlyph.frame = NSRect(x: textX, y: hostLabel.frame.maxY + 2, width: 12, height: 13)
    connectionLabel.frame = NSRect(x: textX + 16, y: hostLabel.frame.maxY, width: max(0, textWidth - 16),
                                   height: max(15, header - m.headerBottom - hostLabel.frame.maxY))
    noteLabel.frame = NSRect(x: m.sideInset, y: header + m.sectionPadding, width: max(0, width - 2 * m.sideInset),
                             height: noteHeight(width: width))

    let footerTop = bounds.height - m.footerHeight
    footerDivider.frame = NSRect(x: 0, y: footerTop - 1, width: width, height: 1)
    let buttonHeight: CGFloat = 24
    let buttonY = footerTop + ((m.footerHeight - buttonHeight) / 2).rounded()
    resetButton.sizeToFit()
    siteSettingsButton.sizeToFit()
    resetButton.frame = NSRect(x: m.footerInset, y: buttonY, width: resetButton.frame.width, height: buttonHeight)
    siteSettingsButton.frame = NSRect(x: width - m.footerInset - siteSettingsButton.frame.width, y: buttonY,
                                      width: siteSettingsButton.frame.width, height: buttonHeight)

    scrollView.frame = NSRect(x: 0, y: header, width: width, height: max(0, footerTop - 1 - header))
    list.frame = NSRect(x: 0, y: 0, width: width, height: listHeight)
    var y: CGFloat = 0
    if let first = dividers.first {
      first.frame = NSRect(x: 0, y: y, width: width, height: 1)
      y += 1
    }
    y += m.sectionPadding
    siteDataRow.frame = NSRect(x: 0, y: y, width: width, height: m.rowHeight)
    y += m.rowHeight + m.sectionPadding
    if dividers.count > 1 {
      dividers[1].frame = NSRect(x: 0, y: y, width: width, height: 1)
      y += 1
      permissionsTitle.frame = NSRect(x: m.sideInset, y: y + 8, width: width - 2 * m.sideInset, height: 14)
      y += m.sectionTitleHeight
      if !readOnlyLabel.isHidden {
        readOnlyLabel.frame = NSRect(x: m.sideInset, y: y, width: width - 2 * m.sideInset, height: 15)
        y += m.readOnlyNoteHeight
      }
      for row in rows {
        row.frame = NSRect(x: 0, y: y, width: width, height: row.height)
        y += row.height
      }
    }
    updateFade()
  }

  /// Whether the list scrolls: then its bottom 12 pt fade out.
  var listScrolls: Bool { list.frame.height > scrollView.frame.height + 0.5 }

  private func updateFade() {
    guard listScrolls, let layer = scrollView.layer, scrollView.bounds.height > 0 else {
      scrollView.layer?.mask = nil
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = layer.bounds
    let fade = Double(PageInfoMetrics.fade / scrollView.bounds.height)
    // The scroll view's layer is not flipped: the bottom edge is at location 0.
    fadeMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
    fadeMask.locations = [0, NSNumber(value: fade), 1]
    fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
    fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
    layer.mask = fadeMask
    CATransaction.commit()
  }

  // MARK: Style

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  func restyle() {
    let flavor = archiveFlavor
    let primary = ShellTokens.primaryText.resolve(flavor).nsColor()
    let secondary = ShellTokens.secondaryText.resolve(flavor).nsColor()
    let glyph = ShellTokens.sidebarForeground.resolve(flavor).nsColor()
    badge.layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
    badgeGlyph.contentTintColor = showsFavicon ? nil : glyph
    hostLabel.textColor = primary
    let warning = model?.connectionIsWarning == true
    connectionLabel.textColor = warning ? primary : secondary          // never red
    connectionGlyph.contentTintColor = warning ? primary : secondary
    noteLabel.textColor = secondary
    permissionsTitle.textColor = secondary
    readOnlyLabel.textColor = secondary
    let divider = ShellTokens.sidebarDivider.resolve(flavor).cgColor
    for view in dividers + [footerDivider] { view.layer?.backgroundColor = divider }
    // Quiet buttons: secondary text, fainter while off.
    for button in [resetButton, siteSettingsButton] {
      let color = button.isEnabled ? secondary : secondary.withAlphaComponent(0.45)
      button.attributedTitle = NSAttributedString(string: button.title, attributes: [
        .foregroundColor: color, .font: button.font ?? ShellType.body.font,
      ])
    }
    siteDataRow.restyle(flavor: flavor)
    let edge = increaseContrast()
    for row in rows { row.restyle(flavor: flavor, increaseContrast: edge) }
  }

  // MARK: Actions

  @objc private func showSiteData(_ sender: Any?) { onShowSiteData?() }
  @objc private func resetPermissions(_ sender: Any?) { onResetPermissions?() }
  @objc private func openSiteSettings(_ sender: Any?) { onSiteSettings?() }
}

/// Cookies and site data: a row-wide button with the summary and a chevron.
@MainActor
final class PageInfoDataRow: NSView {
  let button = NSButton(title: "", target: nil, action: nil)
  private let glyph = NSImageView()
  private let title = NSTextField(labelWithString: "Cookies and site data")
  let summary = NSTextField(labelWithString: "")
  private let chevron = NSImageView()

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.title = ""
    button.setAccessibilityLabel("Cookies and site data")
    glyph.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: nil)
    glyph.symbolConfiguration = .init(pointSize: 13, weight: .regular)
    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    chevron.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
    title.font = ShellType.body.font
    title.lineBreakMode = .byTruncatingTail
    summary.font = ShellType.caption.font
    summary.alignment = .right
    summary.lineBreakMode = .byTruncatingTail
    for view in [glyph, title, summary, chevron] as [NSView] {
      view.setAccessibilityElement(false)
      addSubview(view)
    }
    addSubview(button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layout() {
    super.layout()
    let m = PageInfoMetrics.self
    button.frame = bounds
    glyph.frame = NSRect(x: m.sideInset, y: (bounds.height - m.glyph) / 2, width: m.glyph, height: m.glyph)
    chevron.frame = NSRect(x: bounds.width - m.sideInset - 8, y: (bounds.height - 12) / 2, width: 8, height: 12)
    let textX = glyph.frame.maxX + m.glyphGap
    summary.sizeToFit()
    let summaryWidth = min(summary.frame.width, (bounds.width - textX - m.sideInset) / 2)
    summary.frame = NSRect(x: chevron.frame.minX - 8 - summaryWidth, y: (bounds.height - 16) / 2,
                           width: summaryWidth, height: 16)
    title.frame = NSRect(x: textX, y: (bounds.height - 17) / 2, width: max(0, summary.frame.minX - 8 - textX),
                         height: 17)
  }

  func restyle(flavor: ThemeFlavor) {
    glyph.contentTintColor = ShellTokens.sidebarForeground.resolve(flavor).nsColor()
    chevron.contentTintColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    title.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    summary.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }
}

/// One permission: glyph, the engine's title, and a pop-up of the settings it offers. VoiceOver reads the pop-up as
/// "Camera, Block, pop-up button". While macOS denies Arkt the permission, a secondary note sits under the title
/// ("Turned off in macOS", #786) and VoiceOver reads it with the title.
@MainActor
final class PageInfoPermissionRow: NSView {
  let kind: SitePermissionKind
  private let glyph = NSImageView()
  let title = NSTextField(labelWithString: "")
  let note = NSTextField(labelWithString: "")
  private(set) var height = PageInfoMetrics.rowHeight
  let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
  var onChoose: (@MainActor (SitePermissionKind, PermissionSetting) -> Void)?

  override var isFlipped: Bool { true }

  init(_ model: PageInfoModel.Row) {
    kind = model.kind
    super.init(frame: .zero)
    glyph.symbolConfiguration = .init(pointSize: 13, weight: .regular)
    glyph.setAccessibilityElement(false)
    title.font = ShellType.body.font
    title.lineBreakMode = .byTruncatingTail
    title.setAccessibilityElement(false)
    note.font = ShellType.footnote.font
    note.lineBreakMode = .byTruncatingTail
    note.setAccessibilityElement(false)
    popUp.isBordered = false
    popUp.controlSize = .small
    popUp.font = ShellType.caption.font
    popUp.wantsLayer = true
    popUp.layer?.cornerRadius = PageInfoMetrics.popUpCorner
    popUp.layer?.cornerCurve = .continuous
    popUp.target = self
    popUp.action = #selector(chose(_:))
    popUp.setAccessibilityIdentifierWithCell(AXID.PageInfo.permission(model.kind))
    for view in [glyph, title, note, popUp] as [NSView] { addSubview(view) }
    configure(model)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ model: PageInfoModel.Row) {
    glyph.image = NSImage(systemSymbolName: model.symbol, accessibilityDescription: nil)
      ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    title.stringValue = model.title
    note.stringValue = model.systemNote ?? ""
    note.isHidden = model.systemNote == nil
    height = model.height
    popUp.removeAllItems()
    for option in model.options {
      popUp.addItem(withTitle: option.title)
      popUp.lastItem?.representedObject = option.setting.rawValue
    }
    popUp.selectItem(at: model.options.firstIndex { $0.setting == model.setting } ?? 0)
    popUp.setAccessibilityLabel(model.accessibilityLabel)
    needsLayout = true
  }

  var selectedSetting: PermissionSetting? {
    (popUp.selectedItem?.representedObject as? String).flatMap(PermissionSetting.init(rawValue:))
  }

  override func layout() {
    super.layout()
    let m = PageInfoMetrics.self
    glyph.frame = NSRect(x: m.sideInset, y: (bounds.height - m.glyph) / 2, width: m.glyph, height: m.glyph)
    // Compact, as drawn: the selected title and the arrows, trailing; it grows when the choice does.
    let selected = (popUp.titleOfSelectedItem ?? "") as NSString
    let titleWidth = selected.size(withAttributes: [.font: popUp.font ?? ShellType.caption.font]).width
    let popUpWidth = ceil(titleWidth) + 32
    popUp.frame = NSRect(x: bounds.width - m.sideInset - popUpWidth, y: (bounds.height - m.popUpHeight) / 2,
                         width: popUpWidth, height: m.popUpHeight)
    let textX = glyph.frame.maxX + m.glyphGap
    let textWidth = max(0, popUp.frame.minX - 8 - textX)
    if note.isHidden {
      title.frame = NSRect(x: textX, y: (bounds.height - 17) / 2, width: textWidth, height: 17)
    } else {
      // Title and note as one block, centered on the glyph and the pop-up.
      let top = ((bounds.height - 17 - 1 - 14) / 2).rounded()
      title.frame = NSRect(x: textX, y: top, width: textWidth, height: 17)
      note.frame = NSRect(x: textX, y: title.frame.maxY + 1, width: textWidth, height: 14)
    }
  }

  func restyle(flavor: ThemeFlavor, increaseContrast: Bool) {
    glyph.contentTintColor = ShellTokens.sidebarForeground.resolve(flavor).nsColor()
    title.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    note.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    popUp.layer?.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    popUp.layer?.borderWidth = increaseContrast ? 1 : 0
    popUp.layer?.borderColor = AlertTokens.increasedContrastEdge.resolve(flavor).cgColor
  }

  @objc private func chose(_ sender: Any?) {
    guard let setting = selectedSetting else { return }
    onChoose?(kind, setting)
  }
}
