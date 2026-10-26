import AppKit
import Motion

/// BH-018: a keyboard command that lands on a row scrolled out of view scrolls the sidebar to it (`springyFast`;
/// Reduce Motion: a jump cut), and a pill on the edge where rows stay hidden says how many ("3 more above"). The pill
/// fades after 3 s or on the next scroll. PARITY(NEEDS-RUNTIME-CHECK): the pill's form in Arc is not documented.
@MainActor
public final class SidebarRevealer {
  /// How long the pill stays (design "Reveal and the overflow pill").
  public static let pillDuration: Duration = .seconds(3)

  public let pill = SidebarOverflowPill(frame: .zero)
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private lazy var scrollDriver = SpringDriver(reduceMotion: { [weak self] in self?.reduceMotion() ?? true })
  private let sleep: ToastSleep
  private var pillTimer: Task<Void, Never>?
  private var pillGeneration = 0

  public init(sleep: @escaping ToastSleep = { try await Task.sleep(for: $0) }) {
    self.sleep = sleep
  }

  public var isScrolling: Bool { scrollDriver.isRunning }

  /// Scrolls `page` so `row` is fully in view and shows the pill when that hid other rows. Nothing happens when the
  /// row is already in view.
  public func reveal(row: Int, in page: SpacePageView, flavor: ThemeFlavor) {
    let outline = page.outlineView
    let clip = page.scrollView.contentView
    guard row >= 0, row < outline.numberOfRows else { return }
    let visible = clip.bounds
    let rowRect = outline.rect(ofRow: row)
    let target: CGFloat
    if rowRect.minY < visible.minY {
      target = rowRect.minY
    } else if rowRect.maxY > visible.maxY {
      target = rowRect.maxY - visible.height
    } else {
      return
    }
    let maxY = max(0, outline.frame.height - visible.height)
    let destination = min(max(target, 0), maxY)
    let scrolledDown = destination > visible.minY
    let hidden = hiddenRows(in: outline, page: page, top: destination, height: visible.height, above: scrolledDown)
    scroll(page, to: destination)
    if hidden > 0 { showPill(count: hidden, above: scrolledDown, in: page, flavor: flavor) }
  }

  /// Rows (the divider aside) wholly above `top`, or wholly below `top + height`.
  private func hiddenRows(in outline: SidebarOutlineView, page: SpacePageView, top: CGFloat, height: CGFloat,
                          above: Bool) -> Int {
    let divider = page.outlineController.dividerRow
    return (0..<outline.numberOfRows).filter { row in
      guard row != divider else { return false }
      let rect = outline.rect(ofRow: row)
      return above ? rect.maxY <= top : rect.minY >= top + height
    }.count
  }

  private func scroll(_ page: SpacePageView, to y: CGFloat) {
    let clip = page.scrollView.contentView
    let apply: (Double) -> Void = { [weak page] value in
      guard let page else { return }
      let clip = page.scrollView.contentView
      clip.scroll(to: NSPoint(x: clip.bounds.minX, y: CGFloat(value)))
      page.scrollView.reflectScrolledClipView(clip)
      page.outlineView.noteFocusRingMaskChanged()
    }
    let running = scrollDriver.stop()
    scrollDriver.animate(in: page, from: running?.value ?? Double(clip.bounds.minY), to: Double(y),
                         initialVelocity: running?.velocity ?? 0, parameters: SpringPreset.springyFast.parameters,
                         onUpdate: apply)
  }

  // MARK: Pill

  private func showPill(count: Int, above: Bool, in page: SpacePageView, flavor: ThemeFlavor) {
    pillGeneration += 1
    pillTimer?.cancel()
    if pill.superview !== page { page.addSubview(pill) }
    pill.configure(text: Self.pillText(count: count, above: above), above: above, flavor: flavor)
    let size = pill.preferredSize()
    let area = page.scrollView.frame
    let y = above ? area.minY + SidebarOverflowPill.edgeInset
      : area.maxY - SidebarOverflowPill.edgeInset - size.height
    pill.frame = NSRect(x: (area.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width,
                        height: size.height)
    pill.present(reduceMotion: reduceMotion())
    page.scrollView.onUserScroll = { [weak self] in self?.hidePill() }
    let (sleep, generation) = (self.sleep, pillGeneration)
    pillTimer = Task { [weak self] in
      do { try await sleep(Self.pillDuration) } catch { return }
      guard !Task.isCancelled, let self, self.pillGeneration == generation else { return }
      self.hidePill()
    }
  }

  /// Fades the pill out (0.15 s). Also on the next scroll of the sidebar.
  public func hidePill() {
    pillGeneration += 1
    pillTimer?.cancel()
    pillTimer = nil
    (pill.superview as? SpacePageView)?.scrollView.onUserScroll = nil
    pill.dismiss()
  }

  /// "3 more above" / "1 more below" (design "Copy").
  public nonisolated static func pillText(count: Int, above: Bool) -> String {
    "\(count) more \(above ? "above" : "below")"
  }
}

/// The overflow pill: 24 pt high, the toast surface and shadow, a chevron and the count. Not interactive.
@MainActor
public final class SidebarOverflowPill: NSView {
  static let height: CGFloat = 24
  static let horizontalPadding: CGFloat = 10
  static let chevronSize: CGFloat = 9
  static let gap: CGFloat = 5
  /// From the sidebar list's edge.
  static let edgeInset: CGFloat = 4
  /// The slide of the entrance, towards the edge it sits on.
  static let slide: CGFloat = 4
  static let fadeOutDuration: CFTimeInterval = 0.15

  public let label = NSTextField(labelWithString: "")
  private let chevron = NSImageView()
  private let surface = CALayer()
  private var drops: [CALayer] = []
  private var above = true
  private lazy var driver = SpringDriver(reduceMotion: { [weak self] in self?.reducesMotion ?? true })
  private var reducesMotion = false
  public private(set) var isShowing = false

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    for _ in ShellTokens.toastShadow.drops {
      let drop = CALayer()
      drops.append(drop)
      layer?.addSublayer(drop)
    }
    surface.cornerRadius = Self.height / 2
    surface.cornerCurve = .continuous
    surface.borderWidth = 0.5
    layer?.addSublayer(surface)
    label.font = .systemFont(ofSize: 11, weight: .regular)
    label.setAccessibilityElement(false)
    label.cell?.setAccessibilityElement(false)
    chevron.imageScaling = .scaleProportionallyUpOrDown
    chevron.setAccessibilityElement(false)
    addSubview(chevron)
    addSubview(label)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityIdentifier(AXID.TabSwitcher.overflowPill)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func configure(text: String, above: Bool, flavor: ThemeFlavor) {
    self.above = above
    label.stringValue = text
    label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    chevron.image = SymbolImageCache.shared.symbol(
      above ? "chevron.up" : "chevron.down", box: Self.chevronSize, weight: .semibold,
      color: ShellTokens.secondaryText.resolve(flavor), scale: window?.backingScaleFactor ?? 2)
    setAccessibilityLabel(text)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.backgroundColor = ShellTokens.toastSurface.resolve(flavor).cgColor
    surface.borderColor = ShellTokens.toastShadow.edge.resolve(flavor).cgColor
    for (drop, token) in zip(drops, ShellTokens.toastShadow.drops) {
      let color = token.color.resolve(flavor)
      drop.shadowColor = RGBA(red: color.red, green: color.green, blue: color.blue, alpha: 1, space: color.space)
        .cgColor
      drop.shadowOpacity = Float(color.alpha)
      drop.shadowRadius = token.shadowRadius
      drop.shadowOffset = CGSize(width: 0, height: token.offsetY)      // flipped: y points down
    }
    CATransaction.commit()
    needsLayout = true
  }

  func preferredSize() -> NSSize {
    let text = ceil(label.intrinsicContentSize.width)
    return NSSize(width: 2 * Self.horizontalPadding + Self.chevronSize + Self.gap + text, height: Self.height)
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.frame = bounds
    let path = CGPath(roundedRect: bounds, cornerWidth: Self.height / 2, cornerHeight: Self.height / 2,
                      transform: nil)
    for drop in drops {
      drop.frame = bounds
      drop.shadowPath = path
    }
    CATransaction.commit()
    chevron.frame = NSRect(x: Self.horizontalPadding, y: (bounds.height - Self.chevronSize) / 2,
                           width: Self.chevronSize, height: Self.chevronSize)
    let height = ceil(label.intrinsicContentSize.height)
    let x = chevron.frame.maxX + Self.gap
    label.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: bounds.width - x - Self.horizontalPadding,
                         height: height)
  }

  /// Fades in and slides 4 pt from its edge (`springyFast`). Reduce Motion: a plain fade.
  func present(reduceMotion: Bool) {
    reducesMotion = reduceMotion
    isShowing = true
    isHidden = false
    layer?.removeAllAnimations()
    let slide = above ? -Self.slide : Self.slide
    let apply: (Double) -> Void = { [weak self] progress in
      guard let layer = self?.layer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.opacity = Float(progress)
      layer.transform = CATransform3DMakeTranslation(0, slide * CGFloat(1 - progress), 0)
      CATransaction.commit()
    }
    if reduceMotion {
      apply(1)
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      fade.duration = Self.fadeOutDuration
      layer?.add(fade, forKey: "pill.fade")
      return
    }
    apply(0)
    driver.animate(in: self, from: 0, to: 1, initialVelocity: 0, parameters: SpringPreset.springyFast.parameters,
                   onUpdate: apply)
  }

  /// Fades out (0.15 s) and hides.
  func dismiss() {
    guard isShowing else { return }
    isShowing = false
    driver.stop()
    guard let layer, window != nil else {
      isHidden = true
      return
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
    fade.toValue = 0
    fade.duration = Self.fadeOutDuration
    fade.timingFunction = TabSwitcherView.easeOut
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShowing else { return }
        self.isHidden = true
      }
    }
    layer.opacity = 0
    layer.add(fade, forKey: "pill.fade")
    CATransaction.commit()
  }
}
