import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing

/// The link activation and unhandled key seams of `EngineWindowHosting` (#313), through InMemoryEngine.
@MainActor
struct LinkActivationTests {
  /// A host that answers every link activation with `decision` and records what it was asked.
  final class DecidingHost: EngineWindowHosting {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                          backing: .buffered, defer: true)
    let cardView = NSView()
    var forward: EngineCommandForwarding?
    var onCloseRequested: (@MainActor () -> Void)?
    var decision: EngineLinkDecision = .navigate
    var activations: [EngineLinkActivation] = []
    var keys: [(UInt16, TabID?)] = []
    var handlesKeys = true

    func claim(_ command: EngineCommand) -> CommandClaim? { nil }
    func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool { false }
    func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision {
      activations.append(activation)
      return decision
    }
    func handleUnhandledKeyDown(_ event: NSEvent, in tab: TabID?) -> Bool {
      keys.append((event.keyCode, tab))
      return handlesKeys
    }
  }

  private static let source = URL(string: "https://mail.example/inbox")!
  private static let target = URL(string: "https://atlas.example/lisbon")!

  @Test func aNavigateAnswerLetsTheLinkNavigateTheSourceTab() throws {
    let engine = InMemoryEngine()
    let host = DecidingHost()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: Self.source, in: window)

    let decision = engine.simulateLinkActivation(in: tab, url: Self.target)

    #expect(decision == .navigate)
    #expect(engine.snapshot(of: tab)?.url == Self.target)
    let asked = try #require(host.activations.first)
    #expect(asked == EngineLinkActivation(url: Self.target, sourceTab: tab, sourceURL: Self.source,
                                          modifiers: [], disposition: .currentTab))
  }

  @Test func aCancelAnswerLeavesTheSourceTabWhereItWas() {
    let engine = InMemoryEngine()
    let host = DecidingHost()
    host.decision = .cancel
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: Self.source, in: window)

    #expect(engine.simulateLinkActivation(in: tab, url: Self.target, modifiers: .shift) == .cancel)
    #expect(engine.snapshot(of: tab)?.url == Self.source)
    #expect(host.activations.first?.modifiers == .shift)
  }

  @Test func aHostThatDoesNotDecideNavigates() {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: Self.source, in: window)

    #expect(engine.simulateLinkActivation(in: tab, url: Self.target) == .navigate)
    #expect(engine.snapshot(of: tab)?.url == Self.target)
  }

  @Test func anUnhandledKeyDownReachesTheHostOfTheTabsWindowWithTheTab() throws {
    let engine = InMemoryEngine()
    let host = DecidingHost()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: Self.source, in: window)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: 0, context: nil, characters: "\u{1b}",
                                               charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53))

    #expect(engine.simulateUnhandledKeyDown(escape, in: tab))
    #expect(host.keys.count == 1)
    #expect(host.keys.first?.0 == 53)
    #expect(host.keys.first?.1 == tab)
  }

  @Test func aHostThatDoesNotTakeUnhandledKeysAnswersFalse() throws {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: Self.source, in: window)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: 0, context: nil, characters: "\u{1b}",
                                               charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53))
    #expect(!engine.simulateUnhandledKeyDown(escape, in: tab))
  }

  @Test(arguments: zip(
    [NSEvent.ModifierFlags.shift, .command, .option, .control, [.shift, .command, .capsLock]],
    [EngineLinkModifiers.shift, .command, .option, .control, [.shift, .command]]
  ))
  func linkModifiersMapFromAppKitFlags(flags: NSEvent.ModifierFlags, expected: EngineLinkModifiers) {
    #expect(EngineLinkModifiers(flags) == expected)
  }
}
