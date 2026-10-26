import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// The facade's link activation and unhandled key seams (#313) reach the shell's host with Swift tab ids.
@MainActor
struct ChromiumLinkActivationTests {
  final class Activation: NSObject, ArktLinkActivation {
    let url: URL
    let tab: any ArktTabHandle
    let sourceURL: URL?
    let modifierFlags: NSEvent.ModifierFlags
    let disposition: Int
    init(url: URL, tab: any ArktTabHandle, sourceURL: URL?, modifierFlags: NSEvent.ModifierFlags = [],
         disposition: Int = 1) {
      self.url = url; self.tab = tab; self.sourceURL = sourceURL
      self.modifierFlags = modifierFlags; self.disposition = disposition
    }
  }

  final class Host: EngineWindowHosting {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                          backing: .buffered, defer: true)
    let cardView = NSView()
    var forward: EngineCommandForwarding?
    var onCloseRequested: (@MainActor () -> Void)?
    var decision: EngineLinkDecision = .cancel
    var activations: [EngineLinkActivation] = []
    var keys: [TabID?] = []
    func claim(_ command: EngineCommand) -> CommandClaim? { nil }
    func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool { false }
    func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision {
      activations.append(activation)
      return decision
    }
    func handleUnhandledKeyDown(_ event: NSEvent, in tab: TabID?) -> Bool {
      keys.append(tab)
      return true
    }
  }

  let facade = ScriptedFacade()
  static let source = URL(string: "arkt-test://mail.test/inbox")!
  static let target = URL(string: "arkt-test://atlas.test/lisbon")!

  private func makeEngine() throws -> (ChromiumEngine, Host, TabID, ScriptedBrowser) {
    let engine = ChromiumEngine(facade: facade)
    let host = Host()
    let window = engine.createWindow(host: host)
    let tab = engine.createTab(url: Self.source, in: window)
    let browser = try #require(engine.windows[window]?.browser as? ScriptedBrowser)
    return (engine, host, tab, browser)
  }

  @Test func aLinkActivationReachesTheHostWithTheSwiftTabAndModifiers() throws {
    let (engine, host, tab, browser) = try makeEngine()
    let handle = try #require(engine.handle(of: tab))
    let activation = Activation(url: Self.target, tab: handle, sourceURL: Self.source,
                                modifierFlags: [.shift, .capsLock], disposition: 6)

    let answer = try #require(browser.host.decideLinkActivation?(activation))

    #expect(answer == .cancel)
    #expect(host.activations == [EngineLinkActivation(url: Self.target, sourceTab: tab, sourceURL: Self.source,
                                                      modifiers: .shift,
                                                      disposition: EngineDisposition(rawValue: 6))])
  }

  @Test func aNavigateAnswerMapsToNavigate() throws {
    let (engine, host, tab, browser) = try makeEngine()
    host.decision = .navigate
    let activation = Activation(url: Self.target, tab: try #require(engine.handle(of: tab)), sourceURL: nil)
    #expect(browser.host.decideLinkActivation?(activation) == .navigate)
  }

  @Test func aTabThisInstanceDoesNotListNavigatesWithoutAskingTheHost() throws {
    let (_, host, _, browser) = try makeEngine()
    let stranger = ScriptedTab(facade: facade, owner: browser, opener: nil, origin: .engine)
    let activation = Activation(url: Self.target, tab: stranger, sourceURL: nil)
    #expect(browser.host.decideLinkActivation?(activation) == .navigate)
    #expect(host.activations.isEmpty)
  }

  @Test func anUnhandledKeyDownReachesTheHostWithTheTab() throws {
    let (engine, host, tab, browser) = try makeEngine()
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: 0, context: nil, characters: "\u{1b}",
                                               charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                               keyCode: 53))
    browser.host.unhandledKeyDown?(escape, in: try #require(engine.handle(of: tab)))
    browser.host.unhandledKeyDown?(escape, in: nil)
    #expect(host.keys == [tab, nil])
  }

  /// Peek gives its page the keyboard (#313): the facade's focus, not a responder change on the container.
  @Test func focusPageAsksTheTabHandleToFocus() throws {
    let (engine, _, tab, _) = try makeEngine()
    let handle = try #require(engine.handle(of: tab) as? ScriptedTab)
    #expect(handle.focusCount == 0)
    engine.focusPage(of: tab)
    #expect(handle.focusCount == 1)
  }
}
