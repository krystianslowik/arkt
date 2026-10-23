import AppKit

/// Full-window Space theme behind the sidebar and the card: a diagonal gradient per Space plus a tiled
/// grain layer, crossfaded on the GPU as the pager moves (design section 2). Per frame `setPosition`
/// changes only layer opacities; gradient colors change only when the pair of neighbouring Spaces does.
/// Core Animation for now; a Metal renderer (Arc: N gradient layers + texture overlay) can replace it
/// behind the same `themes` / `setPosition` API. Empty areas drag the window.
@MainActor
public final class ThemeBackgroundView: WindowDragView {
  private let base = CAGradientLayer()
  private let overlay = CAGradientLayer()
  private let grain = CALayer()
  private var lowerIndex = -1
  public private(set) var position: CGFloat = 0

  public var themes: [SpaceThemeInfo] = [] {
    didSet { lowerIndex = -1; setPosition(position) }
  }

  public override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    let none: [String: CAAction] = ["colors": NSNull(), "opacity": NSNull(), "bounds": NSNull(),
                                    "position": NSNull(), "backgroundColor": NSNull()]
    for g in [base, overlay] {
      g.startPoint = CGPoint(x: 0, y: 1)          // top-left to bottom-right (layer y points up)
      g.endPoint = CGPoint(x: 1, y: 0)
      g.actions = none
      layer?.addSublayer(g)
    }
    overlay.opacity = 0
    grain.actions = none
    grain.backgroundColor = GrainTexture.patternColor
    grain.compositingFilter = "softLightBlendMode"   // mid-gray noise adds texture without shifting the tone
    grain.opacity = 0
    layer?.addSublayer(grain)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [base, overlay, grain] { sublayer.frame = bounds }
    CATransaction.commit()
  }

  /// position 1.25 = theme 1 blended 25% toward theme 2.
  public func setPosition(_ newPosition: CGFloat) {
    position = newPosition
    guard !themes.isEmpty else { return }
    let clamped = min(max(newPosition, 0), CGFloat(themes.count - 1))
    let lower = Int(clamped.rounded(.down))
    let upper = min(lower + 1, themes.count - 1)
    let t = clamped - CGFloat(lower)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if lower != lowerIndex {
      base.colors = Self.gradientColors(themes[lower])
      overlay.colors = Self.gradientColors(themes[upper])
      lowerIndex = lower
    }
    overlay.opacity = Float(t)
    let grainFrom = themes[lower].textureOpacity, grainTo = themes[upper].textureOpacity
    grain.opacity = Float(grainFrom + (grainTo - grainFrom) * Double(t))
    CATransaction.commit()
  }

  /// A gradient needs two stops; a single color is drawn flat.
  private static func gradientColors(_ theme: SpaceThemeInfo) -> [CGColor] {
    let colors = theme.baseColors.map(\.cgColor)
    if colors.count == 1 { return colors + colors }
    return colors.isEmpty ? [CGColor.white, CGColor.white] : colors
  }

  var overlayOpacityForTesting: Float { overlay.opacity }
  var grainOpacityForTesting: Float { grain.opacity }
  var baseColorsForTesting: [CGColor] { (base.colors as? [CGColor]) ?? [] }
}

/// Procedural stand-in for Arc's `grain` tile: deterministic monochrome noise, tiled through a pattern color.
@MainActor
enum GrainTexture {
  static let pixels = 256

  static let image: CGImage? = {
    var state: UInt32 = 0x9E37_79B9
    var bytes = [UInt8](repeating: 0, count: pixels * pixels)          // 8-bit gray, opaque
    for i in bytes.indices {
      state ^= state << 13; state ^= state >> 17; state ^= state << 5    // xorshift32
      bytes[i] = UInt8(truncatingIfNeeded: state >> 24)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 8,
                   bytesPerRow: pixels, space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }()

  static let patternColor: CGColor? = {
    guard let image else { return nil }
    let tile = ShellTokens.themeGrainTile
    let nsImage = NSImage(cgImage: image, size: NSSize(width: tile, height: tile))
    return NSColor(patternImage: nsImage).cgColor
  }()
}
