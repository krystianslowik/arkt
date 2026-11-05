import AppKit

/// Increase Contrast on the main window's chrome (#640, design/increase-contrast/README.md). Fills never change: each
/// filled state gets a 1 pt `ShellTokens.increasedContrastEdge`, drawn as a layer border, so no row, tile or pill
/// changes size when the setting does. The edge comes and goes with the setting, without animation.
///
/// Each view reads the setting through its own `increaseContrast` closure (tests replace it) and redraws when the
/// system's display options change, so the edge follows the setting without a relaunch.
@MainActor
enum IncreasedContrast {
  /// The system setting.
  static var systemSetting: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

  /// Calls `selector` (taking the notification) on `observer` whenever the system's display options change. A
  /// selector observer is removed when the observer goes away.
  static func observe(_ observer: NSObject, selector: Selector) {
    NSWorkspace.shared.notificationCenter.addObserver(
      observer, selector: selector, name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Sets `layer`'s border: the 1 pt edge when `increased`, otherwise the surface's own edge (`width` and `color`;
  /// none by default). Call it inside the caller's transaction.
  static func setEdge(on layer: CALayer, increased: Bool, flavor: ThemeFlavor, otherwiseWidth width: CGFloat = 0,
                      color: RGBA? = nil) {
    if increased {
      layer.borderWidth = ShellTokens.increasedContrastEdgeWidth
      layer.borderColor = ShellTokens.increasedContrastEdge.resolve(flavor).cgColor
    } else {
      layer.borderWidth = color == nil ? 0 : width
      layer.borderColor = color?.cgColor
    }
  }
}
