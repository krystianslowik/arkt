import Foundation

// Address-bar navigations (#784), modelled on Chromium as the facade drives it (arkt_engine_facade.mm, `loadURL:`):
// `navigateToURL:` loads with PAGE_TRANSITION_TYPED, `navigateFromAddressBarToURL:` adds FROM_ADDRESS_BAR. Recorded on
// out/Spike (week-3 results, "#784"):
//
// - The same URL as the page on screen: TYPED alone is converted to a reload (NavigationControllerImpl's
//   ShouldConvertToReload; the page sees navigation type "reload"). With FROM_ADDRESS_BAR it is a new navigation that
//   replaces the entry. The back list does not grow either way.
// - The history records every one of these visits with core type TYPED, the converted reload too, so the typed count
//   grows with either call. Only the FROM_ADDRESS_BAR qualifier on the visit tells them apart.
// - A browser debug URL: Chromium runs it only for FROM_ADDRESS_BAR (HandleDebugURL), and never navigates to it. The
//   facade drops FROM_ADDRESS_BAR for one unless the test API is on, so without it nothing happens.

/// One visit the profile's history records for a facade navigation. Only `navigate(to:)` and
/// `navigate(fromAddressBarTo:)` are recorded; the initial load of `createTab` is not.
struct ScriptedVisit: Equatable {
  let url: URL
  /// The FROM_ADDRESS_BAR qualifier.
  let fromAddressBar: Bool
  /// The load ran as a reload of the page on screen (a same-URL navigation without the qualifier).
  let ranAsReload: Bool
}

/// The profile's history as far as typed counting goes, and the browser debug URLs Chromium ran.
final class ScriptedHistory {
  private(set) var visits: [ScriptedVisit] = []
  private(set) var ranDebugURLs: [URL] = []

  /// HistoryBackend's typed count: every visit here has core type TYPED, so each one counts.
  func typedCount(of url: URL) -> Int { visits.filter { $0.url == url }.count }

  func record(_ visit: ScriptedVisit) { visits.append(visit) }
  func ran(_ url: URL) { ranDebugURLs.append(url) }

  /// The browser debug URLs of content's IsDebugURL and IsAsanDebugURL (chrome_debug_urls.h), as the facade lists them.
  static func isBrowserDebugURL(_ url: URL) -> Bool {
    guard url.scheme == "chrome", let host = url.host else { return false }
    if host == "crash" {
      let process = url.pathComponents.dropFirst().first
      return process == "browser" || process == "gpu"
    }
    let hosts: Set = ["inducebrowsercrashforrealz", "inducebrowserdcheckforrealz", "uithreadhang",
                      "delayeduithreadhang", "gpuclean", "gpucrash", "gpuhang", "memory-pressure-critical",
                      "memory-pressure-moderate"]
    return hosts.contains(host) && (url.path.isEmpty || url.path == "/")
  }
}
