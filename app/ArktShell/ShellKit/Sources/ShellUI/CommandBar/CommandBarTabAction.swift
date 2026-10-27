import Foundation

/// What Tab does in the bar. The maintainer's decision on #371 (resolving the README's open question 1): Tab is
/// smart. It scopes the search when something on screen shows a Tab key cap, and otherwise cycles the filters.
///
/// A Tab key cap shows in two places: on the selected site-search row (scope to that site, #322 BH-107), and in the
/// hint strip on a bar just opened for a new tab with an empty field (enter action search, #322 BH-106, KB-081).
/// Shift-Tab always goes back through the filters.
enum CommandBarTabAction: Equatable {
  case scopeSite(SiteSearchEngine)
  case scopeActions
  case cycleFilter
  /// Already scoped: Tab is taken and changes nothing [I].
  case consume

  static func decide(scope: CommandBarResults.Scope, queryIsEmpty: Bool, isNewTab: Bool,
                     selected: CommandBarResults.Result?) -> CommandBarTabAction {
    guard scope == .normal else { return .consume }
    if let selected, selected.showsTabKeyCap, let engine = selected.siteSearchEngine { return .scopeSite(engine) }
    if queryIsEmpty, isNewTab { return .scopeActions }
    return .cycleFilter
  }

  /// The hint strip's Tab item, so what the strip advertises is what Tab does; nil when Tab cycles.
  static func hint(scope: CommandBarResults.Scope, queryIsEmpty: Bool, isNewTab: Bool,
                   selected: CommandBarResults.Result?) -> CommandBarHints.Item? {
    switch decide(scope: scope, queryIsEmpty: queryIsEmpty, isNewTab: isNewTab, selected: selected) {
    case .scopeSite: CommandBarHints.Item(keyCaps: [CommandBarKeyCaps.tab], caption: "Search site")
    case .scopeActions: CommandBarHints.Item(keyCaps: [CommandBarKeyCaps.tab], caption: "Actions")
    case .cycleFilter, .consume: nil
    }
  }
}
