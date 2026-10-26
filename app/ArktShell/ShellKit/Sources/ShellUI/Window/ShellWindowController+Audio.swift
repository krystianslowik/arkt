import AppKit
import EngineAPI

// MARK: - Tab sound (#364, BH-126)

/// The sidebar shows each tab's sound from its engine snapshot, and Mute / Unmute (the row's audio button, its
/// VoiceOver action and the context menus) flips the tab's mute through the engine. The engine's `.mutedChanged`
/// then updates the row, so the row never shows a state the engine has not taken.
extension ShellWindowController {
  /// Mutes the node's page when it plays unmuted, else unmutes it. A node without a page does nothing.
  func toggleMute(_ node: NodeID) {
    guard let tab = tabsByNode[node], let snapshot = engine.snapshot(of: tab) else { return }
    engine.setMuted(tab, muted: !snapshot.isMuted)
  }

  /// `.audibleChanged` or `.mutedChanged` for the page of `node`.
  func audioChanged(_ tab: TabID, node: NodeID) {
    guard let snapshot = engine.snapshot(of: tab) else { return }
    showAudio(of: snapshot, in: node)
  }

  func showAudio(of snapshot: TabSnapshot, in node: NodeID) {
    sidebarController.setAudio(TabAudio(isAudible: snapshot.isAudible, isMuted: snapshot.isMuted), for: node)
  }
}
