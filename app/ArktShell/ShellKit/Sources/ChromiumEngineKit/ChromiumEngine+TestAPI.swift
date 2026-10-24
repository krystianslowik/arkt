import AppKit
internal import ArktEngineABI
import EngineAPI

/// An error from the facade's test API.
public struct EngineTestAPIError: Error, CustomStringConvertible {
  public let description: String
}

// MARK: - Test API (Task W3-5 step 5)

/// The facade's test API, for the in-app contract runner's harness drivers (W3-9): it lives in the app, which cannot
/// see the facade header. The engine answers only when launched with `--arkt-engine-test-api`; otherwise every call
/// reports an error or false.
extension ChromiumEngine {
  public var testAPIEnabled: Bool { facade.testAPIEnabled }

  /// Runs `script` in the tab's main world, with a user gesture when asked (sticky activation for `beforeunload`,
  /// `window.open`). A promise answers an empty object and an exception answers nil (week-3 results, W3-5b).
  public func evaluateScript(_ script: String, in id: TabID, userGesture: Bool) async throws -> ScriptValue? {
    guard let handle = handle(of: id) else {
      throw EngineTestAPIError(description: "evaluateScript: no tab \(id)")
    }
    return try await withCheckedThrowingContinuation { continuation in
      facade.evaluateScript(script, in: handle, userGesture: userGesture) { result, error in
        if let error {
          continuation.resume(throwing: EngineTestAPIError(description: error.localizedDescription))
        } else {
          continuation.resume(returning: ScriptValue(facade: result))
        }
      }
    }
  }

  /// Answers the tab's pending JavaScript dialog (a leave-site dialog included): false when none is pending.
  public func answerDialog(in id: TabID, accept: Bool) -> Bool {
    guard let handle = handle(of: id) else { return false }
    return facade.answerDialog(in: handle, accept: accept)
  }
}
