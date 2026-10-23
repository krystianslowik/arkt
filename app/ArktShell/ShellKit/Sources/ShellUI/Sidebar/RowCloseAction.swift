import Foundation

/// What a sidebar row's (or a Favorite tile's) hover close button does (GS-043), which decides its tooltip and its
/// VoiceOver action name.
/// The action itself is the window's: the same close as Cmd-W (`ShellWindowController.close(node:)`), except on a
/// pane row, where the X takes the pane out of its split (BH-121).
public enum RowCloseAction: Equatable, Sendable {
  /// A Today tab: archived (BH-071).
  case archiveTab
  /// A whole Today split: archived as one unit.
  case archiveSplit
  /// A pinned tab, pane or split: its pages close and the row stays (BH-067; BH-070 is NEEDS-RUNTIME-CHECK RT-17).
  case closeKeepPinned
  /// A Favorite: its page closes and the tile stays (BH-048 [I]). The grid shows the X only on a loaded tile (#82).
  case closeFavorite
  /// A pane of a split, in any section: it leaves the split as its own tab with its page, right after the split
  /// (BH-121, maintainer decision on #56, 2026-10-23). Cmd-W on a pane still closes it (user decision 4).
  case removeFromSplit

  /// The action for the row of `id`: `.removeFromSplit` for a pane, otherwise by its top-level section and kind. Nil
  /// for folders (they only expand and collapse) and unknown nodes.
  @MainActor
  public static func resolve(_ id: NodeID, in source: any SidebarSource) -> RowCloseAction? {
    guard let node = source.node(id) else { return nil }
    let isSplit: Bool
    switch node {
    case .tab:
      if case .split? = source.parent(of: id) { return .removeFromSplit }
      isSplit = false
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
    case .removeFromSplit: "Remove Tab from Split View"     // [S] string (BH-121)
    }
  }

  /// The row's VoiceOver custom action name.
  public var accessibilityName: String {
    switch self {
    case .archiveTab, .archiveSplit: "Archive"
    case .closeKeepPinned, .closeFavorite: "Close"
    case .removeFromSplit: "Remove Tab from Split View"
    }
  }
}
