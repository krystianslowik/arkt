import AppKit

extension ShellWindowController {
  /// A window-modal sheet on this window (an extension dialog, the file chooser, the shell's own sheets) starts below
  /// the current tab's infobar rows (#924), as a page dialog does (#581): at the top of the tab's page less the strip's
  /// height, which is the page's top when the tab has no rows or is in HTML fullscreen; at the card's top while no page
  /// is on screen. The horizontal place stays the one AppKit passed in. AppKit (macOS 27) centers a sheet in the window
  /// and takes this rect only as the highest its top may sit, so a short sheet stays centered; it asks when a sheet
  /// begins and when the window resizes, not when the rows change.
  public func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
    guard let top = sheetTop(in: window) else { return rect }
    return NSRect(x: rect.minX, y: top, width: rect.width, height: 0)
  }

  /// The highest a sheet's top may sit, in `window`'s coordinates; nil while neither a page nor the card is on screen.
  private func sheetTop(in window: NSWindow) -> CGFloat? {
    if let tab = currentTab, let page = engine.contentView(for: tab), page.window === window,
       !page.isHiddenOrHasHiddenAncestor {
      return page.convert(page.bounds, to: nil).maxY - infobarStrips.height(of: tab)
    }
    let card = rootView.card
    guard card.window === window, !card.isHiddenOrHasHiddenAncestor else { return nil }
    return card.convert(card.bounds, to: nil).maxY
  }
}
