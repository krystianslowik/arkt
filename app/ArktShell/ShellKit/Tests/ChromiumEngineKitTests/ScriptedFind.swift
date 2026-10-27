import Foundation
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport

// Find in page and the hovered link on a scripted tab (#134, #114), modelled on what the facade gets from Chromium:
// `FindTabHelper::StartFinding` replies for a new search first with the matches found so far and then with the final
// count, and for the same search again (find next or previous) with the moved ordinal at once; `StopFinding` ends the
// session and reports nothing; empty text reports one 0-of-0 reply with request id 0. A page is a `findPageURL` page.

struct FindSession {
  var text: String
  var matchCase: Bool
  var ordinal: Int
  var match: String?
}

extension ScriptedTab {
  private var pageText: String? {
    guard let url, url.path == "/FindPage",
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
    let count = items.first { $0.name == "count" }?.value.flatMap(Int.init) ?? 0
    let words = Array(repeating: EngineContract.findWord, count: count)
    return (words + [EngineContract.findLinkText]).joined(separator: " filler ")
  }

  private var pageLink: URL? {
    guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
    return items.first { $0.name == "link" }?.value.flatMap(URL.init(string:))
  }

  private func found(_ text: String, matchCase: Bool) -> [String] {
    guard let page = pageText else { return [] }
    var matches: [String] = []
    var start = page.startIndex
    let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
    while start < page.endIndex, let range = page.range(of: text, options: options, range: start..<page.endIndex) {
      matches.append(String(page[range]))
      start = range.upperBound
    }
    return matches
  }

  private func reply(request: Int, ordinal: Int, count: Int, isFinal: Bool) {
    record(.findResult) {
      $0.findRequestId = request; $0.findOrdinal = ordinal; $0.findCount = count; $0.findIsFinal = isFinal
    }
  }

  func findInPage(text: String, forward: Bool, matchCase: Bool) {
    guard owner != nil else { return }
    guard !text.isEmpty else {
      findSession = nil
      pageSelection = ""
      reply(request: 0, ordinal: 0, count: 0, isFinal: true)
      return
    }
    let matches = found(text, matchCase: matchCase)
    var session: FindSession
    let isNew: Bool
    if let current = findSession, current.text == text, current.matchCase == matchCase {
      isNew = false
      session = current
      if matches.isEmpty {
        session.ordinal = 0
      } else {
        session.ordinal = forward ? current.ordinal % matches.count + 1
          : (current.ordinal + matches.count - 2) % matches.count + 1
      }
    } else {
      isNew = true
      session = FindSession(text: text, matchCase: matchCase, ordinal: matches.isEmpty ? 0 : 1)
    }
    session.match = session.ordinal > 0 ? matches[session.ordinal - 1] : nil
    findSession = session
    findRequests += 1
    if isNew, matches.count > 1 {
      // The renderer reports the matches found so far before the final count.
      reply(request: findRequests, ordinal: session.ordinal, count: 1, isFinal: false)
    }
    reply(request: findRequests, ordinal: session.ordinal, count: matches.count, isFinal: true)
  }

  func stopFinding(action: ArktFindAction) {
    guard owner != nil else { return }
    let match = findSession?.match
    findSession = nil
    switch action {
    case .clear:
      pageSelection = ""
    case .keep:
      pageSelection = match ?? ""
    case .activate:
      pageSelection = match ?? ""
      if let match, match.lowercased() == EngineContract.findLinkText, let link = pageLink { startLoad(link, title: nil) }
    @unknown default:
      break
    }
  }

  /// The pointer moves over the page's link, or leaves it (`UpdateTargetURL`).
  func hover(_ link: URL?) {
    guard owner != nil, hoveredLink != link else { return }
    hoveredLink = link
    record(.targetURLChanged) { $0.url = link }
  }

  /// A navigation ends the page's find and hover (Chromium clears the target URL when the document goes).
  func endFindAndHover() {
    findSession = nil
    if hoveredLink != nil { hover(nil) }
  }

  var linkOfPage: URL? { pageLink }
}
