@testable import ArcImport
import CoreTestSupport
import Foundation
import Security
import Testing

struct SafeStorageKeyProviderTests {
  // MARK: - Status mapping

  @Test(arguments: [
    (errSecAuthFailed, SafeStorageError.accessDenied),
    (errSecUserCanceled, .userCanceled),
    (errSecItemNotFound, .itemNotFound),
    (errSecInteractionNotAllowed, .interactionNotAllowed),
    (errSecNotAvailable, .other(errSecNotAvailable)),
    (errSecParam, .other(errSecParam)),
  ])
  func statusMapsToTypedError(status: OSStatus, expected: SafeStorageError) {
    #expect(SafeStorageError(status: status) == expected)
  }

  @Test func userCanceledIsMinus128() {
    #expect(errSecUserCanceled == -128)
    #expect(SafeStorageError(status: -128) == .userCanceled)
  }

  // MARK: - Real provider (never queried here)

  @Test func realProviderTargetsArcItem() {
    let provider = KeychainSafeStorageKeyProvider()
    #expect(provider.service == "Arc Safe Storage")
    #expect(provider.account == "Arc")
  }

  @Test func realProviderQueryAsksForDataOnlyForOneItem() {
    let query = KeychainSafeStorageKeyProvider().query()
    #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(query[kSecAttrService as String] as? String == "Arc Safe Storage")
    #expect(query[kSecAttrAccount as String] as? String == "Arc")
    #expect(query[kSecReturnData as String] as? Bool == true)
    #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
  }

  // MARK: - Fake provider

  @Test func fakeProviderHandsOutPasswordBytes() throws {
    let provider = FakeSafeStorageKeyProvider(password: "pw")
    let seen = try provider.withPassword { Array($0) }
    #expect(seen == Array("pw".utf8))
  }

  @Test(arguments: [SafeStorageError.accessDenied, .userCanceled, .itemNotFound])
  func fakeProviderThrowsConfiguredFailure(error: SafeStorageError) {
    let provider = FakeSafeStorageKeyProvider(failure: error)
    #expect(throws: error) { try provider.withPassword { _ in () } }
  }

  @Test func bodyErrorsPropagateFromProvider() {
    struct Marker: Error {}
    #expect(throws: Marker.self) {
      try FakeSafeStorageKeyProvider(password: "pw").withPassword { _ in throw Marker() }
    }
  }
}

// MARK: - No shelling out

struct NoSecurityCLITests {
  /// Every Swift file under Sources/ArcImport, found relative to this test file.
  private func moduleSources() throws -> [(name: String, text: String)] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/ArcImport")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
      ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
    }
  }

  @Test func moduleNeverShellsOutToSecurity() throws {
    let sources = try moduleSources()
    #expect(sources.contains { $0.name == "ChromiumDecryptor.swift" })
    let banned = ["/usr/bin/security", "find-generic-password", "dump-keychain", "NSTask", "Process(", "posix_spawn", "popen(", "execv", "system("]
    for source in sources {
      // Comments may mention the CLI; code may not.
      let code = source.text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
      for line in code {
        for token in banned {
          #expect(!line.contains(token), "\(source.name) contains \(token)")
        }
      }
    }
  }
}
