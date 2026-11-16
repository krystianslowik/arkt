import AppKit
import EngineAPI

extension ShellWindowController {
  /// A window-modal sheet on this window (an extension dialog, the file chooser, the shell's own sheets) starts below
  /// the infobar rows of the pages at the top of the content (#924), as a page dialog does (#581). Those are every page
  /// whose top is the highest: the card's page, each pane side by side, the top pane stacked. The cap is that top less
  /// the tallest of their strips (no height in HTML fullscreen); the card's top while no page is laid out. It is never
  /// above AppKit's own rect, and never so low that the sheet would pass the window's bottom edge. The horizontal place
  /// stays the one AppKit passed in. AppKit (macOS 27) centers a sheet in the window and takes this rect only as the
  /// highest its top may sit, so a short sheet stays centered; it asks when a sheet begins and when the window resizes,
  /// not when the rows change.
  public func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
    guard let cap = sheetTop(in: window) else { return rect }
    let top = min(rect.maxY, max(cap, sheet.frame.height))
    return NSRect(x: rect.minX, y: top, width: rect.width, height: 0)
  }

  /// The highest a sheet's top may sit, in `window`'s coordinates; nil while neither a page nor the card is on screen.
  private func sheetTop(in window: NSWindow) -> CGFloat? {
    let pages: [(tab: TabID, top: CGFloat)] = shownNodes.compactMap { node in
      guard let tab = engineTab(of: node), let page = engine.contentView(for: tab), page.window === window,
            !page.isHiddenOrHasHiddenAncestor, page.bounds.height > 0 else { return nil }
      return (tab, page.convert(page.bounds, to: nil).maxY)
    }
    if let highest = pages.map(\.top).max() {
      let strips = pages.filter { $0.top >= highest - 0.5 }.map { infobarStrips.height(of: $0.tab) }
      return highest - (strips.max() ?? 0)
    }
    let card = rootView.card
    guard card.window === window, !card.isHiddenOrHasHiddenAncestor else { return nil }
    return card.convert(card.bounds, to: nil).maxY
  }
}
