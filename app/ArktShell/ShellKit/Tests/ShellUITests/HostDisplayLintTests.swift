import Foundation
import Testing

/// ShellUI and CoreBridge write a host for the user only through `HostDisplay` (#697, #732): a raw `url.host()`
/// shown as text (`url.host() ?? url.absoluteString`, `url.host().map`, `host: url.host()`) would show the engine's
/// `xn--` form on one surface and Unicode on another, or, with `percentEncoded: false`, Unicode that skipped the spoof
/// check. A line that reads the raw host only to compare or search ends in `// not shown` and is let through.
struct HostDisplayLintTests {
  /// app/ArktShell/ShellKit/Sources, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/ShellUITests/HostDisplayLintTests.swift
  static let sources = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources")
  static let scanned = ["ShellUI", "CoreBridge"]
  /// The rule itself, which reads the raw host to check it.
  static let exempt = ["HostDisplay.swift"]

  static let patterns = [
    #"\.host\((percentEncoded:\s*\w+)?\)\s*(\?\?|\.map\b|\.flatMap\b)"#,
    #"\bhost:\s*[^,)\n]*\.host\((percentEncoded:\s*\w+)?\)"#,
  ]

  static func rawHostUses(in source: String) -> [String] {
    let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    return source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      let text = String(line)
      guard !text.hasSuffix("// not shown") else { return nil }
      let range = NSRange(text.startIndex..., in: text)
      return regexes.contains { $0.firstMatch(in: text, range: range) != nil }
        ? text.trimmingCharacters(in: .whitespaces) : nil
    }
  }

  static func offendingLines() throws -> [String: [String]] {
    var result: [String: [String]] = [:]
    for module in scanned {
      let root = sources.appending(path: module)
      guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
      for case let url as URL in walker where url.pathExtension == "swift"
        && !exempt.contains(url.lastPathComponent) {
        let uses = rawHostUses(in: try String(contentsOf: url, encoding: .utf8))
        guard !uses.isEmpty else { continue }
        result[module + "/" + url.lastPathComponent] = uses
      }
    }
    return result
  }

  @Test func matcherSeesTheShownForms() {
    #expect(Self.rawHostUses(in: "let t = url.host() ?? url.absoluteString").count == 1)
    #expect(Self.rawHostUses(in: "let s = url?.host().map { $0 } ?? title").count == 1)
    #expect(Self.rawHostUses(in: "let h = url.host(percentEncoded: false) ?? \"\"").count == 1)
    #expect(Self.rawHostUses(in: ".init(card: card, tab: tab, host: snapshot.url?.host()))").count == 1)
    #expect(Self.rawHostUses(in: "let key = url.host() ?? \"\" // not shown").isEmpty)
    #expect(Self.rawHostUses(in: "return url.host() == \"newtab\"").isEmpty)
    #expect(Self.rawHostUses(in: "guard let host = url.host()?.lowercased() else { return false }").isEmpty)
    #expect(Self.rawHostUses(in: "let t = HostDisplay.hostOrAddress(url)").isEmpty)
  }

  @Test func sourcesAreFound() {
    for module in Self.scanned {
      #expect(FileManager.default.fileExists(atPath: Self.sources.appending(path: module).path))
    }
  }

  @Test func noHostIsShownRaw() throws {
    let offending = try Self.offendingLines()
    #expect(offending.isEmpty, "show a host through HostDisplay: \(offending)")
  }
}
