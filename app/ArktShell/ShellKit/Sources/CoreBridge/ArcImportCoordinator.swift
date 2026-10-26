import ArcImport
import Archive
import Foundation
import SidebarModel

/// The files of an Arc data folder that the import reads. Nothing here writes.
public struct ArcSourceFiles: Sendable {
  public let directory: URL

  public init(directory: URL) { self.directory = directory }

  public var sidebarFile: URL { directory.appendingPathComponent("StorableSidebar.json", isDirectory: false) }
  public var archiveFile: URL { directory.appendingPathComponent("StorableArchiveItems.json", isDirectory: false) }
  public var faviconDirectory: URL { directory.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true) }

  /// Whether Arc's sidebar file exists. Existence only, never a read (decision 3); off the main actor.
  @concurrent
  public func isAvailable() async -> Bool { FileManager.default.fileExists(atPath: sidebarFile.path) }
}

/// What an import did, as counts only: no titles, URLs or paths (decision 6d).
public struct ArcImportSummary: Equatable, Sendable {
  /// Spaces added; `existingSpaces` were already in Arkt and left unchanged; `previouslyImportedSpaces` were added
  /// by an earlier import and deleted in Arkt since, and are not restored.
  public var spaces = 0
  public var existingSpaces = 0
  public var previouslyImportedSpaces = 0
  /// Added Spaces that came from another Arc profile and were merged into the default profile.
  public var otherProfileSpaces = 0
  public var tabs = 0
  public var folders = 0
  public var splits = 0
  public var favorites = 0
  /// Favorites never imported before whose URL is already a Favorite in Arkt.
  public var duplicateFavorites = 0
  /// Favorites an earlier import handled; skipped even when deleted in Arkt or moved to another URL in Arc.
  public var previouslyImportedFavorites = 0
  /// Arc sidebar items that could not be imported (unsupported, unreadable or refused).
  public var skipped = 0
  /// Archive rows newly written (0 on a re-import); nil when there was no archive file or it failed.
  public var archiveImported: Int?
  public var archiveSkipped = 0
  /// The archive file exists but could not be read (corrupt or an unsupported version) or saved; the sidebar part
  /// was kept.
  public var archiveFailed = false
  /// The Arc ids of this run were not recorded (the merged sidebar could not be saved first, or the record write
  /// failed), so a later import may add items deleted in Arkt again. Logged, not shown: the import itself succeeded.
  public var recordFailed = false

  public init() {}

  /// One line per fact, for the summary sheet and logs.
  public var lines: [String] {
    var lines: [String] = []
    if spaces > 0 {
      lines.append([count(spaces, "Space"), count(tabs, "tab"), count(folders, "folder"), count(splits, "split")]
        .joined(separator: ", "))
    } else if existingSpaces > 0, previouslyImportedSpaces == 0 {
      lines.append("0 new Spaces: all \(count(existingSpaces, "Space")) are already in Arkt")
    } else {
      lines.append("0 Spaces imported")
    }
    if existingSpaces > 0, spaces > 0 || previouslyImportedSpaces > 0 {
      lines.append("\(count(existingSpaces, "Space")) already in Arkt left unchanged")
    }
    if previouslyImportedSpaces > 0 {
      lines.append("\(count(previouslyImportedSpaces, "Space")) imported before and removed in Arkt not restored")
    }
    if otherProfileSpaces > 0 {
      lines.append("\(count(otherProfileSpaces, "Space")) from other profiles added to the default profile")
    }
    var favoritesLine = "\(count(favorites, "favorite")) added"
    if duplicateFavorites > 0 { favoritesLine += ", \(duplicateFavorites) already in Arkt" }
    if previouslyImportedFavorites > 0 { favoritesLine += ", \(previouslyImportedFavorites) imported before" }
    lines.append(favoritesLine)
    if archiveFailed {
      lines.append("0 archived items: the Archive could not be imported")
    } else if let archiveImported {
      lines.append("\(archiveImported) new archived \(archiveImported == 1 ? "item" : "items")")
    } else {
      lines.append("0 archived items: no Archive file")
    }
    let unreadable = skipped + archiveSkipped
    if unreadable > 0 { lines.append("\(count(unreadable, "item")) could not be imported") }
    return lines
  }

  private func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
}

public struct ArcImportOutcome: Sendable {
  public var summary: ArcImportSummary
  /// Favicons of the nodes this import added, by Arkt node id.
  public var favicons: [UUID: Data]
  /// The Spaces this import added, in Arc's order; the first run lands on the first one.
  public var addedSpaces: [UUID] = []
}

public enum ArcImportCoordinatorError: Error, Equatable, Sendable {
  case alreadyRunning
}

/// Everything read from Arc's folder, off the main actor. Reads only; never writes, never lists other files.
enum ArcImportRead {
  struct Bundle: Sendable {
    var sidebar: ArcImportResult
    var archive: ArcArchiveImportResult?
    /// The archive file exists but could not be read, decoded or is a version this importer does not read.
    var archiveUnreadable = false
    /// By Arkt node id, for every imported tab that has a cached favicon.
    var favicons: [UUID: Data]
  }

  @concurrent
  static func read(_ files: ArcSourceFiles) async throws -> Bundle {
    let file = try ArcSidebarFile.decode(Data(contentsOf: files.sidebarFile))
    let sidebar = try ArcSidebarImporter.makeSidebar(from: file)
    var archive: ArcArchiveImportResult?
    var archiveUnreadable = false
    if FileManager.default.fileExists(atPath: files.archiveFile.path) {
      // A bad archive file never costs the sidebar part: it is reported instead.
      do {
        let decoded = try ArcArchiveFile.decode(Data(contentsOf: files.archiveFile))
        try ArcArchiveImporter.checkVersion(decoded)
        archive = ArcArchiveImporter.makeItems(from: decoded, spaceIDsByArcID: sidebar.spaceIDsByArcID)
      } catch {
        archiveUnreadable = true
      }
    }
    let cache = ArcFaviconCache(directory: files.faviconDirectory)
    var favicons: [UUID: Data] = [:]
    for (arcID, nodeID) in sidebar.nodeIDsByArcID {
      guard case .tab? = sidebar.sidebar.nodes[nodeID]?.kind, let png = cache.pngData(forItemID: arcID) else { continue }
      favicons[nodeID] = png
    }
    return Bundle(sidebar: sidebar, archive: archive, archiveUnreadable: archiveUnreadable, favicons: favicons)
  }
}

/// Imports Arc's sidebar, archive and favicons (Track E decision 6, user decisions of 2026-10-23):
/// - Sidebar: merged by `ArcImportMerge` against the stored `ArcImportRecord`: only Arc Spaces and Favorites never
///   imported before are added (Spaces with their trees, into `visibleProfile`; Favorites without duplicate URLs).
///   Spaces already in Arkt are left untouched, and items deleted in Arkt are not restored. Afterwards the Arc ids
///   this run handled are added to the record, but only after `persistSidebar` reports the merged sidebar saved
///   (the app flushes its autosaver), so a crash can never leave ids recorded for items that never reached disk. An
///   unsaved sidebar or a record write failure is reported in the summary (`recordFailed`), not thrown: the sidebar
///   already changed and keeps autosaving.
/// - Clock: when the import adds a Space, the auto-archive clock restarts at the import time first (user decision
///   1), so imported Today tabs, which carry Arc's old `lastActiveAt`, each get a full threshold. A run that adds no
///   Space (archive-only) leaves the clock alone. A failed record load or clock reset aborts before anything
///   changed.
/// - Archive: always, idempotent (`.keepExisting` with Arc's stable item ids). An unreadable archive file or a
///   failed write keeps the sidebar part and is reported in the summary (`archiveFailed`).
/// The in-memory sidebar changes in one `mutate`, so it autosaves through `onDidChange` like any edit.
@MainActor
public final class ArcImportCoordinator {
  public private(set) var isRunning = false
  /// Called with the new auto-archive start right after a run reset it and before the merge, so a running timer
  /// never sees the imported Today tabs with the old clock.
  public var onAutoArchiveClockReset: (@MainActor (Date) -> Void)?
  private let source: ModelSidebarSource
  private let archive: any ArchiveStoring
  private let archiveState: any ArchiveStateStoring
  private let importRecord: any ArcImportRecordStoring
  private let persistSidebar: @MainActor () async -> Bool
  private let visibleProfile: String
  private let now: @MainActor () -> Date

  public init(
    source: ModelSidebarSource, archive: any ArchiveStoring, archiveState: any ArchiveStateStoring,
    importRecord: any ArcImportRecordStoring, persistSidebar: @escaping @MainActor () async -> Bool,
    visibleProfile: String = "default", now: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.source = source
    self.archive = archive
    self.archiveState = archiveState
    self.importRecord = importRecord
    self.persistSidebar = persistSidebar
    self.visibleProfile = visibleProfile
    self.now = now
  }

  /// Throws `ArcImportCoordinatorError.alreadyRunning` while another run is in progress, a sidebar read or decode
  /// error (nothing changed), or the record load's or clock reset's error (nothing changed).
  public func run(_ files: ArcSourceFiles) async throws -> ArcImportOutcome {
    guard !isRunning else { throw ArcImportCoordinatorError.alreadyRunning }
    isRunning = true
    defer { isRunning = false }

    let bundle = try await ArcImportRead.read(files)
    let imported = bundle.sidebar
    let record = try await importRecord.loadArcImportRecord()
    if !ArcImportMerge.missingSpaces(in: imported, comparedTo: source.sidebar, record: record).isEmpty {
      let resetAt = now()
      try await archiveState.resetAutoArchiveStart(to: resetAt)
      onAutoArchiveClockReset?(resetAt)
    }
    // Merged against the sidebar as it is now, after the awaits (the user may have edited it meanwhile).
    var counts = ArcImportMergeCounts()
    source.mutate { counts = ArcImportMerge.merge(imported, into: &$0, profile: visibleProfile, record: record) }
    // The record must never get ahead of the saved sidebar: recorded ids are never imported again, so recording
    // before the merged sidebar is on disk would lose those items for good after a crash or force quit.
    var recordFailed = false
    if !counts.handled.isEmpty {
      if await persistSidebar() {
        do { try await importRecord.recordArcImport(counts.handled, at: now()) } catch { recordFailed = true }
      } else {
        recordFailed = true
      }
    }

    var summary = ArcImportSummary()
    summary.spaces = counts.spaces
    summary.existingSpaces = counts.existingSpaces
    summary.otherProfileSpaces = counts.otherProfileSpaces
    summary.tabs = counts.tabs
    summary.folders = counts.folders
    summary.splits = counts.splits
    summary.favorites = counts.favorites
    summary.duplicateFavorites = counts.duplicateFavorites
    summary.previouslyImportedSpaces = counts.previouslyImportedSpaces
    summary.previouslyImportedFavorites = counts.previouslyImportedFavorites
    summary.recordFailed = recordFailed
    summary.archiveFailed = bundle.archiveUnreadable
    summary.skipped = bundle.sidebar.report.skipped.count + counts.refused
    if let items = bundle.archive {
      summary.archiveSkipped = items.report.skipped.count
      do {
        summary.archiveImported = try await archive.add(items.items, onConflict: .keepExisting)
      } catch {
        summary.archiveFailed = true
      }
    }
    let favicons = bundle.favicons.filter { counts.addedNodes.contains($0.key) }
    return ArcImportOutcome(summary: summary, favicons: favicons, addedSpaces: counts.addedSpaces)
  }
}
