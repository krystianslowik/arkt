import AppKit

#if DEBUG
// Bundle metadata is independent of the launch environment. Refuse before migration or constructing the app.
let startupOverrides = EnvironmentOverrides(environment: ProcessInfo.processInfo.environment)
let uiTestRequired = Bundle.main.object(forInfoDictionaryKey: "ArktRequireUITestOverrides") as? String == "YES"
let startupViolations = startupOverrides.uiTestStartupViolations(
  required: uiTestRequired, bundleIdentifier: Bundle.main.bundleIdentifier
)
if !startupViolations.isEmpty {
  exit(64)
}
// Capture the effective environment before app settings can be composed.
let startupIdentity: TestIdentity.Request?
do {
  startupIdentity = try TestIdentity.request(environment: ProcessInfo.processInfo.environment,
                                             required: uiTestRequired, pid: ProcessInfo.processInfo.processIdentifier)
  #if ARKT_CHROMIUM_ENGINE
  // This barrier is implemented for the FakeEngine UI-test app only.
  if startupIdentity != nil { exit(64) }
  #endif
} catch {
  exit(64)
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
