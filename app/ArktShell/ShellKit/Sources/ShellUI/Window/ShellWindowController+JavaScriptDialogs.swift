import AppKit
import EngineAPI

extension ShellWindowController {
  /// A page's dialog points at the page view of its tab while that is on screen: the card's page, a split pane's
  /// page, or the Peek's.
  func makeJavaScriptDialogPresenter() -> JavaScriptDialogPresenter {
    JavaScriptDialogPresenter(engine: engine) { [weak self] tab in
      guard let view = self?.engine.contentView(for: tab), view.window != nil, !view.isHiddenOrHasHiddenAncestor else {
        return nil
      }
      return view
    }
  }
}
