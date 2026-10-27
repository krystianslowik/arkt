import CommonCrypto
import CoreTestSupport
import CryptoKit
import Foundation
import SQLite3
import Testing

struct FakeChromiumProfileTests {
  // MARK: - Helpers

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-chromium-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Runs `sql` read-only and returns each row as text/blob-free strings; blobs come back as lowercase hex.
  private func rows(_ url: URL, _ sql: String) throws -> [[String]] {
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TestFailure(message: String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    var result: [[String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      result.append((0..<sqlite3_column_count(statement)).map { column in
        if sqlite3_column_type(statement, column) == SQLITE_BLOB {
          let count = Int(sqlite3_column_bytes(statement, column))
          let bytes = sqlite3_column_blob(statement, column).map { Array(UnsafeRawBufferPointer(start: $0, count: count)) } ?? []
          return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
      })
    }
    return result
  }

  private func blob(_ url: URL, _ sql: String) throws -> [UInt8] {
    let hex = try #require(try rows(url, sql).first?.first)
    return stride(from: 0, to: hex.count, by: 2).map {
      UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16) ?? 0
    }
  }

  private func columnNames(_ url: URL, table: String) throws -> Set<String> {
    Set(try rows(url, "SELECT name FROM pragma_table_info('\(table)')").map { $0[0] })
  }

  /// A minimal v10 decrypt that does not share code with the generator: fixed derivation parameters, AES-128-CBC.
  private func decryptV10(_ data: [UInt8], password: String) throws -> [UInt8] {
    #expect(Array(data.prefix(3)) == Array("v10".utf8))
    var key = [UInt8](repeating: 0, count: 16)
    let pw = Array(password.utf8)
    let salt = Array("saltysalt".utf8)
    let derived = CCKeyDerivationPBKDF(
      CCPBKDFAlgorithm(kCCPBKDF2), pw.map { CChar(bitPattern: $0) }, pw.count, salt, salt.count,
      CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16
    )
    #expect(derived == kCCSuccess)
    let body = Array(data.dropFirst(3))
    var out = [UInt8](repeating: 0, count: body.count + 16)
    var written = 0
    let status = CCCrypt(
      CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding), key, 16,
      [UInt8](repeating: 0x20, count: 16), body, body.count, &out, out.count, &written
    )
    #expect(status == kCCSuccess)
    return Array(out.prefix(written))
  }

  private struct TestFailure: Error { let message: String }

  // MARK: - History

  @Test func historyHasVersion70SchemaAndExpectedCounts() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    #expect(try rows(manifest.historyURL, "SELECT value FROM meta WHERE key='version'") == [["70"]])
    #expect(try rows(manifest.historyURL, "SELECT count(*) FROM urls") == [["\(manifest.history.count)"]])
    #expect(try rows(manifest.historyURL, "SELECT count(*) FROM visits") == [["\(manifest.visitCount)"]])
    #expect(manifest.history.count == 3)
    #expect(manifest.visitCount == 5)

    let first = try #require(manifest.history.first)
    let row = try #require(try rows(manifest.historyURL, "SELECT url, title, visit_count, last_visit_time FROM urls WHERE id=1").first)
    #expect(row == [first.url, first.title, "\(first.visitCount)", "\(first.lastVisitWebKitTime)"])
  }

  @Test func historyUsesWebKitTimeAndTransitionBitmasks() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    let times = try rows(manifest.historyURL, "SELECT visit_time FROM visits WHERE url=1 ORDER BY id").map { Int64($0[0]) ?? 0 }
    #expect(times == manifest.history[0].visits.map(\.webkitTime))
    #expect(manifest.history[0].visits[0].date == Date(timeIntervalSince1970: 1_704_067_260))
    #expect(times.allSatisfy { $0 > 13_000_000_000_000_000 })

    let transitions = try rows(manifest.historyURL, "SELECT transition FROM visits ORDER BY id").map { Int32($0[0]) ?? -1 }
    #expect(transitions.map { $0 & 0xFF } == [1, 0, 8, 0, 1])
    #expect(transitions.allSatisfy { $0 & 0x3000_0000 == 0x3000_0000 })
    #expect(transitions[0] & 0x0200_0000 != 0)
  }

  // MARK: - Login Data

  @Test func loginsRoundTripThroughV10() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    #expect(try rows(manifest.loginDataURL, "SELECT value FROM meta WHERE key='version'") == [["43"]])
    #expect(try rows(manifest.loginDataURL, "SELECT count(*) FROM logins") == [["3"]])
    for login in manifest.logins {
      let encrypted = try blob(manifest.loginDataURL, "SELECT password_value FROM logins WHERE signon_realm='\(login.signonRealm)'")
      #expect(Array(encrypted.prefix(3)) == Array("v10".utf8))
      #expect((encrypted.count - 3) % 16 == 0)
      let plain = try decryptV10(encrypted, password: "fixture-password")
      #expect(String(decoding: plain, as: UTF8.self) == login.password)
    }
    #expect(manifest.derivedKey.count == 16)
  }

  @Test func keyDerivationMatchesTheIndependentDecrypt() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)
    let encrypted = try ChromiumV10.encrypt(Array("hello".utf8), key: manifest.derivedKey)
    #expect(String(decoding: try decryptV10(encrypted, password: manifest.safeStoragePassword), as: UTF8.self) == "hello")
  }

  // MARK: - Cookies

  @Test func cookiesV24PrefixValueWithHostHash() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    #expect(manifest.cookiesMetaVersion == 24)
    #expect(try rows(manifest.cookiesURL, "SELECT value FROM meta WHERE key='version'") == [["24"]])
    #expect(try rows(manifest.cookiesURL, "SELECT count(*) FROM cookies") == [["3"]])
    for cookie in manifest.cookies {
      let encrypted = try blob(manifest.cookiesURL, "SELECT encrypted_value FROM cookies WHERE name='\(cookie.name)'")
      let plain = try decryptV10(encrypted, password: "fixture-password")
      let hash = Array(SHA256.hash(data: Data(cookie.hostKey.utf8)))
      #expect(Array(plain.prefix(32)) == hash)
      #expect(String(decoding: plain.dropFirst(32), as: UTF8.self) == cookie.value)
    }
  }

  @Test func cookiesV23HaveNoPrefix() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(cookieFormat: .v23))

    #expect(manifest.cookiesMetaVersion == 23)
    #expect(manifest.cookieValuesHaveHostPrefix == false)
    #expect(try rows(manifest.cookiesURL, "SELECT value FROM meta WHERE key='version'") == [["23"]])
    for cookie in manifest.cookies {
      let encrypted = try blob(manifest.cookiesURL, "SELECT encrypted_value FROM cookies WHERE name='\(cookie.name)'")
      #expect(String(decoding: try decryptV10(encrypted, password: "fixture-password"), as: UTF8.self) == cookie.value)
    }
  }

  // MARK: - Bookmarks

  @Test func bookmarksHaveThreeRootsAndEntries() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifest.bookmarksURL)) as? [String: Any])
    let roots = try #require(json["roots"] as? [String: Any])
    #expect(Set(roots.keys) == ["bookmark_bar", "other", "synced"])
    let bar = try #require(roots["bookmark_bar"] as? [String: Any])
    let children = try #require(bar["children"] as? [[String: Any]])
    #expect(children.count == 3)
    let first = try #require(children.first)
    #expect(first["url"] as? String == "https://example.com/")
    #expect(first["guid"] as? String == manifest.bookmarks[0].guid)
    #expect(first["date_added"] as? String == String(manifest.bookmarks[0].dateAddedWebKitTime))
    #expect(manifest.bookmarkCount == 5)
  }

  @Test func emptyBookmarksVariantKeepsRoots() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(bookmarks: .empty))

    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifest.bookmarksURL)) as? [String: Any])
    let roots = try #require(json["roots"] as? [String: [String: Any]])
    #expect(Set(roots.keys) == ["bookmark_bar", "other", "synced"])
    #expect(roots.values.allSatisfy { ($0["children"] as? [Any])?.isEmpty == true })
    #expect(manifest.bookmarkCount == 0)
  }

  // MARK: - Preferences

  @Test func preferencesListWebStoreUnpackedAndBuiltInExtensions() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)

    for url in [manifest.preferencesURL, manifest.securePreferencesURL] {
      let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      let settings = try #require((json["extensions"] as? [String: Any])?["settings"] as? [String: [String: Any]])
      #expect(settings.count == 3)
      for entry in manifest.extensions {
        let item = try #require(settings[entry.id])
        switch entry.kind {
        case .webStore: #expect(item["from_webstore"] as? Bool == true && item["location"] as? Int == 1)
        case .unpacked: #expect(item["from_webstore"] as? Bool == false && item["location"] as? Int == 4)
        case .builtIn: #expect(item["location"] as? Int == 5)
        }
        #expect((item["manifest"] as? [String: Any])?["name"] as? String == entry.name)
      }
    }
  }

  // MARK: - Schema drift

  @Test func extraColumnVariantAddsAnUnknownColumn() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(drift: .extraColumn))

    #expect(manifest.extraColumns == ["urls.fixture_extra", "logins.fixture_extra", "cookies.fixture_extra"])
    #expect(try columnNames(manifest.historyURL, table: "urls").contains("fixture_extra"))
    #expect(try columnNames(manifest.loginDataURL, table: "logins").contains("fixture_extra"))
    #expect(try columnNames(manifest.cookiesURL, table: "cookies").contains("fixture_extra"))
    #expect(try rows(manifest.loginDataURL, "SELECT count(*) FROM logins") == [["3"]])
  }

  @Test func missingOptionalColumnVariantDropsColumns() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(drift: .missingOptionalColumn))

    #expect(manifest.missingColumns == ["visits.visit_duration", "logins.date_password_modified", "cookies.source_type"])
    #expect(try !columnNames(manifest.historyURL, table: "visits").contains("visit_duration"))
    #expect(try !columnNames(manifest.loginDataURL, table: "logins").contains("date_password_modified"))
    #expect(try !columnNames(manifest.cookiesURL, table: "cookies").contains("source_type"))
    #expect(try rows(manifest.historyURL, "SELECT count(*) FROM visits") == [["5"]])
  }

  @Test func plainProfileReportsNoDrift() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)
    #expect(manifest.extraColumns.isEmpty && manifest.missingColumns.isEmpty)
  }

  @Test func makingTwiceInTheSameDirectoryReplacesFiles() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try FakeChromiumProfile.make(at: dir)
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(cookieFormat: .v23))
    #expect(try rows(manifest.cookiesURL, "SELECT count(*) FROM cookies") == [["3"]])
  }
}
