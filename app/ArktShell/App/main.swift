import AppKit

#if ARKT_CHROMIUM_SPIKE
// Spike configuration: Chromium owns NSApp and the run loop; never returns.
chromiumSpikeMain()
#else
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#endif
