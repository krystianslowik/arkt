import AppKit
import EngineAPI

// MARK: - Engine window

/// The window side of the engine's windows (week-3 plan, W3-7 A): one engine window per shell window, created on the
/// first tab, the commands the shell claims, and the Extensions control.
extension ShellWindowController {
  /// The engine window, created now when there is none yet (decision 4: on the first tab).
  func ensureEngineWindow() -> EngineWindowID {
    if let engineWindow { return engineWindow }
    let id = engine.createWindow(host: engineHost)
    attach(id)
    return id
  }

  private func attach(_ id: EngineWindowID) {
    engineWindow = id
    windowObservation = engine.observeWindows { [weak self] event in
      guard let self, event.windowID == self.engineWindow else { return }
      self.handleWindow(event)
    }
    refreshExtensions()
  }

  private func handleWindow(_ event: EngineWindowEvent) {
    switch event {
    case .windowOpened:
      break
    case .extensionActionsChanged:
      refreshExtensions()
    case .windowClosed:
      // Its tabs reported `.tabClosed(reason: .windowClosing)` already (contract rule 11).
      engineWindow = nil
      windowObservation = nil
      refreshExtensions()
      window?.close()
    }
  }

  // MARK: Commands (Decision 9)

  /// The commands the shell implements: New Tab opens the command bar, Close Tab archives or closes the current tab.
  /// The rest of the W3-8 table joins with the menu (part D).
  func claim(_ command: EngineCommand) -> CommandClaim? {
    switch command {
    case .newTab: CommandClaim(isEnabled: true)
    case .closeTab: CommandClaim(isEnabled: currentNode != nil)
    default: nil
    }
  }

  func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool {
    switch command {
    case .newTab:
      newTab(nil)
      return true
    case .closeTab:
      closeTab(nil)
      return true
    default:
      return false
    }
  }

  // MARK: Extensions (Decision 10)

  /// The Extensions control, only for an engine that runs extensions.
  func wireExtensions() {
    guard engine is any EngineExtensions else { return }
    let button = ExtensionsButton()
    button.onRun = { [weak self] id in self?.runExtensionAction(id) }
    extensionsButton = button
    sidebarController.view.extensionsButton = button
    refreshExtensions()
  }

  /// The window's actions; none before the engine window exists or after it closed.
  func refreshExtensions() {
    guard let button = extensionsButton, let extensions = engine as? any EngineExtensions else { return }
    button.actions = engineWindow.map { extensions.extensionActions(in: $0) } ?? []
  }

  private func runExtensionAction(_ id: String) {
    guard let engineWindow, let button = extensionsButton,
          let extensions = engine as? any EngineExtensions else { return }
    extensions.runExtensionAction(id, in: engineWindow, anchor: button)
  }
}
