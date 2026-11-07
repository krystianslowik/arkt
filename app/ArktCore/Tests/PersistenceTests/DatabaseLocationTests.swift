import Foundation
import Testing
@testable import Persistence

struct DatabaseLocationTests {
  /// The data folder carries the product name (#128). The engine's default user-data-dir lives under the same folder
  /// (`CrProductDirName` = `Arkt/Engine`, pinned by ShellKit's `ProductIdentityTests`).
  @Test func dataFolderIsNamedAfterTheProduct() throws {
    #expect(DatabaseLocation.productFolderName == "Arkt")
    let location = try DatabaseLocation.applicationSupport()
    #expect(location.directory.lastPathComponent == DatabaseLocation.productFolderName)
    #expect(location.directory.deletingLastPathComponent().lastPathComponent == "Application Support")
  }
}
