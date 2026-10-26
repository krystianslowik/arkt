import AppKit

/// One window's Folder Preview (BH-093, GS-019): hovering a closed folder's row shows its tabs beside the sidebar
/// with a search field that takes the keyboard, so typing selects the first match; Return or a click activates the
/// tab, which then peeks out under the still-closed folder (the outline's peek, BH-092). Esc, leaving both the row
/// and the preview, or the field losing focus closes it and gives focus back. Arc gates it behind
/// `folderPreviewEnabled` [S]; here it is always on [I] until Settings has the switch.
@MainActor
final class FolderPreviewController: NSObject, NSTextFieldDelegate {
  /// How long the pointer rests on a closed folder before the preview shows [I] (Arc's delay is unmeasured).
  static let hoverDelay: TimeInterval = 0.5
  /// How long the preview waits after the pointer left the row and the preview before it closes [I].
  static let leaveGrace: TimeInterval = 0.25

  let source: any SidebarSource
  private(set) lazy var view: FolderPreviewView = {
    let view = FolderPreviewView(frame: .zero)
    view.searchField.delegate = self
    view.onRowClick = { [weak self] index in self?.choose(at: index) }
    view.onRowHover = { [weak self] index in self?.hoverRow(index) }
    view.onPointerInside = { [weak self] inside in self?.pointerInPreviewChanged(inside) }
    return view
  }()

  /// The view the preview joins (the window's root view) and the folder row's frame in it.
  var host: @MainActor () -> NSView? = { nil }
  var anchor: @MainActor (NodeID) -> NSRect? = { _ in nil }
  /// Whether the folder is closed in the window's current page (an open folder shows its tabs already).
  var isClosed: @MainActor (NodeID) -> Bool = { _ in false }
  var favicon: @MainActor (NodeID, String, URL) -> NSImage = { _, _, _ in NSImage() }
  var flavor: @MainActor () -> ThemeFlavor = { .light }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// A tab was chosen; the sidebar activates it.
  var onChoose: (@MainActor (NodeID) -> Void)?

  private(set) var shownFolder: NodeID?
  private var session: FolderPreviewSession?
  private var hoveredFolder: NodeID?
  private var pointerInPreview = false
  /// The responder that had the keyboard before the field took it.
  private weak var previousResponder: NSResponder?
  private var timer: Timer?
  private var pendingAction: (@MainActor () -> Void)?
  /// Set while the preview closes itself, so the field's end-of-editing is not taken for a click elsewhere.
  private var isClosing = false

  init(source: any SidebarSource) {
    self.source = source
  }

  // MARK: Hover

  /// The pointer entered or left a folder row of the current page.
  func folderHoverChanged(_ folder: NodeID, hovered: Bool) {
    if hovered {
      hoveredFolder = folder
      guard shownFolder != folder else {
        cancelTimer()                                 // back on the row before the grace ran out
        return
      }
      guard isClosed(folder) else { return }
      schedule(after: Self.hoverDelay) { [weak self] in
        guard let self, self.hoveredFolder == folder, self.isClosed(folder) else { return }
        self.show(folder: folder)
      }
    } else {
      if hoveredFolder == folder { hoveredFolder = nil }
      if shownFolder == nil {
        cancelTimer()
      } else if !pointerInPreview {
        scheduleLeave()
      }
    }
  }

  /// The pointer entered or left the preview itself.
  func pointerInPreviewChanged(_ inside: Bool) {
    pointerInPreview = inside
    if inside {
      cancelTimer()
    } else if shownFolder != nil, hoveredFolder != shownFolder {
      scheduleLeave()
    }
  }

  /// Runs the pending show or close now (tests; the timer calls it too).
  func firePendingTimer() {
    timer?.invalidate()
    timer = nil
    let action = pendingAction
    pendingAction = nil
    action?()
  }

  private func scheduleLeave() {
    schedule(after: Self.leaveGrace) { [weak self] in
      guard let self, !self.pointerInPreview, self.hoveredFolder != self.shownFolder else { return }
      self.hide(animated: true)
    }
  }

  private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
    cancelTimer()
    pendingAction = action
    timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.firePendingTimer() }
    }
  }

  private func cancelTimer() {
    timer?.invalidate()
    timer = nil
    pendingAction = nil
  }

  // MARK: Show and hide

  /// Shows the preview of `folder` beside its row, with the search field taking the keyboard.
  func show(folder: NodeID) {
    guard case .folder(_, let title)? = source.node(folder), let host = host(), let anchor = anchor(folder),
          let window = host.window else { return }
    cancelTimer()
    let session = FolderPreviewSession(folder: folder, in: source)
    self.session = session
    let wasShown = shownFolder != nil
    shownFolder = folder
    if view.superview !== host { host.addSubview(view, positioned: .above, relativeTo: nil) }
    view.show(title: title, rows: rows(for: session), highlighted: session.highlighted, flavor: flavor(),
              frame: frame(rows: session.items.count, anchor: anchor, in: host.bounds))
    view.searchField.stringValue = ""
    if !wasShown {
      let current = window.firstResponder
      previousResponder = isOurs(current) ? previousResponder : current
    }
    window.makeFirstResponder(view.searchField)
    if !wasShown { view.animateIn(reduceMotion: reduceMotion()) }
  }

  /// Closes the preview and gives the keyboard back to the responder that had it.
  func hide(animated: Bool) {
    cancelTimer()
    guard shownFolder != nil else { return }
    shownFolder = nil
    session = nil
    pointerInPreview = false
    isClosing = true
    if let window = view.window, isOurs(window.firstResponder) {
      let back = previousResponder.flatMap { responder -> NSResponder? in
        guard let viewResponder = responder as? NSView else { return responder }
        return viewResponder.window === window ? viewResponder : nil
      }
      window.makeFirstResponder(back)
    }
    isClosing = false
    previousResponder = nil
    let view = self.view
    view.animateOut(animated: animated && view.window != nil) { [weak self] in
      guard self?.shownFolder == nil else { return }       // shown again meanwhile
      view.removeFromSuperview()
    }
  }

  /// Whether `responder` is the search field or its field editor.
  private func isOurs(_ responder: NSResponder?) -> Bool {
    if responder === view.searchField { return true }
    guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
    return editor.delegate === view.searchField
  }

  /// To the right of the sidebar, its search field level with the folder row; kept inside the host.
  private func frame(rows: Int, anchor: NSRect, in bounds: NSRect) -> NSRect {
    let size = NSSize(width: FolderPreviewView.width, height: FolderPreviewView.height(rows: rows))
    let gap: CGFloat = 6
    let x = min(anchor.maxX + gap, max(bounds.maxX - size.width - gap, bounds.minX))
    let top = anchor.midY - FolderPreviewView.padding - FolderPreviewView.searchHeight / 2
    let y = min(max(top, bounds.minY + gap), max(bounds.maxY - size.height - gap, bounds.minY))
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
  }

  private func rows(for session: FolderPreviewSession) -> [FolderPreviewRow] {
    session.matches.map {
      FolderPreviewRow(node: $0.node, title: $0.title, favicon: favicon($0.node, $0.title, $0.url))
    }
  }

  /// A folder of the current page opened or closed: an open folder shows its tabs already, so its preview closes.
  func folderStatesChanged() {
    if let folder = shownFolder, !isClosed(folder) { hide(animated: true) }
  }

  // MARK: Choosing

  private func choose(at index: Int) {
    guard var session, session.matches.indices.contains(index) else { return }
    session.highlight(index)
    self.session = session
    chooseHighlighted()
  }

  private func chooseHighlighted() {
    guard let node = session?.highlightedNode else { return }
    hide(animated: true)
    onChoose?(node)
  }

  private func hoverRow(_ index: Int) {
    guard var session else { return }
    session.highlight(index)
    self.session = session
    view.setHighlight(session.highlighted)
  }

  // MARK: Search field

  func controlTextDidChange(_ notification: Notification) {
    guard var session else { return }
    session.query = view.searchField.stringValue
    self.session = session
    view.update(rows: rows(for: session), highlighted: session.highlighted)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === view.searchField, var session else { return false }
    switch selector {
    case #selector(NSResponder.moveDown(_:)):
      session.move(by: 1)
    case #selector(NSResponder.moveUp(_:)):
      session.move(by: -1)
    case #selector(NSResponder.insertNewline(_:)):
      chooseHighlighted()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      hide(animated: true)
      return true
    default:
      return false
    }
    self.session = session
    view.setHighlight(session.highlighted)
    return true
  }

  /// A click elsewhere took the keyboard: the preview closes.
  func controlTextDidEndEditing(_ notification: Notification) {
    guard !isClosing, shownFolder != nil else { return }
    hide(animated: true)
  }
}
