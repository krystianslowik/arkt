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
    // The engine app's composition root only (ChromiumEngineKitIsolationTests).
    .library(name: "ChromiumEngineKit", targets: ["ChromiumEngineKit"]),
    // The shared engine contract; the app links it for the Engine configuration's contract runner (W3-9).
    .library(name: "EngineAPITestSupport", targets: ["EngineAPITestSupport"]),
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
    // The engine facade header (engine/arkt/api/arkt_engine.h, a byte-identical copy): protocols and enums only, no
    // code. Only ChromiumEngineKit and its tests may depend on it (EngineABIIsolationTests).
    .target(name: "ArktEngineABI"),
    // ChromiumEngine (EngineClient, EngineExtensions) over the facade, and the typed ArktShellEmbedder (W3-6).
    .target(name: "ChromiumEngineKit", dependencies: ["EngineAPI", "ArktEngineABI"]),
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
    .testTarget(name: "ArktEngineABITests", dependencies: ["ArktEngineABI"]),
    // The shared contract against a scripted facade, no Chromium.
    .testTarget(
      name: "ChromiumEngineKitTests",
      dependencies: ["ChromiumEngineKit", "ArktEngineABI", "EngineAPI", "EngineAPITestSupport"]
    ),
    .testTarget(name: "FakeEngineKitTests", dependencies: ["FakeEngineKit"]),
    .testTarget(
      name: "CoreBridgeTests",
      dependencies: [
        "CoreBridge", "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
        .product(name: "CoreTestSupport", package: "ArktCore"),
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
