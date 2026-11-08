import AppKit
import EngineAPI

/// One window's page info panel (#582, `design/extensions` `surf-pageinfo`, laid out as the Site Control Center
/// direction A it grows into, #651): a 330 pt panel anchored below the address pill, opened from the pill's site glyph
/// (or VoiceOver's Show Site Controls). Height follows the content up to 552 pt and the room below the pill; then the
/// list scrolls with a faded edge. Esc closes it and gives the keyboard back to the window; a mouse down in the browser
/// window outside the panel closes it, as do full screen, the sidebar hiding, another tab or another site, the window
/// no longer being the main window, and the app going to the background.
///
/// Every change goes to the engine (`EngineSiteSettings`) at once, from the panel's tab, and the panel shows what the
/// engine reads back (also on `.pageInfoChanged`, through `pageDidChange`). Opening tells the engine
/// (`pageInfoDidOpen(tab:)`), which counts the site's data only while a panel is open and announces the count when it
/// arrives. Closing tells it too (`pageInfoDidClose(tab:)`), which raises its reload infobar on the page if a change
/// needs one. In a private window the panel is read-only (#557).
@MainActor
public final class PageInfoPanelController: NSObject {
  private let siteSettings: @MainActor () -> (any EngineSiteSettings)?
  private(set) var panel: DialogWindow?
  private(set) var contentView: PageInfoPanelView?
  /// The tab and site the open panel shows.
  public private(set) var tab: TabID?
  private(set) var origin: String?
  private weak var anchor: URLBarView?
  private let container = PageInfoPanelContainer(frame: .zero)
  private var monitor: Any?
  private var windowObservers: [NSObjectProtocol] = []
  /// Reduce Motion and Increase Contrast, read when the panel opens (tests set them).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  /// Where focus goes back to after Esc: the window's page.
  var onReturnFocus: (@MainActor () -> Void)?
  /// Whether the window is private (Incognito, Blank): the panel is then read-only.
  var isReadOnly: @MainActor () -> Bool = { false }
  /// The favicon of a tab's page, for the header badge.
  var favicon: @MainActor (TabID) -> Data? = { _ in nil }
  /// The permissions macOS denies Arkt itself, read each time the panel shows a page (tests set them) (#786).
  var deniedInMacOS: @MainActor () -> Set<SitePermissionKind> = { SystemPermissions.deniedKinds() }

  public var isShown: Bool { panel?.isVisible == true }

  init(siteSettings: @escaping @MainActor () -> (any EngineSiteSettings)?) {
    self.siteSettings = siteSettings
    super.init()
    container.onAppearanceChange = { [weak self] in self?.restyleContainer() }
  }

  isolated deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
    for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
  }

  private func model(for tab: TabID) -> PageInfoModel? {
    siteSettings()?.pageInfo(of: tab).flatMap {
      PageInfoModel($0, isReadOnly: isReadOnly(), favicon: favicon(tab), deniedInMacOS: deniedInMacOS())
    }
  }

  // MARK: Opening

  /// Opens the panel for `tab` below `anchor`, or closes it when it is already up for that tab (the glyph toggles).
  /// Nothing opens for a page of the browser itself. Returns whether the panel is up afterwards.
  @discardableResult
  public func toggle(for tab: TabID, anchoredTo anchor: URLBarView) -> Bool {
    if isShown, self.tab == tab {
      hide(keyboard: false)
      return false
    }
    hide(keyboard: true)
    return show(for: tab, anchoredTo: anchor)
  }

  @discardableResult
  func show(for tab: TabID, anchoredTo anchor: URLBarView) -> Bool {
    guard !isShown, let parent = anchor.window, let model = model(for: tab) else { return false }
    let view = PageInfoPanelView(frame: .zero)
    view.increaseContrast = { [weak self] in self?.increaseContrast() ?? false }
    wire(view)
    contentView = view
    self.tab = tab
    origin = model.origin
    self.anchor = anchor
    siteSettings()?.pageInfoDidOpen(tab: tab)          // the engine counts site data only while the panel is open
    let window = DialogWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                              defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = false
    window.autorecalculatesKeyViewLoop = true
    window.appearance = parent.appearance             // a child window does not inherit the browser window's
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel(model.accessibilityLabel)
    window.setAccessibilityIdentifier(AXID.PageInfo.panel)
    container.wantsLayer = true
    container.layer?.cornerRadius = PageInfoMetrics.corner
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    view.autoresizingMask = [.width, .height]
    container.subviews.forEach { $0.removeFromSuperview() }
    container.addSubview(view)
    window.contentView = container
    window.onEscape = { [weak self] in self?.hide(keyboard: true); return true }
    panel = window
    view.reload(model)
    restyleContainer()
    place(window, view: view, in: parent, anchoredTo: anchor)
    parent.addChildWindow(window, ordered: .above)
    window.orderFront(nil)
    window.makeKey()
    if let first = view.firstControl { window.makeFirstResponder(first) }   // focus starts on the first control
    installMonitor()
    observe(parent)
    playAppearance()
    return true
  }

  public func hide(keyboard: Bool) {
    guard let window = panel else { return }
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    windowObservers = []
    let closedTab = tab
    panel = nil
    contentView = nil
    tab = nil
    origin = nil
    if let closedTab { siteSettings()?.pageInfoDidClose(tab: closedTab) }   // the reload infobar, if a change needs it
    // The panel took the keyboard when it opened; the browser window gets it back.
    if window.isKeyWindow, let parent = window.parent, parent.isVisible { parent.makeKey() }
    let leave = { @MainActor in
      window.parent?.removeChildWindow(window)
      window.orderOut(nil)
    }
    if keyboard || reduceMotion() || window.parent == nil {
      leave()
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = PageInfoMotion.exitDuration
        window.animator().alphaValue = 0
      }, completionHandler: { MainActor.assumeIsolated { leave() } })
    }
    if keyboard { onReturnFocus?() }
  }

  // MARK: Following the page

  /// The window's current tab or its page changed: the panel closes for another tab, another site or a page with no
  /// page info, and shows the new values otherwise.
  public func pageDidChange(currentTab: TabID?) {
    guard isShown, let tab else { return }
    guard currentTab == tab, let model = model(for: tab), model.origin == origin else {
      hide(keyboard: false)
      return
    }
    show(model)
  }

  /// The sidebar was hidden, shown or resized: the pill moved or went, so the panel closes.
  public func sidebarDidChange() { hide(keyboard: false) }

  /// Another window became the main window, or the app went to the background: the panel belongs to this window's
  /// page in front, so it closes.
  func parentDidResignMain() { hide(keyboard: false) }
  func appDidResignActive() { hide(keyboard: false) }

  /// The window enters full screen: its frame and the sidebar move, so the panel closes.
  func windowWillEnterFullScreen() { hide(keyboard: false) }

  /// Reads the page info again after a change and shows it in place.
  private func reread() {
    guard let tab, let model = model(for: tab) else { hide(keyboard: false); return }
    show(model)
  }

  private func show(_ model: PageInfoModel) {
    guard let view = contentView, let window = panel, let anchor, let parent = anchor.window else { return }
    view.reload(model)
    window.setAccessibilityLabel(model.accessibilityLabel)
    place(window, view: view, in: parent, anchoredTo: anchor)
  }

  private func wire(_ view: PageInfoPanelView) {
    view.onSetPermission = { [weak self] kind, setting in
      guard let self, let origin = self.origin, let tab = self.tab, !self.isReadOnly() else { return }
      self.siteSettings()?.setPermission(kind, to: setting, forOrigin: origin, from: tab)
      self.reread()
    }
    view.onResetPermissions = { [weak self] in
      guard let self, let origin = self.origin, let tab = self.tab, !self.isReadOnly() else { return }
      self.siteSettings()?.resetPermissions(forOrigin: origin, from: tab)
      self.reread()
    }
    // Site Settings... and, until #651 brings the data sheet, Cookies and site data: the engine's settings for the
    // site.
    let openSettings: @MainActor () -> Void = { [weak self] in
      guard let self, let origin = self.origin, let tab = self.tab else { return }
      let settings = self.siteSettings()
      self.hide(keyboard: false)
      settings?.openSiteSettings(forOrigin: origin, from: tab)
    }
    view.onSiteSettings = openSettings
    view.onShowSiteData = openSettings
  }

  // MARK: Placement

  /// Sizes the panel to its content within the window and puts it below the pill, its leading edge on the pill's (in
  /// the Toolbar, 14 pt before the glyph so the glyphs line up).
  private func place(_ window: NSWindow, view: PageInfoPanelView, in parent: NSWindow, anchoredTo anchor: URLBarView) {
    let m = PageInfoMetrics.self
    let barRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    let glyphRect = parent.convertToScreen(anchor.convert(anchor.siteGlyph.frame, to: nil))
    let available = parent.frame.width - 2 * m.windowMargin
    let width = PageInfoModel.panelWidth(available: available)
    let top = barRect.minY - m.gap
    let height = PageInfoModel.panelHeight(content: view.preferredHeight(width: width),
                                           available: top - parent.frame.minY - m.windowMargin).height
    let anchorX = anchor.style == .host || anchor.siteGlyph.isHidden ? barRect.minX : glyphRect.minX - m.sideInset
    let x = min(max(anchorX, parent.frame.minX + m.windowMargin), parent.frame.maxX - m.windowMargin - width)
    let frame = NSRect(x: x, y: top - height, width: width, height: height)
    if window.frame != frame { window.setFrame(frame, display: true) }
    container.frame = NSRect(origin: .zero, size: frame.size)
    view.frame = container.bounds
    view.layoutSubtreeIfNeeded()
  }

  private func observe(_ parent: NSWindow) {
    let center = NotificationCenter.default
    windowObservers = [
      center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, let view = self.contentView, let window = self.panel, let anchor = self.anchor,
                let parent = anchor.window else { return }
          self.place(window, view: view, in: parent, anchoredTo: anchor)
        }
      },
      center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: parent,
                         queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.windowWillEnterFullScreen() }
      },
      center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.hide(keyboard: false) }
      },
      center.addObserver(forName: NSWindow.didResignMainNotification, object: parent, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.parentDidResignMain() }
      },
      center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                         queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.appDidResignActive() }
      },
    ]
  }

  // MARK: Dismissal

  private func installMonitor() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouseDown(in: event.window, at: event.locationInWindow) }
      return event
    }
  }

  /// A mouse down at `point` in `window`: closes the panel when it is in the browser window, off the pill's glyph (the
  /// glyph toggles it). A click in the panel, or in another window (a pop-up's menu), leaves it up.
  func handleMouseDown(in window: NSWindow?, at point: NSPoint) {
    guard isShown, let anchor, let window, window === anchor.window else { return }
    if anchor.siteGlyphHitRect.contains(anchor.convert(point, from: nil)) { return }
    hide(keyboard: false)
  }

  // MARK: Motion

  private func restyleContainer() {
    let flavor = container.archiveFlavor
    container.layer?.backgroundColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
    let edge = increaseContrast()
    container.layer?.borderWidth = edge ? 1 : 0.5
    container.layer?.borderColor = (edge ? AlertTokens.increasedContrastEdge : AlertTokens.overlayEdge)
      .resolve(flavor).cgColor
  }

  /// Opacity 0 to 1, scale 0.97 to 1 from the top-leading corner (under the pill) and 4 pt down into place, 0.22 s on
  /// `firmFast`; Reduce Motion: the fade alone, 0.15 s.
  private func playAppearance() {
    guard let layer = container.layer else { return }
    layer.removeAnimation(forKey: "appear.opacity")
    layer.removeAnimation(forKey: "appear.transform")
    let reduced = reduceMotion()
    let duration = reduced ? PageInfoMotion.reducedAppearDuration : PageInfoMotion.appearDuration
    let curve = reduced ? PageInfoMotion.easeOut : PageInfoMotion.firmFast
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = curve
    layer.add(fade, forKey: "appear.opacity")
    guard !reduced else { return }
    // The layer is not flipped: its top-leading corner is at (0, height).
    let from = DialogMotion.transform(scale: PageInfoMotion.appearScale, offsetY: -PageInfoMotion.appearOffset,
                                      about: CGPoint(x: 0, y: layer.bounds.height), bounds: layer.bounds,
                                      layerAnchor: layer.anchorPoint)
    let grow = CABasicAnimation(keyPath: "transform")
    grow.fromValue = NSValue(caTransform3D: from)
    grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    grow.duration = duration
    grow.timingFunction = curve
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

/// The panel's rounded container; it restyles its fill and edge when the appearance changes.
@MainActor
final class PageInfoPanelContainer: NSView {
  var onAppearanceChange: (@MainActor () -> Void)?
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }
}
