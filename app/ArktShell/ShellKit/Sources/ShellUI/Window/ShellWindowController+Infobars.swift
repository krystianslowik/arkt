import AppKit
import EngineAPI

extension ShellWindowController {
  /// A tab's infobars sit flush with the top of its page view while that is on screen in this window: the card's page, a
  /// split pane's page, or the Peek's. The engine reserves the strip's height at the top of the tab's container, so the
  /// page lies below it.
  func makeInfobarPresenter() -> InfobarPresenter {
    let presenter = InfobarPresenter(engine: engine) { [weak self] tab in
      guard let self, let view = engine.contentView(for: tab), let window = view.window, window === self.window,
            !view.isHiddenOrHasHiddenAncestor else { return nil }
      return view
    }
    presenter.focusPage = { [weak self] tab in self?.engine.focusPage(of: tab) }
    return presenter
  }

  /// An F6 the page did not use puts the keyboard in that tab's infobar strip (#478); false when it shows none.
  func focusInfobarStrip(_ event: NSEvent, in tab: TabID?) -> Bool {
    guard event.keyCode == 97,
          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
    return infobarStrips.focusStrip(of: tab, holding: window?.firstResponder)
  }

  /// Dialogs and permission prompts point at the page below the infobar strip, not at the strip.
  func belowInfobars(_ host: AnchoredPanelHost) {
    host.topInset = { [weak self] tab in self?.infobarStrips.height(of: tab) ?? 0 }
  }
}
