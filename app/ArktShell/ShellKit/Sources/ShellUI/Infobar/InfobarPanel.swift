import AppKit
import EngineAPI

/// The surface the rows sit on: one view for the whole list, so two stacked infobars read as one strip with no hairline
/// between them (the surface against the page is the edge). Rows are laid out with frames, top to bottom.
@MainActor
final class InfobarStackView: NSView {
  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.dialogSurface.resolve(archiveFlavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  /// The strip's keys while F6 has put the keyboard in it (#478); nil otherwise, and then the stack takes no keys.
  var keyHandler: (@MainActor (NSEvent) -> Bool)?

  override var acceptsFirstResponder: Bool { keyHandler != nil }

  override func keyDown(with event: NSEvent) {
    if keyHandler?(event) != true { super.keyDown(with: event) }
  }

  override func layout() {
    super.layout()
    var y: CGFloat = 0
    for case let row as InfobarRowView in subviews {
      row.frame = NSRect(x: 0, y: y, width: bounds.width, height: InfobarMetrics.rowHeight)
      y += InfobarMetrics.rowHeight
    }
  }
}

private final class InfobarWindow: NSPanel {
  /// The strip lost the keyboard to another window (a click on the page or elsewhere).
  var onResignKey: (@MainActor () -> Void)?
  override var canBecomeKey: Bool { true }
  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }
}

/// The infobars of one tab as a strip flush with the top of the tab's page view (#400): a non-activating child panel,
/// full width, 40 pt per infobar, with the page card's top corners. The engine reserves the same height at the top of
/// the tab's container, so the page sits below the strip and moves down once when a row arrives; nothing animates
/// the height. A row that arrives fades in over 0.14 s, none fades out, and Reduce Motion shows both at once; the
/// presenter says which infobars are new, so one that was on screen before never fades again. The panel never takes key
/// focus from the page.
@MainActor
final class InfobarPanel: AnchoredPanel {
  let panel: NSPanel
  let stack = InfobarStackView()
  private(set) var infobars: [Infobar]
  private(set) var rows: [InfobarRowView] = []
  /// A click on a row: the infobar and what was clicked. The owner sends it to the engine; the row stays until the
  /// engine's next list drops it.
  var onAction: (@MainActor (Infobar, InfobarAction) -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The keyboard left the strip by Esc or F6, or with the strip going down while it held it: the owner gives it to
  /// the page.
  var onKeyboardExit: (@MainActor () -> Void)?
  /// Where F6's keyboard focus is (#478): the infobar's row and the index into its `keyboardControls`; nil while the
  /// strip does not hold the keyboard, which is always unless F6 put it there.
  private(set) var keyboardFocus: (id: InfobarID, index: Int)?
  private var isShown = false

  init(infobars: [Infobar], width: CGFloat) {
    self.infobars = []
    let window = InfobarWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: InfobarMetrics.rowHeight),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.becomesKeyOnlyIfNeeded = true
    panel = window
    stack.wantsLayer = true
    stack.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]        // the top corners, unflipped
    stack.layer?.cornerCurve = .continuous
    stack.layer?.masksToBounds = true
    window.contentView = stack
    apply(infobars, animated: false)
    resizeToContent(width: width)
    window.onResignKey = { [weak self] in self?.endKeyboard(returningToPage: false) }
  }

  /// The strip's height: 40 pt per infobar.
  var height: CGFloat { CGFloat(rows.count) * InfobarMetrics.rowHeight }

  /// Shows `list`: a row whose infobar is still there keeps its place (its values refresh), a new infobar gets a new row
  /// (faded in once the strip is up), a missing one goes at once. The panel keeps its top edge.
  func update(_ list: [Infobar]) {
    guard list != infobars else { return }
    apply(list, animated: isShown)
    let top = panel.frame.maxY
    let size = NSSize(width: panel.frame.width, height: height)
    panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                   display: true)
    keepKeyboardFocus()
  }

  // MARK: Keyboard (#478)

  /// Puts the keyboard in the strip, on the first control of the first row that has one: the strip becomes the key
  /// window and its stack takes the keys. False, and nothing changes, when no row has a control to reach.
  @discardableResult
  func focusKeyboard() -> Bool {
    guard let row = rows.first(where: { !$0.keyboardControls.isEmpty }) else { return false }
    keyboardFocus = (row.infobar.id, 0)
    stack.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
    panel.makeKey()
    panel.makeFirstResponder(stack)
    showKeyboardFocus()
    return true
  }

  /// Takes the keyboard out of the strip. With `returningToPage` (Esc, F6, the strip going down) the parent window
  /// becomes key again and the owner gives the keyboard to the page; without it (another window took the keyboard)
  /// only the ring goes.
  func endKeyboard(returningToPage: Bool) {
    guard keyboardFocus != nil else { return }
    keyboardFocus = nil
    stack.keyHandler = nil
    showKeyboardFocus()
    if panel.firstResponder === stack { panel.makeFirstResponder(nil) }
    guard returningToPage else { return }
    if panel.isKeyWindow { panel.parent?.makeKey() }
    onKeyboardExit?()
  }

  /// The control the keyboard is on, nil while the strip does not hold it.
  var keyboardFocusedControl: NSButton? {
    guard let focus = keyboardFocus, let row = rows.first(where: { $0.infobar.id == focus.id }) else { return nil }
    let controls = row.keyboardControls
    return controls.indices.contains(focus.index) ? controls[focus.index] : nil
  }

  private func showKeyboardFocus() {
    let focused = keyboardFocusedControl
    for row in rows { row.showKeyboardFocus(on: focused) }
  }

  /// After a new list: the focus stays on its infobar's row, or moves to the row that took its place; the strip lets
  /// the keyboard go when no control is left.
  private func keepKeyboardFocus() {
    guard let focus = keyboardFocus else { return }
    let reachable = rows.filter { !$0.keyboardControls.isEmpty }
    if let row = reachable.first(where: { $0.infobar.id == focus.id }) {
      keyboardFocus = (row.infobar.id, min(focus.index, row.keyboardControls.count - 1))
    } else if let row = reachable.first {
      keyboardFocus = (row.infobar.id, 0)
    } else {
      endKeyboard(returningToPage: true)
      return
    }
    showKeyboardFocus()
  }

  /// Tab and Shift-Tab go through every control of every row (and around); Left and Right go along the row, mirrored
  /// right to left; Up and Down go to the row above or below; Return, Enter and Space press the control; Esc and F6
  /// give the keyboard back to the page.
  private func handleKey(_ event: NSEvent) -> Bool {
    guard let focus = keyboardFocus else { return false }
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    guard modifiers.isEmpty || (modifiers == .shift && event.keyCode == KeyCode.tab) else { return false }
    let reachable = rows.filter { !$0.keyboardControls.isEmpty }
    guard let rowIndex = reachable.firstIndex(where: { $0.infobar.id == focus.id }) else { return false }
    let mirrored = stack.userInterfaceLayoutDirection == .rightToLeft
    switch event.keyCode {
    case KeyCode.escape, KeyCode.f6:
      endKeyboard(returningToPage: true)
    case KeyCode.returnKey, KeyCode.enter, KeyCode.space:
      keyboardFocusedControl?.performClick(nil)
    case KeyCode.tab:
      let flat = reachable.flatMap { row in row.keyboardControls.indices.map { (row.infobar.id, $0) } }
      guard let at = flat.firstIndex(where: { $0.0 == focus.id && $0.1 == focus.index }) else { return false }
      let next = flat[(at + (modifiers == .shift ? flat.count - 1 : 1)) % flat.count]
      keyboardFocus = (next.0, next.1)
    case KeyCode.left, KeyCode.right:
      let count = reachable[rowIndex].keyboardControls.count
      let forward = (event.keyCode == KeyCode.right) != mirrored
      keyboardFocus = (focus.id, (focus.index + (forward ? 1 : count - 1)) % count)
    case KeyCode.up, KeyCode.down:
      let target = event.keyCode == KeyCode.down ? rowIndex + 1 : rowIndex - 1
      guard reachable.indices.contains(target) else { return true }
      let row = reachable[target]
      keyboardFocus = (row.infobar.id, min(focus.index, row.keyboardControls.count - 1))
    default:
      return false
    }
    showKeyboardFocus()
    return true
  }

  private enum KeyCode {
    static let tab: UInt16 = 48
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let f6: UInt16 = 97
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
  }

  private func apply(_ list: [Infobar], animated: Bool) {
    var existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.infobar.id, $0) })
    var next: [InfobarRowView] = []
    var added: [Infobar] = []
    for infobar in list {
      if let row = existing.removeValue(forKey: infobar.id) {
        row.update(infobar)
        next.append(row)
      } else {
        let row = InfobarRowView(infobar: infobar)
        // The row reports the infobar as it is now, not as it was when the row was made.
        row.onAction = { [weak self, weak row] action in
          guard let self, let row else { return }
          onAction?(row.infobar, action)
        }
        stack.addSubview(row)
        next.append(row)
        added.append(infobar)
      }
    }
    for gone in existing.values { gone.removeFromSuperview() }
    rows = next
    infobars = list
    stack.needsLayout = true
    stack.layoutSubtreeIfNeeded()
    if animated { fadeIn(added.map(\.id)) }
  }

  /// Fades in the rows of `ids` (Reduce Motion: none): infobars that were never on screen, joining rows that were.
  func fadeIn(_ ids: [InfobarID]) {
    let reduced = reduceMotion()
    for id in ids { rows.first { $0.infobar.id == id }?.fadeIn(reduceMotion: reduced) }
  }

  private func resizeToContent(width: CGFloat) {
    panel.setContentSize(NSSize(width: width, height: height))
    stack.frame = NSRect(x: 0, y: 0, width: width, height: height)
    stack.layoutSubtreeIfNeeded()
  }

  // MARK: AnchoredPanel

  /// The strip's frame for `anchor` (screen coordinates): flush with its top-leading corner, as wide as the page.
  func frame(anchoredTo anchor: NSRect) -> NSRect {
    NSRect(x: anchor.minX, y: anchor.maxY - height, width: anchor.width, height: height)
  }

  func resize(width: CGFloat) {
    guard width != panel.frame.width else { return }
    resizeToContent(width: width)
  }

  func reposition(anchoredTo anchor: NSRect) {
    guard !anchor.isEmpty else { return }
    panel.setFrame(frame(anchoredTo: anchor), display: true)
  }

  func detach() {
    onAction = nil
  }

  /// Takes the strip down at once: no exit animation (design section 5). A strip that held the keyboard gives it back
  /// to the page first.
  func close(keyboard: Bool) {
    endKeyboard(returningToPage: true)
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    isShown = false
  }

  /// Shows the strip over `parent`, flush with the top of `anchor` (screen coordinates), with the card's corner radius
  /// on its top corners. With `fadeIn` it fades in over 0.14 s (Reduce Motion: at once); a strip whose infobars were
  /// already on screen (the tab comes back from another tab, a Space or HTML fullscreen) shows at once.
  func show(over parent: NSWindow, anchoredTo anchor: NSRect, topCornerRadius: CGFloat, fadeIn: Bool = true) {
    stack.layer?.cornerRadius = topCornerRadius
    panel.setFrame(frame(anchoredTo: anchor), display: false)
    parent.addChildWindow(panel, ordered: .above)
    panel.orderFront(nil)
    isShown = true
    if fadeIn, !reduceMotion(), let layer = stack.layer {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      fade.duration = InfobarMetrics.fadeDuration
      fade.timingFunction = ArchiveMotion.easeOut
      layer.add(fade, forKey: "infobarFade")
    }
  }
}
