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
  /// `clearingPrevious` drops the old row's previous fill when the arrival already faded it out (#455). `dialog` is the
  /// page's pending JavaScript dialog, which this window shows from now on (#471).
  func finishReceiving(_ tab: TabID, node: NodeID, clearingPrevious: Bool, dialog: JavaScriptDialog?) -> Bool
  /// The flight ended without the page coming here: the row's arrival stops and the row goes (the page was never
  /// moved, so nothing here owns it).
  func cancelReceiving(_ tab: TabID, node: NodeID)
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

// MARK: - Abort

/// Why a flight ended before it landed by itself.
enum LittleArktFlightAbort: Equatable {
  /// The main window closed: the page stays in the small window.
  case mainWindowClosed
  case mainWindowMiniaturized
  /// The main window's display link stopped delivering frames (`LittleArktFlight.quietChecksToAbort` checks in a row).
  case framesStopped
  case appTerminating
  /// The small window is closing: the page lands first.
  case smallWindowClosing
  /// Cmd-W or the close button: the page lands first, then the window closes.
  case closeRequested
  /// The page closed itself (`window.close()`): there is nothing to land.
  case pageClosed
}

/// Schedules one watchdog check on a clock the caller injects, and returns what cancels it. The flight counts frames
/// at every check, never seconds.
typealias LittleArktFlightWatchdog = @MainActor (_ check: @escaping @MainActor () -> Void) -> @MainActor () -> Void

// MARK: - Flight

/// One Open in flight: the page's snapshot on its plate, as a layer on `overlay`, flies from the Little Arkt card to
/// the main window's content card (docs/design/little-arkt.md, Motion).
///
/// Nothing changes on screen until the first display frame: if the snapshot is ready by then the card flies with it,
/// else as its plate, and the snapshot fades in on it when it arrives. The live page never moves mid-flight; at rest
/// `onLand` moves it, and after the page's first frame in the main card (the next display frame) the card crossfades
/// away (0.1 s) and the overlay is removed.
///
/// A flight that cannot land by itself (the main window closes or miniaturizes, its display link stops, the small
/// window closes, the page closes, the app terminates) ends with `abort(_:)`: `onAbort` puts the page where the
/// reason says (the landing without the flight, or staying put) and the overlay comes off at once.
///
/// Every frame sets layer properties only: the card's position, mask bounds, scale and opacity, the shadow layer's
/// to match (its path rebuilt only when the size changed), the snapshot's position and opacity, and the arriving
/// row's style through `onRoom`. The image is decoded before it gets here.
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
  /// The card's shadow (#456): a layer of its own under the card, since the card's mask would clip it. It has the
  /// card's position, size, scale and opacity, and an explicit `shadowPath`, so drawing it needs no offscreen pass.
  let shadowLayer = CALayer()
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
  private var watcher: LittleArktFlightWatcher?
  private var cancelWatchdog: (@MainActor () -> Void)?
  private var frames = 0
  private var framesAtLastCheck = 0
  private var quietChecks = 0
  private let cornerRadius = ShellMetrics.standard.cardCornerRadius
  private var shadowPathSize: CGSize?
  /// How many times the shadow's path was rebuilt: only when the card's size changed since the last frame.
  private(set) var shadowPathUpdates = 0

  /// Whether the card carries its shadow. On in light and off in dark (the token is clear there, so no shadow pass
  /// at all); tests and the frame-cost measurement switch it.
  var carriesShadow: Bool {
    didSet { if carriesShadow != oldValue { applyShadowState() } }
  }

  /// Checks with no frame in between that end a flight (the first quiet one is a hitch).
  static let quietChecksToAbort = 2
  /// The production watchdog's interval, on the real clock; tests inject their own.
  static let watchdogInterval: Duration = .milliseconds(250)

  /// Schedules the watchdog's checks. Nil: the real clock when the flight drives a display link, none otherwise.
  var watchdog: LittleArktFlightWatchdog?

  /// Tests turn this off and call `tick(at:)` with times of their own.
  var drivesDisplayLink = true
  /// The first frame: the small frame fades and the main window comes forward.
  var onStart: (@MainActor () -> Void)?
  /// Every frame: the Today rows making room (0 to 1) and the new row fading in (0 to 1).
  var onRoom: (@MainActor (_ room: Double, _ row: Double) -> Void)?
  /// At rest: the page moves.
  var onLand: (@MainActor () -> Void)?
  /// The flight cannot land by itself: the page goes where this says; the overlay comes off right after.
  var onAbort: (@MainActor (LittleArktFlightAbort) -> Void)?
  /// The overlay is gone.
  var onFinish: (@MainActor () -> Void)?

  var hasSnapshot: Bool { snapshot != nil }

  /// `source` is where the window shows the card now, scaled by `scale` about its center; `target` is the main
  /// card. All three rectangles are in screen coordinates; the overlay spans `span`.
  init(source: CGRect, scale: Double, opacity: Double, target: CGRect, span: CGRect, level: NSWindow.Level,
       flavor: ThemeFlavor) {
    carriesShadow = flavor != .dark
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
    cancelWatchdog?()
    watcher?.stop()
    overlay.orderOut(nil)                                     // a flight nobody finished takes its overlay with it
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
    // The same values as the main window's card (`ContentCardView.updateLayer`), which the flight lands on.
    shadowLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    shadowLayer.shadowColor = ShellTokens.cardShadow.resolve(flavor).cgColor
    shadowLayer.shadowRadius = 3
    shadowLayer.shadowOffset = CGSize(width: 0, height: -1)
    applyShadowState()
    overlay.contentView?.layer?.addSublayer(shadowLayer)
    overlay.contentView?.layer?.addSublayer(cardLayer)
  }

  /// On: the shadow shows (its path follows at the next frame). Off: no shadow and no path, so no pass for it.
  private func applyShadowState() {
    shadowLayer.shadowOpacity = carriesShadow ? 1 : 0
    if !carriesShadow {
      shadowLayer.shadowPath = nil
      shadowPathSize = nil
    }
  }

  /// The shadow follows the card in the same tick. The path is rebuilt only when the size changed: while the mask
  /// grows it follows every frame, at rest and while it fades it stays.
  private func presentShadow(size: CGSize) {
    guard carriesShadow else { return }
    shadowLayer.bounds = CGRect(origin: .zero, size: size)
    shadowLayer.position = cardLayer.position
    shadowLayer.transform = cardLayer.transform
    shadowLayer.opacity = cardLayer.opacity
    if shadowPathSize != size {
      shadowPathSize = size
      shadowPathUpdates += 1
      shadowLayer.shadowPath = CGPath(roundedRect: shadowLayer.bounds, cornerWidth: cornerRadius,
                                      cornerHeight: cornerRadius, transform: nil)
    }
  }

  /// The overlay is going: nothing of the shadow stays behind.
  private func clearShadow() {
    shadowLayer.removeFromSuperlayer()
    shadowLayer.shadowOpacity = 0
    shadowLayer.shadowPath = nil
    shadowPathSize = nil
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
    watcher = LittleArktFlightWatcher(flight: self, mainWindow: view?.window)
    armWatchdog()
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
    frames += 1
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
    cancelWatchdog?()
    cancelWatchdog = nil
    watcher?.stop()
    watcher = nil
    overlay.orderOut(nil)
    clearShadow()
    snapshotLayer.contents = nil
    snapshot = nil
    if let interval { ShellSignposts.signposter.endInterval("LittleArkt", interval) }
    interval = nil
    onFinish?()
  }

  // MARK: Abort

  /// Ends the flight early. Before it landed, `onAbort` puts the page where `reason` says; after it landed (the
  /// page is in the main card already) only the overlay comes off.
  func abort(_ reason: LittleArktFlightAbort) {
    switch stage {
    case .waitingForFrame, .flying:
      onAbort?(reason)
    case .landed, .crossfading, .finished:
      break
    }
    finish()
  }

  private func armWatchdog() {
    guard let schedule = watchdog ?? (drivesDisplayLink ? Self.realClockWatchdog : nil) else { return }
    cancelWatchdog = schedule { [weak self] in self?.watchdogChecked() }
  }

  /// One interval passed: no frame since the last check twice in a row means the display link is not running.
  private func watchdogChecked() {
    guard stage != .finished else { return }
    if frames == framesAtLastCheck {
      quietChecks += 1
      if quietChecks >= Self.quietChecksToAbort {
        abort(.framesStopped)
        return
      }
    } else {
      quietChecks = 0
    }
    framesAtLastCheck = frames
    armWatchdog()
  }

  private static let realClockWatchdog: LittleArktFlightWatchdog = { check in
    let task = Task { @MainActor in
      try? await Task.sleep(for: watchdogInterval)
      guard !Task.isCancelled else { return }
      check()
    }
    return { task.cancel() }
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
    presentShadow(size: CGSize(width: width, height: height))
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


/// What ends a flight from outside: the main window closing or miniaturizing, and the app terminating. Selector
/// based, so the flight hears them on the posting turn, before the window is gone.
@MainActor
private final class LittleArktFlightWatcher: NSObject {
  private weak var flight: LittleArktFlight?

  init(flight: LittleArktFlight, mainWindow: NSWindow?) {
    self.flight = flight
    super.init()
    let center = NotificationCenter.default
    if let mainWindow {
      center.addObserver(self, selector: #selector(mainWindowClosed(_:)), name: NSWindow.willCloseNotification,
                         object: mainWindow)
      center.addObserver(self, selector: #selector(mainWindowMiniaturized(_:)),
                         name: NSWindow.didMiniaturizeNotification, object: mainWindow)
    }
    center.addObserver(self, selector: #selector(appTerminating(_:)), name: NSApplication.willTerminateNotification,
                       object: nil)
  }

  func stop() {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func mainWindowClosed(_ note: Notification) { flight?.abort(.mainWindowClosed) }
  @objc private func mainWindowMiniaturized(_ note: Notification) { flight?.abort(.mainWindowMiniaturized) }
  @objc private func appTerminating(_ note: Notification) { flight?.abort(.appTerminating) }
}
