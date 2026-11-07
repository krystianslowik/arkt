import XCTest

/// Runs last in a GUI run (test classes run in name order) so that the window leak guard has a test to record the
/// leaks of the class before it on (#805). See `WindowLeakGuard`.
@MainActor
final class ZZWindowLeakGuardEndTests: XCTestCase {
  func testTheClassesBeforeThisOneClosedTheirWindows() {
    // The guard records a leak of the previous class on this test as it starts; nothing to do here.
  }
}
