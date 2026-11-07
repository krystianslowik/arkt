import Foundation
import Synchronization

/// Plaintext secret bytes (a decrypted cookie value or login password) that are zeroed when the object is destroyed.
///
/// The bytes live in storage the type owns alone: they are lent to a closure as a raw buffer and never handed out as
/// an array, so no copy outlives this object except one the caller makes on purpose (`utf8String`). Printing or
/// reflecting a value shows only its length.
public final class SecretBytes: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let storage: Mutex<[UInt8]>
  public let count: Int

  /// Takes a copy of `bytes` into private storage and zeroes the array it was given, so the plaintext is not left
  /// behind in the caller's buffer.
  public init(taking bytes: consuming [UInt8]) {
    var source = bytes
    count = source.count
    let own = [UInt8](unsafeUninitializedCapacity: source.count) { buffer, initialized in
      _ = buffer.initialize(from: source)
      initialized = source.count
    }
    Self.zero(&source)
    storage = Mutex(own)
  }

  deinit { wipe() }

  public var isEmpty: Bool { count == 0 }

  /// Lends the bytes to `body`. The buffer is valid only for the duration of the call.
  public func withBytes<R: Sendable>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    try storage.withLock { try $0.withUnsafeBytes(body) }
  }

  /// A new string made from the bytes. The string is an ordinary copy the caller must not keep longer than needed.
  public func utf8String() -> String {
    withBytes { String(decoding: $0, as: UTF8.self) }
  }

  /// Overwrites every byte with zero. The length is unchanged. Also runs on deinit.
  public func wipe() {
    storage.withLock { Self.zero(&$0) }
  }

  public var description: String { "SecretBytes(\(count) bytes, redacted)" }
  public var debugDescription: String { description }

  private static func zero(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { buffer in
      guard let base = buffer.baseAddress, buffer.count > 0 else { return }
      _ = memset_s(base, buffer.count, 0, buffer.count)
    }
  }
}
