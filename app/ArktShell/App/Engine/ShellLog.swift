#if ARKT_CHROMIUM_ENGINE
import AppKit
import Darwin
import Foundation

// Log helpers of the Engine and Distribution shells (stderr, timestamped); also used by the stand-in shell.

nonisolated func shellLog(_ message: String) {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    let stamp = String(
        format: "%02d:%02d:%02d.%03d", local.tm_hour, local.tm_min, local.tm_sec,
        Int(now.tv_usec) / 1000)
    FileHandle.standardError.write(Data("[\(stamp)] ARKT engine shell: \(message)\n".utf8))
}

/// The main run loop's current mode, for logs ("none" outside any run loop).
@MainActor
func runLoopModeName() -> String {
    RunLoop.current.currentMode?.rawValue ?? "none"
}
#endif
