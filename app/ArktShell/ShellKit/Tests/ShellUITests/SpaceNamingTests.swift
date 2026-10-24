import Testing
@testable import ShellUI

/// "Space N", N the smallest free number (decision on #106).
struct SpaceNamingTests {
  @Test(arguments: [
    (taken: [String](), expected: "Space 1"),
    (taken: ["Work", "Personal"], expected: "Space 1"),
    (taken: ["Space 1"], expected: "Space 2"),
    (taken: ["Space 2", "Space 1", "Space 3"], expected: "Space 4"),
    (taken: ["Space 1", "Space 3"], expected: "Space 2"),
    (taken: ["Space", "Space 0", "Space -1", "Space 01", "space 1", "Space 1 copy"], expected: "Space 1"),
  ])
  func nextTitleTakesTheSmallestFreeNumber(taken: [String], expected: String) {
    #expect(SpaceNaming.nextTitle(base: "Space", taken: taken) == expected)
  }
}
