import AppKit
import Testing
import EngineAPI
@testable import ShellUI

/// The native menu for an engine item tree (#587, design/tab-context-menus section 7): plain `NSMenuItem`s, explicit
/// enabled and checked states, tidy separators, and a selection that calls back with the item's command.
@MainActor
struct EngineMenuBuilderTests {
  init() {
    _ = NSApplication.shared             // `performActionForItem(at:)` sends through `NSApp`
  }

  private static func command(_ raw: Int) -> EngineMenuCommand { EngineMenuCommand(rawValue: raw) }
  private static func item(_ title: String, _ raw: Int, enabled: Bool = true, checked: Bool = false) -> EngineMenuItem {
    EngineMenuItem(title: title, command: command(raw), isEnabled: enabled, isChecked: checked)
  }

  private func titles(_ menu: NSMenu) -> [String] {
    menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
  }

  // MARK: Structure

  @Test func plainItemsKeepTitlesAndOrder() {
    let menu = EngineMenuBuilder.menu([Self.item("Back", 1), Self.item("Forward", 2), .separator,
                                       Self.item("Reload", 3)]) { _ in }
    #expect(titles(menu) == ["Back", "Forward", "-", "Reload"])
    #expect(!menu.autoenablesItems)
  }

  @Test func itemsAreNativeWithNoCustomViewsAttributedTitlesOrFont() {
    let menu = EngineMenuBuilder.menu([Self.item("Copy", 1), .submenu("More", [Self.item("Paste", 2)])]) { _ in }
    for item in menu.items + (menu.items.last?.submenu?.items ?? []) {
      #expect(item.view == nil)
      #expect(item.attributedTitle == nil)
      #expect(item.image == nil)
      #expect(item.keyEquivalent.isEmpty)
    }
    #expect(menu.font == NSMenu().font)
  }

  @Test func disabledAndCheckedStatesAreExplicit() throws {
    let menu = EngineMenuBuilder.menu([Self.item("Off", 1, enabled: false), Self.item("On", 2, checked: true),
                                       Self.item("Both", 3, enabled: false, checked: true),
                                       Self.item("Plain", 4)]) { _ in }
    let states = menu.items.map { ($0.isEnabled, $0.state) }
    #expect(states.map(\.0) == [false, true, false, true])
    #expect(states.map(\.1) == [.off, .on, .on, .off])
  }

  @Test func commandItemsSendTheirActionAndSubmenuHoldersDoNot() throws {
    let menu = EngineMenuBuilder.menu([Self.item("Copy", 1), .submenu("More", [Self.item("Paste", 2)])]) { _ in }
    let choose = #selector(EngineMenuCommandTarget.choose(_:))
    #expect(menu.items[0].action == choose)
    #expect(menu.items[0].target != nil)
    // AppKit gives a holder its own `submenuAction:` and target once the submenu is set; never the command's.
    #expect(menu.items[1].action != choose)
    #expect(menu.items[1].target !== menu.items[0].target)
    #expect(menu.items[1].submenu != nil)
  }

  @Test func nestedSubmenusBuildEveryLevel() throws {
    let tree: [EngineMenuItem] = [
      .submenu("One", [Self.item("A", 1), .submenu("Two", [Self.item("B", 2), .submenu("Three", [
        Self.item("C", 3, checked: true), Self.item("D", 4, enabled: false),
      ])])]),
    ]
    let menu = EngineMenuBuilder.menu(tree) { _ in }
    let one = try #require(menu.items.first?.submenu)
    let two = try #require(one.items.last?.submenu)
    let three = try #require(two.items.last?.submenu)
    #expect(titles(one) == ["A", "Two"])
    #expect(titles(two) == ["B", "Three"])
    #expect(titles(three) == ["C", "D"])
    #expect(three.items[0].state == .on)
    #expect(!three.items[1].isEnabled)
    #expect(!one.autoenablesItems && !two.autoenablesItems && !three.autoenablesItems)
    #expect(one.title == "One" && three.title == "Three")
  }

  @Test func disabledSubmenuHolderStaysDisabled() {
    let menu = EngineMenuBuilder.menu([.submenu("More", [Self.item("A", 1)], isEnabled: false)]) { _ in }
    #expect(!menu.items[0].isEnabled)
  }

  @Test func emptySubmenuShowsADisabledHolder() {
    let menu = EngineMenuBuilder.menu([.submenu("Empty", []), .submenu("Only separators", [.separator, .separator])])
    { _ in }
    #expect(titles(menu) == ["Empty", "Only separators"])
    #expect(menu.items.allSatisfy { !$0.isEnabled })
    #expect(menu.items.allSatisfy { $0.submenu?.items.isEmpty ?? true })
  }

  @Test func fortyItemsAllBuildInOrder() {
    let items = (0..<40).map { Self.item("Item \($0)", 1000 + $0, enabled: $0 % 3 != 0, checked: $0 % 5 == 0) }
    let menu = EngineMenuBuilder.menu(items) { _ in }
    #expect(menu.items.count == 40)
    #expect(titles(menu) == (0..<40).map { "Item \($0)" })
    #expect(menu.items.map(\.isEnabled) == (0..<40).map { $0 % 3 != 0 })
    #expect(menu.items.map { $0.state == .on } == (0..<40).map { $0 % 5 == 0 })
  }

  @Test func longAndNonLatinTitlesAreKeptVerbatim() {
    let long = String(repeating: "Search the web for a very long selected phrase ", count: 12)
    let other = "\u{0627}\u{0644}\u{0628}\u{062D}\u{062B} \u{691C}\u{7D22} \u{041F}\u{043E}\u{0438}\u{0441}\u{043A}"
    let menu = EngineMenuBuilder.menu([Self.item(long, 1), Self.item(other, 2), Self.item("", 3)]) { _ in }
    #expect(long.count > 500)
    #expect(menu.items[0].title == long)
    #expect(menu.items[1].title == other)
    #expect(menu.items[2].title == "")
    #expect(!menu.items[2].isSeparatorItem)
  }

  // MARK: Separators

  @Test func separatorsAtTheEndsAreDropped() {
    let menu = EngineMenuBuilder.menu([.separator, .separator, Self.item("A", 1), .separator, Self.item("B", 2),
                                       .separator]) { _ in }
    #expect(titles(menu) == ["A", "-", "B"])
  }

  @Test func runsOfSeparatorsCollapseToOne() {
    let menu = EngineMenuBuilder.menu([Self.item("A", 1), .separator, .separator, .separator, Self.item("B", 2)])
    { _ in }
    #expect(titles(menu) == ["A", "-", "B"])
  }

  @Test func separatorsAreTidiedInsideSubmenus() throws {
    let menu = EngineMenuBuilder.menu([.submenu("More", [.separator, Self.item("A", 1), .separator, .separator,
                                                         Self.item("B", 2), .separator])]) { _ in }
    let submenu = try #require(menu.items.first?.submenu)
    #expect(titles(submenu) == ["A", "-", "B"])
  }

  @Test func onlySeparatorsAndEmptyListBuildEmptyMenus() {
    #expect(EngineMenuBuilder.menu([.separator, .separator]) { _ in }.items.isEmpty)
    #expect(EngineMenuBuilder.menu([]) { _ in }.items.isEmpty)
  }

  // MARK: Selection

  @Test func selectingAnItemCallsBackWithItsCommand() {
    var received: [EngineMenuCommand] = []
    let menu = EngineMenuBuilder.menu([Self.item("Copy", 50150), Self.item("Paste", 50151)]) { received.append($0) }
    menu.performActionForItem(at: 1)
    menu.performActionForItem(at: 0)
    #expect(received == [Self.command(50151), Self.command(50150)])
  }

  @Test func selectingANestedItemCallsBackWithItsCommand() throws {
    var received: [EngineMenuCommand] = []
    let menu = EngineMenuBuilder.menu([.submenu("One", [.submenu("Two", [Self.item("Deep", 77)])])]) {
      received.append($0)
    }
    let two = try #require(menu.items.first?.submenu?.items.first?.submenu)
    two.performActionForItem(at: 0)
    #expect(received == [Self.command(77)])
  }

  @Test func disabledItemNeverDeliversItsCommand() {
    var received: [EngineMenuCommand] = []
    let menu = EngineMenuBuilder.menu([Self.item("Off", 9, enabled: false)]) { received.append($0) }
    menu.performActionForItem(at: 0)
    #expect(received.isEmpty)
  }

  @Test func checkedItemStillDeliversItsCommand() {
    var received: [EngineMenuCommand] = []
    let menu = EngineMenuBuilder.menu([Self.item("Spell check", 5, checked: true)]) { received.append($0) }
    menu.performActionForItem(at: 0)
    #expect(received == [Self.command(5)])
  }

  // MARK: Ownership

  /// The owner keeps the menu; the menu reaches the owner only through the callback, which captures it weakly.
  private final class Owner {
    var received: [EngineMenuCommand] = []
    var menu: NSMenu?
    @MainActor func show(_ items: [EngineMenuItem]) {
      menu = EngineMenuBuilder.menu(items) { [weak self] in self?.received.append($0) }
    }
  }

  @Test func ownerHoldingTheMenuIsReleased() {
    weak var weakOwner: Owner?
    weak var weakMenu: NSMenu?
    autoreleasepool {
      let owner = Owner()
      owner.show([Self.item("Copy", 1), .submenu("More", [Self.item("Paste", 2)])])
      owner.menu?.performActionForItem(at: 0)
      #expect(owner.received == [Self.command(1)])
      weakOwner = owner
      weakMenu = owner.menu
    }
    #expect(weakOwner == nil)
    #expect(weakMenu == nil)
  }

  @Test func menuOutlivingItsOwnerDropsSelectionsQuietly() {
    weak var weakOwner: Owner?
    var kept: NSMenu?
    autoreleasepool {
      let owner = Owner()
      owner.show([Self.item("Copy", 1)])
      kept = owner.menu
      weakOwner = owner
    }
    #expect(weakOwner == nil)
    kept?.performActionForItem(at: 0)
    #expect(kept?.items.count == 1)
  }

  @Test func menuAndItsCommandTargetAreReleasedTogether() {
    weak var weakMenu: NSMenu?
    weak var weakTarget: AnyObject?
    autoreleasepool {
      let menu = EngineMenuBuilder.menu([Self.item("Copy", 1), .submenu("More", [Self.item("Paste", 2)])]) { _ in }
      weakMenu = menu
      weakTarget = menu.items[0].target
      #expect(weakTarget != nil)
      #expect(menu.items[1].submenu?.items[0].target === weakTarget)
    }
    #expect(weakMenu == nil)
    #expect(weakTarget == nil)
  }
}
