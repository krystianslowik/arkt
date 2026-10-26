import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Keyframes of the Open in flight for the pull request (#352), at the design's times (`la-kf-promote-*`). Skipped
/// unless `ARKT_FLIGHT_SHOTS_DIR` names a folder; writes `flight-<ms>ms.png` there. Each frame is rendered in process
/// from the test's own windows (main, Little Arkt, overlay), never a screen capture, so nothing else on the
/// screen can show. In-memory pages only; the windows' system frames and shadows are not drawn.
@MainActor
final class LittleArktFlightScreenshotTests: XCTestCase {
  private var folder: URL?
  private var set: ShellWindowSet?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_FLIGHT_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_FLIGHT_SHOTS_DIR to write the flight keyframes")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate()
  }

  override func tearDown() async throws {
    for controller in set?.controllers ?? [] { controller.window?.orderOut(nil) }
    for little in set?.littleArkts ?? [] {
      little.flight?.overlay.orderOut(nil)
      little.window.orderOut(nil)
    }
    set = nil
  }

  private func settle(_ seconds: TimeInterval = 0.4) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
  }

  /// `windows` back to front, each at its frame within `bounds` (screen points), at `scale`.
  private func compose(_ windows: [NSWindow], in bounds: CGRect, scale: CGFloat, name: String) throws {
    let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.55, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for window in windows where window.isVisible && window.alphaValue > 0.01 {
      guard let view = window.contentView else { continue }
      context.saveGState()
      context.setAlpha(window.alphaValue)
      if window is LittleArktFlightOverlay, let layer = view.layer {
        // Plain layers only (the flight's card and snapshot): rendered as they are.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: window.frame.minX - bounds.minX, y: window.frame.minY - bounds.minY)
        layer.render(in: context)
      } else if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let image = rep.cgImage {
          let frame = window.frame
          context.draw(image, in: CGRect(x: (frame.minX - bounds.minX) * scale, y: (frame.minY - bounds.minY) * scale,
                                         width: frame.width * scale, height: frame.height * scale))
        }
      }
      context.restoreGState()
    }
    let output = try XCTUnwrap(context.makeImage())
    let file = try XCTUnwrap(folder).appendingPathComponent("\(name).png")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, output, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  func testFlightKeyframes() throws {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    self.set = set
    set.littleArktReduceMotion = { false }
    set.littleArktConfigure = { $0.drivesDisplayLink = false }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    let main = set.openWindow()
    for name in ["Lisbon", "Calendar", "Recipes"] {
      main.open(try XCTUnwrap(URL(string: "arkt-test://page/\(name)")), inNewTab: true)
    }
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: URL(string: "arkt-test://page/Atlas"), isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    little.finishMotion()
    settle()

    little.openIn()
    let flight = try XCTUnwrap(little.flight)
    let deadline = Date().addingTimeInterval(5)               // screenshots only: a wall-clock bound is fine here
    while !flight.hasSnapshot, Date() < deadline { settle(0.02) }
    XCTAssertTrue(flight.hasSnapshot, "the engine's snapshot arrived")
    let mainWindow = try XCTUnwrap(main.window)
    let bounds = flight.overlay.frame
    let scale = flight.overlay.backingScaleFactor
    var t = 0.0
    for ms in [0, 80, 160, 260, 400] {
      while t <= Double(ms) / 1000 + 1e-9 {
        flight.tick(at: t)
        t += 1.0 / 120
      }
      if ms > 0 { little.finishMotion() }                     // the small frame's 0.12 s fade, near its end by 80 ms
      settle(0.15)
      try compose([mainWindow, little.window, flight.overlay], in: bounds, scale: scale, name: "flight-\(ms)ms")
    }
  }
}
