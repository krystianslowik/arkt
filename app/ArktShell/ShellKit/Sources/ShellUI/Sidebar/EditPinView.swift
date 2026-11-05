import AppKit
import Motion

/// The Edit Pin popover's measures (design/edit-pin): 320 pt wide, padding 16, radius 12, fields 28 high.
enum EditPinMetrics {
  static let width: CGFloat = 320
  static let padding: CGFloat = 16
  static let cornerRadius: CGFloat = 12
  /// The arrow: how far its tip stands out, and half its base.
  static let arrowDepth: CGFloat = 7
  static let arrowHalfBase: CGFloat = 8
  /// The leading arrow's center, from the top: the 12 pt notch starts 16 pt down.
  static let arrowCenter: CGFloat = 22
  /// Space between a Favorite tile and the arrow's tip.
  static let anchorGap: CGFloat = 2
  /// The popover keeps this far from the window's edges.
  static let windowMargin: CGFloat = 8
  static let titleHeight: CGFloat = 16
  /// Above each label (the title's 10 pt and the gap after a field).
  static let labelGap: CGFloat = 10
  static let labelHeight: CGFloat = 14
  /// Between a label and its field.
  static let labelToField: CGFloat = 4
  static let fieldHeight: CGFloat = 28
  static let fieldRadius: CGFloat = 8
  static let fieldInset: CGFloat = 9
  static let errorGap: CGFloat = 5
  static let errorHeight: CGFloat = 14
  static let glyphSize: CGFloat = 12
  static let actionsGap: CGFloat = 16
  static let buttonHeight: CGFloat = 28
  static let buttonSpacing: CGFloat = 8

  /// The popover's height, with or without the invalid address line.
  static func height(showingError: Bool) -> CGFloat {
    let fields = 2 * (labelGap + labelHeight + labelToField + fieldHeight)
    let error = showingError ? errorGap + errorHeight : 0
    return padding + titleHeight + fields + error + actionsGap + buttonHeight + padding
  }
}

/// The Edit Pin popover's motion (design/edit-pin, Motion): it opens from the arrow, scale 0.97 to 1 and fading in
/// on `firm` (0.22 s); Reduce Motion fades only, 0.15 s. It closes with a 0.15 s fade either way, and the invalid
/// address line fades in over 0.15 s.
enum EditPinMotion {
  static let openScale: CGFloat = 0.97
  static let openDuration: CFTimeInterval = 0.22
  static let reducedOpenDuration: CFTimeInterval = 0.15
  static let closeDuration: CFTimeInterval = FadeDuration.standard
  static let errorDuration: CFTimeInterval = FadeDuration.standard
  static let errorFadeKey = "editPin.errorFade"
  static let openScaleKey = "editPin.openScale"
  static let openFadeKey = "editPin.openFade"
  static let closeKey = "editPin.close"

  /// How long the popover takes to grow by the invalid address line: 0.15 s, or nil (at once) with Reduce Motion,
  /// where only the line's fade remains.
  static func errorResizeDuration(reducesMotion: Bool) -> CFTimeInterval? {
    reducesMotion ? nil : errorDuration
  }
}

/// Where the popover's arrow sits: on its leading edge at `y` from the top (a pinned row), or on its top edge at `x`
/// from the leading edge (a Favorite tile).
enum EditPinArrow: Equatable {
  case leading(y: CGFloat)
  case top(x: CGFloat)
}

/// One of the popover's fields: a recessed rounded field (`ArchiveTokens.listField`, radius 8) holding a plain text
/// field that scrolls a long value on one line. A 1 pt `destructiveText` ring marks an invalid address.
@MainActor
final class EditPinFieldView: NSView {
  let field = EditPinTextField(string: "")
  private(set) lazy var focusRing = KeyboardFocusRingView.attach(outside: self, radius: EditPinMetrics.fieldRadius)
  var showsError = false { didSet { if showsError != oldValue { needsDisplay = true } } }

  init(label: String, identifier: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = EditPinMetrics.fieldRadius
    layer?.cornerCurve = .continuous
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.lineBreakMode = .byClipping
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.setAccessibilityLabel(label)
    field.setAccessibilityIdentifier(identifier)
    field.onFocusChange = { [weak self] focused in self?.focusRing.setFocused(focused) }
    addSubview(field)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ArchiveTokens.listField.resolve(flavor).cgColor
    layer?.borderWidth = showsError ? 1 : 0
    layer?.borderColor = ArchiveTokens.destructiveText.resolve(flavor).cgColor
    field.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    let height = ceil(field.intrinsicContentSize.height)
    let inset = EditPinMetrics.fieldInset
    field.frame = NSRect(x: inset, y: ((bounds.height - height) / 2).rounded(),
                         width: max(0, bounds.width - 2 * inset), height: height)
  }
}

/// A text field that reports when it takes and loses the keyboard, for its container's focus ring. The field
/// editor holds the keyboard while it edits, so the ring follows the editing session.
@MainActor
final class EditPinTextField: NSTextField {
  var onFocusChange: (@MainActor (Bool) -> Void)?

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { onFocusChange?(true) }
    return became
  }

  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    onFocusChange?(false)
  }
}

/// The Edit Pin popover (#363, design/edit-pin, direction B): a 320 pt `surfaceBrand` surface with an arrow pointing
/// at the row or tile, holding the title, the Name and Pinned URL fields, the invalid address line, and the actions:
/// Use Current Page (a quiet link, leading), Cancel and Save (the one primary, Return).
///
/// AppKit and Core Animation, frames set directly. `EditPinController` owns the state and the keyboard; this view
/// lays it out.
@MainActor
final class EditPinView: NSView {
  let titleLabel = NSTextField(labelWithString: "")
  let nameLabel = NSTextField(labelWithString: "Name")
  let nameBox = EditPinFieldView(label: "Name", identifier: AXID.EditPin.name)
  let urlLabel = NSTextField(labelWithString: "Pinned URL")
  let urlBox = EditPinFieldView(label: "Pinned URL", identifier: AXID.EditPin.url)
  /// The invalid address line: the warning glyph and the reason.
  let errorLine = NSView()
  let errorGlyph = NSImageView()
  let errorLabel = NSTextField(labelWithString: EditPinForm.invalidAddressMessage)
  let useCurrentPageButton = ArchiveLinkButton(style: .secondary, title: "Use Current Page", fontSize: 13)
  let cancelButton = ArchivePillButton(style: .neutral, title: "Cancel", metrics: .dialog)
  let saveButton = ArchivePillButton(style: .primary, title: "Save", metrics: .dialog)
  /// The node the popover edits.
  let nodeID: NodeID

  var nameField: NSTextField { nameBox.field }
  var urlField: NSTextField { urlBox.field }
  var urlFieldShowsError: Bool { urlBox.showsError }

  /// Escape from a control that is not a field (the buttons).
  var onCancel: (() -> Void)?

  private(set) var arrow: EditPinArrow = .leading(y: EditPinMetrics.arrowCenter)
  private let surface = CAShapeLayer()
  private let dropShadow = CAShapeLayer()
  private let contactShadow = CAShapeLayer()

  /// The arrow tip's x from the leading edge: its center for a top arrow, outside the leading edge otherwise.
  var arrowX: CGFloat {
    if case .top(let x) = arrow { x } else { -EditPinMetrics.arrowDepth }
  }

  /// The arrow tip, in this view's coordinates: the point the open animation grows from.
  var arrowTip: NSPoint {
    switch arrow {
    case .leading(let y): NSPoint(x: -EditPinMetrics.arrowDepth, y: y)
    case .top(let x): NSPoint(x: x, y: -EditPinMetrics.arrowDepth)
    }
  }

  init(nodeID: NodeID, title: String) {
    self.nodeID = nodeID
    super.init(frame: NSRect(x: 0, y: 0, width: EditPinMetrics.width,
                             height: EditPinMetrics.height(showingError: false)))
    wantsLayer = true
    layer?.masksToBounds = false
    for sublayer in [contactShadow, dropShadow, surface] {
      sublayer.actions = ["path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "shadowPath": NSNull()]
      layer?.addSublayer(sublayer)
    }
    surface.lineWidth = 0.5
    titleLabel.stringValue = title
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    for label in [nameLabel, urlLabel] {
      label.font = .systemFont(ofSize: 11, weight: .semibold)
      label.setAccessibilityElement(false)          // the fields carry the same names
    }
    errorLabel.font = .systemFont(ofSize: 11)
    errorLabel.lineBreakMode = .byTruncatingTail
    errorGlyph.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
    errorGlyph.setAccessibilityElement(false)
    errorLine.addSubview(errorGlyph)
    errorLine.addSubview(errorLabel)
    errorLine.wantsLayer = true
    errorLine.isHidden = true
    useCurrentPageButton.setAccessibilityHelp("Sets the pinned URL to this tab's address")
    useCurrentPageButton.cell?.setAccessibilityHelp("Sets the pinned URL to this tab's address")
    useCurrentPageButton.setAccessibilityIdentifierWithCell(AXID.EditPin.useCurrentPage)
    cancelButton.setArchiveAccessibilityLabel("Cancel")
    cancelButton.setAccessibilityIdentifierWithCell(AXID.EditPin.cancel)
    saveButton.setArchiveAccessibilityLabel("Save")
    saveButton.setAccessibilityIdentifierWithCell(AXID.EditPin.save)
    saveButton.keyEquivalent = "\r"
    for subview: NSView in [titleLabel, nameLabel, nameBox, urlLabel, urlBox, errorLine, useCurrentPageButton,
                            cancelButton, saveButton] {
      addSubview(subview)
    }
    nameField.nextKeyView = urlField
    urlField.nextKeyView = useCurrentPageButton
    useCurrentPageButton.nextKeyView = cancelButton
    cancelButton.nextKeyView = saveButton
    saveButton.nextKeyView = nameField
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel(title)
    setAccessibilityIdentifier(AXID.EditPin.popover)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel?() }
  /// Clicks on the surface stay in the popover; the window behind never sees them.
  override func mouseDown(with event: NSEvent) {}

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  func setArrow(_ arrow: EditPinArrow) {
    self.arrow = arrow
    needsLayout = true
  }

  /// Shows or hides the invalid address line and the field's ring; the line is the field's help while it shows.
  func setErrorShown(_ shown: Bool) {
    urlBox.showsError = shown
    errorLine.isHidden = !shown
    urlField.setAccessibilityHelp(shown ? EditPinForm.invalidAddressMessage : nil)
    needsLayout = true
  }

  // MARK: Layout

  override func layout() {
    super.layout()
    let m = EditPinMetrics.self
    let inner = bounds.width - 2 * m.padding
    var y = m.padding
    titleLabel.frame = NSRect(x: m.padding, y: y, width: inner, height: m.titleHeight)
    y += m.titleHeight
    for (label, box) in [(nameLabel, nameBox), (urlLabel, urlBox)] {
      y += m.labelGap
      label.frame = NSRect(x: m.padding, y: y, width: inner, height: m.labelHeight)
      y += m.labelHeight + m.labelToField
      box.frame = NSRect(x: m.padding, y: y, width: inner, height: m.fieldHeight)
      y += m.fieldHeight
    }
    if !errorLine.isHidden {
      y += m.errorGap
      errorLine.frame = NSRect(x: m.padding, y: y, width: inner, height: m.errorHeight)
      errorGlyph.frame = NSRect(x: 0, y: (m.errorHeight - m.glyphSize) / 2, width: m.glyphSize, height: m.glyphSize)
      let textX = m.glyphSize + 5
      errorLabel.frame = NSRect(x: textX, y: 0, width: inner - textX, height: m.errorHeight)
      y += m.errorHeight
    }
    y += m.actionsGap
    let save = pillWidth(saveButton), cancel = pillWidth(cancelButton)
    saveButton.frame = NSRect(x: bounds.width - m.padding - save, y: y, width: save, height: m.buttonHeight)
    cancelButton.frame = NSRect(x: saveButton.frame.minX - m.buttonSpacing - cancel, y: y, width: cancel,
                                height: m.buttonHeight)
    let link = useCurrentPageButton.intrinsicContentSize
    let linkWidth = min(ceil(link.width), max(0, cancelButton.frame.minX - m.buttonSpacing - m.padding))
    useCurrentPageButton.frame = NSRect(x: m.padding, y: y + (m.buttonHeight - ceil(link.height)) / 2,
                                        width: linkWidth, height: ceil(link.height))
    layoutSurface()
  }

  private func pillWidth(_ button: NSButton) -> CGFloat { ceil(button.intrinsicContentSize.width) }

  private func layoutSurface() {
    let path = Self.surfacePath(size: bounds.size, arrow: arrow)
    let flavor = archiveFlavor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [surface, dropShadow, contactShadow] {
      sublayer.frame = bounds
      sublayer.path = path
    }
    let token = ShellTokens.overlayShadow
    dropShadow.shadowPath = path
    dropShadow.shadowColor = token.color.resolve(flavor).cgColor
    dropShadow.shadowOpacity = 1
    dropShadow.shadowRadius = token.radius
    dropShadow.shadowOffset = CGSize(width: 0, height: token.offsetY)
    contactShadow.shadowPath = path
    contactShadow.shadowColor = token.contactColor.resolve(flavor).cgColor
    contactShadow.shadowOpacity = 1
    contactShadow.shadowRadius = token.contactRadius
    contactShadow.shadowOffset = CGSize(width: 0, height: token.contactOffsetY)
    let fill = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    surface.fillColor = fill
    surface.strokeColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    dropShadow.fillColor = fill                     // hidden under the surface; only their shadows show
    contactShadow.fillColor = fill
    CATransaction.commit()
  }

  private func restyle() {
    let flavor = archiveFlavor
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    for label in [nameLabel, urlLabel] { label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor() }
    let destructive = ArchiveTokens.destructiveText.resolve(flavor).nsColor()
    errorLabel.textColor = destructive
    errorGlyph.contentTintColor = destructive
    needsLayout = true
  }

  /// A rounded rectangle with the arrow on its leading or top edge, softened at its tip (flipped coordinates).
  static func surfacePath(size: CGSize, arrow: EditPinArrow) -> CGPath {
    let r = EditPinMetrics.cornerRadius
    let half = EditPinMetrics.arrowHalfBase, tip = EditPinMetrics.arrowDepth
    let w = size.width, h = size.height
    let path = CGMutablePath()
    path.move(to: CGPoint(x: r, y: 0))
    if case .top(let x) = arrow {
      path.addLine(to: CGPoint(x: x - half, y: 0))
      path.addQuadCurve(to: CGPoint(x: x, y: -tip), control: CGPoint(x: x - half * 0.3, y: -tip * 0.55))
      path.addQuadCurve(to: CGPoint(x: x + half, y: 0), control: CGPoint(x: x + half * 0.3, y: -tip * 0.55))
    }
    path.addLine(to: CGPoint(x: w - r, y: 0))
    path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
    path.addLine(to: CGPoint(x: w, y: h - r))
    path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
    path.addLine(to: CGPoint(x: r, y: h))
    path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
    if case .leading(let y) = arrow {
      path.addLine(to: CGPoint(x: 0, y: y + half))
      path.addQuadCurve(to: CGPoint(x: -tip, y: y), control: CGPoint(x: -tip * 0.55, y: y + half * 0.3))
      path.addQuadCurve(to: CGPoint(x: 0, y: y - half), control: CGPoint(x: -tip * 0.55, y: y - half * 0.3))
    }
    path.addLine(to: CGPoint(x: 0, y: r))
    path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
    path.closeSubpath()
    return path
  }
}
