import AppKit

// MARK: - Name field

/// The Space name as the headline (section 6.3): a text field at display size with the placeholder "Space 1" (or
/// the imported Space's name), 40 characters at most. A 120 pt hairline under it widens to 180 and turns mustard
/// while it is focused (M7, 300 ms ease-out, a scale of the underline layer). Escape ends editing and restores the
/// value it had on focus; Return moves on like Continue (the default button's key equivalent).
@MainActor
final class SpaceNameField: NSView, NSTextFieldDelegate {
  var appearanceModel: OnboardingAppearance { didSet { restyle() } }
  var compact = false { didSet { restyle() } }
  /// Every edit, with the field's current text.
  var onChange: (@MainActor (String) -> Void)?
  /// Escape while editing: restored to the value it had on focus.
  var onRestore: (@MainActor (String) -> Void)?

  let field = NameTextField()
  private let underline = CALayer()
  private var valueOnFocus = ""
  private var placeholder = ""
  private(set) var isEditing = false

  init(appearance: OnboardingAppearance) {
    self.appearanceModel = appearance
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.alignment = .center
    field.lineBreakMode = .byClipping
    field.cell?.isScrollable = true
    field.cell?.usesSingleLineMode = true
    field.delegate = self
    field.owner = self
    field.setAccessibilityLabel(OnboardingCopy.nameLabel)
    field.setAccessibilityIdentifier(AXID.Onboarding.name)
    addSubview(field)
    underline.cornerRadius = 1
    layer?.addSublayer(underline)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  private var style: BrandType.Style { BrandType.Role.nameField.style(compact: compact) }

  var lineHeight: CGFloat { style.lineHeight ?? style.size }

  func configure(name: String, placeholder: String) {
    self.placeholder = placeholder
    field.setAccessibilityPlaceholderValue(placeholder)
    if field.stringValue != name { field.stringValue = name }
    restyle()
  }

  /// The field's text attributes: the face, size and tracking, centred, at the font's own line height (the frame
  /// places the baseline; a fixed line height would push the glyphs above the field).
  private func fieldAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
    var attributes = BrandType.attributes(style, color: color)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    attributes[.paragraphStyle] = paragraph
    return attributes
  }

  private func restyle() {
    // The field's font and placeholder change only while no field editor is attached: changing them mid-edit ends
    // the edit.
    var attributes = fieldAttributes(color: appearanceModel.textPrimary)
    if field.currentEditor() == nil {
      field.font = attributes[.font] as? NSFont
      field.textColor = appearanceModel.textPrimary
    }
    attributes[.foregroundColor] = isEditing ? appearanceModel.textSecondary.withAlphaComponent(0.5)
      : appearanceModel.textPrimary
    (field.cell as? NameFieldCell)?.placeholder = NSAttributedString(string: placeholder, attributes: attributes)
    field.needsDisplay = true
    applyTypingAttributes()
    OnboardingMotion.set {
      underline.backgroundColor = (isEditing ? appearanceModel.accent : appearanceModel.hairline).cgColor
    }
  }

  private func applyTypingAttributes() {
    guard let editor = field.currentEditor() as? NSTextView else { return }
    editor.typingAttributes = fieldAttributes(color: appearanceModel.textPrimary)
    editor.insertionPointColor = appearanceModel.accentText
  }

  override func layout() {
    super.layout()
    // The field draws at the font's own line height; it is moved up so its baseline sits where the website's
    // 1.02 line box puts it, and the underline sits 4 pt under that box (section 6.3).
    let font = BrandType.font(for: style)
    let natural = ceil(font.ascender - font.descender + font.leading)
    let shift = BrandType.cssShift(font: font, lineHeight: lineHeight)
    field.frame = NSRect(x: 0, y: -shift - 1, width: bounds.width, height: natural + 4)
    OnboardingMotion.set {
      underline.bounds = CGRect(x: 0, y: 0, width: 180, height: 2)
      underline.position = CGPoint(x: bounds.midX, y: lineHeight + 5)
      if !isEditing { underline.transform = CATransform3DMakeScale(120.0 / 180.0, 1, 1) }
    }
  }

  /// The field's own focus: the underline widens and turns mustard.
  fileprivate func editingChanged(_ editing: Bool) {
    isEditing = editing
    if editing { valueOnFocus = field.stringValue }
    restyle()
    let scale = editing ? 1 : 120.0 / 180.0
    OnboardingMotion.animate(underline, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, 1, 1)),
                             duration: appearanceModel.reduceMotion ? 0 : 0.3)
  }

  /// The caret colour and typing attributes go to the field editor once it is attached.
  fileprivate func fieldEditorAttached() {
    applyTypingAttributes()
  }

  func controlTextDidBeginEditing(_ obj: Notification) {
    applyTypingAttributes()
  }

  func controlTextDidChange(_ obj: Notification) {
    field.needsDisplay = true                         // the placeholder shows only while the field is empty
    if field.stringValue.count > OnboardingTheme.maximumNameLength {
      field.stringValue = String(field.stringValue.prefix(OnboardingTheme.maximumNameLength))
    }
    onChange?(field.stringValue)
  }

  /// Escape ends editing and restores the value it had on focus; only a second Escape (with the field no longer
  /// editing) skips. Arrows stay with the field.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.cancelOperation(_:)) {
      field.stringValue = valueOnFocus
      onRestore?(valueOnFocus)
      var ancestor = superview
      while let view = ancestor, !(view is OnboardingView) { ancestor = view.superview }
      window?.makeFirstResponder(ancestor)
      return true
    }
    return false
  }
}

/// The name text field; tells its owner when the field editor takes and gives back focus.
@MainActor
final class NameTextField: NSTextField {
  weak var owner: SpaceNameField?

  override class var cellClass: AnyClass? {
    get { NameFieldCell.self }
    set {}
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func becomeFirstResponder() -> Bool {
    owner?.editingChanged(true)                      // before the field editor attaches
    let became = super.becomeFirstResponder()
    if became { owner?.fieldEditorAttached() } else { owner?.editingChanged(false) }
    return became
  }

  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    owner?.editingChanged(false)
  }
}

// MARK: - Space preview

/// A true-colour preview of the first Space (section 6.3, 340 x 196, radius 14): the theme gradient, the sidebar
/// with three Favorites, the Space title and rows, and a page. The gradient crossfades in 0.28 s (M6). Hidden from
/// VoiceOver: the name field and the theme name say what it shows.
@MainActor
final class SpacePreviewView: NSView {
  private let gradient = CAGradientLayer()
  private let dots = (0..<3).map { _ in CALayer() }
  private let favorites = (0..<3).map { _ in CALayer() }
  private let rows = (0..<3).map { _ in CALayer() }
  private let page = CALayer()
  private let nameLayer = CALayer()
  private var theme = SpaceThemeCatalog.defaultFamily.light
  private var name = ""

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    gradient.masksToBounds = true
    gradient.borderWidth = 1
    gradient.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
    layer?.addSublayer(gradient)
    for sublayer in dots + favorites + rows + [nameLayer, page] { gradient.addSublayer(sublayer) }
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.45
    layer?.shadowRadius = 24
    layer?.shadowOffset = CGSize(width: 0, height: -14)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func configure(theme: SpaceThemeInfo, name: String, animated: Bool) {
    self.theme = theme
    self.name = name
    let colors = theme.baseColors.map(\.cgColor)
    OnboardingMotion.animate(gradient, "colors", to: colors.count > 1 ? colors : colors + colors,
                             duration: animated ? 0.28 : 0)
    let dark = theme.isDark
    let chrome1 = dark ? NSColor(srgbRed: 250 / 255, green: 251 / 255, blue: 1, alpha: 0.1)
      : NSColor(srgbRed: 14 / 255, green: 15 / 255, blue: 16 / 255, alpha: 0.07)
    let chrome2 = dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.16)
    let current = dark ? NSColor(srgbRed: 250 / 255, green: 251 / 255, blue: 1, alpha: 0.2)
      : NSColor.white.withAlphaComponent(0.85)
    let text = dark ? NSColor.white.withAlphaComponent(0.76) : NSColor.black.withAlphaComponent(0.64)
    let pageColor = dark ? NSColor(srgbRed: 0x1E / 255, green: 0x1F / 255, blue: 0x21 / 255, alpha: 1) : .white
    let label = NSAttributedString(string: name, attributes: [
      .font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: text,
    ])
    let size = BrandTextRenderer.measure(label, maxWidth: 78)
    let image = BrandTextRenderer.image(label, size: NSSize(width: min(size.width, 78), height: size.height), halo: [])
    let update = {
      self.dots.forEach { $0.backgroundColor = chrome2.cgColor }
      self.favorites.forEach { $0.backgroundColor = chrome1.cgColor }
      self.rows.enumerated().forEach { $1.backgroundColor = ($0 == 0 ? current : chrome1).cgColor }
      self.page.backgroundColor = pageColor.cgColor
      BrandTextRenderer.apply(image, to: self.nameLayer, glyphSize: NSSize(width: min(size.width, 78), height: size.height),
                              halo: false, scale: self.window?.backingScaleFactor ?? 2)
    }
    if animated {
      CATransaction.begin()
      CATransaction.setAnimationDuration(0.28)
      update()
      CATransaction.commit()
    } else {
      OnboardingMotion.set(update)
    }
  }

  override func layout() {
    super.layout()
    let s = bounds.width / 340
    OnboardingMotion.set {
      gradient.frame = bounds
      gradient.cornerRadius = 14 * s
      layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14 * s, cornerHeight: 14 * s, transform: nil)
      for (index, dot) in dots.enumerated() {
        dot.frame = CGRect(x: (10 + CGFloat(index) * 12) * s, y: 10 * s, width: 7 * s, height: 7 * s)
        dot.cornerRadius = 3.5 * s
      }
      let tileWidth = (80 - 8) / 3 * s
      for (index, tile) in favorites.enumerated() {
        tile.frame = CGRect(x: 8 * s + CGFloat(index) * (tileWidth + 4 * s), y: 30 * s, width: tileWidth,
                            height: 18 * s)
        tile.cornerRadius = 5 * s
      }
      nameLayer.position = CGPoint(x: 10 * s, y: 58 * s)
      for (index, row) in rows.enumerated() {
        row.frame = CGRect(x: 8 * s, y: (72 + CGFloat(index) * 16) * s, width: 80 * s, height: 13 * s)
        row.cornerRadius = 4 * s
      }
      page.frame = CGRect(x: 100 * s, y: 6 * s, width: bounds.width - 106 * s, height: bounds.height - 12 * s)
      page.cornerRadius = 7 * s
      page.borderWidth = 0.5
      page.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
    }
  }
}

/// Draws and edits the name at the font's own line height from the top of the field, so the frame alone places the
/// baseline (the default cell lays a display-size single line out above its frame).
final class NameFieldCell: NSTextFieldCell {
  /// Drawn by the cell itself, so the field editor never draws one of its own.
  var placeholder: NSAttributedString?
  private func lineRect(_ rect: NSRect) -> NSRect {
    guard let font else { return rect }
    let height = ceil(font.ascender - font.descender + font.leading)
    return NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(height, rect.height))
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect { lineRect(super.drawingRect(forBounds: rect)) }
  override func titleRect(forBounds rect: NSRect) -> NSRect { lineRect(super.titleRect(forBounds: rect)) }

  override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                     event: NSEvent?) {
    super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
               event: event)
  }

  override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                       start selStart: Int, length selLength: Int) {
    super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                 start: selStart, length: selLength)
  }

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    drawInterior(withFrame: cellFrame, in: controlView)
  }

  /// The value when not editing; the placeholder whenever the value is empty, editing or not (the field editor
  /// draws the typed text).
  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    guard let field = controlView as? NSTextField else { return }
    let editing = field.currentEditor() != nil
    let empty = (editing ? (field.currentEditor()?.string ?? "") : stringValue).isEmpty
    let text = empty ? placeholder : (editing ? nil : attributedStringValue)
    text?.draw(with: titleRect(forBounds: cellFrame), options: [.usesLineFragmentOrigin])
  }
}
