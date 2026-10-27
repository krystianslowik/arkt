import ArcImport
import CoreTestSupport
import Foundation
import Testing

struct CookieReaderTests {
  typealias Support = ReaderTestSupport

  private func readAll(
    _ manifest: FixtureManifest, password: String = FakeChromiumProfile.safeStoragePassword,
    now: Date = Support.fixtureNow, log: @escaping @Sendable (String) -> Void = { _ in }
  ) throws -> (cookies: [ArcCookie], summary: CookieReadSummary) {
    var cookies: [ArcCookie] = []
    let summary = try CookieReader(now: { now }, log: log).read(
      cookiesDatabase: manifest.cookiesURL, keyProvider: Support.provider(password: password)
    ) { cookies += $0 }
    return (cookies, summary)
  }

  // MARK: - Fixtures

  @Test(arguments: [FakeChromiumProfile.CookieFormat.v24, .v23])
  func readsTheFixtureCookiesForEachMetaVersion(format: FakeChromiumProfile.CookieFormat) throws {
    try Support.withProfile(.init(cookieFormat: format)) { manifest in
      let (cookies, summary) = try readAll(manifest)
      #expect(summary.metaVersion == manifest.cookiesMetaVersion)
      let persistent = manifest.cookies.filter { $0.expiresWebKitTime != 0 }
      #expect(cookies.count == persistent.count)
      for expected in persistent {
        let cookie = try #require(cookies.first { $0.name == expected.name && $0.hostKey == expected.hostKey })
        #expect(Support.text(cookie.value) == expected.value)
        #expect(cookie.path == expected.path)
        #expect(cookie.isSecure == expected.isSecure)
        #expect(cookie.isHTTPOnly == expected.isHTTPOnly)
        #expect(cookie.expires == ChromiumTime.date(fromWebKit: expected.expiresWebKitTime))
        #expect(cookie.hasExpires)
        #expect(cookie.isPersistent)
        #expect(cookie.sameSite == -1)
        #expect(cookie.priority == 1)
        #expect(cookie.sourceScheme == (expected.isSecure ? 2 : 1))
        #expect(cookie.sourcePort == (expected.isSecure ? 443 : 80))
        #expect(cookie.creation != nil)
        #expect(cookie.lastAccess != nil)
      }
    }
  }

  @Test func extraFixtureCookiesAndLoginsAreWrittenAfterTheFixedOnes() throws {
    let extra = FixtureManifest.Cookie(
      hostKey: "127.0.0.1", name: "local", value: "loopback-value", path: "/", isSecure: false, isHTTPOnly: false,
      expiresWebKitTime: ChromiumTime.webKit(fromUnixSeconds: 4_102_444_800))
    let login = FixtureManifest.Login(
      originURL: "http://127.0.0.1/", signonRealm: "http://127.0.0.1/", username: "local-user", password: "local-pass")
    try Support.withProfile(.init(extraCookies: [extra], extraLogins: [login])) { manifest in
      #expect(manifest.cookies.last == extra)
      #expect(manifest.logins.last == login)
      let (cookies, _) = try readAll(manifest)
      let read = try #require(cookies.first { $0.name == "local" })
      #expect(read.hostKey == "127.0.0.1" && Support.text(read.value) == "loopback-value")
    }
  }

  @Test func countsMatchTheManifest() throws {
    try Support.withProfile { manifest in
      let (cookies, summary) = try readAll(manifest)
      let sessionCount = manifest.cookies.filter { $0.expiresWebKitTime == 0 }.count
      #expect(summary.scanned == manifest.cookies.count)
      #expect(summary.delivered == cookies.count)
      #expect(summary.skippedSession == sessionCount)
      #expect(summary.skippedExpired == 0)
      #expect(summary.skippedUndecryptable == 0)
      #expect(summary.skippedMalformed == 0)
      #expect(summary.delivered + summary.skippedSession == manifest.cookies.count)
    }
  }

  // MARK: - Skips

  @Test func sessionCookiesAreSkippedAndCounted() throws {
    try Support.withProfile { manifest in
      let (cookies, summary) = try readAll(manifest)
      #expect(!cookies.contains { $0.name == "empty" })
      #expect(summary.skippedSession == 1)
    }
  }

  @Test func nonPersistentOrNonExpiringRowsAreSessionCookies() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.cookiesURL, "UPDATE cookies SET is_persistent = 0 WHERE name = 'theme'")
      try Support.execute(manifest.cookiesURL, "UPDATE cookies SET has_expires = 0 WHERE name = 'session'")
      let (cookies, summary) = try readAll(manifest)
      #expect(cookies.isEmpty)
      #expect(summary.skippedSession == 3)
    }
  }

  @Test func expiredCookiesAreSkippedAndCounted() throws {
    try Support.withProfile { manifest in
      let afterTheDayCookie = Support.fixtureBase.addingTimeInterval(100_000)
      let (cookies, summary) = try readAll(manifest, now: afterTheDayCookie)
      #expect(cookies.map(\.name) == ["session"])
      #expect(summary.skippedExpired == 1)
      #expect(summary.skippedSession == 1)

      let afterAll = Support.fixtureBase.addingTimeInterval(40_000_000)
      let everything = try readAll(manifest, now: afterAll)
      #expect(everything.cookies.isEmpty)
      #expect(everything.summary.skippedExpired == 2)
    }
  }

  // MARK: - Schema

  @Test(arguments: [FakeChromiumProfile.SchemaDrift.extraColumn, .missingOptionalColumn])
  func toleratesSchemaDrift(drift: FakeChromiumProfile.SchemaDrift) throws {
    try Support.withProfile(.init(drift: drift)) { manifest in
      let (cookies, summary) = try readAll(manifest)
      #expect(cookies.count == 2)
      #expect(summary.skippedMalformed == 0)
      #expect(summary.skippedUndecryptable == 0)
    }
  }

  @Test func probesColumnsAndFallsBackToDefaultsForMissingOptionalOnes() throws {
    try Support.withProfile { manifest in
      for column in ["samesite", "priority", "source_scheme", "source_port", "has_expires", "is_persistent", "last_access_utc"] {
        try Support.execute(manifest.cookiesURL, "ALTER TABLE cookies DROP COLUMN \(column)")
      }
      let (cookies, summary) = try readAll(manifest)
      #expect(summary.skippedSession == 1)
      #expect(cookies.count == 2)
      for cookie in cookies {
        #expect(cookie.sameSite == -1)
        #expect(cookie.priority == 1)
        #expect(cookie.sourceScheme == 0)
        #expect(cookie.sourcePort == -1)
        #expect(cookie.hasExpires)
        #expect(cookie.isPersistent)
        #expect(cookie.lastAccess == nil)
      }
    }
  }

  @Test func aMissingRequiredColumnIsAFileLevelError() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.cookiesURL, "ALTER TABLE cookies DROP COLUMN encrypted_value")
      #expect(throws: ChromiumReadError.missingColumns(table: "cookies", columns: ["encrypted_value"])) {
        try readAll(manifest)
      }
    }
  }

  @Test func aMissingTableOrMetaVersionIsAFileLevelError() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.cookiesURL, "DELETE FROM meta WHERE key = 'version'")
      #expect(throws: ChromiumReadError.metaVersionUnavailable) { try readAll(manifest) }
      try Support.execute(manifest.cookiesURL, "DROP TABLE cookies")
      #expect(throws: ChromiumReadError.tableMissing("cookies")) { try readAll(manifest) }
    }
  }

  @Test func anUnopenableFileIsAFileLevelError() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
    #expect(throws: ChromiumReadError.self) {
      try CookieReader().read(cookiesDatabase: missing, keyProvider: Support.provider()) { _ in }
    }
  }

  // MARK: - Bad rows

  @Test(arguments: [FakeChromiumProfile.CookieFormat.v24, .v23])
  func aWrongKeyFailsEveryRowAndCountsThem(format: FakeChromiumProfile.CookieFormat) throws {
    try Support.withProfile(.init(cookieFormat: format)) { manifest in
      let (cookies, summary) = try readAll(manifest, password: "not-the-fixture-password")
      #expect(cookies.isEmpty)
      #expect(summary.delivered == 0)
      #expect(summary.skippedUndecryptable == 2)
      #expect(summary.skippedSession == 1)
    }
  }

  @Test func aBadRowIsSkippedAndCountedNotFatal() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.cookiesURL, "UPDATE cookies SET encrypted_value = x'0102030405' WHERE name = 'theme'")
      let (cookies, summary) = try readAll(manifest)
      #expect(cookies.map(\.name) == ["session"])
      #expect(summary.skippedUndecryptable == 1)
    }
  }

  @Test func aV24ValueForAnotherHostIsSkippedAndCounted() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.cookiesURL, "UPDATE cookies SET host_key = '.other.example' WHERE name = 'session'")
      let (cookies, summary) = try readAll(manifest)
      #expect(cookies.map(\.name) == ["theme"])
      #expect(summary.skippedUndecryptable == 1)
    }
  }

  @Test func aRowWithoutAHostIsMalformed() throws {
    try Support.withProfile(.init(cookieFormat: .v23)) { manifest in
      try Support.execute(manifest.cookiesURL, "ALTER TABLE cookies RENAME TO cookies_old")
      try Support.execute(
        manifest.cookiesURL,
        "CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER)")
      try Support.execute(
        manifest.cookiesURL,
        "INSERT INTO cookies SELECT NULL, name, encrypted_value, path, expires_utc FROM cookies_old WHERE name = 'theme'")
      let (cookies, summary) = try readAll(manifest)
      #expect(cookies.isEmpty)
      #expect(summary.skippedMalformed == 1)
      #expect(summary.scanned == 1)
    }
  }

  @Test func anUnencryptedValueColumnIsUsedWhenThereIsNoEncryptedValue() throws {
    try Support.withProfile { manifest in
      try Support.execute(
        manifest.cookiesURL,
        "UPDATE cookies SET encrypted_value = x'', value = 'plain-fixture-value' WHERE name = 'theme'")
      let (cookies, summary) = try readAll(manifest)
      let theme = try #require(cookies.first { $0.name == "theme" })
      #expect(Support.text(theme.value) == "plain-fixture-value")
      #expect(summary.skippedUndecryptable == 0)
    }
  }

  // MARK: - Batches

  @Test func deliversInBatchesOf500() throws {
    #expect(CookieReader.batchSize == 500)
    try Support.withProfile { manifest in
      try Support.multiplyRows(manifest.cookiesURL, table: "cookies", times: 8)
      var sizes: [Int] = []
      let summary = try CookieReader(now: { Support.fixtureNow }).read(
        cookiesDatabase: manifest.cookiesURL, keyProvider: Support.provider()
      ) { sizes.append($0.count) }
      #expect(sizes == [500, 12])
      #expect(summary.scanned == 768)
      #expect(summary.delivered == 512)
      #expect(summary.skippedSession == 256)
    }
  }

  @Test func aThrowingBatchHandlerStopsTheRun() throws {
    try Support.withProfile { manifest in
      struct Stop: Error {}
      var calls = 0
      #expect(throws: Stop.self) {
        try CookieReader(now: { Support.fixtureNow }).read(
          cookiesDatabase: manifest.cookiesURL, keyProvider: Support.provider()
        ) { _ in
          calls += 1
          throw Stop()
        }
      }
      #expect(calls == 1)
    }
  }

  // MARK: - Key handling

  @Test func readsThePasswordOncePerRun() throws {
    try Support.withProfile { manifest in
      let provider = CountingProvider(Support.provider())
      try Support.multiplyRows(manifest.cookiesURL, table: "cookies", times: 8)
      _ = try CookieReader(now: { Support.fixtureNow }).read(cookiesDatabase: manifest.cookiesURL, keyProvider: provider) { _ in }
      #expect(provider.callCount == 1)
    }
  }

  @Test func oneKeyServesBothReadersInARun() throws {
    try Support.withProfile { manifest in
      let provider = CountingProvider(Support.provider())
      let (cookies, logins) = try ChromiumDecryptor.withDecryptor(provider: provider) { decryptor in
        var cookies = 0
        var logins = 0
        _ = try CookieReader(now: { Support.fixtureNow }).read(cookiesDatabase: manifest.cookiesURL, decryptor: decryptor) {
          cookies += $0.count
        }
        _ = try LoginReader().read(loginDatabase: manifest.loginDataURL, decryptor: decryptor) { logins += $0.count }
        return (cookies, logins)
      }
      #expect(cookies == 2)
      #expect(logins == 3)
      #expect(provider.callCount == 1)
    }
  }

  @Test func aKeyProviderFailureStopsBeforeAnyRow() throws {
    try Support.withProfile { manifest in
      var delivered = 0
      #expect(throws: SafeStorageError.accessDenied) {
        try CookieReader(now: { Support.fixtureNow }).read(
          cookiesDatabase: manifest.cookiesURL, keyProvider: FakeSafeStorageKeyProvider(failure: .accessDenied)
        ) { delivered += $0.count }
      }
      #expect(delivered == 0)
    }
  }

  // MARK: - Secrets

  @Test func logsAndDescriptionsContainNoSecrets() throws {
    try Support.withProfile { manifest in
      let collector = LogCollector()
      let good = try readAll(manifest, log: collector.sink)
      _ = try readAll(manifest, password: "not-the-fixture-password", log: collector.sink)
      #expect(!collector.all.isEmpty)

      var forbidden = manifest.cookies.flatMap { [$0.value, $0.hostKey, $0.path] }.filter { $0.count > 2 }
      forbidden += [FakeChromiumProfile.safeStoragePassword, "example", "fixture"]
      forbidden += [manifest.derivedKey.map { String($0, radix: 16) }.joined(), Data(manifest.derivedKey).base64EncodedString()]
      for line in collector.all {
        for secret in forbidden { #expect(!line.contains(secret), "a log line contained a secret") }
      }

      let rendered = [String(describing: good.cookies), String(reflecting: good.cookies), "\(good.summary)"].joined()
      #expect(!rendered.contains("fixture-session-value"))
      #expect(!rendered.contains("dark"))
    }
  }
}
