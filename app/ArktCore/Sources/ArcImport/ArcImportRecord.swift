import CryptoKit
import Foundation

/// What an Arc import has handled before (Track E user decision, 2026-10-23: a re-import adds only Arc items never
/// imported before; items deleted in Arkt are not restored).
///
/// Version 1 held Arc's own ids: Space ids from `StorableSidebar.json`'s `spaces` and Favorite ids of the top-level items
/// under a profile's Favorites root. Version 2 (#515) adds what the browser-data import wrote, per type: the newest
/// history visit (a watermark) and a digest key for each bookmark, cookie, login and extension. A key is the first 16
/// bytes of a SHA-256 over the item's identity (`ArcImportKey`, salted per install), so the stored record holds no host, username, URL or
/// extension name. Stored as JSON with sorted arrays, so the stored bytes are deterministic; every field is read with
/// `decodeIfPresent`, so a version 1 record stays readable.
public struct ArcImportRecord: Hashable, Sendable, Codable {
  public var spaceIDs: Set<String>
  public var favoriteItemIDs: Set<String>
  /// The newest history visit imported so far; the next import writes only visits after it.
  public var historyWatermark: Date?
  public var bookmarkKeys: Set<String>
  public var cookieKeys: Set<String>
  public var loginKeys: Set<String>
  /// Chrome Web Store ids (public identifiers, stored as they are).
  public var extensionIDs: Set<String>
  /// A random per-install value mixed into every digest key (`ArcImportKey`), so two installs' records cannot be
  /// compared and a key cannot be guessed from a known site list. Set once, by the first import that records keys; a
  /// merge keeps the one already stored.
  public var salt: String?

  public init(
    spaceIDs: Set<String> = [], favoriteItemIDs: Set<String> = [], historyWatermark: Date? = nil,
    bookmarkKeys: Set<String> = [], cookieKeys: Set<String> = [], loginKeys: Set<String> = [],
    extensionIDs: Set<String> = [], salt: String? = nil
  ) {
    self.spaceIDs = spaceIDs
    self.favoriteItemIDs = favoriteItemIDs
    self.historyWatermark = historyWatermark
    self.bookmarkKeys = bookmarkKeys
    self.cookieKeys = cookieKeys
    self.loginKeys = loginKeys
    self.extensionIDs = extensionIDs
    self.salt = salt
  }

  /// Nothing recorded: no import ran yet, or the last one ran before the record existed.
  public var isEmpty: Bool { self == ArcImportRecord() }

  /// Unions the id and key sets and keeps the later watermark, so a merge can never move a watermark back.
  public mutating func formUnion(_ other: ArcImportRecord) {
    spaceIDs.formUnion(other.spaceIDs)
    favoriteItemIDs.formUnion(other.favoriteItemIDs)
    bookmarkKeys.formUnion(other.bookmarkKeys)
    cookieKeys.formUnion(other.cookieKeys)
    loginKeys.formUnion(other.loginKeys)
    extensionIDs.formUnion(other.extensionIDs)
    salt = salt ?? other.salt
    historyWatermark = [historyWatermark, other.historyWatermark].compactMap { $0 }.max()
  }

  private enum CodingKeys: String, CodingKey {
    case spaceIDs
    case favoriteItemIDs
    case historyWatermark
    case bookmarkKeys
    case cookieKeys
    case loginKeys
    case extensionIDs
    case salt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    spaceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .spaceIDs) ?? []
    favoriteItemIDs = try container.decodeIfPresent(Set<String>.self, forKey: .favoriteItemIDs) ?? []
    historyWatermark = try container.decodeIfPresent(Date.self, forKey: .historyWatermark)
    bookmarkKeys = try container.decodeIfPresent(Set<String>.self, forKey: .bookmarkKeys) ?? []
    cookieKeys = try container.decodeIfPresent(Set<String>.self, forKey: .cookieKeys) ?? []
    loginKeys = try container.decodeIfPresent(Set<String>.self, forKey: .loginKeys) ?? []
    extensionIDs = try container.decodeIfPresent(Set<String>.self, forKey: .extensionIDs) ?? []
    salt = try container.decodeIfPresent(String.self, forKey: .salt)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(spaceIDs.sorted(), forKey: .spaceIDs)
    try container.encode(favoriteItemIDs.sorted(), forKey: .favoriteItemIDs)
    try container.encodeIfPresent(historyWatermark, forKey: .historyWatermark)
    // Version 2 fields are left out while empty, so a record with only version 1 content keeps its stored bytes.
    if !bookmarkKeys.isEmpty { try container.encode(bookmarkKeys.sorted(), forKey: .bookmarkKeys) }
    if !cookieKeys.isEmpty { try container.encode(cookieKeys.sorted(), forKey: .cookieKeys) }
    if !loginKeys.isEmpty { try container.encode(loginKeys.sorted(), forKey: .loginKeys) }
    if !extensionIDs.isEmpty { try container.encode(extensionIDs.sorted(), forKey: .extensionIDs) }
    try container.encodeIfPresent(salt, forKey: .salt)
  }
}

/// The digest keys of `ArcImportRecord` v2: one-way, so the settings database never holds a host, a username or a URL.
public enum ArcImportKey {
  /// A new random salt for a record that has none.
  public static func makeSalt() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
  }

  public static func cookie(_ cookie: ArcCookie, salt: String = "") -> String {
    digest([salt, cookie.name, cookie.hostKey, cookie.path])
  }

  public static func login(_ login: ArcLogin, salt: String = "") -> String {
    digest([salt, login.signonRealm, login.username, login.actionURL ?? ""])
  }

  /// The guid when Chromium wrote one, else the folder path, title and URL.
  public static func bookmark(_ bookmark: BookmarkRecord, salt: String = "") -> String {
    if let guid = bookmark.guid?.lowercased(), !guid.isEmpty { return digest([salt, "guid", guid]) }
    return digest([salt, "path"] + bookmark.folderPath + [bookmark.title, bookmark.url])
  }

  static func digest(_ parts: [String]) -> String {
    var hasher = SHA256()
    for part in parts {
      hasher.update(data: Data(part.utf8))
      hasher.update(data: Data([0]))
    }
    return hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
  }
}

/// Where the import record lives. `Persistence.SettingsStore` conforms; CoreBridge tests use a fake.
public protocol ArcImportRecordStoring: Sendable {
  /// The stored record, or an empty one when missing or unreadable.
  func loadArcImportRecord() async throws -> ArcImportRecord
  /// Adds `record`'s ids to the stored ones (a union, never a replacement), in one transaction.
  func recordArcImport(_ record: ArcImportRecord, at date: Date) async throws
}
