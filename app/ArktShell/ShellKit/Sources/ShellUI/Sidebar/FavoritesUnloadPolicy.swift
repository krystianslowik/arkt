import Foundation

/// BH-049: only recently used Favorites stay loaded; others unload. Pure policy: the sidebar controller tracks
/// the load order, the window closes the pages this picks.
public enum FavoritesUnloadPolicy {
  /// The most Favorites whose pages stay loaded in a window. The maintainer decided eight on #376 (the first guess
  /// was four): Arc's own threshold is unpublished and BH-049 is single-source, so this is the product decision.
  public static let maximumLoadedFavorites = 8

  /// The ids to unload: `loadedOrder` (least to most recently used) past the limit, least recently used first,
  /// skipping `exempt` (the current tab, visible panes and held closes never unload). Fewer than the excess
  /// returns when exempt nodes sit inside it.
  public static func evictions(loadedOrder: [NodeID], exempt: Set<NodeID>) -> [NodeID] {
    var excess = loadedOrder.count - maximumLoadedFavorites
    guard excess > 0 else { return [] }
    var result: [NodeID] = []
    for id in loadedOrder where excess > 0 {
      guard !exempt.contains(id) else { continue }
      result.append(id)
      excess -= 1
    }
    return result
  }
}
