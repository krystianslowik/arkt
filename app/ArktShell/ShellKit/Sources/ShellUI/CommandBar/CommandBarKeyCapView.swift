import AppKit

/// A key cap: a small rounded label ("tab", the Return glyph, "esc", a letter). 18 pt high in the field row's Esc and
/// the hint strip and on rows; the preview's buttons use 16 (#372).
@MainActor
final class CommandBarKeyCapView: NSView {
  static let height: CGFloat = 18
  private static let minWidth: CGFloat = 18
  private static let horizontalPadding: CGFloat = 5
  private static let cornerRadius: CGFloat = 5

  private(set) var text = ""
  private var flavor: ThemeFlavor = .dark
  private let label = NSTextField(labelWithString: "")
  /// Click handler; nil for a decorative key cap.
  var onClick: (() -> Void)?

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    label.font = .systemFont(ofSize: 10.5, weight: .medium)
    label.alignment = .center
    label.lineBreakMode = .byClipping
    label.cell?.usesSingleLineMode = true
    addSubview(label)
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ text: String, flavor: ThemeFlavor) {
    guard text != self.text || flavor != self.flavor else { return }
    self.text = text
    self.flavor = flavor
    label.stringValue = text
    apply()
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  /// Not an accessibility element unless it is clickable: a key cap beside a caption repeats that caption.
  override func isAccessibilityElement() -> Bool { onClick != nil }

  private func apply() {
    layer?.backgroundColor = ShellTokens.commandBarKeyCap.resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    label.textColor = ShellTokens.commandBarSecondaryText.resolve(flavor).nsColor()
  }

  override var intrinsicContentSize: NSSize { size }

  /// The key cap's size: at least square, wider for a word.
  var size: NSSize {
    let width = ceil(label.fittingSize.width) + 2 * Self.horizontalPadding
    return NSSize(width: max(Self.minWidth, width), height: Self.height)
  }

  override func layout() {
    super.layout()
    let h = ceil(label.fittingSize.height)
    label.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
  }

  override func mouseDown(with event: NSEvent) {
    guard let onClick else { super.mouseDown(with: event); return }
    onClick()
  }

  override func accessibilityPerformPress() -> Bool {
    guard let onClick else { return false }
    onClick()
    return true
  }
}
