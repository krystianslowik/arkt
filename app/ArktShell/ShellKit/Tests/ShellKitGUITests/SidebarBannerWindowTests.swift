import AppKit
import CoreBridge
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The sidebar banner in a real window (#648, design/sidebar-banner): one 34 pt row above the bottom bar that never
/// covers rows (the row list shrinks and fades instead), Restart and the hover close, the announcement popover, the
/// smallest window, and the Reduce Motion variant.
@MainActor
final class SidebarBannerWindowTests: XCTestCase {
  private static let update = SidebarNotice.update(version: "1.4.2")
  /// The design's worst case: a 90-character title.
  private static let announcement = SidebarNotice.announcement(
    id: "archive-search",
    title: "Archived tabs can now be searched by what was on the page, not only by their title, at last",
    body: "Open the Archive and type a few words you remember. It works for tabs archived from today on; older ones "
      + "are indexed in the background over the next few days.",
    actionTitle: "Open Archive")

  private var controllers: [ShellWindowController] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for controller in controllers { controller.close() }
    controllers = []
  }

  @MainActor
  private struct Harness {
    let controller: ShellWindowController
    let source: ManualSidebarNoticeSource
    let model: SidebarBannerModel
    let center: SidebarBannerCenter
    var container: SidebarContainerView { controller.sidebarController.view }
    var banner: SidebarBannerView { container.banner }
    var attachment: SidebarBannerAttachment? { center.attachment(of: controller) }
  }

  /// One Space whose Today holds `tabs` rows, then a Space with two: with 30 the first page's rows run past the
  /// window's bottom, so they reach the banner's fade.
  private static func sidebar(tabs: Int) -> (StubSidebar, SpaceID, SpaceID) {
    let stub = StubSidebar()
    let first = stub.addSpace(title: "Long")
    let second = stub.addSpace(title: "Short")
    for index in 0..<tabs {
      _ = stub.addTab(url: URL(string: "https://example.com/\(index)")!, title: "Tab \(index)", in: .today(first))
    }
    for index in 0..<2 {
      _ = stub.addTab(url: URL(string: "https://example.org/\(index)")!, title: "Short \(index)", in: .today(second))
    }
    return (stub, first, second)
  }

  private func makeHarness(_ notices: [SidebarNotice] = [], reduceMotion: Bool = false,
                           sidebar: StubSidebar = SidebarBannerWindowTests.sidebar(tabs: 30).0) -> Harness {
    let source = ManualSidebarNoticeSource(notices: notices)
    let model = SidebarBannerModel(source: source, dismissals: .ephemeral()) { _, _ in }
    model.reduceMotion = { reduceMotion }
    let center = SidebarBannerCenter(model: model)
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: sidebar)
    controllers.append(controller)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1080, height: 720), display: false)
    center.attach(to: controller)
    controller.rootView.layoutSubtreeIfNeeded()
    return Harness(controller: controller, source: source, model: model, center: center)
  }

  private func rowFrame(_ harness: Harness) -> NSRect {
    harness.banner.convert(harness.banner.row.frame, to: harness.container)
  }

  func testNoNoticeLeavesTheSidebarAsItWas() {
    let harness = makeHarness()
    XCTAssertTrue(harness.banner.isHidden)
    XCTAssertEqual(harness.container.pager.frame.maxY, harness.container.bottomBar.frame.minY)
    XCTAssertNil(harness.container.pager.layer?.mask, "no fade without a banner")
    XCTAssertNil(harness.banner.hitTest(NSPoint(x: harness.banner.frame.midX, y: harness.banner.frame.midY)))
  }

  func testAnUpdateIsOneTabRowAboveTheBottomBarAndTheRowsMakeRoom() throws {
    let harness = makeHarness([Self.update])
    let row = rowFrame(harness)
    XCTAssertFalse(harness.banner.isHidden)
    XCTAssertEqual(row.height, 34)
    XCTAssertEqual(row.maxY, harness.container.bottomBar.frame.minY - 6, accuracy: 0.5)
    XCTAssertEqual(row.minX, SidebarMetrics.horizontalPadding)
    XCTAssertEqual(row.width, harness.container.bounds.width - 2 * SidebarMetrics.horizontalPadding)
    XCTAssertEqual(harness.container.pager.frame.maxY, row.minY, accuracy: 0.5, "the rows end above the banner")
    XCTAssertTrue(harness.container.pager.layer?.mask === harness.container.bannerSlot.fade, "the rows fade out")
    XCTAssertEqual(harness.banner.label.stringValue, "Update")
    XCTAssertNotNil(NSImage(systemSymbolName: SidebarBannerView.updateSymbol, accessibilityDescription: nil))
    XCTAssertFalse(harness.banner.label.isHidden)
    XCTAssertFalse(harness.banner.restartButton.isHidden)
    XCTAssertTrue(harness.banner.chevron.isHidden)
    XCTAssertEqual(harness.banner.restartButton.frame.height, 22)
    XCTAssertEqual(harness.banner.restartButton.style, .primary, "the one mustard pill")
    XCTAssertGreaterThanOrEqual(harness.banner.restartButton.frame.minX, harness.banner.label.frame.maxX + 8)
  }

  func testVoiceOverLabelsAndNoFocusIsTaken() throws {
    let harness = makeHarness()
    let window = try XCTUnwrap(harness.controller.window)
    let before = window.firstResponder
    harness.source.notices = [Self.update]
    XCTAssertTrue(window.firstResponder === before, "a notice never takes focus")
    XCTAssertEqual(harness.banner.accessibilityRole(), .group)
    XCTAssertEqual(harness.banner.accessibilityLabel(), "Update ready")
    XCTAssertEqual(harness.banner.accessibilityIdentifier(), AXID.SidebarBanner.root)
    XCTAssertEqual(harness.banner.restartButton.accessibilityLabel(), "Restart to update")
    XCTAssertEqual(harness.banner.closeButton.accessibilityLabel(), "Dismiss notice")
    XCTAssertFalse(harness.banner.closeButton.isHidden, "Dismiss stays reachable without a pointer")
    XCTAssertFalse(harness.banner.row.isAccessibilityElement(), "an update row is not a button")
  }

  /// The views the window's key view loop visits from its content view, in order (one lap).
  private func keyViewLoop(_ window: NSWindow) -> [NSView] {
    window.recalculateKeyViewLoop()
    guard let start = window.contentView else { return [] }
    var loop: [NSView] = []
    var view = start.nextKeyView
    while let current = view, current !== start, !loop.contains(where: { $0 === current }), loop.count < 500 {
      loop.append(current)
      view = current.nextKeyView
    }
    return loop
  }

  /// Restart and the close button are in the window's key view loop and take keyboard focus; Tab reaches them with
  /// Full Keyboard Access on. The close button shows while it has focus, and hides again when focus leaves.
  func testAnUpdatesControlsAreInTheKeyViewLoopAndTheCloseShowsWithFocus() throws {
    let harness = makeHarness([Self.update], reduceMotion: true)
    let window = try XCTUnwrap(harness.controller.window)
    let banner = harness.banner
    let loop = keyViewLoop(window)
    XCTAssertTrue(loop.contains { $0 === banner.restartButton }, "Restart is in the key view loop")
    XCTAssertTrue(loop.contains { $0 === banner.closeButton }, "the close button is in the key view loop")
    XCTAssertTrue(banner.restartButton.acceptsFirstResponder)
    XCTAssertTrue(banner.closeButton.acceptsFirstResponder)
    XCTAssertFalse(banner.closeButton.isShown, "hidden at rest")
    let close = NSPoint(x: banner.closeButton.frame.midX, y: banner.closeButton.frame.midY)
    if NSApp.isFullKeyboardAccessEnabled {
      XCTAssertTrue(banner.closeButton.canBecomeKeyView)
      XCTAssertTrue(banner.restartButton.canBecomeKeyView)
      XCTAssertTrue(window.makeFirstResponder(banner.closeButton))
    } else {
      // Without Full Keyboard Access (the CI runners) buttons refuse Tab, as everywhere in macOS; the responder
      // call is made directly.
      XCTAssertTrue(banner.closeButton.becomeFirstResponder())
    }
    XCTAssertTrue(banner.closeButton.isShown, "keyboard focus shows the close button")
    XCTAssertTrue(banner.hitTest(banner.convert(close, to: harness.container)) === banner.closeButton)
    XCTAssertTrue(banner.closeButton.keyboardFocusRing.isFocused, "the close button draws the focus ring")
    if NSApp.isFullKeyboardAccessEnabled {
      XCTAssertTrue(window.makeFirstResponder(nil))
    } else {
      XCTAssertTrue(banner.closeButton.resignFirstResponder())
    }
    XCTAssertFalse(banner.closeButton.isShown, "hidden again without focus or hover")
  }

  /// An announcement's row is a button in the key view loop; Space opens its popover.
  func testAnAnnouncementsRowIsInTheKeyViewLoopAndSpaceOpensThePopover() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    let window = try XCTUnwrap(harness.controller.window)
    let row = harness.banner.row
    // A click on the row opens the popover but never takes the keyboard: the window asks during the mouse down.
    for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
      XCTAssertFalse(SidebarBannerRowView.acceptsFocus(isAnnouncement: true, during: type), "\(type)")
    }
    XCTAssertTrue(SidebarBannerRowView.acceptsFocus(isAnnouncement: true, during: .keyDown))
    XCTAssertTrue(SidebarBannerRowView.acceptsFocus(isAnnouncement: true, during: nil))
    XCTAssertFalse(SidebarBannerRowView.acceptsFocus(isAnnouncement: false, during: .keyDown), "an update row")
    let loop = keyViewLoop(window)
    XCTAssertTrue(loop.contains { $0 === row }, "the row is in the key view loop")
    XCTAssertTrue(loop.contains { $0 === harness.banner.closeButton })
    XCTAssertTrue(row.acceptsFirstResponder)
    XCTAssertEqual(row.canBecomeKeyView, NSApp.isFullKeyboardAccessEnabled, "Tab reaches it as it reaches buttons")
    XCTAssertTrue(window.makeFirstResponder(row))
    XCTAssertTrue(row.keyboardFocusRing.isFocused, "the row draws the focus ring")
    let space = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    row.keyDown(with: space)
    XCTAssertEqual(harness.attachment?.popover.isShown, true)
    harness.attachment?.popover.hide()
  }

  /// Focuses the close button through the window when Full Keyboard Access lets it take focus; otherwise (CI) the
  /// announcement's row, which takes focus either way. Returns the focused view.
  private func focusInsideTheBanner(_ harness: Harness, _ window: NSWindow) throws -> NSView {
    if window.makeFirstResponder(harness.banner.closeButton) { return harness.banner.closeButton }
    let row = harness.banner.row
    XCTAssertTrue(row.isAnnouncement, "without Full Keyboard Access the test needs the announcement's row")
    XCTAssertTrue(window.makeFirstResponder(row))
    return row
  }

  /// The banner leaving with motion hands keyboard focus back to the window as it starts to fade, so no ring sits on
  /// the fading banner.
  func testDismissingWithMotionGivesFocusBackToTheWindow() throws {
    let harness = makeHarness([Self.announcement])
    let window = try XCTUnwrap(harness.controller.window)
    let focused = try focusInsideTheBanner(harness, window)
    XCTAssertTrue(window.firstResponder === focused)
    harness.source.notices = []
    XCTAssertTrue(window.firstResponder === window, "focus goes back as the fade starts")
    harness.container.finishBannerMotionForTesting()
    XCTAssertTrue(window.firstResponder === window)
  }

  /// The banner taken away at once (no motion) hands keyboard focus back to the window.
  func testHidingAtOnceGivesFocusBackToTheWindow() throws {
    let harness = makeHarness([Self.announcement])
    let window = try XCTUnwrap(harness.controller.window)
    _ = try focusInsideTheBanner(harness, window)
    harness.container.setBanner(nil, animated: false, reduceMotion: false)
    harness.container.finishBannerMotionForTesting()
    XCTAssertTrue(harness.banner.isHidden)
    XCTAssertTrue(window.firstResponder === window, "focus is not left on a hidden control")
  }

  /// A notice swapped in place gives focus back when the focused control goes away: the announcement's row becomes
  /// an update's (no focus), and Restart is hidden for an announcement.
  func testANoticeSwappedInPlaceGivesUpFocusOnAControlThatGoes() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    let window = try XCTUnwrap(harness.controller.window)
    XCTAssertTrue(window.makeFirstResponder(harness.banner.row))
    harness.source.notices = [Self.update]
    XCTAssertEqual(harness.banner.notice, Self.update, "swapped in place")
    XCTAssertTrue(window.firstResponder === window, "the update's row takes no focus")
    if window.makeFirstResponder(harness.banner.restartButton) {      // Full Keyboard Access on
      harness.source.notices = [Self.announcement]
      XCTAssertTrue(harness.banner.restartButton.isHidden)
      XCTAssertTrue(window.firstResponder === window, "no focus on the hidden Restart")
    }
    // The close button stays: a swap keeps its focus.
    if window.makeFirstResponder(harness.banner.closeButton) {
      harness.source.notices = [Self.update]
      XCTAssertTrue(window.firstResponder === harness.banner.closeButton)
    }
  }

  func testRestartGoesToTheSource() {
    let harness = makeHarness([Self.update])
    harness.banner.restartButton.performClick(nil)
    XCTAssertEqual(harness.source.performed, [Self.update])
  }

  func testHoverShowsTheCloseButtonAtTheTopLeadingCornerAndItDismisses() {
    let harness = makeHarness([Self.update], reduceMotion: true)
    let banner = harness.banner
    let closeCenter = NSPoint(x: banner.closeButton.frame.midX, y: banner.closeButton.frame.midY)
    let inSuperview = banner.convert(closeCenter, to: harness.container)
    XCTAssertFalse(banner.hitTest(inSuperview) === banner.closeButton, "hidden until hovered")
    banner.setHovered(true)
    XCTAssertEqual(banner.closeButton.alphaValue, 1)
    XCTAssertTrue(banner.hitTest(inSuperview) === banner.closeButton)
    let row = banner.row.frame
    XCTAssertEqual(banner.closeButton.frame.size, NSSize(width: 18, height: 18))
    XCTAssertEqual(banner.closeButton.frame.minX, row.minX - 6)
    XCTAssertEqual(banner.closeButton.frame.minY, row.minY - 6)
    banner.closeButton.performClick(nil)
    XCTAssertNil(harness.model.current)
    XCTAssertTrue(harness.model.dismissals.contains(Self.update.id))
    XCTAssertEqual(harness.container.pager.frame.maxY, harness.container.bottomBar.frame.minY, "the rows settle")
  }

  func testAppearingWithMotionRisesAndTheRowsMakeRoomOnTheSameCurve() throws {
    let harness = makeHarness()
    let fullHeight = harness.container.pager.frame.height
    harness.source.notices = [Self.update]
    let layer = try XCTUnwrap(harness.banner.layer)
    let rise = try XCTUnwrap(layer.animation(forKey: "bannerRise") as? CABasicAnimation)
    XCTAssertEqual(rise.duration, 0.24)
    XCTAssertNotNil(layer.animation(forKey: "bannerFade"))
    // The row starts 8 pt below its place on screen.
    let offset = try XCTUnwrap(rise.fromValue as? CGFloat)
    let rest = screenMinY(harness.banner)
    layer.transform = CATransform3DMakeTranslation(0, offset, 0)
    let start = screenMinY(harness.banner)
    layer.transform = CATransform3DIdentity
    XCTAssertEqual(rest - start, 8, accuracy: 0.5, "starts below (screen y grows upward)")
    // The rows keep their frame while their mask moves; the frame follows when the motion ends.
    XCTAssertEqual(harness.container.pager.frame.height, fullHeight)
    let fade = harness.container.bannerSlot.fade
    XCTAssertNotNil(fade.animation(forKey: "banner.bounds"))
    XCTAssertEqual(fade.frame.height, fullHeight - SidebarBannerMetrics.reservedHeight)
    harness.container.finishBannerMotionForTesting()
    XCTAssertEqual(harness.container.pager.frame.height, fullHeight - SidebarBannerMetrics.reservedHeight)
    XCTAssertEqual(fade.frame.height, harness.container.pager.bounds.height)
  }

  func testTheFadeMaskCoversTheTopOfTheRowsOnScreen() throws {
    let harness = makeHarness([Self.update])
    let pager = harness.container.pager
    let fade = harness.container.bannerSlot.fade
    let window = try XCTUnwrap(harness.controller.window)
    let root = try XCTUnwrap(window.contentView?.layer)
    let maskInRoot = try XCTUnwrap(pager.layer).convert(fade.frame, to: root)
    let pagerInWindow = pager.convert(pager.bounds, to: nil)
    let contentFlipped = window.contentView?.isFlipped == true
    let maskMinY = contentFlipped ? root.bounds.height - maskInRoot.maxY : maskInRoot.minY
    XCTAssertEqual(maskMinY, pagerInWindow.minY, accuracy: 0.5)
    XCTAssertEqual(maskInRoot.height, pagerInWindow.height, accuracy: 0.5)
  }

  func testReduceMotionFadesOnlyAndTheRowsJump() throws {
    let harness = makeHarness(reduceMotion: true)
    let fullHeight = harness.container.pager.frame.height
    harness.source.notices = [Self.update]
    let layer = try XCTUnwrap(harness.banner.layer)
    XCTAssertNil(layer.animation(forKey: "bannerRise"), "no movement")
    XCTAssertNotNil(layer.animation(forKey: "bannerFade"))
    XCTAssertEqual(harness.container.pager.frame.height, fullHeight - SidebarBannerMetrics.reservedHeight)
    XCTAssertNil(harness.container.bannerSlot.fade.animation(forKey: "banner.bounds"))
    harness.source.notices = []
    XCTAssertEqual(harness.container.pager.frame.height, fullHeight)
    XCTAssertNil(harness.container.bannerSlot.fade.animation(forKey: "banner.bounds"))
  }

  func testDismissWithMotionFadesAndTheRowsSettle() throws {
    let harness = makeHarness([Self.update])
    let fullHeight = harness.container.pager.frame.height + SidebarBannerMetrics.reservedHeight
    harness.model.dismiss()
    XCTAssertEqual(harness.container.pager.frame.height, fullHeight)
    XCTAssertEqual(harness.banner.alphaValue, 0, "fading out")
    XCTAssertNil(harness.banner.hitTest(NSPoint(x: harness.banner.frame.midX, y: harness.banner.frame.midY)))
    XCTAssertNotNil(harness.container.bannerSlot.fade.animation(forKey: "banner.bounds"))
    XCTAssertEqual((harness.banner.layer?.animation(forKey: "bannerFade") as? CABasicAnimation)?.duration, 0.15)
  }

  func testTheSmallestWindowKeepsTheGlyphAndAFullWidthRestart() {
    let container = SidebarContainerView(source: StubSidebar.sample())
    container.frame = NSRect(x: 0, y: 0, width: ShellMetrics.standard.sidebarMinWidth, height: 420)
    container.setBanner(Self.update, animated: false, reduceMotion: false)
    container.layoutSubtreeIfNeeded()
    let banner = container.banner
    XCTAssertTrue(banner.label.isHidden)
    XCTAssertFalse(banner.glyph.isHidden)
    XCTAssertEqual(banner.restartButton.frame.minX, banner.glyph.frame.maxX + 8)
    XCTAssertEqual(banner.restartButton.frame.maxX, banner.row.bounds.width - 5, accuracy: 0.5)
    XCTAssertGreaterThan(banner.restartButton.frame.width, banner.restartButton.intrinsicContentSize.width)
  }

  func testALongAnnouncementTruncatesBeforeTheChevron() throws {
    let harness = makeHarness([Self.announcement])
    let banner = harness.banner
    XCTAssertEqual(banner.label.stringValue, Self.announcement.title)
    for name in [SidebarBannerView.announcementSymbol, SidebarBannerView.chevronSymbol] {
      XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(name) exists on this macOS")
    }
    XCTAssertTrue(banner.restartButton.isHidden)
    XCTAssertFalse(banner.chevron.isHidden)
    XCTAssertLessThanOrEqual(banner.label.frame.maxX, banner.chevron.frame.minX - 8)
    XCTAssertLessThanOrEqual(banner.chevron.frame.maxX, banner.row.bounds.width)
    XCTAssertLessThan(banner.label.frame.width, banner.label.attributedStringValue.size().width, "truncated")
    XCTAssertEqual(banner.label.lineBreakMode, .byTruncatingTail)
    XCTAssertTrue(banner.row.isAccessibilityElement())
    XCTAssertEqual(banner.row.accessibilityRole(), .button)
    XCTAssertEqual(banner.row.accessibilityLabel(), Self.announcement.title)
  }

  func testAnAnnouncementOpensItsPopoverBesideTheRow() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    XCTAssertTrue(harness.banner.row.accessibilityPerformPress())
    let attachment = try XCTUnwrap(harness.attachment)
    let panel = try XCTUnwrap(attachment.popover.panel)
    XCTAssertEqual(panel.accessibilityLabel(), "What's new")
    XCTAssertEqual(panel.accessibilitySubrole(), .dialog)
    XCTAssertEqual(panel.frame.width, SidebarBannerMetrics.popoverWidth)
    let row = try XCTUnwrap(harness.controller.window).convertToScreen(
      harness.banner.row.convert(harness.banner.row.bounds, to: nil))
    XCTAssertEqual(panel.frame.minX, row.maxX + SidebarBannerMetrics.popoverGap, accuracy: 0.5)
    let content = try XCTUnwrap(attachment.popover.contentView)
    XCTAssertEqual(content.titleLabel.stringValue, Self.announcement.title)
    XCTAssertEqual(content.bodyLabel.stringValue, Self.announcement.body)
    XCTAssertEqual(content.actionButton?.title, "Open Archive")
    XCTAssertEqual(content.actionButton?.style, .neutral, "announcements never use mustard")
    XCTAssertLessThanOrEqual(content.dismissButton.frame.maxY, panel.frame.height)
    XCTAssertGreaterThan(panel.frame.height, content.titleLabel.frame.maxY)
    content.dismissButton.performClick(nil)
    XCTAssertFalse(attachment.popover.isShown)
    XCTAssertNil(harness.model.current)
  }

  /// The pill is styled for the popover's flavor from its first frame, not light first and dark on the next pass.
  func testTheDarkPopoversPillIsDarkFromTheStart() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    let popover = SidebarBannerPopover()
    popover.reduceMotion = { true }
    popover.show(Self.announcement, beside: harness.banner.row, flavor: .dark, takesKey: false)
    defer { popover.hide() }
    let pill = try XCTUnwrap(popover.contentView?.actionButton)
    let dark = ShellTokens.primaryText.resolve(.dark)
    XCTAssertEqual(pill.displayedTitleColor, dark)
    let drawn = try XCTUnwrap(pill.drawnTitleColor?.usingColorSpace(.sRGB))
    let expected = try XCTUnwrap(dark.nsColor().usingColorSpace(.sRGB))
    XCTAssertEqual(drawn.redComponent, expected.redComponent, accuracy: 0.01, "drawn dark, not light")
    XCTAssertEqual(drawn.greenComponent, expected.greenComponent, accuracy: 0.01)
    XCTAssertEqual(drawn.blueComponent, expected.blueComponent, accuracy: 0.01)
    XCTAssertTrue(popover.contentView?.appearance?.name == .darkAqua, "the content carries the flavor itself")
  }

  func testThePopoversActionGoesToTheSource() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    let attachment = try XCTUnwrap(harness.attachment)
    attachment.togglePopover()
    try XCTUnwrap(attachment.popover.contentView?.actionButton).performClick(nil)
    XCTAssertEqual(harness.source.performed, [Self.announcement])
    XCTAssertFalse(attachment.popover.isShown)
  }

  func testThePopoverClosesWhenItsNoticeGoes() throws {
    let harness = makeHarness([Self.announcement], reduceMotion: true)
    let attachment = try XCTUnwrap(harness.attachment)
    attachment.togglePopover()
    XCTAssertTrue(attachment.popover.isShown)
    harness.source.notices = []
    XCTAssertFalse(attachment.popover.isShown)
  }

  func testAnUpdateRowDoesNotOpenAPopover() throws {
    let harness = makeHarness([Self.update])
    harness.attachment?.togglePopover()
    XCTAssertEqual(harness.attachment?.popover.isShown, false)
  }

  func testDimmingANonKeyWindowDimsTheBanner() {
    let harness = makeHarness([Self.update])
    harness.container.isDimmed = true
    XCTAssertEqual(harness.banner.row.alphaValue, SidebarContainerView.dimmedAlpha)
    harness.container.isDimmed = false
    XCTAssertEqual(harness.banner.row.alphaValue, 1)
  }

  /// A closed window's attachment goes at once and stops following the model.
  func testAClosedWindowIsLetGo() throws {
    let harness = makeHarness([Self.update])
    XCTAssertNotNil(harness.attachment)
    harness.controller.close()
    XCTAssertNil(harness.center.attachment(of: harness.controller), "let go when the window closes")
    let bannerNotice = harness.banner.notice
    harness.source.notices = [Self.announcement]
    XCTAssertEqual(harness.banner.notice, bannerNotice, "a closed window's banner is not updated")
  }

  func testEveryWindowShowsTheNotice() {
    let harness = makeHarness([Self.update])
    let second = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controllers.append(second)
    harness.center.attach(to: second)
    XCTAssertEqual(second.sidebarController.view.banner.notice, Self.update)
    harness.source.notices = []
    XCTAssertTrue(second.sidebarController.view.banner.alphaValue == 0 || second.sidebarController.view.banner.isHidden)
  }

  // MARK: The fade mask only while it shows something

  /// Rows that end above the fade need no mask: none at rest, so scrolling and swipes pay no offscreen pass.
  func testRowsThatEndAboveTheFadeGetNoMask() {
    let harness = makeHarness([Self.update], sidebar: Self.sidebar(tabs: 2).0)
    XCTAssertFalse(harness.container.bannerRowsReachFade)
    XCTAssertNil(harness.container.pager.layer?.mask, "no mask while the rows end above the fade")
    XCTAssertEqual(harness.container.pager.frame.maxY, rowFrame(harness).minY, accuracy: 0.5, "the rows make room")
  }

  /// The mask comes when rows grow into the fade and goes when they shrink out of it.
  func testTheMaskFollowsTheRowsReachingTheFade() throws {
    let (stub, first, _) = Self.sidebar(tabs: 2)
    let harness = makeHarness([Self.update], sidebar: stub)
    XCTAssertNil(harness.container.pager.layer?.mask)
    var added: [NodeID] = []
    for index in 0..<30 {
      added.append(stub.addTab(url: URL(string: "https://example.net/\(index)")!, title: "More \(index)",
                               in: .today(first)))
    }
    harness.controller.rootView.layoutSubtreeIfNeeded()
    XCTAssertTrue(harness.container.bannerRowsReachFade)
    XCTAssertTrue(harness.container.pager.layer?.mask === harness.container.bannerSlot.fade, "on once rows reach it")
    for id in added { stub.removeNode(id) }
    harness.controller.rootView.layoutSubtreeIfNeeded()
    XCTAssertNil(harness.container.pager.layer?.mask, "off again once they end above it")
  }

  /// A swipe toward a page whose rows reach the fade turns the mask on as that page comes into view, and off again
  /// when the strip rests on a page that does not need it.
  func testTheMaskFollowsThePagesInView() throws {
    let harness = makeHarness([Self.update], reduceMotion: true)
    let container = harness.container
    let pager = container.pager
    XCTAssertTrue(pager.layer?.mask === container.bannerSlot.fade, "the long page is in view")
    // The pager reports each position to the sidebar controller, which hands it to the container.
    pager.setPositionForTesting(1)
    XCTAssertNil(pager.layer?.mask, "the short page alone needs none")
    pager.setPositionForTesting(0.5)
    XCTAssertTrue(pager.layer?.mask === container.bannerSlot.fade, "on while the long page is half in view")
  }

  /// A layout during the arrival (a window resize) turns the mask's motion toward its new resting frame instead of
  /// letting it finish at the old one and jump.
  func testALayoutDuringTheMotionRetargetsTheMask() throws {
    let harness = makeHarness()
    harness.source.notices = [Self.update]
    let fade = harness.container.bannerSlot.fade
    XCTAssertNotNil(fade.animation(forKey: "banner.bounds"))
    let window = try XCTUnwrap(harness.controller.window)
    window.setFrame(NSRect(x: 0, y: 0, width: 1080, height: 620), display: false)
    harness.controller.rootView.layoutSubtreeIfNeeded()
    let bounds = try XCTUnwrap(fade.animation(forKey: "banner.bounds") as? CABasicAnimation)
    let target = try XCTUnwrap(bounds.toValue as? NSRect)
    XCTAssertEqual(target.height, harness.container.bannerFadeFrame.height, accuracy: 0.5, "heads to the new frame")
    XCTAssertEqual(fade.frame, harness.container.bannerFadeFrame)
    harness.container.finishBannerMotionForTesting()
    XCTAssertEqual(harness.container.pager.frame.maxY, rowFrame(harness).minY, accuracy: 0.5)
    XCTAssertEqual(fade.frame.height, harness.container.pager.bounds.height)
  }

  /// The banner's bottom edge in window coordinates (y up), through its layer, so a transform counts.
  private func screenMinY(_ view: NSView) -> CGFloat {
    guard let layer = view.layer, let content = view.window?.contentView, let root = content.layer else { return 0 }
    let rect = layer.convert(layer.bounds, to: root)
    return content.isFlipped ? root.bounds.height - rect.maxY : rect.minY
  }
}
