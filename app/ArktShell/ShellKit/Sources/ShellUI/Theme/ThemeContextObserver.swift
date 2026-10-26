import AppKit

/// Follows what Space themes are drawn for (#410): the window's appearance and the Increase Contrast setting. Calls
/// `onChange` when either changes; `context` is current at any time.
@MainActor
final class ThemeContextObserver: NSObject {
  private weak var window: NSWindow?
  private var appearanceObservation: NSKeyValueObservation?
  private let increaseContrast: @MainActor () -> Bool
  private let onChange: @MainActor (ThemeContext) -> Void

  init(window: NSWindow?,
       increaseContrast: @escaping @MainActor () -> Bool = {
         NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
       },
       onChange: @escaping @MainActor (ThemeContext) -> Void) {
    self.window = window
    self.increaseContrast = increaseContrast
    self.onChange = onChange
    super.init()
    appearanceObservation = window?.observe(\.effectiveAppearance) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.notify() }
    }
    // A selector observer is removed when the observer goes away.
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(displayOptionsChanged(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  @objc private func displayOptionsChanged(_ notification: Notification) { notify() }

  var context: ThemeContext {
    let appearance = window.map { ThemeFlavor(appearance: $0.effectiveAppearance) } ?? .light
    return ThemeContext(appearance: appearance, increaseContrast: increaseContrast())
  }

  func notify() { onChange(context) }
}
