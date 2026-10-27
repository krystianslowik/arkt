import AppKit
import EngineAPI

// Find in page in the shell window (#134, design/find-in-page direction A). One bar per tab, drawn over the top trailing
// corner of the card while that tab is current. The commands are the shell's (`claim`), so Chromium's own find bar,
// which `CreateFindBar` must never show in an Arkt window, is never asked for.
//
// Cut from this change: Jump to Selection, and split panes (the bar belongs to a single card; with a Split View shown
// the commands are disabled and the bar hides, keeping its text).
extension ShellWindowController {
  /// The presenter, the bar over the card and their wiring to the window: focus, the page's keyboard on close, the
  /// field's nudge and the spoken count.
  func makeFindBar() -> FindBarPresenter {
    let presenter = FindBarPresenter(engine: engine)
    let view = FindBarView(presenter: presenter)
    rootView.card.findBarView = view
    presenter.onChange = { [weak view] in view?.refresh() }
    presenter.onFocusRequested = { [weak view] in view?.focusField() }
    presenter.onNoMatches = { [weak view] in view?.nudgeField() }
    presenter.onAnnouncement = { [weak view] in view?.announce($0) }
    presenter.onClosed = { [weak self] in self?.returnFocusToPage() }
    return presenter
  }

  /// The window shows a single page the bar can belong to.
  private var canFind: Bool { currentTab != nil && splitState.split == nil && onboarding == nil }

  func claimFind(_ command: EngineCommand) -> CommandClaim {
    switch command {
    case .find: CommandClaim(isEnabled: canFind)
    default: CommandClaim(isEnabled: canFind && findBar.canFindAgain)    // Find Next, Find Previous
    }
  }

  func performFind(_ command: EngineCommand) -> Bool {
    // Claimed but disabled (a split, the first run): handled, so nothing falls through to the engine's own find.
    guard claimFind(command).isEnabled else { return true }
    switch command {
    case .find: findBar.open()
    case .findNext: findBar.step(forward: true)
    default: findBar.step(forward: false)
    }
    return true
  }

  /// The content area changed: the bar follows the current tab, and hides while a Split View shows.
  func refreshFindBar() {
    findBar.shownTabChanged(splitState.split == nil ? currentTab : nil)
  }
}
