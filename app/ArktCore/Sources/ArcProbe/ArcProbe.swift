import ArcImport
import Foundation

/// Counts-only probe of an Arc profile root (#504). Reads scratch copies of the profile databases, never writes to
/// the profile root, never touches the Keychain, and returns only counts, numeric schema versions and schema key
/// names. No URL, title, name, cookie value or password can appear in the output.
public enum ArcProbe {
  /// Arc's standard profile root, `~/Library/Application Support/Arc/User Data`.
  public static func defaultRoot() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)
  }

  public struct RootNotFound: Error {}

  /// Maximum number of archive key lines printed per file.
  static let archiveLineLimit = 40

  /// The report, one line per fact. `scratchParent` holds the temporary copies, which are removed before returning.
  public static func report(
    root: URL, scratchParent: URL = FileManager.default.temporaryDirectory
  ) throws -> [String] {
    let files = FileManager.default
    var isDirectory: ObjCBool = false
    guard files.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw RootNotFound()
    }
    let scratch = scratchParent.appendingPathComponent("arkt-arc-probe-\(UUID().uuidString)", isDirectory: true)
    try files.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: scratch) }

    let profiles = profileDirectories(in: root)
    var lines = ["arkt-arc-probe: counts only, no content", "profiles found: \(profiles.count)"]
    var otherIndex = 0
    for (index, profile) in profiles.enumerated() {
      let name = profileName(profile.lastPathComponent, otherIndex: &otherIndex)
      lines.append("profile \(name)")
      lines += profileLines(profile, scratch: scratch.appendingPathComponent("p\(index)", isDirectory: true))
    }
    lines += sidebarLines(root: root)
    lines += archiveThresholdLines(root: root, profiles: profiles)
    return lines
  }

  // MARK: - Profiles

  static func profileDirectories(in root: URL) -> [URL] {
    ArcProfileSnapshot.profileDirectories(in: root)
  }

  /// Chromium names profile folders `Default` and `Profile N`. Any other folder name is not printed.
  private static func profileName(_ name: String, otherIndex: inout Int) -> String {
    if name == "Default" { return name }
    if name.hasPrefix("Profile "), Int(name.dropFirst("Profile ".count)) != nil { return name }
    otherIndex += 1
    return "other-\(otherIndex)"
  }

  private static func profileLines(_ profile: URL, scratch: URL) -> [String] {
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    var lines: [String] = []
    lines.append(
      databaseLine(
        "History", candidates: ["History"], profile: profile, scratch: scratch,
        counts: [("urls", "urls"), ("visits", "visits")]))
    lines.append(
      databaseLine(
        "Login Data", candidates: ["Login Data"], profile: profile, scratch: scratch,
        counts: [("logins", "logins")]))
    lines.append(
      databaseLine(
        "Cookies", candidates: ["Network/Cookies", "Cookies"], profile: profile, scratch: scratch,
        counts: [("cookies", "cookies")]))
    lines.append(
      databaseLine("Web Data", candidates: ["Web Data"], profile: profile, scratch: scratch, counts: []))
    lines.append(bookmarksLine(profile))
    lines.append(extensionsLine(profile))
    return lines.map { "  " + $0 }
  }

  /// Copies the first existing candidate plus its `-wal` and `-shm` files into `scratch`, then reads the copy.
  private static func databaseLine(
    _ label: String, candidates: [String], profile: URL, scratch: URL, counts: [(title: String, table: String)]
  ) -> String {
    let files = FileManager.default
    guard let relative = candidates.first(where: { files.fileExists(atPath: profile.appendingPathComponent($0).path) })
    else { return "\(label): absent" }
    let name = relative.split(separator: "/").last.map(String.init) ?? relative
    for suffix in ["", "-wal", "-shm"] {
      let source = profile.appendingPathComponent(relative + suffix)
      guard files.fileExists(atPath: source.path) else { continue }
      do { try files.copyItem(at: source, to: scratch.appendingPathComponent(name + suffix)) } catch {
        return "\(label): copy failed code \((error as NSError).code)"
      }
    }
    let (database, code) = ProbeDatabase.open(scratch.appendingPathComponent(name))
    guard let database else { return "\(label): open failed sqlite code \(code)" }
    var parts: [String] = []
    let meta = database.meta(keys: ["version", "last_compatible_version"])
    parts.append("schema version \(meta["version"].map(String.init) ?? "unknown")")
    parts.append("compatible \(meta["last_compatible_version"].map(String.init) ?? "unknown")")
    for (title, table) in counts {
      parts.append("\(title) \(database.count(table: table).map(String.init) ?? "unreadable")")
    }
    return "\(label): " + parts.joined(separator: ", ")
  }

  private static func bookmarksLine(_ profile: URL) -> String {
    guard let json = JSONScan.load(profile.appendingPathComponent("Bookmarks")) else { return "Bookmarks: absent" }
    let roots = JSONScan.bookmarkCounts(json)
    if roots.isEmpty { return "Bookmarks: no roots" }
    return "Bookmarks: " + roots.map { "\($0.root) urls \($0.count.urls) folders \($0.count.folders)" }
      .joined(separator: "; ")
  }

  private static func extensionsLine(_ profile: URL) -> String {
    let parsed = ["Preferences", "Secure Preferences"].compactMap {
      JSONScan.load(profile.appendingPathComponent($0))
    }
    let byLocation = JSONScan.extensionLocations(parsed)
    if byLocation.isEmpty { return "Extensions: 0" }
    let total = byLocation.values.reduce(0, +)
    let detail = byLocation.sorted { $0.key < $1.key }.map { "location \($0.key): \($0.value)" }
    return "Extensions: \(total) (" + detail.joined(separator: ", ") + ")"
  }

  // MARK: - Sidebar

  /// `StorableSidebar.json` sits next to `User Data`, in Arc's folder; also accepted inside the root itself.
  private static func sidebarLines(root: URL) -> [String] {
    let name = "StorableSidebar.json"
    let candidates = [root.deletingLastPathComponent().appendingPathComponent(name), root.appendingPathComponent(name)]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
      return ["StorableSidebar.json: absent"]
    }
    var lines: [String] = []
    do {
      let file = try ArcSidebarFile.decode(Data(contentsOf: url))
      var line = "StorableSidebar.json: present, version \(file.version), containers \(file.sidebar.containers.pairs.count)"
      if let global = file.globalContainer {
        line += ", spaces \(global.spaces.pairs.count) (undecodable \(global.spaceFailures.count))"
        line += ", items \(global.items.pairs.count) (undecodable \(global.itemFailures.count))"
        line += ", top apps containers \(global.topAppsContainerIDs.pairs.count)"
      } else {
        line += ", no global container"
      }
      lines.append(line)
    } catch {
      lines.append("StorableSidebar.json: present, decode failed \(type(of: error)) code \((error as NSError).code)")
    }
    let archiveURL = url.deletingLastPathComponent().appendingPathComponent("StorableArchiveItems.json")
    if FileManager.default.fileExists(atPath: archiveURL.path) {
      do {
        let archive = try ArcArchiveFile.decode(Data(contentsOf: archiveURL))
        lines.append("StorableArchiveItems.json: present, version \(archive.version), items \(archive.items.pairs.count)")
      } catch {
        lines.append("StorableArchiveItems.json: present, decode failed \(type(of: error)) code \((error as NSError).code)")
      }
    } else {
      lines.append("StorableArchiveItems.json: absent")
    }
    return lines
  }

  // MARK: - Archive thresholds

  /// Key names containing "archive" in Local State, each profile's Preferences and the sidebar file. Values are
  /// printed only when numeric.
  private static func archiveThresholdLines(root: URL, profiles: [URL]) -> [String] {
    var sources: [(label: String, url: URL)] = [("Local State", root.appendingPathComponent("Local State"))]
    var otherIndex = 0
    for profile in profiles {
      let name = profileName(profile.lastPathComponent, otherIndex: &otherIndex)
      sources.append(("\(name)/Preferences", profile.appendingPathComponent("Preferences")))
    }
    let sidebarName = "StorableSidebar.json"
    let sidebar = [root.deletingLastPathComponent(), root].map { $0.appendingPathComponent(sidebarName) }
      .first { FileManager.default.fileExists(atPath: $0.path) }
    if let sidebar { sources.append((sidebarName, sidebar)) }

    var lines = ["archive threshold keys (key names only, numeric values only):"]
    for source in sources {
      guard let json = JSONScan.load(source.url) else {
        lines.append("  \(source.label): absent or unreadable")
        continue
      }
      let found = JSONScan.archiveKeys(json).sorted { $0.key < $1.key }
      if found.isEmpty { lines.append("  \(source.label): none") }
      for entry in found.prefix(archiveLineLimit) {
        lines.append("  \(source.label): \(entry.key)" + (entry.value > 1 ? " x\(entry.value)" : ""))
      }
      if found.count > archiveLineLimit { lines.append("  \(source.label): \(found.count - archiveLineLimit) more") }
    }
    return lines
  }
}
