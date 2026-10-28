import ArcImport
import EngineAPI
import Foundation

/// What a read left to write: batches in write order, and how many items were left out because an earlier import
/// already handled them (or, for history, because the engine would skip them as too old).
struct PreparedBatches<Item: Sendable>: Sendable {
  var batches: [[Item]] = []
  var alreadyHandled = 0
}

/// Everything the profile import reads from the snapshot, off the main actor. Reads only; never writes, and the only
/// Keychain access is the one `secrets` call.
enum ProfileImportRead {
  struct Counted: Sendable {
    var counts = ProfileDataCounts()
    /// Types that cannot be imported at all: the file is not in the snapshot, or it could not be read.
    var unavailable: [ImportDataType: ImportTypeOutcome] = [:]
  }

  struct Secrets: Sendable {
    var cookies = PreparedBatches<ArcCookie>()
    var logins = PreparedBatches<ArcLogin>()
    var failures: [ImportDataType: ImportTypeOutcome] = [:]

    /// Zeroes every secret still held.
    func wipe() {
      for batch in cookies.batches { for cookie in batch { cookie.value.wipe() } }
      for batch in logins.batches { for login in batch { login.password.wipe() } }
    }
  }

  static let notInProfile = "not in the Arc profile"

  // MARK: Snapshot and count

  @concurrent
  static func snapshot(root: URL, scratchParent: URL) async throws -> ArcProfileSnapshot {
    try ArcProfileSnapshot.make(root: root, scratchParent: scratchParent)
  }

  /// The profile the import reads: Arc's `Default`, else the first one by name.
  static func profile(in snapshot: ArcProfileSnapshot) -> ArcProfileSnapshot.Profile? {
    snapshot.profiles.first { $0.name == "Default" } ?? snapshot.profiles.first
  }

  @concurrent
  static func count(profile: ArcProfileSnapshot.Profile, now: Date) async -> Counted {
    var result = Counted()
    func unreadable(_ type: ImportDataType, _ file: String) {
      result.unavailable[type] = .failed(reason: "could not read \(file)")
    }
    if let history = profile.copiedFile("History") {
      do {
        let summary = try HistoryReader.read(from: history) { _ in }
        result.counts.historyURLs = summary.urlCount
        result.counts.historyVisits = summary.visitCount
      } catch { unreadable(.history, "History") }
    } else {
      result.unavailable[.history] = .skipped(reason: notInProfile)
    }
    if profile.copiedFile("Bookmarks") != nil {
      do { result.counts.bookmarks = try BookmarksReader.read(profile: profile).bookmarks.count } catch {
        unreadable(.bookmarks, "Bookmarks")
      }
    } else {
      result.unavailable[.bookmarks] = .skipped(reason: notInProfile)
    }
    if let cookies = profile.copiedFile("Network/Cookies", "Cookies") {
      do { result.counts.cookies = try ProfileDataCounter.cookies(in: cookies, now: now) } catch {
        unreadable(.cookies, "Cookies")
      }
    } else {
      result.unavailable[.cookies] = .skipped(reason: notInProfile)
    }
    if let logins = profile.copiedFile("Login Data") {
      do { result.counts.logins = try ProfileDataCounter.logins(in: logins) } catch { unreadable(.passwords, "Login Data") }
    } else {
      result.unavailable[.passwords] = .skipped(reason: notInProfile)
    }
    if profile.copiedFile("Preferences", "Secure Preferences") != nil {
      do { result.counts.extensions = try ExtensionListReader.read(profile: profile).count } catch {
        unreadable(.extensions, "Preferences")
      }
    } else {
      result.unavailable[.extensions] = .skipped(reason: notInProfile)
    }
    return result
  }

  // MARK: History, bookmarks, extensions

  /// The visits after `watermark` and not older than `oldest`, regrouped into batches in time order, so the newest visit of
  /// a batch is a valid watermark for the batches after it. A batch is never cut between two visits with the same time.
  @concurrent
  static func history(
    file: URL, after watermark: Date?, oldest: Date, visitsPerBatch: Int
  ) async throws -> PreparedBatches<ImportedHistoryEntry> {
    var entries: [ImportedHistoryEntry] = []
    try HistoryReader.read(from: file) { entries += $0 }

    var visits: [(entry: Int, visit: HistoryVisit)] = []
    var total = 0
    for (index, entry) in entries.enumerated() {
      for visit in entry.visits {
        total += 1
        if visit.time >= oldest, watermark.map({ visit.time > $0 }) ?? true { visits.append((index, visit)) }
      }
    }
    visits.sort { ($0.visit.time, $0.entry) < ($1.visit.time, $1.entry) }

    var result = PreparedBatches<ImportedHistoryEntry>()
    result.alreadyHandled = total - visits.count
    var start = 0
    while start < visits.count {
      var end = min(start + visitsPerBatch, visits.count)
      while end < visits.count, visits[end].visit.time == visits[end - 1].visit.time { end += 1 }
      var order: [Int] = []
      var grouped: [Int: [HistoryVisit]] = [:]
      for item in visits[start..<end] {
        if grouped[item.entry] == nil { order.append(item.entry) }
        grouped[item.entry, default: []].append(item.visit)
      }
      result.batches.append(order.map { index in
        let entry = entries[index]
        return ImportedHistoryEntry(
          url: entry.url, title: entry.title, visitCount: entry.visitCount, typedCount: entry.typedCount,
          lastVisit: entry.lastVisit, visits: grouped[index] ?? [])
      })
      start = end
    }
    return result
  }

  @concurrent
  static func bookmarks(
    profile: ArcProfileSnapshot.Profile, known: Set<String>, batchSize: Int
  ) async throws -> PreparedBatches<BookmarkRecord> {
    let all = try BookmarksReader.read(profile: profile).bookmarks
    let fresh = all.filter { !known.contains(ArcImportKey.bookmark($0)) }
    return PreparedBatches(batches: chunks(fresh, of: batchSize), alreadyHandled: all.count - fresh.count)
  }

  @concurrent
  static func extensionIDs(profile: ArcProfileSnapshot.Profile, known: Set<String>) async throws -> PreparedBatches<String> {
    let all = try ExtensionListReader.read(profile: profile).map(\.id)
    let fresh = all.filter { !known.contains($0) }
    return PreparedBatches(batches: fresh.isEmpty ? [] : [fresh], alreadyHandled: all.count - fresh.count)
  }

  // MARK: Cookies and passwords

  /// Fetches the Safe Storage key once and reads the cookies and the logins with it. The key is dropped when this returns;
  /// no decryptor outlives the call, so the secrets come back as plaintext batches that the caller writes and wipes.
  @concurrent
  static func secrets(
    profile: ArcProfileSnapshot.Profile, readCookies: Bool, readLogins: Bool, provider: any SafeStorageKeyProvider,
    now: Date, knownCookies: Set<String>, knownLogins: Set<String>, batchSize: Int
  ) async -> Secrets {
    var result = Secrets()
    do {
      try ChromiumDecryptor.withDecryptor(provider: provider) { decryptor in
        if readCookies, let file = profile.copiedFile("Network/Cookies", "Cookies") {
          var fresh: [ArcCookie] = []
          do {
            try CookieReader(now: { now }, log: { _ in }).read(cookiesDatabase: file, decryptor: decryptor) { batch in
              for cookie in batch {
                if knownCookies.contains(ArcImportKey.cookie(cookie)) {
                  result.cookies.alreadyHandled += 1
                  cookie.value.wipe()
                } else {
                  fresh.append(cookie)
                }
              }
            }
            result.cookies.batches = chunks(fresh, of: batchSize)
          } catch {
            for cookie in fresh { cookie.value.wipe() }
            result.failures[.cookies] = .failed(reason: "could not read Cookies")
          }
        }
        if readLogins, let file = profile.copiedFile("Login Data") {
          var fresh: [ArcLogin] = []
          do {
            try LoginReader(log: { _ in }).read(loginDatabase: file, decryptor: decryptor) { batch in
              for login in batch {
                if knownLogins.contains(ArcImportKey.login(login)) {
                  result.logins.alreadyHandled += 1
                  login.password.wipe()
                } else {
                  fresh.append(login)
                }
              }
            }
            result.logins.batches = chunks(fresh, of: batchSize)
          } catch {
            for login in fresh { login.password.wipe() }
            result.failures[.passwords] = .failed(reason: "could not read Login Data")
          }
        }
      }
    } catch {
      result.wipe()
      result = Secrets()
      let reason = keyFailureReason(error)
      if readCookies { result.failures[.cookies] = .failed(reason: reason) }
      if readLogins { result.failures[.passwords] = .failed(reason: reason) }
    }
    return result
  }

  /// A fixed phrase for a failed key fetch; nothing from the error's payload.
  static func keyFailureReason(_ error: any Error) -> String {
    switch error as? SafeStorageError {
    case .accessDenied?: "Keychain access denied"
    case .userCanceled?: "Keychain prompt dismissed"
    case .interactionNotAllowed?: "Keychain prompt not available"
    case .itemNotFound?: "Arc Safe Storage item not found"
    case .malformedItem?: "Arc Safe Storage item unreadable"
    case .other?: "Keychain error"
    case nil: "could not derive the key"
    }
  }

  static func chunks<Item>(_ items: [Item], of size: Int) -> [[Item]] {
    stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
  }
}
