// swift-tools-version: 6.0
import PackageDescription

// Focused actual-source probe; the app has no test target.
let package = Package(
  name: "StartupPolicyProbe",
  platforms: [.macOS(.v15)],
  targets: [.testTarget(name: "StartupPolicyTests")]
)
