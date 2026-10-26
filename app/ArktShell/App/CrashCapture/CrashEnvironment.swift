import Foundation

/// The facts a crash report keeps about the running build (#129): OS version, architecture, app version and build,
/// engine version. Read once; plain values, so the capture sources can use them from any thread.
struct CrashEnvironment: Sendable {
  var osVersion: String
  var architecture: String
  var appVersion: String
  var appBuild: String
  var engineVersion: String

  static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> CrashEnvironment {
    #if arch(arm64)
    let architecture = "arm64"
    #elseif arch(x86_64)
    let architecture = "x86_64"
    #else
    let architecture = "unknown"
    #endif
    let info = bundle.infoDictionary ?? [:]
    return CrashEnvironment(
      osVersion: processInfo.operatingSystemVersionString, architecture: architecture,
      appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBuild: info["CFBundleVersion"] as? String ?? "unknown",
      // Only the Engine configuration embeds the framework (project.yml); the stand-in engine has no version.
      engineVersion: info["ArktEngineFrameworkVersion"] as? String ?? "none")
  }
}
