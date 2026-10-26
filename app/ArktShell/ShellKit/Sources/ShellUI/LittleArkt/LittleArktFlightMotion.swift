import AppKit
import Motion

// MARK: - Channels

/// One animated scalar of the Open in flight (#352, docs/design/little-arkt.md, Motion). The card is the snapshot on
/// its plate, on the overlay window: its center and unscaled size (the mask) in the overlay's coordinates, its scale
/// and opacity; `image` is the snapshot's opacity on the plate; `room` and `row` are the main window's Today rows
/// making room and the new row fading in, on the same clock.
public enum LittleArktFlightChannel: Int, SpringChannel {
  case centerX, centerY, width, height
  case scale, opacity
  case image
  case room, row

  public var springScale: Double {
    switch self {
    case .centerX, .centerY, .width, .height: 1
    case .scale, .opacity, .image, .room, .row: 1000
    }
  }

  public var restValue: Double {
    switch self {
    case .scale, .opacity: 1
    case .centerX, .centerY, .width, .height, .image, .room, .row: 0
    }
  }
}

public typealias LittleArktFlightScene = ChannelScene<LittleArktFlightChannel>
public typealias LittleArktFlightTarget = ChannelTarget<LittleArktFlightChannel>
public typealias LittleArktFlightSpringSet = SpringChannelSet<LittleArktFlightChannel>

// MARK: - Motion

/// The flight's motion table, as data.
public enum LittleArktFlightMotion {
  /// The Today rows start making room this long after the flight starts.
  public static let roomDelay = 0.2
  /// The new row fades in this long after the flight starts: 90 ms after the rows start moving.
  public static let rowDelay = 0.29
  /// The new row grows from this scale while it fades in.
  public static let rowStartScale = 0.96

  static func critical(_ seconds: Double) -> SpringParameters { SpringParameters(dampingRatio: 1, response: seconds) }

  /// The first frame: the card where the window shows it now (`visibleCard`, scaled by `scale` about its center),
  /// at the window's opacity, with the snapshot on it when it was ready in time, else its plate alone.
  public static func start(visibleCard: CGRect, scale: Double, opacity: Double,
                           snapshotReady: Bool) -> LittleArktFlightScene {
    let s = max(scale, 0.01)
    return LittleArktFlightScene([
      .centerX: visibleCard.midX, .centerY: visibleCard.midY,
      .width: visibleCard.width / s, .height: visibleCard.height / s,
      .scale: scale, .opacity: opacity, .image: snapshotReady ? 1 : 0, .room: 0, .row: 0,
    ])
  }

  /// The card's position, mask and scale on `firmSlow` to `target`, its opacity back to 1; the rows make room after
  /// 200 ms and the new row follows 90 ms later, both on `springyFast`.
  public static func flight(to target: CGRect) -> [LittleArktFlightTarget] {
    let firmSlow = SpringPreset.firmSlow.parameters
    let springyFast = SpringPreset.springyFast.parameters
    return [
      LittleArktFlightTarget(.centerX, target.midX, firmSlow), LittleArktFlightTarget(.centerY, target.midY, firmSlow),
      LittleArktFlightTarget(.width, target.width, firmSlow), LittleArktFlightTarget(.height, target.height, firmSlow),
      LittleArktFlightTarget(.scale, 1, firmSlow), LittleArktFlightTarget(.opacity, 1, critical(0.16)),
      LittleArktFlightTarget(.room, 1, springyFast, delay: roomDelay),
      LittleArktFlightTarget(.row, 1, springyFast, delay: rowDelay),
    ]
  }

  /// A snapshot that missed the first frame fades in on the plate.
  public static let snapshotFadeIn = LittleArktFlightTarget(.image, 1, critical(0.16))
  /// After the page's first frame in the main card, the snapshot crossfades away.
  public static let crossfade = LittleArktFlightTarget(.opacity, 0, critical(0.10))

  /// The card as drawn: its mask scaled about its center.
  public static func cardRect(_ scene: LittleArktFlightScene) -> CGRect {
    let width = scene[.width] * scene[.scale]
    let height = scene[.height] * scene[.scale]
    return CGRect(x: scene[.centerX] - width / 2, y: scene[.centerY] - height / 2, width: width, height: height)
  }
}

// MARK: - Geometry

public enum LittleArktFlightGeometry {
  /// Where `card` (in the root view, y up) shows on screen under the window content's transform for `scene`
  /// (`LittleArktMotion.transform`: scale about the top center, then the lift).
  public static func visibleCard(_ card: CGRect, in rootBounds: CGRect, scene: LittleArktScene,
                                 windowOrigin: CGPoint) -> CGRect {
    let transform = CATransform3DGetAffineTransform(LittleArktMotion.transform(for: scene, in: rootBounds))
    return card.applying(transform).offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
  }
}

// MARK: - Who takes the flight

/// What the flight needs from the main window: one the user can see on this desktop, not minimized or in full screen,
/// and motion not reduced. Otherwise Open in takes today's path (the small window fades out, then the page moves).
public struct LittleArktFlightConditions: Equatable, Sendable, CustomStringConvertible {
  public var reduceMotion = false
  public var mainVisible = true
  public var mainMiniaturized = false
  public var mainOnActiveSpace = true
  public var mainFullScreen = false
  /// The main window is on a display (a window off every screen has none).
  public var mainOnScreen = true

  public init(reduceMotion: Bool = false, mainVisible: Bool = true, mainMiniaturized: Bool = false,
              mainOnActiveSpace: Bool = true, mainFullScreen: Bool = false, mainOnScreen: Bool = true) {
    self.reduceMotion = reduceMotion
    self.mainVisible = mainVisible
    self.mainMiniaturized = mainMiniaturized
    self.mainOnActiveSpace = mainOnActiveSpace
    self.mainFullScreen = mainFullScreen
    self.mainOnScreen = mainOnScreen
  }

  /// `window`'s state now.
  @MainActor
  public init(window: NSWindow) {
    self.init(mainVisible: window.isVisible, mainMiniaturized: window.isMiniaturized,
              mainOnActiveSpace: window.isOnActiveSpace, mainFullScreen: window.styleMask.contains(.fullScreen),
              mainOnScreen: window.screen != nil)
  }

  public var allowsFlight: Bool {
    !reduceMotion && mainVisible && !mainMiniaturized && mainOnActiveSpace && !mainFullScreen && mainOnScreen
  }

  public var description: String {
    "reduceMotion \(reduceMotion), visible \(mainVisible), minimized \(mainMiniaturized), "
      + "active space \(mainOnActiveSpace), full screen \(mainFullScreen), on screen \(mainOnScreen)"
  }
}
