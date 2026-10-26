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

  // MARK: - Engine-only link (#268)

  /// Package products the app builds in every configuration but links only in the Engine configuration: their only
  /// importers are `App/Engine` files, so the Debug, Release and Profile binaries carry none of their code.
  static let engineOnlyProducts: Set = ["ChromiumEngineKit", "EngineAPITestSupport"]

  /// The `- package:` entries of project.yml with their product and whether they say `link: false`.
  static func packageDependencies(in spec: String) -> [(product: String, linked: Bool)] {
    let entries = spec.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
      .split { $0.hasPrefix("- ") && !$0.hasPrefix("- package:") }
    var found: [(String, Bool)] = []
    for lines in entries {
      var current: (product: String?, linked: Bool)?
      for line in lines {
        if line.hasPrefix("- package:") {
          if let product = current?.product { found.append((product, current?.linked ?? true)) }
          current = (nil, true)
        } else if current != nil, let value = Self.value(of: "product", in: line) {
          current?.product = value
        } else if current != nil, Self.value(of: "link", in: line) == "false" {
          current?.linked = false
        }
      }
      if let product = current?.product { found.append((product, current?.linked ?? true)) }
    }
    return found
  }

  /// The value of `key: value` on one YAML line, without a trailing comment.
  static func value(of key: String, in line: String) -> String? {
    guard line.hasPrefix(key + ":") else { return nil }
    let rest = line.dropFirst(key.count + 1)
    let value = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? rest
    return value.trimmingCharacters(in: .whitespaces)
  }

  /// Each `setting:` line of project.yml with the configuration key (`Engine:` and the like) it sits under.
  static func settingLines(_ setting: String, in spec: String) -> [(configuration: String?, value: String)] {
    var configuration: String?
    var found: [(String?, String)] = []
    for raw in spec.split(separator: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if let match = line.wholeMatch(of: #/(Debug|Release|Profile|Engine|base):/#) {
        configuration = String(match.output.1)
      } else if let value = Self.value(of: setting, in: line) {
        found.append((configuration, value))
      }
    }
    return found
  }

  @Test func packageDependenciesAreReadWithTheirLinkFlag() {
    let sample = """
      dependencies:
        - package: ShellKit
          product: ShellUI
        - package: ShellKit
          product: ChromiumEngineKit
          link: false   # Engine only
        - target: Other
      """
    let dependencies = Self.packageDependencies(in: sample)
    #expect(dependencies.map(\.product) == ["ShellUI", "ChromiumEngineKit"])
    #expect(dependencies.map(\.linked) == [true, false])
  }

  /// Debug, Release and Profile must not link the kit (#268): Xcode builds the product for the Engine configuration's
  /// compile, but only the Engine configuration's linker flags pull its object in.
  @Test func engineOnlyProductsAreNotLinkedByThePackageDependency() throws {
    let spec = try String(contentsOf: WebKitIsolationTests.projectSpec, encoding: .utf8)
    let dependencies = Self.packageDependencies(in: spec)
    let products = Set(dependencies.map(\.product))
    #expect(Self.engineOnlyProducts.isSubset(of: products), "project.yml dependencies: \(products.sorted())")
    let unlinked = Set(dependencies.filter { !$0.linked }.map(\.product))
    #expect(unlinked == Self.engineOnlyProducts, "products with link: false: \(unlinked.sorted())")
  }

  @Test func onlyTheEngineConfigurationLinksTheEngineOnlyObjects() throws {
    let spec = try String(contentsOf: WebKitIsolationTests.projectSpec, encoding: .utf8)
    let flags = Self.settingLines("OTHER_LDFLAGS", in: spec)
    for product in Self.engineOnlyProducts {
      let object = "$(BUILT_PRODUCTS_DIR)/\(product).o"
      let users = flags.filter { $0.value.contains(object) }
      #expect(users.count == 1 && users.first?.configuration == "Engine",
              "\(object) must be in exactly one OTHER_LDFLAGS, under Engine: \(users.map(\.configuration))")
    }
  }

  @Test func engineOnlyProductsAreImportedOnlyByEngineFiles() throws {
    let appRoot = WebKitIsolationTests.appRoot.appending(path: "App")
    let files = try #require(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
    let pattern = CoreIsolationTests.importPattern
    var offenders: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" {
      let source = try String(contentsOf: url, encoding: .utf8)
      let imported = Set(CoreIsolationTests.importedModules(in: source, matching: pattern))
      let relative = WebKitIsolationTests.relativeComponents(url).joined(separator: "/")
      if !imported.isDisjoint(with: Self.engineOnlyProducts), !Self.isAllowed(relative) { offenders.append(relative) }
    }
    #expect(offenders.isEmpty, "engine-only products imported outside App/Engine: \(offenders)")
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
