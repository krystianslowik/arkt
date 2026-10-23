import CryptoKit
import Foundation

/// Arkt ids for Arc ids, stable across imports: the same Arc id always maps to the same UUID. Used for archived item
/// ids and Space ids, so re-importing the same Arc data finds what an earlier import created.
public enum StableID {
  /// Arc's UUID when `id` is one (any letter case); otherwise a version 8 UUID derived from the SHA-256 of `id`.
  public static func uuid(forArcID id: String) -> UUID {
    if let uuid = UUID(uuidString: id) { return uuid }
    var bytes = Array(SHA256.hash(data: Data(id.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x80  // version 8: custom
    bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}
