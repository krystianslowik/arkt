import ArcImport
import CoreTestSupport
import CryptoKit
import Foundation
import SQLite3
import Testing

struct ChromiumDecryptorTests {
  private struct TestFailure: Error { let message: String }

  // MARK: - Helpers

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("decryptor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func blobs(_ url: URL, _ sql: String) throws -> [[UInt8]] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      throw TestFailure(message: "open failed")
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TestFailure(message: String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    var result: [[UInt8]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let count = Int(sqlite3_column_bytes(statement, 0))
      result.append(sqlite3_column_blob(statement, 0).map { Array(UnsafeRawBufferPointer(start: $0, count: count)) } ?? [])
    }
    return result
  }

  @discardableResult
  private func withDecryptor<R>(
    password: String = FakeChromiumProfile.safeStoragePassword, _ body: (borrowing ChromiumDecryptor) throws -> R
  ) throws -> R {
    try ChromiumDecryptor.withDecryptor(provider: FakeSafeStorageKeyProvider(password: password), body)
  }

  // MARK: - Key derivation

  @Test func derivedKeyMatchesFixtureGenerator() throws {
    let key = try ChromiumDecryptor.deriveKey(password: Array(FakeChromiumProfile.safeStoragePassword.utf8))
    #expect(key == (try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)))
    #expect(key.count == 16)
  }

  // MARK: - Round trips

  @Test func loginPasswordsRoundTrip() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)
    let encrypted = try blobs(manifest.loginDataURL, "SELECT password_value FROM logins ORDER BY rowid")
    #expect(encrypted.count == manifest.logins.count)
    try withDecryptor { decryptor in
      for (blob, login) in zip(encrypted, manifest.logins) {
        let plain = try decryptor.decrypt(blob)
        #expect(String(decoding: plain, as: UTF8.self) == login.password)
      }
    }
  }

  @Test func cookiesV24StripAndVerifyHostHash() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(cookieFormat: .v24))
    #expect(manifest.cookiesMetaVersion == 24)
    try withDecryptor { decryptor in
      for cookie in manifest.cookies {
        let sql = "SELECT encrypted_value FROM cookies WHERE name='\(cookie.name)'"
        let blob = try #require(try blobs(manifest.cookiesURL, sql).first)
        let plain = try decryptor.decryptCookie(blob, hostKey: cookie.hostKey, metaVersion: manifest.cookiesMetaVersion)
        #expect(String(decoding: plain, as: UTF8.self) == cookie.value)
      }
    }
  }

  @Test func cookiesV23HaveNoHostHash() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(cookieFormat: .v23))
    #expect(manifest.cookiesMetaVersion == 23)
    try withDecryptor { decryptor in
      for cookie in manifest.cookies {
        let sql = "SELECT encrypted_value FROM cookies WHERE name='\(cookie.name)'"
        let blob = try #require(try blobs(manifest.cookiesURL, sql).first)
        let plain = try decryptor.decryptCookie(blob, hostKey: cookie.hostKey, metaVersion: manifest.cookiesMetaVersion)
        #expect(String(decoding: plain, as: UTF8.self) == cookie.value)
      }
    }
  }

  @Test func v24CookieForAnotherHostIsRejected() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(cookieFormat: .v24))
    let cookie = try #require(manifest.cookies.first)
    let blob = try #require(try blobs(manifest.cookiesURL, "SELECT encrypted_value FROM cookies WHERE name='\(cookie.name)'").first)
    try withDecryptor { decryptor in
      #expect(throws: ChromiumDecryptError.hostHashMismatch) {
        try decryptor.decryptCookie(blob, hostKey: "other.example", metaVersion: 24)
      }
    }
  }

  @Test func v24PlaintextShorterThanHashIsRejected() throws {
    let key = try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)
    let blob = try ChromiumV10.encrypt(Array("short".utf8), key: key)
    try withDecryptor { decryptor in
      #expect(throws: ChromiumDecryptError.missingHostHash) {
        try decryptor.decryptCookie(blob, hostKey: "a.example", metaVersion: 24)
      }
    }
  }

  @Test func emptyAndMultiBlockValuesRoundTrip() throws {
    let key = try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)
    try withDecryptor { decryptor in
      for length in [0, 1, 15, 16, 17, 64, 4_097] {
        let plain = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        let blob = try ChromiumV10.encrypt(plain, key: key)
        #expect(try decryptor.decrypt(blob) == plain)
      }
    }
  }

  // MARK: - Bad data

  @Test func wrongKeyIsATypedError() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)
    let blob = try #require(try blobs(manifest.loginDataURL, "SELECT password_value FROM logins ORDER BY rowid").first)
    try withDecryptor(password: "not-the-password") { decryptor in
      #expect(throws: ChromiumDecryptError.badPadding) { try decryptor.decrypt(blob) }
    }
  }

  @Test func truncatedDataIsATypedError() throws {
    let key = try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)
    let blob = try ChromiumV10.encrypt(Array("a long enough secret value".utf8), key: key)
    try withDecryptor { decryptor in
      #expect(throws: ChromiumDecryptError.truncated) { try decryptor.decrypt(Array(blob.prefix(blob.count - 3))) }
      #expect(throws: ChromiumDecryptError.truncated) { try decryptor.decrypt(Array("v10".utf8)) }
      #expect(throws: ChromiumDecryptError.truncated) { try decryptor.decrypt(Array("v10".utf8) + [1, 2, 3]) }
      #expect(throws: ChromiumDecryptError.unrecognizedFormat) { try decryptor.decrypt([]) }
      #expect(throws: ChromiumDecryptError.unrecognizedFormat) { try decryptor.decrypt([0x76, 0x31]) }
    }
  }

  @Test func corruptedLastBlockIsATypedError() throws {
    let key = try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)
    var blob = try ChromiumV10.encrypt(Array("a long enough secret value".utf8), key: key)
    blob[blob.count - 1] ^= 0xFF
    blob[blob.count - 2] ^= 0xFF
    try withDecryptor { decryptor in
      #expect(throws: ChromiumDecryptError.self) { try decryptor.decrypt(blob) }
    }
  }

  @Test func unknownPrefixIsATypedError() throws {
    let key = try ChromiumV10.deriveKey(password: FakeChromiumProfile.safeStoragePassword)
    let encrypted = try ChromiumV10.encrypt(Array("value".utf8), key: key)
    let body = Array(encrypted.dropFirst(3))
    try withDecryptor { decryptor in
      // macOS Chromium only ever writes v10; v11 is the Linux keyring tag and must not be guessed at.
      #expect(throws: ChromiumDecryptError.unsupportedVersion("v11")) { try decryptor.decrypt(Array("v11".utf8) + body) }
      #expect(throws: ChromiumDecryptError.unsupportedVersion("v20")) { try decryptor.decrypt(Array("v20".utf8) + body) }
      #expect(throws: ChromiumDecryptError.unrecognizedFormat) { try decryptor.decrypt(Array("plain text value".utf8)) }
    }
  }

  // MARK: - Provider wiring

  @Test(arguments: [
    SafeStorageError.accessDenied, .userCanceled, .itemNotFound, .interactionNotAllowed, .malformedItem, .other(-1),
  ])
  func providerFailuresReachTheCallerUnchanged(error: SafeStorageError) {
    #expect(throws: error) {
      try ChromiumDecryptor.withDecryptor(provider: FakeSafeStorageKeyProvider(failure: error)) { _ in () }
    }
  }
}
