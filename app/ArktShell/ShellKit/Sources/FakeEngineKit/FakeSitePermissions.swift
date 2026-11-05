import EngineAPI
import Foundation

/// FakeEngine's per-site permissions (#582), without WebKit: WebKit's public API decides only camera and microphone
/// (`WKUIDelegate`'s media capture request), so those are the two a site lists; Ask leaves the decision to WebKit's
/// own prompt. Kept per origin, in memory, as the engine's non-persistent data store keeps everything else. Site data
/// is not counted (`WKWebsiteDataStore` reports it asynchronously), so `PageInfo.siteData` stays nil.
struct FakeSitePermissions {
  static let kinds: [SitePermissionKind] = [.camera, .microphone]
  private var exceptions: [String: [SitePermissionKind: PermissionSetting]] = [:]

  static func title(_ kind: SitePermissionKind) -> String { kind == .camera ? "Camera" : "Microphone" }

  static func origin(of url: URL) -> String? {
    guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else { return nil }
    return origin(scheme: scheme, host: host, port: url.port)
  }

  /// `scheme://host[:port]`, lowercased, without the scheme's default port (443 for `https:`, 80 for `http:`).
  static func origin(scheme: String, host: String, port: Int?) -> String? {
    let scheme = scheme.lowercased()
    let host = host.lowercased()
    guard !host.isEmpty else { return nil }
    let defaultPort = ["https": 443, "http": 80][scheme]
    guard let port, port != defaultPort else { return "\(scheme)://\(host)" }
    return "\(scheme)://\(host):\(port)"
  }

  private static func host(ofOrigin origin: String) -> String {
    let afterScheme = origin.range(of: "://").map { String(origin[$0.upperBound...]) } ?? origin
    return afterScheme.split(separator: ":").first.map(String.init) ?? afterScheme
  }

  private func permission(_ kind: SitePermissionKind, origin: String) -> SitePermission {
    let exception = exceptions[origin]?[kind]
    return SitePermission(kind: kind, title: Self.title(kind), setting: exception ?? .ask, isDefault: exception == nil)
  }

  /// `https:` is secure, or not fully secure with mixed content; `file:` a local file; a page without a host
  /// (`about:`, `data:`) internal; anything else not secure. WebKit reports no certificate error or Safe Browsing
  /// state through public API. Nil without a URL.
  func pageInfo(tab: TabID, url: URL?, hasOnlySecureContent: Bool) -> PageInfo? {
    guard let url, let scheme = url.scheme?.lowercased() else { return nil }
    if scheme == "file" {
      return PageInfo(tab: tab, origin: "file://", host: url.lastPathComponent, connection: .localFile)
    }
    guard let origin = Self.origin(of: url) else {
      return PageInfo(tab: tab, origin: url.absoluteString, host: url.absoluteString, connection: .internalPage)
    }
    let connection: PageConnection = scheme != "https" ? .notSecure : hasOnlySecureContent ? .secure : .notFullySecure
    return PageInfo(tab: tab, origin: origin, host: Self.host(ofOrigin: origin), connection: connection,
                    permissions: Self.kinds.map { permission($0, origin: origin) })
  }

  func sites() -> [SitePermissions] {
    exceptions.map { origin, settings in
      SitePermissions(origin: origin, host: Self.host(ofOrigin: origin),
                      permissions: Self.kinds.filter { settings[$0] != nil }.map { permission($0, origin: origin) })
    }.sorted { $0.host < $1.host }
  }

  /// Whether anything changed: a kind WebKit cannot decide, or the setting it already has, changes nothing.
  mutating func set(_ kind: SitePermissionKind, to setting: PermissionSetting, forOrigin origin: String) -> Bool {
    guard Self.kinds.contains(kind), permission(kind, origin: origin).setting != setting else { return false }
    exceptions[origin, default: [:]][kind] = setting == .ask ? nil : setting
    if exceptions[origin]?.isEmpty == true { exceptions[origin] = nil }
    return true
  }

  mutating func reset(forOrigin origin: String) -> Bool { exceptions.removeValue(forKey: origin) != nil }

  /// The answer to a media capture request for the devices asked: a block of any wins, then an ask, else allow.
  func mediaDecision(origin: String, camera: Bool, microphone: Bool) -> PermissionSetting {
    let asked = [camera ? SitePermissionKind.camera : nil, microphone ? .microphone : nil].compactMap { $0 }
    let settings = asked.map { permission($0, origin: origin).setting }
    if settings.contains(.block) { return .block }
    return settings.contains(.ask) || settings.isEmpty ? .ask : .allow
  }
}
