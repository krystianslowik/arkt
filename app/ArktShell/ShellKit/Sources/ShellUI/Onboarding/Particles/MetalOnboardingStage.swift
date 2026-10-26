import AppKit
import Metal
import QuartzCore
import simd
import os

/// The particle field (onboarding spec, section 7): a `CAMetalLayer` across the window between the browser and the
/// step content, one field of motes for the whole flow. Every step is a shape made of it, built from the live layout
/// off the main thread; the display link runs the kernel at up to 120 Hz and stops while the window is occluded,
/// miniaturized or hidden, under Reduce Motion once a change has settled, and for good after the finish (P9).
///
/// Tiers: 20,480 motes at 120 Hz; 8,192 at 60 Hz in Low Power Mode, at serious or critical thermal state, on a GPU
/// that is not Apple silicon, or after 30 consecutive frames over 2 ms of GPU time.
@MainActor
public final class MetalOnboardingStage: NSObject, OnboardingStage {
  public var view: NSView { particleView }
  public var drawsCounts: Bool { true }

  /// The stage, or nil when Metal or its shaders are unavailable (the flow then uses the Core Animation stage).
  public static func make(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) -> MetalOnboardingStage? {
    guard let device else { return nil }
    let tier = Self.initialTier(device: device)
    guard let renderer = ParticleRenderer(device: device, tier: tier, size: SIMD2(1120, 720), ink: ParticleColors.graphite)
    else { return nil }
    return MetalOnboardingStage(renderer: renderer)
  }

  static func initialTier(device: any MTLDevice, processInfo: ProcessInfo = .processInfo) -> ParticleRenderer.Tier {
    let thermal = processInfo.thermalState
    if processInfo.isLowPowerModeEnabled || thermal == .serious || thermal == .critical { return .fallback }
    return device.supportsFamily(.apple7) ? .full : .fallback
  }

  private let particleView = ParticleView()
  private(set) var renderer: ParticleRenderer
  private var displayLink: CADisplayLink?
  private var formation: OnboardingFormation = .none
  private var appearance = OnboardingAppearance(flavor: .light)
  private var time: Float = 0
  private var lastTimestamp: CFTimeInterval?
  private var epoch: Float = 0
  private var tipStart: Float = 0
  private var opacity: Float = 1
  private var fadeStart: Float?
  private var finishCompletion: (@MainActor () -> Void)?
  private var visible = true
  private var settleDeadline: Float = .greatestFiniteMagnitude
  private var buildGeneration = 0
  private var isReleased = false
  static let log = Logger(subsystem: ShellSignposts.subsystem, category: "particles")

  init(renderer: ParticleRenderer) {
    self.renderer = renderer
    super.init()
    particleView.metalLayer.device = renderer.device
  }

  var tier: ParticleRenderer.Tier { renderer.tier }
  var fieldTime: Float { time }
  var isRunning: Bool { displayLink != nil }

  // MARK: - OnboardingStage

  public func show(_ formation: OnboardingFormation, appearance: OnboardingAppearance, animated: Bool) {
    guard !isReleased else { return }
    let retarget: Bool = if case .counts = formation, case .counts = self.formation { true } else { false }
    if case .tour(3, _) = formation, !isTip3(self.formation) { tipStart = time }
    self.formation = formation
    self.appearance = appearance
    particleView.metalLayer.isOpaque = false
    if !retarget { epoch += 1 }
    build(formation, retarget: retarget)
    settleDeadline = time + 1.6
    start()
  }

  public func finish(onto card: CGRect, appearance: OnboardingAppearance,
                     completion: @escaping @MainActor () -> Void) {
    guard !isReleased else {
      completion()
      return
    }
    buildGeneration += 1                               // a step's build still in flight must not replace the card
    let input = builderInput(reduceMotion: appearance.reduceMotion)
    renderer.upload(ParticleFormationBuilder(input: input).buildCard(card))
    fadeStart = time + 0.9
    finishCompletion = completion
    settleDeadline = .greatestFiniteMagnitude
    guard visible else {
      release()                                        // nothing on screen to fold: done at once
      return
    }
    start()
    // The fold takes about 1.7 s on the field's clock; a window that stops ticking (occluded, ordered out) must not
    // keep the overlay up.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishTimeout) { [weak self] in
      guard let self, !self.isReleased else { return }
      self.release()
    }
  }

  static let finishTimeout: TimeInterval = 2.5

  public func setVisible(_ visible: Bool) {
    self.visible = visible
    if visible { start() } else { stop() }
  }

  // MARK: - Building

  private func isTip3(_ formation: OnboardingFormation) -> Bool {
    if case .tour(3, _) = formation { return true }
    return false
  }

  private func builderInput(reduceMotion: Bool) -> ParticleFormationBuilder.Input {
    let size = particleView.bounds.size
    return ParticleFormationBuilder.Input(
      size: SIMD2(Float(max(size.width, 1)), Float(max(size.height, 1))), count: renderer.count, now: time,
      epoch: epoch, dark: appearance.flavor == .dark, reduceTransparency: appearance.reduceTransparency,
      increaseContrast: appearance.increaseContrast, reduceMotion: reduceMotion, mark: Self.markSamples,
      tipStart: tipStart)
  }

  /// Built off the main thread; a newer build supersedes an older one still running.
  private func build(_ formation: OnboardingFormation, retarget: Bool) {
    buildGeneration += 1
    let generation = buildGeneration
    let input = builderInput(reduceMotion: appearance.reduceMotion)
    let previous = retarget ? renderer.lastTargets : nil
    Task { [weak self] in
      let targets = await Self.makeTargets(input: input, formation: formation, previous: previous)
      guard let self, generation == self.buildGeneration, !self.isReleased else { return }
      self.renderer.upload(targets)
    }
  }

  @concurrent
  private static func makeTargets(input: ParticleFormationBuilder.Input, formation: OnboardingFormation,
                                  previous: [ParticleTarget]?) async -> [ParticleTarget] {
    let signpost = ShellSignposts.signposter.beginInterval("particles.build")
    defer { ShellSignposts.signposter.endInterval("particles.build", signpost) }
    return ParticleFormationBuilder(input: input).build(formation, previous: previous)
  }

  /// The mark's samples at 140 px, cached for the session.
  static let markSamples: [ParticleFormationBuilder.MarkSample] = BrandMarkArtwork.samples(width: 140).map {
    .init(position: SIMD2($0.x, $0.y),
          color: SIMD3(Float($0.red) / 255, Float($0.green) / 255, Float($0.blue) / 255))
  }

  // MARK: - Frames

  private func start() {
    guard displayLink == nil, visible, !isReleased else { return }
    let link = particleView.displayLink(target: self, selector: #selector(step(_:)))
    let rate = renderer.tier.preferredFrameRate
    link.preferredFrameRateRange = CAFrameRateRange(minimum: rate == 120 ? 80 : 30, maximum: rate, preferred: rate)
    link.add(to: .main, forMode: .common)
    displayLink = link
    lastTimestamp = nil
  }

  private func stop() {
    displayLink?.invalidate()
    displayLink = nil
  }

  @objc private func step(_ link: CADisplayLink) {
    let signpost = ShellSignposts.signposter.beginInterval("particles.frame")
    defer { ShellSignposts.signposter.endInterval("particles.frame", signpost) }
    let now = link.timestamp
    let dt = Float(min(1.0 / 30, max(0, now - (lastTimestamp ?? now - 1.0 / 120))))
    lastTimestamp = now
    time += dt
    if let fadeStart, time > fadeStart {
      opacity *= exp(-6 * dt)
      if opacity < 0.01 {
        release()
        return
      }
    }
    if appearance.reduceMotion, finishCompletion == nil, time > settleDeadline {
      stop()                                           // settled: no frames under Reduce Motion
      return
    }
    let layer = particleView.metalLayer
    let scale = particleView.window?.backingScaleFactor ?? 2
    let size = particleView.bounds.size
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    if layer.drawableSize != pixels { layer.drawableSize = pixels }
    layer.contentsScale = scale
    guard pixels.width > 0, pixels.height > 0, let drawable = layer.nextDrawable() else { return }
    let substeps = max(1, Int((dt * 240).rounded(.up)))
    let uniforms = ParticleUniforms(
      time: SIMD4(time, dt, Float(substeps), appearance.reduceMotion ? 1 : 0),
      view: SIMD4(Float(size.width), Float(size.height), Float(scale), opacity),
      config: SIMD4(Float(renderer.count), 3.4, 3.2, 0))
    let additive = appearance.flavor == .dark && !appearance.reduceTransparency
    renderer.frame(into: drawable, uniforms: uniforms, additive: additive)
    // Not during the fold: a new renderer would rebuild the last step's shape instead of the card.
    if renderer.tier == .full, finishCompletion == nil, renderer.gpuTimes.consecutiveOverBudget >= 30 {
      dropToFallbackTier()
    }
  }

  /// After 30 consecutive frames over 2 ms of GPU time: 8,192 motes at 60 Hz from here on.
  private func dropToFallbackTier() {
    let size = particleView.bounds.size
    guard let fallback = ParticleRenderer(device: renderer.device, tier: .fallback,
                                          size: SIMD2(Float(size.width), Float(size.height)),
                                          ink: appearance.flavor == .dark ? ParticleColors.porcelain
                                            : ParticleColors.graphite) else { return }
    Self.log.notice("particle field fallback tier after GPU frames over budget")
    renderer = fallback
    stop()
    build(formation, retarget: false)
    start()
  }

  /// P9 done: the layer stops and its buffers are released.
  private func release() {
    stop()
    isReleased = true
    particleView.metalLayer.device = nil
    particleView.isHidden = true
    let completion = finishCompletion
    finishCompletion = nil
    completion?()
  }
}

/// The view hosting the field's `CAMetalLayer`: never hit, never focused, not an accessibility element.
@MainActor
final class ParticleView: NSView {
  let metalLayer = CAMetalLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true
    metalLayer.isOpaque = false
    metalLayer.backgroundColor = NSColor.clear.cgColor
    wantsLayer = true
  }

  convenience init() { self.init(frame: .zero) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func makeBackingLayer() -> CALayer { metalLayer }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var acceptsFirstResponder: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }
}
