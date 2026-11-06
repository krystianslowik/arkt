// Sidebar banner identifiers (#648). Kept beside `AXID.swift` like the other late groups; no imports, like it.
extension AXID {
  /// The notice row above the sidebar's bottom bar (`SidebarBannerView`); hidden while there is no notice.
  public enum SidebarBanner {
    /// Role: group (the status region); label: the notice ("Update ready", or the announcement's title).
    public static let root = "sidebarBanner.root"
    /// An announcement row: a button that opens the popover.
    public static let open = "sidebarBanner.open"
    /// Label: "Restart to update".
    public static let restart = "sidebarBanner.restart"
    /// Label: "Dismiss notice".
    public static let dismiss = "sidebarBanner.dismiss"
    /// The announcement popover: subrole dialog, label "What's new".
    public static let popover = "sidebarBanner.popover"
    public static let popoverAction = "sidebarBanner.popover.action"
    public static let popoverDismiss = "sidebarBanner.popover.dismiss"
  }
}
