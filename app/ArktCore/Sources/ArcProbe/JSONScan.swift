import Foundation

/// Counts-only reads over Chromium and Arc JSON files. Nothing here returns a string value.
enum JSONScan {
  static func load(_ url: URL) -> Any? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  // MARK: - Bookmarks

  struct BookmarkCount: Equatable {
    var urls = 0
    var folders = 0
  }

  /// Bookmark roots Chromium writes. Any other key under `roots` is counted as `unlisted`.
  static let bookmarkRoots = ["bookmark_bar", "other", "synced"]

  /// Url and folder counts per root, in a fixed order, from a parsed `Bookmarks` file.
  static func bookmarkCounts(_ json: Any) -> [(root: String, count: BookmarkCount)] {
    guard let roots = (json as? [String: Any])?["roots"] as? [String: Any] else { return [] }
    var result: [(String, BookmarkCount)] = []
    var unlisted = BookmarkCount()
    var sawUnlisted = false
    for key in roots.keys.sorted() {
      guard let node = roots[key] as? [String: Any], node["type"] != nil else { continue }
      var count = BookmarkCount()
      tally(node, into: &count, isRoot: true)
      if bookmarkRoots.contains(key) {
        result.append((key, count))
      } else {
        sawUnlisted = true
        unlisted.urls += count.urls
        unlisted.folders += count.folders
      }
    }
    result.sort { (bookmarkRoots.firstIndex(of: $0.0) ?? 0) < (bookmarkRoots.firstIndex(of: $1.0) ?? 0) }
    if sawUnlisted { result.append(("unlisted", unlisted)) }
    return result
  }

  private static func tally(_ node: [String: Any], into count: inout BookmarkCount, isRoot: Bool) {
    switch node["type"] as? String {
    case "url": count.urls += 1
    case "folder":
      if !isRoot { count.folders += 1 }
      for child in node["children"] as? [[String: Any]] ?? [] { tally(child, into: &count, isRoot: false) }
    default: break
    }
  }

  // MARK: - Extensions

  /// Extension ids per install location from `extensions.settings` of Preferences and Secure Preferences.
  /// An id seen in both files counts once, with the location of the first file. Ids themselves are never kept.
  static func extensionLocations(_ files: [Any]) -> [String: Int] {
    var locationByID: [String: String] = [:]
    for json in files {
      let settings = ((json as? [String: Any])?["extensions"] as? [String: Any])?["settings"] as? [String: Any]
      for (id, value) in settings ?? [:] where locationByID[id] == nil {
        let location = (value as? [String: Any])?["location"] as? Int
        locationByID[id] = location.map { String($0) } ?? "unknown"
      }
    }
    return locationByID.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  // MARK: - Archive keys

  /// A key is printable only when it looks like a schema name (letters, digits, underscore). Anything else, such
  /// as a site name or an identifier used as a dictionary key, is replaced by `*`.
  static func printableKey(_ key: String) -> String {
    guard let first = key.unicodeScalars.first, first.properties.isAlphabetic, first.isASCII, key.count <= 64,
      key.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "_") })
    else { return "*" }
    return key
  }

  /// Every key path whose last key contains "archive", with the value only when it is numeric or a boolean.
  /// Returns `path (kind-or-number)` strings with occurrence counts, so repeated paths collapse to one line.
  static func archiveKeys(_ json: Any) -> [String: Int] {
    var found: [String: Int] = [:]
    walk(json, path: [], into: &found)
    return found
  }

  private static func walk(_ value: Any, path: [String], into found: inout [String: Int]) {
    if let dictionary = value as? [String: Any] {
      for (key, child) in dictionary {
        let printable = printableKey(key)
        let next = path + [printable]
        if printable != "*", printable.lowercased().contains("archive") {
          found["\(next.joined(separator: ".")) (\(describe(child)))", default: 0] += 1
        }
        walk(child, path: next, into: &found)
      }
    } else if let array = value as? [Any] {
      for child in array { walk(child, path: path + ["[]"], into: &found) }
    }
  }

  private static func describe(_ value: Any) -> String {
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return "bool" }
      return "\(number)"
    }
    switch value {
    case is String: return "string"
    case let dictionary as [String: Any]: return "object, \(dictionary.count) keys"
    case let array as [Any]: return "array, \(array.count) items"
    default: return "null"
    }
  }
}
