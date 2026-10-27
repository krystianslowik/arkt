import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// A tab's infobars as a strip over the top of its page (#400): flush and full width while the tab is on screen, one
/// 40 pt row per infobar, actions go to the engine and the row leaves with the engine's next list, a hidden tab keeps its
/// list, and the design's light and dark surfaces, Reduce Motion and VoiceOver values hold.
@MainActor
final class InfobarPresenterTests: XCTestCase {
  private var window: NSWindow!
  private var page: NSView!
  private var engine: InMemoryEngine!
  private var tab: TabID!
  private var presenter: InfobarPresenter!
  private var observation: EngineObservation?
  private var shown = true
  private var windowVisible = true

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500), styleMask: [.titled],
                      backing: .buffered, defer: false)
    page = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = page
    window.orderFront(nil)
    engine = InMemoryEngine()
    let engineWindow = engine.createWindow(host: StubWindowHost())
    tab = engine.createTab(url: URL(string: "arkt-test://example.com/Infobar")!, in: engineWindow)
    engine.activateTab(tab)
    presenter = InfobarPresenter(engine: engine, anchor: { [unowned self] _ in shown ? page : nil },
                                 windowIsVisible: { [unowned self] _ in windowVisible })
    presenter.reduceMotion = { true }
    observation = engine.observe { [unowned self] in presenter.handle($0) }
  }

  override func tearDown() async throws {
    observation?.cancel()
    presenter.closeAll()
    window.orderOut(nil)
  }

  private func strip() throws -> InfobarPanel { try XCTUnwrap(presenter.strip(for: tab)) }
  private func row(_ index: Int = 0) throws -> InfobarRowView { try XCTUnwrap(strip().rows[index]) }
  private var anchor: NSRect { window.convertToScreen(page.convert(page.bounds, to: nil)) }

  // MARK: Placement

  func testAnInfobarShowsAStripFlushWithThePagesTopAndAsWideAsIt() throws {
    engine.raiseInfobar(in: tab, message: "Hello")
    let strip = try strip()
    XCTAssertTrue(window.childWindows?.contains(strip.panel) == true)
    XCTAssertEqual(strip.panel.frame, NSRect(x: anchor.minX, y: anchor.maxY - 40, width: anchor.width, height: 40))
    XCTAssertEqual(presenter.height(of: tab), 40)
  }

  func testEveryInfobarIsA40PointRowAndTheStripKeepsItsTopEdge() throws {
    engine.raiseInfobar(in: tab, message: "One")
    engine.raiseInfobar(in: tab, message: "Two")
    let strip = try strip()
    XCTAssertEqual(strip.rows.map(\.infobar.message), ["One", "Two"])
    XCTAssertEqual(strip.panel.frame.height, 80)
    XCTAssertEqual(strip.panel.frame.maxY, anchor.maxY, "the top edge stays at the page's top")
    XCTAssertEqual(strip.rows.map(\.frame.minY), [0, 40])
    XCTAssertEqual(presenter.height(of: tab), 80)
  }

  func testTheStripFollowsThePageAcrossWindowWidths() throws {
    engine.raiseInfobar(in: tab, message: "Hello")
    let strip = try strip()
    for width: CGFloat in [900, 480, 320, 700] {
      window.setContentSize(NSSize(width: width, height: 500))
      XCTAssertEqual(strip.panel.frame, strip.frame(anchoredTo: anchor), "at \(width)")
      XCTAssertEqual(strip.panel.frame.width, anchor.width, "at \(width)")
      XCTAssertTrue(presenter.strip(for: tab) === strip, "resizing keeps the same strip")
    }
  }

  func testTheStripDoesNotTakeKeyFocusFromThePage() throws {
    engine.raiseInfobar(in: tab, message: "Hello")
    XCTAssertFalse(try strip().panel.isKeyWindow)
  }

  func testTheCardCornerRadiusIsFoundFromThePageViewUpward() throws {
    let card = NSView(frame: page.bounds)
    card.wantsLayer = true
    card.layer?.cornerRadius = 14
    card.layer?.masksToBounds = true
    let inner = NSView(frame: card.bounds)
    card.addSubview(inner)
    page.addSubview(card)
    XCTAssertEqual(InfobarPresenter.cardCornerRadius(of: inner), 14)
    XCTAssertEqual(InfobarPresenter.cardCornerRadius(of: NSView()), 0, "a page with no rounded card has square corners")
  }

  func testTheStripsTopCornersTakeTheCardsRadiusAndTheBottomStaysSquare() throws {
    presenter.cornerRadius = { _ in 14 }
    engine.raiseInfobar(in: tab, message: "Hello")
    let layer = try XCTUnwrap(try strip().stack.layer)
    XCTAssertEqual(layer.cornerRadius, 14)
    XCTAssertEqual(layer.maskedCorners, [.layerMinXMaxYCorner, .layerMaxXMaxYCorner], "the top corners of an unflipped layer")
  }

  // MARK: Actions

  func testEachButtonActsOnTheEngineAndTheRowLeavesWithTheEnginesNextList() throws {
    let cases: [(String, (InfobarRowView) -> Void, InfobarAction)] = [
      ("ok", { $0.okButton?.performClick(nil) }, .ok),
      ("cancel", { $0.cancelButton?.performClick(nil) }, .cancel),
      ("close", { $0.closeButton?.performClick(nil) }, .close),
    ]
    for (name, press, action) in cases {
      let id = try XCTUnwrap(engine.raiseInfobar(in: tab, message: name))
      press(try row())
      XCTAssertEqual(engine.infobarActions.last?.id, id, name)
      XCTAssertEqual(engine.infobarActions.last?.action, action, name)
      XCTAssertNil(presenter.strip(for: tab), "\(name): the engine removed it, so the strip is gone")
      XCTAssertNil(presenter.infobars[tab], name)
    }
    XCTAssertEqual(engine.infobarActions.count, 3)
  }

  func testALinkKeepsTheRowUntilTheEngineRemovesIt() throws {
    let id = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Hello"))
    try row().message.onLink?(2)
    XCTAssertEqual(engine.infobarActions.map(\.action), [.messageLink(2)])
    XCTAssertEqual(engine.infobarActions.first?.id, id)
    XCTAssertEqual(presenter.infobars[tab]?.count, 1, "the delegate kept it: nothing is removed optimistically")
    XCTAssertNotNil(presenter.strip(for: tab))
  }

  func testTheTrailingLinkButtonActsAsALink() throws {
    let id = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Hello"))
    var withLink = try XCTUnwrap(presenter.infobars[tab]?.first { $0.id == id })
    withLink.linkTitle = "Learn more"
    presenter.handle(.infobarsChanged(tab, [withLink]))
    try row().linkButton?.performClick(nil)
    XCTAssertEqual(engine.infobarActions.map(\.action), [.link])
    XCTAssertEqual(engine.infobarActions.first?.id, id)
  }

  func testAnInfobarWithoutAnOkOrCancelOrCloseDrawsNone() throws {
    engine.raiseInfobar(in: tab, message: "Quiet", okTitle: nil, cancelTitle: nil, isCloseable: false)
    let row = try row()
    XCTAssertNil(row.okButton)
    XCTAssertNil(row.cancelButton)
    XCTAssertNil(row.closeButton)
    XCTAssertNil(row.linkButton)
  }

  func testADisabledButtonDoesNotAct() throws {
    let infobar = Infobar(id: InfobarID(), tab: tab, message: "Hello", ok: InfobarButton(title: "Wait", isEnabled: false))
    presenter.handle(.infobarsChanged(tab, [infobar]))
    let ok = try XCTUnwrap(try row().okButton)
    XCTAssertFalse(ok.isEnabled)
  }

  // MARK: Tabs

  func testAHiddenTabKeepsItsListAndTheStripComesBackWhenItIsShown() throws {
    engine.raiseInfobar(in: tab, message: "Mine")
    XCTAssertNotNil(presenter.strip(for: tab))

    shown = false
    presenter.refresh()
    XCTAssertNil(presenter.strip(for: tab), "the page is off screen: no strip")
    XCTAssertEqual(presenter.infobars[tab]?.map(\.message), ["Mine"])

    shown = true
    presenter.refresh()
    XCTAssertEqual(try strip().rows.map(\.infobar.message), ["Mine"])
  }

  func testAListThatArrivesWhileTheTabIsHiddenShowsWhenTheTabIs() throws {
    shown = false
    engine.raiseInfobar(in: tab, message: "Later")
    XCTAssertNil(presenter.strip(for: tab))
    shown = true
    presenter.refresh()
    XCTAssertEqual(try strip().rows.map(\.infobar.message), ["Later"])
  }

  func testAMinimizedWindowShowsNoStripAndTheOneThatComesBackDoes() throws {
    windowVisible = false
    engine.raiseInfobar(in: tab, message: "Hello")
    XCTAssertNil(presenter.strip(for: tab))
    windowVisible = true
    presenter.refresh()
    XCTAssertNotNil(presenter.strip(for: tab))
  }

  func testTheEnginesListChangesUpdateTheSameStripAndRowsKeepTheirIdentity() throws {
    let first = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "First"))
    let strip = try strip()
    let firstRow = try row()
    let second = try XCTUnwrap(engine.raiseInfobar(in: tab, message: "Second"))
    XCTAssertTrue(presenter.strip(for: tab) === strip)
    XCTAssertTrue(try row(0) === firstRow, "the first row stays")
    XCTAssertEqual(strip.rows.map(\.infobar.id), [first, second])
    engine.removeInfobar(first)
    XCTAssertEqual(strip.rows.map(\.infobar.id), [second])
    XCTAssertEqual(strip.panel.frame.height, 40)
    XCTAssertEqual(strip.panel.frame.maxY, anchor.maxY, "the top edge stays when a row leaves")
  }

  func testClosingTheTabTakesTheStripDown() throws {
    engine.raiseInfobar(in: tab, message: "Hello")
    let panel = try strip().panel
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    XCTAssertNil(panel.parent)
    XCTAssertNil(presenter.strip(for: tab))
    XCTAssertNil(presenter.infobars[tab])
  }

  // MARK: Look: light, dark, worst case

  func testTheSurfaceIsTheBrandSurfaceInLightAndDark() throws {
    engine.raiseInfobar(in: tab, message: "Hello")
    let strip = try strip()
    for (name, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      strip.panel.appearance = NSAppearance(named: name)
      strip.stack.updateLayer()
      let expected = AlertTokens.dialogSurface.resolve(flavor).cgColor
      XCTAssertEqual(strip.stack.layer?.backgroundColor?.components, expected.components, "\(name)")
    }
  }

  func testTheMessageAndTheLinksTakeTheirColorsFromTheTokensInLightAndDark() throws {
    let infobar = Infobar(id: InfobarID(), tab: tab, message: "Read the notes.", messageLinks: [InfobarLink(index: 0, range: 9..<14)])
    presenter.handle(.infobarsChanged(tab, [infobar]))
    let message = try row().message
    for (name, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      try strip().panel.appearance = NSAppearance(named: name)
      message.viewDidChangeEffectiveAppearance()
      let plain = message.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
      XCTAssertEqual(plain, ShellTokens.primaryText.resolve(flavor).nsColor(), "\(name) message")
      let link = message.linkTextAttributes?[.foregroundColor] as? NSColor
      XCTAssertEqual(link, ShellTokens.secondaryText.resolve(flavor).nsColor(), "\(name) link")
      XCTAssertNil(message.linkTextAttributes?[.underlineStyle], "links are quiet: no underline")
    }
  }

  func testAVeryLongMessageStaysOnOneLineAndLeavesTheButtonsRoom() throws {
    engine.raiseInfobar(in: tab, message: String(repeating: "A very long message with unbreakableaddress@example.org ", count: 12))
    window.setContentSize(NSSize(width: 480, height: 500))
    let row = try row()
    row.layoutSubtreeIfNeeded()
    let buttons = [row.okButton, row.cancelButton, row.closeButton].compactMap { $0 }
    XCTAssertEqual(row.frame.height, 40)
    XCTAssertGreaterThan(row.message.frame.width, 100)
    for button in buttons {
      XCTAssertGreaterThanOrEqual(button.frame.minX, row.message.frame.maxX, "the message stops before the buttons")
      XCTAssertLessThanOrEqual(button.frame.maxX, row.bounds.width - InfobarMetrics.inset + 0.5)
    }
    XCTAssertEqual(row.message.toolTip?.count, row.infobar.message.count, "the whole message is in the tooltip")
    XCTAssertLessThanOrEqual(row.message.frame.height, 40)
  }

  func testNonLatinTextAndEmojiAndASingleLetterLayOut() throws {
    for message in ["拡張機能がこのブラウザーのデバッグを開始しました", "؟", "Debug \u{1F41E}\u{FE0F}", "x"] {
      engine.raiseInfobar(in: tab, message: message)
    }
    let strip = try strip()
    strip.stack.layoutSubtreeIfNeeded()
    XCTAssertEqual(strip.rows.count, 4)
    for row in strip.rows {
      XCTAssertGreaterThan(row.message.frame.width, 0, row.infobar.message)
      XCTAssertGreaterThan(row.message.frame.height, 0, row.infobar.message)
    }
  }

  func testTheKindPicksAGlyphWhenTheEngineSentNoIcon() throws {
    engine.raiseInfobar(in: tab, message: "Debugging", kind: .debugger)
    let row = try row()
    XCTAssertNotNil(row.iconView.image)
    XCTAssertFalse(row.iconView.isHidden)
    XCTAssertEqual(InfobarRowView.symbol(for: .other), nil)
  }

  func testTheEnginesIconIsUsedAt20Points() throws {
    let image = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
      NSColor.red.setFill(); rect.fill(); return true
    }
    let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
      .representation(using: .png, properties: [:]))
    let infobar = Infobar(id: InfobarID(), tab: tab, message: "Hello", iconPNG: png)
    presenter.handle(.infobarsChanged(tab, [infobar]))
    XCTAssertEqual(try row().iconView.image?.size, NSSize(width: 20, height: 20))
  }

  // MARK: Right to left

  func testARightToLeftRowMirrorsItsLayout() throws {
    engine.raiseInfobar(in: tab, message: "Hello", kind: .debugger)
    let row = try row()
    row.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(try XCTUnwrap(row.closeButton).frame.minX, row.bounds.width / 2, "left to right: close at the right")
    XCTAssertLessThan(row.iconView.frame.minX, row.bounds.width / 2, "left to right: the icon at the left")
    row.userInterfaceLayoutDirection = .rightToLeft
    row.layoutSubtreeIfNeeded()
    row.needsLayout = true
    row.layoutSubtreeIfNeeded()
    XCTAssertLessThan(try XCTUnwrap(row.closeButton).frame.minX, row.bounds.width / 2, "right to left: close at the left")
    XCTAssertGreaterThan(row.iconView.frame.minX, row.bounds.width / 2, "right to left: the icon at the right")
  }

  // MARK: Motion

  func testWithReduceMotionNothingFades() throws {
    engine.raiseInfobar(in: tab, message: "One")
    XCTAssertNil(try strip().stack.layer?.animation(forKey: "infobarFade"))
    engine.raiseInfobar(in: tab, message: "Two")
    XCTAssertNil(try row(1).layer?.animation(forKey: "infobarFade"))
  }

  func testWithoutReduceMotionTheStripAndANewRowFadeInOverAFifthOfASecondOrLess() throws {
    presenter.reduceMotion = { false }
    engine.raiseInfobar(in: tab, message: "One")
    let fade = try XCTUnwrap(try strip().stack.layer?.animation(forKey: "infobarFade") as? CABasicAnimation)
    XCTAssertEqual(fade.keyPath, "opacity")
    XCTAssertEqual(fade.duration, 0.14, accuracy: 0.001)
    engine.raiseInfobar(in: tab, message: "Two")
    XCTAssertNotNil(try row(1).layer?.animation(forKey: "infobarFade"), "a row added later fades in")
    XCTAssertNil(try row(0).layer?.animation(forKey: "infobarFade"), "the row that was there does not")
  }

  func testNoRowFadesOut() throws {
    presenter.reduceMotion = { false }
    engine.raiseInfobar(in: tab, message: "One")
    let panel = try strip().panel
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    XCTAssertNil(panel.parent, "it leaves at once")
  }

  // MARK: VoiceOver

  func testTheRowIsAGroupLabelledWithTheMessageAndItsButtonsAreNamedInOrder() throws {
    let infobar = Infobar(id: InfobarID(), tab: tab, message: "Page Inspector started debugging this browser",
                          linkTitle: "Learn more", linkAccessibilityLabel: "Learn more about debugging",
                          ok: InfobarButton(title: "Cancel", tooltip: "Stop debugging"), closeLabel: "Close")
    presenter.handle(.infobarsChanged(tab, [infobar]))
    let row = try row()
    XCTAssertTrue(row.isAccessibilityElement())
    XCTAssertEqual(row.accessibilityRole(), .group)
    XCTAssertEqual(row.accessibilityLabel(), "Page Inspector started debugging this browser")
    XCTAssertEqual(row.accessibilityIdentifier(), AXID.Infobar.root)
    XCTAssertEqual(row.okButton?.accessibilityLabel(), "Cancel")
    XCTAssertEqual(row.okButton?.accessibilityHelp(), "Stop debugging")
    XCTAssertEqual(row.linkButton?.accessibilityLabel(), "Learn more about debugging")
    XCTAssertEqual(row.closeButton?.accessibilityLabel(), "Close")
    let order = row.subviews.compactMap { ($0 as? NSControl)?.accessibilityIdentifier() }.filter { $0.hasPrefix("infobar.") }
    XCTAssertEqual(order, [AXID.Infobar.link, AXID.Infobar.ok, AXID.Infobar.close], "VoiceOver reads the link, then the buttons")
    let children = row.accessibilityChildren() as? [NSView]
    XCTAssertEqual(children?.map { $0.accessibilityIdentifier() }, order, "the icon is not a child: it is decoration")
    XCTAssertEqual(row.okButton?.accessibilityIdentifier(), AXID.Infobar.ok)
    XCTAssertEqual(row.closeButton?.accessibilityIdentifier(), AXID.Infobar.close)
  }
}
