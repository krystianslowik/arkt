import AppKit

/// Settings > General > Links, the two Peek switches (#348, BH-144, BH-145): the copy is the final copy of
/// docs/design/peek.md ("Settings > Links") and the controls write `PeekLinkSettings`' two defaults keys.
///
/// Own file, like the Little Arkt lookup row (#354): the Settings > Links section is the one place both lanes add to,
/// so each keeps its text and rows here and the section itself stays untouched.
extension SettingsWindowController {
  enum PeekLinkCopy {
    static let crossSite = "Open a Peek window when clicking on links to other sites"
    static let crossSiteNote = "Only affects Favorites and pinned tabs"
    static let shiftClick = "Open a Peek window when clicking on links with Shift held"
  }
}
