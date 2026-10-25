import AppKit

extension NSView {
  /// Removes the tool tips of this view and every view below it: the `toolTip` strings and the rects added with
  /// `addToolTip(_:owner:userData:)`. A shell window calls it while closing (#301 item 3): AppKit left a tool tip that
  /// was on screen at that moment (the Space title's, window layer 103) showing after the window was gone; removing
  /// its owner's tool tips takes it down.
  func removeToolTipsInSubtree() {
    toolTip = nil
    removeAllToolTips()
    for subview in subviews { subview.removeToolTipsInSubtree() }
  }
}
