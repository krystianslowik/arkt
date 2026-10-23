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

  @Test(arguments: SourceKind.allCases)
  func addSpaceAppendsAndEmitsSpaces(kind: SourceKind) throws {
    let source = kind.make()
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let space = try source.addSpace(title: "S")
    #expect(source.spaceOrder == [space])
    #expect(source.space(space)?.title == "S")
    #expect(source.space(space)?.profile == "default")
    #expect(changes == [.spaces])
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
