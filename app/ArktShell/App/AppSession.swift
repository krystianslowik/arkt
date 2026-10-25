import AppKit
import Archive
import CoreBridge
import EngineAPI
import Persistence
import ShellUI
import SidebarModel
import os

/// The open data: the database, the autosaver, backups and the browser windows. `AppComposition` builds it once the
/// data folder loaded. Only the app target imports `Persistence`.
@MainActor
final class AppSession {
  static let log = Logger(subsystem: "dev.arkt.shell", category: "session")
  /// Rolling backups while the sidebar changed (decision 5).
  static let backupInterval: TimeInterval = 30 * 60

  let location: DatabaseLocation
  let database: ArktDatabase
  let source: ModelSidebarSource
  let autosaver: SidebarAutosaver
  /// Every browser window: the launch window, New Window, a Dock reopen after the last one closed (#241), and the
  /// windows the engine asks for (Chromium: a Dock reopen, `chrome.windows.create`, a startup URL). A closed window is
  /// never shown again.
  let windows: ShellWindowSet
  /// One instance for every window, so Show / Hide Toolbar reaches all of them.
  let toolbarSetting = ToolbarSetting(defaults: AppEnvironment.userDefaults)
  let archiveStore: ArchiveStore
  let settingsStore: SettingsStore
  let importer: ArcImportCoordinator
  /// Archive and restore: the model first, then an outbox to `archiveStore` (decision 11).
  let archive: ArchiveCoordinator
  /// The auto-archive pass every minute (E5d).
  let autoArchive: AutoArchiveTimer
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

  /// `hostLookup` pairs the engine's own windows with the windows built for them (`ChromiumEngine.host(of:)`); nil
  /// for an engine that never asks for a window (FakeEngine).
  init(state: LaunchState, location: DatabaseLocation, engine: any EngineClient, faviconStore: FaviconStore?,
       hostLookup: ShellWindowSet.HostLookup? = nil) {
    self.location = location
    self.database = state.database
    let source = ModelSidebarSource(sidebar: state.sidebar ?? SidebarModel.Sidebar())
    self.source = source
    // Toolbar on / off is an app-level setting in the user defaults (`topBarURLEnabled`; Debug test runs use the
    // `ARKT_DEFAULTS_SUITE` suite), not in the database: see ToolbarSetting.
    self.windows = ShellWindowSet(engine: engine, sidebar: source, toolbarSetting: toolbarSetting,
                                  hostLookup: hostLookup)
    let archiveStore = ArchiveStore(database: state.database)
    let settingsStore = SettingsStore(database: state.database)
    self.archiveStore = archiveStore
    self.settingsStore = settingsStore
    let autosaver = SidebarAutosaver(store: SidebarStore(database: state.database),
                                     delay: AppEnvironment.autosaveDelay)
    self.autosaver = autosaver
    self.importer = ArcImportCoordinator(
      source: source, archive: archiveStore, archiveState: settingsStore, importRecord: settingsStore,
      persistSidebar: { await autosaver.flush() })     // the import record waits for the merged sidebar on disk
    let archive = ArchiveCoordinator(source: source, store: archiveStore)
    self.archive = archive
    autosaver.beforeSave = { [weak archive] in await archive?.flushPendingAdds() ?? true }
    self.autoArchive = AutoArchiveTimer(coordinator: archive, state: settingsStore)
    self.faviconStore = faviconStore
    source.onDidChange = { [weak self] sidebar in
      guard let self else { return }
      autosaver.scheduleSave(sidebar)                 // every model change
      changedSinceBackup = true
    }
    windows.configure = { [weak self] controller in self?.wire(controller) }
  }

  /// `defersWindows`: the launch window and auto-archive wait for `finishLaunch(opensWindow:)` (the Chromium engine
  /// calls it after `embedderReady`, when the windows it queued exist).
  func start(outcome: OpenOutcome, defersWindows: Bool = false) {
    startFavicons(prune: outcome == .opened)          // before a window can create engine tabs
    launchNotice = Self.notice(for: outcome)
    if let notice = launchNotice {
      // The notice case only: `OpenOutcome` carries file names, which never go to the log.
      Self.log.notice("launch outcome \(String(describing: notice), privacy: .public)")
    }
    if !defersWindows { finishLaunch(opensWindow: true) }
    refreshArcImportAvailability()
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
    #if DEBUG
    if let phase = AppEnvironment.smokePhase { runSmoke(phase, outcome: outcome) }
    #endif
  }

  /// The recovery notice of this launch; shown in the launch window.
  private var launchNotice: RecoveryNotice?

  /// Opens the launch window (with the launch's recovery notice), then starts auto-archive, so its first pass sees
  /// the shown tab. The Chromium engine passes false when the windows it queued before ready (a startup URL, an
  /// extension's `chrome.windows.create`) opened one already.
  func finishLaunch(opensWindow: Bool) {
    let window = opensWindow ? windows.openWindow() : windows.primary
    if let notice = launchNotice, let window {
      launchNotice = nil
      window.toasts.show(notice.toast) { [location] in
        NSWorkspace.shared.activateFileViewerSelecting([location.directory])
      }
    }
    startAutoArchive()
  }

  /// The app's hooks on every browser window, before it is shown. Its stored favicons load off the main actor
  /// (each window has its own sidebar views); ids the engine reports meanwhile keep the newer one (#91).
  private func wire(_ window: ShellWindowController) {
    window.onImportFromArc = { [weak self] in self?.importFromArc() }
    window.onArchive = { [weak self] ids in self?.archive.archive(ids, reason: .manual) }      // Cmd-W, BH-071
    window.onRemoveSpace = { [weak self] id in self?.archive.removeSpace(id) }                 // #206, decision on #86
    window.onTabHidden = { [weak self] id in self?.source.markInactive([id], at: .now) }       // decision 10
    window.onFaviconChanged = { [weak self] id, data in self?.faviconWriter?.record(data, for: id) }
    window.isArcImportAvailable = isArcImportAvailable
    guard let writer = faviconWriter else { return }
    let load = writer.loadStored(Set(source.sidebar.nodes.keys))
    Task { [weak window] in
      let loaded = await load.value
      window?.sidebarController.setFavicons(loaded)
    }
  }

  /// Dock reopen without a browser window on screen (#241: closing the last window keeps the app running), FakeEngine
  /// only (Chromium sends a `.reopen` window request instead): fronts the primary window, or builds a new one.
  func reopenWindow() { windows.reopen() }

  /// Every open window shows `batch` (imported or restored favicons).
  private func setFavicons(_ batch: [NodeID: Data]) {
    for window in windows.controllers { window.sidebarController.setFavicons(batch) }
  }

  /// The browser window for app-level feedback (the import summary, restore and import toasts): the primary one, built
  /// again first when every window closed (#241), so the feedback is never shown in a closed window.
  private func shownWindow() -> ShellWindowController {
    windows.primary ?? windows.openWindow()
  }

  /// E5d: the visible tab is exempt (BH-076 media-playing tabs join once the engine reports audio state), each
  /// pass that archived something shows the BH-085 toast, and an Arc import that adds a Space restarts the clock for
  /// the running timer before the merged tabs appear (plan decision 7).
  private func startAutoArchive() {
    // A tab whose close a leave-site prompt would hold is skipped too, and retried on the next pass (week-3
    // Decision 11).
    autoArchive.exempt = { [weak self] in self?.windows.autoArchiveExempt ?? [] }   // every window's
    autoArchive.onArchived = { [weak self] archived in
      self?.windows.primary?.toasts.show(Toast(text: ToastText.autoArchived(archived.count)))
    }
    importer.onAutoArchiveClockReset = { [weak self] date in self?.autoArchive.clockDidReset(to: date) }
    resumeAutoArchive()
  }

  /// A quit started and was not cancelled: auto-archive stays stopped.
  private var isTerminating = false

  /// Starts the timer (at launch, and again after a cancelled quit stopped it), unless a quit is under way. A start
  /// while the first one still loads keeps that load going (`AutoArchiveTimer.start`).
  private func resumeAutoArchive() {
    guard !isTerminating else { return }
    Task { [autoArchive] in
      do { try await autoArchive.start() } catch {
        Self.log.error("auto-archive unavailable \(String(describing: type(of: error)), privacy: .public)")
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

  /// Decision 8 plus the launch rules: the prune runs once, at launch, with the node ids loaded from the database
  /// and the ids of every archived node (E5c, `FaviconRetention`), and every favicon write (engine or import) is queued behind it, so the prune can never remove a favicon written
  /// after launch. It runs only when the database opened normally (`prune`): after a restore from backup or an empty
  /// re-creation the loaded sidebar is not the one the favicons were written for, and pruning against it would
  /// delete favicons of nodes the user may get back. The stored favicons are loaded once, without waiting for the
  /// prune (it keeps every sidebar id); ids the engine reported meanwhile keep the newer one (#91).
  private func startFavicons(prune: Bool) {
    guard let store = faviconStore else { return }
    let ids = Set(source.sidebar.nodes.keys)
    // Archived nodes count as kept (E5c), so a restore under the same id gets its favicon back; an unreadable
    // archive skips the prune.
    let pruning: Task<Void, Never>? = prune ? Task { [archiveStore] in
      guard let kept = await FaviconRetention.keptIDs(sidebar: ids, archive: archiveStore) else { return }
      await store.prune(keeping: kept)
    } : nil
    faviconWriter = FaviconWriter(store: store, after: pruning)   // each window loads the stored ones (`wire`)
  }

  // MARK: - Archive window (E5c)

  private var archiveWindow: ArchiveWindowController?

  /// Window > Show Archive: creates the window on first use, then fronts it and reloads its first page.
  func showArchive() {
    if let archiveWindow {
      archiveWindow.show()
      return
    }
    let model = ArchiveListModel(source: source, store: archiveStore, coordinator: archive)
    // The source Space wins; when it is gone the item lands in the Space on screen (BH-157 routing comes later).
    model.currentSpaceProvider = { [weak self] in self?.windows.primary?.currentSpace }
    model.onRestored = { [weak self] restored, text in self?.didRestore(restored, toast: text) }
    model.onRestoreFailed = { [weak self] text in self?.shownWindow().toasts.show(Toast(text: text)) }
    let controller = ArchiveWindowController(dataSource: model)
    archiveWindow = controller
    controller.show()
  }

  /// BH-086: the restore toast in the browser window; "View" focuses the restored item. The item's favicons come
  /// back from the favicon folder (the sidebar dropped them when the item left); ids the engine reports meanwhile
  /// keep the newer one (#91).
  private func didRestore(_ restored: RestoredItem, toast text: String) {
    let window = shownWindow()
    window.toasts.show(Toast(text: text, actionTitle: "View")) { [weak window] in
      guard let window, !window.isClosed else { return }
      window.showWindow(nil)
      window.activate(node: restored.nodeID)
    }
    guard let writer = faviconWriter, let snapshot = source.sidebar.snapshot(of: restored.nodeID) else { return }
    let load = writer.loadStored(Set(FaviconRetention.ids(in: snapshot)))
    Task { [weak self] in
      let loaded = await load.value
      self?.setFavicons(loaded)
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
        for window in self.windows.controllers { window.isArcImportAvailable = available }
      }
    }
  }

  /// File > Import from Arc... and the empty state's button. Reads Arc's folder only now, off the main actor.
  func importFromArc() {
    guard canImportFromArc else { return }
    Task { [weak self] in await self?.runImport() }
  }

  private func runImport() async {
    guard let summary = await performImport() else { return }
    showSummary(summary)
  }

  /// Runs the import and applies its favicons; nil when it was already running or failed (the failure toast is
  /// shown here).
  private func performImport() async -> ArcImportSummary? {
    do {
      let outcome = try await importer.run(arcFiles)
      faviconWriter?.save(outcome.favicons)
      setFavicons(outcome.favicons)
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
      return summary
    } catch ArcImportCoordinatorError.alreadyRunning {
      return nil
    } catch {
      let (errorType, code) = (String(describing: type(of: error)), (error as NSError).code)
      Self.log.error("arc import failed \(errorType, privacy: .public) \(code, privacy: .public)")
      shownWindow().toasts.show(Toast(text: "Couldn't import your browser data."))
      return nil
    }
  }

  /// Counts only (decision 6d).
  private func showSummary(_ summary: ArcImportSummary) {
    let alert = NSAlert()
    alert.messageText = "Import complete"
    alert.informativeText = summary.lines.joined(separator: "\n")
    alert.addButton(withTitle: "OK")
    if let sheetWindow = shownWindow().window {
      alert.beginSheetModal(for: sheetWindow)
    } else {
      alert.runModal()
    }
  }

  // MARK: - Termination

  /// True while a sidebar change is unsaved or being written, an archived entry is not yet in the archive store, or a
  /// favicon batch is pending.
  var needsFlush: Bool {
    autosaver.needsFlush || archive.hasPendingWrites || (faviconWriter?.needsFlush ?? false)
  }

  /// Runs before the termination flush: stops the auto-archive timer, then stamps every window's visible tabs
  /// (decision 10).
  func prepareForTermination() {
    isTerminating = true
    autoArchive.stop()  // stop first: no auto-archive pass may run between the sidebar write and the outbox write
    source.markInactive(windows.visibleNodes, at: .now)
  }

  /// The quit was cancelled (Chromium: a held leave-site prompt, or the user): auto-archive runs again. The visible
  /// tabs keep the stamp `prepareForTermination` wrote; they are stamped again when they stop being visible.
  func terminationCancelled() {
    isTerminating = false
    resumeAutoArchive()
  }

  /// Writes what is pending: the archive outbox first (#213: the on-disk sidebar never gets ahead of the archive
  /// store), then the sidebar, each bounded by its own flush timeout (1 s, decision 11); favicons get at most
  /// `faviconFlushTimeout` more (they are re-fetched by the engine anyway).
  func flush() async -> Bool {
    let favicons = Task { [faviconWriter] in
      if let faviconWriter { await faviconWriter.flush() }
    }
    let archived = await archive.flush()
    let sidebar = archived ? await autosaver.flush() : false
    await Self.wait(for: favicons, atMost: Self.faviconFlushTimeout)
    return sidebar && archived
  }

  /// `flush()` for a quit whose main thread never runs again (#298: Chromium's SIGTERM path blocks the main thread
  /// right after the quit-start seam, then exits). Archive outbox first (#213), then the sidebar, each bounded by its
  /// flush timeout while this thread waits; favicons are skipped (the engine fetches them again).
  func flushBlocking() -> Bool {
    let archived = archive.flushBlocking()
    return archived && autosaver.flushBlocking()
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

#if DEBUG
// MARK: - End-to-end data smoke (E6, Debug builds only)

extension AppSession {
  /// `ARKT_SMOKE=import|verify`: waits for the launch backup (so a quick quit cannot race it), imports on the
  /// `import` phase (no summary sheet), prints one line of counts and case names, then quits through
  /// `NSApp.terminate` like the Quit menu item, so the quit takes the real `applicationShouldTerminate` and flush
  /// path.
  fileprivate func runSmoke(_ phase: AppEnvironment.SmokePhase, outcome: OpenOutcome) {
    Task { [weak self] in
      guard let self else { return }
      await self.lastBackup?.value
      var summary: ArcImportSummary?
      if phase == .import {
        summary = await self.performImport()
      }
      let archive: String
      do {
        archive = String(try await self.archiveStore.items(limit: nil).items.count)
      } catch {
        archive = "failed"
      }
      // The recovery notice is the only toast a launch shows; persistent means the toast is up (decision 4).
      let toast = self.windows.primary?.toasts.current.map { $0.isPersistent ? "persistent" : "timed" } ?? "none"
      let counts = Self.smokeCounts(self.source.sidebar)
      let imported: (added: String, existing: String, archiveAdded: String) = switch (phase, summary) {
      case (.verify, _): ("-", "-", "-")
      case (.import, nil): ("failed", "failed", "failed")
      case (.import, let summary?):
        (String(summary.spaces), String(summary.existingSpaces),
         summary.archiveFailed ? "failed" : summary.archiveImported.map(String.init) ?? "none")
      }
      print([
        "ARKT_SMOKE phase=\(phase.rawValue) outcome=\(Self.caseName(outcome))",
        "spaces=\(counts.spaces) tabs=\(counts.tabs) folders=\(counts.folders) splits=\(counts.splits)",
        "favorites=\(counts.favorites) archive=\(archive)",
        "added=\(imported.added) existing=\(imported.existing) archiveAdded=\(imported.archiveAdded)",
        "toast=\(toast)",
      ].joined(separator: " "))
      fflush(stdout)
      // From the run loop, not from this main-actor job: with `.terminateLater`, `terminate` waits in a nested run
      // loop for the flush Task, which cannot start on the main actor while this job is still running.
      NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }
  }

  /// The case name only: the associated values name files.
  private static func caseName(_ outcome: OpenOutcome) -> String {
    switch outcome {
    case .created: "created"
    case .opened: "opened"
    case .restoredFromBackup: "restoredFromBackup"
    case .recreatedEmpty: "recreatedEmpty"
    }
  }

  /// Every node by kind (Favorites included, like the import check's totals); `favorites` counts the top-level
  /// Favorites.
  private static func smokeCounts(_ sidebar: SidebarModel.Sidebar)
    -> (spaces: Int, tabs: Int, folders: Int, splits: Int, favorites: Int) {
    var counts = (spaces: sidebar.spaceOrder.count, tabs: 0, folders: 0, splits: 0, favorites: 0)
    for node in sidebar.nodes.values {
      switch node.kind {
      case .tab: counts.tabs += 1
      case .folder: counts.folders += 1
      case .split: counts.splits += 1
      }
      if case .favorites = node.parent { counts.favorites += 1 }
    }
    return counts
  }
}
#endif
