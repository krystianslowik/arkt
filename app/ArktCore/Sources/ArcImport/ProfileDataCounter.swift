import Foundation

/// How many items of each type a profile snapshot holds (#515), for the import consent sheet. Counts only.
///
/// Cookies and logins are upper bounds: the count pass has no key, so a row whose value later fails to decrypt is still
/// counted.
public struct ProfileDataCounts: Equatable, Sendable {
  public var historyURLs = 0
  public var historyVisits = 0
  public var bookmarks = 0
  public var cookies = 0
  public var logins = 0
  public var extensions = 0

  public init(
    historyURLs: Int = 0, historyVisits: Int = 0, bookmarks: Int = 0, cookies: Int = 0, logins: Int = 0,
    extensions: Int = 0
  ) {
    self.historyURLs = historyURLs; self.historyVisits = historyVisits; self.bookmarks = bookmarks
    self.cookies = cookies; self.logins = logins; self.extensions = extensions
  }
}

extension ArcProfileSnapshot.Profile {
  /// The copy of the first of `candidates` that the snapshot holds (for example `Network/Cookies`, then `Cookies`), or
  /// nil when none was copied.
  public func copiedFile(_ candidates: String...) -> URL? {
    candidates.first(where: copied.contains).map { directory.appendingPathComponent($0) }
  }
}

/// Key-free row counts over the snapshot's databases. Nothing is decrypted and the Keychain is not touched.
public enum ProfileDataCounter {
  /// Persistent, unexpired, non-partitioned cookies: the rows `CookieReader` would try to decrypt.
  public static func cookies(in database: URL, now: Date) throws -> Int {
    let connection = try ChromiumDatabase(url: database)
    let present = try connection.columns(of: "cookies")
    guard present.contains("expires_utc") else {
      throw ChromiumReadError.missingColumns(table: "cookies", columns: ["expires_utc"])
    }
    let optional = ["has_expires", "is_persistent", "top_frame_site_key"].filter(present.contains)
    var cursor = try connection.query(table: "cookies", columns: ["expires_utc"] + optional)
    var count = 0
    while try cursor.next() {
      guard let micros = cursor.int("expires_utc") else { continue }
      let hasExpires = cursor.int("has_expires").map { $0 != 0 } ?? (micros != 0)
      let isPersistent = cursor.int("is_persistent").map { $0 != 0 } ?? hasExpires
      guard hasExpires, isPersistent, (cursor.text("top_frame_site_key") ?? "").isEmpty,
        WebKitTimestamp.date(micros) > now
      else { continue }
      count += 1
    }
    return count
  }

  /// Saved logins the user did not mark as never-save.
  public static func logins(in database: URL) throws -> Int {
    let connection = try ChromiumDatabase(url: database)
    let present = try connection.columns(of: "logins")
    let optional = ["blacklisted_by_user"].filter(present.contains)
    var cursor = try connection.query(table: "logins", columns: ["signon_realm"] + optional)
    var count = 0
    while try cursor.next() {
      if (cursor.int("blacklisted_by_user") ?? 0) == 0 { count += 1 }
    }
    return count
  }
}
