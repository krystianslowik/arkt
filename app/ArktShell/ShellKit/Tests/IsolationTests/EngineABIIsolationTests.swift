import Foundation
import Testing

/// Layering gate for the engine facade header (week-3 plan, Task W3-2): only `ChromiumEngineKit`, its tests and the
/// header's own conformance tests may import `ArktEngineABI`, and the ShellKit copy of the header stays byte-identical
/// to the engine's. Reads source files only, like the other isolation tests; the target has no dependencies.
struct EngineABIIsolationTests {
  static let module = "ArktEngineABI"
  static let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
  static let kit = CoreIsolationTests.kit.standardizedFileURL
  /// The repository root: app/ArktShell/ShellKit/../../..
  static let repoRoot = kit.appending(path: "../../..").standardizedFileURL
  static let engineHeader = repoRoot.appending(path: "engine/arkt/api/arkt_engine.h")
  static let kitHeader = kit.appending(path: "Sources/ArktEngineABI/include/arkt_engine.h")

  /// Directories, relative to ShellKit, whose Swift files may import the module.
  static let allowedDirectories = ["Sources/ChromiumEngineKit", "Tests/ChromiumEngineKitTests", "Tests/ArktEngineABITests"]
  /// Package targets that may depend on the module.
  static let allowedTargets: Set = ["ChromiumEngineKit", "ChromiumEngineKitTests", "ArktEngineABITests"]

  /// Every Swift file under app/ArktShell that imports the module, as paths relative to ShellKit when inside it.
  static func importers() throws -> [String] {
    let appRoot = WebKitIsolationTests.appRoot
    let files = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: [.isDirectoryKey]))
    let pattern = CoreIsolationTests.importPattern
    var found: [String] = []
    for case let url as URL in files {
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDirectory {
        if WebKitIsolationTests.isBuildDirectory(url.lastPathComponent) { files.skipDescendants() }
        continue
      }
      guard url.pathExtension == "swift", url.standardizedFileURL != thisFile else { continue }
      let source = try String(contentsOf: url, encoding: .utf8)
      guard CoreIsolationTests.importedModules(in: source, matching: pattern).contains(module) else { continue }
      found.append(relativeToKit(url))
    }
    return found
  }

  static func relativeToKit(_ url: URL) -> String {
    let root = kit.pathComponents
    let all = url.standardizedFileURL.pathComponents
    guard all.starts(with: root) else { return url.path }
    return all.dropFirst(root.count).joined(separator: "/")
  }

  static func isAllowed(_ relativePath: String) -> Bool {
    allowedDirectories.contains { relativePath.hasPrefix($0 + "/") }
  }

  @Test func allowlistMatchesWholeDirectories() {
    #expect(Self.isAllowed("Sources/ChromiumEngineKit/ChromiumEngine.swift"))
    #expect(Self.isAllowed("Tests/ArktEngineABITests/ConformanceTests.swift"))
    #expect(!Self.isAllowed("Sources/ChromiumEngineKitExtras/X.swift"))
    #expect(!Self.isAllowed("Sources/ShellUI/X.swift"))
    #expect(!Self.isAllowed("../App/Engine/ArktShellEmbedder.swift"))
  }

  @Test func onlyChromiumEngineKitImportsTheModule() throws {
    let offenders = try Self.importers().filter { !Self.isAllowed($0) }
    #expect(offenders.isEmpty, "\(Self.module) imported outside \(Self.allowedDirectories): \(offenders)")
  }

  /// Guards against a vacuous pass: the conformance tests import the module, so the scanner sees real imports.
  @Test func scannerSeesTheConformanceTests() throws {
    #expect(try Self.importers().contains { $0.hasPrefix("Tests/ArktEngineABITests/") })
  }

  /// Names of every `.target` and `.testTarget` declared in `manifest`.
  static func targetNames(in manifest: String) -> [String] {
    manifest.matches(of: #/\.(?:target|testTarget)\(\s*name:\s*"([^"\n]+)"/#).map { String($0.output.1) }
  }

  @Test func onlyAllowedTargetsDependOnTheModule() throws {
    let manifest = CoreIsolationTests.strippingLineComments(
      try String(contentsOf: WebKitIsolationTests.packageManifest, encoding: .utf8))
    let names = Self.targetNames(in: manifest)
    #expect(names.contains(Self.module), "target \(Self.module) not found in Package.swift")
    var dependents: [String] = []
    for name in names {
      let declaration = try #require(WebKitIsolationTests.declaration("target", named: name, in: manifest)
        ?? WebKitIsolationTests.declaration("testTarget", named: name, in: manifest))
      if CoreIsolationTests.quotedDependencies(in: declaration).contains(Self.module) { dependents.append(name) }
    }
    #expect(dependents.contains("ArktEngineABITests"), "the conformance tests must depend on \(Self.module)")
    #expect(Set(dependents).isSubset(of: Self.allowedTargets),
            "\(Set(dependents).subtracting(Self.allowedTargets).sorted()) must not depend on \(Self.module)")
  }

  @Test func noProductOrAppTargetExposesTheModule() throws {
    let manifest = CoreIsolationTests.strippingLineComments(
      try String(contentsOf: WebKitIsolationTests.packageManifest, encoding: .utf8))
    let products = manifest.matches(of: #/\.library\([^)]*\)/#).map { String($0.output) }
    #expect(!products.isEmpty, "no products found in Package.swift")
    #expect(products.allSatisfy { !$0.contains(Self.module) }, "\(products)")
    #expect(!(try String(contentsOf: WebKitIsolationTests.projectSpec, encoding: .utf8)).contains(Self.module))
  }

  @Test func targetNamesAreReadFromBothKinds() {
    let sample = #"""
      .target(name: "A"),
      .testTarget(name: "B", dependencies: ["A"]),
      .library(name: "C", targets: ["A"]),
      """#
    #expect(Self.targetNames(in: sample) == ["A", "B"])
  }

  @Test func headerCopiesAreByteIdentical() throws {
    let engine = try Data(contentsOf: Self.engineHeader)
    let copy = try Data(contentsOf: Self.kitHeader)
    #expect(!engine.isEmpty)
    #expect(engine == copy, "\(Self.kitHeader.path) differs from \(Self.engineHeader.path)")
  }

  /// The plan's acceptance grep: no C++, no includes (only `#import` of Foundation and AppKit) and no classes.
  @Test func headerHasNoCxxIncludesOrClasses() throws {
    let header = try String(contentsOf: Self.engineHeader, encoding: .utf8)
    for banned in ["#include", "namespace", "std::", "template", "@interface", "@class", "@implementation"] {
      #expect(!header.contains(banned), "arkt_engine.h must not contain \(banned)")
    }
    let imports = header.matches(of: #/(?m)^#import\s+(\S+)/#).map { String($0.output.1) }
    #expect(imports == ["<AppKit/AppKit.h>", "<Foundation/Foundation.h>"], "\(imports)")
  }
}
