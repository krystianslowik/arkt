import Foundation
@main struct Probe {
  @MainActor static func main() {
    let name = "dev.arkt.probe.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let s = CommandBarSettings(defaults: defaults)
    var checks = 0
    func check(_ value: Bool) { precondition(value); checks += 1 }
    check(SearchEngine.allCases == [.google, .duckDuckGo])
    check(s.searchEngine == .google)
    var notifications = 0
    let token = s.observe { notifications += 1 }
    s.setSearchEngine(.google)
    check(notifications == 0)
    s.setSearchEngine(.duckDuckGo)
    s.setSearchEngine(.duckDuckGo)
    check(notifications == 1)
    check(CommandBarSettings(defaults: defaults).searchEngine == .duckDuckGo)
    for engine in SearchEngine.allCases {
      for query in ["  café 雪 &+=?#% /\n", "a+b", "x%20y", ""] {
        let url = URLInputParser.searchURL(for: query, engine: engine)
        check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == query)
        check(url.host() == (engine == .google ? "www.google.com" : "duckduckgo.com"))
      }
    }
    check(URLInputParser.searchURL(for: "a b&c").absoluteString == "https://www.google.com/search?q=a%20b%26c")
    s.resetSearchEngine()
    check(s.searchEngine == .google && notifications == 2)
    check(CommandBarSettings(defaults: defaults).searchEngine == .google)
    check(defaults.object(forKey: CommandBarSettings.searchEngineDefaultsKey) == nil)
    s.resetSearchEngine()
    check(notifications == 2)
    s.removeObserver(token)
    print("\(checks) checks passed")
  }
}
