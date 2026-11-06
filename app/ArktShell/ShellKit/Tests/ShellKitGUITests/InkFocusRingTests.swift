import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The ink focus ring on the controls #642 left on the system ring or the accent (#687): the theme creator, the Peek
/// controls, the Little Arkt top bar, the find bar, the Library and the import checkbox. Each draws
/// `ShellTokens.focusRing` through `KeyboardFocusRingView` with `focusRingType = .none`, only for keyboard focus and
/// only while the window is key.
@MainActor
final class InkFocusRingTests: XCTestCase {
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
    let window = KeyStubWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                               backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    return window
  }

  /// Focuses `control` through the window, or directly when buttons refuse key view (Full Keyboard Access off, a
  /// user setting the CI runners leave off). Returns whether the window took it.
  @discardableResult
  private func focus(_ control: NSView, in window: NSWindow, _ name: String) -> Bool {
    let throughWindow = window.makeFirstResponder(control)
    if !throughWindow {
      XCTAssertFalse(NSApp.isFullKeyboardAccessEnabled, "\(name) refused focus with Full Keyboard Access on")
      XCTAssertTrue(control.becomeFirstResponder(), name)
    }
    return throughWindow
  }

  private func unfocus(_ control: NSView, in window: NSWindow, throughWindow: Bool, _ name: String) {
    XCTAssertTrue(throughWindow ? window.makeFirstResponder(nil) : control.resignFirstResponder(), name)
  }

  private static func appearance(_ flavor: ThemeFlavor) -> NSAppearance? {
    NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
  }

  // MARK: Rings outside the control

  /// Every button in the Peek, Little Arkt, find bar and Library keyboard walks, and the import checkbox: keyboard
  /// focus shows the token ring just outside the control, losing it hides it, and the system ring is off.
  func testEveryControlInTheirKeyboardWalksDrawsTheTokenRingOutsideItself() throws {
    let window = makeWindow()
    let peek = PeekControlButton(symbol: "xmark", label: "Close", help: "", toolTip: "Close", identifier: "test.peek")
    peek.frame = NSRect(x: 0, y: 0, width: PeekLayout.controlSize, height: PeekLayout.controlSize)
    let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 480, height: 40))
    let find = FindBarButton(symbol: "chevron.down", pointSize: 11, label: "Next", identifier: "test.find")
    find.frame = NSRect(x: 0, y: 0, width: FindBarLayout.buttonSize, height: FindBarLayout.buttonSize)
    let rail = LibraryRailItem(section: .downloads)
    rail.frame = NSRect(x: 0, y: 0, width: 160, height: DownloadsMetrics.railRow)
    let download = DownloadIconButton(symbol: "folder", label: "Show in Finder")
    let checkbox = ImportCheckbox(style: ImportViewStyle.sheet(for: window.contentView!, reduceMotion: true))
    checkbox.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
    let cases: [(String, NSView, KeyboardFocusRingView, CGFloat)] = [
      ("peek", peek, peek.keyboardFocusRing, PeekLayout.controlSize / 2 + 3),
      ("copy link", bar.copyButton, bar.copyButton.keyboardFocusRing, 7 + 3),
      ("find", find, find.keyboardFocusRing, FindBarLayout.buttonSize / 2 + 3),
      ("rail", rail, rail.keyboardFocusRing, DownloadsMetrics.rowCorner + 3),
      ("download", download, download.keyboardFocusRing, DownloadsMetrics.iconButton / 2 + 3),
      ("checkbox", checkbox, checkbox.keyboardFocusRing, 4.5 + 3),
    ]
    var x: CGFloat = 20
    for (name, control, ring, radius) in cases {
      if control.superview == nil {
        control.setFrameOrigin(NSPoint(x: x, y: 200))
        window.contentView?.addSubview(control)
        x += control.frame.width + 20
      } else if control.window == nil {
        window.contentView?.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
      }
      if let button = control as? NSButton {
        XCTAssertEqual(button.focusRingType, .none, "\(name): not the system ring")
      } else {
        XCTAssertEqual(control.focusRingType, .none, "\(name): not the system ring")
      }
      XCTAssertTrue(ring.isHidden, "\(name): hidden at rest")
      let throughWindow = focus(control, in: window, name)
      XCTAssertFalse(ring.isHidden, "\(name): shown with keyboard focus")
      XCTAssertTrue(ring.superview === control, name)
      XCTAssertEqual(ring.frame, control.bounds.insetBy(dx: -3, dy: -3), "\(name): outside the control")
      XCTAssertEqual(ring.cornerRadius, radius, "\(name): follows the control's shape")
      XCTAssertFalse(control.clipsToBounds, "\(name): the control does not cut the ring off")
      unfocus(control, in: window, throughWindow: throughWindow, name)
      XCTAssertTrue(ring.isHidden, "\(name): hidden without it")
    }
  }

  /// A corner radius on a control's layer turns AppKit's `clipsToBounds` on, which cut every ring drawn outside such
  /// a control down to nothing (the split close button since #642): a shown ring that reaches past its host unclips it,
  /// and an inside ring leaves its host alone.
  func testARingOutsideARoundedControlIsNotClipped() {
    let window = makeWindow()
    let rounded = NSView(frame: NSRect(x: 20, y: 20, width: 40, height: 24))
    rounded.wantsLayer = true
    rounded.layer?.cornerRadius = 8
    window.contentView?.addSubview(rounded)
    XCTAssertTrue(rounded.clipsToBounds, "AppKit clips a view whose layer has a corner radius")
    let ring = KeyboardFocusRingView.attach(outside: rounded, radius: 8)
    XCTAssertTrue(rounded.clipsToBounds, "nothing changes while the ring is hidden")
    ring.setFocused(true)
    XCTAssertFalse(rounded.clipsToBounds, "a shown outside ring unclips its host")
    ring.setFocused(false)
    XCTAssertTrue(rounded.clipsToBounds, "hiding the ring restores the host's clipping")
    XCTAssertEqual(rounded.layer?.masksToBounds, true)
    ring.setFocused(true)
    XCTAssertFalse(rounded.clipsToBounds, "shown again, unclipped again")
    window.setKey(false)
    XCTAssertTrue(rounded.clipsToBounds, "hidden by the window resigning key, clipped again")
    window.setKey(true)
    ring.setFocused(false)

    let unrounded = NSView(frame: NSRect(x: 60, y: 60, width: 40, height: 24))
    window.contentView?.addSubview(unrounded)
    let plainRing = KeyboardFocusRingView.attach(outside: unrounded, radius: 4)
    plainRing.setFocused(true)
    plainRing.setFocused(false)
    XCTAssertFalse(unrounded.clipsToBounds, "a host that did not clip is not made to clip")

    let inside = NSView(frame: NSRect(x: 100, y: 20, width: 40, height: 24))
    inside.wantsLayer = true
    inside.layer?.cornerRadius = 8
    window.contentView?.addSubview(inside)
    KeyboardFocusRingView.attach(inside: inside, radius: 8).setFocused(true)
    XCTAssertTrue(inside.clipsToBounds, "an inside ring leaves its host as it is")

    // A ring shown while inside its host, then moved past its edge (a theme control's ring placed by a later layout).
    let later = NSView(frame: NSRect(x: 160, y: 20, width: 30, height: 22))
    later.wantsLayer = true
    later.layer?.cornerRadius = 7
    window.contentView?.addSubview(later)
    let placed = KeyboardFocusRingView(frame: .zero)
    later.addSubview(placed)
    placed.setFocused(true)
    XCTAssertTrue(later.clipsToBounds)
    placed.place(around: later.bounds, radius: 7)
    XCTAssertFalse(later.clipsToBounds, "placing a shown ring past the edge unclips its host")

    let close = SplitPaneCloseButton(frame: NSRect(x: 200, y: 20, width: 24, height: 24))
    window.contentView?.addSubview(close)
    let throughWindow = focus(close, in: window, "split close")
    XCTAssertFalse(close.keyboardFocusRing.isHidden)
    XCTAssertFalse(close.clipsToBounds, "the split close button's ring is not cut off")
    unfocus(close, in: window, throughWindow: throughWindow, "split close")
  }

  /// The "Open in" segment's Space swatch stays clear of the 3 pt ring drawn inside the segment.
  func testTheOpenSegmentSwatchClearsTheInsideRing() throws {
    let window = makeWindow()
    let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 480, height: 40))
    bar.configure(host: "example.com", fullURL: "https://example.com/", secure: true, openLabel: "Open in Studio",
                  openHelp: "", accent: true, swatch: [.srgb(hex: 0x3366CC), .srgb(hex: 0xC8743A)])
    window.contentView?.addSubview(bar)
    bar.layoutSubtreeIfNeeded()
    let button = bar.openButton
    let image = try XCTUnwrap(button.image)
    let imageRect = try XCTUnwrap(button.cell?.imageRect(forBounds: button.bounds))
    let firstColumn = try XCTUnwrap(Self.firstDrawnColumn(image))
    let swatchX = imageRect.minX + firstColumn * imageRect.width / image.size.width
    XCTAssertGreaterThanOrEqual(swatchX, 3, "the swatch starts \(swatchX) pt in; the ring covers the first 3")
  }

  /// The first x, in points, at which `image` draws anything, measured from its pixels at 2x; nil if it draws nothing.
  static func firstDrawnColumn(_ image: NSImage) -> CGFloat? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2),
                                     pixelsHigh: Int(image.size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    let column = (0..<rep.pixelsWide).first { x in
      (0..<rep.pixelsHigh).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 }
    }
    return column.map { CGFloat($0) / 2 }
  }

  /// A click toggles the import checkbox without focusing it, so the ring shows only for the keyboard.
  func testAClickDoesNotFocusTheImportCheckbox() {
    for event in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
      XCTAssertFalse(ImportCheckbox.acceptsFocus(during: event), "\(event)")
    }
    for event in [nil, NSEvent.EventType.keyDown, .leftMouseUp] as [NSEvent.EventType?] {
      XCTAssertTrue(ImportCheckbox.acceptsFocus(during: event), "\(String(describing: event))")
    }
    let window = makeWindow()
    let checkbox = ImportCheckbox(style: ImportViewStyle.sheet(for: window.contentView!, reduceMotion: true))
    checkbox.frame = NSRect(x: 20, y: 20, width: 18, height: 18)
    window.contentView?.addSubview(checkbox)
    XCTAssertTrue(checkbox.acceptsFirstResponder, "the keyboard reaches it")
    XCTAssertTrue(window.makeFirstResponder(checkbox))
    XCTAssertFalse(checkbox.keyboardFocusRing.isHidden)
  }

  /// The rail items are 2 pt apart, the ring 3 pt wide: a focused item draws above its neighbors.
  func testAFocusedRailItemIsRaisedAboveItsNeighbors() {
    let window = makeWindow()
    let item = LibraryRailItem(section: .downloads)
    item.frame = NSRect(x: 10, y: 10, width: 160, height: DownloadsMetrics.railRow)
    window.contentView?.addSubview(item)
    let throughWindow = focus(item, in: window, "rail")
    XCTAssertEqual(item.layer?.zPosition, 1)
    unfocus(item, in: window, throughWindow: throughWindow, "rail")
    XCTAssertEqual(item.layer?.zPosition, 0)
  }

  // MARK: Little Arkt split button

  /// The split clips its segments, so each segment draws the ring inside itself; the ring follows whichever segment
  /// has the keyboard.
  func testTheLittleArktSegmentsDrawTheRingInsideThemselves() {
    let window = makeWindow()
    let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 480, height: 40))
    bar.configure(host: "example.com", fullURL: "https://example.com/", secure: true, openLabel: "Open in Studio",
                  openHelp: "", accent: true, swatch: [.srgb(hex: 0x3366CC)])
    window.contentView?.addSubview(bar)
    bar.layoutSubtreeIfNeeded()
    for (name, segment) in [("open", bar.openButton), ("chooser", bar.chooserButton)] {
      XCTAssertEqual(segment.focusRingType, .none, "\(name): not the system ring")
      XCTAssertTrue(segment.keyboardFocusRing.isHidden, "\(name): hidden at rest")
      let throughWindow = focus(segment, in: window, name)
      XCTAssertFalse(segment.keyboardFocusRing.isHidden, "\(name): shown with keyboard focus")
      XCTAssertEqual(segment.keyboardFocusRing.frame, segment.bounds, "\(name): inside the segment")
      let other = segment === bar.openButton ? bar.chooserButton : bar.openButton
      XCTAssertTrue(other.keyboardFocusRing.isHidden, "\(name): only the focused segment draws it")
      unfocus(segment, in: window, throughWindow: throughWindow, name)
      XCTAssertTrue(segment.keyboardFocusRing.isHidden, "\(name): hidden without it")
    }
  }

  /// On the mustard fill the ring takes the fill's text tone (graphite, `onAccent`) in both appearances, as the
  /// sidebar's ring takes the Space's text tone; the quiet "Open as Tab" style follows the window.
  func testTheSegmentRingTakesTheToneOfItsFill() {
    for flavor in [ThemeFlavor.light, .dark] {
      let window = makeWindow()
      window.appearance = Self.appearance(flavor)
      let bar = LittleArktTopBar(frame: NSRect(x: 0, y: 0, width: 480, height: 40))
      window.contentView?.addSubview(bar)
      for accent in [true, false] {
        bar.configure(host: "example.com", fullURL: "https://example.com/", secure: true, openLabel: "Open",
                      openHelp: "", accent: accent, swatch: [])
        bar.updateLayer()
        let expected = ShellTokens.focusRing.resolve(accent ? .light : flavor).cgColor
        for segment in [bar.openButton, bar.chooserButton] {
          segment.keyboardFocusRing.updateLayer()
          XCTAssertEqual(segment.keyboardFocusRing.ring.strokeColor, expected, "\(flavor), accent \(accent)")
        }
      }
    }
  }

  // MARK: Tone from a model

  /// The Peek controls and the import checkbox take their tone from their model, not the view's appearance.
  func testThePeekAndImportRingsFollowTheirFlavor() {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    host.appearance = Self.appearance(.light)
    for flavor in [ThemeFlavor.light, .dark] {
      let peek = PeekControlButton(symbol: "xmark", label: "Close", help: "", toolTip: "", identifier: "test.peek")
      host.addSubview(peek)
      peek.flavor = flavor
      peek.keyboardFocusRing.updateLayer()
      XCTAssertEqual(peek.keyboardFocusRing.ring.strokeColor, ShellTokens.focusRing.resolve(flavor).cgColor,
                     "peek \(flavor)")

      let appearance = OnboardingAppearance(flavor: flavor, reduceMotion: true, reduceTransparency: false,
                                            increaseContrast: false)
      let checkbox = ImportCheckbox(style: .hero(appearance, compact: false))
      host.addSubview(checkbox)
      checkbox.keyboardFocusRing.updateLayer()
      XCTAssertEqual(checkbox.keyboardFocusRing.ring.strokeColor, ShellTokens.focusRing.resolve(flavor).cgColor,
                     "import \(flavor)")
    }
  }

  // MARK: Theme creator

  private func themeControls() -> [(String, ThemeFocusableView)] {
    let slider = ThemeSliderView(label: "Opacity", identifier: "test.slider")
    slider.frame = NSRect(x: 20, y: 20, width: 264, height: ThemeCreatorMetrics.sliderHeight)
    slider.setValue(0.4)
    let count = ThemeColourCountButton(frame: NSRect(x: 20, y: 60, width: 30, height: 22))
    let swatches = ThemeTextureSwatchesView(frame: NSRect(x: 20, y: 100, width: ThemeTextureSwatchesView.width,
                                                          height: ThemeCreatorMetrics.labelRow))
    swatches.update(selected: .sand, flavor: .light)
    let dot = ThemeDotView(index: 0)
    dot.setFrameOrigin(NSPoint(x: 200, y: 100))
    return [("slider", slider), ("count", count), ("swatches", swatches), ("dot", dot)]
  }

  /// The ring shows only once the keyboard is in use, around the part of the control that has the focus (the knob,
  /// the button, the selected swatch, the colour disc); the system ring never draws.
  func testTheThemeCreatorControlsDrawTheTokenRingOnceTheKeyboardIsInUse() {
    let window = makeWindow()
    var keyboardInUse = false
    for (name, control) in themeControls() {
      control.focusVisible = { keyboardInUse }
      window.contentView?.addSubview(control)
      control.layoutSubtreeIfNeeded()
      keyboardInUse = false
      XCTAssertTrue(window.makeFirstResponder(control), name)
      XCTAssertEqual(control.focusRingType, .none, "\(name): not the system ring before a key")
      XCTAssertTrue(control.keyboardFocusRing.isHidden, "\(name): no ring before a key")
      keyboardInUse = true
      control.refreshFocusRing()
      XCTAssertEqual(control.focusRingType, .none, "\(name): not the system ring after a key")
      XCTAssertFalse(control.keyboardFocusRing.isHidden, "\(name): the token ring after a key")
      XCTAssertTrue(control.keyboardFocusRing.superview === control, name)
      XCTAssertEqual(control.keyboardFocusRing.frame, control.focusRingRect.insetBy(dx: -3, dy: -3),
                     "\(name): outside its focus shape")
      XCTAssertEqual(control.keyboardFocusRing.cornerRadius, control.focusRingRadius + 3, name)
      XCTAssertFalse(control.clipsToBounds, "\(name): the control does not cut the ring off")
      XCTAssertTrue(window.makeFirstResponder(nil), name)
      XCTAssertTrue(control.keyboardFocusRing.isHidden, "\(name): hidden without focus")
      XCTAssertFalse(control.keyboardFocusRing.isFocused, name)
    }
  }

  /// The swatch ring hugs the selected swatch's selection ring and moves with the selection; the slider's follows
  /// the knob.
  func testTheThemeRingsFollowTheSelectionAndTheKnob() {
    let swatches = ThemeTextureSwatchesView(frame: NSRect(x: 0, y: 0, width: ThemeTextureSwatchesView.width,
                                                          height: ThemeCreatorMetrics.labelRow))
    for (index, texture) in ThemeTextureSwatchesView.choices.enumerated() {
      swatches.update(selected: texture, flavor: .light)
      let gap = ThemeCreatorMetrics.swatchRingGap
      XCTAssertEqual(swatches.focusRingRect, swatches.swatchFrame(index).insetBy(dx: -gap, dy: -gap))
      XCTAssertEqual(swatches.keyboardFocusRing.frame, swatches.focusRingRect.insetBy(dx: -3, dy: -3), "\(index)")
    }
    let slider = ThemeSliderView(label: "Opacity", identifier: "test.slider")
    slider.frame = NSRect(x: 0, y: 0, width: 200, height: ThemeCreatorMetrics.sliderHeight)
    for value in [0.0, 0.5, 1.0] {
      slider.setValue(value)
      slider.layoutSubtreeIfNeeded()
      XCTAssertEqual(slider.keyboardFocusRing.frame, slider.focusRingRect.insetBy(dx: -3, dy: -3), "\(value)")
      XCTAssertEqual(slider.focusRingRect.midX, 200 * value, accuracy: 0.001)
    }
  }

  /// The selected texture swatch is ringed in the popover's text tone, never the system accent; the controls' rings
  /// take the popover's tone, and the colour dot's the graphite that stands out on its white edge.
  func testTheThemeCreatorRingsAndTheSelectedSwatchUseInk() {
    for flavor in [ThemeFlavor.light, .dark] {
      let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
      host.appearance = Self.appearance(flavor == .light ? .dark : .light)  // the popover's tone wins
      let swatches = ThemeTextureSwatchesView(frame: NSRect(x: 0, y: 0, width: ThemeTextureSwatchesView.width,
                                                            height: ThemeCreatorMetrics.labelRow))
      host.addSubview(swatches)
      swatches.update(selected: .grain, flavor: flavor)
      XCTAssertEqual(swatches.selectionRing.borderColor, ShellTokens.primaryText.resolve(flavor).cgColor)
      XCTAssertNotEqual(swatches.selectionRing.borderColor, NSColor.controlAccentColor.cgColor)
      for control in themeControls().map(\.1) {
        host.addSubview(control)
        control.applyFocusRingFlavor(flavor)
        control.keyboardFocusRing.updateLayer()
        let expected = control is ThemeDotView ? ShellTokens.focusRing.resolve(.light)
          : ShellTokens.focusRing.resolve(flavor)
        XCTAssertEqual(control.keyboardFocusRing.ring.strokeColor, expected.cgColor, "\(type(of: control)) \(flavor)")
      }
    }
  }

  /// Opened for real: focus starts on the first dot with no ring; a key turns the ring on for the control that has
  /// the keyboard, in the popover's tone.
  func testTheOpenPopoverShowsTheRingAfterAKey() throws {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Studio", theme: SpaceThemeInfo(baseColors: [.srgb(hex: 0x3366CC)], isDark: true))
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    defer { controller.close() }
    controller.window?.appearance = Self.appearance(.light)
    controller.sidebarController.themeCreatorReducesMotion = { true }
    controller.rootView.layoutSubtreeIfNeeded()
    controller.sidebarController.openThemeCreator(for: space)
    let popover = try XCTUnwrap(controller.themeCreatorView as? ThemeCreatorView)
    popover.layoutSubtreeIfNeeded()
    let dot = try XCTUnwrap(popover.pad.dots.first)
    XCTAssertTrue(controller.window?.firstResponder === dot)
    XCTAssertFalse(dot.keyboardFocusRing.isFocused, "no ring when the popover opens")
    let shift = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: controller.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 56))
    dot.keyDown(with: shift)
    XCTAssertTrue(dot.keyboardFocusRing.isFocused, "a key shows the ring")
    XCTAssertEqual(dot.focusRingType, .none)
    for control in [popover.countButton, popover.swatches, popover.amountSlider, popover.opacitySlider]
      as [ThemeFocusableView] {
      control.keyboardFocusRing.updateLayer()
      XCTAssertEqual(control.keyboardFocusRing.ring.strokeColor,
                     ShellTokens.focusRing.resolve(popover.flavor).cgColor, "\(type(of: control))")
    }
  }
}
