import AppKit
import EngineAPI

// The zoom pill in the shell window (#579, design/extensions `surf-zoom`). One pill for the window, over the top
// trailing corner of the page the find bar would use (the focused pane while a split shows), below the find bar when
// both show. The zoom commands stay the engine's: Cmd-+, Cmd-- and Cmd-0 are the main menu's page commands, which the
// window passes to the engine unclaimed, so the pill only listens to `.zoomChanged`.
extension ShellWindowController {
  /// The presenter, the pill over the card and their wiring.
  func makeZoomPill() -> ZoomPillPresenter {
    let presenter = ZoomPillPresenter(engine: engine)
    let view = ZoomPillView(presenter: presenter)
    rootView.card.zoomPillView = view
    presenter.onChange = { [weak view] in view?.refresh() }
    presenter.onAnnouncement = { [weak view] in view?.announce($0) }
    return presenter
  }

  /// The one zoom pill, whether the single card or a pane card is hosting it.
  private var installedZoomPill: ZoomPillView? {
    if let pill = rootView.card.zoomPillView { return pill }
    for view in rootView.split.subviews {
      if let card = view as? ContentCardView, let pill = card.zoomPillView { return pill }
    }
    return nil
  }

  /// The content area changed: the pill closes when another tab shows, and moves to the card that now hosts the page.
  func refreshZoomPill() {
    zoomPill.shownTabChanged(findTarget)
    guard let pill = installedZoomPill else { return }
    let card = findAnchorCard
    if pill.superview !== card {
      let host = pill.superview as? ContentCardView
      if host?.zoomPillView === pill { host?.zoomPillView = nil }
      card.zoomPillView = pill
    }
    card.layoutZoomPill()
  }
}
