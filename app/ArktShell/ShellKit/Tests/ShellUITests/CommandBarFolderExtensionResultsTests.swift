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
    sidebar.addFolder(title: "Project notes", in: .folder(outer))
    sidebar.addFolder(title: "Unrelated", in: .today(space))

    var input = CommandBarResults.Input()
    input.folders = CommandBarResults.folders(in: sidebar, spaces: [space])
    let rows = CommandBarResults.make(query: "project", input: input)
    #expect(rows.map(\.title).contains("Projects"))
    #expect(rows.map(\.title).contains("Project notes"))
    #expect(!rows.map(\.title).contains("Unrelated"))
  }

  @Test func matchesExtensionActionsWithoutDroppingOpenTabs() {
    var input = CommandBarResults.Input()
    input.openTabs = [.init(node: UUID(), title: "Notes tab", url: URL(string: "https://example.invalid")!)]
    input.extensionActions = [ExtensionAction(id: "synthetic-notes", name: "Notes extension"),
                              ExtensionAction(id: "synthetic-other", name: "Other extension")]
    let rows = CommandBarResults.make(query: "notes", input: input)
    #expect(rows.map(\.title).contains("Notes tab"))
    #expect(rows.map(\.title).contains("Notes extension"))
    #expect(!rows.map(\.title).contains("Other extension"))
  }
}
