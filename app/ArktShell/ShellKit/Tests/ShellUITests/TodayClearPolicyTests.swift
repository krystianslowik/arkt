import Foundation
import Testing
@testable import ShellUI

/// What Clear Today Tabs archives (#110): every top-level Today row (BH-075), only those with nothing selected
/// (BH-078), and never a row whose page plays media (BH-076). Pure list rules, so no window is needed.
struct TodayClearPolicyTests {
  private let a = NodeID()
  private let b = NodeID()
  private let c = NodeID()

  @Test func allScopeKeepsEveryRow() {
    #expect(TodayClearPolicy.rows([a, b, c], scope: .all, isSelected: { _ in false },
                                  playsMedia: { _ in false }) == [a, b, c])
  }

  @Test func allScopeStillKeepsAPlayingRow() {
    #expect(TodayClearPolicy.rows([a, b, c], scope: .all, isSelected: { _ in false },
                                  playsMedia: { $0 == b }) == [a, c])
  }

  @Test func unselectedScopeKeepsTheSelectedRows() {
    #expect(TodayClearPolicy.rows([a, b, c], scope: .unselected, isSelected: { $0 == b || $0 == c },
                                  playsMedia: { _ in false }) == [a])
  }

  @Test func unselectedScopeIsEmptyWhenEverythingIsSelected() {
    #expect(TodayClearPolicy.rows([a, b], scope: .unselected, isSelected: { _ in true },
                                  playsMedia: { _ in false }).isEmpty)
  }

  @Test func aPlayingRowStaysEvenWhenItIsUnselected() {
    #expect(TodayClearPolicy.rows([a, b], scope: .unselected, isSelected: { $0 == a },
                                  playsMedia: { $0 == b }).isEmpty)
  }

  @Test func aShownRowStaysInEveryScope() {
    #expect(TodayClearPolicy.rows([a, b, c], scope: .all, isSelected: { _ in false },
                                  playsMedia: { _ in false }, isShown: { $0 == b }) == [a, c])
    #expect(TodayClearPolicy.rows([a, b, c], scope: .unselected, isSelected: { $0 == a },
                                  playsMedia: { _ in false }, isShown: { $0 == b }) == [c])
  }

  @Test func shownAndPlayingRowsAreBothKept() {
    #expect(TodayClearPolicy.rows([a, b, c], scope: .all, isSelected: { _ in false },
                                  playsMedia: { $0 == a }, isShown: { $0 == b }) == [c])
  }

  @Test func theRowsKeepTheirOrder() {
    #expect(TodayClearPolicy.rows([c, a, b], scope: .all, isSelected: { _ in false },
                                  playsMedia: { _ in false }) == [c, a, b])
  }

  @Test func noRowsStayNoRows() {
    #expect(TodayClearPolicy.rows([], scope: .all, isSelected: { _ in false },
                                  playsMedia: { _ in false }).isEmpty)
  }
}
