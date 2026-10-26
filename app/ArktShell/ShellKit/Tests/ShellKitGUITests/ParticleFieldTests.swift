import AppKit
import Metal
import QuartzCore
import XCTest
import simd
@testable import ShellUI

/// The particle field on the GPU (onboarding spec, section 7.4): the kernel springs motes onto their targets, Reduce
/// Motion dissolves in place, the stage stops when hidden and releases itself after the finish, and the frame budget
/// at 2x on this machine.
@MainActor
final class ParticleFieldTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func renderer(tier: ParticleRenderer.Tier = .fallback) throws -> ParticleRenderer {
    guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
    return try XCTUnwrap(ParticleRenderer(device: device, tier: tier, size: SIMD2(1120, 720), ink: ParticleColors.graphite))
  }

  private func uniforms(time: Float, dt: Float, reduced: Bool = false, count: Int) -> ParticleUniforms {
    ParticleUniforms(time: SIMD4(time, dt, Float(max(1, Int((dt * 240).rounded(.up)))), reduced ? 1 : 0),
                     view: SIMD4(1120, 720, 2, 1), config: SIMD4(Float(count), 3.4, 3.2, 0))
  }

  private func restTargets(count: Int, at point: SIMD2<Float>, reduced: Bool = false) -> [ParticleTarget] {
    let input = ParticleFormationBuilder.Input(size: SIMD2(1120, 720), count: count, now: 0, epoch: 1, dark: false,
                                               reduceMotion: reduced, mark: [])
    let rect = CGRect(x: CGFloat(point.x) - 2, y: CGFloat(point.y) - 2, width: 4, height: 4)
    return ParticleFormationBuilder(input: input).buildCard(rect).map { target in
      var copy = target
      copy.target = SIMD4(point.x, point.y, 0, 0)
      copy.color.w = 1
      return copy
    }
  }

  func testKernelSpringsMotesOntoTheirTargets() throws {
    let field = try renderer()
    field.upload(restTargets(count: field.count, at: SIMD2(500, 300)))
    var time: Float = 0
    for _ in 0..<360 {                                   // 3 s at 120 Hz
      time += 1.0 / 120
      field.stepForTest(uniforms: uniforms(time: time, dt: 1.0 / 120, count: field.count))
    }
    let states = field.readStates()
    let mean = states.map { simd_distance(SIMD2($0.positionVelocity.x, $0.positionVelocity.y), SIMD2(500, 300)) }
      .reduce(0, +) / Float(states.count)
    XCTAssertLessThan(mean, 2, "motes settle on the target")
    XCTAssertGreaterThan(states.map(\.color.w).min() ?? 0, 0.9, "colour eased in")
  }

  func testReduceMotionDissolvesInPlace() throws {
    let field = try renderer()
    field.upload(restTargets(count: field.count, at: SIMD2(200, 200), reduced: true))
    var time: Float = 0
    for _ in 0..<120 {
      time += 1.0 / 120
      field.stepForTest(uniforms: uniforms(time: time, dt: 1.0 / 120, reduced: true, count: field.count))
    }
    let states = field.readStates()
    XCTAssertTrue(states.allSatisfy { $0.positionVelocity.x == 200 && $0.positionVelocity.y == 200 },
                  "nothing travels: every mote reappears at its target")
  }

  func testStageStopsWhenHiddenAndReleasesAfterTheFinish() throws {
    guard let stage = MetalOnboardingStage.make() else { throw XCTSkip("no Metal device") }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView?.addSubview(stage.view)
    stage.view.frame = window.contentView?.bounds ?? .zero
    window.orderFront(nil)
    stage.show(.welcome(mark: CGRect(x: 450, y: 84, width: 220, height: 200)), appearance: .init(flavor: .light),
               animated: true)
    XCTAssertTrue(stage.isRunning)
    XCTAssertFalse(stage.view.isAccessibilityElement())
    XCTAssertNil(stage.view.hitTest(NSPoint(x: 10, y: 10)))
    stage.setVisible(false)
    XCTAssertFalse(stage.isRunning, "no frames while occluded")
    stage.setVisible(true)
    XCTAssertTrue(stage.isRunning)
    var finished = false
    stage.finish(onto: CGRect(x: 200, y: 10, width: 910, height: 700), appearance: .init(flavor: .light)) {
      finished = true
    }
    let deadline = Date().addingTimeInterval(4)
    while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(finished, "the field fades from +0.9 s and releases itself")
    XCTAssertFalse(stage.isRunning)
    window.close()
  }

  /// Section 7.4 budget: GPU at most 1.0 ms and CPU at most 0.3 ms per frame at 2x and 120 Hz (M1). Measured here on
  /// this machine's GPU with the full tier over 240 frames into a window-sized layer.
  func testFrameBudgetAt2x() throws {
    guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.apple7) else {
      throw XCTSkip("the full tier runs on Apple silicon")
    }
    try PacingEnvironment.skipIfNotMeasurable()
    let field = try renderer(tier: .full)
    let input = ParticleFormationBuilder.Input(size: SIMD2(1120, 720), count: field.count, now: 0, epoch: 1,
                                               dark: false, mark: MetalOnboardingStage.markSamples)
    field.upload(ParticleFormationBuilder(input: input).build(.welcome(mark: CGRect(x: 450, y: 84, width: 220,
                                                                                    height: 200))))
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.isOpaque = false
    layer.drawableSize = CGSize(width: 2240, height: 1440)
    var cpu: [Double] = []
    var time: Float = 0
    for _ in 0..<240 {
      guard let drawable = layer.nextDrawable() else { continue }
      time += 1.0 / 120
      let start = CACurrentMediaTime()
      field.frame(into: drawable, uniforms: uniforms(time: time, dt: 1.0 / 120, count: field.count), additive: false)
      cpu.append((CACurrentMediaTime() - start) * 1000)
    }
    let wait = Date().addingTimeInterval(2)
    while field.gpuTimes.samples.count < 200, Date() < wait { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let gpu = field.gpuTimes.samples.sorted()
    let cpuSorted = cpu.sorted()
    XCTAssertGreaterThan(gpu.count, 100)
    let gpuMedian = gpu[gpu.count / 2], gpuP95 = gpu[gpu.count * 95 / 100]
    let cpuMedian = cpuSorted[cpuSorted.count / 2]
    print("PARTICLE BUDGET motes \(field.count) gpu median \(gpuMedian) ms p95 \(gpuP95) ms cpu median \(cpuMedian) ms")
    XCTAssertLessThanOrEqual(gpuMedian, 1.0, "GPU per frame")
    XCTAssertLessThanOrEqual(cpuMedian, 0.3, "CPU per frame")
  }
}
