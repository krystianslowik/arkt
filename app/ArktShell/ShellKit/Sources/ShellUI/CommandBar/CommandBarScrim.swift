import AppKit

/// The light dim over the window behind the bar (design/command-bar/README.md, Look): a click-through borderless
/// window laid over the parent, black 28 % in dark and graphite 10 % in light. Created and ordered in once, at alpha 0,
/// like the panel; presenting it is an alpha change, so a show orders no window.
@MainActor
final class CommandBarScrim: NSWindow {
  init() {
    super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    isOpaque = false
    hasShadow = false
    backgroundColor = .clear
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    animationBehavior = .none
    alphaValue = 0
    collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    let content = NSView()
    content.wantsLayer = true
    contentView = content
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }

  /// The scrim's current fill, for tests.
  private(set) var fillFlavor: ThemeFlavor = .dark

  func apply(flavor: ThemeFlavor) {
    fillFlavor = flavor
    contentView?.layer?.backgroundColor = ShellTokens.commandBarScrim.resolve(flavor).cgColor
  }

  var isPresented = false {
    didSet {
      guard isPresented != oldValue else { return }
      alphaValue = isPresented ? 1 : 0
    }
  }

  /// Covers `parent`'s frame.
  func cover(_ parent: NSWindow) {
    if frame != parent.frame { setFrame(parent.frame, display: false) }
  }
}
