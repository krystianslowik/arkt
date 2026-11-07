import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// When the pill shows and hides, stepped with numbers: no clock, no sleeping (#114, BH-167).
struct StatusPillModelTests {
  private let a = URL(string: "https://a.example/one")!
  private let b = URL(string: "https://b.example/two")!

  @Test func aLinkShowsOnlyAfterTheDelay() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 10)
    #expect(model.displayed == nil)
    #expect(model.deadline == 10.4)
    model.advance(to: 10.399)
    #expect(model.displayed == nil)
    model.advance(to: 10.4)
    #expect(model.displayed == a)
    #expect(model.deadline == nil)
  }

  @Test func leavingBeforeTheDelayShowsNothing() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 0)
    model.targetChanged(nil, at: 0.3)
    model.advance(to: 5)
    #expect(model.displayed == nil)
    #expect(model.phase == .hidden)
  }

  @Test func anotherLinkWhileWaitingRestartsTheWaitButTheSameLinkDoesNot() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 0)
    model.targetChanged(a, at: 0.3)
    #expect(model.deadline == 0.4)
    model.targetChanged(b, at: 0.3)
    #expect(model.deadline == 0.7)
  }

  @Test func movingBetweenLinksSwapsTheAddressAtOnce() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 0)
    model.advance(to: 0.4)
    model.targetChanged(b, at: 1)
    #expect(model.displayed == b)
    #expect(model.deadline == nil)
  }

  @Test func leavingHidesAfterTheGraceAndALinkInsideItKeepsThePill() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 0)
    model.advance(to: 0.4)
    model.targetChanged(nil, at: 1)
    #expect(model.displayed == a, "still up during the grace")
    #expect(model.deadline == 1.1)
    model.targetChanged(b, at: 1.05)
    model.advance(to: 2)
    #expect(model.displayed == b, "the next link took over; nothing blinked")

    model.targetChanged(nil, at: 3)
    model.advance(to: 3.1)
    #expect(model.displayed == nil)
  }

  @Test func aSuppressedWaitShowsNothing() {
    var model = StatusPillModel()
    model.isSuppressed = true
    model.targetChanged(a, at: 0)
    model.advance(to: 1)
    #expect(model.displayed == nil)
  }

  @Test func resetHidesAtOnce() {
    var model = StatusPillModel()
    model.targetChanged(a, at: 0)
    model.advance(to: 0.4)
    model.reset()
    #expect(model.displayed == nil)
    #expect(model.deadline == nil)
  }
}

struct StatusPillGeometryTests {
  private let card = CGRect(x: 0, y: 0, width: 1000, height: 700)

  @Test func theWidthIsCappedByItsOwnLimitAndByTheCard() {
    #expect(StatusPillGeometry.maxWidth(cardWidth: 1000) == 480)
    #expect(StatusPillGeometry.maxWidth(cardWidth: 400) == 248)
    #expect(StatusPillGeometry.maxWidth(cardWidth: 0) == 0)
  }

  @Test func theCornersSitTwelvePointsInFromTheBottomAndTheEdge() {
    let leading = StatusPillGeometry.frame(corner: .leading, width: 200, in: card)
    #expect(leading == CGRect(x: 12, y: 12, width: 200, height: 26))
    let trailing = StatusPillGeometry.frame(corner: .trailing, width: 200, in: card)
    #expect(trailing == CGRect(x: 788, y: 12, width: 200, height: 26))
  }

  @Test func thePointerWithinTwentyEightPointsSendsItToTheOtherCorner() {
    let pill = StatusPillGeometry.frame(corner: .leading, width: 200, in: card)
    let near = CGPoint(x: pill.maxX + 27, y: pill.midY)
    let far = CGPoint(x: pill.maxX + 29, y: pill.midY)
    #expect(StatusPillGeometry.corner(current: .leading, pointer: near, width: 200, in: card) == .trailing)
    #expect(StatusPillGeometry.corner(current: .leading, pointer: far, width: 200, in: card) == .leading)
    #expect(StatusPillGeometry.corner(current: .leading, pointer: nil, width: 200, in: card) == .leading)
  }

  @Test func thePointerOverThePillSendsItAwayAndItComesBackWhenTheyMeetAgain() {
    let overLeading = CGPoint(x: 100, y: 25)
    #expect(StatusPillGeometry.corner(current: .leading, pointer: overLeading, width: 200, in: card) == .trailing)
    let overTrailing = CGPoint(x: 900, y: 25)
    #expect(StatusPillGeometry.corner(current: .trailing, pointer: overTrailing, width: 200, in: card) == .leading)
    // It stays where it went while the pointer is elsewhere.
    #expect(StatusPillGeometry.corner(current: .trailing, pointer: overLeading, width: 200, in: card) == .trailing)
  }

  @Test func inACardTooSmallToHoldBothApartItStaysPutRatherThanJump() {
    let tiny = CGRect(x: 0, y: 0, width: 260, height: 120)
    let middle = CGPoint(x: 130, y: 25)
    #expect(StatusPillGeometry.corner(current: .leading, pointer: middle, width: 160, in: tiny) == .leading)
  }

  @Test func aCrossingCarriesTheSpeedOfOneInFlight() {
    var slide = StatusPillSlide()
    slide.begin(from: 600, at: 0)
    let early = slide.offset(at: 0.02)
    #expect(early < 600 && early > 0)
    slide.begin(from: early - 100, at: 0.02)         // chased back before it arrived
    #expect(slide.isActive)
    #expect(slide.offset(at: 5) == 0)
    #expect(!slide.isActive, "settled and idle")
  }
}
