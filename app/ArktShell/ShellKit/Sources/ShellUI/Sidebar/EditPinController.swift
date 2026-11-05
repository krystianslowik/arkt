import AppKit
import Motion

/// Runs one Edit Pin popover (#363, design/edit-pin): the form (`EditPinForm`), the view, the keyboard and the
/// writes to the source. Save (or Return in a field) stores a changed name as the node's custom title and a changed
/// address as its pinned URL; the page is not navigated, so Back to Pinned URL then goes to the new address.
/// Escape, Cancel, a click outside and the window resigning key close it without storing anything.
@MainActor
final class EditPinController: NSObject, NSTextFieldDelegate {
  /// What the popover points at, in the host view's coordinates.
  enum Anchor: Equatable {
    /// A pinned row: the arrow on the leading edge touches the row's trailing edge, level with its middle.
    case row(NSRect)
    /// A Favorite tile: the popover opens below it, the arrow on its top edge centered on the tile.
    case tile(NSRect)
  }

  let nodeID: NodeID
  let view: EditPinView
  private(set) var form: EditPinForm
  private let source: any SidebarSource
  private let focus: EditPinFocus
  var reducesMotion: @MainActor () -> Bool
  var announce: AXAnnouncement.Poster
  /// Runs once the popover has closed.
  var onClose: (() -> Void)?
  private var outsideClickMonitor: Any?
  private var resignKeyObserver: (any NSObjectProtocol)?
  private(set) var isClosed = false

  /// Nil when `nodeID` is not a tab.
  init?(nodeID: NodeID, kind: EditPinKind, focus: EditPinFocus, currentPage: URL?, source: any SidebarSource,
        reducesMotion: @escaping @MainActor () -> Bool, announce: @escaping AXAnnouncement.Poster) {
    guard case .tab(_, let url, let title)? = source.node(nodeID) else { return nil }
    self.nodeID = nodeID
    self.source = source
    self.focus = focus
    self.reducesMotion = reducesMotion
    self.announce = announce
    form = EditPinForm(kind: kind, name: title, url: url, currentPage: currentPage ?? url)
    view = EditPinView(nodeID: nodeID, title: form.title)
    super.init()
    view.nameField.stringValue = form.name
    view.urlField.stringValue = form.urlText
    view.nameField.delegate = self
    view.urlField.delegate = self
    view.onCancel = { [weak self] in self?.cancel() }
    for (button, action) in [(view.saveButton, #selector(savePressed(_:))),
                             (view.cancelButton, #selector(cancelPressed(_:))),
                             (view.useCurrentPageButton, #selector(useCurrentPagePressed(_:)))] {
      button.target = self
      button.action = action
    }
  }

  // MARK: Open and close

  /// Adds the popover to `host` pointing at `anchor`, focuses the field the menu item named with its text selected,
  /// and starts watching for clicks outside and the window resigning key.
  func show(in host: NSView, anchor: Anchor) {
    place(in: host, anchor: anchor)
    host.addSubview(view, positioned: .above, relativeTo: nil)
    view.layoutSubtreeIfNeeded()
    let field = focus == .name ? view.nameField : view.urlField
    if host.window?.makeFirstResponder(field) == true { field.currentEditor()?.selectAll(nil) }
    animateOpen()
    outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      MainActor.assumeIsolated { self?.handleOutsideClick(event) }
      return event
    }
    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: host.window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancel() }
    }
  }

  /// Sets the frame and the arrow for `anchor`: the popover keeps its width and stays `windowMargin` inside `host`;
  /// the arrow keeps pointing at the anchor when the body has to move.
  private func place(in host: NSView, anchor: Anchor) {
    let m = EditPinMetrics.self
    let size = view.frame.size
    let hostHeight = host.bounds.height
    /// `rect` with y measured from the top of `host`.
    func fromTop(_ rect: NSRect) -> NSRect {
      host.isFlipped ? rect : NSRect(x: rect.minX, y: hostHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    let maxX = max(host.bounds.width - size.width - m.windowMargin, m.windowMargin)
    let maxTop = max(hostHeight - size.height - m.windowMargin, m.windowMargin)
    let origin: NSPoint
    switch anchor {
    case .row(let rect):
      let row = fromTop(rect)
      let x = min(row.maxX + m.arrowDepth, maxX)
      let top = min(max(row.midY - m.arrowCenter, m.windowMargin), maxTop)
      let lowest = m.cornerRadius + m.arrowHalfBase
      view.setArrow(.leading(y: min(max(row.midY - top, lowest), size.height - lowest)))
      origin = NSPoint(x: x, y: top)
    case .tile(let rect):
      let tile = fromTop(rect)
      let x = min(max(tile.midX - size.width / 2, m.windowMargin), maxX)
      let top = min(tile.maxY + m.arrowDepth + m.anchorGap, maxTop)
      let lowest = m.cornerRadius + m.arrowHalfBase
      view.setArrow(.top(x: min(max(tile.midX - x, lowest), size.width - lowest)))
      origin = NSPoint(x: x, y: top)
    }
    let y = host.isFlipped ? origin.y : hostHeight - origin.y - size.height
    view.frame = NSRect(x: origin.x, y: y, width: size.width, height: size.height)
    // Stays level with its anchor when the window resizes: the margin below the popover is the flexible one.
    view.autoresizingMask = host.isFlipped ? [.maxYMargin] : [.minYMargin]
  }

  func handleOutsideClick(_ event: NSEvent) {
    guard !isClosed, let host = view.superview else { return }
    guard event.window === host.window else { return cancel() }
    if view.frame.contains(host.convert(event.locationInWindow, from: nil)) { return }
    cancel()
  }

  /// Closes without storing anything.
  func cancel() { close(animated: true) }

  /// Closes the popover (a 0.15 s fade when `animated`) and gives the keyboard back to the window.
  func close(animated: Bool) {
    guard !isClosed else { return }
    isClosed = true
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
    if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
    resignKeyObserver = nil
    view.nameField.delegate = nil
    view.urlField.delegate = nil
    let window = view.window
    // A field's editing session belongs to the field editor, whose delegate is the field.
    let responder = window?.firstResponder
    if let owner = ((responder as? NSText)?.delegate as? NSView) ?? (responder as? NSView),
       owner.isDescendant(of: view) {
      window?.makeFirstResponder(nil)
    }
    defer { onClose?() }
    guard animated, let layer = view.layer, window != nil else {
      view.removeFromSuperview()
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [view] in
      MainActor.assumeIsolated { view.removeFromSuperview() }
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = EditPinMotion.closeDuration
    fade.timingFunction = MotionCurve.strongEaseOut.timingFunction
    view.alphaValue = 0
    layer.add(fade, forKey: EditPinMotion.closeKey)
    CATransaction.commit()
  }

  /// Scale 0.97 to 1 from the arrow's tip on `firm`, fading in over 0.22 s; Reduce Motion fades only (0.15 s).
  private func animateOpen() {
    guard let layer = view.layer else { return }
    if reducesMotion() {
      layer.add(Self.fade(duration: EditPinMotion.reducedOpenDuration, curve: .systemEaseOut),
                forKey: EditPinMotion.openFadeKey)
      return
    }
    let tip = view.convertToLayer(view.arrowTip)
    let scale = EditPinMotion.openScale
    let from = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-tip.x, -tip.y, 0),
                                                       CATransform3DMakeScale(scale, scale, 1)),
                                   CATransform3DMakeTranslation(tip.x, tip.y, 0))
    let parameters = SpringPreset.firm.parameters
    let grow = CASpringAnimation(keyPath: "transform")
    grow.mass = CGFloat(parameters.mass)
    grow.stiffness = CGFloat(parameters.stiffness)
    grow.damping = CGFloat(parameters.damping)
    grow.fromValue = NSValue(caTransform3D: from)
    grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    grow.duration = max(parameters.settlingDuration(), grow.settlingDuration)
    layer.add(grow, forKey: EditPinMotion.openScaleKey)
    layer.add(Self.fade(duration: EditPinMotion.openDuration, curve: .strongEaseOut),
              forKey: EditPinMotion.openFadeKey)
  }

  private static func fade(duration: CFTimeInterval, curve: MotionCurve) -> CABasicAnimation {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = curve.timingFunction
    return fade
  }

  // MARK: Actions

  @objc private func savePressed(_ sender: Any?) { save() }
  @objc private func cancelPressed(_ sender: Any?) { cancel() }

  @objc private func useCurrentPagePressed(_ sender: Any?) {
    form.useCurrentPage()
    view.urlField.stringValue = form.urlText
    showError(false)
  }

  /// Save or Return: stores what changed and closes, or shows the invalid address line and stays open.
  func save() {
    guard !isClosed else { return }
    form.edit(name: view.nameField.stringValue)
    let typed = view.urlField.stringValue
    if typed != form.urlText { form.edit(urlText: typed) }
    switch form.submit() {
    case .invalid:
      showError(true)
      if let window = view.window, view.urlField.currentEditor() == nil { window.makeFirstResponder(view.urlField) }
      view.urlField.currentEditor()?.selectAll(nil)
    case .save(let name, let url):
      if let url { source.updateTab(nodeID, url: url, title: nil) }
      if let name { source.renameNode(nodeID, to: name) }
      close(animated: true)
    }
  }

  /// Shows or hides the invalid address line: the popover grows by the line and the line fades in, announced to
  /// VoiceOver; with Reduce Motion the popover takes its new height at once and the line still fades.
  private func showError(_ shown: Bool) {
    guard view.errorLine.isHidden == shown else { return }
    let height = EditPinMetrics.height(showingError: shown)
    var frame = view.frame
    if let host = view.superview, !host.isFlipped { frame.origin.y = frame.maxY - height }
    frame.size.height = height
    view.setErrorShown(shown)
    view.frame = frame
    view.layoutSubtreeIfNeeded()
    guard shown else { return }
    if !reducesMotion(), let layer = view.errorLine.layer {
      layer.add(Self.fade(duration: EditPinMotion.errorDuration, curve: .strongEaseOut), forKey: "editPin.error")
    }
    announce(EditPinForm.invalidAddressMessage, .high)
  }

  // MARK: NSTextFieldDelegate

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField else { return }
    if field === view.urlField {
      form.edit(urlText: field.stringValue)
      showError(false)
    } else {
      form.edit(name: field.stringValue)
    }
  }

  /// Return saves and Escape cancels from inside a field, where the window's key handling does not see them.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      save()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      cancel()
      return true
    default:
      return false
    }
  }

  /// The source changed: the node going away closes the popover.
  func sourceDidChange() {
    if !isClosed, source.node(nodeID) == nil { close(animated: false) }
  }
}
