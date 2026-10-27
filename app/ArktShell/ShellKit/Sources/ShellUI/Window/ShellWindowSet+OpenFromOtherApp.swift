import Foundation

extension ShellWindowSet {
  /// Links and files another app opened with Arkt (it can be the default browser; FakeEngine builds, where the
  /// Chromium engine opens them itself). The primary window comes forward, or a new one opens when every window
  /// closed, even when no URL qualifies. Each web (`http`, `https`) or file URL then becomes a new Today tab in that
  /// window; any other scheme is ignored.
  public func openFromOtherApp(_ urls: [URL]) {
    let window = primary ?? openWindow()
    window.showWindow(nil)
    for url in urls where Self.opensFromOtherApp(url) {
      window.openFromOtherApp(url)
    }
  }

  static func opensFromOtherApp(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") || url.isFileURL
  }
}
