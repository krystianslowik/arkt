import CryptoKit
import Foundation

extension FakeChromiumProfile {
  static func writeHistory(
    to url: URL, entries: [FixtureManifest.HistoryEntry], urlColumns: [FixtureColumn], visitColumns: [FixtureColumn]
  ) throws {
    let db = try FixtureDatabase(creating: url)
    try db.exec("CREATE TABLE meta (key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)")
    try db.exec("INSERT INTO meta VALUES ('version', '70'), ('last_compatible_version', '16')")
    try db.createTable("urls", columns: urlColumns, primaryKey: "id")
    try db.createTable("visits", columns: visitColumns, primaryKey: "id")
    var visitID: Int64 = 0
    for (index, entry) in entries.enumerated() {
      let urlID = Int64(index + 1)
      let typedCount = entry.visits.filter { $0.coreTransition == FixtureData.typed }.count
      try db.insert(into: "urls", columns: urlColumns, row: [
        "id": .int(urlID), "url": .text(entry.url), "title": .text(entry.title),
        "visit_count": .int(Int64(entry.visitCount)), "typed_count": .int(Int64(typedCount)),
        "last_visit_time": .int(entry.lastVisitWebKitTime), "hidden": .int(0),
      ])
      for visit in entry.visits {
        visitID += 1
        try db.insert(into: "visits", columns: visitColumns, row: [
          "id": .int(visitID), "url": .int(urlID), "visit_time": .int(visit.webkitTime), "from_visit": .int(0),
          "transition": .int(Int64(visit.transition)), "segment_id": .int(0), "visit_duration": .int(1_500_000),
          "incremented_omnibox_typed_score": .int(visit.coreTransition == FixtureData.typed ? 1 : 0),
        ])
      }
    }
  }

  static func writeLogins(
    to url: URL, logins: [FixtureManifest.Login], key: [UInt8], columns: [FixtureColumn]
  ) throws {
    let db = try FixtureDatabase(creating: url)
    try db.exec("CREATE TABLE meta (key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)")
    try db.exec("INSERT INTO meta VALUES ('version', '43'), ('last_compatible_version', '40')")
    try db.createTable("logins", columns: columns)
    for (index, login) in logins.enumerated() {
      let encrypted = try ChromiumV10.encrypt(Array(login.password.utf8), key: key)
      try db.insert(into: "logins", columns: columns, row: [
        "origin_url": .text(login.originURL), "action_url": .text(login.originURL),
        "username_element": .text("user"), "username_value": .text(login.username),
        "password_element": .text("pass"), "password_value": .blob(encrypted), "submit_element": .text(""),
        "signon_realm": .text(login.signonRealm),
        "date_created": .int(FixtureData.webKit(afterSeconds: Int64(index) * 100)),
        "blacklisted_by_user": .int(0), "scheme": .int(0), "password_type": .int(0), "times_used": .int(Int64(index + 1)),
        "date_last_used": .int(FixtureData.webKit(afterSeconds: 1_000)),
        "date_password_modified": .int(FixtureData.webKit(afterSeconds: 500)),
      ])
    }
  }

  static func writeCookies(
    to url: URL, cookies: [FixtureManifest.Cookie], key: [UInt8], version: Int, hostPrefixed: Bool,
    columns: [FixtureColumn]
  ) throws {
    let db = try FixtureDatabase(creating: url)
    try db.exec("CREATE TABLE meta (key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)")
    try db.exec("INSERT INTO meta VALUES ('version', '\(version)'), ('last_compatible_version', '\(version)')")
    try db.createTable("cookies", columns: columns)
    for (index, cookie) in cookies.enumerated() {
      var plaintext = Array(cookie.value.utf8)
      if hostPrefixed { plaintext = Array(SHA256.hash(data: Data(cookie.hostKey.utf8))) + plaintext }
      let created = FixtureData.webKit(afterSeconds: Int64(index) * 10)
      try db.insert(into: "cookies", columns: columns, row: [
        "creation_utc": .int(created), "host_key": .text(cookie.hostKey), "top_frame_site_key": .text(""),
        "name": .text(cookie.name), "value": .text(""), "encrypted_value": .blob(try ChromiumV10.encrypt(plaintext, key: key)),
        "path": .text(cookie.path), "expires_utc": .int(cookie.expiresWebKitTime),
        "is_secure": .int(cookie.isSecure ? 1 : 0), "is_httponly": .int(cookie.isHTTPOnly ? 1 : 0),
        "last_access_utc": .int(created), "has_expires": .int(cookie.expiresWebKitTime == 0 ? 0 : 1),
        "is_persistent": .int(cookie.expiresWebKitTime == 0 ? 0 : 1), "priority": .int(1), "samesite": .int(-1),
        "source_scheme": .int(cookie.isSecure ? 2 : 1), "source_port": .int(cookie.isSecure ? 443 : 80),
        "last_update_utc": .int(created), "source_type": .int(0), "has_cross_site_ancestor": .int(0),
      ])
    }
  }
}

enum BookmarksWriter {
  static func write(_ bookmarks: [FixtureManifest.Bookmark], to url: URL) throws {
    var nextID = 1
    func take() -> String { defer { nextID += 1 }; return String(nextID) }
    func rootNode(_ root: String, _ name: String) -> [String: Any] {
      var children: [[String: Any]] = []
      var folders: [String: Int] = [:]
      for bookmark in bookmarks where bookmark.root == root {
        let node: [String: Any] = [
          "date_added": String(bookmark.dateAddedWebKitTime), "guid": bookmark.guid, "id": take(),
          "name": bookmark.title, "type": "url", "url": bookmark.url,
        ]
        if let folder = bookmark.folderPath.first {
          if let at = folders[folder] {
            var folderNode = children[at]
            folderNode["children"] = (folderNode["children"] as? [[String: Any]] ?? []) + [node]
            children[at] = folderNode
          } else {
            folders[folder] = children.count
            children.append([
              "children": [node], "date_added": String(bookmark.dateAddedWebKitTime), "date_modified": "0",
              "guid": "10000000-0000-4000-8000-\(String(format: "%012d", children.count + 1))", "id": take(),
              "name": folder, "type": "folder",
            ])
          }
        } else {
          children.append(node)
        }
      }
      return [
        "children": children, "date_added": String(FixtureData.webKit(afterSeconds: 0)), "date_modified": "0",
        "guid": "0bc5d13f-2cba-5d74-951f-3f233fe6c908-\(root)", "id": take(), "name": name, "type": "folder",
      ]
    }
    let document: [String: Any] = [
      "checksum": "00000000000000000000000000000000",
      "roots": [
        "bookmark_bar": rootNode("bookmark_bar", "Bookmarks bar"),
        "other": rootNode("other", "Other bookmarks"),
        "synced": rootNode("synced", "Mobile bookmarks"),
      ],
      "version": 1,
    ]
    try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: url)
  }
}

enum PreferencesWriter {
  static func write(_ extensions: [FixtureManifest.ExtensionEntry], profileName: String?, to url: URL) throws {
    var settings: [String: Any] = [:]
    for entry in extensions {
      var item: [String: Any] = [
        "manifest": ["name": entry.name, "version": entry.version, "manifest_version": 3],
        "state": 1, "was_installed_by_default": false, "install_time": String(FixtureData.webKit(afterSeconds: 5)),
      ]
      switch entry.kind {
      case .webStore:
        item["from_webstore"] = true
        item["location"] = 1
        item["path"] = "\(entry.id)/\(entry.version)_0"
      case .unpacked:
        item["from_webstore"] = false
        item["location"] = 4
        item["path"] = "/fixture/unpacked-extension"
      case .builtIn:
        item["from_webstore"] = false
        item["location"] = 5
        item["path"] = entry.id
      }
      settings[entry.id] = item
    }
    var document: [String: Any] = ["extensions": ["settings": settings]]
    if let profileName { document["profile"] = ["name": profileName] }
    try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: url)
  }
}
