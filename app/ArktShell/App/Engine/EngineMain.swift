#if ARKT_CHROMIUM_ENGINE
import ChromiumEngineKit
import Darwin
import Foundation

// Engine configuration (week-3 plan, Task W3-3): load the engine framework from
// Contents/Frameworks and hand the process to its ChromeMain, the way Chromium's
// own stub does (chrome/app/chrome_exe_main_mac.cc). Chromium creates NSApp
// itself ([BrowserCrApplication sharedApplication]) and owns the run loop, so
// nothing in this process may touch NSApplication before the call. The Swift UI
// starts later, from the engine's in-process hook, which finds ChromiumEngineKit's
// ArktShellEmbedder by name; the embedder then calls the delegate installed here.

private typealias ChromeMainFunction =
    @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

/// Switches every engine launch gets unless the caller passed them. The shell
/// creates the windows once it is ready, so Chromium opens none at startup and
/// restores no session (Decision 2).
private let engineSwitches = ["--no-startup-window"]

private func engineFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ARKT engine shell: \(message)\n".utf8))
    exit(1)
}

/// The framework's executable, from the two Info.plist keys the Engine build
/// phase writes from the framework itself (name and `Versions/Current`).
private func engineFrameworkPath() -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    guard let name = info["ArktEngineFrameworkName"] as? String,
        let version = info["ArktEngineFrameworkVersion"] as? String
    else {
        engineFail("Info.plist has no ArktEngineFrameworkName or ArktEngineFrameworkVersion")
    }
    guard let frameworks = Bundle.main.privateFrameworksPath else {
        engineFail("no private frameworks path")
    }
    return "\(frameworks)/\(name).framework/Versions/\(version)/\(name)"
}

@MainActor
func engineMain() -> Never {
    // The hook finds the embedder by name only (NSClassFromString). install
    // references the class, which keeps dead stripping from dropping it.
    ChromiumEmbedding.install(StandInShell.shared)

    let path = engineFrameworkPath()
    FileHandle.standardError.write(Data("ARKT engine shell: dlopen \(path)\n".utf8))
    guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST) else {
        engineFail("dlopen failed: \(String(cString: dlerror()))")
    }
    guard let symbol = dlsym(library, "ChromeMain") else {
        engineFail("dlsym ChromeMain failed: \(String(cString: dlerror()))")
    }
    let chromeMain = unsafeBitCast(symbol, to: ChromeMainFunction.self)

    var arguments = CommandLine.arguments
    for engineSwitch in engineSwitches where !arguments.contains(engineSwitch) {
        arguments.append(engineSwitch)
    }
    // Chromium keeps argv for the life of the process; the copies are never freed.
    let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: arguments.count + 1)
    for (index, argument) in arguments.enumerated() {
        argv[index] = strdup(argument)
    }
    argv[arguments.count] = nil

    let status = chromeMain(Int32(arguments.count), argv)
    // exit, not return, as the Chromium stub does.
    exit(status)
}
#endif
