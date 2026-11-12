import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Install events (#592)

extension ChromiumEngine {
  /// The facade's `ExtensionInstalled` for each first install of the profile the engine reports (the Web Store, a
  /// user's .crx, an import's batch; not updates, unpacked, external, policy or component extensions), in place of
  /// Chromium's post-install dialog, which the engine no longer shows on its windows.
  public func observeExtensions(_ handler: @escaping @MainActor (EngineExtensionEvent) -> Void) -> EngineObservation {
    hub.addExtensionObserver(handler)
  }

  /// One `.installed`. An id of an import batch is `.browserImport` and uses its tag up; every other install is the
  /// user's. The facade sends no icon: the shell's toast shows none.
  func extensionInstalled(_ event: any ArktEngineEvent) {
    guard let id = event.extensionID, !id.isEmpty else { return }
    let source: ExtensionInstallSource = importBatchExtensionIDs.remove(id) != nil ? .browserImport : .user
    hub.emit(EngineExtensionEvent.installed(InstalledExtension(id: id, name: event.extensionName ?? "",
                                                                source: source)))
  }

  /// A batch of `ids` has answered: an id it did not install (failed, already installed, cancelled, or missing from
  /// the results) reports no install of the import's, so its tag goes. An installed id keeps its tag until its event
  /// arrives (the facade delivers events on a later task than the batch's completion may run).
  func releaseImportTags(of ids: [String], after results: [ExtensionInstallResult]) {
    let installed = Set(results.filter { $0.outcome == .installed }.map(\.id))
    for id in ids where !installed.contains(id) {
      importBatchExtensionIDs.remove(id)
    }
  }
}
