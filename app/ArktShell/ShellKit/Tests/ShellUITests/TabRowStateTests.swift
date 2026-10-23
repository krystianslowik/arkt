import Foundation
import Testing
@testable import ShellUI

struct TabRowStateTests {
  let a = UUID(), b = UUID(), c = UUID(), d = UUID()

  @Test func resolvesStatePrecedence() {
    let r = TabRowState.Resolver(current: a, visible: [a, b], previous: c)
    #expect(r.state(for: a) == .current)
    #expect(r.state(for: b) == .contentVisible)
    #expect(r.state(for: c) == .previous)
    #expect(r.state(for: d) == .normal)
  }

  @Test func currentWinsOverPreviousWhenTheSameNode() {
    let r = TabRowState.Resolver(current: a, visible: [], previous: a)
    #expect(r.state(for: a) == .current)
  }

  @Test func backgroundLevelsMatchArcTokenLevels() {
    #expect(TabRowState.current.background(.light)?.alpha == 0.85)
    #expect(TabRowState.contentVisible.background(.light)?.alpha == 0.70)
    #expect(TabRowState.previous.background(.light)?.alpha == 0.32)
    #expect(TabRowState.current.background(.light)?.red == 1)       // white over the theme in light
    #expect(TabRowState.current.background(.dark)?.alpha == 0.20)
    #expect(TabRowState.pressed.background(.light)?.alpha == 0.065)
    #expect(TabRowState.normal.background(.light) == nil)
  }

  @Test func displayedStateFoldsHoverAndPress() {
    #expect(TabRowState.previous.displayed(hovered: true, pressed: false) == .previousHovered)
    #expect(TabRowState.normal.displayed(hovered: false, pressed: true) == .pressed)
    #expect(TabRowState.current.displayed(hovered: true, pressed: true) == .current)
    #expect(TabRowState.normal.displayed(hovered: false, pressed: false) == .normal)
  }

  @Test func rowMetrics() {
    #expect(SidebarMetrics.rowPitch == 41)
    #expect(SidebarMetrics.rowBackgroundHeight == 34)
    #expect(SidebarMetrics.rowBackgroundInsetY == 3.5)
  }
}

// C7: only rows whose state changes are pushed when the current tab moves.
struct ResolverDiffTests {
  @Test func changedNodesListsOnlyStateChanges() {
    let a = NodeID(), b = NodeID(), c = NodeID(), d = NodeID()
    let old = TabRowState.Resolver(current: a, visible: [c], previous: b)
    let new = TabRowState.Resolver(current: d, visible: [c], previous: a)
    #expect(new.changedNodes(from: old) == [a, b, d])
    #expect(old.changedNodes(from: old).isEmpty)
  }
}
