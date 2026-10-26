import Foundation
import Testing
@testable import ShellUI

/// BH-049: only recently used Favorites stay loaded. Beyond the limit the least recently used unload, and the
/// exempt (the current tab, visible panes, held closes) never do.
struct FavoritesUnloadPolicyTests {
  private func ids(_ count: Int) -> [NodeID] { (0..<count).map { _ in NodeID() } }

  /// The maintainer's decision on #376: eight loaded Favorites, not the earlier guessed four.
  @Test func theLimitIsTheDecidedEight() {
    #expect(FavoritesUnloadPolicy.maximumLoadedFavorites == 8)
  }

  @Test func atOrUnderTheLimitNothingUnloads() {
    let order = ids(FavoritesUnloadPolicy.maximumLoadedFavorites)
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: []) == [])
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: Array(order.dropLast()), exempt: []) == [])
  }

  @Test func theLeastRecentlyUsedUnloadsFirst() {
    let order = ids(FavoritesUnloadPolicy.maximumLoadedFavorites + 2)
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: []) == Array(order.prefix(2)))
  }

  /// The ninth loaded Favorite unloads the least recently used one; a current or visible ninth stays (BH-049).
  @Test func theNinthLoadedFavoriteUnloadsTheLeastRecentlyUsed() {
    let order = ids(9)
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: []) == [order[0]])
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: [order[0]]) == [order[1]],
            "a current or visible Favorite is exempt; the next least recently used unloads")
  }

  @Test func exemptNodesAreSkipped() {
    let order = ids(FavoritesUnloadPolicy.maximumLoadedFavorites + 1)
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: [order[0]]) == [order[1]])
  }

  /// Every evictable node may be exempt: then nothing unloads, even over the limit.
  @Test func whenEverythingEvictableIsExemptNothingUnloads() {
    let order = ids(FavoritesUnloadPolicy.maximumLoadedFavorites + 1)
    #expect(FavoritesUnloadPolicy.evictions(loadedOrder: order, exempt: Set(order)) == [])
  }
}
