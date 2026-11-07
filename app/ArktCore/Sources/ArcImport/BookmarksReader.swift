import Foundation

/// One bookmark from the `Bookmarks` JSON of an Arc profile snapshot.
public struct BookmarkRecord: Sendable, Equatable {
  /// The root it sits under: `bookmark_bar`, `other` or `synced`.
  public let root: String
  /// Folder titles from the root down to (not including) the bookmark.
  public let folderPath: [String]
  public let title: String
  public let url: String
  public let guid: String?
  public let dateAdded: Date?

  public init(root: String, folderPath: [String], title: String, url: String, guid: String?, dateAdded: Date?) {
    self.root = root
    self.folderPath = folderPath
    self.title = title
    self.url = url
    self.guid = guid
    self.dateAdded = dateAdded
  }
}

/// Reads the roots and children of a Chromium `Bookmarks` file (#508). Small by design: the file is one JSON document.
///
/// A missing file is a profile that never used bookmarks, so it gives an empty result, not an error. A file that is
/// not a JSON object throws `invalidDocument`. Nodes without a usable URL, unknown node types and folders nested
/// deeper than `maxDepth` are skipped and counted.
public enum BookmarksReader {
  public enum ReadError: Error, Equatable {
    /// The file exists but is not a JSON object.
    case invalidDocument
  }

  public struct Result: Sendable, Equatable {
    public var bookmarks: [BookmarkRecord] = []
    public var skippedNodes = 0
  }

  /// Folder nesting beyond this is skipped, which keeps a hostile file from exhausting the stack.
  public static let maxDepth = 64

  public static func read(from url: URL) throws -> Result {
    guard FileManager.default.fileExists(atPath: url.path) else { return Result() }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return Result() }
    guard let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw ReadError.invalidDocument
    }
    var result = Result()
    let roots = document["roots"] as? [String: Any] ?? [:]
    for name in roots.keys.sorted() {
      // Scalars such as `sync_transaction_version` live beside the roots; they are not nodes.
      guard let node = roots[name] as? [String: Any] else { continue }
      visit(children: node["children"], root: name, path: [], depth: 1, into: &result)
    }
    return result
  }

  /// Reads the `Bookmarks` file of a snapshot profile.
  public static func read(profile: ArcProfileSnapshot.Profile) throws -> Result {
    try read(from: profile.directory.appendingPathComponent("Bookmarks"))
  }

  private static func visit(children: Any?, root: String, path: [String], depth: Int, into result: inout Result) {
    guard let children = children as? [Any] else { return }
    for child in children {
      guard let node = child as? [String: Any] else {
        result.skippedNodes += 1
        continue
      }
      switch node["type"] as? String {
      case "url":
        guard let address = node["url"] as? String, !address.isEmpty else {
          result.skippedNodes += 1
          continue
        }
        let added = (node["date_added"] as? String).flatMap { Int64($0) }.flatMap(WebKitTime.date(fromMicroseconds:))
        result.bookmarks.append(
          BookmarkRecord(
            root: root, folderPath: path, title: node["name"] as? String ?? "", url: address,
            guid: node["guid"] as? String, dateAdded: added))
      case "folder":
        guard depth < maxDepth else {
          result.skippedNodes += 1
          continue
        }
        visit(
          children: node["children"], root: root, path: path + [node["name"] as? String ?? ""], depth: depth + 1,
          into: &result)
      default:
        result.skippedNodes += 1
      }
    }
  }
}
