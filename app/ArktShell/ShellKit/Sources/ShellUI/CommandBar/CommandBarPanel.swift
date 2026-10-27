import AppKit

/// Borderless floating panel hosting the command bar. Created once and reused (pre-warmed).
@MainActor
final class CommandBarPanel: NSPanel {
  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: CommandBarGeometry.preferredWidth,
                                   height: CommandBarGeometry.inputHeight),
               styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
    isFloatingPanel = true
    hidesOnDeactivate = true
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none                     // no system fade: it would eat the 16 ms budget
    collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
    alphaValue = 0
    ignoresMouseEvents = true
  }

  /// The panel stays ordered in once pre-warmed; presenting is alpha plus key status (C7: ordering a
  /// window in cost one to three extra frames in the window server). While hidden it is inert: clicks pass
  /// through, it cannot become key, and accessibility does not report it.
  var isPresented = false {
    didSet {
      guard isPresented != oldValue else { return }
      alphaValue = isPresented ? 1 : 0
      ignoresMouseEvents = !isPresented
      contentView?.setAccessibilityValue(isPresented ? AXID.CommandBar.open : AXID.CommandBar.closed)
    }
  }

  /// Test seam: stands in for the window server's answer, since tests cannot switch Spaces.
  var isOnActiveSpaceOverride: Bool?
  override var isOnActiveSpace: Bool { isOnActiveSpaceOverride ?? super.isOnActiveSpace }

  /// Orderings so far (tests check that a show on the active Space does not reorder).
  private(set) var orderOutCount = 0
  private(set) var orderFrontRegardlessCount = 0

  override func orderOut(_ sender: Any?) {
    orderOutCount += 1
    super.orderOut(sender)
  }

  override func orderFrontRegardless() {
    orderFrontRegardlessCount += 1
    super.orderFrontRegardless()
  }

  /// Sees each key-down before the field editor; returning true consumes it. Used for Cmd-Return and
  /// Opt-Return (KB-085), which have no field editor binding to reach the text field delegate through.
  /// No menu item binds Cmd-Return or Opt-Return, so this hides no menu action
  /// (`MainMenuKeyEquivalentTests` builds the app's main menu and checks).
  var keyDownHandler: ((NSEvent) -> Bool)?

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, let keyDownHandler, keyDownHandler(event) { return }
    super.sendEvent(event)
  }

  override var canBecomeKey: Bool { isPresented }
  override var canBecomeMain: Bool { false }

  override func isAccessibilityElement() -> Bool { isPresented && super.isAccessibilityElement() }
  override func accessibilityChildren() -> [Any]? { isPresented ? super.accessibilityChildren() : [] }
}
