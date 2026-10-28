import AppKit
import Motion

/// Full-window Space theme behind the sidebar and the card: a diagonal gradient per Space plus a tiled texture
/// (grain, sand, denim or tweed), crossfaded on the GPU as the pager moves (design section 2). Per frame
/// `setPosition` changes only layer opacities; gradient colors change only when the pair of neighbouring Spaces does.
///
/// Gradients (#381): stops are expanded in OKLab once per theme (`ThemeGradient.expand`), so the layer's own blend
/// runs between points that are already perceptually spaced. A theme's overlay colors are a second gradient of the
/// same shape, source-over above the base gradients and below the textures; one layer for the lower Space and one for
/// the upper, with the pager and the crossfade changing only their opacities. Their strength is in the colors'
/// alpha (`ThemeContrast.drawn` folds the theme's opacity into it). A Space without overlay colors hides its layer.
///
/// Textures (#120): one layer per texture in use, composited as a multiply at the theme's overlay alpha
/// (`gradient * mix(1, texel, alpha)`). With Metal, `ThemeGrainRenderer` draws one 100 pt tile per
/// texture into a `CAMetalLayer` once per backing scale (deferred while the view cannot be seen) and replicator
/// layers repeat it; without Metal, a Core Animation pattern of the same synthesized tile. Neither draws per frame
/// or per resize. Empty areas drag the window.
@MainActor
public final class ThemeBackgroundView: WindowDragView {
  private let base = CAGradientLayer()
  private let overlay = CAGradientLayer()
  /// The overlay colors of the lower and the upper Space, above `base` and `overlay`.
  private let tintLower = CAGradientLayer()
  private let tintUpper = CAGradientLayer()
  private let grainRenderer: ThemeGrainRenderer?
  /// Texture layers, created when a theme first uses the texture; above the gradients, in creation order (a
  /// multiply commutes).
  private var grainLayers: [ThemeTexture: CALayer] = [:]
  /// The Metal tier's tile per texture, and the backing scale it was last drawn at.
  private var grainTiles: [ThemeTexture: CAMetalLayer] = [:]
  private var grainDrawnScale: [ThemeTexture: CGFloat] = [:]
  private var occlusionObserver: (any NSObjectProtocol)?
  private var lowerIndex = -1
  public private(set) var position: CGFloat = 0
  /// TODO(measure): Arc's Space theme crossfade.
  public var crossfadeDuration: TimeInterval = 0.28
  /// While set, a theme crossfade runs on this spring instead of the 0.28 s ease: the theme creator sets `firm` while
  /// it is open, so adding a colour or picking a preset re-tints on the design's curve (#410).
  public var crossfadeSpring: SpringParameters?
  /// Read when a theme is replaced. Tests replace it; Reduce Motion snaps.
  public var reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Whether the window can be seen (not occluded, not miniaturized); a texture draw waits until it can. Tests
  /// replace it.
  var windowIsVisible: @MainActor (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) && !$0.isMiniaturized }
  private var crossfadeToken = 0
  private var crossfadeActive = false
  private var suppressSnap = false
  private static let crossfadeKey = "themeCrossfade"

  /// Another theme background that shows the same Space theme (the hidden sidebar's overlay backdrop, #102). It
  /// follows `themes` and `setPosition` and snaps where this one crossfades.
  weak var mirror: ThemeBackgroundView? {
    didSet {
      guard let mirror else { return }
      mirror.themes = themes
      mirror.setPosition(position)
    }
  }

  public var themes: [SpaceThemeInfo] = [] {
    didSet {
      if let mirror, mirror.themes != themes { mirror.themes = themes }
      ensureGrainLayers()
      guard !suppressSnap else { return }
      cancelCrossfade()
      lowerIndex = -1
      setPosition(position)
    }
  }

  public convenience override init(frame: NSRect) {
    self.init(frame: frame, grainRenderer: ThemeGrainRenderer.shared)
  }

  /// `grainRenderer` nil: the Core Animation texture tier.
  init(frame: NSRect, grainRenderer: ThemeGrainRenderer?) {
    self.grainRenderer = grainRenderer
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true                     // the last row and column of tiles overhang
    let none = Self.noActions
    for g in [base, overlay, tintLower, tintUpper] {
      g.startPoint = CGPoint(x: 0, y: 1)          // top-left to bottom-right (layer y points up)
      g.endPoint = CGPoint(x: 1, y: 0)
      g.actions = none
      layer?.addSublayer(g)
    }
    overlay.opacity = 0
    for tint in [tintLower, tintUpper] {
      tint.opacity = 0
      tint.isHidden = true
    }
  }

  private static let noActions: [String: CAAction] = ["colors": NSNull(), "opacity": NSNull(), "bounds": NSNull(),
                                                      "position": NSNull(), "backgroundColor": NSNull(),
                                                      "hidden": NSNull(), "contents": NSNull()]

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [base, overlay, tintLower, tintUpper] { sublayer.frame = bounds }
    for layer in grainLayers.values { layoutGrain(layer) }
    CATransaction.commit()
    drawGrainIfNeeded()
  }

  public override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    occlusionObserver = nil
  }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    occlusionObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.drawGrainIfNeeded() }
    }
    drawGrainIfNeeded()
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    drawGrainIfNeeded()
  }

  public override func viewDidUnhide() {
    super.viewDidUnhide()
    drawGrainIfNeeded()
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
    let tintsOut = Self.setTint(tintLower, old[index]), tintsIn = Self.setTint(tintUpper, newThemes[index])
    tintLower.opacity = 1
    tintUpper.opacity = 1
    lowerIndex = index
    let grainFrom = Self.grainAlphas(old[index], old[index], t: 0)
    let grainTo = Self.grainAlphas(newThemes[index], newThemes[index], t: 0)
    for (texture, layer) in grainLayers {
      let from = grainFrom[texture] ?? 0, to = grainTo[texture] ?? 0
      layer.opacity = to
      layer.isHidden = from == 0 && to == 0
    }
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
    if tintsOut { fade(tintLower, from: 1, to: 0, duration: duration) }
    if tintsIn { fade(tintUpper, from: 0, to: 1, duration: duration) }
    for (texture, layer) in grainLayers {
      let from = grainFrom[texture] ?? 0, to = grainTo[texture] ?? 0
      if from != to { fade(layer, from: from, to: to, duration: duration) }
    }
    CATransaction.commit()
  }

  /// Draws `theme` for the Space at `index` at once: no crossfade and no implicit animation. The theme creator's live
  /// re-tint calls it on every drag event; Core Animation coalesces the changes to the display refresh.
  public func previewTheme(_ theme: SpaceThemeInfo, at index: Int) {
    guard themes.indices.contains(index), themes[index] != theme else { return }
    themes[index] = theme
  }

  /// position 1.25 = theme 1 blended 25% toward theme 2. An in-flight theme crossfade stops here.
  public func setPosition(_ newPosition: CGFloat) {
    mirror?.setPosition(newPosition)
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
      Self.setTint(tintLower, themes[lower])
      Self.setTint(tintUpper, themes[upper])
      lowerIndex = lower
    }
    overlay.opacity = Float(t)
    tintLower.opacity = Float(1 - t)
    tintUpper.opacity = Float(t)
    let alphas = Self.grainAlphas(themes[lower], themes[upper], t: Double(t))
    for (texture, layer) in grainLayers {
      let alpha = alphas[texture] ?? 0
      layer.opacity = alpha
      layer.isHidden = alpha == 0                      // nothing to composite
    }
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
    for layer in [overlay, tintLower, tintUpper] { layer.removeAnimation(forKey: Self.crossfadeKey) }
    for layer in grainLayers.values { layer.removeAnimation(forKey: Self.crossfadeKey) }
    lowerIndex = -1
  }

  private func fade(_ layer: CALayer, from: Float, to: Float, duration: TimeInterval) {
    let animation: CABasicAnimation
    if let crossfadeSpring {
      animation = SpringAnimationFactory.make(keyPath: "opacity", from: Double(from), to: Double(to),
                                              parameters: crossfadeSpring)
    } else {
      animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = from
      animation.toValue = to
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = false
    layer.add(animation, forKey: Self.crossfadeKey)
  }

  var crossfadeAnimationForTesting: CABasicAnimation? {
    overlay.animation(forKey: Self.crossfadeKey) as? CABasicAnimation
  }

  /// A gradient needs two stops; a single color is drawn flat. Several are expanded in OKLab (`ThemeGradient`).
  private static func gradientColors(_ theme: SpaceThemeInfo) -> [CGColor] {
    let colors = ThemeGradient.expand(theme.baseColors).map(\.cgColor)
    if colors.count == 1 { return colors + colors }
    return colors.isEmpty ? [CGColor.white, CGColor.white] : colors
  }

  /// Sets `layer` to `theme`'s overlay colors and hides it when there are none; whether it shows anything.
  @discardableResult
  private static func setTint(_ layer: CAGradientLayer, _ theme: SpaceThemeInfo) -> Bool {
    let colors = ThemeGradient.expand(theme.overlayColors).map(\.cgColor)
    layer.isHidden = colors.isEmpty
    layer.colors = colors.count == 1 ? colors + colors : colors
    return !colors.isEmpty
  }

  // MARK: - Textures

  /// Each texture's overlay alpha at `t` between two themes (a texture both use adds up).
  private static func grainAlphas(_ lower: SpaceThemeInfo, _ upper: SpaceThemeInfo, t: Double) -> [ThemeTexture: Float] {
    var alphas: [ThemeTexture: Float] = [:]
    if let texture = lower.textureKind { alphas[texture, default: 0] += Float(lower.textureOpacity * (1 - t)) }
    if let texture = upper.textureKind { alphas[texture, default: 0] += Float(upper.textureOpacity * t) }
    return alphas
  }

  /// A layer for every texture the themes use, drawn (Metal) as soon as the view can be seen.
  private func ensureGrainLayers() {
    for texture in Set(themes.compactMap(\.textureKind)).sorted(by: { $0.rawValue < $1.rawValue })
    where grainLayers[texture] == nil {
      let layer: CALayer
      if let grainRenderer {
        let tile = grainRenderer.makeLayer()
        tile.actions = Self.noActions
        let row = CAReplicatorLayer()            // the tile repeated across
        row.actions = Self.noActions
        row.addSublayer(tile)
        let grid = CAReplicatorLayer()           // the row repeated down
        grid.addSublayer(row)
        grainTiles[texture] = tile
        layer = grid
      } else {
        layer = CALayer()
        layer.backgroundColor = ThemeGrainPattern.color(texture)
      }
      layer.actions = Self.noActions
      layer.compositingFilter = "multiplyBlendMode"   // gradient * mix(1, texel, opacity)
      layer.opacity = 0
      layer.isHidden = true
      self.layer?.addSublayer(layer)
      grainLayers[texture] = layer
      layoutGrain(layer)
    }
    drawGrainIfNeeded()
  }

  /// The texture layer fills the view. On the Metal tier it is a grid of one `tilePoints` tile anchored at the top
  /// left: a resize changes only the replica counts, so it never draws and the tiles never shift under the pointer.
  private func layoutGrain(_ layer: CALayer) {
    layer.frame = bounds
    guard let grid = layer as? CAReplicatorLayer, let row = grid.sublayers?.first as? CAReplicatorLayer,
          let tile = row.sublayers?.first else { return }
    let edge = CGFloat(ThemeTexture.tilePoints)
    row.frame = bounds
    tile.frame = CGRect(x: 0, y: isFlipped ? 0 : bounds.height - edge, width: edge, height: edge)
    row.instanceCount = max(1, Int((bounds.width / edge).rounded(.up)))
    row.instanceTransform = CATransform3DMakeTranslation(edge, 0, 0)
    grid.instanceCount = max(1, Int((bounds.height / edge).rounded(.up)))
    grid.instanceTransform = CATransform3DMakeTranslation(0, isFlipped ? edge : -edge, 0)
  }

  /// Draws each Metal tile once per backing scale, only while the view can be seen: in a window that is not
  /// occluded or miniaturized, not hidden. A skipped draw happens on the next unhide, occlusion change or layout.
  private func drawGrainIfNeeded() {
    guard let grainRenderer, let window, !isHiddenOrHasHiddenAncestor, windowIsVisible(window) else { return }
    let scale = window.backingScaleFactor
    let used = Set(themes.compactMap(\.textureKind))
    for (texture, tile) in grainTiles where used.contains(texture) && grainDrawnScale[texture] != scale {
      let drawn = grainRenderer.draw(texture, into: tile, scale: scale) { [weak self] in self?.drawGrainIfNeeded() }
      if drawn { grainDrawnScale[texture] = scale }
    }
  }

  var overlayOpacityForTesting: Float { overlay.opacity }
  /// The overlay-color layers of the lower and the upper Space.
  var overlayColorLayersForTesting: [CAGradientLayer] { [tintLower, tintUpper] }
  /// The texture layers' alphas, summed.
  var grainOpacityForTesting: Float { grainLayers.values.reduce(0) { $0 + $1.opacity } }
  func grainOpacityForTesting(_ texture: ThemeTexture) -> Float { grainLayers[texture]?.opacity ?? 0 }
  func grainLayerForTesting(_ texture: ThemeTexture) -> CALayer? { grainLayers[texture] }
  func grainTileForTesting(_ texture: ThemeTexture) -> CAMetalLayer? { grainTiles[texture] }
  func grainFadeForTesting(_ texture: ThemeTexture) -> CABasicAnimation? {
    grainLayers[texture]?.animation(forKey: Self.crossfadeKey) as? CABasicAnimation
  }
  var baseColorsForTesting: [CGColor] { (base.colors as? [CGColor]) ?? [] }
}

/// The Core Animation texture tier: the synthesized 2x tile as a pattern color, 100 pt per repeat.
@MainActor
enum ThemeGrainPattern {
  private static var colors: [ThemeTexture: CGColor] = [:]

  static func color(_ texture: ThemeTexture) -> CGColor? {
    if let cached = colors[texture] { return cached }
    let tile = texture.tile(scale: 2)
    guard let provider = CGDataProvider(data: Data(tile.bytes) as CFData),
          let image = CGImage(width: tile.pixels, height: tile.pixels, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: tile.pixels, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                              decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
    let points = CGFloat(ThemeTexture.tilePoints)
    let color = NSColor(patternImage: NSImage(cgImage: image, size: NSSize(width: points, height: points))).cgColor
    colors[texture] = color
    return color
  }
}
