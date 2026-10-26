import AppKit

// MARK: - Motion

/// The first run's motion vocabulary (section 8): the strong ease-out for everything that enters, the drawer curve
/// for the segmented thumb, and helpers that start from the presented value so an interrupted change retargets
/// instead of jumping. Nothing uses ease-in.
@MainActor
enum OnboardingMotion {
  static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
  static let drawer = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)

  /// Animates `keyPath` of `layer` to `value` from what is on screen now, after `delay` seconds.
  static func animate(_ layer: CALayer, _ keyPath: String, to value: Any, duration: CFTimeInterval,
                      delay: CFTimeInterval = 0, timing: CAMediaTimingFunction = easeOut) {
    let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
    layer.removeAnimation(forKey: keyPath)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.setValue(value, forKeyPath: keyPath)
    CATransaction.commit()
    guard duration > 0 else { return }
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = value
    animation.duration = duration
    animation.timingFunction = timing
    if delay > 0 {
      animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
      animation.fillMode = .backwards
    }
    layer.add(animation, forKey: keyPath)
  }

  /// Sets values without implicit animations.
  static func set(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }

  /// Incoming element: opacity 0 to 1 and a rise of `rise` points, 700 ms ease-out, after `delay` (M1, M2). Under
  /// Reduce Motion a 200 ms crossfade with no rise.
  static func reveal(_ layer: CALayer, rise: CGFloat, delay: CFTimeInterval, reduceMotion: Bool) {
    if reduceMotion {
      set { layer.opacity = 0; layer.transform = CATransform3DIdentity }
      animate(layer, "opacity", to: Float(1), duration: 0.2)
      return
    }
    set {
      layer.opacity = 0
      layer.transform = CATransform3DMakeTranslation(0, rise, 0)
    }
    animate(layer, "opacity", to: Float(1), duration: 0.7, delay: delay)
    animate(layer, "transform", to: NSValue(caTransform3D: CATransform3DIdentity), duration: 0.7, delay: delay)
  }

  /// Outgoing element: opacity to 0 from where it is, `duration` ease-out.
  static func conceal(_ layer: CALayer, duration: CFTimeInterval) {
    animate(layer, "opacity", to: Float(0), duration: duration)
  }
}

// MARK: - Text rendering

/// Draws brand text into images once per layout: the word layers of a title and every label of the first run. The
/// halo (section 3) is drawn into the image, so it is static and never animated.
@MainActor
enum BrandTextRenderer {
  /// Room around the glyphs for the widest halo shadow, and for glyphs that reach past a display line's fixed
  /// line height (counts at 0.86, titles at 0.92).
  static let haloPadding: CGFloat = 36

  /// The padding of an image whose glyph box is `size`.
  static func padding(for size: NSSize) -> CGFloat { max(haloPadding, ceil(size.height * 0.4)) }

  /// The text's size when wrapped at `maxWidth`.
  static func measure(_ text: NSAttributedString, maxWidth: CGFloat) -> NSSize {
    let rect = text.boundingRect(with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    return NSSize(width: ceil(rect.width), height: ceil(rect.height))
  }

  /// An image of `text` laid out in `size`, padded by `padding(for:)` on every side.
  static func image(_ text: NSAttributedString, size: NSSize, halo: [NSShadow]) -> NSImage {
    let pad = padding(for: size)
    let full = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
    var shift: CGFloat = 0
    if text.length > 0, let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
       let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
       paragraph.maximumLineHeight > 0 {
      shift = BrandType.cssShift(font: font, lineHeight: paragraph.maximumLineHeight)
    }
    return NSImage(size: full, flipped: true) { _ in
      let rect = NSRect(x: pad, y: pad + shift, width: size.width, height: size.height)
      for shadow in halo {
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
      }
      text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
      return true
    }
  }

  /// Puts `image` into `layer` at the window's scale. The anchor point is the glyph box's top-left corner, so the
  /// layer's `position` places the glyphs, whatever the padding.
  static func apply(_ image: NSImage, to layer: CALayer, glyphSize: NSSize, halo: Bool, scale: CGFloat) {
    let pad = padding(for: glyphSize)
    let full = CGSize(width: glyphSize.width + pad * 2, height: glyphSize.height + pad * 2)
    layer.contentsScale = scale
    layer.contents = image.layerContents(forContentsScale: scale)
    layer.bounds = CGRect(origin: .zero, size: full)
    layer.anchorPoint = CGPoint(x: pad / full.width, y: pad / full.height)
  }
}

// MARK: - Label

/// A line or paragraph of brand text (eyebrow, lede, note, labels, the footer's progress): rendered once into a
/// layer, so it can fade and rise without re-layout. Reads to VoiceOver as static text.
@MainActor
final class BrandLabel: NSView {
  var text: String { didSet { if text != oldValue { invalidate() } } }
  var role: BrandType.Role { didSet { if role != oldValue { invalidate() } } }
  var color: NSColor { didSet { if color != oldValue { invalidate() } } }
  var compact = false { didSet { if compact != oldValue { invalidate() } } }
  var alignment: NSTextAlignment = .center { didSet { if alignment != oldValue { invalidate() } } }
  /// Wrapping width; the label is as wide as its longest line.
  var maxWidth: CGFloat = 10_000 { didSet { if maxWidth != oldValue { invalidate() } } }
  /// The halo shadows; empty draws no halo.
  var halo: [NSShadow] = [] { didSet { invalidate() } }
  /// Characters drawn in `emphasisColor` and DemiBold (the keys in the tour's ledes).
  var emphasis: [String] = [] { didSet { if emphasis != oldValue { invalidate() } } }
  var emphasisColor: NSColor = .labelColor { didSet { invalidate() } }

  private let textLayer = CALayer()
  private var cachedSize: NSSize?

  init(text: String = "", role: BrandType.Role, color: NSColor) {
    self.text = text
    self.role = role
    self.color = color
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.addSublayer(textLayer)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  var attributedText: NSAttributedString {
    let result = NSMutableAttributedString(
      attributedString: BrandType.attributed(text, role: role, color: color, compact: compact, alignment: alignment))
    let style = role.style(compact: compact)
    for key in emphasis {
      let range = (result.string as NSString).range(of: style.uppercase ? key.uppercased() : key)
      guard range.location != NSNotFound else { continue }
      result.addAttributes([.font: BrandType.font(.demiBold, size: style.size), .foregroundColor: emphasisColor],
                           range: range)
    }
    return result
  }

  /// The size the text needs at `maxWidth`.
  var textSize: NSSize {
    if let cachedSize { return cachedSize }
    let size = text.isEmpty ? .zero : BrandTextRenderer.measure(attributedText, maxWidth: maxWidth)
    cachedSize = size
    return size
  }

  override var intrinsicContentSize: NSSize { textSize }

  private func invalidate() {
    cachedSize = nil
    needsLayout = true
    rendered = false
    setAccessibilityValue(text)
    setAccessibilityLabel(text)
  }

  private var rendered = false

  override func layout() {
    super.layout()
    guard !rendered else { return }
    rendered = true
    let size = textSize
    let scale = window?.backingScaleFactor ?? 2
    let image = BrandTextRenderer.image(attributedText, size: size, halo: halo)
    OnboardingMotion.set {
      BrandTextRenderer.apply(image, to: textLayer, glyphSize: size, halo: !halo.isEmpty, scale: scale)
      let x: CGFloat = switch alignment {
      case .center: (bounds.width - size.width) / 2
      case .right: bounds.width - size.width
      default: 0
      }
      textLayer.position = CGPoint(x: x, y: 0)
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    rendered = false
    needsLayout = true
  }
}

// MARK: - Word reveal title

/// A display title whose words resolve one by one (M1, M2): each word is its own layer, drawn once from the laid-out
/// line, and animates by opacity and position only, 45 ms apart. No blur and no re-layout during the animation.
@MainActor
final class WordRevealTitle: NSView {
  var text: String { didSet { if text != oldValue { invalidate() } } }
  var role: BrandType.Role { didSet { if role != oldValue { invalidate() } } }
  var color: NSColor { didSet { if color != oldValue { invalidate() } } }
  var compact = false { didSet { if compact != oldValue { invalidate() } } }
  var maxWidth: CGFloat = 10_000 { didSet { if maxWidth != oldValue { invalidate() } } }
  var halo: [NSShadow] = [] { didSet { invalidate() } }

  private var wordLayers: [CALayer] = []
  private var cached: (size: NSSize, words: [(text: String, frame: CGRect)])?
  private var rendered = false

  init(text: String = "", role: BrandType.Role, color: NSColor) {
    self.text = text
    self.role = role
    self.color = color
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityIdentifier(AXID.Onboarding.title)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private func invalidate() {
    cached = nil
    rendered = false
    needsLayout = true
    setAccessibilityLabel(text)
    setAccessibilityValue(text)
  }

  private var style: BrandType.Style { role.style(compact: compact) }

  private func attributed(_ word: String) -> NSAttributedString {
    NSAttributedString(string: word, attributes: BrandType.attributes(style, color: color, alignment: .left))
  }

  /// Greedy lines of words, each line centred; positions are in the view's flipped coordinates.
  private var layoutResult: (size: NSSize, words: [(text: String, frame: CGRect)]) {
    if let cached { return cached }
    let words = text.split(separator: " ").map(String.init)
    let lineHeight = style.lineHeight ?? style.size
    let space = BrandTextRenderer.measure(attributed("a a"), maxWidth: 10_000).width
      - 2 * BrandTextRenderer.measure(attributed("a"), maxWidth: 10_000).width
    var lines: [[(String, CGFloat)]] = [[]]
    var lineWidth: CGFloat = 0
    for word in words {
      let width = BrandTextRenderer.measure(attributed(word), maxWidth: 10_000).width
      let needed = lines[lines.count - 1].isEmpty ? width : lineWidth + space + width
      if needed > maxWidth, !lines[lines.count - 1].isEmpty {
        lines.append([(word, width)])
        lineWidth = width
      } else {
        lines[lines.count - 1].append((word, width))
        lineWidth = needed
      }
    }
    let widths = lines.map { line in line.map(\.1).reduce(0, +) + space * CGFloat(max(line.count - 1, 0)) }
    let totalWidth = ceil(widths.max() ?? 0)
    var placed: [(String, CGRect)] = []
    for (index, line) in lines.enumerated() {
      var x = (totalWidth - widths[index]) / 2
      for (word, width) in line {
        placed.append((word, CGRect(x: x, y: CGFloat(index) * lineHeight, width: width, height: lineHeight)))
        x += width + space
      }
    }
    let result = (NSSize(width: totalWidth, height: ceil(lineHeight * CGFloat(lines.count))), placed)
    cached = result
    return result
  }

  var textSize: NSSize { text.isEmpty ? .zero : layoutResult.size }
  override var intrinsicContentSize: NSSize { textSize }

  override func layout() {
    super.layout()
    guard !rendered else { return }
    rendered = true
    wordLayers.forEach { $0.removeFromSuperlayer() }
    wordLayers = []
    let result = layoutResult
    let scale = window?.backingScaleFactor ?? 2
    let offsetX = (bounds.width - result.size.width) / 2
    OnboardingMotion.set {
      for (word, frame) in result.words {
        let wordLayer = CALayer()
        let image = BrandTextRenderer.image(attributed(word), size: frame.size, halo: halo)
        BrandTextRenderer.apply(image, to: wordLayer, glyphSize: frame.size, halo: !halo.isEmpty, scale: scale)
        wordLayer.position = CGPoint(x: offsetX + frame.minX, y: frame.minY)
        layer?.addSublayer(wordLayer)
        wordLayers.append(wordLayer)
      }
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    rendered = false
    needsLayout = true
  }

  /// Words resolve one by one: opacity and a 0.18 em rise, 700 ms ease-out, 45 ms apart from `delay`. Under Reduce
  /// Motion the whole title crossfades in 200 ms.
  func reveal(delay: CFTimeInterval, reduceMotion: Bool) {
    layoutSubtreeIfNeeded()
    let rise = style.size * 0.18
    for (index, word) in wordLayers.enumerated() {
      OnboardingMotion.reveal(word, rise: rise, delay: delay + Double(index) * 0.045, reduceMotion: reduceMotion)
    }
  }

  /// Shows every word at rest at once (resume without M1, screenshots).
  func showAtRest() {
    layoutSubtreeIfNeeded()
    OnboardingMotion.set {
      for word in wordLayers {
        word.removeAllAnimations()
        word.opacity = 1
        word.transform = CATransform3DIdentity
      }
    }
  }
}
