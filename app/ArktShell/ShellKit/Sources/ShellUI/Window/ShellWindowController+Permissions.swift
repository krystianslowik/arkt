import AppKit
import EngineAPI

extension ShellWindowController {
  /// A site's permission request points at the page view of its tab while that is on screen: the card's page, a split
  /// pane's page, or the Peek's.
  func makePermissionPresenter() -> PermissionPresenter {
    let presenter = PermissionPresenter(engine: engine) { [weak self] tab in
      guard let view = self?.engine.contentView(for: tab), view.window != nil, !view.isHiddenOrHasHiddenAncestor else {
        return nil
      }
      return view
    }
    belowInfobars(presenter.host)
    return presenter
  }
}
