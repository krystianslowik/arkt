// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ShellKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EngineAPI", targets: ["EngineAPI"]),
    .library(name: "FakeEngineKit", targets: ["FakeEngineKit"]),
    .library(name: "Motion", targets: ["Motion"]),
    .library(name: "ShellUI", targets: ["ShellUI"]),
    .library(name: "CoreBridge", targets: ["CoreBridge"]),
  ],
  dependencies: [
    // Local, relative: ShellKit lives in app/ArktShell/ShellKit, ArktCore in app/ArktCore. Only pure products are
    // used here; the app target alone links ArktCore's GRDB-backed product (see project.yml).
    .package(name: "ArktCore", path: "../../ArktCore"),
  ],
  targets: [
    .target(name: "EngineAPI"),
    .target(name: "EngineAPITestSupport", dependencies: ["EngineAPI"]),
    .target(name: "FakeEngineKit", dependencies: ["EngineAPI"]),
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["EngineAPI", "Motion"]),
    .target(
      name: "CoreBridge",
      dependencies: [
        "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
      ]
    ),
    .testTarget(name: "EngineAPITests", dependencies: ["EngineAPI", "EngineAPITestSupport"]),
    .testTarget(name: "MotionTests", dependencies: ["Motion"]),
    .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "EngineAPITestSupport"]),
    .testTarget(name: "IsolationTests"),
    .testTarget(name: "FakeEngineKitTests", dependencies: ["FakeEngineKit"]),
    .testTarget(
      name: "CoreBridgeTests",
      dependencies: [
        "CoreBridge", "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
      ],
      // Synthetic Arc files only (copies of ArktCore's ArcImportTests fixtures); never real Arc data.
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "ShellKitGUITests",
      dependencies: [
        "ShellUI", "FakeEngineKit", "EngineAPITestSupport", "Motion", "CoreBridge",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
      ]
    ),
  ]
)
