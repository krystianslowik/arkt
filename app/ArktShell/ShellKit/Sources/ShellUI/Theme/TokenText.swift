import AppKit

// A layer-backed `NSTextField` or `NSButton` that does not override `draw(_:)` draws its text through AppKit's own
// text layer, which renders a translucent text color heavier than given: `primaryText` dark (white 0.84) lands near
// 0.97 and `secondaryText` light (black 0.66) near 0.89 (#711). Overriding `draw(_:)` sends the text through the view's
// ordinary backing store, where the token's alpha holds. `DialogLabelColorTests` guards both classes.

/// A label whose text color is a token with alpha: it draws the token as given.
final class TokenLabel: NSTextField {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
  }
}

/// A plain button (a text link, a checkbox) whose title color is a token with alpha: it draws the token as given.
class TokenTitleButton: NSButton {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
  }
}
