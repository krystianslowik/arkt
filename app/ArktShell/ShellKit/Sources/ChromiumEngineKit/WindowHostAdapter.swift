import AppKit
internal import ArktEngineABI
import EngineAPI

/// The `ArktWindowHost` object the facade sees for one `EngineWindowHosting` (W3-6).
///
/// The facade sets its three blocks when it creates the `Browser` and clears them on teardown. The adapter turns
/// them into the host's `onCloseRequested` and `forward`, and `forward` consults the host's own claims first: a
/// command the shell claims is validated and performed by the shell, every other command goes to the engine with
/// its raw `IDC_*` and `WindowOpenDisposition` values.
@MainActor
final class WindowHostAdapter: NSObject, ArktWindowHost {
  let host: any EngineWindowHosting

  init(host: any EngineWindowHosting) {
    self.host = host
  }

  /// The host's window until the engine window closes, then `detachedWindow`.
  var window: NSWindow { detachedWindow ?? host.window }
  /// A window never shown, the facade's window after `detach()`. Chromium orders its host window out when it tears a
  /// closed window down (`ArktBrowserWindow::UnbindHost`), after `.windowClosed`; by then the shell has decided about
  /// its own window: it closes it, or keeps it open when its last page moved to another window (#300).
  private var detachedWindow: NSWindow?
  var cardView: NSView { host.cardView }

  var closeRequested: (() -> Void)? {
    didSet {
      guard let closeRequested else {
        host.onCloseRequested = nil
        return
      }
      host.onCloseRequested = { closeRequested() }
    }
  }

  var validateCommand: ((Int) -> Bool)? {
    didSet { updateForwarding() }
  }

  var executeCommand: ((Int, Int) -> Void)? {
    didSet { updateForwarding() }
  }

  /// Maps a facade tab handle to the engine's Swift id; set by `ChromiumEngine` when it makes the adapter. A handle it
  /// does not list (another instance's tab) maps to nil.
  var resolveTab: (@MainActor (any ArktTabHandle) -> TabID?)?

  // MARK: Links and keys (#313)

  /// The facade asks from inside the navigation start; the host answers without calling the engine. A tab this
  /// instance does not list navigates without asking.
  func decideLinkActivation(_ activation: any ArktLinkActivation) -> ArktLinkDecision {
    guard let tab = resolveTab?(activation.tab) else { return .navigate }
    let engineActivation = EngineLinkActivation(url: activation.url, sourceTab: tab, sourceURL: activation.sourceURL,
                                                modifiers: EngineLinkModifiers(activation.modifierFlags),
                                                disposition: EngineDisposition(rawValue: activation.disposition))
    switch host.decideLinkActivation(engineActivation) {
    case .navigate: return .navigate
    case .cancel: return .cancel
    }
  }

  /// Posted by the facade after the page passed on the key.
  func unhandledKeyDown(_ event: NSEvent, in tab: (any ArktTabHandle)?) {
    _ = host.handleUnhandledKeyDown(event, in: tab.flatMap { resolveTab?($0) })
  }

  /// The window is gone: the host keeps no engine closures, and its window is no longer the facade's.
  func detach() {
    if detachedWindow == nil {
      let stand = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
      stand.isReleasedWhenClosed = false
      detachedWindow = stand
    }
    closeRequested = nil
    validateCommand = nil
    executeCommand = nil
  }

  private func updateForwarding() {
    guard let validate = validateCommand, let execute = executeCommand else {
      host.forward = nil
      return
    }
    // Weak: the closures are stored on the host itself.
    host.forward = EngineCommandForwarding(
      validate: { [weak host] command in
        if let claim = host?.claim(command) { return claim.isEnabled }
        return validate(command.rawValue)
      },
      execute: { [weak host] command, disposition in
        if let host, host.claim(command) != nil, host.perform(command, disposition: disposition) { return }
        execute(command.rawValue, disposition.rawValue)
      }
    )
  }
}
