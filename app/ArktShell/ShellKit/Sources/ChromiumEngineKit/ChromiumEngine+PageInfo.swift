import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Page info and per-site permissions (#583, the engine side of #582)

/// The facade reads page info from the tab's profile (its content settings and the connection's security state) and
/// applies changes through Chromium's own page info, which also decides the reload infobar when the panel closes.
/// Every call names a tab; a closed or unknown tab answers nil and changes nothing.
extension ChromiumEngine: EngineSiteSettings {
  public var siteSettings: (any EngineSiteSettings)? { self }

  public func pageInfo(of tab: TabID) -> PageInfo? {
    guard let info = tabs[tab]?.handle.pageInfo else { return nil }
    return PageInfo(facade: info, tab: tab)
  }

  public func sitesWithPermissions() -> [SitePermissions] {
    facade.sitesWithPermissions.map(SitePermissions.init(facade:))
  }

  public func setPermission(_ kind: SitePermissionKind, to setting: PermissionSetting, forOrigin origin: String,
                            from tab: TabID) {
    tabs[tab]?.handle.setPermission(kind.facade, to: setting.facade, forOrigin: origin)
  }

  public func resetPermissions(forOrigin origin: String, from tab: TabID) {
    tabs[tab]?.handle.resetPermissions(forOrigin: origin)
  }

  /// The facade counts site data (`BrowsingDataModel::BuildFromDisk`, the whole profile) only while a panel is open.
  public func pageInfoDidOpen(tab: TabID) {
    tabs[tab]?.handle.pageInfoDidOpen()
  }

  public func pageInfoDidClose(tab: TabID) {
    tabs[tab]?.handle.pageInfoDidClose()
  }

  public func openSiteSettings(forOrigin origin: String, from tab: TabID) {
    tabs[tab]?.handle.openSiteSettings(forOrigin: origin)
  }
}

extension PageInfo {
  init(facade info: any ArktPageInfo, tab: TabID) {
    var certificate: CertificateSummary?
    if let issuedTo = info.certificateIssuedTo {
      certificate = CertificateSummary(issuedTo: issuedTo, issuedBy: info.certificateIssuedBy ?? "",
                                       validUntil: info.certificateValidUntil)
    }
    self.init(tab: tab, origin: info.origin, host: info.host, connection: PageConnection(facade: info.connection),
              certificate: certificate,
              siteData: info.hasSiteData ? SiteData(cookies: info.siteDataCookies, bytes: info.siteDataBytes) : nil,
              permissions: info.permissions.compactMap(SitePermission.init(facade:)))
  }
}

extension SitePermissions {
  init(facade site: any ArktSitePermissions) {
    self.init(origin: site.origin, host: site.host, permissions: site.permissions.compactMap(SitePermission.init(facade:)))
  }
}

extension SitePermission {
  /// Nil for a kind this build does not know (a newer facade).
  init?(facade permission: any ArktSitePermission) {
    guard let kind = SitePermissionKind(facade: permission.kind) else { return nil }
    let setting = PermissionSetting(facade: permission.setting)
    var options = permission.options.compactMap { ArktPermissionSetting(rawValue: $0.intValue) }
      .map(PermissionSetting.init(facade:))
    if !options.contains(setting) { options.append(setting) }
    self.init(kind: kind, title: permission.title, setting: setting, isDefault: permission.isDefault,
              options: options)
  }
}
