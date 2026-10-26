import CoreGraphics
import EngineAPI
import Foundation

/// Little Arkt geometry (docs/design/little-arkt.md, Layout; decided 2026-10-25 until RT-23 is measured). Screen
/// frames are AppKit's (points, origin bottom-left); view frames are in the window's content view (not flipped).
public enum LittleArktLayout {
  /// PARITY(NEEDS-RUNTIME-CHECK RT-23, BH-143).
  public static let defaultSize = CGSize(width: 480, height: 620)
  public static let minimumSize = CGSize(width: 360, height: 400)
  /// The first window's distance from the right edge and from the menu bar.
  public static let rightInset: CGFloat = 24
  public static let topInset: CGFloat = 20
  /// Each further window, left and down from the frontmost one.
  public static let cascadeStep: CGFloat = 28
  /// The frame around the card on the left, right and bottom.
  public static let frameInset: CGFloat = 6
  public static let topBarHeight: CGFloat = 40
  public static let cornerRadius: CGFloat = 12

  /// A new window of `size` (the last size the user set, BH-142): at the top-right of `visible`, or 28 pt left and
  /// down from the frontmost Little Arkt window; back at the first position when that would leave `visible`.
  public static func placement(size: CGSize, frontmost: CGRect?, in visible: CGRect) -> CGRect {
    let size = fitted(size, in: visible)
    let first = CGRect(x: visible.maxX - rightInset - size.width, y: visible.maxY - topInset - size.height,
                       width: size.width, height: size.height)
    guard let frontmost else { return first }
    let next = CGRect(x: frontmost.minX - cascadeStep, y: frontmost.maxY - cascadeStep - size.height,
                      width: size.width, height: size.height)
    return visible.contains(next) ? next : first
  }

  /// The window around a page frame a popup asked for: the top bar above it and the frame on the other three
  /// sides, at least the minimum size, moved fully into `visible`.
  public static func frame(forRequestedPage page: CGRect, in visible: CGRect) -> CGRect {
    let outset = CGRect(x: page.minX - frameInset, y: page.minY - frameInset,
                        width: page.width + frameInset * 2, height: page.height + frameInset + topBarHeight)
    let size = fitted(outset.size, in: visible)
    let x = min(max(outset.minX, visible.minX), visible.maxX - size.width)
    let top = min(max(outset.maxY, visible.minY + size.height), visible.maxY)
    return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
  }

  /// The page card in the window's content view.
  public static func cardFrame(in bounds: CGRect) -> CGRect {
    CGRect(x: bounds.minX + frameInset, y: bounds.minY + frameInset,
           width: max(0, bounds.width - frameInset * 2), height: max(0, bounds.height - frameInset - topBarHeight))
  }

  /// The top bar in the window's content view.
  public static func topBarFrame(in bounds: CGRect) -> CGRect {
    CGRect(x: bounds.minX, y: bounds.maxY - topBarHeight, width: bounds.width, height: topBarHeight)
  }

  private static func fitted(_ size: CGSize, in visible: CGRect) -> CGSize {
    CGSize(width: min(max(size.width, minimumSize.width), max(visible.width - rightInset, minimumSize.width)),
           height: min(max(size.height, minimumSize.height), max(visible.height - topInset, minimumSize.height)))
  }
}

/// Which engine window requests open in Little Arkt (#123, decided 2026-10-25): a page's `window.open` with window
/// features and an extension's popup window. Links from other apps (`.startupURL`) join once routing exists
/// (#135, #113).
public enum LittleArktRouting {
  public static func opensInLittleArkt(_ request: EngineWindowRequest) -> Bool {
    request.kind == .page || request.isPopup
  }
}

/// Little Arkt's copy (docs/design/little-arkt.md, Copy).
public enum LittleArktCopy {
  public static let windowDescription = "Little Arkt"
  public static let copyLink = "Copy Link"
  public static let chooseSpace = "Choose a Space"
  public static let chooserHeading = "Open in"
  public static let openInNewWindow = "Open in New Window"

  /// The primary button: "Open in <Space>", "Open as Tab" for a popup (the quiet style), "Open in New Window" while
  /// no main window has a Space to name.
  public static func openLabel(isPopup: Bool, spaceName: String?) -> String {
    if isPopup { return "Open as Tab" }
    guard let spaceName, !spaceName.isEmpty else { return openInNewWindow }
    return "Open in \(spaceName)"
  }

  public static func openHelp(isPopup: Bool, spaceName: String?) -> String {
    guard !isPopup, let spaceName, !spaceName.isEmpty else { return "Command-O. Moves this page to a tab." }
    return "Command-O. Moves this page to the \(spaceName) Space."
  }

  /// "Opened in Personal", announced after Open in.
  public static func announcement(spaceName: String?) -> String {
    guard let spaceName, !spaceName.isEmpty else { return "Opened as a tab" }
    return "Opened in \(spaceName)"
  }

  /// The top bar's host: the URL's host, else the whole URL (about:blank, data:), else nothing.
  public static func host(of url: URL?) -> String {
    guard let url else { return "" }
    return url.host() ?? url.absoluteString
  }
}
