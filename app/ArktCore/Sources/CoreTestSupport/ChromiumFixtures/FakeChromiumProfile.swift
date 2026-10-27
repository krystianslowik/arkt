import CryptoKit
import Foundation

/// Writes a fake Chromium-family profile (History, Login Data, Network/Cookies, Bookmarks, Preferences and Secure
/// Preferences) into a directory, for the Arc import reader tests (#131). All content is invented and encrypted with
/// a fixture-only key; no real browser data or Keychain item is involved.
public enum FakeChromiumProfile {
  public enum CookieFormat: Sendable {
    /// Cookies `meta` version 24: each plaintext value is prefixed with SHA-256 of `host_key` before encryption.
    case v24
    /// Cookies `meta` version 23: values are encrypted without that prefix.
    case v23
  }

  public enum BookmarksVariant: Sendable {
    case populated
    /// All three roots present with no children.
    case empty
  }

  public enum SchemaDrift: Sendable {
    case none
    /// One unknown extra column in each of `urls`, `logins` and `cookies`.
    case extraColumn
    /// One optional column missing from each of `visits`, `logins` and `cookies`.
    case missingOptionalColumn
  }

  public struct Options: Sendable {
    public var cookieFormat: CookieFormat = .v24
    public var bookmarks: BookmarksVariant = .populated
    public var drift: SchemaDrift = .none
    /// Cookies and logins written after the fixed ones (an engine check needs a cookie for 127.0.0.1 that does not
    /// expire in the past, which the fixed ones do).
    public var extraCookies: [FixtureManifest.Cookie] = []
    public var extraLogins: [FixtureManifest.Login] = []

    public init(
      cookieFormat: CookieFormat = .v24, bookmarks: BookmarksVariant = .populated, drift: SchemaDrift = .none,
      extraCookies: [FixtureManifest.Cookie] = [], extraLogins: [FixtureManifest.Login] = []
    ) {
      self.cookieFormat = cookieFormat
      self.bookmarks = bookmarks
      self.drift = drift
      self.extraCookies = extraCookies
      self.extraLogins = extraLogins
    }
  }

  /// The invented Safe Storage secret the values are encrypted with.
  public static let safeStoragePassword = "fixture-password"
  public static let extraColumnName = "fixture_extra"

  /// Writes the profile files into `directory` (created when missing) and returns what was written.
  public static func make(at directory: URL, options: Options = Options()) throws -> FixtureManifest {
    let fileManager = FileManager.default
    let network = directory.appendingPathComponent("Network", isDirectory: true)
    try fileManager.createDirectory(at: network, withIntermediateDirectories: true)
    let key = try ChromiumV10.deriveKey(password: safeStoragePassword)

    var extra: [String] = []
    var missing: [String] = []
    func columns(
      _ table: String, _ all: [FixtureDatabase.Column], addsExtra: Bool = true, drops optional: String? = nil
    ) -> [FixtureDatabase.Column] {
      switch options.drift {
      case .none:
        return all
      case .extraColumn:
        guard addsExtra else { return all }
        extra.append("\(table).\(extraColumnName)")
        return all + [.init(name: extraColumnName, type: "TEXT", defaultSQL: "''")]
      case .missingOptionalColumn:
        guard let optional else { return all }
        missing.append("\(table).\(optional)")
        return all.filter { $0.name != optional }
      }
    }

    let historyURL = directory.appendingPathComponent("History")
    let history = FixtureData.history
    try writeHistory(
      to: historyURL, entries: history,
      urlColumns: columns("urls", HistorySchema.urls),
      visitColumns: columns("visits", HistorySchema.visits, addsExtra: false, drops: "visit_duration")
    )

    let loginDataURL = directory.appendingPathComponent("Login Data")
    let logins = FixtureData.logins + options.extraLogins
    try writeLogins(
      to: loginDataURL, logins: logins, key: key,
      columns: columns("logins", LoginsSchema.logins, drops: "date_password_modified")
    )

    let cookiesURL = network.appendingPathComponent("Cookies")
    let cookies = FixtureData.cookies + options.extraCookies
    let hostPrefixed = options.cookieFormat == .v24
    try writeCookies(
      to: cookiesURL, cookies: cookies, key: key, version: hostPrefixed ? 24 : 23, hostPrefixed: hostPrefixed,
      columns: columns("cookies", CookiesSchema.cookies, drops: "source_type")
    )

    let bookmarksURL = directory.appendingPathComponent("Bookmarks")
    let bookmarks = options.bookmarks == .populated ? FixtureData.bookmarks : []
    try BookmarksWriter.write(bookmarks, to: bookmarksURL)

    let extensions = FixtureData.extensions
    let preferencesURL = directory.appendingPathComponent("Preferences")
    let securePreferencesURL = directory.appendingPathComponent("Secure Preferences")
    try PreferencesWriter.write(extensions, profileName: "Fixture Profile", to: preferencesURL)
    try PreferencesWriter.write(extensions, profileName: nil, to: securePreferencesURL)

    return FixtureManifest(
      root: directory, historyURL: historyURL, loginDataURL: loginDataURL, cookiesURL: cookiesURL,
      bookmarksURL: bookmarksURL, preferencesURL: preferencesURL, securePreferencesURL: securePreferencesURL,
      history: history, logins: logins, cookies: cookies, bookmarks: bookmarks, extensions: extensions,
      historySchemaVersion: 70, loginDataSchemaVersion: 43, cookiesMetaVersion: hostPrefixed ? 24 : 23,
      cookieValuesHaveHostPrefix: hostPrefixed, safeStoragePassword: safeStoragePassword, derivedKey: key,
      extraColumns: extra, missingColumns: missing
    )
  }
}
