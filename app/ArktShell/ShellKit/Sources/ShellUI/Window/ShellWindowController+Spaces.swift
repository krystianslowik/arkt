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

  private var canDeleteSpace: Bool { onRemoveSpace != nil && window?.attachedSheet == nil }
}

// MARK: - New, rename, reorder (#106)

extension ShellWindowController {
  /// New Space (BH-037; Spaces menu, empty state, the "+" button's menu): "Space N" right after the current Space,
  /// shown at once (a direct response to a command, so the pager jumps) with its title open for editing (decision on
  /// #106).
  @objc public func newSpace(_ sender: Any?) {
    guard let space = createSpace() else { return }
    sidebarController.showSpace(space)
    page(of: space)?.beginRename()
  }

  /// Spaces > Rename Space: opens the current Space's title in its header (BH-038).
  @objc public func renameSpace(_ sender: Any?) {
    guard let space = currentSpace else { return }
    page(of: space)?.beginRename()
  }

  /// Spaces > Move Space Left / Right (BH-039 by menu [I]; the header drag is deferred): the current Space swaps
  /// places with its neighbour in this window's profile and stays current. Ctrl-1 ... Ctrl-9 follow the new order.
  @objc public func moveSpaceLeft(_ sender: Any?) { moveCurrentSpace(by: -1) }
  @objc public func moveSpaceRight(_ sender: Any?) { moveCurrentSpace(by: 1) }

  /// "Space N", N the smallest number no Space holds yet (decision on #106).
  func nextSpaceTitle() -> String {
    SpaceNaming.nextTitle(base: Self.newSpaceTitle, taken: sidebar.spaceOrder.compactMap { sidebar.space($0)?.title })
  }

  /// The bottom bar's "+" keeps Cmd-T on a click; its context menu adds New Space [I]
  /// (PARITY(NEEDS-RUNTIME-CHECK): what Arc's "+" offers).
  func wireSpaceEntryPoints() {
    let menu = NSMenu(title: "New")
    for (title, action) in [("New Tab", #selector(newTab(_:))), ("New Space", #selector(newSpace(_:)))] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    sidebarController.view.newTabButton.menu = menu
  }

  private func page(of space: SpaceID) -> SpacePageView? {
    pager.pages.lazy.compactMap { $0 as? SpacePageView }.first { $0.spaceID == space }
  }

  /// The current Space's place among this profile's Spaces, and the neighbour `offset` away, if any.
  private func neighbour(by offset: Int) -> (space: SpaceID, neighbour: SpaceID)? {
    let spaces = sidebarController.spaces
    guard let space = currentSpace, let index = spaces.firstIndex(of: space),
          spaces.indices.contains(index + offset) else { return nil }
    return (space, spaces[index + offset])
  }

  private func moveCurrentSpace(by offset: Int) {
    guard let (space, neighbour) = neighbour(by: offset),
          let target = sidebar.spaceOrder.firstIndex(of: neighbour) else { return }
    // Measured before the Space is removed: right lands just after the neighbour, left just before it.
    sidebar.moveSpace(space, to: offset > 0 ? target + 1 : target)
  }

  /// Validates the Spaces menu's Space items; nil for other items. New Space works without a Space (empty state);
  /// Rename needs one; a move needs a neighbour on that side; Delete Space needs an app that removes Spaces and no
  /// open sheet.
  func validateSpaceMenuItem(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(newSpace(_:)): true
    case #selector(renameSpace(_:)): currentSpace != nil
    case #selector(moveSpaceLeft(_:)): neighbour(by: -1) != nil
    case #selector(moveSpaceRight(_:)): neighbour(by: 1) != nil
    case #selector(deleteSpace(_:)): canDeleteSpace && currentSpace != nil
    default: nil
    }
  }
}
