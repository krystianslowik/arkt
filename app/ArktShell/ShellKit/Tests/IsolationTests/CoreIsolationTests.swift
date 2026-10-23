import Foundation
import Testing

/// Layering gate for Track E: GRDB (through Persistence) is linked only by the app target, and ShellUI never imports
/// an ArktCore module. Reads source files only, like `WebKitIsolationTests`; the target has no dependencies.
struct CoreIsolationTests {
  /// app/ArktShell/ShellKit, derived from this file's location:
  /// app/ArktShell/ShellKit/Tests/IsolationTests/CoreIsolationTests.swift
  static let kit = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  /// app/ArktCore/Package.swift, relative to the ShellKit package like its own `.package(path:)` dependency.
  static let coreManifest = kit.appendingPathComponent("../../ArktCore/Package.swift").standardizedFileURL

  /// Whole match plus the imported module name.
  typealias ImportRegex = Regex<(Substring, Substring)>

  /// Any import declaration, at line start or after `;`, modelled on `WebKitIsolationTests.importPattern`:
  /// optional attributes with arguments (`@preconcurrency`, `@_spi(X)`), an optional access level, an optional import
  /// kind (`class`, `struct`, ...), then the module name (the first component of `Module.Sub`).
  /// Computed, not stored: `Regex` is not `Sendable`, so a stored static would not be concurrency-safe.
  static var importPattern: ImportRegex {
    #/
      (?: ^ | ; ) \h*
      (?: @\w+ (?: \( [^)\n]* \) )? \s+ )*
      (?: (?: public | package | internal | fileprivate | private ) \s+ )?
      import \h+ (?: (?: typealias | struct | class | enum | protocol | let | var | func ) \h+ )?
      (\w+)
    /#.anchorsMatchLineEndings()
  }

  /// Module names of every import declaration in `source`.
  static func importedModules(in source: String, matching pattern: ImportRegex) -> [String] {
    source.matches(of: pattern).map { String($0.output.1) }
  }

  static func imports(under relative: String) throws -> [(file: String, module: String)] {
    let root = kit.appendingPathComponent(relative)
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
      return []
    }
    let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    let pattern = Self.importPattern
    return try files.flatMap { file in
      Self.importedModules(in: try String(contentsOf: file, encoding: .utf8), matching: pattern)
        .map { (file.lastPathComponent, $0) }
    }
  }

  @Test func matcherCatchesEveryImportForm() {
    let positives = [
      "import Persistence",
      "  import Persistence",
      "\timport Persistence // trailing",
      "@preconcurrency import Persistence",
      "@_exported import Persistence",
      "@testable import Persistence",
      "@_spi(Private) import Persistence",
      "@preconcurrency @_spi(X) import Persistence",
      "import class Persistence.ArchiveStore",
      "import Persistence.ArchiveStore",
      "import Foundation; import Persistence",
      "import AppKit\nimport Persistence\nimport os",
      "public import Persistence",
      "package import struct Persistence.SettingsStore",
      "@preconcurrency internal import Persistence",
      "private import Persistence",
    ]
    let pattern = Self.importPattern
    for sample in positives {
      #expect(Self.importedModules(in: sample, matching: pattern).contains("Persistence"), "should match: \(sample)")
    }
    // An import kind never swallows the next line's `import` keyword.
    #expect(Self.importedModules(in: "import AppKit\nimport Persistence\nimport os", matching: pattern)
      == ["AppKit", "Persistence", "os"])
    let negatives = [
      "import Foundation",
      "import PersistenceKit",
      "// import Persistence",
      "/// import Persistence",
      "let s = \"import Persistence\"",
      "#if canImport(Persistence)",
      "importPersistence",
      "public func importPersistence()",
    ]
    for sample in negatives {
      #expect(!Self.importedModules(in: sample, matching: pattern).contains("Persistence"),
              "should not match: \(sample)")
    }
  }

  @Test func noShellKitSourceImportsPersistenceOrGRDB() throws {
    let offenders = try Self.imports(under: "Sources").filter { ["Persistence", "GRDB"].contains($0.module) }
    #expect(offenders.isEmpty, "\(offenders)")
  }

  @Test func shellUIImportsNoArktCoreModule() throws {
    let banned: Set = ["SidebarModel", "Archive", "ArcImport", "Persistence", "GRDB"]
    let offenders = try Self.imports(under: "Sources/ShellUI").filter { banned.contains($0.module) }
    #expect(offenders.isEmpty, "\(offenders)")
  }

  /// Guards against a vacuous pass: CoreBridge must import SidebarModel, so the scanner sees real imports.
  @Test func scannerSeesCoreBridgeImports() throws {
    #expect(try Self.imports(under: "Sources/CoreBridge").contains { $0.module == "SidebarModel" })
  }

  /// `source` with every `//` line comment removed. A `//` starts a comment only at line start or after whitespace,
  /// so URLs such as `https://...` survive.
  static func strippingLineComments(_ source: String) -> String {
    source.replacing(#/(?:^|\h)\/\/[^\n]*/#.anchorsMatchLineEndings(), with: "")
  }

  /// The quoted names inside the `dependencies: [...]` list of `declaration` (empty when it has none).
  static func quotedDependencies(in declaration: String) -> [String] {
    guard let label = declaration.range(of: "dependencies:"),
          let open = declaration[label.upperBound...].firstIndex(of: "[") else { return [] }
    var depth = 0
    var index = open
    while index < declaration.endIndex {
      switch declaration[index] {
      case "[": depth += 1
      case "]":
        depth -= 1
        if depth == 0 {
          let list = declaration[open...index]
          return list.matches(of: #/"([^"\n]*)"/#).map { String($0.output.1) }
        }
      default: break
      }
      index = declaration.index(after: index)
    }
    return []
  }

  @Test func commentStripperKeepsURLs() {
    let sample = "// GRDB here\n  .package(url: \"https://example.com/x.git\") // and grdb here\nlet a = 1//tight"
    #expect(Self.strippingLineComments(sample) == "\n  .package(url: \"https://example.com/x.git\")\nlet a = 1//tight")
  }

  @Test func dependencyExtractorReadsOnlyTheDependencyList() {
    let declaration = #".target(name: "X", dependencies: ["A", .product(name: "P", package: "Q")], resources: [.copy("F")])"#
    #expect(Self.quotedDependencies(in: declaration) == ["A", "P", "Q"])
    #expect(Self.quotedDependencies(in: #".target(name: "X")"#).isEmpty)
  }

  /// Outside `//` comments, the manifest never mentions GRDB in any spelling.
  @Test func manifestNeverNamesPersistence() throws {
    let manifest = try String(contentsOf: Self.kit.appendingPathComponent("Package.swift"), encoding: .utf8)
    let code = Self.strippingLineComments(manifest)
    #expect(!code.contains("\"Persistence\""))
    #expect(!code.lowercased().contains("grdb"))
  }

  /// The pure ArktCore targets that CoreBridge and its tests link depend only on each other (allowlist), never on a product.
  @Test func pureCoreTargetsDependOnlyOnPureTargets() throws {
    let manifest = try String(contentsOf: Self.coreManifest, encoding: .utf8)
    let allowed: Set = ["SidebarModel", "Archive", "ArcImport"]
    for target in ["Archive", "ArcImport", "SidebarModel", "CoreTestSupport"] {
      let declaration = try #require(WebKitIsolationTests.declaration("target", named: target, in: manifest),
                                     "target \(target) not found in \(Self.coreManifest.path)")
      #expect(!declaration.contains(".product("), "\(target) must not depend on a package product")
      let dependencies = Set(Self.quotedDependencies(in: declaration))
      #expect(dependencies.isSubset(of: allowed), "\(target) depends on \(dependencies.subtracting(allowed).sorted())")
    }
  }
}
