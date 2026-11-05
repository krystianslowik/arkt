import AppKit
import EngineAPI

/// One window's Extensions panel (#595, design/extensions direction C): a 316 pt panel over the page, its left edge
/// 12 pt in from the sidebar's and 8 pt above the bottom bar, opened and closed by the Extensions button. Height
/// follows the content, capped by the window (the list then scrolls with a faded edge). Esc closes it and gives the
/// keyboard back to the button; a mouse down in the browser window outside the panel and the button closes it.
/// Clicks in other windows leave it up: clicking a row runs the extension's action anchored to that row, and the
/// engine draws the popup in a window of its own, which must not take its anchor away.
///
/// Every change goes to the engine (`EngineExtensions`); the panel shows what the engine reports back through
/// `.extensionActionsChanged`, so pin state and order are the profile's.
@MainActor
public final class ExtensionsPanelController: NSObject {
  private weak var extensions: (any EngineExtensions)?
  private weak var button: ExtensionsButton?
  private let engineWindow: @MainActor () -> EngineWindowID?
  private(set) var panel: DialogWindow?
  private(set) var contentView: ExtensionsPanelView?
  private let container = NSView(frame: .zero)
  private var monitor: Any?
  /// Reduce Motion, read when the panel opens and for each drag (tests set it).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Manage Extensions... and the context menu's Manage Extension...: Settings, Extensions.
  public var onManage: (@MainActor () -> Void)?
  /// Browse the Web Store, the empty state's one action.
  public var onBrowseWebStore: (@MainActor () -> Void)?
  /// The context menu's Remove from Arkt...: the remove sheet. Nil until it exists.
  public var onRemove: (@MainActor (ExtensionAction) -> Void)?

  public var isShown: Bool { panel?.isVisible == true }

  init(extensions: any EngineExtensions, button: ExtensionsButton,
       engineWindow: @escaping @MainActor () -> EngineWindowID?) {
    self.extensions = extensions
    self.button = button
    self.engineWindow = engineWindow
    super.init()
    button.target = self
    button.action = #selector(buttonPressed(_:))
  }

  isolated deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
  }

  private var actions: [ExtensionAction] {
    guard let extensions, let window = engineWindow() else { return [] }
    return extensions.extensionActions(in: window)
  }

  // MARK: Opening

  @objc private func buttonPressed(_ sender: Any?) {
    if isShown { hide(keyboard: false) } else { show() }
  }

  func show() {
    guard !isShown, let button, let parent = button.window else { return }
    let view = ExtensionsPanelView(frame: .zero)
    view.reduceMotion = { [weak self] in self?.reduceMotion() ?? false }
    wire(view)
    contentView = view
    view.reload(ExtensionsPanelModel(actions: actions))
    let window = DialogWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                              defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = false
    window.autorecalculatesKeyViewLoop = true
    window.appearance = parent.appearance             // a child window does not inherit the browser window's
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel("Extensions")
    container.wantsLayer = true
    container.layer?.cornerRadius = ExtensionsPanelMetrics.corner
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    view.autoresizingMask = [.width, .height]
    container.subviews.forEach { $0.removeFromSuperview() }
    container.addSubview(view)
    window.contentView = container
    window.onEscape = { [weak self] in self?.hide(keyboard: true); return true }
    panel = window
    restyleContainer()
    place(window, view: view, in: parent, anchoredTo: button)
    parent.addChildWindow(window, ordered: .above)
    window.orderFront(nil)
    window.makeKey()                                  // Tab enters the rows; no ring until the keyboard is used
    button.isOpen = true
    installMonitor()
    playAppearance()
  }

  func hide(keyboard: Bool) {
    guard let window = panel else { return }
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    let wasKey = window.isKeyWindow
    panel = nil
    contentView = nil
    button?.isOpen = false
    let leave = { @MainActor in
      window.parent?.removeChildWindow(window)
      window.orderOut(nil)
    }
    if keyboard || reduceMotion() || window.parent == nil {
      leave()
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = ExtensionsPanelMotion.exitDuration
        window.animator().alphaValue = 0
      }, completionHandler: { MainActor.assumeIsolated { leave() } })
    }
    if wasKey || keyboard { button?.window?.makeFirstResponder(button) }
  }

  /// The engine changed the window's actions (a pin, a move, an install, the active tab): the open panel follows.
  func refresh() {
    guard let view = contentView, let window = panel, let button, let parent = button.window else { return }
    view.reload(ExtensionsPanelModel(actions: actions))
    place(window, view: view, in: parent, anchoredTo: button)
  }

  private func wire(_ view: ExtensionsPanelView) {
    view.onRun = { [weak self] action, anchor in
      guard let self, let window = self.engineWindow() else { return }
      self.extensions?.runExtensionAction(action.id, in: window, anchor: anchor)
    }
    view.onSetPinned = { [weak self] id, pinned in self?.extensions?.setExtensionPinned(id, pinned: pinned) }
    view.onMove = { [weak self] id, index in self?.extensions?.movePinnedExtension(id, to: index) }
    view.onManage = { [weak self] in
      self?.hide(keyboard: true)
      self?.onManage?()
    }
    view.onBrowseWebStore = { [weak self] in
      self?.hide(keyboard: true)
      self?.onBrowseWebStore?()
    }
    view.menuProvider = { [weak self] id in
      guard let self, let extensions = self.extensions, let window = self.engineWindow() else { return nil }
      return ExtensionContextMenu.menu(
        forAction: id, in: window, engine: extensions,
        onManage: { [weak self] _ in
          self?.hide(keyboard: true)
          self?.onManage?()
        },
        onRemove: { [weak self] action in self?.onRemove?(action) })
    }
  }

  /// Sizes the panel to its content within the window and puts it above the button's bar, 12 pt in from the sidebar.
  private func place(_ window: NSWindow, view: ExtensionsPanelView, in parent: NSWindow,
                     anchoredTo button: ExtensionsButton) {
    let m = ExtensionsPanelMetrics.self
    parent.contentView?.layoutSubtreeIfNeeded()        // the button's place, after a resize not laid out yet
    let bar = button.superview ?? button
    let barRect = parent.convertToScreen(bar.convert(bar.bounds, to: nil))
    let buttonRect = parent.convertToScreen(button.convert(button.bounds, to: nil))
    let width = ExtensionsPanelModel.panelWidth(windowWidth: parent.frame.width)
    let bottom = buttonRect.maxY + m.gap
    let available = parent.frame.maxY - m.topMargin - bottom
    let height = ExtensionsPanelModel.panelHeight(content: view.preferredHeight(width: width),
                                                  available: available).height
    var x = barRect.minX + m.sidebarInset
    x = min(max(x, parent.frame.minX + m.windowMargin), parent.frame.maxX - m.windowMargin - width)
    let frame = NSRect(x: x, y: bottom, width: width, height: height)
    if window.frame != frame { window.setFrame(frame, display: true) }
    container.frame = NSRect(origin: .zero, size: frame.size)
    view.frame = container.bounds
    view.layoutSubtreeIfNeeded()
  }

  // MARK: Dismissal

  /// A click anywhere outside the panel and the button closes it.
  private func installMonitor() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouseDown(in: event.window, at: event.locationInWindow) }
      return event
    }
  }

  /// A mouse down at `point` in `window`: closes the panel when it is in the browser window, off the button. A click
  /// in the panel, or in any other window (an extension's popup, a menu), leaves it up.
  func handleMouseDown(in window: NSWindow?, at point: NSPoint) {
    guard isShown, let button, let window, window === button.window else { return }
    if button.bounds.contains(button.convert(point, from: nil)) { return }
    hide(keyboard: false)
  }

  // MARK: Motion

  private func restyleContainer() {
    let flavor = container.archiveFlavor
    container.layer?.backgroundColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(flavor).cgColor
  }

  /// Opacity 0 to 1, scale 0.97 to 1 from the corner nearest the button and 4 pt down into place, 0.22 s on
  /// `firmFast`; Reduce Motion: the fade alone, 0.15 s.
  private func playAppearance() {
    guard let layer = container.layer else { return }
    layer.removeAnimation(forKey: "appear.opacity")
    layer.removeAnimation(forKey: "appear.transform")
    let reduced = reduceMotion()
    let duration = reduced ? ExtensionsPanelMotion.reducedAppearDuration : ExtensionsPanelMotion.appearDuration
    let curve = reduced ? ExtensionsPanelMotion.easeOut : ExtensionsPanelMotion.firmFast
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = curve
    layer.add(fade, forKey: "appear.opacity")
    guard !reduced else { return }
    let from = DialogMotion.transform(scale: ExtensionsPanelMotion.appearScale, offsetY: ExtensionsPanelMotion.appearOffset,
                                      about: .zero, bounds: layer.bounds, layerAnchor: layer.anchorPoint)
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
