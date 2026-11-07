import ArcImport
import CoreTestSupport
import Foundation
import Testing

struct LoginReaderTests {
  typealias Support = ReaderTestSupport

  private func readAll(
    _ manifest: FixtureManifest, password: String = FakeChromiumProfile.safeStoragePassword,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) throws -> (logins: [ArcLogin], summary: LoginReadSummary) {
    var logins: [ArcLogin] = []
    let summary = try LoginReader(log: log).read(
      loginDatabase: manifest.loginDataURL, keyProvider: Support.provider(password: password)
    ) { logins += $0 }
    return (logins, summary)
  }

  // MARK: - Fixtures

  @Test func readsTheFixtureLogins() throws {
    try Support.withProfile { manifest in
      let (logins, summary) = try readAll(manifest)
      #expect(logins.count == manifest.logins.count)
      for expected in manifest.logins {
        let login = try #require(logins.first { $0.originURL == expected.originURL })
        #expect(login.signonRealm == expected.signonRealm)
        #expect(login.username == expected.username)
        #expect(Support.text(login.password) == expected.password)
        #expect(login.actionURL == expected.originURL)
        #expect(login.blacklistedByUser == false)
        #expect(login.dateCreated != nil)
        #expect(login.dateLastUsed == ChromiumTime.date(fromWebKit: ChromiumTime.webKit(fromUnixSeconds: 1_704_067_200 + 1_000)))
      }
      #expect(summary.scanned == manifest.logins.count)
      #expect(summary.delivered == manifest.logins.count)
      #expect(summary.skippedBlacklisted == 0)
      #expect(summary.skippedUndecryptable == 0)
      #expect(summary.skippedMalformed == 0)
    }
  }

  @Test(arguments: [FakeChromiumProfile.SchemaDrift.extraColumn, .missingOptionalColumn])
  func toleratesSchemaDrift(drift: FakeChromiumProfile.SchemaDrift) throws {
    try Support.withProfile(.init(drift: drift)) { manifest in
      let (logins, summary) = try readAll(manifest)
      #expect(logins.count == manifest.logins.count)
      #expect(summary.skippedMalformed == 0)
    }
  }

  @Test func fallsBackToDefaultsForMissingOptionalColumns() throws {
    try Support.withProfile { manifest in
      for column in ["action_url", "username_value", "date_created", "date_last_used", "blacklisted_by_user"] {
        try Support.execute(manifest.loginDataURL, "ALTER TABLE logins DROP COLUMN \(column)")
      }
      let (logins, summary) = try readAll(manifest)
      #expect(logins.count == 3)
      #expect(summary.skippedBlacklisted == 0)
      for login in logins {
        #expect(login.actionURL == nil)
        #expect(login.username == "")
        #expect(login.dateCreated == nil)
        #expect(login.dateLastUsed == nil)
      }
    }
  }

  @Test func aMissingRequiredColumnIsAFileLevelError() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.loginDataURL, "ALTER TABLE logins DROP COLUMN password_value")
      #expect(throws: ChromiumReadError.missingColumns(table: "logins", columns: ["password_value"])) {
        try readAll(manifest)
      }
    }
  }

  // MARK: - Skips

  @Test func blacklistedRowsAreSkippedAndCounted() throws {
    try Support.withProfile { manifest in
      try Support.execute(
        manifest.loginDataURL,
        "UPDATE logins SET blacklisted_by_user = 1, password_value = x'' WHERE signon_realm = 'https://example.org/'")
      let (logins, summary) = try readAll(manifest)
      #expect(logins.count == 2)
      #expect(!logins.contains { $0.signonRealm == "https://example.org/" })
      #expect(summary.skippedBlacklisted == 1)
      #expect(summary.skippedUndecryptable == 0)
      #expect(summary.scanned == 3)
    }
  }

  @Test func aWrongKeyFailsEveryRowAndCountsThem() throws {
    try Support.withProfile { manifest in
      let (logins, summary) = try readAll(manifest, password: "not-the-fixture-password")
      #expect(logins.isEmpty)
      #expect(summary.skippedUndecryptable == manifest.logins.count)
      #expect(summary.delivered == 0)
    }
  }

  @Test func aBadRowIsSkippedAndCountedNotFatal() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.loginDataURL, "UPDATE logins SET password_value = x'0102' WHERE username_value = 'second-user'")
      try Support.execute(manifest.loginDataURL, "UPDATE logins SET password_value = x'' WHERE username_value = ''")
      let (logins, summary) = try readAll(manifest)
      #expect(logins.count == 1)
      #expect(summary.skippedUndecryptable == 2)
    }
  }

  @Test func aRowWithoutAnOriginIsMalformed() throws {
    try Support.withProfile { manifest in
      try Support.execute(manifest.loginDataURL, "ALTER TABLE logins RENAME TO logins_old")
      try Support.execute(
        manifest.loginDataURL, "CREATE TABLE logins (origin_url TEXT, signon_realm TEXT, password_value BLOB)")
      try Support.execute(
        manifest.loginDataURL, "INSERT INTO logins SELECT NULL, signon_realm, password_value FROM logins_old")
      let (logins, summary) = try readAll(manifest)
      #expect(logins.isEmpty)
      #expect(summary.skippedMalformed == 3)
    }
  }

  // MARK: - Batches and secrets

  @Test func deliversInBatchesOf500() throws {
    #expect(LoginReader.batchSize == 500)
    try Support.withProfile { manifest in
      try Support.multiplyRows(manifest.loginDataURL, table: "logins", times: 8)
      var sizes: [Int] = []
      let summary = try LoginReader().read(loginDatabase: manifest.loginDataURL, keyProvider: Support.provider()) {
        sizes.append($0.count)
      }
      #expect(sizes == [500, 268])
      #expect(summary.delivered == 768)
    }
  }

  @Test func readsThePasswordOncePerRun() throws {
    try Support.withProfile { manifest in
      let provider = CountingProvider(Support.provider())
      try Support.multiplyRows(manifest.loginDataURL, table: "logins", times: 8)
      _ = try LoginReader().read(loginDatabase: manifest.loginDataURL, keyProvider: provider) { _ in }
      #expect(provider.callCount == 1)
    }
  }

  @Test func logsAndDescriptionsContainNoSecrets() throws {
    try Support.withProfile { manifest in
      let collector = LogCollector()
      let good = try readAll(manifest, log: collector.sink)
      _ = try readAll(manifest, password: "not-the-fixture-password", log: collector.sink)
      #expect(!collector.all.isEmpty)

      var forbidden = manifest.logins.flatMap { [$0.password, $0.username, $0.originURL, $0.signonRealm] }.filter { $0.count > 2 }
      forbidden += [FakeChromiumProfile.safeStoragePassword, "example", "fixture"]
      for line in collector.all {
        for secret in forbidden { #expect(!line.contains(secret), "a log line contained a secret") }
      }

      let rendered = [String(describing: good.logins.map(\.password)), String(reflecting: good.logins.map(\.password))].joined()
      for login in manifest.logins { #expect(!rendered.contains(login.password)) }
    }
  }
}
