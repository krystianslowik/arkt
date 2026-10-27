import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The link status pill in the shell window (#114, BH-167, design/status-pill/README.md, direction A): the engine's
/// `.targetURLChanged` events drive it on a manual clock, so nothing here waits for time to pass.
@MainActor
final class StatusPillWindowTests: XCTestCase {
  /// A clock the test moves by hand; timers fire in order as it passes them.
  @MainActor
  private final class ManualClock {
    private(set) var time: TimeInterval = 1_000
    private var timers: [(id: Int, due: TimeInterval, fire: @MainActor () -> Void)] = []
    private var nextID = 0
    var pendingCount: Int { timers.count }

    func now() -> TimeInterval { time }

    func schedule(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
      nextID += 1
      let id = nextID
      timers.append((id, time + delay, fire))
      return { [weak self] in self?.timers.removeAll { $0.id == id } }
    }

    func advance(by seconds: TimeInterval) {
      let target = time + seconds
      while let next = timers.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
        timers.removeAll { $0.id == next.id }
        time = max(time, next.due)
        next.fire()
      }
      time = target
    }
  }

  private static let linkA = URL(string: "https://www.example.org/notices/2026/winter?utm=1")!
  private static let linkB = URL(string: "http://other.example.net/a")!

  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var clock: ManualClock!
  private var pointer: CGPoint?
  private var first: NodeID!
  private var second: NodeID!
  private var tab: TabID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    first = try sidebar.addTab(url: URL(string: "https://example.com/a")!, title: "A", in: .today(space))
    second = try sidebar.addTab(url: URL(string: "https://example.com/b")!, title: "B", in: .today(space))
    engine = InMemoryEngine()
    controller = ShellWindowController(engine: engine,
                                       sidebar: ModelSidebarSource(sidebar: sidebar, now: { .now }))
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    clock = ManualClock()
    pointer = nil
    let presenter = controller.statusPill
    presenter.now = { [clock] in clock!.now() }
    presenter.schedule = { [clock] delay, fire in clock!.schedule(delay, fire) }
    presenter.pointer = { [unowned self] _ in pointer }
    presenter.isMouseButtonDown = { false }
    presenter.reduceMotion = { true }
    presenter.drivesDisplayLink = false
    presenter.animatesOffscreen = true
    controller.activate(node: first)
    tab = try XCTUnwrap(controller.currentTab)
    controller.rootView.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws {
    controller.close()
  }

  private var card: ContentCardView { controller.rootView.card }
  private var pill: StatusPillView? { controller.statusPill.pill(for: tab) }

  // MARK: Delay and hide

  func testNothingShowsBeforeTheDelayThenTheHostAndTheRestAppear() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    XCTAssertNil(pill)
    clock.advance(by: 0.399)
    XCTAssertNil(pill, "0.4 s of resting on the link first")
    clock.advance(by: 0.002)
    let shown = try XCTUnwrap(pill)
    XCTAssertEqual(shown.hostLabel.attributedStringValue.string, "www.example.org")
    XCTAssertEqual(shown.restLabel.stringValue, "/notices/2026/winter?utm=1")
    XCTAssertEqual(shown.corner, .leading)
  }

  func testLeavingTheLinkBeforeTheDelayShowsNothingAndLeavesNoTimer() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.3)
    try engine.hoverTarget(tab, url: nil)
    clock.advance(by: 5)
    XCTAssertNil(pill)
    XCTAssertEqual(clock.pendingCount, 0)
  }

  func testLeavingHidesQuicklyAfterTheGraceAndNotBefore() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    XCTAssertNotNil(pill)
    try engine.hoverTarget(tab, url: nil)
    clock.advance(by: 0.099)
    XCTAssertNotNil(pill, "a gap between two close links does not blink it")
    clock.advance(by: 0.002)
    XCTAssertNil(pill)
    XCTAssertEqual(card.statusPillView?.layer?.opacity, 0, "fading out (0.09 s); hidden when the fade ends")
    XCTAssertNotNil(card.statusPillView?.layer?.animation(forKey: StatusPillView.fadeKey))
  }

  func testMovingBetweenLinksSwapsTheTextAtOnceWithoutAnyAnimation() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    shown.layer?.removeAllAnimations()
    let before = shown.layer?.animationKeys() ?? []

    try engine.hoverTarget(tab, url: Self.linkB)
    try engine.hoverTarget(tab, url: nil)               // the gap between two links
    try engine.hoverTarget(tab, url: Self.linkA)
    try engine.hoverTarget(tab, url: Self.linkB)

    XCTAssertTrue(pill === shown, "the same pill, not a new one")
    XCTAssertEqual(shown.hostLabel.attributedStringValue.string, "http://other.example.net")
    XCTAssertEqual(shown.layer?.animationKeys() ?? [], before, "no flicker: no fade, no move")
    XCTAssertEqual(shown.layer?.opacity, 1)
    clock.advance(by: 2)
    XCTAssertNotNil(pill, "it never went away")
  }

  func testANonHTTPSSchemeIsShownAndHTTPSHidesItAndAMouseButtonDownShowsNothing() throws {
    try engine.hoverTarget(tab, url: Self.linkB)
    clock.advance(by: 0.4)
    XCTAssertEqual(try XCTUnwrap(pill).hostLabel.attributedStringValue.string, "http://other.example.net")
    try engine.hoverTarget(tab, url: nil)
    clock.advance(by: 1)

    controller.statusPill.isMouseButtonDown = { true }
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 1)
    XCTAssertNil(pill, "nothing shows while a button is down (a drag)")
  }

  // MARK: Tabs

  func testItIsPerTabAndHidesWhenTheTabIsSwitchedAway() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    XCTAssertNotNil(pill)

    controller.activate(node: second)
    XCTAssertNil(controller.statusPill.pill(for: tab))
    XCTAssertTrue(card.statusPillView?.isHidden == true, "gone at once, not faded behind the other page")
    let secondTab = try XCTUnwrap(controller.currentTab)
    XCTAssertNil(controller.statusPill.pill(for: secondTab))

    controller.activate(node: first)
    clock.advance(by: 5)
    XCTAssertNil(pill, "it does not come back on its own: the engine reports the next link")
    try engine.hoverTarget(tab, url: nil)
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    XCTAssertNotNil(pill)
  }

  func testAHoverReportedForATabThatIsNotShownDrawsNothing() throws {
    controller.activate(node: second)
    let secondTab = try XCTUnwrap(controller.currentTab)
    controller.activate(node: first)
    try engine.hoverTarget(secondTab, url: Self.linkA)
    clock.advance(by: 1)
    XCTAssertNil(controller.statusPill.pill(for: secondTab))
    XCTAssertNil(pill)
    XCTAssertEqual(clock.pendingCount, 0)
  }

  func testClosingTheWindowStopsTheTimers() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    XCTAssertEqual(clock.pendingCount, 1)
    controller.close()
    XCTAssertEqual(clock.pendingCount, 0)
    XCTAssertFalse(controller.statusPill.hasPendingTimerForTesting)
  }

  // MARK: Pointer

  func testThePillCrossesToTheOtherCornerWhenThePointerComesWithinTwentyEightPoints() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    card.layoutSubtreeIfNeeded()
    let leading = shown.frame
    XCTAssertEqual(leading.minX, StatusPillGeometry.inset)
    XCTAssertEqual(leading.minY, StatusPillGeometry.inset)
    XCTAssertEqual(leading.height, 26)

    controller.statusPill.pointerMoved(to: CGPoint(x: leading.maxX + 29, y: leading.midY), in: card)
    XCTAssertEqual(shown.corner, .leading, "29 pt away: it stays")
    controller.statusPill.pointerMoved(to: CGPoint(x: leading.maxX + 27, y: leading.midY), in: card)
    XCTAssertEqual(shown.corner, .trailing)
    XCTAssertEqual(shown.frame.maxX, card.bounds.maxX - StatusPillGeometry.inset)
    XCTAssertEqual(shown.frame.minY, StatusPillGeometry.inset)

    controller.statusPill.pointerMoved(to: CGPoint(x: leading.midX, y: leading.midY), in: card)
    XCTAssertEqual(shown.corner, .trailing, "it stays there until the pointer comes near it again")
    controller.statusPill.pointerMoved(to: CGPoint(x: shown.frame.midX, y: shown.frame.midY), in: card)
    XCTAssertEqual(shown.corner, .leading)
  }

  func testAPillThatWouldAppearUnderThePointerAppearsInTheOtherCorner() throws {
    pointer = CGPoint(x: 60, y: 25)
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    XCTAssertEqual(try XCTUnwrap(pill).corner, .trailing)
  }

  /// The card's tracking area may not reach the pointer over the page view: while the pill is up, the presenter samples
  /// the pointer on its own tick, and only then.
  func testASamplerFollowsThePointerWhileThePillIsUpAndStopsWhenItIsGone() throws {
    XCTAssertEqual(clock.pendingCount, 0)
    try engine.hoverTarget(tab, url: Self.linkA)
    XCTAssertEqual(clock.pendingCount, 1, "only the show timer: no sampling before the pill is up")
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    XCTAssertEqual(clock.pendingCount, 1, "the sampler is armed")
    card.layoutSubtreeIfNeeded()

    pointer = CGPoint(x: shown.frame.midX, y: shown.frame.midY)
    clock.advance(by: 0.1)                              // no mouse-moved event at all
    XCTAssertEqual(shown.corner, .trailing)

    try engine.hoverTarget(tab, url: nil)
    clock.advance(by: 0.2)
    XCTAssertNil(pill)
    XCTAssertEqual(clock.pendingCount, 0, "no work at all once it is hidden")
  }

  func testTheCardFollowsThePointerWithAMouseMovedTrackingArea() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    XCTAssertTrue(card.trackingAreas.contains { $0.options.contains(.mouseMoved) && $0.owner === card })
    XCTAssertNotNil(card.onPointerMoved)
  }

  // MARK: Never in the way

  func testItNeverTakesAClickAndIsOutOfTheAccessibilityTree() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    card.layoutSubtreeIfNeeded()

    let centerInCard = shown.convert(NSPoint(x: shown.bounds.midX, y: shown.bounds.midY), to: card)
    let hit = card.hitTest(card.convert(centerInCard, to: card.superview))
    XCTAssertFalse(hit === shown || hit?.isDescendant(of: shown) == true, "hit testing passes through: \(String(describing: hit))")
    XCTAssertNil(shown.hitTest(NSPoint(x: shown.bounds.midX, y: shown.bounds.midY)))
    XCTAssertFalse(shown.acceptsFirstResponder)

    XCTAssertFalse(shown.isAccessibilityElement())
    XCTAssertTrue(shown.isAccessibilityHidden())
    XCTAssertEqual((shown.accessibilityChildren() ?? []).count, 0)
    XCTAssertFalse(shown.hostLabel.isAccessibilityElement())
    XCTAssertFalse(shown.restLabel.isAccessibilityElement())
  }

  func testItNeverCoversThePageViewsFrameOrChangesIt() throws {
    let page = try XCTUnwrap(engine.contentView(for: tab))
    let frame = page.frame
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    card.layoutSubtreeIfNeeded()
    XCTAssertEqual(page.frame, frame)
    XCTAssertTrue(card.subviews.contains { $0 === card.statusPillView })
    let pillView = try XCTUnwrap(card.statusPillView)
    XCTAssertTrue(pillView.frame.maxX <= card.bounds.width * 0.62 + StatusPillGeometry.inset)
  }

  // MARK: Motion

  func testReduceMotionFadesWithoutAnyMovement() throws {
    controller.statusPill.reduceMotion = { true }
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    let keys = shown.layer?.animationKeys() ?? []
    XCTAssertTrue(keys.contains(StatusPillView.fadeKey), "\(keys)")
    XCTAssertFalse(keys.contains(StatusPillView.riseKey), "no movement under Reduce Motion: \(keys)")

    shown.layer?.removeAllAnimations()
    controller.statusPill.pointerMoved(to: CGPoint(x: shown.frame.midX, y: shown.frame.midY), in: card)
    XCTAssertEqual(shown.corner, .trailing)
    XCTAssertFalse(shown.isSliding, "the crossing is a cross-fade, not a slide")
    XCTAssertEqual(shown.slideOffset, 0)
    XCTAssertNotNil(shown.layer?.animation(forKey: StatusPillView.crossKey), "out, move, in")
  }

  func testWithMotionItRisesAndCrossingSlidesOnASteppedSpringFromWhereItWas() throws {
    controller.statusPill.reduceMotion = { false }
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    XCTAssertTrue(shown.layer?.animationKeys()?.contains(StatusPillView.riseKey) == true)
    card.layoutSubtreeIfNeeded()
    let leadingX = shown.frame.minX

    var time: CFTimeInterval = 5_000
    shown.now = { time }
    controller.statusPill.pointerMoved(to: CGPoint(x: shown.frame.midX, y: shown.frame.midY), in: card)
    XCTAssertEqual(shown.corner, .trailing)
    XCTAssertTrue(shown.isSliding)
    let restX = shown.frame.minX
    XCTAssertEqual(shown.slideOffset, leadingX - restX, accuracy: 0.001, "it starts where it was")

    time += 0.05
    shown.stepSlide(at: time)
    XCTAssertTrue(shown.slideOffset < 0 && shown.slideOffset > leadingX - restX, "mid-crossing: \(shown.slideOffset)")

    // The pointer chases it back before it lands: the new crossing starts from the offset reached, not from rest.
    let reached = shown.slideOffset
    controller.statusPill.pointerMoved(to: CGPoint(x: shown.frame.midX, y: shown.frame.midY), in: card)
    XCTAssertEqual(shown.corner, .leading)
    let newRest = shown.frame.minX
    XCTAssertEqual(shown.slideOffset, (restX + reached) - newRest, accuracy: 0.001, "retargeted from the present place")

    time += 10
    shown.stepSlide(at: time)
    XCTAssertEqual(shown.slideOffset, 0)
    XCTAssertFalse(shown.isSliding)
    XCTAssertEqual(shown.frame.minX, leadingX)
  }

  // MARK: Look

  func testItUsesTheBrandSurfaceInLightAndDarkAndAHairlineUnderIncreaseContrast() throws {
    try engine.hoverTarget(tab, url: Self.linkA)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    for (name, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      shown.appearance = NSAppearance(named: name)
      XCTAssertEqual(shown.layer?.backgroundColor, BrandTokens.surfaceBrand.resolve(flavor).cgColor, "\(flavor)")
      XCTAssertEqual(shown.layer?.cornerRadius, 13)
      XCTAssertEqual(shown.layer?.shadowRadius, ShellTokens.toastShadow.radius)
    }
    shown.increaseContrast = { true }
    shown.appearance = NSAppearance(named: .aqua)
    XCTAssertEqual(shown.layer?.borderWidth, 1)
    XCTAssertEqual(shown.layer?.borderColor, BrandTokens.brandHairlineContrast.light.cgColor)
  }

  func testAVeryLongAddressTruncatesTheMiddleOfThePathAndNeverWidensThePill() throws {
    let long = URL(string: "https://www.example.org/" + String(repeating: "segment/", count: 40) + "end?x=" +
                   String(repeating: "q", count: 200))!
    try engine.hoverTarget(tab, url: long)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    card.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(shown.frame.width, StatusPillGeometry.maxWidth)
    XCTAssertEqual(shown.restLabel.lineBreakMode, .byTruncatingMiddle)
    XCTAssertEqual(shown.hostLabel.attributedStringValue.string, "www.example.org")
    XCTAssertFalse(shown.restLabel.isHidden)
  }

  func testAHostTooWideForThePillTruncatesItselfAndDropsTheRest() throws {
    let host = String(repeating: "a", count: 90) + ".example"
    try engine.hoverTarget(tab, url: URL(string: "https://\(host)/path")!)
    clock.advance(by: 0.4)
    let shown = try XCTUnwrap(pill)
    card.layoutSubtreeIfNeeded()
    XCTAssertEqual(shown.hostLabel.attributedStringValue.string, host, "the full host is the label's text")
    XCTAssertEqual(shown.hostLabel.lineBreakMode, .byTruncatingMiddle)
    XCTAssertTrue(shown.restLabel.isHidden)
    XCTAssertLessThanOrEqual(shown.frame.width, StatusPillGeometry.maxWidth)
  }
}
