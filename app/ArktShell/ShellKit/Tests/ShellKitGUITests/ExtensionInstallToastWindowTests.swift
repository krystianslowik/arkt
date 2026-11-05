import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The post-install toast (#594) shows once per install, on the window app-level feedback goes to, and nowhere else.
@MainActor
final class ExtensionInstallToastWindowTests: XCTestCase {
  private var set: ShellWindowSet?

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for controller in set?.controllers ?? [] { controller.window?.orderOut(nil) }
    set = nil
  }

  func testAnInstallShowsOneToastOnThePrimaryWindowAndPinWorks() throws {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    self.set = set
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let primary = try XCTUnwrap(set.primary)

    engine.installExtension(InstalledExtension(id: "reader", name: "Quiet Reader"),
                            action: ExtensionAction(id: "reader", name: "Quiet Reader"))

    let shown = [first, second].filter { $0.toasts.current != nil }
    XCTAssertEqual(shown.map(ObjectIdentifier.init), [ObjectIdentifier(primary)])
    XCTAssertEqual(primary.toasts.current?.text, "\u{201C}Quiet Reader\u{201D} added")
    XCTAssertEqual(primary.toasts.current?.actionTitle, "Pin")

    primary.toasts.performActionForTesting()
    XCTAssertEqual(engine.pinnedExtensionIDs, ["reader"])
    XCTAssertNil(primary.toasts.current)
  }
}
