import AppKit

/// Fills the content card of a window whose shown page moved to another window (Tab Handoff, #300, BH-066): one line
/// of text and a button that moves the page back. The wording and look are [I] until the design pass; selecting the
/// row again does the same as the button.
@MainActor
final class HandoffPlaceholderView: NSView {
  static let message = "This tab is open in another window."                             // [I]
  static let moveHereTitle = "Move Here"                                                 // [I]
  private static let spacing: CGFloat = 16

  let messageLabel = NSTextField(labelWithString: HandoffPlaceholderView.message)
  let moveHereButton = NSButton(title: HandoffPlaceholderView.moveHereTitle, target: nil, action: nil)

  /// The row whose page left; the button asks for it again.
  var node: NodeID?
  var onMoveHere: (@MainActor (NodeID) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    messageLabel.font = .systemFont(ofSize: 13)
    messageLabel.textColor = .secondaryLabelColor
    messageLabel.alignment = .center
    moveHereButton.bezelStyle = .push
    moveHereButton.target = self
    moveHereButton.action = #selector(moveHerePressed(_:))
    addSubview(messageLabel)
    addSubview(moveHereButton)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(Self.message)
    setAccessibilityIdentifier(AXID.Handoff.placeholder)
    moveHereButton.setAccessibilityIdentifierWithCell(AXID.Handoff.moveHere)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
  }

  override func layout() {
    super.layout()
    let label = messageLabel.intrinsicContentSize
    let button = moveHereButton.intrinsicContentSize
    let labelWidth = min(ceil(label.width) + 4, max(bounds.width - 32, 0))   // the field's inset
    let total = ceil(label.height) + Self.spacing + ceil(button.height)
    var y = ((bounds.height - total) / 2).rounded()
    messageLabel.frame = NSRect(x: ((bounds.width - labelWidth) / 2).rounded(), y: y,
                                width: labelWidth, height: ceil(label.height))
    y += ceil(label.height) + Self.spacing
    moveHereButton.frame = NSRect(x: ((bounds.width - ceil(button.width)) / 2).rounded(), y: y,
                                  width: ceil(button.width), height: ceil(button.height))
  }

  @objc private func moveHerePressed(_ sender: Any?) {
    guard let node else { return }
    onMoveHere?(node)
  }
}
