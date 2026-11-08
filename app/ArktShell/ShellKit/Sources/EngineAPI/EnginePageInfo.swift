import Foundation

// Page info and per-site permissions (#582, part of #122): what the page info panel shows for a tab (host, connection,
// cookies and site data, the site's permissions) and the per-site permission calls that panel and Settings' per-site
// list (#133) share. `EngineClient.siteSettings` is nil by default, so an engine that has none of this offers no panel
// and the address pill stays as it is. ChromiumEngine reports it from the facade since #583.
//
// Every call is keyed by the site's origin as the engine names it (`PageInfo.origin`), never by a URL the shell
// parses: the engine decides what a site is (Chromium keys content settings by origin pattern). The calls that change
// a setting also name the tab they come from, so the engine changes that tab's profile (an Incognito tab's settings
// are not the normal profile's). `EngineEvent.pageInfoChanged` announces a change of a tab's page info.

/// How the page reached the browser, folded to what the panel tells apart.
///
/// Chromium's `security_state::SecurityLevel`, `VisibleSecurityState` and URL scheme map as: `SECURE` to `secure`;
/// `DANGEROUS` from Safe Browsing (`malicious_content_status` set) to `flagged`, else with a certificate error
/// (`cert_status` has an error) to `certificateError`, else to `notSecure`; any other level on `https:` with mixed
/// content (`displayed_mixed_content`, `contained_mixed_form`, `ran_mixed_content`) to `notFullySecure`, else to
/// `notSecure`; `file:` to `localFile`; every other scheme than `http:`, `https:` and `file:` (`chrome:`,
/// `chrome-extension:`, `about:`, `devtools:`, the new tab page) to `internalPage`.
public enum PageConnection: Equatable, Sendable {
  /// An encrypted connection with a valid certificate.
  case secure
  /// No encryption (plain `http:`).
  case notSecure
  /// An encrypted page with parts that are not encrypted (mixed content).
  case notFullySecure
  /// The certificate is not valid (expired, wrong host, untrusted issuer).
  case certificateError
  /// Safe Browsing flagged the site (phishing, malware, unwanted software).
  case flagged
  /// A file on this Mac: it has no site settings.
  case localFile
  /// A page of the browser itself: there is no page info to show.
  case internalPage
}

/// The certificate behind a secure connection, as the engine summarizes it. Every string is the engine's.
public struct CertificateSummary: Equatable, Sendable {
  /// Who it was issued to (the subject's common name).
  public var issuedTo: String
  /// Who issued it (the issuer's organization or common name).
  public var issuedBy: String
  public var validUntil: Date?

  public init(issuedTo: String, issuedBy: String, validUntil: Date? = nil) {
    self.issuedTo = issuedTo
    self.issuedBy = issuedBy
    self.validUntil = validUntil
  }
}

/// What a site may do for one permission. Chromium's `ContentSetting`: `CONTENT_SETTING_ALLOW`, `_ASK` and `_BLOCK`
/// (`_SESSION_ONLY` and `_DETECT_IMPORTANT_CONTENT` are not offered in page info).
public enum PermissionSetting: String, Equatable, Hashable, Sendable, CaseIterable {
  case allow, ask, block
}

/// The permissions page info lists, each one of Chromium's `ContentSettingsType` values. The names are the shell's
/// identifiers; the row's words come from the engine (`SitePermission.title`).
public enum SitePermissionKind: String, Equatable, Hashable, Sendable, CaseIterable {
  /// `GEOLOCATION`
  case location
  /// `MEDIASTREAM_CAMERA`
  case camera
  /// `MEDIASTREAM_MIC`
  case microphone
  /// `NOTIFICATIONS`
  case notifications
  /// `POPUPS`
  case popups
  /// `SOUND`
  case sound
  /// `JAVASCRIPT`
  case javascript
  /// `IMAGES`
  case images
  /// `AUTOMATIC_DOWNLOADS`
  case automaticDownloads
  /// `CLIPBOARD_READ_WRITE`
  case clipboard
  /// `MIDI_SYSEX`
  case midiDevices
  /// `SENSORS`
  case motionSensors
  /// `USB_GUARD`
  case usbDevices
  /// `SERIAL_GUARD`
  case serialPorts
  /// `HID_GUARD`
  case hidDevices
  /// `BLUETOOTH_GUARD`
  case bluetoothDevices
  /// `FILE_SYSTEM_WRITE_GUARD`
  case fileEditing
  /// `WINDOW_MANAGEMENT`
  case windowManagement
  /// `LOCAL_FONTS`
  case localFonts
  /// `IDLE_DETECTION`
  case idleDetection
  /// `BACKGROUND_SYNC`
  case backgroundSync
  /// `MIXEDSCRIPT`
  case insecureContent
}

/// One permission of a site as page info shows it: its current setting, whether that is the browser's default for it,
/// and the settings it can take (some permissions have no Ask: pop-ups, sound, JavaScript).
public struct SitePermission: Equatable, Sendable, Identifiable {
  public var kind: SitePermissionKind
  /// The engine's name for the permission ("Location", "Pop-ups and redirects").
  public var title: String
  public var setting: PermissionSetting
  /// The setting follows the browser's default for this permission (no exception for the site).
  public var isDefault: Bool
  /// What the pop-up offers, in the engine's order. Always contains `setting`.
  public var options: [PermissionSetting]

  public var id: SitePermissionKind { kind }

  public init(kind: SitePermissionKind, title: String, setting: PermissionSetting, isDefault: Bool,
              options: [PermissionSetting] = PermissionSetting.allCases) {
    self.kind = kind; self.title = title; self.setting = setting; self.isDefault = isDefault; self.options = options
  }
}

/// What a site keeps on this Mac: Chromium's cookie count and the storage it uses (`BrowsingDataModel`).
public struct SiteData: Equatable, Sendable {
  public var cookies: Int
  /// Bytes of site storage (local storage, IndexedDB, cache storage and the like).
  public var bytes: Int64

  public init(cookies: Int, bytes: Int64) {
    self.cookies = cookies
    self.bytes = bytes
  }

  public static let none = SiteData(cookies: 0, bytes: 0)
}

/// Everything the page info panel shows for one tab, as plain values.
public struct PageInfo: Equatable, Sendable {
  public var tab: TabID
  /// The site's identity for the per-site calls ("https://fieldguide.example").
  public var origin: String
  /// The host as the engine shows it: an IDN host stays in the form the engine chose (punycode when Chromium's IDN
  /// spoof checks decline to show Unicode). A local file shows its file name.
  public var host: String
  public var connection: PageConnection
  /// Nil without a secure connection, or when the engine does not report one.
  public var certificate: CertificateSummary?
  /// Nil while the engine is still counting, or for a page with no site (a local file, an internal page). The engine
  /// counts only while the tab's page info panel is open (`EngineSiteSettings.pageInfoDidOpen(tab:)`); a read with no
  /// panel open reports the last count it has, however old, or nil.
  public var siteData: SiteData?
  /// The site's permissions in the engine's order: the ones it changed or used, then the common ones. Empty for a
  /// local file or an internal page.
  public var permissions: [SitePermission]

  public init(tab: TabID, origin: String, host: String, connection: PageConnection,
              certificate: CertificateSummary? = nil, siteData: SiteData? = nil, permissions: [SitePermission] = []) {
    self.tab = tab; self.origin = origin; self.host = host; self.connection = connection
    self.certificate = certificate; self.siteData = siteData; self.permissions = permissions
  }

  /// Whether the page has site settings at all (false for a local file and an internal page).
  public var hasSiteSettings: Bool {
    switch connection {
    case .secure, .notSecure, .notFullySecure, .certificateError, .flagged: true
    case .localFile, .internalPage: false
    }
  }
}

/// A site with at least one permission that is not the browser's default: a row of Settings' per-site list (#133).
public struct SitePermissions: Equatable, Sendable, Identifiable {
  public var origin: String
  public var host: String
  /// Only the permissions that are not at the default.
  public var permissions: [SitePermission]

  public var id: String { origin }

  public init(origin: String, host: String, permissions: [SitePermission]) {
    self.origin = origin; self.host = host; self.permissions = permissions
  }
}

/// The engine's page info and per-site permissions. Changes apply at once: the next `pageInfo(of:)` and
/// `sitesWithPermissions()` read the new values. The reload a change needs is offered when the panel closes
/// (`pageInfoDidClose(tab:)`), as Chromium's page info does. Site data is counted only between `pageInfoDidOpen(tab:)`
/// and `pageInfoDidClose(tab:)`: counting reads the whole profile, and the address pill reads page info on every
/// refresh.
@MainActor
public protocol EngineSiteSettings: AnyObject {
  /// The page info of the tab's current page; nil for an unknown or closed tab, or a tab without a page.
  func pageInfo(of tab: TabID) -> PageInfo?
  /// Every site of the normal profile with a permission that is not at the default, sorted by host.
  func sitesWithPermissions() -> [SitePermissions]
  /// Sets one permission of the site in the profile of `tab`. A setting the permission does not offer, or the one it
  /// already has, changes nothing and announces nothing; a change is announced with `.pageInfoChanged` on every tab of
  /// the site in that profile.
  func setPermission(_ kind: SitePermissionKind, to setting: PermissionSetting, forOrigin origin: String,
                     from tab: TabID)
  /// Puts every permission of the site in the profile of `tab` back to the default: the site's own exceptions go (in
  /// Chromium the origin-scoped ones; a broader `[*.]host` exception stays, as with its page info). Cookies and site
  /// data stay.
  func resetPermissions(forOrigin origin: String, from tab: TabID)
  /// The page info panel of `tab` opened (#782). Until `pageInfoDidClose(tab:)` or the tab closing, the engine counts
  /// the site's data for this tab's reads, and announces `.pageInfoChanged` when a new count differs from the one it
  /// reported. A second call while open does nothing more.
  func pageInfoDidOpen(tab: TabID)
  /// The page info panel of `tab` closed. If a setting of its site changed while it was open, the engine raises the
  /// reload infobar (`InfobarKind.reload`) once, on that tab; otherwise nothing happens. The engine stops counting the
  /// site's data for the tab.
  func pageInfoDidClose(tab: TabID)
  /// Opens the browser's settings for the site next to `tab` (Chromium: `chrome://settings/content/siteDetails`).
  func openSiteSettings(forOrigin origin: String, from tab: TabID)
}

extension EngineSiteSettings {
  /// An engine whose site data count costs nothing to keep current ignores the signal.
  public func pageInfoDidOpen(tab: TabID) {}
}

extension EngineClient {
  public var siteSettings: (any EngineSiteSettings)? { nil }
}
