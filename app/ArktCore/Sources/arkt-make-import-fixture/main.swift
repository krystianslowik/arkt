import CoreTestSupport
import Foundation

// Writes an invented Chromium-family profile for the engine import smoke (#517) to `<folder>/User Data/Default`, the
// layout the import reads under its data folder. Usage: `arkt-make-import-fixture <new folder>`. The folder must not
// exist yet. On top of the fixed fixture: two history entries visited in the last days (the fixed visits are from
// 2024, past the 90 days an import keeps), a cookie for 127.0.0.1 that expires in 2100 and an HttpOnly one next to
// it (the fixed cookies are expired), and a second Web Store extension id. The Safe Storage password is the fixture's
// invented one; no Keychain item is involved. Prints the counts the import should report.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  print("usage: arkt-make-import-fixture <new folder>")
  exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
guard !FileManager.default.fileExists(atPath: folder.path) else {
  print("error: \(folder.path) exists; pass a new folder")
  exit(1)
}

let now = Int64(Date().timeIntervalSince1970)
let typed: Int32 = 1, link: Int32 = 0, chainStart: Int32 = 0x1000_0000, chainEnd: Int32 = 0x2000_0000
func visit(hoursAgo: Int64, _ core: Int32) -> FixtureManifest.Visit {
  .init(webkitTime: ChromiumTime.webKit(fromUnixSeconds: now - hoursAgo * 3_600), transition: core | chainStart | chainEnd)
}
let year2100 = ChromiumTime.webKit(fromUnixSeconds: 4_102_444_800)
let options = FakeChromiumProfile.Options(
  extraCookies: [
    .init(hostKey: "127.0.0.1", name: "imported", value: "from-fixture", path: "/", isSecure: false,
          isHTTPOnly: false, expiresWebKitTime: year2100),
    .init(hostKey: "127.0.0.1", name: "imported-httponly", value: "hidden-from-script", path: "/", isSecure: false,
          isHTTPOnly: true, expiresWebKitTime: year2100),
  ],
  extraHistory: [
    .init(url: "https://recent-one.example/", title: "Recent One",
          visits: [visit(hoursAgo: 48, typed), visit(hoursAgo: 24, link)]),
    .init(url: "https://recent-two.example/page", title: "Recent Two", visits: [visit(hoursAgo: 3, link)]),
  ],
  extraExtensions: [
    .init(id: "dddddddddddddddddddddddddddddddd", kind: .webStore, name: "Second Fixture Web Store Extension",
          version: "2.0"),
  ])

do {
  let profile = folder.appendingPathComponent("User Data/Default", isDirectory: true)
  let manifest = try FakeChromiumProfile.make(at: profile, options: options)
  let cutoff = ChromiumTime.webKit(fromUnixSeconds: now - 90 * 86_400)
  let recent = manifest.history.flatMap(\.visits).filter { $0.webkitTime >= cutoff }.count
  let unexpired = manifest.cookies.filter { $0.expiresWebKitTime > ChromiumTime.webKit(fromUnixSeconds: now) }.count
  let kinds = Dictionary(grouping: manifest.extensions, by: \.kind).mapValues(\.count)
  print("fixture \(profile.path)")
  print("history urls \(manifest.history.count) visits \(manifest.visitCount) within 90 days \(recent)")
  print("bookmarks \(manifest.bookmarkCount)")
  print("cookies \(manifest.cookies.count) unexpired \(unexpired)")
  print("logins \(manifest.logins.count)")
  print("extensions webStore \(kinds[.webStore] ?? 0) unpacked \(kinds[.unpacked] ?? 0) builtIn \(kinds[.builtIn] ?? 0)")
} catch {
  print("error: \(error)")
  exit(1)
}
