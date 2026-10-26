import AppKit

/// The first run over this window (onboarding spec): presented by the app on the first window of a profile with no
/// Space (or resumed), and by Help > Welcome to Arkt on the key window. While it shows, the browser's views are hidden
/// from VoiceOver and the key loop, and the window's menu items are disabled.
extension ShellWindowController {
  /// The first run's window: at least 1000 x 680 pt, clamped to the screen's visible frame (decision 7).
  public static let onboardingMinimumSize = NSSize(width: 1000, height: 680)

  public var isShowingOnboarding: Bool { onboarding != nil }

  /// Covers the window with the flow and starts it. Only one window runs it; a second call returns the running one.
  @discardableResult
  public func presentOnboarding(services: any OnboardingServices, options: OnboardingController.Options,
                                stage: any OnboardingStage = CoreAnimationOnboardingStage()) -> OnboardingController {
    if let onboarding { return onboarding }
    if options.mode == .firstRun { fitWindowForOnboarding() }
    let controller = OnboardingController(window: self, services: services, options: options, stage: stage)
    onboarding = controller
    commandBar.hide()
    controller.start()
    return controller
  }

  /// Grows the window to at least `onboardingMinimumSize`, never past the screen's visible frame, keeping it centred
  /// where it was.
  func fitWindowForOnboarding() {
    guard let window else { return }
    let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    var frame = window.frame
    let width = min(max(frame.width, Self.onboardingMinimumSize.width), visible.width)
    let height = min(max(frame.height, Self.onboardingMinimumSize.height), visible.height)
    frame = NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - width)
    frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - height)
    window.setFrame(frame, display: false)
  }

  func onboardingDidFinish() {
    onboarding = nil
  }

  public func windowDidChangeOcclusionState(_ notification: Notification) {
    let visible = window?.occlusionState.contains(.visible) ?? false
    onboarding?.windowVisibilityChanged(visible && window?.isMiniaturized == false)
  }

  public func windowDidMiniaturize(_ notification: Notification) {
    onboarding?.windowVisibilityChanged(false)
  }
}
