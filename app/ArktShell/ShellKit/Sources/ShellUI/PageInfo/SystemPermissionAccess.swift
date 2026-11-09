import CoreLocation
import EngineAPI

/// What macOS lets Arkt itself do for one permission, apart from any site's setting (#786). Page info shows a
/// "Turned off in macOS" state on the row only once macOS has denied access: while macOS has not decided, it still asks
/// on first use, so the stored setting is all there is to show.
enum SystemPermissionAccess: Equatable, Sendable {
  case notDetermined
  case allowed
  case denied
  /// Parental or device management controls: the user cannot grant access either.
  case restricted

  /// Whether macOS keeps the permission from every site, whatever the site's setting.
  var isDenied: Bool {
    switch self {
    case .denied, .restricted: true
    case .notDetermined, .allowed: false
    }
  }
}

/// macOS's own state for the permissions page info lists. Location only, for now: camera, microphone, notifications
/// and the clipboard follow with the shell's system permission work.
@MainActor
enum SystemPermissions {
  /// Reading the authorization status never asks the user; only a request or starting updates does, and nothing here
  /// does either.
  private static let locationManager = CLLocationManager()

  /// The location state of this app as macOS keeps it. Location Services turned off for the whole Mac leaves the
  /// app's own state as it was, so it is not counted here.
  static var location: SystemPermissionAccess {
    switch locationManager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    case .authorizedAlways: .allowed
    @unknown default: .notDetermined
    }
  }

  /// The kinds macOS denies Arkt, for `PageInfoModel`.
  static func deniedKinds() -> Set<SitePermissionKind> {
    location.isDenied ? [.location] : []
  }
}
