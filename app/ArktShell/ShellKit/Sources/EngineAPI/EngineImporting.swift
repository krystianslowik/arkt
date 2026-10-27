import ArcImport
import Foundation

/// The counts of one import call (#512): `written + skipped + failed` is the batch size. Never holds a host, a name or
/// a value.
public struct ImportWriteResult: Equatable, Sendable {
  /// Stored.
  public var written: Int
  /// Not stored on purpose: a duplicate inside the batch, an expired cookie, or a cookie the profile already holds that is
  /// as new or newer.
  public var skipped: Int
  /// Refused by the cookie store or the password store.
  public var failed: Int
  /// The failure reasons with their counts, one `reason: count` line each; nil when nothing failed.
  public var failureReason: String?

  public init(written: Int = 0, skipped: Int = 0, failed: Int = 0, failureReason: String? = nil) {
    self.written = written; self.skipped = skipped; self.failed = failed; self.failureReason = failureReason
  }
}

/// Writes imported browser data into the engine's profile (#512), for engines that have one. A separate protocol, like
/// `EngineExtensions`: the import coordinator needs it, the shell's tab code does not.
///
/// Plaintext crosses in-process only. Every implementation zeroes each `SecretBytes` of the batch before the call
/// returns, so the caller's records hold no secret afterwards; a caller that wants the values again must read them again.
@MainActor
public protocol EngineImporting: AnyObject {
  /// Writes persistent cookies through the profile's cookie store. Duplicates inside the batch by (name, host key,
  /// path) keep the one last used most recently, the later entry on a tie; a cookie that already expired, and one the
  /// profile already holds that was last used at or after the imported one's last access, are skipped.
  func importCookies(_ batch: [ArcCookie]) async -> ImportWriteResult
  /// Writes logins through the profile's password store. Duplicates inside the batch by (signon realm, username,
  /// action) keep the later entry.
  func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult
}

/// What a recording engine received: the plain values of the records, taken before their secrets were zeroed.
public struct ImportedCookieRecord: Equatable, Sendable {
  public var hostKey: String
  public var name: String
  public var value: String
  public var path: String

  public init(hostKey: String, name: String, value: String, path: String) {
    self.hostKey = hostKey; self.name = name; self.value = value; self.path = path
  }
}

public struct ImportedLoginRecord: Equatable, Sendable {
  public var signonRealm: String
  public var username: String
  public var actionURL: String?
  public var password: String

  public init(signonRealm: String, username: String, actionURL: String?, password: String) {
    self.signonRealm = signonRealm; self.username = username; self.actionURL = actionURL; self.password = password
  }
}

/// The recording half of an `EngineImporting` stub (`InMemoryEngine`, `FakeEngine`): applies the same dedupe rules as the
/// engine and keeps what it would have written. Not the engine's code: the real rules run in the engine and are checked
/// there.
public struct ImportRecording: Sendable {
  public private(set) var cookies: [ImportedCookieRecord] = []
  public private(set) var logins: [ImportedLoginRecord] = []
  /// Last-access stamps of the cookies kept, parallel to `cookies`.
  private var stamps: [Date] = []

  public init() {}

  public mutating func record(_ batch: [ArcCookie]) -> ImportWriteResult {
    defer { for cookie in batch { cookie.value.wipe() } }
    var winners: [String: Int] = [:]
    func key(_ cookie: ArcCookie) -> String { "\(cookie.name)\u{0}\(cookie.hostKey)\u{0}\(cookie.path)" }
    func stamp(_ cookie: ArcCookie) -> Date { cookie.lastAccess ?? cookie.creation ?? .distantPast }
    for (index, cookie) in batch.enumerated() {
      if let held = winners[key(cookie)], stamp(cookie) < stamp(batch[held]) { continue }
      winners[key(cookie)] = index
    }
    var result = ImportWriteResult()
    for (index, cookie) in batch.enumerated() {
      guard winners[key(cookie)] == index, cookie.expires > Date() else { result.skipped += 1; continue }
      let record = ImportedCookieRecord(
        hostKey: cookie.hostKey, name: cookie.name, value: cookie.value.utf8String(), path: cookie.path)
      let existing = cookies.firstIndex { ($0.name, $0.hostKey, $0.path) == (record.name, record.hostKey, record.path) }
      if let existing {
        guard stamps[existing] < stamp(cookie) else { result.skipped += 1; continue }
        cookies[existing] = record
        stamps[existing] = stamp(cookie)
      } else {
        cookies.append(record)
        stamps.append(stamp(cookie))
      }
      result.written += 1
    }
    return result
  }

  public mutating func record(_ batch: [ArcLogin]) -> ImportWriteResult {
    defer { for login in batch { login.password.wipe() } }
    func key(_ login: ArcLogin) -> String { "\(login.signonRealm)\u{0}\(login.username)\u{0}\(login.actionURL ?? "")" }
    var last: [String: Int] = [:]
    for (index, login) in batch.enumerated() { last[key(login)] = index }
    var result = ImportWriteResult()
    for (index, login) in batch.enumerated() {
      guard last[key(login)] == index else { result.skipped += 1; continue }
      let record = ImportedLoginRecord(
        signonRealm: login.signonRealm, username: login.username, actionURL: login.actionURL,
        password: login.password.utf8String())
      // The store updates a login whose primary key it holds; that counts as written.
      if let existing = logins.firstIndex(where: {
        ($0.signonRealm, $0.username, $0.actionURL ?? "") == (record.signonRealm, record.username, record.actionURL ?? "")
      }) {
        logins[existing] = record
      } else {
        logins.append(record)
      }
      result.written += 1
    }
    return result
  }
}
