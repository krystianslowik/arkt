import ArcImport
import Foundation

/// Arc's history record under a name that does not clash with `EngineAPI.HistoryEntry`, a tab's back-forward entry.
public typealias ImportedHistoryEntry = ArcImport.HistoryEntry

/// The counts of one import call (#512): `written + skipped + failed` is the batch size (visits, for a history batch).
/// Never holds a host, a name or a value.
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
  /// History only: the newest visit time written, the next call's watermark; nil when no visit was written, and for every
  /// other kind of batch.
  public var latestVisit: Date?

  public init(
    written: Int = 0, skipped: Int = 0, failed: Int = 0, failureReason: String? = nil, latestVisit: Date? = nil
  ) {
    self.written = written; self.skipped = skipped; self.failed = failed; self.failureReason = failureReason
    self.latestVisit = latestVisit
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
  /// action) keep the later entry; a login the store already holds under that key is skipped unless the imported one is
  /// newer (the later of its last use and creation).
  func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult
  /// Writes every visit of the entries through the profile's history service, with its time and core transition (#511);
  /// the visit and typed counts of a URL follow from the visits written. Counts are in visits. A visit at or before
  /// `watermark` (the newest visit the coordinator imported before; nil for none), one older than the 90 days Chromium's
  /// history keeps, and one of a URL the history refuses (not http, https, ftp or file) is skipped; a URL that is not
  /// valid fails its visits. `latestVisit` of the result is the newest visit written: the coordinator keeps the larger of
  /// it and its watermark, and a second call with that watermark writes nothing.
  func importHistory(_ batch: [ImportedHistoryEntry], after watermark: Date?) async -> ImportWriteResult
  /// Writes bookmarks under "Other bookmarks" in a folder named "Imported", their folders kept (#511). The record's root
  /// (bar, other, synced) is not kept: everything lands under the one folder. A bookmark whose guid the profile holds,
  /// or whose url and title its target folder holds, is skipped; an invalid url fails.
  func importBookmarks(_ batch: [BookmarkRecord]) async -> ImportWriteResult
  /// Installs Chrome Web Store extensions by id (#513), an optional step: nil means this engine cannot install by id, and
  /// the coordinator reports the type as skipped with the reason "not yet available". Counts are in extensions;
  /// `written` is the extensions installed and `skipped` those the profile already has. The default implementation
  /// counts `installExtensionResults(ids:)`, so an engine adopts the step by implementing that one.
  func installExtensions(ids: [String]) async -> ImportWriteResult?
  /// Installs the extensions by Web Store id with one confirmation for the whole batch, and answers one result per
  /// distinct id, in the order the ids first appear. An id the profile already has is `.alreadyInstalled` and is not
  /// installed again; an id that is not a Web Store id, that the store does not have, or that cannot be reached is
  /// `.failed` with a reason that holds no id. Declining the confirmation fails every id that needed it. Never throws and
  /// never stops at one failure; nil: this engine cannot install by id.
  func installExtensionResults(ids: [String]) async -> [ExtensionInstallResult]?
}

extension EngineImporting {
  public func installExtensions(ids: [String]) async -> ImportWriteResult? {
    guard let results = await installExtensionResults(ids: ids) else { return nil }
    return ImportWriteResult(counting: results)
  }
  public func installExtensionResults(ids: [String]) async -> [ExtensionInstallResult]? { nil }
}

/// What happened to one extension of an install batch (#513).
public enum ExtensionInstallOutcome: Equatable, Sendable {
  case installed
  case alreadyInstalled
  /// The reason is a short sentence without the extension's id or name.
  case failed(String)
}

public struct ExtensionInstallResult: Equatable, Sendable {
  public var id: String
  public var outcome: ExtensionInstallOutcome

  public init(id: String, outcome: ExtensionInstallOutcome) {
    self.id = id; self.outcome = outcome
  }
}

extension ImportWriteResult {
  /// Installed extensions are written, ones the profile had are skipped, failures are counted by reason.
  public init(counting results: [ExtensionInstallResult]) {
    self.init()
    var reasons: [String: Int] = [:]
    var order: [String] = []
    for result in results {
      switch result.outcome {
      case .installed: written += 1
      case .alreadyInstalled: skipped += 1
      case .failed(let reason):
        failed += 1
        if reasons[reason] == nil { order.append(reason) }
        reasons[reason, default: 0] += 1
      }
    }
    if !order.isEmpty { failureReason = order.map { "\($0): \(reasons[$0] ?? 0)" }.joined(separator: "\n") + "\n" }
  }
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

public struct ImportedVisitRecord: Equatable, Sendable {
  public var url: String
  public var title: String
  public var time: Date
  public var transition: Int

  public init(url: String, title: String, time: Date, transition: Int) {
    self.url = url; self.title = title; self.time = time; self.transition = transition
  }
}

public struct ImportedBookmarkRecord: Equatable, Sendable {
  public var folderPath: [String]
  public var title: String
  public var url: String
  public var guid: String?

  public init(folderPath: [String], title: String, url: String, guid: String?) {
    self.folderPath = folderPath; self.title = title; self.url = url; self.guid = guid
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
  public private(set) var visits: [ImportedVisitRecord] = []
  public private(set) var bookmarks: [ImportedBookmarkRecord] = []
  /// The Web Store ids installed, in order (#513).
  public private(set) var extensionIDs: [String] = []
  /// Last-access stamps of the cookies kept, parallel to `cookies`.
  private var stamps: [Date] = []
  private var loginStamps: [Date] = []

  public init() {}

  public mutating func record(_ batch: [ArcCookie]) -> ImportWriteResult {
    defer { for cookie in batch { cookie.value.wipe() } }
    var winners: [String: Int] = [:]
    func key(_ cookie: ArcCookie) -> String { "\(cookie.name)\u{0}\(cookie.hostKey)\u{0}\(cookie.path)" }
    func stamp(_ cookie: ArcCookie) -> Date { cookie.lastAccess ?? cookie.creation ?? .distantPast }
    for (index, cookie) in batch.enumerated() where cookie.partitionKey.isEmpty {
      if let held = winners[key(cookie)], stamp(cookie) < stamp(batch[held]) { continue }
      winners[key(cookie)] = index
    }
    var result = ImportWriteResult()
    for (index, cookie) in batch.enumerated() {
      guard winners[key(cookie)] == index, cookie.expires > Date(), cookie.partitionKey.isEmpty else { result.skipped += 1; continue }
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
    func stamp(_ login: ArcLogin) -> Date { max(login.dateLastUsed ?? .distantPast, login.dateCreated ?? .distantPast) }
    var last: [String: Int] = [:]
    for (index, login) in batch.enumerated() { last[key(login)] = index }
    var result = ImportWriteResult()
    for (index, login) in batch.enumerated() {
      guard last[key(login)] == index else { result.skipped += 1; continue }
      let record = ImportedLoginRecord(
        signonRealm: login.signonRealm, username: login.username, actionURL: login.actionURL,
        password: login.password.utf8String())
      // A login the store holds is replaced only by a newer one.
      if let existing = logins.firstIndex(where: {
        ($0.signonRealm, $0.username, $0.actionURL ?? "") == (record.signonRealm, record.username, record.actionURL ?? "")
      }) {
        guard loginStamps[existing] < stamp(login) else { result.skipped += 1; continue }
        logins[existing] = record
        loginStamps[existing] = stamp(login)
      } else {
        logins.append(record)
        loginStamps.append(stamp(login))
      }
      result.written += 1
    }
    return result
  }

  /// Chromium's history keeps 90 days; older visits are skipped.
  public static let historyRetention: TimeInterval = 90 * 86_400

  public mutating func record(_ batch: [ImportedHistoryEntry], after watermark: Date?) -> ImportWriteResult {
    var result = ImportWriteResult()
    let oldest = Date().addingTimeInterval(-Self.historyRetention)
    for entry in batch {
      guard let url = URL(string: entry.url), let scheme = url.scheme?.lowercased(), url.host != nil || scheme == "file"
      else {
        result.failed += entry.visits.count
        result.failureReason = "invalid url: \(result.failed)\n"
        continue
      }
      for visit in entry.visits {
        guard ["http", "https", "ftp", "file"].contains(scheme), visit.time >= oldest,
          watermark.map({ visit.time > $0 }) ?? true
        else {
          result.skipped += 1
          continue
        }
        visits.append(ImportedVisitRecord(
          url: entry.url, title: entry.title, time: visit.time, transition: visit.transition.coreValue))
        result.written += 1
        result.latestVisit = max(result.latestVisit ?? visit.time, visit.time)
      }
    }
    return result
  }

  public mutating func record(_ batch: [BookmarkRecord]) -> ImportWriteResult {
    var result = ImportWriteResult()
    for bookmark in batch {
      guard let url = URL(string: bookmark.url), url.scheme != nil else {
        result.failed += 1
        result.failureReason = "invalid url: \(result.failed)\n"
        continue
      }
      let guid = bookmark.guid?.lowercased()
      let held = bookmarks.contains {
        (guid != nil && $0.guid == guid)
          || ($0.folderPath == bookmark.folderPath && $0.url == bookmark.url && $0.title == bookmark.title)
      }
      guard !held else {
        result.skipped += 1
        continue
      }
      bookmarks.append(ImportedBookmarkRecord(
        folderPath: bookmark.folderPath, title: bookmark.title, url: bookmark.url, guid: guid))
      result.written += 1
    }
    return result
  }

  /// A Web Store id is 32 letters from a to p.
  public static func isWebStoreID(_ id: String) -> Bool {
    id.utf8.count == 32 && id.utf8.allSatisfy { $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "p") }
  }

  /// `unavailable` are ids the stub's pretend store does not have.
  public mutating func record(extensions ids: [String], unavailable: Set<String> = []) -> [ExtensionInstallResult] {
    var seen: Set<String> = []
    var results: [ExtensionInstallResult] = []
    for id in ids where seen.insert(id).inserted {
      if !Self.isWebStoreID(id) {
        results.append(ExtensionInstallResult(id: id, outcome: .failed("not a Web Store id")))
      } else if extensionIDs.contains(id) {
        results.append(ExtensionInstallResult(id: id, outcome: .alreadyInstalled))
      } else if unavailable.contains(id) {
        results.append(ExtensionInstallResult(id: id, outcome: .failed("not available from the Web Store")))
      } else {
        extensionIDs.append(id)
        results.append(ExtensionInstallResult(id: id, outcome: .installed))
      }
    }
    return results
  }
}
