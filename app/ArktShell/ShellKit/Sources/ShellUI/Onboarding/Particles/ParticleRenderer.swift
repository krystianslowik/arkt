import Metal
import QuartzCore
import simd

/// The particle field's GPU side (section 7.4): one compute pass per frame springs every mote toward its target,
/// one draw of N point sprites renders them into a `CAMetalLayer`. The CPU sets uniforms only; targets are uploaded
/// when a formation changes. GPU time per frame is read back from the command buffers for the budget and the
/// fallback tier.
@MainActor
final class ParticleRenderer {
  /// Mote counts and frame rates of the two tiers.
  enum Tier: Equatable, Sendable {
    case full, fallback

    var count: Int { self == .full ? 20_480 : 8_192 }
    var preferredFrameRate: Float { self == .full ? 120 : 60 }
  }

<<<<<<< HEAD
  /// Which of the last 60 frames went over 2 ms of GPU time (section 7.4): a sliding window, so a sustained
  /// alternating overload trips the fallback tier while a lone spike does not. Bit 0 is the newest frame.
  struct GPUBudgetWindow: Equatable, Sendable {
    static let frames = 60
    static let tripCount = 30
    static let budgetMilliseconds = 2.0
    private static let mask: UInt64 = (1 << UInt64(frames)) - 1

    private var bits: UInt64 = 0

    mutating func record(_ milliseconds: Double) {
      bits = (bits << 1 | (milliseconds > Self.budgetMilliseconds ? 1 : 0)) & Self.mask
    }

    /// Frames over budget among the last 60.
    var overBudget: Int { bits.nonzeroBitCount }
    /// 30 of the last 60 frames over budget: 8,192 motes at 60 Hz from here on.
    var tripsFallback: Bool { overBudget >= Self.tripCount }
  }

  /// GPU milliseconds of the frames completed so far, written from Metal's completion queue.
  final class GPUTimes: Sendable {
    private let state = Mutex<(last: Double, window: GPUBudgetWindow, samples: [Double])>((0, .init(), []))

    func record(_ milliseconds: Double) {
      state.withLock {
        $0.last = milliseconds
        $0.window.record(milliseconds)
        if $0.samples.count < 4_096 { $0.samples.append(milliseconds) }
      }
    }

    /// 30 of the last 60 frames went over 2 ms of GPU time.
    var tripsFallback: Bool { state.withLock { $0.window.tripsFallback } }
    var samples: [Double] { state.withLock { $0.samples } }
    func reset() { state.withLock { $0 = (0, .init(), []) } }
  }

=======
>>>>>>> origin/main
  let device: any MTLDevice
  let tier: Tier
  let count: Int
  /// GPU milliseconds per frame; 2 ms is the budget the fallback tier watches.
  let gpuTimes = GPUFrameTimes(budgetMilliseconds: 2)
  private let queue: any MTLCommandQueue
  private let stepPipeline: any MTLComputePipelineState
  private let alphaPipeline: any MTLRenderPipelineState
  private let additivePipeline: any MTLRenderPipelineState
  private let states: any MTLBuffer
  private var targets: any MTLBuffer
  private(set) var lastTargets: [ParticleTarget]

  /// Nil when Metal or the shaders are unavailable; the flow then uses the Core Animation stage.
  init?(device: (any MTLDevice)?, tier: Tier, size: SIMD2<Float>, ink: SIMD3<Float>) {
    guard let device, let queue = device.makeCommandQueue() else { return nil }
    let library: any MTLLibrary
    do { library = try device.makeLibrary(source: ParticleShaders.source, options: nil) } catch { return nil }
    guard let step = library.makeFunction(name: "stepParticles"),
          let vertex = library.makeFunction(name: "particleVertex"),
          let fragment = library.makeFunction(name: "particleFragment"),
          let stepPipeline = try? device.makeComputePipelineState(function: step) else { return nil }
    func pipeline(additive: Bool) -> (any MTLRenderPipelineState)? {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = vertex
      descriptor.fragmentFunction = fragment
      let attachment = descriptor.colorAttachments[0]
      attachment?.pixelFormat = .bgra8Unorm
      attachment?.isBlendingEnabled = true
      attachment?.rgbBlendOperation = .add
      attachment?.alphaBlendOperation = .add
      attachment?.sourceRGBBlendFactor = .one
      attachment?.sourceAlphaBlendFactor = .one
      attachment?.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
      attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    guard let alpha = pipeline(additive: false), let additive = pipeline(additive: true) else { return nil }
    let count = tier.count
    var initial: [ParticleState] = []
    initial.reserveCapacity(count)
    var random = SeededRandom(seed: 11)
    for index in 0..<count {
      let position = SIMD2(random.next() * size.x, random.next() * size.y)
      initial.append(ParticleState(positionVelocity: SIMD4(lowHalf: position, highHalf: .zero), color: SIMD4(ink, 0),
                                   sizeSeed: SIMD4(1 + random.next() * 2, ParticleFormationBuilder.seed(index), 0, 0)))
    }
    let empty = [ParticleTarget](repeating: .zero, count: count)
    guard let states = device.makeBuffer(bytes: initial, length: MemoryLayout<ParticleState>.stride * count,
                                         options: .storageModeShared),
          let targets = device.makeBuffer(bytes: empty, length: MemoryLayout<ParticleTarget>.stride * count,
                                          options: .storageModeShared) else { return nil }
    self.device = device
    self.queue = queue
    self.tier = tier
    self.count = count
    self.stepPipeline = stepPipeline
    alphaPipeline = alpha
    additivePipeline = additive
    self.states = states
    self.targets = targets
    lastTargets = empty
  }

  /// A new formation: a fresh buffer, so a frame in flight keeps reading the old one.
  func upload(_ new: [ParticleTarget]) {
    precondition(new.count == count, "a formation has one target per mote")
    lastTargets = new
    if let buffer = device.makeBuffer(bytes: new, length: MemoryLayout<ParticleTarget>.stride * count,
                                      options: .storageModeShared) {
      targets = buffer
    }
  }

  /// Steps the field by `dt` and draws it into `drawable`.
  func frame(into drawable: any CAMetalDrawable, uniforms: ParticleUniforms, additive: Bool) {
    guard let commandBuffer = queue.makeCommandBuffer() else { return }
    var u = uniforms
    if let compute = commandBuffer.makeComputeCommandEncoder() {
      compute.setComputePipelineState(stepPipeline)
      compute.setBuffer(targets, offset: 0, index: 0)
      compute.setBuffer(states, offset: 0, index: 1)
      compute.setBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
      compute.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                              threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
      compute.endEncoding()
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    if let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
      render.setRenderPipelineState(additive ? additivePipeline : alphaPipeline)
      render.setVertexBuffer(states, offset: 0, index: 0)
      render.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
      render.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
      render.endEncoding()
    }
    let times = gpuTimes
    commandBuffer.addCompletedHandler { buffer in
      let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
      if milliseconds > 0 { times.record(milliseconds) }
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  /// The motes' live state, for tests (shared storage; call between frames).
  func readStates() -> [ParticleState] {
    let pointer = states.contents().bindMemory(to: ParticleState.self, capacity: count)
    return Array(UnsafeBufferPointer(start: pointer, count: count))
  }

  /// Steps the field without a drawable (tests): compute only, waited for.
  func stepForTest(uniforms: ParticleUniforms) {
    guard let commandBuffer = queue.makeCommandBuffer(), let compute = commandBuffer.makeComputeCommandEncoder() else {
      return
    }
    var u = uniforms
    compute.setComputePipelineState(stepPipeline)
    compute.setBuffer(targets, offset: 0, index: 0)
    compute.setBuffer(states, offset: 0, index: 1)
    compute.setBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
    compute.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    compute.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
}
