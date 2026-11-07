import AppKit
import ArktEngineABI

// Page info and per-site permissions (#583) as the real facade reports them: plain values read from one profile's
// content settings, changes applied at once and announced with one `PageInfoChanged` per call on every tab of the
// origin, and the reload infobar added when the panel of a tab with a change closes.

final class ScriptedSitePermission: NSObject, ArktSitePermission {
  let kind: ArktSitePermissionKind
  let title: String
  let setting: ArktPermissionSetting
  let isDefault: Bool
  let options: [NSNumber]

  init(kind: ArktSitePermissionKind, title: String, setting: ArktPermissionSetting, isDefault: Bool,
       options: [ArktPermissionSetting]) {
    self.kind = kind; self.title = title; self.setting = setting; self.isDefault = isDefault
    self.options = options.map { NSNumber(value: $0.rawValue) }
  }
}

final class ScriptedPageInfo: NSObject, ArktPageInfo {
  let origin: String
  let host: String
  var connection: ArktPageConnection
  var certificateIssuedTo: String?
  var certificateIssuedBy: String?
  var certificateValidUntil: Date?
  var hasSiteData = false
  var siteDataCookies = 0
  var siteDataBytes: Int64 = 0
  var permissions: [any ArktSitePermission] = []

  init(origin: String, host: String, connection: ArktPageConnection) {
    self.origin = origin; self.host = host; self.connection = connection
  }
}

final class ScriptedSitePermissions: NSObject, ArktSitePermissions {
  let origin: String
  let host: String
  let permissions: [any ArktSitePermission]

  init(origin: String, host: String, permissions: [any ArktSitePermission]) {
    self.origin = origin; self.host = host; self.permissions = permissions
  }
}

/// One profile's content settings, as the facade's `PageInfoHub` reads them.
@MainActor
final class ScriptedSiteSettings {
  /// The site's exceptions, by origin.
  var exceptions: [String: [ArktSitePermissionKind: ArktPermissionSetting]] = [:]
  /// What the site keeps; a missing origin is still being counted (`hasSiteData` NO).
  var siteData: [String: (cookies: Int, bytes: Int64)] = [:]
  /// A tab's connection when it is not the scheme's (a certificate error, mixed content).
  var connections: [ObjectIdentifier: ArktPageConnection] = [:]
  /// The certificate a secure page reports.
  var certificate: (issuedTo: String, issuedBy: String, validUntil: Date)?
  /// Tabs with a change of their own site since their panel last closed.
  var pendingReloads: Set<ObjectIdentifier> = []
  private(set) var openedSiteSettings: [(origin: String, tab: Int32)] = []
  /// The connection last reported per tab, seeded when the tab is bound (the facade's `TabObserver::Seed`).
  private var reportedConnections: [ObjectIdentifier: ArktPageConnection?] = [:]
  private(set) var closes = 0

  static let commonKinds: [ArktSitePermissionKind] = [.location, .camera, .microphone, .notifications]
  static let allKinds: [ArktSitePermissionKind] = (0...21).compactMap { ArktSitePermissionKind(rawValue: $0) }
  static let internalSchemes: Set<String> = ["about", "chrome", "chrome-extension", "chrome-untrusted", "devtools",
                                             "view-source", "data"]

  /// Chromium's defaults on macOS.
  static func defaultSetting(_ kind: ArktSitePermissionKind) -> ArktPermissionSetting {
    switch kind {
    case .sound, .javaScript, .images, .motionSensors, .backgroundSync: .allow
    case .popups, .insecureContent: .block
    default: .ask
    }
  }

  /// The content settings registry's valid settings.
  static func options(_ kind: ArktSitePermissionKind) -> [ArktPermissionSetting] {
    switch kind {
    case .sound, .javaScript, .images, .motionSensors, .backgroundSync, .popups, .insecureContent: [.allow, .block]
    case .usbDevices, .serialPorts, .hidDevices, .bluetoothDevices, .fileEditing: [.ask, .block]
    default: [.allow, .ask, .block]
    }
  }

  static func title(_ kind: ArktSitePermissionKind) -> String {
    switch kind {
    case .location: "Location"
    case .camera: "Camera"
    case .microphone: "Microphone"
    case .notifications: "Notifications"
    case .popups: "Pop-ups and redirects"
    case .sound: "Sound"
    case .javaScript: "JavaScript"
    case .images: "Images"
    default: "Permission \(kind.rawValue)"
    }
  }

  /// `url::Origin::Serialize()` of a site's URL; nil for a local file and the browser's own pages.
  static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), scheme != "file", !internalSchemes.contains(scheme),
          let host = url.host?.lowercased() else { return nil }
    return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
  }

  func permission(_ kind: ArktSitePermissionKind, origin: String) -> ScriptedSitePermission {
    let exception = exceptions[origin]?[kind]
    return ScriptedSitePermission(kind: kind, title: Self.title(kind), setting: exception ?? Self.defaultSetting(kind),
                                  isDefault: exception == nil, options: Self.options(kind))
  }

  func pageInfo(of tab: ScriptedTab) -> ScriptedPageInfo? {
    guard tab.owner != nil, let url = tab.url, let scheme = url.scheme?.lowercased() else { return nil }
    if scheme == "file" { return ScriptedPageInfo(origin: "file://", host: url.lastPathComponent, connection: .localFile) }
    guard let origin = Self.origin(of: url) else {
      return ScriptedPageInfo(origin: url.absoluteString, host: url.absoluteString, connection: .internalPage)
    }
    let connection = connections[ObjectIdentifier(tab)] ?? (scheme == "https" ? .secure : .notSecure)
    let info = ScriptedPageInfo(origin: origin, host: url.host ?? origin, connection: connection)
    if connection == .secure, let certificate {
      info.certificateIssuedTo = certificate.issuedTo
      info.certificateIssuedBy = certificate.issuedBy
      info.certificateValidUntil = certificate.validUntil
    }
    if let data = siteData[origin] {
      info.hasSiteData = true
      info.siteDataCookies = data.cookies
      info.siteDataBytes = data.bytes
    }
    let others = Self.allKinds.filter { !Self.commonKinds.contains($0) && exceptions[origin]?[$0] != nil }
    info.permissions = (Self.commonKinds + others).map { permission($0, origin: origin) }
    return info
  }

  func sites() -> [any ArktSitePermissions] {
    exceptions.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { origin, kinds in
      let host = URL(string: origin)?.host ?? origin
      return ScriptedSitePermissions(origin: origin, host: host, permissions: Self.allKinds.filter { kinds[$0] != nil }
        .map { permission($0, origin: origin) })
    }
  }

  func set(_ kind: ArktSitePermissionKind, to setting: ArktPermissionSetting, origin: String, from tab: ScriptedTab) {
    guard Self.options(kind).contains(setting), permission(kind, origin: origin).setting != setting else { return }
    exceptions[origin, default: [:]][kind] = setting == Self.defaultSetting(kind) ? nil : setting
    if exceptions[origin]?.isEmpty == true { exceptions[origin] = nil }
    changed(origin, from: tab, needsReload: kind != .sound)
  }

  func reset(origin: String, from tab: ScriptedTab) {
    guard exceptions.removeValue(forKey: origin) != nil else { return }
    changed(origin, from: tab, needsReload: true)
  }

  func connection(of tab: ScriptedTab) -> ArktPageConnection? { pageInfo(of: tab)?.connection }

  func bound(_ tab: ScriptedTab) { reportedConnections[ObjectIdentifier(tab)] = connection(of: tab) }

  /// A committed cross-document navigation of the primary main frame (`PrimaryPageChanged`): the tab's page info
  /// session ends without its reload infobar.
  func primaryPageChanged(_ tab: ScriptedTab) { pendingReloads.remove(ObjectIdentifier(tab)) }

  /// `DidChangeVisibleSecurityState`: `PageInfoChanged` when the folded connection differs from the last one reported.
  func securityStateChanged(_ tab: ScriptedTab) {
    let now = connection(of: tab)
    let key = ObjectIdentifier(tab)
    // An unseeded tab only takes the first report as its baseline, as the facade did before the seed.
    guard let reported = reportedConnections[key] else { reportedConnections[key] = now; return }
    guard reported != now else { return }
    reportedConnections[key] = now
    tab.record(.pageInfoChanged)
  }

  func closed(_ tab: ScriptedTab) {
    closes += 1
    guard pendingReloads.remove(ObjectIdentifier(tab)) != nil, tab.owner != nil else { return }
    tab.addInfobar("To apply your updated settings to this site, reload this page") {
      $0.kind = .reload; $0.okTitle = "Reload"; $0.cancelTitle = nil
    }
  }

  func openSiteSettings(origin: String, from tab: ScriptedTab) {
    openedSiteSettings.append((origin, tab.sessionId))
  }

  /// A change counts for the reload infobar of its own site's tab, and is announced on every tab of the origin.
  private func changed(_ origin: String, from tab: ScriptedTab, needsReload: Bool) {
    if needsReload, tab.url.flatMap(Self.origin(of:)) == origin { pendingReloads.insert(ObjectIdentifier(tab)) }
    for other in tab.facade.browserList.flatMap(\.tabList) where other.url.flatMap(Self.origin(of:)) == origin {
      other.record(.pageInfoChanged)
    }
  }
}

extension ScriptedTab {
  var pageInfo: (any ArktPageInfo)? { facade.siteSettings.pageInfo(of: self) }

  func setPermission(_ kind: ArktSitePermissionKind, to setting: ArktPermissionSetting, forOrigin origin: String) {
    facade.siteSettings.set(kind, to: setting, origin: origin, from: self)
  }

  func resetPermissions(forOrigin origin: String) { facade.siteSettings.reset(origin: origin, from: self) }

  func pageInfoDidClose() { facade.siteSettings.closed(self) }

  func openSiteSettings(forOrigin origin: String) { facade.siteSettings.openSiteSettings(origin: origin, from: self) }

  /// The site data count arrived: `PageInfoChanged` on this tab.
  func pageInfoUpdated() { record(.pageInfoChanged) }

  /// The connection's security state changed (mixed content, a certificate decision, a Safe Browsing verdict).
  func securityStateChanged() { facade.siteSettings.securityStateChanged(self) }
}

extension ScriptedFacade {
  var sitesWithPermissions: [any ArktSitePermissions] { siteSettings.sites() }
}
