import CoreGraphics
import Foundation
import EngineAPI
import Testing
@testable import ShellUI

/// Little Arkt geometry (docs/design/little-arkt.md, Layout; decided 2026-10-25). Screen coordinates, points, origin
/// bottom-left as AppKit's.
struct LittleArktLayoutTests {
  /// A 1440 x 900 screen with a 25 pt menu bar.
  private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

  @Test func firstWindowIsAtTheTopRight() {
    let frame = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: nil, in: visible)
    #expect(frame == CGRect(x: 1440 - 24 - 480, y: 875 - 20 - 620, width: 480, height: 620))
  }

  @Test func furtherWindowsCascadeTwentyEightLeftAndDown() {
    let first = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: nil, in: visible)
    let second = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: first, in: visible)
    let third = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: second, in: visible)
    #expect(second == first.offsetBy(dx: -28, dy: -28))
    #expect(third == first.offsetBy(dx: -56, dy: -56))
  }

  @Test func aCascadeLeavingTheScreenWrapsToTheFirstPosition() {
    let first = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: nil, in: visible)
    let low = first.offsetBy(dx: 0, dy: -(first.minY - visible.minY) + 10)
    let next = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: low, in: visible)
    #expect(next == first)
  }

  @Test func theRememberedSizeIsUsedAndKeptAboveTheMinimum() {
    let frame = LittleArktLayout.placement(size: CGSize(width: 300, height: 900), frontmost: nil, in: visible)
    #expect(frame.size == CGSize(width: 360, height: 875 - 20))
    #expect(frame.maxX == visible.maxX - 24)
  }

  @Test func aRequestedPageFrameGetsTheTopBarAndFrameAround() {
    let page = CGRect(x: 200, y: 100, width: 500, height: 400)
    let frame = LittleArktLayout.frame(forRequestedPage: page, in: visible)
    #expect(frame == CGRect(x: 194, y: 94, width: 512, height: 446))
  }

  @Test func aRequestedFrameIsClampedOnScreenAndToTheMinimum() {
    let page = CGRect(x: 1400, y: -50, width: 100, height: 100)
    let frame = LittleArktLayout.frame(forRequestedPage: page, in: visible)
    #expect(frame.size == LittleArktLayout.minimumSize)
    #expect(visible.contains(frame))
  }

  @Test func theCardSitsUnderTheTopBarInsideTheFrame() {
    let card = LittleArktLayout.cardFrame(in: CGRect(x: 0, y: 0, width: 480, height: 620))
    #expect(card == CGRect(x: 6, y: 6, width: 468, height: 574))
  }

  @Test func popupsAndPageRequestsOpenInLittleArkt() {
    let profile = EngineProfileID("p")
    #expect(LittleArktRouting.opensInLittleArkt(EngineWindowRequest(kind: .page, profile: profile, isPopup: true)))
    #expect(LittleArktRouting.opensInLittleArkt(EngineWindowRequest(kind: .extension, profile: profile,
                                                                    isPopup: true)))
    #expect(!LittleArktRouting.opensInLittleArkt(EngineWindowRequest(kind: .extension, profile: profile)))
    #expect(!LittleArktRouting.opensInLittleArkt(EngineWindowRequest(kind: .reopen, profile: profile)))
    #expect(!LittleArktRouting.opensInLittleArkt(EngineWindowRequest(kind: .startupURL, profile: profile)))
  }

  @Test func theTopBarShowsTheHostAndTheOpenLabel() {
    #expect(LittleArktCopy.openLabel(isPopup: false, spaceName: "Personal") == "Open in Personal")
    #expect(LittleArktCopy.openLabel(isPopup: false, spaceName: nil) == "Open in New Window")
    #expect(LittleArktCopy.openLabel(isPopup: true, spaceName: "Personal") == "Open as Tab")
    #expect(LittleArktCopy.host(of: URL(string: "https://accounts.atlas.example/sign-in")) == "accounts.atlas.example")
    #expect(LittleArktCopy.host(of: URL(string: "about:blank")) == "about:blank")
    #expect(LittleArktCopy.host(of: nil) == "")
  }
}
