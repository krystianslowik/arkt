import XCTest

/// Runs last in a GUI run (XCTest runs test classes in byte order of their names, and lowercase sorts after
/// uppercase, so `Zzz` follows every `Z` class) so that the window leak guard has a test to record the
/// leaks of the class before it on (#805). See `WindowLeakGuard`.
@MainActor
final class ZzzWindowLeakGuardEndTests: XCTestCase {
  func testTheClassesBeforeThisOneClosedTheirWindows() {
    // The guard records a leak of the previous class on this test as it starts; nothing to do here.
  }
}
