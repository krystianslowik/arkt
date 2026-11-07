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

  /// One window of decrypted rows: the plaintext items to write now, and how many rows of the window were left out
  /// because an earlier import handled them.
  struct Window<Item: Sendable>: Sendable {
    var items: [Item] = []
    var scanned = 0
    var alreadyHandled = 0
  }

  static let notInProfile = "not in the Arc profile"

  // MARK: Snapshot and count

  @concurrent
  static func snapshot(root: URL, scratchParent: URL) async throws -> ArcProfileSnapshot {
    try ArcProfileSnapshot.make(root: root, scratchParent: scratchParent)
  }

  /// Deletes the scratch copy off the main actor. `ArcProfileSnapshot.sweepStale` at launch is the backstop.
  @concurrent
  static func remove(_ snapshot: ArcProfileSnapshot) async { snapshot.remove() }

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
  /// The read streams: visits outside the window are dropped as each batch of entries arrives, so only the visits the
  /// engine would accept are held.
  @concurrent
  static func history(
    file: URL, after watermark: Date?, oldest: Date, visitsPerBatch: Int
  ) async throws -> PreparedBatches<ImportedHistoryEntry> {
    var entries: [ImportedHistoryEntry] = []
    var visits: [(entry: Int, visit: HistoryVisit)] = []
    var total = 0
    try HistoryReader.read(from: file) { batch in
      for entry in batch {
        let index = entries.count
        entries.append(entry.keepingNoVisits())
        for visit in entry.visits {
          total += 1
          if visit.time >= oldest, watermark.map({ visit.time > $0 }) ?? true { visits.append((index, visit)) }
        }
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
    profile: ArcProfileSnapshot.Profile, known: Set<String>, salt: String, batchSize: Int
  ) async throws -> PreparedBatches<BookmarkRecord> {
    let all = try BookmarksReader.read(profile: profile).bookmarks
    let fresh = all.filter { !known.contains(ArcImportKey.bookmark($0, salt: salt)) }
    return PreparedBatches(batches: chunks(fresh, of: batchSize), alreadyHandled: all.count - fresh.count)
  }

  @concurrent
  static func extensionIDs(profile: ArcProfileSnapshot.Profile, known: Set<String>) async throws -> PreparedBatches<String> {
    let all = try ExtensionListReader.read(profile: profile).map(\.id)
    let fresh = all.filter { !known.contains($0) }
    return PreparedBatches(batches: fresh.isEmpty ? [] : [fresh], alreadyHandled: all.count - fresh.count)
  }

  // MARK: Cookies and passwords

  /// Reads the Safe Storage password once and derives the key. The key is held by the caller between windows and wiped by
  /// it; no plaintext is read here.
  @concurrent
  static func openKey(provider: any SafeStorageKeyProvider) async -> Result<ChromiumKey, KeyFailure> {
    do { return .success(try ChromiumKey(provider: provider)) } catch {
      return .failure(KeyFailure(reason: keyFailureReason(error)))
    }
  }

  struct KeyFailure: Error, Sendable { var reason: String }

  /// Decrypts the cookies of rows `rows` and returns those no earlier import handled. Plaintext exists only in the
  /// returned window; if the read throws, everything decrypted so far is wiped first.
  @concurrent
  static func cookieWindow(
    file: URL, key: ChromiumKey, rows: Range<Int>, now: Date, known: Set<String>, salt: String
  ) async throws -> Window<ArcCookie> {
    var window = Window<ArcCookie>()
    do {
      let summary = try key.withDecryptor { decryptor in
        try CookieReader(now: { now }, log: { _ in }).read(cookiesDatabase: file, decryptor: decryptor, rows: rows) { batch in
          for cookie in batch {
            if known.contains(ArcImportKey.cookie(cookie, salt: salt)) {
              window.alreadyHandled += 1
              cookie.value.wipe()
            } else {
              window.items.append(cookie)
            }
          }
        }
      }
      window.scanned = summary.scanned
      return window
    } catch {
      for cookie in window.items { cookie.value.wipe() }
      throw error
    }
  }

  @concurrent
  static func loginWindow(
    file: URL, key: ChromiumKey, rows: Range<Int>, known: Set<String>, salt: String
  ) async throws -> Window<ArcLogin> {
    var window = Window<ArcLogin>()
    do {
      let summary = try key.withDecryptor { decryptor in
        try LoginReader(log: { _ in }).read(loginDatabase: file, decryptor: decryptor, rows: rows) { batch in
          for login in batch {
            if known.contains(ArcImportKey.login(login, salt: salt)) {
              window.alreadyHandled += 1
              login.password.wipe()
            } else {
              window.items.append(login)
            }
          }
        }
      }
      window.scanned = summary.scanned
      return window
    } catch {
      for login in window.items { login.password.wipe() }
      throw error
    }
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

extension ImportedHistoryEntry {
  /// The same entry without its visits, so a streamed read keeps the entry's fields and only the visits that pass the
  /// filter.
  fileprivate func keepingNoVisits() -> ImportedHistoryEntry {
    ImportedHistoryEntry(url: url, title: title, visitCount: visitCount, typedCount: typedCount, lastVisit: lastVisit, visits: [])
  }
}
