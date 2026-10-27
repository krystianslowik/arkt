import Foundation
import Security

// MARK: - Errors

/// Why the Safe Storage password could not be read. Each case maps one family of Keychain outcomes.
public enum SafeStorageError: Error, Equatable, Sendable {
  /// The user, or the item's access control, refused access (`errSecAuthFailed`).
  case accessDenied
  /// The user dismissed the Keychain prompt (`errSecUserCanceled`, -128).
  case userCanceled
  /// The browser's Safe Storage item does not exist (`errSecItemNotFound`).
  case itemNotFound
  /// A prompt was needed but the session cannot show one (`errSecInteractionNotAllowed`).
  case interactionNotAllowed
  /// The item exists but carries no password data.
  case malformedItem
  /// Any other Keychain status.
  case other(OSStatus)

  /// Maps a Security framework status to a typed error. `errSecSuccess` is not an error and maps to `.other`.
  init(status: OSStatus) {
    switch status {
    case errSecAuthFailed: self = .accessDenied
    case errSecUserCanceled: self = .userCanceled
    case errSecItemNotFound: self = .itemNotFound
    case errSecInteractionNotAllowed: self = .interactionNotAllowed
    default: self = .other(status)
    }
  }
}

// MARK: - Protocol

/// Supplies the Chromium "Safe Storage" password, the secret the v10 value key is derived from.
///
/// The password is lent to `body` for the duration of the call and never returned, so an implementation can
/// drop it as soon as `body` finishes. Reading may block on a Keychain prompt: call from a background context,
/// never from the main actor.
public protocol SafeStorageKeyProvider: Sendable {
  func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R
}

// MARK: - Keychain implementation

/// Reads the browser's generic password item with `SecItemCopyMatching`, only when `withPassword` is called.
/// Nothing is cached in memory between calls or written to disk; the byte buffer is zeroed after use.
public struct KeychainSafeStorageKeyProvider: SafeStorageKeyProvider {
  public let service: String
  public let account: String

  /// Defaults to the Arc item: service "Arc Safe Storage", account "Arc".
  public init(service: String = "Arc Safe Storage", account: String = "Arc") {
    self.service = service
    self.account = account
  }

  func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
  }

  public func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query() as CFDictionary, &item)
    guard status == errSecSuccess else { throw SafeStorageError(status: status) }
    guard let data = item as? Data else { throw SafeStorageError.malformedItem }
    var bytes = [UInt8](data)
    defer { bytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    return try body(bytes)
  }
}
