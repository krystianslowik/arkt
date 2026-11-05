import AppKit

/// The sidebar container's banner state (#648): the row view, whether the row list has given up the banner's height,
/// and the mask that fades the row list over its last 28 pt while a banner shows. The banner never covers rows: the
/// list shrinks instead.
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

  var reservedHeight: CGFloat { reservesSpace ? SidebarBannerMetrics.reservedHeight : 0 }
  var isShown: Bool { target != nil }
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
      installBannerFade()
      let step = SidebarBannerMotion.appear(reduceMotion: reduceMotion)
      if canAnimate && step.movesRows {
        slot.reservesSpace = false
        needsLayout = true
        layout()
        animateBannerFade(from: from, step: step) { [weak self] in self?.bannerArrived() }
      } else {
        slot.reservesSpace = true
        needsLayout = true
        layout()
      }
      if canAnimate { banner.animateIn(step) } else { banner.isHidden = false }
    } else {
      guard slot.isShown else { return }
      let from = bannerFadeFrame
      let wasReserved = slot.reservesSpace
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
      if step.movesRows {
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

  /// Called from `layout()`: places the banner and the row list's fade.
  func layoutBanner() {
    let frame = SidebarBannerView.frame(forRow: bannerRowFrame)
    if banner.frame != frame { banner.frame = frame }
    guard pager.layer?.mask === bannerSlot.fade else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    placeBannerFade(bannerFadeFrame)
    CATransaction.commit()
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
  private func animateBannerFade(from: CGRect, step: SidebarBannerMotion.Step,
                                 completion: @escaping @MainActor () -> Void) {
    let fade = bannerSlot.fade
    let to = bannerFadeFrame
    // A fade already moving turns around from where it is on screen.
    let moving = fade.animation(forKey: "banner.bounds") != nil
    let start = moving ? fade.presentation()?.frame ?? from : from
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    placeBannerFade(to)
    CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
    for (key, fromValue, toValue) in [
      ("bounds", NSValue(rect: CGRect(origin: .zero, size: start.size)), NSValue(rect: fade.bounds)),
      ("position", NSValue(point: CGPoint(x: start.midX, y: start.midY)), NSValue(point: fade.position)),
    ] {
      let animation = CABasicAnimation(keyPath: key)
      animation.fromValue = fromValue
      animation.toValue = toValue
      animation.duration = step.duration
      animation.timingFunction = step.curve.timingFunction
      fade.add(animation, forKey: "banner.\(key)")
    }
    CATransaction.commit()
  }

  /// For tests: ends the running arrival at once, as its completion would.
  func finishBannerMotionForTesting() {
    bannerSlot.fade.removeAllAnimations()
    bannerArrived()
    layoutSubtreeIfNeeded()
  }

  var bannerReservesSpaceForTesting: Bool { bannerSlot.reservesSpace }
}
