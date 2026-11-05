import EngineAPI

// Page info panel identifiers (#582). Kept beside `AXID.swift` while other open branches edit that file.
extension AXID {
  /// The page info panel (`PageInfoPanelController`).
  public enum PageInfo {
    public static let panel = "pageInfo.panel"
    public static let siteData = "pageInfo.siteData"
    public static let reset = "pageInfo.resetPermissions"
    public static let siteSettings = "pageInfo.siteSettings"
    /// The pop-up of one permission.
    public static func permission(_ kind: SitePermissionKind) -> String { "pageInfo.permission.\(kind.rawValue)" }
  }
}
