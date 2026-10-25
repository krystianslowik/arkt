import Archive
import ArcImport
import CoreBridge
import Foundation
import SidebarModel
import Testing

/// Arc import against copies of the synthetic fixtures in a temp folder (never real Arc data). The fixture has two
/// default-profile Spaces (Alpha: pinned folder with 2 tabs and a split with 2 tabs, 1 Today tab; Beta: 1 pinned tab,
/// a skipped easel, 1 Today tab) and 2 Favorites.
@MainActor
struct ArcImportCoordinatorTests {
  static let importTime = Date(timeIntervalSinceReferenceDate: 900_000_000)
  static let profileOnlyURL = "https://example.com/profile-only"

  struct Harness {
    let source: ModelSidebarSource
    let archive: FakeArchiveStore
    let state: FakeArchiveState
    let records: FakeArcImportRecordStore
    let coordinator: ArcImportCoordinator

    let persist: FakeSidebarPersist

    @MainActor
    init(source: ModelSidebarSource = ModelSidebarSource(), records: FakeArcImportRecordStore = .init()) {
      self.source = source
      archive = FakeArchiveStore()
      state = FakeArchiveState()
      self.records = records
      let persist = FakeSidebarPersist()
      self.persist = persist
      coordinator = ArcImportCoordinator(
        source: source, archive: archive, archiveState: state, importRecord: records,
        persistSidebar: { await persist.persist(source.sidebar) },
        now: { ArcImportCoordinatorTests.importTime })
    }
  }

  /// Every Arc Space and top-level Favorite id in the synthetic fixture.
  static let fixtureRecord = ArcImportRecord(
    spaceIDs: [ArcFixtureFolder.alphaID, ArcFixtureFolder.betaID],
    favoriteItemIDs: [ArcFixtureFolder.mailFavoriteID, ArcFixtureFolder.calendarFavoriteID])

  static func children(_ sidebar: SidebarModel.Sidebar, _ location: Location) -> [NodeSnapshot] {
    sidebar.children(of: location).compactMap { sidebar.snapshot(of: $0) }
  }

  static func url(_ snapshot: NodeSnapshot) -> URL? {
    if case .tab(let tab) = snapshot.kind { return tab.url }
    return nil
  }

  // MARK: First import

  @Test func firstImportFillsEmptySidebarAndArchiveAndResetsClock() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    let summary = outcome.summary
    let sidebar = harness.source.sidebar

    #expect(summary.spaces == 2 && sidebar.spaces.count == 2)
    #expect(summary.existingSpaces == 0)
    #expect(summary.tabs == 7)
    #expect(summary.folders == 1)
    #expect(summary.splits == 1)
    #expect(summary.favorites == 2)
    #expect(summary.skipped >= 1)                           // the easel
    #expect(sidebar.spaces.values.allSatisfy { $0.profile == "default" })
    #expect(await harness.archive.addCalls.map(\.policy) == [.keepExisting])
    let stored = await harness.archive.stored.count
    #expect(stored > 0 && summary.archiveImported == stored)
    #expect(await harness.state.resets == [Self.importTime])
    #expect(outcome.favicons.count == 1)
    #expect(outcome.favicons.values.first == ArcFixtureFolder.favicon)
    #expect(outcome.favicons.keys.allSatisfy { sidebar.nodes[$0] != nil })
    #expect(await harness.records.stored == Self.fixtureRecord)
    #expect(try arc.unchanged())
  }

  // MARK: Re-import (user decision 2)

  @Test func reimportOfTheSameFileAddsNothingAndKeepsTheClock() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    _ = try await harness.coordinator.run(arc.files)
    let afterFirst = harness.source.sidebar
    let outcome = try await harness.coordinator.run(arc.files)

    #expect(harness.source.sidebar == afterFirst)
    #expect(outcome.summary.spaces == 0)
    #expect(outcome.summary.existingSpaces == 2)
    #expect(outcome.summary.favorites == 0)
    #expect(outcome.summary.duplicateFavorites == 0)
    #expect(outcome.summary.previouslyImportedFavorites == 2)
    #expect(outcome.summary.archiveImported == 0)
    #expect(outcome.favicons.isEmpty)
    #expect(await harness.archive.addCalls.map(\.policy) == [.keepExisting, .keepExisting])
    #expect(await harness.state.resets.count == 1)          // archive-only re-imports keep the clock
    #expect(try arc.unchanged())
  }

  /// E5d: the running auto-archive timer learns the new clock before the merged Today tabs reach the sidebar, so no
  /// tick in between can archive them with the old clock; an archive-only re-import does not report a reset.
  @Test func clockResetIsReportedBeforeTheMerge() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    var reported: [(date: Date, spacesAtReport: Int)] = []
    let source = harness.source
    harness.coordinator.onAutoArchiveClockReset = { reported.append(($0, source.sidebar.spaces.count)) }

    _ = try await harness.coordinator.run(arc.files)
    _ = try await harness.coordinator.run(arc.files)

    #expect(reported.map(\.date) == [Self.importTime])
    #expect(reported.map(\.spacesAtReport) == [0])
  }

  @Test func reimportAddsMissingSpacesAndLeavesTheRestAlone() async throws {
    let withoutBeta = try ArcFixtureFolder { global in
      try ArcFixtureFolder.removeEntry(ArcFixtureFolder.betaID, in: "spaces", of: &global)
    }
    let full = try ArcFixtureFolder()
    let harness = Harness()
    _ = try await harness.coordinator.run(withoutBeta.files)
    let alpha = try #require(UUID(uuidString: ArcFixtureFolder.alphaID))
    let beta = try #require(UUID(uuidString: ArcFixtureFolder.betaID))
    #expect(harness.source.sidebar.spaces[beta] == nil)
    let userSpace = try harness.source.addSpace(title: "Mine")
    let alphaPinned = Self.children(harness.source.sidebar, .pinned(alpha))
    let alphaToday = Self.children(harness.source.sidebar, .today(alpha))
    let nodesBefore = harness.source.sidebar.nodes.count

    let outcome = try await harness.coordinator.run(full.files)
    let sidebar = harness.source.sidebar

    #expect(outcome.summary.spaces == 1)
    #expect(outcome.summary.existingSpaces == 1)
    #expect(outcome.summary.tabs == 2)
    #expect(sidebar.spaceOrder == [alpha, userSpace, beta])
    #expect(Self.children(sidebar, .pinned(alpha)) == alphaPinned)
    #expect(Self.children(sidebar, .today(alpha)) == alphaToday)
    #expect(sidebar.children(of: .pinned(beta)).count == 1)
    #expect(sidebar.children(of: .today(beta)).count == 1)
    #expect(sidebar.nodes.count == nodesBefore + 2)
    #expect(await harness.state.resets == [Self.importTime, Self.importTime])   // new Today tabs get a full threshold
    #expect(outcome.favicons.count == 1)                                          // Beta's Today tab
    #expect(outcome.favicons.keys.allSatisfy { sidebar.children(of: .today(beta)).contains($0) })
  }

  @Test func archiveSourcesMapToTheSameSpacesOnReimport() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    _ = try await harness.coordinator.run(arc.files)
    _ = try await harness.coordinator.run(arc.files)
    let items = await harness.archive.stored.values
    var spaceSources = 0
    for item in items {
      guard case .space(let id) = item.source else { continue }
      spaceSources += 1
      #expect(harness.source.sidebar.spaces[id] != nil)
    }
    #expect(spaceSources > 0)
  }

  // MARK: Re-import adds only Arc items never imported before (user decision, 2026-10-23)

  @Test func favoriteDeletedInArktIsNotRestored() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    _ = try await harness.coordinator.run(arc.files)
    let favorite = try #require(harness.source.sidebar.children(of: .favorites(profile: "default")).first)
    harness.source.mutate { $0.remove(favorite) }
    let afterDelete = harness.source.sidebar

    let outcome = try await harness.coordinator.run(arc.files)

    #expect(harness.source.sidebar == afterDelete)
    #expect(outcome.summary.favorites == 0 && outcome.summary.previouslyImportedFavorites == 2)
  }

  @Test func recordedSpacesMissingFromArktAreNotRestoredAndKeepTheClock() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness(records: FakeArcImportRecordStore(Self.fixtureRecord))

    let outcome = try await harness.coordinator.run(arc.files)

    #expect(harness.source.sidebar == SidebarModel.Sidebar())
    #expect(outcome.summary.spaces == 0 && outcome.summary.previouslyImportedSpaces == 2)
    #expect(outcome.summary.favorites == 0 && outcome.summary.previouslyImportedFavorites == 2)
    #expect(outcome.summary.lines.contains("2 Spaces imported before and removed in Arkt not restored"))
    #expect(await harness.state.resets.isEmpty)
    #expect(outcome.favicons.isEmpty)
    #expect(await harness.archive.addCalls.count == 1)        // the archive part still runs
  }

  @Test func importFromBeforeTheRecordFallsBackToMatchingThenRecords() async throws {
    let arc = try ArcFixtureFolder()
    let earlier = Harness()
    _ = try await earlier.coordinator.run(arc.files)
    // The same sidebar, but nothing recorded: the import that filled it ran before the record existed.
    let harness = Harness(source: earlier.source)
    let afterFirst = harness.source.sidebar

    let outcome = try await harness.coordinator.run(arc.files)

    #expect(harness.source.sidebar == afterFirst)
    #expect(outcome.summary.existingSpaces == 2 && outcome.summary.duplicateFavorites == 2)
    #expect(await harness.records.stored == Self.fixtureRecord)
    #expect(await harness.state.resets.isEmpty)
  }

  @Test func failedRecordLoadThrowsBeforeAnythingChanges() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    await harness.records.setFailsLoads(true)
    await #expect(throws: FakeStoreError.self) { try await harness.coordinator.run(arc.files) }
    #expect(harness.source.sidebar == SidebarModel.Sidebar())
    #expect(await harness.state.resets.isEmpty)
    #expect(await harness.archive.addCalls.isEmpty)
  }

  @Test func recordIsWrittenOnlyAfterTheMergedSidebarIsSaved() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    // The sidebar the persist hook saw already held the merged Spaces.
    #expect(harness.persist.saved.map(\.spaces.count) == [2])
    #expect(!outcome.summary.recordFailed)
    #expect(await harness.records.stored == Self.fixtureRecord)
  }

  @Test func unsavedSidebarRecordsNothingAndIsReported() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    harness.persist.succeeds = false
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.summary.spaces == 2 && harness.source.sidebar.spaces.count == 2)
    #expect(outcome.summary.recordFailed)
    #expect(await harness.records.writes.isEmpty)
    #expect(outcome.summary.archiveImported != nil)            // the archive part still runs
  }

  @Test func failedRecordWriteKeepsTheImportAndIsReported() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    await harness.records.setFailsWrites(true)
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.summary.spaces == 2)
    #expect(outcome.summary.recordFailed)
    #expect(outcome.summary.archiveImported != nil)
  }

  // MARK: Profiles (user decision 3)

  @Test func otherProfileSpacesAndFavoritesMergeIntoDefault() async throws {
    let customProfile: [String: Any] = ["custom": ["_0": ["directoryBasename": "Profile 1"]]]
    let containerID = "A0000000-0000-4000-8000-000000000401"
    let duplicateID = "A0000000-0000-4000-8000-000000000411"
    let newID = "A0000000-0000-4000-8000-000000000412"
    func tab(_ id: String, _ url: String) -> [String: Any] {
      ["id": id, "parentID": containerID, "childrenIds": [], "title": NSNull(), "createdAt": 780000200.0,
       "data": ["tab": ["savedURL": url, "savedTitle": "T", "timeLastActiveAt": 790000000.0]]]
    }
    let arc = try ArcFixtureFolder { global in
      try ArcFixtureFolder.mutateEntry(ArcFixtureFolder.betaID, in: "spaces", of: &global) {
        $0["profile"] = customProfile
      }
      try ArcFixtureFolder.appendEntry(customProfile, containerID, in: "topAppsContainerIDs", of: &global)
      let container: [String: Any] = [
        "id": containerID, "parentID": NSNull(), "childrenIds": [duplicateID, newID], "title": NSNull(),
        "createdAt": 780000200.0,
        "data": ["itemContainer": ["containerType": ["topApps": ["_0": customProfile]]]],
      ]
      try ArcFixtureFolder.appendEntry(containerID, container, in: "items", of: &global)
      try ArcFixtureFolder.appendEntry(duplicateID, tab(duplicateID, "https://example.com/mail"), in: "items", of: &global)
      try ArcFixtureFolder.appendEntry(newID, tab(newID, Self.profileOnlyURL), in: "items", of: &global)
    }
    let harness = Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    let sidebar = harness.source.sidebar

    #expect(sidebar.spaces.count == 2)
    #expect(sidebar.spaces.values.allSatisfy { $0.profile == "default" })
    #expect(outcome.summary.otherProfileSpaces == 1)
    let favorites = Self.children(sidebar, .favorites(profile: "default")).compactMap(Self.url)
    #expect(favorites.map(\.absoluteString) == [
      "https://example.com/mail", "https://example.com/calendar", Self.profileOnlyURL,
    ])
    #expect(outcome.summary.favorites == 3)
    #expect(outcome.summary.duplicateFavorites == 1)
    #expect(sidebar.childOrder.keys.allSatisfy { location in
      if case .favorites(let profile) = location { return profile == "default" }
      return true
    })
  }

  // MARK: Failures

  @Test func missingArchiveFileStillImportsSidebar() async throws {
    let arc = try ArcFixtureFolder(includeArchive: false)
    let harness = Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.summary.spaces == 2)
    #expect(outcome.summary.archiveImported == nil)
    #expect(await harness.archive.addCalls.isEmpty)
  }

  @Test(arguments: [Data("not json".utf8), Data(#"{"version": 99, "items": []}"#.utf8)])
  func unreadableArchiveFileKeepsTheSidebarAndIsReported(_ archiveFile: Data) async throws {
    let arc = try ArcFixtureFolder(archive: archiveFile)
    let harness = Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.summary.spaces == 2 && harness.source.sidebar.spaces.count == 2)
    #expect(outcome.summary.archiveFailed)
    #expect(outcome.summary.archiveImported == nil)
    #expect(outcome.summary.lines.contains("0 archived items: the Archive could not be imported"))
    #expect(await harness.archive.addCalls.isEmpty)
    #expect(try arc.unchanged())
  }

  @Test func undecodableSidebarThrowsAndChangesNothing() async throws {
    let arc = try ArcFixtureFolder(sidebar: Data("not json".utf8))
    let harness = Harness()
    await #expect(throws: (any Error).self) { try await harness.coordinator.run(arc.files) }
    #expect(harness.source.sidebar == SidebarModel.Sidebar())
    #expect(await harness.state.resets.isEmpty)
    #expect(await harness.archive.addCalls.isEmpty)
  }

  @Test func failedClockResetThrowsBeforeTheSidebarChanges() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    await harness.state.setFailsResets(true)
    await #expect(throws: FakeStoreError.self) { try await harness.coordinator.run(arc.files) }
    #expect(harness.source.sidebar == SidebarModel.Sidebar())
    #expect(await harness.archive.addCalls.isEmpty)
  }

  @Test func failedArchiveWriteKeepsTheSidebarAndIsReported() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    await harness.archive.setFailsAdds(true)
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.summary.spaces == 2)
    #expect(outcome.summary.archiveFailed)
    #expect(outcome.summary.archiveImported == nil)
    #expect(outcome.summary.lines.contains { $0.contains("Archive") })
  }

  @Test func secondRunWhileOneIsRunningIsRefused() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    let files = arc.files
    let first = Task { try await harness.coordinator.run(files) }   // main actor: suspends in the off-main read
    for _ in 0..<100 where !harness.coordinator.isRunning { await Task.yield() }
    #expect(harness.coordinator.isRunning)
    await #expect(throws: ArcImportCoordinatorError.alreadyRunning) { try await harness.coordinator.run(files) }
    #expect(try await first.value.summary.spaces == 2)
    #expect(!harness.coordinator.isRunning)
  }

  // MARK: Summary

  @Test func summaryLinesAreCountsOnly() async throws {
    let arc = try ArcFixtureFolder()
    let harness = Harness()
    let first = try await harness.coordinator.run(arc.files).summary
    let second = try await harness.coordinator.run(arc.files).summary
    for line in first.lines + second.lines {
      #expect(line.contains { $0.isNumber }, "\(line)")
      for text in ArcFixtureFolder.userStrings { #expect(!line.contains(text), "\(line)") }
    }
    #expect(first.lines.first == "2 Spaces, 7 tabs, 1 folder, 1 split")
    #expect(second.lines.first == "0 new Spaces: all 2 Spaces are already in Arkt")
  }

  @Test func availabilityIsAnExistenceCheck() async throws {
    let arc = try ArcFixtureFolder()
    let files = arc.files
    #expect(await files.isAvailable())
    let empty = ArcSourceFiles(directory: arc.url.appendingPathComponent("missing", isDirectory: true))
    #expect(await !empty.isAvailable())
  }
}
