import AppKit
import EngineAPI

/// A window host for contract checks and ShellUI tests. Claims nothing unless told to, and records what it is asked
/// to perform. The window is created on first use (`defer: true`, never shown), so engines that never read it build
/// no window at all.
@MainActor
public final class StubWindowHost: EngineWindowHosting {
  public private(set) lazy var window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                                 styleMask: [.titled, .closable, .resizable],
                                                 backing: .buffered, defer: true)
  public private(set) lazy var cardView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
  public var forward: EngineCommandForwarding?
  public var onCloseRequested: (@MainActor () -> Void)?
  /// Commands this host claims, with their enabled state.
  public var claims: [EngineCommand: CommandClaim] = [:]
  public private(set) var performed: [(EngineCommand, EngineDisposition)] = []

  public init() {}

  public func claim(_ command: EngineCommand) -> CommandClaim? { claims[command] }

  public func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool {
    guard claims[command] != nil else { return false }
    performed.append((command, disposition))
    return true
  }
}
