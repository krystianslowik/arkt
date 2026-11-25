import AppKit

/// The command bar field's editor: its caret is 2 pt wide (README, Look), drawn in the mustard the controller sets.
@MainActor
final class CommandBarFieldEditor: NSTextView {
  static let caretWidth: CGFloat = 2

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    var caret = rect
    caret.size.width = Self.caretWidth
    super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
  }

  /// The caret's blink redraws its old rectangle; widen it so the second point is erased too.
  override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
    var dirty = rect
    dirty.size.width += Self.caretWidth - 1
    super.setNeedsDisplay(dirty, avoidAdditionalLayout: flag)
  }
}

/// Borderless floating panel hosting the command bar. Created once and reused (pre-warmed).
@MainActor
final class CommandBarPanel: NSPanel {
  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: CommandBarGeometry.maxWidth,
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
  /// window in cost one to three extra frames in the window server). No fade either way. While hidden it is inert:
  /// clicks pass through, it cannot become key, and accessibility does not report it (no "open" / "closed" value:
  /// VoiceOver would read it, #608; a hidden bar is absent from the tree instead).
  var isPresented = false {
    didSet {
      guard isPresented != oldValue else { return }
      alphaValue = isPresented ? 1 : 0
      ignoresMouseEvents = !isPresented
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

  /// The bar's field editor, made once: it draws the 2 pt caret (README, Look).
  private lazy var commandFieldEditor: CommandBarFieldEditor = {
    let editor = CommandBarFieldEditor(frame: .zero)
    editor.isFieldEditor = true
    return editor
  }()

  override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
    object is NSTextField ? commandFieldEditor : super.fieldEditor(createFlag, for: object)
  }

  override var canBecomeKey: Bool { isPresented }
  override var canBecomeMain: Bool { false }

  override func isAccessibilityElement() -> Bool { isPresented && super.isAccessibilityElement() }
  override func accessibilityChildren() -> [Any]? { isPresented ? super.accessibilityChildren() : [] }
}
