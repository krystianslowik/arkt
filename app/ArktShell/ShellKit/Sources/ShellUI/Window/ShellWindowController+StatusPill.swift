import AppKit
import EngineAPI

extension ShellWindowController {
  /// A tab's link status pill sits in the card that shows its page: the card's own, or a split pane's. A tab that is not
  /// on screen in this window has none.
  func makeStatusPillPresenter() -> StatusPillPresenter {
    StatusPillPresenter { [weak self] tab in
      guard let self, let view = engine.contentView(for: tab), let window = view.window, window === self.window,
            !view.isHiddenOrHasHiddenAncestor else { return nil }
      var ancestor = view.superview
      while let current = ancestor {
        if let card = current as? ContentCardView { return card }
        ancestor = current.superview
      }
      return nil
    }
  }
}
