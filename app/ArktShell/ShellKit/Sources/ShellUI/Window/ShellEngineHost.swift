import AppKit
import EngineAPI

/// The engine's view of a shell window (week-3 plan, Decisions 2 and 6): the window, the card as dialog fallback, and
/// the command and close seams. A separate object rather than a conformance on `ShellWindowController`, because
/// `NSWindowController.window` is optional and `EngineWindowHosting.window` is not.
///
/// The engine holds the host; the host holds its controller weakly, so a closed shell window is never kept alive by
/// an engine that has not released the host yet.
@MainActor
public final class ShellEngineHost: EngineWindowHosting {
  public let window: NSWindow
  public let cardView: NSView
  /// Set by the engine: validates and runs the commands the shell does not claim.
  public var forward: EngineCommandForwarding?
  /// Set by the engine; the close button and Close Window call it, and the shell never closes its window itself.
  public var onCloseRequested: (@MainActor () -> Void)?
  weak var controller: ShellWindowController?

  init(window: NSWindow, cardView: NSView) {
    self.window = window
    self.cardView = cardView
  }

  public func claim(_ command: EngineCommand) -> CommandClaim? { controller?.claim(command) }

  public func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool {
    controller?.perform(command, disposition: disposition) ?? false
  }

  /// Peek decides user link clicks (#313); it answers without calling the engine.
  public func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision {
    controller?.peek.decide(activation) ?? .navigate
  }

  /// An Esc the page did not use closes an open Peek (Esc goes to the page first, decided 2026-10-25).
  public func handleUnhandledKeyDown(_ event: NSEvent, in tab: TabID?) -> Bool {
    guard event.keyCode == 53, let controller else { return false }
    return controller.peek.handleEscape(in: tab)
  }

  /// A command from a menu item or key equivalent: the shell runs the commands it claims, the engine the rest.
  /// Nothing happens for an unclaimed command while no engine window exists yet.
  func dispatch(_ command: EngineCommand, disposition: EngineDisposition) {
    if claim(command) != nil {
      _ = perform(command, disposition: disposition)
    } else {
      forward?.execute(command, disposition)
    }
  }

  /// The enabled state of `command`: the shell's claim, else the engine's answer; disabled with neither.
  func validate(_ command: EngineCommand) -> Bool {
    if let claim = claim(command) { return claim.isEnabled }
    return forward?.validate(command) ?? false
  }
}
