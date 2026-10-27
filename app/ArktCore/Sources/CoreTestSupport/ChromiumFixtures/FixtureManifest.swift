import Foundation

/// What `FakeChromiumProfile.make` wrote: file locations, expected counts and the plaintext values, so a reader
/// test can assert on them. Every value is invented; nothing here comes from a real profile.
public struct FixtureManifest: Sendable, Equatable {
  public struct Visit: Sendable, Equatable {
    /// Microseconds since 1601-01-01 UTC, the WebKit/Chromium time base.
    public let webkitTime: Int64
    /// The full transition value: core type in the low 8 bits, qualifier flags above.
    public let transition: Int32

    public var date: Date { ChromiumTime.date(fromWebKit: webkitTime) }
    public var coreTransition: Int32 { transition & 0xFF }
  }

  public struct HistoryEntry: Sendable, Equatable {
    public let url: String
    public let title: String
    public let visits: [Visit]
    public var visitCount: Int { visits.count }
    public var lastVisitWebKitTime: Int64 { visits.map(\.webkitTime).max() ?? 0 }
  }

  public struct Login: Sendable, Equatable {
    public let originURL: String
    public let signonRealm: String
    public let username: String
    public let password: String

    public init(originURL: String, signonRealm: String, username: String, password: String) {
      self.originURL = originURL; self.signonRealm = signonRealm; self.username = username; self.password = password
    }
  }

  public struct Cookie: Sendable, Equatable {
    public let hostKey: String
    public let name: String
    public let value: String
    public let path: String
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let expiresWebKitTime: Int64

    public init(
      hostKey: String, name: String, value: String, path: String, isSecure: Bool, isHTTPOnly: Bool,
      expiresWebKitTime: Int64
    ) {
      self.hostKey = hostKey; self.name = name; self.value = value; self.path = path; self.isSecure = isSecure
      self.isHTTPOnly = isHTTPOnly; self.expiresWebKitTime = expiresWebKitTime
    }
  }

  public struct Bookmark: Sendable, Equatable {
    public let root: String
    /// Folder titles from the root down to (not including) the bookmark.
    public let folderPath: [String]
    public let title: String
    public let url: String
    public let guid: String
    public let dateAddedWebKitTime: Int64
  }

  public enum ExtensionKind: String, Sendable, Equatable {
    case webStore
    case unpacked
    case builtIn
  }

  public struct ExtensionEntry: Sendable, Equatable {
    public let id: String
    public let kind: ExtensionKind
    public let name: String
    public let version: String
  }

  public let root: URL
  public let historyURL: URL
  public let loginDataURL: URL
  public let cookiesURL: URL
  public let bookmarksURL: URL
  public let preferencesURL: URL
  public let securePreferencesURL: URL

  public let history: [HistoryEntry]
  public let logins: [Login]
  public let cookies: [Cookie]
  public let bookmarks: [Bookmark]
  public let extensions: [ExtensionEntry]

  /// The History `meta` version (70) and Login Data `meta` version (43).
  public let historySchemaVersion: Int
  public let loginDataSchemaVersion: Int
  /// The Cookies `meta` version written (24 prefixes each value with SHA-256 of `host_key`; 23 does not).
  public let cookiesMetaVersion: Int
  public let cookieValuesHaveHostPrefix: Bool

  /// The fake Safe Storage secret and the 16-byte AES key derived from it. Not a Keychain item.
  public let safeStoragePassword: String
  public let derivedKey: [UInt8]

  /// Columns added to or removed from the three databases by the schema-drift option, as `table.column`.
  public let extraColumns: [String]
  public let missingColumns: [String]

  public var visitCount: Int { history.reduce(0) { $0 + $1.visitCount } }
  public var bookmarkCount: Int { bookmarks.count }
}

/// WebKit (Chromium) time conversions.
public enum ChromiumTime {
  /// Seconds between 1601-01-01 and 1970-01-01.
  public static let unixEpochOffsetSeconds: Int64 = 11_644_473_600

  public static func webKit(fromUnixSeconds seconds: Int64) -> Int64 {
    (seconds + unixEpochOffsetSeconds) * 1_000_000
  }

  public static func date(fromWebKit micros: Int64) -> Date {
    Date(timeIntervalSince1970: Double(micros) / 1_000_000 - Double(unixEpochOffsetSeconds))
  }
}
