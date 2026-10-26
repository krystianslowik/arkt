import Foundation

/// What a sidebar row shows about its page's sound (#364, BH-126): nothing, the playing glyph, or the muted glyph.
/// Muted wins over playing (Chromium keeps reporting a muted page that plays as audible), and a muted page that went
/// quiet keeps its glyph so it can still be unmuted.
public enum TabAudio: Equatable, Sendable {
  case silent
  case playing
  case muted

  public init(isAudible: Bool, isMuted: Bool) {
    self = isMuted ? .muted : isAudible ? .playing : .silent
  }

  /// The toggle's title in menus and its accessibility label: "Unmute" while muted, else "Mute" (design OQ1).
  public var toggleTitle: String { self == .muted ? "Unmute" : "Mute" }

  /// The audio button's hover text. [I]
  public var tooltip: String { self == .muted ? "Unmute this tab" : "Mute this tab" }

  /// The button's SF Symbol; nil for a silent row, which shows no button.
  var symbolName: String? {
    switch self {
    case .silent: nil
    case .playing: "speaker.wave.2.fill"
    case .muted: "speaker.slash.fill"
    }
  }
}
