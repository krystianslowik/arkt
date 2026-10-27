import Foundation

/// One persistent Arc cookie, decrypted. The value is a `SecretBytes` that zeroes itself when released.
public struct ArcCookie: Sendable {
  public let hostKey: String
  public let name: String
  public let value: SecretBytes
  public let path: String
  public let expires: Date
  /// Nil when the column is missing or holds 0.
  public let creation: Date?
  public let lastAccess: Date?
  public let isSecure: Bool
  public let isHTTPOnly: Bool
  /// Chromium's `samesite` enum value: -1 unspecified, 0 none, 1 lax, 2 strict.
  public let sameSite: Int
  /// Chromium's `priority` enum value: 0 low, 1 medium, 2 high.
  public let priority: Int
  /// Chromium's `source_scheme` enum value: 0 unset, 1 non-secure, 2 secure.
  public let sourceScheme: Int
  /// The port the cookie was set from, or -1 when unspecified.
  public let sourcePort: Int
  public let hasExpires: Bool
  public let isPersistent: Bool
}

/// Counts for one cookie read. Never holds row data.
public struct CookieReadSummary: Sendable, Equatable, CustomStringConvertible {
  /// The Cookies `meta` version that chose the value format (24 and later carry a host hash).
  public var metaVersion = 0
  public var scanned = 0
  public var delivered = 0
  /// Session cookies: not persistent, or without an expiry.
  public var skippedSession = 0
  /// Persistent cookies whose expiry is not after the reader's clock.
  public var skippedExpired = 0
  /// Rows whose value did not decrypt: wrong key, corrupt data or a host hash mismatch.
  public var skippedUndecryptable = 0
  /// Rows with a missing or invalid required field.
  public var skippedMalformed = 0

  public var description: String {
    "cookies: version \(metaVersion), scanned \(scanned), delivered \(delivered), session \(skippedSession), "
      + "expired \(skippedExpired), undecryptable \(skippedUndecryptable), malformed \(skippedMalformed)"
  }
}

/// Reads and decrypts the persistent cookies of an Arc profile snapshot's `Cookies` database.
///
/// Blocking: it opens SQLite and, with a key provider, may wait on a Keychain prompt. Call it from a background
/// context. It opens the database read-only, so pass the copy from `ArcProfileSnapshot`, never Arc's own file.
/// A bad row is skipped and counted; only file-level problems and a failing key provider throw.
public struct CookieReader: Sendable {
  /// Records per `onBatch` call.
  public static let batchSize = 500

  private static let required = ["host_key", "name", "encrypted_value", "path", "expires_utc"]
  private static let optional = [
    "value", "creation_utc", "last_access_utc", "is_secure", "is_httponly", "samesite", "priority", "source_scheme",
    "source_port", "has_expires", "is_persistent",
  ]

  private let now: @Sendable () -> Date
  private let log: ImportLog.Sink

  /// `now` is the clock that decides which cookies have expired; `log` receives one counts-only line per read
  /// (default: the unified log).
  public init(now: @escaping @Sendable () -> Date = { Date() }, log: (@Sendable (String) -> Void)? = nil) {
    self.now = now
    self.log = log ?? ImportLog.live
  }

  /// Reads the Safe Storage password from `keyProvider` once, derives the key, reads every cookie, then drops the key.
  @discardableResult
  public func read(
    cookiesDatabase: URL, keyProvider: some SafeStorageKeyProvider, onBatch: ([ArcCookie]) throws -> Void
  ) throws -> CookieReadSummary {
    try ChromiumDecryptor.withDecryptor(provider: keyProvider) { decryptor in
      try read(cookiesDatabase: cookiesDatabase, decryptor: decryptor, onBatch: onBatch)
    }
  }

  /// Reads with a decryptor the caller already holds, so one key can serve the cookie and login readers of a run.
  @discardableResult
  public func read(
    cookiesDatabase: URL, decryptor: borrowing ChromiumDecryptor, onBatch: ([ArcCookie]) throws -> Void
  ) throws -> CookieReadSummary {
    let database = try ChromiumDatabase(url: cookiesDatabase)
    let present = try database.columns(of: "cookies")
    let missing = Self.required.filter { !present.contains($0) }
    guard missing.isEmpty else { throw ChromiumReadError.missingColumns(table: "cookies", columns: missing) }

    var summary = CookieReadSummary()
    summary.metaVersion = try database.metaVersion()
    let clock = now()
    var cursor = try database.query(table: "cookies", columns: (Self.required + Self.optional).filter(present.contains))
    var batch: [ArcCookie] = []
    batch.reserveCapacity(Self.batchSize)

    while try cursor.next() {
      summary.scanned += 1
      guard let host = cursor.text("host_key"), let name = cursor.text("name"), let path = cursor.text("path"),
        let expiresMicros = cursor.int("expires_utc")
      else {
        summary.skippedMalformed += 1
        continue
      }
      let hasExpires = cursor.int("has_expires").map { $0 != 0 } ?? (expiresMicros != 0)
      let isPersistent = cursor.int("is_persistent").map { $0 != 0 } ?? hasExpires
      guard hasExpires, isPersistent else {
        summary.skippedSession += 1
        continue
      }
      let expires = WebKitTimestamp.date(expiresMicros)
      guard expires > clock else {
        summary.skippedExpired += 1
        continue
      }
      guard let value = Self.decryptValue(&cursor, hostKey: host, metaVersion: summary.metaVersion, decryptor) else {
        summary.skippedUndecryptable += 1
        continue
      }
      batch.append(
        ArcCookie(
          hostKey: host, name: name, value: value, path: path, expires: expires,
          creation: WebKitTimestamp.optionalDate(cursor.int("creation_utc")),
          lastAccess: WebKitTimestamp.optionalDate(cursor.int("last_access_utc")),
          isSecure: (cursor.int("is_secure") ?? 0) != 0, isHTTPOnly: (cursor.int("is_httponly") ?? 0) != 0,
          sameSite: Int(cursor.int("samesite") ?? -1), priority: Int(cursor.int("priority") ?? 1),
          sourceScheme: Int(cursor.int("source_scheme") ?? 0), sourcePort: Int(cursor.int("source_port") ?? -1),
          hasExpires: hasExpires, isPersistent: isPersistent
        ))
      summary.delivered += 1
      if batch.count == Self.batchSize {
        try onBatch(batch)
        batch.removeAll(keepingCapacity: true)
      }
    }
    if !batch.isEmpty { try onBatch(batch) }
    log(summary.description)
    return summary
  }

  /// The plaintext value, or nil when it cannot be decrypted or is not valid UTF-8. An empty `encrypted_value` means
  /// Chromium stored the value unencrypted in `value`.
  private static func decryptValue(
    _ cursor: inout ChromiumCursor, hostKey: String, metaVersion: Int, _ decryptor: borrowing ChromiumDecryptor
  ) -> SecretBytes? {
    let blob = cursor.blob("encrypted_value") ?? []
    guard !blob.isEmpty else { return SecretBytes(taking: Array((cursor.text("value") ?? "").utf8)) }
    guard let plain = try? decryptor.decryptCookie(blob, hostKey: hostKey, metaVersion: metaVersion) else { return nil }
    let secret = SecretBytes(taking: plain)
    guard secret.withBytes(isValidUTF8) else { return nil }
    return secret
  }
}

/// True when `bytes` decode as UTF-8 without error. Decodes in place, without building a string.
func isValidUTF8(_ bytes: UnsafeRawBufferPointer) -> Bool {
  var iterator = bytes.makeIterator()
  var decoder = UTF8()
  while true {
    switch decoder.decode(&iterator) {
    case .scalarValue: continue
    case .emptyInput: return true
    case .error: return false
    }
  }
}
