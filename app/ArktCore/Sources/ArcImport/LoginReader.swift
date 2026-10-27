import Foundation

/// One saved Arc login, with the password decrypted into a `SecretBytes` that zeroes itself when released.
public struct ArcLogin: Sendable {
  public let originURL: String
  public let actionURL: String?
  public let signonRealm: String
  public let username: String
  public let password: SecretBytes
  public let dateCreated: Date?
  public let dateLastUsed: Date?
  /// Always false: rows the user marked "never save" are skipped and counted, not delivered.
  public let blacklistedByUser: Bool
}

/// Counts for one login read. Never holds row data.
public struct LoginReadSummary: Sendable, Equatable, CustomStringConvertible {
  public var scanned = 0
  public var delivered = 0
  /// "Never save for this site" entries, which carry no password.
  public var skippedBlacklisted = 0
  /// Rows whose password did not decrypt: empty, wrong key or corrupt data.
  public var skippedUndecryptable = 0
  /// Rows with a missing or invalid required field.
  public var skippedMalformed = 0

  public var description: String {
    "logins: scanned \(scanned), delivered \(delivered), blacklisted \(skippedBlacklisted), "
      + "undecryptable \(skippedUndecryptable), malformed \(skippedMalformed)"
  }
}

/// Reads and decrypts the saved logins of an Arc profile snapshot's `Login Data` database.
///
/// Same contract as `CookieReader`: blocking, read-only on the snapshot copy, bad rows skipped and counted.
public struct LoginReader: Sendable {
  /// Records per `onBatch` call.
  public static let batchSize = 500

  private static let required = ["origin_url", "signon_realm", "password_value"]
  private static let optional = [
    "action_url", "username_value", "date_created", "date_last_used", "blacklisted_by_user",
  ]

  private let log: ImportLog.Sink

  /// `log` receives one counts-only line per read.
  public init(log: (@Sendable (String) -> Void)? = nil) {
    self.log = log ?? ImportLog.live
  }

  /// Reads the Safe Storage password from `keyProvider` once, derives the key, reads every login, then drops the key.
  @discardableResult
  public func read(
    loginDatabase: URL, keyProvider: some SafeStorageKeyProvider, onBatch: ([ArcLogin]) throws -> Void
  ) throws -> LoginReadSummary {
    try ChromiumDecryptor.withDecryptor(provider: keyProvider) { decryptor in
      try read(loginDatabase: loginDatabase, decryptor: decryptor, onBatch: onBatch)
    }
  }

  /// Reads with a decryptor the caller already holds, so one key can serve the cookie and login readers of a run.
  @discardableResult
  public func read(
    loginDatabase: URL, decryptor: borrowing ChromiumDecryptor, onBatch: ([ArcLogin]) throws -> Void
  ) throws -> LoginReadSummary {
    let database = try ChromiumDatabase(url: loginDatabase)
    let present = try database.columns(of: "logins")
    let missing = Self.required.filter { !present.contains($0) }
    guard missing.isEmpty else { throw ChromiumReadError.missingColumns(table: "logins", columns: missing) }

    var summary = LoginReadSummary()
    var cursor = try database.query(table: "logins", columns: (Self.required + Self.optional).filter(present.contains))
    var batch: [ArcLogin] = []
    batch.reserveCapacity(Self.batchSize)

    while try cursor.next() {
      summary.scanned += 1
      guard let origin = cursor.text("origin_url"), let realm = cursor.text("signon_realm"),
        let blob = cursor.blob("password_value")
      else {
        summary.skippedMalformed += 1
        continue
      }
      if (cursor.int("blacklisted_by_user") ?? 0) != 0 {
        summary.skippedBlacklisted += 1
        continue
      }
      guard let plain = try? decryptor.decrypt(blob) else {
        summary.skippedUndecryptable += 1
        continue
      }
      batch.append(
        ArcLogin(
          originURL: origin, actionURL: cursor.text("action_url"), signonRealm: realm,
          username: cursor.text("username_value") ?? "", password: SecretBytes(taking: plain),
          dateCreated: WebKitTimestamp.optionalDate(cursor.int("date_created")),
          dateLastUsed: WebKitTimestamp.optionalDate(cursor.int("date_last_used")), blacklistedByUser: false
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
}
