import AppKit
internal import ArktEngineABI
import EngineAPI
import os

// MARK: - Uninstall (#721)

extension ChromiumEngine {
  private static let uninstallLog = Logger(subsystem: "dev.arkt.shell", category: "ChromiumExtensions")

  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool) {
    uninstallExtension(extensionID, reportAbuse: reportAbuse, in: nil)
  }

  /// The facade uninstalls through `ExtensionRegistrar` as a user-initiated uninstall, without Chromium's dialog (the
  /// remove sheet asked). The removal comes back as `.extensionActionsChanged` from the facade's batch; with
  /// `reportAbuse` the facade opens the Web Store's report page in `window`'s browser (the engine's last active window
  /// when it has none), which arrives as an engine tab. A refused uninstall (an unknown id, one the user may not
  /// remove) changes nothing and is only logged: the shell's call has no answer.
  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool, in window: EngineWindowID?) {
    let browser = window.flatMap { windows[$0]?.browser }
    facade.uninstallExtension(extensionID, reportAbuse: reportAbuse, in: browser) { uninstalled, reason in
      guard !uninstalled else { return }
      Self.uninstallLog.notice("uninstall refused: \(reason ?? "no reason", privacy: .public)")
    }
  }
}
