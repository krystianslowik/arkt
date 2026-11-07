import EngineAPI
import Foundation

// MARK: - Rules 22 and 23 (#134, #114)

extension EngineContract {
  /// The word the find checks search for, and the text of the page's one link (`EngineHarness.findPage`).
  public static let findWord = "needle"
  public static let findLinkText = "jump"

  struct FindReply: Equatable {
    var requestID: Int
    var ordinal: Int
    var count: Int
    var isFinal: Bool
  }

  static func findReplies(_ recorder: EventRecorder, _ id: TabID) -> [FindReply] {
    recorder.events(for: id).compactMap {
      if case .findResult(_, let request, let ordinal, let count, let isFinal) = $0 {
        FindReply(requestID: request, ordinal: ordinal, count: count, isFinal: isFinal)
      } else {
        nil
      }
    }
  }

  /// Runs one `findInPage` and returns the first final reply it caused.
  static func search(_ engine: any EngineClient, _ recorder: EventRecorder, _ id: TabID, _ text: String,
                     forward: Bool = true, matchCase: Bool = false) async throws -> FindReply {
    let seen = findReplies(recorder, id).count
    engine.findInPage(id, text: text, forward: forward, matchCase: matchCase)
    try await wait("a final find reply for \"\(text)\"") {
      findReplies(recorder, id).dropFirst(seen).contains { $0.isFinal }
    }
    return try requireValue(findReplies(recorder, id).dropFirst(seen).first { $0.isFinal }, "final find reply")
  }

  static func requireReply(_ reply: FindReply, ordinal: Int, count: Int, _ what: String) throws {
    try require(reply.ordinal == ordinal && reply.count == count,
                "\(what): expected match \(ordinal) of \(count), got \(reply.ordinal) of \(reply.count)")
  }

  /// A new search reports the match count and the first match; the same search forward or backward moves the ordinal
  /// and wraps at the ends; a changed text or case starts over; `stopFinding` ends the session, so the next search
  /// starts at the first match again; empty text clears and is reported once; request ids never go back (#134).
  public static func findCountsMatchesAndMovesTheOrdinal(_ h: EngineHarness) async throws {
    let findPage = try driver(h.findPage, "findPage")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try findPage(3, try h.pageURL("Target")))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try require(findReplies(recorder, id).isEmpty, "nothing is searched yet: \(findReplies(recorder, id))")

    try requireReply(try await search(engine, recorder, id, findWord), ordinal: 1, count: 3, "a new search")
    try requireReply(try await search(engine, recorder, id, findWord), ordinal: 2, count: 3, "find next")
    engine.stopFinding(id, action: .clear)
    try requireReply(try await search(engine, recorder, id, findWord), ordinal: 1, count: 3,
                     "a search after stopFinding starts over")
    try requireReply(try await search(engine, recorder, id, findWord, forward: false), ordinal: 3, count: 3,
                     "find previous from the first match wraps to the last")
    try requireReply(try await search(engine, recorder, id, findWord, forward: false), ordinal: 2, count: 3,
                     "find previous")
    let upper = findWord.uppercased()
    try requireReply(try await search(engine, recorder, id, upper, matchCase: true), ordinal: 0, count: 0,
                     "match case finds no capitals")
    try requireReply(try await search(engine, recorder, id, upper), ordinal: 1, count: 3, "ignoring case")

    let ids = findReplies(recorder, id).map(\.requestID)
    try require(ids == ids.sorted(), "request ids must never go back: \(ids)")

    let seen = findReplies(recorder, id).count
    engine.findInPage(id, text: "", forward: true, matchCase: false)
    try await wait("the reply to empty text") { findReplies(recorder, id).count > seen }
    try await Task.sleep(for: .milliseconds(100))
    try require(findReplies(recorder, id).dropFirst(seen) == [FindReply(requestID: 0, ordinal: 0, count: 0, isFinal: true)],
                "empty text must be reported once as 0 of 0: \(findReplies(recorder, id).dropFirst(seen))")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  /// Polls the page's selection until it reads `expected`.
  static func selection(_ engine: any EngineClient, _ id: TabID, _ selectedText: EngineHarness.SelectedText,
                        becomes expected: String, _ what: String) async throws {
    let deadline = ContinuousClock.now + eventTimeout
    var text = try await selectedText(engine, id)
    while text != expected {
      if ContinuousClock.now > deadline {
        throw ContractViolation(description: "\(what) must leave \"\(expected)\" selected, got \"\(text)\"")
      }
      try await Task.sleep(for: .milliseconds(20))
      text = try await selectedText(engine, id)
    }
  }

  /// `stopFinding` keeps the active match as the page's selection with `.keep`, removes it with `.clear`, and clicks a
  /// matched link with `.activate`; it reports nothing (#134). Needs `selectedText`.
  public static func stopFindingKeepsClearsOrActivatesTheMatch(_ h: EngineHarness) async throws {
    let findPage = try driver(h.findPage, "findPage")
    let selectedText = try driver(h.selectedText, "selectedText")
    let engine = h.makeEngine()
    let target = try h.pageURL("Target")
    let id = engine.createTab(url: try findPage(2, target))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)

    _ = try await search(engine, recorder, id, findWord)
    engine.stopFinding(id, action: .keep)
    try await selection(engine, id, selectedText, becomes: findWord, "stopFinding(.keep)")

    _ = try await search(engine, recorder, id, findWord)
    engine.stopFinding(id, action: .clear)
    try await selection(engine, id, selectedText, becomes: "", "stopFinding(.clear)")

    let replies = findReplies(recorder, id).count
    _ = try await search(engine, recorder, id, findLinkText)
    engine.stopFinding(id, action: .activate)
    try await wait("the matched link to be followed") { engine.snapshot(of: id)?.url == target }
    try require(findReplies(recorder, id).dropFirst(replies).allSatisfy { $0.count == 1 },
                "the link text is found once: \(findReplies(recorder, id).dropFirst(replies))")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }

  static func targetURLs(_ recorder: EventRecorder, _ id: TabID) -> [URL?] {
    recorder.events(for: id).compactMap { if case .targetURLChanged(_, let url) = $0 { .some(url) } else { nil } }
  }

  /// A pointer over a link reports the link's URL once, leaving it reports nil once, and nothing is reported while
  /// the pointer stays where it is (#114). Needs `hoverLink` and `leaveLink`.
  public static func hoveredLinkReportsItsTargetURL(_ h: EngineHarness) async throws {
    let findPage = try driver(h.findPage, "findPage")
    let hover = try driver(h.hoverLink, "hoverLink")
    let leave = try driver(h.leaveLink, "leaveLink")
    let engine = h.makeEngine()
    let target = try h.pageURL("Target")
    let id = engine.createTab(url: try findPage(1, target))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try require(targetURLs(recorder, id).isEmpty, "no link is hovered yet: \(targetURLs(recorder, id))")

    try await hover(engine, id)
    try await wait("the hovered link's URL") { targetURLs(recorder, id).count == 1 }
    try require(targetURLs(recorder, id) == [target], "hover must report the link's URL: \(targetURLs(recorder, id))")
    try await leave(engine, id)
    try await wait("the end of the hover") { targetURLs(recorder, id).count == 2 }
    try require(targetURLs(recorder, id) == [target, nil], "leaving must report nil: \(targetURLs(recorder, id))")
    try await hover(engine, id)
    try await wait("the second hover") { targetURLs(recorder, id).count == 3 }
    // A redundant report would arrive by now (one batch after the change).
    try await Task.sleep(for: .milliseconds(100))
    try require(targetURLs(recorder, id) == [target, nil, target],
                "each change is reported once: \(targetURLs(recorder, id))")
    engine.closeTab(id, mode: .skipUnloadHandlers)
  }
}
