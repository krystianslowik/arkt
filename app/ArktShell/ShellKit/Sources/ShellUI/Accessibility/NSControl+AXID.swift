import AppKit

extension NSControl {
  /// Sets `identifier` on the control and on its cell. AppKit hands accessibility clients the cell of a control
  /// (a button's parent lists its `NSButtonCell`), and the cell does not report an identifier set only on the control.
  func setAccessibilityIdentifierWithCell(_ identifier: String) {
    setAccessibilityIdentifier(identifier)
    cell?.setAccessibilityIdentifier(identifier)
  }
}
