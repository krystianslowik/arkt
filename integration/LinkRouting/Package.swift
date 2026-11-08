// swift-tools-version: 6.0
import PackageDescription

// A focused cross-boundary probe, not a ShellKit product or part of its CI test target.
let package = Package(
  name: "LinkRoutingIntegration",
  platforms: [.macOS(.v15)],
  dependencies: [.package(name: "ArktCore", path: "../../app/ArktCore")],
  targets: [
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["Motion"]),
    .target(name: "CoreBridge", dependencies: ["ShellUI", .product(name: "SidebarModel", package: "ArktCore")]),
    .testTarget(name: "LinkRoutingIntegrationTests", dependencies: [
      "CoreBridge", .product(name: "Persistence", package: "ArktCore"),
      .product(name: "SidebarModel", package: "ArktCore"),
    ]),
  ]
)
