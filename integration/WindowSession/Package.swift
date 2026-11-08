// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WindowSessionProbe",
  platforms: [.macOS(.v15)],
  targets: [
    .target(name: "EngineAPI"),
    .target(name: "ShellUI", dependencies: ["EngineAPI"]),
    .testTarget(name: "SessionTests", dependencies: ["ShellUI", "EngineAPI"]),
  ]
)
