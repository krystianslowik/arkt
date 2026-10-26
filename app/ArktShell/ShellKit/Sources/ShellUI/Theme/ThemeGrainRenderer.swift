import AppKit
import Metal
import QuartzCore

/// Draws the Space theme textures (#120) into `CAMetalLayer` tiles, once per texture and backing scale; replicator
/// layers repeat the tile across the view. The pager, theme crossfades and resizes never draw: they change alphas
/// and replica counts, which the render server composites as a multiply (`gradient * mix(1, texel, alpha)`, Arc's
/// overlay math). So there is no display link and no frame while idle, and a view that cannot be seen defers its
/// draw.
///
/// The shader is compiled at run time from source, like the particle field's (`ParticleShaders`), so the package
/// needs no Metal build step. Nil when Metal or the shader is unavailable: the view then tiles the same
/// synthesized texture through a Core Animation pattern.
@MainActor
final class ThemeGrainRenderer {
  /// The system default device's renderer, built once; nil without Metal.
  static let shared = ThemeGrainRenderer(device: MTLCreateSystemDefaultDevice())

  let device: any MTLDevice
  /// GPU milliseconds per draw. A draw happens on a resize, not per frame; 1 ms is the budget it is held to.
  let gpuTimes = GPUFrameTimes(budgetMilliseconds: 1)
  /// Layer draws so far (tests: no draw per pager frame, none while hidden).
  private(set) var drawCount = 0
  private let queue: any MTLCommandQueue
  private let pipeline: any MTLRenderPipelineState
  private var tiles: [TileKey: any MTLTexture] = [:]

  private struct TileKey: Hashable {
    var texture: ThemeTexture
    var pixels: Int
  }

  init?(device: (any MTLDevice)?) {
    guard let device, let queue = device.makeCommandQueue(),
          let library = try? device.makeLibrary(source: Self.source, options: nil),
          let vertex = library.makeFunction(name: "grainVertex"),
          let fragment = library.makeFunction(name: "grainFragment") else { return nil }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
    self.device = device
    self.queue = queue
    self.pipeline = pipeline
  }

  /// A layer configured for this renderer: opaque gray texels, sRGB-tagged (gray is the same in every RGB space).
  func makeLayer() -> CAMetalLayer {
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.isOpaque = true
    layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    layer.maximumDrawableCount = 2            // static content: one shown, one being drawn
    return layer
  }

  /// Draws `texture` into `layer` at `scale`, tiled from the top left when the layer is larger than one tile.
  /// Returns false when no drawable was available.
  @discardableResult
  func draw(_ texture: ThemeTexture, into layer: CAMetalLayer, scale: CGFloat) -> Bool {
    let signpost = ShellSignposts.signposter.beginInterval("theme.grain.draw")
    defer { ShellSignposts.signposter.endInterval("theme.grain.draw", signpost) }
    let size = CGSize(width: (layer.bounds.width * scale).rounded(), height: (layer.bounds.height * scale).rounded())
    guard size.width > 0, size.height > 0 else { return false }
    layer.contentsScale = scale
    if layer.drawableSize != size { layer.drawableSize = size }
    guard let drawable = layer.nextDrawable(), let tile = tile(texture, scale: scale),
          let commandBuffer = encode(tile, into: drawable.texture) else { return false }
    commandBuffer.present(drawable)
    commandBuffer.commit()
    drawCount += 1
    return true
  }

  /// Renders `texture` offscreen and returns one byte per pixel (tests and GPU timing).
  func renderForTesting(_ texture: ThemeTexture, scale: CGFloat, width: Int, height: Int,
                        readBack: Bool = true) -> [UInt8]? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                              mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    guard let target = device.makeTexture(descriptor: descriptor), let tile = tile(texture, scale: scale),
          let commandBuffer = encode(tile, into: target) else { return nil }
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    guard readBack else { return [] }
    var bgra = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bgra, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    return stride(from: 0, to: bgra.count, by: 4).map { bgra[$0 + 2] }
  }

  // MARK: - Private

  private func encode(_ tile: any MTLTexture, into target: any MTLTexture) -> (any MTLCommandBuffer)? {
    guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentTexture(tile, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    let times = gpuTimes
    commandBuffer.addCompletedHandler { buffer in
      let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
      if milliseconds > 0 { times.record(milliseconds) }
    }
    return commandBuffer
  }

  /// The tile for `scale` as an R8 texture, synthesized and uploaded once per texture and size.
  private func tile(_ texture: ThemeTexture, scale: CGFloat) -> (any MTLTexture)? {
    let key = TileKey(texture: texture, pixels: ThemeTexture.tilePixels(scale: Double(scale)))
    if let cached = tiles[key] { return cached }
    let tile = texture.tile(scale: Double(scale))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: tile.pixels,
                                                              height: tile.pixels, mipmapped: false)
    descriptor.usage = .shaderRead
    guard let uploaded = device.makeTexture(descriptor: descriptor) else { return nil }
    tile.bytes.withUnsafeBytes {
      uploaded.replace(region: MTLRegionMake2D(0, 0, tile.pixels, tile.pixels), mipmapLevel: 0,
                       withBytes: $0.baseAddress!, bytesPerRow: tile.pixels)   // non-empty: pixels >= 100
    }
    tiles[key] = uploaded
    return uploaded
  }

  /// One full-screen triangle; each pixel reads its texel by integer coordinate (no filtering, no seams).
  static let source = #"""
  #include <metal_stdlib>
  using namespace metal;

  struct GrainOut { float4 position [[position]]; };

  vertex GrainOut grainVertex(uint vid [[vertex_id]]) {
    float2 corner = float2((vid << 1) & 2, vid & 2);
    GrainOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
  }

  fragment float4 grainFragment(GrainOut in [[stage_in]], texture2d<float, access::read> tile [[texture(0)]]) {
    uint2 size = uint2(tile.get_width(), tile.get_height());
    uint2 texel = uint2(in.position.xy) % size;
    float factor = tile.read(texel).r;
    return float4(factor, factor, factor, 1.0);
  }
  """#
}
