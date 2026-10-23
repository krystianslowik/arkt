import AppKit

/// What the Delete Space confirmation says (#206). The wording is [I]: the parity spec has no Delete Space flow,
/// PARITY(NEEDS-RUNTIME-CHECK).
public struct SpaceRemovalPrompt: Equatable, Sendable {
  /// The Space the answer removes.
  public var space: SpaceID
  public var message: String
  public var information: String
  /// The confirming button; Cancel is the other one.
  public static let confirmTitle = "Delete Space"

  /// `hasItems`: the Space holds pinned or Today items, which go to the Archive (decision on #86).
  public init(space: SpaceID, title: String, hasItems: Bool) {
    self.space = space
    message = title.isEmpty ? "Delete this Space?" : "Delete the Space \u{201C}\(title)\u{201D}?"
    information = hasItems
      ? "Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them."
      : "This cannot be undone."
  }
}

// MARK: - Delete Space

extension ShellWindowController {
  /// Spaces menu > Delete Space (#206). Asks through `confirmSpaceRemoval` for every Space, empty ones included (the
  /// Space itself cannot be restored), then hands the Space it asked about to `onRemoveSpace`, unless that Space is
  /// already gone. Removing the last Space shows the empty state (decision on #86). Nothing happens while a sheet is
  /// open, so a second request cannot queue a second sheet.
  @objc public func deleteSpace(_ sender: Any?) {
    guard canDeleteSpace, let space = currentSpace else { return }
    let hasItems = !sidebar.children(of: .pinned(space)).isEmpty || !sidebar.children(of: .today(space)).isEmpty
    let prompt = SpaceRemovalPrompt(space: space, title: sidebar.space(space)?.title ?? "", hasItems: hasItems)
    confirmSpaceRemoval?(prompt) { [weak self] confirmed in
      guard confirmed, let self, self.sidebar.space(space) != nil else { return }
      self.onRemoveSpace?(space)
    }
  }

  /// The default `confirmSpaceRemoval`: an alert sheet on this window, Delete Space first and marked destructive.
  /// Delete Space has no key, so a stray Return never deletes a Space; Escape answers Cancel (AppKit's key for a
  /// button titled Cancel).
  func presentSpaceRemovalSheet(_ prompt: SpaceRemovalPrompt, answer: @escaping @MainActor (Bool) -> Void) {
    guard let window else { return answer(false) }
    let alert = NSAlert()
    alert.messageText = prompt.message
    alert.informativeText = prompt.information
    let delete = alert.addButton(withTitle: SpaceRemovalPrompt.confirmTitle)
    delete.hasDestructiveAction = true
    delete.keyEquivalent = ""
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { response in answer(response == .alertFirstButtonReturn) }
  }

  /// Delete Space needs a current Space, an app that removes Spaces and no open sheet; nil for other items.
  func validateSpaceMenuItem(_ item: NSMenuItem) -> Bool? {
    guard item.action == #selector(deleteSpace(_:)) else { return nil }
    return canDeleteSpace && currentSpace != nil
  }

  private var canDeleteSpace: Bool { onRemoveSpace != nil && window?.attachedSheet == nil }
}
