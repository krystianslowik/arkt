import Foundation

/// What a sidebar row's (or a Favorite tile's) hover close button does (GS-043), which decides its tooltip and its VoiceOver action name.
/// The action itself is the window's: the same close as Cmd-W (`ShellWindowController.close(node:)`).
public enum RowCloseAction: Equatable, Sendable {
  /// A Today tab or a Today split pane: archived (BH-071; a pane alone, user decision 4).
  case archiveTab
  /// A whole Today split: archived as one unit.
  case archiveSplit
  /// A pinned tab, pane or split: its pages close and the row stays (BH-067; BH-070 is NEEDS-RUNTIME-CHECK RT-17).
  case closeKeepPinned
  /// A Favorite: its page closes and the tile stays (BH-048 [I]). The grid shows the X only on a loaded tile (#82).
  case closeFavorite

  /// The action for the row of `id`, by its top-level section and kind. Nil for folders (they only expand and
  /// collapse) and unknown nodes.
  @MainActor
  public static func resolve(_ id: NodeID, in source: any SidebarSource) -> RowCloseAction? {
    guard let node = source.node(id) else { return nil }
    let isSplit: Bool
    switch node {
    case .tab: isSplit = false
    case .split: isSplit = true
    case .folder: return nil
    }
    switch source.section(containing: id) {
    case .today?: return isSplit ? .archiveSplit : .archiveTab
    case .pinned?: return .closeKeepPinned
    case .favorites?: return .closeFavorite
    default: return nil
    }
  }

  /// Hover text. Today and pinned are Arc's shipped strings (GS-043 [S]); the split and Favorite ones are [I].
  public var tooltip: String {
    switch self {
    case .archiveTab: "Archive this tab"
    case .archiveSplit: "Archive this split"
    case .closeKeepPinned: "Close and Keep Pinned"
    case .closeFavorite: "Close this tab"
    }
  }

  /// The row's VoiceOver custom action name.
  public var accessibilityName: String {
    switch self {
    case .archiveTab, .archiveSplit: "Archive"
    case .closeKeepPinned, .closeFavorite: "Close"
    }
  }
}
