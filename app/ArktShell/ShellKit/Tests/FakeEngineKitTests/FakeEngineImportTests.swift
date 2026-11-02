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

  @Test func keepsTheExtensionContract() async throws {
    try await EngineImportContract.runExtensions(FakeEngine())
  }

  @Test func reportsAnUnavailableExtensionAndKeepsGoing() async {
    let engine = FakeEngine()
    let missing = String(repeating: "d", count: 32), present = String(repeating: "e", count: 32)
    engine.unavailableExtensionIDs = [missing]
    let results = await engine.installExtensionResults(ids: [missing, present])
    #expect(results == [
      ExtensionInstallResult(id: missing, outcome: .failed("not available from the Web Store")),
      ExtensionInstallResult(id: present, outcome: .installed),
    ])
    #expect(engine.imports.extensionIDs == [present])
  }

  @Test func recordsWhatItWroteBeforeZeroingIt() async {
    let engine = FakeEngine()
    _ = await engine.importCookies([EngineImportContract.cookie("a", value: "plain")])
    #expect(engine.imports.cookies.map(\.value) == ["plain"])
  }
}
