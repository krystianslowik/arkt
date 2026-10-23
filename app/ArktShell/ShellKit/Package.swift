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
  ],
  targets: [
    .target(name: "EngineAPI"),
    .target(name: "EngineAPITestSupport", dependencies: ["EngineAPI"]),
    .target(name: "FakeEngineKit", dependencies: ["EngineAPI"]),
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["EngineAPI", "Motion"]),
    .testTarget(name: "EngineAPITests", dependencies: ["EngineAPI", "EngineAPITestSupport"]),
    .testTarget(name: "MotionTests", dependencies: ["Motion"]),
    .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "EngineAPITestSupport"]),
    .testTarget(name: "IsolationTests"),
    .testTarget(
      name: "ShellKitGUITests",
      dependencies: ["ShellUI", "FakeEngineKit", "EngineAPITestSupport", "Motion"]
    ),
  ]
)
