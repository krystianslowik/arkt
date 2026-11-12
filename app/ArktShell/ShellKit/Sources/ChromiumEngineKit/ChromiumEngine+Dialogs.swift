import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - JavaScript dialogs (#400, contract rule 19)

extension ChromiumEngine {
  /// Chromium's `TabModalDialogManager` decides when a dialog shows and when it ends; the facade reports each request
  /// with the page's values and each end with one `DialogEnded`. Every instance over the facade sees every request
  /// (#882). A dialog of a tab this instance does not list is not reported here; it is answered at once, so the page's
  /// call returns and never hangs, only when nobody can show it (`nobodyShows`): `accepted: false`, except a leave-site
  /// dialog, which is answered Leave, since Stay would keep its close (a window's, a quit) from ever finishing (#897
  /// review). A tab in another live instance's window is that instance's.
  func dialogRequested(_ event: any ArktEngineEvent) {
    guard let dialog = event.dialog, dialogByHandle[ObjectIdentifier(dialog)] == nil else { return }
    guard let tab = tabByHandle[ObjectIdentifier(dialog.tab)], tabs[tab] != nil else {
      if nobodyShows(dialog.tab) { _ = dialog.respond(accepted: dialog.kind == .beforeUnload, userInput: nil) }
      return
    }
    endDialogs(of: tab)             // Chromium ends the earlier one first; this only guards the order
    let value = JavaScriptDialog(
      id: DialogID(), tab: tab, kind: JavaScriptDialog.Kind(facade: dialog.kind), title: dialog.title,
      message: dialog.message, defaultPromptText: dialog.defaultPromptText, acceptTitle: dialog.acceptTitle,
      cancelTitle: dialog.cancelTitle)
    pendingDialogs[value.id] = PendingDialog(id: value.id, tab: tab, handle: dialog)
    dialogByHandle[ObjectIdentifier(dialog)] = value.id
    hub.emit(.dialogRequested(value))
  }

  /// The engine ended the dialog, or the facade reports the end of one this client answered (dropped: it was reported
  /// when the answer went out).
  func dialogEnded(_ event: any ArktEngineEvent) {
    guard let dialog = event.dialog, let id = dialogByHandle[ObjectIdentifier(dialog)] else { return }
    finishDialog(id)
  }

  /// The facade runs the page's callback and reports the end; the shell sees `.dialogEnded` before this returns. A
  /// dialog the engine already ended (its event is still queued) answers NO and ends here all the same.
  public func respond(to dialog: DialogID, accepted: Bool, userInput: String?) {
    guard let pending = pendingDialogs[dialog] else { return }
    _ = pending.handle.respond(accepted: accepted, userInput: userInput)
    finishDialog(dialog)
  }

  /// True for a tab no instance lists: one this instance retired, one closed or out of every window, one in this
  /// instance's own window (its kept New Tab page, #299), and one in a window whose instance is gone (a runner dropped
  /// it before the window closed). Several instances may answer the last kinds; the second answer does nothing.
  private func nobodyShows(_ tab: any ArktTabHandle) -> Bool {
    if retired[ObjectIdentifier(tab)] != nil { return true }
    guard let adapter = tab.browser?.host as? WindowHostAdapter, let owner = adapter.engine else { return true }
    return owner === self
  }

  /// Ends every pending dialog of `tab`, in the order they were raised.
  func endDialogs(of tab: TabID) {
    for pending in pendingDialogs.values where pending.tab == tab { finishDialog(pending.id) }
  }

  /// A cancelled close is over with its leave-site dialog: the engine may report the cancel before the dialog's end
  /// (the page's callback runs before the dialog closes), and the shell sees the end first (contract rules 16, 19).
  func endLeaveSiteDialogs(of tab: TabID) {
    for pending in pendingDialogs.values where pending.tab == tab && pending.handle.kind == .beforeUnload {
      finishDialog(pending.id)
    }
  }

  private func finishDialog(_ id: DialogID) {
    guard let pending = pendingDialogs.removeValue(forKey: id) else { return }
    dialogByHandle[ObjectIdentifier(pending.handle)] = nil
    hub.emit(.dialogEnded(pending.tab, id))
  }
}

extension JavaScriptDialog.Kind {
  init(facade kind: ArktDialogKind) {
    switch kind {
    case .alert: self = .alert
    case .confirm: self = .confirm
    case .prompt: self = .prompt
    case .beforeUnload: self = .beforeUnload
    @unknown default: self = .alert
    }
  }
}
