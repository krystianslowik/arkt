import ArcImport
import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ChromiumEngineKit

/// The import seam over the facade (#512): records reach it field by field with their bytes lent in place, the facade's
/// counts come back as the result, and the secrets of the batch are zeroed once it answered.
@MainActor
struct ChromiumImportTests {
  let facade = ScriptedFacade()

  private func cookie() -> ArcCookie {
    ArcCookie(
      hostKey: ".example.com", name: "session", value: SecretBytes(taking: Array("cookie-secret".utf8)), path: "/docs",
      expires: Date(timeIntervalSince1970: 2_000_000_000), creation: Date(timeIntervalSince1970: 100),
      lastAccess: Date(timeIntervalSince1970: 200), isSecure: true, isHTTPOnly: true, sameSite: 1, priority: 2,
      sourceScheme: 2, sourcePort: 443, partitionKey: "https://top.example")
  }

  @Test func cookieFieldsAndValueReachTheFacade() async {
    let engine = ChromiumEngine(facade: facade)
    let batch = [cookie()]
    let result = await engine.importCookies(batch)

    #expect(result == ImportWriteResult(written: 1))
    #expect(facade.importedCookieBatches == [[ScriptedFacade.ScriptedImportedCookie(
      hostKey: ".example.com", name: "session", path: "/docs", value: "cookie-secret",
      expires: Date(timeIntervalSince1970: 2_000_000_000), creation: Date(timeIntervalSince1970: 100),
      lastAccess: Date(timeIntervalSince1970: 200), isSecure: true, isHTTPOnly: true, sameSite: 1, priority: 2,
      sourceScheme: 2, sourcePort: 443, partitionKey: "https://top.example")]])
  }

  @Test func theFacadeCountsComeBackAsTheResult() async {
    let engine = ChromiumEngine(facade: facade)
    facade.importAnswer = (written: 1, skipped: 1, failed: 1, failureReason: "refused: EXCLUDE_SECURE_ONLY: 1\n")
    let result = await engine.importCookies([cookie(), cookie(), cookie()])
    #expect(result == ImportWriteResult(
      written: 1, skipped: 1, failed: 1, failureReason: "refused: EXCLUDE_SECURE_ONLY: 1\n"))
  }

  @Test func cookieSecretsAreZeroedAfterTheCall() async {
    let engine = ChromiumEngine(facade: facade)
    let batch = [cookie(), cookie()]
    _ = await engine.importCookies(batch)
    #expect(batch.allSatisfy { EngineImportContract.isZeroed($0.value) })
    #expect(facade.importedCookieBatches.first?.map(\.value) == ["cookie-secret", "cookie-secret"])
  }

  @Test func loginsReachTheFacadeAndTheirPasswordsAreZeroedAfterTheCall() async {
    let engine = ChromiumEngine(facade: facade)
    facade.importAnswer = (written: nil, skipped: 0, failed: 0, failureReason: nil)
    let batch = [
      ArcLogin(
        originURL: "https://example.com/login", actionURL: "https://example.com/post", signonRealm: "https://example.com/",
        username: "user", password: SecretBytes(taking: Array("login-secret".utf8)),
        dateCreated: Date(timeIntervalSince1970: 10), dateLastUsed: Date(timeIntervalSince1970: 20)),
      ArcLogin(
        originURL: "https://example.org/", signonRealm: "https://example.org/", username: "",
        password: SecretBytes(taking: [])),
    ]
    let result = await engine.importPasswords(batch)

    #expect(result == ImportWriteResult(written: 2))
    #expect(facade.importedLoginBatches == [[
      ScriptedFacade.ScriptedImportedLogin(
        originURL: "https://example.com/login", actionURL: "https://example.com/post",
        signonRealm: "https://example.com/", username: "user", password: "login-secret",
        dateCreated: Date(timeIntervalSince1970: 10), dateLastUsed: Date(timeIntervalSince1970: 20)),
      ScriptedFacade.ScriptedImportedLogin(
        originURL: "https://example.org/", actionURL: nil, signonRealm: "https://example.org/", username: "",
        password: "", dateCreated: nil, dateLastUsed: nil),
    ]])
    #expect(batch.allSatisfy { EngineImportContract.isZeroed($0.password) })
  }

  @Test func historyEntriesReachTheFacadeWithTheirVisitsTransitionsAndWatermark() async {
    let engine = ChromiumEngine(facade: facade)
    let newest = Date(timeIntervalSince1970: 3_000)
    facade.importLastVisitTime = newest
    let watermark = Date(timeIntervalSince1970: 1_000)
    let entry = ImportedHistoryEntry(
      url: "https://example.com/", title: "Example", visitCount: 3, typedCount: 1, lastVisit: newest,
      visits: [
        HistoryVisit(time: Date(timeIntervalSince1970: 2_000), transition: .typed),
        HistoryVisit(time: newest, transition: .keywordGenerated),
        HistoryVisit(time: Date(timeIntervalSince1970: 2_500), transition: .unknown),
      ])
    let result = await engine.importHistory([entry], after: watermark)

    #expect(result == ImportWriteResult(written: 3, latestVisit: newest))
    #expect(facade.importedHistoryWatermarks == [watermark])
    #expect(facade.importedHistoryBatches == [[ScriptedFacade.ScriptedImportedHistoryEntry(
      url: "https://example.com/", title: "Example",
      visitTimes: [Date(timeIntervalSince1970: 2_000), newest, Date(timeIntervalSince1970: 2_500)],
      visitTransitions: [1, 10, 0])]])
  }

  @Test func noWatermarkReachesTheFacadeAsNil() async {
    let engine = ChromiumEngine(facade: facade)
    _ = await engine.importHistory([], after: nil)
    #expect(facade.importedHistoryWatermarks.count == 1 && facade.importedHistoryWatermarks[0] == nil)
  }

  @Test func bookmarksReachTheFacadeWithTheirFoldersAndGuid() async {
    let engine = ChromiumEngine(facade: facade)
    facade.importAnswer = (written: 1, skipped: 1, failed: 0, failureReason: nil)
    let added = Date(timeIntervalSince1970: 500)
    let result = await engine.importBookmarks([
      BookmarkRecord(
        root: "bookmark_bar", folderPath: ["Reading", "Later"], title: "Article", url: "https://example.net/a",
        guid: "00000000-0000-4000-8000-000000000003", dateAdded: added),
      BookmarkRecord(root: "other", folderPath: [], title: "", url: "https://example.com/", guid: nil, dateAdded: nil),
    ])

    #expect(result == ImportWriteResult(written: 1, skipped: 1))
    #expect(facade.importedBookmarkBatches == [[
      ScriptedFacade.ScriptedImportedBookmark(
        url: "https://example.net/a", title: "Article", guid: "00000000-0000-4000-8000-000000000003", dateAdded: added,
        folderPath: ["Reading", "Later"]),
      ScriptedFacade.ScriptedImportedBookmark(url: "https://example.com/", title: "", guid: nil, dateAdded: nil, folderPath: []),
    ]])
  }

  @Test func anEmptyBatchStillAnswers() async {
    let engine = ChromiumEngine(facade: facade)
    #expect(await engine.importCookies([]) == ImportWriteResult())
    #expect(await engine.importPasswords([]) == ImportWriteResult())
    #expect(await engine.importHistory([], after: nil) == ImportWriteResult())
    #expect(await engine.importBookmarks([]) == ImportWriteResult())
  }

  @Test func extensionIDsReachTheFacadeAndComeBackAsOneResultEach() async {
    let engine = ChromiumEngine(facade: facade)
    let ids = ["a", "b", "c", "d"].map { String(repeating: $0, count: 32) }
    facade.extensionAnswers[ids[1]] = (.alreadyInstalled, nil)
    facade.extensionAnswers[ids[2]] = (.failed, "not available from the Web Store")
    facade.extensionAnswers[ids[3]] = (.failed, "not confirmed")
    let results = await engine.installExtensionResults(ids: ids)

    #expect(facade.installedExtensionBatches == [ids])
    #expect(results == [
      ExtensionInstallResult(id: ids[0], outcome: .installed),
      ExtensionInstallResult(id: ids[1], outcome: .alreadyInstalled),
      ExtensionInstallResult(id: ids[2], outcome: .failed("not available from the Web Store")),
      ExtensionInstallResult(id: ids[3], outcome: .failed("not confirmed")),
    ])
  }

  @Test func theCoordinatorSeesTheExtensionCounts() async {
    let engine = ChromiumEngine(facade: facade)
    let ids = ["a", "b", "c"].map { String(repeating: $0, count: 32) }
    facade.extensionAnswers[ids[1]] = (.alreadyInstalled, nil)
    facade.extensionAnswers[ids[2]] = (.failed, "not available from the Web Store")
    let counts = await engine.installExtensions(ids: ids)
    #expect(counts == ImportWriteResult(
      written: 1, skipped: 1, failed: 1, failureReason: "not available from the Web Store: 1\n"))
  }

  @Test func aFailedResultWithoutAReasonStillHasOne() async {
    let engine = ChromiumEngine(facade: facade)
    let id = String(repeating: "f", count: 32)
    facade.extensionAnswers[id] = (.failed, nil)
    #expect(await engine.installExtensionResults(ids: [id]) == [
      ExtensionInstallResult(id: id, outcome: .failed("install failed"))])
  }

  @Test func anEmptyExtensionBatchStillAnswers() async {
    let engine = ChromiumEngine(facade: facade)
    #expect(await engine.installExtensionResults(ids: []) == [])
  }
}
