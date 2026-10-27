import Foundation

/// The invented content every fixture profile contains. Fixed values, so manifests are deterministic.
enum FixtureData {
  /// 2024-01-01 00:00:00 UTC.
  static let baseUnixSeconds: Int64 = 1_704_067_200

  static func webKit(afterSeconds seconds: Int64) -> Int64 {
    ChromiumTime.webKit(fromUnixSeconds: baseUnixSeconds + seconds)
  }

  // Transition core types (low 8 bits) and qualifier flags, from Chromium's ui::PageTransition.
  static let link: Int32 = 0
  static let typed: Int32 = 1
  static let reload: Int32 = 8
  static let chainStart: Int32 = 0x1000_0000
  static let chainEnd: Int32 = 0x2000_0000
  static let fromAddressBar: Int32 = 0x0200_0000

  static let history: [FixtureManifest.HistoryEntry] = [
    .init(
      url: "https://example.com/", title: "Example Domain",
      visits: [
        .init(webkitTime: webKit(afterSeconds: 60), transition: typed | chainStart | chainEnd | fromAddressBar),
        .init(webkitTime: webKit(afterSeconds: 3_600), transition: link | chainStart | chainEnd),
        .init(webkitTime: webKit(afterSeconds: 7_200), transition: reload | chainStart | chainEnd),
      ]
    ),
    .init(
      url: "https://example.org/docs/page?q=fixture", title: "Fixture Docs",
      visits: [.init(webkitTime: webKit(afterSeconds: 120), transition: link | chainStart | chainEnd)]
    ),
    .init(
      url: "https://example.net/\u{0161}\u{0159}", title: "",
      visits: [.init(webkitTime: webKit(afterSeconds: 86_400), transition: typed | chainStart | chainEnd)]
    ),
  ]

  static let logins: [FixtureManifest.Login] = [
    .init(originURL: "https://example.com/login", signonRealm: "https://example.com/", username: "fixture.user@example.com", password: "correct-horse-1"),
    .init(originURL: "https://example.org/signin", signonRealm: "https://example.org/", username: "second-user", password: "p\u{00E4}ssw\u{00F6}rd-2"),
    .init(originURL: "https://example.net/", signonRealm: "https://example.net/", username: "", password: "no-username-3"),
  ]

  static let cookies: [FixtureManifest.Cookie] = [
    .init(hostKey: ".example.com", name: "session", value: "fixture-session-value", path: "/", isSecure: true, isHTTPOnly: true, expiresWebKitTime: webKit(afterSeconds: 31_536_000)),
    .init(hostKey: "www.example.org", name: "theme", value: "dark", path: "/docs", isSecure: false, isHTTPOnly: false, expiresWebKitTime: webKit(afterSeconds: 86_400)),
    .init(hostKey: ".example.net", name: "empty", value: "", path: "/", isSecure: true, isHTTPOnly: false, expiresWebKitTime: 0),
  ]

  static let bookmarks: [FixtureManifest.Bookmark] = [
    .init(root: "bookmark_bar", folderPath: [], title: "Example", url: "https://example.com/", guid: "00000000-0000-4000-8000-000000000001", dateAddedWebKitTime: webKit(afterSeconds: 10)),
    .init(root: "bookmark_bar", folderPath: [], title: "Docs", url: "https://example.org/docs/", guid: "00000000-0000-4000-8000-000000000002", dateAddedWebKitTime: webKit(afterSeconds: 20)),
    .init(root: "bookmark_bar", folderPath: ["Reading"], title: "Article", url: "https://example.net/article", guid: "00000000-0000-4000-8000-000000000003", dateAddedWebKitTime: webKit(afterSeconds: 30)),
    .init(root: "other", folderPath: [], title: "Other item", url: "https://example.com/other", guid: "00000000-0000-4000-8000-000000000004", dateAddedWebKitTime: webKit(afterSeconds: 40)),
    .init(root: "synced", folderPath: [], title: "Synced item", url: "https://example.org/synced", guid: "00000000-0000-4000-8000-000000000005", dateAddedWebKitTime: webKit(afterSeconds: 50)),
  ]

  static let extensions: [FixtureManifest.ExtensionEntry] = [
    .init(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", kind: .webStore, name: "Fixture Web Store Extension", version: "1.2.3"),
    .init(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", kind: .unpacked, name: "Fixture Unpacked Extension", version: "0.1"),
    .init(id: "cccccccccccccccccccccccccccccccc", kind: .builtIn, name: "Fixture Built-in Component", version: "9.9"),
  ]
}
