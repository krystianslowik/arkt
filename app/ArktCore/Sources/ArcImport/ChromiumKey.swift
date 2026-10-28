import Foundation

/// The derived Safe Storage key, held between reads so a caller can decrypt one window of rows at a time and still ask
/// the Keychain only once. The bytes live in a `SecretBytes` (zeroed on `wipe` and on deinit); each `withDecryptor` call
/// builds a short-lived decryptor from a temporary copy that is zeroed before the call returns.
public struct ChromiumKey: Sendable {
  private let secret: SecretBytes

  /// Reads the password from `provider` once and derives the key. The password is zeroed by the provider.
  public init(provider: some SafeStorageKeyProvider) throws {
    var derived = try provider.withPassword { password in try ChromiumDecryptor.deriveKey(password: password) }
    secret = SecretBytes(taking: derived)
    derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
  }

  public func withDecryptor<R: Sendable>(_ body: (borrowing ChromiumDecryptor) throws -> R) rethrows -> R {
    var bytes = secret.withBytes { Array($0) }
    defer { bytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    let decryptor = ChromiumDecryptor(key: bytes)
    return try body(decryptor)
  }

  /// Zeroes the key. Later `withDecryptor` calls decrypt with a zero key and fail.
  public func wipe() { secret.wipe() }
}
