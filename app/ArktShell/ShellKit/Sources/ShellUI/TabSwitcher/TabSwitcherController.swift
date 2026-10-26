import AppKit

/// One window's Ctrl-Tab switcher (BH-007 to BH-012, KB-022 to KB-025): the recent-tab list, the open session and
/// the panel. `ShellWindow.sendEvent` hands it every key, flags and mouse-down event before anything else, so a page
/// can never take Ctrl-Tab, and the window controller wires the closures that read and change the sidebar.
@MainActor
public final class TabSwitcherController {
  public let view = TabSwitcherView(frame: .zero)
  public private(set) var recent = RecentTabs()
  public private(set) var session: TabSwitcherSession?
  public var isOpen: Bool { session != nil }
  /// Whether the panel's first frame after the key-down was presented. A Ctrl release before that commits without
  /// any visible UI (the flick, BH-007), so the panel is hidden without a fade.
  public private(set) var hasPresented = false
  /// Read when the highlight or a closed row would move; the view follows the same switch.
  public var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { view.reduceMotion = reduceMotion }
  }

  /// The tab current in the window (a split's focused pane).
  var currentNode: @MainActor () -> NodeID? = { nil }
  /// What a row shows; nil leaves the tab out (it is gone from the sidebar).
  var row: @MainActor (NodeID) -> TabSwitcherRow? = { _ in nil }
  /// The flavor of the window's current Space.
  var flavor: @MainActor () -> ThemeFlavor = { .light }
  /// Ctrl released: show this tab.
  var onCommit: @MainActor (NodeID) -> Void = { _ in }
  /// W: close this tab the way Cmd-W closes it.
  var onClose: @MainActor (NodeID) -> Void = { _ in }

  private var rows: [TabSwitcherRow] = []
  /// The tab current when the switcher opened; if another path changes it, the switcher cancels.
  private var openedOn: NodeID?
  private var presentationLink: CADisplayLink?

  public init() {
    view.reduceMotion = reduceMotion
  }

  /// `node` became the window's current tab.
  public func noteViewed(_ node: NodeID) {
    recent.noteViewed(node)
    if isOpen, node != openedOn { cancel(announce: false) }
  }

  /// Ctrl-Cmd-Right / Left (BH-013): the next tab of the recent-tab cycle, without an overlay.
  public func cycleTarget(forward: Bool) -> NodeID? {
    recent.cycle(forward: forward, current: currentNode())
  }

  /// The sidebar changed: tabs that left it leave the list, and an open switcher collapses their rows as if they
  /// were closed with W.
  public func sourceDidChange() {
    recent.prune { self.row($0) != nil }
    guard let session else { return }
    if let openedOn, row(openedOn) == nil {
      cancel(announce: false)
      return
    }
    for node in session.rows where row(node) == nil { removeRow(node) }
  }

  /// The window stopped being key: the switcher cancels.
  public func windowDidResignKey() {
    if isOpen { cancel(announce: false) }
  }

  // MARK: Events

  /// Takes the events the switcher handles and returns true when the event must go no further. A Ctrl release
  /// commits and still goes on (it is only a modifier change); a key the switcher does not use dismisses it and goes
  /// on to be handled as usual.
  public func handle(_ event: NSEvent) -> Bool {
    if isOpen, currentNode() != openedOn { cancel(announce: false) }
    switch event.type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      return handleMouseDown(event)
    default:
      break
    }
    switch TabSwitcherKeys.action(for: event, isOpen: isOpen) {
    case .pass:
      return false
    case .open(let direction):
      open(direction)
      return true
    case .move(let direction):
      move(direction)
      return true
    case .closeHighlighted:
      closeHighlighted()
      return true
    case .cancel:
      cancel(announce: true)
      return true
    case .commit:
      commit()
      return false
    case .dismissThenPass:
      cancel(announce: false)
      return false
    }
  }

  /// A click on a row lands on it; a click anywhere else cancels and goes on.
  private func handleMouseDown(_ event: NSEvent) -> Bool {
    guard let session, event.window === view.window else { return false }
    let point = view.convert(event.locationInWindow, from: nil)
    if let index = view.row(at: point), index < session.rows.count {
      commit(session.rows[index])
      return true
    }
    cancel(announce: false)
    return false
  }

  // MARK: Actions

  /// Ctrl-Tab or Ctrl-Shift-Tab. With fewer than two viewed tabs nothing opens (and the key is still taken, so it
  /// does not beep or reach the page).
  func open(_ direction: TabSwitcherSession.Direction) {
    let current = currentNode()
    recent.prune { self.row($0) != nil }
    let candidates = recent.previous(excluding: current, limit: TabSwitcherSession.maximumRows)
    let filled = candidates.compactMap { row($0) }
    guard let session = TabSwitcherSession(rows: filled.map(\.node), direction: direction),
          let container = view.superview else { return }
    self.session = session
    rows = filled
    openedOn = current
    hasPresented = false
    view.show(rows: rows, highlight: session.highlight, flavor: flavor(),
              frame: panelFrame(rows: rows.count, in: container.bounds))
    trackPresentation()
    let count = rows.count
    announce("Recent tabs, \(count) \(count == 1 ? "tab" : "tabs")")
    announceHighlightedRow()
  }

  func move(_ direction: TabSwitcherSession.Direction) {
    guard var session else { return }
    session.move(direction)
    self.session = session
    view.setHighlight(index: session.highlight, animated: true)
    announceHighlightedRow()
  }

  /// W (BH-010): the highlighted tab closes and its row collapses; the switcher stays open while rows remain.
  func closeHighlighted() {
    guard let session else { return }
    let node = session.highlighted
    let title = rows.first { $0.node == node }?.title ?? ""
    recent.remove(node)
    removeRow(node)
    announce("Closed \(title)")
    if isOpen { announceHighlightedRow() }
    onClose(node)
  }

  /// Ctrl released: the highlighted tab becomes current.
  func commit() {
    guard let session else { return }
    commit(session.highlighted)
  }

  private func commit(_ node: NodeID) {
    close(animated: hasPresented)
    onCommit(node)
  }

  /// Esc, a click outside, another key, or a lost key window: the current tab stays.
  func cancel(announce: Bool) {
    guard isOpen else { return }
    close(animated: hasPresented)
    if announce { self.announce("Cancelled") }
  }

  private func close(animated: Bool) {
    session = nil
    rows = []
    openedOn = nil
    stopTrackingPresentation()
    view.dismiss(animated: animated)
  }

  /// Drops `node`'s row; the last row going dismisses the switcher, keeping the current tab.
  private func removeRow(_ node: NodeID) {
    guard var session, let index = session.rows.firstIndex(of: node),
          let closed = rows.first(where: { $0.node == node }) else { return }
    if session.remove(node) {
      cancel(announce: false)
      return
    }
    self.session = session
    rows.removeAll { $0.node == node }
    guard let container = view.superview else { return }
    view.collapse(closed: closed, at: index, rows: rows, highlight: session.highlight,
                  frame: panelFrame(rows: rows.count, in: container.bounds))
  }

  /// Centered horizontally in the window (sidebar included), top edge at 38 % of its height (design "Layout";
  /// PARITY(NEEDS-RUNTIME-CHECK): Arc's size and place).
  func panelFrame(rows: Int, in bounds: NSRect) -> NSRect {
    let width = TabSwitcherView.width
    let height = TabSwitcherView.height(rows: rows)
    return NSRect(x: (bounds.midX - width / 2).rounded(), y: (bounds.minY + bounds.height * 0.38).rounded(),
                  width: width, height: height)
  }

  // MARK: Presentation

  private func trackPresentation() {
    stopTrackingPresentation()
    let target = LinkTarget { [weak self] in self?.didPresent() }
    let link = view.displayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
    link.add(to: .main, forMode: .common)
    presentationLink = link
  }

  private func didPresent() {
    hasPresented = true
    stopTrackingPresentation()
  }

  private func stopTrackingPresentation() {
    presentationLink?.invalidate()
    presentationLink = nil
  }

  // MARK: VoiceOver

  private func announceHighlightedRow() {
    guard let session, session.highlight < view.rowViews.count,
          let label = view.rowViews[session.highlight].accessibilityLabel() else { return }
    announce(label)
  }

  private func announce(_ text: String) {
    NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
      .announcement: text,
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }
}

/// Display link target (the controller is not an NSObject).
@MainActor
private final class LinkTarget: NSObject {
  private let onTick: @MainActor () -> Void
  init(onTick: @escaping @MainActor () -> Void) { self.onTick = onTick }
  @objc func tick(_ link: CADisplayLink) { onTick() }
}
