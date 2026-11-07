import AppKit

/// The light dim over the window behind the bar (design/command-bar/README.md, Look): a click-through view laid over
/// the parent's content, black 28 % in dark and graphite 10 % in light. Added once, hidden at opacity 0, like the panel:
/// presenting it is an opacity change, so a show adds no view and orders no window. It is a view, not a child window,
/// so the window's child windows (dialogs, strips) stay what they were.
@MainActor
final class CommandBarScrim: NSView {
  private(set) var fillFlavor: ThemeFlavor = .dark

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    autoresizingMask = [.width, .height]
    layer?.opacity = 0
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Clicks and hover reach the window behind it.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func accessibilityChildren() -> [Any]? { [] }

  func apply(flavor: ThemeFlavor) {
    fillFlavor = flavor
    layer?.backgroundColor = ShellTokens.commandBarScrim.resolve(flavor).cgColor
  }

  /// Whether the scrim is dimming the window (its model opacity).
  var isPresented: Bool {
    get { (layer?.opacity ?? 0) > 0 }
    set { layer?.opacity = newValue ? 1 : 0 }
  }

  /// Lays the scrim over `window`'s content view, above every other subview, once; a show re-checks the order.
  func attach(to window: NSWindow) {
    guard let content = window.contentView else { return }
    if superview !== content {
      removeFromSuperview()
      frame = content.bounds
      content.addSubview(self, positioned: .above, relativeTo: nil)
    } else if content.subviews.last !== self {
      content.addSubview(self, positioned: .above, relativeTo: nil)
    }
  }
}
