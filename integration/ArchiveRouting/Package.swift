// swift-tools-version: 6.0
import PackageDescription

// Headless actual-source archive integration; no App, GUI or Persistence target.
let package = Package(
  name: "ArchiveRoutingIntegration",
  platforms: [.macOS(.v15)],
  dependencies: [.package(name: "ArktCore", path: "../../app/ArktCore")],
  targets: [
    .target(name: "Motion"),
    .target(name: "ShellUI", dependencies: ["Motion"]),
    .target(name: "CoreBridge", dependencies: ["ShellUI",
      .product(name: "SidebarModel", package: "ArktCore"), .product(name: "Archive", package: "ArktCore")]),
    .testTarget(name: "ArchiveRoutingTests", dependencies: ["CoreBridge", "ShellUI",
      .product(name: "SidebarModel", package: "ArktCore"), .product(name: "Archive", package: "ArktCore")]),
  ]
)
