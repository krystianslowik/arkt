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
    let source: FakeSidebarNoticeSource
    let model: SidebarBannerModel
    let center: SidebarBannerCenter
    var container: SidebarContainerView { controller.sidebarController.view }
    var banner: SidebarBannerView { container.banner }
    var attachment: SidebarBannerAttachment? { center.attachment(of: controller) }
  }

  private func makeHarness(_ notices: [SidebarNotice] = [], reduceMotion: Bool = false) -> Harness {
    let source = FakeSidebarNoticeSource(notices: notices)
    let model = SidebarBannerModel(source: source, dismissals: .ephemeral()) { _, _ in }
    model.reduceMotion = { reduceMotion }
    let center = SidebarBannerCenter(model: model)
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
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

  func testEveryWindowShowsTheNotice() {
    let harness = makeHarness([Self.update])
    let second = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    controllers.append(second)
    harness.center.attach(to: second)
    XCTAssertEqual(second.sidebarController.view.banner.notice, Self.update)
    harness.source.notices = []
    XCTAssertTrue(second.sidebarController.view.banner.alphaValue == 0 || second.sidebarController.view.banner.isHidden)
  }

  /// The banner's bottom edge in window coordinates (y up), through its layer, so a transform counts.
  private func screenMinY(_ view: NSView) -> CGFloat {
    guard let layer = view.layer, let content = view.window?.contentView, let root = content.layer else { return 0 }
    let rect = layer.convert(layer.bounds, to: root)
    return content.isFlipped ? root.bounds.height - rect.maxY : rect.minY
  }
}
