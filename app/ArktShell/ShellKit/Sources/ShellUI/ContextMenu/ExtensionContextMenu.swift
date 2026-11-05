import AppKit
import EngineAPI

/// The context menu of an extension action (#596, design/extensions "The context menu"): a native `NSMenu` built by
/// `EngineMenuBuilder` from the engine's item tree, so Chromium's site access semantics stay authoritative and every
/// title and enabled or checked state is the engine's. The design table fixes the items: the name as a disabled
/// header, Options..., Pin or Unpin, Move Left and Move Right (pinned only, each disabled at its end), the site access
/// submenu (host permissions only), Manage Extension... and Remove from Arkt....
///
/// A chosen item goes back to the engine through `performExtensionContextCommand`, except `manage` and `remove`,
/// which the shell runs itself (`ExtensionContextCommand`): `onManage` opens the extension's entry in Settings,
/// Extensions (#600) and `onRemove` opens the remove sheet. Both get the action as it was when the menu was built.
///
/// The menu holds the engine weakly: a menu that outlives its engine drops selections quietly.
@MainActor
public enum ExtensionContextMenu {
  /// The menu of action `id` in `window`; nil when the engine lists no such action (it went away) or gives no items.
  public static func menu(forAction id: String, in window: EngineWindowID, engine: any EngineExtensions,
                          onManage: @escaping @MainActor (ExtensionAction) -> Void,
                          onRemove: @escaping @MainActor (ExtensionAction) -> Void) -> NSMenu? {
    guard let action = engine.extensionActions(in: window).first(where: { $0.id == id }) else { return nil }
    let items = engine.extensionContextMenu(forAction: id, in: window)
    guard !items.isEmpty else { return nil }
    return EngineMenuBuilder.menu(items, title: action.name) { [weak engine] command in
      switch command {
      case ExtensionContextCommand.manage: onManage(action)
      case ExtensionContextCommand.remove: onRemove(action)
      default: engine?.performExtensionContextCommand(command, forAction: action.id, in: window)
      }
    }
  }
}

/// A view that shows an extension action's context menu (#596) the three ways the design asks for: right-click,
/// Ctrl-click (both through `menu(for:)`, which AppKit calls for either) and the accessibility show-menu action, so
/// the menu is reachable without a mouse. Every way asks `menuProvider` for a fresh menu, so the items follow the
/// engine's current state (pin, order, site access).
///
/// The seam for the Extensions panel (#595): its row view inherits from this view (or hosts one covering the row) and
/// sets `menuProvider` to `ExtensionContextMenu.menu(forAction:in:engine:onManage:onRemove:)` for the row's action.
open class ExtensionContextMenuView: NSView {
  /// A fresh menu for the row's action, or nil when it has none.
  public var menuProvider: (@MainActor () -> NSMenu?)?
  /// Shows the menu for the accessibility show-menu action. The default pops it up at the view's leading bottom
  /// corner, as a pull-down from the row; tests replace it, since a real pop-up runs a modal tracking loop.
  public var presentMenu: @MainActor (NSMenu, NSView) -> Void = ExtensionContextMenuView.popUpBelow

  public override func menu(for event: NSEvent) -> NSMenu? {
    menuProvider?()
  }

  public override func accessibilityPerformShowMenu() -> Bool {
    guard let menu = menuProvider?() else { return false }
    presentMenu(menu, self)
    return true
  }

  /// Pops `menu` up under `view`'s leading bottom corner.
  public static func popUpBelow(_ menu: NSMenu, _ view: NSView) {
    let y = view.isFlipped ? view.bounds.maxY : view.bounds.minY
    menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: y), in: view)
  }
}
