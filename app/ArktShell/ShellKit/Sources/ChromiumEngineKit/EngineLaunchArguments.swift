import Foundation

/// The switches the shell adds to every engine launch unless the caller passed them.
///
/// - `--no-startup-window`: the shell creates the windows once it is ready, so Chromium opens none at startup and
///   restores no session (week-3 plan, Decision 2).
/// - `--disable-features=DestroyProfileOnBrowserClose`: Chromium unloads a profile when its last browser window
///   closes (on by default on macOS). The shell keeps running with no window (#241) and opens its first window
///   later, through a facade that holds the profile it was handed at start; an unloaded profile aborts there with
///   "Attempted to access a context that was ShutDown()" in `CreateBrowserWindow` (#469). Arkt has one profile and
///   Chromium's keep-alive holds the process, so the profile stays loaded until the process exits.
/// - `WebAuthenticationAmbientSignin`, `MediaRouter` (Cast and its remoting dialog) and `Glic` in the same list: their
///   Views UI looks for a `BrowserView`, which an Arkt window does not have. They stay off until the shell draws them
///   natively (engine connector design, batch E1).
/// - `HttpsFirstDialogUi` in the same list: with it on, an HTTPS-First fallback to HTTP asks through a tab-modal Views
///   dialog, whose `TabDialogManager` finds no host widget on an Arkt window and takes the browser process down at
///   `CHECK(host)` (#846). An HTTP-only site reached it on the engine build in a window of a fresh profile with default
///   settings, with "Always use secure connections" on, and in an off-the-record window. With it off, HTTPS-First
///   shows its full-page interstitial, which is web content in the tab (engine connector design, decision 6).
public enum EngineLaunchArguments {
  public static let noStartupWindow = "--no-startup-window"
  static let disableFeaturesPrefix = "--disable-features="
  static let requiredDisabledFeatures = [
    "DestroyProfileOnBrowserClose", "WebAuthenticationAmbientSignin", "MediaRouter", "Glic", "HttpsFirstDialogUi",
  ]

  /// Prefixes of the switches that exist for tests and engine-lane probes only (`--arkt-engine-contract`,
  /// `--arkt-engine-test-api`, `--arkt-reentrancy-probe`, `--arkt-embedder-fail`).
  static let testSwitchPrefixes = ["--arkt-"]

  /// `arguments` without the test switches: the Distribution app drops them before they reach the engine framework,
  /// so a shipped bundle never answers the engine test API (#334). Everything else is kept in order.
  public static func strippingTestSwitches(_ arguments: [String]) -> [String] {
    arguments.enumerated().filter { index, argument in
      index == 0 || !testSwitchPrefixes.contains { argument.hasPrefix($0) }
    }.map(\.element)
  }

  /// `arguments` (the executable first) with the switches above added; every other argument is kept as it is.
  public static func applying(to arguments: [String]) -> [String] {
    var result = arguments
    if !result.contains(noStartupWindow) { result.append(noStartupWindow) }
    // Chromium reads one `--disable-features` value, so an existing list is extended rather than repeated.
    if let index = result.lastIndex(where: { $0.hasPrefix(disableFeaturesPrefix) }) {
      var names = result[index].dropFirst(disableFeaturesPrefix.count).split(separator: ",").map(String.init)
      for feature in requiredDisabledFeatures where !names.contains(feature) { names.append(feature) }
      result[index] = disableFeaturesPrefix + names.joined(separator: ",")
    } else {
      result.append(disableFeaturesPrefix + requiredDisabledFeatures.joined(separator: ","))
    }
    return result
  }
}
