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

  /// BH-086: shown after a restore. `spaceTitle` is the destination Space; nil means the item went back to
  /// Favorites [I].
  public static func restored(kind: RestoredKind, spaceTitle: String?) -> String {
    "\(kind.noun) restored to \(spaceTitle ?? "Favorites"). Click to view."
  }
}
