import AppKit
import EngineAPI

/// One window's downloads popover (design/downloads, direction B): a panel over the page, above the Library button.
/// A click on the button toggles it; resting the pointer on the button for 0.4 s shows it too, and it goes when the
/// pointer has left both for a moment. Esc, a click elsewhere or choosing Show Library closes it and gives focus back to
/// the button. The panel never takes focus unless it is clicked, so a download that starts never steals the keyboard.
@MainActor
final class DownloadsPopoverController: NSObject {
  let model: DownloadsModel
  private(set) var panel: DialogWindow?
  private(set) var contentView: DownloadsPopoverView?
  private let container = NSView(frame: .zero)
  private weak var button: LibraryButton?
  private var observation: DownloadsObservation?
  private var timer: Timer?
  private var pendingAction: (@MainActor () -> Void)?
  private var monitor: Any?
  private(set) var pointerInPanel = false
  private var tracking: NSTrackingArea?
  /// Reduce Motion, read when the popover opens (tests set it).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var onShowLibrary: (@MainActor () -> Void)?
  var onReview: (@MainActor (DownloadID) -> Void)?
  /// The key handler a row's Retry and the others run through the model; Review goes to `onReview`.
  var isShown: Bool { panel?.isVisible == true }

  init(model: DownloadsModel, button: LibraryButton) {
    self.model = model
    self.button = button
    super.init()
    button.target = self
    button.action = #selector(buttonPressed(_:))
    button.onHoverChanged = { [weak self] hovered in self?.buttonHoverChanged(hovered) }
  }

  isolated deinit {
    timer?.invalidate()
    if let monitor { NSEvent.removeMonitor(monitor) }
  }

  // MARK: Opening

  @objc private func buttonPressed(_ sender: Any?) {
    if isShown { hide(keyboard: false) } else { show(takesKey: true) }
  }

  /// Shows the popover with the recent downloads. `takesKey`: a click, so the keyboard goes in with it.
  func show(takesKey: Bool) {
    guard !isShown, let button, let parent = button.window else { return }
    let view = DownloadsPopoverView(frame: .zero)
    view.reduceMotion = reduceMotion
    view.onAction = { [weak self] action, id in self?.perform(action, id) }
    view.onShowLibrary = { [weak self] in self?.hide(keyboard: true); self?.onShowLibrary?() }
    view.onClear = { [weak self] in self?.model.clearList() }
    contentView = view
    view.reload(model.recent(limit: DownloadsMetrics.recentLimit), canClear: canClear)
    let size = NSSize(width: DownloadsMetrics.popoverWidth, height: view.preferredHeight)
    view.frame = NSRect(origin: .zero, size: size)
    let window = DialogWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = true
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel("Downloads")
    container.frame = NSRect(origin: .zero, size: size)
    container.wantsLayer = true
    container.layer?.cornerRadius = DownloadsMetrics.popoverCorner
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    view.autoresizingMask = [.width, .height]
    container.addSubview(view)
    window.contentView = container
    window.onEscape = { [weak self] in self?.hide(keyboard: true); return true }
    panel = window
    restyleContainer()
    window.setFrame(frame(for: size, anchoredTo: button), display: false)
    parent.addChildWindow(window, ordered: .above)
    window.orderFront(nil)
    if takesKey { window.makeKey() }
    installTracking()
    installMonitor()
    observation = model.addObserver { [weak self] _ in self?.modelChanged() }
    playAppearance()
  }

  /// The panel's frame: left edge on the button's, `popoverGap` above it, kept inside the window.
  private func frame(for size: NSSize, anchoredTo button: LibraryButton) -> NSRect {
    let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
    var origin = NSPoint(x: anchor.minX - 6, y: anchor.maxY + DownloadsMetrics.popoverGap)
    if let parent = button.window?.frame {
      origin.x = min(max(origin.x, parent.minX + 8), max(parent.minX + 8, parent.maxX - size.width - 8))
    }
    return NSRect(origin: origin, size: size)
  }

  private var canClear: Bool { model.items.contains { $0.state.isFinished && !$0.dangerType.needsSheet } }

  func hide(keyboard: Bool) {
    cancelTimer()
    guard let window = panel else { return }
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    observation?.cancel()
    observation = nil
    pointerInPanel = false
    let wasKey = window.isKeyWindow
    panel = nil
    contentView = nil
    let leave = { @MainActor in
      window.parent?.removeChildWindow(window)
      window.orderOut(nil)
    }
    if keyboard || reduceMotion() || window.parent == nil {
      leave()
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = DownloadsMotion.popoverExitDuration
        window.animator().alphaValue = 0
      }, completionHandler: { MainActor.assumeIsolated { leave() } })
    }
    if wasKey || keyboard { button?.window?.makeFirstResponder(button) }
  }

  // MARK: Updating

  private func modelChanged() {
    guard let view = contentView, let panel, let button else { return }
    let changed = view.reload(model.recent(limit: DownloadsMetrics.recentLimit), canClear: canClear)
    guard changed else { return }
    let size = NSSize(width: DownloadsMetrics.popoverWidth, height: view.preferredHeight)
    var frame = panel.frame
    frame.size = size
    frame.origin = self.frame(for: size, anchoredTo: button).origin
    panel.setFrame(frame, display: true)
  }

  private func perform(_ action: DownloadRowAction, _ id: DownloadID) {
    switch action {
    case .cancel: model.cancel(id)
    case .open: model.open(id)
    case .showInFinder: model.showInFinder(id)
    case .retry: model.retry(id)
    case .remove: model.remove(id)
    case .keep: model.keep(id)
    case .discard: model.discard(id)
    case .review:
      hide(keyboard: true)
      onReview?(id)
    }
  }

  // MARK: Hover

  /// The pointer entered or left the Library button.
  private func buttonHoverChanged(_ hovered: Bool) {
    if hovered {
      guard !isShown else { cancelTimer(); return }       // back on the button before the grace ran out
      schedule(after: DownloadsMetrics.hoverDelay) { [weak self] in
        guard let self, self.button?.isHovered == true, !self.isShown else { return }
        self.show(takesKey: false)
      }
    } else if isShown, !pointerInPanel {
      scheduleLeave()
    } else if !isShown {
      cancelTimer()
    }
  }

  func pointerInPanelChanged(_ inside: Bool) {
    pointerInPanel = inside
    if inside { cancelTimer() } else if isShown, button?.isHovered != true { scheduleLeave() }
  }

  private func scheduleLeave() {
    schedule(after: DownloadsMetrics.leaveGrace) { [weak self] in
      guard let self, !self.pointerInPanel, self.button?.isHovered != true else { return }
      self.hide(keyboard: false)
    }
  }

  private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
    cancelTimer()
    pendingAction = action
    timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.firePendingTimer() }
    }
  }

  /// Runs the pending show or close now (tests; the timer calls it too).
  func firePendingTimer() {
    timer?.invalidate()
    timer = nil
    let action = pendingAction
    pendingAction = nil
    action?()
  }

  private func cancelTimer() {
    timer?.invalidate()
    timer = nil
    pendingAction = nil
  }

  private func installTracking() {
    let tracker = PointerTracker(frame: container.bounds)
    tracker.autoresizingMask = [.width, .height]
    tracker.onChange = { [weak self] inside in self?.pointerInPanelChanged(inside) }
    container.addSubview(tracker, positioned: .below, relativeTo: nil)
  }

  /// A click anywhere outside the panel and the button closes it.
  private func installMonitor() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouseDown(in: event.window, at: event.locationInWindow) }
      return event
    }
  }

  /// A mouse down at `point` in `window`: closes the popover unless it is in the panel or on the button.
  func handleMouseDown(in window: NSWindow?, at point: NSPoint) {
    guard isShown, let button else { return }
    if window === panel { return }
    if window === button.window, button.convert(point, from: nil).x.isFinite,
       button.bounds.contains(button.convert(point, from: nil)) { return }
    hide(keyboard: false)
  }

  // MARK: Motion

  private func restyleContainer() {
    let flavor = container.archiveFlavor
    container.layer?.backgroundColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(flavor).cgColor
  }

  /// Scale 0.97 to 1 from the corner nearest the button, with a 0.22 s fade (Reduce Motion: the fade, 0.15 s).
  private func playAppearance() {
    guard let layer = container.layer else { return }
    layer.removeAnimation(forKey: "appear.opacity")
    layer.removeAnimation(forKey: "appear.transform")
    let step = DownloadsMotion.popoverAppears(reduceMotion: reduceMotion())
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.duration
    fade.timingFunction = step.curve.timingFunction
    layer.add(fade, forKey: "appear.opacity")
    guard step.scale != 1 else { return }
    let bounds = layer.bounds
    let from = DialogMotion.transform(scale: step.scale, offsetY: 0, about: CGPoint(x: 0, y: 0), bounds: bounds,
                                      layerAnchor: layer.anchorPoint)
    let grow = CABasicAnimation(keyPath: "transform")
    grow.fromValue = NSValue(caTransform3D: from)
    grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    grow.duration = step.duration
    grow.timingFunction = step.curve.timingFunction
    layer.add(grow, forKey: "appear.transform")
  }

  /// The entrance animations on the panel's layer, for tests.
  var entranceAnimations: [String: CABasicAnimation] {
    guard let layer = container.layer else { return [:] }
    var found: [String: CABasicAnimation] = [:]
    for key in layer.animationKeys() ?? [] { found[key] = layer.animation(forKey: key) as? CABasicAnimation }
    return found
  }
}

/// Reports the pointer entering and leaving the panel.
@MainActor
final class PointerTracker: NSView {
  var onChange: (@MainActor (Bool) -> Void)?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }
  override func mouseEntered(with event: NSEvent) { onChange?(true) }
  override func mouseExited(with event: NSEvent) { onChange?(false) }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
