import AppKit

/// An announcement's popover (design/sidebar-banner): a 280 pt panel beside the banner row with the whole title (14
/// semibold), the body (12.5 pt secondary), one neutral action and a quiet Dismiss. A dialog named "What's new". A
/// click on the row opens it and gives it the keyboard; Esc, a click elsewhere, either button, or the notice going
/// away closes it.
@MainActor
final class SidebarBannerPopover: NSObject {
  private(set) var panel: DialogWindow?
  private(set) var contentView: SidebarBannerPopoverView?
  private let container = NSView(frame: .zero)
  private var monitor: Any?
  /// Reduce Motion, read when it opens.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var onAction: (@MainActor () -> Void)?
  var onDismiss: (@MainActor () -> Void)?
  var isShown: Bool { panel != nil }
  private(set) var notice: SidebarNotice?

  isolated deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
    panel?.parent?.removeChildWindow(panel!)
    panel?.orderOut(nil)
  }

  /// Opens beside `row` (the banner's row view) for `notice`.
  func show(_ notice: SidebarNotice, beside row: NSView, flavor: ThemeFlavor, takesKey: Bool = true) {
    hide()
    guard let parent = row.window else { return }
    self.notice = notice
    let view = SidebarBannerPopoverView(notice: notice, flavor: flavor)
    view.onAction = { [weak self] in self?.hide(); self?.onAction?() }
    view.onDismiss = { [weak self] in self?.hide(); self?.onDismiss?() }
    contentView = view
    let size = NSSize(width: SidebarBannerMetrics.popoverWidth, height: view.preferredHeight)
    view.frame = NSRect(origin: .zero, size: size)
    view.autoresizingMask = [.width, .height]
    let window = DialogWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = true
    window.appearance = SidebarBannerPopoverView.appearance(for: flavor)
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel("What's new")
    window.setAccessibilityIdentifier(AXID.SidebarBanner.popover)
    container.subviews.forEach { $0.removeFromSuperview() }
    container.frame = NSRect(origin: .zero, size: size)
    container.wantsLayer = true
    container.layer?.cornerRadius = SidebarBannerMetrics.popoverCorner
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    container.layer?.backgroundColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(flavor).cgColor
    container.addSubview(view)
    window.contentView = container
    window.onEscape = { [weak self] in self?.hide(); return true }
    panel = window
    window.setFrame(Self.frame(for: size, beside: row), display: false)
    parent.addChildWindow(window, ordered: .above)
    window.orderFront(nil)
    if takesKey {
      window.makeKey()
      window.makeFirstResponder(nil)                // keys go in; no button shows a ring until Tab moves to it
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated { self?.mouseDown(in: event.window, at: event.locationInWindow, row: row) }
      return event
    }
    playAppearance()
  }

  /// Beside the sidebar, `popoverGap` right of the row, its bottom on the row's bottom; kept inside the parent window.
  static func frame(for size: NSSize, beside row: NSView) -> NSRect {
    guard let window = row.window else { return NSRect(origin: .zero, size: size) }
    let anchor = window.convertToScreen(row.convert(row.bounds, to: nil))
    var origin = NSPoint(x: anchor.maxX + SidebarBannerMetrics.popoverGap, y: anchor.minY)
    let parent = window.frame
    origin.x = min(origin.x, max(parent.minX + 8, parent.maxX - size.width - 8))
    origin.y = min(max(origin.y, parent.minY + 8), max(parent.minY + 8, parent.maxY - size.height - 8))
    return NSRect(origin: origin, size: size)
  }

  func hide() {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    guard let window = panel else { return }
    panel = nil
    contentView = nil
    notice = nil
    let parent = window.parent
    let wasKey = window.isKeyWindow
    parent?.removeChildWindow(window)
    window.orderOut(nil)
    if wasKey { parent?.makeKey() }
  }

  /// A mouse down outside the panel and the row closes it (the row toggles it itself).
  func mouseDown(in window: NSWindow?, at point: NSPoint, row: NSView) {
    guard isShown, window !== panel else { return }
    if window === row.window, row.bounds.contains(row.convert(point, from: nil)) { return }
    hide()
  }

  /// Scale 0.97 to 1 from the corner nearest the row with its fade (Reduce Motion: the fade).
  private func playAppearance() {
    guard let layer = container.layer else { return }
    let step = SidebarBannerMotion.popover(reduceMotion: reduceMotion())
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.duration
    fade.timingFunction = step.curve.timingFunction
    layer.add(fade, forKey: "appear.opacity")
    guard step.scale != 1 else { return }
    let from = DialogMotion.transform(scale: step.scale, offsetY: 0, about: CGPoint(x: 0, y: 0), bounds: layer.bounds,
                                      layerAnchor: layer.anchorPoint)
    let grow = CABasicAnimation(keyPath: "transform")
    grow.fromValue = NSValue(caTransform3D: from)
    grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    grow.duration = step.duration
    grow.timingFunction = step.curve.timingFunction
    layer.add(grow, forKey: "appear.transform")
  }
}

/// The popover's content: title, body, the neutral action and a quiet Dismiss.
@MainActor
final class SidebarBannerPopoverView: NSView {
  var onAction: (@MainActor () -> Void)?
  var onDismiss: (@MainActor () -> Void)?
  let titleLabel: NSTextField
  let bodyLabel: NSTextField
  let actionButton: ArchivePillButton?
  let dismissButton = TokenTitleButton(title: "Dismiss", target: nil, action: nil)

  init(notice: SidebarNotice, flavor: ThemeFlavor) {
    titleLabel = TokenLabel(wrappingLabelWithString: notice.title)
    bodyLabel = TokenLabel(wrappingLabelWithString: notice.body)
    actionButton = notice.actionTitle.map { ArchivePillButton(style: .neutral, title: $0, metrics: .infobar) }
    super.init(frame: .zero)
    // The flavor before any subview joins: the pill restyles for it as it is added, before the panel exists or draws,
    // never once in the app's appearance on screen and again in the panel's.
    appearance = Self.appearance(for: flavor)
    titleLabel.font = .systemFont(ofSize: SidebarBannerMetrics.popoverTitleSize, weight: .semibold)
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    bodyLabel.font = .systemFont(ofSize: SidebarBannerMetrics.popoverBodySize)
    bodyLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    bodyLabel.isHidden = notice.body.isEmpty
    for label in [titleLabel, bodyLabel] {
      label.isSelectable = false
      addSubview(label)
    }
    if let actionButton {
      actionButton.setAccessibilityIdentifierWithCell(AXID.SidebarBanner.popoverAction)
      actionButton.target = self
      actionButton.action = #selector(actionPressed(_:))
      addSubview(actionButton)
    }
    dismissButton.isBordered = false
    dismissButton.bezelStyle = .regularSquare
    dismissButton.attributedTitle = NSAttributedString(string: "Dismiss", attributes: [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: ShellTokens.secondaryText.resolve(flavor).nsColor(),
    ])
    dismissButton.setAccessibilityLabel("Dismiss notice")
    dismissButton.setAccessibilityIdentifierWithCell(AXID.SidebarBanner.popoverDismiss)
    dismissButton.target = self
    dismissButton.action = #selector(dismissPressed(_:))
    addSubview(dismissButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  static func appearance(for flavor: ThemeFlavor) -> NSAppearance? {
    NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
  }

  override var isFlipped: Bool { true }

  private var textWidth: CGFloat { SidebarBannerMetrics.popoverWidth - 2 * SidebarBannerMetrics.popoverPadding }

  private func height(of label: NSTextField) -> CGFloat {
    guard !label.isHidden else { return 0 }
    label.preferredMaxLayoutWidth = textWidth
    return ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 10_000)).height ?? 0)
  }

  private var buttonsHeight: CGFloat { actionButton?.intrinsicContentSize.height ?? 24 }

  /// Padding, title, 4 pt, body, 12 pt, the buttons, padding.
  var preferredHeight: CGFloat {
    let padding = SidebarBannerMetrics.popoverPadding
    let body = height(of: bodyLabel)
    return padding + height(of: titleLabel) + (body > 0 ? 4 + body : 0) + 12 + buttonsHeight + padding
  }

  override func layout() {
    super.layout()
    let padding = SidebarBannerMetrics.popoverPadding
    var y = padding
    let titleHeight = height(of: titleLabel)
    titleLabel.frame = NSRect(x: padding, y: y, width: textWidth, height: titleHeight)
    y += titleHeight
    let bodyHeight = height(of: bodyLabel)
    if bodyHeight > 0 {
      y += 4
      bodyLabel.frame = NSRect(x: padding, y: y, width: textWidth, height: bodyHeight)
      y += bodyHeight
    }
    y += 12
    var x = padding
    if let actionButton {
      let size = actionButton.intrinsicContentSize
      actionButton.frame = NSRect(x: x, y: y, width: min(size.width, textWidth), height: size.height)
      x = actionButton.frame.maxX + 12
    }
    let dismissWidth = ceil(dismissButton.attributedTitle.size().width) + 4
    dismissButton.frame = NSRect(x: x, y: y, width: dismissWidth, height: buttonsHeight)
  }

  @objc private func actionPressed(_ sender: Any?) { onAction?() }
  @objc private func dismissPressed(_ sender: Any?) { onDismiss?() }
}
