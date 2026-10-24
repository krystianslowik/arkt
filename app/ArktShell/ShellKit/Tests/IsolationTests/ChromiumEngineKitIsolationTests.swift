import Foundation
import Testing

/// Layering gate for `ChromiumEngineKit` (week-3 plan, Task W3-6): only the engine app's composition root
/// (`app/ArktShell/App/Engine/`, compiled in the Engine configuration only) and the kit's own tests import it, and no
/// ShellKit target depends on it. ShellUI and CoreBridge know only `EngineAPI`. Reads source files only, like the
/// other isolation tests.
struct ChromiumEngineKitIsolationTests {
  static let module = "ChromiumEngineKit"
  static let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
  /// Directories, relative to app/ArktShell, whose Swift files may import the module.
  static let allowedDirectories = ["App/Engine", "ShellKit/Tests/ChromiumEngineKitTests"]
  /// Package targets that may depend on the module.
  static let allowedTargets: Set = ["ChromiumEngineKitTests"]
  /// The Engine configuration's compilation condition (project.yml).
  static let engineCondition = "#if ARKT_CHROMIUM_ENGINE"

  /// Every Swift file under app/ArktShell that imports the module, with its path relative to app/ArktShell.
  static func importers() throws -> [(path: String, source: String)] {
    let appRoot = WebKitIsolationTests.appRoot
    let files = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: [.isDirectoryKey]))
    let pattern = CoreIsolationTests.importPattern
    var found: [(String, String)] = []
    for case let url as URL in files {
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if isDirectory {
        if WebKitIsolationTests.isBuildDirectory(url.lastPathComponent) { files.skipDescendants() }
        continue
      }
      guard url.pathExtension == "swift", url.standardizedFileURL != thisFile else { continue }
      let source = try String(contentsOf: url, encoding: .utf8)
      guard CoreIsolationTests.importedModules(in: source, matching: pattern).contains(module) else { continue }
      let relative = url.standardizedFileURL.pathComponents.dropFirst(appRoot.standardizedFileURL.pathComponents.count)
      found.append((relative.joined(separator: "/"), source))
    }
    return found
  }

  static func isAllowed(_ relativePath: String) -> Bool {
    allowedDirectories.contains { relativePath.hasPrefix($0 + "/") }
  }

  @Test func allowlistMatchesWholeDirectories() {
    #expect(Self.isAllowed("App/Engine/EngineMain.swift"))
    #expect(Self.isAllowed("ShellKit/Tests/ChromiumEngineKitTests/ScriptedFacade.swift"))
    #expect(!Self.isAllowed("App/EngineExtras/X.swift"))
    #expect(!Self.isAllowed("App/AppDelegate.swift"))
    #expect(!Self.isAllowed("ShellKit/Sources/ShellUI/Window/ShellWindowController.swift"))
  }

  @Test func onlyTheEngineCompositionRootImportsTheKit() throws {
    let offenders = try Self.importers().map(\.path).filter { !Self.isAllowed($0) }
    #expect(offenders.isEmpty, "\(Self.module) imported outside \(Self.allowedDirectories): \(offenders)")
  }

  /// Guards against a vacuous pass: the engine entry point references the embedder class, so it imports the kit.
  @Test func scannerSeesTheEngineEntryPoint() throws {
    #expect(try Self.importers().contains { $0.path == "App/Engine/EngineMain.swift" })
  }

  /// App files are compiled into every configuration; only the Engine configuration may see the kit, so the Debug
  /// (FakeEngine) build stays free of engine code.
  @Test func appImportersAreEngineConfigurationOnly() throws {
    for importer in try Self.importers() where importer.path.hasPrefix("App/") {
      let firstCode = importer.source.split(separator: "\n").first { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.hasPrefix("//")
      }
      #expect(firstCode.map(String.init) == Self.engineCondition,
              "\(importer.path) must start with \(Self.engineCondition)")
    }
  }

  @Test func noShellKitTargetDependsOnTheKit() throws {
    let manifest = CoreIsolationTests.strippingLineComments(
      try String(contentsOf: WebKitIsolationTests.packageManifest, encoding: .utf8))
    let names = EngineABIIsolationTests.targetNames(in: manifest)
    #expect(names.contains(Self.module), "target \(Self.module) not found in Package.swift")
    var dependents: [String] = []
    for name in names {
      let declaration = try #require(WebKitIsolationTests.declaration("target", named: name, in: manifest)
        ?? WebKitIsolationTests.declaration("testTarget", named: name, in: manifest))
      if CoreIsolationTests.quotedDependencies(in: declaration).contains(Self.module) { dependents.append(name) }
    }
    #expect(Set(dependents) == Self.allowedTargets, "targets depending on \(Self.module): \(dependents.sorted())")
  }
}
