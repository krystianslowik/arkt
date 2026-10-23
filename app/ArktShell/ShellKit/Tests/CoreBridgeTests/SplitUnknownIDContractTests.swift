import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// Split writes given an id the source does not know. Both sources refuse and change nothing, but they refuse
/// differently, and callers must not rely on one error:
/// - `StubSidebar` throws `SplitEditError.invalid`.
/// - `ModelSidebarSource` passes the model's `SidebarError.unknownNode(id)` through unmapped (decision 13 maps only
///   the split errors).
/// An unknown `addToSplit` target is `SplitEditError.invalid` from both sources
/// (`addToSplitRejectsUnknownTargetsAndItself`).
@MainActor
struct SplitUnknownIDContractTests {
  private static let url = URL(string: "https://a.example")!

  /// Each split write that takes a pane or split id, applied to `id`.
  private static let writes: [(name: String, run: @MainActor (any SidebarSource, UUID) throws -> Void)] = [
    ("separatePane", { try $0.separatePane($1) }),
    ("separateSplit", { _ = try $0.separateSplit($1) }),
    ("expandPane", { try $0.expandPane($1) }),
    ("movePane", { try $0.movePane($1, to: 0) }),
    ("setSplitWidthFactors", { try $0.setSplitWidthFactors($1, [0.5, 0.5]) }),
    ("setSplitOrientation", { try $0.setSplitOrientation($1, .vertical) }),
    ("duplicateSplit", { _ = try $0.duplicateSplit($1) }),
  ]

  @Test(arguments: SourceKind.allCases)
  func unknownIDsAreRefusedWithoutChanges(kind: SourceKind) throws {
    let source = kind.make()
    let space = try source.addSpace(title: "S")
    let a = try source.addTab(url: Self.url, title: "A", in: .today(space))
    let (split, _) = try source.addToSplit(.new(url: Self.url, title: "N"), target: a, at: 1,
                                           orientation: .horizontal)
    let before = source.children(of: .today(space))
    let panesBefore = source.children(of: .split(split))
    var changes: [SidebarChange] = []
    let observation = source.observe { changes.append($0) }
    let unknown = UUID()
    for write in Self.writes {
      expectRefusal(kind: kind, unknown: unknown, name: write.name) { try write.run(source, unknown) }
    }
    // An unknown pane joining an existing tab.
    expectRefusal(kind: kind, unknown: unknown, name: "addToSplit(.existing)") {
      _ = try source.addToSplit(.existing(unknown), target: split, at: 0, orientation: .horizontal)
    }
    #expect(source.node(unknown) == nil)
    #expect(source.children(of: .today(space)) == before)
    #expect(source.children(of: .split(split)) == panesBefore)
    #expect(changes.isEmpty)
    _ = observation
  }

  private func expectRefusal(
    kind: SourceKind, unknown: UUID, name: String, sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
  ) {
    switch kind {
    case .stub:
      #expect(throws: SplitEditError.invalid, "\(name)", sourceLocation: sourceLocation) { try body() }
    case .model:
      #expect(throws: SidebarError.unknownNode(unknown), "\(name)", sourceLocation: sourceLocation) { try body() }
    }
  }
}
