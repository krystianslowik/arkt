import CoreBridge
import Foundation
import ShellUI
import Testing

/// The two `SidebarSource` implementations the shell runs on.
enum SourceKind: CaseIterable, Sendable {
  case stub, model

  @MainActor
  func make() -> any SidebarSource { self == .stub ? StubSidebar() : ModelSidebarSource() }
}

/// Behavior every `SidebarSource` must share, run against `StubSidebar` and `ModelSidebarSource`.
@MainActor
struct SidebarSourceContractTests {
  private static let urlA = URL(string: "https://a.example")!
  private static let urlB = URL(string: "https://b.example")!

  @Test(arguments: SourceKind.allCases)
  func addTabAppendsAndEmitsStructure(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let a = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    let b = try source.addTab(url: Self.urlB, title: "B", in: .today(space))
    #expect(source.children(of: .today(space)) == [a, b])
    #expect(source.parent(of: a) == .today(space))
    #expect(changes == [.structure(.today(space)), .structure(.today(space))])
    _ = observation
  }

  /// Cmd-T opens on top (BH-079, #293): a tab added at index 0 lands before its siblings on both sources.
  @Test(arguments: SourceKind.allCases)
  func addTabAtIndexZeroLandsOnTopAndEmitsStructure(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let b = try source.addTab(url: Self.urlB, title: "B", in: .today(space), at: 0)
    #expect(source.children(of: .today(space)) == [b, a])
    #expect(changes == [.structure(.today(space))])
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func addSpaceAppendsAndEmitsSpaceAdded(kind: SourceKind) throws {
    let source = kind.make()
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let space = try source.addSpace(title: "S")
    #expect(source.spaceOrder == [space])
    #expect(source.space(space)?.title == "S")
    #expect(source.space(space)?.profile == "default")
    #expect(changes == [.spaceAdded(space)])
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func updateTabEmitsNodeOnlyWhenDrawnFieldsChange(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    source.updateTab(a, url: nil, title: "A2")
    #expect(changes == [.node(a)])
    #expect(source.node(a) == .tab(id: a, url: Self.urlA, title: "A2"))
    _ = observation
  }

  @Test(arguments: SourceKind.allCases)
  func releasedObservationStopsDelivery(kind: SourceKind) throws {
    let source = kind.make()
    var changes: [SidebarChange] = []
    var observation: SidebarObservation? = source.observe { changes.append($0) }
    _ = observation
    observation = nil
    let space = try source.addSpace(title: "S")
    _ = try source.addTab(url: Self.urlA, title: "A", in: .today(space))
    #expect(changes.isEmpty)
  }

  @Test(arguments: SourceKind.allCases)
  func cancelledObservationStopsDelivery(kind: SourceKind) throws {
    let source = kind.make()
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    observation.cancel()
    _ = try source.addSpace(title: "S")
    #expect(changes.isEmpty)
  }
}

// MARK: - Split writes

/// Split writes every `SidebarSource` must share. The model source reports changes in `SidebarDiff` order; the stub
/// is held to the same set of changes only.
extension SidebarSourceContractTests {
  /// A Space with Today `[a, b]` and the source's change log from that point on.
  @MainActor
  private final class World {
    let source: any SidebarSource
    let kind: SourceKind
    let space: SpaceID
    let a: NodeID
    let b: NodeID
    var changes: [SidebarChange] = []
    private var observation: SidebarObservation?

    init(_ kind: SourceKind) throws {
      self.kind = kind
      source = kind.make()
      space = try source.addSpace(title: "S")
      a = try source.addTab(url: SidebarSourceContractTests.urlA, title: "A", in: .today(space))
      b = try source.addTab(url: SidebarSourceContractTests.urlB, title: "B", in: .today(space))
      observation = source.observe { [unowned self] in self.changes.append($0) }
    }

    /// Today `[split, b]` with panes `[a, pane]`; the change log is cleared afterwards.
    func makeSplit() throws -> (split: NodeID, pane: NodeID) {
      let result = try source.addToSplit(
        .new(url: SidebarSourceContractTests.urlB, title: "N"), target: a, at: 1, orientation: .horizontal)
      changes = []
      return result
    }

    func layout(_ split: NodeID) -> SplitLayoutInfo? {
      guard case .split(_, let layout)? = source.node(split) else { return nil }
      return layout
    }

    /// Exact order for the model source, the same set for the stub.
    func expectChanges(_ expected: [SidebarChange], sourceLocation: SourceLocation = #_sourceLocation) {
      switch kind {
      case .model: #expect(changes == expected, sourceLocation: sourceLocation)
      case .stub:
        #expect(Set(changes) == Set(expected), sourceLocation: sourceLocation)
        #expect(changes.count == expected.count, sourceLocation: sourceLocation)
      }
    }
  }

  private static let halves = SplitLayoutInfo(orientation: .horizontal, widthFactors: [0.5, 0.5])

  @Test(arguments: SourceKind.allCases)
  func addToSplitNewCreatesSplitAtTargetsPlace(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.source.addToSplit(
      .new(url: Self.urlB, title: "N"), target: world.a, at: 1, orientation: .horizontal)
    #expect(world.source.children(of: .today(world.space)) == [split, world.b])
    #expect(world.source.children(of: .split(split)) == [world.a, pane])
    #expect(world.source.node(split) == .split(id: split, layout: Self.halves))
    #expect(world.source.node(pane) == .tab(id: pane, url: Self.urlB, title: "N"))
    #expect(world.source.parent(of: pane) == .split(split))
    world.expectChanges([.structure(.today(world.space)), .structure(.split(split))])
  }

  @Test(arguments: SourceKind.allCases)
  func addToSplitAtIndexZeroPutsThePaneFirst(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.source.addToSplit(
      .existing(world.b), target: world.a, at: 0, orientation: .vertical)
    #expect(world.source.children(of: .today(world.space)) == [split])
    #expect(world.source.children(of: .split(split)) == [world.b, world.a])
    #expect(pane == world.b)
    #expect(world.layout(split) == SplitLayoutInfo(orientation: .vertical, widthFactors: [0.5, 0.5]))
  }

  @Test(arguments: SourceKind.allCases)
  func addToSplitIntoAnExistingSplitEqualizesAndKeepsOrientation(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    let result = try world.source.addToSplit(.existing(world.b), target: pane, at: 1, orientation: .vertical)
    #expect(result.split == split)
    #expect(result.pane == world.b)
    #expect(world.source.children(of: .today(world.space)) == [split])
    #expect(world.source.children(of: .split(split)) == [world.a, world.b, pane])
    let third = 1.0 / 3
    #expect(world.layout(split) == SplitLayoutInfo(orientation: .horizontal, widthFactors: [third, third, third]))
    world.expectChanges([.structure(.today(world.space)), .structure(.split(split)), .node(split)])
  }

  @Test(arguments: SourceKind.allCases)
  func addToSplitFifthThrowsSplitFullAndChangesNothing(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, _) = try world.makeSplit()
    for _ in 0..<2 {
      _ = try world.source.addToSplit(.new(url: Self.urlA, title: "P"), target: split, at: 9, orientation: .horizontal)
    }
    let panes = world.source.children(of: .split(split))
    #expect(panes.count == 4)
    world.changes = []
    #expect(throws: SplitEditError.splitFull) {
      try world.source.addToSplit(.new(url: Self.urlA, title: "Fifth"), target: split, at: 4, orientation: .horizontal)
    }
    #expect(throws: SplitEditError.splitFull) {
      try world.source.addToSplit(.existing(world.b), target: panes[0], at: 0, orientation: .horizontal)
    }
    #expect(world.changes.isEmpty)
    #expect(world.source.children(of: .today(world.space)) == [split, world.b])
    #expect(world.source.children(of: .split(split)) == panes)
  }

  @Test(arguments: SourceKind.allCases)
  func addToSplitRejectsUnknownTargetsAndItself(kind: SourceKind) throws {
    let world = try World(kind)
    #expect(throws: SplitEditError.invalid) {
      try world.source.addToSplit(.new(url: Self.urlA, title: "N"), target: NodeID(), at: 1, orientation: .horizontal)
    }
    #expect(throws: SplitEditError.invalid) {
      try world.source.addToSplit(.existing(world.a), target: world.a, at: 1, orientation: .horizontal)
    }
    #expect(world.changes.isEmpty)
    #expect(world.source.children(of: .today(world.space)) == [world.a, world.b])
  }

  @Test(arguments: SourceKind.allCases)
  func separatePaneKeepsTabAfterSplitAndRescales(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    _ = try world.source.addToSplit(.existing(world.b), target: split, at: 2, orientation: .horizontal)
    try world.source.setSplitWidthFactors(split, [2, 1, 1])
    try world.source.separatePane(world.a)
    #expect(world.source.children(of: .today(world.space)) == [split, world.a])
    #expect(world.source.children(of: .split(split)) == [pane, world.b])
    #expect(world.layout(split)?.widthFactors == [0.5, 0.5])
    #expect(world.source.parent(of: world.a) == .today(world.space))
  }

  @Test(arguments: SourceKind.allCases)
  func separatePaneOfTwoCollapsesToTheSurvivor(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    try world.source.separatePane(world.a)
    #expect(world.source.children(of: .today(world.space)) == [pane, world.a, world.b])
    #expect(world.source.node(split) == nil)
    #expect(world.source.parent(of: pane) == .today(world.space))
    world.expectChanges([.structure(.today(world.space))])
    #expect(throws: SplitEditError.invalid) { try world.source.separatePane(world.b) }
  }

  @Test(arguments: SourceKind.allCases)
  func separateSplitRestoresOrder(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    #expect(try world.source.separateSplit(split) == [world.a, pane])
    #expect(world.source.children(of: .today(world.space)) == [world.a, pane, world.b])
    #expect(world.source.node(split) == nil)
    world.expectChanges([.structure(.today(world.space))])
  }

  @Test(arguments: SourceKind.allCases)
  func expandPaneKeepsFocusedFirst(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    try world.source.expandPane(pane)
    #expect(world.source.children(of: .today(world.space)) == [pane, world.a, world.b])
    #expect(world.source.node(split) == nil)
  }

  @Test(arguments: SourceKind.allCases)
  func movePaneReordersFactorsWithPanes(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    _ = try world.source.addToSplit(.existing(world.b), target: split, at: 2, orientation: .horizontal)
    try world.source.setSplitWidthFactors(split, [2, 1, 1])
    world.changes = []
    try world.source.movePane(world.a, to: 3)
    #expect(world.source.children(of: .split(split)) == [pane, world.b, world.a])
    #expect(world.layout(split)?.widthFactors == [0.25, 0.25, 0.5])
    world.expectChanges([.structure(.split(split)), .node(split)])
  }

  @Test(arguments: SourceKind.allCases)
  func setSplitWidthFactorsEmitsNodeChangeOnly(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, _) = try world.makeSplit()
    try world.source.setSplitWidthFactors(split, [3, 1])
    #expect(world.layout(split)?.widthFactors == [0.75, 0.25])
    world.expectChanges([.node(split)])
    world.changes = []
    #expect(throws: SplitEditError.invalid) { try world.source.setSplitWidthFactors(split, [1]) }
    #expect(throws: SplitEditError.invalid) { try world.source.setSplitWidthFactors(split, [0, 1]) }
    #expect(throws: SplitEditError.invalid) { try world.source.setSplitWidthFactors(split, [.nan, 1]) }
    #expect(world.changes.isEmpty)
    #expect(world.layout(split)?.widthFactors == [0.75, 0.25])
  }

  @Test(arguments: SourceKind.allCases)
  func setSplitOrientationEmitsNodeChange(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, _) = try world.makeSplit()
    try world.source.setSplitOrientation(split, .vertical)
    #expect(world.layout(split) == SplitLayoutInfo(orientation: .vertical, widthFactors: [0.5, 0.5]))
    world.expectChanges([.node(split)])
    #expect(throws: SplitEditError.invalid) { try world.source.setSplitOrientation(world.b, .vertical) }
  }

  @Test(arguments: SourceKind.allCases)
  func duplicateSplitInsertsACopyAfterTheOriginal(kind: SourceKind) throws {
    let world = try World(kind)
    let (split, pane) = try world.makeSplit()
    try world.source.setSplitWidthFactors(split, [3, 1])
    world.changes = []
    let copy = try world.source.duplicateSplit(split)
    #expect(copy != split)
    #expect(world.source.children(of: .today(world.space)) == [split, copy, world.b])
    #expect(world.layout(copy) == world.layout(split))
    let panes = world.source.children(of: .split(copy))
    #expect(panes.count == 2)
    #expect(Set(panes).isDisjoint(with: [world.a, pane]))
    #expect(panes.map { world.source.node($0).map(Self.urlAndTitle) } == [
      world.source.node(world.a).map(Self.urlAndTitle), world.source.node(pane).map(Self.urlAndTitle),
    ])
    world.expectChanges([.structure(.today(world.space)), .structure(.split(copy))])
    #expect(throws: SplitEditError.invalid) { try world.source.duplicateSplit(world.b) }
  }

  private static func urlAndTitle(_ info: SidebarNodeInfo) -> String {
    guard case .tab(_, let url, let title) = info else { return "not a tab" }
    return "\(url.absoluteString) \(title)"
  }
}
