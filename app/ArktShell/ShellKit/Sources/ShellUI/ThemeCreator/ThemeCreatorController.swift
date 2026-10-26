import AppKit
import Motion

/// Runs one Space theme creator popover (#410): the state (`ThemeCreatorModel`), the view, haptics, the live
/// re-tint and the writes to the source.
///
/// - A pointer drag (dot or slider) previews every event through `SidebarController.previewTheme`: the window, the
///   page and the sidebar text follow at once with no animation, and nothing is stored. The theme is stored when the
///   drag ends, after the preview already shows it, so the window does not crossfade.
/// - Discrete changes from the pointer (adding or removing a colour, a texture) are stored at once; the window
///   crossfades on `firm` while the creator is open. Keyboard changes are stored at once without animation.
/// - Closing registers one undo step for the whole session.
@MainActor
final class ThemeCreatorController {
  let spaceID: SpaceID
  let view = ThemeCreatorView(frame: .zero)
  private(set) var model: ThemeCreatorModel
  private weak var sidebar: SidebarController?
  private let haptics: ThemeHaptics
  /// Read on open, close and dot changes. Tests replace it.
  var reducesMotion: @MainActor () -> Bool
  /// The theme at open; nil when the Space drew the default theme.
  private let themeAtOpen: SpaceThemeInfo?
  /// The state at open: a Space on the default theme stores nothing until the user changes something.
  private let modelAtOpen: ThemeCreatorModel
  /// The source's theme after the creator's last write: a different one came from elsewhere (a preset).
  private var lastStored: SpaceThemeInfo?
  private var isWriting = false
  private var dragHue: Double?
  private var leavingDot: Int?
  private var outsideClickMonitor: Any?
  private(set) var isClosed = false
  /// Runs once the popover has closed.
  var onClose: (() -> Void)?

  init(spaceID: SpaceID, sidebar: SidebarController, haptics: ThemeHaptics = ThemeHaptics(),
       reducesMotion: @escaping @MainActor () -> Bool = {
         NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
       }) {
    self.spaceID = spaceID
    self.sidebar = sidebar
    self.haptics = haptics
    self.reducesMotion = reducesMotion
    let info = sidebar.source.space(spaceID)
    let stored = info?.theme ?? SpaceThemeInfo(baseColors: [], isDark: false)
    let isNew = info?.usesDefaultTheme ?? true
    themeAtOpen = isNew ? nil : stored
    lastStored = stored
    model = ThemeCreatorModel(theme: stored, isNew: isNew)
    modelAtOpen = model
    view.pad.reducesMotion = reducesMotion
    wire()
  }

  private var flavor: ThemeFlavor { sidebar?.themeContext.appearance ?? .light }
  private var title: String { sidebar?.source.space(spaceID)?.title ?? "" }

  // MARK: - Open and close

  /// Adds the popover to `host` with its arrow at `anchor` (the Space name's centre, host coordinates), its body
  /// `gap` points right of `edge` (the sidebar's trailing edge). Focus starts on the first dot.
  func show(in host: NSView, anchor: NSPoint, edge: CGFloat, gap: CGFloat = 12) {
    let size = view.frame.size
    var x = max(edge, anchor.x) + gap
    x = min(x, max(host.bounds.width - size.width - 8, ThemeCreatorMetrics.arrowDepth))
    let arrow = ThemeCreatorMetrics.arrowCenterY
    var y = host.isFlipped ? anchor.y - arrow : anchor.y + arrow - size.height
    y = min(max(y, 8), max(host.bounds.height - size.height - 8, 8))
    view.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    apply(animated: false)
    host.addSubview(view, positioned: .above, relativeTo: nil)
    view.layoutSubtreeIfNeeded()
    view.updateKeyViewLoop()
    if let first = view.pad.dots.first { host.window?.makeFirstResponder(first) }
    animateOpen()
    outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      MainActor.assumeIsolated { self?.handleOutsideClick(event) }
      return event
    }
  }

  private func handleOutsideClick(_ event: NSEvent) {
    guard !isClosed, let host = view.superview else { return }
    if event.window !== host.window || !view.frame.contains(host.convert(event.locationInWindow, from: nil)) {
      close(animated: true)
    }
  }

  /// Closes the popover (fade out 0.12 s), keeps every change and registers one undo step for the session.
  func close(animated: Bool) {
    guard !isClosed else { return }
    isClosed = true
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
    sidebar?.previewTheme(nil, for: spaceID)
    registerUndo()
    let window = view.window
    if let first = window?.firstResponder as? NSView, first.isDescendant(of: view) { window?.makeFirstResponder(nil) }
    guard animated, let layer = view.layer, view.window != nil else {
      view.removeFromSuperview()
      onClose?()
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.view.removeFromSuperview() }
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = ThemeCreatorMotion.closeDuration
    fade.timingFunction = ThemeCreatorMotion.easeOut
    view.alphaValue = 0
    layer.add(fade, forKey: "close")
    CATransaction.commit()
    onClose?()
  }

  /// Scale 0.96 to 1 and fade in from the arrow on `springyFast`; Reduce Motion fades only.
  private func animateOpen() {
    guard let layer = view.layer else { return }
    if reducesMotion() {
      layer.add(ThemeDotView.fade(from: 0, to: 1, duration: ThemeCreatorMotion.stateDuration), forKey: "open")
      return
    }
    let tip = view.convertToLayer(NSPoint(x: -ThemeCreatorMetrics.arrowDepth, y: ThemeCreatorMetrics.arrowCenterY))
    let scale = ThemeCreatorMotion.openScale
    let from = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-tip.x, -tip.y, 0),
                                                       CATransform3DMakeScale(scale, scale, 1)),
                                   CATransform3DMakeTranslation(tip.x, tip.y, 0))
    let grow = CASpringAnimation(keyPath: "transform")
    let parameters = ThemeCreatorMotion.open
    grow.mass = CGFloat(parameters.mass)
    grow.stiffness = CGFloat(parameters.stiffness)
    grow.damping = CGFloat(parameters.damping)
    grow.fromValue = NSValue(caTransform3D: from)
    grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    grow.duration = max(parameters.settlingDuration(), grow.settlingDuration)
    layer.add(grow, forKey: "openScale")
    layer.add(SpringAnimationFactory.make(keyPath: "opacity", from: 0, to: 1, parameters: parameters),
              forKey: "openFade")
  }

  // MARK: - Wiring

  private func wire() {
    view.onCancel = { [weak self] in self?.close(animated: true) }
    view.countButton.onPress = { [weak self] in self?.toggleColourCount() }
    view.pad.onDragBegan = { [weak self] index in self?.dotDragBegan(index) }
    view.pad.onDragMoved = { [weak self] index, location in self?.dotDragged(index, to: location) }
    view.pad.onDragEnded = { [weak self] index, location in self?.dotDragEnded(index, at: location) }
    view.pad.onDoubleClick = { [weak self] location in self?.addSecondColour(at: location) }
    view.swatches.onSelect = { [weak self] texture, byPointer in self?.selectTexture(texture, byPointer: byPointer) }
    view.amountSlider.onChange = { [weak self] value, phase in self?.sliderChanged(.amount, value, phase) }
    view.opacitySlider.onChange = { [weak self] value, phase in self?.sliderChanged(.opacity, value, phase) }
  }

  /// Redraws the popover from the model.
  private func apply(animated: Bool) {
    view.apply(model, title: title, flavor: flavor, animated: animated)
    for dot in view.pad.dots {
      dot.onArrow = { [weak self] index, arrow, large in self?.dotKey(index, arrow, large: large) }
      dot.onDelete = { [weak self] index in self?.deleteDot(index) }
    }
  }

  // MARK: - Writing

  /// Shows the model's theme on the window at once, without storing it.
  private func preview() { sidebar?.previewTheme(model.theme, for: spaceID) }

  /// Stores the model's theme. `animated` false: the preview shows it first, so the window does not crossfade.
  private func store(animated: Bool) {
    guard let sidebar else { return }
    if !animated { preview() }
    sidebar.previewTheme(nil, for: spaceID)
    guard let info = sidebar.source.space(spaceID) else { return }
    let changed = info.usesDefaultTheme ? model != modelAtOpen : info.theme != model.theme
    isWriting = true
    if changed { sidebar.source.setTheme(spaceID, to: model.theme) }
    isWriting = false
    lastStored = sidebar.source.space(spaceID)?.theme
  }

  /// The source changed: a preset picked while the creator is open moves the dots. The Space gone closes it.
  func sourceDidChange() {
    guard !isClosed, !isWriting, !view.pad.isDragging, let sidebar else { return }
    guard let info = sidebar.source.space(spaceID) else {
      close(animated: false)
      return
    }
    if info.theme != lastStored {
      lastStored = info.theme
      model.replace(with: info.theme)
      apply(animated: true)
      view.updateKeyViewLoop()
    } else {
      view.apply(model, title: title, flavor: flavor, animated: false)
    }
  }

  // MARK: - Dots

  private func dotDragBegan(_ index: Int) {
    guard model.dots.indices.contains(index) else { return }
    let point = model.dots[index].point
    dragHue = point.hue
    haptics.beginToneTracking(distanceFromLimit: Self.distanceFromToneLimit(point))
  }

  private func dotDragged(_ index: Int, to location: CGPoint) {
    guard model.dots.indices.contains(index) else { return }
    let leaving = model.dots.count > 1 && ThemeCreatorModel.isOffPad(location, padSize: view.pad.bounds.size)
    view.pad.setLeaving(leaving, dot: index)
    leavingDot = leaving ? index : nil
    guard !leaving else { return }
    let point = ThemePad.point(at: location, in: view.pad.bounds.size)
    if let dragHue { haptics.hue(from: dragHue, to: point.hue) }
    dragHue = point.hue
    haptics.tone(distanceFromLimit: Self.distanceFromToneLimit(point))
    model.moveDot(index, to: point)
    apply(animated: false)
    preview()
  }

  private func dotDragEnded(_ index: Int, at location: CGPoint) {
    dragHue = nil
    if leavingDot == index, model.dots.count > 1 {
      leavingDot = nil
      view.pad.removeDot(at: index, animated: true)
      model.removeDot(index)
      apply(animated: true)
      view.updateKeyViewLoop()
      store(animated: true)
      return
    }
    leavingDot = nil
    store(animated: false)
  }

  /// Points between `point` and the nearer tone limit.
  static func distanceFromToneLimit(_ point: ThemePadPoint) -> Double {
    min(point.tone - ThemePad.minimumTone, ThemePad.maximumTone - point.tone) * ThemePad.size.height
  }

  private func dotKey(_ index: Int, _ arrow: ThemePad.Arrow, large: Bool) {
    guard model.dots.indices.contains(index) else { return }
    model.moveDot(index, to: ThemePad.step(model.dots[index].point, arrow, large: large))
    apply(animated: false)
    store(animated: false)
  }

  private func deleteDot(_ index: Int) {
    guard model.dots.count > 1 else { return }
    view.pad.removeDot(at: index, animated: false)
    model.removeDot(index)
    apply(animated: false)
    view.updateKeyViewLoop()
    if let dot = view.pad.dots.first { view.window?.makeFirstResponder(dot) }
    store(animated: false)
  }

  private func toggleColourCount() {
    if model.dots.count > 1 {
      view.pad.removeDot(at: 1, animated: true)
      model.removeDot(1)
    } else {
      model.addSecondColour(at: nil)
    }
    apply(animated: true)
    view.updateKeyViewLoop()
    store(animated: true)
  }

  private func addSecondColour(at location: CGPoint) {
    guard model.dots.count == 1 else { return }
    model.addSecondColour(at: ThemePad.point(at: location, in: view.pad.bounds.size))
    apply(animated: true)
    view.updateKeyViewLoop()
    store(animated: true)
  }

  // MARK: - Texture and sliders

  private func selectTexture(_ texture: ThemeTexture?, byPointer: Bool) {
    guard texture?.rawValue != model.theme.texture else { return }
    if byPointer { haptics.textureChanged() }
    model.setTexture(texture?.rawValue)
    apply(animated: false)
    store(animated: byPointer)
  }

  private func sliderChanged(_ slider: ThemeHapticGate.Slider, _ value: Double, _ phase: ThemeSliderView.Phase) {
    let old = slider == .amount ? model.theme.noiseFactor : model.theme.opacity
    if phase != .keyboard { haptics.slider(slider, from: old, to: value) }
    if slider == .amount { model.setAmount(value) } else { model.setOpacity(value) }
    apply(animated: false)
    switch phase {
    case .began, .changed: preview()
    case .ended, .keyboard: store(animated: false)
    }
  }

  // MARK: - Undo

  /// One undo step for the session: back to the theme at open (the default theme included), and redo.
  private func registerUndo() {
    guard let sidebar, let manager = view.window?.undoManager ?? sidebar.view.window?.undoManager,
          let info = sidebar.source.space(spaceID) else { return }
    let after: SpaceThemeInfo? = info.usesDefaultTheme ? nil : info.theme
    guard after != themeAtOpen else { return }
    Self.registerUndo(manager, source: sidebar.source, space: spaceID, to: themeAtOpen, redo: after)
  }

  private static func registerUndo(_ manager: UndoManager, source: any SidebarSource, space: SpaceID,
                                   to theme: SpaceThemeInfo?, redo: SpaceThemeInfo?) {
    manager.registerUndo(withTarget: source) { [weak manager] source in
      MainActor.assumeIsolated {
        source.setTheme(space, to: theme)
        if let manager { registerUndo(manager, source: source, space: space, to: redo, redo: theme) }
      }
    }
    manager.setActionName("Space Theme")
  }
}
