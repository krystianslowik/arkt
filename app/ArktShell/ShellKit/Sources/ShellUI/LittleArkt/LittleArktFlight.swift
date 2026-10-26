import AppKit
import EngineAPI
import Motion
import os
import QuartzCore

// MARK: - Destination

/// The main window's side of the Open in flight (#352): where the card lands, and the page's row, which is in the
/// sidebar from the start (drawn by the flight's clock) while the page itself moves only at rest.
@MainActor
protocol LittleArktFlightDestination: AnyObject {
  var flightWindow: NSWindow? { get }
  /// The content card on screen, laid out now.
  var flightCardFrame: CGRect? { get }
  /// Adds `tab`'s row at the top of Today in `space` (the current Space when nil) without showing it yet; nil when
  /// the sidebar refuses the row.
  func beginReceiving(_ tab: TabID, in space: SpaceID?) -> NodeID?
  /// One frame of the row's arrival: the rows below making room, the row fading in.
  func presentArrival(of node: NodeID, room: Double, appear: Double)
  /// The flight is at rest: the page moves into this window, mounted at its final size, selected and focused.
  func finishReceiving(_ tab: TabID, node: NodeID) -> Bool
}

// MARK: - Overlay

/// The transparent, click-through window the flight draws on, spanning the Little Arkt window and the main window.
/// It never becomes key or main and is not in the Window menu.
@MainActor
final class LittleArktFlightOverlay: NSWindow {
  init(frame: CGRect, level: NSWindow.Level) {
    super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    isExcludedFromWindowsMenu = true
    animationBehavior = .none
    collectionBehavior = [.transient, .ignoresCycle]
    self.level = level
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    view.setAccessibilityElement(false)
    contentView = view
    setAccessibilityElement(false)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// MARK: - Flight

/// One Open in flight: the page's snapshot on its plate, as a layer on `overlay`, flies from the Little Arkt card to
/// the main window's content card (docs/design/little-arkt.md, Motion).
///
/// Nothing changes on screen until the first display frame: if the snapshot is ready by then the card flies with it,
/// else as its plate, and the snapshot fades in on it when it arrives. The live page never moves mid-flight; at rest
/// `onLand` moves it, and after the page's first frame in the main card (the next display frame) the card crossfades
/// away (0.1 s) and the overlay is removed.
///
/// Every frame sets layer properties only: the card's position, mask bounds, scale and opacity, the snapshot's
/// position and opacity, and the arriving row's style through `onRoom`. The image is decoded before it gets here.
@MainActor
final class LittleArktFlight {
  enum Stage: Equatable {
    /// Built; nothing on screen yet. The first frame starts the flight.
    case waitingForFrame
    case flying
    /// At rest: the page moved into the main card; its first frame there is next.
    case landed
    case crossfading
    case finished
  }

  let overlay: LittleArktFlightOverlay
  /// The plate (the page's stand-in background), clipped to the card's corners: the mask that grows.
  let cardLayer = CALayer()
  /// The page's frame at its own size, centered at the top of the card.
  let snapshotLayer = CALayer()
  private(set) var stage = Stage.waitingForFrame
  /// The first frame's scene, in the overlay's coordinates.
  private(set) var startScene: LittleArktFlightScene
  private var springs: LittleArktFlightSpringSet
  private var scene: LittleArktFlightScene
  private let target: CGRect
  private var snapshot: LittleArktSnapshot?
  private var fadesSnapshotIn = false
  private var link: CADisplayLink?
  private var interval: OSSignpostIntervalState?

  /// Tests turn this off and call `tick(at:)` with times of their own.
  var drivesDisplayLink = true
  /// The first frame: the small frame fades and the main window comes forward.
  var onStart: (@MainActor () -> Void)?
  /// Every frame: the Today rows making room (0 to 1) and the new row fading in (0 to 1).
  var onRoom: (@MainActor (_ room: Double, _ row: Double) -> Void)?
  /// At rest: the page moves.
  var onLand: (@MainActor () -> Void)?
  /// The overlay is gone.
  var onFinish: (@MainActor () -> Void)?

  var hasSnapshot: Bool { snapshot != nil }

  /// `source` is where the window shows the card now, scaled by `scale` about its center; `target` is the main
  /// card. All three rectangles are in screen coordinates; the overlay spans `span`.
  init(source: CGRect, scale: Double, opacity: Double, target: CGRect, span: CGRect, level: NSWindow.Level,
       flavor: ThemeFlavor) {
    let frame = span.union(source).union(target).integral
    overlay = LittleArktFlightOverlay(frame: frame, level: level)
    let origin = frame.origin
    let local = { (rect: CGRect) in rect.offsetBy(dx: -origin.x, dy: -origin.y) }
    self.target = local(target)
    startScene = LittleArktFlightMotion.start(visibleCard: local(source), scale: scale, opacity: opacity,
                                              snapshotReady: false)
    springs = LittleArktFlightSpringSet(scene: startScene)
    scene = startScene
    buildLayers(flavor: flavor)
  }

  isolated deinit {
    link?.invalidate()
  }

  private func buildLayers(flavor: ThemeFlavor) {
    let radius = ShellMetrics.standard.cardCornerRadius
    cardLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    cardLayer.cornerRadius = radius
    cardLayer.cornerCurve = .continuous
    cardLayer.masksToBounds = true
    cardLayer.backgroundColor = ShellTokens.toolbarSurface.resolve(flavor).cgColor
    cardLayer.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    cardLayer.borderWidth = 1 / max(overlay.backingScaleFactor, 1)
    snapshotLayer.contentsGravity = .resize
    snapshotLayer.opacity = 0
    cardLayer.addSublayer(snapshotLayer)
    overlay.contentView?.layer?.addSublayer(cardLayer)
  }

  /// The card as drawn now, in screen coordinates.
  var cardFrameOnScreen: CGRect {
    LittleArktFlightMotion.cardRect(scene).offsetBy(dx: overlay.frame.minX, dy: overlay.frame.minY)
  }

  // MARK: Driving

  /// Waits for the next display frame of `view` (the main window's), which starts the flight. Without a display
  /// (no window), the flight runs to its end at once.
  func start(on view: NSView?) {
    interval = ShellSignposts.signposter.beginInterval("LittleArkt", "flight")
    guard drivesDisplayLink else { return }
    guard let view, view.window != nil else {
      runToEnd()
      return
    }
    let link = view.displayLink(target: LittleArktFlightLinkTarget(flight: self),
                                selector: #selector(LittleArktFlightLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  /// The decoded snapshot, or nil when the engine had no frame to copy (the plate flies alone).
  func snapshotArrived(_ snapshot: LittleArktSnapshot?) {
    guard let snapshot, self.snapshot == nil else { return }
    switch stage {
    case .waitingForFrame:
      install(snapshot)
    case .flying:
      install(snapshot)
      fadesSnapshotIn = true                                // from the next frame
    case .landed, .crossfading, .finished:
      break                                                 // the page is in the main card already
    }
  }

  private func install(_ snapshot: LittleArktSnapshot) {
    self.snapshot = snapshot
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    snapshotLayer.contents = snapshot.image
    snapshotLayer.contentsScale = snapshot.scale
    snapshotLayer.bounds = CGRect(origin: .zero, size: snapshot.pointSize)
    CATransaction.commit()
  }

  /// One display frame at `t` (the display link's target timestamp).
  func tick(at t: Double) {
    switch stage {
    case .waitingForFrame:
      begin(at: t)
    case .flying:
      if fadesSnapshotIn {
        fadesSnapshotIn = false
        springs.apply([LittleArktFlightMotion.snapshotFadeIn], at: t)
      }
      present(springs.scene(at: t))
      if springs.isSettled(at: t) { land() }
    case .landed:
      // The page's first frame in the main card: the snapshot crossfades away.
      stage = .crossfading
      springs.apply([LittleArktFlightMotion.crossfade], at: t)
      present(springs.scene(at: t))
    case .crossfading:
      present(springs.scene(at: t))
      if springs.isSettled(at: t) { finish() }
    case .finished:
      link?.invalidate()
      link = nil
    }
  }

  private func begin(at t: Double) {
    stage = .flying
    if snapshot != nil { startScene[.image] = 1 }
    springs = LittleArktFlightSpringSet(scene: startScene)
    springs.apply(LittleArktFlightMotion.flight(to: target), at: t)
    present(springs.scene(at: t))
    overlay.orderFront(nil)
    onStart?()
  }

  private func land() {
    stage = .landed
    onLand?()
  }

  /// No display: every stage at once, ending with the overlay gone.
  func runToEnd() {
    if stage == .waitingForFrame { begin(at: 0) }
    if stage == .flying {
      springs.jump(to: springs.scene(at: 30))
      present(springs.scene(at: 30))
      land()
    }
    finish()
  }

  private func finish() {
    guard stage != .finished else { return }
    stage = .finished
    link?.invalidate()
    link = nil
    overlay.orderOut(nil)
    snapshotLayer.contents = nil
    snapshot = nil
    if let interval { ShellSignposts.signposter.endInterval("LittleArkt", interval) }
    interval = nil
    onFinish?()
  }

  // MARK: Presenting

  private func present(_ next: LittleArktFlightScene) {
    scene = next
    let width = max(next[.width], 0)
    let height = max(next[.height], 0)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    cardLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    cardLayer.position = CGPoint(x: next[.centerX], y: next[.centerY])
    cardLayer.transform = CATransform3DMakeScale(next[.scale], next[.scale], 1)
    cardLayer.opacity = Float(min(max(next[.opacity], 0), 1))
    // Top-anchored and centered (y up): the page keeps its size while the mask grows around it.
    let size = snapshotLayer.bounds.size
    snapshotLayer.position = CGPoint(x: width / 2, y: height - size.height / 2)
    snapshotLayer.opacity = snapshot == nil ? 0 : Float(min(max(next[.image], 0), 1))
    CATransaction.commit()
    if stage == .flying { onRoom?(next[.room], next[.row]) }    // at rest the row is the window's again
  }
}

/// Display-link target that does not retain the flight.
@MainActor
private final class LittleArktFlightLinkTarget: NSObject {
  weak var flight: LittleArktFlight?
  init(flight: LittleArktFlight) { self.flight = flight }
  @objc func tick(_ link: CADisplayLink) {
    guard let flight else { link.invalidate(); return }
    flight.tick(at: link.targetTimestamp)
  }
}
