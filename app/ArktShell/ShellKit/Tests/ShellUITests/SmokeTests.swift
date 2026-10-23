import Testing
@testable import ShellUI

@Test func shellUIVersionIsOne() { #expect(ShellUIVersion.current == 1) }
