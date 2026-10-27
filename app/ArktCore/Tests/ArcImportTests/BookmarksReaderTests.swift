import CoreTestSupport
import Foundation
import Testing

@testable import ArcImport

struct BookmarksReaderTests {
  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarks-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func write(_ json: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("Bookmarks")
    try Data(json.utf8).write(to: url)
    return url
  }

  @Test func readsPopulatedFixtureMatchingManifest() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir)
    let result = try BookmarksReader.read(from: manifest.bookmarksURL)
    #expect(result.bookmarks.count == manifest.bookmarkCount)
    #expect(result.skippedNodes == 0)
    for expected in manifest.bookmarks {
      let found = try #require(result.bookmarks.first { $0.guid == expected.guid })
      #expect(found.root == expected.root)
      #expect(found.folderPath == expected.folderPath)
      #expect(found.title == expected.title)
      #expect(found.url == expected.url)
      #expect(found.dateAdded == ChromiumTime.date(fromWebKit: expected.dateAddedWebKitTime))
    }
  }

  @Test func emptyRootsGiveAnEmptyResult() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let manifest = try FakeChromiumProfile.make(at: dir, options: .init(bookmarks: .empty))
    let result = try BookmarksReader.read(from: manifest.bookmarksURL)
    #expect(result.bookmarks.isEmpty)
    #expect(result.skippedNodes == 0)
  }

  @Test func missingFileGivesAnEmptyResultNotAnError() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let result = try BookmarksReader.read(from: dir.appendingPathComponent("Bookmarks"))
    #expect(result.bookmarks.isEmpty)
    #expect(result.skippedNodes == 0)
  }

  @Test func zeroByteAndRootlessFilesAreEmpty() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try BookmarksReader.read(from: write("{\"roots\": {}}", in: dir)).bookmarks.isEmpty)
    #expect(try BookmarksReader.read(from: write("{}", in: dir)).bookmarks.isEmpty)
  }

  @Test func malformedJSONThrows() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write("{ this is not json", in: dir)
    #expect(throws: BookmarksReader.ReadError.invalidDocument) { try BookmarksReader.read(from: url) }
    let array = try write("[1, 2]", in: dir)
    #expect(throws: BookmarksReader.ReadError.invalidDocument) { try BookmarksReader.read(from: array) }
  }

  @Test func badNodesAreSkippedAndCounted() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = try write(
      """
      {"roots": {"bookmark_bar": {"type": "folder", "name": "Bar", "children": [
        {"type": "url", "name": "Good", "url": "https://example.com/", "guid": "g1", "date_added": "13348540800000000"},
        {"type": "url", "name": "No URL", "guid": "g2"},
        {"type": "url", "name": "Empty URL", "url": "", "guid": "g3"},
        "not a node",
        {"type": "mystery", "name": "Unknown"},
        {"type": "url", "name": "Bad date", "url": "https://example.org/", "date_added": "abc"},
        {"type": "folder", "name": "Sub", "children": [
          {"type": "url", "name": "Nested", "url": "https://example.net/", "guid": "g4", "date_added": "13348540800000000"}
        ]}
      ]}, "sync_transaction_version": "3"}}
      """, in: dir)
    let result = try BookmarksReader.read(from: url)
    #expect(result.bookmarks.map(\.title) == ["Good", "Bad date", "Nested"])
    #expect(result.skippedNodes == 4)
    #expect(result.bookmarks[1].dateAdded == nil)
    #expect(result.bookmarks[1].guid == nil)
    #expect(result.bookmarks[2].folderPath == ["Sub"])
    #expect(result.bookmarks[0].dateAdded == Date(timeIntervalSince1970: 1_704_067_200))
  }

  @Test func deeplyNestedFoldersAreBoundedNotCrashing() throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let depth = 100
    let open = String(repeating: "{\"type\":\"folder\",\"name\":\"f\",\"children\":[", count: depth)
    let close = String(repeating: "]}", count: depth)
    let url = try write("{\"roots\":{\"other\":\(open)\(close)}}", in: dir)
    let result = try BookmarksReader.read(from: url)
    #expect(result.bookmarks.isEmpty)
    #expect(result.skippedNodes >= 1)
  }
}
