import AppKit
import EngineAPI

extension ShellWindowController {
  /// A tab's infobars sit flush with the top of its page view while that is on screen in this window: the card's page, a
  /// split pane's page, or the Peek's. The engine reserves the strip's height at the top of the tab's container, so the
  /// page lies below it.
  func makeInfobarPresenter() -> InfobarPresenter {
    InfobarPresenter(engine: engine) { [weak self] tab in
      guard let self, let view = engine.contentView(for: tab), let window = view.window, window === self.window,
            !view.isHiddenOrHasHiddenAncestor else { return nil }
      return view
    }
  }

  /// Dialogs and permission prompts point at the page below the infobar strip, not at the strip.
  func belowInfobars(_ host: AnchoredPanelHost) {
    host.topInset = { [weak self] tab in self?.infobarStrips.height(of: tab) ?? 0 }
  }
}
