import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Installed list, enable, developer mode, Load unpacked (#964, the engine side of #600)

extension ChromiumEngine {
  /// The facade lists the profile's extensions from `ExtensionRegistry` (enabled, disabled and terminated; no component
  /// or hidden ones; blocklisted ones left out), sorted by name, with icons that arrive after a first listing (an
  /// `.installedExtensionsChanged` follows each).
  public var installedExtensions: [InstalledExtensionInfo] {
    facade.installedExtensions.map { item in
      InstalledExtensionInfo(id: item.extensionID, name: item.name, version: item.version,
                             description: item.shortDescription, iconPNG: item.iconPNG, isEnabled: item.isEnabled,
                             canDisable: item.mayChangeEnabled, canUninstall: item.canUninstall,
                             origin: Self.origin(of: item.source), hasOptionsPage: item.hasOptionsPage)
    }
  }

  /// The facade applies the checks Chrome's extensions page makes (management policy) and answers synchronously. A
  /// policy refusal and an extension waiting for permission approval (Chrome's re-enable prompt, which the engine does
  /// not grant silently) are both `.refused`.
  public func setExtensionEnabled(_ extensionID: String, enabled: Bool) -> ExtensionEnableResult {
    switch facade.setExtensionEnabled(extensionID, enabled: enabled) {
    case .applied: .applied
    case .unknownExtension: .unknownExtension
    case .notAllowed, .needsPermissionApproval: .refused
    @unknown default: .refused
    }
  }

  /// Chromium's `extensions.ui.developer_mode` pref, as the facade reads it.
  public var isExtensionDeveloperModeEnabled: Bool { facade.extensionDeveloperMode }

  /// Turning it off also disables the extensions loaded with Load unpacked, as Chrome does; turning it on enables
  /// them again. Each change arrives as `.installedExtensionsChanged`.
  public func setExtensionDeveloperModeEnabled(_ enabled: Bool) {
    facade.extensionDeveloperMode = enabled
  }

  /// The facade's sentence when developer mode is off (`loadUnpackedExtensionAtPath:completion:`).
  static let developerModeOffReason = "Developer mode is off."

  /// Asks the facade only while developer mode is on; a facade that finds it off meanwhile answers with its own
  /// sentence, which maps to `.developerModeOff` too.
  public func loadUnpackedExtension(at folder: URL) async -> UnpackedExtensionResult {
    guard facade.extensionDeveloperMode else { return .developerModeOff }
    return await withCheckedContinuation { continuation in
      facade.loadUnpackedExtension(atPath: folder.path) { extensionID, reason in
        if let extensionID {
          continuation.resume(returning: .loaded(extensionID: extensionID))
        } else if reason == Self.developerModeOffReason {
          continuation.resume(returning: .developerModeOff)
        } else {
          continuation.resume(returning: .failed(reason: reason ?? ""))
        }
      }
    }
  }

  /// The facade opens it in the profile's last active window.
  public func openExtensionOptionsPage(_ extensionID: String) {
    facade.openExtensionOptionsPage(extensionID, in: nil)
  }

  private static func origin(of source: ArktExtensionSource) -> ExtensionOrigin {
    switch source {
    case .webStore: .webStore
    case .unpacked: .unpacked
    case .policy: .policy
    case .other: .other
    @unknown default: .other
    }
  }
}
