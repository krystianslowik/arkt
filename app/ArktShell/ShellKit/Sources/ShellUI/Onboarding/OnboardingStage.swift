import AppKit

/// What the stage shows for a step (onboarding spec, section 7.2), built from the live layout when the step appears,
/// at the views' resting positions. Rects are in the stage view's (flipped) coordinates.
public enum OnboardingFormation: Equatable, Sendable {
  case none
  /// Welcome: the mark in its 220 x 200 stage.
  case welcome(mark: CGRect)
  /// Import: the four counts.
  case counts(OnboardingCountFormation)
  /// Make it yours: the field outlines the preview and rises in the margins in the theme's colours. `origin` is the
  /// pressed swatch's centre for the re-tint (P6), nil when the step appears.
  case theme(preview: CGRect, theme: SpaceThemeInfo, origin: CGPoint?)
  /// Default browser: the mark at 150 pt with streams from the window's left edge.
  case defaultBrowser(mark: CGRect)
  /// Extensions: the mark at 104 pt inside three tilted rings.
  case extensions(mark: CGRect, rings: CGRect)
  /// A tip's shape in its 560 x 236 stage.
  case tour(tip: Int, stage: CGRect)
  /// Done: the mark at 168 pt with a slow mustard orbit.
  case done(mark: CGRect)
}

/// The Import step's numbers as the stage draws them: each count's text and glyph box at its laid-out size.
public struct OnboardingCountFormation: Equatable, Sendable {
  public struct Number: Equatable, Sendable {
    public var kind: OnboardingCounts.Kind
    public var text: String
    public var frame: CGRect
    public var fontSize: CGFloat
  }

  public enum State: Equatable, Sendable {
    case counting, ready
    /// Each finished category turns mustard (P5).
    case importing(landed: Set<OnboardingCounts.Kind>)
    case imported
    /// The numbers scatter into a loose cloud over the stage.
    case failed
  }

  public var numbers: [Number]
  public var state: State
}

/// The particle stage behind the step content (section 7): one view across the window, between the browser and the
/// step content. It never takes events, focus or accessibility, and nothing it shows exists only there: every fact
/// is also text. The Metal particle field and the Core Animation fallback both conform.
@MainActor
public protocol OnboardingStage: AnyObject {
  var view: NSView { get }
  /// True when the stage draws the counts itself (particles); the step then draws them clear, as text for
  /// VoiceOver only. False: the step draws the counts as Avenir Next text.
  var drawsCounts: Bool { get }
  /// Changes to `formation` (P3), springing from where everything is (or in place under Reduce Motion).
  func show(_ formation: OnboardingFormation, appearance: OnboardingAppearance, animated: Bool)
  /// Finish (P9): the current formation folds onto the content card's edge and fades; `completion` runs once the
  /// stage has nothing left to draw, and its resources are released.
  func finish(onto card: CGRect, appearance: OnboardingAppearance, completion: @escaping @MainActor () -> Void)
  /// False while the window is occluded, miniaturized or hidden: no frames.
  func setVisible(_ visible: Bool)
}

/// The stage without particles (section 7.4, "No particle layer"): the raster mark on Welcome, Default browser,
/// Extensions and Done, the counts as text in the step, and drawn key caps and demos in the tour. Shapes change with
/// a 200 ms crossfade. The Metal stage replaces it when the device can run it.
@MainActor
public final class CoreAnimationOnboardingStage: NSObject, OnboardingStage {
  public let view: NSView = StageView()
  public var drawsCounts: Bool { false }
  private var current: CALayer?
  private var formation: OnboardingFormation = .none

  public override init() {
    super.init()
    view.wantsLayer = true
    view.layer?.masksToBounds = false
  }

  public func show(_ formation: OnboardingFormation, appearance: OnboardingAppearance, animated: Bool) {
    if case .theme = formation, case .theme = self.formation {
      self.formation = formation
      return                                   // the preview itself shows the re-tint
    }
    self.formation = formation
    let next = Self.layer(for: formation, appearance: appearance, scale: view.window?.backingScaleFactor ?? 2)
    if let old = current {
      if animated {
        OnboardingMotion.conceal(old, duration: 0.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak old] in old?.removeFromSuperlayer() }
      } else {
        old.removeFromSuperlayer()
      }
    }
    current = next
    guard let next else { return }
    view.layer?.addSublayer(next)
    if animated {
      OnboardingMotion.set { next.opacity = 0 }
      OnboardingMotion.animate(next, "opacity", to: Float(1), duration: appearance.reduceMotion ? 0.2 : 0.5,
                               delay: appearance.reduceMotion ? 0 : 0.12)
    }
  }

  public func finish(onto card: CGRect, appearance: OnboardingAppearance,
                     completion: @escaping @MainActor () -> Void) {
    if let current { OnboardingMotion.conceal(current, duration: 0.16) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.current?.removeFromSuperlayer()
      self?.current = nil
      completion()
    }
  }

  public func setVisible(_ visible: Bool) {}

  // MARK: Shapes

  static func layer(for formation: OnboardingFormation, appearance: OnboardingAppearance,
                    scale: CGFloat) -> CALayer? {
    switch formation {
    case .none, .counts, .theme: return nil
    case .welcome(let rect), .defaultBrowser(let rect), .done(let rect): return markLayer(in: rect)
    case .extensions(let mark, _): return markLayer(in: mark)
    case .tour(let tip, let stage): return TourDrawing.layer(tip: tip, in: stage, appearance: appearance, scale: scale)
    }
  }

  /// The raster mark, fitted into `rect` and centred.
  static func markLayer(in rect: CGRect) -> CALayer? {
    guard let image = BrandMarkArtwork.image else { return nil }
    let ratio = BrandMarkArtwork.aspectRatio
    var size = CGSize(width: rect.height * ratio, height: rect.height)
    if size.width > rect.width { size = CGSize(width: rect.width, height: rect.width / ratio) }
    let layer = CALayer()
    layer.contents = image
    layer.contentsGravity = .resizeAspect
    layer.frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width,
                         height: size.height)
    return layer
  }
}

/// The stage's view: flipped, never hit, never focused, not an accessibility element.
@MainActor
final class StageView: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var acceptsFirstResponder: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }
}

// MARK: - Tour drawings

/// The tour's shapes without particles: key caps (72 pt, radius 16, a heavier bottom edge; the Command glyph from the
/// system font, letters from Avenir Next), an archive tray, Space rooms, and a window with a split page or Favorites.
/// Ink is `brandTextPrimary`, accents are mustard fills.
@MainActor
enum TourDrawing {
  static let capSize: CGFloat = 72

  static func layer(tip: Int, in stage: CGRect, appearance: OnboardingAppearance, scale: CGFloat) -> CALayer {
    let root = CALayer()
    root.frame = stage
    let ink = appearance.textPrimary
    let mustard = appearance.accent
    switch tip {
    case 1:
      let gap: CGFloat = 8, pairGap: CGFloat = 76
      let total = capSize * 4 + gap * 2 + pairGap
      var x = (stage.width - total) / 2
      for (index, glyph) in ["\u{2318}", "T", "\u{2318}", "L"].enumerated() {
        root.addSublayer(keyCap(glyph, at: CGPoint(x: x, y: (stage.height - capSize) / 2), ink: ink,
                                surface: appearance.surface, scale: scale))
        x += capSize + (index == 1 ? pairGap : gap)
      }
      root.addSublayer(sparks(in: CGRect(x: (stage.width - pairGap) / 2, y: stage.height / 2 - 30, width: pairGap,
                                         height: 60), color: mustard, count: 14, seed: 1))
    case 2:
      let y = (stage.height - capSize) / 2
      let left = stage.width / 2 - 200
      root.addSublayer(keyCap("\u{2318}", at: CGPoint(x: left, y: y), ink: ink, surface: appearance.surface,
                              scale: scale))
      root.addSublayer(keyCap("W", at: CGPoint(x: left + capSize + 8, y: y), ink: ink, surface: appearance.surface,
                              scale: scale))
      let trayRect = CGRect(x: stage.width / 2 + 90, y: stage.height / 2 - 34, width: 110, height: 68)
      root.addSublayer(tray(in: trayRect, ink: ink))
      let streamStart = left + capSize * 2 + 24
      root.addSublayer(stream(from: CGPoint(x: streamStart, y: stage.height / 2),
                              to: CGPoint(x: trayRect.minX - 10, y: trayRect.midY), color: mustard))
    case 3:
      let families = [SpaceThemeCatalog.families[0], SpaceThemeCatalog.families[1], SpaceThemeCatalog.families[4]]
      let room = CGSize(width: 150, height: 104)
      let gap: CGFloat = 26
      let total = room.width * 3 + gap * 2
      for (index, family) in families.enumerated() {
        let frame = CGRect(x: (stage.width - total) / 2 + CGFloat(index) * (room.width + gap),
                           y: (stage.height - room.height) / 2 + (index == 1 ? -8 : 6), width: room.width,
                           height: room.height)
        let roomLayer = miniWindow(in: frame, ink: ink, fill: family.light, panes: 1, mustardPane: false,
                                   mustardFavorite: nil)
        roomLayer.opacity = index == 1 ? 1 : 0.55
        root.addSublayer(roomLayer)
      }
    case 4:
      let frame = CGRect(x: (stage.width - 300) / 2, y: (stage.height - 170) / 2, width: 300, height: 170)
      root.addSublayer(miniWindow(in: frame, ink: ink, fill: nil, panes: 2, mustardPane: true, mustardFavorite: nil))
      root.addSublayer(stream(from: CGPoint(x: frame.minX + 40, y: frame.minY + 86),
                              to: CGPoint(x: frame.midX + 70, y: frame.midY), color: mustard))
    default:
      let frame = CGRect(x: (stage.width - 300) / 2, y: (stage.height - 170) / 2, width: 300, height: 170)
      root.addSublayer(miniWindow(in: frame, ink: ink, fill: nil, panes: 1, mustardPane: false, mustardFavorite: 2))
      root.addSublayer(stream(from: CGPoint(x: frame.minX + 40, y: frame.minY + 110),
                              to: CGPoint(x: frame.minX + 70, y: frame.minY + 40), color: mustard))
    }
    return root
  }

  static func keyCap(_ glyph: String, at origin: CGPoint, ink: NSColor, surface: NSColor, scale: CGFloat) -> CALayer {
    let cap = CALayer()
    cap.frame = CGRect(origin: origin, size: CGSize(width: capSize, height: capSize))
    cap.cornerRadius = 16
    cap.borderWidth = 1.5
    cap.borderColor = ink.withAlphaComponent(0.85).cgColor
    cap.backgroundColor = surface.cgColor
    let edge = CALayer()
    edge.frame = CGRect(x: 6, y: capSize - 3, width: capSize - 12, height: 4)
    edge.cornerRadius = 2
    edge.backgroundColor = ink.withAlphaComponent(0.85).cgColor
    cap.addSublayer(edge)
    let font: NSFont = glyph == "\u{2318}" ? .systemFont(ofSize: 30, weight: .semibold)
      : BrandType.font(.demiBold, size: 32)
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: ink])
    let size = BrandTextRenderer.measure(text, maxWidth: 200)
    let label = CALayer()
    BrandTextRenderer.apply(BrandTextRenderer.image(text, size: size, halo: []), to: label, glyphSize: size,
                            halo: false, scale: scale)
    label.position = CGPoint(x: ((capSize - size.width) / 2).rounded(), y: ((capSize - size.height) / 2 - 2).rounded())
    cap.addSublayer(label)
    return cap
  }

  static func tray(in rect: CGRect, ink: NSColor) -> CALayer {
    let tray = CAShapeLayer()
    let path = CGMutablePath()
    path.addRoundedRect(in: rect.insetBy(dx: 0, dy: 10), cornerWidth: 10, cornerHeight: 10)
    path.move(to: CGPoint(x: rect.minX + 30, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX - 30, y: rect.midY))
    tray.path = path
    tray.fillColor = nil
    tray.strokeColor = ink.withAlphaComponent(0.85).cgColor
    tray.lineWidth = 1.5
    tray.lineCap = .round
    return tray
  }

  /// A row of mustard dots from `start` to `end`, larger near the end: a stream frozen at rest.
  static func stream(from start: CGPoint, to end: CGPoint, color: NSColor) -> CALayer {
    let layer = CALayer()
    let count = 12
    for i in 0..<count {
      let t = CGFloat(i) / CGFloat(count - 1)
      let dot = CALayer()
      let size = 2.5 + 3 * t
      let x = start.x + (end.x - start.x) * t
      let y = start.y + (end.y - start.y) * t + sin(t * .pi) * -10
      dot.frame = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
      dot.cornerRadius = size / 2
      dot.backgroundColor = color.withAlphaComponent(0.45 + 0.55 * t).cgColor
      layer.addSublayer(dot)
    }
    return layer
  }

  static func sparks(in rect: CGRect, color: NSColor, count: Int, seed: UInt64) -> CALayer {
    let layer = CALayer()
    var state = seed &* 0x9E37_79B9_7F4A_7C15
    func next() -> CGFloat {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
    for _ in 0..<count {
      let dot = CALayer()
      let size = 1.5 + next() * 2
      dot.frame = CGRect(x: rect.minX + next() * rect.width, y: rect.minY + next() * rect.height, width: size,
                         height: size)
      dot.cornerRadius = size / 2
      dot.backgroundColor = color.withAlphaComponent(0.4 + next() * 0.5).cgColor
      layer.addSublayer(dot)
    }
    return layer
  }

  /// A small browser window: outline, sidebar strip with Favorites and rows, a page in one or two panes.
  static func miniWindow(in frame: CGRect, ink: NSColor, fill: SpaceThemeInfo?, panes: Int, mustardPane: Bool,
                         mustardFavorite: Int?) -> CALayer {
    let window = CALayer()
    window.frame = frame
    window.cornerRadius = 12
    window.borderWidth = 1.5
    window.borderColor = ink.withAlphaComponent(0.85).cgColor
    if let fill {
      let gradient = CAGradientLayer()
      gradient.frame = CGRect(origin: .zero, size: frame.size)
      gradient.cornerRadius = 12
      gradient.colors = fill.baseColors.map(\.cgColor)
      gradient.startPoint = .zero
      gradient.endPoint = CGPoint(x: 1, y: 1)
      window.addSublayer(gradient)
    }
    let sidebarWidth = frame.width * 0.3
    let tile = (sidebarWidth - 16 - 8) / 3
    for i in 0..<3 {
      let favorite = CALayer()
      favorite.frame = CGRect(x: 8 + CGFloat(i) * (tile + 4), y: 14, width: tile, height: tile * 0.7)
      favorite.cornerRadius = 3
      favorite.borderWidth = 1
      favorite.borderColor = ink.withAlphaComponent(0.6).cgColor
      if mustardFavorite == i { favorite.backgroundColor = BrandTokens.Palette.mustard.cgColor; favorite.borderWidth = 0 }
      window.addSublayer(favorite)
    }
    for i in 0..<4 {
      let row = CALayer()
      row.frame = CGRect(x: 8, y: 14 + tile * 0.7 + 12 + CGFloat(i) * 12, width: sidebarWidth - 16, height: 6)
      row.cornerRadius = 3
      row.backgroundColor = ink.withAlphaComponent(i == 0 ? 0.5 : 0.22).cgColor
      window.addSublayer(row)
    }
    let pageRect = CGRect(x: sidebarWidth, y: 8, width: frame.width - sidebarWidth - 8, height: frame.height - 16)
    let paneWidth = (pageRect.width - CGFloat(panes - 1) * 6) / CGFloat(panes)
    for i in 0..<panes {
      let pane = CALayer()
      pane.frame = CGRect(x: pageRect.minX + CGFloat(i) * (paneWidth + 6), y: pageRect.minY, width: paneWidth,
                          height: pageRect.height)
      pane.cornerRadius = 6
      pane.borderWidth = 1.5
      pane.borderColor = ink.withAlphaComponent(0.7).cgColor
      if fill != nil { pane.backgroundColor = NSColor.white.cgColor }
      if mustardPane, i == panes - 1 {
        pane.backgroundColor = BrandTokens.Palette.mustard.withAlpha(0.85).cgColor
        pane.borderWidth = 0
      }
      window.addSublayer(pane)
    }
    return window
  }
}

private extension RGBA {
  func withAlpha(_ alpha: Double) -> RGBA {
    var copy = self
    copy.alpha = alpha
    return copy
  }
}
