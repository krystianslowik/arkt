import AppKit
import EngineAPI

/// One window's downloads popover (design/downloads, direction B): a panel over the page, above the Library button.
/// A click on the button toggles it; resting the pointer on the button for 0.4 s shows it too, and it goes when the
/// pointer has left both for a moment. Esc, a click elsewhere or choosing Show Library closes it and gives focus back to
/// the button. The panel never takes focus unless it is clicked, so a download that starts never steals the keyboard.
///
/// The state is one `Phase` (#877, #878). Everything one show creates (the panel, its view and pointer tracker, the
/// click monitor and the model observation) is a `Session` that lives only in the open phases, and closing tears it
/// down, so no show leaves anything behind for the next one. Every event goes through `send(_:)`.
@MainActor
final class DownloadsPopoverController: NSObject {
  /// What one show owns. Dropped as a whole when the popover closes.
  @MainActor
  final class Session {
    let panel: DialogWindow
    let container: NSView
    let view: DownloadsPopoverView
    let tracker: PointerTracker
    let monitor: Any?
    let observation: DownloadsObservation

    init(panel: DialogWindow, container: NSView, view: DownloadsPopoverView, tracker: PointerTracker, monitor: Any?,
         observation: DownloadsObservation) {
      self.panel = panel
      self.container = container
      self.view = view
      self.tracker = tracker
      self.monitor = monitor
      self.observation = observation
    }
  }

  enum Phase {
    case closed
    /// The pointer rests on the button; the timer shows the popover after the hover delay.
    case showPending(Timer)
    case open(Session, pointerInside: Bool)
    /// The pointer left the button and the panel; the timer closes the popover after the grace.
    case leavePending(Session, Timer)
  }

  enum Event: Equatable {
    case buttonPressed
    case buttonHover(Bool)
    case pointerInPanel(Bool)
    case timerFired
    case show(takesKey: Bool)
    case hide(keyboard: Bool)
  }

  /// The phase without its payload, for tests and the transition log.
  enum PhaseName: Equatable {
    case closed, showPending, open(pointerInside: Bool), leavePending
  }

  struct Transition: Equatable {
    let from: PhaseName
    let event: Event
    let to: PhaseName
  }

  let model: DownloadsModel
  private(set) var phase: Phase = .closed
  private weak var button: LibraryButton?
  /// Reduce Motion, read when the popover opens (tests set it).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var onShowLibrary: (@MainActor () -> Void)?
  var onReview: (@MainActor (DownloadID) -> Void)?

  #if DEBUG
  /// Every event `send` handled, oldest first, for tests (#877). Debug builds only; keeps the last 64.
  private(set) var transitionLog: [Transition] = []
  #endif

  init(model: DownloadsModel, button: LibraryButton) {
    self.model = model
    self.button = button
    super.init()
    button.target = self
    button.action = #selector(buttonPressed(_:))
    button.onHoverChanged = { [weak self] hovered in self?.send(.buttonHover(hovered)) }
  }

  isolated deinit {
    switch phase {
    case .closed: break
    case .showPending(let timer): timer.invalidate()
    case .open(let session, _): detach(session)
    case .leavePending(let session, let timer): timer.invalidate(); detach(session)
    }
  }

  // MARK: Reading the phase

  /// The current show's session, if open. Read-only: tests and the controller read it; only `send` changes it.
  var session: Session? {
    switch phase {
    case .open(let session, _), .leavePending(let session, _): session
    case .closed, .showPending: nil
    }
  }

  var phaseName: PhaseName {
    switch phase {
    case .closed: .closed
    case .showPending: .showPending
    case .open(_, let inside): .open(pointerInside: inside)
    case .leavePending: .leavePending
    }
  }

  var panel: DialogWindow? { session?.panel }
  var contentView: DownloadsPopoverView? { session?.view }
  var pointerInPanel: Bool { if case .open(_, true) = phase { true } else { false } }
  var isShown: Bool { session?.panel.isVisible == true }

  // MARK: Events

  @objc private func buttonPressed(_ sender: Any?) { send(.buttonPressed) }

  /// Shows the popover with the recent downloads. `takesKey`: a click, so the keyboard goes in with it.
  func show(takesKey: Bool) { send(.show(takesKey: takesKey)) }

  func hide(keyboard: Bool) { send(.hide(keyboard: keyboard)) }

  func pointerInPanelChanged(_ inside: Bool) { send(.pointerInPanel(inside)) }

  /// Runs the pending show or close now (tests; the timer calls it too).
  func firePendingTimer() { send(.timerFired) }

  /// A mouse down at `point` in `window`: closes the popover unless it is in the panel or on the button.
  func handleMouseDown(in window: NSWindow?, at point: NSPoint) {
    guard isShown, let button else { return }
    if window === panel { return }
    if window === button.window, button.convert(point, from: nil).x.isFinite,
       button.bounds.contains(button.convert(point, from: nil)) { return }
    send(.hide(keyboard: false))
  }

  /// The one place the phase changes. Pairs not listed change nothing.
  func send(_ event: Event) {
    #if DEBUG
    let from = phaseName
    #endif
    switch (phase, event) {
    case (.closed, .buttonHover(true)):
      phase = .showPending(makeTimer(after: DownloadsMetrics.hoverDelay))
    case (.closed, .buttonPressed):
      open(takesKey: true)
    case (.closed, .show(let takesKey)):
      open(takesKey: takesKey)

    case (.showPending(let timer), .buttonHover(false)), (.showPending(let timer), .hide):
      timer.invalidate()
      phase = .closed
    case (.showPending(let timer), .timerFired):
      timer.invalidate()
      phase = .closed
      if button?.isHovered == true { open(takesKey: false) }
    case (.showPending(let timer), .buttonPressed):
      timer.invalidate()
      phase = .closed
      open(takesKey: true)
    case (.showPending(let timer), .show(let takesKey)):
      timer.invalidate()
      phase = .closed
      open(takesKey: takesKey)

    case (.open(let session, false), .buttonHover(false)):
      phase = .leavePending(session, makeTimer(after: DownloadsMetrics.leaveGrace))
    case (.open(let session, _), .pointerInPanel(let inside)):
      if inside || button?.isHovered == true {
        phase = .open(session, pointerInside: inside)
      } else {
        phase = .leavePending(session, makeTimer(after: DownloadsMetrics.leaveGrace))
      }
    case (.open(let session, _), .buttonPressed):
      close(session, keyboard: false)
    case (.open(let session, _), .hide(let keyboard)):
      close(session, keyboard: keyboard)

    case (.leavePending(let session, let timer), .buttonHover(true)):
      timer.invalidate()
      phase = .open(session, pointerInside: false)
    case (.leavePending(let session, let timer), .pointerInPanel(true)):
      timer.invalidate()
      phase = .open(session, pointerInside: true)
    case (.leavePending(let session, let timer), .timerFired):
      timer.invalidate()
      if button?.isHovered == true {
        phase = .open(session, pointerInside: false)
      } else {
        close(session, keyboard: false)
      }
    case (.leavePending(let session, let timer), .buttonPressed):
      timer.invalidate()
      close(session, keyboard: false)
    case (.leavePending(let session, let timer), .hide(let keyboard)):
      timer.invalidate()
      close(session, keyboard: keyboard)

    default:
      return
    }
    #if DEBUG
    transitionLog.append(Transition(from: from, event: event, to: phaseName))
    if transitionLog.count > 64 { transitionLog.removeFirst(transitionLog.count - 64) }
    #endif
  }

  /// The timer of a pending phase. It fires only while its phase is current; a timer from an earlier phase does
  /// nothing even if it was not invalidated.
  private func makeTimer(after delay: TimeInterval) -> Timer {
    Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] timer in
      // The Timer itself cannot cross into the main-actor closure under Swift 6 region checking ("sending 'timer'
      // risks causing data races"), so its identity does.
      let fired = ObjectIdentifier(timer)
      MainActor.assumeIsolated {
        guard let self, let pending = self.pendingTimer, ObjectIdentifier(pending) == fired else { return }
        self.send(.timerFired)
      }
    }
  }

  private var pendingTimer: Timer? {
    switch phase {
    case .showPending(let timer), .leavePending(_, let timer): timer
    case .closed, .open: nil
    }
  }

  // MARK: Opening and closing

  /// Builds a session and moves to `open`. Only called from `send` while closed.
  private func open(takesKey: Bool) {
    guard let button, let parent = button.window else { return }
    let view = DownloadsPopoverView(frame: .zero)
    view.reduceMotion = reduceMotion
    view.onAction = { [weak self] action, id in self?.perform(action, id) }
    view.onShowLibrary = { [weak self] in self?.hide(keyboard: true); self?.onShowLibrary?() }
    view.onClear = { [weak self] in self?.model.clearList() }
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
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    container.wantsLayer = true
    container.layer?.cornerRadius = DownloadsMetrics.popoverCorner
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    view.autoresizingMask = [.width, .height]
    container.addSubview(view)
    let tracker = PointerTracker(frame: container.bounds)
    tracker.autoresizingMask = [.width, .height]
    tracker.onChange = { [weak self] inside in self?.send(.pointerInPanel(inside)) }
    container.addSubview(tracker, positioned: .below, relativeTo: nil)
    window.contentView = container
    window.onEscape = { [weak self] in self?.hide(keyboard: true); return true }
    restyle(container)
    window.setFrame(frame(for: size, anchoredTo: button), display: false)
    parent.addChildWindow(window, ordered: .above)
    window.orderFront(nil)
    if takesKey { window.makeKey() }
    let session = Session(panel: window, container: container, view: view, tracker: tracker,
                          monitor: installMonitor(), observation: model.addObserver { [weak self] _ in self?.modelChanged() })
    phase = .open(session, pointerInside: false)
    playAppearance(on: container)
  }

  /// Leaves `session` and moves to `closed`: the panel fades out (at once for the keyboard or under Reduce Motion), and
  /// with it go the view and the tracker.
  private func close(_ session: Session, keyboard: Bool) {
    phase = .closed
    let window = session.panel
    let wasKey = window.isKeyWindow
    detach(session)
    let leave = { @MainActor in
      window.parent?.removeChildWindow(window)
      window.orderOut(nil)
      session.view.removeFromSuperview()
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

  /// Stops everything in `session` that reacts to the user or the model: the click monitor, the observation and the
  /// pointer tracker, which leaves the view tree at once.
  private func detach(_ session: Session) {
    if let monitor = session.monitor { NSEvent.removeMonitor(monitor) }
    session.observation.cancel()
    session.tracker.onChange = nil
    session.tracker.removeFromSuperview()
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

  // MARK: Updating

  private func modelChanged() {
    guard let session, let button else { return }
    let changed = session.view.reload(model.recent(limit: DownloadsMetrics.recentLimit), canClear: canClear)
    guard changed else { return }
    let size = NSSize(width: DownloadsMetrics.popoverWidth, height: session.view.preferredHeight)
    var frame = session.panel.frame
    frame.size = size
    frame.origin = self.frame(for: size, anchoredTo: button).origin
    session.panel.setFrame(frame, display: true)
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

  /// A click anywhere outside the panel and the button closes it.
  private func installMonitor() -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouseDown(in: event.window, at: event.locationInWindow) }
      return event
    }
  }

  // MARK: Motion

  private func restyle(_ container: NSView) {
    let flavor = container.archiveFlavor
    container.layer?.backgroundColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(flavor).cgColor
  }

  /// Scale 0.97 to 1 from the corner nearest the button, with a 0.22 s fade (Reduce Motion: the fade, 0.15 s).
  private func playAppearance(on container: NSView) {
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

  /// The entrance animations on the open panel's layer, for tests.
  var entranceAnimations: [String: CABasicAnimation] {
    guard let layer = session?.container.layer else { return [:] }
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
