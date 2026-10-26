import AppKit

// MARK: - Folder drop seam (#104, #109)

/// Where nodes dropped onto a folder row land (GS-009, BH-091). Folder behavior is #109's: this one function is the
/// seam it extends (for example BH-092, a moved tab peeking out of a closed folder). The folder keeps its open or
/// closed state either way; the outline keeps it across moves.
extension ShellWindowController {
  /// The end of the folder [I]. PARITY(NEEDS-RUNTIME-CHECK): whether Arc adds to the top or the end.
  func folderDropPlacement(_ folder: NodeID) -> SidebarDropPlacement {
    SidebarDropPlacement(location: .folder(folder), index: nil)
  }
}
