# Custom icon integration gate (#339)

This is a test-first Shell gate on top of the Core icon and legacy archive tests. The proposed Shell boundary uses
`SpaceIconInfo` for node metadata and `setNodeIcon(_:to:)` for changes. The tests also require duplicate snapshots to
keep every descendant's icon. Core already covers storage round trips. The picker follows the Space icon catalog and
emoji prompt; opening the picker must not mutate a node. The emoji sheet's Cancel path still needs an integration
check when it can be driven without opening the system Character Viewer.

The new tests have not run: red is unobserved. Parse and source checks do not establish a behavioral result. Run the
focused CoreBridge, ShellUI and GUI tests on the supported Xcode toolchain before implementation, observe the missing
boundary failure, then implement and run the required suites. UI state and mutations stay on the main actor; the
sidebar is a hot path, and these checks introduce no animation or per-frame work. Use synthetic data, and check missing
favicons, both folder states, light and dark appearance, keyboard and accessibility in the eventual UI validation.

## Integration order

- Retain #822's pager hover deferral when integrating Favorite rendering. Its current diff adds a hover regression test;
  carry the eventual `FavoritesGridView.swift` changes before the custom-icon rendering edits.
- Integrate #802's Favorite split context-menu close changes in `FavoritesGridView.swift` and
  `SidebarContextMenu.swift` before the custom-icon menu and rendering edits; preserve its split behavior and tests.
- #830 currently adds only the pure `FavoriteUnreadBadge.swift` model and tests. Integrate it before any badge
  rendering, then compose badge and custom-icon rendering in `FavoritesGridView.swift` without replacing either.
- #824 owns `FavoritesLayout.swift` math. Merge it independently and preserve its geometry; custom icons need no layout
  math changes. Rebase the later hot-file changes on the merged versions and rerun their affected tests.
- Append results to the shared Track C results history only after announcing that hot-file edit in the issue. Preserve
  all existing sections, including Core and archive results.
