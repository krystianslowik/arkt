import Testing
import EngineAPI

/// The engine's menu item model (#587): one value per command, separator or submenu, as the page and extension
/// context menus report them.
struct EngineMenuItemTests {
  private let copy = EngineCommand(rawValue: 50150)

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

  @Test func itemsCompareByValue() {
    #expect(EngineMenuItem(title: "Copy", command: copy) == EngineMenuItem(title: "Copy", command: copy))
    #expect(EngineMenuItem(title: "Copy", command: copy)
            != EngineMenuItem(title: "Copy", command: copy, isChecked: true))
    #expect(EngineMenuItem.submenu("A", []) != EngineMenuItem.submenu("A", [.separator]))
  }
}
