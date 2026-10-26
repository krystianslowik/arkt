import AppKit
import EngineAPI
import os

/// One open Peek: a tab with no sidebar row (BH-152) shown over the tab it came from.
public struct PeekSession: Equatable, Sendable {
  public enum Phase: Equatable, Sendable { case opening, open, dragging, closing, expanding }
  public let tab: TabID
  public let source: TabID
  public var url: URL
  /// The clicked link from the card's center, in points; the open grows from it and a close returns to it.
  public var linkOffset: CGVector
  public var phase: Phase
}

/// How a Peek is closed (BH-149): each keeps the source tab as it was.
public enum PeekCloseKind: Equatable, Sendable {
  /// The Close control.
  case control
  /// A click on the scrim, or on another pane of a split.
  case scrim
  /// Esc or Cmd-W: in place, almost at once.
  case keyboard
  /// A drag released past the threshold.
  case fling(velocity: Double)
}

/// Peek for one shell window (docs/design/peek.md, #313): decides link activations, opens the Peek over the source
/// tab, closes it each way, opens it as a Today tab or adds it to a Split View. The page's view moves into the
/// content card or a pane only at the end, at rest.
@MainActor
public final class PeekController {
  static let logger = Logger(subsystem: ShellSignposts.subsystem, category: "peek")
  unowned let shell: ShellWindowController
  public private(set) var session: PeekSession?
  public private(set) var overlay: PeekOverlayView?
  let animator = PeekAnimator(scene: .rest)
  /// Reduce Motion, read when a transition starts. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Settings > Links. The app reads its defaults suite; the default reads the standard defaults.
  public var linkSettings: @MainActor () -> PeekLinkSettings = { PeekLinkSettings(defaults: .standard) }
  /// Accessibility announcements (tests record them).
  var announce: @MainActor (String, NSView) -> Void = { text, element in
    NSAccessibility.post(element: element, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }
  private var observation: EngineObservation?
  private var mouseMonitor: Any?
  /// The last left mouse down in the window: where a clicked link probably was.
  private var lastMouseDown: (point: CGPoint, time: TimeInterval)?
  /// The views that recede under the Peek (the source card, a pane card, or the whole split).
  private var receded: [NSView] = []
  private var dragOrigin = 0.0
  /// Source tabs whose last link the engine opens in a new tab itself, with the time it was answered (#345).
  private var engineOpens: [TabID: TimeInterval] = [:]

  public var isOpen: Bool { session != nil }

  init(shell: ShellWindowController) {
    self.shell = shell
    animator.onFrame = { [weak self] scene in self?.present(scene) }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      MainActor.assumeIsolated { self?.mouseDown(event) }
      return event
    }
  }

  /// The window closed: no monitor, no observation, and no display link left running.
  func invalidate() {
    if animator.isRunning { animator.jump(to: animator.currentScene) }
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    mouseMonitor = nil
    observation = nil
  }

  // MARK: - Link activations

  /// The engine asks before it navigates. Answers without calling the engine; a Peek or a new tab opens after the
  /// call returns.
  public func decide(_ activation: EngineLinkActivation) -> EngineLinkDecision {
    let source = activation.sourceTab
    guard source == session?.tab || shownTabs.contains(source) else { return .navigate }
    let point = linkPoint()
    switch PeekRouting.route(activation, section: section(of: source), settings: linkSettings()) {
    case .navigate:
      // A modified click the engine opens itself (Command-Shift: a foreground tab) must not be taken for a
      // `target=_blank` tab of the same source when that tab arrives (#345).
      if activation.disposition != .currentTab { engineOpens[source] = ProcessInfo.processInfo.systemUptime }
      return .navigate
    case .peek:
      DispatchQueue.main.async { [weak self] in self?.open(activation.url, from: source, at: point) }
      return .cancel
    case .newTab:
      DispatchQueue.main.async { [weak self] in self?.openTodayTab(activation.url, from: source) }
      return .cancel
    }
  }

  private var shownTabs: Set<TabID> {
    Set(shell.visibleNodes.compactMap { shell.engineTab(of: $0) } + (shell.currentTab.map { [$0] } ?? []))
  }

  func section(of tab: TabID) -> PeekSourceSection {
    if tab == session?.tab { return .peek }
    guard let node = shell.nodeByTab[tab] else { return .other }
    switch shell.sidebar.section(containing: node) {
    case .pinned?: return .pinned
    case .favorites?: return .favorites
    case .today?: return .today
    default: return .other
    }
  }

  private func mouseDown(_ event: NSEvent) {
    guard event.window === shell.window else { return }
    lastMouseDown = (event.locationInWindow, event.timestamp)
    // A click on another pane of a split closes a Peek that covers only the source pane.
    let root = shell.rootView
    guard let overlay, let geometry = overlay.geometry, session?.phase != .closing, !root.split.isHidden else { return }
    let point = root.convert(event.locationInWindow, from: nil)
    if root.split.frame.contains(point), overlay.hitTest(point) == nil, !geometry.coverage.contains(point) {
      close(.scrim)
    }
  }

  /// The clicked link in root view coordinates, when a click came just before the activation.
  private func linkPoint() -> CGPoint? {
    guard let last = lastMouseDown, ProcessInfo.processInfo.systemUptime - last.time < 2 else { return nil }
    return shell.rootView.convert(last.point, from: nil)
  }

  // MARK: - Open

  /// Opens `url` in a Peek over `source`. A second request for the same source while one is open replaces its URL
  /// without restarting the open.
  public func open(_ url: URL, from source: TabID, at point: CGPoint? = nil) {
    guard shell.window != nil else { return }
    if let session {
      if session.source == source, session.phase == .opening || session.phase == .open {
        shell.engine.navigate(session.tab, to: url)
        self.session?.url = url
        return
      }
      teardown(closingTab: true)
    }
    let tab = shell.engine.createTab(url: url, in: shell.ensureEngineWindow())
    if !present(tab, url: url, from: source, at: point) { shell.engine.closeTab(tab, mode: .skipUnloadHandlers) }
  }

  /// A tab the engine opened on its own from `snapshot.opener` (#345: a `target=_blank` link, `window.open` without
  /// window features) becomes the Peek when the link rules say so: the engine's tab itself, with its page, history and
  /// opener, never a second load. True when it did; the window then adds no row for it.
  func adoptOpenedTab(_ snapshot: TabSnapshot) -> Bool {
    guard shell.window != nil, let source = snapshot.opener, shownTabs.contains(source), source != session?.tab else {
      return false
    }
    if let answered = engineOpens.removeValue(forKey: source),
       ProcessInfo.processInfo.systemUptime - answered < Self.engineOpenWindow { return false }
    let route = PeekRouting.routeOpenedTab(url: snapshot.url, openerURL: shell.engine.snapshot(of: source)?.url,
                                           section: section(of: source), isActive: snapshot.isActive,
                                           settings: linkSettings())
    guard route == .peek, let url = snapshot.url else { return false }
    let point = linkPoint()
    if session != nil { teardown(closingTab: true) }
    guard present(snapshot.id, url: url, from: source, at: point) else { return false }
    Self.logger.notice("peek adopted an engine tab")
    return true
  }

  /// How long a link the engine opens itself is remembered for its source. [I]
  static let engineOpenWindow: TimeInterval = 2

  /// Shows `tab` in a new Peek over `source`. False when the tab has no page to show.
  private func present(_ tab: TabID, url: URL, from source: TabID, at point: CGPoint?) -> Bool {
    guard let page = shell.engine.contentView(for: tab) else { return false }
    let overlay = makeOverlay()
    overlay.card.mount(page)
    let geometry = overlay.geometry ?? PeekLayout.compute(content: shell.rootView.card.frame)
    let offset = point.map { CGVector(dx: $0.x - geometry.card.midX, dy: $0.y - geometry.card.midY) } ?? .zero
    session = PeekSession(tab: tab, source: source, url: url, linkOffset: offset, phase: .opening)
    refreshSplitControl()
    observe()
    let reduce = reduceMotion()
    animator.jump(to: PeekMotion.openStart(linkOffset: offset, reduceMotion: reduce))
    animator.run(PeekMotion.targets(for: .open, reduceMotion: reduce), label: "open", in: overlay) { [weak self] done in
      guard done, self?.session?.phase == .opening else { return }
      self?.session?.phase = .open
    }
    shell.activateEngineTab(tab)
    shell.engine.focusPage(of: tab)
    refreshAccessibility()
    shell.refreshAddress()
    let title = shell.engine.snapshot(of: tab)?.title ?? ""
    announce(title.isEmpty ? "Peek opened" : "Peek opened, \(title)", overlay.card)
    return true
  }

  private func makeOverlay() -> PeekOverlayView {
    let root = shell.rootView
    let overlay = PeekOverlayView(frame: root.bounds)
    overlay.autoresizingMask = [.width, .height]
    overlay.flavor = shell.toasts.view?.flavor ?? .light
    overlay.geometryProvider = { [weak self] _ in self?.currentGeometry() ?? PeekLayout.compute(content: .zero) }
    overlay.onScrimClick = { [weak self] in self?.close(.scrim) }
    overlay.onOpenAsTab = { [weak self] in self?.openAsTab() }
    overlay.onEscape = { [weak self] in _ = self?.handleEscape(in: nil) }
    overlay.card.onCancel = { [weak self] in
      guard let self, self.session != nil else { return false }
      self.close(.keyboard)
      return true
    }
    overlay.closeButton.target = self
    overlay.closeButton.action = #selector(closeControl(_:))
    overlay.expandButton.target = self
    overlay.expandButton.action = #selector(expandControl(_:))
    overlay.splitButton.target = self
    overlay.splitButton.action = #selector(splitControl(_:))
    overlay.dragHandle.onBegan = { [weak self] in self?.dragBegan() }
    overlay.dragHandle.onChanged = { [weak self] offset in self?.dragChanged(offset) }
    overlay.dragHandle.onEnded = { [weak self] offset, velocity in self?.dragEnded(offset, velocity: velocity) }
    root.addSubview(overlay, positioned: .below, relativeTo: root.sidebarOverlay)
    self.overlay = overlay
    receded = recedingViews()
    overlay.setGeometry(currentGeometry())
    return overlay
  }

  /// The Peek's geometry now: over the source pane when it is a pane of the shown split at least 600 pt wide.
  func currentGeometry() -> PeekGeometry {
    let root = shell.rootView
    let content = root.card.frame
    guard !root.split.isHidden, let pane = sourcePaneCard() else { return PeekLayout.compute(content: content) }
    return PeekLayout.compute(content: content, sourcePane: root.convert(pane.frame, from: root.split))
  }

  private func sourcePaneCard() -> ContentCardView? {
    guard let session, let node = shell.nodeByTab[session.source],
          let index = shell.splitState.panes.firstIndex(of: node) else { return nil }
    let cards = shell.rootView.split.paneCards
    return cards.indices.contains(index) ? cards[index] : nil
  }

  private func recedingViews() -> [NSView] {
    let root = shell.rootView
    guard !root.split.isHidden else { return [root.card] }
    let geometry = currentGeometry()
    if let pane = sourcePaneCard(), geometry.coverage != root.card.frame { return [pane] }
    return [root.split]
  }

  // MARK: - Frames

  private func present(_ scene: PeekScene) {
    overlay?.apply(scene)
    let scale = CGFloat(scene[.recede])
    for view in receded { setScale(view, scale) }
  }

  /// Scale about the view's center, whatever the layer's anchor point (AppKit uses the origin).
  private func setScale(_ view: NSView, _ scale: CGFloat) {
    guard let layer = view.layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if scale == 1 {
      layer.transform = CATransform3DIdentity
    } else {
      let size = layer.bounds.size
      let dx = size.width / 2 - layer.anchorPoint.x * size.width
      let dy = size.height / 2 - layer.anchorPoint.y * size.height
      var t = CATransform3DMakeTranslation(dx, dy, 0)
      t = CATransform3DScale(t, scale, scale, 1)
      layer.transform = CATransform3DTranslate(t, -dx, -dy, 0)
    }
    CATransaction.commit()
  }

  // MARK: - Close

  @objc private func closeControl(_ sender: Any?) { close(.control) }
  @objc private func expandControl(_ sender: Any?) { openAsTab() }
  @objc private func splitControl(_ sender: Any?) { addToSplitView() }

  /// Closes the Peek (BH-149). The source tab is left as it was and gets the focus back at once.
  public func close(_ kind: PeekCloseKind) {
    guard var session, let overlay, session.phase != .closing, session.phase != .expanding else { return }
    Self.logger.notice("peek close \(String(describing: kind), privacy: .public)")
    session.phase = .closing
    self.session = session
    let transition: PeekTransition = switch kind {
    case .control, .scrim: .close(linkOffset: session.linkOffset)
    case .keyboard: .closeInPlace
    case .fling(let velocity): .fling(velocity: velocity)
    }
    restoreSourceFocus()
    animator.run(PeekMotion.targets(for: transition, reduceMotion: reduceMotion()), label: "close", in: overlay) {
      [weak self] done in
      guard done else { return }
      self?.teardown(closingTab: true)
      self?.announceClosed()
    }
  }

  private func announceClosed() {
    guard let root = shell.window?.contentView else { return }
    announce("Peek closed.", root)
  }

  private func restoreSourceFocus() {
    guard let session else { return }
    shell.engine.focusPage(of: session.source)
  }

  /// Removes the Peek now: the overlay goes, the source stands back up, and the Peek's tab closes unless it moved
  /// into the sidebar.
  func teardown(closingTab: Bool) {
    guard let session else { return }
    self.session = nil
    observation = nil
    animator.jump(to: .rest)
    for view in receded { setScale(view, 1) }
    receded = []
    overlay?.card.unmount()
    overlay?.removeFromSuperview()
    overlay = nil
    if closingTab { shell.engine.closeTab(session.tab, mode: .skipUnloadHandlers) }
    if let current = shell.currentTab { shell.activateEngineTab(current) }
    shell.refreshAddress()
  }

  /// The content area no longer shows the source tab (another tab, Space or an empty Space): the Peek goes with it.
  /// It is not kept for a later return (deviation from the design's edge case, follow-up issue).
  func shownTabsDidChange() {
    guard let session, session.phase != .expanding, !shownTabs.contains(session.source) else { return }
    teardown(closingTab: true)
  }

  // MARK: - Keys

  /// An Esc the page did not use (the engine's unhandled key path, or the responder chain): closes the Peek when the
  /// focus is in it. True when it did.
  public func handleEscape(in tab: TabID?) -> Bool {
    Self.logger.notice("peek unhandled Esc (\(tab == nil ? "no tab" : "tab", privacy: .public))")
    guard let session, session.phase != .closing, session.phase != .expanding, let overlay else { return false }
    if let tab, tab != session.tab { return false }
    if tab == nil {
      guard let responder = shell.window?.firstResponder as? NSView, responder.isDescendant(of: overlay.card) else {
        return false
      }
    }
    close(.keyboard)
    return true
  }

  // MARK: - Drag (GS-022)

  private func dragBegan() {
    guard var session, session.phase == .open || session.phase == .opening || session.phase == .dragging else {
      return
    }
    dragOrigin = animator.currentScene[.cardY]
    session.phase = .dragging
    self.session = session
    animator.jump(to: animator.currentScene)
  }

  private func dragChanged(_ offset: Double) {
    guard session?.phase == .dragging else { return }
    animator.jump(to: PeekMotion.dragScene(offset: dragOrigin + offset, reduceMotion: reduceMotion()))
  }

  private func dragEnded(_ offset: Double, velocity: Double) {
    guard var session, session.phase == .dragging, let overlay else { return }
    let total = dragOrigin + offset
    if PeekMotion.releaseDismisses(offset: total, velocity: velocity) {
      session.phase = .open
      self.session = session
      close(.fling(velocity: velocity))
      return
    }
    session.phase = .open
    self.session = session
    animator.run(PeekMotion.targets(for: .snapBack(velocity: velocity), reduceMotion: reduceMotion()),
                 label: "snapback", in: overlay)
  }

  // MARK: - Open as Tab (Cmd-O, BH-148, KB-076)

  /// The Peek becomes a Today tab at the top of Today in the source's Space, selected, with its history.
  public func openAsTab() {
    guard let session, let overlay, session.phase == .open || session.phase == .opening else { return }
    let target = shell.rootView.card.frame
    expand(into: target, overlay: overlay) { [weak self] in self?.commitAsTab() }
  }

  private func expand(into target: CGRect, overlay: PeekOverlayView, commit: @escaping @MainActor () -> Void) {
    session?.phase = .expanding
    let reduce = reduceMotion()
    if !reduce { overlay.beginExpand(to: target) }
    animator.run(PeekMotion.targets(for: .expand, reduceMotion: reduce), label: "expand", in: overlay) { done in
      guard done else { return }
      commit()
    }
  }

  private func commitAsTab() {
    guard let session else { return }
    let (url, title) = pageInfo(session)
    let sourceNode = shell.nodeByTab[session.source]
    guard let space = sourceNode.flatMap({ shell.sidebar.spaceID(containing: $0) }) ?? shell.currentSpace
      ?? shell.createSpace() else {
      teardown(closingTab: true)
      return
    }
    do {
      let node = try shell.sidebar.addTab(url: url, title: title, in: .today(space), at: 0)   // BH-079 top
      adopt(session.tab, as: node)
      teardown(closingTab: false)
      shell.activate(node: node)
      fadeInContent()
    } catch {
      shell.onError?(.addTab, error)
      teardown(closingTab: true)
    }
  }

  /// Reduce Motion: the content takes the page while the Peek is faded out, then fades in.
  private func fadeInContent() {
    guard reduceMotion(), let layer = shell.rootView.showsSplit ? shell.rootView.split.layer
      : shell.rootView.card.layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.20
    fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    layer.add(fade, forKey: "peekFadeIn")
  }

  private func adopt(_ tab: TabID, as node: NodeID) {
    shell.tabsByNode[node] = tab
    shell.nodeByTab[tab] = node
    shell.sidebarController.markLoaded(node: node)
  }

  private func pageInfo(_ session: PeekSession) -> (URL, String) {
    let snapshot = shell.engine.snapshot(of: session.tab)
    let url = snapshot?.url ?? session.url
    let title = snapshot.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? (url.host() ?? url.absoluteString)
    return (url, title)
  }

  // MARK: - Add to Split View (BH-117, BH-148)

  /// The split the source is a pane of is full (BH-116): the control is disabled with "Split View is full".
  public var isSplitFull: Bool {
    guard let session, let node = shell.nodeByTab[session.source],
          case .split(let split)? = shell.sidebar.parent(of: node) else { return false }
    return shell.sidebar.children(of: .split(split)).count >= SplitLayoutInfo.maximumPanes
  }

  private func refreshSplitControl() {
    guard let overlay else { return }
    let full = isSplitFull
    overlay.splitButton.isEnabled = !full && session.flatMap { shell.nodeByTab[$0.source] } != nil
    overlay.splitButton.toolTip = full ? "Split View is full" : "Add to Split View"
    let sourceTitle = session.flatMap { shell.engine.snapshot(of: $0.source)?.title } ?? ""
    overlay.splitButton.setAccessibilityHelp(full ? "Split View is full"
      : sourceTitle.isEmpty ? "Adds this page next to the current tab" : "Adds this page next to \(sourceTitle)")
  }

  /// The source and the Peek become a Split View, the Peek on the right with the focus; a source already in a split
  /// with room gets the Peek as the pane after it.
  public func addToSplitView() {
    guard let session, let overlay, session.phase == .open || session.phase == .opening, !isSplitFull,
          let sourceNode = shell.nodeByTab[session.source] else { return }
    let (target, index) = splitTarget(for: sourceNode)
    expand(into: target, overlay: overlay) { [weak self] in self?.commitToSplit(sourceNode: sourceNode, index: index) }
  }

  /// Where the new pane will be (equal shares, as the split edit makes them) and its index.
  private func splitTarget(for sourceNode: NodeID) -> (CGRect, Int) {
    let root = shell.rootView
    let container = root.split
    let scale = shell.window?.backingScaleFactor ?? 2
    if case .split(let split)? = shell.sidebar.parent(of: sourceNode), case .split(_, let layout)? =
      shell.sidebar.node(split), !container.isHidden {
      let panes = shell.sidebar.children(of: .split(split))
      let index = (panes.firstIndex(of: sourceNode) ?? panes.count - 1) + 1
      let frames = SplitLayout.frames(in: container.bounds, axis: SplitLayout.axis(for: layout.orientation),
                                      factors: SplitLayout.equalShares(panes.count + 1), gap: container.gap,
                                      scale: scale)
      return (root.convert(frames.panes[index], from: container), index)
    }
    let frames = SplitLayout.frames(in: root.card.bounds, axis: .sideBySide, factors: [0.5, 0.5],
                                    gap: container.gap, scale: scale)
    return (root.convert(frames.panes[1], from: root.card), 1)
  }

  private func commitToSplit(sourceNode: NodeID, index: Int) {
    guard let session else { return }
    let (url, title) = pageInfo(session)
    do {
      let added = try shell.sidebar.addToSplit(.new(url: url, title: title), target: sourceNode, at: index,
                                               orientation: .horizontal)
      adopt(session.tab, as: added.pane)
      teardown(closingTab: false)
      shell.activate(node: added.pane)
      fadeInContent()
    } catch {
      shell.onError?(.addPane, error)
      teardown(closingTab: true)
    }
  }

  // MARK: - New Today tab (BH-146, Shift-click inside a Peek)

  private func openTodayTab(_ url: URL, from source: TabID) {
    let node = shell.nodeByTab[source] ?? session.flatMap { shell.nodeByTab[$0.source] }
    guard let space = node.flatMap({ shell.sidebar.spaceID(containing: $0) }) ?? shell.currentSpace else { return }
    if session != nil { teardown(closingTab: true) }
    do {
      let created = try shell.sidebar.addTab(url: url, title: url.host() ?? url.absoluteString, in: .today(space),
                                             at: 0)
      shell.activate(node: created)
    } catch {
      shell.onError?(.addTab, error)
    }
  }

  // MARK: - Engine events

  private func observe() {
    guard let window = shell.engineWindow else { return }
    observation = shell.engine.observe(window: window) { [weak self] event in self?.handle(event) }
  }

  private func handle(_ event: EngineEvent) {
    guard let session else { return }
    switch event {
    case .tabClosed(let tab, _) where tab == session.tab || tab == session.source:
      // The page closed itself, or the source went: the Peek goes at once.
      teardown(closingTab: tab != session.tab)
    case .urlChanged(let tab, let url) where tab == session.tab:
      if let url { self.session?.url = url }
      shell.refreshAddress()
    case .titleChanged(let tab, _) where tab == session.tab:
      refreshAccessibility()
    default:
      break
    }
  }

  /// The URL bars show the Peek's URL while it is open (KB-013, KB-014 act on it).
  var addressOverride: URL? {
    guard let session, session.phase != .closing else { return nil }
    return shell.engine.snapshot(of: session.tab)?.url ?? session.url
  }

  private func refreshAccessibility() {
    guard let session, let overlay else { return }
    let title = shell.engine.snapshot(of: session.tab)?.title ?? ""
    overlay.card.setAccessibilityLabel(title.isEmpty ? "Peek" : "Peek, \(title)")
  }
}
