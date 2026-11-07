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
  private let container = ExtensionsPanelContainer(frame: .zero)
  private var monitor: Any?
  /// Reduce Motion, read when the panel opens and for each drag (tests set it).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Manage Extensions... and the context menu's Manage Extension...: Settings, Extensions.
  public var onManage: (@MainActor () -> Void)?
  /// Browse the Web Store, the empty state's one action.
  public var onBrowseWebStore: (@MainActor () -> Void)?
  /// The context menu's Remove from Arkt...: the window sets it to `presentRemoveSheet(for:)` (#720). While it is nil
  /// the item is disabled.
  public var onRemove: (@MainActor (ExtensionAction) -> Void)?
  /// The remove sheet while it is up.
  public private(set) var removeSheet: ExtensionRemoveSheet?

  public var isShown: Bool { panel?.isVisible == true }

  init(extensions: any EngineExtensions, button: ExtensionsButton,
       engineWindow: @escaping @MainActor () -> EngineWindowID?) {
    self.extensions = extensions
    self.button = button
    self.engineWindow = engineWindow
    super.init()
    container.onAppearanceChange = { [weak self] in self?.restyleContainer() }
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
    // Space or Return on the focused button: the keyboard goes into the first row.
    if isShown { hide(keyboard: false) } else { show(fromKeyboard: NSApp.currentEvent?.type == .keyDown) }
  }

  /// Opens the panel. `fromKeyboard`: the first row (or Browse the Web Store) takes the focus; from a click nothing
  /// does, so no focus ring shows until Tab.
  func show(fromKeyboard: Bool = false) {
    guard !isShown, let button, let parent = button.window else { return }
    let view = ExtensionsPanelView(frame: .zero)
    view.reduceMotion = { [weak self] in self?.reduceMotion() ?? false }
    view.increaseContrast = { [weak self] in self?.increaseContrast() ?? false }
    view.scheduleSettleTimeout = { [weak self] delay, action in
      (self?.schedule ?? ExtensionsPanelController.defaultSchedule)(delay, action)
    }
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
    if fromKeyboard {
      if let first = view.displayedRowIDs.first.flatMap(view.row(for:)) {
        window.makeFirstResponder(first.runButton)
      } else if view.state == .empty {
        window.makeFirstResponder(view.browseButton)
      }
    }
    button.isOpen = true
    installMonitor()
    playAppearance()
  }

  func hide(keyboard: Bool) {
    guard let window = panel else { return }
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
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
    if keyboard { button?.window?.makeFirstResponder(button) }
  }

  /// The engine changed the window's actions (a pin, a move, an install, the active tab): the open panel follows.
  /// The engine window went away (the window closes or waits for its next page): the panel closes instead of showing
  /// the empty state.
  func refresh() {
    closeRemoveSheetIfGone()
    guard let view = contentView, let window = panel, let button, let parent = button.window else { return }
    guard engineWindow() != nil else { hide(keyboard: false); return }
    view.reload(ExtensionsPanelModel(actions: actions))
    place(window, view: view, in: parent, anchoredTo: button)
  }

  // MARK: Remove from Arkt... (#720)

  /// Asks before removing `action`'s extension: the panel closes and the remove sheet hangs from the panel's window,
  /// which it never blocks for other windows. Remove uninstalls through the engine with the Report abuse state; Cancel
  /// and Escape do nothing. Nothing happens while a sheet is already up on the window.
  public func presentRemoveSheet(for action: ExtensionAction) {
    guard removeSheet == nil, let parent = button?.window, parent.attachedSheet == nil else { return }
    hide(keyboard: false)
    let sheet = ExtensionRemoveSheet(action: action)
    let extensionID = sheet.extensionID              // not the sheet: it owns this closure
    sheet.onFinish = { [weak self] reportAbuse in
      guard let self else { return }
      self.removeSheet = nil
      guard let reportAbuse else { return }
      self.extensions?.uninstallExtension(extensionID, reportAbuse: reportAbuse)
    }
    removeSheet = sheet
    sheet.begin(on: parent)
  }

  /// The extension the sheet asks about went away (removed elsewhere, or the engine window closed): the sheet closes
  /// without a call.
  private func closeRemoveSheetIfGone() {
    guard let sheet = removeSheet else { return }
    if engineWindow() != nil, actions.contains(where: { $0.extensionID == sheet.extensionID }) { return }
    closeRemoveSheet()
  }

  /// Closes the remove sheet, if it is up, without a call.
  func closeRemoveSheet() {
    let sheet = removeSheet
    removeSheet = nil
    sheet?.dismiss()
  }

  /// The browser window resized: the panel keeps its place above the bar and its height cap.
  func windowDidResize() {
    guard let view = contentView, let window = panel, let button, let parent = button.window else { return }
    place(window, view: view, in: parent, anchoredTo: button)
  }

  /// The sidebar was hidden or resized. Hidden, the button is gone, so the panel goes too; resized, it moves along.
  func sidebarDidChange(isVisible: Bool) {
    guard isShown else { return }
    if isVisible { windowDidResize() } else { hide(keyboard: false) }
  }

  /// The window enters full screen: its frame and the sidebar move, so the panel closes.
  func windowWillEnterFullScreen() { hide(keyboard: false) }

  /// Increase Contrast, read on each reload (tests set it).
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  /// Runs an action after a delay: the timeout for a drop the engine never answers. Tests replace it with a clock they
  /// step by hand.
  var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = defaultSchedule

  static func defaultSchedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
    Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
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
      let menu = ExtensionContextMenu.menu(
        forAction: id, in: window, engine: extensions,
        onManage: { [weak self] _ in
          self?.hide(keyboard: true)
          self?.onManage?()
        },
        onRemove: { [weak self] action in self?.onRemove?(action) })
      // Remove from Arkt... needs the remove sheet; until the app provides it the item stays disabled.
      if self.onRemove == nil {
        for item in menu?.items ?? [] where item.tag == ExtensionContextCommand.remove.rawValue { item.isEnabled = false }
      }
      return menu
    }
  }

  /// Sizes the panel to its content within the window and puts it above the button's bar, 12 pt in from the sidebar.
  /// In a blank or incognito window the button sits in the sidebar's footer band, so the bar is the sidebar itself.
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

/// The panel's rounded container; it restyles its fill and edge when the appearance changes.
@MainActor
final class ExtensionsPanelContainer: NSView {
  var onAppearanceChange: (@MainActor () -> Void)?
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }
}
