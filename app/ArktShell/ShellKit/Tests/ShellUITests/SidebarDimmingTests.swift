import AppKit
import Testing
@testable import ShellUI

/// BH-025: which key window dims a window's sidebar. The window's own panels (the command bar) never do.
struct SidebarDimmingTests {
  private let window = NSObject()
  private let panel = NSObject()
  private let other = NSObject()

  @Test func theKeyWindowKeepsItsSidebar() {
    #expect(!ShellWindowController.dimsSidebar(window: window, keyWindow: window, isKey: true, ownPanels: [panel]))
  }

  @Test func itsOwnPanelBeingKeyKeepsTheSidebar() {
    #expect(!ShellWindowController.dimsSidebar(window: window, keyWindow: panel, isKey: false, ownPanels: [panel]))
  }

  @Test func anotherKeyWindowDimsTheSidebar() {
    #expect(ShellWindowController.dimsSidebar(window: window, keyWindow: other, isKey: false, ownPanels: [panel]))
  }

  @Test func noKeyWindowDimsTheSidebar() {
    #expect(ShellWindowController.dimsSidebar(window: window, keyWindow: nil, isKey: false, ownPanels: [panel]))
  }
}
