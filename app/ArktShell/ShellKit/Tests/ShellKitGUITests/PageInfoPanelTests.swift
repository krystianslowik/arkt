import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@testable import ShellUI

/// The page info panel (#582) in the shell window, on InMemoryEngine's page info: the pill's site glyph, the panel's
/// place, content and worst cases (long and IDN hosts, many permissions, `file:` and `chrome:` pages, an insecure
/// page), the per-site calls and the reload infobar they raise, dismissal, VoiceOver and Reduce Motion. No synthetic
/// input: presses go through the views' handlers and accessibility actions.
@MainActor
final class PageInfoPanelTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var controller: ShellWindowController!
  private var setting: ToolbarSetting!
  private var sidebar: StubSidebar!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    makeController()
  }

  // Reduce Motion by default: a hide then takes the panel down at once, so no fade outlives a test (the run loop does
  // not spin between tests to finish it). The motion tests set what they check.

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    controller.pageInfo.hide(keyboard: true)
    controller.close()
    controller = nil
    sidebar = nil
    engine = nil
  }

  private func makeController(reduceMotion: Bool = true) {
    engine = InMemoryEngine()
    setting = .ephemeral()
    sidebar = StubSidebar.sample()
    controller = ShellWindowController(engine: engine, sidebar: sidebar, toolbarSetting: setting)
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    controller.showWindow(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    controller.pageInfo.reduceMotion = { reduceMotion }
    controller.pageInfo.increaseContrast = { false }
    controller.pageInfo.deniedInMacOS = { [] }          // never the host's real location state (#786)
  }

  private var panel: PageInfoPanelController { controller.pageInfo }
  private var view: PageInfoPanelView? { panel.contentView }

  /// Loads `address` in the current tab.
  @discardableResult
  private func open(_ address: String) throws -> TabID {
    let tab = try XCTUnwrap(controller.currentTab, "the window opens with a tab")
    engine.navigate(tab, to: try XCTUnwrap(URL(string: address)))
    engine.finishLoad(tab, title: "Page")
    return tab
  }

  private func pressGlyph(_ bar: URLBarView? = nil) {
    (bar ?? controller.urlBar).onPressSiteGlyph?()
  }

  private func row(_ kind: SitePermissionKind) throws -> PageInfoPermissionRow {
    try XCTUnwrap(view?.rows.first { $0.kind == kind })
  }

  private func choose(_ title: String, in kind: SitePermissionKind) throws {
    let popUp = try row(kind).popUp
    popUp.selectItem(withTitle: title)
    XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
  }

  // MARK: The pill's glyph

  func testPillShowsTheConnectionGlyphOnlyForPagesWithPageInfo() throws {
    try open("https://fieldguide.example/trails")
    XCTAssertEqual(controller.urlBar.siteSymbol, "lock")
    XCTAssertFalse(controller.urlBar.siteGlyph.isHidden)
    XCTAssertGreaterThan(controller.urlBar.label.frame.minX, controller.urlBar.siteGlyph.frame.maxX,
                         "the host follows the glyph")
    XCTAssertEqual(controller.urlBar.accessibilityCustomActions()?.map(\.name), ["Show Site Controls"])

    try open("http://old-mirror.fieldguide.example/")
    XCTAssertEqual(controller.urlBar.siteSymbol, "exclamationmark.triangle")

    try open("file:///tmp/trail-notes.html")
    XCTAssertEqual(controller.urlBar.siteSymbol, "doc")

    try open("chrome://settings/")
    XCTAssertNil(controller.urlBar.siteSymbol, "the browser's own pages leave the pill inert")
    XCTAssertTrue(controller.urlBar.siteGlyph.isHidden)
    XCTAssertNil(controller.urlBar.accessibilityCustomActions())
    pressGlyph()
    XCTAssertFalse(panel.isShown)
  }

  func testClickOnTheGlyphOpensThePanelAndElsewhereTheCommandBar() throws {
    try open("https://fieldguide.example/")
    let bar = controller.urlBar
    var glyphPresses = 0
    var barPresses = 0
    bar.onPressSiteGlyph = { glyphPresses += 1 }
    bar.onPress = { barPresses += 1 }
    let window = try XCTUnwrap(bar.window)
    func click(_ point: NSPoint) throws {
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
          with: type, location: bar.convert(point, to: nil), modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
          pressure: type == .leftMouseDown ? 1 : 0))
        if type == .leftMouseDown { bar.mouseDown(with: event) } else { bar.mouseUp(with: event) }
      }
    }
    try click(NSPoint(x: bar.siteGlyph.frame.midX, y: bar.siteGlyph.frame.midY))
    try click(NSPoint(x: bar.bounds.midX, y: bar.bounds.midY))
    XCTAssertEqual(glyphPresses, 1)
    XCTAssertEqual(barPresses, 1)
  }

  // MARK: Opening and place

  func testGlyphOpensTheDialogBelowThePillWithFocusOnTheFirstControl() throws {
    let tab = try open("https://fieldguide.example/trails")
    pressGlyph()

    XCTAssertTrue(panel.isShown)
    XCTAssertEqual(panel.tab, tab)
    let window = try XCTUnwrap(panel.panel)
    XCTAssertEqual(window.accessibilitySubrole(), .dialog)
    XCTAssertEqual(window.accessibilityLabel(), "Site controls for fieldguide.example")
    XCTAssertTrue(window.parent === controller.window, "a child of the browser window")
    let bar = controller.urlBar
    let pill = try XCTUnwrap(bar.window).convertToScreen(bar.convert(bar.bounds, to: nil))
    XCTAssertEqual(window.frame.width, 330)
    XCTAssertEqual(window.frame.minX, pill.minX, "its leading edge on the pill's")
    XCTAssertEqual(window.frame.maxY, pill.minY - PageInfoMetrics.gap, "below the pill")

    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.hostLabel.stringValue, "fieldguide.example")
    XCTAssertEqual(view.connectionLabel.stringValue, "Connection is secure")
    XCTAssertEqual(view.rows.map(\.title.stringValue), ["Location", "Camera", "Microphone", "Notifications"])
    XCTAssertEqual(view.rows.map { $0.popUp.titleOfSelectedItem }, ["Ask", "Ask", "Ask", "Ask"])
    XCTAssertEqual(view.rows.first?.popUp.itemTitles, ["Allow", "Ask", "Block"])
    XCTAssertEqual(view.rows.first?.popUp.accessibilityLabel(), "Location")
    XCTAssertFalse(view.resetButton.isEnabled, "nothing to reset")
    XCTAssertFalse(view.listScrolls)
    XCTAssertTrue(window.firstResponder === view.rows.first?.popUp, "focus starts on the first control")
    XCTAssertEqual(window.frame.height, view.preferredHeight(width: 330), accuracy: 0.5, "height follows the content")
  }

  func testGlyphTogglesThePanel() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    XCTAssertTrue(panel.isShown)
    pressGlyph()
    XCTAssertFalse(panel.isShown)
  }

  func testToolbarGlyphOpensThePanelBelowTheToolbar() throws {
    setting.isVisible = true
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    try open("https://fieldguide.example/")
    let bar = controller.rootView.card.toolbar.urlBar
    XCTAssertEqual(bar.siteSymbol, "lock")
    bar.layoutSubtreeIfNeeded()
    XCTAssertLessThan(bar.siteGlyph.frame.maxX, bar.label.frame.minX + 0.5, "just before the centered URL")

    pressGlyph(bar)

    let window = try XCTUnwrap(panel.panel)
    let toolbarRect = try XCTUnwrap(bar.window).convertToScreen(bar.convert(bar.bounds, to: nil))
    XCTAssertEqual(window.frame.maxY, toolbarRect.minY - PageInfoMetrics.gap)
    let glyph = try XCTUnwrap(bar.window).convertToScreen(bar.convert(bar.siteGlyph.frame, to: nil))
    XCTAssertEqual(window.frame.minX, glyph.minX - PageInfoMetrics.sideInset, accuracy: 0.5)
  }

  // MARK: Worst cases

  func testInsecurePageSaysSoInPrimaryTextWithAWarningGlyph() throws {
    try open("http://old-mirror.fieldguide.example/")
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.connectionLabel.stringValue, "Not secure: this site has no encrypted connection")
    XCTAssertEqual(view.connectionLabel.textColor, ShellTokens.primaryText.resolve(view.archiveFlavor).nsColor(),
                   "never red")
    XCTAssertGreaterThanOrEqual(view.connectionLabel.frame.maxX, view.connectionLabel.frame.minX)
    XCTAssertLessThanOrEqual(view.connectionLabel.frame.maxX, view.bounds.width - PageInfoMetrics.sideInset + 0.5)
  }

  func testLongPunycodeHostTruncatesInTheMiddleInsideThePanel() throws {
    let host = "xn--bergfhrer-verband-kartenarchiv-q9b-sektion-nordwest-archiv.example"
    try open("https://\(host)/karten")
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.hostLabel.stringValue, host)
    XCTAssertEqual(view.hostLabel.lineBreakMode, .byTruncatingMiddle)
    XCTAssertEqual(view.hostLabel.toolTip, host)
    XCTAssertLessThanOrEqual(view.hostLabel.frame.maxX, view.bounds.width - PageInfoMetrics.sideInset + 0.5)
    XCTAssertEqual(panel.panel?.accessibilityLabel(), "Site controls for \(host)")
  }

  func testTenPermissionsFitAndMoreScrollUnderAFixedFooter() throws {
    try open("https://fieldguide.example/")
    let site = "https://fieldguide.example"
    let six: [(SitePermissionKind, PermissionSetting)] = [
      (.popups, .allow), (.sound, .block), (.javascript, .block), (.automaticDownloads, .block), (.clipboard, .allow),
      (.midiDevices, .allow),
    ]
    for (kind, value) in six { engine.setPermission(kind, to: value, forOrigin: site, from: TabID()) }
    pressGlyph()
    XCTAssertEqual(view?.rows.count, 10)
    XCTAssertEqual(view?.listScrolls, false, "ten rows fit under 552 pt")
    panel.hide(keyboard: true)

    let more: [SitePermissionKind] = [.usbDevices, .serialPorts, .hidDevices, .bluetoothDevices, .fileEditing,
                                      .localFonts]
    for kind in more {
      engine.setPermission(kind, to: .block, forOrigin: site, from: TabID())
    }
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.rows.count, 16)
    XCTAssertEqual(panel.panel?.frame.height, PageInfoMetrics.maxHeight)
    XCTAssertTrue(view.listScrolls)
    XCTAssertNotNil(view.scrollView.layer?.mask, "the list fades at its bottom edge")
    XCTAssertFalse(view.resetButton.isHidden)
    XCTAssertEqual(view.resetButton.frame.maxY, view.bounds.height - (PageInfoMetrics.footerHeight - 24) / 2,
                   accuracy: 1, "the footer stays")
  }

  func testLocalFileShowsTheNoteAndNothingElse() throws {
    try open("file:///tmp/trail-notes.html")
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.hostLabel.stringValue, "trail-notes.html")
    XCTAssertEqual(view.connectionLabel.stringValue, "Local file on this Mac")
    XCTAssertFalse(view.noteLabel.isHidden)
    XCTAssertEqual(view.noteLabel.stringValue,
                   "Local files have no site settings.")
    XCTAssertTrue(view.scrollView.isHidden && view.resetButton.isHidden && view.siteSettingsButton.isHidden)
    XCTAssertLessThan(try XCTUnwrap(panel.panel).frame.height, 200)
  }

  func testSmallWindowCapsThePanel() throws {
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: 640, height: 420), display: false)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    try open("https://fieldguide.example/")
    for kind in SitePermissionKind.allCases.dropFirst(4).prefix(10) {
      let target: PermissionSetting = kind == .popups || kind == .insecureContent ? .allow : .block
      engine.setPermission(kind, to: target, forOrigin: "https://fieldguide.example", from: TabID())
    }
    pressGlyph()
    let window = try XCTUnwrap(panel.panel)
    let parent = try XCTUnwrap(controller.window)
    XCTAssertGreaterThanOrEqual(window.frame.minY, parent.frame.minY + PageInfoMetrics.windowMargin - 0.5)
    XCTAssertTrue(view?.listScrolls == true)
  }

  // MARK: Changes

  func testChoosingASettingAppliesAtOnceAndRaisesTheReloadInfobar() throws {
    let tab = try open("https://fieldguide.example/")
    pressGlyph()

    try choose("Block", in: .camera)

    XCTAssertEqual(engine.pageInfo(of: tab)?.permissions.first { $0.kind == .camera }?.setting, .block)
    XCTAssertTrue(panel.isShown, "the panel stays up")
    XCTAssertEqual(try row(.camera).popUp.titleOfSelectedItem, "Block")
    XCTAssertTrue(view?.resetButton.isEnabled == true)
    XCTAssertTrue(engine.infobars(of: tab).isEmpty, "no reload infobar while the panel is open")

    try choose("Allow", in: .microphone)
    panel.hide(keyboard: false)
    XCTAssertEqual(engine.infobars(of: tab).map(\.kind), [.reload], "the reload infobar when the panel closes")
  }

  func testClosingWithoutAChangeRaisesNoInfobar() throws {
    let tab = try open("https://fieldguide.example/")
    pressGlyph()
    try XCTUnwrap(panel.panel).cancelOperation(nil)
    XCTAssertTrue(engine.infobars(of: tab).isEmpty)
  }

  func testAnOpenPanelFollowsTheEnginesAnnouncements() throws {
    try open("https://fieldguide.example/")
    engine.setSiteData(nil, forOrigin: "https://fieldguide.example")
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertEqual(view.siteDataRow.summary.stringValue, "", "still counting")

    engine.setSiteData(SiteData(cookies: 0, bytes: 0), forOrigin: "https://fieldguide.example")
    XCTAssertEqual(view.siteDataRow.summary.stringValue, "None", "the count arrived")

    engine.setPermission(.camera, to: .block, forOrigin: "https://fieldguide.example", from: TabID())
    XCTAssertEqual(try row(.camera).popUp.titleOfSelectedItem, "Block", "a change made elsewhere")

    let tab = try XCTUnwrap(controller.currentTab)
    engine.setConnection(tab, .notFullySecure)
    XCTAssertEqual(view.connectionLabel.stringValue, "Not fully secure: parts of this page are not encrypted")
    XCTAssertEqual(controller.urlBar.accessibilityValue() as? String, "Not fully secure, fieldguide.example")
  }

  func testPrivateWindowShowsThePanelReadOnly() throws {
    controller.makeIncognito()
    controller.openPrivately(try XCTUnwrap(URL(string: "https://fieldguide.example/")))
    let tab = try XCTUnwrap(controller.currentTab)
    engine.finishLoad(tab, title: "Page")
    XCTAssertEqual(controller.urlBar.siteSymbol, "lock")
    pressGlyph()
    let view = try XCTUnwrap(view)
    XCTAssertFalse(view.readOnlyLabel.isHidden)
    XCTAssertEqual(view.readOnlyLabel.stringValue, "Site settings can't be changed in this window.")
    XCTAssertTrue(view.popUps.allSatisfy { !$0.isEnabled }, "the pop-ups are off")
    XCTAssertFalse(view.resetButton.isEnabled)
    XCTAssertTrue(engine.sitesWithPermissions().isEmpty)
  }

  func testResetPermissionsPutsEveryPermissionBack() throws {
    let tab = try open("https://fieldguide.example/")
    engine.setPermission(.location, to: .block, forOrigin: "https://fieldguide.example", from: TabID())
    engine.setPermission(.popups, to: .allow, forOrigin: "https://fieldguide.example", from: TabID())
    pressGlyph()
    XCTAssertEqual(view?.rows.count, 5)
    let reset = try XCTUnwrap(view?.resetButton)
    XCTAssertTrue(reset.isEnabled)

    reset.performClick(nil)

    XCTAssertEqual(view?.rows.map(\.kind), [.location, .camera, .microphone, .notifications])
    XCTAssertEqual(view?.resetButton.isEnabled, false)
    XCTAssertTrue(engine.pageInfo(of: tab)?.permissions.allSatisfy(\.isDefault) == true)
  }

  func testSiteSettingsAsksTheEngineAndCloses() throws {
    let tab = try open("https://fieldguide.example/")
    pressGlyph()
    try XCTUnwrap(view?.siteSettingsButton).performClick(nil)
    XCTAssertFalse(panel.isShown)
    XCTAssertEqual(engine.openedSiteSettings.map(\.origin), ["https://fieldguide.example"])
    XCTAssertEqual(engine.openedSiteSettings.map(\.tab), [tab])
  }

  func testCookiesAndSiteDataShowsTheSummaryAndOpensTheSiteSettings() throws {
    try open("https://fieldguide.example/")
    engine.setSiteData(SiteData(cookies: 14, bytes: 2_400_000), forOrigin: "https://fieldguide.example")
    pressGlyph()
    let row = try XCTUnwrap(view?.siteDataRow)
    XCTAssertEqual(row.summary.stringValue, PageInfoModel.siteDataText(SiteData(cookies: 14, bytes: 2_400_000)))
    XCTAssertEqual(row.button.accessibilityLabel(), "Cookies and site data")
    row.button.performClick(nil)
    XCTAssertEqual(engine.openedSiteSettings.count, 1)
  }

  // MARK: Dismissal

  func testEscapeClosesAndReturnsTheKeyboardToThePage() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    var returned = 0
    panel.onReturnFocus = { returned += 1 }
    try XCTUnwrap(panel.panel).cancelOperation(nil)
    XCTAssertFalse(panel.isShown)
    XCTAssertEqual(returned, 1)
  }

  func testAClickInTheWindowClosesItButNotOnTheGlyphOrInOtherWindows() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    let bar = controller.urlBar
    let glyph = bar.convert(NSPoint(x: bar.siteGlyph.frame.midX, y: bar.siteGlyph.frame.midY), to: nil)
    panel.handleMouseDown(in: controller.window, at: glyph)
    XCTAssertTrue(panel.isShown, "the glyph toggles instead")
    panel.handleMouseDown(in: panel.panel, at: NSPoint(x: 10, y: 10))
    XCTAssertTrue(panel.isShown, "a click in the panel")
    panel.handleMouseDown(in: controller.window, at: NSPoint(x: 900, y: 300))
    XCTAssertFalse(panel.isShown)
  }

  func testAnotherTabOrSiteClosesItAndTheSameSiteFollows() throws {
    let tab = try open("https://fieldguide.example/a")
    pressGlyph()
    engine.navigate(tab, to: try XCTUnwrap(URL(string: "https://fieldguide.example/b")))
    XCTAssertTrue(panel.isShown, "the same site keeps the panel")
    engine.navigate(tab, to: try XCTUnwrap(URL(string: "https://other.example/")))
    XCTAssertFalse(panel.isShown, "another site closes it")

    pressGlyph()
    XCTAssertTrue(panel.isShown)
    let other = try XCTUnwrap(sidebar.children(of: .today(sidebar.spaceOrder[0])).last)
    controller.activate(node: other)
    XCTAssertNotEqual(controller.currentTab, tab)
    XCTAssertFalse(panel.isShown, "another tab closes it")
  }

  func testTheEngineCountsSiteDataOnlyWhileThePanelIsOpen() throws {
    let tab = try open("https://fieldguide.example/a")
    XCTAssertTrue(engine.openPageInfoPanels.isEmpty, "the pill reads without opening")
    pressGlyph()
    XCTAssertEqual(engine.openPageInfoPanels, [tab], "the panel tells the engine it opened")
    pressGlyph()
    XCTAssertTrue(engine.openPageInfoPanels.isEmpty, "the glyph closes it again")

    pressGlyph()
    engine.navigate(tab, to: try XCTUnwrap(URL(string: "https://other.example/")))
    XCTAssertFalse(panel.isShown)
    XCTAssertTrue(engine.openPageInfoPanels.isEmpty, "another site closes it for the engine too")

    pressGlyph()
    panel.hide(keyboard: true)
    XCTAssertTrue(engine.openPageInfoPanels.isEmpty)
  }

  func testLosingMainOrTheAppGoingToTheBackgroundClosesIt() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    panel.parentDidResignMain()
    XCTAssertFalse(panel.isShown)
    pressGlyph()
    panel.appDidResignActive()
    XCTAssertFalse(panel.isShown)
  }

  func testTheBadgeShowsTheFavicon() throws {
    let tab = try open("https://fieldguide.example/")
    pressGlyph()
    XCTAssertFalse(try XCTUnwrap(view).showsFavicon, "the site glyph without a favicon")
    panel.hide(keyboard: true)
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
      NSColor.systemOrange.setFill()
      rect.fill()
      return true
    }
    let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
      .representation(using: .png, properties: [:]))
    engine.navigate(tab, to: try XCTUnwrap(URL(string: "https://fieldguide.example/again")))
    engine.finishLoad(tab, title: "Page", favicon: png)
    pressGlyph()
    XCTAssertTrue(try XCTUnwrap(view).showsFavicon)
  }

  func testVoiceOverReadsTheSecurityStateBeforeTheAddress() throws {
    try open("https://fieldguide.example/")
    XCTAssertEqual(controller.urlBar.accessibilityValue() as? String, "fieldguide.example", "a secure page: the address")
    try open("http://old-mirror.fieldguide.example/")
    XCTAssertEqual(controller.urlBar.accessibilityValue() as? String, "Not secure, old-mirror.fieldguide.example")
    try open("chrome://settings/")
    XCTAssertEqual(controller.urlBar.accessibilityValue() as? String, controller.urlBar.displayedText,
                   "the address alone without a glyph")
  }

  func testSidebarChangeAndFullScreenCloseIt() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    panel.sidebarDidChange()
    XCTAssertFalse(panel.isShown)
    pressGlyph()
    panel.windowWillEnterFullScreen()       // a posted notification would put the real window in a full-screen state
    XCTAssertFalse(panel.isShown)
  }

  func testWindowResizeKeepsItBelowThePill() throws {
    try open("https://fieldguide.example/")
    pressGlyph()
    controller.window?.setFrame(NSRect(x: 160, y: 140, width: 1000, height: 700), display: true)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let bar = controller.urlBar
    let pill = try XCTUnwrap(bar.window).convertToScreen(bar.convert(bar.bounds, to: nil))
    let window = try XCTUnwrap(panel.panel)
    XCTAssertEqual(window.frame.maxY, pill.minY - PageInfoMetrics.gap)
    XCTAssertEqual(window.frame.minX, pill.minX)
  }

  // MARK: Motion

  func testEntranceScalesAndFadesOnFirmFast() throws {
    controller.close()
    makeController(reduceMotion: false)
    try open("https://fieldguide.example/")
    pressGlyph()
    let animations = panel.entranceAnimations
    XCTAssertEqual(animations["appear.opacity"]?.duration, 0.22)
    XCTAssertNotNil(animations["appear.transform"])
    let curve = try XCTUnwrap(animations["appear.transform"]?.timingFunction)
    var first: [Float] = [0, 0]
    var second: [Float] = [0, 0]
    curve.getControlPoint(at: 1, values: &first)
    curve.getControlPoint(at: 2, values: &second)
    XCTAssertEqual(first + second, [0.2, 1, 0.4, 1], "firmFast")
  }

  func testReduceMotionFadesOnly() throws {
    controller.close()
    makeController(reduceMotion: true)
    try open("https://fieldguide.example/")
    pressGlyph()
    let animations = panel.entranceAnimations
    XCTAssertEqual(animations["appear.opacity"]?.duration, 0.15)
    XCTAssertNil(animations["appear.transform"], "no scale or movement")
  }
}
