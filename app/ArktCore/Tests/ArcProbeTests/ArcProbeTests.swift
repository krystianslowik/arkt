import Foundation
import SQLite3
import Testing

@testable import ArcProbe

/// Synthetic Arc profile roots built in temporary folders. Every text value carries `secret` so a test can prove the
/// report never prints content.
struct ArcProbeTests {
  static let secret = "SENTINEL-secret-content"

  struct Fixture {
    let parent: URL
    var root: URL { parent.appendingPathComponent("Arc/User Data", isDirectory: true) }
    var arcFolder: URL { parent.appendingPathComponent("Arc", isDirectory: true) }
    var scratch: URL { parent.appendingPathComponent("scratch", isDirectory: true) }

    init() throws {
      parent = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: parent) }

    func profile(_ name: String) throws -> URL {
      let url = root.appendingPathComponent(name, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    }
  }

  /// Runs SQL on a fresh database at `url`.
  static func makeDatabase(_ url: URL, sql: [String]) throws {
    var handle: OpaquePointer?
    #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
    defer { sqlite3_close(handle) }
    for statement in sql { #expect(sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK, "\(statement)") }
  }

  static func write(_ json: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: url)
  }

  static func snapshot(of directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
    while let url = walker?.nextObject() as? URL {
      guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
      result[url.path] = try Data(contentsOf: url)
    }
    return result
  }

  static func populate(_ profile: URL) throws {
    let secret = Self.secret
    try makeDatabase(
      profile.appendingPathComponent("History"),
      sql: [
        "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
        "INSERT INTO meta VALUES('version','61'),('last_compatible_version','16'),('mmap_status','-1')",
        "CREATE TABLE urls(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR)",
        "INSERT INTO urls(url,title) VALUES('https://\(secret).example/a','\(secret)'),('https://\(secret).example/b','t')",
        "CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER)",
        "INSERT INTO visits(url) VALUES(1),(1),(2)",
      ])
    try makeDatabase(
      profile.appendingPathComponent("Login Data"),
      sql: [
        "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
        "INSERT INTO meta VALUES('version','40'),('last_compatible_version','40')",
        "CREATE TABLE logins(origin_url VARCHAR, username_value VARCHAR, password_value BLOB)",
        "INSERT INTO logins VALUES('https://\(secret)','\(secret)',x'0102')",
      ])
    try FileManager.default.createDirectory(
      at: profile.appendingPathComponent("Network"), withIntermediateDirectories: true)
    try makeDatabase(
      profile.appendingPathComponent("Network/Cookies"),
      sql: [
        "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
        "INSERT INTO meta VALUES('version','23'),('last_compatible_version','23')",
        "CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB)",
        "INSERT INTO cookies VALUES('\(secret).example','\(secret)','\(secret)',x'00')",
        "INSERT INTO cookies VALUES('b.example','n','v',x'00')",
        "INSERT INTO cookies VALUES('c.example','n','v',x'00')",
        "INSERT INTO cookies VALUES('d.example','n','v',x'00')",
      ])
    try makeDatabase(
      profile.appendingPathComponent("Web Data"),
      sql: [
        "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
        "INSERT INTO meta VALUES('version','125'),('last_compatible_version','125')",
        "CREATE TABLE autofill(name TEXT, value TEXT)",
        "INSERT INTO autofill VALUES('\(secret)','\(secret)')",
      ])
    try write(
      """
      {"roots":{"bookmark_bar":{"type":"folder","name":"\(secret)","children":[
        {"type":"url","name":"\(secret)","url":"https://\(secret).example"},
        {"type":"folder","name":"\(secret)","children":[{"type":"url","name":"x","url":"https://x"}]}]},
       "other":{"type":"folder","name":"o","children":[{"type":"url","name":"y","url":"https://y"}]},
       "synced":{"type":"folder","name":"s","children":[]},
       "sync_transaction_version":"1"},"version":1}
      """, to: profile.appendingPathComponent("Bookmarks"))
    try write(
      """
      {"autoArchiveAfterSeconds":43200,"profile":{"name":"\(secret)","archive_enabled":true},
       "extensions":{"settings":{
         "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":{"location":1,"path":"\(secret)"},
         "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":{"location":4}}},
       "content_settings":{"archive.org":{"setting":"\(secret)"}}}
      """, to: profile.appendingPathComponent("Preferences"))
    try write(
      """
      {"extensions":{"settings":{
         "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":{"location":1},
         "cccccccccccccccccccccccccccccccc":{"location":5}}}}
      """, to: profile.appendingPathComponent("Secure Preferences"))
  }

  static let sidebarJSON = """
    {"version":1,"sidebar":{"containers":[{"global":{}},{"spaces":["S1",{"id":"S1","title":"\(secret)"}],
      "items":[],"topAppsContainerIDs":[]}]}}
    """

  static func lines(_ fixture: Fixture) throws -> [String] {
    try ArcProbe.report(root: fixture.root, scratchParent: fixture.scratch)
  }

  @Test func reportsCountsSchemaVersionsBookmarksAndExtensions() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Self.populate(fixture.profile("Default"))
    try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Crashpad"), withIntermediateDirectories: true)

    let text = try Self.lines(fixture).joined(separator: "\n")
    #expect(text.contains("profiles found: 1"))
    #expect(text.contains("History: schema version 61, compatible 16, urls 2, visits 3"))
    #expect(text.contains("Login Data: schema version 40, compatible 40, logins 1"))
    #expect(text.contains("Cookies: schema version 23, compatible 23, cookies 4"))
    #expect(text.contains("Web Data: schema version 125, compatible 125"))
    #expect(text.contains("bookmark_bar urls 2 folders 1; other urls 1 folders 0; synced urls 0 folders 0"))
    #expect(text.contains("Extensions: 3 (location 1: 1, location 4: 1, location 5: 1)"))
  }

  @Test func neverPrintsContent() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Self.populate(fixture.profile("Default"))
    try Self.write(Self.sidebarJSON, to: fixture.arcFolder.appendingPathComponent("StorableSidebar.json"))

    let text = try Self.lines(fixture).joined(separator: "\n")
    #expect(!text.contains(Self.secret))
    #expect(!text.contains("example"))
    #expect(!text.contains("aaaaaaaa"))
    #expect(!text.contains("archive.org"))
    #expect(!text.contains(fixture.parent.lastPathComponent))
  }

  @Test func archiveKeysShowNamesAndNumericValuesOnly() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Self.populate(fixture.profile("Default"))

    let text = try Self.lines(fixture).joined(separator: "\n")
    #expect(text.contains("Default/Preferences: autoArchiveAfterSeconds (43200)"))
    #expect(text.contains("Default/Preferences: profile.archive_enabled (bool)"))
    // A dictionary key that is not a schema name is masked, so "archive.org" never appears.
    #expect(!text.contains("content_settings"))
  }

  @Test func sidebarAndMissingFiles() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Self.populate(fixture.profile("Default"))
    try Self.write(Self.sidebarJSON, to: fixture.arcFolder.appendingPathComponent("StorableSidebar.json"))
    let present = try Self.lines(fixture).joined(separator: "\n")
    #expect(present.contains("StorableSidebar.json: present, version 1, containers 1"))
    #expect(present.contains("spaces 1 (undecodable 1), items 0 (undecodable 0), top apps containers 0"))

    let bare = try Fixture()
    defer { bare.remove() }
    _ = try bare.profile("Profile 1")
    try Self.write("{}", to: bare.root.appendingPathComponent("Profile 1/Preferences"))
    let text = try Self.lines(bare).joined(separator: "\n")
    #expect(text.contains("profile Profile 1"))
    #expect(text.contains("History: absent"))
    #expect(text.contains("Bookmarks: absent"))
    #expect(text.contains("Extensions: 0"))
    #expect(text.contains("StorableSidebar.json: absent"))
  }

  @Test func listsProfilesAndMasksUnknownFolderNames() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for name in ["Default", "Profile 2", "\(Self.secret)-folder"] {
      try Self.write("{}", to: fixture.profile(name).appendingPathComponent("Preferences"))
    }
    let text = try Self.lines(fixture).joined(separator: "\n")
    #expect(text.contains("profiles found: 3"))
    #expect(text.contains("profile Default"))
    #expect(text.contains("profile Profile 2"))
    #expect(text.contains("profile other-1"))
    #expect(!text.contains(Self.secret))
  }

  @Test func countsRowsStillInTheWriteAheadLog() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let profile = try fixture.profile("Default")
    let live = fixture.parent.appendingPathComponent("live", isDirectory: true)
    try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)

    // Keep the connection open so the rows stay in History-wal, then copy the three files as Arc would have them.
    var handle: OpaquePointer?
    #expect(sqlite3_open(live.appendingPathComponent("History").path, &handle) == SQLITE_OK)
    for sql in [
      "PRAGMA journal_mode=WAL", "PRAGMA wal_autocheckpoint=0",
      "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
      "INSERT INTO meta VALUES('version','61'),('last_compatible_version','16')",
      "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT)", "INSERT INTO urls(url) VALUES('a'),('b'),('c')",
    ] { #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK) }
    for suffix in ["", "-wal", "-shm"] {
      let source = live.appendingPathComponent("History" + suffix)
      #expect(FileManager.default.fileExists(atPath: source.path), "\(suffix)")
      try FileManager.default.copyItem(at: source, to: profile.appendingPathComponent("History" + suffix))
    }
    sqlite3_close(handle)

    let text = try Self.lines(fixture).joined(separator: "\n")
    #expect(text.contains("History: schema version 61, compatible 16, urls 3, visits unreadable"))
  }

  @Test func leavesTheProfileRootUntouchedAndCleansScratch() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Self.populate(fixture.profile("Default"))
    try Self.write(Self.sidebarJSON, to: fixture.arcFolder.appendingPathComponent("StorableSidebar.json"))
    let before = try Self.snapshot(of: fixture.arcFolder)

    _ = try Self.lines(fixture)

    #expect(try Self.snapshot(of: fixture.arcFolder) == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.scratch.path).isEmpty)
  }

  @Test func missingRootThrows() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
    #expect(throws: ArcProbe.RootNotFound.self) { try ArcProbe.report(root: missing) }
  }
}
