// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ArktCore",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SidebarModel", targets: ["SidebarModel"]),
    .library(name: "ArcImport", targets: ["ArcImport"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "Archive", targets: ["Archive"]),
  ],
  dependencies: [
    // Exact pin: the on-disk format is user data. Upgrade only in a dedicated, reviewed commit.
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
  ],
  targets: [
    .target(name: "SidebarModel"),
    .target(name: "ArcImport", dependencies: ["SidebarModel", "Archive"]),
    .target(
      name: "Persistence",
      dependencies: ["SidebarModel", "Archive", .product(name: "GRDB", package: "GRDB.swift")]
    ),
    .target(name: "Archive", dependencies: ["SidebarModel"]),
    .executableTarget(name: "arkt-import-check", dependencies: ["ArcImport"]),
    .testTarget(name: "SidebarModelTests", dependencies: ["SidebarModel"], resources: [.copy("Fixtures")]),
    .testTarget(
      name: "ArcImportTests",
      dependencies: ["ArcImport", "SidebarModel", "Archive"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "PersistenceTests",
      dependencies: ["Persistence", "SidebarModel", "Archive", .product(name: "GRDB", package: "GRDB.swift")]
    ),
    .testTarget(name: "ArchiveTests", dependencies: ["Archive", "SidebarModel"]),
  ]
)
