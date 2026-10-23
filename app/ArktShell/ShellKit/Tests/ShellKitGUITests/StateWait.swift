import Foundation
import XCTest

/// Turns the main run loop until `condition` holds, for at most `timeout` seconds, and fails naming `state` when it
/// never does. Waits on the state a test asserts, not on a timer or a proxy flag (#190): each turn returns as soon as
/// the run loop handled a source (for example a block queued with `DispatchQueue.main.async`), so a fast machine does
/// not wait and a slow one waits as long as it needs, up to the deadline.
@MainActor
func waitUntil(_ state: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
               _ condition: () -> Bool) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() {
    guard Date() < deadline else {
      XCTFail("timed out after \(timeout) s waiting for \(state)", file: file, line: line)
      return
    }
    RunLoop.main.run(mode: .default, before: deadline)
  }
}
