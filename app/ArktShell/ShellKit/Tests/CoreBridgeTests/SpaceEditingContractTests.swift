import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// New Space after the current one, rename and reorder (#106: BH-037, BH-038, BH-039), on both sources.
@MainActor
struct SpaceEditingContractTests {
  /// A source with Spaces A, B, C and a recorder attached after they were added.
  @MainActor
  private final class Fixture {
    let source: any SidebarSource
    let ids: [SpaceID]
    var changes: [SidebarChange] = []
    private var observation: SidebarObservation?

    init(_ kind: SourceKind) throws {
      let source = kind.make()
      self.source = source
      ids = try ["A", "B", "C"].map { try source.addSpace(title: $0) }
      observation = source.observe { [unowned self] in self.changes.append($0) }
    }
  }

  // MARK: - New Space

  @Test(arguments: SourceKind.allCases)
  func addSpaceAfterInsertsDirectlyAfterThatSpace(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let new = try fixture.source.addSpace(title: "Space 1", after: fixture.ids[1])
    #expect(fixture.source.spaceOrder == [fixture.ids[0], fixture.ids[1], new, fixture.ids[2]])
    #expect(fixture.source.space(new)?.title == "Space 1")
    #expect(fixture.source.space(new)?.profile == "default")
    #expect(fixture.changes == [.spaceAdded(new)], "the others keep their relative order, so none moved")
  }

  @Test(arguments: SourceKind.allCases)
  func addSpaceAfterTheLastSpaceAppends(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let new = try fixture.source.addSpace(title: "N", after: fixture.ids[2])
    #expect(fixture.source.spaceOrder == fixture.ids + [new])
  }

  @Test(arguments: SourceKind.allCases)
  func addSpaceAfterNilOrAnUnknownSpaceAppends(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let first = try fixture.source.addSpace(title: "N1", after: nil)
    let second = try fixture.source.addSpace(title: "N2", after: SpaceID())
    #expect(fixture.source.spaceOrder == fixture.ids + [first, second])
    #expect(fixture.changes == [.spaceAdded(first), .spaceAdded(second)])
  }

  // MARK: - Rename

  @Test(arguments: SourceKind.allCases)
  func renameSpaceChangesTheTitleAndEmitsSpaceChanged(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    fixture.source.renameSpace(fixture.ids[1], to: "Research")
    #expect(fixture.source.space(fixture.ids[1])?.title == "Research")
    #expect(fixture.changes == [.spaceChanged(fixture.ids[1])])
  }

  @Test(arguments: SourceKind.allCases)
  func renameToTheSameTitleOrOfAnUnknownSpaceEmitsNothing(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    fixture.source.renameSpace(fixture.ids[0], to: "A")
    fixture.source.renameSpace(SpaceID(), to: "X")
    #expect(fixture.changes.isEmpty)
  }

  // MARK: - Reorder

  @Test(arguments: SourceKind.allCases)
  func moveSpaceReordersAndEmitsSpaceMoved(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    fixture.source.moveSpace(fixture.ids[0], to: 2)
    #expect(fixture.source.spaceOrder == [fixture.ids[1], fixture.ids[0], fixture.ids[2]])
    #expect(fixture.changes == [.spaceMoved(fixture.ids[0])])
  }

  @Test(arguments: SourceKind.allCases)
  func moveSpaceToItsOwnPlaceOrOfAnUnknownSpaceEmitsNothing(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    fixture.source.moveSpace(fixture.ids[1], to: 1)
    fixture.source.moveSpace(fixture.ids[1], to: 2)
    fixture.source.moveSpace(SpaceID(), to: 0)
    #expect(fixture.source.spaceOrder == fixture.ids)
    #expect(fixture.changes.isEmpty)
  }

  // MARK: - Persistence

  /// Every edit reaches `onDidChange` once, the hook the app wires to `SidebarAutosaver.scheduleSave`.
  @Test func everyEditReachesTheAutosaveHookOnce() throws {
    let source = ModelSidebarSource()
    let a = try source.addSpace(title: "A")
    var saved: [SidebarModel.Sidebar] = []
    source.onDidChange = { saved.append($0) }

    let b = try source.addSpace(title: "Space 1", after: a)
    source.renameSpace(b, to: "B")
    source.moveSpace(b, to: 0)
    source.renameSpace(b, to: "B")                    // unchanged: no save
    source.setIcon(b, to: SpaceIconInfo(symbol: "star"))
    source.setTheme(b, to: Self.persistedTheme)
    source.setIcon(b, to: SpaceIconInfo(symbol: "star"))   // unchanged: no save
    source.setTheme(b, to: Self.persistedTheme)            // unchanged: no save

    #expect(saved.count == 5)
    #expect(saved.last?.spaceOrder == [b, a])
    #expect(saved.last?.spaces[b]?.title == "B")
    #expect(saved.last?.spaces[b]?.icon == SidebarModel.SpaceIcon(symbol: "star"))
    #expect(saved.last?.spaces[b]?.theme?.isDark == true)
  }

  /// sRGB, no texture: `BridgeMapping` reads that back as the same `SpaceThemeInfo` (the menu checkmark).
  private static let persistedTheme = SpaceThemeInfo(
    baseColors: [.srgb(hex: 0x3A4158), .srgb(hex: 0x1C2030)], isDark: true)

  @Test(arguments: SourceKind.allCases)
  func setIconAndThemeEmitSpaceChangedAndRoundTrip(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let id = fixture.ids[1]
    fixture.source.setIcon(id, to: SpaceIconInfo(symbol: "star"))
    fixture.source.setTheme(id, to: Self.persistedTheme)
    fixture.source.setIcon(id, to: SpaceIconInfo(symbol: "star"))
    fixture.source.setTheme(id, to: Self.persistedTheme)
    fixture.source.setIcon(SpaceID(), to: SpaceIconInfo(symbol: "bolt"))
    fixture.source.setTheme(SpaceID(), to: Self.persistedTheme)
    #expect(fixture.source.space(id)?.icon == SpaceIconInfo(symbol: "star"))
    #expect(fixture.source.space(id)?.theme == Self.persistedTheme)
    #expect(fixture.changes == [.spaceChanged(id), .spaceChanged(id)])

    fixture.source.setIcon(id, to: nil)
    #expect(fixture.source.space(id)?.icon == nil)
    #expect(fixture.changes == [.spaceChanged(id), .spaceChanged(id), .spaceChanged(id)])
  }
}
