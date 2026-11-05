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

  func testSidebarDropHighlightAndLineUseTheDragHint() {
    for flavor in Self.flavors {
      let canvas = SidebarDropCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
      host(canvas, flavor)
      canvas.applyColors()
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

  /// Every Settings control and the split close button: keyboard focus shows the token ring, losing it hides it, and
  /// the system ring is off.
  func testSettingsControlsAndTheSplitCloseButtonDrawTheTokenRing() {
    let item = SettingsPaneItemView(pane: SettingsPane.allCases[0])
    let toggle = SettingsSwitch(frame: .zero)
    let popUp = SettingsPopUpButton(items: ["One", "Two"], selected: "One")
    let addRow = SettingsAddRowButton(title: "Add Route...")
    let close = SplitPaneCloseButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
    let cases: [(String, NSView, () -> KeyboardFocusRingView)] = [
      ("pane item", item, { item.keyboardFocusRing }), ("switch", toggle, { toggle.keyboardFocusRing }),
      ("pop-up", popUp, { popUp.keyboardFocusRing }), ("add row", addRow, { addRow.keyboardFocusRing }),
      ("split close", close, { close.keyboardFocusRing }),
    ]
    for (name, control, ring) in cases {
      XCTAssertEqual(control.focusRingType, .none, "\(name): not the system ring")
      XCTAssertTrue(control.becomeFirstResponder(), name)
      XCTAssertFalse(ring().isHidden, "\(name): shown with keyboard focus")
      XCTAssertTrue(ring().superview === control, name)
      XCTAssertTrue(control.resignFirstResponder(), name)
      XCTAssertTrue(ring().isHidden, "\(name): hidden without it")
    }
  }
}
