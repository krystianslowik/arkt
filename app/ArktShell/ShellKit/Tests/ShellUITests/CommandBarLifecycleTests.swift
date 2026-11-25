import Foundation
import Testing
@testable import ShellUI

/// The bar's one show-and-hide state (#884): hidden, showing (until the first frame) and shown. A session's
/// generation tags every async reply; a reply from an earlier session is not accepted.
@MainActor
struct CommandBarLifecycleTests {
  @Test func showCommitFirstFrameHide() {
    var life = CommandBarLifecycle()
    #expect(life.phase == .hidden)
    life.send(.show)
    #expect(life.phase == .showing)
    let generation = life.generation
    #expect(generation == 1)
    #expect(life.commitTime == nil)
    life.send(.commitEnded(generation: 1, at: 5))
    #expect(life.commitTime == 5)
    life.send(.firstFrame(generation: 1))
    #expect(life.phase == .shown)
    life.send(.hide)
    #expect(life.phase == .hidden)
    #expect(life.generation == nil)
  }

  /// A commit or first frame of an earlier show changes nothing.
  @Test func eventsOfAnEarlierShowAreIgnored() {
    var life = CommandBarLifecycle()
    life.send(.show)
    life.send(.hide)
    life.send(.show)
    #expect(life.generation == 2)
    life.send(.commitEnded(generation: 1, at: 3))
    #expect(life.commitTime == nil)
    life.send(.firstFrame(generation: 1))
    #expect(life.phase == .showing)
    #expect(!life.accepts(generation: 1))
    #expect(life.accepts(generation: 2))
  }

  /// Hidden accepts nothing; a first frame before the commit landed does nothing; hiding twice is a no-op.
  @Test func unknownPairsAreNoOps() {
    var life = CommandBarLifecycle()
    life.send(.hide)
    life.send(.firstFrame(generation: 0))
    #expect(life.phase == .hidden)
    #expect(!life.accepts(generation: 0))
    life.send(.show)
    life.send(.firstFrame(generation: 1))
    #expect(life.phase == .showing, "no commit yet")
  }

  /// Hiding, or showing again, cancels the session's suggestion request.
  @Test func hideAndReshowCancelTheRequest() {
    var life = CommandBarLifecycle()
    life.send(.show)
    let first = Task<Void, Never> { }
    life.attach(suggestions: first)
    life.send(.hide)
    #expect(first.isCancelled)
    life.send(.show)
    let second = Task<Void, Never> { }
    life.attach(suggestions: second)
    life.send(.show)
    #expect(second.isCancelled, "a second show before the first frame starts a new session")
    #expect(life.generation == 3)
  }

  #if DEBUG
  /// The debug transition log names each change.
  @Test func theTransitionLog() {
    var life = CommandBarLifecycle()
    life.send(.show)
    life.send(.commitEnded(generation: 1, at: 1))
    life.send(.firstFrame(generation: 1))
    life.send(.hide)
    #expect(life.log == ["hidden -> showing(1)", "showing(1) -> shown(1)", "shown(1) -> hidden"])
  }
  #endif
}
