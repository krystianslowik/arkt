import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Pins, order and the context menu (#593)

extension ChromiumEngine {
  /// Chromium's toolbar pins of the engine's profile, in order: the same pins `chrome://extensions` shows as "Pin to
  /// toolbar". The facade lists each window's actions pinned first in this order.
  public var pinnedExtensionIDs: [String] { facade.pinnedExtensionIDs }

  /// The facade changes the profile's pins; every window that lists the action gets `.extensionActionsChanged` from
  /// its batch. A call the facade refuses (unknown, already in that state, pinned by policy) changes nothing.
  public func setExtensionPinned(_ extensionID: String, pinned: Bool) {
    facade.setExtensionPinned(extensionID, pinned: pinned)
  }

  public func movePinnedExtension(_ extensionID: String, to index: Int) {
    facade.movePinnedExtension(extensionID, to: index)
  }

  /// The items of Chromium's `ExtensionContextMenuModel` for the window's active tab, as the design lists them, with
  /// the extension's own action items after the header (#915). The facade keeps that model for
  /// `performExtensionContextCommand`, so a site access choice made after the tab moved to another site, or an
  /// extension item chosen after another tab became active, does nothing. Empty for a window the engine does not list.
  public func extensionContextMenu(forAction id: String, in window: EngineWindowID) -> [EngineMenuItem] {
    guard let browser = windows[window]?.browser else { return [] }
    return facade.extensionContextMenu(forAction: id, in: browser).map(EngineMenuItem.init(facade:))
  }

  /// Passed through as chosen, the extension's own items (`ExtensionContextCommand.customRange`, #915) included; the
  /// facade ignores Header, Manage and Remove, which the shell runs itself.
  public func performExtensionContextCommand(_ command: EngineMenuCommand, forAction id: String,
                                             in window: EngineWindowID) {
    guard let browser = windows[window]?.browser else { return }
    facade.performExtensionContextCommand(command.rawValue, forAction: id, in: browser)
  }
}
