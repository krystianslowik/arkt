import Foundation
import Testing

/// ShellUI never calls the window-less `createTab(url:)`: with two windows a tab could land in the wrong engine
/// window (week-3 plan, "Interface boundary"). Every call names its window: `createTab(url:in:)`.
struct CreateTabLintTests {
  /// app/ArktShell/ShellKit/Sources/ShellUI, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/ShellUITests/CreateTabLintTests.swift
  static let shellUI = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/ShellUI")

  /// A `createTab(url: ...)` call whose argument list has no `in:` label. The argument may hold one level of
  /// parentheses (`createTab(url: URL(string: s))`).
  static let windowlessCall = #"createTab\(\s*url:(?:[^()]|\([^()]*\))*\)"#

  static func windowlessCalls(in source: String) -> [String] {
    let regex = try? NSRegularExpression(pattern: windowlessCall)
    let range = NSRange(source.startIndex..., in: source)
    return (regex?.matches(in: source, range: range) ?? []).compactMap { match in
      Range(match.range, in: source).map { String(source[$0]) }
    }.filter { !$0.contains(" in:") && !$0.contains(",in:") }
  }

  /// ShellUI source files with window-less calls, as paths relative to `Sources/ShellUI`.
  static func offendingFiles() throws -> [String: [String]] {
    let root = shellUI.path + "/"
    guard let walker = FileManager.default.enumerator(at: shellUI, includingPropertiesForKeys: nil) else {
      return [:]
    }
    var result: [String: [String]] = [:]
    for case let url as URL in walker where url.pathExtension == "swift" {
      let calls = windowlessCalls(in: try String(contentsOf: url, encoding: .utf8))
      guard !calls.isEmpty else { continue }
      result[url.standardizedFileURL.path.replacingOccurrences(of: root, with: "")] = calls
    }
    return result
  }

  @Test func matcherSeesOnlyTheWindowlessForm() {
    #expect(Self.windowlessCalls(in: "engine.createTab(url: url)") == ["createTab(url: url)"])
    #expect(Self.windowlessCalls(in: "engine.createTab(url: nil)").count == 1)
    #expect(Self.windowlessCalls(in: "engine.createTab(url: URL(string: s))").count == 1)
    #expect(Self.windowlessCalls(in: "engine.createTab(url: url, in: windowID)").isEmpty)
    #expect(Self.windowlessCalls(in: "engine.createTab(url: URL(string: s), in: window)").isEmpty)
    #expect(Self.windowlessCalls(in: "func createTabs(urls: [URL])").isEmpty)
  }

  @Test func shellUISourcesAreFound() throws {
    #expect(FileManager.default.fileExists(atPath: Self.shellUI.appending(path: "Window").path))
  }

  @Test func noWindowlessCreateTabCalls() throws {
    let offending = try Self.offendingFiles()
    #expect(offending.isEmpty, "use createTab(url:in:): \(offending)")
  }
}
