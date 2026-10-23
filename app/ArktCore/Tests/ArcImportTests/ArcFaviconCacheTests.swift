import Foundation
import Testing
import ArcImport

struct ArcFaviconCacheTests {
  static let itemID = "0B3F1C2A-1111-2222-3333-444455556666"
  // printf %s "0B3F1C2A-1111-2222-3333-444455556666" | md5
  static let expectedFileName = "6260558a3bf735be129d5b4514e8a016"

  @Test func fileNameIsLowercaseHexMD5OfItemID() {
    #expect(ArcFaviconCache.fileName(forItemID: Self.itemID) == Self.expectedFileName)
  }

  @Test func pngDataReadsFileByHashedNameAndReturnsNilWhenMissing() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArcFaviconCacheTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    try bytes.write(to: directory.appendingPathComponent(Self.expectedFileName))

    let cache = ArcFaviconCache(directory: directory)
    #expect(cache.pngData(forItemID: Self.itemID) == bytes)
    #expect(cache.pngData(forItemID: "FFFFFFFF-0000-0000-0000-000000000000") == nil)
  }
}
