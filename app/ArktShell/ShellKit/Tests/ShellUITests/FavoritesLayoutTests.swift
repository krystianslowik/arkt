import CoreGraphics
import Testing
@testable import ShellUI

struct FavoritesLayoutTests {
  @Test func threeTilesFitDefaultSidebar() {
    // 190 pt sidebar minus 8 pt padding each side = 174 = 3 * 52 + 2 * 9
    #expect(FavoritesLayout.contentWidth(sidebarWidth: 190) == 174)
    #expect(FavoritesLayout.itemSize(contentWidth: 174) == CGSize(width: 52, height: 46))
  }

  @Test func tilesStretchWithSidebar() {
    let size = FavoritesLayout.itemSize(contentWidth: 201)
    #expect(size.height == 46)
    #expect(abs(size.width - 61) < 0.001)
  }

  @Test func gridHeight() {
    #expect(FavoritesLayout.height(itemCount: 0) == 0)
    #expect(FavoritesLayout.height(itemCount: 3) == 46)
    #expect(FavoritesLayout.height(itemCount: 4) == CGFloat(46 * 2 + 9))
  }
}
