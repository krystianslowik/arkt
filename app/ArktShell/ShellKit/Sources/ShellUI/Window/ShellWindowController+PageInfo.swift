import AppKit
import EngineAPI

// The page info panel (#582): the address pill's site glyph opens it for the current tab. Only for an engine with page
// info (`EngineClient.siteSettings`); without one the pills show no glyph and nothing opens.
extension ShellWindowController {
  func makePageInfoPanel() -> PageInfoPanelController {
    let panel = PageInfoPanelController { [weak self] in self?.engine.siteSettings }
    panel.onReturnFocus = { [weak self] in self?.returnFocusToPage() }
    panel.isReadOnly = { [weak self] in self?.isPrivateWindow ?? false }          // until #557
    panel.favicon = { [weak self] tab in self?.engine.snapshot(of: tab)?.faviconData }
    return panel
  }

  /// The site glyph of both address bars follows the current tab's page info, and an open panel follows the page.
  /// While a Peek shows its own address, or for a page of the browser itself, the pills stay inert.
  func refreshPageInfo() {
    let info = peek.addressOverride == nil ? currentTab.flatMap { engine.siteSettings?.pageInfo(of: $0) } : nil
    let pill = PageInfoModel.pill(for: info)
    for bar in [urlBar, rootView.card.toolbar.urlBar] {
      bar.siteDescription = pill?.description
      bar.siteSymbol = pill?.symbol
    }
    refreshPaneSiteGlyphs()                                         // #698: inert while a Peek shows, as these are
    pageInfo.pageDidChange(currentTab: info == nil ? nil : currentTab)
  }

  /// The glyph of `bar` was pressed: the panel for the current tab opens below it, or closes.
  func toggleSiteControls(from bar: URLBarView) {
    guard let tab = currentTab, bar.siteSymbol != nil else { return }
    splitState.pageInfoCard = nil                                   // not from a pane Toolbar (#698)
    pageInfo.toggle(for: tab, anchoredTo: bar)
  }
}
