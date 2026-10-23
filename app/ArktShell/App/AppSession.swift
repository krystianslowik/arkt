import AppKit
import Archive
import CoreBridge
import EngineAPI
import Persistence
import ShellUI
import SidebarModel
import os

/// Composition root: the one place that owns the database, the autosaver, backups and the window. Only the app
/// target imports `Persistence`.
@MainActor
final class AppSession {
  static let log = Logger(subsystem: "dev.arkt.shell", category: "session")
  /// Rolling backups while the sidebar changed (decision 5).
  static let backupInterval: TimeInterval = 30 * 60

  let location: DatabaseLocation
  let database: ArktDatabase
  let source: ModelSidebarSource
  let autosaver: SidebarAutosaver
  let window: ShellWindowController
  let archiveStore: ArchiveStore
  let settingsStore: SettingsStore
  let importer: ArcImportCoordinator
  /// Arc's folder; read only when the user asks for an import.
  let arcFiles = ArcSourceFiles(directory: AppEnvironment.arcDirectory)
  /// Arc's sidebar file existed at the last check (existence only, off the main actor): at launch and again each
  /// time the File menu is validated (`refreshArcImportAvailability`), so Arc installed or removed while Arkt runs
  /// shows up the next time the menu opens.
  private(set) var isArcImportAvailable = false
  /// The availability check in flight; at most one at a time.
  private var availabilityCheck: Task<Void, Never>?
  /// nil when the favicon folder was refused (it never is for Arkt's own data folder).
  private let faviconStore: FaviconStore?
  private var faviconWriter: FaviconWriter?
  private var backupTimer: Timer?
  private var changedSinceBackup = false
  /// The latest backup task; the DEBUG smoke phases await it before printing and quitting (E6), so a quick quit
  /// cannot race the launch backup.
  private(set) var lastBackup: Task<Void, Never>?

  init(state: LaunchState, location: DatabaseLocation, engine: any EngineClient, faviconStore: FaviconStore?) {
    self.location = location
    self.database = state.database
    let source = ModelSidebarSource(sidebar: state.sidebar ?? SidebarModel.Sidebar())
    self.source = source
    self.window = ShellWindowController(engine: engine, sidebar: source)
    let archiveStore = ArchiveStore(database: state.database)
    let settingsStore = SettingsStore(database: state.database)
    self.archiveStore = archiveStore
    self.settingsStore = settingsStore
    let autosaver = SidebarAutosaver(store: SidebarStore(database: state.database))
    self.autosaver = autosaver
    self.importer = ArcImportCoordinator(
      source: source, archive: archiveStore, archiveState: settingsStore, importRecord: settingsStore,
      persistSidebar: { await autosaver.flush() })     // the import record waits for the merged sidebar on disk
    self.faviconStore = faviconStore
    source.onDidChange = { [weak self] sidebar in
      guard let self else { return }
      autosaver.scheduleSave(sidebar)                 // every model change
      changedSinceBackup = true
    }
  }

  func start(outcome: OpenOutcome) {
    startFavicons(prune: outcome == .opened)          // before the window can create engine tabs
    window.onImportFromArc = { [weak self] in self?.importFromArc() }
    window.window?.center()
    window.showWindow(nil)
    refreshArcImportAvailability()
    if let notice = Self.notice(for: outcome) {
      // The notice case only: `OpenOutcome` carries file names, which never go to the log.
      Self.log.notice("launch outcome \(String(describing: notice), privacy: .public)")
      window.toasts.show(notice.toast) { [location] in
        NSWorkspace.shared.activateFileViewerSelecting([location.directory])
      }
    }
    switch outcome {
    case .opened, .restoredFromBackup: backUp()
    case .created, .recreatedEmpty: break           // nothing to back up; never seed (decision 3)
    }
    backupTimer = Timer.scheduledTimer(withTimeInterval: Self.backupInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.changedSinceBackup else { return }
        self.backUp()
      }
    }
  }

  static func notice(for outcome: OpenOutcome) -> RecoveryNotice? {
    switch outcome {
    case .created, .opened: nil
    case .restoredFromBackup(_, let quarantined): .restoredFromBackup(liveFileWasDamaged: quarantined != nil)
    case .recreatedEmpty(let quarantined): .recreatedEmpty(liveFileWasDamaged: quarantined != nil)
    }
  }

  /// `makeBackup` is `@concurrent` and returns nil while the database is empty, so this never blocks the main thread.
  /// A failed backup marks the sidebar changed again, so the next timer tick retries it.
  private func backUp() {
    changedSinceBackup = false
    let (database, location) = (database, location)
    lastBackup = Task { [weak self] in
      do { _ = try await database.makeBackup(in: location, now: .now) } catch {
        Self.log.error("backup failed \(String(describing: type(of: error)), privacy: .public)")
        self?.changedSinceBackup = true
      }
    }
  }

  // MARK: - Favicons

  /// Decision 8 plus the launch rules: the prune runs once, at launch, with the node ids loaded from the database,
  /// and every favicon write (engine or import) is queued behind it, so the prune can never remove a favicon written
  /// after launch. It runs only when the database opened normally (`prune`): after a restore from backup or an empty
  /// re-creation the loaded sidebar is not the one the favicons were written for, and pruning against it would
  /// delete favicons of nodes the user may get back. The stored favicons are then loaded once; ids the engine
  /// reported meanwhile keep the newer one, and the writer stops tracking them afterwards.
  private func startFavicons(prune: Bool) {
    guard let store = faviconStore else { return }
    let ids = Set(source.sidebar.nodes.keys)
    let pruning: Task<Void, Never>? = prune ? Task { await store.prune(keeping: ids) } : nil
    let writer = FaviconWriter(store: store, after: pruning)
    faviconWriter = writer
    window.onFaviconChanged = { [weak writer] id, data in writer?.record(data, for: id) }
    Task { [weak self] in
      await pruning?.value
      let loaded = await store.loadAll(for: ids)
      guard let self, let writer = self.faviconWriter else { return }
      self.window.sidebarController.setFavicons(loaded.filter { !writer.touched.contains($0.key) })
      writer.launchLoadDidComplete()
    }
  }

  // MARK: - Arc import (E4c)

  var canImportFromArc: Bool { isArcImportAvailable && !importer.isRunning }

  /// Re-checks whether Arc's sidebar file exists, off the main actor, unless a check is already running. The menu
  /// validation that calls it returns the cached answer; the fresh one applies from the next validation and updates
  /// the empty state's button right away.
  func refreshArcImportAvailability() {
    guard availabilityCheck == nil else { return }
    availabilityCheck = Task { [weak self, arcFiles] in
      let available = await arcFiles.isAvailable()
      guard let self else { return }
      self.availabilityCheck = nil
      if self.isArcImportAvailable != available {
        self.isArcImportAvailable = available
        self.window.isArcImportAvailable = available
      }
    }
  }

  /// File > Import from Arc... and the empty state's button. Reads Arc's folder only now, off the main actor.
  func importFromArc() {
    guard canImportFromArc else { return }
    Task { [weak self] in await self?.runImport() }
  }

  private func runImport() async {
    do {
      let outcome = try await importer.run(arcFiles)
      faviconWriter?.save(outcome.favicons)
      window.sidebarController.setFavicons(outcome.favicons)
      let summary = outcome.summary
      // Counts only, never titles, URLs or paths.
      let (spaces, existing, removed) = (summary.spaces, summary.existingSpaces, summary.previouslyImportedSpaces)
      let (tabs, favorites) = (summary.tabs, summary.favorites)
      let (archived, archiveFailed) = (summary.archiveImported ?? -1, summary.archiveFailed)
      Self.log.notice("arc import spaces \(spaces, privacy: .public) existing \(existing, privacy: .public)")
      Self.log.notice("arc import spaces removed in Arkt \(removed, privacy: .public)")
      Self.log.notice("arc import tabs \(tabs, privacy: .public)")
      Self.log.notice(
        "arc import favorites \(favorites, privacy: .public) archive \(archived, privacy: .public)")
      if archiveFailed { Self.log.error("arc import archive failed") }
      if summary.recordFailed { Self.log.error("arc import record not saved") }
      showSummary(summary)
    } catch ArcImportCoordinatorError.alreadyRunning {
      return
    } catch {
      let (errorType, code) = (String(describing: type(of: error)), (error as NSError).code)
      Self.log.error("arc import failed \(errorType, privacy: .public) \(code, privacy: .public)")
      window.toasts.show(Toast(text: "Couldn't import from Arc."))
    }
  }

  /// Counts only (decision 6d).
  private func showSummary(_ summary: ArcImportSummary) {
    let alert = NSAlert()
    alert.messageText = "Imported from Arc"
    alert.informativeText = summary.lines.joined(separator: "\n")
    alert.addButton(withTitle: "OK")
    if let sheetWindow = window.window {
      alert.beginSheetModal(for: sheetWindow)
    } else {
      alert.runModal()
    }
  }

  // MARK: - Termination

  /// True while a sidebar change is unsaved or being written, or a favicon batch is pending. E5a adds the archive
  /// outbox.
  var needsFlush: Bool { autosaver.needsFlush || (faviconWriter?.needsFlush ?? false) }

  /// Stamps visible tabs before the flush (decision 10). E5b fills it in once the window reports its visible nodes.
  func prepareForTermination() {}

  /// Writes what is pending, bounded by the autosaver's flush timeout; favicons get at most `faviconFlushTimeout`
  /// more (they are re-fetched by the engine anyway). E5a also flushes the archive outbox.
  func flush() async -> Bool {
    let favicons = Task { [faviconWriter] in
      if let faviconWriter { await faviconWriter.flush() }
    }
    let saved = await autosaver.flush()
    await Self.wait(for: favicons, atMost: Self.faviconFlushTimeout)
    return saved
  }

  static let faviconFlushTimeout: Duration = .seconds(1)

  private static func wait(for task: Task<Void, Never>, atMost timeout: Duration) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await task.value }
      group.addTask { try? await Task.sleep(for: timeout) }
      await group.next()
      group.cancelAll()
    }
  }
}
