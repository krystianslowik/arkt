import AppKit

/// Folder commands of the Tabs menu (#109): New Folder (KB-040) and Collapse / Expand All Folders (BH-097). Every
/// item reaches the main window's controller through the responder chain; the menu bar shows them with no key.
/// PARITY(NEEDS-RUNTIME-CHECK RT-04): New Folder's key is unknown and Cmd-Shift-N stays New Incognito Window (CF-02).
extension ShellWindowController {
  /// New Folder: the multi-selection goes into a new folder (BH-094), else an empty folder lands at the end of the
  /// current Space's Pinned; either opens for naming [I].
  @objc public func newFolder(_ sender: Any?) {
    let selected = sidebarController.selectedNodes
    if selected.count >= 2 {
      newFolder(holding: selected)
      return
    }
    guard let space = sidebarController.currentSpace ?? createSpace() else { return }
    newFolder(in: space)
  }

  /// Collapse All Folders (BH-097): every folder of this window closes; the current tab keeps peeking out [I].
  @objc public func collapseAllFolders(_ sender: Any?) {
    sidebarController.setAllFolders(open: false)
  }

  /// Expand All Folders (BH-097): every folder of this window opens.
  @objc public func expandAllFolders(_ sender: Any?) {
    sidebarController.setAllFolders(open: true)
  }

  /// Collapse / Expand All need a folder in the current Space; New Folder is always available. Nil for other items.
  func validateFolderMenuItem(_ menuItem: NSMenuItem) -> Bool? {
    switch menuItem.action {
    case #selector(collapseAllFolders(_:)), #selector(expandAllFolders(_:)):
      sidebarController.currentSpaceHasFolders
    case #selector(newFolder(_:)):
      true
    default:
      nil
    }
  }
}
