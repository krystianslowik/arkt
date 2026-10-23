import CryptoKit
import Foundation

/// Renders the bundled synthetic Arc fixtures into a per-test sandbox with every `https://example.com` origin
/// rewritten to the loopback server's base URL, and computes SHA-256 digests of the rendered files (Task U6, #171).
enum ArcFixture {
  /// The placeholder origin in the synthetic fixture JSON files (`StorableSidebar-synthetic.json` and
  /// `StorableArchiveItems-synthetic.json`), rewritten to `FixtureServer.base` at render time.
  static let placeholderOrigin = "https://example.com"

  /// Expected counts from E6 (`docs/plans/2026-10-23-track-e-results.md`, section "Expected counts").
  struct ExpectedCounts: Equatable, Sendable {
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `spaces: 2 (report: 2)`.
    let spaces = 2
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `imported totals (report): tabs 9`.
    let tabs = 9
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `imported totals (report): folders 1`.
    let folders = 1
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `imported totals (report): splits 1`.
    let splits = 1
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `favorites: tabs 2`.
    let favorites = 2
    /// `docs/plans/2026-10-23-track-e-results.md`, "Expected counts": `archive imported: 7 (manual 5, auto 2)`.
    let archive = 7
  }

  static let expected = ExpectedCounts()

  /// Every path in the synthetic fixtures (plus `/favicon.ico`, which the FakeEngine fetches relative to the page).
  static let fixturePaths: Set<String> = [
    "/mail",
    "/calendar",
    "/articles/one",
    "/articles/two",
    "/docs/left",
    "/docs/right",
    "/news",
    "/wiki",
    "/search?q=arkt",
    "/manual",
    "/auto",
    "/little",
    "/unknown",
    "/gone",
    "/no-date",
    "/odd-reason",
    "/favicon.ico",
  ]

  /// SHA-256 digests of the rendered `StorableSidebar.json` and `StorableArchiveItems.json`.
  struct Checksums: Equatable, Sendable {
    let sidebar: SHA256.Digest
    let archive: SHA256.Digest

    /// True when the files in `arcDir` still have the exact bytes written by `render(into:base:)`.
    func unchanged(in arcDir: URL) throws -> Bool {
      try ArcFixture.checksums(in: arcDir) == self
    }
  }

  /// Reads the bundled synthetic fixtures, replaces every `https://example.com` with `base`, writes
  /// `StorableSidebar.json` and `StorableArchiveItems.json` into `arcDir`, and returns their SHA-256 digests.
  @discardableResult
  static func render(into arcDir: URL, base: String) throws -> Checksums {
    let sidebarData = try renderFile(resource: "StorableSidebar-synthetic", base: base)
    let archiveData = try renderFile(resource: "StorableArchiveItems-synthetic", base: base)
    try sidebarData.write(to: arcDir.appendingPathComponent("StorableSidebar.json", isDirectory: false),
                          options: .atomic)
    try archiveData.write(to: arcDir.appendingPathComponent("StorableArchiveItems.json", isDirectory: false),
                          options: .atomic)
    return Checksums(sidebar: SHA256.hash(data: sidebarData), archive: SHA256.hash(data: archiveData))
  }

  /// Current SHA-256 digests of `StorableSidebar.json` and `StorableArchiveItems.json` in `arcDir`.
  static func checksums(in arcDir: URL) throws -> Checksums {
    let sidebar = try Data(contentsOf: arcDir.appendingPathComponent("StorableSidebar.json", isDirectory: false))
    let archive = try Data(contentsOf: arcDir.appendingPathComponent("StorableArchiveItems.json", isDirectory: false))
    return Checksums(sidebar: SHA256.hash(data: sidebar), archive: SHA256.hash(data: archive))
  }

  private static func renderFile(resource: String, base: String) throws -> Data {
    let bundle = Bundle(for: ArktUITestCase.self)
    guard let url = bundle.url(forResource: resource, withExtension: "json") else {
      throw HarnessError("missing bundled fixture \(resource).json")
    }
    let template = try String(contentsOf: url, encoding: .utf8)
    let rendered = template.replacingOccurrences(of: placeholderOrigin, with: base)
    return Data(rendered.utf8)
  }
}
