import AppKit

/// The Return key cap on the selected row (design/command-bar/README.md, Layout): 20 high, 5 radius, 11 medium,
/// `commandBarKeyCap` fill with a hairline. Decorative: the row's verb says what it does.
@MainActor
final class CommandBarKeyCapView: NSView {
  static let fontSize: CGFloat = 11
  static let horizontalPadding: CGFloat = 5

  private(set) var text = ""
  private var flavor: ThemeFlavor = .dark
  private let label = NSTextField(labelWithString: "")

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = CommandBarGeometry.keyCapRadius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    label.font = .systemFont(ofSize: Self.fontSize, weight: .medium)
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

  override func isAccessibilityElement() -> Bool { false }

  private func apply() {
    layer?.backgroundColor = ShellTokens.commandBarKeyCap.resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    label.textColor = ShellTokens.commandBarSecondaryText.resolve(flavor).nsColor()
  }

  override var intrinsicContentSize: NSSize { size }

  /// Square for one glyph (the Return cap is 20 x 20); wider for a word.
  var size: NSSize {
    let height = CommandBarGeometry.keyCapHeight
    guard text.count > 1 else { return NSSize(width: height, height: height) }
    return NSSize(width: max(height, ceil(label.fittingSize.width) + 2 * Self.horizontalPadding), height: height)
  }

  override func layout() {
    super.layout()
    let h = ceil(label.fittingSize.height)
    label.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
  }
}
