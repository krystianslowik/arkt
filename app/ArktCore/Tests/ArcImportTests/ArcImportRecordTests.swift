import ArcImport
import CoreTestSupport
import Foundation
import Synchronization
import Testing

struct ArcImportRecordTests {
  private static let date = Date(timeIntervalSince1970: 1_704_067_200)

  @Test func versionOneRecordStaysReadable() throws {
    let stored = Data(#"{"favoriteItemIDs":["f1"],"spaceIDs":["s1","s2"]}"#.utf8)
    let record = try JSONDecoder().decode(ArcImportRecord.self, from: stored)
    #expect(record == ArcImportRecord(spaceIDs: ["s1", "s2"], favoriteItemIDs: ["f1"]))
    #expect(record.historyWatermark == nil)
    #expect(record.cookieKeys.isEmpty && record.loginKeys.isEmpty && record.bookmarkKeys.isEmpty)
    #expect(record.extensionIDs.isEmpty)
  }

  @Test func recordWithOnlyNewFieldsDecodes() throws {
    let record = try JSONDecoder().decode(ArcImportRecord.self, from: Data(#"{"cookieKeys":["k"]}"#.utf8))
    #expect(record == ArcImportRecord(cookieKeys: ["k"]))
  }

  @Test func versionTwoRoundTripsWithSortedBytes() throws {
    let record = ArcImportRecord(
      spaceIDs: ["b", "a"], favoriteItemIDs: ["z"], historyWatermark: Self.date, bookmarkKeys: ["y", "x"],
      cookieKeys: ["c2", "c1"], loginKeys: ["l"], extensionIDs: ["e2", "e1"])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(record)
    #expect(try JSONDecoder().decode(ArcImportRecord.self, from: data) == record)
    #expect(try encoder.encode(record) == data)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""spaceIDs":["a","b"]"#) && text.contains(#""bookmarkKeys":["x","y"]"#))
  }

  @Test func aRecordWithOnlyVersionOneContentKeepsItsStoredBytes() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(ArcImportRecord(spaceIDs: ["b", "a"], favoriteItemIDs: ["z"]))
    #expect(String(decoding: data, as: UTF8.self) == #"{"favoriteItemIDs":["z"],"spaceIDs":["a","b"]}"#)
  }

  @Test func unionKeepsTheLaterWatermarkAndEverySet() {
    var stored = ArcImportRecord(historyWatermark: Self.date, cookieKeys: ["a"])
    stored.formUnion(ArcImportRecord(historyWatermark: Self.date.addingTimeInterval(-10), cookieKeys: ["b"]))
    #expect(stored.historyWatermark == Self.date)
    stored.formUnion(ArcImportRecord(historyWatermark: Self.date.addingTimeInterval(10), loginKeys: ["l"]))
    #expect(stored.historyWatermark == Self.date.addingTimeInterval(10))
    #expect(stored.cookieKeys == ["a", "b"] && stored.loginKeys == ["l"])
    var empty = ArcImportRecord()
    empty.formUnion(ArcImportRecord())
    #expect(empty.isEmpty && empty.historyWatermark == nil)
    #expect(!stored.isEmpty && !ArcImportRecord(historyWatermark: Self.date).isEmpty)
  }

  @Test func keysAreDigestsThatHoldNoPlainText() throws {
    try ReaderTestSupport.withProfile { manifest in
      var cookies: [ArcCookie] = []
      try CookieReader(now: { ReaderTestSupport.fixtureNow }, log: { _ in }).read(
        cookiesDatabase: manifest.cookiesURL, keyProvider: ReaderTestSupport.provider()
      ) { cookies += $0 }
      var logins: [ArcLogin] = []
      try LoginReader(log: { _ in }).read(
        loginDatabase: manifest.loginDataURL, keyProvider: ReaderTestSupport.provider()
      ) { logins += $0 }
      let bookmarks = try BookmarksReader.read(from: manifest.bookmarksURL).bookmarks
      let keys = cookies.map { ArcImportKey.cookie($0) } + logins.map { ArcImportKey.login($0) }
        + bookmarks.map { ArcImportKey.bookmark($0) }
      #expect(!keys.isEmpty && Set(keys).count == keys.count)
      for key in keys {
        #expect(key.count == 32 && key.allSatisfy { $0.isHexDigit })
      }
      let session = try #require(cookies.first { $0.name == "session" })
      #expect(ArcImportKey.cookie(session) == ArcImportKey.cookie(session))
    }
  }

  @Test func theSaltChangesEveryKeyAndSurvivesTheRecord() throws {
    let bookmark = BookmarkRecord(root: "bar", folderPath: [], title: "One", url: "https://a.test/", guid: "g", dateAdded: nil)
    #expect(ArcImportKey.bookmark(bookmark, salt: "one") != ArcImportKey.bookmark(bookmark, salt: "two"))
    #expect(ArcImportKey.bookmark(bookmark, salt: "one") == ArcImportKey.bookmark(bookmark, salt: "one"))
    let salt = ArcImportKey.makeSalt()
    #expect(salt.count == 32 && salt != ArcImportKey.makeSalt())
    var stored = ArcImportRecord(salt: "first")
    stored.formUnion(ArcImportRecord(salt: "second"))
    #expect(stored.salt == "first")
    var unsalted = ArcImportRecord()
    unsalted.formUnion(ArcImportRecord(salt: "second"))
    #expect(unsalted.salt == "second")
    let data = try JSONEncoder().encode(ArcImportRecord(salt: "s"))
    #expect(try JSONDecoder().decode(ArcImportRecord.self, from: data).salt == "s")
  }

  @Test func bookmarkKeyIgnoresTheTitleWhenTheGuidIsKnown() {
    let first = BookmarkRecord(root: "bar", folderPath: ["A"], title: "One", url: "https://a.test/", guid: "G-1", dateAdded: nil)
    let renamed = BookmarkRecord(root: "bar", folderPath: ["B"], title: "Two", url: "https://a.test/", guid: "g-1", dateAdded: nil)
    let plain = BookmarkRecord(root: "bar", folderPath: ["A"], title: "One", url: "https://a.test/", guid: nil, dateAdded: nil)
    #expect(ArcImportKey.bookmark(first) == ArcImportKey.bookmark(renamed))
    #expect(ArcImportKey.bookmark(plain) != ArcImportKey.bookmark(first))
  }
}

struct ProfileDataCounterTests {
  @Test func countsCookiesTheReaderWouldTryToDecrypt() throws {
    try ReaderTestSupport.withProfile { manifest in
      // Fixture: 3 cookies, one is a session cookie. Both persistent ones expire after fixtureNow.
      let now = try ProfileDataCounter.cookies(in: manifest.cookiesURL, now: ReaderTestSupport.fixtureNow)
      #expect(now == 2)
      // After the one-day cookie expired, only the one-year cookie is left.
      let later = ReaderTestSupport.fixtureBase.addingTimeInterval(2 * 86_400)
      let afterExpiry = try ProfileDataCounter.cookies(in: manifest.cookiesURL, now: later)
      #expect(afterExpiry == 1)
    }
  }

  @Test func countsLoginsWithoutAKey() throws {
    try ReaderTestSupport.withProfile { manifest in
      let all = try ProfileDataCounter.logins(in: manifest.loginDataURL)
      #expect(all == manifest.logins.count)
      try ReaderTestSupport.execute(manifest.loginDataURL, "UPDATE logins SET blacklisted_by_user = 1 WHERE rowid = 1")
      let remaining = try ProfileDataCounter.logins(in: manifest.loginDataURL)
      #expect(remaining == manifest.logins.count - 1)
    }
  }

  @Test func countsSurviveMissingOptionalColumns() throws {
    try ReaderTestSupport.withProfile(.init(drift: .missingOptionalColumn)) { manifest in
      let cookies = try ProfileDataCounter.cookies(in: manifest.cookiesURL, now: ReaderTestSupport.fixtureNow)
      let logins = try ProfileDataCounter.logins(in: manifest.loginDataURL)
      #expect(cookies >= 1 && logins == manifest.logins.count)
    }
  }

  @Test func aFileThatIsNotADatabaseThrows() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("counter-\(UUID().uuidString)")
    try Data("not a database".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(throws: (any Error).self) { try ProfileDataCounter.logins(in: file) }
  }
}

struct ChromiumKeyTests {
  private final class CountingProvider: SafeStorageKeyProvider {
    private let asked = Mutex(0)
    var timesAsked: Int { asked.withLock { $0 } }
    func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
      asked.withLock { $0 += 1 }
      return try body(Array(FakeChromiumProfile.safeStoragePassword.utf8))
    }
  }

  @Test func windowsDecryptWithOneKeyFetchAndMatchTheFullRead() throws {
    try ReaderTestSupport.withProfile { manifest in
      let provider = CountingProvider()
      let key = try ChromiumKey(provider: provider)
      let reader = CookieReader(now: { ReaderTestSupport.fixtureNow }, log: { _ in })
      var names: [String] = []
      var scanned: [Int] = []
      for window in [0..<2, 2..<4, 4..<6] {
        let summary = try key.withDecryptor { decryptor in
          try reader.read(cookiesDatabase: manifest.cookiesURL, decryptor: decryptor, rows: window) { names += $0.map(\.name) }
        }
        scanned.append(summary.scanned)
      }
      #expect(scanned == [2, 1, 0])
      var full: [String] = []
      try reader.read(cookiesDatabase: manifest.cookiesURL, keyProvider: ReaderTestSupport.provider()) { full += $0.map(\.name) }
      #expect(names == full)
      #expect(provider.timesAsked == 1)
    }
  }

  @Test func loginWindowsCoverEveryRowOnce() throws {
    try ReaderTestSupport.withProfile { manifest in
      let key = try ChromiumKey(provider: ReaderTestSupport.provider())
      var users: [String] = []
      for window in [0..<2, 2..<4] {
        try key.withDecryptor { decryptor in
          try LoginReader(log: { _ in }).read(loginDatabase: manifest.loginDataURL, decryptor: decryptor, rows: window) {
            users += $0.map(\.username)
          }
        }
      }
      #expect(users.sorted() == manifest.logins.map(\.username).sorted())
    }
  }

  @Test func aWipedKeyDecryptsNothing() throws {
    try ReaderTestSupport.withProfile { manifest in
      let key = try ChromiumKey(provider: ReaderTestSupport.provider())
      key.wipe()
      var count = 0
      let summary = try key.withDecryptor { decryptor in
        try LoginReader(log: { _ in }).read(loginDatabase: manifest.loginDataURL, decryptor: decryptor) { count += $0.count }
      }
      #expect(count == 0 && summary.skippedUndecryptable == manifest.logins.count)
    }
  }
}
