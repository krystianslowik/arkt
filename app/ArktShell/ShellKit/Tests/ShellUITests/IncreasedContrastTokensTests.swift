import Testing
@testable import ShellUI

/// Increase Contrast for the main window (#640, design/increase-contrast/README.md): one edge token for the whole
/// shell, and the 2 pt ink ring of the focused Split View pane.
struct IncreasedContrastTokensTests {
  @Test func theEdgeIsBlackOrWhiteAtTwentyPercentOnePointWide() {
    #expect(ShellTokens.increasedContrastEdge == TokenPair(light: .black(0.20), dark: .white(0.20)))
    #expect(ShellTokens.increasedContrastEdgeWidth == 1)
  }

  /// Settings, the Archive, the dialogs and the toasts point at the shell's token instead of their own copies.
  @Test func everySurfaceUsesTheOneEdgeToken() {
    #expect(ArchiveTokens.increasedContrastEdge == ShellTokens.increasedContrastEdge)
    #expect(AlertTokens.increasedContrastEdge == ShellTokens.increasedContrastEdge)
    #expect(SettingsTokens.separatorIncreasedContrast == ShellTokens.increasedContrastEdge)
  }

  @Test func thePaneFocusRingIsTheInkToneTwoPointsWide() {
    #expect(ShellTokens.splitPaneFocusRing == TokenPair(light: .srgb(hex: 0x202321, alpha: 0.50),
                                                         dark: .srgb(hex: 0xFAF9F5, alpha: 0.60)))
    #expect(ShellTokens.splitPaneFocusRingWidth == 2)
  }
}
