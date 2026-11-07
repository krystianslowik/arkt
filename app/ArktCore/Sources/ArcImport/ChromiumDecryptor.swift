import CommonCrypto
import CryptoKit
import Foundation

/// Why a Chromium encrypted value could not be decrypted. Bad data is always one of these, never a crash.
public enum ChromiumDecryptError: Error, Equatable, Sendable {
  /// No `vNN` prefix: empty, too short, or an unencrypted value.
  case unrecognizedFormat
  /// A `vNN` prefix other than `v10`. macOS Chromium only writes `v10`; `v11` is the Linux keyring tag.
  case unsupportedVersion(String)
  /// No ciphertext after the prefix, or its length is not a whole number of AES blocks.
  case truncated
  /// The padding is invalid: the key is wrong or the data is corrupt.
  case badPadding
  /// A version-24 cookie plaintext is shorter than the 32-byte host hash.
  case missingHostHash
  /// The leading SHA-256 does not match the cookie's `host_key`.
  case hostHashMismatch
  /// An unexpected CommonCrypto status.
  case cipher(Int32)
  /// PBKDF2 failed with this CommonCrypto status.
  case keyDerivation(Int32)
}

/// Decrypts Chromium macOS "v10" values: AES-128-CBC with an IV of 16 spaces and PKCS7 padding, under a key
/// derived with PBKDF2-HMAC-SHA1 (salt `saltysalt`, 1003 rounds, 16 bytes) from the Safe Storage password.
///
/// Matches Chromium's `components/os_crypt` keychain provider, which tags values only with `v10`.
/// The key lives only inside `withDecryptor` and is zeroed when the decryptor is destroyed.
public struct ChromiumDecryptor: ~Copyable {
  public static let salt = Array("saltysalt".utf8)
  public static let iterations: UInt32 = 1003
  public static let keyLength = 16
  public static let prefix = Array("v10".utf8)
  /// Cookies `meta` version from which each plaintext value starts with SHA-256 of `host_key`.
  public static let hostHashMetaVersion = 24
  static let hostHashLength = 32

  /// Manually owned so `deinit` can wipe it: an array may share storage with copies that outlive the decryptor.
  private let key: UnsafeMutableBufferPointer<UInt8>

  init(key bytes: [UInt8]) {
    key = .allocate(capacity: bytes.count)
    _ = key.initialize(from: bytes)
  }

  deinit {
    _ = memset_s(key.baseAddress, key.count, 0, key.count)
    key.deallocate()
  }

  // MARK: - Session

  /// Reads the password from `provider`, derives the key, runs `body`, then zeros the password and key.
  public static func withDecryptor<R>(
    provider: some SafeStorageKeyProvider, _ body: (borrowing ChromiumDecryptor) throws -> R
  ) throws -> R {
    var derived = try provider.withPassword { password in try deriveKey(password: password) }
    defer { derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    let decryptor = ChromiumDecryptor(key: derived)
    return try body(decryptor)
  }

  /// PBKDF2-HMAC-SHA1 with the fixed Chromium parameters.
  public static func deriveKey(password: [UInt8]) throws(ChromiumDecryptError) -> [UInt8] {
    var derived = [UInt8](repeating: 0, count: keyLength)
    let status = password.withUnsafeBufferPointer { passwordBuffer in
      passwordBuffer.withMemoryRebound(to: CChar.self) { chars in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), chars.baseAddress, chars.count, salt, salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), iterations, &derived, derived.count
        )
      }
    }
    guard status == kCCSuccess else { throw .keyDerivation(status) }
    return derived
  }

  // MARK: - Decrypt

  /// Decrypts a `v10` blob (a login password, or a cookie value before meta version 24).
  /// The returned plaintext is the caller's to zero when done.
  public func decrypt(_ blob: [UInt8]) throws(ChromiumDecryptError) -> [UInt8] {
    guard blob.starts(with: Self.prefix) else {
      if blob.count >= 3, blob[0] == UInt8(ascii: "v"), blob[1].isASCIIDigit, blob[2].isASCIIDigit {
        throw .unsupportedVersion(String(decoding: blob.prefix(3), as: UTF8.self))
      }
      throw .unrecognizedFormat
    }
    let cipherText = Array(blob.dropFirst(Self.prefix.count))
    guard !cipherText.isEmpty, cipherText.count % kCCBlockSizeAES128 == 0 else { throw .truncated }

    let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
    var out = [UInt8](repeating: 0, count: cipherText.count)
    defer { out.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    var written = 0
    let status = CCCrypt(
      CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(0),
      key.baseAddress, key.count, iv, cipherText, cipherText.count, &out, out.count, &written
    )
    switch status {
    case Int32(kCCSuccess):
      // Padding is checked here, strictly, rather than left to CommonCrypto's lenient PKCS7 option.
      guard written == out.count, let pad = out.last.map(Int.init), (1...kCCBlockSizeAES128).contains(pad),
        out.suffix(pad).allSatisfy({ Int($0) == pad })
      else { throw .badPadding }
      return Array(out.dropLast(pad))
    case Int32(kCCDecodeError): throw .badPadding
    case Int32(kCCAlignmentError): throw .truncated
    default: throw .cipher(status)
    }
  }

  /// Decrypts a cookie value. From `metaVersion` 24 the plaintext starts with SHA-256 of `hostKey`, which is
  /// verified and stripped; earlier versions have no prefix.
  public func decryptCookie(
    _ blob: [UInt8], hostKey: String, metaVersion: Int
  ) throws(ChromiumDecryptError) -> [UInt8] {
    var plain = try decrypt(blob)
    guard metaVersion >= Self.hostHashMetaVersion else { return plain }
    defer { plain.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    guard plain.count >= Self.hostHashLength else { throw .missingHostHash }
    guard plain.prefix(Self.hostHashLength).elementsEqual(SHA256.hash(data: Data(hostKey.utf8))) else {
      throw .hostHashMismatch
    }
    return Array(plain.dropFirst(Self.hostHashLength))
  }
}

private extension UInt8 {
  var isASCIIDigit: Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) }
}
