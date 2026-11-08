import Foundation

/// One result per input URL, in input order. Unresolved URLs can be retried by the composition root.
public enum ExternalLinkOpenResult: Equatable {
  case dispatched(URL)
  case ignored(URL)
  case unresolved(URL)
  case missingSpace(URL, UUID?)
}

extension ShellWindowSet {
  /// Dispatches qualifying URLs in order. Without a resolver, retains the historical primary-window behavior.
  @discardableResult
  public func openFromOtherApp(_ urls: [URL]) -> [ExternalLinkOpenResult] {
    guard let resolve = externalLinkDestination else {
      let window = primary ?? openWindow()
      window.showWindow(nil)
      return urls.map { url in
        guard Self.opensFromOtherApp(url) else { return .ignored(url) }
        window.openFromOtherApp(url)
        return .dispatched(url)
      }
    }
    return urls.map { url in
      guard Self.opensFromOtherApp(url) else { return .ignored(url) }
      guard let destination = resolve(url) else { return .unresolved(url) }
      switch destination {
      case .littleArkt:
        openLittleArkt(url: url)
      case .space(let id):
        guard sidebar.space(id) != nil else { return .missingSpace(url, id) }
        let window = externalLinkHost ?? openWindow(opensFirstTab: false)
        window.sidebarController.showSpace(id)
        guard window.currentSpace == id else { return .unresolved(url) }
        window.showWindow(nil)
        window.openFromOtherApp(url)
      case .mostRecentSpace:
        let host = externalLinkHost
        guard let id = host?.currentSpace ?? sidebar.spaceOrder.first, sidebar.space(id) != nil else {
          return .missingSpace(url, host?.currentSpace)
        }
        let window = host ?? openWindow(opensFirstTab: false)
        window.sidebarController.showSpace(id)
        guard window.currentSpace == id else { return .unresolved(url) }
        window.showWindow(nil)
        window.openFromOtherApp(url)
      }
      return .dispatched(url)
    }
  }

  static func opensFromOtherApp(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") || url.isFileURL
  }
}
