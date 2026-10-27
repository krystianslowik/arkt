import CommonCrypto
import Foundation

/// The macOS Chromium "v10" value encryption: PBKDF2-HMAC-SHA1 (salt `saltysalt`, 1003 rounds, 16-byte key) then
/// AES-128-CBC with an IV of 16 spaces and PKCS7 padding, behind a `v10` prefix. Fixture use only.
public enum ChromiumV10 {
  public static let salt = "saltysalt"
  public static let iterations: UInt32 = 1003
  public static let keyLength = 16
  public static let prefix = Array("v10".utf8)

  public enum Failure: Error { case keyDerivation(Int32), cipher(Int32) }

  public static func deriveKey(password: String) throws -> [UInt8] {
    var key = [UInt8](repeating: 0, count: keyLength)
    let saltBytes = Array(salt.utf8)
    let passwordBytes = Array(password.utf8)
    let status = CCKeyDerivationPBKDF(
      CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
      saltBytes, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), iterations, &key, key.count
    )
    guard status == kCCSuccess else { throw Failure.keyDerivation(status) }
    return key
  }

  public static func encrypt(_ plaintext: [UInt8], key: [UInt8]) throws -> [UInt8] {
    let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
    var out = [UInt8](repeating: 0, count: plaintext.count + kCCBlockSizeAES128)
    var written = 0
    let status = CCCrypt(
      CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
      key, key.count, iv, plaintext, plaintext.count, &out, out.count, &written
    )
    guard status == kCCSuccess else { throw Failure.cipher(status) }
    return prefix + out.prefix(written)
  }
}
