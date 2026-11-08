import SidebarModel

/// Routing is a profile-data settings group in the existing SQLite `setting` table, backed up with the database.
/// A missing or unreadable group uses no routes and the Little Arkt default, like other typed settings groups.
extension LinkRouting: SettingsGroup {
  public static let storageKey = "linkRouting.settings"
  public static var defaultValue: LinkRouting { LinkRouting(routes: []) }
}
