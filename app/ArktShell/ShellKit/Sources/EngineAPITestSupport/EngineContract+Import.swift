import ArcImport
import EngineAPI
import Foundation

/// The import contract (#512) every `EngineImporting` stub keeps: the counts, the dedupe rules and the zeroing of the
/// secrets. The Chromium engine keeps the same rules in C++; they run there in the engine check, not here.
public enum EngineImportContract {
  public static let future = Date(timeIntervalSinceNow: 86_400 * 30)

  public static func cookie(
    _ name: String, value: String = "v", host: String = ".example.com", path: String = "/", lastAccess: TimeInterval = 100,
    expires: Date = future, partitionKey: String = ""
  ) -> ArcCookie {
    ArcCookie(
      hostKey: host, name: name, value: SecretBytes(taking: Array(value.utf8)), path: path, expires: expires,
      creation: Date(timeIntervalSince1970: 50), lastAccess: Date(timeIntervalSince1970: lastAccess),
      partitionKey: partitionKey)
  }

  public static func login(
    _ realm: String, user: String, password: String, action: String? = nil, lastUsed: TimeInterval = 100
  ) -> ArcLogin {
    ArcLogin(
      originURL: realm + "login", actionURL: action, signonRealm: realm, username: user,
      password: SecretBytes(taking: Array(password.utf8)), dateCreated: Date(timeIntervalSince1970: 50),
      dateLastUsed: Date(timeIntervalSince1970: lastUsed))
  }

  /// A history entry whose visits are `days` days old, one hour apart, with the given core transitions.
  public static func historyEntry(
    _ url: String, title: String = "Title", days: Double = 2, transitions: [HistoryTransition] = [.link]
  ) -> ImportedHistoryEntry {
    let base = Date().addingTimeInterval(-days * 86_400)
    let visits = transitions.enumerated().map { HistoryVisit(time: base.addingTimeInterval(Double($0.offset) * 3_600), transition: $0.element) }
    return ImportedHistoryEntry(
      url: url, title: title, visitCount: visits.count, typedCount: transitions.filter { $0 == .typed }.count,
      lastVisit: visits.last?.time, visits: visits)
  }

  public static func bookmark(
    _ title: String, url: String, path: [String] = [], guid: String? = nil, root: String = "bookmark_bar"
  ) -> BookmarkRecord {
    BookmarkRecord(root: root, folderPath: path, title: title, url: url, guid: guid, dateAdded: nil)
  }

  public static func isZeroed(_ secret: SecretBytes) -> Bool { secret.withBytes { $0.allSatisfy { $0 == 0 } } }

  @MainActor
  public static func run(_ engine: some EngineImporting) async throws {
    // An empty batch writes nothing and answers zero counts.
    var result = await engine.importCookies([])
    try EngineContract.require(result == ImportWriteResult(), "empty cookie batch: \(result)")
    result = await engine.importPasswords([])
    try EngineContract.require(result == ImportWriteResult(), "empty login batch: \(result)")

    // Duplicates by (name, host key, path): the cookie last used most recently wins wherever it is in the batch; the
    // later entry wins a tie; another name, host key or path is not a duplicate.
    let first = [
      cookie("a", value: "old", lastAccess: 100), cookie("a", value: "new", lastAccess: 200),
      cookie("b", value: "x", lastAccess: 300), cookie("b", value: "y", lastAccess: 100),
      cookie("c", value: "x", lastAccess: 100), cookie("c", value: "y", lastAccess: 100),
      cookie("a", value: "other-host", host: "www.example.com", lastAccess: 100),
      cookie("a", value: "other-path", path: "/docs", lastAccess: 100),
    ]
    result = await engine.importCookies(first)
    try EngineContract.require(result == ImportWriteResult(written: 5, skipped: 3), "first cookie batch: \(result)")
    try EngineContract.require(first.allSatisfy { isZeroed($0.value) }, "cookie secrets are zeroed after the call")

    // The same cookies again: none is newer than what the profile holds. A newer one replaces it. An expired one is
    // skipped and never written.
    result = await engine.importCookies([cookie("a", value: "again", lastAccess: 200)])
    try EngineContract.require(result == ImportWriteResult(skipped: 1), "same cookie again: \(result)")
    result = await engine.importCookies([
      cookie("a", value: "newer", lastAccess: 250), cookie("gone", expires: Date(timeIntervalSinceNow: -60)),
    ])
    try EngineContract.require(result == ImportWriteResult(written: 1, skipped: 1), "newer and expired: \(result)")

    // A partitioned cookie is skipped, even when it is newer than an ordinary one with the same key (which still
    // lands), and an ordinary cookie next to it is written.
    let partitioned = [
      cookie("p", value: "top-level-only", host: ".tracker.example", lastAccess: 900, partitionKey: "https://news.example"),
      cookie("p", value: "plain", host: ".tracker.example", lastAccess: 100),
      cookie("q", value: "only-partitioned", host: ".tracker.example", partitionKey: "https://news.example"),
    ]
    result = await engine.importCookies(partitioned)
    try EngineContract.require(result == ImportWriteResult(written: 1, skipped: 2), "partitioned cookies: \(result)")
    try EngineContract.require(partitioned.allSatisfy { isZeroed($0.value) }, "partitioned secrets are zeroed too")

    // Logins: duplicates by (signon realm, username, action) keep the later entry; another action or user is not a
    // duplicate; a login the store holds is replaced only by a newer one.
    let logins = [
      login("https://example.com/", user: "u", password: "first"),
      login("https://example.com/", user: "u", password: "second"),
      login("https://example.com/", user: "u", password: "other-action", action: "https://example.com/post"),
      login("https://example.com/", user: "v", password: "other-user"),
    ]
    result = await engine.importPasswords(logins)
    try EngineContract.require(result == ImportWriteResult(written: 3, skipped: 1), "login batch: \(result)")
    try EngineContract.require(logins.allSatisfy { isZeroed($0.password) }, "login secrets are zeroed after the call")
    let older = [login("https://example.com/", user: "u", password: "third", lastUsed: 100)]
    result = await engine.importPasswords(older)
    try EngineContract.require(result == ImportWriteResult(skipped: 1), "login the store holds: \(result)")
    try EngineContract.require(isZeroed(older[0].password), "the secret of a skipped login is zeroed")
    let newer = [login("https://example.com/", user: "u", password: "fourth", lastUsed: 200)]
    result = await engine.importPasswords(newer)
    try EngineContract.require(result == ImportWriteResult(written: 1), "newer login: \(result)")
    try EngineContract.require(isZeroed(newer[0].password), "the secret of a stored login is zeroed")
  }

  /// History (#511): counts are in visits; the watermark skips what was imported before; the result carries the newest
  /// visit written; old visits and URLs the history refuses are skipped; an invalid URL fails its visits.
  @MainActor
  public static func runHistory(_ engine: some EngineImporting) async throws {
    var result = await engine.importHistory([], after: nil)
    try EngineContract.require(result == ImportWriteResult(), "empty history batch: \(result)")

    let first = historyEntry("https://example.com/", title: "One", days: 3, transitions: [.typed, .link, .reload])
    let second = historyEntry("https://example.org/a", days: 2, transitions: [.link])
    result = await engine.importHistory([first, second], after: nil)
    try EngineContract.require(
      result == ImportWriteResult(written: 4, latestVisit: second.visits.last?.time), "first history batch: \(result)")

    // The same batch with the watermark the first call returned writes nothing.
    result = await engine.importHistory([first, second], after: second.visits.last?.time)
    try EngineContract.require(result == ImportWriteResult(skipped: 4), "same batch at the watermark: \(result)")

    // A watermark inside the batch keeps the visits after it only; a visit exactly at it is skipped.
    let third = historyEntry("https://example.net/", days: 1, transitions: [.link, .link, .link])
    result = await engine.importHistory([third], after: third.visits[1].time)
    try EngineContract.require(
      result == ImportWriteResult(written: 1, skipped: 2, latestVisit: third.visits[2].time), "watermark inside: \(result)")

    // Older than the 90 days Chromium keeps, an address the history refuses, and an address that is not one.
    let old = historyEntry("https://old.example/", days: 120)
    let internalPage = historyEntry("chrome://settings/", transitions: [.link, .link])
    let broken = historyEntry("not a url", transitions: [.link, .link, .link])
    result = await engine.importHistory([old, internalPage, broken], after: nil)
    try EngineContract.require(
      result.written == 0 && result.skipped == 3 && result.failed == 3 && result.latestVisit == nil,
      "old, refused and invalid: \(result)")
  }

  /// Bookmarks (#511): a guid the profile holds, or a url and title the target folder holds, is skipped; folders are
  /// kept; an invalid url fails.
  @MainActor
  public static func runBookmarks(_ engine: some EngineImporting) async throws {
    var result = await engine.importBookmarks([])
    try EngineContract.require(result == ImportWriteResult(), "empty bookmark batch: \(result)")

    let guid = "00000000-0000-4000-8000-0000000000AA"
    let batch = [
      bookmark("Top", url: "https://example.com/", guid: guid),
      bookmark("Nested", url: "https://example.com/n", path: ["Reading", "Later"], guid: "00000000-0000-4000-8000-0000000000AB"),
      bookmark("Same guid", url: "https://example.com/elsewhere", path: ["Other"], guid: guid.lowercased()),
      bookmark("Top", url: "https://example.com/", root: "other"),
      bookmark("Bad", url: ""),
    ]
    result = await engine.importBookmarks(batch)
    try EngineContract.require(
      result.written == 2 && result.skipped == 2 && result.failed == 1, "first bookmark batch: \(result)")

    result = await engine.importBookmarks(batch)
    try EngineContract.require(result.written == 0 && result.skipped == 4 && result.failed == 1, "re-import: \(result)")

    // No guid: the same url and title in the same folder is a duplicate, in another folder it is not.
    result = await engine.importBookmarks([
      bookmark("Nested", url: "https://example.com/n", path: ["Reading", "Later"]),
      bookmark("Nested", url: "https://example.com/n", path: ["Reading"]),
    ])
    try EngineContract.require(result == ImportWriteResult(written: 1, skipped: 1), "url and title by folder: \(result)")
  }
}
