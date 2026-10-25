import CoreBridge
import CoreGraphics
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
    source.setIcon(b, to: .symbol("star"))
    source.setTheme(b, to: Self.persistedTheme)
    source.setIcon(b, to: .symbol("star"))   // unchanged: no save
    source.setTheme(b, to: Self.persistedTheme)            // unchanged: no save

    #expect(saved.count == 5)
    #expect(saved.last?.spaceOrder == [b, a])
    #expect(saved.last?.spaces[b]?.title == "B")
    #expect(saved.last?.spaces[b]?.icon == SidebarModel.SpaceIcon.symbol("star"))
    #expect(saved.last?.spaces[b]?.theme?.isDark == true)

    source.setTheme(b, to: nil)                             // Default (D2): saved as no theme
    source.setTheme(b, to: nil)                             // unchanged: no save
    #expect(saved.count == 6)
    #expect(saved.last?.spaces[b]?.theme == nil)
  }

  /// sRGB, no texture: `BridgeMapping` reads that back as the same `SpaceThemeInfo` (the menu checkmark).
  private static let persistedTheme = SpaceThemeInfo(
    baseColors: [.srgb(hex: 0x3A4158), .srgb(hex: 0x1C2030)], isDark: true)

  @Test(arguments: SourceKind.allCases)
  func setIconAndThemeEmitSpaceChangedAndRoundTrip(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let id = fixture.ids[1]
    fixture.source.setIcon(id, to: .symbol("star"))
    fixture.source.setTheme(id, to: Self.persistedTheme)
    fixture.source.setIcon(id, to: .symbol("star"))
    fixture.source.setTheme(id, to: Self.persistedTheme)
    fixture.source.setIcon(SpaceID(), to: .symbol("bolt"))
    fixture.source.setTheme(SpaceID(), to: Self.persistedTheme)
    #expect(fixture.source.space(id)?.icon == .symbol("star"))
    #expect(fixture.source.space(id)?.theme == Self.persistedTheme)
    #expect(fixture.changes == [.spaceChanged(id), .spaceChanged(id)])

    fixture.source.setIcon(id, to: nil)
    #expect(fixture.source.space(id)?.icon == nil)
    #expect(fixture.changes == [.spaceChanged(id), .spaceChanged(id), .spaceChanged(id)])

    let rocket = SpaceIconInfo.emoji("\u{1F680}")
    fixture.source.setIcon(id, to: rocket)
    #expect(fixture.source.space(id)?.icon == rocket)
    #expect(fixture.changes.count == 4)
  }

  /// D2 on #279: "Default" clears the Space's theme; the Space then draws the source's default and says so.
  @Test(arguments: SourceKind.allCases)
  func setThemeToNilGoesBackToTheDefaultTheme(kind: SourceKind) throws {
    let fixture = try Fixture(kind)
    let id = fixture.ids[1]
    let defaultTheme = try #require(fixture.source.space(id)?.theme)
    #expect(fixture.source.space(id)?.usesDefaultTheme == true, "a new Space has no theme of its own")
    fixture.source.setTheme(id, to: nil)
    #expect(fixture.changes.isEmpty, "already the default")

    fixture.source.setTheme(id, to: Self.persistedTheme)
    #expect(fixture.source.space(id)?.usesDefaultTheme == false)
    fixture.source.setTheme(id, to: nil)
    #expect(fixture.source.space(id)?.usesDefaultTheme == true)
    #expect(fixture.source.space(id)?.theme == defaultTheme)
    #expect(fixture.changes == [.spaceChanged(id), .spaceChanged(id)])
    fixture.source.setTheme(SpaceID(), to: nil)
    #expect(fixture.changes.count == 2)
  }

  /// The model stores sRGB components. A Display P3 color is converted, so it reads back as the same color (#287
  /// review): copying the P3 components into sRGB would shift it.
  @Test func aDisplayP3ThemeColorIsStoredAsTheSameColorInSRGB() throws {
    let source = ModelSidebarSource()
    let id = try source.addSpace(title: "A")
    let p3 = ShellUI.RGBA.p3(hex: 0x3D7BD9, alpha: 1)
    source.setTheme(id, to: SpaceThemeInfo(baseColors: [p3, .p3(hex: 0xF2F0EE, alpha: 1)], isDark: false))
    let stored = try #require(source.sidebar.spaces[id]?.theme?.baseColors.first)
    #expect(abs(stored.red - p3.red) > 0.01, "converted, not copied")

    let readBack = try #require(source.space(id)?.theme.baseColors.first)
    let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let original = try #require(p3.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components)
    let extended = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
    let readColor = try #require(CGColor(
      colorSpace: extended, components: [readBack.red, readBack.green, readBack.blue, readBack.alpha].map { CGFloat($0) }))
    let roundTripped = try #require(readColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components)
    #expect(original.count == roundTripped.count)
    for (want, got) in zip(original, roundTripped) { #expect(abs(want - got) < 0.001) }
  }
}
