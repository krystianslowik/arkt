import AppKit
import EngineAPI

/// What the Extensions panel shows (design/extensions, direction C), as plain values: the window's actions split into
/// Pinned (in the profile's pin order) and Not pinned, the panel's state, and the arithmetic of the keyboard moves and
/// the drag. Pure, so tests read it without a window.
struct ExtensionsPanelModel: Equatable {
  enum State: Equatable {
    /// No extensions: the puzzle tile, "No extensions yet" and Browse the Web Store.
    case empty
    /// Extensions, none pinned: the Pinned group shows the hint row.
    case nonePinned
    /// At least one pinned extension.
    case list
  }

  /// A row's second line, and whether the icon carries the graphite "needs attention" dot. The text always says what
  /// the dot means, so the dot is never the only signal.
  struct Status: Equatable {
    var text: String
    var needsAttention: Bool
  }

  let pinned: [ExtensionAction]
  let unpinned: [ExtensionAction]

  /// `actions` in the engine's toolbar order: pinned ones first, in `pinnedExtensionIDs` order.
  init(actions: [ExtensionAction]) {
    pinned = actions.filter(\.isPinned)
    unpinned = actions.filter { !$0.isPinned }
  }

  var state: State {
    if pinned.isEmpty { return unpinned.isEmpty ? .empty : .nonePinned }
    return .list
  }

  /// The status line. The engine reports site access and the enabled state for the active tab, not the action's badge
  /// text, so the line describes access. [I] product wording.
  static func status(of action: ExtensionAction) -> Status {
    guard action.isEnabled else { return Status(text: "Not available on this page", needsAttention: false) }
    switch action.siteAccess {
    case .onThisSite, .onAllSites: return Status(text: "Can read this site", needsAttention: false)
    case .onClick: return Status(text: "Needs access to this site", needsAttention: true)
    case .noSiteAccess: return Status(text: "Doesn't need site access", needsAttention: false)
    }
  }

  // MARK: Order

  /// The index in the pin order a Move Left (`by: -1`) or Move Right (`by: 1`) of `extensionID` goes to; nil at the end
  /// it moves towards, and for an extension that is not pinned.
  func moveTarget(of extensionID: String, by step: Int) -> Int? {
    guard let place = pinned.firstIndex(where: { $0.extensionID == extensionID }) else { return nil }
    let target = place + step
    return pinned.indices.contains(target) ? target : nil
  }

  /// The gap (0 before the first row, `rowMiddles.count` after the last) a pointer at `pointerY` points at, in a
  /// top-down coordinate space, from the middles of the rows the dragged row passes over.
  static func insertionGap(pointerY: CGFloat, rowMiddles: [CGFloat]) -> Int {
    rowMiddles.firstIndex { pointerY < $0 } ?? rowMiddles.count
  }

  /// The pin order index a row dragged from `from` lands at when dropped in `gap` (gaps counted among all pinned rows,
  /// the dragged one included); nil when the gap is either side of the row itself.
  static func dropIndex(from: Int, gap: Int) -> Int? {
    if gap == from || gap == from + 1 { return nil }
    return gap > from ? gap - 1 : gap
  }

  // MARK: Geometry

  struct Height: Equatable {
    var height: CGFloat
    var scrolls: Bool
  }

  /// The panel's height: its content's, capped to the room the window has (the smallest window), never below the
  /// footer and one row. When capped the list scrolls with a faded edge and the footer stays.
  static func panelHeight(content: CGFloat, available: CGFloat) -> Height {
    let cap = max(available, ExtensionsPanelMetrics.minimumHeight)
    return content <= cap ? Height(height: content, scrolls: false) : Height(height: cap, scrolls: true)
  }

  /// 316 pt, narrowed to leave 8 pt either side in a narrower window.
  static func panelWidth(windowWidth: CGFloat) -> CGFloat {
    min(ExtensionsPanelMetrics.width, max(0, windowWidth - 2 * ExtensionsPanelMetrics.windowMargin))
  }
}

/// Geometry of the Extensions panel, in points (design/extensions, direction C).
enum ExtensionsPanelMetrics {
  static let dotRadius: CGFloat = 4
  static let insertionLineRadius: CGFloat = 1
  static let width: CGFloat = 316
  static let padding: CGFloat = 6
  static let corner: CGFloat = 14
  static let rowHeight: CGFloat = 44
  static let rowCorner: CGFloat = 9
  static let headerHeight: CGFloat = 28
  static let hintHeight: CGFloat = 56
  static let footerHeight: CGFloat = 40
  static let iconSize: CGFloat = 30
  static let iconCorner: CGFloat = 8
  static let gripWidth: CGFloat = 10
  static let buttonSize: CGFloat = 28
  static let insertionHeight: CGFloat = 2
  /// The panel's left edge sits this far in from the sidebar's, and this far above the bottom bar's button.
  static let sidebarInset: CGFloat = 12
  static let gap: CGFloat = 8
  /// Room kept between the panel and the window's top edge (below the traffic lights).
  static let topMargin: CGFloat = 40
  static let windowMargin: CGFloat = 8
  static let fadeHeight: CGFloat = 36
  static var minimumHeight: CGFloat { padding * 2 + headerHeight + rowHeight + footerHeight }
}
