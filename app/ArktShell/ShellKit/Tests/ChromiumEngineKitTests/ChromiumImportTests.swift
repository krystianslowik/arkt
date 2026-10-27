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

  @Test func anEmptyBatchStillAnswers() async {
    let engine = ChromiumEngine(facade: facade)
    #expect(await engine.importCookies([]) == ImportWriteResult())
    #expect(await engine.importPasswords([]) == ImportWriteResult())
  }
}
