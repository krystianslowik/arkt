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
    // Local crash reports (#129): Foundation only; the app target links it, ShellUI never does.
    .library(name: "CrashReporting", targets: ["CrashReporting"]),
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
    // EngineAPI names the Arc import readers' records (ArcCookie, ArcLogin, SecretBytes) in EngineImporting (#512).
    .target(name: "EngineAPI", dependencies: [.product(name: "ArcImport", package: "ArktCore")]),
    .target(name: "EngineAPITestSupport", dependencies: ["EngineAPI", .product(name: "ArcImport", package: "ArktCore")]),
    .target(name: "FakeEngineKit", dependencies: ["EngineAPI", .product(name: "ArcImport", package: "ArktCore")]),
    .target(name: "Motion"),
    // The report model, stripping, local store, consent policy and the GitHub hand-off. No dependencies at all.
    .target(name: "CrashReporting"),
    // The engine facade header (engine/arkt/api/arkt_engine.h, a byte-identical copy): protocols and enums only, no
    // code. Only ChromiumEngineKit and its tests may depend on it (EngineABIIsolationTests).
    .target(name: "ArktEngineABI"),
    // ChromiumEngine (EngineClient, EngineExtensions) over the facade, and the typed ArktShellEmbedder (W3-6).
    .target(name: "ChromiumEngineKit", dependencies: ["EngineAPI", "ArktEngineABI", .product(name: "ArcImport", package: "ArktCore")]),
    // The mark artwork (design/brand/logos/01-mustard-on-white.png, byte-identical) for the first run's stage.
    .target(name: "ShellUI", dependencies: ["EngineAPI", "Motion"],
            resources: [.copy("Resources/01-mustard-on-white.png")]),
    .target(
      name: "CoreBridge",
      dependencies: [
        "ShellUI",
        .product(name: "SidebarModel", package: "ArktCore"),
        .product(name: "Archive", package: "ArktCore"),
        .product(name: "ArcImport", package: "ArktCore"),
      ]
    ),
    .testTarget(name: "EngineAPITests", dependencies: ["EngineAPI", "EngineAPITestSupport", .product(name: "ArcImport", package: "ArktCore")]),
    .testTarget(name: "MotionTests", dependencies: ["Motion"]),
    .testTarget(name: "CrashReportingTests", dependencies: ["CrashReporting"]),
    .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "EngineAPITestSupport"]),
    .testTarget(name: "IsolationTests"),
    .testTarget(name: "ArktEngineABITests", dependencies: ["ArktEngineABI"]),
    // The shared contract against a scripted facade, no Chromium.
    .testTarget(
      name: "ChromiumEngineKitTests",
      dependencies: ["ChromiumEngineKit", "ArktEngineABI", "EngineAPI", "EngineAPITestSupport", .product(name: "ArcImport", package: "ArktCore")]
    ),
    .testTarget(name: "FakeEngineKitTests", dependencies: ["FakeEngineKit", "EngineAPI", "EngineAPITestSupport", .product(name: "ArcImport", package: "ArktCore")]),
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
