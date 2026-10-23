import CryptoKit
import Foundation

/// Read-only lookup into Arc's `SidebarItemsFaviconCache` directory.
/// Each favicon is a 32x32 PNG with no extension, named by the lowercase hex
/// MD5 of the sidebar item id string exactly as Arc stores it (uppercase UUID).
public struct ArcFaviconCache: Sendable {
  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public static func fileName(forItemID itemID: String) -> String {
    Insecure.MD5.hash(data: Data(itemID.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  /// Returns the cached PNG bytes, or nil when no file exists. Never writes.
  public func pngData(forItemID itemID: String) -> Data? {
    let url = directory.appendingPathComponent(Self.fileName(forItemID: itemID), isDirectory: false)
    return try? Data(contentsOf: url)
  }
}
