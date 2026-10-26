import CoreGraphics

/// A shadow token: color per flavor plus geometry (points, y down).
public struct ShadowToken: Sendable, Equatable {
  public let color: TokenPair
  public let radius: CGFloat
  public let offsetY: CGFloat
  /// A second, tighter shadow under the first, for a contact edge.
  public let contactColor: TokenPair
  public let contactRadius: CGFloat
  public let contactOffsetY: CGFloat
}

// Peek (docs/design/peek.md, #313). Kept apart from `ShellTokens.swift` to stay off a file other work changes.
extension ShellTokens {
  /// Over the source card while a Peek is open, clipped to it: the source reads as set aside.
  public static let peekScrim = TokenPair(light: .black(0.18), dark: .black(0.42))
  /// The lifted card. Dark keeps it (unlike `cardShadow`): it is what separates two cards over a dark page.
  public static let peekShadow = ShadowToken(color: TokenPair(light: .black(0.22), dark: .black(0.55)), radius: 24,
                                             offsetY: 18,
                                             contactColor: TokenPair(light: .black(0.10), dark: .black(0.30)),
                                             contactRadius: 5, contactOffsetY: 3)
  /// The drag grabber above the card: WCAG 1.4.11 3:1 under `peekScrim` (3.6:1 light over white, 6.3:1 dark over
  /// the dark page fill; `PeekTokensContrastTests`).
  public static let peekGrabber = TokenPair(light: .black(0.50), dark: .white(0.55))
}
