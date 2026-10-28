import AppKit

/// A key cap: a small rounded label ("tab", the Return glyph, "esc", a letter). 18 pt high in the field row's Esc and
/// the hint strip and on rows; the preview's buttons use 16 (#372).
@MainActor
final class CommandBarKeyCapView: NSView {
  static let height: CGFloat = 18

  /// 18 pt in the field row, the hint strip and on rows. The preview's buttons use 16 (#372).
  struct Metrics: Equatable {
    var height: CGFloat
    var fontSize: CGFloat
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat
    static let standard = Metrics(height: 18, fontSize: 10.5, cornerRadius: 5, horizontalPadding: 5)
    static let preview = Metrics(height: 16, fontSize: 10, cornerRadius: 4, horizontalPadding: 4)
  }

  /// A key cap drawn on the mustard button: graphite at 14% fill, graphite text, no border.
  enum Tone: Equatable { case neutral, onMustard }

  private(set) var text = ""
  private var flavor: ThemeFlavor = .dark
  private var metrics = Metrics.standard
  private var tone: Tone = .neutral
  private let label = NSTextField(labelWithString: "")
  /// Click handler; nil for a decorative key cap.
  var onClick: (() -> Void)?

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Metrics.standard.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    label.font = .systemFont(ofSize: Metrics.standard.fontSize, weight: .medium)
    label.alignment = .center
    label.lineBreakMode = .byClipping
    label.cell?.usesSingleLineMode = true
    addSubview(label)
    apply()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ text: String, flavor: ThemeFlavor, metrics: Metrics = .standard, tone: Tone = .neutral) {
    guard text != self.text || flavor != self.flavor || metrics != self.metrics || tone != self.tone else { return }
    self.text = text
    self.flavor = flavor
    self.metrics = metrics
    self.tone = tone
    label.stringValue = text
    label.font = .systemFont(ofSize: metrics.fontSize, weight: .medium)
    layer?.cornerRadius = metrics.cornerRadius
    apply()
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  /// Not an accessibility element unless it is clickable: a key cap beside a caption repeats that caption.
  override func isAccessibilityElement() -> Bool { onClick != nil }

  private func apply() {
    switch tone {
    case .neutral:
      layer?.backgroundColor = ShellTokens.commandBarKeyCap.resolve(flavor).cgColor
      layer?.borderWidth = 0.5
      layer?.borderColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
      label.textColor = ShellTokens.commandBarSecondaryText.resolve(flavor).nsColor()
    case .onMustard:
      layer?.backgroundColor = RGBA.srgb(hex: 0x202321, alpha: 0.14).cgColor
      layer?.borderWidth = 0
      label.textColor = BrandTokens.onAccent.resolve(flavor).nsColor()
    }
  }

  override var intrinsicContentSize: NSSize { size }

  /// The key cap's size: at least square, wider for a word.
  var size: NSSize {
    let width = ceil(label.fittingSize.width) + 2 * metrics.horizontalPadding
    return NSSize(width: max(metrics.height, width), height: metrics.height)
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
