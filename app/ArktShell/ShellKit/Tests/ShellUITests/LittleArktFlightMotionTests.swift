import CoreGraphics
import Foundation
import ImageIO
import Motion
import Testing
import UniformTypeIdentifiers
import EngineAPI
@testable import ShellUI

/// The Open in flight as data (#352, docs/design/little-arkt.md, Motion): the snapshot card flies on `firmSlow` with
/// its position and mask size, the Today rows make room 200 ms in and the new row follows 90 ms later on
/// `springyFast`, the snapshot crossfades away in 0.1 s, and only a main window the user can see takes the flight.
struct LittleArktFlightMotionTests {
  private let card = CGRect(x: 6, y: 6, width: 468, height: 574)
  private let root = CGRect(x: 0, y: 0, width: 480, height: 620)
  private let target = CGRect(x: 250, y: 130, width: 660, height: 600)

  private func settle(_ start: LittleArktFlightScene, _ targets: [LittleArktFlightTarget],
                      at t: Double = 30) -> LittleArktFlightScene {
    var springs = LittleArktFlightSpringSet(scene: start)
    springs.apply(targets, at: 0)
    return springs.scene(at: t)
  }

  // MARK: Where the card starts

  @Test func atRestTheCardStartsAtItsFrameOnScreen() {
    let origin = CGPoint(x: 900, y: 200)
    let source = LittleArktFlightGeometry.visibleCard(card, in: root, scene: .rest, windowOrigin: origin)
    #expect(source == card.offsetBy(dx: 900, dy: 200))
  }

  /// Open in during the appear (prototype: Play > Interrupt) starts from where the appear has the card: scaled about
  /// the window's top center and lifted, so smaller, still centered, and higher.
  @Test func duringTheAppearTheCardStartsScaledAboutTheTopCenterAndLifted() {
    let scene = LittleArktScene([.lift: 10, .scale: 0.94, .opacity: 0.3])
    let source = LittleArktFlightGeometry.visibleCard(card, in: root, scene: scene, windowOrigin: .zero)
    #expect(abs(source.width - card.width * 0.94) < 0.001)
    #expect(abs(source.height - card.height * 0.94) < 0.001)
    #expect(abs(source.midX - root.midX) < 0.001, "the top center anchor keeps the card centered")
    // The top edge: the root's top stays put under the scale, the card's top gap shrinks, the lift raises it.
    let expectedTop = root.maxY - (root.maxY - card.maxY) * 0.94 + 10
    #expect(abs(source.maxY - expectedTop) < 0.001)
  }

  @Test func theStartSceneCarriesTheAppearsScaleAndOpacity() {
    let visible = CGRect(x: 100, y: 100, width: 468 * 0.96, height: 574 * 0.96)
    let start = LittleArktFlightMotion.start(visibleCard: visible, scale: 0.96, opacity: 0.4, snapshotReady: false)
    #expect(abs(start[.width] - 468) < 1e-9 && abs(start[.height] - 574) < 1e-9,
            "the unscaled size; the scale is its own channel")
    #expect(start[.centerX] == visible.midX && start[.centerY] == visible.midY)
    #expect(start[.scale] == 0.96 && start[.opacity] == 0.4)
    #expect(start[.image] == 0 && start[.room] == 0 && start[.row] == 0)
    #expect(LittleArktFlightMotion.start(visibleCard: visible, scale: 1, opacity: 1, snapshotReady: true)[.image] == 1)
  }

  // MARK: The flight

  @Test func theCardFliesOnFirmSlowToTheMainCard() {
    let targets = LittleArktFlightMotion.flight(to: target)
    let firmSlow = SpringPreset.firmSlow.parameters
    for channel in [LittleArktFlightChannel.centerX, .centerY, .width, .height, .scale] {
      #expect(targets.first { $0.channel == channel }?.parameters == firmSlow, "\(channel)")
    }
    #expect(targets.first { $0.channel == .opacity }?.parameters == SpringParameters(dampingRatio: 1, response: 0.16))
    let start = LittleArktFlightMotion.start(visibleCard: card, scale: 0.94, opacity: 0.5, snapshotReady: true)
    let end = settle(start, targets)
    #expect(end[.centerX] == target.midX && end[.centerY] == target.midY)
    #expect(end[.width] == target.width && end[.height] == target.height)
    #expect(end[.scale] == 1 && end[.opacity] == 1 && end[.image] == 1)
    #expect(LittleArktFlightMotion.cardRect(end) == target)
  }

  @Test func theTodayRowsMakeRoomAfter200MillisecondsAndTheNewRow90Later() {
    let targets = LittleArktFlightMotion.flight(to: target)
    let springyFast = SpringPreset.springyFast.parameters
    let room = targets.first { $0.channel == .room }
    let row = targets.first { $0.channel == .row }
    #expect(room?.parameters == springyFast && room?.delay == 0.2)
    #expect(row?.parameters == springyFast && row?.delay == 0.29)
    var springs = LittleArktFlightSpringSet(scene: .rest)
    springs.apply(targets, at: 0)
    #expect(springs.scene(at: 0.199)[.room] == 0, "the rows hold still for 200 ms")
    #expect(springs.scene(at: 0.289)[.row] == 0)
    #expect(springs.scene(at: 0.25)[.room] > 0)
    #expect(springs.scene(at: 30)[.room] == 1 && springs.scene(at: 30)[.row] == 1)
  }

  @Test func aLateSnapshotFadesInOnThePlate() {
    let fade = LittleArktFlightMotion.snapshotFadeIn
    #expect(fade.channel == .image && fade.value == 1)
    #expect(fade.parameters == SpringParameters(dampingRatio: 1, response: 0.16))
  }

  @Test func theSnapshotCrossfadesAwayInATenth() {
    let fade = LittleArktFlightMotion.crossfade
    #expect(fade.channel == .opacity && fade.value == 0)
    #expect(fade.parameters == SpringParameters(dampingRatio: 1, response: 0.10))
  }

  /// A retarget mid-flight continues from the current value: no jump.
  @Test func theFlightIsInterruptibleWithoutAJump() {
    var springs = LittleArktFlightSpringSet(
      scene: LittleArktFlightMotion.start(visibleCard: card, scale: 1, opacity: 1, snapshotReady: true))
    springs.apply(LittleArktFlightMotion.flight(to: target), at: 0)
    let mid = springs.scene(at: 0.1)
    let moved = target.offsetBy(dx: 80, dy: -40)
    springs.apply(LittleArktFlightMotion.flight(to: moved), at: 0.1)
    let after = springs.scene(at: 0.1001)
    #expect(abs(after[.centerX] - mid[.centerX]) < 0.5 && abs(after[.width] - mid[.width]) < 0.5)
    #expect(LittleArktFlightMotion.cardRect(springs.scene(at: 30)) == moved)
  }

  // MARK: Who takes the flight

  @Test(arguments: [
    (LittleArktFlightConditions(), true),
    (LittleArktFlightConditions(reduceMotion: true), false),
    (LittleArktFlightConditions(mainVisible: false), false),
    (LittleArktFlightConditions(mainMiniaturized: true), false),
    (LittleArktFlightConditions(mainOnActiveSpace: false), false),
    (LittleArktFlightConditions(mainFullScreen: true), false),
    (LittleArktFlightConditions(mainOnScreen: false), false),
  ])
  func onlyAMainWindowTheUserCanSeeTakesTheFlight(conditions: LittleArktFlightConditions, flies: Bool) {
    #expect(conditions.allowsFlight == flies)
  }

  // MARK: The rows making room

  @Test func theRowsBelowHoldTheirPlaceUntilTheRoomOpens() {
    let heights: [CGFloat] = [28, 34, 34, 34]
    let held = SidebarArrivalLayout.styles(rowHeights: heights, arrivalRow: 1, room: 0, appear: 0)
    #expect(held[0] == .rest, "rows above never move")
    #expect(held[1].alpha == 0 && abs(held[1].scale - 0.96) < 1e-9)
    #expect(held[2].offsetY == -34 && held[3].offsetY == -34, "rows below draw where they were")
    let half = SidebarArrivalLayout.styles(rowHeights: heights, arrivalRow: 1, room: 0.5, appear: 0.5)
    #expect(half[2].offsetY == -17 && half[1].alpha == 0.5 && abs(half[1].scale - 0.98) < 0.0001)
    let open = SidebarArrivalLayout.styles(rowHeights: heights, arrivalRow: 1, room: 1, appear: 1)
    #expect(open.allSatisfy { $0 == .rest })
  }

  // MARK: The snapshot image

  @Test func theSnapshotDecodesOffTheMainActorAtThePagesScale() async throws {
    let page = try Self.pageImage(width: 40, height: 20, scale: 2)
    let snapshot = try #require(await LittleArktSnapshot.decode(page))
    #expect(snapshot.image.width == 40 && snapshot.image.height == 20)
    #expect(snapshot.scale == 2)
    #expect(snapshot.pointSize == CGSize(width: 20, height: 10))
    #expect(await LittleArktSnapshot.decode(PageImage(data: Data([1, 2, 3]), pixelWidth: 1, pixelHeight: 1, scale: 1,
                                                      format: .png)) == nil)
  }

  private static func pageImage(width: Int, height: Int, scale: Double) throws -> PageImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
    context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return PageImage(data: data as Data, pixelWidth: width, pixelHeight: height, scale: scale, format: .png)
  }
}
