import ArcImport
import CoreBridge
import Foundation
import SidebarModel
import Testing

/// The first run's read-only count pass (onboarding spec, section 15, item 1; decision 1): Spaces, pinned tabs,
/// Favorites and folders, rising as the pass walks the Spaces. Nothing is written, nothing but counts comes out.
@MainActor
struct ArcImportCountTests {
  /// The synthetic fixture: Alpha's pinned folder holds 2 tabs and a split of 2, Beta has 1 pinned tab; 2 Favorites;
  /// 1 folder.
  static let fixtureCounts = ArcImportCounts(spaces: 2, pinnedTabs: 5, favorites: 2, folders: 1)

  @Test func countsTheFixture() async throws {
    let arc = try ArcFixtureFolder()
    var updates: [ArcImportCounts] = []
    for try await counts in ArcImportCounter.counts(arc.files) { updates.append(counts) }
    #expect(updates.last == Self.fixtureCounts)
    #expect(try arc.unchanged())
  }

  /// The numbers rise: one update per Space, then the Favorites; never down.
  @Test func countsRiseSpaceBySpace() async throws {
    let arc = try ArcFixtureFolder()
    var updates: [ArcImportCounts] = []
    for try await counts in ArcImportCounter.counts(arc.files) { updates.append(counts) }
    #expect(updates.count == 3)
    #expect(updates.map(\.spaces) == [1, 2, 2])
    for (a, b) in zip(updates, updates.dropFirst()) {
      #expect(b.spaces >= a.spaces && b.pinnedTabs >= a.pinnedTabs && b.favorites >= a.favorites
              && b.folders >= a.folders)
    }
  }

  @Test func aMissingFileThrows() async throws {
    let empty = FileManager.default.temporaryDirectory.appendingPathComponent("ArcCountEmpty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    await #expect(throws: (any Error).self) {
      for try await _ in ArcImportCounter.counts(ArcSourceFiles(directory: empty)) {}
    }
  }

  @Test func countsAreOnlyNumbers() {
    let text = String(describing: Self.fixtureCounts)
    for user in ArcFixtureFolder.userStrings { #expect(!text.contains(user)) }
  }

  /// The pure count over a sidebar value: pinned tabs nested in folders and splits count, Today tabs do not.
  @Test func pureCountOverASidebar() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "S")
    let blank = try #require(URL(string: "about:blank"))
    let folder = try sidebar.addFolder(title: "F", in: .pinned(space))
    try sidebar.addTab(url: blank, title: "t", in: .folder(folder))
    try sidebar.addTab(url: blank, title: "t", in: .today(space))
    try sidebar.addTab(url: blank, title: "t", in: .favorites(profile: "default"))
    let counts = ArcImportCounter.count(sidebar)
    #expect(counts.last == ArcImportCounts(spaces: 1, pinnedTabs: 1, favorites: 1, folders: 1))
  }
}

/// The first imported Space, for Make it yours and for landing in the browser after an import.
@MainActor
struct ArcImportFirstSpaceTests {
  @Test func firstImportReportsTheFirstAddedSpace() async throws {
    let arc = try ArcFixtureFolder()
    let harness = ArcImportCoordinatorTests.Harness()
    let outcome = try await harness.coordinator.run(arc.files)
    #expect(outcome.addedSpaces.count == 2)
    #expect(outcome.addedSpaces.first == StableID.uuid(forArcID: ArcFixtureFolder.alphaID))
    #expect(outcome.addedSpaces == harness.source.sidebar.spaceOrder)
  }

  @Test func reimportAddsNoSpace() async throws {
    let arc = try ArcFixtureFolder()
    let harness = ArcImportCoordinatorTests.Harness()
    _ = try await harness.coordinator.run(arc.files)
    let again = try await harness.coordinator.run(arc.files)
    #expect(again.addedSpaces.isEmpty)
  }
}
