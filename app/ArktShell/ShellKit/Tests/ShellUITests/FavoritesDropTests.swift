import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// BH-047 drop zones: a tab dropped above the Space title (the Favorites band) becomes a Favorite; a Favorite
/// dropped below it (on the Space page) is pinned there. Every other combination refuses.
struct FavoritesDropTests {
  private let space = SpaceID()
  private let band = CGRect(x: 8, y: 0, width: 200, height: 46)
  private let bounds = CGRect(x: 0, y: 0, width: 216, height: 600)

  private func target(at point: CGPoint, section: SidebarLocation?) -> SidebarLocation? {
    FavoritesDrop.target(at: point, band: band, bounds: bounds, section: section, profile: "default",
                         currentSpace: space)
  }

  @Test func anEmptyGridStillOffersAOneRowBand() {
    let empty = FavoritesDrop.band(favoritesFrame: CGRect(x: 8, y: 100, width: 200, height: 0))
    #expect(empty.height == FavoritesLayout.tileHeight)
    #expect(empty.minY == 100)
    let filled = FavoritesDrop.band(favoritesFrame: CGRect(x: 8, y: 100, width: 200, height: 92))
    #expect(filled == CGRect(x: 8, y: 100, width: 200, height: 92))
  }

  @Test func aTodayTabOverTheBandBecomesAFavorite() {
    let point = CGPoint(x: 20, y: 10)
    #expect(target(at: point, section: .today(space)) == .favorites(profile: "default"))
    #expect(target(at: point, section: .pinned(space)) == .favorites(profile: "default"))
    #expect(target(at: point, section: .folder(NodeID())) == .favorites(profile: "default"))
  }

  @Test func aFavoriteOverTheBandIsRefused() {
    #expect(target(at: CGPoint(x: 20, y: 10), section: .favorites(profile: "default")) == nil)
  }

  @Test func aFavoriteBelowTheBandIsPinnedInTheCurrentSpace() {
    let point = CGPoint(x: 20, y: 200)
    #expect(target(at: point, section: .favorites(profile: "default")) == .pinned(space))
    #expect(target(at: point, section: .today(space)) == nil)
    #expect(target(at: point, section: .pinned(space)) == nil)
  }

  @Test func anUnknownNodeIsRefusedEverywhere() {
    #expect(target(at: CGPoint(x: 20, y: 10), section: nil) == nil)
    #expect(target(at: CGPoint(x: 20, y: 200), section: nil) == nil)
  }

  @Test func aFavoriteWithoutACurrentSpaceIsRefused() {
    #expect(FavoritesDrop.target(at: CGPoint(x: 20, y: 200), band: band, bounds: bounds,
                                 section: .favorites(profile: "default"), profile: "default",
                                 currentSpace: nil) == nil)
  }
}
