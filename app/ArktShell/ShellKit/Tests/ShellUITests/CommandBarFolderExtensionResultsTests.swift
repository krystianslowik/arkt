import Foundation
import Testing
import EngineAPI
@testable import ShellUI

/// BH-104: synthetic sources exercise the same result builder used by the command bar.
@MainActor
struct CommandBarFolderExtensionResultsTests {
  @Test func matchesFoldersFromNestedSidebarLocations() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let outer = sidebar.addFolder(title: "Projects", in: .pinned(space))
    let nested = sidebar.addFolder(title: "Project notes", in: .folder(outer))
    let today = sidebar.addFolder(title: "Project today", in: .today(space))
    let unrelated = sidebar.addFolder(title: "Unrelated", in: .today(space))

    var input = CommandBarResults.Input()
    input.folders = CommandBarResults.folders(in: sidebar, spaces: [space])
    #expect(Set(input.folders.map(\.node)) == Set([outer, nested, today, unrelated]))
    let rows = CommandBarResults.make(query: "project", input: input)
    let matched = rows.compactMap { row -> UUID? in
      if case .folder(let node) = row.kind { return node }
      return nil
    }
    #expect(Set(matched) == Set([outer, nested, today]))
    #expect(matched.count == 3)
    #expect(rows.first { $0.kind == .folder(outer) }?.title == "Projects")
    #expect(rows.first { $0.kind == .folder(nested) }?.title == "Project notes")
    #expect(rows.first { $0.kind == .folder(today) }?.title == "Project today")
    #expect(rows.map(\.title).contains("Projects"))
    #expect(rows.map(\.title).contains("Project notes"))
    #expect(!rows.map(\.title).contains("Unrelated"))
  }

  @Test func matchesExtensionActionsWithoutDroppingOpenTabs() {
    var input = CommandBarResults.Input()
    let tab = UUID()
    input.openTabs = [.init(node: tab, title: "Notes tab", url: URL(string: "https://example.invalid")!)]
    input.extensionActions = [ExtensionAction(id: "synthetic-notes", name: "Notes extension"),
                              ExtensionAction(id: "synthetic-other", name: "Other extension")]
    let rows = CommandBarResults.make(query: "notes", input: input)
    #expect(rows.map(\.title).contains("Notes tab"))
    #expect(rows.map(\.title).contains("Notes extension"))
    #expect(!rows.map(\.title).contains("Other extension"))
    #expect(rows.filter { $0.kind == .switchTo(tab) }.count == 1)
    #expect(rows.first { $0.kind == .switchTo(tab) }?.title == "Notes tab")
    #expect(rows.filter { $0.kind == .extensionAction("synthetic-notes") }.count == 1)
    #expect(rows.first { $0.kind == .extensionAction("synthetic-notes") }?.title == "Notes extension")
    #expect(!rows.contains { $0.kind == .extensionAction("synthetic-other") })
  }

  @Test func disabledActionsAreExcludedAndProviderRowsAreNotActionable() {
    var input = CommandBarResults.Input()
    let node = UUID()
    input.folders = [.init(node: node, title: "Notes folder")]
    input.extensionActions = [.init(id: "enabled", name: "Notes enabled"),
                              .init(id: "disabled", name: "Notes disabled", isEnabled: false)]
    let rows = CommandBarResults.make(query: "notes", input: input)
    #expect(rows.first { $0.kind == .folder(node) }?.isActionable == false)
    #expect(rows.first { $0.kind == .extensionAction("enabled") }?.isActionable == false)
    #expect(!rows.contains { $0.kind == .extensionAction("disabled") })
  }

  @Test func newSourcesPreserveExistingMixedResultKindsAndRelativeOrder() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Notes space")
    let folder = sidebar.addFolder(title: "Notes folder", in: .pinned(space))
    let tab = UUID(), archived = UUID()
    let historyURL = URL(string: "https://history.example.invalid/notes")!
    var input = CommandBarResults.Input()
    input.openTabs = [.init(node: tab, title: "Notes tab", url: URL(string: "https://open.example.invalid")!)]
    input.history = [.init(title: "Notes visit", url: historyURL)]
    input.spaces = [.init(id: space, title: "Notes space")]
    input.archived = [.init(id: archived, title: "Notes archived", subtitle: "Synthetic archive")]
    input.actions = [.init(id: "synthetic-notes-action", title: "Notes action")]
    let expected: [CommandBarResults.Kind] = [.switchTo(tab), .history(historyURL), .switchSpace(space),
      .restore(archived), .search(URLInputParser.searchURL(for: "notes")), .action("synthetic-notes-action")]
    #expect(CommandBarResults.make(query: "notes", input: input).map(\.kind) == expected)

    input.folders = CommandBarResults.folders(in: sidebar, spaces: [space])
    input.extensionActions = [ExtensionAction(id: "synthetic-notes", name: "Notes extension")]
    let rows = CommandBarResults.make(query: "notes", input: input)
    let existing = rows.compactMap { row -> CommandBarResults.Kind? in
      switch row.kind {
      case .folder, .extensionAction: return nil
      default: return row.kind
      }
    }
    #expect(existing == expected)
    #expect(rows.filter { $0.kind == .folder(folder) }.count == 1)
    #expect(rows.filter { $0.kind == .extensionAction("synthetic-notes") }.count == 1)
  }
}
