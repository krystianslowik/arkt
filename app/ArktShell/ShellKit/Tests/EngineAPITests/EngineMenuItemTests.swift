import Testing
import EngineAPI

/// The engine's menu item model (#587): one value per command, separator or submenu, as the page and extension
/// context menus report them.
struct EngineMenuItemTests {
  private let copy = EngineMenuCommand(rawValue: 50150)

  @Test func commandItemCarriesItsValues() {
    let item = EngineMenuItem(title: "Copy", command: copy, isEnabled: false, isChecked: true)
    #expect(item.title == "Copy")
    #expect(item.command == copy)
    #expect(!item.isEnabled)
    #expect(item.isChecked)
    #expect(!item.isSeparator)
    #expect(item.submenu == nil)
  }

  @Test func commandItemDefaultsToEnabledAndUnchecked() {
    let item = EngineMenuItem(title: "Copy", command: copy)
    #expect(item.isEnabled)
    #expect(!item.isChecked)
  }

  @Test func separatorHasNoTitleCommandOrSubmenu() {
    let item = EngineMenuItem.separator
    #expect(item.isSeparator)
    #expect(item.title.isEmpty)
    #expect(item.command == nil)
    #expect(item.submenu == nil)
    #expect(!item.isEnabled)
  }

  @Test func submenuHoldsItsChildrenAndNoCommand() {
    let children = [EngineMenuItem(title: "Copy", command: copy), .separator]
    let item = EngineMenuItem.submenu("Edit", children)
    #expect(item.title == "Edit")
    #expect(item.submenu == children)
    #expect(item.command == nil)
    #expect(!item.isSeparator)
    #expect(item.isEnabled)
  }

  @Test func menuCommandKeepsItsRawValueAndHashes() {
    #expect(EngineMenuCommand(rawValue: 7).rawValue == 7)
    #expect(Set([EngineMenuCommand(rawValue: 1), EngineMenuCommand(rawValue: 1), EngineMenuCommand(rawValue: 2)])
            .count == 2)
  }

  @Test func tidiedDropsEndSeparatorsAndCollapsesRunsAtEveryLevel() {
    let a = EngineMenuItem(title: "A", command: copy)
    let b = EngineMenuItem(title: "B", command: EngineMenuCommand(rawValue: 2))
    let tidied = EngineMenuItem.tidied([.separator, a, .separator, .separator,
                                        .submenu("S", [.separator, b, .separator]), .separator])
    #expect(tidied == [a, .separator, .submenu("S", [b])])
    #expect(EngineMenuItem.tidied([.separator, .separator]).isEmpty)
  }

  @Test func tidiedKeepsTheHolderValuesItDoesNotTouch() {
    let holder = EngineMenuItem.submenu("Disabled", [.separator, EngineMenuItem(title: "A", command: copy)],
                                        isEnabled: false)
    let tidied = EngineMenuItem.tidied([holder])
    #expect(tidied.count == 1)
    #expect(tidied.first?.title == "Disabled")
    #expect(tidied.first?.isEnabled == false)
    #expect(tidied.first?.submenu == [EngineMenuItem(title: "A", command: copy)])
  }

  @Test func itemsCompareByValue() {
    #expect(EngineMenuItem(title: "Copy", command: copy) == EngineMenuItem(title: "Copy", command: copy))
    #expect(EngineMenuItem(title: "Copy", command: copy)
            != EngineMenuItem(title: "Copy", command: copy, isChecked: true))
    #expect(EngineMenuItem.submenu("A", []) != EngineMenuItem.submenu("A", [.separator]))
  }
}
