import AppKit

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
