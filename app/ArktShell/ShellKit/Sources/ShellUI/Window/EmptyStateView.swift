import AppKit

/// First run (decision 3): fills the content card while the window's profile has no Space. A centered panel with
/// a heading, one line of text, "Import from Arc" (only when Arc data exists) and "New Space". Frames are set in
/// `layout()`; no onboarding beyond this (BH-211 is a later track).
@MainActor
final class EmptyStateView: NSView {
  static let heading = "Welcome to Arkt"                                                  // [I] open question 3
  static let body = "Bring your Spaces, pinned tabs and Archive over, or start fresh."
  private static let panelWidth: CGFloat = 420
  private static let headingSpacing: CGFloat = 8
  private static let buttonsSpacing: CGFloat = 20
  private static let buttonGap: CGFloat = 12

  let headingLabel = NSTextField(labelWithString: EmptyStateView.heading)
  let bodyLabel = NSTextField(wrappingLabelWithString: EmptyStateView.body)
  let importButton = NSButton(title: "Import", target: nil, action: nil)
  let newSpaceButton = NSButton(title: "New Space", target: nil, action: nil)

  var onImport: (@MainActor () -> Void)?
  var onNewSpace: (@MainActor () -> Void)?

  /// "Import from Arc" is shown (and is the default button) only while Arc's sidebar file exists.
  var showsImport = false {
    didSet {
      guard showsImport != oldValue else { return }
      applyImportVisibility()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    headingLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    headingLabel.alignment = .center
    bodyLabel.font = .systemFont(ofSize: 13)
    bodyLabel.textColor = .secondaryLabelColor
    bodyLabel.alignment = .center
    for button in [importButton, newSpaceButton] {
      button.bezelStyle = .push
      button.target = self
    }
    importButton.action = #selector(importPressed(_:))
    newSpaceButton.action = #selector(newSpacePressed(_:))
    for view in [headingLabel, bodyLabel, importButton, newSpaceButton] { addSubview(view) }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.EmptyState.root)
    importButton.setAccessibilityIdentifierWithCell(AXID.EmptyState.importFromArc)
    newSpaceButton.setAccessibilityIdentifierWithCell(AXID.EmptyState.newSpace)
    applyImportVisibility()
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
    let width = min(Self.panelWidth, bounds.width - 32)
    let headingHeight = ceil(headingLabel.intrinsicContentSize.height)
    bodyLabel.preferredMaxLayoutWidth = width
    let bodyHeight = ceil(bodyLabel.fittingSize.height)
    let buttons = [importButton, newSpaceButton].filter { !$0.isHidden }
    let sizes = buttons.map { $0.intrinsicContentSize }
    let buttonsWidth = sizes.reduce(0) { $0 + ceil($1.width) } + CGFloat(max(buttons.count - 1, 0)) * Self.buttonGap
    let buttonHeight = ceil(sizes.map(\.height).max() ?? 0)
    let total = headingHeight + Self.headingSpacing + bodyHeight + Self.buttonsSpacing + buttonHeight
    let left = ((bounds.width - width) / 2).rounded()
    var y = ((bounds.height - total) / 2).rounded()
    headingLabel.frame = NSRect(x: left, y: y, width: width, height: headingHeight)
    y += headingHeight + Self.headingSpacing
    bodyLabel.frame = NSRect(x: left, y: y, width: width, height: bodyHeight)
    y += bodyHeight + Self.buttonsSpacing
    var x = ((bounds.width - buttonsWidth) / 2).rounded()
    for (button, size) in zip(buttons, sizes) {
      button.frame = NSRect(x: x, y: y, width: ceil(size.width), height: buttonHeight)
      x += ceil(size.width) + Self.buttonGap
    }
  }

  /// The visible primary action is the default button (Return): Import when shown, else New Space.
  private func applyImportVisibility() {
    importButton.isHidden = !showsImport
    importButton.keyEquivalent = showsImport ? "\r" : ""
    newSpaceButton.keyEquivalent = showsImport ? "" : "\r"
    needsLayout = true
  }

  @objc private func importPressed(_ sender: Any?) { onImport?() }
  @objc private func newSpacePressed(_ sender: Any?) { onNewSpace?() }
}
