import Foundation
import Testing
@testable import ShellUI

struct CommandBarActionsTests {
  let actions = [
    CommandBarAction(id: "newSpace", title: "New Space"),
    CommandBarAction(id: "nextSpace", title: "Next Space"),
    CommandBarAction(id: "toggleToolbar", title: "Toggle Toolbar"),
  ]

  @Test func emptyQueryKeepsEveryActionInOrder() {
    #expect(CommandBarActions.filter(actions, query: "").map(\.id) == ["newSpace", "nextSpace", "toggleToolbar"])
    #expect(CommandBarActions.filter(actions, query: "  ").count == 3)
  }

  @Test func filtersCaseInsensitively() {
    #expect(CommandBarActions.filter(actions, query: "space").map(\.id) == ["newSpace", "nextSpace"])
    #expect(CommandBarActions.filter(actions, query: "TOOLBAR").map(\.id) == ["toggleToolbar"])
  }

  @Test func noMatchKeepsNothing() {
    #expect(CommandBarActions.filter(actions, query: "zzz").isEmpty)
  }
}
