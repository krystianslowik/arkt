import AppKit
import Motion

// The three hosts of a `DialogContent` (docs/design/alerts-sheets-toasts.md, section 3.3): a window sheet, a panel
// anchored to the page, and an app-modal alert when no window exists. Each draws a `DialogSheetView` and reports one
// answer.

// MARK: - Window sheet

/// A dialog hung from a window as a sheet (`NSWindow.beginSheet`): Delete Space, Clear Archive. AppKit owns the slide;
/// focus starts on the default button, else Cancel; Escape answers Cancel; Return presses only the default button.
@MainActor
public final class DialogSheet: NSWindowController {
  let view: DialogSheetView
  /// Called once with the answer.
  public var onAnswer: (@MainActor (DialogContent.Answer) -> Void)?
  public var onFooterLink: (@MainActor () -> Void)? {
    get { view.onFooterLink }
    set { view.onFooterLink = newValue }
  }

  public init(content: DialogContent) {
    view = DialogSheetView(content: content, insets: .sheet)
    let height = view.layoutContent(width: content.width)
    let window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: content.width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: true)
    super.init(window: window)
    view.frame = NSRect(x: 0, y: 0, width: content.width, height: height)
    window.contentView = view
    window.initialFirstResponder = view.initialFocus
    window.onEscape = { [weak self] in self?.view.escape() ?? false }
    window.setAccessibilityLabel(content.title)
    view.onAnswer = { [weak self] answer in self?.finish(answer) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The content this sheet shows.
  public var content: DialogContent { view.content }

  /// Shows the sheet on `parent`.
  public func begin(on parent: NSWindow) {
    guard let window else { return }
    parent.beginSheet(window) { _ in }
    window.makeFirstResponder(view.initialFocus)
  }

  private func finish(_ answer: DialogContent.Answer) {
    guard let window else { return }
    let callback = onAnswer
    onAnswer = nil
    window.sheetParent?.endSheet(window)
    window.orderOut(nil)
    callback?(answer)
  }
}

/// A dialog window: Escape goes to the dialog, and it can become key without a title bar.
@MainActor
final class DialogWindow: NSPanel {
  var onEscape: (@MainActor () -> Bool)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) {
    if onEscape?() != true { super.cancelOperation(sender) }
  }
}

// MARK: - App-modal alert

/// A centered app-modal alert for when no window exists (the launch failure): a borderless panel with 14 pt corners and
/// the overlay shadow, run with `NSApp.runModal(for:)`. It grows from its center on `firmFast` while it fades in
/// (Reduce Motion: a fade). Run it from a run-loop callout, never from inside a main-actor job (week-3 Decision 3).
@MainActor
public final class DialogAlert {
  public let panel: NSPanel
  let view: DialogSheetView
  /// The rounded container the view sits in; the entrance moves its layer.
  let container: NSView
  /// The footer link (Show Data Folder); the alert stays up.
  public var onFooterLink: (@MainActor () -> Void)? {
    get { view.onFooterLink }
    set { view.onFooterLink = newValue }
  }
  /// Reduce Motion, read at the entrance. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private(set) var answer: DialogContent.Answer?

  public init(content: DialogContent) {
    view = DialogSheetView(content: content, insets: .alert)
    let height = view.layoutContent(width: content.width)
    let size = NSSize(width: content.width, height: height)
    let window = DialogWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .modalPanel
    window.isMovableByWindowBackground = true
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel(content.title)
    container = NSView(frame: NSRect(origin: .zero, size: size))
    container.wantsLayer = true
    container.layer?.cornerRadius = DialogMetrics.alertCornerRadius
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    view.frame = container.bounds
    view.autoresizingMask = [.width, .height]
    container.addSubview(view)
    window.contentView = container
    window.initialFirstResponder = view.initialFocus
    panel = window
    window.onEscape = { [weak self] in self?.view.escape() ?? false }
    view.onAnswer = { [weak self] answer in self?.finish(answer) }
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(view.archiveFlavor).cgColor
  }

  public var content: DialogContent { view.content }

  /// Shows the alert centered and waits for the answer.
  public func runModal() -> DialogContent.Answer {
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(view.initialFocus)
    enter()
    NSApp.runModal(for: panel)
    return answer ?? .cancel
  }

  /// The entrance: scale 0.96 to 1 about the center on `firmFast`, opacity over 0.18 s (Reduce Motion: 0.15 s fade).
  /// The window shadow is recomputed once the content is fully drawn.
  func enter() {
    guard let layer = container.layer else { return }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak panel] in MainActor.assumeIsolated { panel?.invalidateShadow() } }
    defer { CATransaction.commit() }
    let step = DialogMotion.alertIn(reduceMotion: reduceMotion())
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.fadeDuration
    fade.timingFunction = DialogMotion.easeOut
    layer.add(fade, forKey: "dialogFade")
    guard let spring = step.spring else { return }
    let bounds = container.bounds
    let start = DialogMotion.transform(scale: step.scale, offsetY: 0, about: CGPoint(x: bounds.midX, y: bounds.midY),
                                       bounds: bounds, layerAnchor: layer.anchorPoint)
    layer.add(Self.spring(spring, from: start), forKey: "dialogTransform")
  }

  static func spring(_ spring: SpringParameters, from start: CATransform3D) -> CASpringAnimation {
    let motion = CASpringAnimation(keyPath: "transform")
    motion.mass = CGFloat(spring.mass)
    motion.stiffness = CGFloat(spring.stiffness)
    motion.damping = CGFloat(spring.damping)
    motion.fromValue = NSValue(caTransform3D: start)
    motion.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    motion.duration = max(spring.settlingDuration(), motion.settlingDuration)
    return motion
  }

  private func finish(_ answer: DialogContent.Answer) {
    guard self.answer == nil else { return }
    self.answer = answer
    if NSApp.modalWindow === panel { NSApp.stopModal() }
    panel.orderOut(nil)
  }
}

// MARK: - Anchored panel

/// A non-activating child panel whose top-leading corner sits 12 pt inside `anchor` (the content card or the focused
/// pane), so the prompt points at the page that asked. It never takes focus from the page unless clicked; Escape
/// answers Cancel only while it is key. In: scale 0.97 and 4 pt from above to rest on `firmFast` from its top-leading
/// corner, opacity over 0.16 s; out: 0.10 s fade, instant when the keyboard answered (Reduce Motion: fades only).
@MainActor
public final class DialogPanel {
  public static let anchorInset: CGFloat = 12
  public let panel: NSPanel
  let view: DialogSheetView
  let container: NSView
  public var onAnswer: (@MainActor (DialogContent.Answer) -> Void)?
  /// Escape closed a dialog whose content `escapeDismisses`: no answer, the panel leaves at once.
  public var onDismiss: (@MainActor () -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The time the input protection reads (seconds); tests inject it.
  var clock: @MainActor () -> TimeInterval {
    get { view.clock }
    set { view.clock = newValue }
  }
  /// The last answer came from a key (Return, Escape): the panel leaves at once.
  private var keyboardAnswer = false

  public init(content: DialogContent) {
    view = DialogSheetView(content: content, insets: .panel)
    let height = view.layoutContent(width: content.width)
    let size = NSSize(width: content.width, height: height)
    let window = DialogWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = true
    window.setAccessibilitySubrole(.dialog)
    window.setAccessibilityLabel(content.title)
    container = NSView(frame: NSRect(origin: .zero, size: size))
    container.wantsLayer = true
    container.layer?.cornerRadius = DialogMetrics.panelCornerRadius
    container.layer?.cornerCurve = .continuous
    container.layer?.masksToBounds = true
    container.layer?.borderWidth = 0.5
    view.frame = container.bounds
    view.autoresizingMask = [.width, .height]
    container.addSubview(view)
    window.contentView = container
    panel = window
    window.onEscape = { [weak self] in
      self?.keyboardAnswer = true
      return self?.view.escape() ?? false
    }
    view.onAnswer = { [weak self] answer in self?.finish(answer) }
    view.onDismiss = { [weak self] in self?.finishDismissed() }
    container.layer?.borderColor = AlertTokens.overlayEdge.resolve(view.archiveFlavor).cgColor
  }

  public var content: DialogContent { view.content }

  /// The panel's frame for `anchor` (screen coordinates): top-leading corner `anchorInset` inside it.
  public func frame(anchoredTo anchor: NSRect) -> NSRect {
    let size = panel.frame.size
    return NSRect(x: anchor.minX + Self.anchorInset, y: anchor.maxY - Self.anchorInset - size.height,
                  width: size.width, height: size.height)
  }

  /// The text in the prompt's field; nil when the content has none.
  public var inputText: String? { view.inputText }

  /// Moves the panel to `anchor` (screen coordinates) again, when the page it points at moved or resized.
  public func reposition(anchoredTo anchor: NSRect) {
    panel.setFrame(frame(anchoredTo: anchor), display: true)
  }

  /// Shows the panel over `parent`, anchored to `anchor` (screen coordinates). It takes no focus unless
  /// `takesFocus` (a page's dialog, which blocks the page: the answer keys go to it). VoiceOver hears its title.
  public func show(over parent: NSWindow, anchoredTo anchor: NSRect, takesFocus: Bool = false) {
    panel.setFrame(frame(anchoredTo: anchor), display: false)
    parent.addChildWindow(panel, ordered: .above)
    panel.orderFront(nil)
    view.beginInputProtection()
    if takesFocus {
      panel.makeKey()
      panel.makeFirstResponder(view.initialFocus)            // a field starts editing with its text selected
    }
    enter()
    NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
      .announcement: content.title, .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }

  func enter() {
    guard let layer = container.layer else { return }
    let step = DialogMotion.panelIn(reduceMotion: reduceMotion())
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.fadeDuration
    fade.timingFunction = DialogMotion.easeOut
    layer.add(fade, forKey: "dialogFade")
    guard let spring = step.spring else { return }
    let bounds = container.bounds
    // The container is not flipped: its top-leading corner is (0, height), and "4 pt from above" is +4 on y.
    let start = DialogMotion.transform(scale: step.scale, offsetY: -step.offsetY, about: CGPoint(x: 0, y: bounds.maxY),
                                       bounds: bounds, layerAnchor: layer.anchorPoint)
    layer.add(DialogAlert.spring(spring, from: start), forKey: "dialogTransform")
  }

  /// Takes the panel down: a 0.10 s fade, or at once when `keyboard` (or Reduce Motion).
  public func close(keyboard: Bool) {
    let duration = DialogMotion.panelOut(keyboard: keyboard, reduceMotion: reduceMotion())
    guard duration > 0, let layer = container.layer else { return remove() }
    CATransaction.begin()
    // The window, not `self`: the owner lets go of this object at the answer, and the fade must still take it down.
    let window = panel
    CATransaction.setCompletionBlock { MainActor.assumeIsolated { Self.remove(window) } }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = duration
    fade.timingFunction = DialogMotion.easeOut
    layer.opacity = 0
    layer.add(fade, forKey: "dialogFade")
    CATransaction.commit()
  }

  private func remove() { Self.remove(panel) }

  private static func remove(_ window: NSPanel) {
    window.parent?.removeChildWindow(window)
    window.orderOut(nil)
  }

  private func finish(_ answer: DialogContent.Answer) {
    let keyboard = keyboardAnswer || NSApp.currentEvent?.type == .keyDown
    keyboardAnswer = false
    let callback = onAnswer
    onAnswer = nil
    onDismiss = nil
    close(keyboard: keyboard)
    callback?(answer)
  }

  private func finishDismissed() {
    keyboardAnswer = false
    let callback = onDismiss
    onAnswer = nil
    onDismiss = nil
    close(keyboard: true)
    callback?()
  }
}
