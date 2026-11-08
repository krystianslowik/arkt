import AppKit

// A layer-backed `NSTextField` or `NSButton` that does not override `draw(_:)` draws its text through AppKit's own
// text layer, which renders a translucent text color heavier than given: `primaryText` dark (white 0.84) lands near
// 0.97 and `secondaryText` light (black 0.66) near 0.89 (#711). Overriding `draw(_:)` sends the text through the view's
// ordinary backing store, where the token's alpha holds. `DialogLabelColorTests` guards both classes.

/// A label whose text color is a token with alpha: it draws the token as given.
final class TokenLabel: NSTextField {
  /// Clicks go to the views under the label (a title drawn over a checkbox's own).
  var passesMouseThrough = false

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    passesMouseThrough ? nil : super.hitTest(point)
  }
}

/// A plain text button (a link) whose title color is a token with alpha: it draws the token as given.
class TokenTitleButton: NSButton {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
  }
}
