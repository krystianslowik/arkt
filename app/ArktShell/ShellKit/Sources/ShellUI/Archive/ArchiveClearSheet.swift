import AppKit

/// The Clear Archive confirmation (BH-087, design section 6), hosted as a window sheet on the Archive window: the
/// count in the question, a note when filters hide some of what is cleared, Cancel and Clear Archive as neutral pills
/// (Clear Archive in `destructiveText`). Focus starts on Cancel, neither button has the Return key, and Escape
/// cancels.
@MainActor
final class ArchiveClearSheet: NSWindowController {
  static let width: CGFloat = 400
  static let padding: CGFloat = 20

  let titleField = NSTextField(wrappingLabelWithString: "Clear the Archive?")
  let bodyField = NSTextField(wrappingLabelWithString: "")
  let noteField = NSTextField(wrappingLabelWithString: "This includes items hidden by the current filters.")
  let cancelButton = ArchivePillButton(style: .neutral, title: "Cancel")
  let clearButton = ArchivePillButton(style: .destructive, title: "Clear Archive")
  /// Called once with the choice: true for Clear Archive.
  var onFinish: (@MainActor (Bool) -> Void)?

  /// The body for `count` archived items (nil when the count is unknown).
  static func body(count: Int?) -> String {
    switch count {
    case nil: "All archived items are permanently deleted. This cannot be undone."
    case 1?: "The 1 archived item is permanently deleted. This cannot be undone."
    case let count?: "All \(count) archived items are permanently deleted. This cannot be undone."
    }
  }

  init(count: Int?, hiddenByFilters: Bool) {
    let window = ArchiveSheetWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
                                    styleMask: [.titled], backing: .buffered, defer: true)
    super.init(window: window)
    window.onCancel = { [weak self] in self?.finish(false) }
    bodyField.stringValue = Self.body(count: count)
    noteField.isHidden = !hiddenByFilters
    let content = ArchiveSheetContentView(frame: window.contentLayoutRect)
    titleField.font = .systemFont(ofSize: 15, weight: .semibold)
    bodyField.font = .systemFont(ofSize: 13)
    noteField.font = .systemFont(ofSize: 13)
    for field in [titleField, bodyField, noteField] {
      field.isSelectable = false
      content.addSubview(field)
    }
    cancelButton.target = self
    cancelButton.action = #selector(cancelPressed(_:))
    clearButton.target = self
    clearButton.action = #selector(clearPressed(_:))
    clearButton.setAccessibilityIdentifierWithCell(AXID.Archive.clearConfirm)
    content.addSubview(cancelButton)
    content.addSubview(clearButton)
    window.contentView = content
    let height = layout(in: content)
    window.setContentSize(NSSize(width: Self.width, height: height))
    content.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
    _ = layout(in: content)
    window.initialFirstResponder = cancelButton
    cancelButton.nextKeyView = clearButton
    clearButton.nextKeyView = cancelButton
    restyle(content)
    content.onAppearanceChange = { [weak self, weak content] in
      guard let self, let content else { return }
      self.restyle(content)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Shows the sheet on `parent`; `onFinish` reports the choice.
  func begin(on parent: NSWindow) {
    guard let window else { return }
    parent.beginSheet(window) { _ in }
    window.makeFirstResponder(cancelButton)
  }

  private func restyle(_ content: NSView) {
    let flavor = content.archiveFlavor
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    bodyField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    noteField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }

  /// Lays the content out top down and returns its height.
  private func layout(in content: NSView) -> CGFloat {
    let width = Self.width - 2 * Self.padding
    var y = Self.padding
    for field in [titleField, bodyField, noteField] where !field.isHidden {
      let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 400)).height ?? 18)
      field.frame = NSRect(x: Self.padding, y: y, width: width, height: height)
      y += height + (field === titleField ? 10 : 6)
    }
    y += 14
    let clearWidth = clearButton.intrinsicContentSize.width
    let cancelWidth = max(cancelButton.intrinsicContentSize.width, 76)
    clearButton.frame = NSRect(x: Self.width - Self.padding - clearWidth, y: y, width: clearWidth,
                               height: ArchiveMetrics.pillHeight)
    cancelButton.frame = NSRect(x: clearButton.frame.minX - 8 - cancelWidth, y: y, width: cancelWidth,
                                height: ArchiveMetrics.pillHeight)
    return y + ArchiveMetrics.pillHeight + Self.padding
  }

  @objc func cancelPressed(_ sender: Any?) { finish(false) }
  @objc func clearPressed(_ sender: Any?) { finish(true) }

  private func finish(_ confirmed: Bool) {
    guard let window else { return }
    let callback = onFinish
    onFinish = nil
    window.sheetParent?.endSheet(window)
    window.orderOut(nil)
    callback?(confirmed)
  }
}

/// Escape on the sheet cancels.
@MainActor
private final class ArchiveSheetWindow: NSWindow {
  var onCancel: (@MainActor () -> Void)?
  override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
private final class ArchiveSheetContentView: NSView {
  var onAppearanceChange: (@MainActor () -> Void)?
  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func updateLayer() {
    layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(archiveFlavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
    onAppearanceChange?()
  }
}
