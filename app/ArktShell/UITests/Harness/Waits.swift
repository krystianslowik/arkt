import Foundation
import XCTest

/// Waits on accessibility state, never on time (plan, Rules: "No sleeps"). Every wait is an
/// `XCTNSPredicateExpectation` evaluated by `XCTWaiter`, and fails the test with the element's description when it
/// times out.
@MainActor
enum Waits {
  /// The default timeout in seconds before scaling.
  static let defaultTimeout: TimeInterval = 10

  /// `ARKT_UITEST_TIMEOUT_SCALE` from the runner's environment (CI passes it as
  /// `TEST_RUNNER_ARKT_UITEST_TIMEOUT_SCALE=3`); 1 when unset or not a positive number.
  static var scale: Double {
    guard let raw = ProcessInfo.processInfo.environment["ARKT_UITEST_TIMEOUT_SCALE"],
          let value = Double(raw), value > 0 else { return 1 }
    return value
  }

  static func scaled(_ timeout: TimeInterval?) -> TimeInterval {
    (timeout ?? defaultTimeout) * scale
  }

  /// Waits until `condition` holds. Returns whether it did; on timeout also records a failure naming `what`.
  @discardableResult
  static func until(
    _ what: @autoclosure () -> String,
    timeout: TimeInterval? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
  ) -> Bool {
    let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
    let limit = scaled(timeout)
    let result = XCTWaiter().wait(for: [expectation], timeout: limit)
    guard result == .completed else {
      XCTFail("timed out after \(limit) s waiting for \(what())", file: file, line: line)
      return false
    }
    return true
  }
}

// MARK: - Helpers for test cases

@MainActor
extension XCTestCase {
  @discardableResult
  func waitFor(
    _ element: XCUIElement, timeout: TimeInterval? = nil, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) to exist", timeout: timeout, file: file, line: line) { element.exists }
  }

  @discardableResult
  func waitFor(
    _ element: XCUIElement, value: String, timeout: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) value \(value)", timeout: timeout, file: file, line: line) {
      element.exists && (element.value as? String) == value
    }
  }

  @discardableResult
  func waitFor(
    _ element: XCUIElement, label: String, timeout: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) label \(label)", timeout: timeout, file: file, line: line) {
      element.exists && element.label == label
    }
  }

  @discardableResult
  func waitForEnabled(
    _ element: XCUIElement, _ enabled: Bool = true, timeout: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) isEnabled \(enabled)", timeout: timeout, file: file, line: line) {
      element.exists && element.isEnabled == enabled
    }
  }

  @discardableResult
  func waitForSelected(
    _ element: XCUIElement, _ selected: Bool = true, timeout: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) isSelected \(selected)", timeout: timeout, file: file, line: line) {
      element.exists && element.isSelected == selected
    }
  }

  @discardableResult
  func waitUntilGone(
    _ element: XCUIElement, timeout: TimeInterval? = nil, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("\(element) to disappear", timeout: timeout, file: file, line: line) { !element.exists }
  }

  @discardableResult
  func waitFor(
    _ app: XCUIApplication, _ state: XCUIApplication.State, timeout: TimeInterval? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("app state \(state.rawValue)", timeout: timeout, file: file, line: line) { app.state == state }
  }
}
