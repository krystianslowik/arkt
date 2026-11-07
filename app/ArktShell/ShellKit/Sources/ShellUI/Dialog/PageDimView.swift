import AppKit

/// The dim over a page while its JavaScript dialog is up (#693, design/extensions `surf-dialog`). It sits directly
/// above the page view in the page's own superview, as the card's page overlay does, so everything the shell draws
/// over the page stays over the dim: the Toolbar, the find bar, the pills, the toast, a split pane's close button, the
/// slid-out sidebar and the Peek. Its frame is the page below its infobar rows; the card's clip view rounds its corners.
/// Clicks pass through it and VoiceOver skips it: the dialog is what it announces.
///
/// It only fades, so it never moves under Reduce Motion either: in with the panel's fade, out over `exitDuration` on
/// every exit path, even when the panel itself leaves at once. A dialog that comes up over the same page while the dim
/// is leaving takes the dim back from its current opacity, so a page is never dimmed twice.
@MainActor
final class PageDimView: NSView {
  /// The animation key of its fades.
  static let fadeKey = "pageDimFade"
  /// How long the dim takes to leave, on every exit path, Reduce Motion included.
  static let exitDuration: CFTimeInterval = 0.10

  /// The page view the dim covers.
  private(set) weak var page: NSView?
  /// The dim is fading out and goes when the fade ends, unless a dialog takes it back first.
  private(set) var isLeaving = false
  /// Counts the fades, so the end of an older fade-out never removes a dim that was taken back.
  private var fadeGeneration = 0

  init(page: NSView) {
    self.page = page
    super.init(frame: .zero)
    wantsLayer = true
    autoresizingMask = []
    layer?.opacity = 0
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.pageDim.resolve(archiveFlavor).cgColor
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func accessibilityChildren() -> [Any]? { [] }

  /// The view that holds the dim of `page`: its superview, or the page itself when it is its window's content view
  /// (whose superview is the window's frame view) or has no superview.
  private static func container(of page: NSView) -> NSView {
    guard let superview = page.superview, page !== page.window?.contentView else { return page }
    return superview
  }

  /// The dim still over `page`, leaving or not, so a follow-up dialog takes it back instead of adding a second one.
  static func existing(over page: NSView) -> PageDimView? {
    container(of: page).subviews.lazy.compactMap { $0 as? PageDimView }.first { $0.page === page }
  }

  /// Puts the dim directly above its page and over `screenFrame` (the page below its rows, screen coordinates).
  func place(screenFrame: NSRect) {
    guard let page, let window = page.window else { return }
    let container = Self.container(of: page)
    if container === page {
      if superview !== container { container.addSubview(self, positioned: .above, relativeTo: nil) }
    } else if superview !== container || !isDirectlyAbove(page, in: container) {
      container.addSubview(self, positioned: .above, relativeTo: page)
    }
    frame = container.convert(window.convertFromScreen(screenFrame), from: nil)
    needsDisplay = true
  }

  private func isDirectlyAbove(_ page: NSView, in container: NSView) -> Bool {
    let views = container.subviews
    guard let index = views.firstIndex(where: { $0 === page }), index + 1 < views.count else { return false }
    return views[index + 1] === self
  }

  /// Fades in (or back in, from where a fade-out left it) over `duration`.
  func enter(duration: CFTimeInterval) {
    isLeaving = false
    fadeGeneration += 1
    fade(to: 1, duration: duration)
  }

  /// Fades out over `duration` and leaves its superview at the end; at once for a zero duration, or when its page is
  /// already off screen (another tab took the page's place, and must not show a dim fading over it).
  func leave(duration: CFTimeInterval) {
    isLeaving = true
    fadeGeneration += 1
    let pageIsShown = page.map { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor } ?? false
    guard duration > 0, pageIsShown else {
      layer?.removeAnimation(forKey: Self.fadeKey)
      layer?.opacity = 0
      removeFromSuperview()
      return
    }
    let generation = fadeGeneration
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.isLeaving, self.fadeGeneration == generation else { return }
        self.removeFromSuperview()
      }
    }
    fade(to: 0, duration: duration)
    CATransaction.commit()
  }

  /// Opacity only, from the opacity on screen now; leaves `to` as the model opacity.
  private func fade(to opacity: Float, duration: CFTimeInterval) {
    guard let layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
    fade.toValue = opacity
    fade.duration = duration
    fade.timingFunction = DialogMotion.easeOut
    layer.opacity = opacity
    layer.add(fade, forKey: Self.fadeKey)
  }
}
