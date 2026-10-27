import ArcImport
import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing

@MainActor
struct InMemoryEngineImportTests {
  @Test func keepsTheImportContract() async throws {
    try await EngineImportContract.run(InMemoryEngine())
  }

  @Test func keepsTheHistoryAndBookmarkContract() async throws {
    try await EngineImportContract.runHistory(InMemoryEngine())
    try await EngineImportContract.runBookmarks(InMemoryEngine())
  }

  @Test func recordsVisitsWithTheirCoreTransitionAndFoldersWithTheirPath() async {
    let engine = InMemoryEngine()
    let entry = EngineImportContract.historyEntry("https://example.com/", title: "T", transitions: [.typed, .keyword])
    _ = await engine.importHistory([entry], after: nil)
    _ = await engine.importBookmarks([EngineImportContract.bookmark("B", url: "https://example.com/b", path: ["F"], guid: "ABC")])
    #expect(engine.imports.visits.map(\.transition) == [1, 9])
    #expect(engine.imports.visits.map(\.title) == ["T", "T"])
    #expect(engine.imports.bookmarks == [ImportedBookmarkRecord(folderPath: ["F"], title: "B", url: "https://example.com/b", guid: "abc")])
  }

  @Test func recordsWhatItWroteBeforeZeroingIt() async {
    let engine = InMemoryEngine()
    _ = await engine.importCookies([EngineImportContract.cookie("a", value: "plain", lastAccess: 10)])
    _ = await engine.importPasswords([EngineImportContract.login("https://example.com/", user: "u", password: "pw")])
    #expect(engine.imports.cookies == [
      ImportedCookieRecord(hostKey: ".example.com", name: "a", value: "plain", path: "/")])
    #expect(engine.imports.logins == [
      ImportedLoginRecord(signonRealm: "https://example.com/", username: "u", actionURL: nil, password: "pw")])
  }

  @Test func theNewestCookieReplacesTheOlderOneInTheRecording() async {
    let engine = InMemoryEngine()
    _ = await engine.importCookies([EngineImportContract.cookie("a", value: "old", lastAccess: 10)])
    _ = await engine.importCookies([EngineImportContract.cookie("a", value: "new", lastAccess: 20)])
    #expect(engine.imports.cookies.map(\.value) == ["new"])
  }
}
