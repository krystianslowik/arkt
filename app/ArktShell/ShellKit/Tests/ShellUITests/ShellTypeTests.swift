import AppKit
import Foundation
import Testing
@testable import ShellUI

/// The chrome's type roles (#621). The values are the ones the surfaces used before the roles existed, so a change
/// here is a visible change and needs screenshots.
struct ShellTypeTests {
  @Test func rolesArePinned() {
    #expect(ShellType.rowTitle == ShellTypeStyle(size: 13, weight: .medium))
    #expect(ShellType.body == ShellTypeStyle(size: 13, weight: .regular))
    #expect(ShellType.bodyEmphasis == ShellTypeStyle(size: 13, weight: .semibold))
    #expect(ShellType.caption == ShellTypeStyle(size: 12, weight: .regular))
    #expect(ShellType.captionEmphasis == ShellTypeStyle(size: 12, weight: .semibold))
    #expect(ShellType.chip == ShellTypeStyle(size: 12, weight: .medium))
    #expect(ShellType.hint == ShellTypeStyle(size: 11.5, weight: .regular))
    #expect(ShellType.footnote == ShellTypeStyle(size: 11, weight: .regular))
    #expect(ShellType.sectionHeader == ShellTypeStyle(size: 11, weight: .semibold))
    #expect(ShellType.dialogTitle == ShellTypeStyle(size: 15, weight: .semibold))
    #expect(ShellType.commandInput == ShellTypeStyle(size: 22, weight: .regular))
  }

  /// A role's font is the system font the surfaces built by hand before, descriptor for descriptor.
  @Test func roleFontsMatchTheCallsTheyReplaced() {
    #expect(ShellType.body.font == NSFont.systemFont(ofSize: 13))
    #expect(ShellType.caption.font == NSFont.systemFont(ofSize: 12))
    #expect(ShellType.hint.font == NSFont.systemFont(ofSize: 11.5))
    #expect(ShellType.commandInput.font == NSFont.systemFont(ofSize: 22))
    #expect(ShellType.footnote.font == NSFont.systemFont(ofSize: 11, weight: .regular))
    #expect(ShellType.rowTitle.font == NSFont.systemFont(ofSize: 13, weight: .medium))
    #expect(ShellType.bodyEmphasis.font == NSFont.systemFont(ofSize: 13, weight: .semibold))
    #expect(ShellType.captionEmphasis.font == NSFont.systemFont(ofSize: 12, weight: .semibold))
    #expect(ShellType.chip.font == NSFont.systemFont(ofSize: 12, weight: .medium))
    #expect(ShellType.sectionHeader.font == NSFont.systemFont(ofSize: 11, weight: .semibold))
    #expect(ShellType.dialogTitle.font == NSFont.systemFont(ofSize: 15, weight: .semibold))
    #expect(ShellType.body.font.pointSize == 13)
  }

  /// A style with another weight keeps the role's size (the Settings segment, the sidebar banner label).
  @Test func weightVariantKeepsTheSize() {
    let style = ShellType.caption.weight(.semibold)
    #expect(style == ShellType.captionEmphasis)
    #expect(style.font == NSFont.systemFont(ofSize: 12, weight: .semibold))
  }

  /// The sidebar keeps its own measured metrics (tab titles 14 medium, #186); the roles do not move them.
  @Test func sidebarKeepsItsMeasuredMetrics() {
    #expect(SidebarMetrics.titleFontSize == 14)
    #expect(SidebarMetrics.spaceTitleFontSize == 12)
    #expect(SidebarMetrics.urlBarFontSize == 13)
  }

  /// #623: the Toolbar URL has its own token; the sidebar URL bar keeps `SidebarMetrics.urlBarFontSize`.
  @Test @MainActor func toolbarURLHasItsOwnToken() {
    #expect(ShellType.toolbarURL == ShellTypeStyle(size: 13, weight: .medium))
    #expect(URLBarView.font(showsPill: false) == ShellType.toolbarURL.font)
    #expect(URLBarView.font(showsPill: true) == NSFont.systemFont(ofSize: SidebarMetrics.urlBarFontSize, weight: .medium))
    #expect(URLBarView(style: .full).label.font == ShellType.toolbarURL.font)
    #expect(URLBarView(style: .host).label.font == URLBarView.font(showsPill: true))
  }
}

/// A regression guard (#621): ShellUI builds a system font from a `ShellType` role or a named size, never from a
/// number written at the call. `monospacedDigitSystemFont` is outside this check.
struct SystemFontLintTests {
  /// app/ArktShell/ShellKit/Sources/ShellUI, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/ShellUITests/ShellTypeTests.swift
  static let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/ShellUI")

  static let pattern = #"systemFont\(ofSize:\s*[0-9.]"#
  /// Onboarding artwork: fixed-scale miniatures whose every size is part of the drawing, not chrome.
  static let exempt = ["Onboarding/OnboardingStage.swift", "Onboarding/OnboardingThemeViews.swift"]

  static func literalCalls(in source: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      let text = String(line)
      let range = NSRange(text.startIndex..., in: text)
      return regex.firstMatch(in: text, range: range) != nil ? text.trimmingCharacters(in: .whitespaces) : nil
    }
  }

  static func offendingLines() throws -> [String: [String]] {
    var result: [String: [String]] = [:]
    let prefix = root.path + "/"
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
    for case let url as URL in walker where url.pathExtension == "swift" {
      let path = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
      guard !exempt.contains(path) else { continue }
      let lines = literalCalls(in: try String(contentsOf: url, encoding: .utf8))
      guard !lines.isEmpty else { continue }
      result[path] = lines
    }
    return result
  }

  @Test func matcherSeesLiteralCalls() {
    #expect(Self.literalCalls(in: "label.font = .systemFont(ofSize: 13)").count == 1)
    #expect(Self.literalCalls(in: "NSFont.systemFont(ofSize: 11.5, weight: .medium)").count == 1)
    #expect(Self.literalCalls(in: ".systemFont(ofSize: 12 * capHeight / keycapHeight)").count == 1)
    #expect(Self.literalCalls(in: "label.font = ShellType.body.font").isEmpty)
    #expect(Self.literalCalls(in: ".systemFont(ofSize: SidebarMetrics.titleFontSize, weight: .medium)").isEmpty)
    #expect(Self.literalCalls(in: ".systemFont(ofSize: size, weight: weight)").isEmpty)
    #expect(Self.literalCalls(in: ".monospacedDigitSystemFont(ofSize: 12, weight: .regular)").isEmpty)
  }

  @Test func sourcesAreFound() {
    #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: "Theme/ShellType.swift").path))
    for path in Self.exempt {
      #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: path).path), "\(path)")
    }
  }

  @Test func noSystemFontSizeIsALiteral() throws {
    let offending = try Self.offendingLines()
    #expect(offending.isEmpty, "use a ShellType role or a named size: \(offending)")
  }
}
