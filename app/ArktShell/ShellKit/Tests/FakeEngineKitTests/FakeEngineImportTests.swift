import ArcImport
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import FakeEngineKit

@MainActor
struct FakeEngineImportTests {
  @Test func keepsTheImportContract() async throws {
    try await EngineImportContract.run(FakeEngine())
  }

  @Test func keepsTheHistoryAndBookmarkContract() async throws {
    try await EngineImportContract.runHistory(FakeEngine())
    try await EngineImportContract.runBookmarks(FakeEngine())
  }

  @Test func recordsWhatItWroteBeforeZeroingIt() async {
    let engine = FakeEngine()
    _ = await engine.importCookies([EngineImportContract.cookie("a", value: "plain")])
    #expect(engine.imports.cookies.map(\.value) == ["plain"])
  }
}
