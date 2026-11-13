import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Pin state, order, site access and the context menu through the facade (#593). The facade owns the order (pinned
/// first, in pin order) and the profile's pins; ChromiumEngine maps its values onto `EngineExtensions` and passes the
/// shell's calls through once each.
@MainActor
struct ChromiumExtensionPinTests {
  let facade = ScriptedFacade()

  private func makeEngine(_ actions: [ScriptedAction] = [
    ScriptedAction(actionId: "alpha", name: "Alpha"), ScriptedAction(actionId: "beta", name: "Beta"),
    ScriptedAction(actionId: "gamma", name: "Gamma"),
  ]) throws -> (ChromiumEngine, EngineWindowID, EngineWindowID) {
    let engine = ChromiumEngine(facade: facade)
    let first = engine.createWindow(host: StubWindowHost())
    let second = engine.createWindow(host: StubWindowHost())
    for window in [first, second] {
      facade.setActions(actions, in: try ScriptedHarness.scriptedBrowser(engine, window))
    }
    return (engine, first, second)
  }

  // MARK: - Listing

  @Test(arguments: [
    (ArktExtensionSiteAccess.none, ExtensionSiteAccess.noSiteAccess), (.onClick, .onClick), (.onThisSite, .onThisSite),
    (.onAllSites, .onAllSites),
  ])
  func theListingCarriesSiteAccess(facadeValue: ArktExtensionSiteAccess, expected: ExtensionSiteAccess) throws {
    let (engine, first, _) = try makeEngine([ScriptedAction(actionId: "alpha", name: "Alpha", siteAccess: facadeValue)])
    let alpha = try #require(engine.extensionActions(in: first).first)
    #expect(alpha.siteAccess == expected)
  }

  @Test(arguments: [false, true])
  func theListingCarriesTheOptionsPage(hasOptionsPage: Bool) throws {
    let (engine, first, _) = try makeEngine([
      ScriptedAction(actionId: "alpha", name: "Alpha", hasOptionsPage: hasOptionsPage),
    ])
    #expect(try #require(engine.extensionActions(in: first).first).hasOptionsPage == hasOptionsPage)
  }

  @Test func theListingCarriesPinStateInTheFacadesOrder() throws {
    let (engine, first, _) = try makeEngine()
    facade.pinnedIDs = ["gamma", "alpha"]
    let actions = engine.extensionActions(in: first)
    #expect(actions.map(\.id) == ["gamma", "alpha", "beta"])
    #expect(actions.map(\.isPinned) == [true, true, false])
    #expect(actions.map(\.extensionID) == ["gamma", "alpha", "beta"], "action ids are extension ids")
  }

  @Test func pinnedExtensionIDsReadsTheProfile() throws {
    let (engine, _, _) = try makeEngine()
    #expect(engine.pinnedExtensionIDs.isEmpty)
    facade.pinnedIDs = ["beta", "alpha"]
    #expect(engine.pinnedExtensionIDs == ["beta", "alpha"])
  }

  // MARK: - Pin and move

  @Test(arguments: [true, false])
  func setPinnedReachesTheFacadeOnce(pinned: Bool) throws {
    let (engine, _, _) = try makeEngine()
    if !pinned { facade.pinnedIDs = ["beta"] }
    engine.setExtensionPinned("beta", pinned: pinned)
    #expect(facade.pinCalls.map(\.extensionID) == ["beta"])
    #expect(facade.pinCalls.map(\.pinned) == [pinned])
    #expect(engine.pinnedExtensionIDs == (pinned ? ["beta"] : []))
  }

  @Test func aPinChangeIsAnnouncedForEveryWindow() async throws {
    let (engine, first, second) = try makeEngine()
    try await ScriptedHarness.delivered(engine)
    var changed: [EngineWindowID] = []
    let observation = engine.observeWindows { event in
      if case .extensionActionsChanged(let window) = event { changed.append(window) }
    }
    engine.setExtensionPinned("alpha", pinned: true)
    try await ScriptedHarness.delivered(engine)
    #expect(Set(changed) == [first, second])
    #expect(changed.count == 2)
    #expect(engine.extensionActions(in: second).first?.id == "alpha")
    _ = observation
  }

  @Test func moveReachesTheFacadeWithTheIndex() throws {
    let (engine, first, _) = try makeEngine()
    facade.pinnedIDs = ["alpha", "beta", "gamma"]
    engine.movePinnedExtension("gamma", to: 0)
    #expect(facade.moveCalls.map(\.extensionID) == ["gamma"])
    #expect(facade.moveCalls.map(\.index) == [0])
    #expect(engine.pinnedExtensionIDs == ["gamma", "alpha", "beta"])
    #expect(engine.extensionActions(in: first).map(\.id) == ["gamma", "alpha", "beta"])
  }

  // MARK: - Context menu

  @Test func theContextMenuMapsTheFacadeItems() throws {
    let (engine, first, _) = try makeEngine()
    facade.contextMenus["alpha"] = [
      ScriptedMenuItem(title: "Alpha", command: .header, isEnabled: false),
      ScriptedMenuItem(title: "Options...", command: .options),
      ScriptedMenuItem(title: "Unpin", command: .togglePin),
      ScriptedMenuItem(title: "This Can Read and Change Site Data", children: [
        ScriptedMenuItem(title: "When You Click the Extension", command: .siteAccessOnClick),
        ScriptedMenuItem(title: "On example.com", command: .siteAccessOnThisSite, isChecked: true),
        ScriptedMenuItem(title: "On All Sites", command: .siteAccessOnAllSites, isEnabled: false),
      ]),
      ScriptedMenuItem.separator(),
      ScriptedMenuItem(title: "Manage Extension...", command: .manage),
      ScriptedMenuItem(title: "Remove from Arkt...", command: .remove),
    ]
    let menu = engine.extensionContextMenu(forAction: "alpha", in: first)
    #expect(menu == [
      EngineMenuItem(title: "Alpha", command: ExtensionContextCommand.header, isEnabled: false),
      EngineMenuItem(title: "Options...", command: ExtensionContextCommand.options),
      EngineMenuItem(title: "Unpin", command: ExtensionContextCommand.togglePin),
      .submenu("This Can Read and Change Site Data", [
        EngineMenuItem(title: "When You Click the Extension", command: ExtensionContextCommand.siteAccessOnClick),
        EngineMenuItem(title: "On example.com", command: ExtensionContextCommand.siteAccessOnThisSite,
                       isChecked: true),
        EngineMenuItem(title: "On All Sites", command: ExtensionContextCommand.siteAccessOnAllSites,
                       isEnabled: false),
      ]),
      .separator,
      EngineMenuItem(title: "Manage Extension...", command: ExtensionContextCommand.manage),
      EngineMenuItem(title: "Remove from Arkt...", command: ExtensionContextCommand.remove),
    ])
    #expect(facade.contextMenuCalls.map(\.actionId) == ["alpha"])
    #expect(facade.contextMenuCalls.map(\.window) == [try ScriptedHarness.scriptedBrowser(engine, first).windowId])
  }

  @Test func theContextMenuOfAClosedWindowIsEmpty() async throws {
    let (engine, first, _) = try makeEngine()
    facade.contextMenus["alpha"] = [ScriptedMenuItem(title: "Alpha", command: .header, isEnabled: false)]
    engine.closeWindow(first)
    try await ScriptedHarness.delivered(engine)
    #expect(engine.extensionContextMenu(forAction: "alpha", in: first).isEmpty)
    #expect(facade.contextMenuCalls.isEmpty)
  }

  @Test func aChosenCommandReachesTheFacadeWithItsWindow() throws {
    let (engine, _, second) = try makeEngine()
    engine.performExtensionContextCommand(ExtensionContextCommand.siteAccessOnAllSites, forAction: "beta", in: second)
    #expect(facade.performedContextCommands.map(\.command) == [ExtensionContextCommand.siteAccessOnAllSites.rawValue])
    #expect(facade.performedContextCommands.map(\.actionId) == ["beta"])
    #expect(facade.performedContextCommands.map(\.window)
      == [try ScriptedHarness.scriptedBrowser(engine, second).windowId])
  }

  @Test func theExtensionsOwnItemsPassThroughUnchanged() throws {
    let (engine, first, _) = try makeEngine()
    facade.contextMenus["alpha"] = [
      ScriptedMenuItem(title: "Alpha", command: .header, isEnabled: false),
      ScriptedMenuItem.separator(),
      ScriptedMenuItem(title: "Run Probe", rawCommand: 1000),
      ScriptedMenuItem(title: "Follow This Site", rawCommand: 1002, isChecked: true),
      ScriptedMenuItem(title: "More", children: [ScriptedMenuItem(title: "Child Off", rawCommand: 1006,
                                                                  isEnabled: false)]),
      ScriptedMenuItem.separator(),
      ScriptedMenuItem(title: "Options...", command: .options),
    ]
    let menu = engine.extensionContextMenu(forAction: "alpha", in: first)
    #expect(menu == [
      EngineMenuItem(title: "Alpha", command: ExtensionContextCommand.header, isEnabled: false),
      .separator,
      EngineMenuItem(title: "Run Probe", command: ExtensionContextCommand.custom(0)),
      EngineMenuItem(title: "Follow This Site", command: ExtensionContextCommand.custom(2), isChecked: true),
      .submenu("More", [EngineMenuItem(title: "Child Off", command: ExtensionContextCommand.custom(6),
                                       isEnabled: false)]),
      .separator,
      EngineMenuItem(title: "Options...", command: ExtensionContextCommand.options),
    ])
  }

  @Test func aChosenCustomItemReachesTheFacadeUnchanged() throws {
    let (engine, first, _) = try makeEngine()
    engine.performExtensionContextCommand(ExtensionContextCommand.custom(4), forAction: "alpha", in: first)
    #expect(facade.performedContextCommands.map(\.command) == [1004])
    #expect(facade.performedContextCommands.map(\.actionId) == ["alpha"])
  }

  @Test func theCustomRangeMatchesTheFacades() {
    #expect(ArktExtensionContextCommand.customFirst.rawValue == ExtensionContextCommand.customRange.lowerBound)
    #expect(ArktExtensionContextCommand.customLast.rawValue == ExtensionContextCommand.customRange.upperBound)
  }

  @Test func theCommandValuesMatchTheShells() {
    let pairs: [(ArktExtensionContextCommand, EngineMenuCommand)] = [
      (.header, ExtensionContextCommand.header), (.options, ExtensionContextCommand.options),
      (.togglePin, ExtensionContextCommand.togglePin), (.moveUp, ExtensionContextCommand.moveUp),
      (.moveDown, ExtensionContextCommand.moveDown), (.siteAccessOnClick, ExtensionContextCommand.siteAccessOnClick),
      (.siteAccessOnThisSite, ExtensionContextCommand.siteAccessOnThisSite),
      (.siteAccessOnAllSites, ExtensionContextCommand.siteAccessOnAllSites),
      (.manage, ExtensionContextCommand.manage), (.remove, ExtensionContextCommand.remove),
    ]
    for (facade, shell) in pairs { #expect(facade.rawValue == shell.rawValue) }
  }
}
