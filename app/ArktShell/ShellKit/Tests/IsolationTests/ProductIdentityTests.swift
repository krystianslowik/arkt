import Foundation
import Testing

/// The product identity (#73, #128): one bundle id prefix (`dev.arkt.*`) for the app, the engine framework and its
/// helpers, the product name on screen, and a product data folder that holds the engine's user-data-dir while the
/// development engine keeps its own. Reads the committed files only, like the other isolation tests.
struct ProductIdentityTests {
  static let repoRoot = EngineABIIsolationTests.repoRoot
  static let productBundleID = "dev.arkt.Arkt"

  static func text(_ path: String) throws -> String {
    try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
  }

  /// The value of `KEY=value` or `KEY = value` on its own line, else nil.
  static func setting(_ key: String, in source: String) -> String? {
    for line in source.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      if parts.count == 2, parts[0] == key { return parts[1] }
    }
    return nil
  }

  @Test func engineBrandingAndAppShareTheProductBundleID() throws {
    let branding = try Self.text("engine/arkt/branding/BRANDING")
    #expect(Self.setting("MAC_BUNDLE_ID", in: branding) == Self.productBundleID)
    let project = try Self.text("app/ArktShell/project.yml")
    let ids = project.split(whereSeparator: \.isNewline).compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return trimmed.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER:")
        ? trimmed.dropFirst("PRODUCT_BUNDLE_IDENTIFIER:".count).trimmingCharacters(in: .whitespaces) : nil
    }
    #expect(ids.contains(Self.productBundleID))
  }

  @Test func noPlaceholderBundleIDRemains() throws {
    for path in ["engine/arkt/branding/BRANDING", "app/ArktShell/project.yml", "app/ArktShell/Engine.xcconfig"] {
      let source = try Self.text(path)
      #expect(!source.contains("com.arkt"), "\(path) still names the placeholder com.arkt")
      #expect(!source.contains("dev.arkt.ArktShell\n"), "\(path) still names dev.arkt.ArktShell as the app id")
    }
  }

  @Test func appIsNamedArktOnScreen() throws {
    let project = try Self.text("app/ArktShell/project.yml")
    #expect(project.contains("CFBundleName: Arkt\n"))
    #expect(project.contains("CFBundleDisplayName: Arkt\n"))
    #expect(!project.contains("Arkt Shell"))
  }

  @Test func developmentEngineKeepsItsOwnFolderAndNoLiteralIsScripted() throws {
    let xcconfig = try Self.text("app/ArktShell/Engine.xcconfig")
    #expect(Self.setting("ARKT_PRODUCT_DIR_NAME", in: xcconfig) == "Arkt Dev Engine")
    let project = try Self.text("app/ArktShell/project.yml")
    #expect(project.contains("CrProductDirName -string \"$ARKT_PRODUCT_DIR_NAME\""))
  }

  @Test func productEngineFolderIsInsideTheProductDataFolder() throws {
    let readme = try Self.text("engine/README.md")
    #expect(readme.contains("ARKT_PRODUCT_DIR_NAME=Arkt/Engine"))
    let components = "Arkt/Engine".split(separator: "/")
    #expect(components.first == "Arkt")
  }
}
