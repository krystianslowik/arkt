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
  /// TODO(measure): Arc's Space theme crossfade.
  public var crossfadeDuration: TimeInterval = 0.28
  /// Read when a theme is replaced. Tests replace it; Reduce Motion snaps.
  public var reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private var crossfadeToken = 0
  private var crossfadeActive = false
  private var suppressSnap = false
  private static let crossfadeKey = "themeCrossfade"

  public var themes: [SpaceThemeInfo] = [] {
    didSet {
      guard !suppressSnap else { return }
      cancelCrossfade()
      lowerIndex = -1
      setPosition(position)
    }
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

  /// Replaces `themes`. `crossfade` fades the settled Space from its old theme to the new one. Anything else (a
  /// reorder, a different count, a swipe in progress, Reduce Motion, a duration of 0) snaps, which is what
  /// `themes`'s setter does.
  public func replaceThemes(_ newThemes: [SpaceThemeInfo], crossfade: Bool) {
    let old = themes
    guard crossfade, let index = settledIndex(), old.indices.contains(index), newThemes.count == old.count,
          newThemes[index] != old[index], crossfadeDuration > 0, !reducesMotion()
    else {
      if themes != newThemes { themes = newThemes }
      return
    }
    cancelCrossfade()
    let token = crossfadeToken
    suppressSnap = true
    themes = newThemes
    suppressSnap = false
    let duration = crossfadeDuration
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    base.colors = Self.gradientColors(old[index])
    overlay.colors = Self.gradientColors(newThemes[index])
    overlay.opacity = 1
    lowerIndex = index
    let grainFrom = Float(old[index].textureOpacity)
    let grainTo = Float(newThemes[index].textureOpacity)
    grain.opacity = grainTo
    CATransaction.commit()
    crossfadeActive = true
    // The settle is tied to the animations themselves (#296): the completion block runs when they finish (or are
    // removed, which `cancelCrossfade` guards against via the token), never at a wall-clock deadline.
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.crossfadeToken == token, self.crossfadeActive else { return }
        self.setPosition(self.position)
      }
    }
    fade(overlay, from: 0, to: 1, duration: duration)
    if grainFrom != grainTo { fade(grain, from: grainFrom, to: grainTo, duration: duration) }
    CATransaction.commit()
  }

  /// position 1.25 = theme 1 blended 25% toward theme 2. An in-flight theme crossfade stops here.
  public func setPosition(_ newPosition: CGFloat) {
    position = newPosition
    cancelCrossfade()
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

  private func settledIndex() -> Int? {
    guard !themes.isEmpty else { return nil }
    let nearest = position.rounded()
    guard abs(position - nearest) < 0.001 else { return nil }
    let index = Int(nearest)
    return themes.indices.contains(index) ? index : nil
  }

  private func cancelCrossfade() {
    guard crossfadeActive else { return }
    crossfadeActive = false
    crossfadeToken &+= 1
    overlay.removeAnimation(forKey: Self.crossfadeKey)
    grain.removeAnimation(forKey: Self.crossfadeKey)
    lowerIndex = -1
  }

  private func fade(_ layer: CALayer, from: Float, to: Float, duration: TimeInterval) {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = false
    layer.add(animation, forKey: Self.crossfadeKey)
  }

  var crossfadeAnimationForTesting: CABasicAnimation? {
    overlay.animation(forKey: Self.crossfadeKey) as? CABasicAnimation
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
