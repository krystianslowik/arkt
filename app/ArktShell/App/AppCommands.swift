import AppKit
import ShellUI

/// The target of the main menu's app-level items (week-3 results, W3-8 step 3): New Window, Settings, Import Browser
/// Data, Show Archive, Clear Archive and Welcome to Arkt. Explicit, so the items never reach the end of the responder chain, which in the Engine build is
/// Chromium's `AppController`. Enabled from the session: nothing is enabled before the data folder loaded.
@MainActor
final class AppCommands: NSObject {
  weak var composition: AppComposition?
  /// Edit > Undo's target (menu targets are weak): Cmd-Z reopens a closed tab or Peek unless text is being edited
  /// (#346, KB-011).
  let undoRouter = ReopenUndoRouter()

  private var session: AppSession? { composition?.session }

  /// File > New Window (Cmd-N, KB-005): a window on the same Spaces, without a page until the user picks one.
  @objc func newWindow(_ sender: Any?) { session?.windows.openWindow(opensFirstTab: false) }

  /// Arkt Shell > Settings... (Cmd-, KB-066): no Settings window yet, so the item stays disabled.
  @objc func showSettings(_ sender: Any?) {}

  /// File > Import from Arc... (E4c).
  @objc func importFromArc(_ sender: Any?) { session?.importFromArc() }

  /// Window > Show Archive (E5c, unbound by default, KB-043).
  @objc func showArchive(_ sender: Any?) { session?.showArchive() }

  /// Window > Clear Archive... (BH-087, unbound, KB-043): fronts the Archive window and asks there.
  @objc func clearArchive(_ sender: Any?) { session?.clearArchive() }

  /// Help > Welcome to Arkt (onboarding spec, section 12): the first run again over the frontmost window.
  @objc func showWelcome(_ sender: Any?) { session?.showWelcome() }
}

extension AppCommands: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard let session else { return false }
    switch menuItem.action {
    case #selector(importFromArc(_:)):
      session.refreshArcImportAvailability()           // off main; applies from the next validation
      return session.canImportFromArc
    case #selector(showSettings(_:)):
      return false
    case #selector(showWelcome(_:)):
      return session.canShowWelcome
    case #selector(clearArchive(_:)):
      session.refreshArchiveHasItems()                 // off main; applies from the next validation
      return session.archiveHasItems
    default:
      return true
    }
  }
}
