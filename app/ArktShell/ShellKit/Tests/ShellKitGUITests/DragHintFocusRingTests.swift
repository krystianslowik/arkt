import AppKit
import XCTest
@testable import ShellUI

/// The drag hint (#641) and the focus ring (#642) on every surface that draws them, in both tones: each resolves its
/// token from its own appearance (the sidebar's follows the Space's text tone; the page card and Settings follow the
/// window's), and no surface uses the system accent or focus color.
@MainActor
final class DragHintFocusRingTests: XCTestCase {
  private static let flavors: [ThemeFlavor] = [.light, .dark]

  /// `view` inside a host whose appearance is `flavor`'s, as the sidebar container sets it.
  private func host(_ view: NSView, _ flavor: ThemeFlavor) {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    host.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    host.addSubview(view)
  }

  private func assertHint(_ layer: CALayer, _ flavor: ThemeFlavor, file: StaticString = #filePath,
                          line: UInt = #line) {
    XCTAssertEqual(layer.backgroundColor, ShellTokens.dragHint.resolve(flavor).cgColor, "\(flavor) fill",
                   file: file, line: line)
    XCTAssertEqual(layer.borderColor, ShellTokens.dragHintEdge.resolve(flavor).cgColor, "\(flavor) edge",
                   file: file, line: line)
    XCTAssertEqual(layer.borderWidth, 1, "a 1 pt edge", file: file, line: line)
  }

  // MARK: Drag hint

  func testSidebarDropSlotHighlightAndLineUseTheDragHint() {
    for flavor in Self.flavors {
      let canvas = SidebarDropCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
      host(canvas, flavor)
      canvas.applyColors()
      assertHint(canvas.slot, flavor)
      assertHint(canvas.highlight, flavor)
      XCTAssertEqual(canvas.line.backgroundColor, ShellTokens.dragHintEdge.resolve(flavor).cgColor,
                     "\(flavor) insert line")
    }
  }

  func testFavoritesDropHighlightUsesTheDragHint() {
    for flavor in Self.flavors {
      let overlay = FavoritesDropOverlayView()
      host(overlay, flavor)
      overlay.applyColors()
      assertHint(overlay.highlightLayer, flavor)
    }
  }

  /// The Split View zone sits on the page card, so its tone is the window's: graphite in light, porcelain in dark.
  func testSplitDropZoneUsesTheDragHintInTheCardTone() {
    for flavor in Self.flavors {
      let overlay = SplitDropOverlayView()
      host(overlay, flavor)
      overlay.applyColors()
      assertHint(overlay.previewLayer, flavor)
      var edge = ShellTokens.dragHintEdge.resolve(flavor)
      edge.alpha = 1
      XCTAssertEqual(edge, flavor == .light ? BrandTokens.Palette.graphite : BrandTokens.Palette.porcelain)
    }
  }

  // MARK: Focus ring

  func testTheRingIsTheFocusRingTokenInEachTone() {
    for flavor in Self.flavors {
      let ring = KeyboardFocusRingView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
      host(ring, flavor)
      ring.updateLayer()
      XCTAssertEqual(ring.ring.strokeColor, ShellTokens.focusRing.resolve(flavor).cgColor, "\(flavor)")
      XCTAssertEqual(ring.ring.lineWidth, 3)
    }
  }

  /// Controls draw the ring just outside themselves, following their size.
  func testAnAttachedRingSitsOutsideItsControlAndFollowsItsSize() {
    let control = NSView(frame: NSRect(x: 10, y: 10, width: 40, height: 20))
    let ring = KeyboardFocusRingView.attach(outside: control, radius: 10)
    XCTAssertTrue(ring.superview === control)
    XCTAssertEqual(ring.frame, control.bounds.insetBy(dx: -3, dy: -3))
    XCTAssertEqual(ring.cornerRadius, 13)
    control.setFrameSize(NSSize(width: 80, height: 26))
    XCTAssertEqual(ring.frame, control.bounds.insetBy(dx: -3, dy: -3))
    XCTAssertTrue(ring.isHidden)
    XCTAssertNil(ring.hitTest(NSPoint(x: 1, y: 1)))
  }

  /// A window whose key status the test sets, and announces the way AppKit does: a test runner process may never
  /// become active, so a real window cannot be relied on to turn key.
  private final class KeyStubWindow: NSWindow {
    var stubKey = true
    override var isKeyWindow: Bool { stubKey }
    func setKey(_ key: Bool) {
      stubKey = key
      NotificationCenter.default.post(name: key ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification,
                                      object: self)
    }
  }

  private var windows: [NSWindow] = []

  override func tearDown() async throws {
    for window in windows { window.close() }
    windows = []
  }

  private func makeWindow() -> KeyStubWindow {
    let window = KeyStubWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                               backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    return window
  }

  /// Like the system ring, the token ring shows only while its window is key.
  func testTheRingShowsOnlyWhileTheWindowIsKey() {
    let window = makeWindow()
    let control = NSView(frame: NSRect(x: 20, y: 20, width: 60, height: 24))
    window.contentView?.addSubview(control)
    let ring = KeyboardFocusRingView.attach(outside: control, radius: 12)

    ring.setFocused(true)
    XCTAssertFalse(ring.isHidden, "focused in a key window")
    window.setKey(false)
    XCTAssertTrue(ring.isHidden, "the window resigned key")
    XCTAssertTrue(ring.isFocused, "focus itself stays")
    window.setKey(true)
    XCTAssertFalse(ring.isHidden, "the window became key again")
    ring.setFocused(false)
    XCTAssertTrue(ring.isHidden)

    window.setKey(false)
    ring.setFocused(true)
    XCTAssertTrue(ring.isHidden, "focus in a window that is not key draws nothing")
  }

  /// Only a ring that asks for it raises its control above the control's neighbors while shown (Settings' pane items
  /// are 2 pt apart, the ring 3 pt wide); by default the control stays in place.
  func testOnlyAnOptedInRingRaisesItsControl() {
    let window = makeWindow()
    let control = NSView(frame: NSRect(x: 20, y: 20, width: 60, height: 24))
    control.wantsLayer = true
    window.contentView?.addSubview(control)
    let ring = KeyboardFocusRingView.attach(outside: control, radius: 12, raisesHost: true)
    ring.setFocused(true)
    XCTAssertEqual(control.layer?.zPosition, 1)
    ring.setFocused(false)
    XCTAssertEqual(control.layer?.zPosition, 0)

    let plain = NSView(frame: NSRect(x: 100, y: 20, width: 60, height: 24))
    plain.wantsLayer = true
    window.contentView?.addSubview(plain)
    let plainRing = KeyboardFocusRingView.attach(outside: plain, radius: 12)
    plainRing.setFocused(true)
    XCTAssertFalse(plainRing.isHidden)
    XCTAssertEqual(plain.layer?.zPosition, 0)
  }

  /// The split close button sits under the find bar and the zoom pill, which take the clicks there: focusing it must
  /// not draw it over them.
  func testAFocusedSplitCloseButtonStaysInItsLayer() {
    let window = makeWindow()
    let close = SplitPaneCloseButton(frame: NSRect(x: 20, y: 20, width: 24, height: 24))
    window.contentView?.addSubview(close)
    XCTAssertTrue(window.makeFirstResponder(close) || close.becomeFirstResponder())
    XCTAssertFalse(close.keyboardFocusRing.isHidden)
    XCTAssertEqual(close.layer?.zPosition, 0)
  }

  /// The Settings pane items opt in: a focused item draws above the next one.
  func testAFocusedSettingsPaneItemIsRaised() {
    let window = makeWindow()
    let item = SettingsPaneItemView(pane: SettingsPane.allCases[0])
    window.contentView?.addSubview(item)
    XCTAssertTrue(window.makeFirstResponder(item) || item.becomeFirstResponder())
    XCTAssertFalse(item.keyboardFocusRing.isHidden)
    XCTAssertEqual(item.layer?.zPosition, 1)
  }

  /// Every Settings and Archive button and the split close button, focused through the window: keyboard focus shows
  /// the token ring, losing it hides it, and the system ring is off.
  func testEveryButtonInAKeyboardWalkDrawsTheTokenRing() throws {
    let window = makeWindow()
    let item = SettingsPaneItemView(pane: SettingsPane.allCases[0])
    let toggle = SettingsSwitch(frame: .zero)
    let popUp = SettingsPopUpButton(items: ["One", "Two"], selected: "One")
    let addRow = SettingsAddRowButton(title: "Add Route...")
    let close = SplitPaneCloseButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let pill = ArchivePillButton(style: .neutral, title: "Got It")
    let link = ArchiveLinkButton(style: .secondary, title: "Clear Filters")
    let filter = ArchiveFilterButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
    let cases: [(String, NSView, KeyboardFocusRingView)] = [
      ("pane item", item, item.keyboardFocusRing), ("switch", toggle, toggle.keyboardFocusRing),
      ("pop-up", popUp, popUp.keyboardFocusRing), ("add row", addRow, addRow.keyboardFocusRing),
      ("split close", close, close.keyboardFocusRing), ("pill", pill, pill.keyboardFocusRing),
      ("link", link, link.keyboardFocusRing), ("filter", filter, filter.keyboardFocusRing),
    ]
    for (name, control, ring) in cases {
      control.frame.size = NSSize(width: max(control.frame.width, 40), height: max(control.frame.height, 20))
      window.contentView?.addSubview(control)
      XCTAssertEqual(control.focusRingType, .none, "\(name): not the system ring")
      XCTAssertTrue(ring.isHidden, "\(name): hidden at rest")
      // Buttons take first responder only with Full Keyboard Access on, a user setting; without it the window's
      // responder call is made directly.
      let throughWindow = window.makeFirstResponder(control)
      if !throughWindow {
        XCTAssertFalse(NSApp.isFullKeyboardAccessEnabled, "\(name) refused focus with Full Keyboard Access on")
        XCTAssertTrue(control.becomeFirstResponder(), name)
      }
      XCTAssertFalse(ring.isHidden, "\(name): shown with keyboard focus")
      XCTAssertTrue(ring.superview === control, name)
      XCTAssertEqual(ring.frame, control.bounds.insetBy(dx: -3, dy: -3), "\(name): outside the control")
      XCTAssertTrue(throughWindow ? window.makeFirstResponder(nil) : control.resignFirstResponder(), name)
      XCTAssertTrue(ring.isHidden, "\(name): hidden without it")
    }
  }
}
