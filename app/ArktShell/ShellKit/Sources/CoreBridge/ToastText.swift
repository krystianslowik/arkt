import ShellUI
import SidebarModel

/// Texts of the archive toasts. Counts and Space titles only; never a tab title or URL.
public enum ToastText {
  /// What a restore brought back, for the restore toast.
  public enum RestoredKind: Hashable, Sendable {
    case tab
    case folder
    case split

    public init(_ kind: NodeKind) {
      switch kind {
      case .tab: self = .tab
      case .folder: self = .folder
      case .split: self = .split
      }
    }

    var noun: String {
      switch self {
      case .tab: "Tab"
      case .folder: "Folder"
      case .split: "Split View"  // [I]
      }
    }
  }

  /// BH-085: shown after an auto-archive pass that archived `count` tabs (singular form [I]).
  public static func autoArchived(_ count: Int) -> String {
    "Auto archived \(count) \(count == 1 ? "tab" : "tabs")"
  }

  /// The undo toast after an auto-archive pass: only when it archived two or more tabs (alerts design, decision 3).
  /// Undo, like Cmd-Z, brings the pass back; the pill carries no key hint.
  public static func autoArchiveToast(count: Int) -> Toast? {
    guard count >= 2 else { return nil }
    return Toast(text: autoArchived(count), kind: .undo, actionTitle: undoTitle)
  }

  /// The undo toast's action.
  public static let undoTitle = "Undo"

  /// BH-086: shown after a restore, with a View button (so "Click to view." is dropped, alerts design 4.3).
  /// `spaceTitle` is the destination Space; nil means the item went back to Favorites [I].
  public static func restored(kind: RestoredKind, spaceTitle: String?) -> String {
    "\(kind.noun) restored to \(spaceTitle ?? "Favorites")"
  }

  /// The restore toast's glyph.
  public static let restoredGlyph = "arrow.counterclockwise"

  /// Shown when an import of browser data fails (no user-facing "Arc").
  public static let importFailed = "Couldn't import browser data."

  /// Shown when the sidebar model refuses a restore (#91).
  public static let restoreFailed = "Couldn't restore from the Archive."
}
