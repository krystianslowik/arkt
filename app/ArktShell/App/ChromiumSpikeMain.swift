#if ARKT_CHROMIUM_SPIKE
import Darwin
import Foundation

// Embedding spike (engine week 2, Task WE): load the Chromium framework from
// Contents/Frameworks and hand the process to ChromeMain, the way Chromium's own
// stub does (chrome/app/chrome_exe_main_mac.cc). Chromium creates NSApp itself
// ([BrowserCrApplication sharedApplication]) and owns the run loop, so nothing in
// this process may touch NSApplication before this call.

private let spikeFrameworkName = "Chromium Framework"
private let spikeFrameworkVersion = "156.0.8078.48"

private typealias ChromeMainFunction =
    @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

private func spikeFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ARKT spike: \(message)\n".utf8))
    exit(1)
}

func chromiumSpikeMain() -> Never {
    guard let frameworks = Bundle.main.privateFrameworksPath else {
        spikeFail("no private frameworks path")
    }
    let path = "\(frameworks)/\(spikeFrameworkName).framework/Versions/"
        + "\(spikeFrameworkVersion)/\(spikeFrameworkName)"
    FileHandle.standardError.write(Data("ARKT spike: dlopen \(path)\n".utf8))

    guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST) else {
        spikeFail("dlopen failed: \(String(cString: dlerror()))")
    }
    guard let symbol = dlsym(library, "ChromeMain") else {
        spikeFail("dlsym ChromeMain failed: \(String(cString: dlerror()))")
    }
    let chromeMain = unsafeBitCast(symbol, to: ChromeMainFunction.self)
    // W3-0a probe (ChromiumSpikeProbe.swift): keep the class from dead stripping and
    // schedule main-actor and main-queue work that only Chromium's run loop can drain.
    _ = ArktShellEmbedderProbe.self
    startMainActorProbe()
    let status = chromeMain(CommandLine.argc, CommandLine.unsafeArgv)
    // exit, not return, as the Chromium stub does.
    exit(status)
}
#endif
