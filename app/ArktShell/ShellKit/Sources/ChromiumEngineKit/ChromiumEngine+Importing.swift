import ArcImport
internal import ArktEngineABI
import EngineAPI
import Foundation

/// A cookie record as the facade reads it (`ArktImportCookie`). It lends the value's bytes in place, so no copy of the
/// plaintext is made on this side.
private final class FacadeImportCookie: NSObject, ArktImportCookie {
  private let cookie: ArcCookie
  init(_ cookie: ArcCookie) { self.cookie = cookie }

  var hostKey: String { cookie.hostKey }
  var name: String { cookie.name }
  var path: String { cookie.path }
  var expires: Date { cookie.expires }
  var creation: Date? { cookie.creation }
  var lastAccess: Date? { cookie.lastAccess }
  var isSecure: Bool { cookie.isSecure }
  var isHTTPOnly: Bool { cookie.isHTTPOnly }
  var sameSite: Int { cookie.sameSite }
  var priority: Int { cookie.priority }
  var sourceScheme: Int { cookie.sourceScheme }
  var sourcePort: Int { cookie.sourcePort }
  var partitionKey: String { cookie.partitionKey }

  func withValueBytes(_ body: (UnsafeRawPointer, UInt) -> Void) {
    lend(cookie.value, to: body)
  }
}

private final class FacadeImportLogin: NSObject, ArktImportLogin {
  private let login: ArcLogin
  init(_ login: ArcLogin) { self.login = login }

  var originURL: String { login.originURL }
  var actionURL: String? { login.actionURL }
  var signonRealm: String { login.signonRealm }
  var username: String { login.username }
  var dateCreated: Date? { login.dateCreated }
  var dateLastUsed: Date? { login.dateLastUsed }

  func withPasswordBytes(_ body: (UnsafeRawPointer, UInt) -> Void) {
    lend(login.password, to: body)
  }
}

/// Lends `secret`'s bytes to `body`. An empty secret has no address, so `body` gets a valid pointer and a length of 0.
private func lend(_ secret: SecretBytes, to body: (UnsafeRawPointer, UInt) -> Void) {
  secret.withBytes { buffer in
    if let base = buffer.baseAddress {
      body(base, UInt(buffer.count))
    } else {
      var empty: UInt8 = 0
      withUnsafePointer(to: &empty) { body($0, 0) }
    }
  }
}

extension ImportWriteResult {
  @MainActor fileprivate init(_ result: any ArktImportResult) {
    self.init(
      written: result.written, skipped: result.skipped, failed: result.failed, failureReason: result.failureReason)
  }
}

/// Import writes over the facade (#512). The secrets of the batch are zeroed once the facade answered.
extension ChromiumEngine: EngineImporting {
  public func importCookies(_ batch: [ArcCookie]) async -> ImportWriteResult {
    defer { for cookie in batch { cookie.value.wipe() } }
    let records = batch.map(FacadeImportCookie.init)
    return await withCheckedContinuation { continuation in
      facade.importCookies(records) { continuation.resume(returning: ImportWriteResult($0)) }
    }
  }

  public func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult {
    defer { for login in batch { login.password.wipe() } }
    let records = batch.map(FacadeImportLogin.init)
    return await withCheckedContinuation { continuation in
      facade.importPasswords(records) { continuation.resume(returning: ImportWriteResult($0)) }
    }
  }
}
