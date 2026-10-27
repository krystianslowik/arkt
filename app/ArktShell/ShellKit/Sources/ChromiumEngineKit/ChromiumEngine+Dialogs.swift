import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - JavaScript dialogs (#400, contract rule 19)

extension ChromiumEngine {
  /// Chromium's `TabModalDialogManager` decides when a dialog shows and when it ends; the facade reports each request
  /// with the page's values and each end with one `DialogEnded`. A dialog of a tab this instance does not list (it
  /// closed, or no window of this instance holds it) has nobody to show it: it is answered `accepted: false` at once,
  /// so the page's call returns and never hangs, and it is not reported.
  func dialogRequested(_ event: any ArktEngineEvent) {
    guard let dialog = event.dialog, dialogByHandle[ObjectIdentifier(dialog)] == nil else { return }
    guard let tab = tabByHandle[ObjectIdentifier(dialog.tab)], tabs[tab] != nil else {
      _ = dialog.respond(accepted: false, userInput: nil)
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

  /// Ends every pending dialog of `tab`, in the order they were raised.
  func endDialogs(of tab: TabID) {
    for pending in pendingDialogs.values where pending.tab == tab { finishDialog(pending.id) }
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
    @unknown default: self = .alert
    }
  }
}
