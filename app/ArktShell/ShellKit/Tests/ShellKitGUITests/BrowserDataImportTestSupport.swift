import AppKit
@testable import CoreBridge
import Foundation
@testable import ShellUI
import ArcImport

/// A scripted `ProfileImporting` for the browser data import tests (#514): the test sends the events the coordinator
/// would stream, and asks the consent closure the way its counting step does.
@MainActor
final class ScriptedProfileImporter: ProfileImporting {
  var consent: (@MainActor (ProfileDataCounts) async -> ImportSelection?)?
  var continuation: AsyncStream<ProfileImportEvent>.Continuation?
  private(set) var retries = 0
  private(set) var cancels = 0

  func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
    -> AsyncStream<ProfileImportEvent> {
    self.consent = consent
    return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
  }

  func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
    retries += 1
    return AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
  }

  func cancel() { cancels += 1 }
  func send(_ event: ProfileImportEvent) { continuation?.yield(event) }
  func finish(_ summary: ProfileImportSummary) {
    continuation?.yield(.finished(summary))
    continuation?.finish()
  }
}
