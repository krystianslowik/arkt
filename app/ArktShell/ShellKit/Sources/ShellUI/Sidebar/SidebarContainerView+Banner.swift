import AppKit
import Motion

/// The sidebar container's banner state (#648): the row view, whether the row list has given up the banner's height,
/// and the mask that fades the row list over its last 28 pt while a banner shows. The banner never covers rows: the
/// list shrinks instead.
///
/// A mask costs an offscreen pass on every frame the list draws (scrolling, Space swipes), so it is on only while it
/// shows something: during the appear and dismiss motion, and at rest only while the rows of a page in view reach
/// into the fade.
@MainActor
final class SidebarBannerSlot {
  let view = SidebarBannerView(frame: .zero)
  /// The row list's mask while a banner shows or leaves: opaque, then clear over its last `rowFade` points.
  let fade = CAGradientLayer()
  /// The notice the banner is showing or arriving with; nil while it is gone or leaving.
  fileprivate(set) var target: SidebarNotice?
  /// True once the row list is shorter by the banner's height. While the banner arrives with motion the list keeps
  /// its frame and only its mask moves; the frame follows when the motion ends.
  fileprivate(set) var reservesSpace = false
  /// Bumped by every show and hide; a motion's completion applies only while it is the latest.
  fileprivate var generation = 0
  /// The running mask motion: its step, start time and what runs when it ends; nil at rest.
  fileprivate var fadeMotion: (step: SidebarBannerMotion.Step, start: CFTimeInterval,
                               completion: @MainActor () -> Void)?
  /// Bumped by every mask animation; a Core Animation completion applies only while it is the latest.
  fileprivate var fadeToken = 0
  /// The pages in view the last time the fade was checked (`floor(position)...ceil(position)`).
  fileprivate var pagesInView: ClosedRange<Int>?

  var reservedHeight: CGFloat { reservesSpace ? SidebarBannerMetrics.reservedHeight : 0 }
  var isShown: Bool { target != nil }
  var isFadeMoving: Bool { fadeMotion != nil }
}

extension SidebarContainerView {
  /// Shows `notice` in the banner, swaps the shown notice in place, or (nil) takes the banner away. With motion the
  /// row rises and fades in while the rows above make room on the same curve; leaving, it fades while the rows
  /// settle. Reduce Motion: opacity only, the rows jump. Never moves focus.
  public func setBanner(_ notice: SidebarNotice?, animated: Bool, reduceMotion: Bool) {
    let slot = bannerSlot
    let canAnimate = animated && window != nil
    if let notice {
      if slot.isShown {                                    // a different notice in the same place: no motion
        slot.target = notice
        banner.setNotice(notice)
        return
      }
      let from = bannerFadeFrame                           // the whole list (or where a leaving fade is)
      slot.target = notice
      slot.generation &+= 1
      banner.setNotice(notice)
      banner.reduceMotion = { reduceMotion }
      let step = SidebarBannerMotion.appear(reduceMotion: reduceMotion)
      slot.reservesSpace = false
      if canAnimate && step.movesRows && bannerRowsReachFade {
        // Rows reach where the banner arrives: the list keeps its frame while its mask rises on the banner's curve.
        needsLayout = true
        layout()
        installBannerFade()
        let generation = slot.generation
        animateBannerFade(from: from, step: step) { [weak self] in
          guard let self, self.bannerSlot.generation == generation else { return }
          self.bannerArrived()
        }
      } else {
        // Reduce Motion, or rows that end above the banner: the list takes its shorter frame at once.
        slot.reservesSpace = true
        needsLayout = true
        layout()
      }
      if canAnimate { banner.animateIn(step) } else { banner.isHidden = false }
    } else {
      guard slot.isShown else { return }
      let from = bannerFadeFrame
      let wasReserved = slot.reservesSpace
      let wasMasked = pager.layer?.mask === slot.fade
      slot.target = nil
      slot.generation &+= 1
      let generation = slot.generation
      let step = SidebarBannerMotion.dismiss(reduceMotion: reduceMotion)
      slot.reservesSpace = false
      needsLayout = true
      layout()
      guard canAnimate else {
        banner.hideNow()
        removeBannerFade()
        return
      }
      if step.movesRows && wasMasked {
        installBannerFade()
        // A list that had given up the banner's height grew back at once: its mask starts at the old bottom.
        // In an unflipped layer the list's top moved up by the banner's height, so the old visible part starts there.
        let flipped = pager.layer?.contentsAreFlipped() == true
        let shift = wasReserved && !flipped ? SidebarBannerMetrics.reservedHeight : 0
        let start = CGRect(x: from.minX, y: from.minY + shift, width: from.width, height: from.height)
        animateBannerFade(from: start, step: step) { [weak self] in
          guard let self, self.bannerSlot.generation == generation else { return }
          self.removeBannerFade()
        }
      } else {
        removeBannerFade()
      }
      banner.animateOut(step) {}
    }
  }

  /// The arrival's motion ended: the row list takes its shorter frame (its mask already shows that height).
  func bannerArrived() {
    guard bannerSlot.isShown, !bannerSlot.reservesSpace else { return }
    bannerSlot.reservesSpace = true
    needsLayout = true
  }

  /// The banner row's frame in this view: tab-row width, `bottomGap` above the bottom bar.
  var bannerRowFrame: NSRect {
    let padding = SidebarMetrics.horizontalPadding
    let height = SidebarBannerMetrics.rowHeight
    return NSRect(x: padding, y: bottomBar.frame.minY - SidebarBannerMetrics.bottomGap - height,
                  width: max(0, bounds.width - 2 * padding), height: height)
  }

  /// Called from `layout()`: places the banner and the row list's fade. A layout during the mask's motion (a window
  /// resize) turns the motion toward the new resting frame from where it is on screen, instead of jumping at its end.
  func layoutBanner() {
    let frame = SidebarBannerView.frame(forRow: bannerRowFrame)
    if banner.frame != frame { banner.frame = frame }
    let slot = bannerSlot
    if slot.isFadeMoving {
      if bannerSlot.fade.frame != bannerFadeFrame { retargetBannerFade() }
      return
    }
    refreshBannerFade()
    guard pager.layer?.mask === slot.fade, slot.fade.frame != bannerFadeFrame else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    placeBannerFade(bannerFadeFrame)
    CATransaction.commit()
  }

  /// At rest, puts the mask on while the rows of a page in view reach into the fade and takes it off otherwise.
  func refreshBannerFade() {
    let slot = bannerSlot
    guard !slot.isFadeMoving else { return }                // the motion owns the mask until it ends
    slot.pagesInView = pagesInView
    if slot.isShown && bannerRowsReachFade { installBannerFade() } else { removeBannerFade() }
  }

  /// The pager moved (a swipe or a settle frame): checks the fade again only when another page comes into view, so a
  /// frame costs one comparison.
  func bannerPagerMoved() {
    guard bannerSlot.isShown, pagesInView != bannerSlot.pagesInView else { return }
    refreshBannerFade()
  }

  /// A page's rows changed (insert, remove, expand, collapse, reload): checked again in the next layout, once the
  /// outline has its new rows.
  func bannerRowsChanged() {
    guard bannerSlot.isShown else { return }
    needsLayout = true
  }

  /// The pages the pager shows now: one at rest, two while it moves between them.
  private var pagesInView: ClosedRange<Int>? {
    guard !pager.pages.isEmpty else { return nil }
    let last = pager.pages.count - 1
    let position = pager.position
    let low = min(max(Int(position.rounded(.down)), 0), last)
    let high = min(max(Int(position.rounded(.up)), 0), last)
    return low...high
  }

  /// Whether the last row of a page in view ends below the top of the fade (in the pager, whatever the scroll).
  var bannerRowsReachFade: Bool {
    guard let range = pagesInView else { return false }
    let hidden = bannerSlot.isShown && !bannerSlot.reservesSpace ? SidebarBannerMetrics.reservedHeight : 0
    let fadeTop = pager.bounds.height - hidden - SidebarBannerMetrics.rowFade
    for index in range {
      guard let page = pager.pages[index] as? SpacePageView else { continue }
      let outline = page.outlineView
      let rows = outline.numberOfRows
      guard rows > 0 else { continue }
      let last = outline.convert(outline.rect(ofRow: rows - 1), to: pager)
      let bottom = pager.isFlipped ? last.maxY : pager.bounds.height - last.minY
      if bottom > fadeTop + 0.5 { return true }
    }
    return false
  }

  /// The part of the row list left visible: all of it, less the banner's height while the banner is arriving or
  /// shown and the list has not given it up yet. In the pager layer's coordinates.
  var bannerFadeFrame: CGRect {
    let bounds = pager.bounds
    let hidden = bannerSlot.isShown && !bannerSlot.reservesSpace ? SidebarBannerMetrics.reservedHeight : 0
    let height = max(0, bounds.height - hidden)
    let flipped = pager.layer?.contentsAreFlipped() == true
    return CGRect(x: 0, y: flipped ? 0 : bounds.height - height, width: bounds.width, height: height)
  }

  private func installBannerFade() {
    guard let layer = pager.layer, layer.mask !== bannerSlot.fade else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.mask = bannerSlot.fade
    placeBannerFade(bannerFadeFrame)
    CATransaction.commit()
  }

  private func removeBannerFade() {
    bannerSlot.fadeToken &+= 1
    bannerSlot.fadeMotion = nil
    guard let layer = pager.layer, layer.mask === bannerSlot.fade else { return }
    bannerSlot.fade.removeAllAnimations()
    layer.mask = nil
  }

  /// Sets the mask's frame and its gradient: opaque down to `rowFade` points above the visible bottom, then clear.
  private func placeBannerFade(_ frame: CGRect) {
    let fade = bannerSlot.fade
    let flipped = pager.layer?.contentsAreFlipped() == true
    fade.frame = frame
    // From the top of the list to its bottom, in the layer's own y direction.
    fade.startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
    fade.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
    let opaque = CGColor(gray: 0, alpha: 1)
    let clear = CGColor(gray: 0, alpha: 0)
    let edge = frame.height > 0 ? max(0, 1 - SidebarBannerMetrics.rowFade / frame.height) : 0
    fade.colors = [opaque, opaque, clear]
    fade.locations = [0, NSNumber(value: Double(edge)), 1]
  }

  /// Moves the mask from `from` to its current frame on `step`'s curve. Core Animation runs it; no layout per frame.
  /// `completion` runs once when the motion ends, not when a retarget or a newer motion replaces the animation.
  private func animateBannerFade(from: CGRect, step: SidebarBannerMotion.Step,
                                 completion: @escaping @MainActor () -> Void) {
    // A fade already moving turns around from where it is on screen.
    let moving = bannerSlot.fade.animation(forKey: "banner.bounds") != nil
    let start = moving ? bannerSlot.fade.presentation()?.frame ?? from : from
    bannerSlot.fadeMotion = (step, CACurrentMediaTime(), completion)
    runBannerFade(from: start, duration: step.duration, curve: step.curve)
  }

  /// A layout moved the resting frame mid-motion: heads there from the mask's frame on screen in the time left.
  private func retargetBannerFade() {
    guard let motion = bannerSlot.fadeMotion else { return }
    let start = bannerSlot.fade.presentation()?.frame ?? bannerSlot.fade.frame
    let left = max(motion.step.duration - (CACurrentMediaTime() - motion.start), 1.0 / 120)
    runBannerFade(from: start, duration: left, curve: motion.step.curve)
  }

  private func runBannerFade(from start: CGRect, duration: CFTimeInterval, curve: MotionCurve) {
    let slot = bannerSlot
    let fade = slot.fade
    slot.fadeToken &+= 1
    let token = slot.fadeToken
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    placeBannerFade(bannerFadeFrame)
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.bannerFadeEnded(token) }
    }
    for (key, fromValue, toValue) in [
      ("bounds", NSValue(rect: CGRect(origin: .zero, size: start.size)), NSValue(rect: fade.bounds)),
      ("position", NSValue(point: CGPoint(x: start.midX, y: start.midY)), NSValue(point: fade.position)),
    ] {
      let animation = CABasicAnimation(keyPath: key)
      animation.fromValue = fromValue
      animation.toValue = toValue
      animation.duration = duration
      animation.timingFunction = curve.timingFunction
      fade.add(animation, forKey: "banner.\(key)")
    }
    CATransaction.commit()
  }

  private func bannerFadeEnded(_ token: Int) {
    let slot = bannerSlot
    guard token == slot.fadeToken, let motion = slot.fadeMotion else { return }
    slot.fadeMotion = nil
    motion.completion()
    needsLayout = true                                       // the next layout checks the fade at rest
  }

  /// For tests: ends the running mask motion at once, as its completion would.
  func finishBannerMotionForTesting() {
    let completion = bannerSlot.fadeMotion?.completion
    bannerSlot.fadeToken &+= 1
    bannerSlot.fadeMotion = nil
    bannerSlot.fade.removeAllAnimations()
    completion?()
    layoutSubtreeIfNeeded()
    refreshBannerFade()
  }

  var bannerReservesSpaceForTesting: Bool { bannerSlot.reservesSpace }
}
