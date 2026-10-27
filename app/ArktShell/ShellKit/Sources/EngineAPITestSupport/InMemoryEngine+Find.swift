import EngineAPI
import Foundation

// Find in page and link hover for the in-memory engine (contract rules 22, 23, #134, #114). A page is described by its
// URL: `findPageURL` builds one whose text is `occurrences` copies of `EngineContract.findWord` and one link.

struct FindSession {
  var text: String
  var matchCase: Bool
  var ordinal: Int
  var count: Int
  /// The page text of the active match, nil when there is none.
  var match: String?
}

extension InMemoryEngine {
  /// A page with `occurrences` copies of the find word and one link to `link`, with the text `EngineContract.findLinkText`.
  public static func findPageURL(occurrences: Int, link: URL) -> URL {
    var components = URLComponents(string: "arkt-test://page.test/FindPage")!
    components.queryItems = [URLQueryItem(name: "count", value: String(occurrences)),
                             URLQueryItem(name: "link", value: link.absoluteString)]
    return components.url!
  }

  private struct Page {
    var text: String
    var link: URL?
  }

  private func page(of id: TabID) -> Page? {
    guard let url = snapshots[id]?.url, url.path == "/FindPage",
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
    let count = items.first { $0.name == "count" }?.value.flatMap(Int.init) ?? 0
    let link = items.first { $0.name == "link" }?.value.flatMap(URL.init(string:))
    let words = Array(repeating: EngineContract.findWord, count: count)
    return Page(text: (words + [EngineContract.findLinkText]).joined(separator: " filler "), link: link)
  }

  private func matches(_ text: String, in page: String, matchCase: Bool) -> [String] {
    var found: [String] = []
    var start = page.startIndex
    let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
    while start < page.endIndex, let range = page.range(of: text, options: options, range: start..<page.endIndex) {
      found.append(String(page[range]))
      start = range.upperBound
    }
    return found
  }

  public func findInPage(_ id: TabID, text: String, forward: Bool, matchCase: Bool) {
    guard snapshots[id] != nil else { return }
    findRequestCounter += 1
    guard !text.isEmpty else {
      finds[id] = nil
      pageSelections[id] = ""
      hub.emit(.findResult(id, requestID: 0, ordinal: 0, count: 0, isFinal: true))
      return
    }
    let found = page(of: id).map { matches(text, in: $0.text, matchCase: matchCase) } ?? []
    var session: FindSession
    if let current = finds[id], current.text == text, current.matchCase == matchCase {
      // The same search again: the next or previous match, wrapping at the ends.
      session = current
      session.count = found.count
      if found.isEmpty {
        session.ordinal = 0
      } else {
        session.ordinal = forward ? current.ordinal % found.count + 1 : (current.ordinal + found.count - 2) % found.count + 1
      }
    } else {
      session = FindSession(text: text, matchCase: matchCase, ordinal: found.isEmpty ? 0 : 1, count: found.count)
    }
    session.match = session.ordinal > 0 ? found[session.ordinal - 1] : nil
    finds[id] = session
    hub.emit(.findResult(id, requestID: findRequestCounter, ordinal: session.ordinal, count: found.count, isFinal: true))
  }

  public func stopFinding(_ id: TabID, action: FindStopAction) {
    guard snapshots[id] != nil else { return }
    let match = finds[id]?.match
    finds[id] = nil
    switch action {
    case .clear:
      pageSelections[id] = ""
    case .keep:
      pageSelections[id] = match ?? ""
    case .activate:
      pageSelections[id] = match ?? ""
      if let match, match.lowercased() == EngineContract.findLinkText, let link = page(of: id)?.link {
        navigate(id, to: link)
      }
    }
  }

  /// Test driver: the page's selection (`window.getSelection().toString()`).
  public func selectedText(_ id: TabID) throws -> String {
    guard snapshots[id] != nil else { throw FindDriverError(description: "no tab \(id)") }
    return pageSelections[id] ?? ""
  }

  /// Test driver: the pointer moves over the page's link.
  public func hoverLink(_ id: TabID) throws {
    guard let link = page(of: id)?.link else { throw FindDriverError(description: "no link in \(id)") }
    guard hoveredLinks[id] != link else { return }
    hoveredLinks[id] = link
    hub.emit(.targetURLChanged(id, link))
  }

  /// Test driver: the pointer leaves the page's link.
  public func leaveLink(_ id: TabID) throws {
    guard snapshots[id] != nil else { throw FindDriverError(description: "no tab \(id)") }
    guard hoveredLinks.removeValue(forKey: id) != nil else { return }
    hub.emit(.targetURLChanged(id, nil))
  }

  func endFindAndHover(of id: TabID) {
    finds[id] = nil
    if hoveredLinks.removeValue(forKey: id) != nil { hub.emit(.targetURLChanged(id, nil)) }
  }

  struct FindDriverError: Error, CustomStringConvertible {
    let description: String
  }
}
