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

  var window: NSWindow { host.window }
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

  /// The window is gone: the host keeps no engine closures.
  func detach() {
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
