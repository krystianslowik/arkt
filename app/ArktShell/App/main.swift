import AppKit

#if DEBUG
import OSLog

let startupLog = Logger(subsystem: "dev.arkt.ui-test-startup", category: "startup")
// Bundle metadata is independent of the launch environment. Refuse before migration or constructing the app.
let uiTestRequired = Bundle.main.object(forInfoDictionaryKey: "ArktRequireUITestOverrides") as? String == "YES"
let startupConfiguration: StartupConfiguration
do {
  startupConfiguration = try StartupConfiguration.resolve(
    arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment,
    required: uiTestRequired, bundleIdentifier: Bundle.main.bundleIdentifier)
} catch {
  startupLog.error("stage=carrier-rejected")
  exit(64)
}
let startupOverrides = EnvironmentOverrides(environment: startupConfiguration.environment)
let startupViolations = startupOverrides.uiTestStartupViolations(
  required: uiTestRequired, bundleIdentifier: Bundle.main.bundleIdentifier
)
if uiTestRequired || startupOverrides.isUITest {
  startupLog.notice("stage=validate required=\(uiTestRequired, privacy: .public) testFlag=\(startupOverrides.isUITest, privacy: .public)")
}
if !startupViolations.isEmpty {
  startupLog.error("stage=rejected missing=\(startupViolations.joined(separator: ","), privacy: .public)")
  exit(64)
}
// Capture the effective environment before app settings can be composed.
let startupIdentity: TestIdentity.Request?
do {
  startupIdentity = try TestIdentity.request(environment: startupConfiguration.environment,
                                             required: uiTestRequired, pid: ProcessInfo.processInfo.processIdentifier)
  #if ARKT_CHROMIUM_ENGINE
  // This barrier is implemented for the FakeEngine UI-test app only.
  if startupIdentity != nil { exit(64) }
  #endif
} catch {
  startupLog.error("stage=identity-request-rejected")
  exit(64)
}
if uiTestRequired || startupOverrides.isUITest {
  startupLog.notice("stage=validated identityEndpoint=\(startupIdentity != nil, privacy: .public)")
}
#endif

// Before anything reads a default: the delegate, the engine and the settings objects all start after this line.
AppEnvironment.migrateLegacyDefaults()

#if ARKT_CHROMIUM_ENGINE
// Engine configuration: Chromium owns NSApp and the run loop; never returns.
engineMain()
#else
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#endif
