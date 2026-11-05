import AppKit
import EngineAPI

/// The native menu for a tree of engine menu items (#587): the page context menu (#122) and the extension context
/// menu (#121) share it. It follows design/tab-context-menus, section 7: plain `NSMenuItem`s with the system font
/// (the menu's font is left alone), no custom views, attributed titles, images or brand colors, and
/// `autoenablesItems` off so each item shows the engine's enabled and checked state as given. Titles are kept
/// verbatim; AppKit lays out and truncates long ones.
///
/// Separators are tidied the macOS way, at every level: a separator at the start or end of a menu is dropped and a
/// run of separators shows as one. A submenu left with no items shows its holder disabled, with no arrow.
///
/// Choosing an enabled command item calls `onCommand` with its command. The menu keeps its command target alive
/// through the items, and the target holds only `onCommand`, so the menu never retains its owner: an owner that
/// keeps the menu captures itself weakly in `onCommand`.
@MainActor
public enum EngineMenuBuilder {
  public static func menu(_ items: [EngineMenuItem], title: String = "",
                          onCommand: @escaping @MainActor (EngineCommand) -> Void) -> NSMenu {
    build(tidied(items), title: title, target: EngineMenuCommandTarget(onCommand))
  }

  /// `items` with separators dropped at the ends and runs collapsed, in every submenu too.
  public nonisolated static func tidied(_ items: [EngineMenuItem]) -> [EngineMenuItem] {
    var result: [EngineMenuItem] = []
    for item in items {
      if item.isSeparator {
        if let last = result.last, !last.isSeparator { result.append(item) }
      } else if let children = item.submenu {
        result.append(.submenu(item.title, tidied(children), isEnabled: item.isEnabled))
      } else {
        result.append(item)
      }
    }
    if result.last?.isSeparator == true { result.removeLast() }
    return result
  }

  private static func build(_ items: [EngineMenuItem], title: String, target: EngineMenuCommandTarget) -> NSMenu {
    let menu = NSMenu(title: title)
    menu.autoenablesItems = false
    for item in items {
      switch item.kind {
      case .separator:
        menu.addItem(.separator())
      case .command(let command):
        let native = NSMenuItem(title: item.title, action: #selector(EngineMenuCommandTarget.choose(_:)),
                                keyEquivalent: "")
        native.target = target
        native.representedObject = target     // the menu's items keep the unretained target alive
        native.tag = command.rawValue
        native.isEnabled = item.isEnabled
        native.state = item.isChecked ? .on : .off
        menu.addItem(native)
      case .submenu(let children):
        let holder = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        if children.isEmpty {
          holder.isEnabled = false
        } else {
          holder.submenu = build(children, title: item.title, target: target)
          holder.isEnabled = item.isEnabled
        }
        menu.addItem(holder)
      }
    }
    return menu
  }
}

/// Every command item's target in one built menu. It holds the callback only, never the menu or the owner.
@MainActor
final class EngineMenuCommandTarget: NSObject {
  private let onCommand: @MainActor (EngineCommand) -> Void

  init(_ onCommand: @escaping @MainActor (EngineCommand) -> Void) {
    self.onCommand = onCommand
  }

  /// A disabled item never delivers its command, even when its action is sent by hand.
  @objc func choose(_ sender: NSMenuItem) {
    guard sender.isEnabled else { return }
    onCommand(EngineCommand(rawValue: sender.tag))
  }
}
