import Foundation
import Testing

struct WebKitIsolationTests {
  /// app/ArktShell, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/IsolationTests/WebKitIsolationTests.swift
  static let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
  static let appRoot = thisFile
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  static let packageManifest = appRoot.appending(path: "ShellKit/Package.swift")
  static let projectSpec = appRoot.appending(path: "project.yml")

  /// Path components, relative to `appRoot`, of the one file allowed to import WebKit.
  static let allowed = ["ShellKit", "Sources", "FakeEngineKit", "FakeEngine.swift"]

  /// Directories whose contents are build output, never source.
  static func isBuildDirectory(_ name: String) -> Bool {
    ["build", ".build", "DerivedData"].contains(name) || name.hasSuffix(".xcodeproj")
  }

  /// Any import declaration of WebKit or a WebKit submodule, at line start or after `;`:
  /// optional attributes (`@preconcurrency`, `@_exported`, `@_spi(X)`), an optional access level
  /// (`public import`, SE-0409), an optional import kind (`class`, `struct`, `func`, ...), then
  /// `WebKit` as a whole module name (`WebKit.Sub` matches, `WebKitLegacy` does not).
  static let importPattern =
    #"(?m)(^|;)[ \t]*(@\w+(\([^)\n]*\))?\s+)*((public|package|internal|fileprivate|private)\s+)?import\s+(\w+\s+)?WebKit\b"#

  static func importsWebKit(_ source: String) -> Bool {
    source.range(of: importPattern, options: .regularExpression) != nil
  }

  static func relativeComponents(_ url: URL) -> [String] {
    let root = appRoot.standardizedFileURL.pathComponents
    let all = url.standardizedFileURL.pathComponents
    guard all.starts(with: root) else { return all }
    return Array(all.dropFirst(root.count))
  }

  @Test func matcherCatchesEveryImportForm() {
    let positives = [
      "import WebKit",
      "  import WebKit",
      "\timport WebKit // trailing",
      "@preconcurrency import WebKit",
      "@_exported import WebKit",
      "@testable import WebKit",
      "@_spi(Private) import WebKit",
      "@preconcurrency @_exported import WebKit",
      "import class WebKit.WKWebView",
      "import struct WebKit.WKPDFConfiguration",
      "import WebKit.WKWebView",
      "import Foundation; import WebKit",
      "import AppKit\nimport WebKit\nimport os",
      "public import WebKit",
      "internal import WebKit",
      "package import class WebKit.WKWebView",
      "@preconcurrency public import WebKit",
      "private import WebKit",
    ]
    for sample in positives {
      #expect(Self.importsWebKit(sample), "should match: \(sample)")
    }
    let negatives = [
      "import Foundation",
      "import WebKitLegacy",
      "// import WebKit",
      "/// import WebKit",
      "let s = \"import WebKit\"",
      "#if canImport(WebKit)",
      "import EngineAPI",
      "importWebKit",
      "public import Foundation",
      "public func importWebKit()",
    ]
    for sample in negatives {
      #expect(!Self.importsWebKit(sample), "should not match: \(sample)")
    }
  }

  @Test func buildDirectoriesAreRecognizedByName() {
    #expect(Self.isBuildDirectory("build"))
    #expect(Self.isBuildDirectory(".build"))
    #expect(Self.isBuildDirectory("DerivedData"))
    #expect(Self.isBuildDirectory("ArktShell.xcodeproj"))
    #expect(!Self.isBuildDirectory("rebuild"))
    #expect(!Self.isBuildDirectory("Sources"))
    #expect(!Self.isBuildDirectory("buildTools"))
  }

  @Test func onlyFakeEngineImportsWebKit() throws {
    let files = try #require(FileManager.default.enumerator(
      at: Self.appRoot, includingPropertiesForKeys: [.isDirectoryKey]))
    var offenders: [String] = []
    var allowedFileImports = false
    var scanned = 0
    for case let url as URL in files {
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDirectory {
        if Self.isBuildDirectory(url.lastPathComponent) { files.skipDescendants() }
        continue
      }
      guard url.pathExtension == "swift", url.standardizedFileURL != Self.thisFile else { continue }
      scanned += 1
      let text = try String(contentsOf: url, encoding: .utf8)
      guard Self.importsWebKit(text) else { continue }
      if Self.relativeComponents(url) == Self.allowed { allowedFileImports = true } else { offenders.append(url.path) }
    }
    #expect(scanned > 1, "scan found no Swift sources under \(Self.appRoot.path)")
    #expect(offenders.isEmpty, "WebKit imported outside FakeEngine.swift: \(offenders)")
    #expect(allowedFileImports, "FakeEngine.swift should be the one WebKit importer")
  }

  @Test func fakeEngineDoesNotReexportWebKit() throws {
    let url = Self.appRoot.appending(path: Self.allowed.joined(separator: "/"))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains("@_exported"), "FakeEngine.swift must not re-export anything")
    // An internal import makes the compiler reject any WebKit type in FakeEngine's public API.
    #expect(text.range(of: #"(?m)^internal import WebKit$"#, options: .regularExpression) != nil,
            "FakeEngine.swift must use `internal import WebKit`")
  }

  @Test func appProjectDoesNotMentionWebKit() throws {
    #expect(!(try String(contentsOf: Self.projectSpec, encoding: .utf8)).contains("WebKit"))
  }

  /// Returns the text of the first `.<kind>(name: "<name>" ...)` call in a manifest, parentheses balanced.
  static func declaration(_ kind: String, named name: String, in manifest: String) -> String? {
    let pattern = #"\.\#(kind)\(\s*name:\s*"\#(name)""#
    guard let start = manifest.range(of: pattern, options: .regularExpression) else { return nil }
    var depth = 0
    var index = manifest.index(after: start.lowerBound)  // skip the leading "."
    while index < manifest.endIndex {
      switch manifest[index] {
      case "(": depth += 1
      case ")":
        depth -= 1
        if depth == 0 { return String(manifest[start.lowerBound...index]) }
      default: break
      }
      index = manifest.index(after: index)
    }
    return nil
  }

  @Test func declarationExtractorBalancesParentheses() {
    let sample = """
      .target(name: "A", dependencies: [.product(name: "X", package: "p")]),
      .target(name: "B", dependencies: ["A"]),
      """
    #expect(Self.declaration("target", named: "A", in: sample)
      == #".target(name: "A", dependencies: [.product(name: "X", package: "p")])"#)
    #expect(Self.declaration("target", named: "B", in: sample) == #".target(name: "B", dependencies: ["A"])"#)
    #expect(Self.declaration("target", named: "C", in: sample) == nil)
  }

  @Test func manifestKeepsWebKitOutOfShellUI() throws {
    let manifest = try String(contentsOf: Self.packageManifest, encoding: .utf8)
    #expect(manifest.range(of: #"linkedFramework\(\s*"WebKit""#, options: .regularExpression) == nil,
            "Package.swift must not link WebKit explicitly")
    for target in ["ShellUI", "EngineAPI", "Motion"] {
      let declaration = try #require(Self.declaration("target", named: target, in: manifest),
                                     "target \(target) not found in Package.swift")
      #expect(!declaration.contains("FakeEngineKit"), "\(target) must not depend on FakeEngineKit")
    }
    let product = try #require(Self.declaration("library", named: "ShellUI", in: manifest))
    #expect(!product.contains("FakeEngineKit"), "the ShellUI product must not bundle FakeEngineKit")
  }
}
