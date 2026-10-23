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
    message = title.isEmpty ? "Delete this Space?" : "Delete the Space \"\(title)\"?"
    information = hasItems
      ? "Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them."
      : "This cannot be undone."
  }
}

// MARK: - Delete Space

extension ShellWindowController {
  /// Spaces menu > Delete Space (#206). Asks through `confirmSpaceRemoval` for every Space, empty ones included (the
  /// Space itself cannot be restored), then hands the Space it asked about to `onRemoveSpace`, unless that Space is
  /// already gone. Removing the last Space shows the empty state (decision on #86).
  @objc public func deleteSpace(_ sender: Any?) {
    guard onRemoveSpace != nil, let space = currentSpace else { return }
    let hasItems = !sidebar.children(of: .pinned(space)).isEmpty || !sidebar.children(of: .today(space)).isEmpty
    let prompt = SpaceRemovalPrompt(space: space, title: sidebar.space(space)?.title ?? "", hasItems: hasItems)
    confirmSpaceRemoval?(prompt) { [weak self] confirmed in
      guard confirmed, let self, self.sidebar.space(space) != nil else { return }
      self.onRemoveSpace?(space)
    }
  }

  /// The default `confirmSpaceRemoval`: an alert sheet on this window, Delete Space first and marked destructive.
  func presentSpaceRemovalSheet(_ prompt: SpaceRemovalPrompt, answer: @escaping @MainActor (Bool) -> Void) {
    guard let window else { return answer(false) }
    let alert = NSAlert()
    alert.messageText = prompt.message
    alert.informativeText = prompt.information
    alert.addButton(withTitle: SpaceRemovalPrompt.confirmTitle).hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { response in answer(response == .alertFirstButtonReturn) }
  }

  /// Delete Space needs a current Space and an app that removes Spaces; nil for other items.
  func validateSpaceMenuItem(_ item: NSMenuItem) -> Bool? {
    guard item.action == #selector(deleteSpace(_:)) else { return nil }
    return onRemoveSpace != nil && currentSpace != nil
  }
}
