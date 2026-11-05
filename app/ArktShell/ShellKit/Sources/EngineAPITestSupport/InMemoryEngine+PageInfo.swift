import EngineAPI
import Foundation

// Page info and per-site permissions (#582). The connection follows the scheme (`https:` secure, `file:` a local
// file, the browser's own schemes internal, any other site not secure) unless a test sets it; permissions are kept per
// origin as exceptions to the defaults below, as Chromium's content settings map keeps them. One profile: the tab a
// change comes from only decides where the reload infobar goes when its panel closes. Titles are this engine's
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
    let siteData: SiteData? = if let entry = siteDataByOrigin[origin] { entry } else { SiteData.none }
    return PageInfo(tab: tab, origin: origin, host: Self.host(ofOrigin: origin), connection: connection,
                    certificate: override?.certificate, siteData: siteData,
                    permissions: (Self.commonPermissions + changed).map { permission($0, origin: origin) })
  }

  public func sitesWithPermissions() -> [SitePermissions] {
    siteExceptions.filter { !$0.value.isEmpty }.map { origin, exceptions in
      SitePermissions(origin: origin, host: Self.host(ofOrigin: origin),
                      permissions: SitePermissionKind.allCases.filter { exceptions[$0] != nil }
                        .map { permission($0, origin: origin) })
    }.sorted { $0.host < $1.host }
  }

  public func setPermission(_ kind: SitePermissionKind, to setting: PermissionSetting, forOrigin origin: String,
                            from tab: TabID) {
    guard Self.options(kind).contains(setting), permission(kind, origin: origin).setting != setting else { return }
    siteExceptions[origin, default: [:]][kind] = setting == Self.defaultSetting(kind) ? nil : setting
    if siteExceptions[origin]?.isEmpty == true { siteExceptions[origin] = nil }
    changed(origin, from: tab)
  }

  public func resetPermissions(forOrigin origin: String, from tab: TabID) {
    guard siteExceptions.removeValue(forKey: origin) != nil else { return }
    changed(origin, from: tab)
  }

  public func pageInfoDidClose(tab: TabID) {
    guard pendingReloads.remove(tab) != nil, snapshots[tab] != nil,
          infobars[tab]?.contains(where: { $0.kind == .reload }) != true else { return }
    _ = raiseInfobar(in: tab, message: Self.reloadMessage, kind: .reload, okTitle: "Reload", cancelTitle: nil)
  }

  public func openSiteSettings(forOrigin origin: String, from tab: TabID) {
    openedSiteSettings.append((origin, tab))
  }

  /// A setting of the site changed from `tab`: its panel offers a reload when it closes, and every tab of the site
  /// hears of it.
  private func changed(_ origin: String, from tab: TabID) {
    if snapshots[tab] != nil { pendingReloads.insert(tab) }
    announce(origin)
  }

  private func announce(_ origin: String) {
    for tab in tabIDs where snapshots[tab]?.url.flatMap(Self.origin(of:)) == origin {
      hub.emit(.pageInfoChanged(tab))
    }
  }

  // MARK: Test drivers

  /// Test hook: the tab's connection as the engine would report it (a certificate error, a flagged page).
  public func setConnection(_ tab: TabID, _ connection: PageConnection, certificate: CertificateSummary? = nil) {
    connectionOverrides[tab] = (connection, certificate)
    if snapshots[tab] != nil { hub.emit(.pageInfoChanged(tab)) }
  }

  /// Test hook: what the site keeps on this Mac; nil while the engine is still counting.
  public func setSiteData(_ data: SiteData?, forOrigin origin: String) {
    siteDataByOrigin[origin] = .some(data)
    announce(origin)
  }

  /// The tab's reported infobars, in order.
  public func infobars(of tab: TabID) -> [Infobar] { infobars[tab] ?? [] }
}
