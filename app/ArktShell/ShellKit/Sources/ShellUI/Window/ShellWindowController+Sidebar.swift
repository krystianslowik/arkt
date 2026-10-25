import AppKit

/// What a creation toast announces while the sidebar is hidden (BH-006).
public enum SidebarCreation: Sendable {
  case tab
  case space
}

/// Sidebar hide and show (#102): Cmd-S (KB-017, BH-001), the View menu item, and the toasts that stand in for the
/// hidden sidebar (BH-006). The edge drag (BH-002, BH-003) and the hover reveal (BH-004) live in `ShellRootView` and
/// `SidebarOverlayView`. BH-005 (a brief Option press shows the sidebar, 2021) is not implemented: expected absent in
/// Arc 1.168, PARITY(NEEDS-RUNTIME-CHECK RT-11).
///
/// The state belongs to this window (`rootView.sidebarVisible`) and lives as long as it, like the sidebar width; it is
/// not persisted across launches (neither is the width).
extension ShellWindowController {
  /// The sidebar is shown (docked) in this window.
  public var isSidebarVisible: Bool { rootView.sidebarVisible }

  /// Cmd-S (KB-017, BH-001) and View > Show / Hide Sidebar: hides or shows this window's sidebar at once. Not a reserved
  /// key: a page that handles Cmd-S itself (an editor's Save) keeps it, as with any menu key.
  ///
  /// Not named `toggleSidebar:`: `NSWindow` implements that selector (and disables it), and the window comes before its
  /// controller in the responder chain, so the menu item would never reach this method.
  @objc public func toggleSidebarVisibility(_ sender: Any?) {
    rootView.sidebarVisible.toggle()
  }

  /// The View menu item's title for the current state.
  public nonisolated static func sidebarMenuTitle(isVisible: Bool) -> String {
    isVisible ? "Hide Sidebar" : "Show Sidebar"
  }

  /// Arc's toast texts (BH-006; "New Space Created" is in Arc's strings).
  public nonisolated static func creationToastText(_ creation: SidebarCreation) -> String {
    switch creation {
    case .tab: "New Tab Created"
    case .space: "New Space Created"
    }
  }

  /// The toast's button. PARITY(NEEDS-RUNTIME-CHECK BH-006): Arc's toast is clickable; what the click does is not
  /// recorded. Arkt shows the sidebar, so the new tab or Space is in view.
  static let creationToastAction = "Show Sidebar"

  /// With the sidebar hidden, a new tab or Space would appear nowhere: a toast says it happened (BH-006).
  func announceCreation(_ creation: SidebarCreation) {
    guard !isSidebarVisible else { return }
    toasts.show(Toast(text: Self.creationToastText(creation), actionTitle: Self.creationToastAction)) { [weak self] in
      self?.rootView.sidebarVisible = true
    }
  }

  /// Titles View > Show / Hide Sidebar; nil for any other item.
  func validateSidebarMenuItem(_ menuItem: NSMenuItem) -> Bool? {
    guard menuItem.action == #selector(toggleSidebarVisibility(_:)) else { return nil }
    menuItem.title = Self.sidebarMenuTitle(isVisible: isSidebarVisible)
    return true
  }
}
