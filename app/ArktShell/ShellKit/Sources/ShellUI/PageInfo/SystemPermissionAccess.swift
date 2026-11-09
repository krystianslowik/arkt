import CoreLocation
import EngineAPI
import Foundation

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

/// Why macOS keeps a permission from every site, for the note on its page info row.
enum SystemPermissionBlock: Equatable, Sendable {
  /// macOS denies Arkt itself the permission (#786).
  case appAccess
  /// Location Services is off for the whole Mac, so no app gets the location (#856).
  case locationServices

  /// The note under the row's title.
  var note: String {
    switch self {
    case .appAccess: "Turned off in macOS"
    case .locationServices: "Location Services off"
    }
  }

  /// The note as VoiceOver reads it after the row's title: lowercase where the note is a plain phrase, the feature's
  /// name as written.
  var spokenNote: String {
    switch self {
    case .appAccess: "turned off in macOS"
    case .locationServices: note
    }
  }
}

/// Whether Location Services is on for the whole Mac, read off the main thread and cached (#856). Apple warns that
/// `CLLocationManager.locationServicesEnabled()` can block, and freeze the UI on the main thread; the cache is read
/// again when macOS reports a location change and each time page info asks, and the main actor only reads the cache.
@MainActor
final class LocationServicesState {
  /// The last value read; nil until the first read lands, when nothing is assumed.
  private(set) var isEnabled: Bool?
  /// Runs when a read changes the cached value, the first read included.
  var onChange: (@MainActor () -> Void)?
  private let read: @Sendable () -> Bool
  private var reading: Task<Void, Never>?
  /// A refresh was asked for while a read was running: that read's value may be stale, so one more follows it.
  private var readAgain = false

  /// `read` runs on the concurrent pool, never on the main thread. Tests pass their own; nothing is read until
  /// `refresh()`.
  init(read: @escaping @Sendable () -> Bool) {
    self.read = read
  }

  /// Reads the setting again off the main thread. A refresh asked for while a read is running returns nil and makes
  /// the running task read once more after it, so a change during the read is not lost; otherwise the returned task
  /// ends once the cache holds the new value.
  @discardableResult
  func refresh() -> Task<Void, Never>? {
    guard reading == nil else {
      readAgain = true
      return nil
    }
    let read = self.read
    let task = Task { [weak self] in
      var again = true
      while again {
        let value = await Self.readOffMain(read)
        guard let self else { return }
        again = self.readAgain
        self.readAgain = false
        if again == false { self.reading = nil }
        if value != self.isEnabled {
          self.isEnabled = value
          self.onChange?()
        }
      }
    }
    reading = task
    return task
  }

  @concurrent
  private nonisolated static func readOffMain(_ read: @Sendable () -> Bool) async -> Bool {
    read()
  }
}

/// macOS's own state for the permissions page info lists. Location only, for now: camera, microphone, notifications
/// and the clipboard follow with the shell's system permission work.
@MainActor
enum SystemPermissions {
  /// Posted on the main thread when the cached macOS state changed; an open page info panel reads it again.
  nonisolated static let didChange = Notification.Name("ArktSystemPermissionsDidChange")

  /// Reading the authorization status never asks the user; only a request or starting updates does, and nothing here
  /// does either. Its delegate rereads Location Services whenever macOS reports a change, and once at creation.
  private static let locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = locationDelegate
    return manager
  }()
  private static let locationDelegate = LocationManagerDelegate()

  /// Location Services for the whole Mac, cached (#856).
  private static let locationServices: LocationServicesState = {
    let state = LocationServicesState(read: { CLLocationManager.locationServicesEnabled() })
    state.onChange = { NotificationCenter.default.post(name: didChange, object: nil) }
    return state
  }()

  /// The location state of this app as macOS keeps it. macOS also reports `.denied` while Location Services is off for
  /// the whole Mac (`CLLocationManager.h`), so `blocks` asks `locationServices` which of the two it is.
  static var location: SystemPermissionAccess {
    switch locationManager.authorizationStatus {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    case .authorizedAlways: .allowed
    @unknown default: .notDetermined
    }
  }

  /// Which permissions macOS keeps from every site, and why. Location Services off for the whole Mac wins over the
  /// app's own state: no site gets the location either way, and it is the setting the user has to change. Until the
  /// first read of Location Services lands (`nil`), `.denied` shows no note: macOS reports it for both causes, and
  /// guessing would flash "Turned off in macOS" before the read says otherwise. `.restricted` is never Location
  /// Services, so it shows at once.
  nonisolated static func blocks(location: SystemPermissionAccess,
                                 locationServicesEnabled: Bool?) -> [SitePermissionKind: SystemPermissionBlock] {
    switch (locationServicesEnabled, location) {
    case (false, _): [.location: .locationServices]
    case (nil, .denied): [:]
    case (_, let access) where access.isDenied: [.location: .appAccess]
    default: [:]
    }
  }

  /// The permissions macOS keeps from every site now, for `PageInfoModel`. Returns the cached Location Services state
  /// and reads it again off the main thread; a changed value posts `didChange`.
  static func blockedKinds() -> [SitePermissionKind: SystemPermissionBlock] {
    let access = location                       // creates the manager, whose delegate starts the first read
    locationServices.refresh()
    return blocks(location: access, locationServicesEnabled: locationServices.isEnabled)
  }

  fileprivate static func locationAuthorizationDidChange() {
    locationServices.refresh()
  }
}

/// The location manager's delegate. macOS calls it on the thread that made the manager, the main thread, when the
/// manager is made and when the app's authorization changes, which includes Location Services going on or off.
private final class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in SystemPermissions.locationAuthorizationDidChange() }
  }
}
