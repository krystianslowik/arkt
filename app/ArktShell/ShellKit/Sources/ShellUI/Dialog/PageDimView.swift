import AppKit

/// The dim over a page while its JavaScript dialog is up (#693, design/extensions `surf-dialog`). It lies in the
/// page's window, above the page and below every child panel, so the infobar rows and the dialog stay clear; its
/// frame is the page below the rows. Clicks pass through and VoiceOver skips it: the dialog is what it announces.
@MainActor
final class PageDimView: NSView {
  /// The animation key of its fades.
  static let fadeKey = "pageDimFade"

  /// `cornerRadius` is the card's; the top corners round only when no infobar row sits above the dim.
  init(cornerRadius: CGFloat, roundsTop: Bool) {
    super.init(frame: .zero)
    wantsLayer = true
    autoresizingMask = []
    layer?.cornerRadius = cornerRadius
    layer?.cornerCurve = .continuous
    if !roundsTop {
      layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // the bottom ones (not flipped)
    }
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

  /// Lays the dim over `screenFrame` (the page below its rows, screen coordinates) in `window`, above the window's
  /// own views.
  func place(in window: NSWindow, screenFrame: NSRect) {
    guard let content = window.contentView else { return }
    if superview !== content {
      removeFromSuperview()
      content.addSubview(self, positioned: .above, relativeTo: nil)
    }
    frame = content.convert(window.convertFromScreen(screenFrame), from: nil)
    updateLayer()
  }

  /// Fades from `from` to `to` over `duration` (opacity only, the dim never moves). Leaves `to` as the opacity.
  func fade(from: Float, to: Float, duration: CFTimeInterval) {
    guard let layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = to
    fade.duration = duration
    fade.timingFunction = DialogMotion.easeOut
    layer.opacity = to
    layer.add(fade, forKey: Self.fadeKey)
  }
}
