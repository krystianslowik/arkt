import EngineAPI
import Foundation

// Page info and per-site permissions (#582). The connection follows the scheme (`https:` secure, `file:` a local
// file, the browser's own schemes internal, any other site not secure) unless a test sets it; permissions are kept per
// origin as exceptions to the defaults below, as Chromium's content settings map keeps them. Titles are this engine's
// stand-ins for the engine's strings.
extension InMemoryEngine: EngineSiteSettings {
  public var siteSettings: (any EngineSiteSettings)? { self }

  /// The permissions every site lists, in this order; others follow once the site has a setting for them.
  static let commonPermissions: [SitePermissionKind] = [.location, .camera, .microphone, .notifications]
  /// Schemes of the browser's own pages.
  static let internalSchemes: Set<String> = ["about", "chrome", "chrome-extension", "chrome-untrusted", "devtools",
                                             "arkt"]
  static let reloadMessage = "To apply your updated settings to this site, reload this page"

  /// The browser's default for each permission, and what it offers (no Ask for content a page shows on its own).
  static func defaultSetting(_ kind: SitePermissionKind) -> PermissionSetting {
    switch kind {
    case .sound, .javascript, .images, .backgroundSync, .motionSensors: .allow
    case .popups, .insecureContent: .block
    default: .ask
    }
  }

  static func options(_ kind: SitePermissionKind) -> [PermissionSetting] {
    switch kind {
    case .sound, .javascript, .images, .backgroundSync, .motionSensors, .popups, .insecureContent: [.allow, .block]
    default: PermissionSetting.allCases
    }
  }

  static func title(_ kind: SitePermissionKind) -> String {
    switch kind {
    case .location: "Location"
    case .camera: "Camera"
    case .microphone: "Microphone"
    case .notifications: "Notifications"
    case .popups: "Pop-ups and redirects"
    case .sound: "Sound"
    case .javascript: "JavaScript"
    case .images: "Images"
    case .automaticDownloads: "Automatic downloads"
    case .clipboard: "Clipboard"
    case .midiDevices: "MIDI devices"
    case .motionSensors: "Motion sensors"
    case .usbDevices: "USB devices"
    case .serialPorts: "Serial ports"
    case .hidDevices: "HID devices"
    case .bluetoothDevices: "Bluetooth devices"
    case .fileEditing: "File editing"
    case .windowManagement: "Window management"
    case .localFonts: "Fonts"
    case .idleDetection: "Your device use"
    case .backgroundSync: "Background sync"
    case .insecureContent: "Insecure content"
    }
  }

  /// The origin a URL belongs to: `scheme://host[:port]`, `file://` for every local file, nil without a host.
  static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased() else { return nil }
    if scheme == "file" { return "file://" }
    guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
    return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
  }

  private static func host(ofOrigin origin: String) -> String {
    origin.range(of: "://").map { String(origin[$0.upperBound...]) } ?? origin
  }

  private func permission(_ kind: SitePermissionKind, origin: String) -> SitePermission {
    let exception = siteExceptions[origin]?[kind]
    return SitePermission(kind: kind, title: Self.title(kind), setting: exception ?? Self.defaultSetting(kind),
                          isDefault: exception == nil, options: Self.options(kind))
  }

  public func pageInfo(of tab: TabID) -> PageInfo? {
    guard let url = snapshots[tab]?.url, let scheme = url.scheme?.lowercased() else { return nil }
    if scheme == "file" {
      return PageInfo(tab: tab, origin: "file://", host: url.lastPathComponent, connection: .localFile)
    }
    guard !Self.internalSchemes.contains(scheme), let origin = Self.origin(of: url) else {
      return PageInfo(tab: tab, origin: url.absoluteString, host: url.absoluteString, connection: .internalPage)
    }
    let override = connectionOverrides[tab]
    let connection = override?.connection ?? (scheme == "https" ? .secure : .notSecure)
    let changed = SitePermissionKind.allCases.filter {
      !Self.commonPermissions.contains($0) && siteExceptions[origin]?[$0] != nil
    }
    return PageInfo(tab: tab, origin: origin, host: Self.host(ofOrigin: origin), connection: connection,
                    certificate: override?.certificate, siteData: siteDataByOrigin[origin] ?? SiteData.none,
                    permissions: (Self.commonPermissions + changed).map { permission($0, origin: origin) })
  }

  public func sitesWithPermissions() -> [SitePermissions] {
    siteExceptions.filter { !$0.value.isEmpty }.map { origin, exceptions in
      SitePermissions(origin: origin, host: Self.host(ofOrigin: origin),
                      permissions: SitePermissionKind.allCases.filter { exceptions[$0] != nil }
                        .map { permission($0, origin: origin) })
    }.sorted { $0.host < $1.host }
  }

  public func setPermission(_ kind: SitePermissionKind, to setting: PermissionSetting, forOrigin origin: String) {
    guard Self.options(kind).contains(setting), permission(kind, origin: origin).setting != setting else { return }
    siteExceptions[origin, default: [:]][kind] = setting == Self.defaultSetting(kind) ? nil : setting
    if siteExceptions[origin]?.isEmpty == true { siteExceptions[origin] = nil }
    raiseReloadInfobars(forOrigin: origin)
  }

  public func resetPermissions(forOrigin origin: String) {
    guard siteExceptions.removeValue(forKey: origin) != nil else { return }
    raiseReloadInfobars(forOrigin: origin)
  }

  public func openSiteSettings(forOrigin origin: String, from tab: TabID) {
    openedSiteSettings.append((origin, tab))
  }

  /// The reload infobar on every tab showing the site, unless one is already up there.
  private func raiseReloadInfobars(forOrigin origin: String) {
    for tab in tabIDs where snapshots[tab]?.url.flatMap(Self.origin(of:)) == origin {
      guard infobars[tab]?.contains(where: { $0.kind == .reload }) != true else { continue }
      _ = raiseInfobar(in: tab, message: Self.reloadMessage, kind: .reload, okTitle: "Reload", cancelTitle: nil)
    }
  }

  // MARK: Test drivers

  /// Test hook: the tab's connection as the engine would report it (a certificate error, a flagged page).
  public func setConnection(_ tab: TabID, _ connection: PageConnection, certificate: CertificateSummary? = nil) {
    connectionOverrides[tab] = (connection, certificate)
  }

  /// Test hook: what the site keeps on this Mac.
  public func setSiteData(_ data: SiteData, forOrigin origin: String) {
    siteDataByOrigin[origin] = data
  }

  /// The tab's reported infobars, in order.
  public func infobars(of tab: TabID) -> [Infobar] { infobars[tab] ?? [] }
}
