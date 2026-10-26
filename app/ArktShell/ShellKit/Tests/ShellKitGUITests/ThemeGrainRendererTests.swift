import AppKit
import Metal
import XCTest
@testable import ShellUI

/// The Metal tier of the Space theme texture (#120): tiles drawn once per size, never per pager frame, and never
/// while the view cannot be seen.
@MainActor
final class ThemeGrainRendererTests: XCTestCase {
  private var window: NSWindow?

  override func tearDown() async throws {
    window?.close()
    window = nil
  }

  /// A renderer with every tile already synthesized (`warm`), so draws happen synchronously.
  private func renderer(warm: Bool = true) throws -> ThemeGrainRenderer {
    guard let renderer = ThemeGrainRenderer(device: MTLCreateSystemDefaultDevice()) else {
      throw XCTSkip("no Metal device")
    }
    if warm {
      renderer.prepareForTesting(scale: 1)
      renderer.prepareForTesting(scale: 2)
    }
    return renderer
  }

  private func theme(_ texture: String?, _ noise: Double) -> SpaceThemeInfo {
    SpaceThemeInfo(baseColors: [.p3(hex: 0x2D4468, alpha: 1), .p3(hex: 0x120F2E, alpha: 1)], texture: texture,
                   noiseFactor: noise, isDark: true)
  }

  /// Hosted in a window the view treats as visible while `visible` is true (the real check reads occlusion, which
  /// depends on whatever else is on screen).
  private var visible = true

  private func hosted(_ renderer: ThemeGrainRenderer, themes: [SpaceThemeInfo]) -> ThemeBackgroundView {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 320), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 320), grainRenderer: renderer)
    view.windowIsVisible = { [unowned self] _ in visible }
    window.contentView = view
    window.orderFrontRegardless()
    self.window = window
    view.themes = themes
    view.setPosition(0)
    view.layoutSubtreeIfNeeded()
    return view
  }

  /// Nearest sampling at the backing scale: every drawn pixel is the synthesized texel, tiled from the top left.
  func testTheDrawnTileIsTheSynthesizedTexturePixelForPixel() throws {
    let renderer = try renderer()
    for texture in ThemeTexture.allCases {
      let tile = texture.tile(scale: 2)
      let width = 330, height = 214
      let pixels = try XCTUnwrap(renderer.renderForTesting(texture, scale: 2, width: width, height: height))
      var mismatches = 0
      for y in 0..<height {
        for x in 0..<width where pixels[y * width + x] != tile.bytes[(y % tile.pixels) * tile.pixels + x % tile.pixels] {
          mismatches += 1
        }
      }
      XCTAssertEqual(mismatches, 0, "\(texture)")
    }
  }

  func testTexturesInUseAreDrawnOnceAndThePagerDrawsNothing() throws {
    let renderer = try renderer()
    let view = hosted(renderer, themes: [theme("grain", 0.5), theme("sand", 1), theme(nil, 0)])
    XCTAssertTrue(view.grainLayerForTesting(.grain) is CAReplicatorLayer)
    XCTAssertNotNil(view.grainTileForTesting(.grain))
    XCTAssertEqual(renderer.drawCount, 2, "one draw per texture in use")
    for step in 0...240 { view.setPosition(CGFloat(step) / 120) }
    XCTAssertEqual(renderer.drawCount, 2, "pager frames change alphas only")
    view.layoutSubtreeIfNeeded()
    XCTAssertEqual(renderer.drawCount, 2, "a layout at the same size draws nothing")
  }

  /// The tile is drawn once per scale; a resize only changes how many replicas cover the view.
  func testAResizeNeverDrawsAndTheReplicasCoverTheView() throws {
    let renderer = try renderer()
    let view = hosted(renderer, themes: [theme("tweed", 0.5)])
    XCTAssertEqual(renderer.drawCount, 1)
    for size in [NSSize(width: 520, height: 340), NSSize(width: 1333, height: 777), NSSize(width: 301, height: 199)] {
      window?.setContentSize(size)
      view.layoutSubtreeIfNeeded()
      let grid = try XCTUnwrap(view.grainLayerForTesting(.tweed) as? CAReplicatorLayer)
      let row = try XCTUnwrap(grid.sublayers?.first as? CAReplicatorLayer)
      let tile = try XCTUnwrap(view.grainTileForTesting(.tweed))
      XCTAssertEqual(tile.frame.size, CGSize(width: 100, height: 100))
      XCTAssertEqual(tile.frame.maxY, view.bounds.maxY, "anchored at the top left")
      XCTAssertGreaterThanOrEqual(CGFloat(row.instanceCount) * 100, size.width)
      XCTAssertLessThan(CGFloat(row.instanceCount - 1) * 100, size.width)
      XCTAssertGreaterThanOrEqual(CGFloat(grid.instanceCount) * 100, size.height)
      XCTAssertLessThan(CGFloat(grid.instanceCount - 1) * 100, size.height)
    }
    XCTAssertEqual(renderer.drawCount, 1, "no draw per resize")
  }

  func testAHiddenViewDefersItsDrawUntilItShows() throws {
    let renderer = try renderer()
    let view = hosted(renderer, themes: [theme(nil, 0)])
    view.isHidden = true
    view.themes = [theme("sand", 1)]
    view.setPosition(0)
    view.layoutSubtreeIfNeeded()
    XCTAssertEqual(renderer.drawCount, 0, "no frames while the view cannot be seen")
    view.isHidden = false
    XCTAssertEqual(renderer.drawCount, 1, "the deferred draw lands when it shows")
  }

  /// Occluded or miniaturized: nothing is drawn until the window server reports the window visible again.
  func testAnOccludedWindowDefersTheDrawUntilItIsVisible() throws {
    let renderer = try renderer()
    visible = false
    let view = hosted(renderer, themes: [theme("sand", 1), theme("denim", 0.5)])
    view.layoutSubtreeIfNeeded()
    XCTAssertEqual(renderer.drawCount, 0)
    visible = true
    NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
    XCTAssertEqual(renderer.drawCount, 2)
  }

  /// The main thread never synthesizes a tile: the first draw waits for it, made off the main thread, then lands.
  func testAColdTileIsSynthesizedOffTheMainThreadAndThenDrawn() throws {
    let renderer = try renderer(warm: false)
    _ = hosted(renderer, themes: [theme("sand", 1), theme("tweed", 0.5)])
    XCTAssertEqual(renderer.drawCount, 0, "nothing to draw before the tiles exist")
    let deadline = Date().addingTimeInterval(10)
    while renderer.drawCount < 2, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    XCTAssertEqual(renderer.drawCount, 2)
  }

  func testAViewInNoWindowNeverDraws() throws {
    let renderer = try renderer()
    let view = ThemeBackgroundView(frame: NSRect(x: 0, y: 0, width: 200, height: 100), grainRenderer: renderer)
    view.themes = [theme("denim", 1)]
    view.setPosition(0)
    view.layout()
    XCTAssertEqual(renderer.drawCount, 0)
  }

  /// A live resize of a 2x window from 900 to 1740 pt wide, 7 pt per frame: no draws at all, main-thread cost of
  /// each layout, and the footprint of two textures in use. GPU time of the one tile draw per texture is printed.
  func testALiveResizeDrawsNothingAndTheTexturesCostAlmostNoMemory() throws {
    let renderer = try renderer()
    _ = renderer.renderForTesting(.sand, scale: 2, width: 200, height: 200, readBack: false)   // Metal warm-up
    _ = renderer.renderForTesting(.grain, scale: 2, width: 200, height: 200, readBack: false)
    let view = hosted(renderer, themes: [theme(nil, 0)])
    window?.setContentSize(NSSize(width: 900, height: 800))
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let footprintBefore = Self.footprintMegabytes()
    renderer.gpuTimes.reset()
    view.themes = [theme("sand", 1), theme("grain", 0.5)]
    view.setPosition(0.5)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let footprintTextures = Self.footprintMegabytes() - footprintBefore
    let drawsBefore = renderer.drawCount
    var main: [Double] = []
    for step in 1...120 {
      window?.setContentSize(NSSize(width: 900 + CGFloat(step) * 7, height: 800))
      let start = ContinuousClock.now
      view.layoutSubtreeIfNeeded()
      let elapsed = ContinuousClock.now - start
      main.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
      RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))     // one frame: the commit lands
    }
    let gpu = renderer.gpuTimes.samples.sorted()
    main.sort()
    func percentile(_ values: [Double], _ p: Double) -> Double {
      values[min(values.count - 1, Int(Double(values.count) * p))]
    }
    print(String(format: "theme.grain.resize frames=120 draws=%d main p50=%.3f p95=%.3f max=%.3f ms; tile draws gpu "
                   + "max=%.3f ms; footprint +%.1f MB for two textures", renderer.drawCount - drawsBefore,
                 percentile(main, 0.5), percentile(main, 0.95), main.last ?? 0, gpu.last ?? 0, footprintTextures))
    XCTAssertEqual(renderer.drawCount - drawsBefore, 0, "a resize never draws")
    XCTAssertLessThan(percentile(main, 0.95), 1)
    XCTAssertLessThan(footprintTextures, 8)
  }

  /// The process's physical footprint (what Activity Monitor shows as memory).
  private static func footprintMegabytes() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
  }
}
